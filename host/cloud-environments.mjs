import { execFile, spawn } from 'node:child_process';
import { promisify } from 'node:util';
import { randomUUID, createHash } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import path from 'node:path';
import { tencentCvmBackend } from './tencent-cvm.mjs';

const executeFile = promisify(execFile);
export const shellQuote = value => `'${String(value).replaceAll("'", "'\\''")}'`;

export function cloudEnvironmentBackend(cloud) {
  if (cloud?.backend !== 'tencent_cvm' || !cloud.tencent_cvm) throw new Error('Cloud workspace backend is not configured');
  const settings = structuredClone(cloud.tencent_cvm);
  return { ...tencentCvmBackend(settings), settings };
}

const filesystemProgram = String.raw`
import sys, os, json, stat, base64, errno
def facts(value):
    return dict(mode=value.st_mode, size=value.st_size, mtimeMs=value.st_mtime_ns / 1000000, ctimeMs=value.st_ctime_ns / 1000000)
def observed(operation):
    try: return dict(value=operation())
    except OSError as error: return dict(error=dict(code=errno.errorcode.get(error.errno, 'EIO'), message=str(error)))
def request(value):
    op, filename = value['operation'], value['filename']
    if op == 'prefetchDirectory':
        result = dict(lstat={}, realpath={}, readdir={})
        result['lstat'][filename] = observed(lambda: facts(os.lstat(filename)))
        result['realpath'][filename] = observed(lambda: (os.stat(filename), os.path.realpath(filename))[1])
        directory = result['lstat'][filename].get('value')
        # DEFENSE: Discovery rejects symlinked/noncanonical directories before enumerating their target.
        if not directory or not stat.S_ISDIR(directory['mode']) or result['realpath'][filename].get('value') != filename:
            return result
        entries = []
        def scan():
            with os.scandir(filename) as children:
                for entry in children:
                    child = os.path.join(filename, entry.name)
                    observation = observed(lambda: facts(entry.stat(follow_symlinks=False)))
                    result['lstat'][child] = observation
                    result['realpath'][child] = observed(lambda: (os.stat(child), os.path.realpath(child))[1])
                    if 'value' in observation: entries.append(dict(name=entry.name, **observation['value']))
                    if len(entries) > value['maximum']: break
            return entries
        result['readdir'][filename] = observed(scan)
        for candidate in value['candidates']:
            child = os.path.join(filename, candidate)
            result['lstat'][child] = observed(lambda: facts(os.lstat(child)))
            result['realpath'][child] = observed(lambda: (os.stat(child), os.path.realpath(child))[1])
        return result
    if op == 'realpath':
        os.stat(filename)
        return os.path.realpath(filename)
    if op == 'lstat': return facts(os.lstat(filename))
    if op == 'stat': return facts(os.stat(filename))
    if op == 'readdir':
        with os.scandir(filename) as entries:
            return [dict(name=entry.name, **facts(entry.stat(follow_symlinks=False))) for entry in entries]
    if op == 'readFile':
        flags = os.O_RDONLY | os.O_NONBLOCK | (os.O_NOFOLLOW if value.get('noFollow') else 0)
        with os.fdopen(os.open(filename, flags), 'rb') as file:
            before = os.fstat(file.fileno())
            if not stat.S_ISREG(before.st_mode): raise OSError(errno.EINVAL, 'Remote path must be a regular file', filename)
            data = file.read(value['maximum'] + 1)
            after = os.fstat(file.fileno())
            if (before.st_size, before.st_mtime_ns, before.st_ctime_ns) != (after.st_size, after.st_mtime_ns, after.st_ctime_ns):
                raise OSError(errno.EAGAIN, 'Remote file changed while being read', filename)
            return base64.b64encode(data).decode('ascii')
    raise ValueError('Unknown remote filesystem operation')
for line in sys.stdin:
    value = json.loads(line)
    try: result = dict(id=value['id'], ok=True, value=request(value))
    except OSError as error: result = dict(id=value['id'], ok=False, error=dict(code=errno.errorcode.get(error.errno, 'EIO'), message=str(error)))
    except Exception as error: result = dict(id=value['id'], ok=False, error=dict(code='remote_filesystem_failed', message=str(error)))
    print(json.dumps(result), flush=True)
`;

