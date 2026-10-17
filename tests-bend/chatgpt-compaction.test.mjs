import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { readFile, writeFile } from 'node:fs/promises';
import { setTimeout as delay } from 'node:timers/promises';
import { taskIdle } from './support.mjs';
import { jsonResponse, modelResponse, compactResponse } from './fixtures/chatgpt.mjs';
import { accountCompactionService as fixtureService, contextReplaced, until } from './fixtures/compaction.mjs';

const assistant = text => ({ type: 'message', role: 'assistant', content: [{ type: 'output_text', text }] });
const opaque = { type: 'compaction', id: 'cmp_fixture', encrypted_content: 'opaque-native-checkpoint' };
const compact = request => request.url === '/v1/responses/compact';
const replacementEvents = page => page.messages.filter(message => message.role === 'context_replacement');

test('account native compaction replaces the sent window, keeps original history and survives journal recovery', { timeout: 15_000 }, async t => {
  const originalRequest = 'Original user request.';
  const longAnswer = 'Original answer retained in history. '.repeat(80);
  let compactCalls = 0, modelCalls = 0;
  const retained = { role: 'user', content: originalRequest };
  const running = await fixtureService(t, (request, response) => {
    if (compact(request)) {
      compactCalls++;
      assert.equal(request.body.model, 'fixture-model');
      assert.ok(request.body.input.some(item => item.role === 'user' && item.content === originalRequest));
      assert.ok(JSON.stringify(request.body.input).includes(longAnswer));
      assert.equal(request.body.input.some(item => /Summarize this task/.test(item.content)), false);
      return compactResponse(response, [retained, opaque]);
    }
    modelCalls++;
    if (modelCalls > 1) {
      assert.equal(request.body.input.filter(item => item.role === 'user' && item.content === originalRequest).length, 1);
      assert.equal(request.body.input.filter(item => item.type === 'compaction').length, 1);
      assert.deepEqual(request.body.input.find(item => item.type === 'compaction'), opaque);
      assert.equal(JSON.stringify(request.body.input).includes(longAnswer), false);
      assert.ok(request.body.input.some(item => item.role === 'user' && /Continue after/.test(item.content)));
    }
    modelResponse(response, [assistant(modelCalls === 1 ? longAnswer : 'Continued.')]);
  });
  await running.service.command({ op: 'create', profile: 'fixture', message: originalRequest });
  const before = await taskIdle(running.service);
  await running.service.command({ op: 'compact', task_id: 0 });
  const after = await contextReplaced(running.service);
  assert.deepEqual(after.messages.slice(0, before.messages.length), before.messages);
  assert.equal(replacementEvents(after).length, 1);
  assert.equal(modelCalls, 1, 'Compaction does not start another ordinary turn');
  await running.service.command({ op: 'send', task_id: 0, message: 'Continue after compaction.' });
  await taskIdle(running.service);
  await running.restart();
  await running.service.command({ op: 'send', task_id: 0, message: 'Continue after restart.' });
  const recovered = await taskIdle(running.service);
  assert.ok(JSON.stringify(recovered.messages).includes(longAnswer));
  assert.equal(replacementEvents(recovered).length, 1);
  assert.equal(compactCalls, 1); assert.equal(modelCalls, 3);
  assert.deepEqual(running.failures, []);
});

test('native compaction keeps historical tool records as context without executing their side effect again', { timeout: 15_000 }, async t => {
  let models = 0, retainedTools;
  const invocation = { type: 'function_call', namespace: 'selvedge', call_id: 'write-once', name: 'bash',
    arguments: JSON.stringify({ command: "printf 'once\\n' >> executed.txt" }) };
  const running = await fixtureService(t, (request, response) => {
    if (compact(request)) {
      assert.equal(retainedTools.length, 2);
      return compactResponse(response, [...retainedTools, opaque]);
    }
    models++;
    if (models === 1) return modelResponse(response, [invocation]);
    const pair = request.body.input.filter(item => ['function_call', 'function_call_output'].includes(item.type));
    if (models === 2) retainedTools = pair;
    else assert.deepEqual(pair, retainedTools);
    modelResponse(response, [assistant('Finished.')]);
  });
  await running.service.command({ op: 'create', profile: 'fixture', message: 'Write the artifact once.' });
  await taskIdle(running.service);
  const filename = path.join(running.directory, 'executed.txt');
  assert.equal(await readFile(filename, 'utf8'), 'once\n');
  await running.service.command({ op: 'compact', task_id: 0 });
  await contextReplaced(running.service);
  await running.service.command({ op: 'send', task_id: 0, message: 'Continue without repeating the write.' });
  await taskIdle(running.service);
  await running.restart();
  await running.service.command({ op: 'send', task_id: 0, message: 'Continue after restart.' });
  const page = await taskIdle(running.service);
  assert.equal(await readFile(filename, 'utf8'), 'once\n');
  assert.equal(page.messages.filter(message => message.role === 'function_output').length, 1);
  assert.equal(replacementEvents(page).length, 1);
  assert.equal(models, 4);
  assert.deepEqual(running.failures, []);
});

