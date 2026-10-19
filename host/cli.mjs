#!/usr/bin/env bun
import { readFile, mkdir, open } from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { loadConfig, homeDirectory, defaultConfig, validateConfig } from './config.mjs';
import { login } from './chatgpt-account.mjs';
import { loginAccount, discoverAccount, withAccountModels } from './chatgpt-models.mjs';
import { startServer } from './server.mjs';
import { requestJson, events } from './network.mjs';
import { parseJson, stringifyJson } from './codec.mjs';
import { writeAtomic } from './files.mjs';
import { provisionRemote } from './remote-control.mjs';

function parseOptions(args) {
  const values = [];
  const global = {};
  for (let i = 0; i < args.length; i++) {
    if (['--home', '--config'].includes(args[i])) {
      const name = args[i].slice(2);
      // DEFENSE: Users can omit the value after --home or --config.
      if (!args[i + 1]) throw new Error(`${args[i]} requires a value`);
      global[name === 'config' ? 'filename' : name] = args[++i];
    } else values.push(args[i]);
  }
  return { global, values };
}

async function connection(home) {
  const value = JSON.parse(await readFile(path.join(homeDirectory(home), 'server.json'), 'utf8'));
  // DEFENSE: A saved server record may be from another format or edited outside the service.
  if (value.format !== 'selvedge-local-server-1' || typeof value.token !== 'string') throw new Error('Invalid local server record');
  const url = new URL(value.address);
  // DEFENSE: Never send the local Bearer secret to a non-loopback endpoint from an edited server record.
  if (url.protocol !== 'http:' || !['127.0.0.1', '[::1]'].includes(url.hostname)) throw new Error('Local server record must identify a loopback address');
  return value;
}

export function commandArguments(spec, args) {
  const result = { op: spec.name };
  for (let i = 0; i < args.length; i += 2) {
    // DEFENSE: CLI input can contain positional arguments or an option without its paired value.
    if (!args[i].startsWith('--') || args[i + 1] === undefined) throw new Error('Arguments must be --name value pairs');
    const name = args[i].slice(2).replaceAll('-', '_');
    const property = spec.schema.properties[name];
    // DEFENSE: Users can supply unknown/repeated options or attempt to override the selected command name.
    if (!property || name === 'op' || Object.hasOwn(result, name)) throw new Error(`Unknown or duplicate argument: ${args[i]}`);
    result[name] = property.type === 'string' ? args[i + 1] : parseJson(args[i + 1]);
  }
  return result;
}

function remoteArguments(args, required) {
  const result = {};
  for (let index = 0; index < args.length; index += 2) {
    const option = args[index];
    const name = option.startsWith('--') ? option.slice(2).replaceAll('-', '_') : '';
    // DEFENSE: Remote CLI input must reject unknown, repeated or valueless options before sending a request.
    if (!required.includes(name) || Object.hasOwn(result, name) || args[index + 1] === undefined) {
      throw new Error('Remote arguments must be the required --name value pairs');
    }
    result[name] = name === 'permissions' ? parseJson(args[index + 1]) : args[index + 1];
  }
  // DEFENSE: A remote operation may be invoked without one of its required options.
  if (required.some(name => !Object.hasOwn(result, name))) {
    throw new Error(`Remote command requires ${required.map(name => `--${name.replaceAll('_', '-')}`).join(', ')}`);
  }
  return result;
}

