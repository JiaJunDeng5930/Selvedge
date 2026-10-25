import { createHash, randomBytes } from 'node:crypto';
import { constants } from 'node:fs';
import { lstat, mkdir, open, realpath, rename, rm } from 'node:fs/promises';
import path from 'node:path';
import { parseJson, stringifyJson } from './codec.mjs';
import { boundary } from './public/model-boundary.mjs';
import { durableDirectory, syncDirectory, readBoundedRegularSnapshot } from './file-io.mjs';

export const BOARD_FILE_LIMIT = 10 * 1024 * 1024;
const hash = bytes => createHash('sha256').update(bytes).digest('hex');

function filename(value) { return boundary('effect.filename', { value }); }

export function mediaType(bytes) {
  return boundary('effect.attachment_media_type', { prefix: Array.from(bytes.subarray(0, 12)) });
}

async function vault(home, { create }) {
  const canonicalHome = await realpath(home);
  const directory = path.join(canonicalHome, 'board-attachments');
  if (create) await durableDirectory(directory);
  const stat = await lstat(directory);
  // DEFENSE: Replacing the attachment vault with a link must not redirect attachment reads or writes outside the service home.
  if (!stat.isDirectory() || stat.isSymbolicLink() || await realpath(directory) !== directory) {
    throw new Error('The attachment vault must be a real directory inside the service home');
  }
  return directory;
}

async function regularFile(file, maximum) {
  return (await readBoundedRegularSnapshot(file, { maximumBytes: maximum })).bytes;
}

export async function readBoardAttachment(home, id) {
  boundary('effect.attachment_id', { id });
  const root = await vault(home, { create: false });
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
  const root = await vault(home, { create: true });
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
    await syncDirectory(pending);
    let existing = false;
    try { await rename(pending, target); }
    // DEFENSE: Repeated or concurrent uploads of identical bytes share the existing immutable hash directory.
    catch (error) {
      if (!['EEXIST', 'ENOTEMPTY'].includes(error.code)) throw error;
      existing = true;
    }
    // Repeated bytes reuse immutable metadata, including its original name.
    if (!existing) await syncDirectory(root);
    const verified = await readBoardAttachment(home, id);
    if (existing) {
      // A concurrent winner may not have completed its barriers yet; establish them before acknowledging its reference.
      for (const name of ['content', 'metadata.json']) {
        const file = await open(path.join(target, name), constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
        try { await file.sync(); } finally { await file.close(); }
      }
      await syncDirectory(target);
    }
    if (existing) await syncDirectory(root);
    return verified.attachment;
  } finally { await rm(pending, { recursive: true, force: true }); }
}

export function observeBoardClock() {
  const seconds = Math.floor(Date.now() / 1000);
  return boundary('effect.board_clock', { seconds });
}

/** Resolve immutable image references before an input reaches the durable journal. */
export async function observeMessageImages(command, home) {
  const references = boundary('effect.message_images', { command });
  await Promise.all(references.map(async value => {
    const { attachment } = await readBoardAttachment(home, value.id);
    boundary('effect.message_image_match', { value, attachment });
  }));
  return command;
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
