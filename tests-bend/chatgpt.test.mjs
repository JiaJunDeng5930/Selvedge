import test from 'node:test';
import assert from 'node:assert/strict';
import { requestModel, responseBody, providerInput } from '../host/providers.mjs';
import { chatgptSession, modelsURL, codexContractVersion } from '../host/chatgpt-contract.mjs';
import { chatgptFixture, fakeTokens, jsonResponse, modelResponse, modelEffect, wireLimits } from './fixtures/chatgpt.mjs';

test('ChatGPT wire uses the Codex string tool choice and never exposes withheld tools', async t => {
  const output = [
    { type: 'reasoning', id: 'rs-fixture', encrypted_content: 'opaque-fixture', summary: [] },
    { type: 'message', id: 'msg-fixture', role: 'assistant', phase: 'final_answer', content: [{ type: 'output_text', text: 'done' }] },
  ];
  const upstream = await chatgptFixture(t, (request, response) => {
    assert.equal(request.url, '/backend-api/codex/responses');
    assert.equal(request.method, 'POST');
    assert.equal(request.headers['chatgpt-account-id'], 'fixture-account');
    assert.equal(request.headers.originator, 'selvedge');
    assert.equal(request.headers.session_id, request.body.prompt_cache_key);
    assert.match(request.headers.session_id, /^[a-f0-9-]{36}$/);
    assert.equal(request.body.tool_choice, 'auto');
    assert.deepEqual(request.body.tools.map(tool => tool.name), ['allowed']);
    assert.equal(request.body.stream, true);
    assert.equal(request.body.store, false);
    assert.deepEqual(request.body.include, ['reasoning.encrypted_content']);
    modelResponse(response, output);
  });
  const result = await requestModel(modelEffect(), { profiles: { fixture: upstream.profile } }, upstream.directory, wireLimits);
  assert.deepEqual(result.map(item => item.value), output);
  assert.deepEqual(providerInput(result.map(item => ({ role: 'model_context', content: item.value }))), output);
  assert.deepEqual(upstream.failures, []);
  assert.equal(responseBody({ ...modelEffect(), callable: [] }).tool_choice, 'auto');
  assert.deepEqual(responseBody({ ...modelEffect(), callable: [] }).tools, []);
  assert.equal(responseBody(modelEffect(), { provider: 'responses' }).tool_choice.type, 'allowed_tools');
});

test('ChatGPT refreshes a rejected credential once and rebuilds the account headers', async t => {
  let posts = 0;
  let refreshes = 0;
  const upstream = await chatgptFixture(t, (request, response) => {
    if (request.url === '/oauth/token') {
      refreshes++;
      assert.equal(request.headers['content-type'], 'application/json');
      assert.equal(request.body.grant_type, 'refresh_token');
      jsonResponse(response, fakeTokens('fixture-account', 'renewed'));
    } else if (++posts === 1) jsonResponse(response, { error: 'fixture rejection' }, 401);
    else {
      assert.ok(request.headers.authorization.endsWith('.renewed'));
      modelResponse(response, [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'ok' }] }]);
    }
  });
  await requestModel(modelEffect(), { profiles: { fixture: upstream.profile } }, upstream.directory, wireLimits);
  assert.equal(posts, 2);
  assert.equal(refreshes, 1);
  assert.deepEqual(upstream.failures, []);
});

test('model discovery URL preserves routing parameters and version; session identity is scoped', () => {
  const url = new URL(modelsURL('https://example.invalid/backend-api/codex/responses?route=fixture'));
  assert.equal(url.pathname, '/backend-api/codex/models');
  assert.equal(url.searchParams.get('route'), 'fixture');
  assert.equal(url.searchParams.get('client_version'), codexContractVersion);
  assert.throws(() => modelsURL('https://example.invalid/other'), /responses/);
  assert.equal(chatgptSession('/fixture/a', 1), chatgptSession('/fixture/a', 1));
  assert.notEqual(chatgptSession('/fixture/a', 1), chatgptSession('/fixture/a', 2));
  assert.notEqual(chatgptSession('/fixture/a', 1), chatgptSession('/fixture/b', 1));
});
