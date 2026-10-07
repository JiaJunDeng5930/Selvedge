import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdir, readFile, realpath } from 'node:fs/promises';
import { DatabaseSync } from 'node:sqlite';
import { setTimeout as delay } from 'node:timers/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { startServer } from '../host/server.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { approvalOutcome } from '../host/approvals.mjs';
import { bendTag, decodeBendValue } from '../host/public/bend-value.mjs';
import { home, responsesServer, shellQuote, taskIdle, browserUI, surfaceNodes as nodes } from './support.mjs';

const answer = text => [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text }] }];
const find = (view, semantic) => nodes(view.surface).find(node => node.semantic === semantic);
const regionNodes = region => nodes({ base: { $: 'Con', head: region, tail: { $: 'Nil' } }, overlays: { $: 'Nil' } });
const approvalControl = (view, operation, semantic) => regionNodes(find(view, `approval/${operation}`)).find(node => node.semantic === semantic);
const available = node => bendTag(node.meaning.availability) === 'Available';
const observations = region => regionNodes(region).filter(node => bendTag(node.meaning) === 'ReadOnly').map(node => node.meaning.text);
const pressedCommand = (view, node) => {
  const result = view.ui.press_state(view.state, view.ui.key(node));
  assert.equal(result.$, 'Done');
  const commands = JSON.parse(result.value);
  assert.equal(commands.length, 1);
  return commands[0];
};
const probe = fileURLToPath(new URL('./fixtures/approved-tool.mjs', import.meta.url));

function journal(state) {
  const db = new DatabaseSync(path.join(state, 'journal.sqlite'), { readOnly: true });
  try { return db.prepare('SELECT input, decision FROM journal ORDER BY seq').all()
    .map(row => ({ input: JSON.parse(row.input), ...JSON.parse(row.decision) })); }
  finally { db.close(); }
}

async function pending(service, task_id = 0) {
  const deadline = Date.now() + 5000;
  do {
    const page = (await service.command({ op: 'read', task_id })).reply.result;
    const operation = page.task.operations.find(operation => operation.status === 'awaiting_approval');
    if (operation) return { page, operation };
    await delay(10);
  } while (Date.now() < deadline);
  throw new Error('The real provider did not produce a pending approval');
}

async function fixture(t, review = () => answer(JSON.stringify({ decision: 'allow', reason: 'The user requested this exact file.' }))) {
  const base = await realpath(await home(t));
  const workspace = path.join(base, 'workspace');
  const state = path.join(base, 'state');
  const marker = path.join(base, 'outside-workspace.txt');
  await mkdir(workspace);
  const api_key_env = 'SELVEDGE_APPROVAL_FIXTURE';
  const previous = process.env[api_key_env];
  process.env[api_key_env] = 'local-fixture-only';
  t.after(() => { if (previous === undefined) delete process.env[api_key_env]; else process.env[api_key_env] = previous; });
  const arguments_ = {
    command: [process.execPath, probe, path.join(state, 'journal.sqlite'), marker, 'approval-shell'].map(shellQuote).join(' '),
    sandbox_permissions: 'require_escalated', justification: 'Write the one requested file outside the workspace.',
    timeout_ms: 5000,
  };
  const upstream = await responsesServer(t, body => body.model === 'review-model' ? review(body, state) :
    body.input.some(item => item.type === 'function_call_output') ? answer('The operation has settled.') :
      [{ type: 'function_call', call_id: 'approval-shell', name: 'bash', arguments: JSON.stringify(arguments_) }]);
  const config = validateConfig({ ...defaultConfig, chatgpt: false, port: 0, profiles: {
    worker: { provider: 'responses', model: 'worker-model', endpoint: upstream.endpoint, api_key_env },
    reviewer: { provider: 'responses', model: 'review-model', endpoint: upstream.endpoint, api_key_env },
  } });
  const options = { home: state, cwd: workspace, config };
  const f = { base, state, workspace, marker, arguments_, upstream, options, site: await startServer(options) };
  t.after(() => f.site.close());
  const ui = await browserUI(t);
  f.post = async (command, authorized = true) => {
    const response = await fetch(`${f.site.address}/api/browser/command`, { method: 'POST',
      headers: { 'content-type': 'application/json', ...(authorized ? { authorization: `Bearer ${f.site.token}` } : {}) },
      body: JSON.stringify({ command }) });
    return { status: response.status, body: await response.json() };
  };
  f.view = async (id = 0) => {
    const response = await fetch(`${f.site.address}/api/browser/state`, { headers: { authorization: `Bearer ${f.site.token}` } });
    assert.equal(response.status, 200);
    const { program } = decodeBendValue(await response.json());
    const task = BigInt(id);
    const authenticated = ui.authenticated(program, task, f.site.token);
    assert.equal(authenticated.$, 'Done');
    const state = authenticated.value;
    return { ui, program, task, state, surface: ui.surface_state(state) };
  };
  f.settings = mode => ({ workspace: { roots: [workspace], primary_root: workspace },
    approval: { mode, ...(mode === 'approval-for-me' ? { reviewer_profile: 'reviewer' } : {}) } });
  f.create = async (mode = 'ask-for-approval') => {
    const result = await f.post({ op: 'create', profile: 'worker', reasoning: 'medium',
      message: `Write only ${marker}.`, settings: f.settings(mode) });
    assert.equal(result.status, 200, JSON.stringify(result.body));
    assert.equal(result.body.reply.ok, true, JSON.stringify(result.body.reply));
    return result;
  };
  return f;
}

