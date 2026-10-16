import { readFile, access } from 'node:fs/promises';
import { homedir } from 'node:os';
import path from 'node:path';
import { accountConfig, accountConnection } from './chatgpt-account.mjs';
import { adaptivePolicy, evaluatorConnections, configurationObserver } from './reasoning-config.mjs';
import { connectionConfig } from './chatgpt-plugin.mjs';

import { boundary } from './public/model-boundary.mjs';

export const defaultConfig = boundary('config.defaults', {});
export const format = defaultConfig.format;

function urlObservation(value) {
  try {
    const url = new URL(value);
    return Object.fromEntries(['href', 'protocol', 'hostname', 'username', 'password', 'hash', 'pathname', 'search', 'origin'].map(key => [key, url[key]]));
  } catch { return null; }
}

function profileBoundary(operation, source) {
  try { return boundary(operation, source); }
  catch (error) { throw new TypeError(error.message); }
}

export function validateConfig(value) {
  const observer = configurationObserver();
  const root = observer.observe(value, { shallow: true });
  if (root.kind === 'object') root.fields = Object.entries(value).map(([key, item]) => ({
    key: observer.observe(key), value: observer.observe(item, { shallow: !['format', 'instructions'].includes(key) }),
  }));
  const config = observer.materialize(observer.execute('config.configuration_head', { value: root }));
  config.chatgpt_plugin = connectionConfig(value.chatgpt_plugin);
  config.chatgpt = value.chatgpt === false ? false : accountConfig(value.chatgpt);
  config.reasoning_evaluators = evaluatorConnections(value.reasoning_evaluators);
  observer.execute('config.configuration_transport', {
    transport: Object.fromEntries(['host', 'port', 'max_fork', 'max_descendants', 'profiles', 'instructions'].map(key =>
      [key, observer.observe(config[key], { shallow: key === 'profiles' })])),
    instructions_bytes: typeof config.instructions === 'string' ? Buffer.byteLength(config.instructions, 'utf8') : null,
    instructions_well_formed: typeof config.instructions === 'string' && config.instructions.isWellFormed() && !config.instructions.includes('\0'),
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
  return { home, filename, config: validateConfig(config) };
}

export function profileCatalog(config) {
  return boundary('backend.profile_catalog', { config });
}
