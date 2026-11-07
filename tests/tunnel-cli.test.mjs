import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { mkdtemp, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';

const launcher = fileURLToPath(new URL('../plugins/selvedge-chatgpt/bin/tunnel.mjs', import.meta.url));

async function launch(t, args, { clientExit = 0, clientAvailable = true } = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'selvedge-tunnel-cli-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const record = join(directory, 'arguments.json');
  const fixture = join(directory, 'client.mjs');
  if (clientAvailable) {
    await Promise.all([
      writeFile(join(directory, 'tunnel-client'), '#!/bin/sh\nexec "$SELVEDGE_TUNNEL_TEST_RUNTIME" "$SELVEDGE_TUNNEL_TEST_FIXTURE" "$@"\n', { mode: 0o755 }),
      writeFile(fixture, `
import { writeFileSync } from 'node:fs';
writeFileSync(process.env.SELVEDGE_TUNNEL_TEST_RECORD, JSON.stringify(process.argv.slice(2)));
process.exit(Number(process.env.SELVEDGE_TUNNEL_TEST_EXIT));
`),
    ]);
  }
  const child = spawn(process.execPath, [launcher, ...args], {
    env: {
      ...process.env,
      PATH: directory,
      SELVEDGE_TUNNEL_TEST_RUNTIME: process.execPath,
      SELVEDGE_TUNNEL_TEST_FIXTURE: fixture,
      SELVEDGE_TUNNEL_TEST_RECORD: record,
      SELVEDGE_TUNNEL_TEST_EXIT: String(clientExit),
    },
    stdio: ['ignore', 'pipe', 'pipe'],
    timeout: 5000,
  });
  let stdout = '';
  let stderr = '';
  child.stdout.setEncoding('utf8').on('data', text => { stdout += text; });
  child.stderr.setEncoding('utf8').on('data', text => { stderr += text; });
  const [status, signal] = await once(child, 'close');
  assert.equal(signal, null, `CLI must finish without a timeout or signal: ${stderr}`);
  const invocation = (await readdir(directory)).includes('arguments.json')
    ? parseArgs({
      args: JSON.parse(await readFile(record, 'utf8')),
      options: {
        profile: { type: 'string' },
        sample: { type: 'string' },
        'tunnel-id': { type: 'string' },
        'mcp-command': { type: 'string' },
      },
      allowPositionals: true,
      strict: false,
    })
    : null;
  return { status, stdout, stderr, invocation };
}

test('tunnel launcher forwards supported profile names to doctor and run', async t => {
  const results = await Promise.all([
    ['doctor', 'team.prod'],
    ['run', `a${'x'.repeat(127)}`],
  ].map(async ([action, profile]) => {
    return { action, profile, ...await launch(t, [action, '--profile', profile]) };
  }));
  for (const result of results) {
    assert.equal(result.status, 0, result.stderr);
    assert.ok(result.invocation, 'The external client must receive the request');
    assert.equal(result.invocation.positionals[0], result.action);
    assert.equal(result.invocation.values.profile, result.profile);
  }
});

test('tunnel init passes the tunnel value to the client and preserves its rejection', async t => {
  const tunnelId = 'opaque:external/id?revision=2';
  const result = await launch(t, ['init', '--profile', 'selvedge', '--tunnel-id', tunnelId], { clientExit: 23 });
  assert.ok(result.invocation, 'The external client must decide whether the tunnel ID is valid');
  assert.equal(result.invocation.positionals[0], 'init');
  assert.equal(result.invocation.values.profile, 'selvedge');
  assert.equal(result.invocation.values['tunnel-id'], tunnelId);
  assert.ok(result.invocation.values['mcp-command']?.trim(), 'Initialization must bind a stdio command');
  assert.notEqual(result.status, 0, result.stderr);
});

test('tunnel launcher rejects its action and option syntax before invoking the client', async t => {
  const invalidCommands = [
    ['unknown-action'],
    ['run', 'unexpected-positional'],
    ['doctor', '--unknown-option', 'value'],
    ['doctor', '--profile', 'first', '--profile', 'second'],
    ['doctor', '--profile'],
    ['init', '--profile', 'selvedge'],
    ['init', '--tunnel-id'],
    ['doctor', '--tunnel-id', 'tunnel_example'],
    ['run', '--tunnel-id', 'tunnel_example'],
  ];
  const results = await Promise.all(invalidCommands.map(async args => {
    return { args, ...await launch(t, args) };
  }));
  for (const result of results) {
    assert.notEqual(result.status, 0, JSON.stringify(result.args));
    assert.equal(result.invocation, null, `Invalid launcher syntax must not reach the client: ${JSON.stringify(result.args)}`);
  }
});

test('tunnel launcher reports an unavailable client as failure', async t => {
  const result = await launch(t, ['doctor', '--profile', 'selvedge'], { clientAvailable: false });
  assert.notEqual(result.status, 0);
  assert.equal(result.invocation, null);
});