test('HTTP approval UI commits a one-use grant before a real outside-workspace process and rejects stale clicks', { timeout: 20_000 }, async t => {
  const f = await fixture(t);
  await f.create();
  const { operation, page: before } = await pending(f.site.service);
  const view = await f.view();
  const allow = approvalControl(view, operation.operation_id, 'approve');
  assert.equal(available(allow), true);
  assert.equal(available(approvalControl(view, operation.operation_id, 'deny')), true);
  const facts = observations(find(view, `approval/${operation.operation_id}`));
  for (const value of [f.arguments_.command, f.arguments_.justification, f.workspace]) assert.ok(facts.includes(value));
  const command = pressedCommand(view, allow);
  await assert.rejects(readFile(f.marker), { code: 'ENOENT' });
  const sequence = f.site.service.journal.sequence;
  assert.equal((await f.post(command, false)).status, 401);
  assert.equal(f.site.service.journal.sequence, sequence);
  assert.equal((await f.post(command)).status, 200);
  const page = await taskIdle(f.site.service);
  assert.equal(await readFile(f.marker, 'utf8'), 'ran\n');
  assert.deepEqual(page.task.settings, before.task.settings);
  assert.equal(page.messages.find(message => message.role === 'approval_record').content.decision, 'allow');
  assert.equal(nodes((await f.view()).surface).find(node => view.ui.key(node) === view.ui.key(allow)), undefined);
  const stale = await f.post(command);
  assert.equal(stale.status, 400);
  assert.equal(stale.body.reply.ok, false);
  assert.equal(stale.body.reply.error.code, 'approval_not_pending');
  assert.equal(await readFile(f.marker, 'utf8'), 'ran\n');
  assert.deepEqual(f.upstream.failures, []);
});

test('denial, UI cancellation and a real journal reopen do not dispatch or replay an unapproved command', { timeout: 30_000 }, async t => {
  for (const action of ['deny', 'cancel', 'restart']) await t.test(action, async t => {
    const f = await fixture(t);
    await f.create();
    const { operation } = await pending(f.site.service);
    const view = await f.view();
    const allow = approvalControl(view, operation.operation_id, 'approve');
    const command = pressedCommand(view, allow);
    if (action === 'restart') {
      await f.site.close();
      f.site = await startServer(f.options);
    } else {
      const control = action === 'deny' ? approvalControl(view, operation.operation_id, 'deny') : find(view, `cancel/${operation.operation_id}`);
      assert.equal((await f.post(pressedCommand(view, control))).status, 200);
    }
    const page = await taskIdle(f.site.service);
    assert.equal(page.task.operations.length, 0);
    const stale = await f.post(command);
    assert.equal(stale.status, 400);
    assert.equal(stale.body.reply.ok, false);
    assert.equal(stale.body.reply.error.code, 'approval_not_pending');
    await assert.rejects(readFile(f.marker), { code: 'ENOENT' });
    assert.equal(journal(f.state).flatMap(row => row.effects).filter(effect => effect.kind === 'tool').length, 0);
    if (action === 'restart') assert.match(JSON.stringify(page), /approval_interrupted/);
    assert.deepEqual(f.upstream.failures, []);
  });
});

