import { constants } from 'node:fs';
import { mkdir, open, realpath, rename, link, unlink } from 'node:fs/promises';
import { createHash, randomUUID } from 'node:crypto';
import path from 'node:path';

const mutations = new Map();
const revision = bytes => createHash('sha256').update(bytes).digest('hex');

function fail(code, message) {
  throw Object.assign(new Error(message), { toolCode: code });
}

function text(value, name, { empty = false } = {}) {
  if (typeof value !== 'string' || (!empty && !value.length) || !value.isWellFormed()) {
    fail('invalid_arguments', `${name} must be ${empty ? 'a' : 'a nonempty'} well-formed string`);
  }
}

function expected(value, { optional = false, absent = false } = {}) {
  if (optional && value === undefined) return;
  if (absent && value === 'absent') return;
  if (typeof value !== 'string' || !/^[a-f0-9]{64}$/.test(value)) {
    fail('invalid_revision', 'Use the revision returned by read_file, or absent when creating a file');
  }
}

function decode(bytes) {
  if (bytes.includes(0)) fail('binary_file', 'File contains NUL bytes; use a binary-aware tool');
  try { return new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(bytes); }
  catch { fail('invalid_utf8', 'File is not valid UTF-8'); }
}

async function snapshot(filename, maximum, signal, allowAbsent = false) {
  signal?.throwIfAborted();
  let file;
  try { file = await open(filename, constants.O_RDONLY | constants.O_NONBLOCK | constants.O_NOFOLLOW); }
  catch (error) { if (allowAbsent && error.code === 'ENOENT') return null; throw error; }
  try {
    const stat = await file.stat();
    if (!stat.isFile()) fail('not_a_file', 'The path must resolve to a regular file');
    if (stat.size > maximum) fail('file_too_large', `File exceeds ${maximum} bytes; use bounded Bash reads`);
    const bytes = Buffer.alloc(Math.min(stat.size + 1, maximum + 1));
    let length = 0;
    while (length < bytes.length) {
      signal?.throwIfAborted();
      const { bytesRead } = await file.read(bytes, length, bytes.length - length, length);
      if (!bytesRead) break;
      length += bytesRead;
    }
    const after = await file.stat();
    if (length !== stat.size || after.size !== stat.size || after.mtimeMs !== stat.mtimeMs || after.ctimeMs !== stat.ctimeMs) {
      fail('file_changed', 'File changed while being read; read it again');
    }
    const content = bytes.subarray(0, length);
    return { bytes: content, text: decode(content), revision: revision(content), stat };
  } finally { await file.close(); }
}

/** A bounded, no-follow observation of root project guidance, before Configure. */
export async function snapshotProject(cwd, limits, { signal } = {}) {
  const workspace = await realpath(cwd);
  if (Buffer.byteLength(workspace) > 4096) throw new Error('Workspace path exceeds the model boundary');
  if (!Number.isSafeInteger(limits.project_context_bytes) || limits.project_context_bytes <= 0) {
    throw new Error('The kernel did not declare a project-context bound');
  }
  const observed = await snapshot(path.join(workspace, 'AGENTS.md'), limits.project_context_bytes, signal, true);
  return { workspace, revision: observed?.revision ?? 'absent', instructions: observed?.text ?? '' };
}

async function canonical(filename, create) {
  try { return await realpath(filename); }
  catch (error) {
    if (error.code !== 'ENOENT' || !create) throw error;
    await mkdir(path.dirname(filename), { recursive: true });
    return path.join(await realpath(path.dirname(filename)), path.basename(filename));
  }
}

async function serialize(filename, operation) {
  const previous = mutations.get(filename) ?? Promise.resolve();
  const current = previous.catch(() => {}).then(operation);
  mutations.set(filename, current);
  try { return await current; }
  finally { if (mutations.get(filename) === current) mutations.delete(filename); }
}

function requireRevision(before, wanted) {
  if ((before?.revision ?? 'absent') !== wanted) fail('revision_conflict', 'File no longer has the expected revision; read it before editing');
}

