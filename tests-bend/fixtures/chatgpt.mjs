import http from 'node:http';
import path from 'node:path';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { generateKeyPair, exportJWK, SignJWT } from 'jose';
import { writeAtomic } from '../../host/files.mjs';
import { defaultChatGPTAccount, chatgptAccountIdentity } from '../../host/chatgpt-account.mjs';
import { home } from '../support.mjs';

const resource = 'https://api.openai.com/v1';
const scope = 'openid profile email offline_access resource.invoke chatgpt.tokens.use.direct';

export async function chatgptFixture(t, handler = (_, response) => jsonResponse(response, {})) {
  const directory = await home(t);
  const failures = [], requests = [], oauthRequests = [];
  const { privateKey, publicKey } = await generateKeyPair('RS256');
  const jwk = { ...await exportJWK(publicKey), kid: 'fixture-key', use: 'sig', alg: 'RS256' };
  const options = { subject: 'fixture-account', marker: 'original', client_id: 'fixture-issued-client',
    scope, expires_in: 3600, earliest_refresh_at: null };
  const authorizations = new Map();
  let address;
  const tokens = async (overrides = {}) => {
    const value = { ...options, ...overrides };
    const id_token = await new SignJWT({ nonce: value.nonce, name: 'Fixture User', email: 'fixture@example.invalid',
      ...(value.claims ?? {}) }).setProtectedHeader({ alg: 'RS256', kid: 'fixture-key' })
      .setIssuer(address).setSubject(value.subject).setAudience(value.audience ?? value.client_id)
      .setIssuedAt().setExpirationTime('1h').sign(value.privateKey ?? privateKey);
    const response = { access_token: `opaque-access-${value.marker}`, refresh_token: `fixture-refresh-${value.marker}`,
      token_type: 'Bearer', id_token, scope: value.scope, expires_in: value.expires_in,
      ...(value.earliest_refresh_at === null ? {} : { earliest_refresh_at: value.earliest_refresh_at }) };
    for (const key of value.tokenOmissions ?? []) delete response[key];
    return response;
  };
  const server = http.createServer((request, response) => {
    void (async () => {
      const chunks = [];
      for await (const chunk of request) chunks.push(chunk);
      const raw = Buffer.concat(chunks).toString('utf8');
      const mediaType = request.headers['content-type']?.split(';')[0].trim().toLowerCase();
      const body = raw ? mediaType === 'application/x-www-form-urlencoded'
        ? Object.fromEntries(new URLSearchParams(raw)) : JSON.parse(raw) : undefined;
      const entry = { method: request.method, url: request.url, headers: request.headers, body };
      const url = new URL(request.url, address);
      if (url.pathname === '/.well-known/openid-configuration') {
        oauthRequests.push(entry);
        return jsonResponse(response, { issuer: address, authorization_endpoint: `${address}/authorize`,
          token_endpoint: `${address}/oauth/token`, jwks_uri: `${address}/jwks`,
          response_types_supported: ['code'], subject_types_supported: ['public'],
          id_token_signing_alg_values_supported: ['RS256'], token_endpoint_auth_methods_supported: ['none'],
          code_challenge_methods_supported: ['S256'], scopes_supported: scope.split(' ') });
      }
      if (url.pathname === '/jwks') { oauthRequests.push(entry); return jsonResponse(response, { keys: [jwk] }); }
      if (url.pathname === '/authorize') {
        oauthRequests.push(entry);
        const query = url.searchParams;
        assert.equal(query.get('response_type'), 'code');
        assert.equal(query.get('resource'), resource);
        assert.equal(query.get('scope'), scope);
        assert.equal(query.get('code_challenge_method'), 'S256');
        assert.match(query.get('state'), /^[A-Za-z0-9_-]{20,}$/);
        assert.match(query.get('nonce'), /^[A-Za-z0-9_-]{20,}$/);
        assert.match(query.get('ext_agent_host_id'), /^[a-f0-9-]{36}$/);
        const first = query.get('client_id') === 'dynamic_agent_client';
        assert.equal(query.get('agent_name_hint'), first ? 'Selvedge' : null);
        if (!first) assert.equal(query.get('client_id'), options.client_id);
        const callback = new URL(query.get('redirect_uri'));
        assert.equal(callback.hostname, '127.0.0.1');
        assert.equal(callback.pathname, '/auth/callback');
        const code = `fixture-grant-${authorizations.size}`;
        authorizations.set(code, { nonce: query.get('nonce'), challenge: query.get('code_challenge'), redirect: callback.href });
        callback.searchParams.set('code', code);
        callback.searchParams.set('state', options.callbackState ?? query.get('state'));
        if (first) callback.searchParams.set('client_id', options.client_id);
        response.writeHead(302, { location: callback.href }); return response.end();
      }
      if (url.pathname === '/oauth/token') {
        oauthRequests.push(entry);
        assert.equal(request.method, 'POST');
        assert.equal(mediaType, 'application/x-www-form-urlencoded');
        assert.equal(body.client_id, options.client_id);
        assert.equal(body.resource, resource);
        let nonce;
        if (body.grant_type === 'authorization_code') {
          const grant = authorizations.get(body.code);
          assert.ok(grant);
          assert.equal(body.redirect_uri, grant.redirect);
          assert.equal(createHash('sha256').update(body.code_verifier).digest('base64url'), grant.challenge);
          nonce = options.nonce ?? grant.nonce;
        } else {
          assert.equal(body.grant_type, 'refresh_token');
          assert.match(body.refresh_token, /^fixture-refresh-/);
          assert.equal(body.scope, undefined);
          options.marker = 'renewed';
        }
        if (options.holdToken) return options.holdToken(entry, response);
        if (options.tokenStatus) return jsonResponse(response, { error: 'fixture rejection' }, options.tokenStatus);
        return jsonResponse(response, await tokens({ nonce }));
      }
      assert.equal(request.headers['chatgpt-account-id'], undefined);
      assert.equal(request.headers.originator, undefined);
      assert.equal(request.headers.session_id, undefined);
      assert.equal(url.searchParams.has('client_version'), false);
      assert.equal(request.headers.authorization, `Bearer opaque-access-${options.marker}`);
      assert.ok(['/v1/responses', '/v1/models'].includes(url.pathname));
      if (body) {
        assert.equal(body.store, false); assert.equal(body.stream, true); assert.ok(Array.isArray(body.input));
        for (const key of ['previous_response_id', 'prompt_cache_key', 'background', 'conversation', 'max_output_tokens', 'max_tool_calls',
          'metadata', 'moderation', 'multi_agent', 'prompt', 'prompt_cache_retention', 'safety_identifier', 'temperature',
          'top_logprobs', 'top_p', 'truncation', 'user', 'programmatic_tool_calling']) assert.equal(Object.hasOwn(body, key), false);
        assert.equal(body.input.some(item => ['compaction_trigger', 'configuration_update'].includes(item.type)), false);
        for (const tool of body.tools ?? []) { assert.equal(tool.type, 'namespace'); assert.equal(tool.name, 'selvedge'); }
      }
      requests.push(entry);
      await handler(entry, response);
    })().catch(error => { failures.push(error); response.destroy(error); });
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => { server.closeAllConnections(); server.close(resolve); }));
  address = `http://127.0.0.1:${server.address().port}`;
  const profile = { ...defaultChatGPTAccount, endpoint: `${address}/v1/responses`, issuer: address, timeout_ms: 5000 };
  const credential = async (subject = options.subject, marker = options.marker, overrides = {}) => ({
    format: 'selvedge-chatgpt-2', issuer: address, client_id: options.client_id, subject,
    account_id: chatgptAccountIdentity(address, options.client_id, subject),
    ...await tokens({ subject, marker }), scope, expires_at: new Date(Date.now() + 3600_000).toISOString(),
    earliest_refresh_at: null, last_refresh: new Date().toISOString(), name: 'Fixture User', email: 'fixture@example.invalid',
    ...overrides,
  });
  const save = async (subject = 'fixture-account', marker = 'original', overrides = {}) => {
    options.subject = subject; options.marker = marker;
    const value = await credential(subject, marker, overrides);
    delete value.token_type; delete value.expires_in;
    await writeAtomic(path.join(directory, profile.auth_file), value);
    await writeAtomic(path.join(directory, `${profile.auth_file}.registration.json`), {
      format: 'selvedge-chatgpt-registration-1', issuer: address, client_id: options.client_id, subject,
    });
    return value;
  };
  await save();
  return { directory, profile, requests, oauthRequests, failures, save, credential, tokens, options, server, address,
    authorize: async ({ url }) => fetch(url),
    accountId: subject => chatgptAccountIdentity(address, options.client_id, subject) };
}

