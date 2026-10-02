import { DatabaseSync } from 'node:sqlite';
import { readFile, mkdir } from 'node:fs/promises';
import { createHash, randomBytes, randomUUID } from 'node:crypto';
import http from 'node:http';
import path from 'node:path';
import { createLocalJWKSet, jwtVerify } from 'jose';
import { requestJson } from './network.mjs';
import { writeAtomic } from './files.mjs';
import { chatgptAccountIdentity, chatgptOAuthResource, chatgptScopes } from './chatgpt-contract.mjs';

const format = 'selvedge-chatgpt-2';
const locks = new Map();
const text = value => typeof value === 'string' && value.trim().length > 0;
const date = value => typeof value === 'string' && Number.isFinite(Date.parse(value));
const planScope = scope => text(scope) && scope.split(/\s+/).includes('chatgpt.tokens.use.direct');
const issuedClient = value => text(value) && value !== 'dynamic_agent_client';

export function validateCredential(value) {
  const fields = ['format', 'issuer', 'client_id', 'subject', 'account_id', 'access_token', 'refresh_token', 'id_token',
    'scope', 'expires_at', 'earliest_refresh_at', 'last_refresh', 'name', 'email'];
  if (!value || value.format !== format || Object.keys(value).length !== fields.length || fields.some(key => !Object.hasOwn(value, key)) ||
      ['issuer', 'subject', 'account_id', 'access_token', 'refresh_token', 'id_token'].some(key => !text(value[key])) ||
      !issuedClient(value.client_id) || !planScope(value.scope) || !date(value.expires_at) || !date(value.last_refresh) ||
      (value.earliest_refresh_at !== null && !date(value.earliest_refresh_at)) ||
      ['name', 'email'].some(key => value[key] !== null && !text(value[key])) ||
      value.account_id !== chatgptAccountIdentity(value.issuer, value.client_id, value.subject)) {
    throw new Error('Invalid current-format ChatGPT credential; sign in again');
  }
  return value;
}

async function readRecord(filename, optional = false) {
  let contents;
  try { contents = await readFile(filename, 'utf8'); }
  catch (error) { if (optional && error.code === 'ENOENT') return null; throw error; }
  // Parser diagnostics can expose token-bearing file contents in durable errors.
  try { return JSON.parse(contents); }
  catch { throw new Error('Invalid ChatGPT authentication record; sign in again'); }
}

function registration(value, issuer) {
  if (!value || value.format !== 'selvedge-chatgpt-registration-1' || Object.keys(value).length !== 4 ||
      value.issuer !== issuer || !issuedClient(value.client_id) || (value.subject !== null && !text(value.subject))) {
    throw new Error('Invalid ChatGPT client registration; sign in again');
  }
  return value;
}

async function locked(filename, action) {
  const prior = locks.get(filename) ?? Promise.resolve();
  const pending = prior.catch(() => {}).then(async () => {
    await mkdir(path.dirname(filename), { recursive: true, mode: 0o700 });
    const lock = new DatabaseSync(`${filename}.lock`, { timeout: 1000 });
    try {
      lock.exec('CREATE TABLE IF NOT EXISTS owner (id INTEGER PRIMARY KEY); BEGIN EXCLUSIVE');
      return await action();
    } finally {
      try { lock.exec('ROLLBACK'); } catch {}
      lock.close();
    }
  });
  locks.set(filename, pending);
  try { return await pending; }
  finally { if (locks.get(filename) === pending) locks.delete(filename); }
}

async function discovery(profile, signal) {
  const response = await requestJson(`${profile.issuer}/.well-known/openid-configuration`, { method: 'GET', signal });
  if (!response.ok || response.value?.issuer !== profile.issuer) throw new Error('Invalid ChatGPT OpenID discovery');
  const origin = new URL(profile.issuer).origin;
  for (const key of ['authorization_endpoint', 'token_endpoint', 'jwks_uri']) {
    let url;
    try { url = new URL(response.value[key]); } catch { throw new Error('Invalid ChatGPT OpenID endpoint'); }
    if (url.origin !== origin || !['https:', 'http:'].includes(url.protocol) || url.username || url.password || url.hash ||
        (url.protocol !== 'https:' && !['localhost', '127.0.0.1', '[::1]'].includes(url.hostname))) {
      throw new Error('ChatGPT OpenID endpoints must belong to the configured issuer');
    }
  }
  return response.value;
}

