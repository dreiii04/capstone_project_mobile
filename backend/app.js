import bcrypt from 'bcryptjs';
import {
  createHash,
  randomBytes,
} from 'crypto';
import express from 'express';
import jwt from 'jsonwebtoken';
import { ObjectId } from 'mongodb';

import config, { refreshConfig } from './components/config/config.js';
import {
  dummyPasswordHash,
  emailRegex,
  passwordRegex,
  personNameRegex,
  refundStatusAliases,
  studentIdRegex,
  studentYearLevels,
  terminalWorkflowStatuses,
} from './components/config/constants.js';
import {
  alumniUsers,
  client,
  dbEnabled,
  notifications,
  receipts,
  refunds,
  requests,
  studentUsers,
  transactions,
} from './components/config/db.js';
import { initializeDatabase } from './components/config/database-startup.js';
import { healthCheck } from './components/controllers/system.controller.js';
import { applyAppMiddleware } from './components/middleware/app.middleware.js';
import {
  requireAuth,
  requireNotificationSender,
} from './components/middleware/auth.middleware.js';
import {
  errorHandler,
  notFoundHandler,
} from './components/middleware/error.middleware.js';
import {
  loginLimiter,
  otpRequestLimiter,
  otpVerifyLimiter,
  uploadLimiter,
  writeLimiter,
} from './components/middleware/rate-limit.middleware.js';
import {
  profileUpload,
  receiptUpload,
  validateUploadedImage,
} from './components/middleware/upload.middleware.js';
import {
  defaultDocumentPrice,
  defaultProcessingFee,
  getDocumentPrice,
} from './components/models/document.model.js';
import {
  memoryNotifications,
  memoryReceipts,
  memoryRefunds,
  memoryRequests,
  memoryTransactions,
  memoryUsers,
  otpStore,
  registrationOtpStore,
  resetTokenStore,
} from './components/models/memory-store.js';
import {
  buildProfileResponse,
  buildUserResponse,
  normalizeRole,
  parseRegistrationRole,
  requesterRoleLabel as getRequesterRoleLabel,
} from './components/models/user.model.js';
import {
  challengeTokenMatches,
  cleanupOtpData,
  consumeChallenge,
  getChallenge,
  hashChallenge,
  hashChallengeToken,
  makeChallengeToken,
  makeResetToken,
  otpMatches,
  otpTtlMinutes,
  putOtp,
  recordFailedChallengeAttempt,
  setChallenge,
} from './components/services/challenge.service.js';
import {
  sendOtpEmail,
  sendOtpResponse,
} from './components/services/mail.service.js';
import {
  deleteUploadedReceipt,
  initializeMediaStorage,
  uploadProfilePhoto,
  uploadReceipt,
} from './components/services/media.service.js';

refreshConfig();

const {
  isProduction,
  mailboxlayerAccessKey: MAILBOXLAYER_ACCESS_KEY,
} = config;
const jwtSecret = config.jwt.secret;
const OTP_DEV_MODE = config.otp.developmentMode;
const maxOtpVerificationAttempts = 5;
initializeMediaStorage();

const app = express();
applyAppMiddleware(app);

function normalizeEmail(email) {
  return String(email || '').trim().toLowerCase();
}

function isValidEmail(email) {
  return email.length <= 254 && emailRegex.test(email);
}

function makeUserId() {
  return randomBytes(12).toString('hex');
}

function makeRequestId() {
  return `req_${Date.now()}_${randomBytes(6).toString('hex')}`;
}

function makeRefundId() {
  return makeUserId();
}

function getCollectionForRole(role) {
  const normalized = normalizeRole(role);
  return normalized === 'student' ? studentUsers : alumniUsers;
}

async function getUserById(id) {
  if (!id) return null;
  if (dbEnabled) {
    if (!ObjectId.isValid(id)) return null;
    const objectId = new ObjectId(id);
    const student = await studentUsers.findOne({ _id: objectId });
    if (student) return student;
    return alumniUsers.findOne({ _id: objectId });
  }

  for (const user of memoryUsers.values()) {
    const candidate = String(user?._id || user?.id || '');
    if (candidate && candidate === id) return user;
  }
  return null;
}

async function getUserByEmailWithCollection(email, preferredRole) {
  if (dbEnabled) {
    const preference = preferredRole ? normalizeRole(preferredRole) : '';
    const studentQuery = { $or: [{ email }, { schoolEmail: email }] };
    const alumniQuery = { $or: [{ email }, { personalEmail: email }] };

    if (preference === 'student') {
      const student = await studentUsers.findOne(studentQuery);
      if (student) return { user: student, collection: studentUsers };
    }

    if (preference && preference !== 'student') {
      const alumni = await alumniUsers.findOne(alumniQuery);
      if (alumni) return { user: alumni, collection: alumniUsers };
    }

    if (preference) {
      const fallbackCollection =
        preference === 'student' ? alumniUsers : studentUsers;
      const fallbackQuery =
        preference === 'student' ? alumniQuery : studentQuery;
      const fallbackUser = await fallbackCollection.findOne(fallbackQuery);
      if (fallbackUser) {
        return { user: fallbackUser, collection: fallbackCollection };
      }
      return null;
    }

    const student = await studentUsers.findOne(studentQuery);
    if (student) return { user: student, collection: studentUsers };
    const alumni = await alumniUsers.findOne(alumniQuery);
    if (alumni) return { user: alumni, collection: alumniUsers };
    return null;
  }

  const user = memoryUsers.get(email) || null;
  if (user) return { user, collection: null };
  for (const candidate of memoryUsers.values()) {
    const schoolEmail = normalizeEmail(candidate?.schoolEmail);
    const personalEmail = normalizeEmail(candidate?.personalEmail);
    if (schoolEmail === email || personalEmail === email) {
      return { user: candidate, collection: null };
    }
  }
  return null;
}

async function getUserFromAuth(payload) {
  if (!payload) return null;
  const sub = String(payload.sub || '').trim();
  if (!sub) return null;
  const user = await getUserById(sub);
  if (!user) return null;
  const tokenSessionVersion = Number(payload.sv || 0);
  const currentSessionVersion = Number(user.sessionVersion || 0);
  if (!Number.isSafeInteger(tokenSessionVersion) ||
      tokenSessionVersion !== currentSessionVersion) {
    return null;
  }
  const tokensValidAfter = new Date(user.tokensValidAfter || 0).getTime();
  const issuedAt = Number(payload.iat || 0) * 1000;
  if (Number.isFinite(tokensValidAfter) && tokensValidAfter > 0 &&
      issuedAt < Math.floor(tokensValidAfter / 1000) * 1000) {
    return null;
  }
  return user;
}

function toPositiveNumber(value, fallback) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) return fallback;
  return parsed;
}

function toBoundedInteger(value, fallback, maximum) {
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed <= 0) return fallback;
  return Math.min(parsed, maximum);
}

function toNonNegativeNumber(value, fallback) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < 0) return fallback;
  return parsed;
}

function firstNonEmptyString(...values) {
  for (const value of values) {
    if (value == null) continue;
    const normalized = String(value).trim();
    if (normalized) return normalized;
  }
  return '';
}

function firstMeaningfulString(...values) {
  const placeholders = new Set([
    'none',
    'null',
    'n/a',
    'na',
    '_',
    'not_applicable',
  ]);
  for (const value of values) {
    const normalized = firstNonEmptyString(value);
    if (normalized && !placeholders.has(normalizeWorkflowStatus(normalized))) {
      return normalized;
    }
  }
  return '';
}

function normalizeWorkflowStatus(value) {
  return String(value || '')
    .trim()
    .toLowerCase()
    .replace(/[\s-]+/g, '_');
}

function isTerminalWorkflowStatus(value) {
  return terminalWorkflowStatuses.has(normalizeWorkflowStatus(value));
}

function isRejectedWorkflowStatus(value) {
  const normalized = normalizeWorkflowStatus(value);
  return normalized === 'rejected' ||
    normalized === 'declined' ||
    normalized === 'denied';
}

function resolveWorkflowStatus(record, {
  preferMobile = false,
  linkedRecord = null,
} = {}) {
  if (!record && !linkedRecord) return '';
  const primary = preferMobile
    ? [record?.mobileStatus, record?.status, record?.state, record?.requestStatus]
    : [record?.status, record?.state, record?.mobileStatus, record?.requestStatus];
  const linked = preferMobile
    ? [
        linkedRecord?.mobileStatus,
        linkedRecord?.status,
        linkedRecord?.state,
        linkedRecord?.requestStatus,
      ]
    : [
        linkedRecord?.status,
        linkedRecord?.state,
        linkedRecord?.mobileStatus,
        linkedRecord?.requestStatus,
      ];
  const allCandidates = [...primary, ...linked];
  const rejected = allCandidates.find(isRejectedWorkflowStatus);
  const terminal = allCandidates.find(isTerminalWorkflowStatus);
  return firstNonEmptyString(rejected, terminal, ...primary, ...linked);
}

function getRecordRemarks(record, linkedRecord = null) {
  return firstMeaningfulString(
    record?.remarks,
    record?.remark,
    record?.rejectionReason,
    record?.adminRemarks,
    record?.rejectionRemarks,
    record?.statusRemarks,
    linkedRecord?.remarks,
    linkedRecord?.remark,
    linkedRecord?.rejectionReason,
    linkedRecord?.adminRemarks,
    linkedRecord?.rejectionRemarks,
    linkedRecord?.statusRemarks,
  );
}

function getStoredRequestId(record) {
  return firstNonEmptyString(
    record?.requestId,
    record?.request_id,
    record?.linkedRequestId,
  );
}

function getRequestResponseId(record) {
  return firstNonEmptyString(
    getStoredRequestId(record),
    record?._id,
    record?.id,
  );
}

function buildRefundGuidance({
  status,
  amount,
  paymentType,
  refundStatus,
  refundRequestedAt,
}) {
  const rejected = isRejectedWorkflowStatus(status);
  const paymentReceived =
    toNonNegativeNumber(amount, 0) > 0 && Boolean(firstNonEmptyString(paymentType));
  const normalizedRefundStatus = firstMeaningfulString(refundStatus);
  const refundEligible = rejected && paymentReceived && !normalizedRefundStatus;

  let refundInstructions = '';
  if (rejected && normalizedRefundStatus) {
    refundInstructions =
      `Your refund request is ${normalizedRefundStatus.toLowerCase()}. ` +
      'You will receive a notification when its status changes.';
  } else if (refundEligible) {
    refundInstructions =
      'This paid request was rejected. Submit your preferred GCash or bank ' +
      'account details through the refund request form.';
  } else if (rejected) {
    refundInstructions =
      'No received payment is recorded for this request. Contact the office ' +
      'if you believe a refund is due.';
  }

  return {
    refundEligible,
    paymentReceived,
    refundStatus: normalizedRefundStatus,
    refundRequestedAt: firstNonEmptyString(refundRequestedAt),
    refundInstructions,
  };
}

const jwtIssuer = config.jwt.issuer;
const jwtAudience = config.jwt.audience;
const accessTokenTtlSeconds =
  toPositiveNumber(config.jwt.accessTtlMinutes, 15) * 60;
const refreshTokenTtlMs =
  toPositiveNumber(config.jwt.refreshTtlDays, 30) * 24 * 60 * 60 * 1000;

function signAccessToken(user) {
  const payload = {
    sub: String(user._id || user.id || ''),
    email: user.email,
    role: normalizeRole(user.role),
    sv: Number(user.sessionVersion || 0),
  };
  const options = {
    algorithm: 'HS256',
    expiresIn: accessTokenTtlSeconds,
    jwtid: randomBytes(16).toString('hex'),
    ...(jwtIssuer ? { issuer: jwtIssuer } : {}),
    ...(jwtAudience ? { audience: jwtAudience } : {}),
  };
  return jwt.sign(payload, jwtSecret, options);
}

function makeRefreshToken() {
  return randomBytes(48).toString('hex');
}

function hashRefreshToken(token) {
  return createHash('sha256').update(token).digest('hex');
}

function buildRefreshTokenRecord(token, user) {
  return {
    tokenHash: hashRefreshToken(token),
    sessionVersion: Number(user?.sessionVersion || 0),
    createdAt: new Date().toISOString(),
    expiresAt: new Date(Date.now() + refreshTokenTtlMs).toISOString(),
  };
}

