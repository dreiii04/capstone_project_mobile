export const allowedReceiptMimeTypes = new Set([
  'image/jpeg',
  'image/jpg',
  'image/png',
  'image/webp',
  'image/heic',
  'image/heif',
  'image/heic-sequence',
  'image/heif-sequence',
]);

export const allowedImageExtensions = new Set([
  '.jpg',
  '.jpeg',
  '.png',
  '.webp',
  '.heic',
  '.heif',
]);

export const commonUploadLimits = Object.freeze({
  files: 1,
  fields: 10,
  parts: 12,
  fieldNameSize: 100,
  fieldSize: 8 * 1024,
});

export const emailRegex = /^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/;
export const passwordRegex =
  /^(?=\S{8,72}$)(?=.*[A-Z])(?=.*[a-z])(?=.*[0-9])(?=.*[!@#$%^&*(),.?":{}|<>]).*$/;
export const dummyPasswordHash =
  '$2a$12$i8ZFwZWuQesbxZnbw5tSrOx3QPXtqFaypm3LBKf2ZCBYvPo3ZOWie';
export const personNameRegex = /^[\p{L}][\p{L}\p{M} .'-]*$/u;
export const studentIdRegex = /^[A-Za-z0-9][A-Za-z0-9-]{3,29}$/;
export const studentYearLevels = new Set([
  '1st Year',
  '2nd Year',
  '3rd Year',
  '4th Year',
  '5th Year',
  'Graduate Student',
]);

export const terminalWorkflowStatuses = new Set([
  'approved',
  'completed',
  'complete',
  'released',
  'rejected',
  'declined',
  'denied',
  'cancelled',
  'canceled',
  'refunded',
]);

export const refundStatusAliases = new Map([
  ['pending', 'pending'],
  ['under_review', 'pending'],
  ['reviewing', 'pending'],
  ['approved', 'approved'],
  ['processing', 'processing'],
  ['in_process', 'processing'],
  ['completed', 'completed'],
  ['complete', 'completed'],
  ['sent', 'completed'],
  ['refunded', 'refunded'],
  ['rejected', 'rejected'],
  ['declined', 'rejected'],
  ['denied', 'rejected'],
]);
