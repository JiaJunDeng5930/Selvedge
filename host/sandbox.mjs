import { constants } from 'node:fs';
import { access, mkdtemp, open, realpath, rm, stat, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';

/** Canonicalize an explicit workspace observation; this does not choose task policy. */
export async function canonicalWorkspace(value) {
  if (!value || !Array.isArray(value.roots) || value.roots.length > 32 ||
      Object.keys(value).some(key => !['roots', 'primary_root'].includes(key))) {
    throw new TypeError('A workspace requires at most 32 roots and an optional primary_root');
  }
  const canonical = async root => {
    if (typeof root !== 'string' || !path.isAbsolute(root) || root.includes('\0') || Buffer.byteLength(root) > 4096) {
      throw new TypeError('Workspace roots must be bounded absolute directory paths');
    }
    const resolved = await realpath(root);
    if (!(await stat(resolved)).isDirectory()) throw new TypeError('A workspace root must be a directory');
    return resolved;
  };
  const roots = await Promise.all(value.roots.map(canonical));
  if (new Set(roots).size !== roots.length) throw new TypeError('Workspace roots must be distinct after resolving symbolic links');
  const selected = value.primary_root;
  const primary = selected === undefined || selected === null || selected === '' ? roots[0] ?? null : await canonical(selected);
  if (primary !== null && !roots.includes(primary)) throw new TypeError('The primary root must be one of the workspace roots');
  return { roots, primary_root: primary };
}

function literal(value) {
  if (typeof value !== 'string' || value.includes('\0')) throw new TypeError('Invalid sandbox path');
  // SBPL strings, not regular expressions. Quotes/backslashes must never add rules.
  return JSON.stringify(value);
}

/** Interpret an already-authorized filesystem/network plan as a Seatbelt policy. */
export function seatbeltProfile({ writableRoots, scratch, readOnlyPaths = [], networkAccess }) {
  const writes = [...writableRoots, scratch].map(root => `(subpath ${literal(root)})`).join('\n  ');
  const protectedRules = readOnlyPaths.flatMap(root => {
    const rules = [`(deny file-write* (subpath ${literal(root)}))`];
    // A writable ancestor must not rename a protected subtree out of its deny rule.
    for (let ancestor = root; ancestor !== path.dirname(ancestor); ancestor = path.dirname(ancestor)) {
      rules.push(`(deny file-write-unlink (literal ${literal(ancestor)}))`);
    }
    return rules;
  });
  return [
    '(version 1)', '(deny default)',
    '(allow process-exec process-fork)',
    '(allow signal (target same-sandbox))',
    '(allow process-info* (target same-sandbox))',
    '(allow file-read*)', '(allow sysctl-read)',
    '(allow mach-lookup (global-name "com.apple.system.opendirectoryd.libinfo"))',
    '(allow ipc-posix-sem)',
    '(allow file-write-data (require-all (literal "/dev/null") (vnode-type CHARACTER-DEVICE)))',
    `(allow file-write*\n  ${writes})`,
    ...protectedRules,
    // No blanket Mach/Unix-socket access: a host daemon could otherwise perform
    // filesystem mutations on the child's behalf outside its writable roots.
    ...(networkAccess ? [
      '(allow network-outbound (remote ip "*:*"))',
      '(allow network-inbound (local ip "*:*"))',
      '(allow mach-lookup (global-name "com.apple.system.config.network_change") (global-name "com.apple.mDNSResponder") (global-name "com.apple.trustd.agent"))',
    ] : []),
  ].join('\n');
}

const syscallTables = {
  x64: { audit: 0xc000003e, socket: 41, clone: 56, denied: [101, 133, 155, 161, 165, 166, 167, 168, 169, 172, 173, 175, 176,
    246, 248, 249, 250, 259, 272, 298, 303, 304, 308, 310, 311, 313, 320, 321, 323] },
  arm64: { audit: 0xc00000b7, socket: 198, clone: 220, denied: [33, 39, 40, 41, 51, 97, 104, 105, 106, 117, 142,
    217, 218, 219, 224, 225, 241, 264, 265, 268, 270, 271, 273, 280, 282, 294] },
};

/** Linux seccomp classic-BPF program; architecture and socket-family checks are explicit. */
export function seccompFilter(architecture, networkAccess) {
  const table = syscallTables[architecture];
  if (!table) throw new Error(`Linux sandbox does not support architecture ${architecture}`);
  const program = [];
  const instruction = (code, jt, jf, k) => program.push({ code, jt, jf, k });
  const load = offset => instruction(0x20, 0, 0, offset);
  const equal = (value, jt, jf) => instruction(0x15, jt, jf, value);
  const result = value => instruction(0x06, 0, 0, value);
  const deny = 0x00050001; // SECCOMP_RET_ERRNO | EPERM
  const allow = 0x7fff0000;
  load(4); // seccomp_data.arch
  equal(table.audit, 1, 0);
  result(0x80000000); // SECCOMP_RET_KILL_PROCESS: another ABI must not bypass the filter.
  load(0); // seccomp_data.nr
  if (architecture === 'x64') {
    instruction(0x35, 0, 1, 0x40000000); // Also reject the x32 syscall ABI.
    result(deny);
  }
  for (const number of table.denied) { equal(number, 0, 1); result(deny); }
  equal(435, 0, 1); // clone3 stores flags behind a pointer that classic BPF cannot inspect.
  result(0x00050026); // ENOSYS allows libc to fall back to the flag-checked clone syscall.
  equal(table.clone, 0, 3);
  load(16);
  instruction(0x45, 0, 1, 0x7e020000); // Namespace-creating clone flags; ordinary threads/forks remain permitted.
  result(deny);
  load(0);
  if (!networkAccess) { equal(table.socket, 0, 1); result(deny); }
  else {
    equal(table.socket, 0, 5);
    load(16); // seccomp_data.args[0], socket family (little-endian supported ABIs).
    equal(2, 2, 0); // AF_INET
    equal(10, 1, 0); // AF_INET6; host pathname/abstract Unix sockets stay inaccessible.
    result(deny);
    result(allow);
  }
  result(allow);
  const bytes = Buffer.alloc(program.length * 8);
  program.forEach(({ code, jt, jf, k }, index) => {
    bytes.writeUInt16LE(code, index * 8);
    bytes[index * 8 + 2] = jt;
    bytes[index * 8 + 3] = jf;
    bytes.writeUInt32LE(k >>> 0, index * 8 + 4);
  });
  return bytes;
}

function environment(scratch) {
  const env = { ...process.env, TMPDIR: scratch, TMP: scratch, TEMP: scratch, HISTFILE: '/dev/null' };
  for (const key of Object.keys(env)) {
    if (key === 'BASH_ENV' || key === 'ENV' || key.startsWith('LD_') || key.startsWith('DYLD_')) delete env[key];
  }
  return env;
}

async function executable(candidates) {
  for (const candidate of candidates) {
    try { await access(candidate, constants.X_OK); return candidate; }
    catch (error) { if (!['ENOENT', 'EACCES'].includes(error.code)) throw error; }
  }
  throw new Error(`Sandbox executable unavailable (${candidates.join(', ')}); refusing to run without isolation`);
}

/**
 * Produce a process launch from a committed native plan. Failure never falls back
 * to unrestricted execution. Policy selection/approval is not implemented here.
 */
export async function prepareSandbox(plan, { platform = process.platform, architecture = process.arch,
  readOnlyPaths = [], signal } = {}) {
  signal?.throwIfAborted();
  if (!['linux', 'darwin'].includes(platform)) throw new Error('Selvedge supports Linux and macOS only');
  if (!plan || !['sandboxed', 'unrestricted'].includes(plan.access) ||
      !['workspace-write', 'read-only'].includes(plan.sandbox?.mode) || typeof plan.sandbox.network_access !== 'boolean') {
    throw new TypeError('Malformed committed sandbox execution plan');
  }
  const workspace = await canonicalWorkspace(plan.workspace);
  if (JSON.stringify(workspace) !== JSON.stringify({ roots: plan.workspace.roots, primary_root: plan.workspace.primary_root })) {
    throw new Error('A workspace root changed after it was committed; reselect the workspace before executing');
  }
  const cwd = workspace.primary_root ?? '/';
  if (plan.access === 'unrestricted') {
    return { file: '/bin/bash', prefix: ['--noprofile', '--norc'], cwd, env: environment(tmpdir()),
      descriptors: [], cleanup: async () => {} };
  }
  const scratch = await realpath(await mkdtemp(path.join(tmpdir(), 'selvedge-sandbox-')));
  const handles = [];
  const cleanup = async () => {
    await Promise.allSettled(handles.map(handle => handle.close()));
    await rm(scratch, { recursive: true, force: true });
  };
  try {
    const writableRoots = plan.sandbox.mode === 'workspace-write' ? workspace.roots : [];
    const protectedRoots = await Promise.all(readOnlyPaths.map(root => realpath(root)));
    signal?.throwIfAborted();
    if (platform === 'darwin') {
      return { file: await executable(['/usr/bin/sandbox-exec']), prefix: ['-p', seatbeltProfile({
        writableRoots, scratch, readOnlyPaths: protectedRoots, networkAccess: plan.sandbox.network_access,
      }), '/bin/bash', '--noprofile', '--norc'], cwd, env: environment(scratch), descriptors: [], cleanup };
    }
    const file = await executable(['/usr/bin/bwrap', '/bin/bwrap']);
    const policyPath = path.join(scratch, 'seccomp.bpf');
    await writeFile(policyPath, seccompFilter(architecture, plan.sandbox.network_access), { mode: 0o600, flag: 'wx' });
    handles.push(await open(policyPath, constants.O_RDONLY | constants.O_NOFOLLOW));
    const prefix = ['--die-with-parent', '--new-session', '--unshare-user', '--unshare-pid',
      '--unshare-ipc', '--unshare-uts', '--cap-drop', 'ALL', '--ro-bind', '/', '/'];
    if (!plan.sandbox.network_access) prefix.push('--unshare-net');
    const bind = async (root, readonly) => {
      // Pin the source directory. Replacing its name with a symlink between
      // validation and exec cannot give bwrap a different writable subtree.
      const handle = await open(root, constants.O_RDONLY | constants.O_DIRECTORY | constants.O_NOFOLLOW);
      handles.push(handle);
      prefix.push(readonly ? '--ro-bind' : '--bind', `/proc/self/fd/${handles.length + 2}`, root);
    };
    for (const root of [...writableRoots, scratch]) await bind(root, false);
    for (const root of protectedRoots) await bind(root, true);
    prefix.push('--proc', '/proc', '--dev', '/dev', '--seccomp', '3', '--chdir', cwd,
      '--', '/bin/bash', '--noprofile', '--norc');
    return { file, prefix, cwd, env: environment(scratch), descriptors: handles.map(handle => handle.fd), cleanup };
  } catch (error) { await cleanup(); throw error; }
}
