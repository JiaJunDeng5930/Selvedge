import { boundary } from './public/model-boundary.mjs';
import { constants } from 'node:fs';
import { access, mkdtemp, open, realpath, rm, stat, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';

/** Canonicalize an explicit workspace observation; this does not choose task policy. */
export async function canonicalWorkspace(value) {
  boundary('effect.workspace_admit', { value });
  const canonical = async root => {
    boundary('effect.root_admit', { root, absolute: typeof root === 'string' && path.isAbsolute(root), value });
    const resolved = await realpath(root);
    // DEFENSE: An explicitly selected external workspace path can name a file or change before stat.
    if (!(await stat(resolved)).isDirectory()) throw new TypeError('A workspace root must be a directory');
    return resolved;
  };
  const roots = await Promise.all(value.roots.map(canonical));
  boundary('effect.workspace_distinct', { value, roots });
  const selected = boundary('effect.workspace_selection', { value, roots });
  const primary = selected.canonicalize ? await canonical(selected.root) : selected.root;
  return boundary('effect.workspace_selected', { value, roots, primary });
}

// These coordinates attest only standard path observations, never launch policy.
function workspaceObservations(original, workspace) {
  const observe = root => ({ root, absolute: typeof root === 'string' && path.isAbsolute(root) });
  const selected = boundary('effect.workspace_selection', { value: original, roots: workspace.roots });
  return { original: original.roots.map(observe), canonical: workspace.roots.map(observe),
    ...(selected.canonicalize ? { primary: observe(selected.root), canonical_primary: observe(workspace.primary_root) } : {}) };
}

// Standard platform path observation; all permission rules are assembled natively.
function ancestors(root, includeSelf) {
  const result = [];
  let parent = includeSelf ? root : path.dirname(root);
  while (true) {
    if (!includeSelf || parent !== path.dirname(parent)) result.push(parent);
    if (parent === path.dirname(parent)) return result;
    parent = path.dirname(parent);
  }
}

export function seccompFilter(architecture, networkAccess) {
  const program = boundary('effect.seccomp', { architecture, networkAccess });
  const bytes = Buffer.alloc(program.length * 8);
  program.forEach(({ code, jt, jf, k }, index) => {
    bytes.writeUInt16LE(code, index * 8);
    bytes[index * 8 + 2] = jt;
    bytes[index * 8 + 3] = jf;
    bytes.writeUInt32LE(k >>> 0, index * 8 + 4);
  });
  return bytes;
}

function environment(scratch, projectOnly = false) {
  const plan = boundary('effect.environment', { scratch, projectOnly, platform: process.platform,
    names: Object.keys(process.env) });
  const env = {};
  for (const name of plan.names) env[name] = process.env[name];
  return Object.assign(env, plan.overrides);
}

async function executable(candidates) {
  for (const candidate of candidates) {
    try { await access(candidate, constants.X_OK); return candidate; }
    // DEFENSE: The supported OS installation paths may omit the sandbox binary or contain a nonexecutable file.
    catch (error) { if (!['ENOENT', 'EACCES'].includes(error.code)) throw error; }
  }
  throw new Error(`Sandbox executable unavailable (${candidates.join(', ')}); refusing to run without isolation`);
}

async function runtimeReads(platform) {
  // Do not grant /System (its Data-volume alias contains user files), /usr,
  // /opt/homebrew, or /etc wholesale. Runtime code/certificates are read-only;
  // package-manager databases, user homes and service state are not runtimes.
  const candidates = boundary('effect.runtime_candidates', { platform });
  const paths = [];
  for (const root of candidates) {
    try { paths.push({ root, canonical: await realpath(root) }); }
    // DEFENSE: Runtime directories differ across supported OS installations; only existing declared roots are mounted.
    catch (error) { if (error.code !== 'ENOENT') throw error; }
  }
  return paths;
}

/**
 * Produce a process launch from a committed native plan. Failure never falls back
 * to unrestricted execution. Policy selection/approval is not implemented here.
 */
export async function prepareSandbox(plan, { platform = process.platform, architecture = process.arch,
  readOnlyPaths = [], managedWorktreeRoot, signal } = {}) {
  signal?.throwIfAborted();
  const options = { platform, architecture, readOnlyPaths, managedWorktreeRoot };
  boundary('effect.sandbox_admit', { plan, options });
  const workspace = await canonicalWorkspace(plan.workspace);
  const source = { plan, options, workspace, root_observations: workspaceObservations(plan.workspace, workspace) };
  const { projectOnly, unrestricted } = boundary('effect.workspace_bound', source);
  if (unrestricted) {
    return { ...boundary('effect.unrestricted_launch', source), env: environment(tmpdir()),
      descriptors: [], cleanup: async () => {} };
  }
  const scratch = await realpath(await mkdtemp(path.join(tmpdir(), 'selvedge-sandbox-')));
  const handles = [];
  const cleanup = async () => {
    // DEFENSE: Launch preparation may fail after opening descriptors; attempt every close and propagate failures.
    const closed = await Promise.allSettled(handles.map(handle => handle.close()));
    await rm(scratch, { recursive: true, force: true });
    for (const result of closed) if (result.status === 'rejected') throw result.reason;
  };
  try {
    const protectedRoots = await Promise.all(readOnlyPaths.map(root => realpath(root)));
    const managedRoot = managedWorktreeRoot === undefined ? null : await realpath(managedWorktreeRoot);
    const context = { ...source, scratch, protectedRoots, managedWorktreeRoot: managedRoot, separator: path.sep };
    boundary('effect.protected_workspace', { ...context, projectOnly });
    const preparation = boundary('effect.sandbox_prepare', context);
    signal?.throwIfAborted();
    if (platform === 'darwin') {
      const file = await executable(boundary('effect.executable_candidates', { plan, options, platform }));
      const runtimeObservations = projectOnly ? await runtimeReads(platform) : [];
      const input = boundary('effect.seatbelt_input', { ...context, ...preparation, runtimeReads: runtimeObservations });
      const terminal = boundary('effect.sandbox_launch', { ...context, runtimeReads: runtimeObservations,
        protectedAncestors: protectedRoots.map(root => ancestors(root, true)),
        readAncestors: input.readableRoots ? [...input.readableRoots, scratch].map(root => ancestors(root, false)) : [] });
      return { file, ...terminal, env: environment(scratch, projectOnly), descriptors: [], cleanup };
    }
    const file = await executable(boundary('effect.executable_candidates', { plan, options, platform }));
    const policyPath = path.join(scratch, 'seccomp.bpf');
    await writeFile(policyPath, seccompFilter(architecture, plan.sandbox.network_access), { mode: 0o600, flag: 'wx' });
    handles.push(await open(policyPath, constants.O_RDONLY | constants.O_NOFOLLOW));
    const observedRuntime = projectOnly ? await runtimeReads(platform) : [];
    const bindings = preparation.bindings;
    for (const binding of bindings) {
      // Pin each admitted source directory against replacement before execution.
      const handle = await open(binding.root, constants.O_RDONLY | constants.O_DIRECTORY | constants.O_NOFOLLOW);
      handles.push(handle);
      binding.descriptor = handles.length + 2;
    }
    const terminal = boundary('effect.sandbox_launch', { ...context, bindings, runtimeReads: observedRuntime });
    return { file, ...terminal, env: environment(scratch, projectOnly), descriptors: handles.map(handle => handle.fd), cleanup };
  // DEFENSE: Sandbox binary/policy preparation can fail after allocating scratch space and pinned descriptors.
  } catch (error) { await cleanup(); throw error; }
}
