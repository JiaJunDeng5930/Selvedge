import test from 'node:test';
import assert from 'node:assert/strict';
import { isDeepStrictEqual } from 'node:util';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { pathToFileURL, fileURLToPath } from 'node:url';
import { compileJavaScript } from '../scripts/compile-javascript.mjs';
import { browserUI, surfaceNodes, taskIdle } from './support.mjs';
import { bendValue, bendTag } from '../host/public/bend-value.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { startServer } from '../host/server.mjs';
import browserModel from '../host/public/generated/browser-model.mjs';
import { chatgptFixture, jsonResponse, modelResponse } from './fixtures/chatgpt.mjs';
import path from 'node:path';
import { checkUiSeparation, prepareUiVerification } from '../scripts/ui-verification.mjs';

const firstRule = 'browser/sample/first-laws.bend';
const secondRule = 'browser/sample/second-rules.bend';
const ownerImports = 'import Base\nimport ./first-laws.bend as First\nimport ./second-rules.bend as Second\n';
const laws = ['First.alpha', 'First.beta', 'Second.gamma', 'Second.delta'];

function binding(law, body = '{==}') {
  return `def ${law}():\n  ${body}\n`;
}

function fixture(run) {
  const root = mkdtempSync(path.join(tmpdir(), 'selvedge-ui-verification-'));
  function write(filename, source) {
    const target = path.join(root, filename);
    mkdirSync(path.dirname(target), { recursive: true });
    writeFileSync(target, source);
  }
  try {
    write('PROOF.bend', 'import Base\n');
    write('BROWSER.bend', 'import Base\n');
    write(firstRule, 'import Base\nlaw alpha:\n  {True{} == True{} : Bool}\nlaw beta:\n  {True{} == True{} : Bool}\n');
    write(secondRule, 'import Base\nlaw gamma:\n  {True{} == True{} : Bool}\nlaw delta:\n  {True{} == True{} : Bool}\n');
    run({ root, write });
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

function rejectsSeparation(root, reason) {
  assert.throws(() => checkUiSeparation(root), error => {
    assert.ok(error.message.startsWith('UI verification separation failed:\n'));
    assert.ok(error.message.split('\n').some(line => line.startsWith(reason)), error.message);
    return true;
  });
}

test('UI laws can be split across providers or merged in the concept proof', () => {
  fixture(({ root, write }) => {
    const providers = ['browser/sample/one-proof.bend', 'browser/sample/two-proof.bend'];
    write(providers[0], ownerImports + binding(laws[0]) + binding(laws[2]));
    write(providers[1], ownerImports + binding(laws[1]) + binding(laws[3]));
    const discovered = checkUiSeparation(root);
    assert.ok(Array.isArray(discovered));
    assert.deepEqual(discovered, [firstRule, secondRule, ...providers].sort());
  });
  fixture(({ root, write }) => {
    write('browser/sample/PROOF.bend', ownerImports + laws.map(law => binding(law)).join(''));
    assert.deepEqual(checkUiSeparation(root), ['browser/sample/PROOF.bend', firstRule, secondRule].sort());
  });
});

test('UI laws require exactly one binding, including within a single provider', () => {
  for (const missing of laws) {
    fixture(({ root, write }) => {
      write('browser/sample/PROOF.bend', ownerImports + laws.filter(law => law !== missing).map(law => binding(law)).join(''));
      const [alias, name] = missing.split('.');
      rejectsSeparation(root, `UI proof does not fill its rule law: ${alias === 'First' ? firstRule : secondRule}:${name}`);
    });
  }
  for (const sameFile of [false, true]) {
    fixture(({ root, write }) => {
      write('browser/sample/PROOF.bend', ownerImports + laws.map(law => binding(law)).join('') + (sameFile ? binding(laws[0]) : ''));
      if (!sameFile) write('browser/sample/extra-proof.bend', ownerImports + binding(laws[0]));
      rejectsSeparation(root, `UI rule law has multiple proof providers: ${firstRule}:alpha:`);
    });
  }
});

test('UI verification imports the actual referenced law provider before its consumer', () => {
  fixture(({ root, write }) => {
    const provider = 'browser/sample/z-provider-proof.bend';
    const consumer = 'browser/sample/a-consumer-proof.bend';
    write(provider, ownerImports + binding(laws[0]) + binding(laws[2]));
    write(consumer, ownerImports + binding(laws[1], 'First.alpha()') + binding(laws[3], 'Second.gamma()'));
    const prepared = prepareUiVerification(root);
    const imports = readFileSync(path.join(root, prepared.entry), 'utf8').split('\n');
    const providerIndex = imports.findIndex(line => line.startsWith(`import ../${provider} as `));
    const consumerIndex = imports.findIndex(line => line.startsWith(`import ../${consumer} as `));
    assert.ok(providerIndex >= 0);
    assert.ok(consumerIndex > providerIndex);
  });
});

test('UI models and rules cannot import proofs transitively or implement evidence', () => {
  for (const source of ['model', 'rule']) {
    fixture(({ root, write }) => {
      write('browser/sample/PROOF.bend', ownerImports + laws.map(law => binding(law)).join(''));
      write('shared/bridge.bend', 'import Base\nimport ../browser/sample/PROOF.bend as Evidence\n');
      const filename = source === 'model' ? 'browser/sample/MODEL.bend' : firstRule;
      const declarations = source === 'rule' ? 'law alpha:\n  {True{} == True{} : Bool}\nlaw beta:\n  {True{} == True{} : Bool}\n' : '';
      write(filename, 'import Base\nimport ../../shared/bridge.bend as Bridge\n' + declarations);
      rejectsSeparation(root, `UI model/rule imports a proof provider: ${filename} -> browser/sample/PROOF.bend`);
    });
  }
  for (const [source, reason] of [
    [ownerImports + binding(laws[0]), 'UI law implementation outside proofs:'],
    ['import Base\ndef evidence() -> {True{} == True{} : Bool}:\n  {==}\n', 'UI equality witness outside proofs:'],
  ]) {
    fixture(({ root, write }) => {
      write('browser/sample/PROOF.bend', ownerImports + laws.map(law => binding(law)).join(''));
      write('browser/sample/MODEL.bend', source);
      rejectsSeparation(root, reason);
    });
  }
});


// This facade only forwards inputs into the production transition. Assertions
// below inspect its emitted surface and command, rather than replaying UI rules.
async function activityInput(t) {
  const repository = fileURLToPath(new URL('../', import.meta.url));
  const directory = mkdtempSync(path.join(repository, '.workpad', 'activity-acceptance-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const entry = path.join(directory, 'input.bend');
  const output = path.join(directory, 'input.mjs');
  writeFileSync(entry, `import Base
import ../../interaction/MODEL.bend as UI
import ../../interaction/TYPES.bend as Core
import ../../interaction/presentation/MODEL.bend as View
import ../../interaction/presentation/SURFACE.bend as Surface
import ../../interaction/presentation/surface-proof.bend as SurfaceProof

def decide(input: Core.Input, state: Core.State) -> Core.Decision:
  UI.step(UI.InterfaceInput{input}, state)

def press(key: String, state: Core.State) -> Core.Decision:
  UI.step(UI.Element{View.Capacity{True{}, False{}}, key, Surface.Press{}}, state)

def state_from_step(result: Core.Decision) -> Core.State:
  match result:
    case Core.Decision{next, reply, runtime, interaction, service, durable}: next

def apply(input: Core.Input, state: Core.State) -> Core.State:
  state_from_step(UI.step(UI.InterfaceInput{input}, state))
`);
  await compileJavaScript({ entry, output, sourceRoot: repository, exports: { apply: 'apply', decide: 'decide', press: 'press' } });
  return import(pathToFileURL(output).href);
}

const uiValue = (name, fields = {}) => bendValue(`interaction/INPUT.${name}`, fields);
const listValues = list => {
  const values = [];
  for (; bendTag(list) === 'Con'; list = list.tail) values.push(list.head);
  return values;
};
const subtree = node => [node, ...listValues(node.children).flatMap(subtree)];
const isDecision = (node, field) => bendTag(node.meaning) === 'DecisionGroup'
  && bendTag(node.meaning.decision.subject.field) === field;
const carriesInput = (value, tag) => value !== null && typeof value === 'object'
  && (bendTag(value) === tag || Object.values(value).some(child => carriesInput(child, tag)));
const surfaceText = nodes => nodes.map(node => `${node.label} ${node.meaning.text ?? ''} ${node.meaning.description ?? ''}`).join('\n');

// These observations deliberately stop at the emitted semantic tree. Physical
// geometry needs the actual browser: this repository has no DOM/measurement fixture.
test('production activity surfaces retain current decisions and project obstructions', { timeout: 240_000 }, async t => {
  const [ui, input] = await Promise.all([browserUI(t), activityInput(t)]);
  const upstream = await chatgptFixture(t, (request, response) => {
    if (request.method === 'GET') jsonResponse(response, { models: [{
      slug: 'activity-model', display_name: 'Activity model', priority: 0, visibility: 'list', supported_in_api: false,
      default_reasoning_level: 'medium', supported_reasoning_levels: [{ effort: 'medium', description: 'Normal' }, { effort: 'high', description: 'High' }],
    }] });
    else modelResponse(response, [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'Settled.' }] }]);
  });
  const server = await startServer({ home: upstream.directory, cwd: upstream.directory,
    config: validateConfig({ ...defaultConfig, port: 0, profiles: {}, chatgpt: upstream.profile }) });
  t.after(() => server.close());
  const profile = server.service.browserSnapshot().program.local.environment.profiles.head.key;
  assert.equal((await server.service.command({ op: 'create', profile, reasoning: 'medium', message: 'Activity acceptance.' })).reply.ok, true);
  await taskIdle(server.service, 0);
  const initial = () => {
    const authenticated = ui.authenticated(server.service.browserSnapshot().program, 0n);
    assert.equal(bendTag(authenticated), 'Done');
    return authenticated.value;
  };
  const apply = (state, value) => input.apply(bendValue('interaction/TYPES.ApplicationInput', {
    input: bendValue('interaction/session/MODEL.UserInput', { input: value }),
  }), state);
  const activate = (state, action) => apply(state, uiValue('Activate', { action }));
  const nodes = state => surfaceNodes(ui.surface_state(state));
  const enterDecision = (state, field) => {
    const decision = nodes(state).find(node => isDecision(node, field));
    assert.ok(decision, `${field} must expose its current decision`);
    const entrance = subtree(decision).find(node => carriesInput(node.meaning.input, 'EnterDecision'));
    assert.ok(entrance, `${field} must expose a real current-value entrance`);
    return ui.activate_state(state, ui.key(entrance));
  };
  const editor = uiValue('MessageEditor', { task: 0n });
  const open = (state, name, owner) => activate(state, uiValue('OpenPanel', {
    panel: uiValue(name, { editor: owner }), trigger: 'acceptance',
  }));

  await t.test('searching away from the selected model retains its live reasoning command', async () => {
    let state = open(initial(), 'ModelPicker', editor);
    state = apply(state, uiValue('SearchChoices', { query: 'no-model-matches-this-query' }));
    const emitted = nodes(state);
    const reasoning = emitted.filter(node => isDecision(node, 'ReasoningEffort'));
    assert.equal(reasoning.length, 1);
    const high = subtree(reasoning[0]).find(node => node.semantic === 'effort/high');
    assert.ok(high, 'Search results must not remove the current model reasoning capability');
    assert.equal(bendTag(high.meaning.availability), 'Available');
    const pressed = ui.press_state(state, ui.key(high));
    assert.equal(bendTag(pressed), 'Done');
    const commands = JSON.parse(pressed.value);
    assert.equal(commands.length, 1);
    assert.equal(commands[0].profile, profile);
    assert.equal(commands[0].reasoning, 'high');
    const response = await fetch(`${server.address}/api/browser/command`, { method: 'POST',
      headers: { authorization: `Bearer ${server.token}`, 'content-type': 'application/json' },
      body: JSON.stringify({ command: commands[0] }) });
    assert.equal(response.status, 200);
    assert.equal((await response.json()).reply.ok, true);
  });

  await t.test('FullAccess exposes unrestricted effects and removes effective restriction choices', async () => {
    assert.equal((await server.service.command({ op: 'configure_task_execution', task_id: 0, profile,
      reasoning: 'high', sandbox: { mode: 'workspace-write', network_access: false }, approval: { mode: 'full-access' } })).reply.ok, true);
    const emitted = nodes(open(initial(), 'PermissionsConfiguration', editor));
    assert.match(surfaceText(emitted), /unrestricted|full access/i);
    assert.match(surfaceText(emitted), /no approval|without approval/i);
    for (const field of ['SandboxMode', 'NetworkAccess']) {
      assert.equal(emitted.filter(node => isDecision(node, field)).length, 0,
        `${field} must not appear as an effective decision under FullAccess`);
    }
    assert.equal(emitted.filter(node => isDecision(node, 'ApprovalReviewer')).length, 0);
  });

  await t.test('AutomaticReview owns its reviewer selection', async () => {
    assert.equal((await server.service.command({ op: 'configure_task_execution', task_id: 0, profile,
      reasoning: 'high', sandbox: { mode: 'workspace-write', network_access: false }, approval: { mode: 'approval-for-me', reviewer_profile: profile } })).reply.ok, true);
    const state = open(initial(), 'PermissionsConfiguration', editor);
    const emitted = nodes(state);
    const strategy = emitted.filter(node => isDecision(node, 'ApprovalPolicy'));
    assert.equal(strategy.length, 1, 'There must be one strategy decision');
    const reviewers = emitted.filter(node => isDecision(node, 'ApprovalReviewer'));
    assert.equal(reviewers.length, 1, 'AutomaticReview must introduce a separate reviewer parameter');
    assert.ok(subtree(strategy[0]).includes(reviewers[0]), 'Reviewer choice must belong to the strategy decision');
    const expanded = nodes(enterDecision(state, 'ApprovalReviewer'));
    const reviewerChoice = expanded.find(node => isDecision(node, 'ApprovalReviewer'));
    assert.ok(subtree(reviewerChoice).some(node => bendTag(node.meaning) === 'Choice' && node.meaning.selected));
  });


  await t.test('AutomaticReview without a valid reviewer exposes its unavailable reason', async () => {
    const authenticated = ui.authenticated(browserModel.empty(), 0n);
    assert.equal(bendTag(authenticated), 'Done');
    const state = open(authenticated.value, 'PermissionsConfiguration', uiValue('NewTaskEditor'));
    const emitted = nodes(enterDecision(state, 'ApprovalPolicy'));
    const automatic = emitted.find(node => bendTag(node.meaning) === 'ReadOnly' && /automatic/i.test(node.label));
    assert.ok(automatic, 'The strategy remains readable without reviewers');
    assert.match(automatic.meaning.text, /no automatic review models are available/i);
    assert.equal(automatic.meaning.input, undefined, 'The unavailable strategy must not expose a selection input');
    assert.equal(subtree(automatic).some(node => node.meaning.input !== undefined), false);
    assert.equal(emitted.filter(node => isDecision(node, 'ApprovalReviewer')).length, 0);
  });

  await t.test('directory failure retries the complete draft and succeeds with a correlated observation', async () => {
    const created = await server.service.command({ op: 'create_project', name: 'Retry project',
      workspace: { roots: [upstream.directory], primary_root: upstream.directory } });
    assert.equal(created.reply.ok, true);
    const project = bendValue('Some', { value: BigInt(created.reply.result.project_id) });
    const projectEditor = uiValue('ProjectEditor', { project });
    let state = activate(initial(), uiValue('EditProject', { project }));
    state = apply(state, uiValue('EditDraft', { editor: projectEditor, edit: uiValue('NameProject', { name: 'Recovered project' }) }));
    const draft = state => listValues(state.application.session.drafts).find(value =>
      bendTag(value.body) === 'Project' && value.body.project.value === project.value);
    const commit = nodes(state).find(node => bendTag(node.meaning) === 'ActionCommit'
      && bendTag(node.meaning.assessment.identity.editor) === 'ProjectEditor');
    assert.ok(commit);
    const original = draft(state);
    const submitted = input.press(ui.key(commit), state);
    const request = listValues(submitted.interaction_effects).find(effect => bendTag(effect) === 'ObserveDirectories');
    assert.ok(request, 'A real save must request physical directory observation');
    const observed = (state, ticket, result) => input.decide(bendValue('interaction/TYPES.ApplicationInput', {
      input: bendValue('interaction/session/MODEL.DirectoriesObserved', { ticket, result }),
    }), state);
    const failed = observed(submitted.state, request.ticket, bendValue('Fail', { error: 'Physical directory probe failed' }));
    const failedDraft = draft(failed.state);
    assert.deepEqual(failedDraft.body, original.body);
    assert.equal(failedDraft.revision, original.revision);
    assert.equal(failedDraft.directory_entry, original.directory_entry);
    assert.equal(bendTag(failedDraft.feedback), 'WorkspaceRejected');
    const retry = nodes(failed.state).find(node => node.label === 'Retry' && carriesInput(node.meaning.input, 'RetryWorkspace'));
    assert.ok(retry, 'Directory failure must expose an actual Retry control');
    const retried = input.press(ui.key(retry), failed.state);
    const secondRequest = listValues(retried.interaction_effects).find(effect => bendTag(effect) === 'ObserveDirectories');
    assert.ok(secondRequest, 'Retry must launch a fresh physical directory observation');
    assert.notEqual(secondRequest.ticket, request.ticket);
    assert.deepEqual(draft(retried.state).body, original.body);
    assert.equal(draft(retried.state).revision, original.revision);
    const succeeded = observed(retried.state, secondRequest.ticket, bendValue('Done', { value:
      bendValue('interaction/services/CONTEXT.DirectoryObservation', { workspace: secondRequest.entered,
        guidance: bendValue('harness/DOMAIN.NoProject') }) }));
    const save = listValues(succeeded.interaction_effects).find(effect => bendTag(effect) === 'RequestCommand');
    assert.ok(save, 'A successful correlated observation must continue the original save');
    assert.equal(bendTag(save.command), 'UpdateProject');
    assert.equal(save.command.project_id, project.value);
    assert.equal(save.command.name.value, 'Recovered project');

    const pending = apply(failed.state, uiValue('EditDraft', { editor: projectEditor,
      edit: uiValue('WriteDirectory', { path: '/pending/not-yet-added' }) }));
    const pendingDraft = draft(pending);
    const refused = input.decide(retry.meaning.input, pending);
    assert.equal(listValues(refused.interaction_effects).filter(effect => bendTag(effect) === 'ObserveDirectories').length, 0,
      'A retained Retry input cannot bypass the unadded directory obstruction');
    assert.deepEqual(draft(refused.state), pendingDraft, 'Refused Retry must preserve the complete current draft');
  });

  await t.test('project pending input obstructs saving and clearing restores the edited draft', async () => {
    const created = await server.service.command({ op: 'create_project', name: 'Activity project',
      workspace: { roots: [upstream.directory], primary_root: upstream.directory } });
    assert.equal(created.reply.ok, true);
    const projectEditor = uiValue('ProjectEditor', { project: bendValue('Some', { value: BigInt(created.reply.result.project_id) }) });
    let state = activate(initial(), uiValue('EditProject', { project: bendValue('Some', { value: BigInt(created.reply.result.project_id) }) }));
    const commit = state => {
      const matches = nodes(state).filter(node => bendTag(node.meaning) === 'ActionCommit'
        && bendTag(node.meaning.assessment.identity.editor) === 'ProjectEditor');
      assert.equal(matches.length, 1);
      return matches[0];
    };
    assert.equal(bendTag(commit(state).meaning.availability), 'Unavailable');
    assert.match(surfaceText(nodes(state)), /no project changes|unchanged/i);
    assert.equal(nodes(state).filter(node => isDecision(node, 'WorkspacePrimary')).length, 0,
      'Primary editing must occur only at workspace members');
    const members = nodes(state).filter(node => bendTag(node.meaning) === 'WorkspaceMember');
    assert.equal(members.length, 1);
    assert.equal(subtree(members[0]).filter(node => node.semantic === 'directory/primary').length, 1);
    const edit = change => { state = apply(state, uiValue('EditDraft', { editor: projectEditor, edit: change })); };
    edit(uiValue('NameProject', { name: 'Edited activity project' }));
    assert.equal(bendTag(commit(state).meaning.availability), 'NeedsDirectoryObservation');
    edit(uiValue('WriteDirectory', { path: '/pending/not-yet-added' }));
    assert.equal(bendTag(commit(state).meaning.availability), 'Unavailable');
    const emittedTree = nodes(state);
    const entry = emittedTree.find(node => bendTag(node.meaning) === 'EnterDirectory');
    assert.ok(entry);
    assert.equal(entry.meaning.text, '/pending/not-yet-added');
    const parents = emittedTree.filter(node => listValues(node.children).some(child => isDeepStrictEqual(child.key, entry.key)));
    assert.ok(parents.some(parent => /add or clear.*directory/i.test(surfaceText(subtree(parent)))),
      'The pending entry must expose its obstruction beside the field');
    edit(uiValue('WriteDirectory', { path: '' }));
    assert.equal(bendTag(commit(state).meaning.availability), 'NeedsDirectoryObservation');
  });
});
