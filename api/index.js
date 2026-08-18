const { randomBytes } = require('crypto');

let handler;

function removePublicApiPrefix(req) {
  const url = String(req.url || '/');
  if (url !== '/api' &&
      !url.startsWith('/api/') &&
      !url.startsWith('/api?')) {
    return;
  }

  const suffix = url.slice('/api'.length);
  req.url = !suffix
    ? '/'
    : suffix.startsWith('?')
      ? `/${suffix}`
      : suffix;
}

// Vercel serverless entrypoint. The Express app never opens its own port.
module.exports = async function vercelHandler(req, res) {
  if (!handler) {
    try {
      const backend = await import('../backend/app.js');
      handler = backend.default;
    } catch (_error) {
      const errorId = randomBytes(8).toString('hex');
      console.error(`Failed to import backend application (${errorId}).`);
      return res.status(500).json({
        success: false,
        message: 'Internal server error.',
        errorId,
      });
    }
  }
  // Web and mobile clients share the public /api contract while the Express
  // application keeps clean, host-independent routes such as /auth/login.
  removePublicApiPrefix(req);
  return handler(req, res);
};
