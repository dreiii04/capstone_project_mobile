import config from './config.js';
import {
  alumniUsers,
  authChallenges,
  client,
  connectDatabase,
  dbEnabled,
  notifications,
  rateLimits,
  receipts,
  refunds,
  requests,
  studentUsers,
  transactions,
} from './db.js';

function normalizeEmail(value) {
  return String(value || '').trim().toLowerCase();
}

async function normalizeEmailsInCollection(collection, label) {
  if (!collection) return;
  try {
    const cursor = collection.find({}, {
      projection: { email: 1, schoolEmail: 1, personalEmail: 1 },
    });
    for await (const user of cursor) {
      const updates = {};
      for (const field of ['email', 'schoolEmail', 'personalEmail']) {
        const normalized = normalizeEmail(user?.[field]);
        if (normalized && normalized !== user[field]) updates[field] = normalized;
      }
      if (Object.keys(updates).length === 0) continue;
      try {
        await collection.updateOne({ _id: user._id }, { $set: updates });
      } catch (_error) {
        console.warn(`Failed to normalize one ${label} account.`);
      }
    }
  } catch (_error) {
    console.warn(`Email normalization skipped for ${label}.`);
  }
}

async function createIndexes() {
  for (const collection of [alumniUsers, studentUsers]) {
    await collection.createIndex({ email: 1 }, { unique: true });
    await collection.createIndex(
      { username: 1 },
      { unique: true, sparse: true },
    );
  }
  await receipts.createIndex({ userId: 1, createdAt: -1 });
  await receipts.createIndex(
    { paymentSubmissionId: 1 },
    { unique: true, sparse: true },
  );
  await requests.createIndex({ userId: 1, createdAt: -1 });
  await requests.createIndex({ status: 1, createdAt: -1 });
  await notifications.createIndex({ userId: 1, createdAt: -1 });
  await notifications.createIndex({ email: 1, createdAt: -1 });
  await notifications.createIndex(
    { eventKey: 1 },
    { unique: true, sparse: true },
  );
  await transactions.createIndex({ userId: 1, createdAt: -1 });
  await transactions.createIndex({ email: 1, createdAt: -1 });
  await refunds.createIndex(
    { transactionId: 1, userId: 1 },
    { unique: true },
  );
  await authChallenges.createIndex(
    { expiresAt: 1 },
    { expireAfterSeconds: 0 },
  );
  await rateLimits.createIndex(
    { expiresAt: 1 },
    { expireAfterSeconds: 0 },
  );
  await normalizeEmailsInCollection(studentUsers, 'students');
  await normalizeEmailsInCollection(alumniUsers, 'alumni');
}

export async function initializeDatabase() {
  if (!dbEnabled) {
    console.warn('DISABLE_DB is true. Using in-memory users only.');
    return;
  }
  if (!client) {
    console.warn('MongoDB is not configured. API requests will fail closed.');
    return;
  }

  try {
    await connectDatabase();
    if (!config.runDbMigrations) return;
    try {
      await createIndexes();
    } catch (_error) {
      console.warn('Database migration failed.');
    }
  } catch (error) {
    console.error(
      config.isProduction
        ? 'MongoDB connection failed.'
        : `MongoDB connection failed: ${error.message}`,
    );
  }
}