function getRefreshTokenRecord(user, tokenHash) {
  const tokens = Array.isArray(user?.refreshTokens) ? user.refreshTokens : [];
  return tokens.find((record) => record.tokenHash === tokenHash);
}

function isRefreshTokenExpired(record) {
  if (!record?.expiresAt) return true;
  return new Date(record.expiresAt).getTime() <= Date.now();
}

function refreshTokenPredatesSecurityChange(user, record) {
  const validAfter = new Date(user?.tokensValidAfter || 0).getTime();
  const createdAt = new Date(record?.createdAt || 0).getTime();
  return Number.isFinite(validAfter) && validAfter > 0 && createdAt < validAfter;
}

function sessionVersionMongoFilter(expectedSessionVersion) {
  return expectedSessionVersion === 0
    ? {
        $or: [
          { sessionVersion: 0 },
          { sessionVersion: { $exists: false } },
        ],
      }
    : { sessionVersion: expectedSessionVersion };
}

async function storeRefreshToken(user, record) {
  const email = normalizeEmail(user?.email);
  const expectedSessionVersion = Number(user?.sessionVersion || 0);
  if (dbEnabled) {
    const collection = getCollectionForRole(user?.role);
    if (!collection || !user?._id) return false;
    const sessionVersionFilter = sessionVersionMongoFilter(
      expectedSessionVersion,
    );
    const result = await collection.updateOne(
      { _id: user._id, ...sessionVersionFilter },
      {
        $push: {
          refreshTokens: {
            $each: [record],
            $slice: -5,
          },
        },
      },
    );
    return result.modifiedCount === 1;
  }

  const existing = memoryUsers.get(email);
  if (!existing || Number(existing.sessionVersion || 0) !== expectedSessionVersion) {
    return false;
  }
  const refreshTokens = Array.isArray(existing.refreshTokens)
    ? existing.refreshTokens
    : [];
  memoryUsers.set(email, {
    ...existing,
    refreshTokens: [...refreshTokens, record].slice(-5),
  });
  return true;
}

async function revokeRefreshToken(user, tokenHash) {
  const email = normalizeEmail(user?.email);
  if (dbEnabled) {
    const collection = getCollectionForRole(user?.role);
    if (!collection || !user?._id) return false;
    const result = await collection.updateOne(
      { _id: user._id },
      { $pull: { refreshTokens: { tokenHash } } },
    );
    return result.modifiedCount === 1;
  }

  const existing = memoryUsers.get(email);
  if (!existing) return false;
  const refreshTokens = Array.isArray(existing.refreshTokens)
    ? existing.refreshTokens
    : [];
  memoryUsers.set(email, {
    ...existing,
    refreshTokens: refreshTokens.filter(
      (record) => record.tokenHash !== tokenHash,
    ),
  });
  return refreshTokens.some((record) => record.tokenHash === tokenHash);
}

async function issueTokensForUser(user) {
  const refreshToken = makeRefreshToken();
  const refreshRecord = buildRefreshTokenRecord(refreshToken, user);
  const stored = await storeRefreshToken(user, refreshRecord);
  if (!stored) return null;
  const accessToken = signAccessToken(user);
  return {
    accessToken,
    refreshToken,
    expiresInSeconds: accessTokenTtlSeconds,
  };
}

async function getUserByEmail(email) {
  if (dbEnabled) {
    const record = await getUserByEmailWithCollection(email);
    return record?.user || null;
  }
  return memoryUsers.get(email) || null;
}

async function createUserDocument(user) {
  if (dbEnabled) {
    const collection = getCollectionForRole(user.role);
    return collection.insertOne(user);
  }

  const id = user._id || user.id || makeUserId();
  memoryUsers.set(user.email, { ...user, _id: id });
  return { insertedId: id };
}

function buildReceiptRecord({
  user,
  paymentType,
  docName,
  purpose,
  trueRequestId,
  amount,
  status,
  imageUrl,
  publicId,
  originalName,
  mimeType,
  size,
}) {
  return {
    transactionId: `TXN-${Date.now()}`,
    transactionHash: `hash-${Date.now()}-${Math.round(Math.random() * 1e9)}`,
    requestId: firstNonEmptyString(trueRequestId),
    name: `${user?.firstName || ''} ${user?.lastName || ''}`.trim(),
    documentType: docName || '',
    paymentMode: paymentType === 'onsite' ? 'Other Online Payment' : 'GCash',
    amount: amount ? amount.toString() : '0.00',
    receiptImage: imageUrl || '',
    payerName: `${user?.firstName || ''} ${user?.lastName || ''}`.trim(),
    payerEmail: user?.email || '',
    payerType: getRequesterRoleLabel(user?.role),
    status: 'Pending Verification',
    date: new Date(),

    // Legacy mobile fields
    userId: user?._id || user?.id,
    email: user?.email || '',
    firstName: user?.firstName || '',
    lastName: user?.lastName || '',
    paymentType: paymentType || '',
    docName: docName || '',
    purpose: purpose || '',
    originalAmount: amount,
    mobileStatus: status,
    imageUrl: imageUrl,
    publicId: publicId || '',
    originalName,
    mimeType,
    size,
    createdAt: new Date().toISOString(),
  };
}

function buildReceiptResponse(record) {
  if (!record) return null;
  const id = record._id || record.id;
  return {
    id: id ? String(id) : '',
    amount: record.amount ?? null,
    status: record.status || '',
    paymentType: record.paymentType || '',
    docName: record.docName || '',
    purpose: record.purpose || '',
    createdAt: record.createdAt || new Date().toISOString(),
  };
}

function buildMongoOwnerClauses(user) {
  const clauses = [];
  const userId = user?._id || user?.id;
  if (userId) {
    const stringId = String(userId);
    if (ObjectId.isValid(stringId)) {
      clauses.push({ userId: new ObjectId(stringId) });
    }
    clauses.push({ userId: stringId });
    return clauses;
  }
  const email = normalizeEmail(user?.email);
  if (isValidEmail(email)) clauses.push({ email });
  return clauses;
}

function recordBelongsToUser(record, user) {
  const userId = user?._id || user?.id;
  const email = normalizeEmail(user?.email);
  if (userId) {
    return String(record?.userId || '') === String(userId);
  }
  return Boolean(email && normalizeEmail(record?.email) === email);
}

async function findLatestRequestForUser(user, {
  requestId = '',
  docName = '',
  purpose = '',
} = {}) {
  const normalizedRequestId = firstNonEmptyString(requestId);
  const normalizedDocName = firstNonEmptyString(docName);
  const normalizedPurpose = firstNonEmptyString(purpose);
  if (!normalizedRequestId && !normalizedDocName && !normalizedPurpose) {
    return null;
  }

  if (dbEnabled) {
    const ownerClauses = buildMongoOwnerClauses(user);
    if (ownerClauses.length === 0) return null;

    const matchClauses = [];
    if (normalizedRequestId) {
      matchClauses.push(
        { requestId: normalizedRequestId },
        { request_id: normalizedRequestId },
        { linkedRequestId: normalizedRequestId },
      );
      if (ObjectId.isValid(normalizedRequestId)) {
        matchClauses.push({ _id: new ObjectId(normalizedRequestId) });
      }
    }
    if (normalizedDocName || normalizedPurpose) {
      const details = {};
      if (normalizedDocName) details.docName = normalizedDocName;
      if (normalizedPurpose) details.purpose = normalizedPurpose;
      matchClauses.push(details);
    }

    return requests.findOne(
      { $and: [{ $or: ownerClauses }, { $or: matchClauses }] },
      { sort: { createdAt: -1 } },
    );
  }

  return [...memoryRequests]
    .filter((record) => recordBelongsToUser(record, user))
    .filter((record) => {
      const identifiers = [
        record?._id,
        record?.id,
        record?.requestId,
        record?.request_id,
        record?.linkedRequestId,
      ].map((value) => firstNonEmptyString(value));
      const matchesId = normalizedRequestId &&
        identifiers.includes(normalizedRequestId);
      const hasDetails = Boolean(normalizedDocName || normalizedPurpose);
      const matchesDetails = hasDetails &&
        (!normalizedDocName || record?.docName === normalizedDocName) &&
        (!normalizedPurpose || record?.purpose === normalizedPurpose);
      return Boolean(matchesId || matchesDetails);
    })
    .sort(
      (a, b) =>
        new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime(),
    )[0] || null;
}

async function findLinkedRequestForTransaction(user, transaction) {
  if (!transaction) return null;
  return findLatestRequestForUser(user, {
    requestId: getStoredRequestId(transaction),
    docName: firstNonEmptyString(
      transaction.docName,
      transaction.documentName,
      transaction.documentType,
      transaction.title,
    ),
    purpose: transaction.purpose,
  });
}

function requestMatchesTransaction(request, transaction) {
  if (!request || !transaction) return false;
  const transactionRequestId = getStoredRequestId(transaction);
  if (transactionRequestId) {
    const requestIdentifiers = [
      request._id,
      request.id,
      request.requestId,
      request.request_id,
      request.linkedRequestId,
    ].map((value) => firstNonEmptyString(value));
    if (requestIdentifiers.includes(transactionRequestId)) return true;
  }

  const transactionDocName = firstNonEmptyString(
    transaction.docName,
    transaction.documentName,
    transaction.documentType,
    transaction.title,
  );
  const requestDocName = firstNonEmptyString(
    request.docName,
    request.documentType,
  );
  const transactionPurpose = firstNonEmptyString(transaction.purpose);
  const requestPurpose = firstNonEmptyString(request.purpose);
  const hasDetails = Boolean(transactionDocName || transactionPurpose);
  return hasDetails &&
    (!transactionDocName || transactionDocName === requestDocName) &&
    (!transactionPurpose || transactionPurpose === requestPurpose);
}

async function findLinkedRequestsForTransactions(user, transactionRecords) {
  if (!Array.isArray(transactionRecords) || transactionRecords.length === 0) {
    return [];
  }

  let candidates;
  if (dbEnabled) {
    const ownerClauses = buildMongoOwnerClauses(user);
    if (ownerClauses.length === 0) {
      return transactionRecords.map(() => null);
    }

    const matchClauses = [];
    for (const transaction of transactionRecords) {
      const requestId = getStoredRequestId(transaction);
      if (requestId) {
        matchClauses.push(
          { requestId },
          { request_id: requestId },
          { linkedRequestId: requestId },
        );
        if (ObjectId.isValid(requestId)) {
          matchClauses.push({ _id: new ObjectId(requestId) });
        }
      }

      const docName = firstNonEmptyString(
        transaction.docName,
        transaction.documentName,
        transaction.documentType,
        transaction.title,
      );
      const purpose = firstNonEmptyString(transaction.purpose);
      if (docName || purpose) {
        const details = [];
        if (docName) {
          details.push({ $or: [{ docName }, { documentType: docName }] });
        }
        if (purpose) details.push({ purpose });
        matchClauses.push(details.length === 1 ? details[0] : { $and: details });
      }
    }

    if (matchClauses.length === 0) {
      return transactionRecords.map(() => null);
    }
    candidates = await requests
      .find({ $and: [{ $or: ownerClauses }, { $or: matchClauses }] })
      .sort({ createdAt: -1 })
      .toArray();
  } else {
    candidates = [...memoryRequests]
      .filter((record) => recordBelongsToUser(record, user))
      .sort(
        (a, b) =>
          new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime(),
      );
  }

  return transactionRecords.map(
    (transaction) =>
      candidates.find((request) =>
        requestMatchesTransaction(request, transaction)) || null,
  );
}

async function findLatestReceiptForUser(user, { docName, purpose }) {
  if (dbEnabled) {
    const query = {};
    const clauses = buildMongoOwnerClauses(user);
    if (clauses.length === 0) return null;
    query.$or = clauses;
    if (docName) query.docName = docName;
    if (purpose) query.purpose = purpose;
    const results = await receipts
      .find(query)
      .sort({ createdAt: -1 })
      .limit(1)
      .toArray();
    return results[0] || null;
  }

  const items = memoryReceipts.filter((record) =>
    recordBelongsToUser(record, user));

  const filtered = items.filter((record) => {
    if (docName && record.docName !== docName) return false;
    if (purpose && record.purpose !== purpose) return false;
    return true;
  });

  return filtered.sort(
    (a, b) =>
      new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime(),
  )[0] || null;
}