async function verifyIdentity(idToken, metadata, clientId, signal, { nonce, subject } = {}) {
  try {
    const response = await requestJson(metadata.jwks_uri, { method: 'GET', signal });
    if (!response.ok) throw new Error('Cannot fetch identity verification keys');
    const { payload } = await jwtVerify(idToken, createLocalJWKSet(response.value), {
      issuer: metadata.issuer, audience: clientId, requiredClaims: ['sub', 'iat', 'exp', 'aud', 'iss'],
    });
    if (!text(payload.sub) || (nonce !== undefined && payload.nonce !== nonce) ||
        (subject !== undefined && payload.sub !== subject) ||
        (payload.azp !== undefined && payload.azp !== clientId) ||
        (Array.isArray(payload.aud) && payload.aud.length > 1 && payload.azp !== clientId)) throw new Error('Invalid identity claims');
    return { subject: payload.sub, name: text(payload.name) ? payload.name : null, email: text(payload.email) ? payload.email : null };
  } catch { signal?.throwIfAborted(); throw new Error('ChatGPT identity verification failed; sign in again'); }
}

function earliest(value) {
  if (value === undefined || value === null) return null;
  const instant = typeof value === 'number' ? value * 1000 : Date.parse(value);
  if (!Number.isFinite(instant)) throw new Error('Invalid ChatGPT token refresh time');
  try { return new Date(instant).toISOString(); } catch { throw new Error('Invalid ChatGPT token refresh time'); }
}

async function tokenCredential(tokens, metadata, clientId, signal, { previous, nonce, subject } = {}) {
  if (!tokens || !text(tokens.access_token) || !text(tokens.refresh_token) ||
      typeof tokens.token_type !== 'string' || tokens.token_type.toLowerCase() !== 'bearer' ||
      !Number.isFinite(tokens.expires_in) || tokens.expires_in <= 0 ||
      (!previous && !text(tokens.id_token)) || !planScope(tokens.scope ?? previous?.scope)) {
    throw new Error('ChatGPT returned an invalid token grant');
  }
  let identity;
  if (tokens.id_token !== undefined) {
    if (!text(tokens.id_token)) throw new Error('ChatGPT returned an invalid identity token');
    identity = await verifyIdentity(tokens.id_token, metadata, clientId, signal, { nonce, subject });
  } else identity = { subject: previous.subject, name: previous.name, email: previous.email };
  return validateCredential({ format, issuer: metadata.issuer, client_id: clientId, ...identity,
    account_id: chatgptAccountIdentity(metadata.issuer, clientId, identity.subject),
    access_token: tokens.access_token, refresh_token: tokens.refresh_token, id_token: tokens.id_token ?? previous.id_token,
    scope: tokens.scope ?? previous?.scope, expires_at: new Date(Date.now() + tokens.expires_in * 1000).toISOString(),
    earliest_refresh_at: earliest(tokens.earliest_refresh_at), last_refresh: new Date().toISOString() });
}

export async function resolveAuth(profile, home, { signal, rejectedToken } = {}) {
  const filename = path.resolve(home, profile.auth_file);
  return locked(filename, async () => {
    const current = validateCredential(await readRecord(filename));
    if (current.issuer !== profile.issuer) throw new Error('ChatGPT credential belongs to a different issuer; sign in again');
    const registered = registration(await readRecord(`${filename}.registration.json`), profile.issuer);
    if (registered.client_id !== current.client_id || registered.subject !== current.subject) throw new Error('ChatGPT credential does not match its registered identity');
    const stale = Date.parse(current.expires_at) <= Date.now() + 300_000;
    if ((!stale && (rejectedToken === undefined || rejectedToken !== current.access_token)) ||
        (current.earliest_refresh_at !== null && Date.parse(current.earliest_refresh_at) > Date.now() && rejectedToken === undefined)) return current;
    const metadata = await discovery(profile, signal);
    const response = await requestJson(metadata.token_endpoint, { signal, encoding: 'form', body: {
      grant_type: 'refresh_token', client_id: current.client_id, refresh_token: current.refresh_token, resource: chatgptOAuthResource,
    } });
    if (!response.ok) throw new Error(`ChatGPT token refresh failed with HTTP ${response.status}`);
    const next = await tokenCredential(response.value, metadata, current.client_id, signal, { previous: current, subject: current.subject });
    await writeAtomic(filename, next);
    return next;
  });
}

async function hostIdentity(home) {
  const filename = path.resolve(home, 'auth/chatgpt-host.json');
  return locked(filename, async () => {
    const saved = await readRecord(filename, true);
    if (saved) {
      if (saved.format !== 'selvedge-chatgpt-host-1' || Object.keys(saved).length !== 2 || !text(saved.ext_agent_host_id) || !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(saved.ext_agent_host_id)) throw new Error('Invalid ChatGPT host registration');
      return saved.ext_agent_host_id;
    }
    const ext_agent_host_id = randomUUID();
    await writeAtomic(filename, { format: 'selvedge-chatgpt-host-1', ext_agent_host_id });
    return ext_agent_host_id;
  });
}

