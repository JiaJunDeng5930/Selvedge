import test from 'node:test';
import { writeFile } from 'node:fs/promises';
import path from 'node:path';
import { specimen, unchanged, check, checked, rejected, replaceOnce } from './locality-support.mjs';

// Challenge the evidence in an isolated copy. Each mutation must still compile
// as a pure UI before the assembled proof rejects it. Production is unchanged.
test('conversation evidence rejects content, audit, error and input-intent faults', { timeout: 240_000 }, async t => {
  const copy = await specimen(t);
  const filename = path.join(copy.directory, 'UI.bend');
  const original = copy.originals.get('UI.bend').toString();
  checked(check(copy.directory));
  const mutations = [
    ['user message omission',
      'case D.UserMessage{text}: [Surface.Text{key, "user", "You", text}]',
      'case D.UserMessage{text}: Nil{}', /speech_prefix|ui_transcript_content/],
    ['incorrect error status',
      'case True{}: Surface.Failed{}', 'case True{}: Surface.Complete{}', /result_value|ui_result_content/],
    ['incorrect audit payload',
      'T.message_json(D.ToolReceipt{owner, operation, call, value, error})',
      'J.Null{}', /ui_audit_content/],
    ['incorrect Steer binding',
      '"Change direction now", "Steer", M.Steer{id, "message"}',
      '"Change direction now", "Steer", M.Send{id, "message"}', /ui_composer_intents/],
    ['incorrect draft ownership',
      'Surface.Composer{"compose", "task/" ++ Nat.show(id)',
      'Surface.Composer{"compose", "shared"', /ui_composer_intents/],
  ];
  for (const [label, before, after, obligation] of mutations) await t.test(label, async () => {
    try {
      await writeFile(filename, replaceOnce(original, before, after));
      checked(check(copy.directory, 'UI.bend'));
      rejected(check(copy.directory), obligation);
      await unchanged(copy, ['UI.bend']);
    } finally { await writeFile(filename, original); }
  });
});
