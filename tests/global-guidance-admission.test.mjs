import test from 'node:test';
import assert from 'node:assert/strict';
import { Kernel } from '../host/kernel.mjs';
import { snapshotGlobalInstructions } from '../host/project.mjs';
import { writeFile } from 'node:fs/promises';
import path from 'node:path';
import { home } from './support.mjs';

test('global guidance is admitted as the same revisioned context snapshot used by task creation', async t => {
  const kernel = new Kernel();
  t.after(() => kernel.close());
  const { limits } = await kernel.initialize();
  const directory = await home(t);
  await writeFile(path.join(directory, 'AGENTS.md'), 'Accepted global instructions');
  const observed = await snapshotGlobalInstructions(directory, limits);
  assert.ok(observed);
  const packet = async input => (await kernel.request(input)).value;
  const configuration = global => ({ kind: 'configure',
    profiles: [{ key: 'fixture', provider: 'openai', name: 'fixture-model', reasoning_options: null }],
    tools: [], plugins: [], max_fork: 4, max_descendants: 64,
    instructions: { configured: '', global },
  });
  assert.equal((await packet(configuration(observed))).reply.ok, true);
  const refused = await packet(configuration({ ...observed, revision: '', content: 'Rejected global instructions' }));
  assert.equal(refused.reply.ok, false);
  assert.equal(refused.reply.error.code, 'invalid_input');
  assert.deepEqual(refused.effects, []);

  const created = await packet({ kind: 'command', command: {
    op: 'create', profile: 'fixture', message: 'Use the accepted context.',
  } });
  assert.equal(created.reply.ok, true, JSON.stringify(created.reply));
  const read = await packet({ kind: 'command', command: { op: 'read', task_id: created.reply.result.task_id } });
  const history = JSON.stringify(read.reply.result.messages);
  assert.ok(history.includes(observed.revision));
  assert.ok(history.includes('Accepted global instructions'));
  assert.equal(history.includes('Rejected global instructions'), false);
});
