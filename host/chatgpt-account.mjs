import { DatabaseSync } from 'node:sqlite';
import { readFile, mkdir } from 'node:fs/promises';
import { randomUUID, createHash } from 'node:crypto';
import http from 'node:http';
import path from 'node:path';
import * as oidc from 'openid-client';
import { decodeJwt } from 'jose';
import { writeAtomic } from './files.mjs';
import { modelsURL } from './chatgpt-contract.mjs';

import { boundary } from './public/model-boundary.mjs';

const contract = boundary('account.contract', {});
const chatgptOAuthResource = contract.resource;
const chatgptScopes = contract.scopes;
export const defaultChatGPTAccount = Object.freeze(contract.default);
export const chatgptAccountFields = Object.freeze(Object.keys(defaultChatGPTAccount));

export function chatgptAccountIdentity(issuer, clientId, subject) {
  return createHash('sha256').update(`${issuer}\0${clientId}\0${subject}`).digest('hex');
}

function urlObservation(value) {
  // DEFENSE: Configured endpoints and OpenID discovery metadata can contain invalid URLs; native admission rejects the null observation.
  try {
    const url = new URL(value);
    return Object.fromEntries(['href', 'protocol', 'origin', 'hostname', 'host', 'pathname', 'search', 'username', 'password', 'hash'].map(key => [key, url[key]]));
  } catch { return null; }
}
function dateObservation(value, numeric = false) {
  // DEFENSE: OAuth fields and persisted credential records can supply a non-string timestamp; do not coerce an object into a date.
  if (typeof value !== (numeric ? 'number' : 'string')) return null;
  const date = new Date(numeric ? value : Date.parse(value));
  const epoch = date.getTime();
  // DEFENSE: Credential timestamps and token lifetimes come from disk or OAuth; invalid or out-of-range dates must fail native admission.
  if (!Number.isFinite(epoch)) return null;
  return { iso: date.toISOString(), epoch: String(epoch),
    ordered_epoch: String(BigInt(epoch) + 8640000000000000n).padStart(17, '0') };
}
function credentialObservations(value, audio = false) {
  return { value, audio, identity: chatgptAccountIdentity(value?.issuer, value?.client_id, value?.subject),
    dates: Object.fromEntries(['expires_at', 'earliest_refresh_at', 'last_refresh'].map(key => [key, dateObservation(value?.[key])])) };
}
function connectionObservations(value) {
  return { value, urls: { endpoint: urlObservation(value?.endpoint ?? defaultChatGPTAccount.endpoint),
    issuer: urlObservation(value?.issuer ?? defaultChatGPTAccount.issuer) } };
}
export function accountConfig(value = {}) {
  return Object.freeze(boundary('account.connection', connectionObservations(value)));
}
export function accountConnection(profile) {
  const connection = boundary('account.profile_connection', { profile });
  return Object.freeze(boundary('account.connection', { profile, ...connectionObservations(connection) }));
}
const locks = new Map();

function validateCredential(value, audio = false) {
  return boundary('account.credential', credentialObservations(value, audio));
}

async function readRecord(filename, optional = false) {
  let contents;
  try { contents = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(await readFile(filename)); }
  // DEFENSE: First login has no host/registration record; only ENOENT for an optional record means absence.
  catch (error) { if (boundary('account.record_read_failure', { filename, optional, code: error.code })) return null; throw error; }
  return boundary('account.record_decode', { text: contents, filename, optional });
}

function registration(value, issuer) {
  return boundary('account.registration', { value, issuer });
}

async function locked(filename, action) {
  const prior = locks.get(filename) ?? Promise.resolve();
  // DEFENSE: A failed earlier login/refresh releases its place in the queue; a later explicit attempt must still acquire the lock.
  const enter = async () => {
    await mkdir(path.dirname(filename), { recursive: true, mode: 0o700 });
    const lock = new DatabaseSync(`${filename}.lock`, { timeout: 1000 });
    try {
      lock.exec('CREATE TABLE IF NOT EXISTS owner (id INTEGER PRIMARY KEY); BEGIN EXCLUSIVE');
      return await action();
    } finally {
      lock.close();
    }
  };
  const pending = prior.then(enter, enter);
  locks.set(filename, pending);
  try { return await pending; }
  finally { if (locks.get(filename) === pending) locks.delete(filename); }
}

