import assert from 'node:assert/strict';
import { readdir, unlink } from 'node:fs/promises';
import { createServer } from 'node:http';
import { after, before, describe, test } from 'node:test';

import jwt from 'jsonwebtoken';

import { memoryUsers } from '../components/models/memory-store.js';

const JWT_SECRET =
  'security-integration-test-secret-with-more-than-thirty-two-bytes';
const JWT_ISSUER = 'verifitor-security-tests';
const JWT_AUDIENCE = 'verifitor-security-test-client';
const NOTIFICATIONS_API_KEY =
  'security-integration-notification-key-more-than-thirty-two-bytes';

const testEnvironment = {
  NODE_ENV: 'development',
  VERCEL: '1',
  PORT: '0',
  DISABLE_DB: 'true',
  MONGODB_URI: '',
  MONGODB_DB_NAME: 'verifitor_security_test',
  ALLOWED_ORIGIN: 'http://localhost',
  MAILBOXLAYER_ACCESS_KEY: '',
  OTP_TTL_MINUTES: '10',
  OTP_DEV_MODE: 'true',
  JWT_SECRET,
  JWT_ACCESS_TTL_MINUTES: '15',
  JWT_REFRESH_TTL_DAYS: '30',
  JWT_ISSUER,
  JWT_AUDIENCE,
  TRUST_PROXY_HOPS: '1',
  RUN_DB_MIGRATIONS: 'false',
  SMTP_HOST: '',
  SMTP_PORT: '',
  SMTP_SECURE: 'false',
  SMTP_USER: '',
  SMTP_PASS: '',
  SMTP_FROM: '',
  NOTIFICATIONS_API_KEY,
  CLOUDINARY_URL: '',
  CLOUDINARY_CLOUD_NAME: '',
  CLOUDINARY_API_KEY: '',
  CLOUDINARY_API_SECRET: '',
};

const originalEnvironment = new Map(
  Object.keys(testEnvironment).map((key) => [key, process.env[key]]),
);

function applyEnvironment(values) {
  for (const [key, value] of Object.entries(values)) {
    if (value === undefined) {
      delete process.env[key];
    } else {
      process.env[key] = value;
    }
  }
}

function restoreEnvironment() {
  for (const [key, value] of originalEnvironment) {
    if (value === undefined) {
      delete process.env[key];
    } else {
      process.env[key] = value;
    }
  }
}

async function listen(app) {
  const server = createServer(app);
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  const address = server.address();
  assert(address && typeof address === 'object');
  return {
    baseUrl: `http://127.0.0.1:${address.port}`,
    server,
  };
}

async function close(server) {
  if (!server?.listening) return;
  await new Promise((resolve, reject) => {
    server.close((error) => (error ? reject(error) : resolve()));
  });
}

async function request(baseUrl, path, options = {}) {
  const headers = new Headers(options.headers || {});
  let body = options.body;
  if (options.json !== undefined) {
    headers.set('content-type', 'application/json');
    body = JSON.stringify(options.json);
  }

  const response = await fetch(`${baseUrl}${path}`, {
    method: options.method || (body === undefined ? 'GET' : 'POST'),
    headers,
    body,
  });
  const text = await response.text();
  let json = null;
  try {
    json = JSON.parse(text);
  } catch {
    // Tests that expect JSON report the raw response in their assertion output.
  }
  return { response, json, text };
}

function bearer(token) {
  return { authorization: `Bearer ${token}` };
}

const receiptFilesUrl = new URL('../uploads/receipts/', import.meta.url);
const validPng = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk' +
    '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  'base64',
);

function makeReceiptForm(requestId) {
  const form = new FormData();
  form.set('receipt', new Blob([validPng], { type: 'image/png' }), 'receipt.png');
  form.set('paymentType', 'gcash');
  form.set('requestId', requestId);
  return form;
}

async function listLocalReceiptFiles() {
  try {
    return new Set(await readdir(receiptFilesUrl));
  } catch (error) {
    if (error?.code === 'ENOENT') return new Set();
    throw error;
  }
}

async function withLocalReceiptStorage(callback) {
  const before = await listLocalReceiptFiles();
  const previousVercel = process.env.VERCEL;
  process.env.VERCEL = '';
  try {
    return await callback();
  } finally {
    if (previousVercel === undefined) {
      delete process.env.VERCEL;
    } else {
      process.env.VERCEL = previousVercel;
    }
    const afterFiles = await listLocalReceiptFiles();
    const createdFiles = [...afterFiles].filter(
      (fileName) => !before.has(fileName) && /^receipt-[a-f0-9]+\.[a-z0-9]+$/i.test(fileName),
    );
    await Promise.all(
      createdFiles.map((fileName) =>
        unlink(new URL(fileName, receiptFilesUrl)).catch(() => {})),
    );
  }
}

applyEnvironment(testEnvironment);
after(restoreEnvironment);

