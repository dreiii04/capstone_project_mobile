import { createHash } from 'crypto';
import rateLimit from 'express-rate-limit';

import config from '../config/config.js';
import { dbEnabled, ensureDb, rateLimits } from '../config/db.js';

const rateLimitHandler = (_req, res) => res.status(429).json({
  success: false,
  message: 'Too many requests. Please try again later.',
});

class MongoRateLimitStore {
  constructor(namespace) {
    this.namespace = namespace;
    this.prefix = `${namespace}:`;
    this.localKeys = false;
    this.windowMs = 60 * 1000;
  }

  init(options) {
    this.windowMs = options.windowMs;
  }

  documentId(key) {
    return `${this.namespace}:${createHash('sha256')
      .update(`${this.namespace}:${key}:${config.jwt.secret}`)
      .digest('hex')}`;
  }

  async increment(key) {
    await ensureDb();
    const now = new Date();
    const nextResetTime = new Date(now.getTime() + this.windowMs);
    const result = await rateLimits.findOneAndUpdate(
      { _id: this.documentId(key) },
      [
        {
          $set: {
            namespace: this.namespace,
            totalHits: {
              $cond: [
                { $gt: ['$expiresAt', now] },
                { $add: [{ $ifNull: ['$totalHits', 0] }, 1] },
                1,
              ],
            },
            expiresAt: {
              $cond: [
                { $gt: ['$expiresAt', now] },
                '$expiresAt',
                nextResetTime,
              ],
            },
          },
        },
      ],
      { upsert: true, returnDocument: 'after' },
    );
    const document = result?.value === undefined ? result : result.value;
    if (!document) throw new Error('Rate-limit counter was not stored.');
    return {
      totalHits: Number(document.totalHits),
      resetTime: new Date(document.expiresAt),
    };
  }

  async decrement(key) {
    try {
      await ensureDb();
      await rateLimits.updateOne(
        { _id: this.documentId(key), totalHits: { $gt: 0 } },
        { $inc: { totalHits: -1 } },
      );
    } catch (_error) {
      console.warn('Rate-limit counter decrement failed.');
    }
  }

  async resetKey(key) {
    try {
      await ensureDb();
      await rateLimits.deleteOne({ _id: this.documentId(key) });
    } catch (_error) {
      console.warn('Rate-limit counter reset failed.');
    }
  }
}

function accountAndIpRateLimitKey(req) {
  const ip = String(req.ip || req.socket?.remoteAddress || 'unknown');
  const email = String(req.body?.email || '').trim().toLowerCase() ||
    'invalid-account';
  return `${ip}|${email}`;
}

function makeRateLimiter({
  namespace,
  windowMs,
  max,
  skipSuccessfulRequests = false,
  keyGenerator,
}) {
  return rateLimit({
    windowMs,
    max,
    skipSuccessfulRequests,
    ...(keyGenerator ? { keyGenerator } : {}),
    ...(dbEnabled ? { store: new MongoRateLimitStore(namespace) } : {}),
    standardHeaders: true,
    legacyHeaders: false,
    handler: rateLimitHandler,
  });
}

export const apiLimiter = makeRateLimiter({
  namespace: 'api',
  windowMs: 15 * 60 * 1000,
  max: 300,
});
export const authLimiter = makeRateLimiter({
  namespace: 'auth',
  windowMs: 15 * 60 * 1000,
  max: 40,
});
export const loginLimiter = makeRateLimiter({
  namespace: 'login-account-ip',
  windowMs: 15 * 60 * 1000,
  max: 10,
  keyGenerator: accountAndIpRateLimitKey,
});
export const otpRequestLimiter = makeRateLimiter({
  namespace: 'otp-request',
  windowMs: 15 * 60 * 1000,
  max: 5,
  keyGenerator: accountAndIpRateLimitKey,
});
export const otpVerifyLimiter = makeRateLimiter({
  namespace: 'otp-verify',
  windowMs: 15 * 60 * 1000,
  max: 10,
  keyGenerator: accountAndIpRateLimitKey,
});
export const uploadLimiter = makeRateLimiter({
  namespace: 'upload',
  windowMs: 15 * 60 * 1000,
  max: 20,
});
export const writeLimiter = makeRateLimiter({
  namespace: 'write',
  windowMs: 60 * 60 * 1000,
  max: 60,
});
