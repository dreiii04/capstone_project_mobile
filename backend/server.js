import { app, initializeBackend } from './app.js';
import config from './components/config/config.js';

try {
  await initializeBackend();
  app.listen(config.port, () => {
    console.log(`Auth API listening on port ${config.port}`);
  });
} catch (error) {
  console.error(
    config.isProduction
      ? 'Failed to start server.'
      : `Failed to start server: ${error.message}`,
  );
  process.exitCode = 1;
}