async function publish(filename, bytes, before, limits, signal) {
  if (before?.stat.nlink > 1) fail('hard_link', 'Atomic replacement of a multiply-linked file is not supported');
  const temporary = path.join(path.dirname(filename), `.selvedge-${randomUUID()}.tmp`);
  let file;
  try {
    file = await open(temporary, 'wx', before ? before.stat.mode & 0o777 : 0o644);
    if (before) await file.chmod(before.stat.mode & 0o777);
    await file.writeFile(bytes, { signal });
    await file.sync();
    await file.close();
    file = undefined;
    signal?.throwIfAborted();
    const latest = await snapshot(filename, limits.file_bytes, signal, true);
    requireRevision(latest, before?.revision ?? 'absent');
    if (before && (latest.stat.ino !== before.stat.ino || latest.stat.dev !== before.stat.dev)) {
      fail('revision_conflict', 'File identity changed while preparing the edit; read it again');
    }
    signal?.throwIfAborted();
    // Creation is no-clobber. Replacement is atomic for readers and serialized
    // among our tools; a noncooperating external writer remains an OS boundary.
    if (before) await rename(temporary, filename);
    else await link(temporary, filename);
    const directory = await open(path.dirname(filename), 'r');
    try { await directory.sync(); } finally { await directory.close(); }
  } finally {
    await file?.close();
    await unlink(temporary).catch(error => { if (error.code !== 'ENOENT') throw error; });
  }
}

async function perform(name, args, limits, { signal, cwd }) {
  signal?.throwIfAborted();
  text(args.path, 'path');
  if (args.path.includes('\0')) fail('invalid_arguments', 'path must not contain NUL');
  if (name === 'write_file') {
    expected(args.expected_revision, { absent: true });
    text(args.content, 'content', { empty: true });
    const bytes = Buffer.from(args.content, 'utf8');
    decode(bytes);
    if (bytes.length > limits.file_bytes) fail('file_too_large', `Result exceeds ${limits.file_bytes} bytes`);
  }
  const filename = await canonical(path.resolve(cwd, args.path), name === 'write_file');
  if (name === 'read_file') {
    expected(args.expected_revision, { optional: true });
    const offset = args.offset ?? 0;
    const limit = args.limit ?? limits.file_default_page_bytes;
    if (!Number.isSafeInteger(offset) || offset < 0 || !Number.isSafeInteger(limit) || limit < 4 || limit > limits.file_page_bytes) {
      fail('invalid_arguments', 'Invalid byte offset or page limit');
    }
    const before = await snapshot(filename, limits.file_bytes, signal);
    if (args.expected_revision !== undefined) requireRevision(before, args.expected_revision);
    if (offset > before.bytes.length || (before.bytes[offset] & 0xc0) === 0x80) fail('invalid_offset', 'offset must be a UTF-8 character boundary within the file');
    let end = Math.min(before.bytes.length, offset + limit);
    while (end < before.bytes.length && (before.bytes[end] & 0xc0) === 0x80) end--;
    return { path: filename, revision: before.revision, content: decode(before.bytes.subarray(offset, end)),
      offset, next_offset: end < before.bytes.length ? end : null, total_bytes: before.bytes.length };
  }
  if (!['write_file', 'edit_file'].includes(name)) fail('unknown_tool', 'Unknown file operation');
  expected(args.expected_revision, { absent: name === 'write_file' });
  return serialize(filename, async () => {
    signal?.throwIfAborted();
    const before = await snapshot(filename, limits.file_bytes, signal, name === 'write_file');
    requireRevision(before, args.expected_revision);
    let content;
    let changedLine;
    if (name === 'write_file') {
      text(args.content, 'content', { empty: true });
      content = args.content;
    } else {
      text(args.old_text, 'old_text');
      text(args.new_text, 'new_text', { empty: true });
      const position = before.text.indexOf(args.old_text);
      if (position === -1) fail('text_not_found', 'old_text does not occur in the file; read the current contents');
      if (before.text.indexOf(args.old_text, position + 1) !== -1) fail('ambiguous_edit', 'old_text occurs more than once; include more surrounding text');
      content = before.text.slice(0, position) + args.new_text + before.text.slice(position + args.old_text.length);
      changedLine = 1 + (before.text.slice(0, position).match(/\n/g)?.length ?? 0);
    }
    const bytes = Buffer.from(content, 'utf8');
    decode(bytes);
    if (bytes.length > limits.file_bytes) fail('file_too_large', `Result exceeds ${limits.file_bytes} bytes`);
    const nextRevision = revision(bytes);
    if (nextRevision !== before?.revision) await publish(filename, bytes, before, limits, signal);
    return { path: filename, revision: nextRevision, previous_revision: before?.revision ?? 'absent',
      bytes: bytes.length, changed: nextRevision !== before?.revision, ...(changedLine ? { first_changed_line: changedLine } : {}) };
  });
}

/** Interpret only already-committed file effects; no lifecycle decisions here. */
export async function runFileTool(name, args, limits, { signal, cwd = process.cwd() } = {}) {
  try { return { error: false, value: await perform(name, args, limits, { signal, cwd }) }; }
  catch (error) {
    const code = signal?.aborted ? 'cancelled' : error.toolCode ?? error.code ?? 'file_operation_failed';
    return { error: true, value: { error: { code, message: String(error.message).slice(0, 1024) } } };
  }
}
