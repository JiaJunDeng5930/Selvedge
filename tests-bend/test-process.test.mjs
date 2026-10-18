import test from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { runTestProcess, terminateTestProcessGroup } from '../scripts/test-process.mjs';

const cwd = fileURLToPath(new URL('../', import.meta.url));

function running(pid) {
  try { process.kill(pid, 0); }
  catch (error) { if (error.code === 'ESRCH') return false; throw error; }
  const state = spawnSync('ps', ['-o', 'stat=', '-p', String(pid)], { encoding: 'utf8' }).stdout.trim();
  // An adopted zombie has exited and closed its descriptors; PID 1 owns its reap.
  return state !== '' && !state.startsWith('Z');
}

test('a normally exiting parent cannot leave descendants holding the test output pipes', async () => {
  const active = new Set();
  const result = await runTestProcess('inherited pipe fixture', ['sh', '-c', 'sleep 300 & printf "descendant=%s\\n" "$!"; exit 0'], { cwd, active });
  assert.equal(result.exitCode, 0);
  assert.equal(result.signal, null);
  assert.equal(active.size, 0);
  const pid = Number(result.out.match(/descendant=(\d+)/)?.[1]);
  assert.ok(pid > 0);
  assert.equal(running(pid), false, 'The owned descendant must terminate');
});

test('explicit cancellation terminates the owned process group and reports a failing signal', async () => {
  const active = new Set();
  const pending = runTestProcess('cancellation fixture', [process.execPath, '--eval', 'setInterval(() => {}, 1000);'], { cwd, active });
  assert.equal(active.size, 1);
  for (const proc of active) terminateTestProcessGroup(proc);
  const result = await pending;
  assert.equal(result.signal, 'SIGKILL');
  assert.notEqual(result.exitCode, 0);
  assert.equal(active.size, 0);
  assert.equal(running(result.pid), false);
});
