import { createHash } from 'node:crypto';
import { readFile, realpath } from 'node:fs/promises';
import { homedir } from 'node:os';
import path from 'node:path';
import { accountConfig, accountConnection } from './chatgpt-account.mjs';
import { adaptivePolicy, evaluatorConnections, configurationObserver } from './reasoning-config.mjs';
import { connectionConfig } from './chatgpt-plugin.mjs';
import { publishBytes } from './file-io.mjs';

import { JsonNumber, parseJson, safeInteger } from './public/json-tokens.mjs';
import { boundary } from './public/model-boundary.mjs';

export const defaultConfig = boundary('config.defaults', {});
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
  // DEFENSE: A user-configured endpoint can be an invalid URL; native admission rejects the null observation.
  } catch { return null; }
}

function profileBoundary(operation, source) {
  try { return boundary(operation, source); }
  // DEFENSE: Invalid user configuration is reported to CLI/HTTP callers as a configuration TypeError.
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
export function contextConfiguration(value, definitions) {
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
  config.cloud = profileBoundary('config.cloud', { cloud: value.cloud ?? false });
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
    if (backend.auth === 'account') Object.assign(profile, accountConfig(accountConnection(profile)));
    return [key, profile];
  }));
  config.compaction = profileBoundary('config.compaction', { config: { compaction: value.compaction }, profiles: compactionProfiles(config.profiles) });
  observer.execute('config.configuration_extensions', {
    mcp: observer.observe(config.mcp), plugins: observer.observe(config.plugins),
  });
  return config;
}

export function homeDirectory(home) {
  return path.resolve(home ?? process.env.SELVEDGE_HOME ?? path.join(homedir(), '.selvedge'));
}

function configurationLocation({ home, filename } = {}) {
  home = homeDirectory(home);
  return { home, filename: filename ? path.resolve(filename) : path.join(home, 'config.json') };
}

async function configurationFile({ home, filename }) {
  try {
    const target = await realpath(filename);
    return { target, bytes: await readFile(target) };
  } catch (error) {
    // DEFENSE: A fresh default home can run without a file. Explicit missing files and other read failures remain errors.
    if (error.code !== 'ENOENT' || filename !== path.join(home, 'config.json')) throw error;
    return { target: filename, bytes: undefined };
  }
}

function parseConfiguration(text) {
  return parseJson(text, source => {
    const token = new JsonNumber(source);
    return safeInteger(token) ?? token;
  });
}

export async function loadConfig({ home, filename, source } = {}) {
  ({ home, filename } = configurationLocation({ home, filename }));
  if (source === undefined) {
    const { bytes } = await configurationFile({ home, filename });
    source = bytes === undefined ? structuredClone(defaultConfig) : parseConfiguration(bytes.toString('utf8'));
  }
  const validated = validateConfig(source);
  configurationFiles.set(validated, filename);
  return { home, filename, config: validated, source };
}

function configurationRevision({ target, bytes }) {
  return createHash('sha256').update(target).update(bytes === undefined ? '\0missing' : '\0present')
    .update(bytes ?? '').digest('base64url');
}

function editableSource({ bytes }) {
  return bytes === undefined ? { format: defaultConfig.format }
    : parseJson(new TextDecoder('utf-8', { fatal: true }).decode(bytes));
}

export class ConfigurationConflictError extends Error {
  constructor() {
    super('Configuration changed. Reload settings before applying the edit.');
    this.name = 'ConfigurationConflictError';
  }
}

export async function readServiceConfiguration(options) {
  const current = await configurationFile(configurationLocation(options));
  const view = profileBoundary('config.editable', { configuration: editableSource(current) });
  return { ...view, revision: configurationRevision(current) };
}

const configurationWrites = new Map();

export async function changeServiceConfiguration(options, { revision, ...change }) {
  // DEFENSE: The public request can omit the revision needed to identify the edit's target.
  if (typeof revision !== 'string') throw new TypeError('A configuration revision is required');
  const location = configurationLocation(options);
  const { target } = await configurationFile(location);
  const previous = configurationWrites.get(target) ?? Promise.resolve();
  const next = previous.then(async () => {
    const current = await configurationFile(location);
    // DEFENSE: An intervening edit can change the meaning of an array position, or retarget a configuration symlink.
    if (current.target !== target || configurationRevision(current) !== revision) throw new ConfigurationConflictError();
    const updated = profileBoundary('config.edit', { configuration: editableSource(current), change });
    const text = JSON.stringify(updated, null, 2) + '\n';
    validateConfig(parseConfiguration(text));
    const view = profileBoundary('config.editable', { configuration: updated });
    const bytes = Buffer.from(text);
    // DEFENSE: The user can edit the configuration file outside this service while it prepares the new contents.
    if (configurationRevision(await configurationFile(location)) !== revision) throw new ConfigurationConflictError();
    const written = await publishBytes(target, bytes, { mode: current.bytes === undefined ? 'create-if-absent' : 'replace' });
    // DEFENSE: A concurrent init can create a fresh default file after the revision check.
    if (written === 'already-exists') throw new ConfigurationConflictError();
    return { ...view, revision: configurationRevision({ target: await realpath(target), bytes }) };
  });
  // DEFENSE: A refused edit must release the queue for later edits to the same file.
  const settled = next.catch(() => {});
  configurationWrites.set(target, settled);
  try { return await next; }
  finally { if (configurationWrites.get(target) === settled) configurationWrites.delete(target); }
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
