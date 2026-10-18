import { access, readFile, stat } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { accountConnection, authorize, defaultChatGPTAccount } from './chatgpt-account.mjs';
import { requestJson } from './network.mjs';
import { writeAtomic } from './files.mjs';
import { boundary as modelBoundary } from './public/model-boundary.mjs';
function boundary(operation, source) {
  try { return modelBoundary(operation, source); }
  catch (error) {
    if (error.code === 'RangeError') throw new RangeError(error.message);
    throw error;
  }
}
import { modelsURL } from './chatgpt-contract.mjs';

const maximum = boundary('account.contract', {}).maximum;
const hash = text => boundary('account.hash_prefix', { text, digest: createHash('sha256').update(text).digest('hex') });
function numberObservation(value) {
  return Number.isFinite(value) ? { value, floor: Math.floor(value), ceil: Math.ceil(value) } : null;
}
function dateObservation(value, numeric = false) {
  const instant = numeric ? value : Date.parse(value);
  if (!Number.isFinite(instant)) return null;
  try {
    const date = new Date(instant);
    return { iso: date.toISOString(), ordered_epoch: String(BigInt(date.getTime()) + 8640000000000000n).padStart(17, '0') };
  } catch { return null; }
}
function freezeProfile(profile) {
  if (profile.model_info) Object.freeze(profile.model_info);
  if (profile.adaptive_reasoning) {
    Object.freeze(profile.adaptive_reasoning.efforts);
    Object.freeze(profile.adaptive_reasoning);
  }
  return Object.freeze(profile);
}
/** Only account-visible models are candidates; supported_in_api is irrelevant here. */
export function accountModels(value) {
  return boundary('account.catalog', { value });
}

function connectionIdentity(profile) {
  return boundary('account.connection_identity', { profile, models_url: modelsURL(profile.endpoint) });
}

export function modelCacheFile(profile, home) {
  return boundary('account.model_cache_path', { profile, home, resolved: path.resolve(home, profile.auth_file), hash: hash(connectionIdentity(profile)) });
}

async function readCache(profile, home, account, now) {
  const filename = modelCacheFile(profile, home);
  try {
    if (!boundary('account.cache_size', { profile, home, account, now, filename, size: (await stat(filename)).size })) return undefined;
    const cache = JSON.parse(await readFile(filename, 'utf8'));
    return boundary('account.cache', { value: cache, profile, home, account, now,
      elapsed: numberObservation(now - Date.parse(cache.fetched_at)),
      fetched: dateObservation(cache.fetched_at), connection: connectionIdentity(profile) }) ?? undefined;
  } catch (error) {
    // A cache is disposable and never a source of credentials or parser diagnostics.
    return boundary('account.cache_error', { profile, home, account, now, filename, code: error.code }) ?? undefined;
  }
}

/** Discovery never performs interactive login and never reads a different app's credentials. */
export async function discoverAccount(profile, home, { signal, force = false, now = Date.now() } = {}) {
  const lifetime = signal ? AbortSignal.any([signal, AbortSignal.timeout(profile.timeout_ms)]) : AbortSignal.timeout(profile.timeout_ms);
  let authorization = await authorize(profile, home, { signal: lifetime });
  const cached = await readCache(profile, home, authorization.account_id, now);
  if (boundary('account.cache_fresh', { profile, home, force, now, cached, age_measurement: numberObservation(cached?.age) })) return boundary('account.catalog_result', { profile, home, force, now, authorization: { account_id: authorization.account_id }, cached, cached_result: true, stale: false });
  const fetchCatalog = () => requestJson(modelsURL(profile.endpoint), {
    method: 'GET', headers: authorization.headers, signal: lifetime, maximum,
  });
  let response;
  try {
    response = await fetchCatalog();
  } catch (error) {
    signal?.throwIfAborted();
    if (boundary('account.cache_fallback', { profile, home, now, force, cached, type_error: error instanceof TypeError, error_name: error.name })) {
      return boundary('account.catalog_result', { profile, home, force, now, authorization: { account_id: authorization.account_id }, cached, cached_result: true, stale: true });
    }
    throw new Error(boundary('account.catalog_fetch_failure', { profile, home, force, now, error_name: error.name, type_error: error instanceof TypeError }), { cause: error });
  }
  if (boundary('account.catalog_transport', { status: response.status, ok: response.ok }) === 'refresh') {
    authorization = await authorization.refreshAfterRejection({ signal: lifetime });
    response = await fetchCatalog();
  }
  if (boundary('account.catalog_transport', { status: response.status, ok: response.ok }) !== 'success') {
    if (boundary('account.cache_fallback', { profile, home, now, force, cached, status: response.status })) {
      return boundary('account.catalog_result', { profile, home, force, now, authorization: { account_id: authorization.account_id }, cached, cached_result: true, stale: true });
    }
    boundary('account.catalog_failure', { status: response.status });
  }
  const models = accountModels(response.value);
  boundary('account.catalog_selectable', { models });
  await writeAtomic(modelCacheFile(profile, home), boundary('account.cache_record', {
    profile, home, force, account: authorization.account_id, connection: connectionIdentity(profile), now, now_date: dateObservation(now, true), models,
  }));
  return boundary('account.catalog_result', { profile, home, force, now, authorization: { account_id: authorization.account_id }, models, cached_result: false, stale: false });
}