async function createRequestRecord(request) {
  if (dbEnabled) {
    if (!request.requestId) {
      request.requestId = makeRequestId();
    }
    const result = await requests.insertOne(request);
    return result.insertedId;
  }

  if (!request.requestId) {
    request.requestId = makeRequestId();
  }
  const id = makeUserId();
  memoryRequests.push({ ...request, _id: id });
  return id;
}

async function createNotificationRecord(notification) {
  if (dbEnabled) {
    const result = await notifications.insertOne(notification);
    return result.insertedId;
  }

  const id = makeUserId();
  memoryNotifications.push({ ...notification, _id: id });
  return id;
}

async function listNotificationsForUser(user, limit) {
  const safeLimit = toBoundedInteger(limit, 50, 200);

  if (dbEnabled) {
    const clauses = buildMongoOwnerClauses(user);
    if (clauses.length === 0) return [];
    return notifications
      .find({ $or: clauses })
      .sort({ createdAt: -1 })
      .limit(safeLimit)
      .toArray();
  }

  return memoryNotifications
    .filter((record) => recordBelongsToUser(record, user))
    .sort(
      (a, b) =>
        new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime(),
    )
    .slice(0, safeLimit);
}

function buildNotificationResponse(record) {
  if (!record) return null;
  const id = record._id || record.id;
  return {
    id: id ? String(id) : '',
    title: firstNonEmptyString(record.title, 'Request update'),
    message: record.message || '',
    isRead: Boolean(record.isRead),
    createdAt: record.createdAt || new Date().toISOString(),
  };
}

async function listTransactionsForUser(user, limit) {
  const safeLimit = toBoundedInteger(limit, 50, 200);

  if (dbEnabled) {
    const clauses = buildMongoOwnerClauses(user);
    if (clauses.length === 0) return [];
    return transactions
      .find({ $or: clauses })
      .sort({ createdAt: -1 })
      .limit(safeLimit)
      .toArray();
  }

  return memoryTransactions
    .filter((record) => recordBelongsToUser(record, user))
    .sort(
      (a, b) =>
        new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime(),
    )
    .slice(0, safeLimit);
}

async function listRefundsForUser(user, limit = 200) {
  const safeLimit = toBoundedInteger(limit, 200, 500);
  if (dbEnabled) {
    const ownerClauses = buildMongoOwnerClauses(user);
    if (ownerClauses.length === 0) return [];
    return refunds
      .find({ $or: ownerClauses })
      .sort({ createdAt: -1 })
      .limit(safeLimit)
      .toArray();
  }

  return memoryRefunds
    .filter((record) => recordBelongsToUser(record, user))
    .sort(
      (a, b) =>
        new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime(),
    )
    .slice(0, safeLimit);
}

function refundMatchesTransaction(refund, transaction) {
  const refundTransactionId = firstNonEmptyString(refund?.transactionId);
  const transactionIds = [
    transaction?._id,
    transaction?.id,
    transaction?.transactionId,
  ].map((value) => firstNonEmptyString(value));
  if (refundTransactionId && transactionIds.includes(refundTransactionId)) {
    return true;
  }

  const refundRequestId = firstNonEmptyString(refund?.requestId);
  return Boolean(
    refundRequestId && refundRequestId === getStoredRequestId(transaction),
  );
}

function buildRefundResponse(record) {
  if (!record) return null;
  const id = record._id || record.id;
  return {
    id: id ? String(id) : '',
    transactionId: firstNonEmptyString(record.transactionId),
    requestId: firstNonEmptyString(record.requestId),
    docName: firstNonEmptyString(record.docName),
    amount: record.amount ?? null,
    paymentType: firstNonEmptyString(record.paymentType),
    refundMethod: firstNonEmptyString(record.refundMethod),
    reason: firstNonEmptyString(record.reason),
    rejectionRemarks: firstNonEmptyString(record.rejectionRemarks),
    statusRemarks: getRefundStatusRemarks(record),
    status: firstNonEmptyString(record.status, 'pending'),
    createdAt: record.createdAt || new Date().toISOString(),
    updatedAt: record.updatedAt || record.createdAt || new Date().toISOString(),
  };
}

function normalizeRefundStatus(value) {
  let normalized = normalizeWorkflowStatus(value);
  if (normalized.startsWith('refund_')) {
    normalized = normalized.slice('refund_'.length);
  }
  return refundStatusAliases.get(normalized) || '';
}

function getRefundRecordId(record) {
  return firstNonEmptyString(record?.refundId, record?._id, record?.id);
}

function getRefundStatusRemarks(record) {
  return firstMeaningfulString(
    record?.refundStatusRemarks,
    record?.statusRemarks,
    record?.refundRejectionReason,
    record?.rejectionReason,
    record?.adminRemarks,
    record?.remarks,
  );
}

function buildRefundStatusNotification(record, fallbackUser = null) {
  const status = normalizeRefundStatus(record?.status);
  const refundId = getRefundRecordId(record);
  if (!refundId || !status || status === 'pending') return null;

  const docName = firstNonEmptyString(record?.docName, 'your document');
  const remarks = getRefundStatusRemarks(record);
  let title;
  let message;
  switch (status) {
    case 'approved':
      title = 'Refund request approved';
      message = `Your refund request for ${docName} was approved.`;
      break;
    case 'processing':
      title = 'Refund is being processed';
      message = `Your approved refund for ${docName} is being processed.`;
      break;
    case 'completed':
    case 'refunded':
      title = 'Refund sent';
      message = `Your refund for ${docName} was marked as sent.`;
      break;
    case 'rejected':
      title = 'Refund request rejected';
      message = `Your refund request for ${docName} was rejected.`;
      if (remarks) message += ` Reason: ${remarks}`;
      break;
    default:
      return null;
  }

  const createdAt = new Date().toISOString();
  return {
    eventKey: `refund:${refundId}:status:${status}`,
    userId: record?.userId || fallbackUser?._id || fallbackUser?.id,
    email: normalizeEmail(record?.email || fallbackUser?.email),
    title,
    message,
    isRead: false,
    createdAt,
    updatedAt: createdAt,
  };
}

function notificationIdForEvent(eventKey) {
  const hex = createHash('sha256').update(eventKey).digest('hex').slice(0, 24);
  return new ObjectId(hex);
}

async function createNotificationRecordOnce(notification) {
  const eventKey = firstNonEmptyString(notification?.eventKey);
  if (!eventKey) {
    const notificationId = await createNotificationRecord(notification);
    return { notificationId, created: true };
  }

  const notificationId = notificationIdForEvent(eventKey);
  if (dbEnabled) {
    try {
      await notifications.insertOne({ ...notification, _id: notificationId });
      return { notificationId, created: true };
    } catch (error) {
      if (error?.code !== 11000) throw error;
      return { notificationId, created: false };
    }
  }

  const existing = memoryNotifications.find(
    (record) => record.eventKey === eventKey,
  );
  if (existing) {
    return {
      notificationId: existing._id || existing.id,
      created: false,
    };
  }
  memoryNotifications.push({ ...notification, _id: String(notificationId) });
  return { notificationId, created: true };
}

async function reconcileRefundNotificationsForUser(user) {
  const refundRecords = await listRefundsForUser(user);
  for (const refundRecord of refundRecords) {
    const notification = buildRefundStatusNotification(refundRecord, user);
    if (notification) {
      await createNotificationRecordOnce(notification);
    }
  }
}

function buildTransactionResponse(
  record,
  linkedRequest = null,
  refundRecord = null,
) {
  if (!record) return null;
  const id = record._id || record.id || record.transactionId;
  const transactionId = firstNonEmptyString(record.transactionId, id);
  const requestId = firstNonEmptyString(
    linkedRequest && getRequestResponseId(linkedRequest),
    getStoredRequestId(record),
  );
  const status = firstNonEmptyString(
    resolveWorkflowStatus(record, { linkedRecord: linkedRequest }),
    'completed',
  );
  const remarks = getRecordRemarks(record, linkedRequest);
  const paymentType = firstNonEmptyString(
    record.paymentType,
    record.paymentMode,
  );
  const totalAmount =
    record.totalAmount ?? record.amount ?? record.originalAmount ?? null;
  const refund = buildRefundGuidance({
    status,
    amount: totalAmount,
    paymentType,
    refundStatus: refundRecord?.status || record.refundStatus,
    refundRequestedAt: refundRecord?.createdAt || record.refundRequestedAt,
  });
  return {
    id: id ? String(id) : '',
    transactionId,
    requestId,
    linkedRequestId: requestId,
    docName: firstNonEmptyString(
      record.docName,
      record.documentName,
      record.documentType,
      record.title,
      linkedRequest?.docName,
      linkedRequest?.documentType,
    ),
    purpose: firstNonEmptyString(record.purpose, linkedRequest?.purpose),
    status,
    createdAt: record.createdAt || record.date || new Date().toISOString(),
    paymentType,
    totalAmount,
    remarks,
    remark: remarks,
    rejectionReason: remarks,
    ...refund,
    refundId: firstNonEmptyString(refundRecord?._id, refundRecord?.id),
    refundUpdatedAt: firstNonEmptyString(
      refundRecord?.updatedAt,
      refundRecord?.createdAt,
    ),
  };
}

async function findTransactionForUser(user, transactionId) {
  const userId = user?._id || user?.id;
  const email = normalizeEmail(user?.email);
  if ((!userId && !email) || !transactionId) return null;

  if (dbEnabled) {
    const ownerClauses = buildMongoOwnerClauses(user);
    if (ownerClauses.length === 0) return null;

    const idClauses = [{ id: transactionId }, { transactionId }];
    if (ObjectId.isValid(transactionId)) {
      idClauses.push({ _id: new ObjectId(transactionId) });
    }
    return transactions.findOne({
      $and: [{ $or: ownerClauses }, { $or: idClauses }],
    });
  }

  return memoryTransactions.find((record) => {
    const recordIds = [record._id, record.id, record.transactionId]
      .map((value) => firstNonEmptyString(value));
    const ownsRecord = recordBelongsToUser(record, user);
    return ownsRecord && recordIds.includes(transactionId);
  }) || null;
}

async function findRefundForTransaction(user, transactionId, transaction = null) {
  const userId = user?._id || user?.id;
  const email = normalizeEmail(user?.email);
  const transactionIds = [
    transactionId,
    transaction?._id,
    transaction?.id,
    transaction?.transactionId,
  ]
    .map((value) => firstNonEmptyString(value))
    .filter((value, index, values) => value && values.indexOf(value) === index);
  if (transactionIds.length === 0) return null;
  if (dbEnabled) {
    const ownerClauses = buildMongoOwnerClauses(user);
    if (ownerClauses.length === 0) return null;
    return refunds.findOne({
      transactionId: { $in: transactionIds },
      $or: ownerClauses,
    });
  }

  return memoryRefunds.find((record) =>
    transactionIds.includes(firstNonEmptyString(record.transactionId)) &&
    recordBelongsToUser(record, user)
  ) || null;
}

async function findRefundById(refundId) {
  const normalizedId = firstNonEmptyString(refundId);
  if (!normalizedId) return null;

  if (dbEnabled) {
    const identifiers = [
      { refundId: normalizedId },
      { id: normalizedId },
    ];
    if (ObjectId.isValid(normalizedId)) {
      identifiers.push({ _id: new ObjectId(normalizedId) });
    }
    return refunds.findOne({ $or: identifiers });
  }

  return memoryRefunds.find((record) => [
    record.refundId,
    record._id,
    record.id,
  ].map((value) => firstNonEmptyString(value)).includes(normalizedId)) || null;
}

async function updateRefundRecordStatus(record, status, remarks, updatedAt) {
  const updates = {
    status,
    statusRemarks: remarks,
    updatedAt,
  };

  if (dbEnabled) {
    const id = getRefundRecordId(record);
    const identifiers = [
      { refundId: id },
      { id },
    ];
    if (record?._id) identifiers.unshift({ _id: record._id });
    const updated = await refunds.findOneAndUpdate(
      { $or: identifiers },
      { $set: updates },
      { returnDocument: 'after' },
    );
    return updated || null;
  }

  Object.assign(record, updates);
  return record;
}

