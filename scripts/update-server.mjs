import { readFile } from 'node:fs/promises';
import { loadConfig } from '../host/config.mjs';
import { Journal } from '../host/journal.mjs';
import { startServer } from '../host/server.mjs';
import { writeAtomic } from '../host/files.mjs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { waitForJournalOwnership } from './update-handoff.mjs';

const launch = JSON.parse(await readFile(new URL('../launch.json', import.meta.url), 'utf8'));
const configuration = fileURLToPath(new URL('../configuration.json', import.meta.url));
const publication = fileURLToPath(new URL('../ready.json', import.meta.url));
const journal = process.send ? await Journal.open(path.join(launch.home, 'journal.sqlite'),
  { waitForOwnership: waitForJournalOwnership }) : undefined;
let server;
try {
  const source = launch.useSavedConfig ? JSON.parse(await readFile(configuration, 'utf8')) : undefined;
  const settings = await loadConfig({ home: launch.home, filename: launch.filename, source });
  if (!launch.useSavedConfig) await writeAtomic(configuration, settings.source);
  server = await startServer({ ...settings, journal, cwd: launch.cwd, listenPort: launch.listenPort, listenHost: launch.listenHost,
    release: { ...launch.release, publish: instance => writeAtomic(publication, instance) } });
// DEFENSE: Configuration or listener startup may fail before the preopened journal is attached to the service.
} catch (error) {
  await journal?.close();
  throw error;
}
server.service.on('notice', event => {
  if (event.type === 'diagnostic' || event.type === 'fatal') console.error(event.message);
});
for (const [signal, code] of [['SIGINT', 130], ['SIGTERM', 0]]) {
  process.once(signal, () => {
    process.exitCode = code;
    server.close().catch(error => { console.error(error); process.exitCode = 1; });
  });
}