test('production configuration fails closed when the database is disabled', async () => {
  let productionApp;
  try {
    applyEnvironment({
      ...testEnvironment,
      NODE_ENV: 'production',
      OTP_DEV_MODE: 'false',
      ALLOWED_ORIGIN: 'https://app.example.test',
    });
    const moduleUrl = new URL('../app.js', import.meta.url);
    moduleUrl.searchParams.set('security-production', `${Date.now()}`);
    ({ app: productionApp } = await import(moduleUrl.href));
  } finally {
    applyEnvironment(testEnvironment);
  }

  const { baseUrl, server } = await listen(productionApp);
  try {
    const insecure = await request(baseUrl, '/health');
    assert.equal(insecure.response.status, 400, insecure.text);
    assert.deepEqual(insecure.json, {
      success: false,
      message: 'HTTPS is required.',
    });

    const { response, json, text } = await request(baseUrl, '/health', {
      headers: { 'x-forwarded-proto': 'https' },
    });
    assert.equal(response.status, 503, text);
    assert.match(
      String(response.headers.get('strict-transport-security') || ''),
      /max-age=63072000/i,
    );
    assert.deepEqual(json, {
      success: false,
      message: 'Service configuration is unavailable.',
    });
    assert.doesNotMatch(text, /DISABLE_DB|MONGODB|JWT_SECRET|stack/i);
  } finally {
    await close(server);
  }
});

test('notification delivery fails closed when its sender key is not configured', async () => {
  let unconfiguredApp;
  try {
    applyEnvironment({
      ...testEnvironment,
      NOTIFICATIONS_API_KEY: '',
    });
    const moduleUrl = new URL('../app.js', import.meta.url);
    moduleUrl.searchParams.set('notification-key-unconfigured', `${Date.now()}`);
    ({ app: unconfiguredApp } = await import(moduleUrl.href));
  } finally {
    applyEnvironment(testEnvironment);
  }

  const { baseUrl, server } = await listen(unconfiguredApp);
  try {
    const { response, json, text } = await request(baseUrl, '/notifications', {
      headers: { 'x-notification-key': 'attacker-controlled-key' },
      json: {
        email: 'nobody@example.test',
        title: 'Untrusted notification',
        message: 'This must not be created.',
      },
    });
    assert.equal(response.status, 503, text);
    assert.deepEqual(json, {
      success: false,
      message: 'Notification delivery is not configured.',
    });
  } finally {
    await close(server);
  }
});

