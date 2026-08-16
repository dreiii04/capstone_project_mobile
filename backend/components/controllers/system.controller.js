export function healthCheck(_req, res) {
  return res.json({ success: true, message: 'API is healthy' });
}
