import { timingSafeEqual } from 'crypto';
import jwt from 'jsonwebtoken';

import config from '../config/config.js';

export function requireAuth(req, res, next) {
  const authHeader = String(req.headers.authorization || '');
  if (!authHeader.startsWith('Bearer ')) {
    return res
      .status(401)
      .json({ success: false, message: 'Missing access token.' });
  }

  const token = authHeader.slice(7).trim();
  if (!token || token.length > 4096) {
    return res
      .status(401)
      .json({ success: false, message: 'Missing access token.' });
  }

  try {
    const payload = jwt.verify(token, config.jwt.secret, {
      algorithms: ['HS256'],
      ...(config.jwt.issuer ? { issuer: config.jwt.issuer } : {}),
      ...(config.jwt.audience ? { audience: config.jwt.audience } : {}),
    });
    if (!payload ||
        typeof payload !== 'object' ||
        !String(payload.sub || '').trim()) {
      throw new Error('Missing token subject.');
    }
    req.auth = payload;
    return next();
  } catch (_error) {
    return res
      .status(401)
      .json({ success: false, message: 'Invalid or expired token.' });
  }
}

export function constantTimeEqual(left, right) {
  const leftBuffer = Buffer.from(String(left || ''), 'utf8');
  const rightBuffer = Buffer.from(String(right || ''), 'utf8');
  if (leftBuffer.length !== rightBuffer.length || leftBuffer.length === 0) {
    return false;
  }
  return timingSafeEqual(leftBuffer, rightBuffer);
}

export function requireNotificationSender(req, res, next) {
  const headerKey = String(req.headers['x-notification-key'] || '').trim();
  const senderKey = config.notificationsApiKey;
  if (!senderKey || Buffer.byteLength(senderKey) < 32) {
    return res.status(503).json({
      success: false,
      message: 'Notification delivery is not configured.',
    });
  }
  if (!constantTimeEqual(headerKey, senderKey)) {
    return res.status(401).json({
      success: false,
      message: 'Invalid notification credentials.',
    });
  }
  return next();
}
