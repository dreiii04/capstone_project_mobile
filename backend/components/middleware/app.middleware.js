import cors from 'cors';
import express from 'express';
import helmet from 'helmet';

import config from '../config/config.js';
import { ensureDb } from '../config/db.js';
import { apiLimiter, authLimiter } from './rate-limit.middleware.js';

export function applyAppMiddleware(app) {
  app.disable('x-powered-by');
  if (config.trustProxyHops > 0) {
    app.set('trust proxy', config.trustProxyHops);
  }

  app.use(helmet({
    strictTransportSecurity: config.isProduction
      ? {
          maxAge: 63_072_000,
          includeSubDomains: true,
          preload: true,
        }
      : false,
  }));
  app.use((req, res, next) => {
    if (!config.isProduction || req.secure) return next();
    return res.status(400).json({
      success: false,
      message: 'HTTPS is required.',
    });
  });
  app.use(cors({
    origin(origin, callback) {
      if (!origin) return callback(null, true);
      if (!config.isProduction && config.allowedOrigins.includes('*')) {
        return callback(null, true);
      }
      return callback(null, config.allowedOrigins.includes(origin));
    },
    credentials: false,
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'OPTIONS'],
    allowedHeaders: ['Authorization', 'Content-Type', 'X-Notification-Key'],
  }));

  app.use((_req, res, next) => {
    if (!config.startupError) return next();
    if (!config.isProduction) {
      console.error(`Startup configuration error: ${config.startupError}`);
    }
    return res.status(503).json({
      success: false,
      message: 'Service configuration is unavailable.',
    });
  });
  app.use((_req, res, next) => {
    res.set('Cache-Control', 'no-store');
    res.set('Pragma', 'no-cache');
    next();
  });

  app.use(
    '/uploads/profiles',
    express.static(config.paths.profiles, {
      dotfiles: 'deny',
      index: false,
      maxAge: '1d',
    }),
  );
  app.use(express.json({ limit: '1mb' }));
  app.use(async (_req, _res, next) => {
    try {
      await ensureDb();
      next();
    } catch (error) {
      if (!config.isProduction) {
        console.error('Database unavailable:', error.message);
      }
      return _res.status(503).json({
        success: false,
        message: 'Database is temporarily unavailable.',
      });
    }
  });
  app.use(apiLimiter);
  app.use('/auth', authLimiter);
}
