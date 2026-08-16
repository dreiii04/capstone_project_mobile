const http = require('http');

process.env.VERCEL = '1';
process.env.DISABLE_DB = 'true';
process.env.NODE_ENV = 'development';
process.env.JWT_SECRET = 'deployment-import-test-key-32-bytes-minimum';

const handler = require('../../api/index.js');
const server = http.createServer(handler);

server.listen(0, '127.0.0.1', async () => {
  try {
    const { port } = server.address();
    const response = await fetch(`http://127.0.0.1:${port}/health`);
    const body = await response.json();

    if (response.status !== 200 || body.success !== true) {
      throw new Error(`Unexpected health response: ${response.status}`);
    }

    console.log('Vercel backend entrypoint smoke test passed.');
  } catch (error) {
    console.error('Vercel backend entrypoint smoke test failed.');
    process.exitCode = 1;
  } finally {
    server.close();
  }
});
