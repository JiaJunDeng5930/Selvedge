import test from 'node:test';
import assert from 'node:assert/strict';
import { requestModel, responseBody, providerInput } from '../host/providers.mjs';
import { modelsURL } from '../host/chatgpt-contract.mjs';
import { chatgptFixture, jsonResponse, modelResponse, modelEffect, wireLimits } from './fixtures/chatgpt.mjs';

test('ChatGPT Responses uses the official namespace and preserves opaque reasoning history', async t => {
  const output = [
    { type: 'reasoning', id: 'rs-fixture', encrypted_content: 'opaque-fixture', summary: [] },
    { type: 'message', id: 'msg-fixture', role: 'assistant', content: [{ type: 'output_text', text: 'done' }] },
  ];
  const upstream = await chatgptFixture(t, (request, response) => {
    assert.equal(request.url, '/v1/responses'); assert.equal(request.method, 'POST');
    assert.equal(request.body.tool_choice, 'auto');
    assert.deepEqual(request.body.tools.map(tool => ({ type: tool.type, name: tool.name, names: tool.tools.map(item => item.name) })),
      [{ type: 'namespace', name: 'selvedge', names: ['allowed'] }]);
    assert.deepEqual(request.body.include, ['reasoning.encrypted_content']);
    modelResponse(response, output);
  });
  const result = await requestModel(modelEffect(), { profiles: { fixture: upstream.profile } }, upstream.directory, wireLimits);
  assert.deepEqual(result.map(item => item.value), output);
  assert.deepEqual(providerInput(result.map(item => ({ role: 'model_context', content: item.value }))), output);
  assert.deepEqual(upstream.failures, []);
  assert.equal(responseBody({ ...modelEffect(), callable: [] }, { provider: 'chatgpt' }).tool_choice, 'none');
  assert.deepEqual(responseBody({ ...modelEffect(), callable: [] }, { provider: 'chatgpt' }).tools, []);
  assert.equal(responseBody(modelEffect(), { provider: 'responses' }).tool_choice.type, 'allowed_tools');
});

test('namespace call and result history is retained and foreign tool namespaces fail', async t => {
  let namespace = 'selvedge';
  const upstream = await chatgptFixture(t, (request, response) => {
    if (request.body.input.some(item => item.type === 'function_call')) {
      const call = request.body.input.find(item => item.type === 'function_call');
      assert.equal(call.namespace, 'selvedge');
      assert.ok(request.body.input.some(item => item.type === 'function_call_output' && item.call_id === call.call_id));
    }
    modelResponse(response, [{ type: 'function_call', namespace, call_id: 'call-fixture', name: 'allowed', arguments: '{}' }]);
  });
  const config = { profiles: { fixture: upstream.profile } };
  const result = await requestModel(modelEffect(), config, upstream.directory, wireLimits);
  assert.equal(result[0].type, 'call'); assert.equal(result[0].name, 'allowed');
  await requestModel({ ...modelEffect(), history: [{ role: 'function_call', content: { id: 'call-fixture', name: 'allowed', arguments: {} } },
    { role: 'function_output', call_id: 'call-fixture', content: 'done', is_error: false }] }, config, upstream.directory, wireLimits);
  namespace = 'foreign';
  await assert.rejects(requestModel(modelEffect(), config, upstream.directory, wireLimits), /namespace/i);
  assert.deepEqual(upstream.failures, []);
});

test('ChatGPT refreshes one rejected opaque credential and retries only once', async t => {
  let posts = 0;
  const upstream = await chatgptFixture(t, (_, response) => {
    if (++posts === 1) jsonResponse(response, { error: 'fixture rejection' }, 401);
    else modelResponse(response, [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'ok' }] }]);
  });
  await requestModel(modelEffect(), { profiles: { fixture: upstream.profile } }, upstream.directory, wireLimits);
  assert.equal(posts, 2);
  assert.equal(upstream.oauthRequests.filter(request => request.url === '/oauth/token').length, 1);
  assert.deepEqual(upstream.failures, []);
});

test('a second authorization rejection stops after one refresh', async t => {
  const upstream = await chatgptFixture(t, (_, response) => jsonResponse(response, { error: 'fixture rejection' }, 401));
  await assert.rejects(requestModel(modelEffect(), { profiles: { fixture: upstream.profile } }, upstream.directory, wireLimits), /HTTP 401/);
  assert.equal(upstream.requests.length, 2);
  assert.equal(upstream.oauthRequests.filter(request => request.url === '/oauth/token').length, 1);
  assert.deepEqual(upstream.failures, []);
});

test('model discovery preserves routing parameters without adding a client version', () => {
  const url = new URL(modelsURL('https://api.openai.com/v1/responses?route=fixture'));
  assert.equal(url.pathname, '/v1/models'); assert.equal(url.searchParams.get('route'), 'fixture');
  assert.equal(url.searchParams.has('client_version'), false);
  assert.throws(() => modelsURL('https://example.invalid/other'), /responses/);
});