function operationFetch(signal, audio = false) {
  return async (url, options) => {
    let request = options;
    if (audio && options.body instanceof URLSearchParams && options.body.get('grant_type') === 'refresh_token') {
      // The ChatGPT audio grant uses JSON refresh requests; openid-client retains response and signature validation.
      request = { ...options, headers: new Headers(options.headers), body: JSON.stringify(Object.fromEntries(options.body)) };
      request.headers.set('content-type', 'application/json');
    }
    const response = await fetch(url, { ...request,
      signal: AbortSignal.any([signal, options.signal].filter(Boolean)) });
    if (audio && options.body instanceof URLSearchParams && response.ok) {
      // This fixed ChatGPT grant returns Bearer credentials without requiring an OAuth token_type field.
      const tokens = await response.json();
      return new Response(JSON.stringify({ token_type: 'Bearer', ...tokens }), {
        status: response.status, statusText: response.statusText, headers: response.headers,
      });
    }
    return response;
  };
}

function configuration(metadata, clientId, profile, signal, audio = false) {
  const config = new oidc.Configuration(metadata, clientId);
  config.timeout = boundary('account.sdk_timeout', { metadata, clientId, profile }) / 1000;
  config[oidc.customFetch] = operationFetch(signal, audio);
  if (boundary('account.http', { metadata, clientId, profile, url: urlObservation(metadata.issuer) })) oidc.allowInsecureRequests(config);
  // Token endpoint TLS alone does not authenticate an ID-token signature.
  oidc.enableNonRepudiationChecks(config);
  return config;
}

async function discovery(profile, signal, audio = false) {
  // DEFENSE: OpenID discovery can reject network, metadata or signing-configuration errors; SDK diagnostics must not enter durable task errors.
  try {
    const issuer = new URL(profile.issuer);
    const insecure = boundary('account.insecure', { profile, url: urlObservation(issuer.href) });
    const discovered = await oidc.discovery(issuer, audio ? contract.audio.client_id : 'dynamic_agent_client', undefined, undefined, {
      [oidc.customFetch]: operationFetch(signal), timeout: boundary('account.sdk_timeout', { profile }) / 1000,
      execute: insecure ? [oidc.allowInsecureRequests] : [],
    });
    const metadata = discovered.serverMetadata();
    return boundary('account.discovery', { profile, audio, value: metadata, issuer: profile.issuer,
      issuer_url: urlObservation(profile.issuer), urls: Object.fromEntries(
        ['authorization_endpoint', 'token_endpoint', 'jwks_uri'].map(key => [key, urlObservation(metadata[key])])) });
  } catch { signal?.throwIfAborted(); return boundary('account.discovery_failure', { profile }); }
}

async function grant(action, signal) {
  // DEFENSE: OAuth grants can fail HTTP or token-signature checks; expose the native sanitized failure instead of token-bearing SDK diagnostics.
  try { return await action(); }
  catch { signal?.throwIfAborted(); return boundary('account.grant_failure', {}); }
}

function tokenCredential(tokens, metadata, clientId, { previous, subject, audio = false } = {}) {
  const source = { audio, tokens: Object.fromEntries(Object.entries(tokens).filter(([, value]) => typeof value !== 'function')), metadata, clientId,
    ...(previous === undefined ? {} : { previous }),
    ...(subject === undefined ? {} : { subject }) };
  boundary('account.token', { ...source, phase: 'grant' });
  const claims = tokens.claims();
  const identitySubject = boundary('account.token_subject', { ...source, claims: claims ?? null });
  const identity = audio ? boundary('account.audio_identity', { ...source, claims: claims ?? null })
    : chatgptAccountIdentity(metadata.issuer, clientId, identitySubject);
  const expiresNow = Date.now();
  let expiration = expiresNow + tokens.expires_in * 1000;
  if (audio && tokens.expires_in === undefined) {
    let accessClaims;
    // DEFENSE: This grant can issue opaque access tokens; Codex schedules those for refresh after eight days.
    try { accessClaims = decodeJwt(tokens.access_token); } catch { accessClaims = null; }
    expiration = typeof accessClaims?.exp === 'number' ? accessClaims.exp * 1000 : expiresNow + contract.audio.refresh_interval_ms;
  }
  const expires = dateObservation(expiration, true);
  // Expiry admission precedes refresh parsing and the final clock observation.
  boundary('account.token_expiration', { ...source, claims, identity, expiresNow, expires });
  const earliestValue = tokens.earliest_refresh_at;
  const earliest = dateObservation(typeof earliestValue === 'number' ? earliestValue * 1000 : earliestValue, typeof earliestValue === 'number');
  boundary('account.token_times', { ...source, claims, identity, expiresNow, expires, earliest });
  const now = Date.now();
  return boundary('account.token', { ...source, claims: claims ?? null, identity, expiresNow, expires, earliest,
    now, now_date: dateObservation(now, true) });
}

