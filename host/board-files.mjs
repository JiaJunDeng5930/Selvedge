import { createHash, randomBytes } from 'node:crypto';
import { constants } from 'node:fs';
import { lstat, mkdir, open, realpath, rename, rm } from 'node:fs/promises';
import path from 'node:path';
import { parseJson, stringifyJson } from './codec.mjs';

export const BOARD_FILE_LIMIT = 10 * 1024 * 1024;
const ID = /^[a-f0-9]{64}$/;
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);

function filename(value) {
  if (typeof value !== 'string' || !value || Buffer.byteLength(value) > 256 ||
      /[\u0000-\u001f\u007f/\\]/u.test(value) || value === '.' || value === '..') {
    throw new TypeError('An attachment needs a plain filename of at most 256 UTF-8 bytes');
  }
  return value;
}

function mediaType(bytes) {
  if (bytes.length >= 8 && bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))) return 'image/png';
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return 'image/jpeg';
  if (bytes.length >= 6 && ['GIF87a', 'GIF89a'].includes(bytes.toString('ascii', 0, 6))) return 'image/gif';
  if (bytes.length >= 12 && bytes.toString('ascii', 0, 4) === 'RIFF' && bytes.toString('ascii', 8, 12) === 'WEBP') return 'image/webp';
  // SVG, HTML and a caller-supplied MIME type never authorize an inline preview.
  return 'application/octet-stream';
}

async function vault(home) {
  const canonicalHome = await realpath(home);
  const directory = path.join(canonicalHome, 'board-attachments');
  await mkdir(directory, { recursive: true, mode: 0o700 });
  const stat = await lstat(directory);
  if (!stat.isDirectory() || stat.isSymbolicLink() || await realpath(directory) !== directory) {
    throw new Error('The attachment vault must be a real directory inside the service home');
  }
  return directory;
}

async function regularFile(file, maximum) {
  const handle = await open(file, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const stat = await handle.stat();
    if (!stat.isFile() || stat.size > maximum) throw new RangeError('Attachment storage is not a bounded regular file');
    const data = await handle.readFile();
    if (data.length > maximum) throw new RangeError('Attachment storage changed beyond its byte budget');
    return data;
  } finally { await handle.close(); }
}

export async function readBoardAttachment(home, id) {
  if (typeof id !== 'string' || !ID.test(id)) throw new TypeError('Invalid attachment identifier');
  const root = await vault(home);
  const directory = path.join(root, id);
  const stat = await lstat(directory);
  if (!stat.isDirectory() || stat.isSymbolicLink() || await realpath(directory) !== directory) {
    throw new Error('Attachment directories cannot be symbolic links');
  }
  const record = parseJson((await regularFile(path.join(directory, 'metadata.json'), 2048)).toString('utf8'));
  const data = await regularFile(path.join(directory, 'content'), BOARD_FILE_LIMIT);
  if (!object(record) || record.version !== 1 || record.id !== id || record.bytes !== data.length ||
      record.mime !== mediaType(data) || hash(data) !== id) throw new Error('Attachment content or metadata failed its integrity check');
  filename(record.name);
  return { attachment: { id, name: record.name, mime: record.mime,
    path: path.join(directory, 'content'), bytes: String(data.length) }, data };
}

export async function saveBoardAttachment(home, name, stream) {
  filename(name);
  const chunks = [];
  let size = 0;
  for await (const part of stream) {
    const bytes = Buffer.from(part);
    size += bytes.length;
    if (size > BOARD_FILE_LIMIT) throw new RangeError('Each board attachment is limited to 10 MiB');
    chunks.push(bytes);
  }
  const data = Buffer.concat(chunks, size);
  const id = hash(data);
  const root = await vault(home);
  const target = path.join(root, id);
  const pending = path.join(root, `.upload-${randomBytes(16).toString('hex')}`);
  await mkdir(pending, { mode: 0o700 });
  try {
    const content = await open(path.join(pending, 'content'), 'wx', 0o400);
    try { await content.writeFile(data); await content.sync(); } finally { await content.close(); }
    const metadata = await open(path.join(pending, 'metadata.json'), 'wx', 0o400);
    try {
      await metadata.writeFile(stringifyJson({ version: 1, id, name, mime: mediaType(data), bytes: size }));
      await metadata.sync();
    } finally { await metadata.close(); }
    try { await rename(pending, target); }
    catch (error) { if (!['EEXIST', 'ENOTEMPTY'].includes(error.code)) throw error; }
    // Repeated bytes reuse immutable metadata, including its original name.
    return (await readBoardAttachment(home, id)).attachment;
  } finally { await rm(pending, { recursive: true, force: true }); }
}

export function observeBoardClock() {
  const seconds = Math.floor(Date.now() / 1000);
  if (!Number.isSafeInteger(seconds) || seconds < 0 || seconds > 0xffff_ffff) {
    throw new RangeError('The clock is outside the native board timestamp range');
  }
  return String(seconds);
}

/** Capture external observations. Card transitions and eligibility stay native. */
export async function observeBoardCommand(command, home) {
  if (!object(command)) return command;
  const operations = ['create_card', 'update_card', 'move_card', 'archive_card', 'restore_card', 'delete_card', 'run_card',
    'link_card', 'regenerate_card_title', 'pin_card'];
  if (!operations.includes(command.op)) return command;
  const result = { ...command, observed_at: observeBoardClock() };
  if (Object.hasOwn(command, 'attachments')) {
    if (!['create_card', 'update_card'].includes(command.op)) return result;
    if (!Array.isArray(command.attachments) || command.attachments.length > 4) throw new RangeError('A card accepts at most four attachments');
    const ids = new Set();
    result.attachments = [];
    for (const value of command.attachments) {
      if (!object(value) || Object.keys(value).some(key => !['id', 'name', 'mime', 'path', 'bytes'].includes(key)) ||
          typeof value.id !== 'string' || ids.has(value.id)) throw new TypeError('Attachments must be distinct uploaded file references');
      ids.add(value.id);
      const { attachment } = await readBoardAttachment(home, value.id);
      for (const key of ['name', 'mime', 'path', 'bytes']) {
        if (Object.hasOwn(value, key) && value[key] !== attachment[key]) throw new TypeError(`Attachment ${key} does not match its stored observation`);
      }
      result.attachments.push(attachment);
    }
  }
  return result;
}
