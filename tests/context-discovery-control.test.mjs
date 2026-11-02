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
