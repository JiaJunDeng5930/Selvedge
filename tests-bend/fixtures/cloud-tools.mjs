import { spawn } from 'node:child_process';
import { appendFileSync } from 'node:fs';
import { Transform } from 'node:stream';
import { StringDecoder } from 'node:string_decoder';

const [tool, ...source] = process.argv.slice(2);
const arguments_ = source.map(value => value.replaceAll('/workspace/selvedge/', `${process.env.SELVEDGE_CLOUD_TEST_REMOTE}/`));
let file;
let options;
if (tool === 'git') {
  file = process.env.SELVEDGE_CLOUD_TEST_GIT;
  options = arguments_.map(value => value === 'https://github.com/selvedge-fixture/project.git'
    ? process.env.SELVEDGE_CLOUD_TEST_SOURCE : value);
} else {
  appendFileSync(process.env.SELVEDGE_CLOUD_TEST_SSH_LOG, JSON.stringify(source) + '\n');
  let index = 0;
  while (arguments_[index]?.startsWith('-')) {
    const option = arguments_[index++];
    if (['-o', '-i', '-p', '-l', '-F', '-S', '-J'].includes(option)) index++;
  }
  index++;
  file = '/bin/bash';
  options = ['-c', arguments_.slice(index).join(' ')];
}
// Keep a fixture's remote filesystem isolated while preserving paths in SSH JSON requests and observations.
function substitute(from, to) {
  const decoder = new StringDecoder('utf8');
  let pending = '';
  return new Transform({
    transform(chunk, encoding, callback) {
      pending += decoder.write(chunk);
      let output = '';
      let index;
      while ((index = pending.indexOf(from)) >= 0) {
        output += pending.slice(0, index) + to;
        pending = pending.slice(index + from.length);
      }
      let retained = Math.min(from.length - 1, pending.length);
      while (retained && !pending.endsWith(from.slice(0, retained))) retained--;
      // JSON-lines peers wait for each newline; retain only an actual partial path prefix.
      this.push(output + pending.slice(0, pending.length - retained));
      pending = pending.slice(pending.length - retained);
      callback();
    },
    flush(callback) { this.push((pending + decoder.end()).replaceAll(from, to)); callback(); },
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
