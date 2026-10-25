import { open, mkdir, lstat, realpath, rename, rm, link } from 'node:fs/promises';
import { constants } from 'node:fs';
import { randomUUID } from 'node:crypto';
import path from 'node:path';

const durableDirectories = new Map();

export async function syncDirectory(directory) {
  const handle = await open(directory, constants.O_RDONLY | constants.O_DIRECTORY | constants.O_NOFOLLOW);
  try { await handle.sync(); } finally { await handle.close(); }
}

/** Establish every directory entry from a stable filesystem root before publishing a recovery record. */
export async function durableDirectory(directory) {
  directory = path.resolve(directory);
  const parent = path.dirname(directory);
  if (parent === directory) return;
  let existing;
  try { existing = await lstat(directory); }
  catch (error) {
    // DEFENSE: A newly selected service home or namespace has not been created yet.
    if (error.code !== 'ENOENT') throw error;
  }
  const known = durableDirectories.get(directory);
  if (existing?.isDirectory() && known?.dev === existing.dev && known?.ino === existing.ino) return;
  await durableDirectory(parent);
  try { await mkdir(directory, { mode: 0o700 }); }
  catch (error) {
    // DEFENSE: Service homes and receipt directories normally already exist on reopen.
    if (error.code !== 'EEXIST') throw error;
  }
  const entry = await lstat(directory);
  // Existing system ancestors such as macOS /var can be symlinks; sync their canonical directory.
  const canonical = entry.isSymbolicLink() ? await realpath(directory) : directory;
  // DEFENSE: A file occupying a required service directory cannot hold durable child records.
  if (!entry.isDirectory() && !entry.isSymbolicLink()) throw new Error(`Control storage is not a directory: ${directory}`);
  await syncDirectory(canonical);
  await syncDirectory(await realpath(parent));
  const observed = await lstat(directory);
  durableDirectories.set(directory, { dev: observed.dev, ino: observed.ino });
}

/** Publish bytes only after both the contents and final directory entry are durable. */
export async function publishBytes(filename, bytes, { mode = 'replace', permissions = 0o600 } = {}) {
  // DEFENSE: The publication contract supports only these two explicit overwrite policies.
  if (mode !== 'replace' && mode !== 'create-if-absent') throw new TypeError('Unknown publication mode');
  const directory = path.dirname(filename);
  await durableDirectory(directory);
  const temporary = `${filename}.${randomUUID()}.tmp`;
  try {
    const file = await open(temporary, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | constants.O_NOFOLLOW, permissions);
    try { await file.writeFile(bytes); await file.sync(); }
    finally { await file.close(); }
    let result = 'created';
    if (mode === 'replace') await rename(temporary, filename);
    else {
      try { await link(temporary, filename); }
      catch (error) {
        // DEFENSE: Concurrent identity/configuration creation must not overwrite the existing winner.
        if (error.code !== 'EEXIST') throw error;
        result = 'already-exists';
      }
      await rm(temporary);
    }
    await syncDirectory(await realpath(directory));
    return result;
  } finally { await rm(temporary, { force: true }); }
}

function snapshotError(code, message) { return Object.assign(new Error(message), { code }); }

/** Bound allocation and reads on one nonblocking descriptor; callers own metadata and text admission. */
export async function readBoundedRegularSnapshot(filename, { maximumBytes, noFollow = true, admitMetadata = () => {} }) {
  const file = await open(filename, constants.O_RDONLY | constants.O_NONBLOCK | (noFollow ? constants.O_NOFOLLOW : 0));
  try {
    const before = await file.stat();
    // DEFENSE: Public file paths can name FIFOs/devices or files larger than their declared byte budget.
    if (!before.isFile()) throw snapshotError('NOT_REGULAR', 'Storage is not a regular file');
    if (before.size > maximumBytes) throw snapshotError('TOO_LARGE', 'Storage exceeds its byte budget');
    await admitMetadata(before);
    const buffer = Buffer.alloc(Math.min(before.size + 1, maximumBytes + 1));
    let length = 0;
    while (length < buffer.length) {
      const { bytesRead } = await file.read(buffer, length, buffer.length - length, length);
      if (!bytesRead) break;
      length += bytesRead;
    }
    const after = await file.stat();
    await admitMetadata(after);
    // DEFENSE: A real external edit during the read must not combine different file revisions.
    if (length !== before.size || after.size !== before.size || after.mtimeMs !== before.mtimeMs ||
        after.ctimeMs !== before.ctimeMs || after.mode !== before.mode || after.uid !== before.uid || after.gid !== before.gid) {
      throw snapshotError('CHANGED', 'Storage changed while being read');
    }
    return { bytes: buffer.subarray(0, length), before, after };
  } finally { await file.close(); }
}
