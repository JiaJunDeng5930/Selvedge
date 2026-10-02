import { access, readFile, stat } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { accountAutoPreset } from './reasoning-config.mjs';
import { accountConnection, authorize, defaultChatGPTAccount } from './chatgpt-account.mjs';
import { requestJson } from './network.mjs';
import { writeAtomic } from './files.mjs';
import { modelsURL } from './chatgpt-contract.mjs';

const maximum = 1024 * 1024;
const freshFor = 5 * 60_000;
const usableFor = 24 * 60 * 60_000;
const cacheFormat = 'selvedge-siwc-models-1';
const hash = text => createHash('sha256').update(text).digest('hex').slice(0, 16);
const text = value => typeof value === 'string' && value.trim().length > 0 && value.length <= 256;
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);

/** Only account-visible models are candidates; supported_in_api is irrelevant here. */
export function accountModels(value) {
  if (!object(value) || !Array.isArray(value.models) || value.models.length > 512) {
    throw new Error('ChatGPT returned an invalid model catalog');
  }
  const slugs = new Set();
  const models = value.models.map(model => {
    if (!object(model) || !text(model.slug) || !text(model.display_name) ||
        !/^[A-Za-z0-9][A-Za-z0-9._:/-]*$/.test(model.slug) || slugs.has(model.slug) ||
        !['list', 'hide', 'none'].includes(model.visibility) ||
        (Object.hasOwn(model, 'priority') && !Number.isSafeInteger(model.priority)) ||
        (Object.hasOwn(model, 'supported_reasoning_levels') && (!Array.isArray(model.supported_reasoning_levels) ||
          model.supported_reasoning_levels.length > 32 || model.supported_reasoning_levels.some(level =>
            !object(level) || !text(level.effort)))) ||
        (model.default_reasoning_level != null && !text(model.default_reasoning_level))) {
      throw new Error('ChatGPT returned an invalid model descriptor');
    }
    slugs.add(model.slug);
    return {
      slug: model.slug, display_name: model.display_name, visibility: model.visibility,
      ...(Object.hasOwn(model, 'priority') ? { priority: model.priority } : {}),
      ...(Object.hasOwn(model, 'default_reasoning_level') ? { default_reasoning_level: model.default_reasoning_level } : {}),
      ...(Object.hasOwn(model, 'supported_reasoning_levels') ? {
        supported_reasoning_levels: model.supported_reasoning_levels.map(level => ({ effort: level.effort })),
      } : {}),
    };
  });
  return models;
}

function connectionIdentity(profile) {
  return `${modelsURL(profile.endpoint)}\0${profile.issuer}`;
}

export function modelCacheFile(profile, home) {
  return `${path.resolve(home, profile.auth_file)}.models-${hash(connectionIdentity(profile))}.json`;
}

async function readCache(profile, home, account, now) {
  const filename = modelCacheFile(profile, home);
  try {
    if ((await stat(filename)).size > maximum) return undefined;
    const cache = JSON.parse(await readFile(filename, 'utf8'));
    const age = now - Date.parse(cache.fetched_at);
    if (cache.format !== cacheFormat || cache.account_id !== account ||
        cache.connection !== connectionIdentity(profile) ||
        !Number.isFinite(age) || age < 0 || age > usableFor) return undefined;
    return { models: accountModels(cache), age };
  } catch (error) {
    // A cache is disposable and never a source of credentials or parser diagnostics.
    if (error.code && error.code !== 'ENOENT') throw new Error('Cannot read the ChatGPT model cache');
    return undefined;
  }
}