async function syncLinkedRefundStatus(record, status, updatedAt) {
  const updates = { refundStatus: status, refundUpdatedAt: updatedAt };
  const ownerClauses = buildMongoOwnerClauses({
    _id: record?.userId,
    email: record?.email,
  });
  const transactionId = firstNonEmptyString(record?.transactionId);
  const requestId = firstNonEmptyString(record?.requestId);

  if (dbEnabled) {
    if (transactionId) {
      const identifiers = [
        { transactionId },
        { id: transactionId },
      ];
      if (ObjectId.isValid(transactionId)) {
        identifiers.push({ _id: new ObjectId(transactionId) });
      }
      await transactions.updateOne(
        ownerClauses.length > 0
          ? { $and: [{ $or: ownerClauses }, { $or: identifiers }] }
          : { $or: identifiers },
        { $set: updates },
      );
    }

    if (requestId) {
      const identifiers = [
        { requestId },
        { request_id: requestId },
        { linkedRequestId: requestId },
      ];
      if (ObjectId.isValid(requestId)) {
        identifiers.push({ _id: new ObjectId(requestId) });
      }
      await requests.updateOne(
        ownerClauses.length > 0
          ? { $and: [{ $or: ownerClauses }, { $or: identifiers }] }
          : { $or: identifiers },
        { $set: updates },
      );
    }
    return;
  }

  const owner = { _id: record?.userId, email: record?.email };
  if (transactionId) {
    const transaction = memoryTransactions.find((candidate) =>
      recordBelongsToUser(candidate, owner) && [
        candidate._id,
        candidate.id,
        candidate.transactionId,
      ].map((value) => firstNonEmptyString(value)).includes(transactionId));
    if (transaction) Object.assign(transaction, updates);
  }

  if (requestId) {
    const request = memoryRequests.find((candidate) =>
      recordBelongsToUser(candidate, owner) && [
        candidate._id,
        candidate.id,
        candidate.requestId,
        candidate.request_id,
        candidate.linkedRequestId,
      ].map((value) => firstNonEmptyString(value)).includes(requestId));
    if (request) Object.assign(request, updates);
  }
}

async function createRefundRecord(record, transaction) {
  // Some deployed databases retain a non-sparse unique refundId index.
  // Always populate it so separate refunds never collide on a null key.
  record.refundId = firstNonEmptyString(record.refundId, makeRefundId());
  if (dbEnabled) {
    if (!record._id && ObjectId.isValid(record.refundId)) {
      record._id = new ObjectId(record.refundId);
    }
    const result = await refunds.insertOne(record);
    const refundUpdates = {
      refundStatus: 'pending',
      refundRequestedAt: record.createdAt,
    };
    await transactions.updateOne(
      { _id: transaction._id },
      { $set: refundUpdates },
    );
    if (record.requestId) {
      const requestIdentifiers = [
        { requestId: record.requestId },
        { request_id: record.requestId },
        { linkedRequestId: record.requestId },
      ];
      if (ObjectId.isValid(record.requestId)) {
        requestIdentifiers.push({ _id: new ObjectId(record.requestId) });
      }
      const requestOwners = buildMongoOwnerClauses({
        _id: record.userId,
        email: record.email,
      });
      await requests.updateOne(
        requestOwners.length > 0
          ? { $and: [{ $or: requestOwners }, { $or: requestIdentifiers }] }
          : { $or: requestIdentifiers },
        { $set: refundUpdates },
      );
    }
    return result.insertedId;
  }

  const id = firstNonEmptyString(record._id, record.refundId, makeUserId());
  memoryRefunds.push({ ...record, _id: id });
  const index = memoryTransactions.indexOf(transaction);
  if (index >= 0) {
    memoryTransactions[index] = {
      ...memoryTransactions[index],
      refundStatus: 'pending',
      refundRequestedAt: record.createdAt,
    };
  }
  if (record.requestId) {
    const requestIndex = memoryRequests.findIndex((request) => {
      const ownsRequest =
        (record.userId &&
          String(request.userId || '') === String(record.userId)) ||
        (record.email &&
          normalizeEmail(request.email) === normalizeEmail(record.email));
      return ownsRequest && [
          request._id,
          request.id,
          request.requestId,
          request.request_id,
          request.linkedRequestId,
        ]
          .map((value) => firstNonEmptyString(value))
          .includes(record.requestId);
    });
    if (requestIndex >= 0) {
      memoryRequests[requestIndex] = {
        ...memoryRequests[requestIndex],
        refundStatus: 'pending',
        refundRequestedAt: record.createdAt,
      };
    }
  }
  return id;
}

class PaymentSubmissionConflictError extends Error {}

function isAwaitingPayment(record) {
  return normalizeWorkflowStatus(record?.mobileStatus) === 'pending_payment' &&
    !isTerminalWorkflowStatus(resolveWorkflowStatus(record));
}

async function commitPaymentReceipt({ user, linkedRequest, receipt }) {
  if (!isAwaitingPayment(linkedRequest)) {
    throw new PaymentSubmissionConflictError();
  }

  const paymentSubmissionId = randomBytes(24).toString('hex');
  const updatedAt = new Date().toISOString();

  if (dbEnabled) {
    if (!linkedRequest?._id) throw new PaymentSubmissionConflictError();
    const ownerClauses = buildMongoOwnerClauses(user);
    if (ownerClauses.length === 0) throw new PaymentSubmissionConflictError();

    const receiptId = new ObjectId();
    const session = client.startSession();
    try {
      await session.withTransaction(async () => {
        const observedRevision = ['updatedAt', 'status', 'state', 'requestStatus', 'mobileStatus']
          .map((field) => Object.prototype.hasOwnProperty.call(linkedRequest, field)
            ? { [field]: linkedRequest[field] }
            : { [field]: { $exists: false } });
        const requestUpdate = await requests.updateOne(
          {
            $and: [
              { _id: linkedRequest._id },
              { $or: ownerClauses },
              { mobileStatus: 'pending_payment' },
              ...observedRevision,
              {
                $or: [
                  { paymentReceiptId: { $exists: false } },
                  { paymentReceiptId: null },
                  { paymentReceiptId: '' },
                ],
              },
            ],
          },
          {
            $set: {
              status: 'Pending',
              mobileStatus: 'pending',
              paymentType: receipt.paymentType,
              paymentReceiptId: receiptId,
              paymentSubmissionId,
              updatedAt,
            },
          },
          { session },
        );
        if (requestUpdate.modifiedCount !== 1) {
          throw new PaymentSubmissionConflictError();
        }
        await receipts.insertOne(
          { ...receipt, _id: receiptId, paymentSubmissionId },
          { session },
        );
      });
      return receiptId;
    } finally {
      await session.endSession();
    }
  }

  const requestIndex = memoryRequests.findIndex((record) =>
    recordBelongsToUser(record, user) &&
    getRequestResponseId(record) === getRequestResponseId(linkedRequest));
  const currentRequest = memoryRequests[requestIndex];
  if (requestIndex < 0 || !isAwaitingPayment(currentRequest) ||
      firstNonEmptyString(currentRequest.paymentReceiptId)) {
    throw new PaymentSubmissionConflictError();
  }

  const receiptId = makeUserId();
  memoryRequests[requestIndex] = {
    ...currentRequest,
    status: 'Pending',
    mobileStatus: 'pending',
    paymentType: receipt.paymentType,
    paymentReceiptId: receiptId,
    paymentSubmissionId,
    updatedAt,
  };
  memoryReceipts.push({
    ...receipt,
    _id: receiptId,
    paymentSubmissionId,
  });
  return receiptId;
}

function buildRequestResponse(record) {
  if (!record) return null;
  const id = record._id || record.id;
  const docName = firstNonEmptyString(record.docName, record.documentType);
  const mappedPrice = getDocumentPrice(docName);
  const storedPrice = record.documentPrice;
  const documentPrice =
    storedPrice == null || storedPrice === defaultDocumentPrice
      ? mappedPrice
      : toNonNegativeNumber(storedPrice, mappedPrice);
  const processingFee = toNonNegativeNumber(
    record.processingFee,
    defaultProcessingFee,
  );
  const totalAmount = toNonNegativeNumber(
    record.totalAmount,
    documentPrice + processingFee,
  );
  const requestId = getRequestResponseId(record);
  const status = firstNonEmptyString(
    resolveWorkflowStatus(record, { preferMobile: true }),
    'pending',
  );
  const remarks = getRecordRemarks(record);
  const paymentType = firstNonEmptyString(
    record.paymentType,
    record.paymentMode,
  );
  const refund = buildRefundGuidance({
    status,
    amount: totalAmount,
    paymentType,
    refundStatus: record.refundStatus,
    refundRequestedAt: record.refundRequestedAt,
  });
  return {
    id: id ? String(id) : '',
    requestId,
    linkedRequestId: requestId,
    docName,
    purpose: record.purpose || '',
    status,
    createdAt: record.createdAt || new Date().toISOString(),
    updatedAt: record.updatedAt || record.createdAt || new Date().toISOString(),
    documentPrice,
    processingFee,
    totalAmount,
    paymentType,
    remarks,
    remark: remarks,
    rejectionReason: remarks,
    ...refund,
  };
}

function parseStatusFilter(value) {
  if (!value) return [];
  return String(value)
    .split(',')
    .map((status) => status.trim().toLowerCase())
    .filter((status) => status && status.length <= 50)
    .slice(0, 20);
}

