import test from 'node:test';
import assert from 'node:assert/strict';
import { isDeepStrictEqual } from 'node:util';
import { mkdtempSync, mkdirSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { pathToFileURL, fileURLToPath } from 'node:url';
import { compileJavaScript } from '../scripts/compile-javascript.mjs';
import { browserUI, surfaceNodes, taskIdle, home } from './support.mjs';
import { bendValue, bendTag, decodeBendValue } from '../host/public/bend-value.mjs';
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
const actualUIInput = (value, tag) => {
  if (!value || typeof value !== 'object') return undefined;
  if (bendTag(value) === tag) return value;
  for (const child of Object.values(value)) {
    const found = actualUIInput(child, tag);
    if (found) return found;
  }
  return undefined;
};

// These observations deliberately stop at the emitted semantic tree. Physical
// geometry needs the actual browser: this repository has no DOM/measurement fixture.
test('production activity surfaces retain current decisions and project obstructions', { timeout: 240_000 }, async t => {
  const [ui, input] = await Promise.all([browserUI(t, { sourceAdmission: true }), activityInput(t)]);
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
  const overlayNodes = state => listValues(ui.surface_state(state).overlays).flatMap(subtree);
  const enterDecision = (state, field) => {
    const fieldKey = { ReasoningEffort: 'reasoning-effort', ApprovalReviewer: 'approval-reviewer' }[field];
    const entrances = nodes(state).filter(node => {
      const requested = actualUIInput(node.meaning.input, 'EnterDecision');
      return requested?.field_key === fieldKey && isDeepStrictEqual(requested.editor, editor);
    });
    assert.equal(entrances.length, 1, `${field} must expose one actual entrance for its owning editor`);
    return ui.activate_state(state, ui.key(entrances[0]));
  };
  const editor = uiValue('MessageEditor', { task: 0n });
  const open = (state, name, owner) => activate(state, uiValue('OpenPanel', {
    panel: uiValue(name, { editor: owner }), trigger: 'acceptance',
  }));
  const expandedView = (state, title) => {
    const emitted = overlayNodes(state);
    assert.ok(emitted.some(node => bendTag(node.role) === 'Heading' && title.test(node.label)),
      'An expanded view must visibly identify its current activity');
    const returns = emitted.filter(node => {
      const request = actualUIInput(node.meaning.input, 'LeaveDecision');
      return request && isDeepStrictEqual(request.editor, editor);
    });
    assert.equal(returns.length, 1, 'The identified view must expose one return action for its actual owner');
    return returns[0];
  };

  await t.test('searching away from the selected model retains its live reasoning command', async () => {
    let state = open(initial(), 'ModelPicker', editor);
    state = apply(state, uiValue('SearchChoices', { query: 'no-model-matches-this-query' }));
    state = enterDecision(state, 'ReasoningEffort');
    expandedView(state, /reasoning/i);
    const emitted = nodes(state);
    const high = emitted.find(node => node.semantic === 'effort/high');
    assert.ok(high, 'Search results must not remove the current model reasoning capability');
    assert.equal(bendTag(high.meaning.availability), 'Available');
    assert.deepEqual(actualUIInput(high.meaning.input, 'EditDraft').editor, editor);
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

  await t.test('Ask inspection retains applicable settings without suggesting a missing automatic reviewer', () => {
    const state = apply(open(initial(), 'PermissionsConfiguration', editor), uiValue('TogglePropertySource', { editor }));
    const emitted = nodes(state);
    assert.doesNotMatch(surfaceText(emitted), /reviewing model|no automatic reviewing model/i,
      'An inactive dependency must not appear as an unconfigured permission');
    expandedView(state, /permissions/i);
    for (const field of ['approval-policy', 'sandbox-mode', 'network-access']) {
      const entrances = emitted.filter(node => {
        const request = actualUIInput(node.meaning.input, 'EnterDecision');
        return request?.field_key === field && isDeepStrictEqual(request.editor, editor);
      });
      assert.equal(entrances.length, 1, `${field} must retain one actual setting entry in Ask inspection`);
    }
  });

  await t.test('model inspection and its dependent parameter return through their identified owning views', () => {
    let state = open(initial(), 'ModelPicker', editor);
    state = apply(state, uiValue('TogglePropertySource', { editor }));
    expandedView(state, /model/i);
    assert.match(surfaceText(overlayNodes(state)), /applies to this task/i);
    assert.doesNotMatch(surfaceText(overlayNodes(state)), /configured model list/i,
      'The ordinary settings view must retain scope without displaying detailed provenance');
    state = enterDecision(state, 'ReasoningEffort');
    const dependencyBack = expandedView(state, /reasoning/i);
    state = ui.activate_state(state, ui.key(dependencyBack));
    assert.equal(state.application.session.layers.head.source_expanded, true);
    assert.equal(bendTag(state.application.session.layers.head.decision_field), 'None');
    const inspectionBack = expandedView(state, /model/i);
    state = ui.activate_state(state, ui.key(inspectionBack));
    assert.equal(state.application.session.layers.head.source_expanded, false);
    assert.ok(nodes(state).some(node => bendTag(node.meaning) === 'Choice' && node.meaning.selected),
      'Returning from inspection must retain the actual selected model');
  });

  await t.test('FullAccess exposes unrestricted effects and omits inapplicable settings from inspection', async () => {
    assert.equal((await server.service.command({ op: 'configure_task_execution', task_id: 0, profile,
      reasoning: 'high', sandbox: { mode: 'workspace-write', network_access: false }, approval: { mode: 'full-access' } })).reply.ok, true);
    let state = open(initial(), 'PermissionsConfiguration', editor);
    const emitted = nodes(state);
    assert.match(surfaceText(emitted), /unrestricted|full access/i);
    assert.match(surfaceText(emitted), /no approval|without approval/i);
    for (const field of ['SandboxMode', 'NetworkAccess']) {
      assert.equal(emitted.filter(node => isDecision(node, field)).length, 0,
        `${field} must not appear as an effective decision under FullAccess`);
    }
    assert.equal(emitted.filter(node => isDecision(node, 'ApprovalReviewer')).length, 0);
    state = apply(state, uiValue('TogglePropertySource', { editor }));
    const inspected = nodes(state);
    assert.doesNotMatch(surfaceText(inspected), /no automatic reviewing model/i);
    for (const field of ['sandbox-mode', 'network-access', 'approval-reviewer']) {
      assert.equal(inspected.some(node => actualUIInput(node.meaning.input, 'EnterDecision')?.field_key === field), false,
        `${field} must not become editable merely by opening inspection`);
    }
    assert.equal(inspected.some(node => node.label === 'Reviewing model'
      || node.label === 'Filesystem access' || node.label === 'Network access'), false,
      'Inapplicable fields must be absent rather than presented as missing values');
  });

  await t.test('AutomaticReview owns its reviewer selection', async () => {
    assert.equal((await server.service.command({ op: 'configure_task_execution', task_id: 0, profile,
      reasoning: 'high', sandbox: { mode: 'workspace-write', network_access: false }, approval: { mode: 'approval-for-me', reviewer_profile: profile } })).reply.ok, true);
    const state = apply(open(initial(), 'PermissionsConfiguration', editor), uiValue('TogglePropertySource', { editor }));
    const emitted = nodes(state);
    const reviewerEntrances = emitted.filter(node => {
      const request = actualUIInput(node.meaning.input, 'EnterDecision');
      return request?.field_key === 'approval-reviewer' && isDeepStrictEqual(request.editor, editor);
    });
    assert.equal(reviewerEntrances.length, 1, 'AutomaticReview must expose its own retained reviewer parameter');
    const expandedState = enterDecision(state, 'ApprovalReviewer');
    assert.equal(expandedState.application.session.layers.head.source_expanded, true);
    const expanded = nodes(expandedState);
    const selected = expanded.filter(node => bendTag(node.meaning) === 'Choice' && node.meaning.selected);
    assert.equal(selected.length, 1);
    assert.equal(actualUIInput(selected[0].meaning.input, 'AutomaticReview').profile, profile);
    assert.deepEqual(actualUIInput(selected[0].meaning.input, 'EditDraft').editor, editor);
  });


  await t.test('AutomaticReview without a valid reviewer exposes its unavailable reason', async () => {
    const authenticated = ui.authenticated(browserModel.empty(), 0n);
    assert.equal(bendTag(authenticated), 'Done');
    const state = open(authenticated.value, 'PermissionsConfiguration', uiValue('NewTaskEditor'));
    const emitted = nodes(state);
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
    const admittedSource = observedState => {
      const result = ui.source_admission(observedState);
      assert.equal(bendTag(result), 'Done');
      assert.equal(bendTag(result.value), 'Ready', `Actual project source admission: ${JSON.stringify(result.value, (_, value) => typeof value === 'bigint' ? value.toString() : value)}`);
      return result.value.source;
    };
    admittedSource(state);
    const sourceToggle = nodes(state).find(node => bendTag(actualUIInput(node.meaning.input, 'OpenPanel')?.panel) === 'PropertySource');
    assert.ok(sourceToggle, 'Project settings must expose their actual source disclosure');
    const expandedSource = ui.activate_state(state, ui.key(sourceToggle));
    admittedSource(expandedSource);
    const sourceDetails = nodes(expandedSource).find(node => node.label === 'Source' && node.meaning.text === 'Project configuration');
    assert.ok(sourceDetails, 'Expanded project source must retain its actual disclosure content');
    assert.equal(sourceDetails.meaning.text, 'Project configuration');
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


test('production activity choices complete and compound cancellation discards buffers', { timeout: 240_000 }, async t => {
  const [ui, input] = await Promise.all([browserUI(t, { sourceAdmission: true }), activityInput(t)]);
  const editor = uiValue('NewTaskEditor');
  const observe = state => surfaceNodes(ui.surface_state(state));
  const apply = (state, value) => input.apply(bendValue('interaction/TYPES.ApplicationInput', {
    input: bendValue('interaction/session/MODEL.UserInput', { input: value }),
  }), state);
  const open = (state, panel) => apply(state, uiValue('Activate', { action: uiValue('OpenPanel', {
    panel: uiValue(panel, { editor }), trigger: 'activity-lifecycle',
  }) }));
  const authenticated = server => {
    const result = ui.authenticated(server.service.browserSnapshot().program, 0n);
    assert.equal(bendTag(result), 'Done');
    return result.value;
  };
  const draft = state => listValues(state.application.session.drafts).find(item => bendTag(item.body) === 'NewTask').body;
  const layer = state => listValues(state.application.session.layers)[0];
  const actualInput = (value, tag) => {
    if (!value || typeof value !== 'object') return undefined;
    if (bendTag(value) === tag) return value;
    for (const child of Object.values(value)) {
      const found = actualInput(child, tag);
      if (found) return found;
    }
    return undefined;
  };
  const modelChoices = state => observe(state).filter(node => bendTag(node.meaning) === 'Choice'
    && actualInput(node.meaning.input, 'ChooseModel'));
  const enter = (state, field) => apply(state, uiValue('EnterDecision', { editor, field_key: field }));
  const back = state => apply(state, uiValue('LeaveDecision', { editor }));

  const oneHome = await home(t);
  const singleton = await startServer({ home: oneHome, cwd: oneHome,
    config: validateConfig({ ...defaultConfig, port: 0, chatgpt: false }) });
  t.after(() => singleton.close());
  await t.test('one open model is directly selected without an unnecessary search and commits its buffer only on completion', () => {
    let state = open(authenticated(singleton), 'ModelPicker');
    const choices = modelChoices(state);
    assert.equal(choices.length, 1);
    assert.equal(choices[0].meaning.selected, true);
    assert.equal(actualInput(choices[0].meaning.input, 'ChooseModel').profile, draft(state).profile);
    assert.equal(observe(state).some(node => bendTag(node.meaning) === 'SearchChoices'), false);
    const original = draft(state).reasoning;
    state = enter(state, 'reasoning-effort');
    const openField = observe(state).find(node => bendTag(node.meaning) === 'Edit' && bendTag(node.meaning.field) === 'ReasoningEffort');
    assert.ok(openField, 'An open capability must render its actual parameter field');
    assert.equal(bendTag(openField.meaning.entry), 'SingleLine');
    assert.equal(bendTag(layer(state).decision_field), 'Some');
    state = apply(state, uiValue('WriteDecisionParameter', { editor, value: 'custom-effort' }));
    assert.equal(draft(state).reasoning, original, 'An open buffer must not apply configuration while typing');
    assert.equal(layer(state).parameter_buffer.value, 'custom-effort');
    const complete = observe(state).find(node => actualInput(node.meaning.input, 'CompleteDecisionParameter'));
    assert.ok(complete, 'The open parameter must expose its actual completion action');
    state = ui.activate_state(state, ui.key(complete));
    assert.equal(draft(state).reasoning, 'custom-effort');
    assert.ok(layer(state), 'Parameter completion returns to its existing parent surface');
    assert.equal(bendTag(layer(state).decision_field), 'None');
    assert.equal(bendTag(layer(state).parameter_buffer), 'None');
    assert.equal(modelChoices(state).some(node => node.meaning.selected), true);
  });

  const upstream = await chatgptFixture(t, (_, response) => jsonResponse(response, { models:
    Array.from({ length: 9 }, (_, index) => ({ slug: index === 0 ? 'gpt-6-astra' : `catalog-${index}`,
      display_name: `Catalog model ${index}`, priority: index, visibility: 'list', supported_in_api: false,
      default_reasoning_level: 'medium', supported_reasoning_levels: [{ effort: 'medium', description: 'Normal' }, { effort: 'high', description: 'High' }],
    })),
  }));
  const catalog = await startServer({ home: upstream.directory, cwd: upstream.directory,
    config: validateConfig({ ...defaultConfig, port: 0, profiles: {}, chatgpt: upstream.profile }) });
  t.after(() => catalog.close());
  await t.test('filtering retains the selected finite model and completing its parameter returns to principal choices', () => {
    let state = open(authenticated(catalog), 'ModelPicker');
    const current = draft(state).profile;
    assert.ok(modelChoices(state).some(node => node.meaning.selected
      && actualInput(node.meaning.input, 'ChooseModel').profile === current));
    assert.ok(observe(state).some(node => bendTag(node.meaning) === 'SearchChoices'));
    state = apply(state, uiValue('SearchChoices', { query: 'no-catalog-name-matches-this-query' }));
    assert.ok(modelChoices(state).some(node => node.meaning.selected
      && actualInput(node.meaning.input, 'ChooseModel').profile === current));
    state = enter(state, 'reasoning-effort');
    const high = observe(state).find(node => bendTag(node.meaning) === 'Choice'
      && actualInput(node.meaning.input, 'ChooseModel')?.reasoning === 'high');
    assert.ok(high, 'A declared finite parameter must expose its actual high alternative');
    state = ui.activate_state(state, ui.key(high));
    assert.equal(draft(state).reasoning, 'high');
    assert.ok(layer(state));
    assert.equal(bendTag(layer(state).decision_field), 'None');
    assert.ok(modelChoices(state).some(node => node.meaning.selected));
  });
  await t.test('adaptive reasoning is readable without an editable parameter entrance', () => {
    const profiles = listValues(catalog.service.browserSnapshot().program.local.environment.profiles);
    const automatic = profiles.find(profile => bendTag(profile.reasoning) === 'Adaptive');
    assert.ok(automatic, 'The actual account catalog must materialize its automatic profile');
    let state = authenticated(catalog);
    state = apply(state, uiValue('EditDraft', { editor, edit: uiValue('ChooseModel', { profile: automatic.key, reasoning: 'auto' }) }));
    state = open(state, 'ModelPicker');
    state = enter(state, 'reasoning-effort');
    const automaticValue = observe(state).find(node => bendTag(node.meaning) === 'Edit'
      && bendTag(node.meaning.field) === 'ReasoningEffort');
    assert.ok(automaticValue, 'The actual automatic capability must remain observable');
    assert.equal(bendTag(automaticValue.meaning.entry), 'DisplayOnly');
    assert.equal(automaticValue.meaning.value.profile, automatic.key);
    assert.equal(automaticValue.meaning.value.reasoning, 'auto');
    assert.equal(listValues(automaticValue.meaning.choices).length, 0);
    assert.equal(observe(state).some(node => actualInput(node.meaning.input, 'WriteDecisionParameter')
      || actualInput(node.meaning.input, 'CompleteDecisionParameter')), false);
    const appliedAutomatic = draft(state).reasoning;
    state = apply(state, uiValue('WriteDecisionParameter', { editor, value: 'high' }));
    state = apply(state, uiValue('CompleteDecisionParameter', { editor }));
    assert.equal(draft(state).reasoning, appliedAutomatic, 'A read-only adaptive capability must reject parameter editing');
  });
  await t.test('permission principal completion closes while inspection and dependency Back retain their parent', () => {
    let state = open(authenticated(singleton), 'PermissionsConfiguration');
    const ask = observe(state).find(node => bendTag(node.meaning) === 'Choice'
      && actualInput(node.meaning.input, 'SetApproval') && /ask|approval/i.test(node.label));
    assert.ok(ask, 'A principal permission alternative must be directly operable');
    state = ui.activate_state(state, ui.key(ask));
    assert.equal(listValues(state.application.session.layers).length, 0);
    state = open(state, 'PermissionsConfiguration');
    state = apply(state, uiValue('TogglePropertySource', { editor }));
    assert.equal(layer(state).source_expanded, true);
    const inspection = observe(state);
    assert.match(surfaceText(inspection), /applies to this new task/i);
    assert.doesNotMatch(surfaceText(inspection), /filesystem and network:|approval: environment defaults/i,
      'Detailed origins must wait for the user to request the source view');
    const source = inspection.find(node => bendTag(actualInput(node.meaning.input, 'OpenPanel')?.panel) === 'PropertySource');
    assert.ok(source, 'Settings inspection must expose an actual source-view entrance');
    const settingsDepth = listValues(state.application.session.layers).length;
    state = ui.activate_state(state, ui.key(source));
    assert.equal(listValues(state.application.session.layers).length, settingsDepth + 1);
    const sourceNodes = observe(state);
    assert.ok(sourceNodes.some(node => bendTag(node.role) === 'Heading' && /source/i.test(node.label)),
      'The source view must identify its own information activity');
    assert.match(surfaceText(sourceNodes), /filesystem and network: environment defaults/i);
    assert.match(surfaceText(sourceNodes), /approval: custom/i,
      'Manually choosing Ask must remain distinguishable from an inherited policy');
    const sourceBack = sourceNodes.find(node => actualInput(node.meaning.input, 'ClosePanel') && /back/i.test(node.label));
    assert.ok(sourceBack, 'The source view must expose its actual stack return');
    state = ui.activate_state(state, ui.key(sourceBack));
    assert.equal(listValues(state.application.session.layers).length, settingsDepth);
    assert.equal(layer(state).source_expanded, true, 'Source Back must preserve its settings inspection parent');
    state = enter(state, 'sandbox-mode');
    assert.equal(bendTag(layer(state).decision_field), 'Some');
    state = back(state);
    assert.equal(layer(state).source_expanded, true, 'Dependency Back returns to its actual inspection parent');
    assert.equal(bendTag(layer(state).decision_field), 'None');
    state = back(state);
    assert.equal(layer(state).source_expanded, false);
    assert.ok(observe(state).some(node => bendTag(node.meaning) === 'Choice'));
  });
  await t.test('workspace source retains its actual observation and returns to the working-directory editor', () => {
    let state = open(authenticated(singleton), 'WorkspaceConfiguration');
    const source = observe(state).find(node => bendTag(actualInput(node.meaning.input, 'OpenPanel')?.panel) === 'PropertySource');
    assert.ok(source, 'The working-directory editor must expose its actual configuration source');
    const settingsDepth = listValues(state.application.session.layers).length;
    state = ui.activate_state(state, ui.key(source));
    const emitted = observe(state);
    assert.ok(emitted.some(node => bendTag(node.role) === 'Heading' && /source/i.test(node.label)));
    assert.match(surfaceText(emitted), /environment defaults/i,
      'Workspace source must retain the real inherited workspace observation');
    assert.doesNotMatch(surfaceText(emitted), /original.*unavailable|observation.*unavailable/i);
    const sourceBack = emitted.find(node => actualInput(node.meaning.input, 'ClosePanel') && /back/i.test(node.label));
    assert.ok(sourceBack);
    state = ui.activate_state(state, ui.key(sourceBack));
    assert.equal(listValues(state.application.session.layers).length, settingsDepth);
    assert.equal(bendTag(layer(state).panel), 'WorkspaceConfiguration');
    assert.ok(observe(state).some(node => node.label === 'Working directories'),
      'Returning from the source view must retain the actual workspace editor');
  });
  await t.test('cancelling a compound project discards both its name and pending directory before reopening', async () => {
    const created = await singleton.service.command({ op: 'create_project', name: 'Saved lifecycle project',
      workspace: { roots: [oneHome], primary_root: oneHome } });
    assert.equal(created.reply.ok, true);
    const project = bendValue('Some', { value: BigInt(created.reply.result.project_id) });
    const projectEditor = uiValue('ProjectEditor', { project });
    const editProject = state => apply(state, uiValue('Activate', { action: uiValue('EditProject', { project }) }));
    const projectDraft = state => listValues(state.application.session.drafts).find(item => bendTag(item.body) === 'Project'
      && isDeepStrictEqual(item.body.project, project));
    let state = editProject(authenticated(singleton));
    const original = projectDraft(state);
    state = apply(state, uiValue('EditDraft', { editor: projectEditor, edit: uiValue('NameProject', { name: 'Discard this name' }) }));
    state = apply(state, uiValue('EditDraft', { editor: projectEditor, edit: uiValue('WriteDirectory', { path: '/discard/pending/directory' }) }));
    const cancel = observe(state).find(node => node.label === 'Cancel' && actualInput(node.meaning.input, 'ClosePanel'));
    assert.ok(cancel, 'The actual compound surface must expose Cancel');
    const cancelled = input.press(ui.key(cancel), state);
    assert.equal(listValues(cancelled.interaction_effects).some(effect => bendTag(effect) === 'RequestCommand'), false);
    state = editProject(cancelled.state);
    assert.equal(projectDraft(state).body.name, original.body.name);
    assert.deepEqual(projectDraft(state).body.workspace, original.body.workspace);
    assert.equal(projectDraft(state).directory_entry, '');
    assert.equal(bendTag(layer(state).parameter_buffer), 'None');
  });
});

test('committed task forks retain project groups and executable nested sidebar rows', { timeout: 240_000 }, async t => {
  const ui = await browserUI(t, { sourceAdmission: true });
  const directory = await home(t);
  const alphaRoots = ['alpha-guided', 'alpha-empty'].map(name => {
    const root = path.join(directory, name);
    mkdirSync(root);
    return realpathSync(root);
  });
  const alphaWorkspace = { roots: alphaRoots, primary_root: alphaRoots[0] };
  const overridePath = path.join(alphaRoots[0], 'AGENTS.override.md');
  const overrideGuidance = 'Alpha override guidance applies within the guided root.';
  writeFileSync(path.join(alphaRoots[0], 'AGENTS.md'), 'The ordinary guidance is superseded by the override.');
  writeFileSync(overridePath, overrideGuidance);
  const server = await startServer({ home: path.join(directory, 'state'), cwd: directory,
    config: validateConfig({ ...defaultConfig, port: 0, chatgpt: false }) });
  t.after(() => server.close());
  const command = async value => {
    const result = await server.service.command(value);
    assert.equal(result.reply.ok, true, JSON.stringify(result.reply));
    return result.reply.result;
  };
  const project = async (name, workspace = { roots: [] }) => (await command({ op: 'create_project', name, workspace })).project_id;
  const create = async (message, project_id) => {
    const { task_id } = await command({ op: 'create', profile: 'demo', message,
      ...(project_id === undefined ? {} : { settings: { project_id } }) });
    await taskIdle(server.service, task_id);
    return task_id;
  };
  const fork = async (task_id, messages, project_id, workspace) => {
    await taskIdle(server.service, task_id);
    const settings = {
      ...(project_id === undefined ? {} : { project_id }),
      ...(workspace === undefined ? {} : { workspace }),
    };
    const { children } = await command({ op: 'fork', task_id, child_count: messages.length, messages,
      ...(Object.keys(settings).length === 0 ? {} : { settings }) });
    await Promise.all([task_id, ...children].map(id => taskIdle(server.service, id)));
    return children;
  };
  const alpha = await project('Alpha project', alphaWorkspace);
  const beta = await project('Beta project');
  const empty = await project('Empty project');
  const root = await create('Project root 世界', alpha);
  const rootPage = await taskIdle(server.service, root);
  const contextChanges = messages => messages.filter(item => item.type === 'context_change').map(item => item.change);
  const primaryIntroduction = contextChanges(rootPage.messages).find(change => change.type === 'introduce'
    && change.snapshot.key.type === 'project_guidance');
  assert.ok(primaryIntroduction, 'A project with root guidance records its selected source before execution');
  const primaryGuidance = primaryIntroduction.snapshot;
  assert.equal(primaryGuidance.value.fields.path, overridePath);
  assert.equal(primaryGuidance.value.fields.content, overrideGuidance);
  assert.deepEqual(rootPage.task.settings.workspace, alphaWorkspace);
  const [first, second] = await fork(root, ['First child', 'Second child']);
  const firstPage = await taskIdle(server.service, first);
  const switchedWorkspace = { roots: alphaRoots, primary_root: alphaRoots[1] };
  const [grandchild] = await fork(first, ['Grandchild'], alpha, switchedWorkspace);
  const grandchildPage = await taskIdle(server.service, grandchild);
  const switchedChanges = contextChanges(grandchildPage.messages.slice(firstPage.messages.length));
  assert.equal(grandchildPage.task.settings.project_id, alpha);
  assert.deepEqual(grandchildPage.task.settings.workspace, switchedWorkspace);
  assert.ok(switchedChanges.some(change => change.type === 'remove'
    && isDeepStrictEqual(change.key, primaryGuidance.key)), 'An empty new primary root removes the inherited primary guidance');
  assert.equal(switchedChanges.some(change => change.type === 'introduce'
    && change.snapshot.key.type === 'project_guidance'), false, 'An empty primary root does not introduce synthetic guidance');
  assert.ok(switchedChanges.some(change => change.type === 'introduce'
    && change.snapshot.key.type === 'directory_guidance'
    && change.snapshot.value.fields.path === overridePath
    && change.snapshot.value.fields.content === overrideGuidance), 'The former primary retains its selected override as directory guidance');
  const otherRoot = await create('Another project root', alpha);
  const independent = await create('Independent root');
  const [independentChild] = await fork(independent, ['Independent child']);
  const [crossProject] = await fork(root, ['Child in another project'], beta);
  const [returnedProject] = await fork(crossProject, ['Grandchild back in Alpha'], alpha);
  const [betaChild] = await fork(crossProject, ['Child within Beta']);
  await command({ op: 'freeze', task_id: second });

  const response = await fetch(`${server.address}/api/browser/state`, {
    headers: { authorization: `Bearer ${server.token}` },
  });
  assert.equal(response.status, 200);
  const snapshot = decodeBendValue(await response.json());
  const authenticated = ui.authenticated(snapshot.program, BigInt(root));
  assert.equal(bendTag(authenticated), 'Done');
  let state = authenticated.value;
  const navigation = () => surfaceNodes(ui.surface_state(state)).find(node => bendTag(node.role) === 'Navigation');
  const group = id => subtree(navigation()).find(node => bendTag(node.meaning) === 'ProjectGroup'
    && node.meaning.project === BigInt(id));
  const rows = () => subtree(navigation()).filter(node => bendTag(node.meaning) === 'TaskRow');
  const hierarchy = node => {
    const visit = (current, parent) => {
      const tag = bendTag(current.meaning);
      return [
        ...(tag === 'TaskRow' ? [{ task: Number(current.meaning.task), parent }] : []),
        ...listValues(current.children).flatMap(child => visit(child, tag === 'TaskChildren' ? Number(current.meaning.task) : parent)),
      ];
    };
    return visit(node, null);
  };
  const alphaHierarchy = [
    { task: root, parent: null }, { task: first, parent: root }, { task: grandchild, parent: first },
    { task: second, parent: root }, { task: otherRoot, parent: null }, { task: returnedProject, parent: null },
  ];
  assert.deepEqual(hierarchy(group(alpha)), alphaHierarchy);
  assert.deepEqual(hierarchy(group(beta)), [{ task: crossProject, parent: null }, { task: betaChild, parent: crossProject }],
    'A fork into another project starts a visible tree in that project');
  assert.deepEqual(hierarchy(group(empty)), [], 'An empty project must retain its group');
  const independentGroup = subtree(navigation()).find(node => node.semantic === 'independent-tasks');
  assert.ok(independentGroup);
  assert.deepEqual(hierarchy(independentGroup), [{ task: independent, parent: null }, { task: independentChild, parent: independent }]);
  const expectedTasks = [root, first, second, grandchild, otherRoot, independent, independentChild, crossProject, returnedProject, betaChild];
  assert.deepEqual(rows().map(node => Number(node.meaning.task)).sort((a, b) => a - b), expectedTasks.sort((a, b) => a - b),
    'Every committed task must appear exactly once');
  assert.equal(bendTag(rows().find(node => node.meaning.task === BigInt(second)).meaning.status.lifecycle), 'Frozen');

  const descendant = rows().find(node => node.meaning.task === BigInt(grandchild));
  const open = subtree(descendant).find(node => actualUIInput(node.meaning.input, 'Navigate'));
  assert.ok(open, 'A nested descendant must retain its actual navigation command');
  assert.equal(actualUIInput(open.meaning.input, 'Navigate').route.task, BigInt(grandchild));
  state = ui.activate_state(state, ui.key(open));
  assert.deepEqual(rows().filter(node => node.meaning.selected).map(node => Number(node.meaning.task)), [grandchild]);

  const authored = ui.source_admission(state);
  assert.equal(bendTag(authored), 'Done');
  assert.equal(bendTag(authored.value), 'Ready', 'Nested semantic navigation must reach the production browser source');
  const sourceNodes = node => [node, ...listValues(node.children).flatMap(sourceNodes)];
  const data = node => Object.fromEntries(listValues(node.attributes)
    .filter(attribute => bendTag(attribute) === 'DataAttribute').map(attribute => [attribute.name, attribute.value]));
  const depths = sourceNodes(authored.value.source).map(data)
    .filter(attributes => attributes.task !== undefined && attributes['navigation-depth'] !== undefined)
    .map(attributes => [Number(attributes.task), Number(attributes['navigation-depth'])]);
  assert.deepEqual(new Map(depths), new Map([
    [root, 1], [first, 2], [grandchild, 3], [second, 2], [otherRoot, 1], [returnedProject, 1],
    [crossProject, 1], [betaChild, 2], [independent, 0], [independentChild, 1],
  ]), 'Browser-authored indentation must follow immediate parents inside each project group');

  const toggle = subtree(group(alpha)).find(node => actualUIInput(node.meaning.input, 'ToggleProjectGroup'));
  assert.ok(toggle);
  state = ui.activate_state(state, ui.key(toggle));
  assert.equal(group(alpha).meaning.expanded, false);
  assert.deepEqual(hierarchy(group(alpha)), [], 'Project collapse hides its complete task tree');
  assert.equal(rows().some(node => node.meaning.task === BigInt(betaChild)), true);
  state = ui.activate_state(state, ui.key(toggle));
  assert.equal(group(alpha).meaning.expanded, true);
  assert.deepEqual(hierarchy(group(alpha)), alphaHierarchy);
  assert.deepEqual(rows().filter(node => node.meaning.selected).map(node => Number(node.meaning.task)), [grandchild]);
});