async function resolveCredential(profile, home, { signal, rejectedToken, audio = false } = {}) {
  const filename = path.resolve(home, profile.auth_file);
  return locked(filename, async () => {
    const current = validateCredential(await readRecord(filename), audio);
    boundary('account.issuer_admission', { profile, home, value: current, issuer: profile.issuer });
    const registered = audio ? { client_id: contract.audio.client_id, subject: current.subject }
      : registration(await readRecord(`${filename}.registration.json`), profile.issuer);
    boundary('account.refresh_registration', { profile, home, value: current, registered, rejectedToken });
    const staleNow = Date.now();
    const source = { profile, home, ...credentialObservations(current, audio), registered, issuer: profile.issuer,
      staleNow, threshold: dateObservation(staleNow + 300_000, true),
      ...(rejectedToken === undefined ? {} : { rejectedToken }) };
    const initial = boundary('account.refresh_initial', source);
    if (initial === 'keep') return current;
    if (initial === 'earliest') {
      const now = Date.now();
      if (boundary('account.refresh', { ...source, now, now_date: dateObservation(now, true) })) return current;
    }
    const metadata = await discovery(profile, signal, audio);
    const config = configuration(metadata, current.client_id, profile, signal, audio);
    const tokens = await grant(() => oidc.refreshTokenGrant(config, current.refresh_token, audio ? undefined : { resource: chatgptOAuthResource }), signal);
    const next = tokenCredential(tokens, metadata, current.client_id, { previous: current, subject: current.subject, audio });
    await writeAtomic(filename, next);
    return next;
  });
}

function authorizationView(credential, connection, home, audio = false) {
  const view = boundary('account.authorization_view', { credential, connection, home, audio });
  return Object.freeze({
    ...view, headers: Object.freeze(view.headers),
    async refreshAfterRejection({ signal } = {}) {
      // Keep the rejected token private so concurrent refreshes can reuse a newer credential.
      const next = await resolveCredential(connection, home, { signal, rejectedToken: credential.access_token, audio });
      return authorizationView(next, connection, home, audio);
    },
  });
}

export async function authorize(profile, home, { signal, audio = false } = {}) {
  const connection = accountConnection(profile);
  const credential = await resolveCredential(connection, home, { signal, audio });
  return authorizationView(credential, connection, home, audio);
}

async function hostIdentity(home) {
  const filename = path.resolve(home, 'auth/chatgpt-host.json');
  return locked(filename, async () => {
    const saved = await readRecord(filename, true);
    const existing = boundary('account.host_saved', { home, filename, saved, value: saved });
    if (existing !== null) return existing;
    const ext_agent_host_id = `urn:uuid:${randomUUID()}`;
    await writeAtomic(filename, boundary('account.host_registration_record', { home, filename, saved, ext_agent_host_id }));
    return ext_agent_host_id;
  });
}

