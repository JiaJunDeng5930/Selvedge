import { spawn } from 'node:child_process';
import { constants } from 'node:fs';
import { chmod, copyFile, cp, mkdir, open, readFile, readdir, rename, rm, stat } from 'node:fs/promises';
import { DatabaseSync } from 'node:sqlite';
import { randomBytes } from 'node:crypto';
import { homedir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { targets } from './build-tools.mjs';

const root = fileURLToPath(new URL('..', import.meta.url));
const launchFile = 'launch.json';
const releaseId = /^[0-9a-f]{32}$/;
const fromJson = async filename => JSON.parse(await readFile(filename, 'utf8'));

function argumentsForUpdate(args) {
  const options = {};
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--foreground') options.foreground = true;
    else if (['--home', '--config'].includes(args[i]) && args[i + 1] && !args[i + 1].startsWith('--')) {
      options[args[i].slice(2)] = path.resolve(args[++i]);
    } else throw new Error('Usage: bun run update [--home <directory>] [--config <file>]');
  }
  return options;
}

async function optionalRecord(filename) {
  try { return await fromJson(filename); }
  // DEFENSE: A stopped or not-yet-published service has no record at this path.
  catch (error) { if (error.code !== 'ENOENT') throw error; }
}

function localRequest(instance, pathname, options) {
  const url = new URL(instance.address);
  // DEFENSE: Edited or legacy discovery records must never redirect local credentials off loopback.
  if (instance.format !== 'selvedge-local-server-1' || url.protocol !== 'http:' ||
      !['127.0.0.1', '[::1]'].includes(url.hostname) || typeof instance.token !== 'string') {
    throw new Error('Invalid local server discovery record');
  }
  return fetch(new URL(pathname, url), { ...options, redirect: 'error',
    headers: { authorization: `Bearer ${instance.token}` } });
}

async function isListening(instance) {
  // Keep validation outside the rejection handler for the network probe.
  const request = localRequest(instance, '/api/health', { signal: AbortSignal.timeout(1000) });
  let result;
  // DEFENSE: A killed server can leave its old discovery record behind.
  try { result = await request; }
  catch { return false; }
  await result.body?.cancel();
  // DEFENSE: A different server can now own the recorded port. Never treat it as the old service.
  if (!result.ok) throw new Error(`The service at ${instance.address} rejected its discovery credentials (HTTP ${result.status})`);
  return true;
}

async function awaitAvailable({ instance, child }) {
  const deadline = Date.now() + 5000;
  while (child.exitCode === null && child.signalCode === null && Date.now() < deadline) {
    const request = localRequest(instance, '/api/health', { signal: AbortSignal.timeout(1000) });
    let response;
    // DEFENSE: A published child can exit before the first health probe reaches it.
    try { response = await request; }
    catch { break; }
    await response.body?.cancel();
    if (response.ok) return;
    // DEFENSE: Discovery can become visible while its publication directory is still being synced.
    if (response.status !== 503) break;
    await Bun.sleep(25);
  }
  throw new Error('The published release did not become available. Its journal was retained.');
}

async function snapshotRuntime(directory) {
  await Promise.all(['.build', 'scripts'].map(name => mkdir(path.join(directory, name))));
  const copies = ['host', 'remote', 'node_modules', 'package.json'];
  await Promise.all(copies.map(name => cp(path.join(root, name), path.join(directory, name), {
    recursive: true, mode: constants.COPYFILE_FICLONE, verbatimSymlinks: true,
  })));
  await Promise.all([
    copyFile(path.join(root, '.build/kernel-model.mjs'), path.join(directory, '.build/kernel-model.mjs'), constants.COPYFILE_FICLONE),
    copyFile(path.join(root, 'scripts/update-server.mjs'), path.join(directory, 'scripts/update-server.mjs')),
  ]);
}

async function start(directory, launch, writeAtomic) {
  const publication = path.join(directory, 'ready.json');
  await rm(publication, { force: true });
  await writeAtomic(path.join(directory, launchFile), launch);
  const logPath = path.join(directory, 'server.log');
  const log = await open(logPath, 'a', 0o600);
  let child;
  let exited;
  try {
    child = spawn(process.execPath, [path.join(directory, 'scripts/update-server.mjs')], {
      cwd: launch.cwd, detached: true, stdio: ['ignore', log.fd, log.fd],
    });
    exited = new Promise(resolve => {
      child.once('error', resolve);
      child.once('exit', (code, signal) => resolve(Object.assign(new Error(`Service exited (${signal ?? code})`), { exitCode: code })));
    });
  } finally { await log.close(); }
  async function published() {
    const instance = await optionalRecord(publication);
    if (instance?.pid === child.pid && instance.release?.id === launch.release.id) return { child, instance, exited };
  }

  const deadline = Date.now() + 120_000;
  try {
    let failure;
    for (;;) {
      const running = await published();
      if (running) return running;
      if (failure) throw failure;
      // DEFENSE: A plugin or dependency can block candidate startup before a listener is published.
      if (Date.now() >= deadline) throw new Error('Service startup timed out');
      failure = await Promise.race([exited, Bun.sleep(50)]);
    }
  } catch (error) {
    // DEFENSE: A failed or timed-out candidate must release the database before rollback.
    child.kill('SIGKILL');
    await exited;
    // Publication survives process exit. After this point the candidate may have executed tools.
    const running = await published();
    if (running) return running;
    const logText = await readFile(logPath, 'utf8');
    throw new Error(`${error.message}\n${logText.trimEnd().split('\n').slice(-12).join('\n')}`, { cause: error });
  }
}

