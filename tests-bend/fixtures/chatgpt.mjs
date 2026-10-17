import http from 'node:http';
import path from 'node:path';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { generateKeyPair, exportJWK, SignJWT } from 'jose';
import { writeAtomic } from '../../host/files.mjs';
import { defaultChatGPTAccount, chatgptAccountIdentity } from '../../host/chatgpt-account.mjs';
import { home } from '../support.mjs';

const scope = 'openid profile email offline_access resource.invoke chatgpt.tokens.use.direct';
const clientId = 'fixture-issued-client', subject = 'fixture-account';

export async function chatgptFixture(t) {
  const directory = await home(t);
  const failures = [], requests = [], oauthRequests = [];
  const { privateKey, publicKey } = await generateKeyPair('RS256');
  const jwk = { ...await exportJWK(publicKey), kid: 'fixture-key', use: 'sig', alg: 'RS256' };
  const options = {};
  const authorizations = new Map();
  let address, marker = 'original', refreshes = 0;
  const tokens = async nonce => ({
    access_token: `opaque-access-${marker}`, refresh_token: `fixture-refresh-${marker}`,
    token_type: 'Bearer', scope, expires_in: 3600,
    id_token: await new SignJWT({ nonce, name: 'Fixture User', email: 'fixture@example.invalid' })
      .setProtectedHeader({ alg: 'RS256', kid: 'fixture-key' })
      .setIssuer(address).setSubject(subject).setAudience(clientId)
      .setIssuedAt().setExpirationTime('1h').sign(options.privateKey ?? privateKey),
  });
  const server = http.createServer((request, response) => {
    void (async () => {
      const entry = { url: request.url, headers: request.headers };
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
        assert.equal(query.get('code_challenge_method'), 'S256');
        const first = query.get('client_id') === 'dynamic_agent_client';
        if (!first) assert.equal(query.get('client_id'), clientId);
        const callback = new URL(query.get('redirect_uri'));
        const code = `fixture-grant-${authorizations.size}`;
        authorizations.set(code, { nonce: query.get('nonce'), challenge: query.get('code_challenge'), redirect: callback.href });
        callback.searchParams.set('code', code);
        callback.searchParams.set('state', query.get('state'));
        if (first) callback.searchParams.set('client_id', clientId);
        response.writeHead(302, { location: callback.href }); return response.end();
      }
      if (url.pathname === '/oauth/token') {
        oauthRequests.push(entry);
        const chunks = [];
        for await (const chunk of request) chunks.push(chunk);
        const body = Object.fromEntries(new URLSearchParams(Buffer.concat(chunks).toString('utf8')));
        assert.equal(body.client_id, clientId);
        let nonce;
        if (body.grant_type === 'authorization_code') {
          const grant = authorizations.get(body.code);
          assert.ok(grant);
          assert.equal(body.redirect_uri, grant.redirect);
          assert.equal(createHash('sha256').update(body.code_verifier).digest('base64url'), grant.challenge);
          nonce = grant.nonce;
        } else {
          assert.equal(body.grant_type, 'refresh_token');
          assert.equal(body.refresh_token, `fixture-refresh-${marker}`);
          marker = `renewed-${++refreshes}`;
        }
        return jsonResponse(response, await tokens(nonce));
      }
      assert.equal(request.headers.authorization, `Bearer opaque-access-${marker}`);
      requests.push(entry);
      request.resume();
      jsonResponse(response, { error: 'fixture rejection' }, 401);
    })().catch(error => { failures.push(error); response.destroy(error); });
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => { server.closeAllConnections(); server.close(resolve); }));
  address = `http://127.0.0.1:${server.address().port}`;
  const profile = { ...defaultChatGPTAccount, endpoint: `${address}/v1/responses`, issuer: address, timeout_ms: 5000 };
  return { directory, profile, requests, oauthRequests, failures, options, address,
    authorize: async ({ url }) => fetch(url),
    async seedExpiredCredential() {
      const { token_type, expires_in, ...credential } = await tokens();
      await writeAtomic(path.join(directory, profile.auth_file), {
        format: 'selvedge-chatgpt-2', issuer: address, client_id: clientId, subject,
        account_id: chatgptAccountIdentity(address, clientId, subject), ...credential,
        expires_at: new Date(0).toISOString(), earliest_refresh_at: null,
        last_refresh: new Date().toISOString(), name: 'Fixture User', email: 'fixture@example.invalid',
      });
      await writeAtomic(path.join(directory, `${profile.auth_file}.registration.json`), {
        format: 'selvedge-chatgpt-registration-1', issuer: address, client_id: clientId, subject,
      });
    },
  };
}

function jsonResponse(response, value, status = 200) {
  response.writeHead(status, { 'content-type': 'application/json' }); response.end(JSON.stringify(value));
}
