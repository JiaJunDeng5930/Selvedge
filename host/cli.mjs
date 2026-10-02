#!/usr/bin/env node
import { readFile, mkdir, open } from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { loadConfig, homeDirectory, defaultConfig } from './config.mjs';
import { login } from './auth.mjs';
import { loginAccount, discoverAccount, withAccountModels } from './chatgpt-models.mjs';
import { startServer } from './server.mjs';
import { requestJson, events } from './network.mjs';
import { parseJson, stringifyJson } from './codec.mjs';

function parseOptions(args) {
  const values = [];
  const global = {};
  for (let i = 0; i < args.length; i++) {
    if (['--home', '--config'].includes(args[i])) {
      const name = args[i].slice(2);
      if (!args[i + 1]) throw new Error(`${args[i]} requires a value`);
      global[name === 'config' ? 'filename' : name] = args[++i];
    } else values.push(args[i]);
  }
  return { global, values };
}

async function connection(home) {
  const value = JSON.parse(await readFile(path.join(homeDirectory(home), 'server.json'), 'utf8'));
  if (value.format !== 'selvedge-local-server-1' || typeof value.token !== 'string') throw new Error('Invalid local server record');
  const url = new URL(value.address);
  if (url.protocol !== 'http:' || !['127.0.0.1', '[::1]'].includes(url.hostname)) throw new Error('Local server record must identify a loopback address');
  return value;
}

export function commandArguments(spec, args) {
  const result = { op: spec.name };
  for (let i = 0; i < args.length; i += 2) {
    if (!args[i]?.startsWith('--') || args[i + 1] === undefined) throw new Error('Arguments must be --name value pairs');
    const name = args[i].slice(2).replaceAll('-', '_');
    const property = spec.schema.properties[name];
    if (!property || name === 'op' || Object.hasOwn(result, name)) throw new Error(`Unknown or duplicate argument: ${args[i]}`);
    result[name] = property.type === 'string' ? args[i + 1] : parseJson(args[i + 1]);
  }
  return result;
}

export async function main(args = process.argv.slice(2)) {
  const { global, values } = parseOptions(args);
  const [operation = 'help', ...rest] = values;
  if (operation === 'server') {
    const settings = await loadConfig(global);
    const server = await startServer(settings);
    console.log(`Selvedge: ${server.url}`);
    console.log(`Home: ${settings.home}`);
    await new Promise((resolve, reject) => {
      let stopping = false;
      const stop = code => {
        if (stopping) return;
        stopping = true;
        process.off('SIGINT', interrupt);
        process.off('SIGTERM', terminate);
        server.close().then(() => { process.exitCode = code; resolve(); }, reject);
      };
      const interrupt = () => stop(130);
      const terminate = () => stop(0);
      process.once('SIGINT', interrupt);
      process.once('SIGTERM', terminate);
      server.service.on('notice', event => {
        if (event.type === 'diagnostic') console.error(event.message);
        if (event.type === 'fatal') { console.error(event.message); stop(1); }
      });
    });
    return;
  }
  if (operation === 'init') {
    const home = homeDirectory(global.home);
    await mkdir(home, { recursive: true, mode: 0o700 });
    const filename = global.filename ? path.resolve(global.filename) : path.join(home, 'config.json');
    const file = await open(filename, 'wx', 0o600);
    try { await file.writeFile(JSON.stringify(defaultConfig, null, 2) + '\n'); await file.sync(); }
    finally { await file.close(); }
    console.log(filename);
    return;
  }
  if (operation === 'login') {
    const settings = await loadConfig(global);
    const profile = loginAccount(settings.config, rest[0]);
    const controller = new AbortController();
    const interrupt = () => controller.abort(new Error('Login cancelled'));
    process.once('SIGINT', interrupt);
    try {
      const result = await login(profile, settings.home, { signal: controller.signal,
        onAuthorize: ({ url }) => console.log(`Continue with ChatGPT: ${url}`) });
      console.log(`Signed in${result.name || result.email ? ` as ${result.name ?? result.email}` : ''}. Credential saved to ${result.filename}`);
      console.log('Manage usage: https://chatgpt.com/settings/usage');
      const catalog = await discoverAccount(profile, settings.home, { signal: controller.signal, force: true });
      console.log(`Available account models: ${catalog.models.filter(model => model.visibility === 'list').map(model => model.slug).join(', ')}`);
      try {
        const local = await connection(settings.home);
        const refreshed = await requestJson(`${local.address}/api/accounts/refresh`, {
          headers: { authorization: `Bearer ${local.token}` }, body: {}, signal: controller.signal,
        });
        if (!refreshed.ok || !refreshed.value?.ok) throw new Error('The running server could not refresh its model catalog');
        console.log('The running server’s model selector has been refreshed.');
      } catch (error) {
        if (error.code !== 'ENOENT') console.error(`Account saved; restart the server to refresh its models (${error.message}).`);
      }
    } finally { process.off('SIGINT', interrupt); }
    return;
  }
  if (operation === 'models') {
    const settings = await loadConfig(global);
    if (rest.some(value => value !== '--refresh')) throw new Error('Usage: models [--refresh]');
    const result = await withAccountModels(settings.config, settings.home, { force: rest.includes('--refresh'), onDiagnostic: message => console.error(message) });
    for (const [key, profile] of Object.entries(result.config.profiles)) console.log(`${key}\t${profile.provider}\t${profile.model}`);
    return;
  }
  if (operation === 'help' && rest.length === 0) {
    console.log('Usage: node host/cli.mjs [--home PATH] [--config FILE] server|init|login [PROFILE]|models [--refresh]|describe|watch|COMMAND [--field value]\nRun describe against a running server for its executable command schemas. Array arguments use JSON.\nRun login to use your ChatGPT account models without writing model profiles. The demo profile is offline.');
    return;
  }
  const local = await connection(global.home);
  const headers = { authorization: `Bearer ${local.token}` };
  if (operation === 'watch') {
    const response = await fetch(`${local.address}/api/events`, { headers });
    if (!response.ok) throw new Error(`Event stream failed: HTTP ${response.status}`);
    for await (const event of events(response.body, 4 * 1024 * 1024)) console.log(event);
    return;
  }
  const description = await requestJson(`${local.address}/api/describe`, { method: 'GET', headers });
  if (!description.ok || !description.value?.ok) throw new Error('Cannot read the server command vocabulary');
  if (operation === 'describe') { console.log(stringifyJson(description.value.result)); return; }
  const spec = description.value.result.commands.find(command => command.name === operation);
  if (!spec) throw new Error(`Unknown command ${operation}; run describe to list commands`);
  const response = await requestJson(`${local.address}/api/commands`, { headers, body: commandArguments(spec, rest), maximum: description.value.result.limits.frame_bytes });
  console.log(stringifyJson(response.value));
  if (!response.ok || !response.value?.ok) process.exitCode = 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch(error => { console.error(error.message); process.exitCode = 1; });
}
