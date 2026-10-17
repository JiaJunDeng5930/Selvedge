import { readFile, access } from 'node:fs/promises';
import { homedir } from 'node:os';
import path from 'node:path';
import { accountConfig, accountConnection } from './chatgpt-account.mjs';
import { adaptivePolicy, evaluatorConnections, configurationObserver } from './reasoning-config.mjs';
import { connectionConfig } from './chatgpt-plugin.mjs';

import { boundary } from './public/model-boundary.mjs';

export const defaultConfig = boundary('config.defaults', {});
export const format = defaultConfig.format;
const contextDefinitions = boundary('config.context_definitions', {});

function contextSettings(definitions = contextDefinitions) {
  return definitions.filter(definition => ['config_text', 'config_files'].includes(definition.observer.type));
}

const configurationFiles = new WeakMap();

/** Only configurations loaded from disk participate in file refresh. */
export function configurationFilename(config) {
  return configurationFiles.get(config);
}

function urlObservation(value) {
  try {
    const url = new URL(value);
    return Object.fromEntries(['href', 'protocol', 'hostname', 'port', 'username', 'password', 'hash', 'pathname', 'search', 'origin'].map(key => [key, url[key]]));
  } catch { return null; }
}

function profileBoundary(operation, source) {
  try { return boundary(operation, source); }
  catch (error) { throw new TypeError(error.message); }
}

function configurationHead(value, observer) {
  const contextKeys = new Set(contextSettings().map(definition => definition.observer.setting));
  const root = observer.observe(value, { shallow: true });
  if (root.kind === 'object') root.fields = Object.entries(value).map(([key, item]) => ({
    key: observer.observe(key), value: observer.observe(item, { shallow: key !== 'format' && !contextKeys.has(key) }),
  }));
  return observer.materialize(observer.execute('config.configuration_head', { value: root }));
}

/** Observe mutable context configuration without changing frozen task policy. */
export function contextConfiguration(value, definitions = contextDefinitions) {
  const observer = configurationObserver();
  const current = configurationHead(value, observer);
  const settings = Object.fromEntries(contextSettings(definitions).map(definition => {
    const { type, setting } = definition.observer;
    return [setting, Object.hasOwn(current, setting) ? current[setting] : (type === 'config_text' ? '' : [])];
  }));
  observer.execute('config.context_transport', contextTransport(settings, definitions, observer));
  return settings;
}

function textObservation(value) {
  return { bytes: typeof value === 'string' ? Buffer.byteLength(value, 'utf8') : null,
    well_formed: typeof value === 'string' && value.isWellFormed() && !value.includes('\0') };
}

function contextTransport(config, definitions, observer) {
  return { definitions,
    values: Object.fromEntries(contextSettings(definitions).map(definition => {
      const setting = definition.observer.setting;
      return [setting, observer.observe(config[setting])];
    })),
    observations: Object.fromEntries(contextSettings(definitions).map(definition => {
      const setting = definition.observer.setting;
      const value = config[setting];
      return [setting, { ...textObservation(value), items: Array.isArray(value) ? value.map(textObservation) : [] }];
    })) };
}

export function validateConfig(value) {
  const observer = configurationObserver();
  const config = configurationHead(value, observer);
  config.chatgpt_plugin = connectionConfig(value.chatgpt_plugin);
  config.chatgpt = value.chatgpt === false ? false : accountConfig(value.chatgpt);
  config.reasoning_evaluators = evaluatorConnections(value.reasoning_evaluators);
  config.remote = profileBoundary('config.remote', {
    remote: value.remote === undefined ? false : value.remote,
    endpoint_observation: urlObservation(value.remote?.relay_url),
  });
  observer.execute('config.configuration_transport', {
    transport: Object.fromEntries(['host', 'port', 'max_fork', 'max_descendants', 'profiles'].map(key =>
      [key, observer.observe(config[key], { shallow: key === 'profiles' })])),
    context: contextTransport(config, contextDefinitions, observer),
  });
  config.profiles = Object.fromEntries(Object.entries(config.profiles).map(([key, source]) => {
    profileBoundary('backend.profile_head', { key, profile: source });
    const adaptive = adaptivePolicy(source.adaptive_reasoning);
    const endpoint = boundary('backend.endpoint', { profile: source });
    const profile = profileBoundary('backend.profile', {
      key, profile: source, adaptive, endpoint_observation: urlObservation(endpoint),
    });
    const backend = boundary('backend.support', { profile, effect: { model: { provider: profile.provider } } });
    if (backend.auth === 'account') Object.assign(profile, accountConnection(profile));
    return [key, Object.freeze(profile)];
  }));
  config.compaction = profileBoundary('config.compaction', { config: { compaction: value.compaction }, profiles: compactionProfiles(config.profiles) });
  observer.execute('config.configuration_extensions', {
    mcp: observer.observe(config.mcp), plugins: observer.observe(config.plugins),
  });
  return config;
}

export function homeDirectory(home) {
  return path.resolve(home ?? process.env.SELVEDGE_HOME ?? path.join(homedir(), '.selvedge-bend'));
}

export async function loadConfig({ home, filename } = {}) {
  home = homeDirectory(home);
  filename = filename ? path.resolve(filename) : path.join(home, 'config.json');
  let config;
  try { config = JSON.parse(await readFile(filename, 'utf8')); }
  catch (error) {
    if (error.code !== 'ENOENT') throw error;
    if (filename !== path.join(home, 'config.json')) throw error;
    try { await access(path.join(home, 'config.toml')); }
    catch (legacyError) { if (legacyError.code !== 'ENOENT') throw legacyError; config = structuredClone(defaultConfig); }
    if (!config) throw new Error('A legacy config.toml exists in this home; choose a new home or supply the current config.json explicitly');
  }
  const validated = validateConfig(config);
  configurationFiles.set(validated, filename);
  return { home, filename, config: validated };
}

export function profileCatalog(config) {
  return boundary('backend.profile_catalog', { config });
}

function compactionProfiles(profiles) {
  return Object.fromEntries(Object.entries(profiles).map(([key, profile]) => [key, {
    provider: profile.provider, model_info: profile.model_info,
  }]));
}

/** Resolve maintenance budgets only after account model discovery has completed. */
export function compactionSettings(config) {
  return boundary('config.compaction_runtime', { config: {
    compaction: config.compaction, profiles: compactionProfiles(config.profiles),
  } });
}
