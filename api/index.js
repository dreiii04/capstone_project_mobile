const { randomBytes } = require('crypto');

let handler;

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
  return handler(req, res);
};
