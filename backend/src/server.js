import bcrypt from 'bcryptjs';
import { v2 as cloudinary } from 'cloudinary';
import { createHash, randomBytes, randomInt } from 'crypto';
import cors from 'cors';
import dotenv from 'dotenv';
import express from 'express';
import fs from 'fs';
import rateLimit from 'express-rate-limit';
import helmet from 'helmet';
import jwt from 'jsonwebtoken';
import { MongoClient, ObjectId } from 'mongodb';
import multer from 'multer';
import nodemailer from 'nodemailer';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
dotenv.config({ path: path.resolve(__dirname, '..', '.env') });
dotenv.config(); // Also try default .env in case of Vercel env vars

const {
  PORT = '4000',
  DISABLE_DB = 'false',
  MONGODB_URI = '',
  MONGODB_DB_NAME = 'test',
  MONGODB_USERS_COLLECTION = 'users',
  MONGODB_STUDENTS_COLLECTION = 'students',
  MONGODB_ALUMNI_COLLECTION = 'alumni',
  ALLOWED_ORIGIN = '*',
  MAILBOXLAYER_ACCESS_KEY = '',
  OTP_TTL_MINUTES = '10',
  OTP_DEV_MODE = 'false',
  JWT_SECRET = '',
  JWT_ACCESS_TTL_MINUTES = '15',
  JWT_REFRESH_TTL_DAYS = '30',
  JWT_ISSUER = 'verifitor',
  SMTP_HOST = 'smtp-relay.brevo.com',
  SMTP_PORT = '587',
  SMTP_SECURE = 'false',
  SMTP_USER = '',
  SMTP_PASS = '',
  SMTP_FROM = 'Verifitor <andreisembrano8@gmail.com>',
  NOTIFICATIONS_API_KEY = '',
  CLOUDINARY_CLOUD_NAME = '',
  CLOUDINARY_API_KEY = '',
  CLOUDINARY_API_SECRET = '',
} = process.env;

const dbEnabled = DISABLE_DB !== 'true';
const alumniCollectionName = String(
  MONGODB_ALUMNI_COLLECTION || MONGODB_USERS_COLLECTION || 'alumni',
);
const studentsCollectionName = String(
  MONGODB_STUDENTS_COLLECTION || 'students',
);

let startupError = null;

if (dbEnabled && !MONGODB_URI) {
  startupError = 'Missing MONGODB_URI in backend/.env';
}

if (!JWT_SECRET) {
  startupError = startupError || 'Missing JWT_SECRET in backend/.env';
}

const cloudinaryEnabled = Boolean(
  process.env.CLOUDINARY_URL || (CLOUDINARY_CLOUD_NAME && CLOUDINARY_API_KEY && CLOUDINARY_API_SECRET),
);
if (cloudinaryEnabled) {
  if (process.env.CLOUDINARY_URL) {
    // The Cloudinary SDK automatically picks up process.env.CLOUDINARY_URL
    // We just need to make sure we don't override it with empty values.
    cloudinary.config(true);
  } else {
    cloudinary.config({
      cloud_name: CLOUDINARY_CLOUD_NAME,
      api_key: CLOUDINARY_API_KEY,
      api_secret: CLOUDINARY_API_SECRET,
      secure: true,
    });
  }
}

const app = express();

const uploadsDir = path.join(__dirname, '..', 'uploads');
const receiptsDir = path.join(uploadsDir, 'receipts');
try {
  fs.mkdirSync(receiptsDir, { recursive: true });
} catch (err) {
  console.warn('Could not create receipts upload directory (read-only filesystem):', err.message);
}

const allowedReceiptMimeTypes = new Set([
  'image/jpeg',
  'image/jpg',
  'image/png',
  'image/webp',
  'image/heic',
  'image/heif',
  'image/heic-sequence',
  'image/heif-sequence',
]);
const allowedImageExtensions = new Set([
  '.jpg',
  '.jpeg',
  '.png',
  '.webp',
  '.heic',
  '.heif',
]);

function imageFileFilter(req, file, cb) {
  const ext = path.extname(file.originalname || '').toLowerCase();
  if (!allowedReceiptMimeTypes.has(file.mimetype)) {
    if (file.mimetype === 'application/octet-stream' &&
        allowedImageExtensions.has(ext)) {
      return cb(null, true);
    }
    req.fileValidationError =
      'Only JPG, PNG, WEBP, or HEIC images are allowed.';
    return cb(null, false);
  }
  return cb(null, true);
}
const receiptUpload = multer({
  storage: multer.memoryStorage(),
  fileFilter: imageFileFilter,
  limits: {
    fileSize: 8 * 1024 * 1024,
  },
});
const profileUpload = multer({
  storage: multer.memoryStorage(),
  fileFilter: imageFileFilter,
  limits: {
    fileSize: 5 * 1024 * 1024,
  },
});

app.use(helmet());
app.use(
  cors({
    origin: ALLOWED_ORIGIN === '*' ? true : ALLOWED_ORIGIN,
  }),
);

app.use((req, res, next) => {
  if (startupError) {
    return res.status(500).json({ error: startupError });
  }
  next();
});
app.use(express.json({ limit: '1mb' }));
app.use(async (req, res, next) => {
  try {
    await ensureDb();
    next();
  } catch (err) {
    next(err);
  }
});
app.use('/uploads', express.static(uploadsDir));

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 100,
  standardHeaders: true,
  legacyHeaders: false,
});

app.use('/auth', authLimiter);

const client = dbEnabled ? new MongoClient(MONGODB_URI) : null;
let alumniUsers;
let studentUsers;
let receipts;
let requests;
let notifications;
let transactions;
let refunds;
const memoryUsers = new Map();
const memoryReceipts = [];
const memoryRequests = [];
const memoryNotifications = [];
const memoryTransactions = [];
const memoryRefunds = [];

async function ensureDb() {
  if (!dbEnabled) return;
  if (alumniUsers && studentUsers) return;

  try {
    await client.connect();
    const db = client.db(MONGODB_DB_NAME);
    alumniUsers = db.collection(alumniCollectionName);
    studentUsers = db.collection(studentsCollectionName);
    receipts = db.collection('transactions');
    requests = db.collection('requests');
    notifications = db.collection('notifications');
    transactions = db.collection('transactions');
    refunds = db.collection('refunds');
  } catch (error) {
    throw new Error(`MongoDB connection failed: ${error.message}`);
  }
}

const defaultDocumentPrice = 100;
const defaultProcessingFee = 0;

