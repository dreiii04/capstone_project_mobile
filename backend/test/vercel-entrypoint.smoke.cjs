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
    for (const path of ['/health', '/api/health']) {
      const response = await fetch(`http://127.0.0.1:${port}${path}`);
      const body = await response.json();

      if (response.status !== 200 || body.success !== true) {
        throw new Error(
          `Unexpected health response for ${path}: ${response.status}`,
        );
      }
    }

    const loginResponse = await fetch(
      `http://127.0.0.1:${port}/api/auth/login`,
      {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: '{}',
      },
    );
    const loginBody = await loginResponse.json();
    if (loginResponse.status !== 400 || loginBody.success !== false) {
      throw new Error(
        `Unexpected shared login response: ${loginResponse.status}`,
      );
    }

    console.log('Vercel backend entrypoint smoke test passed.');
  } catch (error) {
    console.error('Vercel backend entrypoint smoke test failed.');
    process.exitCode = 1;
  } finally {
    server.close();
  }
});
