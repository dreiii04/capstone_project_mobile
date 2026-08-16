import { randomBytes } from 'crypto';
import dotenv from 'dotenv';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const configDirectory = path.dirname(fileURLToPath(import.meta.url));
export const backendRoot = path.resolve(configDirectory, '..', '..');

// This is the backend's only dotenv import and load. All other modules consume
// the normalized configuration object exported below.
dotenv.config({ path: path.join(backendRoot, '.env.local') });

function loadOrCreateLocalJwtSecret() {
  const secretPath = path.join(backendRoot, '.local-jwt-secret');
  try {
    const existing = fs.readFileSync(secretPath, 'utf8').trim();
    if (Buffer.byteLength(existing, 'utf8') >= 32) return existing;
  } catch (_error) {
    // Created below on the first local startup.
  }

  const generated = randomBytes(48).toString('base64url');
  try {
    fs.writeFileSync(secretPath, generated, {
      encoding: 'utf8',
      flag: 'wx',
      mode: 0o600,
    });
    return generated;
  } catch (_error) {
    try {
      const existing = fs.readFileSync(secretPath, 'utf8').trim();
      if (Buffer.byteLength(existing, 'utf8') >= 32) return existing;
    } catch (_readError) {
      console.warn(
        'Local JWT key could not be persisted; sessions will reset on restart.',
      );
    }
    return generated;
  }
}

