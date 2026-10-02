import { DatabaseSync } from 'node:sqlite';
import { readFile, mkdir } from 'node:fs/promises';
import { randomUUID, createHash } from 'node:crypto';
import http from 'node:http';
import path from 'node:path';
import * as oidc from 'openid-client';
import { writeAtomic } from './files.mjs';
import { modelsURL } from './chatgpt-contract.mjs';

const chatgptOAuthResource = 'https://api.openai.com/v1';
const chatgptScopes = 'openid profile email offline_access resource.invoke chatgpt.tokens.use.direct';
export const defaultChatGPTAccount = Object.freeze({
  provider: 'chatgpt', endpoint: 'https://api.openai.com/v1/responses',
  auth_file: 'auth/chatgpt.json', issuer: 'https://auth.openai.com', timeout_ms: 300_000,
});

export function chatgptAccountIdentity(issuer, clientId, subject) {
  return createHash('sha256').update(`${issuer}\0${clientId}\0${subject}`).digest('hex');
}

export const chatgptAccountFields = Object.freeze(Object.keys(defaultChatGPTAccount));

function object(value, label, keys) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError(`${label} must be an object`);
  for (const key of Object.keys(value)) if (!keys.includes(key)) throw new TypeError(`Unknown ${label} field: ${key}`);
}
function requiredText(value, label) {
  if (typeof value !== 'string' || !value.trim()) throw new TypeError(`${label} must be a nonempty string`);
}
function number(value, label, lower, upper) {
  if (!Number.isSafeInteger(value) || value < lower || value > upper) throw new TypeError(`${label} must be in ${lower}..${upper}`);
}
function endpoint(value, label) {
  requiredText(value, label);
  const url = new URL(value);
  if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password || url.hash) throw new TypeError(`Invalid ${label}`);
  if (url.protocol !== 'https:' && !['localhost', '127.0.0.1', '[::1]'].includes(url.hostname)) throw new TypeError(`${label} requires HTTPS except on loopback`);
}

function loopback(url) { return ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname); }
function chatgptEndpoint(value) {
  const url = new URL(value);
  modelsURL(value);
  if (!loopback(url) && (url.origin !== 'https://api.openai.com' || url.pathname !== '/v1/responses')) {
    throw new TypeError('ChatGPT requires the official public Responses endpoint');
  }
}
function chatgptIssuer(value) {
  endpoint(value, 'ChatGPT issuer');
  const url = new URL(value);
  if (!loopback(url) && url.origin !== 'https://auth.openai.com') throw new TypeError('ChatGPT requires the official issuer');
  if (url.pathname !== '/' || url.search) throw new TypeError('ChatGPT issuer must be an origin');
}

export function accountConfig(value = {}) {
  object(value, 'ChatGPT account', chatgptAccountFields);
  const account = { ...defaultChatGPTAccount, ...value };
  if (account.provider !== 'chatgpt') throw new TypeError('The account provider must be chatgpt');
  endpoint(account.endpoint, 'ChatGPT endpoint');
  chatgptEndpoint(account.endpoint);
  chatgptIssuer(account.issuer);
  requiredText(account.auth_file, 'ChatGPT auth_file');
  number(account.timeout_ms, 'ChatGPT timeout', 100, 1_800_000);
  account.issuer = account.issuer.replace(/\/+$/, '');
  return Object.freeze(account);
}

export function accountConnection(profile) {
  const connection = Object.fromEntries(chatgptAccountFields
    .filter(key => Object.hasOwn(profile, key)).map(key => [key, profile[key]]));
  for (const key of ['endpoint', 'auth_file', 'issuer']) connection[key] ??= defaultChatGPTAccount[key];
  return accountConfig(connection);
}

const format = 'selvedge-chatgpt-2';
const locks = new Map();
const text = value => typeof value === 'string' && value.trim().length > 0;
const date = value => typeof value === 'string' && Number.isFinite(Date.parse(value));
const planScope = scope => text(scope) && scope.split(/\s+/).includes('chatgpt.tokens.use.direct');
const issuedClient = value => text(value) && value !== 'dynamic_agent_client';