async function remoteCommand(global, args) {
  const [operation, ...rest] = args;
  if (operation === 'init') {
    const { relay_url } = remoteArguments(rest, ['relay_url']);
    const enrollmentToken = process.env.SELVEDGE_RELAY_ENROLLMENT_TOKEN;
    // DEFENSE: Provisioning without the explicitly supplied enrollment secret cannot authenticate to the relay.
    if (!enrollmentToken) throw new Error('Set SELVEDGE_RELAY_ENROLLMENT_TOKEN before remote init; credentials are not accepted as command arguments');
    const settings = await loadConfig(global);
    let raw;
    try { raw = JSON.parse(await readFile(settings.filename, 'utf8')); }
    // DEFENSE: First-time remote init can use a new home's absent default config.json; other read/parse failures must remain visible.
    catch (error) { if (error.code !== 'ENOENT') throw error; raw = structuredClone(defaultConfig); }
    const proposed = { ...raw, remote: { relay_url } };
    const remote = validateConfig(proposed).remote;
    const result = await provisionRemote({ home: settings.home, relayUrl: remote.relay_url, enrollmentToken });
    await writeAtomic(settings.filename, { ...raw, remote });
    console.log(stringifyJson({ ok: true, result, restart_required: true }));
    console.error('Remote relay configured. Restart the local server, then run remote enable.');
    return;
  }
  let body;
  switch (operation) {
    case 'status': case 'pending':
      remoteArguments(rest, []);
      break;
    case 'enable': case 'disable': case 'pair':
      body = remoteArguments(rest, []);
      break;
    case 'approve':
      body = remoteArguments(rest, ['request_id', 'permissions']);
      break;
    case 'revoke':
      body = remoteArguments(rest, ['controller_id']);
      break;
    // DEFENSE: A user can omit or misspell the remote subcommand.
    default: throw new Error('Usage: remote init --relay-url URL | status | enable | disable | pair | pending | approve --request-id ID --permissions JSON | revoke --controller-id ID');
  }
  const local = await connection(global.home);
  const response = await requestJson(`${local.address}/api/remote/${operation}`, {
    method: body === undefined ? 'GET' : 'POST', body,
    headers: { authorization: `Bearer ${local.token}` },
  });
  console.log(stringifyJson(response.value));
  // DEFENSE: The remote endpoint can return a transport or native rejection; preserve failure in the CLI exit status.
  if (!response.ok || !response.value?.ok) process.exitCode = 1;
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
        // DEFENSE: SIGINT, SIGTERM and fatal service notices can arrive during the same shutdown.
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
      // DEFENSE: Login can finish while no local server is running, or while its refresh request fails; keep the saved account and report refresh failure.
      try {
        const local = await connection(settings.home);
        const refreshed = await requestJson(`${local.address}/api/accounts/refresh`, {
          headers: { authorization: `Bearer ${local.token}` }, body: {}, signal: controller.signal,
        });
        // DEFENSE: The running server can reject catalog refresh after the account was saved.
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
    // DEFENSE: Reject unsupported model-list options typed by the user.
    if (rest.some(value => value !== '--refresh')) throw new Error('Usage: models [--refresh]');
    const result = await withAccountModels(settings.config, settings.home, { force: rest.includes('--refresh'), onDiagnostic: message => console.error(message) });
    for (const [key, profile] of Object.entries(result.config.profiles)) console.log(`${key}\t${profile.provider}\t${profile.model}`);
    return;
  }
  if (operation === 'remote') {
    await remoteCommand(global, rest);
    return;
  }
  if (operation === 'help' && rest.length === 0) {
    console.log('Usage: bun host/cli.mjs [--home PATH] [--config FILE] server|init|login [PROFILE]|models [--refresh]|remote SUBCOMMAND|describe|watch|COMMAND [--field value]\nRun describe against a running server for its executable command schemas. Array arguments use JSON.\nRun remote for relay configuration, pairing and device management commands.\nRun login to use your ChatGPT account models without writing model profiles. The demo profile is offline.');
    return;
  }
  const local = await connection(global.home);
  const headers = { authorization: `Bearer ${local.token}` };
  if (operation === 'watch') {
    const response = await fetch(`${local.address}/api/events`, { headers });
    // DEFENSE: A server restart or invalid credential can reject the event stream before SSE begins.
    if (!response.ok) throw new Error(`Event stream failed: HTTP ${response.status}`);
    for await (const event of events(response.body, 4 * 1024 * 1024)) console.log(event);
    return;
  }
  const description = await requestJson(`${local.address}/api/describe`, { method: 'GET', headers });
  // DEFENSE: A rejected description request cannot provide command schemas for the requested invocation.
  if (!description.ok || !description.value?.ok) throw new Error('Cannot read the server command vocabulary');
  if (operation === 'describe') { console.log(stringifyJson(description.value.result)); return; }
  const spec = description.value.result.commands.find(command => command.name === operation);
  // DEFENSE: Users can invoke a command name absent from the server's public vocabulary.
  if (!spec) throw new Error(`Unknown command ${operation}; run describe to list commands`);
  const response = await requestJson(`${local.address}/api/commands`, { headers, body: commandArguments(spec, rest), maximum: description.value.result.limits.frame_bytes });
  console.log(stringifyJson(response.value));
  // DEFENSE: Native command rejection and HTTP failure must yield a failing CLI status.
  if (!response.ok || !response.value?.ok) process.exitCode = 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  // DEFENSE: Invalid CLI input, filesystem failures and rejected network requests must produce a diagnostic and failing exit status.
  main().catch(error => { console.error(error.message); process.exitCode = 1; });
}
