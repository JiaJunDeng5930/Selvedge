import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdir, realpath, unlink, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { compileJavaScript } from '../scripts/compile-javascript.mjs';
import { auditComponents } from '../scripts/check-components.mjs';
import { Kernel } from '../host/kernel.mjs';
import { specimen, unchanged } from './locality-support.mjs';
import { definitionAssembly, extendTrackedContexts } from './fixtures/context-definitions.mjs';

const contextChanges = page => page.messages.filter(item => item.type === 'context_change').map(item => item.change);
const fixtureKind = key => ['review_notes', 'review_policy'].includes(key.type);
const keyOf = change => change.type === 'introduce' ? change.snapshot.key : change.key;
const fixtureChanges = page => contextChanges(page).filter(change => fixtureKind(keyOf(change)));
const metadata = (runner, rationale, mode, body = 'PRIVATE-REVIEW-BODY') =>
  `---\nrunner: ${runner}\nrationale: ${rationale}\nmode: ${mode}\n---\n${body}\n`;

test('text and record definitions extend actual observation, history and provider execution with all existing consumers frozen', { timeout: 420_000 }, async t => {
  const copy = await specimen(t);
  const { entry, module } = await extendTrackedContexts(copy);
  const audit = await auditComponents(copy.directory);
  assert.equal(audit.ok, true, audit.errors.join('\n'));
  await unchanged(copy, [definitionAssembly]);
  await compileJavaScript({ entry, output: module, sourceRoot: copy.directory,
    exports: { initial: 'initial', packet: 'packet', envelope: 'envelope', show: 'show', state: 'state', run: 'run' } });
  const [{ observeContextSources }, { defaultConfig, validateConfig }, { responseBody }] = await Promise.all([
    import(pathToFileURL(path.join(copy.directory, 'host/context-sources.mjs')).href),
    import(pathToFileURL(path.join(copy.directory, 'host/config.mjs')).href),
    import(pathToFileURL(path.join(copy.directory, 'host/providers.mjs')).href),
  ]);
  const kernel = new Kernel({ module, timeout: 15_000 });
  t.after(() => kernel.close());
  const description = await kernel.initialize();
  const send = async input => (await kernel.request(input)).value;
  const command = command => send({ kind: 'command', command });
  const serviceHome = path.join(copy.directory, 'service-home');
  const workspace = path.join(copy.directory, 'workspace');
  await mkdir(serviceHome); await mkdir(workspace);
  const root = await realpath(workspace);
  const textPath = path.join(root, '.review.md');
  const recordPath = path.join(root, '.review-policy.md');
  const originalText = 'Keep 🧵 the unchanged review prefix.\nUse npm.\nKeep the unchanged review tail.\n';
  const updatedText = 'Keep 🧵 the unchanged review prefix.\nUse bun.\nKeep the unchanged review tail.\n';
  await writeFile(textPath, originalText);
  await writeFile(recordPath, metadata('npm test', 'Review changed modules.', 'strict'));
  const instructions = 'Use the task workspace.';
  const config = validateConfig({ ...defaultConfig, instructions });
  assert.equal((await send({ kind: 'configure', instructions: { configured: instructions, global: null },
    project: { workspace: root, path: '', revision: 'absent', instructions: '' },
    profiles: [{ key: 'fixture', provider: 'responses', name: 'fixture-model', reasoning_options: null }],
    tools: [], max_fork: 4, max_descendants: 8 })).reply.ok, true);

  async function settle(decision, selectedTask) {
    const pending = [...decision.effects];
    let transitions = 0;
    const observed = new Map();
    let selected;
    while (pending.length) {
      assert.ok(transitions++ < 30, 'Task effects must settle within the bounded fixture model calls');
      const effect = pending.shift();
      let completed;
      if (effect.kind === 'observe_context') {
        for (const kind of ['review_notes', 'review_policy']) {
          assert.ok(effect.definitions.some(definition => definition.kind === kind));
        }
        const observations = await observeContextSources(effect, { home: serviceHome, config, limits: description.limits });
        observed.set(effect.task_id, observations);
        completed = await send({ kind: 'context_observed', task_id: effect.task_id, ticket: effect.ticket, ok: true, observations });
      } else {
        assert.equal(effect.kind, 'model');
        const body = responseBody(effect);
        assert.equal(JSON.stringify(body).includes('PRIVATE-REVIEW-BODY'), false);
        if (effect.task_id === selectedTask) selected = { model: effect, body, observations: observed.get(selectedTask) };
        completed = await send({ kind: 'model', task_id: effect.task_id, ticket: effect.ticket, ok: true,
          items: [{ type: 'text', text: 'done' }] });
      }
      assert.equal(completed.reply.ok, true);
      pending.push(...completed.effects);
    }
    return selected;
  }

  async function round(operation) {
    const decision = await command(operation);
    assert.equal(decision.reply.ok, true);
    const task = operation.task_id ?? 0;
    const selected = await settle(decision, task);
    assert.ok(selected?.observations, 'The actual kernel observes sources before constructing the model history');
    const read = await command({ op: 'read', task_id: task });
    assert.equal(read.reply.ok, true);
    return { page: read.reply.result, ...selected };
  }

  const initial = await round({ op: 'create', profile: 'fixture', message: 'Review this workspace.' });
  const settings = structuredClone(initial.page.task.settings);
  const introductions = fixtureChanges(initial.page);
  assert.equal(introductions.length, 2);
  const text = introductions.find(change => change.snapshot.key.type === 'review_notes').snapshot;
  const record = introductions.find(change => change.snapshot.key.type === 'review_policy').snapshot;
  assert.equal(text.value.fields.content, originalText);
  assert.deepEqual(text.key.identity, { workspace: root });
  assert.deepEqual(record.value.fields, { runner: 'npm test', rationale: 'Review changed modules.', mode: 'strict', path: recordPath });
  assert.deepEqual(record.key.identity, { workspace: root, path: recordPath });
  assert.ok(JSON.stringify(initial.body).includes('Workspace review metadata'));
  assert.equal(JSON.stringify(initial.body).includes(record.revision), false);
  assert.ok(JSON.stringify(initial.body).includes('Review changed modules.'));

  const stable = await round({ op: 'send', task_id: 0, message: 'Check unchanged sources.' });
  assert.deepEqual(fixtureChanges(stable.page), introductions);
  assert.deepEqual(stable.page.messages.slice(0, initial.page.messages.length), initial.page.messages);
  await writeFile(recordPath, metadata('npm test', 'Review changed modules.', 'strict', 'PRIVATE-REVIEW-BODY-CHANGED'));
  const bodyOnly = await round({ op: 'send', task_id: 0, message: 'Check metadata with changed body.' });
  assert.deepEqual(fixtureChanges(bodyOnly.page), introductions);

  await writeFile(textPath, updatedText);
  await writeFile(recordPath, metadata('bun test', 'Review affected modules.', 'strict'));
  const changed = await round({ op: 'send', task_id: 0, message: 'Check revised review definitions.' });
  assert.deepEqual(changed.page.messages.slice(0, bodyOnly.page.messages.length), bodyOnly.page.messages);
  assert.deepEqual(changed.page.task.settings, settings, 'A new definition cannot change workspace or sandbox authority');
  const amendments = fixtureChanges(changed.page).slice(introductions.length);
  assert.equal(amendments.length, 2);
  for (const amendment of amendments) {
    const before = amendment.key.type === 'review_notes' ? text : record;
    assert.equal(amendment.type, 'amend');
    assert.equal(amendment.base_revision, before.revision);
    assert.notEqual(amendment.revision, before.revision);
    assert.equal(amendment.patch.type, 'field_edits');
    assert.equal(JSON.stringify(changed.body).includes(amendment.revision), false);
    assert.equal(JSON.stringify(amendment.patch).includes('unchanged review'), false);
    assert.equal(amendment.patch.fields.some(field => field.field === 'path'), false);
  }
  const recordAmendment = amendments.find(change => change.key.type === 'review_policy');
  assert.deepEqual(recordAmendment.patch.fields.map(field => field.field), ['runner', 'rationale']);
  const developer = changed.body.input.filter(item => item.role === 'developer');
  const appendedMessages = developer.slice(-2).map(item => item.content).join('\n');
  assert.ok(appendedMessages.includes('runner')); assert.ok(appendedMessages.includes('rationale'));
  assert.equal(appendedMessages.includes('Workspace review metadata; body is excluded.'), false,
    'Amendments do not repeat their definition descriptor');
  assert.equal(appendedMessages.includes('unchanged review'), false);
  const next = await round({ op: 'send', task_id: 0, message: 'Verify reconstructed bindings.' });
  const textBinding = next.observations.find(item => item.type === 'present' && item.snapshot.key.type === 'review_notes');
  const recordBinding = next.observations.find(item => item.type === 'present' && item.snapshot.key.type === 'review_policy');
  assert.equal(textBinding.snapshot.value.fields.content, updatedText);
  assert.equal(recordBinding.snapshot.value.fields.runner, 'bun test');
  assert.equal(recordBinding.snapshot.value.fields.rationale, 'Review affected modules.');
  assert.deepEqual(textBinding.patch.fields, []);
  assert.deepEqual(recordBinding.patch.fields, []);
  assert.deepEqual(fixtureChanges(next.page), fixtureChanges(changed.page));

  const sameWorkspaceFork = await command({ op: 'fork', task_id: 0, child_count: 1,
    messages: ['Review with stricter execution settings.'],
    settings: { sandbox: { mode: 'read-only', network_access: false }, approval: { mode: 'ask-for-approval' } } });
  assert.equal(sameWorkspaceFork.reply.ok, true);
  await settle(sameWorkspaceFork, 1);
  const sameWorkspaceChild = (await command({ op: 'read', task_id: 1 })).reply.result;
  assert.equal(sameWorkspaceChild.task.settings.workspace.primary_root, root);
  assert.equal(sameWorkspaceChild.task.settings.sandbox.mode, 'read-only');
  assert.equal(sameWorkspaceChild.task.settings.approval.mode, 'ask-for-approval');
  assert.deepEqual(sameWorkspaceChild.messages.slice(0, next.page.messages.length), next.page.messages);
  assert.deepEqual(fixtureChanges(sameWorkspaceChild), fixtureChanges(next.page),
    'Changing sandbox or approval in the same workspace preserves context baselines without Remove or Introduce');
  const childText = updatedText.replace('Use bun.', 'Use bun test.');
  await writeFile(textPath, childText);
  await writeFile(recordPath, metadata('bun run test', 'Review affected modules.', 'strict'));
  const childUpdated = await round({ op: 'send', task_id: 1, message: 'Recheck the updated sources.' });
  const childAmendments = fixtureChanges(childUpdated.page).slice(fixtureChanges(sameWorkspaceChild).length);
  assert.equal(childAmendments.length, 2);
  for (const amendment of childAmendments) {
    const baseline = amendments.find(change => change.key.type === amendment.key.type);
    assert.equal(amendment.type, 'amend');
    assert.equal(amendment.base_revision, baseline.revision);
  }
  const parentBeforeSelection = await round({ op: 'send', task_id: 0, message: 'Synchronize the revised review sources.' });
  const latestAmendments = fixtureChanges(parentBeforeSelection.page).filter(change => change.type === 'amend');
  const latestAmendment = type => latestAmendments.findLast(change => change.key.type === type);

  const alternatePath = path.join(copy.directory, 'alternate');
  await mkdir(alternatePath);
  const alternate = await realpath(alternatePath);
  const project = await command({ op: 'create_project', name: 'Alternate workspace', workspace: { roots: [alternate] } });
  assert.equal(project.reply.ok, true);
  const fork = await command({ op: 'fork', task_id: 0, child_count: 1, messages: ['Review the alternate workspace.'],
    settings: { project_id: project.reply.result.project_id } });
  assert.equal(fork.reply.ok, true);
  await settle(fork, 2);
  const selected = (await command({ op: 'read', task_id: 2 })).reply.result;
  assert.deepEqual(selected.messages.slice(0, parentBeforeSelection.page.messages.length), parentBeforeSelection.page.messages);
  const retired = fixtureChanges(selected).slice(fixtureChanges(parentBeforeSelection.page).length);
  assert.equal(retired.length, 2, 'Selecting another workspace retires every constructed workspace-scoped kind');
  for (const removal of retired) {
    const previous = latestAmendment(removal.key.type);
    assert.deepEqual(removal, { type: 'remove', key: previous.key, base_revision: previous.revision });
  }
  assert.equal(selected.task.settings.workspace.primary_root, await realpath(alternate));
  assert.deepEqual((await command({ op: 'read', task_id: 0 })).reply.result.task.settings, settings);

  await unlink(textPath); await unlink(recordPath);
  const removed = await round({ op: 'send', task_id: 0, message: 'Check withdrawn review definitions.' });
  const removals = fixtureChanges(removed.page).slice(fixtureChanges(parentBeforeSelection.page).length);
  assert.equal(removals.length, 2);
  for (const removal of removals) {
    const previous = latestAmendment(removal.key.type);
    assert.deepEqual(removal, { type: 'remove', key: previous.key, base_revision: previous.revision });
  }
  assert.deepEqual(removed.page.task.settings, settings);
  assert.deepEqual(removed.page.messages.slice(0, parentBeforeSelection.page.messages.length), parentBeforeSelection.page.messages);
  await unchanged(copy, [definitionAssembly]);
});
