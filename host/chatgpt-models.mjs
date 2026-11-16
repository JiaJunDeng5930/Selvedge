import { createHash } from 'node:crypto';
import path from 'node:path';
import { accountConnection, authorize, defaultChatGPTAccount } from './chatgpt-account.mjs';
import { requestJson } from './network.mjs';
import { writeAtomic } from './files.mjs';
import { readBoundedRegularSnapshot } from './file-io.mjs';
import { boundary } from './public/model-boundary.mjs';
import { modelsURL, modelCatalogURL } from './chatgpt-contract.mjs';

const maximum = boundary('account.contract', {}).maximum;
const hash = text => boundary('account.hash_prefix', { digest: createHash('sha256').update(text).digest('hex') });
function cacheAge(value, now) {
  // DEFENSE: An externally edited cache may contain a non-string fetched_at value; native cache admission must see an invalid age.
  if (typeof value !== 'string') return null;
  const elapsed = now - Date.parse(value);
  // DEFENSE: A persisted cache timestamp can be invalid; null lets native cache admission discard that record.
  return Number.isFinite(elapsed) ? elapsed : null;
}
function connectionIdentity(profile) {
  return boundary('account.connection_identity', { profile, models_url: modelsURL(profile.endpoint) });
}

async function readCache(filename, account, connection, now) {
  let contents;
  try {
    const snapshot = await readBoundedRegularSnapshot(filename, { maximumBytes: 1048576, noFollow: false });
    contents = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(snapshot.bytes);
  } catch (error) {
    // DEFENSE: A missing cache causes discovery; other filesystem failures become a native cache-read error.
    return boundary('account.cache_error', { code: error.code });
  }
  const cache = boundary('account.cache_decode', { text: contents });
  return boundary('account.cache', { value: cache, account, connection, elapsed: cacheAge(cache?.fetched_at, now) });
}

/** Discovery never performs interactive login and never reads a different app's credentials. */
export async function discoverAccount(profile, home, { signal, force = false, optional = false } = {}) {
  const lifetime = signal ? AbortSignal.any([signal, AbortSignal.timeout(profile.timeout_ms)]) : AbortSignal.timeout(profile.timeout_ms);
  let authorization = await authorize(profile, home, { signal: lifetime, optional });
  if (authorization === null) return null;
  const now = Date.now();
  const connection = connectionIdentity(profile);
  const filename = boundary('account.model_cache_path', { resolved: path.resolve(home, profile.auth_file), hash: hash(connection) });
  const cached = await readCache(filename, authorization.account_id, connection, now);
  if (boundary('account.cache_fresh', { force, cached })) return boundary('account.catalog_result', { authorization: { account_id: authorization.account_id }, cached, cached_result: true, stale: false });
  const endpoint = modelCatalogURL(profile.endpoint);
  const fetchCatalog = () => requestJson(endpoint, {
    method: 'GET', headers: authorization.headers, signal: lifetime, maximum,
  });
  let response;
  try {
    response = await fetchCatalog();
  } catch (error) {
    signal?.throwIfAborted();
    // DEFENSE: Network/timeout discovery failures may use this account's admitted cache unless a fresh catalog was explicitly requested.
    if (boundary('account.cache_fallback', { force, cached, type_error: error instanceof TypeError, error_name: error.name })) {
      return boundary('account.catalog_result', { authorization: { account_id: authorization.account_id }, cached, cached_result: true, stale: true });
    }
    throw new Error(boundary('account.catalog_fetch_failure', {}), { cause: error });
  }
  // DEFENSE: A catalog HTTP 401 can follow server-side token rejection; refresh once before reporting the repeated rejection.
  let outcome = boundary('account.catalog_transport', { status: response.status, ok: response.ok });
  if (outcome === 'refresh') {
    authorization = await authorization.refreshAfterRejection({ signal: lifetime });
    response = await fetchCatalog();
    outcome = boundary('account.catalog_transport', { status: response.status, ok: response.ok });
  }
  // DEFENSE: Non-success catalog HTTP responses cannot be admitted as model data.
  if (outcome !== 'success') {
    // DEFENSE: HTTP 429/5xx may use the admitted cache during automatic discovery; forced refresh must surface the failure.
    if (boundary('account.cache_fallback', { force, cached, status: response.status })) {
      return boundary('account.catalog_result', { authorization: { account_id: authorization.account_id }, cached, cached_result: true, stale: true });
    }
    boundary('account.catalog_failure', { status: response.status });
  }
  const models = boundary('account.discovery_catalog', { value: response.value });
  await writeAtomic(filename, boundary('account.cache_record', {
    account: authorization.account_id, connection, fetched_at: new Date(now).toISOString(), models,
  }));
  return boundary('account.catalog_result', { authorization: { account_id: authorization.account_id }, models, cached_result: false, stale: false });
}

export function loginAccount(config, key) {
  return boundary('account.login_account', { config, key });
}

/** Materialize discovery as ordinary native profiles, preserving frozen task identity. */
export async function withAccountModels(config, home, { signal, force = false, onDiagnostic = () => {} } = {}) {
  const configuredAuthPaths = Object.fromEntries(Object.entries(config.profiles).map(([key, profile]) =>
    [key, path.resolve(home, profile.auth_file ?? defaultChatGPTAccount.auth_file)]));
  const observedCandidates = boundary('account.candidates', { config }).map(candidate => ({ ...candidate,
    path: path.resolve(home, candidate.profile.auth_file),
    identity: boundary('account.candidate_identity', { resolved: path.resolve(home, candidate.profile.auth_file), connection: connectionIdentity(candidate.profile) }) }));
  const candidates = boundary('account.candidate_paths', { candidates: observedCandidates });
  const generated = {};
  const accounts = [];
  const discoveries = [];
  for (const candidate of candidates) {
    const filename = path.resolve(home, candidate.auth_file);
    const profile = candidate;
    let result, namespace, connection, profiles, summary, diagnostic;
    try {
      result = await discoverAccount(profile, home, { signal, force, optional: true });
      // A connection without a credential file has not been signed in.
      if (result === null) continue;
      namespace = boundary('account.account_namespace', { hash: hash(boundary('account.candidate_identity', { resolved: result.account_id, connection: connectionIdentity(profile) })) });
      connection = accountConnection(profile);
      ({ profiles, summary, diagnostic } = boundary('account.materialize', { config, result, namespace,
        connection, auth_path: filename, configured_auth_paths: configuredAuthPaths }));
    } catch (error) {
      signal?.throwIfAborted();
      // DEFENSE: Explicit catalog refresh must fail on credential, network or catalog admission errors.
      if (force) throw error;
      // DEFENSE: Automatic account discovery reports unavailable accounts while leaving configured non-account profiles usable.
      onDiagnostic(error.message);
      continue;
    }
    discoveries.push({ namespace, connection, auth_path: filename, result: { account_id: result.account_id } });
    Object.assign(generated, profiles);
    accounts.push(summary);
    if (diagnostic !== null) onDiagnostic(diagnostic);
  }
  return { config: boundary('account.config_materialized', { config, generated, discoveries, configured_auth_paths: configuredAuthPaths }), accounts };
}
