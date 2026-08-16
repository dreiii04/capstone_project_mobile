import { randomBytes } from 'crypto';
import multer from 'multer';

import config from '../config/config.js';

export function notFoundHandler(_req, res) {
  return res.status(404).json({
    success: false,
    message: 'Route not found.',
  });
}

export function errorHandler(err, _req, res, _next) {
  if (err instanceof SyntaxError && err.status === 400 && 'body' in err) {
    return res.status(400).json({
      success: false,
      message: 'Invalid JSON payload.',
    });
  }
  if (err instanceof multer.MulterError) {
    return res.status(400).json({
      success: false,
      message: err.code === 'LIMIT_FILE_SIZE'
        ? 'Uploaded image is too large.'
        : 'Invalid multipart upload.',
    });
  }
  if (err instanceof Error && new Set([
    'Unexpected end of form',
    'Unexpected end of file',
    'Malformed part header',
  ]).has(err.message)) {
    return res.status(400).json({
      success: false,
      message: 'Invalid multipart upload.',
    });
  }

  const errorId = randomBytes(8).toString('hex');
  if (config.isProduction) {
    console.error(`Request failed (${errorId}).`);
  } else {
    console.error(`Request failed (${errorId}):`, err);
  }
  return res.status(500).json({
    success: false,
    message: 'Internal server error.',
    errorId,
  });
}
