import { realpath } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { canonicalWorkspace } from './sandbox.mjs';
import { boundary } from './public/model-boundary.mjs';
import { workspaceCommandResult } from './model-api.ts';
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
    let bytes;
    // The cloud reader pins and checks one regular-file descriptor throughout the read.
    try { bytes = await filesystem.readFile(filename, { maximum }); }
    catch (error) {
      // DEFENSE: Guidance is optional and can disappear before the remote descriptor is opened.
      if (error.code === 'ENOENT') return null;
      throw error;
    }
    // DEFENSE: Cloud guidance must obey the same model context byte budget as local files.
    if (bytes.length > maximum) throw new Error(`File exceeds ${maximum} bytes; use bounded Bash reads`);
    return contextSnapshot(filename, bytes);
  }
  let snapshot;
  try { snapshot = await readBoundedRegularSnapshot(filename, { maximumBytes: maximum, signal }); }
  catch (error) {
    // DEFENSE: Guidance files are optional and may be deleted between discovery and open.
    if (error.code === 'ENOENT') return null;
    throw error;
  }
  return contextSnapshot(filename, snapshot.bytes);
}

function contextSnapshot(filename, bytes) {
  // DEFENSE: Guidance and skill files are externally editable; their content contract excludes NUL and invalid UTF-8.
  if (bytes.includes(0)) throw new Error('File contains NUL bytes; use a binary-aware tool');
  const instructions = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(bytes);
  return { path: filename, revision: createHash('sha256').update(bytes).digest('hex'), content: instructions };
}

/** Observe guidance before a birth command; the journal owns the snapshot. */
export async function snapshotProject(cwd, limits, options) {
  const workspace = await (options?.filesystem?.realpath ?? realpath)(cwd);
  return snapshotWorkspaceGuidance(workspace, limits, options);
}

export async function snapshotWorkspaceGuidance(workspace, limits, options) {
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
  return { command, ...workspaceCommandResult(boundary('effect.workspace_command', { command })) };
}

export function admitRawWorkspaceCommand(command) {
  return boundary('effect.workspace_command_raw', { command });
}

export async function observeWorkspaceCommand({ command, selections }, limits, options = {}) {
  if (!selections.length) return command;
  const observations = await Promise.all(selections.map(async selection => ({ selection,
    value: await observeWorkspaceSettings(selection, limits, options),
  })));
  return boundary('effect.workspace_command_observed', { command, observations });
}

export function hasRootTaskCreation(command) {
  return boundary('effect.root_task_creation', { command });
}

function observedGuidance(root, limits, filesystem, localGuidance) {
  // Only observations of the same canonical directory on the host share a snapshot.
  if (filesystem || !localGuidance) return snapshotWorkspaceGuidance(root, limits, { filesystem });
  const cached = localGuidance.get(root);
  if (cached) return cached;
  const snapshot = snapshotWorkspaceGuidance(root, limits);
  localGuidance.set(root, snapshot);
  return snapshot;
}

async function observeWorkspaceSettings({ value, project_id }, limits, { projectWorkspace, workspaceEnvironment, localGuidance }) {
  const workspace = project_id === null ? value.workspace : await projectWorkspace(project_id);
  // DEFENSE: A public project ID can name a deleted or unavailable Project; preserve it for native command rejection.
  if (workspace === undefined) return {};
  const resolution = await workspaceEnvironment?.(workspace.environment || project_id === null ? { workspace } : { project_id });
  const environment = resolution?.environment;
  try {
    const canonical = await canonicalWorkspace(workspace, { filesystem: environment?.filesystem });
    if (environment && !workspace.environment) boundary('effect.workspace_environment_bound', { workspace: canonical, root: environment.root });
    const observed = { workspace: { roots: canonical.roots,
      ...(workspace.environment ? { environment: workspace.environment } : {}) } };
    if (resolution) observed.workspace_binding = resolution.workspace_binding;
    if (canonical.primary_root !== null) {
      observed.workspace.primary_root = canonical.primary_root;
      observed.guidance = await observedGuidance(canonical.primary_root, limits, environment?.filesystem, localGuidance);
    }
    return observed;
  } finally { await environment?.filesystem.close(); }
}