function escapeRegExp(value) {
  return String(value).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

async function listRequestsForUser(user, statuses) {
  const userId = user?._id || user?.id;
  const email = normalizeEmail(user?.email);
  if (!userId && !email) return [];

  if (dbEnabled) {
    const ownerClauses = buildMongoOwnerClauses(user);
    if (ownerClauses.length === 0) return [];
    const queryClauses = [{ $or: ownerClauses }];
    if (statuses && statuses.length > 0) {
      const regexes = statuses.map(
        (status) => new RegExp(`^${escapeRegExp(status)}$`, 'i'),
      );
      queryClauses.push({
        $or: [
          { status: { $in: regexes } },
          { state: { $in: regexes } },
          { mobileStatus: { $in: regexes } },
          { requestStatus: { $in: regexes } },
        ],
      });
    }
    return requests
      .find(queryClauses.length === 1 ? queryClauses[0] : { $and: queryClauses })
      .sort({ createdAt: -1 })
      .toArray();
  }

  let items = memoryRequests.filter(
    (record) => recordBelongsToUser(record, user),
  );
  if (statuses && statuses.length > 0) {
    items = items.filter((record) => {
      const recordStatuses = [
        record.status,
        record.state,
        record.mobileStatus,
        record.requestStatus,
      ].map((status) => String(status || '').trim().toLowerCase());
      return recordStatuses.some((status) => statuses.includes(status));
    });
  }
  return items.sort(
    (a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime(),
  );
}

async function upsertUserDocument(user) {
  if (dbEnabled) {
    const { createdAt, ...userSet } = user;
    const collection = getCollectionForRole(user.role);
    await collection.updateOne(
      { email: user.email },
      {
        $set: userSet,
        $setOnInsert: {
          createdAt: createdAt ?? new Date().toISOString(),
        },
      },
      { upsert: true },
    );
    return;
  }

  const existing = memoryUsers.get(user.email);
  memoryUsers.set(user.email, {
    ...existing,
    ...user,
    _id: existing?._id ?? user._id ?? makeUserId(),
    createdAt:
      existing?.createdAt ?? user.createdAt ?? new Date().toISOString(),
  });
}

async function updateUserPassword(
  user,
  passwordHash,
  expectedSessionVersion = Number(user?.sessionVersion || 0),
) {
  const email = normalizeEmail(user?.email);
  if (dbEnabled) {
    const collection = getCollectionForRole(user?.role);
    if (!collection || !user?._id) return false;
    const result = await collection.updateOne(
      {
        _id: user._id,
        ...sessionVersionMongoFilter(expectedSessionVersion),
      },
      {
        $set: {
          passwordHash,
          refreshTokens: [],
          tokensValidAfter: new Date().toISOString(),
          updatedAt: new Date().toISOString(),
        },
        $inc: { sessionVersion: 1 },
        $unset: { password: '' },
      },
    );
    return result.matchedCount === 1;
  }

  const existing = memoryUsers.get(email);
  if (!existing ||
      Number(existing.sessionVersion || 0) !== expectedSessionVersion) {
    return false;
  }
  memoryUsers.set(email, {
    ...existing,
    passwordHash,
    password: undefined,
    refreshTokens: [],
    sessionVersion: Number(existing.sessionVersion || 0) + 1,
    tokensValidAfter: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
  });
  return true;
}

async function ensurePasswordHash(user) {
  if (!user) return '';
  if (/^\$2[aby]\$\d{2}\$/.test(String(user.passwordHash || ''))) {
    return user.passwordHash;
  }
  if (!user.password) return '';

  const legacyPassword = String(user.password);
  if (!legacyPassword) return '';
  const passwordHash = /^\$2[aby]\$\d{2}\$/.test(legacyPassword)
    ? legacyPassword
    : await bcrypt.hash(legacyPassword, 12);
  const expectedSessionVersion = Number(user.sessionVersion || 0);

  if (dbEnabled) {
    const collection = getCollectionForRole(user.role);
    if (collection && user._id) {
      const result = await collection.updateOne(
        {
          $and: [
            { _id: user._id, password: user.password },
            sessionVersionMongoFilter(expectedSessionVersion),
            {
              $or: [
                { passwordHash: { $exists: false } },
                { passwordHash: null },
                { passwordHash: '' },
              ],
            },
          ],
        },
        {
          $set: { passwordHash, updatedAt: new Date().toISOString() },
          $unset: { password: '' },
        },
      );
      if (result.matchedCount === 1) return passwordHash;
      const current = await getUserById(String(user._id));
      return /^\$2[aby]\$\d{2}\$/.test(String(current?.passwordHash || ''))
        ? current.passwordHash
        : '';
    }
  } else {
    const email = normalizeEmail(user.email);
    const existing = memoryUsers.get(email);
    if (existing &&
        Number(existing.sessionVersion || 0) === expectedSessionVersion &&
        existing.password === user.password &&
        !/^\$2[aby]\$\d{2}\$/.test(String(existing.passwordHash || ''))) {
      memoryUsers.set(email, {
        ...existing,
        passwordHash,
        password: undefined,
        updatedAt: new Date().toISOString(),
      });
      return passwordHash;
    }
    return /^\$2[aby]\$\d{2}\$/.test(String(existing?.passwordHash || ''))
      ? existing.passwordHash
      : '';
  }

  return passwordHash;
}

async function updateUserProfile(user, updates) {
  if (!user) return;
  if (dbEnabled) {
    const collection = getCollectionForRole(user.role);
    await collection.updateOne(
      { _id: user._id },
      { $set: { ...updates, updatedAt: new Date().toISOString() } },
    );
    return;
  }

  const existing = memoryUsers.get(user.email);
  if (!existing) return;
  const nextEmailRaw = String(updates.email || existing.email || '').trim();
  const nextEmail = nextEmailRaw ? normalizeEmail(nextEmailRaw) : user.email;

  if (nextEmail !== user.email) {
    memoryUsers.delete(user.email);
  }

  memoryUsers.set(nextEmail, {
    ...existing,
    ...updates,
    email: nextEmail,
    updatedAt: new Date().toISOString(),
  });
}

async function validateEmailWithMailboxlayer(email) {
  if (!MAILBOXLAYER_ACCESS_KEY) {
    return { isValid: true, reason: 'Mailboxlayer not configured' };
  }

  const endpoint = `https://apilayer.net/api/check?access_key=${encodeURIComponent(
    MAILBOXLAYER_ACCESS_KEY,
  )}&email=${encodeURIComponent(email)}&smtp=1&format=1`;

  try {
    const response = await fetch(endpoint, {
      signal: AbortSignal.timeout(5000),
    });
    if (!response.ok) {
      return { isValid: true, reason: 'Mailboxlayer request failed' };
    }

    const data = await response.json();
    if (data.success === false) {
      return { isValid: true, reason: 'Mailboxlayer API error' };
    }

    const isDeliverable = Boolean(data.format_valid) && Boolean(data.mx_found);
    return {
      isValid: isDeliverable,
      reason: isDeliverable ? 'ok' : 'Email failed mailbox checks',
    };
  } catch (_error) {
    return { isValid: true, reason: 'Mailboxlayer unreachable' };
  }
}

function normalizeEducationalLevel(value) {
  const normalized = String(value || '')
    .trim()
    .toLowerCase()
    .replace(/[\u2018\u2019']/g, '')
    .replace(/[\s-]+/g, '_');
  const aliases = new Map([
    ['jhs', 'jhs'],
    ['junior_high', 'jhs'],
    ['junior_high_school', 'jhs'],
    ['shs', 'shs'],
    ['senior_high', 'shs'],
    ['senior_high_school', 'shs'],
    ['bachelor', 'bachelors'],
    ['bachelors', 'bachelors'],
    ['bachelor_degree', 'bachelors'],
    ['master', 'masters'],
    ['masters', 'masters'],
    ['master_degree', 'masters'],
    ['doctorate', 'doctorate'],
    ['doctoral', 'doctorate'],
    ['doctorate_degree', 'doctorate'],
    ['phd', 'doctorate'],
  ]);
  return aliases.get(normalized) || '';
}

function isValidPastOrCurrentYear(value) {
  const year = Number(value);
  return /^\d{4}$/.test(value) &&
    year >= 1950 && year <= new Date().getFullYear();
}

function validateRegisterPayload(body) {
  const role = parseRegistrationRole(body.studentStatus || body.role);
  const educationalLevel = normalizeEducationalLevel(body.educationalLevel);
  const firstName = String(body.firstName || '').trim();
  const lastName = String(body.lastName || '').trim();
  const personalEmail = normalizeEmail(body.email);
  const password = String(body.password || '');
  const submittedProgram = String(body.program || '').trim();
  const submittedYearGraduated = String(body.yearGraduated || '').trim();
  const submittedLastYearAttended = String(body.lastYearAttended || '').trim();
  const submittedLastGradeLevelCompleted = String(
    body.lastGradeLevelCompleted || '',
  ).trim();
  const submittedLastYearLevelCompleted = String(
    body.lastYearLevelCompleted || '',
  ).trim();

  if (role !== 'former_student' && role !== 'alumni') {
    return {
      error: 'Please select Former Student or Alumni.',
    };
  }

  if (!educationalLevel) {
    return { error: 'Select a valid educational level.' };
  }

  if (firstName.length < 2 || firstName.length > 50 ||
      !personNameRegex.test(firstName)) {
    return { error: 'Enter a valid first name (2-50 characters).' };
  }
  if (lastName.length < 2 || lastName.length > 50 ||
      !personNameRegex.test(lastName)) {
    return { error: 'Enter a valid last name (2-50 characters).' };
  }

  if (!isValidEmail(personalEmail)) {
    return { error: 'Enter a valid personal email address.' };
  }

  if (!passwordRegex.test(password)) {
    return {
      error:
        'Password must be 8-72 characters with uppercase, lowercase, number, and special character, without spaces.',
    };
  }

  const requiresProgram = new Set([
    'bachelors',
    'masters',
    'doctorate',
  ]).has(educationalLevel);
  if (requiresProgram &&
      (submittedProgram.length < 2 || submittedProgram.length > 100)) {
    return { error: 'Select a valid program.' };
  }

  let yearGraduated = '';
  let lastYearAttended = '';
  let lastGradeLevelCompleted = '';
  let lastYearLevelCompleted = '';

  if (role === 'alumni') {
    if (!isValidPastOrCurrentYear(submittedYearGraduated)) {
      return { error: 'Select a valid graduation year.' };
    }
    yearGraduated = submittedYearGraduated;
  } else {
    if (!isValidPastOrCurrentYear(submittedLastYearAttended)) {
      return { error: 'Select a valid last-attended year.' };
    }
    lastYearAttended = submittedLastYearAttended;

    if (educationalLevel === 'jhs' || educationalLevel === 'shs') {
      const acceptedGrades = educationalLevel === 'jhs'
        ? new Set(['Grade 7', 'Grade 8', 'Grade 9', 'Grade 10'])
        : new Set(['Grade 11', 'Grade 12']);
      if (!acceptedGrades.has(submittedLastGradeLevelCompleted)) {
        return { error: 'Select a valid last completed grade level.' };
      }
      lastGradeLevelCompleted = submittedLastGradeLevelCompleted;
    } else {
      const acceptedYearLevels = new Set([
        '1st Year',
        '2nd Year',
        '3rd Year',
        '4th Year',
        '5th Year',
      ]);
      if (!acceptedYearLevels.has(submittedLastYearLevelCompleted)) {
        return { error: 'Select a valid last completed year level.' };
      }
      lastYearLevelCompleted = submittedLastYearLevelCompleted;
    }
  }

  const program = requiresProgram ? submittedProgram : '';
  const yearLevel = role === 'alumni' ? yearGraduated : lastYearAttended;

  return {
    role,
    studentStatus: role,
    educationalLevel,
    firstName,
    lastName,
    email: personalEmail,
    password,
    personalEmail,
    schoolEmail: '',
    studentId: '',
    yearLevel,
    program,
    yearGraduated,
    lastYearAttended,
    lastGradeLevelCompleted,
    lastYearLevelCompleted,
  };
}

function validateProfilePayload(body) {
  if (Object.prototype.hasOwnProperty.call(body, 'currentPassword') ||
      Object.prototype.hasOwnProperty.call(body, 'newPassword')) {
    return { error: 'Use the dedicated password change endpoint.' };
  }

  const firstName = String(body.firstName || '').trim();
  const lastName = String(body.lastName || '').trim();
  const schoolEmail = String(body.schoolEmail || '').trim();
  const personalEmail = String(body.personalEmail || '').trim();
  const studentId = String(body.studentId || '').trim();
  const yearLevel = String(body.yearLevel || '').trim();
  const program = String(body.program || '').trim();

  if (firstName.length < 2 || firstName.length > 50 ||
      !personNameRegex.test(firstName) ||
      lastName.length < 2 || lastName.length > 50 ||
      !personNameRegex.test(lastName)) {
    return { error: 'Enter valid first and last names (2-50 characters).' };
  }

  if (schoolEmail && !isValidEmail(schoolEmail)) {
    return { error: 'Invalid school email address.' };
  }

  if (personalEmail && !isValidEmail(personalEmail)) {
    return { error: 'Invalid personal email address.' };
  }

  if (studentId && !studentIdRegex.test(studentId)) {
    return { error: 'Student ID must be 4-30 letters, numbers, or hyphens.' };
  }

  if (yearLevel.length < 1 || yearLevel.length > 30) {
    return { error: 'Select a valid academic year.' };
  }

  if (program.length < 2 || program.length > 100) {
    return { error: 'Select a valid program.' };
  }

  return {
    firstName,
    lastName,
    schoolEmail,
    personalEmail,
    studentId,
    yearLevel,
    program,
  };
}

app.get('/health', healthCheck);

app.get('/profile', requireAuth, async (req, res, next) => {
  try {
    const user = await getUserFromAuth(req.auth);
    if (!user) {
      return res
        .status(404)
        .json({ success: false, message: 'User not found.' });
    }

    return res.json({ success: true, user: buildProfileResponse(user) });
  } catch (error) {
    return next(error);
  }
});

app.post(
  '/payments/receipt',
  requireAuth,
  uploadLimiter,
  receiptUpload.single('receipt'),
  async (req, res, next) => {
    try {


      if (req.fileValidationError) {
        return res.status(400).json({
          success: false,
          message: req.fileValidationError,
        });
      }

      if (!req.file) {
        return res.status(400).json({
          success: false,
          message: 'Receipt image is required.',
        });
      }

      const imageMetadata = validateUploadedImage(req.file);
      if (!imageMetadata) {
        return res.status(400).json({
          success: false,
          message: 'The uploaded file is not a valid supported image.',
        });
      }

      const paymentType = String(req.body?.paymentType || '')
        .trim()
        .toLowerCase();
      if (paymentType !== 'onsite' && paymentType !== 'gcash' && paymentType !== 'receipt') {
        return res.status(400).json({
          success: false,
          message: 'Invalid payment type.',
        });
      }

      const user = await getUserFromAuth(req.auth);
      if (!user) {
        return res
          .status(404)
          .json({ success: false, message: 'User not found.' });
      }

      const requestId = String(req.body?.requestId || '').trim();
      if (!requestId || requestId.length > 100) {
        return res.status(400).json({
          success: false,
          message: 'A valid document request is required.',
        });
      }

      const linkedRequest = await findLatestRequestForUser(user, { requestId });
      if (!linkedRequest) {
        return res.status(404).json({
          success: false,
          message: 'Document request not found.',
        });
      }
      if (!isAwaitingPayment(linkedRequest) ||
          firstNonEmptyString(linkedRequest.paymentReceiptId)) {
        return res.status(409).json({
          success: false,
          message: 'Payment has already been submitted for this request.',
        });
      }
      const trueRequestId = getRequestResponseId(linkedRequest);
      const docName = firstNonEmptyString(
        linkedRequest.docName,
        linkedRequest.documentType,
      );
      const purpose = firstNonEmptyString(linkedRequest.purpose);
      const documentPrice = toNonNegativeNumber(
        linkedRequest.documentPrice,
        getDocumentPrice(docName),
      );
      const processingFee = toNonNegativeNumber(
        linkedRequest.processingFee,
        defaultProcessingFee,
      );
      const amount = toNonNegativeNumber(
        linkedRequest.totalAmount,
        documentPrice + processingFee,
      );

      const uploadResult = await uploadReceipt(
        req.file,
        imageMetadata,
      );
      const receipt = buildReceiptRecord({
        user,
        paymentType,
        docName,
        purpose,
        trueRequestId, // Pass the real requestId
        amount,
        status: 'pending',
        imageUrl: '',
        publicId: uploadResult?.public_id || '',
        originalName: imageMetadata.originalName,
        mimeType: imageMetadata.mimeType,
        size: req.file.size,
      });

      let receiptId;
      try {
        receiptId = await commitPaymentReceipt({
          user,
          linkedRequest,
          receipt,
        });
      } catch (error) {
        if (error instanceof PaymentSubmissionConflictError) {
          await deleteUploadedReceipt(uploadResult?.public_id);
          return res.status(409).json({
            success: false,
            message: 'Payment has already been submitted for this request.',
          });
        }
        throw error;
      }
      return res.status(201).json({
        success: true,
        receiptId,
      });
    } catch (error) {
      return next(error);
    }
  },
);

app.get('/receipts', requireAuth, async (req, res, next) => {
  try {
    const user = await getUserFromAuth(req.auth);
    if (!user) {
      return res
        .status(404)
        .json({ success: false, message: 'User not found.' });
    }

    const docName = String(req.query?.docName || '').trim();
    const purpose = String(req.query?.purpose || '').trim();
    if (docName.length > 100 ||
        purpose.length > 500 ||
        /[\u0000-\u001f\u007f]/.test(docName + purpose)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid receipt search parameters.',
      });
    }
    const receipt = await findLatestReceiptForUser(user, { docName, purpose });

    return res.json({
      success: true,
      receipt: buildReceiptResponse(receipt),
    });
  } catch (error) {
    return next(error);
  }
});

app.post('/requests', requireAuth, writeLimiter, async (req, res, next) => {
  try {
    const docName = String(req.body?.docName || '').trim();
    const purpose = String(req.body?.purpose || '').trim();

    if (!docName || docName.length > 100 || /[\u0000-\u001f\u007f]/.test(docName)) {
      return res.status(400).json({
        success: false,
        message: 'Document name is required.',
      });
    }

    if (!purpose || purpose.length > 500 || /[\u0000-\u001f\u007f]/.test(purpose)) {
      return res.status(400).json({
        success: false,
        message: 'Purpose is required.',
      });
    }

    const user = await getUserFromAuth(req.auth);
    if (!user) {
      return res
        .status(404)
        .json({ success: false, message: 'User not found.' });
    }

    const documentPrice = getDocumentPrice(docName);
    const processingFee = defaultProcessingFee;
    const totalAmount = documentPrice + processingFee;

    const requestRecord = {
      requestId: makeRequestId(),
      name: `${user.firstName || ''} ${user.lastName || ''}`.trim(),
      studentId: user.studentId || '',
      course: user.course || user.program || '',
      yearLevel: user.yearLevel || '',
      status: 'Pending',
      documentType: docName,
      purpose: purpose,
      dateRequested: new Date(),

      // Legacy mobile fields
      userId: user._id || user.id,
      email: user.email,
      role: normalizeRole(user.role),
      roleLabel: getRequesterRoleLabel(user.role),
      firstName: user.firstName || '',
      lastName: user.lastName || '',
      personalEmail: user.personalEmail || user.email || '',
      schoolEmail: user.schoolEmail || '',
      studentStatus: user.studentStatus || normalizeRole(user.role),
      educationalLevel: user.educationalLevel || '',
      yearGraduated: user.yearGraduated || '',
      lastYearAttended: user.lastYearAttended || '',
      lastGradeLevelCompleted: user.lastGradeLevelCompleted || '',
      lastYearLevelCompleted: user.lastYearLevelCompleted || '',
      program: user.program || '',
      docName,
      documentPrice,
      processingFee,
      totalAmount,
      mobileStatus: 'pending_payment',
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    };

    const requestId = await createRequestRecord(requestRecord);
    
    const notificationCreatedAt = new Date().toISOString();
    await createNotificationRecord({
      title: 'Request submitted',
      message:
        `Your request for ${docName} was submitted. ` +
        'Status: pending for payment. Follow updates in Tracking.',
      isRead: false,
      email: normalizeEmail(user.email),
      userId: user._id || user.id,
      createdAt: notificationCreatedAt,
      updatedAt: notificationCreatedAt,
    });

    return res.status(201).json({
      success: true,
      requestId: String(requestId),
      request: buildRequestResponse({
        ...requestRecord,
        _id: requestId,
      }),
    });
  } catch (error) {
    return next(error);
  }
});

app.get('/requests', requireAuth, async (req, res, next) => {
  try {
    const user = await getUserFromAuth(req.auth);
    if (!user) {
      return res
        .status(404)
        .json({ success: false, message: 'User not found.' });
    }

    const statusFilters = parseStatusFilter(req.query?.status);
    const records = await listRequestsForUser(user, statusFilters);
    return res.json({
      success: true,
      requests: records.map(buildRequestResponse).filter(Boolean),
    });
  } catch (error) {
    return next(error);
  }
});

app.get('/notifications', requireAuth, async (req, res, next) => {
  try {
    const user = await getUserFromAuth(req.auth);
    if (!user) {
      return res
        .status(404)
        .json({ success: false, message: 'User not found.' });
    }

    // Older administration tools update refunds directly in MongoDB. Repair
    // any missing status event before returning the notification feed.
    await reconcileRefundNotificationsForUser(user);
    const records = await listNotificationsForUser(user, req.query?.limit);
    return res.json({
      success: true,
      notifications: records.map(buildNotificationResponse).filter(Boolean),
    });
  } catch (error) {
    return next(error);
  }
});

app.post(
  '/notifications',
  requireNotificationSender,
  writeLimiter,
  async (req, res, next) => {
  try {
    const title = String(req.body?.title || '').trim();
    const message = String(req.body?.message || '').trim();
    const emailInput = normalizeEmail(req.body?.email);
    const userIdInput = String(req.body?.userId || '').trim();

    if (!title || title.length > 120 || !message || message.length > 1000 ||
        /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/.test(title + message)) {
      return res.status(400).json({
        success: false,
        message: 'Notification title and message are required.',
      });
    }

    let user = null;
    if (req.auth) {
      user = await getUserFromAuth(req.auth);
    }

    if (emailInput && isValidEmail(emailInput)) {
      user = (await getUserByEmail(emailInput)) || user;
    }

    const resolvedEmail =
      (user?.email && normalizeEmail(user.email)) ||
      (isValidEmail(emailInput) ? emailInput : '');

    let resolvedUserId = null;
    const rawUserId = user?._id || user?.id || userIdInput || null;
    if (rawUserId && ObjectId.isValid(String(rawUserId))) {
      resolvedUserId = dbEnabled
        ? new ObjectId(String(rawUserId))
        : String(rawUserId);
    }

    if (!resolvedUserId && !resolvedEmail) {
      return res.status(400).json({
        success: false,
        message: 'Notification must target a valid user.',
      });
    }

    const notification = {
      userId: resolvedUserId || undefined,
      email: resolvedEmail || undefined,
      title,
      message,
      isRead: false,
      createdAt: new Date().toISOString(),
    };

    const notificationId = await createNotificationRecord(notification);
    return res.status(201).json({
      success: true,
      notificationId: String(notificationId),
    });
  } catch (error) {
    return next(error);
  }
});

app.get('/transactions', requireAuth, async (req, res, next) => {
  try {
    const user = await getUserFromAuth(req.auth);
    if (!user) {
      return res
        .status(404)
        .json({ success: false, message: 'User not found.' });
    }

    const records = await listTransactionsForUser(user, req.query?.limit);
    const [linkedRequests, refundRecords] = await Promise.all([
      findLinkedRequestsForTransactions(user, records),
      listRefundsForUser(user),
    ]);
    return res.json({
      success: true,
      transactions: records
        .map((record, index) => buildTransactionResponse(
          record,
          linkedRequests[index],
          refundRecords.find((refund) =>
            refundMatchesTransaction(refund, record)) || null,
        ))
        .filter(Boolean),
    });
  } catch (error) {
    return next(error);
  }
  },
);

app.get('/refunds', requireAuth, async (req, res, next) => {
  try {
    const user = await getUserFromAuth(req.auth);
    if (!user) {
      return res
        .status(404)
        .json({ success: false, message: 'User not found.' });
    }

    const records = await listRefundsForUser(user, req.query?.limit);
    return res.json({
      success: true,
      refunds: records.map(buildRefundResponse).filter(Boolean),
    });
  } catch (error) {
    return next(error);
  }
});

app.patch(
  '/refunds/:refundId/status',
  requireNotificationSender,
  writeLimiter,
  async (req, res, next) => {
    try {
      const refundId = String(req.params?.refundId || '').trim();
      const status = normalizeRefundStatus(req.body?.status);
      const remarks = String(req.body?.remarks || '').trim();

      if (!refundId || refundId.length > 200) {
        return res.status(400).json({
          success: false,
          message: 'A valid refund ID is required.',
        });
      }
      if (!status) {
        return res.status(400).json({
          success: false,
          message:
            'Status must be pending, approved, processing, completed, refunded, or rejected.',
        });
      }
      if (remarks.length > 500) {
        return res.status(400).json({
          success: false,
          message: 'Refund status remarks must be 500 characters or fewer.',
        });
      }

      const refundRecord = await findRefundById(refundId);
      if (!refundRecord) {
        return res.status(404).json({
          success: false,
          message: 'Refund request not found.',
        });
      }

      const updatedAt = new Date().toISOString();
      const updatedRefund = await updateRefundRecordStatus(
        refundRecord,
        status,
        remarks,
        updatedAt,
      );
      if (!updatedRefund) {
        return res.status(409).json({
          success: false,
          message: 'Refund status could not be updated.',
        });
      }

      await syncLinkedRefundStatus(updatedRefund, status, updatedAt);
      const notification = buildRefundStatusNotification(updatedRefund);
      let notificationCreated = false;
      if (notification) {
        const result = await createNotificationRecordOnce(notification);
        notificationCreated = result.created;
      }

      return res.json({
        success: true,
        refund: buildRefundResponse(updatedRefund),
        notificationCreated,
      });
    } catch (error) {
      return next(error);
    }
  },
);

app.post('/refunds', requireAuth, writeLimiter, async (req, res, next) => {
  try {
    const user = await getUserFromAuth(req.auth);
    if (!user) {
      return res
        .status(404)
        .json({ success: false, message: 'User not found.' });
    }

    const transactionId = String(req.body?.transactionId || '').trim();
    const refundMethod = String(req.body?.refundMethod || '')
      .trim()
      .toLowerCase();
    const accountName = String(req.body?.accountName || '').trim();
    const accountNumber = String(req.body?.accountNumber || '')
      .replace(/[^0-9]/g, '');
    const bankName = String(req.body?.bankName || '').trim();
    const reason = String(req.body?.reason || '').trim();

    if (!transactionId || transactionId.length > 200) {
      return res.status(400).json({
        success: false,
        message: 'A valid transaction is required.',
      });
    }
    if (!['gcash', 'bank_transfer'].includes(refundMethod)) {
      return res.status(400).json({
        success: false,
        message: 'Choose a valid refund method.',
      });
    }
    if (accountName.length < 2 || accountName.length > 100) {
      return res.status(400).json({
        success: false,
        message: 'Enter a valid account holder name.',
      });
    }
    if (refundMethod === 'gcash' && !/^09\d{9}$/.test(accountNumber)) {
      return res.status(400).json({
        success: false,
        message: 'Enter a valid 11-digit GCash number.',
      });
    }
    if (refundMethod === 'bank_transfer' &&
        (!bankName || bankName.length > 100 ||
          accountNumber.length < 6 || accountNumber.length > 30)) {
      return res.status(400).json({
        success: false,
        message: 'Enter valid bank account details.',
      });
    }
    if (reason.length > 500) {
      return res.status(400).json({
        success: false,
        message: 'Refund reason must be 500 characters or fewer.',
      });
    }

    const transaction = await findTransactionForUser(user, transactionId);
    if (!transaction) {
      return res.status(404).json({
        success: false,
        message: 'Payment transaction not found.',
      });
    }

    const linkedRequest = await findLinkedRequestForTransaction(
      user,
      transaction,
    );
    const transactionStatus = resolveWorkflowStatus(transaction, {
      linkedRecord: linkedRequest,
    });
    const amount = toNonNegativeNumber(
      transaction.totalAmount ?? transaction.amount ?? transaction.originalAmount,
      0,
    );
    const paymentType = firstNonEmptyString(
      transaction.paymentType,
      transaction.paymentMode,
    );

    if (!isRejectedWorkflowStatus(transactionStatus)) {
      return res.status(409).json({
        success: false,
        message: 'Only rejected requests can be refunded.',
      });
    }
    if (amount <= 0 || !paymentType) {
      return res.status(409).json({
        success: false,
        message: 'No received payment was found for this request.',
      });
    }

    const existingRefund = await findRefundForTransaction(
      user,
      transactionId,
      transaction,
    );
    if (existingRefund) {
      return res.status(409).json({
        success: false,
        message: 'A refund has already been requested for this payment.',
        refundStatus: existingRefund.status || 'pending',
        refundInstructions:
          'You will receive a notification when the refund status changes.',
      });
    }

    const createdAt = new Date().toISOString();
    const canonicalTransactionId = firstNonEmptyString(
      transaction._id,
      transaction.id,
      transaction.transactionId,
      transactionId,
    );
    const linkedRequestId = firstNonEmptyString(
      linkedRequest && getRequestResponseId(linkedRequest),
      getStoredRequestId(transaction),
    );
    const rejectionRemarks = getRecordRemarks(transaction, linkedRequest);
    const refundRecord = {
      refundId: makeRefundId(),
      transactionId: canonicalTransactionId,
      requestId: linkedRequestId,
      userId: user._id || user.id,
      email: normalizeEmail(user.email),
      docName: transaction.docName || transaction.documentName ||
        transaction.documentType || transaction.title || '',
      amount,
      paymentType,
      refundMethod,
      accountName,
      accountNumber,
      bankName: refundMethod === 'bank_transfer' ? bankName : '',
      reason: reason || 'Document request was rejected.',
      rejectionRemarks,
      status: 'pending',
      createdAt,
      updatedAt: createdAt,
    };

    const refundId = await createRefundRecord(refundRecord, transaction);
    await createNotificationRecord({
      userId: user._id || user.id,
      email: normalizeEmail(user.email),
      title: 'Refund request received',
      message: `Your refund request for ${refundRecord.docName || 'your document'} is now under review.`,
      isRead: false,
      createdAt,
    });

    return res.status(201).json({
      success: true,
      refundId: String(refundId),
      refundStatus: 'pending',
      message: 'Your refund request has been submitted.',
      refundInstructions:
        'The office will review your refund details. You will receive a ' +
        'notification when the refund status changes.',
    });
  } catch (error) {
    return next(error);
  }
});

app.post(
  '/profile/photo',
  requireAuth,
  uploadLimiter,
  profileUpload.single('photo'),
  async (req, res, next) => {
    try {


      if (req.fileValidationError) {
        return res.status(400).json({
          success: false,
          message: req.fileValidationError,
        });
      }

      if (!req.file) {
        return res.status(400).json({
          success: false,
          message: 'Profile photo is required.',
        });
      }

      const imageMetadata = validateUploadedImage(req.file);
      if (!imageMetadata) {
        return res.status(400).json({
          success: false,
          message: 'The uploaded file is not a valid supported image.',
        });
      }

      const user = await getUserFromAuth(req.auth);
      if (!user) {
        return res
          .status(404)
          .json({ success: false, message: 'User not found.' });
      }

      const uploadResult = await uploadProfilePhoto(
        req.file,
        imageMetadata,
      );
      const profileImageUrl =
        uploadResult?.secure_url || uploadResult?.url || '';
      const profileImagePublicId = uploadResult?.public_id || '';

      await updateUserProfile(user, {
        profileImageUrl,
        profileImagePublicId,
        profilePic: profileImageUrl,
      });

      const refreshed = (await getUserById(String(user._id || user.id || ''))) || {
        ...user,
        profileImageUrl,
        profilePic: profileImageUrl,
      };

      return res.status(201).json({
        success: true,
        imageUrl: profileImageUrl,
        profile: buildProfileResponse(refreshed),
      });
    } catch (error) {
      return next(error);
    }
  },
);

app.put('/profile', requireAuth, writeLimiter, async (req, res, next) => {
  try {
    const parsed = validateProfilePayload(req.body || {});
    if (parsed.error) {
      return res.status(400).json({ success: false, message: parsed.error });
    }

    const user = await getUserFromAuth(req.auth);
    if (!user) {
      return res
        .status(404)
        .json({ success: false, message: 'User not found.' });
    }

    const role = normalizeRole(user.role);
    const isStudent = role === 'student';
    const submittedEmail = normalizeEmail(
      isStudent ? parsed.schoolEmail : parsed.personalEmail,
    );
    if (submittedEmail !== normalizeEmail(user.email)) {
      return res.status(400).json({
        success: false,
        message: 'Login email changes require a separate verified process.',
      });
    }

    if (isStudent &&
        (!studentIdRegex.test(parsed.studentId) ||
          !studentYearLevels.has(parsed.yearLevel))) {
      return res.status(400).json({
        success: false,
        message: 'Enter valid student ID and year-level details.',
      });
    }
    if (!isStudent) {
      const year = Number(parsed.yearLevel);
      const currentYear = new Date().getFullYear();
      if (!/^\d{4}$/.test(parsed.yearLevel) || year < 1950 || year > currentYear) {
        return res.status(400).json({
          success: false,
          message: 'Select a valid graduation or last-attended year.',
        });
      }

    }

    const updates = {
      firstName: parsed.firstName,
      lastName: parsed.lastName,
      studentId: isStudent ? parsed.studentId : '',
      yearLevel: parsed.yearLevel,
      program: parsed.program,
    };
    await updateUserProfile(user, updates);

    const refreshed = await getUserById(String(user._id || user.id || ''));
    return res.json({
      success: true,
      message: 'Profile updated.',
      user: buildProfileResponse(refreshed || { ...user, ...updates }),
    });
  } catch (error) {
    return next(error);
  }
});

app.put(
  '/profile/password',
  requireAuth,
  writeLimiter,
  async (req, res, next) => {
    try {
      const currentPassword = String(req.body?.currentPassword || '');
      const newPassword = String(req.body?.newPassword || '');

      if (!currentPassword || currentPassword.length > 72) {
        return res.status(400).json({
          success: false,
          message: 'Current password is required.',
        });
      }
      if (!passwordRegex.test(newPassword)) {
        return res.status(400).json({
          success: false,
          message:
            'Password must be 8-72 characters with uppercase, lowercase, number, and special character, without spaces.',
        });
      }
      if (currentPassword === newPassword) {
        return res.status(400).json({
          success: false,
          message: 'New password must be different from your current password.',
        });
      }

      const user = await getUserFromAuth(req.auth);
      if (!user) {
        return res
          .status(404)
          .json({ success: false, message: 'User not found.' });
      }

      const currentHash = await ensurePasswordHash(user);
      const currentPasswordMatches = currentHash
        ? await bcrypt.compare(currentPassword, currentHash)
        : false;
      if (!currentPasswordMatches) {
        return res.status(403).json({
          success: false,
          message: 'Current password is incorrect.',
        });
      }

      const passwordHash = await bcrypt.hash(newPassword, 12);
      const passwordUpdated = await updateUserPassword(
        user,
        passwordHash,
        Number(user.sessionVersion || 0),
      );
      if (!passwordUpdated) {
        return res.status(409).json({
          success: false,
          message: 'Account security state changed. Please log in again.',
        });
      }

      const refreshed = await getUserById(String(user._id || user.id || ''));
      const session = refreshed ? await issueTokensForUser(refreshed) : null;
      if (!refreshed || !session) {
        return res.status(409).json({
          success: false,
          message: 'Account security state changed. Please log in again.',
        });
      }

      return res.json({
        success: true,
        message: 'Password changed successfully.',
        user: buildProfileResponse(refreshed),
        ...session,
      });
    } catch (error) {
      return next(error);
    }
  },
);

app.post('/auth/register', (_req, res) => {
  return res.status(410).json({
    success: false,
    message: 'Email verification is required before registration.',
  });
});

app.post('/auth/register/request-otp', otpRequestLimiter, async (req, res, next) => {
  try {
    cleanupOtpData();

    const parsed = validateRegisterPayload(req.body || {});
    if (parsed.error) {
      return res.status(400).json({ success: false, message: parsed.error });
    }

    const role = parsed.role;

    const pendingOtp = await getChallenge(registrationOtpStore, parsed.email);
    if (pendingOtp?.lastSentAt && Date.now() - pendingOtp.lastSentAt < 30 * 1000) {
      return res.status(429).json({
        success: false,
        message: 'A verification code was recently sent. Please wait.',
      });
    }

    const mailboxCheck = await validateEmailWithMailboxlayer(parsed.email);
    if (!mailboxCheck.isValid) {
      return res.status(400).json({
        success: false,
        message: 'Email is not deliverable. Please use a valid email.',
      });
    }

    const existing = await getUserByEmail(parsed.email);
    if (existing) {
      return res
        .status(409)
        .json({ success: false, message: 'Email already exists.' });
    }

    const { password, ...registrationPayload } = parsed;
    const passwordHash = await bcrypt.hash(password, 12);
    const challengeToken = makeChallengeToken();
    const otp = await putOtp(registrationOtpStore, parsed.email, {
      lastSentAt: Date.now(),
      challengeTokenHash: hashChallengeToken('registration', challengeToken),
      payload: {
        ...registrationPayload,
        passwordHash,
        role,
      },
    });
    return await sendOtpResponse(res, {
      email: parsed.email,
      otp,
      purpose: 'registration',
      challengeToken,
    });
  } catch (error) {
    return next(error);
  }
});

app.post('/auth/register/verify-otp', otpVerifyLimiter, async (req, res, next) => {
  try {
    cleanupOtpData();

    const email = normalizeEmail(req.body?.email);
    const otp = String(req.body?.otp || '').trim();
    const challengeToken = String(req.body?.challengeToken || '').trim();

    if (!isValidEmail(email) ||
        !/^\d{6}$/.test(otp) ||
        !/^[a-f0-9]{64}$/.test(challengeToken)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid verification request.',
      });
    }

    const record = await getChallenge(registrationOtpStore, email);
    if (!record || record.expiresAt <= Date.now()) {
      return res.status(400).json({
        success: false,
        message: 'OTP expired or not found. Please request a new one.',
      });
    }

    if (Number(record.attempts || 0) >= maxOtpVerificationAttempts) {
      await consumeChallenge(registrationOtpStore, email, record.otpHash);
      return res.status(401).json({
        success: false,
        message: 'Invalid or expired verification code.',
      });
    }

    if (!challengeTokenMatches(record, 'registration', challengeToken) ||
        !otpMatches(record, email, otp)) {
      const attempts = await recordFailedChallengeAttempt(
        registrationOtpStore,
        email,
        record.otpHash,
      );
      if (attempts >= maxOtpVerificationAttempts) {
        await consumeChallenge(registrationOtpStore, email, record.otpHash);
      }

      return res.status(401).json({
        success: false,
        message: 'Invalid or expired verification code.',
      });
    }

    const consumed = await consumeChallenge(
      registrationOtpStore,
      email,
      record.otpHash,
    );
    if (!consumed) {
      return res.status(401).json({
        success: false,
        message: 'Invalid or expired verification code.',
      });
    }
    const payload = consumed.payload;

    if (!payload) {
      return res
        .status(400)
        .json({ success: false, message: 'Missing registration payload.' });
    }

    const existing = await getUserByEmail(payload.email);
    if (existing) {
      return res
        .status(409)
        .json({ success: false, message: 'Email already exists.' });
    }

    const role = parseRegistrationRole(payload.role);
    if (!role) {
      return res.status(400).json({
        success: false,
        message: 'Invalid registration account type.',
      });
    }

    if (!/^\$2[aby]\$12\$/.test(String(payload.passwordHash || ''))) {
      return res.status(400).json({
        success: false,
        message: 'Registration challenge is invalid. Please start again.',
      });
    }
    const result = await createUserDocument({
      firstName: payload.firstName,
      lastName: payload.lastName,
      email: normalizeEmail(payload.email),
      personalEmail: normalizeEmail(payload.personalEmail || ''),
      passwordHash: payload.passwordHash,
      role,
      schoolEmail: normalizeEmail(payload.schoolEmail || ''),
      studentId: payload.studentId || '',
      studentStatus: role,
      educationalLevel: payload.educationalLevel,
      yearLevel: payload.yearLevel,
      course: payload.program,
      program: payload.program, // kept for backward compatibility with mobile code
      yearGraduated: payload.yearGraduated || '',
      lastYearAttended: payload.lastYearAttended || '',
      lastGradeLevelCompleted: payload.lastGradeLevelCompleted || '',
      lastYearLevelCompleted: payload.lastYearLevelCompleted || '',
      emailVerifiedAt: new Date().toISOString(),
      sessionVersion: 0,
      createdAt: new Date().toISOString(),
    });

    return res.status(201).json({
      success: true,
      userId: result.insertedId,
      message: 'Account created successfully.',
    });
  } catch (error) {
    return next(error);
  }
});

