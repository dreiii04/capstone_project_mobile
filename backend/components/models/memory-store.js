export const memoryUsers = new Map();
export const memoryReceipts = [];
export const memoryRequests = [];
export const memoryNotifications = [];
// MongoDB stores receipts and transactions in one collection. The in-memory
// adapter mirrors that behavior so local development and tests match MongoDB.
export const memoryTransactions = memoryReceipts;
export const memoryRefunds = [];

export const otpStore = new Map();
export const registrationOtpStore = new Map();
export const resetTokenStore = new Map();