async function databaseBackup(journal, backup, withJournalOwnership) {
  return withJournalOwnership(journal, async () => {
    try { await stat(journal); }
    // DEFENSE: Starting an empty home has no existing journal to restore.
    catch (error) { if (error.code === 'ENOENT') return false; throw error; }
    const db = new DatabaseSync(journal);
    try { db.prepare('VACUUM INTO ?').run(backup); }
    finally { db.close(); }
    await chmod(backup, 0o600);
    const file = await open(backup, 'r');
    try { await file.sync(); }
    finally { await file.close(); }
    return true;
  });
}

async function restoreDatabase(journal, backup, hadJournal, withJournalOwnership) {
  await withJournalOwnership(journal, async () => {
    await Promise.all(['-wal', '-shm'].map(suffix => rm(journal + suffix, { force: true })));
    if (hadJournal) await rename(backup, journal);
    else await rm(journal, { force: true });
  });
}

async function update(options) {
  const home = options.home ?? path.resolve(process.env.SELVEDGE_HOME ?? path.join(homedir(), '.selvedge'));
  const releases = path.join(home, 'releases');
  await mkdir(releases, { recursive: true, mode: 0o700 });
  const lock = new DatabaseSync(path.join(releases, 'update.lock'), { timeout: 0 });
  try {
    // A dead updater releases its SQLite lock without leaving a stale mutex.
    lock.exec('PRAGMA journal_mode=DELETE; BEGIN EXCLUSIVE');
    let active = await optionalRecord(path.join(home, 'server.json'));
    if (active && !await isListening(active)) active = undefined;
    // DEFENSE: A pre-update server cannot acknowledge a durable handoff. Its active tools must not be interrupted.
    if (active && !releaseId.test(active.release?.id)) throw new Error('This running Selvedge predates managed updates. Stop it once after its tools finish, then run bun run update.');
    const previousDirectory = active ? path.join(releases, active.release.id) : undefined;
    const previous = active ? await fromJson(path.join(previousDirectory, launchFile)) : undefined;

    const build = Bun.spawn([process.execPath, 'run', 'build', '--target', Object.keys(targets).join(',')],
      { cwd: root, stdout: 'inherit', stderr: 'inherit' });
    if (await build.exited !== 0) throw new Error('The new release could not be built');

    const { withJournalOwnership } = await import('../host/journal.mjs');
    const { writeAtomic } = await import('../host/files.mjs');
    const id = randomBytes(16).toString('hex');
    const directory = path.join(releases, id);
    await mkdir(directory, { mode: 0o700 });
    const journal = path.join(home, 'journal.sqlite');
    const backup = path.join(directory, 'journal-before-update.sqlite');
    const address = active && new URL(active.address);
    const launch = { home, filename: options.config ?? previous?.filename, cwd: previous?.cwd ?? process.cwd(),
      ...(address ? { listenPort: Number(address.port || 80), listenHost: address.hostname.replace(/^\[|\]$/g, '') } : {}),
      release: { id, token: active?.token ?? randomBytes(32).toString('hex') } };
    let installed = false;
    let drained = false;
    let backupComplete = false;
    let hadJournal;
    try {
      await snapshotRuntime(directory);
      if (active) {
        console.log('Waiting for the running Selvedge to finish its operations…');
        const response = await localRequest(active, '/_selvedge/update/drain', { method: 'POST', timeout: false });
        const reply = await response.json();
        // DEFENSE: A competing local handoff or journal failure can deny shutdown.
        if (!response.ok || !reply.ok) throw new Error(reply.error?.message ?? 'The running release did not acknowledge handoff');
        drained = true;
      }
      hadJournal = await databaseBackup(journal, backup, withJournalOwnership);
      backupComplete = true;
      const running = await start(directory, launch, writeAtomic);
      installed = true;
      running.child.unref();
      await awaitAvailable(running);
      await rm(backup, { force: true });
      for (const name of await readdir(releases)) {
        if (name !== id && releaseId.test(name)) await rm(path.join(releases, name), { recursive: true });
      }
      console.log(`Selvedge: ${running.instance.address}/\nPID: ${running.instance.pid}`);
      return running;
    } catch (error) {
      if (installed) throw error;
      // DEFENSE: After a candidate attempted startup it may have committed migrations or recovery inputs before failing to bind.
      if (backupComplete) await restoreDatabase(journal, backup, hadJournal, withJournalOwnership);
      if (drained) {
        const running = await start(previousDirectory, { ...previous, useSavedConfig: true,
          listenPort: launch.listenPort, listenHost: launch.listenHost,
          release: { ...previous.release, failure: error.message.split('\n')[0] } }, writeAtomic);
        running.child.unref();
        await awaitAvailable(running);
        throw new Error(`Update failed. Previous release restored at ${running.instance.address}/.\nPID: ${running.instance.pid}\n${error.message}`,
          { cause: error });
      }
      throw error;
    }
  } finally { lock.close(); }
}

try {
  const options = argumentsForUpdate(process.argv.slice(2));
  const running = await update(options);
  if (options.foreground) {
    running.child.ref();
    for (const signal of ['SIGINT', 'SIGTERM']) process.once(signal, () => running.child.kill(signal));
    process.exitCode = (await running.exited).exitCode ?? 1;
  }
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
