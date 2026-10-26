import { realpath } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { canonicalWorkspace } from './sandbox.mjs';
import { cloneJson } from './codec.mjs';
import { boundary } from './public/model-boundary.mjs';
import { workspaceCommandResult, interpretWorkspaceSettings } from './model-api.ts';
import { readBoundedRegularSnapshot } from './file-io.mjs';

const contextDefinitions = boundary('config.context_definitions', {});

async function snapshotGuidance(directory, kind, limits, options) {
  const definition = contextDefinitions.find(definition => definition.kind === kind);
  for (const filename of definition.observer.policy.files) {
    const snapshot = await snapshotContextFile(path.join(directory, filename), limits, options);
    if (snapshot !== null) return snapshot;
  }
  return null;
}

export async function snapshotContextFile(filename, limits, { signal, filesystem } = {}) {
  signal?.throwIfAborted();
  const maximum = limits.project_context_bytes;
  // DEFENSE: Configured skill paths and discovered guidance paths must fit the native source identity limit.
  if (Buffer.byteLength(filename) > 4096) throw new Error('Instruction path exceeds the model boundary');
  if (filesystem) {
    let before;
    try { before = await filesystem.lstat(filename); }
    catch (error) {
      // DEFENSE: Guidance is optional and can disappear during a cloud filesystem observation.
      if (error.code === 'ENOENT') return null;
      throw error;
    }
    // DEFENSE: Repository guidance may name a symbolic link, device or directory in the cloud environment.
    if (!before.isFile() || before.isSymbolicLink()) throw new Error('The path must resolve to a regular file without symbolic links');
    // DEFENSE: Cloud guidance must obey the same model context byte budget as local files.
    if (before.size > maximum) throw new Error(`File exceeds ${maximum} bytes; use bounded Bash reads`);
    const bytes = await filesystem.readFile(filename, { signal, maximum, noFollow: true });
    const after = await filesystem.lstat(filename);
    // DEFENSE: An editor or Bash operation can replace cloud guidance while it is being read.
    if (bytes.length !== before.size || after.size !== before.size || after.mtimeMs !== before.mtimeMs || after.ctimeMs !== before.ctimeMs) {
      throw new Error('File changed while being read; read it again');
    }
    return contextSnapshot(filename, bytes);
  }
  let snapshot;
  try { snapshot = await readBoundedRegularSnapshot(filename, { maximumBytes: maximum, signal }); }
  catch (error) {
    // DEFENSE: Guidance files are optional and may be deleted between discovery and open.
    if (error.code === 'ENOENT') return null;
    // DEFENSE: The shared descriptor reader reports physical snapshot failures;
    // guidance retains its public context-specific diagnostics.
    if (error.code === 'NOT_REGULAR') throw new Error('The path must resolve to a regular file');
    if (error.code === 'TOO_LARGE') throw new Error(`File exceeds ${maximum} bytes; use bounded Bash reads`);
    if (error.code === 'CHANGED') throw new Error('File changed while being read; read it again');
    throw error;
  }
  return contextSnapshot(filename, snapshot.bytes);
}

function contextSnapshot(filename, bytes) {
  // DEFENSE: Guidance and skill files are externally editable; their content contract excludes NUL and invalid UTF-8.
  if (bytes.includes(0)) throw new Error('File contains NUL bytes; use a binary-aware tool');
  let instructions;
  // DEFENSE: TextDecoder rejects invalid UTF-8 in external instruction files rather than replacing bytes.
  try { instructions = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(bytes); }
  catch { throw new Error('File is not valid UTF-8'); }
  return { path: filename, revision: createHash('sha256').update(bytes).digest('hex'), content: instructions };
}

/** Observe guidance before a birth command; the journal owns the snapshot. */
export async function snapshotProject(cwd, limits, options) {
  const workspace = await (options?.filesystem?.realpath ?? realpath)(cwd);
  const snapshot = await snapshotGuidance(workspace, 'project_guidance', limits, options);
  return { workspace, path: snapshot?.path ?? '', revision: snapshot?.revision ?? 'absent', instructions: snapshot?.content ?? '' };
}

export async function snapshotGlobalInstructions(home, limits, options) {
  return snapshotGuidance(await realpath(home), 'global_agents', limits, options);
}

/**
 * Observe only directories explicitly selected by the user. Project default
 * selection and fork inheritance remain in the native command resolver.
 */
export function workspaceCommandPlan(command) {
  return workspaceCommandResult(boundary('effect.workspace_command', { command }));
}

export function admitRawWorkspaceCommand(command) {
  return boundary('effect.workspace_command_raw', { command });
}

export async function observeWorkspaceCommand(command, limits, { projectWorkspace, workspaceEnvironment } = {}) {
  command = cloneJson(command);
  const plan = workspaceCommandPlan(command);
  const observations = await Promise.all(plan.selections.map(selection =>
    observeWorkspaceSettings(selection.value, limits,
      selection.resolve_project ? projectWorkspace : undefined, workspaceEnvironment)));
  return boundary('effect.workspace_command_observed', { command, observations });
}

export function hasRootTaskCreation(command) {
  return workspaceCommandPlan(command).rootTask;
}

async function observeWorkspaceSettings(selected, limits, projectWorkspace, workspaceEnvironment) {
  return interpretWorkspaceSettings(boundary('effect.workspace_settings', { value: selected, resolve_project: Boolean(projectWorkspace) }), {
    project: async projectId => {
      const workspace = await projectWorkspace(projectId);
      // DEFENSE: A public project ID can name a deleted or unavailable Project; preserve it for native command rejection.
      if (workspace === undefined) return false;
      selected = { ...selected, workspace };
      return true;
    },
    observe: async projectId => {
      const resolution = await workspaceEnvironment?.(projectId === null
        ? { workspace: selected.workspace } : { project_id: projectId });
      const environment = resolution?.environment;
      try {
        const canonical = await canonicalWorkspace(selected.workspace, { filesystem: environment?.filesystem });
        if (environment) boundary('effect.workspace_environment_bound', { workspace: canonical, root: environment.root });
        const observed = { workspace: { roots: canonical.roots } };
        if (resolution) observed.workspace_binding = resolution.workspace_binding;
        if (canonical.primary_root !== null) {
          observed.workspace.primary_root = canonical.primary_root;
          observed.guidance = await snapshotProject(canonical.primary_root, limits, { filesystem: environment?.filesystem });
        }
        return observed;
      } finally { await environment?.filesystem.close(); }
    },
  });
}