/** Interactive authorization is called only by the explicit CLI login command. */
export async function login(profile, home, { signal, onAuthorize = () => {} } = {}) {
  const lifetime = signal ? AbortSignal.any([signal, AbortSignal.timeout(10 * 60_000)]) : AbortSignal.timeout(10 * 60_000);
  const metadata = await discovery(profile, lifetime);
  const ext_agent_host_id = await hostIdentity(home);
  const filename = path.resolve(home, profile.auth_file);
  return locked(filename, async () => {
    lifetime.throwIfAborted();
    let registered = await readRecord(`${filename}.registration.json`, true);
    if (registered) registered = registration(registered, profile.issuer);
    const state = randomBytes(32).toString('base64url');
    const nonce = randomBytes(32).toString('base64url');
    const verifier = randomBytes(32).toString('base64url');
    let resolveCallback, rejectCallback;
    const callback = new Promise((resolve, reject) => { resolveCallback = resolve; rejectCallback = reject; });
    // An abort may occur while the caller is showing the authorization URL.
    callback.catch(() => {});
    let redirectUri;
    let received = false;
    const server = http.createServer((request, response) => {
      let url;
      try { url = new URL(request.url, redirectUri); } catch { response.writeHead(400); response.end(); return; }
      if (url.pathname !== '/auth/callback') { response.writeHead(404); response.end(); return; }
      const fail = message => { response.writeHead(400); response.end('ChatGPT authorization failed. Return to the terminal.'); rejectCallback(new Error(message)); };
      if (received) { response.writeHead(409); response.end(); return; }
      if (request.method !== 'GET' || request.headers.host !== new URL(redirectUri).host || url.origin !== new URL(redirectUri).origin ||
          ['code', 'state', 'client_id', 'error'].some(key => url.searchParams.getAll(key).length > 1) || url.searchParams.get('state') !== state) {
        fail('Invalid ChatGPT authorization callback'); return;
      }
      received = true;
      if (url.searchParams.has('error')) { fail('ChatGPT authorization was declined or failed'); return; }
      const code = url.searchParams.get('code');
      const clientId = url.searchParams.get('client_id') ?? registered?.client_id;
      if (!text(code) || !issuedClient(clientId) || (registered && clientId !== registered.client_id)) { fail('Invalid ChatGPT issued client'); return; }
      response.writeHead(200, { 'content-type': 'text/plain', 'cache-control': 'no-store' });
      response.end('ChatGPT authorization received. Return to the terminal.');
      resolveCallback({ code, clientId });
    });
    const abort = () => rejectCallback(lifetime.reason);
    lifetime.addEventListener('abort', abort, { once: true });
    try {
      await new Promise((resolve, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', resolve); });
      redirectUri = `http://127.0.0.1:${server.address().port}/auth/callback`;
      lifetime.throwIfAborted();
      const authorize = new URL(metadata.authorization_endpoint);
      const parameters = { response_type: 'code', resource: chatgptOAuthResource, scope: chatgptScopes, redirect_uri: redirectUri,
        state, nonce, code_challenge: createHash('sha256').update(verifier).digest('base64url'), code_challenge_method: 'S256',
        ext_agent_host_id, client_id: registered?.client_id ?? 'dynamic_agent_client' };
      if (!registered) parameters.agent_name_hint = 'Selvedge';
      for (const [key, value] of Object.entries(parameters)) authorize.searchParams.set(key, value);
      await onAuthorize({ url: authorize.href, redirect_uri: redirectUri });
      const { code, clientId } = await callback;
      registered = { format: 'selvedge-chatgpt-registration-1', issuer: profile.issuer, client_id: clientId, subject: registered?.subject ?? null };
      // The issued client survives a failed exchange; registration cannot be replayed with the placeholder.
      await writeAtomic(`${filename}.registration.json`, registered);
      const exchanged = await requestJson(metadata.token_endpoint, { signal: lifetime, encoding: 'form', body: {
        grant_type: 'authorization_code', client_id: clientId, code, code_verifier: verifier, redirect_uri: redirectUri, resource: chatgptOAuthResource,
      } });
      if (!exchanged.ok) throw new Error(`ChatGPT token exchange failed with HTTP ${exchanged.status}`);
      const saved = await tokenCredential(exchanged.value, metadata, clientId, lifetime, { nonce, subject: registered.subject ?? undefined });
      await writeAtomic(`${filename}.registration.json`, { ...registered, subject: saved.subject });
      await writeAtomic(filename, saved);
      return { account_id: saved.account_id, filename, name: saved.name, email: saved.email };
    } finally {
      lifetime.removeEventListener('abort', abort);
      server.closeAllConnections();
      await new Promise(resolve => server.close(resolve));
    }
  });
}
