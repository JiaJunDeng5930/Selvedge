import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdir, symlink, unlink, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { home } from './support.mjs';
import { answer, filesystemServer } from './fixtures/filesystem-boundaries-server.mjs';
import { contextChanges, contextContent } from './fixtures/context-observations.mjs';

test('guidance discovery orders directories and withdraws missing members only after a complete successful scan', async t => {
  const directory = await home(t);
  const workspace = path.join(directory, 'workspace');
  const names = ['zeta', 'alpha', 'middle'];
  await mkdir(path.join(workspace, '.git'), { recursive: true });
  for (const name of names) {
    await mkdir(path.join(workspace, name));
    await writeFile(path.join(workspace, name, 'AGENTS.md'), `ACCEPTED-${name.toUpperCase()}`);
  }
  const fixture = await filesystemServer(t, { directory, cwd: workspace, respond: () => answer('Observed.') });
  const { task_id } = await fixture.command({ op: 'create', profile: fixture.profile,
    message: 'Observe project guidance.', settings: { workspace: { roots: [workspace], primary_root: workspace } } });
  const first = contextChanges(await fixture.idle(task_id), 'directory_guidance');
  for (const name of names) assert.ok(JSON.stringify(fixture.upstream.requests[0]).includes(`ACCEPTED-${name.toUpperCase()}`));
  const filename = name => path.join(workspace, name, 'AGENTS.md');
  assert.deepEqual(first.map(item => item.key.identity.path), ['alpha', 'middle', 'zeta'].map(filename));

  await unlink(filename('alpha'));
  // Distinct alphabets keep the new provider value observable without parsing prompt typography.
  await writeFile(filename('middle'), 'updated after complete scan');
  const outside = path.join(directory, 'outside.md');
  await writeFile(outside, 'OUTSIDE-SOURCE');
  await unlink(filename('zeta'));
  await symlink(outside, filename('zeta'));
  await fixture.command({ op: 'send', task_id, message: 'Observe an incomplete scan.' });
  const failed = contextChanges(await fixture.idle(task_id), 'directory_guidance');
  assert.equal(failed.some(item => item.type === 'remove'), false);
  assert.equal(contextContent(failed, filename('alpha')), 'ACCEPTED-ALPHA');
  assert.equal(contextContent(failed, filename('middle')), 'ACCEPTED-MIDDLE');

  await unlink(filename('zeta'));
  await writeFile(filename('zeta'), 'recovered guidance');
  await fixture.command({ op: 'send', task_id, message: 'Observe the completed replacement scan.' });
  const recovered = contextChanges(await fixture.idle(task_id), 'directory_guidance');
  assert.deepEqual(recovered.filter(item => item.type === 'remove')
    .map(item => item.key.identity.path), [filename('alpha')]);
  assert.equal(contextContent(recovered, filename('alpha')), undefined);
  assert.equal(contextContent(recovered, filename('middle')), 'updated after complete scan');
  assert.equal(contextContent(recovered, filename('zeta')), 'recovered guidance');
  for (const text of ['updated after complete scan', 'recovered guidance']) {
    assert.ok(JSON.stringify(fixture.upstream.requests[2]).includes(text), 'The actual provider receives the newly observed guidance');
  }
});

test('a tool cycle refreshes known context files and discovers new files on the next user message', async t => {
  const directory = await home(t);
  const workspace = path.join(directory, 'workspace');
  const existing = path.join(workspace, 'known');
  const added = path.join(workspace, 'new-module', '.agents', 'skills', 'new-skill');
  const existingSkill = path.join(existing, '.agents', 'skills', 'known-skill');
  await mkdir(path.join(workspace, '.git'), { recursive: true });
  await mkdir(existingSkill, { recursive: true });
  // Disjoint characters keep the replacement intact in the generated context edit.
  await writeFile(path.join(existing, 'AGENTS.md'), 'aaaa');
  const skill = (name, description) => `---\nname: ${name}\ndescription: ${description}\n---\nRead the rule.\n`;
  await writeFile(path.join(existingSkill, 'SKILL.md'), skill('known-skill', 'aaaa'));
  let taskId;
  const fixture = await filesystemServer(t, { directory, cwd: workspace, respond: async (_body, index) => {
    if (index !== 0) return answer('Observed.');
    await writeFile(path.join(existing, 'AGENTS.md'), 'RULE UPDATED MID TURN');
    await writeFile(path.join(existingSkill, 'SKILL.md'), skill('known-skill', 'SKILL UPDATED MID TURN'));
    await mkdir(added, { recursive: true });
    await writeFile(path.join(workspace, 'new-module', 'AGENTS.md'), 'A new rule discovered on the next message.');
    await writeFile(path.join(added, 'SKILL.md'), skill('new-skill', 'A new skill discovered on the next message.'));
    return [{ type: 'function_call', name: 'read_task', call_id: 'during-context-turn',
      arguments: JSON.stringify({ task_id: taskId, limit: 1 }) }];
  } });
  ({ task_id: taskId } = await fixture.command({ op: 'create_idle', profile: fixture.profile,
    settings: { workspace: { roots: [workspace], primary_root: workspace } } }));
  await fixture.command({ op: 'send', task_id: taskId, message: 'Run one tool before completing this message.' });
  await fixture.idle(taskId, { completed: () => fixture.upstream.requests.length >= 2 });
  const resumed = JSON.stringify(fixture.upstream.requests[1].input);
  assert.ok(resumed.includes('RULE UPDATED MID TURN'), resumed);
  assert.ok(resumed.includes('SKILL UPDATED MID TURN'), resumed);
  assert.ok(!resumed.includes('A new rule discovered on the next message.'));
  assert.ok(!resumed.includes('A new skill discovered on the next message.'));

  await fixture.command({ op: 'send', task_id: taskId, message: 'Observe the rule files added during the previous message.' });
  await fixture.idle(taskId, { completed: () => fixture.upstream.requests.length >= 3 });
  const next = JSON.stringify(fixture.upstream.requests[2].input);
  assert.ok(next.includes('A new rule discovered on the next message.'));
  assert.ok(next.includes('A new skill discovered on the next message.'));
});