function getDocumentPrice(docName) {
  const key = String(docName || '').trim().toLowerCase();
  if (!key) return defaultDocumentPrice;
  const priceMap = {
    'f-137 (sh)': 400,
    'f-137 (gs/jh)': 250,
    'f-137 (gs/jh)': 250,
    'tor': 600,
    'transcript of records': 600,
    'transcript of records (tor)': 600,
    'gwa': 250,
    'general weighted average (gwa)': 250,
    'gmc/esc': 200,
    'good moral character/esc (gmc/esc)': 200,
    'certificate of good moral': 200,
    'card (re-print)': 200,
    'moi': 250,
    'moi (memorandum of inclusion)': 250,
    'student verification': 250,
    'request form (lost)': 200,
    'ctc': 200,
    'certified true copy (ctc)': 200,
    'ctc of certificate of matriculation': 200,
    'ctc of diploma': 200,
    'ctc of curriculum': 200,
    'diploma (2nd copy)': 300,
    'application for grad': 200,
    'application for graduation': 200,
    'certificate of candidacy for graduation': 200,
    'prospectus': 200,
    'cert. of grades': 250,
    'certificate of grades': 250,
    'grade certification': 250,
    'transfer credential': 300,
    'cert. of enrollment': 250,
    'certificate of enrollment': 250,
    'clearance': 200,
    'certificate of units earned': 200,
    'certificate of assessment': 200,
    'certificate of registration': 200,
    'others': 0,
  };
  if (priceMap[key] != null) return priceMap[key];
  if (key.includes('ctc')) return 200;
  return defaultDocumentPrice;
}

const emailRegex = /^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/;
const passwordRegex =
  /^(?=\S{8,72}$)(?=.*[A-Z])(?=.*[a-z])(?=.*[0-9])(?=.*[!@#$%^&*(),.?":{}|<>]).*$/;
const personNameRegex = /^[\p{L}][\p{L}\p{M} .'-]*$/u;
const studentIdRegex = /^[A-Za-z0-9][A-Za-z0-9-]{3,29}$/;
const studentYearLevels = new Set([
  '1st Year',
  '2nd Year',
  '3rd Year',
  '4th Year',
  '5th Year',
  'Graduate Student',
]);

const otpStore = new Map();
const registrationOtpStore = new Map();
const resetTokenStore = new Map();

const smtpEnabled = Boolean(SMTP_HOST && SMTP_PORT && SMTP_USER && SMTP_PASS);
const mailTransporter = smtpEnabled
  ? nodemailer.createTransport({
      host: SMTP_HOST,
      port: Number(SMTP_PORT),
      secure: SMTP_SECURE === 'true',
      auth: {
        user: SMTP_USER,
        pass: SMTP_PASS,
      },
      tls: {
        rejectUnauthorized: false
      }
    })
  : null;

function normalizeEmail(email) {
  return String(email || '').trim().toLowerCase();
}

async function normalizeEmailsInCollection(collection, label) {
  if (!collection) return;
  try {
    const cursor = collection.find({}, {
      projection: { email: 1, schoolEmail: 1, personalEmail: 1 },
    });
    for await (const user of cursor) {
      const updates = {};
      if (user?.email) {
        const nextEmail = normalizeEmail(user.email);
        if (nextEmail && nextEmail !== user.email) {
          updates.email = nextEmail;
        }
      }
      if (user?.schoolEmail) {
        const nextSchoolEmail = normalizeEmail(user.schoolEmail);
        if (nextSchoolEmail && nextSchoolEmail !== user.schoolEmail) {
          updates.schoolEmail = nextSchoolEmail;
        }
      }
      if (user?.personalEmail) {
        const nextPersonalEmail = normalizeEmail(user.personalEmail);
        if (nextPersonalEmail && nextPersonalEmail !== user.personalEmail) {
          updates.personalEmail = nextPersonalEmail;
        }
      }
      if (Object.keys(updates).length > 0) {
        try {
          await collection.updateOne({ _id: user._id }, { $set: updates });
        } catch (error) {
          console.warn(
            `Failed to normalize emails for ${label} ${user._id}:`,
            error?.message || error,
          );
        }
      }
    }
  } catch (error) {
    console.warn(
      `Email normalization skipped for ${label}:`,
      error?.message || error,
    );
  }
}

function makeUserId() {
  return randomBytes(12).toString('hex');
}

function makeRequestId() {
  return `req_${Date.now()}_${randomBytes(6).toString('hex')}`;
}

function buildUserResponse(user) {
  if (!user) return null;
  return {
    id: user._id || user.id,
    firstName: user.firstName,
    lastName: user.lastName,
    email: user.email,
    role: user.role,
  };
}

function buildProfileResponse(user) {
  if (!user) return null;
  const role = normalizeRole(user.role);
  const isStudent = role === 'student';
  const schoolEmail = isStudent ? user.schoolEmail || '' : '';
  return {
    id: user._id || user.id,
    firstName: user.firstName,
    lastName: user.lastName,
    profileImageUrl: user.profileImageUrl || user.profilePic || '',
    email: isStudent && schoolEmail ? schoolEmail : user.email,
    personalEmail: isStudent ? '' : user.personalEmail || user.email || '',
    role: role || 'alumni',
    schoolEmail,
    studentId: isStudent ? user.studentId || '' : '',
    yearLevel: user.yearLevel || '',
    program: user.program || '',
  };
}

function normalizeRole(role) {
  const normalized = String(role || '').trim().toLowerCase();
  if (normalized === 'student') return 'student';
  if (normalized === 'former_student') return 'former_student';
  return 'alumni';
}

function parseRegistrationRole(role) {
  const normalized = String(role || '').trim().toLowerCase();
  if (normalized === 'former_student' || normalized === 'alumni') {
    return normalized;
  }
  return '';
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
  if (sub) {
    const byId = await getUserById(sub);
    if (byId) return byId;
  }

  const email = normalizeEmail(payload.email);
  if (emailRegex.test(email)) {
    return getUserByEmail(email);
  }

  return null;
}

function toPositiveNumber(value, fallback) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) return fallback;
  return parsed;
}

function toNonNegativeNumber(value, fallback) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < 0) return fallback;
  return parsed;
}

const jwtIssuer = String(JWT_ISSUER || '').trim();
const accessTokenTtlSeconds =
  toPositiveNumber(JWT_ACCESS_TTL_MINUTES, 15) * 60;
const refreshTokenTtlMs =
  toPositiveNumber(JWT_REFRESH_TTL_DAYS, 30) * 24 * 60 * 60 * 1000;
const notificationsApiKey = String(NOTIFICATIONS_API_KEY || '').trim();

function signAccessToken(user) {
  const payload = {
    sub: String(user._id || user.id || ''),
    email: user.email,
    role: user.role,
  };
  const options = jwtIssuer
    ? { expiresIn: accessTokenTtlSeconds, issuer: jwtIssuer }
    : { expiresIn: accessTokenTtlSeconds };
  return jwt.sign(payload, JWT_SECRET, options);
}

function makeRefreshToken() {
  return randomBytes(48).toString('hex');
}

function hashRefreshToken(token) {
  return createHash('sha256').update(token).digest('hex');
}

