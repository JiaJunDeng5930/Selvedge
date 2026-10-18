import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdir, realpath, symlink, unlink, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { observeContextSources } from '../host/context-sources.mjs';
import { snapshotProject } from '../host/project.mjs';
import { boundary } from '../host/public/model-boundary.mjs';
import { home } from './support.mjs';

test('filesystem discovery respects Git-file boundaries and retains an accepted collection after a source becomes a link', async t => {
  const base = await realpath(await home(t));
  const state = path.join(base, 'state');
  const repository = path.join(base, 'checkout');
  const primary = path.join(repository, 'packages', 'app');
  const nested = path.join(primary, 'src');
  const second = path.join(base, 'second');
  const write = async (filename, content) => {
    await mkdir(path.dirname(filename), { recursive: true });
    await writeFile(filename, content);
    return filename;
  };
  await mkdir(path.join(second, '.git'), { recursive: true });
  // Linked worktrees use a file marker; guidance above it must not enter context.
  await write(path.join(repository, '.git'), 'gitdir: /not-traversed\n');
  await write(path.join(base, 'AGENTS.md'), 'OUTSIDE-GIT-BOUNDARY');
  await write(path.join(repository, 'AGENTS.md'), 'Repository guidance');
  await write(path.join(primary, 'AGENTS.md'), 'Superseded primary guidance');
  const override = await write(path.join(primary, 'AGENTS.override.md'), 'Primary override');
  const nestedGuidance = await write(path.join(nested, 'AGENTS.md'), 'Nested guidance');
  await write(path.join(second, 'AGENTS.md'), 'Second root guidance');
  const global = await write(path.join(state, 'AGENTS.md'), 'Global guidance');
  const skill = '---\nname: fixture\ndescription: Read fixture metadata\n---\nPRIVATE-SKILL-BODY';
  const explicit = await write(path.join(repository, '.agents', 'skills', 'explicit', 'SKILL.md'), skill);
  const automatic = await write(path.join(nested, '.claude', 'skills', 'automatic', 'SKILL.md'), skill);
  await write(path.join(state, 'skills', 'user', 'SKILL.md'), skill);
  const outside = path.join(base, 'outside');
  await write(path.join(outside, 'AGENTS.md'), 'DIRECTORY-LINK-MUST-NOT-BE-FOLLOWED');
  await symlink(outside, path.join(primary, 'linked'));

  const limits = { project_context_bytes: 32768 };
  const definitions = boundary('config.context_definitions', {});
  const config = validateConfig({ ...defaultConfig, skills: [explicit] });
  const settings = { workspace: { roots: [primary, second], primary_root: primary } };
  let bindings = [];
  const observe = () => observeContextSources({ definitions, bindings, settings }, { home: state, config, limits });
  const first = await observe();
  assert.equal(first.some(item => item.type === 'failure'), false, JSON.stringify(first));
  bindings = first.filter(item => item.type === 'present').map(item => item.snapshot);
  const observed = filename => bindings.find(item => (item.value.fields.path ?? item.key.identity.path) === filename);
  assert.deepEqual(bindings.filter(item => item.key.type === 'directory_guidance').map(item => item.value.fields.path).sort(),
    [path.join(repository, 'AGENTS.md'), nestedGuidance, path.join(second, 'AGENTS.md')].sort());
  assert.equal(observed(override).key.type, 'project_guidance');
  assert.equal((await snapshotProject(primary, limits)).path, override);
  assert.equal(bindings.filter(item => item.value.fields.path === explicit).length, 1);
  assert.equal(observed(explicit).key.type, 'skill_information');
  assert.equal(observed(automatic).value.fields.applies_to, nested);
  assert.ok(bindings.some(item => item.key.type === 'user_skill_information'));
  for (const hidden of ['OUTSIDE-GIT-BOUNDARY', 'DIRECTORY-LINK-MUST-NOT-BE-FOLLOWED', 'PRIVATE-SKILL-BODY', 'Superseded primary guidance']) {
    assert.equal(JSON.stringify(bindings).includes(hidden), false);
  }

  // The linked source makes the scan incomplete; its accepted peers remain bound.
  await unlink(nestedGuidance);
  await symlink(path.join(repository, 'AGENTS.md'), nestedGuidance);
  await writeFile(global, 'Independent global update');
  const failed = await observe();
  const accepted = bindings.filter(item => item.key.type === 'directory_guidance');
  assert.deepEqual(failed.filter(item => item.key?.type === 'directory_guidance').map(item => item.key), accepted.map(item => item.key));
  assert.ok(failed.filter(item => item.key?.type === 'directory_guidance').every(item => item.type === 'failure'));
  assert.ok(failed.some(item => item.type === 'present' && item.snapshot.key.type === 'global_agents'
    && item.snapshot.value.fields.content === 'Independent global update'));
});
