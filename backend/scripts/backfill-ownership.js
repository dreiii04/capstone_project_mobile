import { MongoClient } from 'mongodb';

import config from '../components/config/config.js';

const applyChanges = process.argv.includes('--apply');
const accountCollections = ['students', 'alumni', 'users'];
const recordCollections = [
  { name: 'requests', emailFields: ['email'], canonicalEmailField: 'email' },
  {
    name: 'transactions',
    emailFields: ['payerEmail', 'email'],
    canonicalEmailField: 'payerEmail',
  },
  {
    name: 'refunds',
    emailFields: ['studentEmail', 'email'],
    canonicalEmailField: 'studentEmail',
  },
  {
    name: 'notifications',
    emailFields: ['email'],
    canonicalEmailField: 'email',
  },
];

function normalizeEmail(value) {
  return String(value || '').trim().toLowerCase();
}

async function buildAccountIndex(database) {
  const accountsByEmail = new Map();
  const accountIds = new Set();
  for (const collectionName of accountCollections) {
    const cursor = database.collection(collectionName).find({}, {
      projection: {
        _id: 1,
        email: 1,
        personalEmail: 1,
        schoolEmail: 1,
      },
    });
    for await (const account of cursor) {
      accountIds.add(String(account._id));
      for (const value of [
        account.email,
        account.personalEmail,
        account.schoolEmail,
      ]) {
        const email = normalizeEmail(value);
        if (!email) continue;
        if (!accountsByEmail.has(email)) accountsByEmail.set(email, new Set());
        accountsByEmail.get(email).add(String(account._id));
      }
    }
  }
  return { accountsByEmail, accountIds };
}

function resolveUniqueOwner(record, emailFields, accountsByEmail) {
  const emails = new Set(
    emailFields
      .map((field) => normalizeEmail(record[field]))
      .filter(Boolean),
  );
  const ownerIds = new Set();
  for (const email of emails) {
    for (const ownerId of accountsByEmail.get(email) || []) {
      ownerIds.add(ownerId);
    }
  }
  if (ownerIds.size !== 1) {
    return {
      ownerId: '',
      email: '',
      reason: ownerIds.size > 1 ? 'ambiguous' : 'unmatched',
    };
  }
  return {
    ownerId: [...ownerIds][0],
    email: [...emails].find((value) =>
      accountsByEmail.get(value)?.has([...ownerIds][0])) || '',
    reason: 'matched',
  };
}

async function backfillCollection(
  database,
  spec,
  accountsByEmail,
  accountIds,
) {
  const collection = database.collection(spec.name);
  const typedIdCursor = collection.find({ userId: { $type: 'objectId' } });
  const summary = {
    matched: 0,
    updated: 0,
    ambiguous: 0,
    unmatched: 0,
    typedIdMatched: 0,
    typedIdUpdated: 0,
    typedIdUnmatched: 0,
  };

  for await (const record of typedIdCursor) {
    const normalizedUserId = String(record.userId || '');
    if (!accountIds.has(normalizedUserId)) {
      summary.typedIdUnmatched += 1;
      continue;
    }
    summary.typedIdMatched += 1;
    if (!applyChanges) continue;
    const result = await collection.updateOne(
      { _id: record._id, userId: record.userId },
      { $set: { userId: normalizedUserId } },
    );
    summary.typedIdUpdated += result.modifiedCount;
  }

  const cursor = collection.find({
    $or: [
      { userId: { $exists: false } },
      { userId: null },
      { userId: '' },
    ],
  });

  for await (const record of cursor) {
    const owner = resolveUniqueOwner(
      record,
      spec.emailFields,
      accountsByEmail,
    );
    if (owner.reason !== 'matched') {
      summary[owner.reason] += 1;
      continue;
    }
    summary.matched += 1;
    if (!applyChanges) continue;

    const result = await collection.updateOne(
      {
        _id: record._id,
        $or: [
          { userId: { $exists: false } },
          { userId: null },
          { userId: '' },
        ],
      },
      {
        $set: {
          userId: owner.ownerId,
          [spec.canonicalEmailField]: owner.email,
        },
      },
    );
    summary.updated += result.modifiedCount;
  }
  return summary;
}

if (!config.database.uriIsValid) {
  throw new Error('MONGODB_URI is not configured.');
}

const client = new MongoClient(config.database.uri, {
  serverSelectionTimeoutMS: 10000,
});

try {
  await client.connect();
  const database = client.db(config.database.name);
  const { accountsByEmail, accountIds } = await buildAccountIndex(database);
  const summary = {};
  for (const spec of recordCollections) {
    summary[spec.name] = await backfillCollection(
      database,
      spec,
      accountsByEmail,
      accountIds,
    );
  }
  console.log(JSON.stringify({
    mode: applyChanges ? 'apply' : 'dry-run',
    database: config.database.name,
    summary,
  }));
} finally {
  await client.close();
}
