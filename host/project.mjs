import { constants } from 'node:fs';
import { open, realpath } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { canonicalWorkspace } from './sandbox.mjs';

/** Observe root guidance before a configuration/birth command; the journal owns the snapshot. */
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

/**
 * Observe only directories explicitly selected by the user. Project default
 * selection and fork inheritance remain in the native command resolver.
 */
export async function observeWorkspaceCommand(command, limits) {
  if (command === null || typeof command !== 'object' || Array.isArray(command)) return command;
  const settingCommand = ['create', 'fork', 'save_board_agent'].includes(command.op);
  const projectCommand = ['create_project', 'update_project'].includes(command.op);
  if (!settingCommand && !projectCommand) return command;
  const selected = settingCommand ? command.settings : command;
  if (!selected || typeof selected !== 'object' || Array.isArray(selected)) return command;
  if (selected.guidance !== undefined) throw new TypeError('Root guidance is observed by the service, not supplied by a client');
  if (selected.workspace === undefined) return command;
  const canonical = await canonicalWorkspace(selected.workspace);
  const observed = { ...selected, workspace: { roots: canonical.roots } };
  if (canonical.primary_root !== null) {
    observed.workspace.primary_root = canonical.primary_root;
    observed.guidance = await snapshotProject(canonical.primary_root, limits);
  }
  return settingCommand ? { ...command, settings: observed } : observed;
}
