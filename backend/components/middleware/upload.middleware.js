import multer from 'multer';
import path from 'path';

import {
  allowedImageExtensions,
  allowedReceiptMimeTypes,
  commonUploadLimits,
} from '../config/constants.js';

function imageFileFilter(req, file, callback) {
  const extension = path.extname(file.originalname || '').toLowerCase();
  const acceptedOctetStream =
    file.mimetype === 'application/octet-stream' &&
    allowedImageExtensions.has(extension);

  if (!allowedReceiptMimeTypes.has(file.mimetype) && !acceptedOctetStream) {
    req.fileValidationError =
      'Only JPG, PNG, WEBP, or HEIC images are allowed.';
    return callback(null, false);
  }
  return callback(null, true);
}

function detectImageFormat(buffer) {
  if (!Buffer.isBuffer(buffer) || buffer.length < 12) return null;
  if (buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff) {
    return { extension: '.jpg', mimeType: 'image/jpeg' };
  }

  const pngSignature = Buffer.from([
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
  ]);
  if (buffer.subarray(0, 8).equals(pngSignature)) {
    return { extension: '.png', mimeType: 'image/png' };
  }
  if (buffer.subarray(0, 4).toString('ascii') === 'RIFF' &&
      buffer.subarray(8, 12).toString('ascii') === 'WEBP') {
    return { extension: '.webp', mimeType: 'image/webp' };
  }
  if (buffer.subarray(4, 8).toString('ascii') === 'ftyp') {
    const brand = buffer.subarray(8, 12).toString('ascii').toLowerCase();
    if (new Set(['heic', 'heix', 'hevc', 'hevx', 'mif1', 'msf1']).has(brand)) {
      return { extension: '.heic', mimeType: 'image/heic' };
    }
  }
  return null;
}

export function validateUploadedImage(file) {
  const detected = detectImageFormat(file?.buffer);
  if (!detected) return null;
  return {
    ...detected,
    originalName: path.basename(String(file.originalname || 'image')).slice(0, 120),
  };
}

function imageUpload(fileSize) {
  return multer({
    storage: multer.memoryStorage(),
    fileFilter: imageFileFilter,
    limits: {
      ...commonUploadLimits,
      fileSize,
    },
  });
}

export const receiptUpload = imageUpload(8 * 1024 * 1024);
export const profileUpload = imageUpload(5 * 1024 * 1024);