export function jsonResponse(response, value, status = 200) {
  response.writeHead(status, { 'content-type': 'application/json' }); response.end(JSON.stringify(value));
}

export function modelResponse(response, output, deltas = []) {
  response.writeHead(200, { 'content-type': 'text/event-stream' });
  for (const delta of deltas) response.write(`data: ${JSON.stringify(delta)}\n\n`);
  for (const [output_index, item] of output.entries()) response.write(`data: ${JSON.stringify({ type: 'response.output_item.done', output_index, item })}\n\n`);
  response.end(`data: ${JSON.stringify({ type: 'response.completed', response: { status: 'completed', output: [] } })}\n\n`);
}

export const modelEffect = () => ({
  kind: 'model', task_id: 1, ticket: 2,
  model: { profile: 'fixture', provider: 'chatgpt', name: 'model-from-account', reasoning: 'medium', project: null },
  instructions: 'Fixture instructions', history: [{ role: 'user', content: 'hello' }],
  tools: [
    { name: 'allowed', description: 'Allowed tool', parameters: { type: 'object', properties: {} } },
    { name: 'withheld', description: 'Not callable', parameters: { type: 'object', properties: {} } },
  ], callable: ['allowed'],
});
export const wireLimits = { frame_bytes: 4 * 1024 * 1024, provider_checkpoint_limit_bytes: 262144,
  model_retry: { delays_ms: [1], statuses: [429, 503], max_retry_after_ms: 100 } };