/** Discovery never performs interactive login and never reads a different app's credentials. */
export async function discoverAccount(profile, home, { signal, force = false, now = Date.now() } = {}) {
  const lifetime = signal ? AbortSignal.any([signal, AbortSignal.timeout(profile.timeout_ms)]) : AbortSignal.timeout(profile.timeout_ms);
  let authorization = await authorize(profile, home, { signal: lifetime });
  const cached = await readCache(profile, home, authorization.account_id, now);
  if (!force && cached && cached.age < freshFor) return { account_id: authorization.account_id, models: cached.models, cached: true, stale: false };
  const fetchCatalog = () => requestJson(modelsURL(profile.endpoint), {
    method: 'GET', headers: authorization.headers, signal: lifetime, maximum,
  });
  let response;
  try {
    response = await fetchCatalog();
  } catch (error) {
    signal?.throwIfAborted();
    if (!force && cached && (error instanceof TypeError || error.name === 'TimeoutError')) {
      return { account_id: authorization.account_id, models: cached.models, cached: true, stale: true };
    }
    throw new Error('Could not fetch the ChatGPT model catalog', { cause: error });
  }
  if (response.status === 401) {
    authorization = await authorization.refreshAfterRejection({ signal: lifetime });
    response = await fetchCatalog();
  }
  if (!response.ok) {
    if (!force && cached && (response.status === 429 || response.status >= 500)) {
      return { account_id: authorization.account_id, models: cached.models, cached: true, stale: true };
    }
    throw new Error(`ChatGPT model discovery failed with HTTP ${response.status}`);
  }
  const models = accountModels(response.value);
  if (!models.some(model => model.visibility === 'list')) throw new Error('This ChatGPT account advertised no selectable models');
  await writeAtomic(modelCacheFile(profile, home), {
    format: cacheFormat, account_id: authorization.account_id, connection: connectionIdentity(profile),
    fetched_at: new Date(now).toISOString(), models,
  });
  return { account_id: authorization.account_id, models, cached: false, stale: false };
}

export function loginAccount(config, key) {
  if (key !== undefined) {
    const selected = config.profiles[key];
    if (selected?.provider !== 'chatgpt') throw new Error('Select a ChatGPT profile or omit the profile to sign in');
    return selected;
  }
  const configured = Object.values(config.profiles).find(profile => profile.provider === 'chatgpt');
  if (!configured && config.chatgpt === false) throw new Error('Automatic ChatGPT account discovery is disabled in this configuration');
  return configured || config.chatgpt || defaultChatGPTAccount;
}

/** Materialize discovery as ordinary native profiles, preserving frozen task identity. */
export async function withAccountModels(config, home, { signal, force = false, onDiagnostic = () => {} } = {}) {
  const configured = Object.values(config.profiles).filter(profile => profile.provider === 'chatgpt');
  const primary = config.chatgpt === false ? [] : [config.chatgpt ?? defaultChatGPTAccount];
  const candidates = [...configured, ...primary.filter(profile => !configured.some(other =>
    path.resolve(home, other.auth_file) === path.resolve(home, profile.auth_file)))];
  const seen = new Set();
  const generated = {};
  const accounts = [];
  for (const profile of candidates) {
    const identity = `${path.resolve(home, profile.auth_file)}\0${connectionIdentity(profile)}`;
    if (seen.has(identity)) continue;
    seen.add(identity);
    try { await access(path.resolve(home, profile.auth_file)); }
    catch (error) { if (error.code === 'ENOENT') continue; throw error; }
    try {
      const result = await discoverAccount(profile, home, { signal, force });
      const namespace = `chatgpt/${hash(`${result.account_id}\0${connectionIdentity(profile)}`)}`;
      for (const model of result.models.filter(model => model.visibility === 'list')) {
        const key = `${namespace}/${model.slug}`;
        if (Object.hasOwn(config.profiles, key)) throw new Error('A configured profile conflicts with an account model');
        generated[key] = Object.freeze({ ...accountConnection(profile), model: model.slug, bound_account_id: result.account_id,
          model_info: Object.freeze(model) });
        const auto = Array.isArray(model.supported_reasoning_levels) ? accountAutoPreset(generated[key], model) : undefined;
        const autoKey = `${namespace}/${model.slug}-auto`;
        // A manually configured profile overrides the login convenience. Its
        // evaluator connection remains independent of the ChatGPT credentials.
        if (auto && !Object.hasOwn(config.profiles, autoKey)) generated[autoKey] = auto;
      }
      accounts.push({ models: result.models.filter(model => model.visibility === 'list').length,
        cached: result.cached, stale: result.stale });
      if (result.stale) onDiagnostic('ChatGPT is temporarily unavailable; using this account’s cached model catalog');
    } catch (error) {
      signal?.throwIfAborted();
      if (force) throw error;
      onDiagnostic(error.message);
    }
  }
  // Advertised models precede the offline demo, so login changes the default picker.
  return { config: { ...config, profiles: { ...generated, ...config.profiles } }, accounts };
}