const cancelSessionProgram = String.raw`
import os, sys, signal, time
with open(sys.argv[1]) as marker:
    session = int(marker.read())
def terminate_members(signum):
    for name in os.listdir('/proc'):
        if not name.isdecimal(): continue
        try:
            with open('/proc/' + name + '/stat') as source: value = source.read()
        # DEFENSE: A process can exit between enumerating /proc and reading its session.
        except (FileNotFoundError, ProcessLookupError): continue
        fields = value[value.rfind(')') + 2:].split()
        if int(fields[3]) != session: continue
        try: os.kill(int(name), signum)
        # DEFENSE: An observed session member can exit before its cancellation signal arrives.
        except ProcessLookupError: pass
terminate_members(signal.SIGTERM)
time.sleep(0.2)
terminate_members(signal.SIGKILL)
`;

function fileFacts(value) {
  return { ...value, isFile: () => (value.mode & 0o170000) === 0o100000,
    isDirectory: () => (value.mode & 0o170000) === 0o040000,
    isSymbolicLink: () => (value.mode & 0o170000) === 0o120000 };
}

/** One SSH session serves a complete scan, rather than a handshake per path. */
function remoteFilesystem(connection, signal) {
  let child, nextId = 0, idle;
  const cached = { lstat: new Map(), realpath: new Map(), readdir: new Map() };
  function close() {
    clearTimeout(idle);
    child?.stdin.end();
    child = undefined;
    for (const entries of Object.values(cached)) entries.clear();
  }
  function opened() {
    if (child) return child;
    const current = spawn('ssh', [...connection, `exec python3 -u -c ${shellQuote(filesystemProgram)}`],
      { stdio: ['pipe', 'pipe', 'pipe'] });
    child = current;
    let buffered = '', stderr = '';
    const pending = new Map();
    current.pending = pending;
    const aborted = () => { failed(signal.reason); current.kill(); };
    signal?.addEventListener('abort', aborted, { once: true });
    current.stdout.setEncoding('utf8');
    current.stdout.on('data', chunk => {
      buffered += chunk;
      let newline;
      while ((newline = buffered.indexOf('\n')) !== -1) {
        const line = buffered.slice(0, newline); buffered = buffered.slice(newline + 1);
        let result;
        try { result = JSON.parse(line); }
        catch (error) { failed(error); current.kill(); return; }
        const waiter = pending.get(result.id);
        if (!waiter) { failed(new Error('Unexpected cloud filesystem response identity')); current.kill(); return; }
        pending.delete(result.id);
        clearTimeout(waiter.timer);
        if (result.ok) waiter.resolve(result.value);
        else waiter.reject(Object.assign(new Error(result.error.message), { code: result.error.code }));
        if (!pending.size) { idle = setTimeout(close, 2000); idle.unref(); }
      }
    });
    current.stderr.on('data', chunk => { stderr = (stderr + chunk).slice(-8192); });
    function failed(error) {
      for (const waiter of pending.values()) { clearTimeout(waiter.timer); waiter.reject(error); }
      pending.clear();
      if (child === current) child = undefined;
    }
    current.on('error', failed);
    current.stdin.on('error', failed);
    current.on('exit', code => {
      signal?.removeEventListener('abort', aborted);
      // DEFENSE: Spot reclamation or SSH loss can interrupt an in-flight file observation.
      if (pending.size) failed(new Error(`Cloud filesystem connection closed (${code}): ${stderr}`));
      if (child === current) child = undefined;
    });
    return current;
  }
  function request(operation, filename, options = {}) {
    signal?.throwIfAborted();
    clearTimeout(idle);
    const current = opened(), id = ++nextId;
    return new Promise((resolve, reject) => {
      // DEFENSE: A disconnected SSH channel or a remote filesystem read can stall without producing a response.
      const timer = setTimeout(() => { current.kill(); reject(new Error('Cloud filesystem observation deadline exceeded')); }, 30_000);
      timer.unref();
      current.pending.set(id, { resolve, reject, timer });
      current.stdin.write(JSON.stringify({ id, operation, filename, ...options }) + '\n');
    });
  }
  async function observation(operation, filename) {
    const stored = cached[operation].get(filename);
    if (!stored) return request(operation, filename);
    if (stored.error) throw Object.assign(new Error(stored.error.message), { code: stored.error.code });
    return stored.value;
  }
  const filesystem = {
    close,
    async prefetchDirectory(filename, { candidates = [], maximum = 100_000 } = {}) {
      const result = await request('prefetchDirectory', filename, { candidates, maximum });
      for (const [operation, entries] of Object.entries(result)) {
        for (const [name, value] of Object.entries(entries)) cached[operation].set(name, value);
      }
    },
    realpath: filename => observation('realpath', filename),
    lstat: async filename => fileFacts(await observation('lstat', filename)),
    stat: async filename => fileFacts(await request('stat', filename)),
    async readFile(filename, options = {}) {
      const value = await request('readFile', filename, { maximum: options.maximum ?? 64 * 1024 * 1024, noFollow: Boolean(options.noFollow) });
      const bytes = Buffer.from(value, 'base64');
      return typeof options === 'string' ? bytes.toString(options) : options.encoding ? bytes.toString(options.encoding) : bytes;
    },
    async readdir(filename, options = {}) {
      const entries = await observation('readdir', filename);
      return options.withFileTypes ? entries.map(entry => ({ name: entry.name, ...fileFacts(entry) })) : entries.map(entry => entry.name);
    },
    async opendir(filename) {
      const entries = await filesystem.readdir(filename, { withFileTypes: true });
      return { async *[Symbol.asyncIterator]() { yield* entries; }, async close() {} };
    },
  };
  return filesystem;
}