test('compaction during a real pending tool preserves complete call and result pairs', { timeout: 15_000 }, async t => {
  let models = 0, compactions = 0;
  const completePairs = input => {
    const calls = new Set();
    for (const item of input) {
      if (item.type === 'function_call') calls.add(item.call_id);
      if (item.type === 'function_call_output') {
        assert.ok(calls.delete(item.call_id), 'A result must retain its matching invocation');
      }
    }
    assert.equal(calls.size, 0, 'A compaction source or subsequent model request cannot end inside a tool exchange');
  };
  const running = await fixtureService(t, (request, response) => {
    if (compact(request)) {
      compactions++; completePairs(request.body.input);
      return compactResponse(response, [opaque]);
    }
    models++;
    if (models === 1) return modelResponse(response, [{ type: 'function_call', namespace: 'selvedge', call_id: 'held-tool', name: 'bash',
      arguments: JSON.stringify({ command: "printf started > held.started; while [ ! -f release-held ]; do sleep 0.01; done; printf 'once\\n' >> held.executions; printf 'tool complete'" }) }]);
    completePairs(request.body.input);
    modelResponse(response, [assistant('The tool completed.')]);
  });
  const release = path.join(running.directory, 'release-held');
  await running.service.command({ op: 'create', profile: 'fixture', message: 'Complete this tool exchange once.' });
  await until('the held Bash process', async () => {
    try { return await readFile(path.join(running.directory, 'held.started'), 'utf8') === 'started'; }
    catch (error) { if (error.code === 'ENOENT') return false; throw error; }
  });
  const compacted = await running.service.command({ op: 'compact', task_id: 0 });
  assert.equal(compacted.reply.ok, true);
  await delay(60);
  await writeFile(release, 'release');
  await contextReplaced(running.service);
  const page = await taskIdle(running.service);
  assert.equal(await readFile(path.join(running.directory, 'held.executions'), 'utf8'), 'once\n');
  assert.equal(compactions, 1);
  assert.equal(page.messages.filter(message => message.role === 'function_output').length, 1);
  assert.deepEqual(running.failures, []);
});

test('cancelled and archived tasks cannot install a late native replacement', async t => {
  for (const control of ['interrupt', 'archive']) await t.test(control, async t => {
  let models = 0, pending;
  const started = Promise.withResolvers();
  const running = await fixtureService(t, (request, response) => {
    if (compact(request)) { pending = response; started.resolve(); }
    else { models++; modelResponse(response, [assistant('Finished.')]); }
  });
  await running.service.command({ op: 'create', profile: 'fixture', message: 'A task.' });
  await taskIdle(running.service);
  await running.service.command({ op: 'compact', task_id: 0 });
  await started.promise;
  await running.service.command({ op: control, task_id: 0 });
  compactResponse(pending, [opaque]);
  await delay(30);
  const page = await taskIdle(running.service);
  assert.equal(page.task.status, control === 'archive' ? 'archived' : 'stopped');
  assert.equal(replacementEvents(page).length, 0);
  assert.equal(models, 1);
  assert.deepEqual(running.failures, []);
  });
});

test('restart resumes pending compaction without repeating the ordinary model turn or installing twice', { timeout: 15_000 }, async t => {
  let models = 0, compactions = 0;
  const started = Promise.withResolvers();
  const running = await fixtureService(t, (request, response) => {
    if (compact(request)) {
      if (++compactions === 1) started.resolve();
      else compactResponse(response, [opaque]);
      return;
    }
    models++; modelResponse(response, [assistant('Finished.')]);
  });
  await running.service.command({ op: 'create', profile: 'fixture', message: 'Keep this task across restart.' });
  await taskIdle(running.service);
  await running.service.command({ op: 'compact', task_id: 0 });
  await started.promise;
  await running.restart();
  const recovered = await contextReplaced(running.service);
  assert.equal(compactions, 2);
  assert.equal(models, 1);
  assert.equal(replacementEvents(recovered).length, 1);
  await running.restart();
  const again = await taskIdle(running.service);
  assert.deepEqual(again.messages, recovered.messages);
  assert.equal(compactions, 2);
  assert.equal(models, 1);
  assert.deepEqual(running.failures, []);
});

test('an upstream context-limit error remains an ordinary failed call rather than an implicit retry loop', async t => {
  let compactions = 0, models = 0;
  const running = await fixtureService(t, (request, response) => {
    if (compact(request)) { compactions++; return compactResponse(response, [opaque]); }
    models++;
    jsonResponse(response, { error: { code: 'context_length_exceeded', message: 'private upstream details' } }, 400);
  });
  await running.service.command({ op: 'create', profile: 'fixture', message: 'A small request.' });
  const page = await taskIdle(running.service);
  assert.equal(compactions, 0); assert.equal(models, 1);
  assert.ok(page.messages.some(message => message.role === 'error'));
  assert.equal(JSON.stringify(page).includes('private upstream details'), false);
  assert.deepEqual(running.failures, []);
});