function validateCredential(value) {
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

function operationFetch(signal) {
  return (url, options) => fetch(url, { ...options,
    signal: AbortSignal.any([signal, options.signal].filter(Boolean)) });
}

function configuration(metadata, clientId, profile, signal) {
  const config = new oidc.Configuration(metadata, clientId);
  config.timeout = (profile.timeout_ms ?? 300_000) / 1000;
  config[oidc.customFetch] = operationFetch(signal);
  if (new URL(metadata.issuer).protocol === 'http:') oidc.allowInsecureRequests(config);
  // Token endpoint TLS alone does not authenticate an ID-token signature.
  oidc.enableNonRepudiationChecks(config);
  return config;
}

async function discovery(profile, signal) {
  try {
    const issuer = new URL(profile.issuer);
    const insecure = issuer.protocol === 'http:' && ['localhost', '127.0.0.1', '[::1]'].includes(issuer.hostname);
    const discovered = await oidc.discovery(issuer, 'dynamic_agent_client', undefined, undefined, {
      [oidc.customFetch]: operationFetch(signal), timeout: (profile.timeout_ms ?? 300_000) / 1000,
      execute: insecure ? [oidc.allowInsecureRequests] : [],
    });
    const metadata = discovered.serverMetadata();
    if (metadata.issuer !== profile.issuer) throw new Error();
    for (const key of ['authorization_endpoint', 'token_endpoint', 'jwks_uri']) {
      const url = new URL(metadata[key]);
      if (url.origin !== issuer.origin || !['https:', 'http:'].includes(url.protocol) || url.username || url.password || url.hash ||
          (url.protocol === 'http:' && !insecure)) throw new Error();
    }
    return metadata;
  } catch { signal?.throwIfAborted(); throw new Error('Invalid ChatGPT OpenID discovery'); }
}

async function grant(action, signal) {
  try { return await action(); }
  catch { signal?.throwIfAborted(); throw new Error('ChatGPT token grant or identity verification failed; sign in again'); }
}

function earliest(value) {
  if (value === undefined || value === null) return null;
  const instant = typeof value === 'number' ? value * 1000 : Date.parse(value);
  if (!Number.isFinite(instant)) throw new Error('Invalid ChatGPT token refresh time');
  try { return new Date(instant).toISOString(); } catch { throw new Error('Invalid ChatGPT token refresh time'); }
}

function tokenCredential(tokens, metadata, clientId, { previous, subject } = {}) {
  if (!tokens || !text(tokens.access_token) || !text(tokens.refresh_token) ||
      typeof tokens.token_type !== 'string' || tokens.token_type.toLowerCase() !== 'bearer' ||
      !Number.isFinite(tokens.expires_in) || tokens.expires_in <= 0 ||
      (!previous && !text(tokens.id_token)) || !planScope(tokens.scope ?? previous?.scope)) {
    throw new Error('ChatGPT returned an invalid token grant');
  }
  const claims = tokens.claims();
  if ((!previous && !claims) || (claims && (!text(claims.sub) ||
      (subject !== undefined && claims.sub !== subject) || (claims.azp !== undefined && claims.azp !== clientId)))) {
    throw new Error('ChatGPT identity verification failed; sign in again');
  }
  const identity = claims ? { subject: claims.sub, name: text(claims.name) ? claims.name : null,
    email: text(claims.email) ? claims.email : null } : { subject: previous.subject, name: previous.name, email: previous.email };
  return validateCredential({ format, issuer: metadata.issuer, client_id: clientId, ...identity,
    account_id: chatgptAccountIdentity(metadata.issuer, clientId, identity.subject),
    access_token: tokens.access_token, refresh_token: tokens.refresh_token, id_token: tokens.id_token ?? previous.id_token,
    scope: tokens.scope ?? previous?.scope, expires_at: new Date(Date.now() + tokens.expires_in * 1000).toISOString(),
    earliest_refresh_at: earliest(tokens.earliest_refresh_at), last_refresh: new Date().toISOString() });
}

async function resolveCredential(profile, home, { signal, rejectedToken } = {}) {
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
    const config = configuration(metadata, current.client_id, profile, signal);
    const tokens = await grant(() => oidc.refreshTokenGrant(config, current.refresh_token, { resource: chatgptOAuthResource }), signal);
    const next = tokenCredential(tokens, metadata, current.client_id, { previous: current, subject: current.subject });
    await writeAtomic(filename, next);
    return next;
  });
}

function authorizationView(credential, connection, home) {
  return Object.freeze({
    account_id: credential.account_id,
    headers: Object.freeze({ authorization: `Bearer ${credential.access_token}` }),
    async refreshAfterRejection({ signal } = {}) {
      // Keep the rejected token private so concurrent refreshes can reuse a newer credential.
      const next = await resolveCredential(connection, home, { signal, rejectedToken: credential.access_token });
      return authorizationView(next, connection, home);
    },
  });
}

export async function authorize(profile, home, { signal } = {}) {
  const connection = accountConnection(profile);
  const credential = await resolveCredential(connection, home, { signal });
  return authorizationView(credential, connection, home);
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
    const state = oidc.randomState();
    const nonce = oidc.randomNonce();
    const verifier = oidc.randomPKCECodeVerifier();
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
      resolveCallback({ url, clientId });
    });
    const abort = () => rejectCallback(lifetime.reason);
    lifetime.addEventListener('abort', abort, { once: true });
    try {
      await new Promise((resolve, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', resolve); });
      redirectUri = `http://127.0.0.1:${server.address().port}/auth/callback`;
      lifetime.throwIfAborted();
      const parameters = { response_type: 'code', resource: chatgptOAuthResource, scope: chatgptScopes, redirect_uri: redirectUri,
        state, nonce, code_challenge: await oidc.calculatePKCECodeChallenge(verifier), code_challenge_method: 'S256',
        ext_agent_host_id, client_id: registered?.client_id ?? 'dynamic_agent_client' };
      if (!registered) parameters.agent_name_hint = 'Selvedge';
      const authorize = oidc.buildAuthorizationUrl(configuration(metadata, parameters.client_id, profile, lifetime), parameters);
      await onAuthorize({ url: authorize.href, redirect_uri: redirectUri });
      const { url, clientId } = await callback;
      registered = { format: 'selvedge-chatgpt-registration-1', issuer: profile.issuer, client_id: clientId, subject: registered?.subject ?? null };
      // The issued client survives a failed exchange; registration cannot be replayed with the placeholder.
      await writeAtomic(`${filename}.registration.json`, registered);
      const config = configuration(metadata, clientId, profile, lifetime);
      const tokens = await grant(() => oidc.authorizationCodeGrant(config, url, {
        expectedNonce: nonce, expectedState: state, idTokenExpected: true, pkceCodeVerifier: verifier,
      }, { resource: chatgptOAuthResource }), lifetime);
      const saved = tokenCredential(tokens, metadata, clientId, { subject: registered.subject ?? undefined });
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
