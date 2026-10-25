import { spawn } from 'node:child_process';
import { appendFileSync } from 'node:fs';
import { Transform } from 'node:stream';

const [tool, ...source] = process.argv.slice(2);
const arguments_ = source.map(value => value.replaceAll('/workspace/selvedge/', `${process.env.SELVEDGE_CLOUD_TEST_REMOTE}/`));
let file;
let options;
if (tool === 'base64') {
  // GNU base64 accepts a positional file; the macOS binary requires -i.
  file = 'python3';
  options = ['-c', 'import base64,sys; source=open(sys.argv[1],"rb") if len(sys.argv)>1 else sys.stdin.buffer; sys.stdout.buffer.write(base64.encodebytes(source.read()))', ...arguments_];
} else if (tool === 'setsid') {
  // The loopback SSH fixture runs on macOS as well as Linux. Python invokes
  // the actual POSIX session syscall where the GNU command is unavailable.
  file = 'python3';
  options = ['-c', 'import os,sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])',
    ...arguments_.filter(value => value !== '--wait')];
} else if (tool === 'git') {
  file = process.env.SELVEDGE_CLOUD_TEST_GIT;
  options = arguments_.map(value => value === 'https://github.com/selvedge-fixture/project.git'
    ? process.env.SELVEDGE_CLOUD_TEST_REPOSITORY : value);
} else {
  appendFileSync(process.env.SELVEDGE_CLOUD_TEST_SSH_LOG, JSON.stringify(source) + '\n');
  let index = 0;
  while (arguments_[index]?.startsWith('-')) {
    const option = arguments_[index++];
    if (['-o', '-i', '-p', '-l', '-F', '-S', '-J'].includes(option)) index++;
  }
  index++;
  file = '/bin/bash';
  let command = arguments_.slice(index).join(' ');
  if (process.platform === 'darwin') {
    // Linux exposes the same session observation in /proc; the local fixture
    // obtains the real parent session directly on macOS.
    command = command.replace('read -r pid comm state parent group session rest < /proc/$$/stat;',
      'session=$(python3 -c "import os; print(os.getsid(os.getppid()))");');
    // Loopback commands own a POSIX process group; macOS has no /proc session table.
    command = command.replace(/def terminate_members\(signum\):[\s\S]*?\nterminate_members\(signal\.SIGTERM\)/,
      'def terminate_members(signum):\n    try: os.killpg(session, signum)\n    # DEFENSE: The command may finish before fixture cancellation arrives.\n    except ProcessLookupError: pass\nterminate_members(signal.SIGTERM)');
  }
  options = ['-c', command];
}
// Keep remote paths isolated without decoding SSH's binary byte streams.
function substitute(from, to) {
  const needle = Buffer.from(from);
  const replacement = Buffer.from(to);
  let pending = Buffer.alloc(0);
  return new Transform({
    transform(chunk, encoding, callback) {
      pending = Buffer.concat([pending, chunk]);
      let index;
      while ((index = pending.indexOf(needle)) >= 0) {
        this.push(pending.subarray(0, index));
        this.push(replacement);
        pending = pending.subarray(index + needle.length);
      }
      let retained = Math.min(needle.length - 1, pending.length);
      while (retained && !pending.subarray(pending.length - retained).equals(needle.subarray(0, retained))) retained--;
      // JSON-lines peers wait for each newline; retain only an actual partial path prefix.
      this.push(pending.subarray(0, pending.length - retained));
      pending = pending.subarray(pending.length - retained);
      callback();
    },
    flush(callback) { this.push(pending); callback(); },
  });
}
const child = spawn(file, options, { stdio: tool === 'ssh' ? ['pipe', 'pipe', 'pipe'] : 'inherit' });
if (tool === 'ssh') {
  const local = `${process.env.SELVEDGE_CLOUD_TEST_REMOTE}/`;
  process.stdin.pipe(substitute('/workspace/selvedge/', local)).pipe(child.stdin);
  child.stdout.pipe(substitute(local, '/workspace/selvedge/')).pipe(process.stdout);
  child.stderr.pipe(process.stderr);
}
child.on('error', error => { process.stderr.write(`${error.message}\n`); process.exitCode = 127; });
child.on('exit', (code, signal) => {
  if (tool === 'ssh') {
    // SSH exits when the remote command finishes, even if its caller keeps stdin open.
    process.stdin.unpipe();
    process.stdin.destroy();
  }
  if (signal) process.kill(process.pid, signal);
  else process.exitCode = code;
});
