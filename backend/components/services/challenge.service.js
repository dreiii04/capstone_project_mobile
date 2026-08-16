import { createHash, randomBytes, randomInt } from 'crypto';

import config from '../config/config.js';
import {
  authChallenges,
  dbEnabled,
  ensureDb,
} from '../config/db.js';
import { constantTimeEqual } from '../middleware/auth.middleware.js';
import {
  otpStore,
  registrationOtpStore,
  resetTokenStore,
} from '../models/memory-store.js';

function normalizeEmail(email) {
  return String(email || '').trim().toLowerCase();
}

function positiveNumber(value, fallback) {
  const number = Number(value);
  return Number.isFinite(number) && number > 0 ? number : fallback;
}

export const otpTtlMinutes = Math.min(
  positiveNumber(config.otp.ttlMinutes, 10),
  30,
);

function makeOtp() {
  return String(randomInt(100000, 1000000));
}

export function makeResetToken() {
  return randomBytes(32).toString('hex');
}

export function makeChallengeToken() {
  return randomBytes(32).toString('hex');
}

export function hashChallenge(namespace, value) {
  return createHash('sha256')
    .update(`${namespace}:${String(value)}:${config.jwt.secret}`)
    .digest('hex');
}

export function hashChallengeToken(purpose, token) {
  return hashChallenge(`challenge-token:${purpose}`, token);
}

export function challengeTokenMatches(record, purpose, token) {
  if (!/^[a-f0-9]{64}$/.test(String(token || ''))) return false;
  return constantTimeEqual(
    record?.challengeTokenHash,
    hashChallengeToken(purpose, token),
  );
}

export function otpMatches(record, email, otp) {
  return constantTimeEqual(
    record?.otpHash,
    hashChallenge(`otp:${normalizeEmail(email)}`, otp),
  );
}

function challengeNamespace(store) {
  if (store === registrationOtpStore) return 'registration-otp';
  if (store === resetTokenStore) return 'reset-token';
  return 'password-reset-otp';
}

function challengeDocumentId(store, key) {
  const namespace = challengeNamespace(store);
  return `${namespace}:${hashChallenge(`challenge-key:${namespace}`, key)}`;
}

function fromChallengeDocument(document) {
  if (!document) return null;
  const { _id, namespace, expiresAt, ...record } = document;
  return {
    ...record,
    expiresAt: new Date(expiresAt).getTime(),
  };
}

export async function getChallenge(store, key) {
  if (!dbEnabled) {
    const record = store.get(key) || null;
    if (record && record.expiresAt <= Date.now()) {
      store.delete(key);
      return null;
    }
    return record;
  }

  await ensureDb();
  const document = await authChallenges.findOne({
    _id: challengeDocumentId(store, key),
    expiresAt: { $gt: new Date() },
  });
  return fromChallengeDocument(document);
}

export async function setChallenge(store, key, record) {
  if (!dbEnabled) {
    store.set(key, record);
    return;
  }

  await ensureDb();
  const { expiresAt, ...value } = record;
  await authChallenges.updateOne(
    { _id: challengeDocumentId(store, key) },
    {
      $set: {
        ...value,
        namespace: challengeNamespace(store),
        expiresAt: new Date(expiresAt),
      },
    },
    { upsert: true },
  );
}

export async function consumeChallenge(store, key, expectedOtpHash = '') {
  if (!dbEnabled) {
    const record = store.get(key) || null;
    if (!record || record.expiresAt <= Date.now() ||
        (expectedOtpHash && record.otpHash !== expectedOtpHash)) {
      store.delete(key);
      return null;
    }
    store.delete(key);
    return record;
  }

  await ensureDb();
  const result = await authChallenges.findOneAndDelete({
    _id: challengeDocumentId(store, key),
    expiresAt: { $gt: new Date() },
    ...(expectedOtpHash ? { otpHash: expectedOtpHash } : {}),
  });
  const document = result?.value === undefined ? result : result.value;
  return fromChallengeDocument(document);
}

export async function recordFailedChallengeAttempt(
  store,
  key,
  expectedOtpHash,
) {
  if (!dbEnabled) {
    const record = store.get(key);
    if (!record || record.otpHash !== expectedOtpHash) return 0;
    record.attempts = Number(record.attempts || 0) + 1;
    store.set(key, record);
    return record.attempts;
  }

  await ensureDb();
  const result = await authChallenges.findOneAndUpdate(
    {
      _id: challengeDocumentId(store, key),
      expiresAt: { $gt: new Date() },
      otpHash: expectedOtpHash,
    },
    { $inc: { attempts: 1 } },
    { returnDocument: 'after' },
  );
  const document = result?.value === undefined ? result : result.value;
  return Number(document?.attempts || 0);
}

export function cleanupOtpData() {
  const now = Date.now();
  for (const store of [otpStore, registrationOtpStore, resetTokenStore]) {
    for (const [key, value] of store.entries()) {
      if (value.expiresAt <= now) store.delete(key);
    }
  }
}

export async function putOtp(store, email, extra = {}) {
  const otp = makeOtp();
  await setChallenge(store, email, {
    otpHash: hashChallenge(`otp:${normalizeEmail(email)}`, otp),
    expiresAt: Date.now() + otpTtlMinutes * 60 * 1000,
    attempts: 0,
    ...extra,
  });
  return otp;
}
