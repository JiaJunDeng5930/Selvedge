import { constants } from 'node:fs';
import { open, realpath } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { canonicalWorkspace } from './sandbox.mjs';

export async function snapshotContextFile(filename, limits, { signal } = {}) {
  signal?.throwIfAborted();
  const maximum = limits.project_context_bytes;
  if (!Number.isSafeInteger(maximum) || maximum <= 0) throw new Error('The kernel did not declare a project-context bound');
  if (Buffer.byteLength(filename) > 4096) throw new Error('Instruction path exceeds the model boundary');
  let file;
  try { file = await open(filename, constants.O_RDONLY | constants.O_NONBLOCK | constants.O_NOFOLLOW); }
  catch (error) {
    if (error.code === 'ENOENT') return null;
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
    return { path: filename, revision: createHash('sha256').update(bytes).digest('hex'), content: instructions };
  } finally { await file.close(); }
}

/** Observe guidance before a birth command; the journal owns the snapshot. */
export async function snapshotProject(cwd, limits, options) {
  const workspace = await realpath(cwd);
  const snapshot = await snapshotContextFile(path.join(workspace, 'AGENTS.md'), limits, options);
  return { workspace, revision: snapshot?.revision ?? 'absent', instructions: snapshot?.content ?? '' };
}

export async function snapshotGlobalInstructions(home, limits, options) {
  return snapshotContextFile(path.join(await realpath(home), 'AGENTS.md'), limits, options);
}

export function configuredInstructions(config, limits) {
  const value = config.instructions;
  const maximum = limits.project_context_bytes;
  if (!Number.isSafeInteger(maximum) || maximum <= 0) throw new Error('The kernel did not declare an instruction bound');
  if (typeof value !== 'string' || !value.isWellFormed() || value.includes('\0')) {
    throw new TypeError('Configured instructions must be a valid UTF-8 string without NUL bytes');
  }
  if (Buffer.byteLength(value, 'utf8') > maximum) {
    throw new RangeError('Configured instructions exceed the instruction byte limit');
  }
  return value;
}

/**
 * Observe only directories explicitly selected by the user. Project default
 * selection and fork inheritance remain in the native command resolver.
 */
export async function observeWorkspaceCommand(command, limits, { projectWorkspace } = {}) {
  if (command === null || typeof command !== 'object' || Array.isArray(command)) return command;
  const settingCommand = ['create', 'fork', 'save_board_agent'].includes(command.op);
  const projectCommand = ['create_project', 'update_project'].includes(command.op);
  if (graphCommand(command) && Array.isArray(command.nodes)) {
    const nodes = await Promise.all(command.nodes.map(async node => {
      if (!newGraphNode(node)) return node;
      const settings = await observeWorkspaceSettings(node.settings, limits, projectWorkspace);
      return settings === node.settings ? node : { ...node, settings };
    }));
    return { ...command, nodes };
  }
  if (settingCommand) {
    const settings = await observeWorkspaceSettings(command.settings, limits, projectWorkspace);
    return settings === command.settings ? command : { ...command, settings };
  }
  return projectCommand ? observeWorkspaceSettings(command, limits) : command;
}

function graphCommand(command) {
  return ['create_task_graph', 'update_task_graph'].includes(command.op);
}

function newGraphNode(node) {
  return node !== null && typeof node === 'object' && !Array.isArray(node) && node.task_id === undefined;
}

export function hasRootTaskCreation(command) {
  return command?.op === 'create' || (command !== null && typeof command === 'object' &&
    graphCommand(command) && Array.isArray(command.nodes) && command.nodes.some(newGraphNode));
}

async function observeWorkspaceSettings(selected, limits, projectWorkspace) {
  if (!selected || typeof selected !== 'object' || Array.isArray(selected)) return selected;
  if (selected.guidance !== undefined) throw new TypeError('Root guidance is observed by the service, not supplied by a client');
  if (selected.workspace === undefined && projectWorkspace && Number.isSafeInteger(selected.project_id)) {
    const workspace = await projectWorkspace(selected.project_id);
    if (workspace !== undefined) selected = { ...selected, workspace };
  }
  if (selected.workspace === undefined) return selected;
  const canonical = await canonicalWorkspace(selected.workspace);
  const observed = { ...selected, workspace: { roots: canonical.roots } };
  if (canonical.primary_root !== null) {
    observed.workspace.primary_root = canonical.primary_root;
    observed.guidance = await snapshotProject(canonical.primary_root, limits);
  }
  return observed;
}
