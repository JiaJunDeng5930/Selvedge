import { createHash, randomBytes } from 'node:crypto';
import { constants } from 'node:fs';
import { lstat, mkdir, open, realpath, rename, rm } from 'node:fs/promises';
import path from 'node:path';
import { parseJson, stringifyJson } from './codec.mjs';
import { boundary } from './public/model-boundary.mjs';

export const BOARD_FILE_LIMIT = 10 * 1024 * 1024;
const hash = bytes => createHash('sha256').update(bytes).digest('hex');

function filename(value) { return boundary('effect.filename', { value }); }

function mediaType(bytes) {
  if (bytes.length >= 8 && bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))) return 'image/png';
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return 'image/jpeg';
  if (bytes.length >= 6 && ['GIF87a', 'GIF89a'].includes(bytes.toString('ascii', 0, 6))) return 'image/gif';
  if (bytes.length >= 12 && bytes.toString('ascii', 0, 4) === 'RIFF' && bytes.toString('ascii', 8, 12) === 'WEBP') return 'image/webp';
  // DEFENSE: Uploaded SVG/HTML and caller-supplied MIME types must not authorize active inline content.
  return 'application/octet-stream';
}

async function vault(home) {
  const canonicalHome = await realpath(home);
  const directory = path.join(canonicalHome, 'board-attachments');
  await mkdir(directory, { recursive: true, mode: 0o700 });
  const stat = await lstat(directory);
  // DEFENSE: Replacing the attachment vault with a link must not redirect writes outside the service home.
  if (!stat.isDirectory() || stat.isSymbolicLink() || await realpath(directory) !== directory) {
    throw new Error('The attachment vault must be a real directory inside the service home');
  }
  return directory;
}

async function regularFile(file, maximum) {
  const handle = await open(file, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const stat = await handle.stat();
    // DEFENSE: Stored attachment paths can be replaced by oversized or special files outside the upload API.
    if (!stat.isFile() || stat.size > maximum) throw new RangeError('Attachment storage is not a bounded regular file');
    const data = await handle.readFile();
    // DEFENSE: An external write can grow the opened attachment after the initial stat.
    if (data.length > maximum) throw new RangeError('Attachment storage changed beyond its byte budget');
    return data;
  } finally { await handle.close(); }
}

export async function readBoardAttachment(home, id) {
  boundary('effect.attachment_id', { id });
  const root = await vault(home);
  const directory = path.join(root, id);
  const stat = await lstat(directory);
  // DEFENSE: A replaced attachment directory must not redirect reads outside its content-addressed vault.
  if (!stat.isDirectory() || stat.isSymbolicLink() || await realpath(directory) !== directory) {
    throw new Error('Attachment directories cannot be symbolic links');
  }
  const record = parseJson((await regularFile(path.join(directory, 'metadata.json'), 2048)).toString('utf8'));
  const data = await regularFile(path.join(directory, 'content'), BOARD_FILE_LIMIT);
  const attachment = boundary('effect.attachment', { home, id, record, bytes: data.length,
    mime: mediaType(data), hash: hash(data), path: path.join(directory, 'content') });
  return { attachment, data };
}

export async function saveBoardAttachment(home, name, stream) {
  filename(name);
  const chunks = [];
  let size = 0;
  for await (const part of stream) {
    const bytes = Buffer.from(part);
    size += bytes.length;
    boundary('effect.attachment_budget', { home, name, size });
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
    // DEFENSE: Repeated or concurrent uploads of identical bytes share the existing immutable hash directory.
    catch (error) { if (!['EEXIST', 'ENOTEMPTY'].includes(error.code)) throw error; }
    // Repeated bytes reuse immutable metadata, including its original name.
    return (await readBoardAttachment(home, id)).attachment;
  } finally { await rm(pending, { recursive: true, force: true }); }
}

export function observeBoardClock() {
  const seconds = Math.floor(Date.now() / 1000);
  return boundary('effect.board_clock', { seconds });
}

/** Capture external observations. Card transitions and eligibility stay native. */
export async function observeBoardCommand(command, home) {
  const observation = boundary('effect.board_command', { command, home });
  if (!observation.observe) return command;
  const result = { ...command, observed_at: observeBoardClock() };
  if (observation.attachments) {
    const references = boundary('effect.board_references', { command, home });
    result.attachments = [];
    for (const value of references) {
      const { attachment } = await readBoardAttachment(home, value.id);
      boundary('effect.reference_match', { command, home, value, attachment });
      result.attachments.push(attachment);
    }
  }
  return result;
}
