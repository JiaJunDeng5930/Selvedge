import { constants } from 'node:fs';
import { open, realpath } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import path from 'node:path';

/** Observe root guidance once before Configure; the committed snapshot owns it. */
export async function snapshotProject(cwd, limits, { signal } = {}) {
  signal?.throwIfAborted();
  const maximum = limits.project_context_bytes;
  if (!Number.isSafeInteger(maximum) || maximum <= 0) throw new Error('The kernel did not declare a project-context bound');
  const workspace = await realpath(cwd);
  if (Buffer.byteLength(workspace) > 4096) throw new Error('Workspace path exceeds the model boundary');
  let file;
  try { file = await open(path.join(workspace, 'AGENTS.md'), constants.O_RDONLY | constants.O_NONBLOCK | constants.O_NOFOLLOW); }
  catch (error) {
    if (error.code === 'ENOENT') return { workspace, revision: 'absent', instructions: '' };
    throw error;
  }
  try {
    const before = await file.stat();
    if (!before.isFile()) throw new Error('The path must resolve to a regular file');
    if (before.size > maximum) throw new Error(`File exceeds ${maximum} bytes; use bounded Bash reads`);
    const buffer = Buffer.alloc(Math.min(before.size + 1, maximum + 1));
    let length = 0;
    while (length < buffer.length) {
      signal?.throwIfAborted();
      const { bytesRead } = await file.read(buffer, length, buffer.length - length, length);
      if (!bytesRead) break;
      length += bytesRead;
    }
    const after = await file.stat();
    if (length !== before.size || after.size !== before.size || after.mtimeMs !== before.mtimeMs || after.ctimeMs !== before.ctimeMs) {
      throw new Error('File changed while being read; read it again');
    }
    const bytes = buffer.subarray(0, length);
    if (bytes.includes(0)) throw new Error('File contains NUL bytes; use a binary-aware tool');
    let instructions;
    try { instructions = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(bytes); }
    catch { throw new Error('File is not valid UTF-8'); }
    return { workspace, revision: createHash('sha256').update(bytes).digest('hex'), instructions };
  } finally { await file.close(); }
}
