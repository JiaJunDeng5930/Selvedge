import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { writeFile, unlink, symlink } from 'node:fs/promises';
import { Kernel } from '../host/kernel.mjs';
import { JsonNumber, stringifyJson } from '../host/codec.mjs';
import { boundary } from '../host/public/model-boundary.mjs';
import { snapshotContextFile } from '../host/project.mjs';
import { home } from './support.mjs';

test('full-size text survives file observation, native JSON rendering and Worker transport', async t => {
  const kernel = new Kernel();
  t.after(() => kernel.close());
  const { limits } = await kernel.initialize();
  const definition = boundary('config.context_definitions', {}).find(value => value.kind === 'project_guidance');
  const field = definition.fields.find(value => value.source.type === 'body').name;
  const directory = await home(t);
  const filename = path.join(directory, 'AGENTS.md');
  // The old non-tail native scanner overflowed on the actual 26,575-byte file.
  for (const size of [26_575, limits.project_context_bytes]) {
    const content = 'a'.repeat(size);
    await writeFile(filename, content);
    const observed = await snapshotContextFile(filename, limits);
    assert.equal(boundary('config.context_field', { definition, identity: false, field, value: observed.content }), content);
  }
  const target = path.join(directory, 'source');
  await writeFile(target, 'a'.repeat(limits.project_context_bytes));
  await unlink(filename);
  await symlink(target, filename);
  await assert.rejects(snapshotContextFile(filename, limits), error => ['ELOOP', 'EMLINK'].includes(error.code));

  const text = '🙂'.repeat(262_144) + '\n"\\\u0000';
  const input = [{ role: 'user', content: text }];
  const numbers = { huge: new JsonNumber('9007199254740993'), fraction: new JsonNumber('1.2300') };
  const rendered = boundary('backend.compaction_portable_request', {
    effect: { plan: { output_reserve_tokens: 65_536 } }, request: { input, numbers },
  });
  assert.equal(rendered.input[0].content, text);
  assert.equal(stringifyJson(rendered.numbers), stringifyJson(numbers));
  const configured = await kernel.request({ kind: 'configure', instructions: { configured: '', global: null },
    profiles: [{ key: 'fixture', provider: 'responses', name: 'fixture-model', reasoning_options: null }],
    tools: [], max_fork: 4, max_descendants: 8 });
  assert.equal(configured.value.reply.ok, true);
  assert.equal((await kernel.request({ kind: 'command', command: { op: 'create', profile: 'fixture', message: text } })).value.reply.ok, true);
  const page = await kernel.request({ kind: 'command', command: { op: 'read', task_id: 0 } });
  assert.equal(page.value.reply.result.messages.find(message => message.role === 'user').content, text);
});
