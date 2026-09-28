import { readFile, access } from 'node:fs/promises';
import { homedir } from 'node:os';
import path from 'node:path';
import { validPluginName } from './plugins.mjs';
import { defaultChatGPTAccount, modelsURL } from './chatgpt-contract.mjs';
import { adaptivePolicy, evaluatorConnections } from './reasoning-config.mjs';

export const format = 'selvedge-bend-config-1';
export const defaultConfig = {
  format, host: '127.0.0.1', port: 7421, max_fork: 4, max_descendants: 64,
  profiles: { demo: { provider: 'echo', model: 'echo' } }, mcp: {}, plugins: {},
};

function object(value, label, keys) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError(`${label} must be an object`);
  for (const key of Object.keys(value)) if (!keys.includes(key)) throw new TypeError(`Unknown ${label} field: ${key}`);
}
function text(value, label) {
  if (typeof value !== 'string' || !value.trim()) throw new TypeError(`${label} must be a nonempty string`);
}
function number(value, label, lower, upper) {
  if (!Number.isSafeInteger(value) || value < lower || value > upper) throw new TypeError(`${label} must be in ${lower}..${upper}`);
}
function endpoint(value, label) {
  text(value, label);
  const url = new URL(value);
  if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password || url.hash) throw new TypeError(`Invalid ${label}`);
  if (url.protocol !== 'https:' && !['localhost', '127.0.0.1', '[::1]'].includes(url.hostname)) throw new TypeError(`${label} requires HTTPS except on loopback`);
}

export function accountConfig(value = {}) {
  object(value, 'ChatGPT account', ['provider', 'endpoint', 'auth_file', 'issuer', 'client_id', 'timeout_ms']);
  const account = { ...defaultChatGPTAccount, ...value };
  if (account.provider !== 'chatgpt') throw new TypeError('The account provider must be chatgpt');
  endpoint(account.endpoint, 'ChatGPT endpoint');
  modelsURL(account.endpoint);
  endpoint(account.issuer, 'ChatGPT issuer');
  text(account.auth_file, 'ChatGPT auth_file');
  text(account.client_id, 'ChatGPT client_id');
  number(account.timeout_ms, 'ChatGPT timeout', 100, 1_800_000);
  account.issuer = account.issuer.replace(/\/+$/, '');
  return Object.freeze(account);
}