app.post(
  '/auth/login',
  loginLimiter,
  async (req, res, next) => {
  try {
    const email = normalizeEmail(req.body?.email);
    const password = String(req.body?.password || '');

    if (!isValidEmail(email) || !password || password.length > 72) {
      return res
        .status(400)
        .json({ success: false, message: 'Invalid email or password format.' });
    }

    const user = await getUserByEmail(email);
    const passwordHash = user
      ? (await ensurePasswordHash(user)) || dummyPasswordHash
      : dummyPasswordHash;
    const isMatch = await bcrypt.compare(password, passwordHash);
    if (!user || !isMatch) {
      return res
        .status(401)
        .json({ success: false, message: 'Invalid email or password.' });
    }

    const session = await issueTokensForUser(user);
    if (!session) {
      return res.status(409).json({
        success: false,
        message: 'Account security state changed. Please try again.',
      });
    }
    return res.json({
      success: true,
      message: 'Login successful.',
      user: buildUserResponse(user),
      ...session,
    });
  } catch (error) {
    return next(error);
  }
});

app.post('/auth/refresh', async (req, res, next) => {
  try {
    const email = normalizeEmail(req.body?.email);
    const refreshToken = String(req.body?.refreshToken || '').trim();

    if (!isValidEmail(email) || !/^[a-f0-9]{96}$/.test(refreshToken)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid email or refresh token.',
      });
    }

    const user = await getUserByEmail(email);
    if (!user) {
      return res
        .status(401)
        .json({ success: false, message: 'Invalid refresh session.' });
    }

    const tokenHash = hashRefreshToken(refreshToken);
    const record = getRefreshTokenRecord(user, tokenHash);
    if (!record || isRefreshTokenExpired(record) ||
        Number(record.sessionVersion || 0) !== Number(user.sessionVersion || 0) ||
        refreshTokenPredatesSecurityChange(user, record)) {
      await revokeRefreshToken(user, tokenHash);
      return res
        .status(401)
        .json({ success: false, message: 'Invalid refresh session.' });
    }

    const consumed = await revokeRefreshToken(user, tokenHash);
    if (!consumed) {
      return res
        .status(401)
        .json({ success: false, message: 'Invalid refresh session.' });
    }
    const session = await issueTokensForUser(user);
    if (!session) {
      return res
        .status(401)
        .json({ success: false, message: 'Invalid refresh session.' });
    }

    return res.json({
      success: true,
      message: 'Session refreshed.',
      ...session,
    });
  } catch (error) {
    return next(error);
  }
});

