import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdir, symlink, unlink, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { home } from './support.mjs';
import { answer, filesystemServer } from './fixtures/filesystem-boundaries-server.mjs';

function guidanceEvents(request) {
  return request.input.filter(item => typeof item.content === 'string'
    && item.content.startsWith('Committed context object ')).map(item => {
    const lines = item.content.split('\n');
    return { kind: lines[0], key: JSON.parse(lines[1].slice('Context: '.length)), content: item.content };
  }).filter(item => item.key.type === 'directory_guidance');
}

function currentContent(events, filename) {
  let content;
  for (const event of events.filter(item => item.key.identity.path === filename)) {
    if (event.kind === 'Committed context object introduced.') {
      content = event.content.split('Field: content\n')[1].split('\nField: ')[0].trimEnd();
    } else if (event.kind === 'Committed context object removed.') content = undefined;
    else if (event.kind === 'Committed context object update.') {
      const patch = event.content.split('Field: content\n')[1]?.split('\nField: ')[0];
      if (patch === undefined) continue;
      const characters = [...content];
      const edits = [...patch.matchAll(/^@@ code point (\d+) @@\n- (.+)\n\+ (.+)$/gm)];
      for (const [, position, removed, inserted] of edits.reverse()) {
        const start = Number(position), previous = [...JSON.parse(removed)];
        assert.equal(characters.slice(start, start + previous.length).join(''), previous.join(''));
        characters.splice(start, previous.length, ...JSON.parse(inserted));
      }
      content = characters.join('');
    }
  }
  return content;
}

test('guidance discovery orders directories and withdraws missing members only after a complete successful scan', async t => {
  const directory = await home(t);
  const workspace = path.join(directory, 'workspace');
  const names = ['zeta', 'alpha', 'middle'];
  await mkdir(path.join(workspace, '.git'), { recursive: true });
  for (const name of names) {
    await mkdir(path.join(workspace, name));
    await writeFile(path.join(workspace, name, 'AGENTS.md'), `ACCEPTED-${name}`);
  }
  const fixture = await filesystemServer(t, { directory, cwd: workspace, respond: () => answer('Observed.') });
  const { task_id } = await fixture.command({ op: 'create', profile: fixture.profile,
    message: 'Observe project guidance.', settings: { workspace: { roots: [workspace], primary_root: workspace } } });
  await fixture.idle(task_id);
  const first = guidanceEvents(fixture.upstream.requests[0]);
  const filename = name => path.join(workspace, name, 'AGENTS.md');
  assert.deepEqual(first.map(item => item.key.identity.path), ['alpha', 'middle', 'zeta'].map(filename));

  await unlink(filename('alpha'));
  await writeFile(filename('middle'), 'UPDATE-AFTER-COMPLETE-SCAN');
  const outside = path.join(directory, 'outside.md');
  await writeFile(outside, 'OUTSIDE-SOURCE');
  await unlink(filename('zeta'));
  await symlink(outside, filename('zeta'));
  await fixture.command({ op: 'send', task_id, message: 'Observe an incomplete scan.' });
  await fixture.idle(task_id);
  const failed = guidanceEvents(fixture.upstream.requests[1]);
  assert.equal(failed.some(item => item.kind === 'Committed context object removed.'), false);
  assert.equal(currentContent(failed, filename('alpha')), 'ACCEPTED-alpha');
  assert.equal(currentContent(failed, filename('middle')), 'ACCEPTED-middle');

  await unlink(filename('zeta'));
  await writeFile(filename('zeta'), 'RECOVERED-zeta');
  await fixture.command({ op: 'send', task_id, message: 'Observe the completed replacement scan.' });
  await fixture.idle(task_id);
  const recovered = guidanceEvents(fixture.upstream.requests[2]);
  assert.deepEqual(recovered.filter(item => item.kind === 'Committed context object removed.')
    .map(item => item.key.identity.path), [filename('alpha')]);
  assert.equal(currentContent(recovered, filename('alpha')), undefined);
  assert.equal(currentContent(recovered, filename('middle')), 'UPDATE-AFTER-COMPLETE-SCAN');
  assert.equal(currentContent(recovered, filename('zeta')), 'RECOVERED-zeta');
});