function buildRefreshTokenRecord(token) {
  return {
    tokenHash: hashRefreshToken(token),
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

async function storeRefreshToken(email, record) {
  if (dbEnabled) {
    const found = await getUserByEmailWithCollection(email);
    if (!found?.collection) return;
    await found.collection.updateOne(
      { email },
      {
        $push: {
          refreshTokens: {
            $each: [record],
            $slice: -5,
          },
        },
      },
    );
    return;
  }

  const existing = memoryUsers.get(email);
  if (!existing) return;
  const refreshTokens = Array.isArray(existing.refreshTokens)
    ? existing.refreshTokens
    : [];
  memoryUsers.set(email, {
    ...existing,
    refreshTokens: [...refreshTokens, record].slice(-5),
  });
}

async function revokeRefreshToken(email, tokenHash) {
  if (dbEnabled) {
    const found = await getUserByEmailWithCollection(email);
    if (!found?.collection) return;
    await found.collection.updateOne(
      { email },
      { $pull: { refreshTokens: { tokenHash } } },
    );
    return;
  }

  const existing = memoryUsers.get(email);
  if (!existing) return;
  const refreshTokens = Array.isArray(existing.refreshTokens)
    ? existing.refreshTokens
    : [];
  memoryUsers.set(email, {
    ...existing,
    refreshTokens: refreshTokens.filter(
      (record) => record.tokenHash !== tokenHash,
    ),
  });
}

async function issueTokensForUser(user) {
  const refreshToken = makeRefreshToken();
  const refreshRecord = buildRefreshTokenRecord(refreshToken);
  await storeRefreshToken(user.email, refreshRecord);
  const accessToken = signAccessToken(user);
  return {
    accessToken,
    refreshToken,
    expiresInSeconds: accessTokenTtlSeconds,
  };
}

function requireAuth(req, res, next) {
  const authHeader = String(req.headers.authorization || '');
  if (!authHeader.startsWith('Bearer ')) {
    return res
      .status(401)
      .json({ success: false, message: 'Missing access token.' });
  }

  const token = authHeader.slice(7).trim();
  if (!token) {
    return res
      .status(401)
      .json({ success: false, message: 'Missing access token.' });
  }

  try {
    const payload = jwtIssuer
      ? jwt.verify(token, JWT_SECRET, { issuer: jwtIssuer })
      : jwt.verify(token, JWT_SECRET);
    req.auth = payload;
    return next();
  } catch (error) {
    return res
      .status(401)
      .json({ success: false, message: 'Invalid or expired token.' });
  }
}

function requireNotificationSender(req, res, next) {
  const headerKey = String(req.headers['x-notification-key'] || '').trim();
  if (notificationsApiKey) {
    if (headerKey && headerKey === notificationsApiKey) {
      return next();
    }
    return requireAuth(req, res, next);
  }

  if (headerKey) {
    return next();
  }
  return requireAuth(req, res, next);
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

async function createReceiptRecord(receipt) {
  if (dbEnabled) {
    const result = await receipts.insertOne(receipt);
    return result.insertedId;
  }

  const id = makeUserId();
  memoryReceipts.push({ ...receipt, _id: id });
  return id;
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
    requestId: trueRequestId || purpose, // Maps real requestId to link accurately
    name: `${user?.firstName || ''} ${user?.lastName || ''}`.trim(),
    documentType: docName || '',
    paymentMode: paymentType === 'onsite' ? 'Other Online Payment' : 'GCash',
    amount: amount ? amount.toString() : '0.00',
    receiptImage: imageUrl || '',
    payerName: `${user?.firstName || ''} ${user?.lastName || ''}`.trim(),
    payerEmail: user?.email || '',
    payerType:
      normalizeRole(user?.role) === 'alumni'
        ? 'Alumni'
        : normalizeRole(user?.role) === 'former_student'
          ? 'Former Student'
          : 'Student',
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
    imageUrl: record.imageUrl || '',
    publicId: record.publicId || '',
    amount: record.amount ?? null,
    status: record.status || '',
    paymentType: record.paymentType || '',
    docName: record.docName || '',
    purpose: record.purpose || '',
    createdAt: record.createdAt || new Date().toISOString(),
  };
}

async function uploadReceiptToCloudinary(file) {
  if (!cloudinaryEnabled) {
    if (process.env.VERCEL) {
      throw new Error('Cloudinary is not configured. Local uploads are not supported on Vercel. Please add CLOUDINARY_CLOUD_NAME, CLOUDINARY_API_KEY, and CLOUDINARY_API_SECRET to Vercel environment variables.');
    }
    const fileName = `receipt-${Date.now()}-${Math.round(Math.random() * 1e9)}${path.extname(file.originalname)}`;
    const uploadDir = 'c:\\Users\\Sarah\\VeriFitorWeb\\Verifitor-Web-main\\backend\\uploads\\receipts';
    if (!fs.existsSync(uploadDir)) {
      fs.mkdirSync(uploadDir, { recursive: true });
    }
    const filePath = path.join(uploadDir, fileName);
    await fs.promises.writeFile(filePath, file.buffer);
    return {
      secure_url: `/uploads/receipts/${fileName}`,
      url: `/uploads/receipts/${fileName}`,
      public_id: `local-${fileName}`
    };
  }
  if (!file?.buffer) {
    throw new Error('Receipt image is required.');
  }

  return new Promise((resolve, reject) => {
    const upload = cloudinary.uploader.upload_stream(
      {
        folder: 'capstone/receipts',
        resource_type: 'image',
      },
      (error, result) => {
        if (error) {
          reject(error);
          return;
        }
        resolve(result);
      },
    );

    upload.end(file.buffer);
  });
}

async function uploadProfilePhotoToCloudinary(file) {
  if (!cloudinaryEnabled) {
    if (process.env.VERCEL) {
      throw new Error('Cloudinary is not configured. Local uploads are not supported on Vercel. Please add CLOUDINARY_CLOUD_NAME, CLOUDINARY_API_KEY, and CLOUDINARY_API_SECRET to Vercel environment variables.');
    }
    const fileName = `profile-${Date.now()}-${Math.round(Math.random() * 1e9)}${path.extname(file.originalname)}`;
    const uploadDir = 'c:\\Users\\Sarah\\VeriFitorWeb\\Verifitor-Web-main\\backend\\uploads\\profiles';
    if (!fs.existsSync(uploadDir)) {
      fs.mkdirSync(uploadDir, { recursive: true });
    }
    const filePath = path.join(uploadDir, fileName);
    await fs.promises.writeFile(filePath, file.buffer);
    return {
      secure_url: `/uploads/profiles/${fileName}`,
      url: `/uploads/profiles/${fileName}`,
      public_id: `local-${fileName}`
    };
  }
  if (!file?.buffer) {
    throw new Error('Profile photo is required.');
  }

  return new Promise((resolve, reject) => {
    const upload = cloudinary.uploader.upload_stream(
      {
        folder: 'capstone/profiles',
        resource_type: 'image',
      },
      (error, result) => {
        if (error) {
          reject(error);
          return;
        }
        resolve(result);
      },
    );

    upload.end(file.buffer);
  });
}

async function findLatestReceiptForUser(user, { docName, purpose }) {
  const userId = user?._id || user?.id;
  const email = normalizeEmail(user?.email);
  if (!userId && !email) return null;

  if (dbEnabled) {
    const query = {};
    const clauses = [];
    if (userId && ObjectId.isValid(String(userId))) {
      clauses.push({ userId: new ObjectId(String(userId)) });
    }
    if (emailRegex.test(email)) {
      clauses.push({ email });
    }
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

  const normalizedId = userId ? String(userId) : '';
  const items = memoryReceipts.filter((record) => {
    if (normalizedId && String(record.userId) === normalizedId) {
      return true;
    }
    if (email && String(record.email || '').toLowerCase() === email) {
      return true;
    }
    return false;
  });

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
  const userId = user?._id || user?.id;
  const email = normalizeEmail(user?.email);
  if (!userId && !email) return [];

  const safeLimit = Math.min(toPositiveNumber(limit, 50), 200);

  if (dbEnabled) {
    const clauses = [];
    if (userId && ObjectId.isValid(String(userId))) {
      clauses.push({ userId: new ObjectId(String(userId)) });
    }
    if (emailRegex.test(email)) {
      clauses.push({ email });
    }
    if (clauses.length === 0) return [];
    return notifications
      .find({ $or: clauses })
      .sort({ createdAt: -1 })
      .limit(safeLimit)
      .toArray();
  }

  const normalizedId = userId ? String(userId) : '';
  return memoryNotifications
    .filter((record) => {
      if (normalizedId && String(record.userId) === normalizedId) {
        return true;
      }
      if (email && String(record.email || '').toLowerCase() === email) {
        return true;
      }
      return false;
    })
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
    title: record.title || '',
    message: record.message || '',
    isRead: Boolean(record.isRead),
    createdAt: record.createdAt || new Date().toISOString(),
    email: record.email || '',
    userId: record.userId ? String(record.userId) : '',
  };
}

async function listTransactionsForUser(user, limit) {
  const userId = user?._id || user?.id;
  const email = normalizeEmail(user?.email);
  if (!userId && !email) return [];

  const safeLimit = Math.min(toPositiveNumber(limit, 50), 200);

  if (dbEnabled) {
    const clauses = [];
    if (userId && ObjectId.isValid(String(userId))) {
      clauses.push({ userId: new ObjectId(String(userId)) });
    }
    if (emailRegex.test(email)) {
      clauses.push({ email });
    }
    if (clauses.length === 0) return [];
    return transactions
      .find({ $or: clauses })
      .sort({ createdAt: -1 })
      .limit(safeLimit)
      .toArray();
  }

  const normalizedId = userId ? String(userId) : '';
  return memoryTransactions
    .filter((record) => {
      if (normalizedId && String(record.userId) === normalizedId) {
        return true;
      }
      if (email && String(record.email || '').toLowerCase() === email) {
        return true;
      }
      return false;
    })
    .sort(
      (a, b) =>
        new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime(),
    )
    .slice(0, safeLimit);
}

function buildTransactionResponse(record) {
  if (!record) return null;
  const id = record._id || record.id;
  return {
    id: id ? String(id) : '',
    docName: record.docName || record.documentName || record.title || '',
    purpose: record.purpose || '',
    status: record.status || record.state || 'completed',
    createdAt: record.createdAt || record.date || new Date().toISOString(),
    paymentType: record.paymentType || record.paymentMode || '',
    totalAmount: record.totalAmount ?? record.amount ?? null,
    refundStatus: record.refundStatus || '',
    email: record.email || '',
    userId: record.userId ? String(record.userId) : '',
  };
}

async function revokeAllRefreshTokens(email) {
  if (dbEnabled) {
    const found = await getUserByEmailWithCollection(email);
    if (!found?.collection) return;
    await found.collection.updateOne(
      { email },
      { $set: { refreshTokens: [] } },
    );
    return;
  }

  const existing = memoryUsers.get(email);
  if (!existing) return;
  memoryUsers.set(email, { ...existing, refreshTokens: [] });
}

async function findTransactionForUser(user, transactionId) {
  const userId = user?._id || user?.id;
  const email = normalizeEmail(user?.email);
  if ((!userId && !email) || !transactionId) return null;

  if (dbEnabled) {
    const ownerClauses = [];
    if (userId && ObjectId.isValid(String(userId))) {
      ownerClauses.push({ userId: new ObjectId(String(userId)) });
    }
    if (emailRegex.test(email)) ownerClauses.push({ email });
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
    const recordId = String(record._id || record.id || record.transactionId || '');
    const ownsRecord =
      (userId && String(record.userId) === String(userId)) ||
      (email && normalizeEmail(record.email) === email);
    return ownsRecord && recordId === transactionId;
  }) || null;
}

async function findRefundForTransaction(user, transactionId) {
  const userId = user?._id || user?.id;
  const email = normalizeEmail(user?.email);
  if (dbEnabled) {
    const ownerClauses = [];
    if (userId && ObjectId.isValid(String(userId))) {
      ownerClauses.push({ userId: new ObjectId(String(userId)) });
    }
    if (emailRegex.test(email)) ownerClauses.push({ email });
    if (ownerClauses.length === 0) return null;
    return refunds.findOne({ transactionId, $or: ownerClauses });
  }

  return memoryRefunds.find((record) =>
    record.transactionId === transactionId &&
    ((userId && String(record.userId) === String(userId)) ||
      (email && normalizeEmail(record.email) === email))
  ) || null;
}

async function createRefundRecord(record, transaction) {
  if (dbEnabled) {
    const result = await refunds.insertOne(record);
    await transactions.updateOne(
      { _id: transaction._id },
      { $set: { refundStatus: 'pending', refundRequestedAt: record.createdAt } },
    );
    return result.insertedId;
  }

  const id = makeUserId();
  memoryRefunds.push({ ...record, _id: id });
  const index = memoryTransactions.indexOf(transaction);
  if (index >= 0) {
    memoryTransactions[index] = {
      ...memoryTransactions[index],
      refundStatus: 'pending',
      refundRequestedAt: record.createdAt,
    };
  }
  return id;
}

async function updateRequestStatusForPayment({
  userId,
  docName,
  purpose,
  paymentType,
}) {
  if (!userId || !docName || !purpose) return null;

  const updates = {
    status: 'Pending',
    mobileStatus: 'pending',
    paymentType,
    updatedAt: new Date().toISOString(),
  };

  if (dbEnabled) {
    const record = await requests.findOne(
      { userId, docName, purpose },
      { sort: { createdAt: -1 } },
    );
    if (!record?._id) return null;
    await requests.updateOne({ _id: record._id }, { $set: updates });
    return record._id;
  }

  const recordIndex = [...memoryRequests]
    .reverse()
    .findIndex(
      (record) =>
        String(record.userId) === String(userId) &&
        record.docName === docName &&
        record.purpose === purpose,
    );

  if (recordIndex < 0) return null;
  const actualIndex = memoryRequests.length - 1 - recordIndex;
  memoryRequests[actualIndex] = {
    ...memoryRequests[actualIndex],
    ...updates,
  };
  return memoryRequests[actualIndex]._id || memoryRequests[actualIndex].id;
}

function buildRequestResponse(record) {
  if (!record) return null;
  const id = record._id || record.id;
  const mappedPrice = getDocumentPrice(record.docName);
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
  return {
    id: id ? String(id) : '',
    requestId: record.requestId ? String(record.requestId) : '',
    docName: record.docName || '',
    purpose: record.purpose || '',
    status: record.mobileStatus || record.status || 'pending',
    createdAt: record.createdAt || new Date().toISOString(),
    updatedAt: record.updatedAt || record.createdAt || new Date().toISOString(),
    email: record.email || '',
    role: record.role || '',
    schoolEmail: record.schoolEmail || '',
    studentId: record.studentId || '',
    yearGraduated: record.yearGraduated || '',
    yearLevel: record.yearLevel || '',
    program: record.program || '',
    documentPrice,
    processingFee,
    totalAmount,
  };
}

function parseStatusFilter(value) {
  if (!value) return [];
  return String(value)
    .split(',')
    .map((status) => status.trim().toLowerCase())
    .filter(Boolean);
}

async function listRequestsForUser(user, statuses) {
  const userId = user?._id || user?.id;
  if (!userId) return [];

  if (dbEnabled) {
    const query = { userId };
    if (statuses && statuses.length > 0) {
      const regexes = statuses.map((s) => new RegExp(`^${s}$`, 'i'));
      query.$or = [{ status: { $in: regexes } }, { mobileStatus: { $in: regexes } }];
    }
    return requests.find(query).sort({ createdAt: -1 }).toArray();
  }

  const userIdValue = String(userId);
  let items = memoryRequests.filter(
    (record) => String(record.userId) === userIdValue,
  );
  if (statuses && statuses.length > 0) {
    items = items.filter((record) =>
      statuses.includes(String(record.status || '').toLowerCase()) ||
      statuses.includes(String(record.mobileStatus || '').toLowerCase())
    );
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

async function updateUserPassword(email, passwordHash) {
  if (dbEnabled) {
    const found = await getUserByEmailWithCollection(email);
    if (!found?.collection) return;
    await found.collection.updateOne(
      { email },
      {
        $set: { passwordHash, updatedAt: new Date().toISOString() },
        $unset: { password: '' },
      },
    );
    return;
  }

  const existing = memoryUsers.get(email);
  if (!existing) return;
  memoryUsers.set(email, {
    ...existing,
    passwordHash,
    password: undefined,
    updatedAt: new Date().toISOString(),
  });
}

async function ensurePasswordHash(user) {
  if (!user) return '';
  if (user.passwordHash) return user.passwordHash;
  if (!user.password) return '';

  const legacyHash = String(user.password).trim();
  if (!legacyHash) return '';

  if (dbEnabled) {
    const found = await getUserByEmailWithCollection(
      normalizeEmail(user.email),
    );
    if (found?.collection && user._id) {
      await found.collection.updateOne(
        { _id: user._id },
        {
          $set: { passwordHash: legacyHash, updatedAt: new Date().toISOString() },
          $unset: { password: '' },
        },
      );
    }
  } else {
    const email = normalizeEmail(user.email);
    const existing = memoryUsers.get(email);
    if (existing) {
      memoryUsers.set(email, {
        ...existing,
        passwordHash: legacyHash,
        password: undefined,
        updatedAt: new Date().toISOString(),
      });
    }
  }

  return legacyHash;
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

  const endpoint = `http://apilayer.net/api/check?access_key=${encodeURIComponent(
    MAILBOXLAYER_ACCESS_KEY,
  )}&email=${encodeURIComponent(email)}&smtp=1&format=1`;

  try {
    const response = await fetch(endpoint);
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

function makeOtp() {
  return String(randomInt(100000, 1000000));
}

function makeResetToken() {
  return randomBytes(24).toString('hex');
}

function cleanupOtpData() {
  const now = Date.now();

  for (const store of [otpStore, registrationOtpStore]) {
    for (const [email, value] of store.entries()) {
      if (value.expiresAt <= now) store.delete(email);
    }
  }

  for (const [token, value] of resetTokenStore.entries()) {
    if (value.expiresAt <= now) resetTokenStore.delete(token);
  }
}

function putOtp(store, email, extra = {}) {
  const otp = makeOtp();
  const expiresAt = Date.now() + Number(OTP_TTL_MINUTES) * 60 * 1000;
  store.set(email, { otp, expiresAt, attempts: 0, ...extra });
  return otp;
}

async function sendOtpEmail({ email, otp, purpose }) {
  if (!mailTransporter) {
    throw new Error('SMTP is not configured.');
  }

  const ttlMinutes = Number(OTP_TTL_MINUTES);
  const subjects = {
    registration: 'Your Verifitor registration OTP',
    login: 'Your Verifitor login OTP',
    'password-reset': 'Your Verifitor password reset OTP',
  };
  const subject = subjects[purpose] || 'Your Verifitor OTP';
  const text = `Your OTP is ${otp}. It expires in ${ttlMinutes} minutes.`;

  await mailTransporter.sendMail({
    from: SMTP_FROM,
    to: email,
    subject,
    text,
  });
}

async function sendOtpResponse(res, { email, otp, purpose }) {
  if (OTP_DEV_MODE === 'true') {
    return res.json({
      success: true,
      message: 'OTP generated (dev mode).',
      otp,
    });
  }

  if (!mailTransporter) {
    return res.status(500).json({
      success: false,
      message: 'SMTP is not configured.',
    });
  }

  try {
    await sendOtpEmail({ email, otp, purpose });
    return res.json({
      success: true,
      message: 'OTP sent to your email.',
    });
  } catch (error) {
    console.error('OTP email failed:', error?.message || error);
    return res.status(502).json({
      success: false,
      message: 'Failed to send OTP email. Check SMTP credentials and sender.',
    });
  }
}

function validateRegisterPayload(body) {
  const role = parseRegistrationRole(body.role);
  const firstName = String(body.firstName || '').trim();
  const lastName = String(body.lastName || '').trim();
  const personalEmail = normalizeEmail(body.email);
  const schoolEmail = normalizeEmail(body.schoolEmail);
  const password = String(body.password || '');
  const studentId = String(body.studentId || '').trim();
  const yearLevel = String(body.yearLevel || '').trim();
  const program = String(body.program || '').trim();
  const isStudent = role === 'student';
  const email = isStudent ? schoolEmail : personalEmail;

  if (!role) {
    return { error: 'Please select Former student or Alumni.' };
  }

  if (firstName.length < 2 || firstName.length > 50 ||
      !personNameRegex.test(firstName)) {
    return { error: 'Enter a valid first name (2-50 characters).' };
  }
  if (lastName.length < 2 || lastName.length > 50 ||
      !personNameRegex.test(lastName)) {
    return { error: 'Enter a valid last name (2-50 characters).' };
  }

  if (isStudent && !emailRegex.test(schoolEmail)) {
    return { error: 'Enter a valid school email address.' };
  }
  if (!isStudent && !emailRegex.test(personalEmail)) {
    return { error: 'Enter a valid personal email address.' };
  }

  if (!passwordRegex.test(password)) {
    return {
      error:
        'Password must be 8-72 characters with uppercase, lowercase, number, and special character, without spaces.',
    };
  }

  if (isStudent && !studentIdRegex.test(studentId)) {
    return {
      error: 'Student ID must be 4-30 letters, numbers, or hyphens.',
    };
  }

  if (isStudent && !studentYearLevels.has(yearLevel)) {
    return { error: 'Select a valid year level.' };
  }

  if (!isStudent) {
    const graduationYear = Number(yearLevel);
    const currentYear = new Date().getFullYear();
    if (!/^\d{4}$/.test(yearLevel) ||
        graduationYear < 1950 || graduationYear > currentYear) {
      return { error: 'Select a valid graduation or last-attended year.' };
    }
  }

  if (program.length < 2 || program.length > 100) {
    return { error: 'Select a valid program.' };
  }

  return {
    role,
    firstName,
    lastName,
    email,
    password,
    personalEmail: isStudent ? '' : personalEmail,
    schoolEmail: isStudent ? schoolEmail : '',
    studentId: isStudent ? studentId : '',
    yearLevel,
    program,
  };
}

function validateProfilePayload(body) {
  const firstName = String(body.firstName || '').trim();
  const lastName = String(body.lastName || '').trim();
  const schoolEmail = String(body.schoolEmail || '').trim();
  const personalEmail = String(body.personalEmail || '').trim();
  const studentId = String(body.studentId || '').trim();
  const yearLevel = String(body.yearLevel || '').trim();
  const program = String(body.program || '').trim();
  const newPassword = String(body.newPassword || '').trim();

  if (firstName.length < 2 || lastName.length < 2) {
    return { error: 'First name and last name are required (min 2 chars).' };
  }

  if (schoolEmail && !emailRegex.test(schoolEmail)) {
    return { error: 'Invalid school email address.' };
  }

  if (personalEmail && !emailRegex.test(personalEmail)) {
    return { error: 'Invalid personal email address.' };
  }

  if (newPassword && !passwordRegex.test(newPassword)) {
    return {
      error:
        'Password must be at least 8 chars and include uppercase, lowercase, number, and special character.',
    };
  }

  return {
    firstName,
    lastName,
    schoolEmail,
    personalEmail,
    studentId,
    yearLevel,
    program,
    newPassword,
  };
}

app.get('/health', (_req, res) => {
  res.json({ success: true, message: 'API is healthy' });
});

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

      const docName = String(req.body?.docName || '').trim();
      const purpose = String(req.body?.purpose || '').trim();
      const amount = toNonNegativeNumber(req.body?.amount, 0);
      const status = String(req.body?.status || 'pending_completion').trim();

      let trueRequestId = purpose;
      if (dbEnabled) {
        const reqRecord = await requests.findOne(
          { userId: new ObjectId(String(user._id || user.id)), docName, purpose },
          { sort: { createdAt: -1 } }
        );
        if (reqRecord && reqRecord.requestId) {
          trueRequestId = reqRecord.requestId;
        }
      }

      const uploadResult = await uploadReceiptToCloudinary(req.file);
      const receipt = buildReceiptRecord({
        user,
        paymentType,
        docName,
        purpose,
        trueRequestId, // Pass the real requestId
        amount,
        status: status || 'pending_completion',
        imageUrl: uploadResult?.secure_url || uploadResult?.url || '',
        publicId: uploadResult?.public_id || '',
        originalName: req.file.originalname,
        mimeType: req.file.mimetype,
        size: req.file.size,
      });

      const receiptId = await createReceiptRecord(receipt);
      await updateRequestStatusForPayment({
        userId: receipt.userId,
        docName: docName,
        purpose: purpose,
        paymentType: receipt.paymentType,
      });
      return res.status(201).json({
        success: true,
        receiptId,
        imageUrl: receipt.imageUrl,
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
    const receipt = await findLatestReceiptForUser(user, { docName, purpose });

    return res.json({
      success: true,
      receipt: buildReceiptResponse(receipt),
    });
  } catch (error) {
    return next(error);
  }
});

app.post('/requests', requireAuth, async (req, res, next) => {
  try {
    const docName = String(req.body?.docName || '').trim();
    const purpose = String(req.body?.purpose || '').trim();

    if (!docName) {
      return res.status(400).json({
        success: false,
        message: 'Document name is required.',
      });
    }

    if (!purpose) {
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

    const documentPrice = toNonNegativeNumber(
      req.body?.documentPrice,
      getDocumentPrice(docName),
    );
    const processingFee = toNonNegativeNumber(
      req.body?.processingFee,
      defaultProcessingFee,
    );
    const totalAmount = toNonNegativeNumber(
      req.body?.totalAmount,
      documentPrice + processingFee,
    );

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
      role: user.role || '',
      firstName: user.firstName || '',
      lastName: user.lastName || '',
      personalEmail: user.personalEmail || user.email || '',
      schoolEmail: user.schoolEmail || '',
      yearGraduated:
        normalizeRole(user.role) !== 'student' ? user.yearLevel || '' : '',
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
    
    if (dbEnabled) {
      await notifications.insertOne({
        message: `Your document request for ${docName} has been submitted!`,
        isRead: false,
        email: user.email || '',
        userId: user._id || user.id,
        date: new Date(),
        createdAt: new Date(),
        updatedAt: new Date()
      });
    }

    return res.status(201).json({
      success: true,
      requestId: String(requestId),
      request: { ...requestRecord, id: String(requestId) },
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

    const records = await listNotificationsForUser(user, req.query?.limit);
    return res.json({
      success: true,
      notifications: records.map(buildNotificationResponse).filter(Boolean),
    });
  } catch (error) {
    return next(error);
  }
});

app.post('/notifications', requireNotificationSender, async (req, res, next) => {
  try {
    const title = String(req.body?.title || '').trim();
    const message = String(req.body?.message || '').trim();
    const emailInput = normalizeEmail(req.body?.email);
    const userIdInput = String(req.body?.userId || '').trim();

    if (!title || !message) {
      return res.status(400).json({
        success: false,
        message: 'Notification title and message are required.',
      });
    }

    let user = null;
    if (req.auth) {
      user = await getUserFromAuth(req.auth);
    }

    if (emailInput && emailRegex.test(emailInput)) {
      user = (await getUserByEmail(emailInput)) || user;
    }

    const resolvedEmail =
      (user?.email && normalizeEmail(user.email)) ||
      (emailRegex.test(emailInput) ? emailInput : '');

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
    return res.json({
      success: true,
      transactions: records.map(buildTransactionResponse).filter(Boolean),
    });
  } catch (error) {
    return next(error);
  }
});

app.post('/refunds', requireAuth, async (req, res, next) => {
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

    if (!transactionId) {
      return res.status(400).json({
        success: false,
        message: 'Transaction is required.',
      });
    }
    if (!['gcash', 'bank_transfer'].includes(refundMethod)) {
      return res.status(400).json({
        success: false,
        message: 'Choose a valid refund method.',
      });
    }
    if (accountName.length < 2) {
      return res.status(400).json({
        success: false,
        message: 'Enter the account holder name.',
      });
    }
    if (refundMethod === 'gcash' && !/^09\d{9}$/.test(accountNumber)) {
      return res.status(400).json({
        success: false,
        message: 'Enter a valid 11-digit GCash number.',
      });
    }
    if (refundMethod === 'bank_transfer' &&
        (!bankName || accountNumber.length < 6 || accountNumber.length > 30)) {
      return res.status(400).json({
        success: false,
        message: 'Enter valid bank account details.',
      });
    }

    const transaction = await findTransactionForUser(user, transactionId);
    if (!transaction) {
      return res.status(404).json({
        success: false,
        message: 'Payment transaction not found.',
      });
    }

    const transactionStatus = String(
      transaction.status || transaction.state || '',
    ).trim().toLowerCase();
    const amount = toNonNegativeNumber(
      transaction.totalAmount ?? transaction.amount,
      0,
    );
    const paymentType = String(
      transaction.paymentType || transaction.paymentMode || '',
    ).trim();

    if (transactionStatus !== 'rejected') {
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

    const existingRefund = await findRefundForTransaction(user, transactionId);
    if (existingRefund) {
      return res.status(409).json({
        success: false,
        message: 'A refund has already been requested for this payment.',
        refundStatus: existingRefund.status || 'pending',
      });
    }

    const createdAt = new Date().toISOString();
    const refundRecord = {
      transactionId,
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
    });
  } catch (error) {
    return next(error);
  }
});

app.post(
  '/profile/photo',
  requireAuth,
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

      const user = await getUserFromAuth(req.auth);
      if (!user) {
        return res
          .status(404)
          .json({ success: false, message: 'User not found.' });
      }

      const uploadResult = await uploadProfilePhotoToCloudinary(req.file);
      const profileImageUrl =
        uploadResult?.secure_url || uploadResult?.url || '';
      const profileImagePublicId = uploadResult?.public_id || '';

      await updateUserProfile(user, {
        profileImageUrl,
        profileImagePublicId,
        profilePic: profileImageUrl,
      });

      const refreshed = (await getUserByEmail(user.email)) || {
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

app.put('/profile', requireAuth, async (req, res, next) => {
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

    if (isStudent) {
      const schoolEmail = normalizeEmail(parsed.schoolEmail || '');
      if (!emailRegex.test(schoolEmail)) {
        return res.status(400).json({
          success: false,
          message: 'School email is required for student accounts.',
        });
      }

      if (!parsed.studentId) {
        return res.status(400).json({
          success: false,
          message: 'Student ID is required for student accounts.',
        });
      }

      if (schoolEmail !== user.email) {
        const existing = await getUserByEmail(schoolEmail);
        if (
          existing &&
          String(existing._id || existing.id || '') !==
            String(user._id || user.id || '')
        ) {
          return res
            .status(409)
            .json({ success: false, message: 'Email already exists.' });
        }
      }

      const updates = {
        firstName: parsed.firstName,
        lastName: parsed.lastName,
        schoolEmail,
        personalEmail: '',
        email: schoolEmail,
        studentId: parsed.studentId,
        yearLevel: parsed.yearLevel,
        program: parsed.program,
      };

      await updateUserProfile(user, updates);
    } else {
      const nextPersonalEmail =
        parsed.personalEmail || user.personalEmail || user.email;
      const nextEmail = normalizeEmail(nextPersonalEmail);
      if (!emailRegex.test(nextEmail)) {
        return res
          .status(400)
          .json({ success: false, message: 'Invalid login email address.' });
      }

      if (nextEmail !== user.email) {
        const existing = await getUserByEmail(nextEmail);
        if (
          existing &&
          String(existing._id || existing.id || '') !==
            String(user._id || user.id || '')
        ) {
          return res
            .status(409)
            .json({ success: false, message: 'Email already exists.' });
        }
      }

      const updates = {
        firstName: parsed.firstName,
        lastName: parsed.lastName,
        schoolEmail: '',
        personalEmail: nextPersonalEmail,
        email: nextEmail,
        studentId: '',
        yearLevel: parsed.yearLevel,
        program: parsed.program,
      };

      await updateUserProfile(user, updates);
    }

    if (parsed.newPassword) {
      const passwordHash = await bcrypt.hash(parsed.newPassword, 12);
      await updateUserPassword(user.email, passwordHash);
    }

    const refreshed = await getUserByEmail(user.email);
    return res.json({
      success: true,
      message: 'Profile updated.',
      user: buildProfileResponse(refreshed || { ...user, ...updates }),
    });
  } catch (error) {
    return next(error);
  }
});

app.post('/auth/register', async (req, res, next) => {
  try {
    const parsed = validateRegisterPayload(req.body || {});
    if (parsed.error) {
      return res.status(400).json({ success: false, message: parsed.error });
    }

    const role = parsed.role;

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

    const passwordHash = await bcrypt.hash(parsed.password, 12);

    const result = await createUserDocument({
      firstName: parsed.firstName,
      lastName: parsed.lastName,
      email: parsed.email,
      personalEmail: parsed.personalEmail,
      passwordHash,
      role,
      schoolEmail: parsed.schoolEmail,
      studentId: parsed.studentId,
      yearLevel: parsed.yearLevel,
      course: parsed.program,
      program: parsed.program, // kept for backward compatibility with mobile code
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

app.post('/auth/register/request-otp', async (req, res, next) => {
  try {
    cleanupOtpData();

    const parsed = validateRegisterPayload(req.body || {});
    if (parsed.error) {
      return res.status(400).json({ success: false, message: parsed.error });
    }

    const role = parsed.role;

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

    const otp = putOtp(registrationOtpStore, parsed.email, {
      payload: {
        ...parsed,
        role,
      },
    });
    return await sendOtpResponse(res, {
      email: parsed.email,
      otp,
      purpose: 'registration',
    });
  } catch (error) {
    return next(error);
  }
});

app.post('/auth/register/verify-otp', async (req, res, next) => {
  try {
    cleanupOtpData();

    const email = normalizeEmail(req.body?.email);
    const otp = String(req.body?.otp || '').trim();

    if (!emailRegex.test(email) || !/^\d{6}$/.test(otp)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid email or OTP format.',
      });
    }

    const record = registrationOtpStore.get(email);
    if (!record || record.expiresAt <= Date.now()) {
      registrationOtpStore.delete(email);
      return res.status(400).json({
        success: false,
        message: 'OTP expired or not found. Please request a new one.',
      });
    }

    if (record.otp !== otp) {
      record.attempts += 1;
      registrationOtpStore.set(email, record);

      if (record.attempts >= 5) {
        registrationOtpStore.delete(email);
      }

      return res.status(401).json({ success: false, message: 'Invalid OTP.' });
    }

    const payload = record.payload;
    registrationOtpStore.delete(email);

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

    const passwordHash = await bcrypt.hash(payload.password, 12);
    const result = await createUserDocument({
      firstName: payload.firstName,
      lastName: payload.lastName,
      email: normalizeEmail(payload.email),
      personalEmail: normalizeEmail(payload.personalEmail || ''),
      passwordHash,
      role,
      schoolEmail: normalizeEmail(payload.schoolEmail || ''),
      studentId: payload.studentId || '',
      yearLevel: payload.yearLevel,
      course: payload.program,
      program: payload.program, // kept for backward compatibility with mobile code
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

app.post('/auth/login', async (req, res, next) => {
  try {
    const email = normalizeEmail(req.body?.email);
    const password = String(req.body?.password || '').trim();

    if (!emailRegex.test(email) || !password) {
      return res
        .status(400)
        .json({ success: false, message: 'Invalid email or password format.' });
    }

    const user = await getUserByEmail(email);
    if (!user) {
      return res
        .status(401)
        .json({ success: false, message: 'Invalid email or password.' });
    }

    const passwordHash = await ensurePasswordHash(user);
    if (!passwordHash) {
      return res
        .status(401)
        .json({ success: false, message: 'Invalid email or password.' });
    }

    const isMatch = await bcrypt.compare(password, passwordHash);
    if (!isMatch) {
      return res
        .status(401)
        .json({ success: false, message: 'Invalid email or password.' });
    }

    const session = await issueTokensForUser(user);
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

    if (!emailRegex.test(email) || !refreshToken) {
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
    if (!record || isRefreshTokenExpired(record)) {
      await revokeRefreshToken(email, tokenHash);
      return res
        .status(401)
        .json({ success: false, message: 'Refresh token expired.' });
    }

    await revokeRefreshToken(email, tokenHash);
    const session = await issueTokensForUser(user);

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

    if (!emailRegex.test(email) || !refreshToken) {
      return res.status(400).json({
        success: false,
        message: 'Invalid email or refresh token.',
      });
    }

    const tokenHash = hashRefreshToken(refreshToken);
    await revokeRefreshToken(email, tokenHash);

    return res.json({ success: true, message: 'Logged out.' });
  } catch (error) {
    return next(error);
  }
});

app.post('/auth/forgot-password/request-otp', async (req, res, next) => {
  try {
    cleanupOtpData();

    const email = normalizeEmail(req.body?.email);
    if (!emailRegex.test(email)) {
      return res.status(400).json({ success: false, message: 'Invalid email.' });
    }

    const user = await getUserByEmail(email);
    if (!user) {
      return res.json({
        success: true,
        message:
          'If an account exists for this email, a verification code has been sent.',
        expiresInSeconds: Number(OTP_TTL_MINUTES) * 60,
        resendAfterSeconds: 30,
      });
    }

    const pendingOtp = otpStore.get(email);
    const lastSentAt = Number(pendingOtp?.lastSentAt || 0);
    const elapsedSinceSend = Date.now() - lastSentAt;
    if (lastSentAt && elapsedSinceSend < 30 * 1000) {
      return res.json({
        success: true,
        message: 'A verification code was recently sent.',
        expiresInSeconds: Math.max(
          0,
          Math.ceil((pendingOtp.expiresAt - Date.now()) / 1000),
        ),
        resendAfterSeconds: Math.ceil((30 * 1000 - elapsedSinceSend) / 1000),
      });
    }

    const otp = putOtp(otpStore, email, { lastSentAt: Date.now() });

    const response = await sendOtpResponse(res, {
      email,
      otp,
      purpose: 'password-reset',
    });
    return response;
  } catch (error) {
    return next(error);
  }
});

app.post('/auth/forgot-password/verify-otp', async (req, res, next) => {
  try {
    cleanupOtpData();

    const email = normalizeEmail(req.body?.email);
    const otp = String(req.body?.otp || '').trim();

    if (!emailRegex.test(email) || !/^\d{6}$/.test(otp)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid email or OTP format.',
      });
    }

    const record = otpStore.get(email);
    if (!record || record.expiresAt <= Date.now()) {
      otpStore.delete(email);
      return res.status(400).json({
        success: false,
        message: 'OTP expired or not found. Please request a new one.',
      });
    }

    if (record.otp !== otp) {
      record.attempts += 1;
      otpStore.set(email, record);

      if (record.attempts >= 5) {
        otpStore.delete(email);
      }

      return res.status(401).json({ success: false, message: 'Invalid OTP.' });
    }

    otpStore.delete(email);
    const resetToken = makeResetToken();
    resetTokenStore.set(resetToken, {
      email,
      expiresAt: Date.now() + Number(OTP_TTL_MINUTES) * 60 * 1000,
    });

    return res.json({
      success: true,
      message: 'OTP verified.',
      resetToken,
    });
  } catch (error) {
    return next(error);
  }
});

app.post('/auth/forgot-password/reset', async (req, res, next) => {
  try {
    cleanupOtpData();

    const resetToken = String(req.body?.resetToken || '').trim();
    const newPassword = String(req.body?.newPassword || '');

    if (!resetToken) {
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

    const tokenRecord = resetTokenStore.get(resetToken);
    if (!tokenRecord || tokenRecord.expiresAt <= Date.now()) {
      resetTokenStore.delete(resetToken);
      return res.status(401).json({
        success: false,
        message: 'Reset token is invalid or expired.',
      });
    }

    const passwordHash = await bcrypt.hash(newPassword, 12);
    await updateUserPassword(tokenRecord.email, passwordHash);
    await revokeAllRefreshTokens(tokenRecord.email);

    resetTokenStore.delete(resetToken);

    return res.json({
      success: true,
      message: 'Password reset successful.',
    });
  } catch (error) {
    return next(error);
  }
});

app.use((err, _req, res, _next) => {
  if (err instanceof multer.MulterError) {
    return res.status(400).json({
      success: false,
      message: err.code === 'LIMIT_FILE_SIZE'
        ? 'Receipt image is too large.'
        : err.message,
    });
  }
  console.error(err);
  res.status(500).json({ 
    success: false, 
    message: err.message || 'Internal server error.',
    stack: err.stack 
  });
});
async function start() {
  if (dbEnabled) {
    try {
      await client.connect();
      const db = client.db(MONGODB_DB_NAME);
      alumniUsers = db.collection(alumniCollectionName);
      studentUsers = db.collection(studentsCollectionName);
      receipts = db.collection('transactions');
      requests = db.collection('requests');
      notifications = db.collection('notifications');
      transactions = db.collection('transactions');
      refunds = db.collection('refunds');
      try {
        for (const collection of [alumniUsers, studentUsers]) {
          try {
            await collection.dropIndex('username_1');
          } catch (err) {
            // Index doesn't exist, that's fine
          }
          await collection.createIndex({ email: 1 }, { unique: true });
          await collection.createIndex(
            { username: 1 },
            { unique: true, sparse: true },
          );
        }
        await receipts.createIndex({ userId: 1, createdAt: -1 });
        await requests.createIndex({ userId: 1, createdAt: -1 });
        await requests.createIndex({ status: 1, createdAt: -1 });
        await notifications.createIndex({ userId: 1, createdAt: -1 });
        await notifications.createIndex({ email: 1, createdAt: -1 });
        await transactions.createIndex({ userId: 1, createdAt: -1 });
        await transactions.createIndex({ email: 1, createdAt: -1 });
        await refunds.createIndex(
          { transactionId: 1, userId: 1 },
          { unique: true },
        );
        await normalizeEmailsInCollection(studentUsers, 'students');
        await normalizeEmailsInCollection(alumniUsers, 'alumni');
      } catch (err) {
        console.warn('Could not create indexes (permission denied):', err.message);
      }
    } catch (error) {
      console.error(`MongoDB connection failed: ${error.message}`);
    }
  } else {
    console.warn('DISABLE_DB is true. Using in-memory users only.');
  }

  if (!process.env.VERCEL) {
    app.listen(Number(PORT), () => {
      console.log(`Auth API listening on port ${PORT}`);
    });
  }
}

setInterval(cleanupOtpData, 60 * 1000);

start().catch((error) => {
  console.error('Failed to start server:', error);
});

app.use((err, req, res, next) => {
  console.error("Unhandled Error:", err);
  res.status(500).json({
    success: false,
    message: err.message || 'Internal Server Error',
    stack: process.env.NODE_ENV === 'production' ? undefined : err.stack
  });
});

export default function handler(req, res) {
  return app(req, res);
}
