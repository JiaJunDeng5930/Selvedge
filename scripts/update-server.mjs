import { readFile } from 'node:fs/promises';
import { loadConfig } from '../host/config.mjs';
import { startServer } from '../host/server.mjs';
import { writeAtomic } from '../host/files.mjs';
import { fileURLToPath } from 'node:url';

const launch = JSON.parse(await readFile(new URL('../launch.json', import.meta.url), 'utf8'));
const configuration = fileURLToPath(new URL('../configuration.json', import.meta.url));
const source = launch.useSavedConfig ? JSON.parse(await readFile(configuration, 'utf8')) : undefined;
const settings = await loadConfig({ home: launch.home, filename: launch.filename, source });
if (!launch.useSavedConfig) await writeAtomic(configuration, settings.source);
const publication = fileURLToPath(new URL('../ready.json', import.meta.url));
const server = await startServer({ ...settings, cwd: launch.cwd, listenPort: launch.listenPort, listenHost: launch.listenHost,
  release: { ...launch.release, publish: instance => writeAtomic(publication, instance) } });
server.service.on('notice', event => {
  if (event.type === 'diagnostic' || event.type === 'fatal') console.error(event.message);
});
for (const [signal, code] of [['SIGINT', 130], ['SIGTERM', 0]]) {
  process.once(signal, () => {
    process.exitCode = code;
    server.close().catch(error => { console.error(error); process.exitCode = 1; });
  });
}
