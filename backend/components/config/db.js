import { MongoClient } from 'mongodb';

import config from './config.js';

export const dbEnabled = config.database.enabled;
export const client = dbEnabled && config.database.uriIsValid
  ? new MongoClient(config.database.uri, {
      // Keep API failures inside the Flutter client's 12-second request limit.
      connectTimeoutMS: 5000,
      serverSelectionTimeoutMS: 5000,
    })
  : null;

export let alumniUsers;
export let studentUsers;
export let receipts;
export let requests;
export let notifications;
export let transactions;
export let refunds;
export let authChallenges;
export let rateLimits;

function bindCollections(database) {
  alumniUsers = database.collection(config.database.alumniCollection);
  studentUsers = database.collection(config.database.studentsCollection);
  receipts = database.collection('transactions');
  requests = database.collection('requests');
  notifications = database.collection('notifications');
  transactions = database.collection('transactions');
  refunds = database.collection('refunds');
  authChallenges = database.collection('auth_challenges');
  rateLimits = database.collection('rate_limits');
}

export async function connectDatabase() {
  if (!dbEnabled) return null;
  if (!client) throw new Error('MongoDB is not configured.');
  await client.connect();
  const database = client.db(config.database.name);
  bindCollections(database);
  return database;
}

export async function ensureDb() {
  if (!dbEnabled) return;
  if (!client) throw new Error('MongoDB is not configured.');
  if (alumniUsers && studentUsers) return;

  try {
    await connectDatabase();
  } catch (error) {
    throw new Error(`MongoDB connection failed: ${error.message}`);
  }
}