describe('backend security integration', { concurrency: false }, () => {
  let baseUrl;
  let server;
  let accessToken;
  let refreshToken;
  let userId;
  let makeRefundId;

  const email = 'security.integration@example.test';
  const password = 'StrongSecurity1!';
  const registration = {
    studentStatus: 'alumni',
    educationalLevel: 'bachelors',
    firstName: 'Security',
    lastName: 'Tester',
    email,
    password,
    yearGraduated: '2024',
    program: 'Computer Science',
  };

  before(async () => {
    applyEnvironment(testEnvironment);
    const moduleUrl = new URL('../app.js', import.meta.url);
    moduleUrl.searchParams.set('security-development', `${Date.now()}`);
    const serverModule = await import(moduleUrl.href);
    const { app } = serverModule;
    makeRefundId = serverModule.makeRefundId;
    ({ baseUrl, server } = await listen(app));

    const otpResponse = await request(baseUrl, '/auth/register/request-otp', {
      json: registration,
    });
    assert.equal(otpResponse.response.status, 200, otpResponse.text);
    assert.match(String(otpResponse.json?.otp || ''), /^\d{6}$/);
    assert.match(
      String(otpResponse.json?.challengeToken || ''),
      /^[a-f0-9]{64}$/,
    );

    const verifyResponse = await request(baseUrl, '/auth/register/verify-otp', {
      json: {
        email,
        otp: otpResponse.json.otp,
        challengeToken: otpResponse.json.challengeToken,
      },
    });
    assert.equal(verifyResponse.response.status, 201, verifyResponse.text);
    userId = String(verifyResponse.json?.userId || '');
    assert.match(userId, /^[a-f0-9]{24}$/);

    const loginResponse = await request(baseUrl, '/auth/login', {
      json: { email, password },
    });
    assert.equal(loginResponse.response.status, 200, loginResponse.text);
    accessToken = loginResponse.json?.accessToken;
    refreshToken = loginResponse.json?.refreshToken;
    assert.equal(typeof accessToken, 'string');
    assert.match(String(refreshToken || ''), /^[a-f0-9]{96}$/);
  });

  after(async () => {
    await close(server);
  });

  test('development responses do not set HSTS', async () => {
    const health = await request(baseUrl, '/health');
    assert.equal(health.response.status, 200, health.text);
    assert.equal(health.response.headers.get('strict-transport-security'), null);
    assert.equal(
      health.response.headers.get('x-content-type-options'),
      'nosniff',
    );
    assert.match(
      String(health.response.headers.get('content-security-policy') || ''),
      /frame-ancestors 'self'/,
    );
    assert.equal(health.response.headers.get('referrer-policy'), 'no-referrer');
    assert.equal(health.response.headers.get('cache-control'), 'no-store');
  });

  test('inactive accounts cannot log in or receive tokens', async () => {
    const user = memoryUsers.get(email);
    assert.ok(user, 'Expected the registered test user to exist.');
    user.status = 'Inactive';

    try {
      const denied = await request(baseUrl, '/auth/login', {
        json: { email, password },
      });
      assert.equal(denied.response.status, 403, denied.text);
      assert.deepEqual(denied.json, {
        success: false,
        message:
          'This account has been deactivated. Contact the administrator.',
      });
      assert.equal(denied.json?.accessToken, undefined);
      assert.equal(denied.json?.refreshToken, undefined);

      const deniedRefresh = await request(baseUrl, '/auth/refresh', {
        json: { email, refreshToken },
      });
      assert.equal(deniedRefresh.response.status, 403, deniedRefresh.text);
      assert.equal(deniedRefresh.json?.accessToken, undefined);
      assert.equal(deniedRefresh.json?.refreshToken, undefined);

      const deniedProfile = await request(baseUrl, '/profile', {
        headers: bearer(accessToken),
      });
      assert.equal(deniedProfile.response.status, 404, deniedProfile.text);
    } finally {
      delete user.status;
    }
  });

  test('CORS does not reflect unapproved browser origins', async () => {
    const rejected = await request(baseUrl, '/health', {
      headers: { origin: 'https://attacker.example' },
    });
    assert.equal(rejected.response.status, 200, rejected.text);
    assert.equal(rejected.response.headers.get('access-control-allow-origin'), null);

    const allowed = await request(baseUrl, '/health', {
      headers: { origin: 'http://localhost' },
    });
    assert.equal(allowed.response.status, 200, allowed.text);
    assert.equal(
      allowed.response.headers.get('access-control-allow-origin'),
      'http://localhost',
    );
  });

  test('protected APIs reject requests without server-verified authentication', async () => {
    for (const path of [
      '/profile',
      '/receipts',
      '/requests',
      '/notifications',
      '/transactions',
      '/refunds',
    ]) {
      const denied = await request(baseUrl, path);
      assert.equal(denied.response.status, 401, `${path}: ${denied.text}`);
      assert.deepEqual(denied.json, {
        success: false,
        message: 'Missing access token.',
      });
    }
  });

  test('direct registration is disabled in favor of verified registration', async () => {
    const { response, json, text } = await request(baseUrl, '/auth/register', {
      json: registration,
    });
    assert.equal(response.status, 410, text);
    assert.deepEqual(json, {
      success: false,
      message: 'Email verification is required before registration.',
    });
  });

  test('academic registration validates and stores only applicable fields', async () => {
    const formerEmail = 'former.jhs@example.test';
    const formerRegistration = {
      studentStatus: 'former_student',
      educationalLevel: 'jhs',
      firstName: 'Former',
      lastName: 'Learner',
      email: formerEmail,
      password,
      lastYearAttended: '2023',
    };

    const missingGrade = await request(
      baseUrl,
      '/auth/register/request-otp',
      { json: formerRegistration },
    );
    assert.equal(missingGrade.response.status, 400, missingGrade.text);
    assert.equal(
      missingGrade.json?.message,
      'Select a valid last completed grade level.',
    );

    const otpResponse = await request(baseUrl, '/auth/register/request-otp', {
      json: {
        ...formerRegistration,
        lastGradeLevelCompleted: 'Grade 10',
      },
    });
    assert.equal(otpResponse.response.status, 200, otpResponse.text);

    const verifyResponse = await request(baseUrl, '/auth/register/verify-otp', {
      json: {
        email: formerEmail,
        otp: otpResponse.json.otp,
        challengeToken: otpResponse.json.challengeToken,
      },
    });
    assert.equal(verifyResponse.response.status, 201, verifyResponse.text);

    const loginResponse = await request(baseUrl, '/auth/login', {
      json: { email: formerEmail, password },
    });
    assert.equal(loginResponse.response.status, 200, loginResponse.text);

    const profileResponse = await request(baseUrl, '/profile', {
      headers: bearer(loginResponse.json.accessToken),
    });
    assert.equal(profileResponse.response.status, 200, profileResponse.text);
    assert.equal(profileResponse.json?.user?.studentStatus, 'former_student');
    assert.equal(profileResponse.json?.user?.educationalLevel, 'jhs');
    assert.equal(profileResponse.json?.user?.lastYearAttended, '2023');
    assert.equal(
      profileResponse.json?.user?.lastGradeLevelCompleted,
      'Grade 10',
    );
    assert.equal(profileResponse.json?.user?.yearGraduated, '');
    assert.equal(profileResponse.json?.user?.program, '');
  });

  test('registration OTPs require a challenge token and lock after five failures', async () => {
    const challengedEmail = 'challenge.lockout@example.test';
    const otpResponse = await request(baseUrl, '/auth/register/request-otp', {
      json: {
        studentStatus: 'alumni',
        educationalLevel: 'shs',
        firstName: 'Challenge',
        lastName: 'Tester',
        email: challengedEmail,
        password,
        yearGraduated: '2024',
      },
    });
    assert.equal(otpResponse.response.status, 200, otpResponse.text);
    assert.match(
      String(otpResponse.json?.challengeToken || ''),
      /^[a-f0-9]{64}$/,
    );

    const missingChallenge = await request(
      baseUrl,
      '/auth/register/verify-otp',
      {
        json: { email: challengedEmail, otp: otpResponse.json.otp },
      },
    );
    assert.equal(missingChallenge.response.status, 400, missingChallenge.text);

    const wrongOtp = otpResponse.json.otp === '000000' ? '111111' : '000000';
    for (let attempt = 0; attempt < 5; attempt += 1) {
      const denied = await request(baseUrl, '/auth/register/verify-otp', {
        json: {
          email: challengedEmail,
          otp: wrongOtp,
          challengeToken: otpResponse.json.challengeToken,
        },
      });
      assert.equal(denied.response.status, 401, denied.text);
    }

    const locked = await request(baseUrl, '/auth/register/verify-otp', {
      json: {
        email: challengedEmail,
        otp: otpResponse.json.otp,
        challengeToken: otpResponse.json.challengeToken,
      },
    });
    assert.equal(locked.response.status, 400, locked.text);
    assert.doesNotMatch(locked.text, /userId|Account created/i);
  });

  test('refund IDs are always unique non-null values', () => {
    assert.equal(typeof makeRefundId, 'function');
    const ids = Array.from({ length: 100 }, () => makeRefundId());
    assert.equal(new Set(ids).size, ids.length);
    for (const refundId of ids) {
      assert.match(refundId, /^[a-f0-9]{24}$/);
    }
  });

  test('notification creation rejects an invalid sender key', async () => {
    const { response, json, text } = await request(baseUrl, '/notifications', {
      headers: { 'x-notification-key': 'attacker-controlled-key' },
      json: {
        email,
        title: 'Untrusted notification',
        message: 'This must not be created.',
      },
    });
    assert.equal(response.status, 401, text);
    assert.deepEqual(json, {
      success: false,
      message: 'Invalid notification credentials.',
    });
  });

  test('unknown routes and parser failures return generic responses without stacks', async () => {
    const missing = await request(baseUrl, '/not-a-real-security-route');
    assert.equal(missing.response.status, 404, missing.text);
    assert.deepEqual(missing.json, {
      success: false,
      message: 'Route not found.',
    });
    assert.equal(missing.response.headers.get('x-powered-by'), null);

    const originalConsoleError = console.error;
    let malformed;
    try {
      console.error = () => {};
      malformed = await request(baseUrl, '/auth/login', {
        body: '{"email":',
        headers: { 'content-type': 'application/json' },
      });
    } finally {
      console.error = originalConsoleError;
    }
    assert.equal(malformed.response.status, 400, malformed.text);
    assert.deepEqual(malformed.json, {
      success: false,
      message: 'Invalid JSON payload.',
    });
    assert.doesNotMatch(
      malformed.text,
      /SyntaxError|server\.js|node_modules|\bat\s+\S+\s+\(/i,
    );
  });

  test('access tokens use the configured algorithm, audience, issuer, and subject', async () => {
    const decoded = jwt.decode(accessToken, { complete: true });
    assert(decoded && typeof decoded === 'object');
    assert.equal(decoded.header.alg, 'HS256');
    assert.equal(decoded.payload.aud, JWT_AUDIENCE);
    assert.equal(decoded.payload.iss, JWT_ISSUER);
    assert.equal(decoded.payload.sub, userId);
    assert.equal(decoded.payload.sv, 0);

    const profile = await request(baseUrl, '/profile', {
      headers: bearer(accessToken),
    });
    assert.equal(profile.response.status, 200, profile.text);
    assert.equal(profile.json?.user?.id, userId);
  });

  test('access-token verification rejects wrong algorithms, audiences, and missing subjects', async () => {
    const commonPayload = { sub: userId, email, role: 'alumni' };
    const invalidTokens = [
      jwt.sign(commonPayload, JWT_SECRET, {
        algorithm: 'HS384',
        issuer: JWT_ISSUER,
        audience: JWT_AUDIENCE,
        expiresIn: '5m',
      }),
      jwt.sign(commonPayload, JWT_SECRET, {
        algorithm: 'HS256',
        issuer: JWT_ISSUER,
        audience: 'attacker-audience',
        expiresIn: '5m',
      }),
      jwt.sign({ email, role: 'alumni' }, JWT_SECRET, {
        algorithm: 'HS256',
        issuer: JWT_ISSUER,
        audience: JWT_AUDIENCE,
        expiresIn: '5m',
      }),
    ];

    for (const token of invalidTokens) {
      const denied = await request(baseUrl, '/profile', {
        headers: bearer(token),
      });
      assert.equal(denied.response.status, 401, denied.text);
      assert.deepEqual(denied.json, {
        success: false,
        message: 'Invalid or expired token.',
      });
    }
  });

  test('authenticated profile updates do not require an unrelated image upload', async () => {
    const updated = await request(baseUrl, '/profile', {
      method: 'PUT',
      headers: bearer(accessToken),
      json: {
        firstName: 'Security',
        lastName: 'Tester',
        schoolEmail: '',
        personalEmail: email,
        studentId: '',
        yearLevel: '2024',
        program: 'Computer Science',
        role: 'student',
        isAdmin: true,
        permissions: ['*'],
        verified: true,
        passwordHash: '$2b$12$attacker-controlled-value',
      },
    });
    assert.equal(updated.response.status, 200, updated.text);
    assert.equal(updated.json?.user?.id, userId);
    assert.equal(updated.json?.user?.personalEmail, email);
    assert.equal(updated.json?.user?.role, 'alumni');
    assert.equal(updated.json?.user?.isAdmin, undefined);
    assert.equal(updated.json?.user?.permissions, undefined);
    assert.equal(updated.json?.user?.passwordHash, undefined);
  });

  test('receipt image validation rejects spoofed image bytes without throwing', async () => {
    const form = new FormData();
    form.set(
      'receipt',
      new Blob(['this is not an image'], { type: 'image/png' }),
      'receipt.png',
    );
    form.set('paymentType', 'gcash');
    form.set('requestId', 'irrelevant-for-invalid-image');

    const rejected = await request(baseUrl, '/payments/receipt', {
      headers: bearer(accessToken),
      body: form,
    });
    assert.equal(rejected.response.status, 400, rejected.text);
    assert.deepEqual(rejected.json, {
      success: false,
      message: 'The uploaded file is not a valid supported image.',
    });
  });

  test('malformed multipart uploads return a generic 400 response', async () => {
    const boundary = 'security-test-truncated-boundary';
    const truncatedBody = [
      `--${boundary}`,
      'Content-Disposition: form-data; name="receipt"; filename="receipt.png"',
      'Content-Type: image/png',
      '',
      'truncated-image-content',
    ].join('\r\n');

    const malformed = await request(baseUrl, '/payments/receipt', {
      headers: {
        ...bearer(accessToken),
        'content-type': `multipart/form-data; boundary=${boundary}`,
      },
      body: truncatedBody,
    });
    assert.equal(malformed.response.status, 400, malformed.text);
    assert.deepEqual(malformed.json, {
      success: false,
      message: 'Invalid multipart upload.',
    });
    assert.doesNotMatch(malformed.text, /Unexpected end|Multer|Busboy|stack/i);
  });

  test('document request pricing is server-controlled', async () => {
    const created = await request(baseUrl, '/requests', {
      headers: bearer(accessToken),
      json: {
        docName: 'Transcript of Records (TOR)',
        purpose: 'Security integration test',
        documentPrice: 0.01,
        processingFee: -999,
        totalAmount: 0.01,
        status: 'Completed',
        role: 'admin',
        userId: '000000000000000000000000',
      },
    });
    assert.equal(created.response.status, 201, created.text);
    assert.equal(created.json?.request?.documentPrice, 600);
    assert.equal(created.json?.request?.processingFee, 0);
    assert.equal(created.json?.request?.totalAmount, 600);
    assert.equal(created.json?.request?.status, 'pending_payment');
    for (const privateField of [
      'email',
      'userId',
      'role',
      'schoolEmail',
      'studentId',
      'yearLevel',
      'program',
    ]) {
      assert.equal(created.json?.request?.[privateField], undefined);
    }

    const notificationResponse = await request(baseUrl, '/notifications', {
      headers: bearer(accessToken),
    });
    assert.equal(
      notificationResponse.response.status,
      200,
      notificationResponse.text,
    );
    const submittedNotification = notificationResponse.json?.notifications
      ?.find((item) => item.title === 'Request submitted');
    assert(submittedNotification, notificationResponse.text);
    assert.equal(submittedNotification.email, undefined);
    assert.equal(submittedNotification.userId, undefined);
    assert.match(
      submittedNotification.message,
      /Status: pending for payment\. Follow updates in Tracking\./,
    );
  });

  test('record IDs cannot be used to access another user\'s request', async () => {
    const otherEmail = 'other.owner@example.test';
    const otherRegistration = await request(
      baseUrl,
      '/auth/register/request-otp',
      {
        json: {
          studentStatus: 'alumni',
          educationalLevel: 'bachelors',
          firstName: 'Other',
          lastName: 'Owner',
          email: otherEmail,
          password,
          yearGraduated: '2024',
          program: 'Computer Science',
        },
      },
    );
    assert.equal(
      otherRegistration.response.status,
      200,
      otherRegistration.text,
    );
    const otherVerification = await request(
      baseUrl,
      '/auth/register/verify-otp',
      {
        json: {
          email: otherEmail,
          otp: otherRegistration.json.otp,
          challengeToken: otherRegistration.json.challengeToken,
        },
      },
    );
    assert.equal(otherVerification.response.status, 201, otherVerification.text);

    const otherLogin = await request(baseUrl, '/auth/login', {
      json: { email: otherEmail, password },
    });
    assert.equal(otherLogin.response.status, 200, otherLogin.text);

    const otherRequest = await request(baseUrl, '/requests', {
      headers: bearer(otherLogin.json.accessToken),
      json: {
        docName: 'Certificate of Enrollment',
        purpose: 'Ownership isolation test',
      },
    });
    assert.equal(otherRequest.response.status, 201, otherRequest.text);
    const otherRequestId = otherRequest.json?.request?.requestId;

    const deniedReceipt = await request(baseUrl, '/payments/receipt', {
      headers: bearer(accessToken),
      body: makeReceiptForm(otherRequestId),
    });
    assert.equal(deniedReceipt.response.status, 404, deniedReceipt.text);
    assert.deepEqual(deniedReceipt.json, {
      success: false,
      message: 'Document request not found.',
    });

    const ownRequests = await request(baseUrl, '/requests', {
      headers: bearer(accessToken),
    });
    assert.equal(ownRequests.response.status, 200, ownRequests.text);
    assert.equal(
      ownRequests.json?.requests?.some(
        (candidate) => candidate.requestId === otherRequestId,
      ),
      false,
    );
  });

  test('a document request accepts only one payment receipt', async () => {
    const docName = 'Certificate of Enrollment';
    const purpose = 'Duplicate receipt integrity test';
    const created = await request(baseUrl, '/requests', {
      headers: bearer(accessToken),
      json: { docName, purpose },
    });
    assert.equal(created.response.status, 201, created.text);
    const requestId = created.json?.request?.requestId;
    assert.match(String(requestId || ''), /^req_/);

    const first = await withLocalReceiptStorage(() => request(
      baseUrl,
      '/payments/receipt',
      {
        headers: bearer(accessToken),
        body: makeReceiptForm(requestId),
      },
    ));
    assert.equal(first.response.status, 201, first.text);
    assert.match(String(first.json?.receiptId || ''), /^[a-f0-9]{24}$/);

    const duplicate = await request(baseUrl, '/payments/receipt', {
      headers: bearer(accessToken),
      body: makeReceiptForm(requestId),
    });
    assert.equal(duplicate.response.status, 409, duplicate.text);
    assert.deepEqual(duplicate.json, {
      success: false,
      message: 'Payment has already been submitted for this request.',
    });

    const receipt = await request(
      baseUrl,
      `/receipts?${new URLSearchParams({ docName, purpose })}`,
      { headers: bearer(accessToken) },
    );
    assert.equal(receipt.response.status, 200, receipt.text);
    assert.equal(receipt.json?.receipt?.id, first.json.receiptId);

    const requests = await request(baseUrl, '/requests', {
      headers: bearer(accessToken),
    });
    assert.equal(requests.response.status, 200, requests.text);
    const stored = requests.json?.requests?.find(
      (candidate) => candidate.requestId === requestId,
    );
    assert(stored, requests.text);
    assert.equal(stored.status, 'pending');
    assert.equal(stored.paymentType, 'gcash');
  });

  test('terminal requests reject receipts without resetting their status', async () => {
    for (const terminalStatus of ['Rejected', 'Completed']) {
      let capturedRecord;
      const originalPush = Array.prototype.push;
      Array.prototype.push = function captureMemoryRequest(...items) {
        for (const item of items) {
          if (item && typeof item === 'object' &&
              item.mobileStatus === 'pending_payment' &&
              String(item.requestId || '').startsWith('req_')) {
            capturedRecord = item;
          }
        }
        return Reflect.apply(originalPush, this, items);
      };

      let created;
      try {
        created = await request(baseUrl, '/requests', {
          headers: bearer(accessToken),
          json: {
            docName: 'Certificate of Grades',
            purpose: `${terminalStatus} payment integrity test`,
          },
        });
      } finally {
        Array.prototype.push = originalPush;
      }
      assert.equal(created.response.status, 201, created.text);
      assert(capturedRecord, 'Expected to capture the DISABLE_DB request record.');

      const requestId = created.json?.request?.requestId;
      assert.equal(capturedRecord.requestId, requestId);
      capturedRecord.status = terminalStatus;
      capturedRecord.mobileStatus = 'pending_payment';

      const rejected = await request(baseUrl, '/payments/receipt', {
        headers: bearer(accessToken),
        body: makeReceiptForm(requestId),
      });
      assert.equal(rejected.response.status, 409, rejected.text);
      assert.deepEqual(rejected.json, {
        success: false,
        message: 'Payment has already been submitted for this request.',
      });
      assert.equal(capturedRecord.status, terminalStatus);
      assert.equal(capturedRecord.mobileStatus, 'pending_payment');
      assert.equal(capturedRecord.paymentReceiptId, undefined);

      const requests = await request(baseUrl, '/requests', {
        headers: bearer(accessToken),
      });
      assert.equal(requests.response.status, 200, requests.text);
      const stored = requests.json?.requests?.find(
        (candidate) => candidate.requestId === requestId,
      );
      assert(stored, requests.text);
      assert.equal(stored.status, terminalStatus);
      assert.equal(stored.paymentType, '');
    }
  });

  test('a directly rejected refund creates one user notification', async () => {
    const created = await request(baseUrl, '/requests', {
      headers: bearer(accessToken),
      json: {
        docName: 'Certificate of Graduation',
        purpose: 'Refund rejection notification test',
      },
    });
    assert.equal(created.response.status, 201, created.text);
    const requestId = created.json?.request?.requestId;

    let transactionRecord;
    const originalPush = Array.prototype.push;
    Array.prototype.push = function captureTransaction(...items) {
      for (const item of items) {
        if (item && typeof item === 'object' &&
            item.requestId === requestId && item.paymentSubmissionId) {
          transactionRecord = item;
        }
      }
      return Reflect.apply(originalPush, this, items);
    };

    let receipt;
    try {
      receipt = await withLocalReceiptStorage(() => request(
        baseUrl,
        '/payments/receipt',
        {
          headers: bearer(accessToken),
          body: makeReceiptForm(requestId),
        },
      ));
    } finally {
      Array.prototype.push = originalPush;
    }
    assert.equal(receipt.response.status, 201, receipt.text);
    assert(transactionRecord, 'Expected to capture the in-memory transaction.');

    transactionRecord.status = 'Rejected';
    transactionRecord.mobileStatus = 'rejected';
    transactionRecord.remarks = 'The paid document request was rejected.';

    let refundRecord;
    Array.prototype.push = function captureRefund(...items) {
      for (const item of items) {
        if (item && typeof item === 'object' &&
            item.transactionId === receipt.json?.receiptId &&
            item.refundMethod === 'gcash') {
          refundRecord = item;
        }
      }
      return Reflect.apply(originalPush, this, items);
    };

    let submitted;
    try {
      submitted = await request(baseUrl, '/refunds', {
        headers: bearer(accessToken),
        json: {
          transactionId: receipt.json?.receiptId,
          refundMethod: 'gcash',
          accountName: 'Security Tester',
          accountNumber: '09171234567',
          reason: 'The document request was rejected.',
        },
      });
    } finally {
      Array.prototype.push = originalPush;
    }
    assert.equal(submitted.response.status, 201, submitted.text);
    assert(refundRecord, 'Expected to capture the in-memory refund.');
    assert.match(String(refundRecord.refundId || ''), /^[a-f0-9]{24}$/);
    assert.equal(submitted.json?.refundId, refundRecord.refundId);

    const duplicate = await request(baseUrl, '/refunds', {
      headers: bearer(accessToken),
      json: {
        transactionId: receipt.json?.receiptId,
        refundMethod: 'gcash',
        accountName: 'Security Tester',
        accountNumber: '09171234567',
        reason: 'The document request was rejected.',
      },
    });
    assert.equal(duplicate.response.status, 409, duplicate.text);
    assert.equal(duplicate.json?.alreadyRequested, true);
    assert.equal(duplicate.json?.refundStatus, 'pending');

    const approved = await request(
      baseUrl,
      `/refunds/${submitted.json?.refundId}/status`,
      {
        method: 'PATCH',
        headers: { 'x-notification-key': NOTIFICATIONS_API_KEY },
        json: { status: 'approved' },
      },
    );
    assert.equal(approved.response.status, 200, approved.text);
    assert.equal(approved.json?.refund?.status, 'approved');
    assert.equal(approved.json?.notificationCreated, true);
    const repeatedApproval = await request(
      baseUrl,
      `/refunds/${submitted.json?.refundId}/status`,
      {
        method: 'PATCH',
        headers: { 'x-notification-key': NOTIFICATIONS_API_KEY },
        json: { status: 'approved' },
      },
    );
    assert.equal(repeatedApproval.response.status, 200, repeatedApproval.text);
    assert.equal(repeatedApproval.json?.notificationCreated, false);
    const transactionsAfterApproval = await request(baseUrl, '/transactions', {
      headers: bearer(accessToken),
    });
    assert.equal(
      transactionsAfterApproval.json?.transactions?.find(
        (item) => item.id === receipt.json?.receiptId,
      )?.refundStatus,
      'approved',
      transactionsAfterApproval.text,
    );

    // Simulate the legacy admin application updating MongoDB directly.
    refundRecord.status = 'refund_rejected';
    refundRecord.statusRemarks = 'The destination account could not be verified.';
    refundRecord.updatedAt = new Date().toISOString();

    const firstFeed = await request(baseUrl, '/notifications', {
      headers: bearer(accessToken),
    });
    assert.equal(firstFeed.response.status, 200, firstFeed.text);
    const rejectionNotifications = firstFeed.json?.notifications?.filter(
      (item) => item.title === 'Refund request rejected',
    );
    assert.equal(rejectionNotifications?.length, 1, firstFeed.text);
    assert.match(
      rejectionNotifications[0].message,
      /Reason: The destination account could not be verified\./,
    );

    const secondFeed = await request(baseUrl, '/notifications', {
      headers: bearer(accessToken),
    });
    assert.equal(secondFeed.response.status, 200, secondFeed.text);
    assert.equal(
      secondFeed.json?.notifications?.filter(
        (item) => item.title === 'Refund request rejected',
      ).length,
      1,
      secondFeed.text,
    );
  });

  test('a password change invalidates stale sessions and issues usable versioned tokens', async () => {
    const oldAccessToken = accessToken;
    const oldRefreshToken = refreshToken;
    const newPassword = 'RotatedSecurity2!';

    const mixedProfileUpdate = await request(baseUrl, '/profile', {
      method: 'PUT',
      headers: bearer(oldAccessToken),
      json: {
        firstName: 'Security',
        lastName: 'Tester',
        schoolEmail: '',
        personalEmail: email,
        studentId: '',
        yearLevel: '2024',
        program: 'Computer Science',
        currentPassword: password,
        newPassword,
      },
    });
    assert.equal(mixedProfileUpdate.response.status, 400, mixedProfileUpdate.text);
    assert.equal(
      mixedProfileUpdate.json?.message,
      'Use the dedicated password change endpoint.',
    );

    const incorrectCurrentPassword = await request(
      baseUrl,
      '/profile/password',
      {
        method: 'PUT',
        headers: bearer(oldAccessToken),
        json: {
          currentPassword: 'IncorrectSecurity1!',
          newPassword,
        },
      },
    );
    assert.equal(
      incorrectCurrentPassword.response.status,
      403,
      incorrectCurrentPassword.text,
    );
    assert.equal(
      incorrectCurrentPassword.json?.message,
      'Current password is incorrect.',
    );

    const changed = await request(baseUrl, '/profile/password', {
      method: 'PUT',
      headers: bearer(oldAccessToken),
      json: {
        currentPassword: password,
        newPassword,
      },
    });
    assert.equal(changed.response.status, 200, changed.text);
    assert.equal(typeof changed.json?.accessToken, 'string');
    assert.match(String(changed.json?.refreshToken || ''), /^[a-f0-9]{96}$/);
    assert.equal(jwt.decode(changed.json.accessToken)?.sv, 1);

    const staleAccess = await request(baseUrl, '/profile', {
      headers: bearer(oldAccessToken),
    });
    assert.ok([401, 404].includes(staleAccess.response.status), staleAccess.text);
    assert.equal(staleAccess.json?.success, false);

    const staleRefresh = await request(baseUrl, '/auth/refresh', {
      json: { email, refreshToken: oldRefreshToken },
    });
    assert.equal(staleRefresh.response.status, 401, staleRefresh.text);
    assert.deepEqual(staleRefresh.json, {
      success: false,
      message: 'Invalid refresh session.',
    });

    const currentAccess = await request(baseUrl, '/profile', {
      headers: bearer(changed.json.accessToken),
    });
    assert.equal(currentAccess.response.status, 200, currentAccess.text);

    const rotated = await request(baseUrl, '/auth/refresh', {
      json: { email, refreshToken: changed.json.refreshToken },
    });
    assert.equal(rotated.response.status, 200, rotated.text);
    assert.equal(jwt.decode(rotated.json?.accessToken)?.sv, 1);

    const replayedRefresh = await request(baseUrl, '/auth/refresh', {
      json: { email, refreshToken: changed.json.refreshToken },
    });
    assert.equal(replayedRefresh.response.status, 401, replayedRefresh.text);

    accessToken = rotated.json.accessToken;
    refreshToken = rotated.json.refreshToken;
  });

  test('password reset tokens are one-time and invalidate the prior session', async () => {
    const preResetAccessToken = accessToken;
    const preResetRefreshToken = refreshToken;
    const resetPassword = 'ResetSecurity3!';

    const requested = await request(
      baseUrl,
      '/auth/forgot-password/request-otp',
      { json: { email } },
    );
    assert.equal(requested.response.status, 200, requested.text);
    assert.match(String(requested.json?.otp || ''), /^\d{6}$/);

    const verified = await request(
      baseUrl,
      '/auth/forgot-password/verify-otp',
      {
        json: {
          email,
          otp: requested.json.otp,
          challengeToken: requested.json.challengeToken,
        },
      },
    );
    assert.equal(verified.response.status, 200, verified.text);
    assert.match(String(verified.json?.resetToken || ''), /^[a-f0-9]{64}$/);

    const reset = await request(baseUrl, '/auth/forgot-password/reset', {
      json: { resetToken: verified.json.resetToken, newPassword: resetPassword },
    });
    assert.equal(reset.response.status, 200, reset.text);

    const replay = await request(baseUrl, '/auth/forgot-password/reset', {
      json: {
        resetToken: verified.json.resetToken,
        newPassword: 'AttackerReplay4!',
      },
    });
    assert.equal(replay.response.status, 401, replay.text);
    assert.deepEqual(replay.json, {
      success: false,
      message: 'Reset token is invalid or expired.',
    });

    const staleAccess = await request(baseUrl, '/profile', {
      headers: bearer(preResetAccessToken),
    });
    assert.ok([401, 404].includes(staleAccess.response.status), staleAccess.text);

    const staleRefresh = await request(baseUrl, '/auth/refresh', {
      json: { email, refreshToken: preResetRefreshToken },
    });
    assert.equal(staleRefresh.response.status, 401, staleRefresh.text);

    const loggedIn = await request(baseUrl, '/auth/login', {
      json: { email, password: resetPassword },
    });
    assert.equal(loggedIn.response.status, 200, loggedIn.text);
    assert.equal(jwt.decode(loggedIn.json?.accessToken)?.sv, 2);
  });

  test('concurrent reset tokens from one session version permit only one password update', async () => {
    async function issueResetToken() {
      const requested = await request(
        baseUrl,
        '/auth/forgot-password/request-otp',
        { json: { email } },
      );
      assert.equal(requested.response.status, 200, requested.text);
      assert.match(String(requested.json?.otp || ''), /^\d{6}$/);

      const verified = await request(
        baseUrl,
        '/auth/forgot-password/verify-otp',
        {
          json: {
            email,
            otp: requested.json.otp,
            challengeToken: requested.json.challengeToken,
          },
        },
      );
      assert.equal(verified.response.status, 200, verified.text);
      assert.match(String(verified.json?.resetToken || ''), /^[a-f0-9]{64}$/);
      return verified.json.resetToken;
    }

    const resetTokenA = await issueResetToken();
    const resetTokenB = await issueResetToken();
    assert.notEqual(resetTokenA, resetTokenB);

    const candidates = [
      { resetToken: resetTokenA, password: 'ConcurrentWinnerA4!' },
      { resetToken: resetTokenB, password: 'ConcurrentWinnerB5!' },
    ];
    const attempts = await Promise.all(
      candidates.map((candidate) => request(
        baseUrl,
        '/auth/forgot-password/reset',
        {
          json: {
            resetToken: candidate.resetToken,
            newPassword: candidate.password,
          },
        },
      )),
    );

    const successIndexes = attempts
      .map((attempt, index) => attempt.response.status === 200 ? index : -1)
      .filter((index) => index !== -1);
    assert.deepEqual(
      attempts.map((attempt) => attempt.response.status).sort(),
      [200, 401],
      attempts.map((attempt) => attempt.text).join('\n'),
    );
    assert.equal(successIndexes.length, 1);

    const winningIndex = successIndexes[0];
    const losingIndex = winningIndex === 0 ? 1 : 0;
    assert.deepEqual(attempts[losingIndex].json, {
      success: false,
      message: 'Reset token is invalid or expired.',
    });

    const winningLogin = await request(baseUrl, '/auth/login', {
      json: { email, password: candidates[winningIndex].password },
    });
    assert.equal(winningLogin.response.status, 200, winningLogin.text);
    assert.equal(jwt.decode(winningLogin.json?.accessToken)?.sv, 3);

    const losingLogin = await request(baseUrl, '/auth/login', {
      json: { email, password: candidates[losingIndex].password },
    });
    assert.equal(losingLogin.response.status, 401, losingLogin.text);
    assert.deepEqual(losingLogin.json, {
      success: false,
      message: 'Invalid email or password.',
    });

    const winnerProfile = await request(baseUrl, '/profile', {
      headers: bearer(winningLogin.json.accessToken),
    });
    assert.equal(winnerProfile.response.status, 200, winnerProfile.text);
    assert.equal(winnerProfile.json?.user?.id, userId);
  });
});
