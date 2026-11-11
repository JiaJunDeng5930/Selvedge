import { DatabaseSync } from 'node:sqlite';
import { readFile, mkdir } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import http from 'node:http';
import path from 'node:path';
import * as oidc from 'openid-client';
import { decodeJwt } from 'jose';
import { writeAtomic } from './files.mjs';

import { boundary } from './public/model-boundary.mjs';

const contract = boundary('account.contract', {});
export const defaultChatGPTAccount = contract.default;

function principalIdentity(credential) {
  const parts = [credential.issuer, credential.client_id, credential.subject, credential.account_id];
  return createHash('sha256').update(parts.join('\0')).digest('hex');
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
  return { iso: date.toISOString(), ordered_epoch: String(BigInt(epoch) + 8640000000000000n).padStart(17, '0') };
}
function credentialObservations(value) {
  return { value, dates: Object.fromEntries(['expires_at', 'earliest_refresh_at'].map(key => [key, dateObservation(value?.[key])])) };
}
function connectionObservations(value) {
  return { value, urls: { endpoint: urlObservation(value?.endpoint ?? defaultChatGPTAccount.endpoint),
    issuer: urlObservation(value?.issuer ?? defaultChatGPTAccount.issuer) } };
}
export function accountConfig(value = {}) {
  return boundary('account.connection', connectionObservations(value));
}
export function accountConnection(profile) {
  return boundary('account.profile_connection', { profile });
}
const locks = new Map();