function buildConfig(env) {
  const nodeEnv = env.NODE_ENV || 'development';
  const isProduction = nodeEnv === 'production';
  const databaseEnabled = env.DISABLE_DB !== 'true';
  const mongoUri = String(env.MONGODB_URI || '').trim();
  const mongoUriIsValid = /^mongodb(?:\+srv)?:\/\//i.test(mongoUri);
  const configuredJwtSecret = String(env.JWT_SECRET || '').trim();
  const jwtSecret = Buffer.byteLength(configuredJwtSecret, 'utf8') >= 32
    ? configuredJwtSecret
    : (!isProduction ? loadOrCreateLocalJwtSecret() : configuredJwtSecret);
  const allowedOrigins = String(env.ALLOWED_ORIGIN || '')
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean);
  const cloudinaryUrl = String(env.CLOUDINARY_URL || '').trim();
  const cloudinaryCloudName = String(env.CLOUDINARY_CLOUD_NAME || '').trim();
  const cloudinaryApiKey = String(env.CLOUDINARY_API_KEY || '').trim();
  const cloudinaryApiSecret = String(env.CLOUDINARY_API_SECRET || '').trim();
  const notificationsApiKey = String(
    env.NOTIFICATIONS_API_KEY || '',
  ).trim();
  const cloudinaryEnabled = Boolean(
    cloudinaryUrl ||
      (cloudinaryCloudName && cloudinaryApiKey && cloudinaryApiSecret),
  );
  const smtp = Object.freeze({
    host: String(env.SMTP_HOST || 'smtp-relay.brevo.com').trim(),
    port: String(env.SMTP_PORT || '587').trim(),
    secure: env.SMTP_SECURE === 'true',
    user: String(env.SMTP_USER || '').trim(),
    pass: String(env.SMTP_PASS || ''),
    from: String(env.SMTP_FROM || '').trim(),
  });
  const smtpEnabled = Boolean(
    smtp.host && smtp.port && smtp.user && smtp.pass && smtp.from,
  );
  const otpTtl = Number(env.OTP_TTL_MINUTES || '10');
  const accessTtl = Number(env.JWT_ACCESS_TTL_MINUTES || '15');
  const refreshTtl = Number(env.JWT_REFRESH_TTL_DAYS || '30');

  let startupError = null;
  if (databaseEnabled && !mongoUriIsValid) {
    startupError =
      'MONGODB_URI must be configured by the host or backend/.env.local.';
  }
  if (Buffer.byteLength(jwtSecret, 'utf8') < 32) {
    startupError ||= 'JWT_SECRET must contain at least 32 bytes.';
  }
  if (/change[_-]?me|replace|example/i.test(jwtSecret)) {
    startupError ||= 'JWT_SECRET must not use a placeholder value.';
  }
  if (isProduction &&
      (allowedOrigins.length === 0 || allowedOrigins.includes('*'))) {
    startupError ||= 'Production requires an explicit ALLOWED_ORIGIN allowlist.';
  }
  if (isProduction && allowedOrigins.some((origin) => {
    try {
      return new URL(origin).protocol !== 'https:';
    } catch (_error) {
      return true;
    }
  })) {
    startupError ||=
      'Production ALLOWED_ORIGIN entries must be valid HTTPS origins.';
  }
  if (isProduction && env.OTP_DEV_MODE === 'true') {
    startupError ||= 'OTP_DEV_MODE must be disabled in production.';
  }
  if (isProduction && !databaseEnabled) {
    startupError ||= 'DISABLE_DB cannot be enabled in production.';
  }
  if (isProduction && !String(env.MONGODB_DB_NAME || '').trim()) {
    startupError ||= 'Production requires an explicit MONGODB_DB_NAME.';
  }
  if (isProduction && !String(
    env.MONGODB_ALUMNI_COLLECTION || env.MONGODB_USERS_COLLECTION || '',
  ).trim()) {
    startupError ||=
      'Production requires an explicit alumni/users collection name.';
  }
  if (isProduction && !String(env.MONGODB_STUDENTS_COLLECTION || '').trim()) {
    startupError ||=
      'Production requires an explicit students collection name.';
  }
  if (isProduction &&
      (!String(env.JWT_ISSUER || '').trim() ||
        !String(env.JWT_AUDIENCE || '').trim())) {
    startupError ||= 'Production requires JWT_ISSUER and JWT_AUDIENCE.';
  }
  if (!Number.isFinite(otpTtl) || otpTtl < 5 || otpTtl > 30 ||
      !Number.isFinite(accessTtl) || accessTtl < 5 || accessTtl > 60 ||
      !Number.isFinite(refreshTtl) || refreshTtl < 1 || refreshTtl > 90) {
    startupError ||= 'Authentication TTL configuration is invalid.';
  }
  if (isProduction && !cloudinaryEnabled) {
    startupError ||= 'Production requires private media storage configuration.';
  }
  if (isProduction && !smtpEnabled) {
    startupError ||=
      'Production requires SMTP configuration for email verification.';
  }
  if (isProduction &&
      (Buffer.byteLength(notificationsApiKey, 'utf8') < 32 ||
        /change[_-]?me|replace|example/i.test(notificationsApiKey))) {
    startupError ||=
      'Production requires a non-placeholder notification API key of at least 32 bytes.';
  }

  const configuredTrustProxy = Number.parseInt(
    String(env.TRUST_PROXY_HOPS || (env.VERCEL ? '1' : '0')),
    10,
  );
  const configuredPort = Number.parseInt(String(env.PORT || '4000'), 10);

  return {
    nodeEnv,
    isProduction,
    port: Number.isInteger(configuredPort) && configuredPort > 0
      ? configuredPort
      : 4000,
    trustProxyHops:
      Number.isInteger(configuredTrustProxy) && configuredTrustProxy > 0
        ? configuredTrustProxy
        : 0,
    runDbMigrations: env.RUN_DB_MIGRATIONS === 'true',
    database: Object.freeze({
      enabled: databaseEnabled,
      uri: mongoUri,
      uriIsValid: mongoUriIsValid,
      name: String(env.MONGODB_DB_NAME || 'test'),
      alumniCollection: String(
        env.MONGODB_ALUMNI_COLLECTION ||
          env.MONGODB_USERS_COLLECTION ||
          'alumni',
      ),
      studentsCollection: String(
        env.MONGODB_STUDENTS_COLLECTION || 'students',
      ),
    }),
    allowedOrigins: Object.freeze(allowedOrigins),
    mailboxlayerAccessKey: String(env.MAILBOXLAYER_ACCESS_KEY || '').trim(),
    otp: Object.freeze({
      ttlMinutes: String(env.OTP_TTL_MINUTES || '10'),
      developmentMode: env.OTP_DEV_MODE === 'true',
    }),
    jwt: Object.freeze({
      secret: jwtSecret,
      accessTtlMinutes: String(env.JWT_ACCESS_TTL_MINUTES || '15'),
      refreshTtlDays: String(env.JWT_REFRESH_TTL_DAYS || '30'),
      issuer: String(env.JWT_ISSUER || 'verifitor').trim(),
      audience: String(env.JWT_AUDIENCE || 'verifitor-app').trim(),
    }),
    notificationsApiKey,
    smtp,
    smtpEnabled,
    cloudinary: Object.freeze({
      enabled: cloudinaryEnabled,
      url: cloudinaryUrl,
      cloudName: cloudinaryCloudName,
      apiKey: cloudinaryApiKey,
      apiSecret: cloudinaryApiSecret,
    }),
    paths: Object.freeze({
      uploads: path.join(backendRoot, 'uploads'),
      receipts: path.join(backendRoot, 'uploads', 'receipts'),
      profiles: path.join(backendRoot, 'uploads', 'profiles'),
    }),
    startupError,
  };
}

// The object identity stays stable for importing modules. Refreshing exists for
// isolated integration tests that intentionally reload the app with new env.
export const config = {
  get isVercel() {
    return Boolean(process.env.VERCEL);
  },
};

export function refreshConfig() {
  Object.assign(config, buildConfig(process.env));
  return config;
}

refreshConfig();

export default config;
