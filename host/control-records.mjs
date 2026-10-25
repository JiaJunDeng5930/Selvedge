import { open, mkdir, lstat, realpath, rename, rm } from 'node:fs/promises';
import { constants } from 'node:fs';
import { randomUUID } from 'node:crypto';
import path from 'node:path';
import { parseJson, stringifyJson } from './codec.mjs';

const durableDirectories = new Map();

async function syncDirectory(directory) {
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

export async function writeControlRecord(filename, value) {
  const directory = path.dirname(filename);
  await durableDirectory(directory);
  const temporary = `${filename}.${randomUUID()}.tmp`;
  try {
    const file = await open(temporary, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | constants.O_NOFOLLOW, 0o600);
    try { await file.writeFile(stringifyJson(value)); await file.sync(); }
    finally { await file.close(); }
    await rename(temporary, filename);
    await syncDirectory(await realpath(directory));
  } finally { await rm(temporary, { force: true }); }
}

/** Read one bounded control-file revision without following replaced links. */
export async function readControlRecord(filename, { maximumBytes, label }) {
  const file = await open(filename, constants.O_RDONLY | constants.O_NONBLOCK | constants.O_NOFOLLOW);
  try {
    const before = await file.stat();
    // DEFENSE: A persisted control file can be replaced by a special or oversized file.
    if (!before.isFile() || before.size > maximumBytes) throw new Error(`Invalid ${label}`);
    const buffer = Buffer.alloc(before.size + 1);
    let length = 0;
    while (length < buffer.length) {
      const { bytesRead } = await file.read(buffer, length, buffer.length - length, length);
      if (!bytesRead) break;
      length += bytesRead;
    }
    const after = await file.stat();
    // DEFENSE: External edits during the read must not assemble different control-file revisions.
    if (length !== before.size || after.size !== before.size ||
        after.mtimeMs !== before.mtimeMs || after.ctimeMs !== before.ctimeMs) {
      throw new Error(`${label[0].toUpperCase()}${label.slice(1)} changed while being read`);
    }
    return parseJson(new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(buffer.subarray(0, length)));
  } finally { await file.close(); }
}