/** Interactive authorization is called only by the explicit CLI login command. */
export async function login(profile, home, { signal, onAuthorize = () => {}, audio = false } = {}) {
  const lifetime = signal ? AbortSignal.any([signal, AbortSignal.timeout(contract.login_timeout_ms)]) : AbortSignal.timeout(contract.login_timeout_ms);
  const metadata = await discovery(profile, lifetime, audio);
  const ext_agent_host_id = audio ? undefined : await hostIdentity(home);
  const filename = path.resolve(home, profile.auth_file);
  return locked(filename, async () => {
    lifetime.throwIfAborted();
    let registered = audio ? { client_id: contract.audio.client_id, subject: null }
      : boundary('account.optional_registration', { profile, home, value: await readRecord(`${filename}.registration.json`, true), issuer: profile.issuer });
    const state = oidc.randomState();
    const nonce = oidc.randomNonce();
    const verifier = oidc.randomPKCECodeVerifier();
    let resolveCallback, rejectCallback;
    const callback = new Promise((resolve, reject) => { resolveCallback = resolve; rejectCallback = reject; });
    // DEFENSE: Timeout can reject the callback while onAuthorize is still displaying the URL; attach a handler until the callback is awaited below.
    callback.catch(() => {});
    let redirectUri;
    let received = false;
    const server = http.createServer((request, response) => {
      let url;
      // DEFENSE: The loopback HTTP listener also receives malformed request targets; native callback admission responds without accepting a grant.
      try { url = new URL(request.url, redirectUri); } catch { url = null; }
      const redirect = new URL(redirectUri);
      const decision = boundary('account.callback', { profile, home, audio, redirectUri, request: { url: request.url, method: request.method, headers: { host: request.headers.host }, host: request.headers.host },
        url: url ? urlObservation(url.href) : null, redirect: urlObservation(redirect.href), received, state, registered,
        parameters: Object.fromEntries(['code', 'state', 'client_id', 'error'].map(key => [key, url ? url.searchParams.getAll(key) : []])) });
      if (decision.received) received = true;
      // DEFENSE: Wrong-path, wrong-host and duplicate HTTP callbacks must not settle the pending OAuth grant.
      if (decision.action === 'ignore') { response.writeHead(decision.status, decision.headers); response.end(decision.body); return; }
      // DEFENSE: An OAuth error or invalid callback parameters reject this login rather than exchanging an untrusted code.
      if (decision.action === 'reject') {
        response.writeHead(decision.status, decision.headers); response.end(decision.body);
        rejectCallback(new Error(decision.message)); return;
      }
      const clientId = decision.clientId;
      response.writeHead(decision.status, decision.headers);
      response.end(decision.body);
      resolveCallback({ url, clientId });
    });
    const abort = () => rejectCallback(lifetime.reason);
    lifetime.addEventListener('abort', abort, { once: true });
    try {
      await new Promise((resolve, reject) => { server.once('error', reject); server.listen(audio ? contract.audio.callback_port : 0, '127.0.0.1', resolve); });
      redirectUri = `http://127.0.0.1:${server.address().port}/auth/callback`;
      lifetime.throwIfAborted();
      const parameters = boundary('account.auth_parameters', { profile, home, audio, registered, redirectUri, state, nonce, verifier,
        challenge: await oidc.calculatePKCECodeChallenge(verifier), ext_agent_host_id });
      const authorize = oidc.buildAuthorizationUrl(configuration(metadata, parameters.client_id, profile, lifetime, audio), parameters);
      await onAuthorize(boundary('account.authorize_prompt', { profile, home, url: authorize.href, redirectUri }));
      const { url, clientId } = await callback;
      registered = boundary('account.registration_record', { profile, home, issuer: profile.issuer, clientId, registered });
      // The issued client survives a failed exchange; registration cannot be replayed with the placeholder.
      if (!audio) await writeAtomic(`${filename}.registration.json`, registered);
      const config = configuration(metadata, clientId, profile, lifetime, audio);
      const tokens = await grant(() => oidc.authorizationCodeGrant(config, url, boundary('account.code_grant_checks', { profile, home, nonce, state, verifier, clientId }), audio ? undefined : { resource: chatgptOAuthResource }), lifetime);
      const saved = tokenCredential(tokens, metadata, clientId, { subject: registered.subject ?? undefined, audio });
      if (!audio) await writeAtomic(`${filename}.registration.json`, boundary('account.registration_subject', { profile, home, registered, saved }));
      await writeAtomic(filename, saved);
      return boundary('account.login_result', { profile, home, saved, filename });
    } finally {
      lifetime.removeEventListener('abort', abort);
      server.closeAllConnections();
      await new Promise(resolve => server.close(resolve));
    }
  });
}


export function createAudioAccount({ home, onChange = () => {} }) {
  const profile = Object.freeze({ ...defaultChatGPTAccount, auth_file: contract.audio.auth_file });
  const filename = path.resolve(home, profile.auth_file);
  let pending;
  let closed = false;
  return {
    async connections({ signal } = {}) {
      signal?.throwIfAborted();
      const value = await readRecord(filename, true);
      if (value === null) return [];
      validateCredential(value, true);
      return [{ id: 'chatgpt-voice', label: 'ChatGPT', source: 'chatgpt_audio', authorized: true }];
    },
    async authorize(connectionId, { signal } = {}) {
      boundary('account.audio_connection', { connectionId });
      return authorize(profile, home, { signal, audio: true });
    },
    startLogin({ signal } = {}) {
      if (closed) throw new Error('ChatGPT audio account is closed');
      if (pending) return pending.ready;
      const controller = new AbortController();
      const lifetime = AbortSignal.any([controller.signal, signal].filter(Boolean));
      let resolveURL, rejectURL;
      const ready = new Promise((resolve, reject) => { resolveURL = resolve; rejectURL = reject; });
      const entry = { ready, controller, completion: null };
      pending = entry;
      entry.completion = login(profile, home, { audio: true, signal: lifetime,
        onAuthorize: ({ url }) => resolveURL({ url }),
      }).then(() => { onChange({ type: 'account_changed' }); }, error => {
        rejectURL(error);
        if (!lifetime.aborted) onChange({ type: 'account_changed', error: 'ChatGPT voice sign-in failed; try again' });
      }).finally(() => { pending = undefined; });
      return ready;
    },
    async close() {
      closed = true;
      const login = pending;
      if (login) { login.controller.abort(); await login.completion; }
    },
  };
}