export function validateConfig(value) {
  object(value, 'configuration', ['format', 'host', 'port', 'max_fork', 'max_descendants', 'profiles', 'chatgpt', 'mcp', 'plugins', 'reasoning_evaluators']);
  if (value.format !== format) throw new Error('The configuration is not in the current Bend format');
  const config = { ...defaultConfig, ...value };
  config.chatgpt = value.chatgpt === false ? false : accountConfig(value.chatgpt);
  config.reasoning_evaluators = evaluatorConnections(value.reasoning_evaluators);
  if (!['127.0.0.1', '::1'].includes(config.host)) throw new TypeError('The local server requires a loopback address');
  number(config.port, 'port', 0, 65535);
  number(config.max_fork, 'max_fork', 1, 0xffffffff);
  number(config.max_descendants, 'max_descendants', 1, 0xffffffff);
  if (!config.profiles || typeof config.profiles !== 'object' || Array.isArray(config.profiles)) throw new TypeError('profiles must be an object');
  config.profiles = Object.fromEntries(Object.entries(config.profiles).map(([key, source]) => {
    text(key, 'profile key');
    object(source, `profile ${key}`, ['provider', 'model', 'endpoint', 'api_key_env', 'auth_file', 'issuer', 'client_id', 'timeout_ms', 'adaptive_reasoning']);
    if (!['echo', 'responses', 'chatgpt', 'chatgpt-web'].includes(source.provider)) throw new TypeError(`Unknown provider for ${key}`);
    text(source.model, `model for ${key}`);
    const profile = { timeout_ms: 300_000, ...source };
    const adaptive = adaptivePolicy(source.adaptive_reasoning);
    if (adaptive && profile.provider === 'echo') throw new TypeError('The offline echo provider cannot select model reasoning effort');
    if (profile.provider === 'chatgpt-web') {
      if (!/^chatgpt-web\/(light|medium|high|xhigh|pro)$/.test(profile.model)) throw new TypeError(`Invalid ChatGPT Web model for ${key}`);
      if (adaptive) throw new TypeError('ChatGPT Web fixes effort at the root; adaptive reasoning is not supported');
    }
    if (adaptive) profile.adaptive_reasoning = adaptive;
    else delete profile.adaptive_reasoning;
    number(profile.timeout_ms, `timeout for ${key}`, 100, 1_800_000);
    if (profile.provider !== 'echo') {
      profile.endpoint ??= profile.provider === 'chatgpt-web' ? 'http://127.0.0.1:8787/v1/responses' :
        profile.provider === 'chatgpt' ? 'https://chatgpt.com/backend-api/codex/responses' : 'https://api.openai.com/v1/responses';
      endpoint(profile.endpoint, `endpoint for ${key}`);
      if (profile.provider === 'chatgpt-web') {
        const url = new URL(profile.endpoint);
        if (!url.pathname.endsWith('/v1/responses') || url.search) throw new TypeError('ChatGPT Web endpoint must end in /v1/responses without a query');
      }
    }
    if (profile.provider === 'responses' || profile.provider === 'chatgpt-web') {
      profile.api_key_env ??= profile.provider === 'chatgpt-web' ? 'CHATGPT_WEB_TOKEN' : 'OPENAI_API_KEY';
      if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(profile.api_key_env)) throw new TypeError(`Invalid API key environment variable for ${key}`);
    }
    if (profile.provider === 'chatgpt') {
      profile.auth_file ??= 'auth/chatgpt.json';
      profile.issuer ??= 'https://auth.openai.com';
      profile.client_id ??= 'app_EMoamEEZ73f0CkXaXp7hrann';
      text(profile.auth_file, `auth_file for ${key}`);
      text(profile.client_id, `client_id for ${key}`);
      endpoint(profile.issuer, `issuer for ${key}`);
      profile.issuer = profile.issuer.replace(/\/+$/, '');
    }
    return [key, Object.freeze(profile)];
  }));
  if (!config.mcp || typeof config.mcp !== 'object' || Array.isArray(config.mcp)) throw new TypeError('mcp must be an object');
  for (const [name, server] of Object.entries(config.mcp)) {
    text(name, 'MCP server name');
    object(server, `MCP ${name}`, ['command', 'args', 'cwd', 'env', 'timeout_ms']);
    text(server.command, `MCP ${name} command`);
    if (server.args !== undefined && (!Array.isArray(server.args) || server.args.some(x => typeof x !== 'string'))) throw new TypeError(`Invalid MCP ${name} arguments`);
    if (server.cwd !== undefined) text(server.cwd, `MCP ${name} cwd`);
    if (server.timeout_ms !== undefined) number(server.timeout_ms, `MCP ${name} timeout`, 100, 1_800_000);
    if (server.env !== undefined && (!server.env || typeof server.env !== 'object' || Array.isArray(server.env) || Object.values(server.env).some(x => typeof x !== 'string'))) throw new TypeError(`Invalid MCP ${name} environment`);
  }
  if (!config.plugins || typeof config.plugins !== 'object' || Array.isArray(config.plugins)) throw new TypeError('plugins must be an object');
  for (const [name, plugin] of Object.entries(config.plugins)) {
    if (!validPluginName(name)) throw new TypeError(`Invalid plugin name: ${name}`);
    object(plugin, `plugin ${name}`, ['command', 'args', 'cwd', 'env', 'timeout_ms', 'event_timeout_ms', 'event_queue']);
    text(plugin.command, `plugin ${name} command`);
    if (plugin.args !== undefined && (!Array.isArray(plugin.args) || plugin.args.some(value => typeof value !== 'string'))) throw new TypeError(`Invalid plugin ${name} arguments`);
    if (plugin.cwd !== undefined) text(plugin.cwd, `plugin ${name} cwd`);
    if (plugin.timeout_ms !== undefined) number(plugin.timeout_ms, `plugin ${name} timeout`, 100, 1_800_000);
    if (plugin.event_timeout_ms !== undefined) number(plugin.event_timeout_ms, `plugin ${name} event timeout`, 100, 60_000);
    if (plugin.event_queue !== undefined) number(plugin.event_queue, `plugin ${name} event queue`, 1, 4096);
    if (plugin.env !== undefined && (!plugin.env || typeof plugin.env !== 'object' || Array.isArray(plugin.env) || Object.values(plugin.env).some(value => typeof value !== 'string'))) throw new TypeError(`Invalid plugin ${name} environment`);
  }
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
  return Object.entries(config.profiles).map(([key, profile]) => ({ key, provider: profile.provider, name: profile.model,
    ...(profile.adaptive_reasoning ? { adaptive_reasoning: profile.adaptive_reasoning } : {}) }));
}
