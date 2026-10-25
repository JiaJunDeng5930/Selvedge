import { access } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { accountConnection, authorize, defaultChatGPTAccount } from './chatgpt-account.mjs';
import { requestJson } from './network.mjs';
import { writeAtomic } from './files.mjs';
import { readBoundedRegularSnapshot } from './file-io.mjs';
import { boundary } from './public/model-boundary.mjs';
import { modelsURL } from './chatgpt-contract.mjs';

const maximum = boundary('account.contract', {}).maximum;
const hash = text => boundary('account.hash_prefix', { text, digest: createHash('sha256').update(text).digest('hex') });
function numberObservation(value) {
  // DEFENSE: Invalid persisted cache dates produce a non-finite age, which native cache admission must reject.
  return Number.isFinite(value) ? { value, floor: Math.floor(value), ceil: Math.ceil(value) } : null;
}
function dateObservation(value, numeric = false) {
  // DEFENSE: An externally edited cache may contain a non-string fetched_at value; native cache admission must see an invalid date observation.
  if (typeof value !== (numeric ? 'number' : 'string')) return null;
  const date = new Date(numeric ? value : Date.parse(value));
  const epoch = date.getTime();
  // DEFENSE: A persisted cache timestamp can be invalid; null lets native cache admission discard that record.
  if (!Number.isFinite(epoch)) return null;
  return { iso: date.toISOString(), ordered_epoch: String(BigInt(epoch) + 8640000000000000n).padStart(17, '0') };
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
  let contents;
  try {
    const snapshot = await readBoundedRegularSnapshot(filename, { maximumBytes: 1048576, noFollow: false });
    contents = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(snapshot.bytes);
  } catch (error) {
    // DEFENSE: A missing cache causes discovery; other filesystem failures become a native cache-read error.
    return boundary('account.cache_error', { profile, home, account, now, filename, code: error.code }) ?? undefined;
  }
  const cache = boundary('account.cache_decode', { text: contents });
  const fetched = dateObservation(cache?.fetched_at);
  return boundary('account.cache', { value: cache, profile, home, account, now,
    elapsed: numberObservation(now - Date.parse(fetched?.iso)),
    fetched, connection: connectionIdentity(profile) }) ?? undefined;
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
    // DEFENSE: Network/timeout discovery failures may use this account's admitted cache unless a fresh catalog was explicitly requested.
    if (boundary('account.cache_fallback', { profile, home, now, force, cached, type_error: error instanceof TypeError, error_name: error.name })) {
      return boundary('account.catalog_result', { profile, home, force, now, authorization: { account_id: authorization.account_id }, cached, cached_result: true, stale: true });
    }
    throw new Error(boundary('account.catalog_fetch_failure', { profile, home, force, now, error_name: error.name, type_error: error instanceof TypeError }), { cause: error });
  }
  // DEFENSE: A catalog HTTP 401 can follow server-side token rejection; refresh once before reporting the repeated rejection.
  if (boundary('account.catalog_transport', { status: response.status, ok: response.ok }) === 'refresh') {
    authorization = await authorization.refreshAfterRejection({ signal: lifetime });
    response = await fetchCatalog();
  }
  // DEFENSE: Non-success catalog HTTP responses cannot be admitted as model data.
  if (boundary('account.catalog_transport', { status: response.status, ok: response.ok }) !== 'success') {
    // DEFENSE: HTTP 429/5xx may use the admitted cache during automatic discovery; forced refresh must surface the failure.
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
    // DEFENSE: Automatic discovery observes credentials that may be absent or unreadable; native admission distinguishes ENOENT from an access failure.
    catch (error) {
      readFailure = error;
      read = { ok: false, error: { code: error.code, name: error.name, message: error.message } };
    }
    const selected = boundary('account.candidate_read', { config, home, force, profile: candidate, candidate, read });
    // DEFENSE: A connection without a credential file has not been signed in and contributes no discovered models.
    if (selected.action === 'skip') continue;
    // DEFENSE: Credential access failures other than ENOENT must remain visible rather than acting like a signed-out connection.
    if (selected.action === 'fail') throw readFailure;
    const profile = selected.candidate;
    let result, namespace, profiles, summary, diagnostic;
    try {
      result = await discoverAccount(profile, home, { signal, force });
      namespace = boundary('account.account_namespace', { config, home, force, profile, result, hash: hash(boundary('account.candidate_identity', { resolved: result.account_id, connection: connectionIdentity(profile) })) });
      profiles = boundary('account.materialize', { config, home, force, profile, result, namespace,
        connection: accountConnection(profile), auth_path: filename, configured_auth_paths: configuredAuthPaths });
      summary = boundary('account.account_summary', { config, home, force, profile, result });
      diagnostic = boundary('account.materialization_diagnostic', { config, home, force, profile, result });
    } catch (error) {
      signal?.throwIfAborted();
      const decision = boundary('account.materialization_failure', { config, home, profile, force, message: error.message });
      // DEFENSE: Explicit catalog refresh must fail on credential, network or catalog admission errors.
      if (decision.rethrow) throw error;
      // DEFENSE: Automatic account discovery reports unavailable accounts while leaving configured non-account profiles usable.
      onDiagnostic(decision.message);
      continue;
    }
    discoveries.push({ namespace, connection: accountConnection(profile), auth_path: filename, result: { account_id: result.account_id } });
    for (const [key, value] of Object.entries(profiles)) generated[key] = freezeProfile(value);
    accounts.push(summary);
    if (diagnostic !== null) onDiagnostic(diagnostic);
  }
  // Advertised models precede the offline demo, so login changes the default picker.
  return { config: boundary('account.config_materialized', { config, home, force, generated, discoveries, configured_auth_paths: configuredAuthPaths }), accounts };
}