test('Approval for Me crosses a committed tool-free provider request and starts no extra task', { timeout: 20_000 }, async t => {
  let reviewerInput;
  const f = await fixture(t, (body, state) => {
    assert.deepEqual(body.tools, []);
    assert.equal(body.tool_choice, 'none');
    assert.equal(body.reasoning, undefined);
    reviewerInput = JSON.parse(body.input.findLast(item => item.role === 'user').content);
    const effects = journal(state).flatMap(row => row.effects);
    assert.equal(effects.filter(effect => effect.kind === 'approval').length, 1);
    assert.equal(effects.filter(effect => effect.kind === 'tool').length, 0);
    return answer(JSON.stringify({ decision: 'allow', reason: 'The one requested file write is authorized.' }));
  });
  const notices = [];
  f.site.service.on('notice', notice => notices.push(notice));
  await f.create('approval-for-me');
  const page = await taskIdle(f.site.service);
  assert.equal(await readFile(f.marker, 'utf8'), 'ran\n');
  assert.deepEqual(reviewerInput.command.arguments, f.arguments_);
  assert.deepEqual(reviewerInput.recent_user_requests_newest_first, [`Write only ${f.marker}.`]);
  assert.equal(f.upstream.requests.filter(body => body.model === 'review-model').length, 1);
  assert.equal((await f.site.service.command({ op: 'list' })).reply.result.tasks.length, 1);
  const review = journal(f.state).flatMap(row => row.effects).find(effect => effect.kind === 'approval');
  assert.ok(!notices.some(notice => notice.type === 'stream_start' && notice.ticket === review.ticket));
  assert.equal(page.messages.find(message => message.role === 'approval_record').reviewer.kind, 'model');
  assert.deepEqual(f.upstream.failures, []);
});

test('malformed model authority fails closed and a cancelled independent review cannot launch Bash', { timeout: 30_000 }, async t => {
  await t.test('malformed response', async t => {
    const f = await fixture(t, () => answer(JSON.stringify({ decision: 'allow', reason: 'Yes', command: 'another command' })));
    await f.create('approval-for-me');
    const page = await taskIdle(f.site.service);
    assert.equal(page.messages.find(message => message.role === 'approval_record').content.decision, 'failed');
    await assert.rejects(readFile(f.marker), { code: 'ENOENT' });
    assert.equal(f.upstream.requests.filter(body => body.model === 'review-model').length, 1);
    assert.deepEqual(f.upstream.failures, []);
  });
  await t.test('cancel a pending provider response', async t => {
    const review = Promise.withResolvers();
    t.after(() => review.resolve(answer(JSON.stringify({ decision: 'allow', reason: 'Late answer' }))));
    const f = await fixture(t, () => review.promise);
    await f.create('approval-for-me');
    const { operation } = await pending(f.site.service);
    const view = await f.view();
    assert.equal(approvalControl(view, operation.operation_id, 'approve'), undefined);
    const region = find(view, `approval/${operation.operation_id}`);
    assert.match(regionNodes(region).find(node => node.semantic === 'reviewer').meaning.text, /review-model/);
    const cancel = find(view, `cancel/${operation.operation_id}`);
    assert.equal((await f.post(pressedCommand(view, cancel))).status, 200);
    review.resolve(answer(JSON.stringify({ decision: 'allow', reason: 'A now stale answer' })));
    await taskIdle(f.site.service);
    await assert.rejects(readFile(f.marker), { code: 'ENOENT' });
    assert.equal(journal(f.state).flatMap(row => row.effects).filter(effect => effect.kind === 'tool').length, 0);
    assert.deepEqual(f.upstream.failures, []);
  });
});

test('the reviewer transport decoder rejects ambiguous, overlong or authority-shaped responses', () => {
  const items = text => [{ type: 'context', value: answer(text)[0] }];
  assert.deepEqual(approvalOutcome(items('{"decision":"allow","reason":"好好"}'), 6), { decision: 'allow', reason: '好好' });
  assert.deepEqual(approvalOutcome(items('{"reason":"line\\nquote\\\"","decision":"deny"}'), 2048),
    { decision: 'deny', reason: 'line\nquote"' });
  for (const text of [
    '```json\n{"decision":"allow","reason":"yes"}\n```',
    '{"decision":"allow","reason":""}', '{"decision":"allow","reason":"   "}',
    '{"decision":"allow","reason":"yes","command":"other"}',
    '{"decision":"deny","decision":"allow","reason":"duplicate"}',
    '{"decision":"deny","\\u0064ecision":"allow","reason":"escaped duplicate"}',
    '{"decision":"allow","reason":"\\u0000"}',
    JSON.stringify({ decision: 'allow', reason: 'x'.repeat(2049) }),
  ]) assert.throws(() => approvalOutcome(items(text), 2048));
  const valid = items('{"decision":"deny","reason":"Not authorized"}');
  assert.throws(() => approvalOutcome([...valid, ...valid], 2048));
  assert.throws(() => approvalOutcome([{ type: 'call', name: 'bash', arguments: {} }], 2048));
  assert.throws(() => approvalOutcome(valid, undefined));
});