app.post('/auth/logout', async (req, res, next) => {
  try {
    const email = normalizeEmail(req.body?.email);
    const refreshToken = String(req.body?.refreshToken || '').trim();

    if (!isValidEmail(email) || !/^[a-f0-9]{96}$/.test(refreshToken)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid email or refresh token.',
      });
    }

    const user = await getUserByEmail(email);
    if (user) {
      const tokenHash = hashRefreshToken(refreshToken);
      await revokeRefreshToken(user, tokenHash);
    }

    return res.json({ success: true, message: 'Logged out.' });
  } catch (error) {
    return next(error);
  }
});

app.post(
  '/auth/forgot-password/request-otp',
  otpRequestLimiter,
  async (req, res, next) => {
  try {
    cleanupOtpData();

    const email = normalizeEmail(req.body?.email);
    if (!isValidEmail(email)) {
      return res.status(400).json({ success: false, message: 'Invalid email.' });
    }

    const challengeToken = makeChallengeToken();
    const user = await getUserByEmail(email);
    if (!user) {
      return res.json({
        success: true,
        message:
          'If an account exists for this email, a verification code has been sent.',
        challengeToken,
        expiresInSeconds: otpTtlMinutes * 60,
        resendAfterSeconds: 30,
      });
    }

    const pendingOtp = await getChallenge(otpStore, email);
    const lastSentAt = Number(pendingOtp?.lastSentAt || 0);
    const elapsedSinceSend = Date.now() - lastSentAt;
    if (lastSentAt && elapsedSinceSend < 30 * 1000) {
      await setChallenge(otpStore, email, {
        ...pendingOtp,
        challengeTokenHash: hashChallengeToken(
          'password-reset',
          challengeToken,
        ),
      });
      return res.json({
        success: true,
        message:
          'If an account exists for this email, a verification code has been sent.',
        challengeToken,
        expiresInSeconds: otpTtlMinutes * 60,
        resendAfterSeconds: 30,
      });
    }

    const otp = await putOtp(otpStore, email, {
      lastSentAt: Date.now(),
      userId: String(user._id || user.id || ''),
      sessionVersion: Number(user.sessionVersion || 0),
      challengeTokenHash: hashChallengeToken(
        'password-reset',
        challengeToken,
      ),
    });
    if (OTP_DEV_MODE && !isProduction) {
      return res.json({
        success: true,
        message: 'OTP generated (dev mode).',
        otp,
        challengeToken,
        expiresInSeconds: otpTtlMinutes * 60,
        resendAfterSeconds: 30,
      });
    }
    try {
      await sendOtpEmail({ email, otp, purpose: 'password-reset' });
    } catch (error) {
      console.error('Password reset email delivery failed.');
    }
    return res.json({
      success: true,
      message:
        'If an account exists for this email, a verification code has been sent.',
      challengeToken,
      expiresInSeconds: otpTtlMinutes * 60,
      resendAfterSeconds: 30,
    });
  } catch (error) {
    return next(error);
  }
  },
);

