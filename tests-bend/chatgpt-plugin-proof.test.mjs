import test from 'node:test';
import assert from 'node:assert/strict';
import { cp, mkdtemp, readdir, readFile, writeFile, rm } from 'node:fs/promises';
import path from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { compiler } from '../scripts/toolchain.mjs';

const compilerCallBudget = 45_000;
const mutations = [
  ['drop the executable effect', 'bendlib/chatgpt.bend',
    'D.success(G.receipt(id, job)), [G.Execute{id, job}]', 'D.success(G.receipt(id, job)), Nil{}'],
  ['repeat an already accepted operation', 'bendlib/chatgpt.bend',
    'case G.Reuse{id, job}: respond(state, G.receipt(id, job))',
    'case G.Reuse{+id, +job}: C.Decision{state, D.success(G.receipt(id, job)), [G.Execute{id, job}]}'],
  ['give another connection ownership', 'CHATGPT.bend',
    'Nat.is_eq(connection, owner) && Nat.is_eq(project, target)', 'Nat.is_eq(project, target)'],
  ['leave unknown work running on restart', 'CHATGPT.bend',
    'case True{}: with_outcome(Interrupted{"Service restarted; execution may have happened and will not be replayed"}, job)',
    'case True{}: job'],
  ['skip cancelling the physical operation', 'bendlib/chatgpt.bend',
    'D.success(G.receipt(id, job)), [G.Stop{id}]', 'D.success(G.receipt(id, job)), Nil{}'],
  ['silently clear another feature when updating the board', 'FEATURES.bend',
    'C.replace(Board.State, Modules(), value, state)',
    'C.Frame{value, C.Frame{ChatGPT.initial(), rest(state)}}'],
];

// Cover every individual call budget, including the baseline and file cleanup.
test('ChatGPT production evidence rejects type-correct lost effects, cross-connection ownership and replay', { timeout: (1 + 2 * mutations.length) * compilerCallBudget + 15_000 }, async t => {
  const root = fileURLToPath(new URL('../', import.meta.url));
  const directory = await mkdtemp(path.join(tmpdir(), 'selvedge-chatgpt-proof-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  for (const name of await readdir(root)) if (name.endsWith('.bend')) await cp(path.join(root, name), path.join(directory, name));
  for (const name of ['bendlib', 'core', 'webui']) await cp(path.join(root, name), path.join(directory, name), { recursive: true });
  const binary = compiler();
  const check = entry => spawnSync(binary, [entry, '--check-only'], { cwd: directory, encoding: 'utf8',
    timeout: compilerCallBudget, env: { ...process.env, BEND_NO_TELEMETRY: '1' } });
  const baseline = check('PROOF.bend');
  assert.equal(baseline.status, 0, baseline.stdout + baseline.stderr);
  assert.equal(baseline.stdout.trim(), 'ALL PROOFS CHECK\nUse --verdict for mathematical validity.');
  for (const [label, name, before, after] of mutations) await t.test(label, async () => {
    const filename = path.join(directory, name), original = await readFile(filename, 'utf8');
    assert.equal(original.split(before).length, 2, `${label}: mutation must affect exactly one production expression`);
    try {
      await writeFile(filename, original.replace(before, after));
      const runtime = check('UI.bend');
      assert.equal(runtime.error, undefined);
      assert.equal(runtime.status, 0, runtime.stdout + runtime.stderr);
      assert.equal(runtime.stdout.trim(), 'ALL PROOFS CHECK\nUse --verdict for mathematical validity.');
      const proof = check('PROOF.bend');
      assert.equal(proof.error, undefined);
      assert.notEqual(proof.status, 0, `${label}: the root accepted a semantic defect`);
      assert.match(proof.stdout + proof.stderr, /chatgpt|board_preserves|refinement|boundary/);
    } finally { await writeFile(filename, original); }
  });
});
