import { startServer } from './server';

void startServer().catch((error) => {
  console.error('Fatal server startup error:', error);
  process.exit(1);
});