/** SSH carries only commands and their streams; host credentials are never forwarded. */
export function cloudExecutionEnvironment(receipt, { knownHosts, signal }) {
  const settings = receipt.settings;
  const connection = ['-F', '/dev/null', '-o', 'BatchMode=yes', '-o', 'IdentitiesOnly=yes', '-o', 'ConnectTimeout=10',
    '-o', 'ServerAliveInterval=15', '-o', 'ServerAliveCountMax=3', '-o', 'StrictHostKeyChecking=accept-new',
    '-o', `UserKnownHostsFile=${knownHosts}`, '-i', settings.ssh_private_key,
    '-p', String(settings.ssh_port ?? 22), `${settings.ssh_user ?? 'root'}@${receipt.host}`];
  const filesystem = remoteFilesystem(connection, signal);

  async function execute(command, { signal, maxBuffer = 16 * 1024 * 1024, input, timeout = 120_000 } = {}) {
    const child = executeFile('ssh', [...connection, command], { signal, maxBuffer, timeout, encoding: 'utf8' });
    child.child.stdin.end(input);
    try { const result = await child; return { ...result, exit_code: 0 }; }
    catch (error) {
      // DEFENSE: A remote command's nonzero exit is an execution result, while launch/transport I/O errors still throw.
      if (Number.isInteger(error.code)) return { stdout: error.stdout ?? '', stderr: error.stderr ?? '', exit_code: error.code };
      throw error;
    }
  }

  return {
    kind: 'cloud', backend: receipt.backend, task_id: receipt.task_id, root: receipt.root, filesystem, execute,
    readFile: (filename, options) => filesystem.readFile(filename, options),
    async ready({ signal, deadline }) {
      while (Date.now() < deadline) {
        signal?.throwIfAborted();
        const result = await execute('command -v bash >/dev/null && command -v git >/dev/null && command -v setsid >/dev/null',
          { signal, timeout: Math.min(15_000, Math.max(1, deadline - Date.now())) });
        if (result.exit_code === 0) return;
        // DEFENSE: RUNNING precedes SSH daemon/cloud-init readiness on a newly booting CVM image.
        if (result.exit_code !== 255) throw new Error(`Cloud image requires bash, git and setsid: ${result.stderr}`);
        await delay(Math.min(2000, Math.max(1, deadline - Date.now())), undefined, { signal });
      }
      throw new Error('Cloud SSH startup deadline exceeded');
    },
    async prepareBash(arguments_, execution, { signal } = {}) {
      signal?.throwIfAborted();
      const cwd = execution.workspace.primary_root ?? receipt.root;
      const directory = `/tmp/selvedge-process-${randomUUID()}`;
      const marker = `${directory}/session`, cancelledPath = `${directory}/cancelled`;
      const reserved = await execute(`mkdir -m 700 -- ${shellQuote(directory)}`, { signal, timeout: 15_000 });
      if (reserved.exit_code !== 0) throw new Error(`Cloud process reservation failed: ${reserved.stderr}`);
      // Reserve before spawn: cancellation can arrive while SSH is connecting, before a process session exists.
      const body = `set -e; read -r pid comm state parent group session rest < /proc/$$/stat; ` +
        `printf '%s\\n' "$session" > ${shellQuote(marker + '.tmp')}; mv -- ${shellQuote(marker + '.tmp')} ${shellQuote(marker)}; ` +
        `test ! -e ${shellQuote(cancelledPath)} || exit 0; ` +
        `exec bash -c ${shellQuote(arguments_.command)}`;
      // OpenSSH already owns the PTY session and controlling terminal; pipes need a distinct, waited process group.
      const command = `cd ${shellQuote(cwd)} && exec ${arguments_.mode === 'pty' ? 'bash' : 'setsid --wait bash'} -c ${shellQuote(body)}`;
      let cancelled;
      async function cancel() {
        // Job control creates new process groups; cancellation owns the complete SSH/Bash session.
        cancelled ??= execute(`if test -d ${shellQuote(directory)}; then : > ${shellQuote(cancelledPath)}; ` +
          `if test -f ${shellQuote(marker)}; then python3 -c ${shellQuote(cancelSessionProgram)} ${shellQuote(marker)}; fi; fi`,
        { timeout: 15_000 }).then(result => {
          if (result.exit_code !== 0) throw new Error(`Cloud process cancellation failed: ${result.stderr}`);
        });
        return cancelled;
      }
      return { file: 'ssh', prefix: [...(arguments_.mode === 'pty' ? ['-tt'] : []), ...connection], command: [command],
        cwd: undefined, env: process.env, descriptors: [], cancel,
        async cleanup() {
          try { await cancel(); }
          finally {
            const removed = await execute(`rm -rf -- ${shellQuote(directory)}`, { timeout: 15_000 });
            if (removed.exit_code !== 0) throw new Error(`Cloud process marker cleanup failed: ${removed.stderr}`);
          }
        } };
    },
    async snapshotProject(limits, { signal } = {}) {
      for (const name of ['AGENTS.override.md', 'AGENTS.md']) {
        const filename = path.posix.join(receipt.workspace?.primary_root ?? receipt.root, name);
        let bytes;
        try { bytes = await filesystem.readFile(filename, { maximum: limits.project_context_bytes, noFollow: true }); }
        catch (error) {
          // DEFENSE: A repository may omit its optional project guidance file.
          if (error.code === 'ENOENT') continue;
          throw error;
        }
        signal?.throwIfAborted();
        if (bytes.length > limits.project_context_bytes) throw new Error('Cloud project guidance exceeds the context byte limit');
        return { workspace: receipt.workspace?.primary_root ?? receipt.root, path: filename,
          revision: createHash('sha256').update(bytes).digest('hex'), instructions: new TextDecoder('utf-8', { fatal: true }).decode(bytes) };
      }
      return { workspace: receipt.workspace?.primary_root ?? receipt.root, path: '', revision: 'absent', instructions: '' };
    },
  };
}
