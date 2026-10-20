#!/usr/bin/env node
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { pathToFileURL } from 'node:url';

const quote = value => `'${value.replaceAll("'", "'\\''")}'`;

/** Build only documented official tunnel-client commands; no replacement relay is implemented. */
export function tunnelArguments(argv, { node = process.execPath, server = fileURLToPath(new URL('./server.mjs', import.meta.url)) } = {}) {
  const [action, ...rest] = argv;
  // DEFENSE: CLI users can name unsupported tunnel actions; only documented official commands are forwarded.
  if (!['init', 'doctor', 'run'].includes(action)) throw new Error('Usage: tunnel.mjs init|doctor|run --profile NAME [--tunnel-id tunnel_ID]');
  const options = {};
  for (let index = 0; index < rest.length; index += 2) {
    const key = rest[index], value = rest[index + 1];
    // DEFENSE: CLI options may be unknown, duplicated, or missing their value.
    if (!['--profile', '--tunnel-id'].includes(key) || !value || Object.hasOwn(options, key)) throw new Error('Invalid tunnel options');
    options[key] = value;
  }
  const profile = options['--profile'] ?? 'selvedge';
  // DEFENSE: A supplied profile name must remain a bounded tunnel-client identifier.
  if (!/^[A-Za-z0-9_-]{1,64}$/.test(profile)) throw new Error('Invalid tunnel profile name');
  if (action === 'init') {
    const tunnel = options['--tunnel-id'];
    // DEFENSE: init requires the registered tunnel ID; arbitrary or missing CLI values cannot select a tunnel.
    if (typeof tunnel !== 'string' || !/^tunnel_[A-Za-z0-9_-]+$/.test(tunnel)) throw new Error('init requires --tunnel-id from OpenAI tunnel settings');
    return ['init', '--sample', 'sample_mcp_stdio_local', '--profile', profile, '--tunnel-id', tunnel,
      '--mcp-command', `${quote(node)} ${quote(server)}`];
  }
  // DEFENSE: doctor/run must not silently ignore a tunnel-id option that applies only to initialization.
  if (options['--tunnel-id']) throw new Error('--tunnel-id is only accepted by init');
  return [action, '--profile', profile, ...(action === 'doctor' ? ['--explain'] : [])];
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const child = spawn('tunnel-client', tunnelArguments(process.argv.slice(2)), { stdio: 'inherit' });
    // DEFENSE: The separately installed official tunnel-client may be absent or fail to spawn; report failure without a replacement transport.
    child.once('error', error => {
      console.error(error.code === 'ENOENT' ? 'Install the official OpenAI tunnel-client and put it on PATH.' : 'Could not start tunnel-client.');
      process.exitCode = 1;
    });
    // DEFENSE: A signal-terminated tunnel-client has no numeric exit code and must not report success.
    child.once('exit', code => { process.exitCode = code ?? 1; });
    for (const signal of ['SIGINT', 'SIGTERM']) process.once(signal, () => child.kill(signal));
  // DEFENSE: Rejected CLI arguments must fail the launcher before starting the tunnel process.
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