app.post(
  '/auth/forgot-password/verify-otp',
  otpVerifyLimiter,
  async (req, res, next) => {
  try {
    cleanupOtpData();

    const email = normalizeEmail(req.body?.email);
    const otp = String(req.body?.otp || '').trim();
    const challengeToken = String(req.body?.challengeToken || '').trim();

    if (!isValidEmail(email) ||
        !/^\d{6}$/.test(otp) ||
        !/^[a-f0-9]{64}$/.test(challengeToken)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid verification request.',
      });
    }

    const record = await getChallenge(otpStore, email);
    if (!record || record.expiresAt <= Date.now()) {
      return res.status(400).json({
        success: false,
        message: 'OTP expired or not found. Please request a new one.',
      });
    }

    if (Number(record.attempts || 0) >= maxOtpVerificationAttempts) {
      await consumeChallenge(otpStore, email, record.otpHash);
      return res.status(401).json({
        success: false,
        message: 'Invalid or expired verification code.',
      });
    }

    if (!challengeTokenMatches(record, 'password-reset', challengeToken) ||
        !otpMatches(record, email, otp)) {
      const attempts = await recordFailedChallengeAttempt(
        otpStore,
        email,
        record.otpHash,
      );
      if (attempts >= maxOtpVerificationAttempts) {
        await consumeChallenge(otpStore, email, record.otpHash);
      }

      return res.status(401).json({
        success: false,
        message: 'Invalid or expired verification code.',
      });
    }

    const consumed = await consumeChallenge(otpStore, email, record.otpHash);
    if (!consumed) {
      return res.status(401).json({
        success: false,
        message: 'Invalid or expired verification code.',
      });
    }
    const challengeUser = await getUserById(String(consumed.userId || ''));
    if (!challengeUser ||
        Number(challengeUser.sessionVersion || 0) !==
          Number(consumed.sessionVersion || 0)) {
      return res.status(401).json({ success: false, message: 'Invalid OTP.' });
    }
    const resetToken = makeResetToken();
    const resetTokenHash = hashChallenge('reset-token', resetToken);
    await setChallenge(resetTokenStore, resetTokenHash, {
      userId: consumed.userId,
      sessionVersion: Number(consumed.sessionVersion || 0),
      expiresAt: Date.now() + otpTtlMinutes * 60 * 1000,
    });

    return res.json({
      success: true,
      message: 'OTP verified.',
      resetToken,
    });
  } catch (error) {
    return next(error);
  }
  },
);

app.post('/auth/forgot-password/reset', async (req, res, next) => {
  try {
    cleanupOtpData();

    const resetToken = String(req.body?.resetToken || '').trim();
    const newPassword = String(req.body?.newPassword || '');

    if (!/^[a-f0-9]{64}$/.test(resetToken)) {
      return res
        .status(400)
        .json({ success: false, message: 'Missing reset token.' });
    }

    if (!passwordRegex.test(newPassword)) {
      return res.status(400).json({
        success: false,
        message:
          'Password must be 8-72 characters with uppercase, lowercase, number, and special character, without spaces.',
      });
    }

    const resetTokenHash = hashChallenge('reset-token', resetToken);
    const tokenRecord = await consumeChallenge(resetTokenStore, resetTokenHash);
    if (!tokenRecord) {
      return res.status(401).json({
        success: false,
        message: 'Reset token is invalid or expired.',
      });
    }

    const user = await getUserById(String(tokenRecord.userId || ''));
    if (!user ||
        Number(user.sessionVersion || 0) !==
          Number(tokenRecord.sessionVersion || 0)) {
      return res.status(401).json({
        success: false,
        message: 'Reset token is invalid or expired.',
      });
    }
    const passwordHash = await bcrypt.hash(newPassword, 12);
    const passwordUpdated = await updateUserPassword(
      user,
      passwordHash,
      Number(tokenRecord.sessionVersion || 0),
    );
    if (!passwordUpdated) {
      return res.status(401).json({
        success: false,
        message: 'Reset token is invalid or expired.',
      });
    }

    return res.json({
      success: true,
      message: 'Password reset successful.',
    });
  } catch (error) {
    return next(error);
  }
});

app.use(notFoundHandler);
app.use(errorHandler);

let cleanupTimer;

export async function initializeBackend() {
  if (!cleanupTimer) {
    cleanupTimer = setInterval(cleanupOtpData, 60 * 1000);
    cleanupTimer.unref?.();
  }

  await initializeDatabase();
}

export default function handler(req, res) {
  return app(req, res);
}

export { app, makeRefundId };