export function loginAccount(config, key) {
  return boundary('account.login_account', { config, key });
}

/** Materialize discovery as ordinary native profiles, preserving frozen task identity. */
export async function withAccountModels(config, home, { signal, force = false, onDiagnostic = () => {} } = {}) {
  const configuredAuthPaths = Object.fromEntries(Object.entries(config.profiles).map(([key, profile]) =>
    [key, path.resolve(home, profile.auth_file ?? defaultChatGPTAccount.auth_file)]));
  const observedCandidates = boundary('account.candidates', { config, home, force }).map(candidate => ({ ...candidate,
    path: path.resolve(home, candidate.profile.auth_file),
    identity: boundary('account.candidate_identity', { config, home, force, candidate, resolved: path.resolve(home, candidate.profile.auth_file), connection: connectionIdentity(candidate.profile) }) }));
  const candidates = boundary('account.candidate_paths', { config, home, force, candidates: observedCandidates });
  const generated = {};
  const accounts = [];
  const discoveries = [];
  for (const candidate of candidates) {
    const filename = path.resolve(home, candidate.auth_file);
    let read, readFailure;
    try { await access(filename); read = { ok: true, path: filename }; }
    catch (error) {
      readFailure = error;
      read = { ok: false, error: { code: error.code, name: error.name, message: error.message } };
    }
    const selected = boundary('account.candidate_read', { config, home, force, profile: candidate, candidate, read });
    if (selected.action === 'skip') continue;
    if (selected.action === 'fail') throw readFailure;
    const profile = selected.candidate;
    try {
      const result = await discoverAccount(profile, home, { signal, force });
      const namespace = boundary('account.account_namespace', { config, home, force, profile, result, hash: hash(boundary('account.candidate_identity', { resolved: result.account_id, connection: connectionIdentity(profile) })) });
      discoveries.push({ namespace, connection: accountConnection(profile), auth_path: filename, result: { account_id: result.account_id } });
      const profiles = boundary('account.materialize', { config, home, force, profile, result, namespace,
        connection: accountConnection(profile), auth_path: filename, configured_auth_paths: configuredAuthPaths });
      for (const [key, value] of Object.entries(profiles)) generated[key] = freezeProfile(value);
      accounts.push(boundary('account.account_summary', { config, home, force, profile, result }));
      const diagnostic = boundary('account.materialization_diagnostic', { config, home, force, profile, result });
      if (diagnostic !== null) onDiagnostic(diagnostic);
    } catch (error) {
      signal?.throwIfAborted();
      const decision = boundary('account.materialization_failure', { config, home, profile, force, message: error.message });
      if (decision.rethrow) throw error;
      onDiagnostic(decision.message);
    }
  }
  // Advertised models precede the offline demo, so login changes the default picker.
  return { config: boundary('account.config_materialized', { config, home, force, generated, discoveries, configured_auth_paths: configuredAuthPaths }), accounts };
}
