import test from 'node:test';
import assert from 'node:assert/strict';
import { cp, mkdtemp, readdir, readFile, writeFile, rm } from 'node:fs/promises';
import path from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { compiler } from '../scripts/toolchain.mjs';

test('board evidence rejects type-correct loss of ordering, effects, freshness and dialog behavior', { timeout: 300_000 }, async t => {
  const root = fileURLToPath(new URL('../', import.meta.url));
  const directory = await mkdtemp(path.join(tmpdir(), 'selvedge-board-proof-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  for (const name of await readdir(root)) if (name.endsWith('.bend')) await cp(path.join(root, name), path.join(directory, name));
  await cp(path.join(root, 'bendlib'), path.join(directory, 'bendlib'), { recursive: true });
  const binary = compiler();
  const check = entry => spawnSync(binary, [entry, '--check-only'], {
    cwd: directory, encoding: 'utf8', timeout: 60_000, env: { ...process.env, BEND_NO_TELEMETRY: '1' },
  });
  const baseline = check('PROOF.bend');
  assert.equal(baseline.status, 0, baseline.stdout + baseline.stderr);
  assert.equal(baseline.stdout.trim(), 'All terms check.');
  const mutations = [
    ['ignore the insertion position', 'bendlib/board.bend',
      'B.reposition(id, card, position, S.registry(world))', 'B.reposition(id, card, 0n, S.registry(world))', /change_meaning|reposition_meaning|relocate_meaning/],
    ['discard the cards following an insertion', 'BOARD.bend',
      'List.drop(&2, Finite.Entry(Card), remaining, position)', 'Nil{}', /change_meaning|reposition_meaning|relocate_meaning/],
    ['record drafting without dispatching its effect', 'bendlib/board.bend',
      '[Effects.FeatureEffect{F.RequestBoardText{id, ticket, profile, B.drafting_prompt(retitle, B.draft(card)), retitle}}]', 'Nil{}', /change_meaning|reposition_meaning|relocate_meaning/],
    ['replace a description during title-only generation', 'bendlib/board.bend',
      'B.Draft{title, old_description, stage, priority, owner, project, labels, attachments}',
      'B.Draft{title, description, stage, priority, owner, project, labels, attachments}', /board_boundary|text_meaning|draft_meaning/],
    ['accept an unrelated drafting ticket', 'bendlib/feature-protocol.bend',
      'board_selected_callback(Nat.is_eq(ticket, expected) && Nat.is_eq(version, revision), retitle)',
      'board_selected_callback(True{}, retitle)', /board_boundary/],
  ];
  for (const [label, name, before, after, diagnostic] of mutations) await t.test(label, async () => {
    const filename = path.join(directory, name), original = await readFile(filename, 'utf8');
    assert.equal(original.split(before).length, 2, `${label}: mutation must hit exactly one production expression`);
    try {
      await writeFile(filename, original.replace(before, after));
      const runtime = check('UI.bend');
      assert.equal(runtime.error, undefined, `${label}: operational check must finish`);
      assert.equal(runtime.status, 0, runtime.stdout + runtime.stderr);
      assert.equal(runtime.stdout.trim(), 'All terms check.');
      const proof = check('PROOF.bend');
      assert.equal(proof.error, undefined, `${label}: a timeout is not a rejected proof`);
      assert.notEqual(proof.status, 0, `${label}: assembled proof accepted the defect`);
      assert.match(proof.stdout + proof.stderr, diagnostic);
    } finally { await writeFile(filename, original); }
  });
});
