import nodemailer from 'nodemailer';

import config from '../config/config.js';

function otpTtlMinutes() {
  const configured = Number(config.otp.ttlMinutes);
  if (!Number.isFinite(configured) || configured <= 0) return 10;
  return Math.min(configured, 30);
}

function createMailTransporter() {
  if (!config.smtpEnabled) return null;
  const smtp = config.smtp;
  return nodemailer.createTransport({
    host: smtp.host,
    port: smtp.port,
    secure: smtp.secure,
    requireTLS: !smtp.secure,
    connectionTimeout: 10 * 1000,
    greetingTimeout: 10 * 1000,
    socketTimeout: 15 * 1000,
    auth: {
      user: smtp.user,
      pass: smtp.pass,
    },
    tls: {
      rejectUnauthorized: true,
      minVersion: 'TLSv1.2',
    },
  });
}

export async function sendOtpEmail({ email, otp, purpose }) {
  const transporter = createMailTransporter();
  if (!transporter) throw new Error('SMTP is not configured.');

  const subjects = {
    registration: 'Your Verifitor registration OTP',
    login: 'Your Verifitor login OTP',
    'password-reset': 'Your Verifitor password reset OTP',
  };
  const subject = subjects[purpose] || 'Your Verifitor OTP';
  const text =
    `Your OTP is ${otp}. It expires in ${otpTtlMinutes()} minutes.`;

  await transporter.sendMail({
    from: config.smtp.from,
    to: email,
    subject,
    text,
  });
}

export async function sendOtpResponse(
  res,
  { email, otp, purpose, challengeToken },
) {
  if (config.otp.developmentMode && !config.isProduction) {
    return res.json({
      success: true,
      message: 'OTP generated (dev mode).',
      otp,
      challengeToken,
    });
  }

  if (!config.smtpEnabled) {
    return res.status(500).json({
      success: false,
      message: 'SMTP is not configured.',
    });
  }

  try {
    await sendOtpEmail({ email, otp, purpose });
    return res.json({
      success: true,
      message: 'OTP sent to your email.',
      challengeToken,
    });
  } catch (_error) {
    console.error('OTP email delivery failed.');
    return res.status(502).json({
      success: false,
      message: 'Unable to send a verification email right now.',
    });
  }
}