async function readRecord(filename, optional = false) {
  let contents;
  try { contents = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(await readFile(filename)); }
  // DEFENSE: A fresh service has no credential record; only ENOENT for an optional record means absence.
  catch (error) { if (boundary('account.record_read_failure', { optional, code: error.code })) return null; throw error; }
  return boundary('account.record_decode', { text: contents });
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

function operationFetch(signal) {
  return async (url, options) => {
    let request = options;
    if (options.body instanceof URLSearchParams && options.body.get('grant_type') === 'refresh_token') {
      // The Codex grant uses JSON refresh requests; openid-client retains response and signature validation.
      request = { ...options, headers: new Headers(options.headers), body: JSON.stringify(Object.fromEntries(options.body)) };
      request.headers.set('content-type', 'application/json');
    }
    const response = await fetch(url, { ...request,
      signal: AbortSignal.any([signal, options.signal].filter(Boolean)) });
    if (options.body instanceof URLSearchParams && response.ok) {
      // This fixed ChatGPT grant returns Bearer credentials without requiring an OAuth token_type field.
      const tokens = await response.json();
      return new Response(JSON.stringify({ token_type: 'Bearer', ...tokens }), {
        status: response.status, statusText: response.statusText, headers: response.headers,
      });
    }
    return response;
  };
}

function configuration(metadata, profile, signal) {
  const config = new oidc.Configuration(metadata, contract.client_id);
  config.timeout = boundary('account.sdk_timeout', { profile }) / 1000;
  config[oidc.customFetch] = operationFetch(signal);
  if (boundary('account.http', { url: urlObservation(metadata.issuer) })) oidc.allowInsecureRequests(config);
  // Token endpoint TLS alone does not authenticate an ID-token signature.
  oidc.enableNonRepudiationChecks(config);
  return config;
}

async function discovery(profile, signal) {
  // DEFENSE: OpenID discovery can reject network, metadata or signing-configuration errors; SDK diagnostics must not enter durable task errors.
  try {
    const issuer = new URL(profile.issuer);
    const insecure = boundary('account.insecure', { url: urlObservation(issuer.href) });
    const discovered = await oidc.discovery(issuer, contract.client_id, undefined, undefined, {
      [oidc.customFetch]: operationFetch(signal), timeout: boundary('account.sdk_timeout', { profile }) / 1000,
      execute: insecure ? [oidc.allowInsecureRequests] : [],
    });
    const metadata = discovered.serverMetadata();
    return boundary('account.discovery', { value: metadata, issuer: profile.issuer,
      issuer_url: urlObservation(profile.issuer), urls: Object.fromEntries(
        ['authorization_endpoint', 'token_endpoint', 'jwks_uri'].map(key => [key, urlObservation(metadata[key])])) });
  } catch { signal?.throwIfAborted(); return boundary('account.discovery_failure', {}); }
}

async function grant(action, signal) {
  // DEFENSE: OAuth grants can fail HTTP or token-signature checks; expose the native sanitized failure instead of token-bearing SDK diagnostics.
  try { return await action(); }
  catch { signal?.throwIfAborted(); return boundary('account.grant_failure', {}); }
}

function tokenCredential(tokens, metadata, previous) {
  const claims = tokens.claims() ?? null;
  const source = { tokens: Object.fromEntries(Object.entries(tokens).filter(([, value]) => typeof value !== 'function')), claims,
    ...(previous === undefined ? {} : { previous }) };
  const now = Date.now();
  let expiration = now + tokens.expires_in * 1000;
  if (tokens.expires_in === undefined) {
    let accessClaims;
    // DEFENSE: Codex grants can omit an expiry and issue opaque access tokens; use its refresh interval when the token has no readable expiry.
    try { accessClaims = decodeJwt(tokens.access_token); } catch { accessClaims = null; }
    expiration = typeof accessClaims?.exp === 'number' ? accessClaims.exp * 1000 : now + contract.refresh_interval_ms;
  }
  const expires = dateObservation(expiration, true);
  const earliestValue = tokens.earliest_refresh_at;
  const earliest = dateObservation(typeof earliestValue === 'number' ? earliestValue * 1000 : earliestValue, typeof earliestValue === 'number');
  return boundary('account.token', { ...source, metadata, expires, earliest });
}

async function resolveCredential(profile, home, { signal, rejectedToken, requestCredential } = {}) {
  const filename = path.resolve(home, profile.auth_file);
  return locked(filename, async () => {
    const observed = credentialObservations(await readRecord(filename));
    const current = boundary('account.credential', observed);
    boundary('account.issuer_admission', { value: current, issuer: profile.issuer });
    const binding = { value: current,
      ...(requestCredential === undefined ? {} : { requestCredential }),
      ...(rejectedToken === undefined ? {} : { rejectedToken }) };
    const now = Date.now();
    const source = { ...binding, dates: observed.dates,
      threshold: dateObservation(now + 300_000, true), now_date: dateObservation(now, true) };
    // DEFENSE: A sign-in can replace the account while an earlier request awaits
    // its 401. Admit that request's principal before deciding reuse or refresh.
    if (boundary('account.refresh', source) === 'keep') return current;
    const metadata = await discovery(profile, signal);
    const config = configuration(metadata, profile, signal);
    const tokens = await grant(() => oidc.refreshTokenGrant(config, current.refresh_token), signal);
    const next = tokenCredential(tokens, metadata, current);
    await writeAtomic(filename, next);
    return next;
  });
}

function authorizationView(credential, connection, home) {
  const view = boundary('account.authorization_view', { credential, principal: principalIdentity(credential) });
  return {
    ...view,
    async refreshAfterRejection({ signal } = {}) {
      // Reuse a concurrent token rotation only for this request's principal.
      const next = await resolveCredential(connection, home, {
        signal, rejectedToken: credential.access_token, requestCredential: credential,
      });
      return authorizationView(next, connection, home);
    },
  };
}

export async function authorize(profile, home, { signal } = {}) {
  const credential = await resolveCredential(profile, home, { signal });
  return authorizationView(credential, profile, home);
}

async function listenForCallback(server, ports) {
  for (const port of ports) {
    try {
      await new Promise((resolve, reject) => {
        const failed = error => {
          server.off('listening', listening);
          reject(error);
        };
        const listening = () => {
          server.off('error', failed);
          resolve();
        };
        server.once('error', failed);
        server.once('listening', listening);
        server.listen(port, '127.0.0.1');
      });
      return;
    // DEFENSE: A different program can occupy the primary Codex callback port; try only the declared alternate.
    } catch (error) {
      if (error.code !== 'EADDRINUSE' || port === ports.at(-1)) throw error;
    }
  }
}

/** Both entry points authorize the same installation account. */
export async function login(profile, home, { signal, onAuthorize = () => {} } = {}) {
  const lifetime = signal ? AbortSignal.any([signal, AbortSignal.timeout(contract.login_timeout_ms)]) : AbortSignal.timeout(contract.login_timeout_ms);
  const metadata = await discovery(profile, lifetime);
  const filename = path.resolve(home, profile.auth_file);
  return locked(filename, async () => {
    lifetime.throwIfAborted();
    const state = oidc.randomState();
    const nonce = oidc.randomNonce();
    const verifier = oidc.randomPKCECodeVerifier();
    let resolveCallback, rejectCallback;
    const callback = new Promise((resolve, reject) => { resolveCallback = resolve; rejectCallback = reject; });
    // DEFENSE: Timeout can reject the callback while onAuthorize is still displaying the URL; attach a handler until the callback is awaited below.
    callback.catch(() => {});
    const server = http.createServer();
    const receiveCallback = (redirect, request, response) => {
      let url;
      // DEFENSE: The loopback HTTP listener also receives malformed request targets; native callback admission responds without accepting a grant.
      try { url = new URL(request.url, redirect); } catch { url = null; }
      const decision = boundary('account.callback', { request: { method: request.method, host: request.headers.host },
        url: url ? urlObservation(url.href) : null, redirect: urlObservation(redirect.href), state,
        parameters: Object.fromEntries(['code', 'state', 'client_id', 'error'].map(key => [key, url ? url.searchParams.getAll(key) : []])) });
      // DEFENSE: Unparseable targets and unrelated paths do not supply an authorization response.
      if (decision.action === 'ignore') { response.writeHead(decision.status, decision.headers); response.end(decision.body); return; }
      // DEFENSE: An OAuth error or invalid callback parameters reject this login rather than exchanging an untrusted code.
      if (decision.action === 'reject') {
        response.writeHead(decision.status, decision.headers); response.end(decision.body);
        rejectCallback(new Error(decision.message)); return;
      }
      response.writeHead(decision.status, decision.headers);
      response.end(decision.body);
      resolveCallback(url);
    };
    const abort = () => rejectCallback(lifetime.reason);
    lifetime.addEventListener('abort', abort, { once: true });
    try {
      await listenForCallback(server, boundary('account.callback_ports', { issuer_url: urlObservation(profile.issuer) }));
      const redirect = new URL(`http://127.0.0.1:${server.address().port}${contract.callback_path}`);
      server.on('request', (request, response) => receiveCallback(redirect, request, response));
      lifetime.throwIfAborted();
      const parameters = boundary('account.auth_parameters', { redirectUri: redirect.href, state, nonce,
        challenge: await oidc.calculatePKCECodeChallenge(verifier) });
      const config = configuration(metadata, profile, lifetime);
      const authorize = oidc.buildAuthorizationUrl(config, parameters);
      await onAuthorize({ url: authorize.href });
      // The single await owns settlement; repeated HTTP callbacks cannot start another exchange.
      const url = await callback;
      const tokens = await grant(() => oidc.authorizationCodeGrant(config, url,
        boundary('account.code_grant_checks', { nonce, state, verifier })), lifetime);
      const saved = tokenCredential(tokens, metadata);
      await writeAtomic(filename, saved);
      return boundary('account.login_result', { saved, filename });
    } finally {
      lifetime.removeEventListener('abort', abort);
      server.closeAllConnections();
      await new Promise(resolve => server.close(resolve));
    }
  });
}

export function createAudioAccount({ home, config, onChange = () => {} }) {
  const profile = boundary('account.default_login_account', { config });
  const filename = profile === null ? null : path.resolve(home, profile.auth_file);
  let pending;
  let closed = false;
  return {
    async connections({ signal } = {}) {
      signal?.throwIfAborted();
      // DEFENSE: An installation can disable ChatGPT account discovery with no explicit account configured.
      if (filename === null) return [];
      const value = await readRecord(filename, true);
      if (value === null) return [];
      const credential = boundary('account.credential', credentialObservations(value));
      boundary('account.issuer_admission', { value: credential, issuer: profile.issuer });
      return [{ id: 'chatgpt-voice', label: 'ChatGPT', source: 'chatgpt_audio', authorized: true }];
    },
    async authorize(connectionId, { signal } = {}) {
      boundary('account.audio_connection', { connectionId });
      // DEFENSE: A request can name the ChatGPT connection while this installation has account access disabled.
      if (profile === null) throw new Error('ChatGPT account access is disabled in this configuration');
      return authorize(profile, home, { signal });
    },
    startLogin({ signal } = {}) {
      if (closed) throw new Error('ChatGPT audio account is closed');
      // DEFENSE: The browser can request login while ChatGPT account access is disabled.
      if (profile === null) throw new Error('ChatGPT account access is disabled in this configuration');
      if (pending) return pending.ready;
      const controller = new AbortController();
      const lifetime = AbortSignal.any([controller.signal, signal].filter(Boolean));
      let resolveURL, rejectURL;
      const ready = new Promise((resolve, reject) => { resolveURL = resolve; rejectURL = reject; });
      const entry = { ready, controller, completion: null };
      pending = entry;
      entry.completion = login(profile, home, { signal: lifetime,
        onAuthorize: ({ url }) => resolveURL({ url }),
      }).then(() => onChange({ type: 'account_changed' }), error => {
        rejectURL(error);
        if (!lifetime.aborted) onChange({ type: 'account_changed', error: 'ChatGPT sign-in failed; try again' });
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
