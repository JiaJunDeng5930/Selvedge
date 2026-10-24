import { startServer } from '../../host/server.mjs';

const running = await startServer(JSON.parse(process.argv[2]));
process.send({ address: running.address, token: running.token });
process.once('SIGTERM', async () => {
  await running.close();
  process.disconnect();
});
