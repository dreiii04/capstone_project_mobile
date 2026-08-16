import { v2 as cloudinary } from 'cloudinary';
import { randomBytes } from 'crypto';
import fs from 'fs';
import path from 'path';

import config from '../config/config.js';

export function initializeMediaStorage() {
  try {
    fs.mkdirSync(config.paths.receipts, { recursive: true });
    fs.mkdirSync(config.paths.profiles, { recursive: true });
  } catch (_error) {
    console.warn('Could not create local upload directories.');
  }

  if (!config.cloudinary.enabled) return;
  if (config.cloudinary.url) {
    cloudinary.config(true);
    return;
  }
  cloudinary.config({
    cloud_name: config.cloudinary.cloudName,
    api_key: config.cloudinary.apiKey,
    api_secret: config.cloudinary.apiSecret,
    secure: true,
  });
}

function requireLocalMediaSupport() {
  if (config.isVercel) {
    throw new Error(
      'Cloudinary is not configured. Local uploads are not supported on Vercel.',
    );
  }
}

export async function uploadReceipt(file, imageMetadata) {
  if (!config.cloudinary.enabled) {
    requireLocalMediaSupport();
    const fileName =
      `receipt-${randomBytes(18).toString('hex')}${imageMetadata.extension}`;
    fs.mkdirSync(config.paths.receipts, { recursive: true });
    await fs.promises.writeFile(
      path.join(config.paths.receipts, fileName),
      file.buffer,
    );
    return {
      secure_url: '',
      url: '',
      public_id: `local-${fileName}`,
      type: 'authenticated',
    };
  }
  if (!file?.buffer) throw new Error('Receipt image is required.');

  return new Promise((resolve, reject) => {
    const stream = cloudinary.uploader.upload_stream(
      {
        folder: 'capstone/receipts',
        resource_type: 'image',
        type: 'authenticated',
        use_filename: false,
        unique_filename: true,
      },
      (error, result) => error ? reject(error) : resolve(result),
    );
    stream.end(file.buffer);
  });
}

export async function uploadProfilePhoto(file, imageMetadata) {
  if (!config.cloudinary.enabled) {
    requireLocalMediaSupport();
    const fileName =
      `profile-${randomBytes(18).toString('hex')}${imageMetadata.extension}`;
    fs.mkdirSync(config.paths.profiles, { recursive: true });
    await fs.promises.writeFile(
      path.join(config.paths.profiles, fileName),
      file.buffer,
    );
    return {
      secure_url: `/uploads/profiles/${fileName}`,
      url: `/uploads/profiles/${fileName}`,
      public_id: `local-${fileName}`,
    };
  }
  if (!file?.buffer) throw new Error('Profile photo is required.');

  return new Promise((resolve, reject) => {
    const stream = cloudinary.uploader.upload_stream(
      {
        folder: 'capstone/profiles',
        resource_type: 'image',
      },
      (error, result) => error ? reject(error) : resolve(result),
    );
    stream.end(file.buffer);
  });
}

export async function deleteUploadedReceipt(publicId) {
  const normalizedPublicId = String(publicId || '');
  if (!normalizedPublicId) return;

  try {
    if (normalizedPublicId.startsWith('local-')) {
      const fileName = path.basename(normalizedPublicId.slice(6));
      const target = path.resolve(config.paths.receipts, fileName);
      const root = `${path.resolve(config.paths.receipts)}${path.sep}`;
      if (target.startsWith(root)) {
        await fs.promises.unlink(target).catch(() => {});
      }
      return;
    }
    if (config.cloudinary.enabled) {
      await cloudinary.uploader.destroy(normalizedPublicId, {
        resource_type: 'image',
        type: 'authenticated',
        invalidate: true,
      });
    }
  } catch (_error) {
    console.warn('Orphaned receipt cleanup failed.');
  }
}
