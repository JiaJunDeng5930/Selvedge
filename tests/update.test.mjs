import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { access, readFile, writeFile } from 'node:fs/promises';
import net from 'node:net';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { setTimeout as delay } from 'node:timers/promises';
import { gunzipSync } from 'node:zlib';
import { defaultConfig } from '../host/config.mjs';
import { asyncToolResult, home, responsesServer } from './support.mjs';

const project = fileURLToPath(new URL('../', import.meta.url));
const toolFixture = fileURLToPath(new URL('./fixtures/update-tool.mjs', import.meta.url));
const legacyJournal = new URL('./fixtures/journal-format28-unversioned.sqlite.gz', import.meta.url);
const callId = 'update-handoff-tool';
const toolName = 'mcp__update__record_update';
const waiting = [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'Waiting for the local operation.' }] }];
const done = [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'The local operation is complete.' }] }];

async function unusedPort() {
  const server = net.createServer();
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  const { port } = server.address();
  await new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
  return port;
}

function reportedPids(output) {
  return [...output.matchAll(/^PID:\s*(\d+)\s*$/gm)].map(match => Number(match[1]));
}

function startUpdate(directory, state) {
  const args = ['run', 'update', '--home', directory];
  const child = spawn(process.execPath, args, { cwd: project, stdio: ['ignore', 'pipe', 'pipe'] });
  state.updateChildren.add(child);
  child.once('close', () => state.updateChildren.delete(child));
  let stdout = '';
  let stderr = '';
  child.stdout.setEncoding('utf8');
  child.stderr.setEncoding('utf8');
  child.stdout.on('data', chunk => { stdout = `${stdout}${chunk}`.slice(-30_000); });
  child.stderr.on('data', chunk => { stderr = `${stderr}${chunk}`.slice(-30_000); });
  const closed = new Promise((resolve, reject) => {
    child.once('error', reject);
    child.once('close', (code, signal) => {
      const output = `${stdout}\n${stderr}`.replaceAll(/\u001b\[[0-9;]*m/g, '');
      resolve({ code, signal, output });
    });
  });
  return { child, closed, output: () => `${stdout}\n${stderr}` };
}

async function finishUpdate(update, timeoutMs = 60_000) {
  let timer;
  try {
    const timeout = new Promise((_, reject) => {
      timer = setTimeout(() => {
        update.child.kill('SIGTERM');
        reject(new Error(`Update command exceeded ${timeoutMs} ms:\n${update.output()}`));
      }, timeoutMs);
    });
    return await Promise.race([update.closed, timeout]);
  } finally {
    clearTimeout(timer);
  }
}

function managedService(output) {
  const clean = output.replaceAll(/\u001b\[[0-9;]*m/g, '');
  const url = clean.match(/^Selvedge:\s*(https?:\/\/\S+)\s*$/m)?.[1];
  const pid = reportedPids(clean).at(-1);
  assert.ok(url, `Update must print its service URL. Output:\n${clean}`);
  assert.ok(pid, `Update must print its server PID. Output:\n${clean}`);
  return { url: new URL(url).origin, pid };
}

async function authenticatedClient(url) {
  const page = await fetch(url);
  assert.equal(page.status, 200);
  const cookie = page.headers.get('set-cookie')?.split(';', 1)[0];
  assert.ok(cookie, 'The public page must establish its browser session');
  const headers = { cookie, origin: new URL(url).origin, 'content-type': 'application/json' };
  return {
    headers,
    async command(command) {
      const response = await fetch(`${url}/api/commands`, {
        method: 'POST', headers, body: JSON.stringify(command),
      });
      const body = await response.text();
      assert.equal(response.status, 200, body);
      const reply = JSON.parse(body);
      assert.equal(reply.ok, true, JSON.stringify(reply));
      return reply.result;
    },
  };
}

async function waitForService(url, timeoutMs = 20_000) {
  const deadline = Date.now() + timeoutMs;
  let last;
  do {
    try {
      const response = await fetch(url);
      if (response.status === 200) return;
      last = `HTTP ${response.status}`;
    } catch (error) {
      // DEFENSE: The managed process has a real stop/start window during a version handoff.
      last = error.message;
    }
    await delay(20);
  } while (Date.now() < deadline);
  assert.fail(`Managed service did not become ready at ${url}: ${last}`);
}

async function waitForFile(filename, timeoutMs = 15_000) {
  const deadline = Date.now() + timeoutMs;
  do {
    try {
      await access(filename);
      return;
    } catch (error) {
      // DEFENSE: The tool writes this marker only after the model has called it.
      if (error.code !== 'ENOENT') throw error;
    }
    await delay(10);
  } while (Date.now() < deadline);
  assert.fail(`The delayed MCP tool did not start: ${filename}`);
}

async function openEvents(url, headers) {
  const controller = new AbortController();
  const response = await fetch(`${url}/api/events?after=0`, { headers, signal: controller.signal });
  assert.equal(response.status, 200);
  return { response, controller };
}

async function waitForUpdateDrain(stream, timeoutMs = 15_000) {
  const reader = stream.response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';
  const deadline = Date.now() + timeoutMs;
  let last;
  try {
    while (Date.now() < deadline) {
      let timer;
      const remaining = deadline - Date.now();
      const timedRead = new Promise((_, reject) => {
        timer = setTimeout(() => reject(new Error('Timed out waiting for the draining event')), remaining);
      });
      let chunk;
      try {
        chunk = await Promise.race([reader.read(), timedRead]);
      } finally {
        clearTimeout(timer);
      }
      if (chunk.done) break;
      buffer += decoder.decode(chunk.value, { stream: true });
      let boundary;
      while ((boundary = buffer.search(/\r?\n\r?\n/)) >= 0) {
        const frame = buffer.slice(0, boundary);
        buffer = buffer.slice(boundary).replace(/^\r?\n\r?\n/, '');
        const data = frame.split(/\r?\n/).find(line => line.startsWith('data:'));
        if (!data) continue;
        const event = JSON.parse(data.slice(5).trim());
        last = event;
        if (event.type === 'selvedge-update' && event.status === 'draining') return event;
      }
    }
  } finally {
    stream.controller.abort();
    // DEFENSE: Closing this long-lived observation after status delivery can reject its pending read.
    await reader.cancel().catch(error => { if (error.name !== 'AbortError') throw error; });
  }
  assert.fail(`The service did not announce update draining: ${JSON.stringify(last)}`);
}

async function waitForTask(client, taskId, accepts, timeoutMs = 20_000) {
  const deadline = Date.now() + timeoutMs;
  let page;
  do {
    page = await client.command({ op: 'read', task_id: taskId });
    if (accepts(page)) return page;
    await delay(20);
  } while (Date.now() < deadline);
  assert.fail(`Task did not reach the requested state: ${JSON.stringify(page?.task)}`);
}

function recordCurrentPid(state, output) {
  const pid = reportedPids(output).at(-1);
  if (!pid) return;
  if (state.currentPid && state.currentPid !== pid) state.retiredPids.add(state.currentPid);
  state.currentPid = pid;
}

async function processIsAlive(pid) {
  try { process.kill(pid, 0); return true; }
  catch (error) { if (error.code === 'ESRCH') return false; throw error; }
}

async function stopManagedService(directory, state) {
  const updates = [...state.updateChildren];
  for (const child of updates) if (child.exitCode === null) child.kill('SIGTERM');
  await Promise.all(updates.map(child => child.exitCode !== null ? Promise.resolve() : new Promise(resolve => {
    const timer = setTimeout(resolve, 5_000);
    child.once('close', () => { clearTimeout(timer); resolve(); });
  })));

  let pid = state.currentPid;
  try {
    const discovery = JSON.parse(await readFile(path.join(directory, 'server.json'), 'utf8'));
    if (Number.isSafeInteger(discovery.pid) && !state.retiredPids.has(discovery.pid)) pid = discovery.pid;
  } catch (error) {
    // DEFENSE: A failed startup can leave no local discovery record for cleanup to read.
    if (error.code !== 'ENOENT') throw error;
  }

  if (!pid || pid <= 1 || pid === process.pid || state.retiredPids.has(pid) || !await processIsAlive(pid)) return;
  process.kill(pid, 'SIGTERM');
  const deadline = Date.now() + 5_000;
  while (Date.now() < deadline && await processIsAlive(pid)) {
    await delay(20);
  }
  if (await processIsAlive(pid)) process.kill(pid, 'SIGKILL');
}

test('terminal update waits for a durable tool result and restarts the same task at the same endpoint', async t => {
  const directory = await home(t);
  const port = await unusedPort();
  const effects = path.join(directory, 'tool-effects.jsonl');
  const ready = path.join(directory, 'tool-ready');
  const release = path.join(directory, 'tool-release');
  const configPath = path.join(directory, 'config.json');
  const serviceState = { currentPid: undefined, retiredPids: new Set(), updateChildren: new Set() };
  t.after(() => stopManagedService(directory, serviceState));

  const key = `SELVEDGE_UPDATE_${Math.random().toString(16).slice(2).toUpperCase()}`;
  const previousKey = process.env[key];
  process.env[key] = 'loopback-update-fixture';
  t.after(() => {
    if (previousKey === undefined) delete process.env[key];
    else process.env[key] = previousKey;
  });

  let issued = false;
  const upstream = await responsesServer(t, body => {
    const results = body.input.map(item => {
      if (item.type === 'function_call_output' && item.call_id === callId) {
        return { call_id: item.call_id, output: JSON.parse(item.output) };
      }
      const result = asyncToolResult(item);
      return result?.call_id === callId ? result : undefined;
    }).filter(Boolean);
    if (results.length) {
      const result = results.at(-1);
      if (result.output?.value?.status === 'running' || result.value?.status === 'running') return waiting;
      assert.match(JSON.stringify(result), /UPDATE_TOOL_RECEIPT/);
      return done;
    }
    if (!issued) {
      issued = true;
      return [{ type: 'function_call', call_id: callId, name: toolName,
        arguments: JSON.stringify({ ticket: 'same-task-update' }) }];
    }
    return waiting;
  });

  const config = {
    ...defaultConfig,
    chatgpt: false,
    port,
    profiles: {
      ...defaultConfig.profiles,
      update_fixture: {
        provider: 'responses', model: 'update-handoff-model', endpoint: upstream.endpoint,
        api_key_env: key,
      },
    },
    mcp: {
      ...defaultConfig.mcp,
      update: { command: process.execPath, args: [toolFixture, effects, ready, release] },
    },
  };
  await writeFile(configPath, JSON.stringify(config));
  // Captured through the public CLI from revision 3e764dfe, before managed updates added the journal schema marker.
  await writeFile(path.join(directory, 'journal.sqlite'), gunzipSync(await readFile(legacyJournal)));

  const initial = startUpdate(directory, serviceState);
  const initialResult = await finishUpdate(initial);
  assert.equal(initialResult.code, 0, initialResult.output);
  recordCurrentPid(serviceState, initialResult.output);
  const firstService = managedService(initialResult.output);
  assert.equal(Number(new URL(firstService.url).port), port);
  await waitForService(firstService.url);

  const client = await authenticatedClient(firstService.url);
  const migrated = await client.command({ op: 'read', task_id: 0 });
  assert.equal(migrated.task.phase, 'idle');
  assert.ok(JSON.stringify(migrated.messages).includes('History recorded before managed updates.'));
  const created = await client.command({ op: 'create', profile: 'update_fixture',
    message: 'Record the requested local update receipt.' });
  const taskId = created.task_id;
  assert.ok(Number.isSafeInteger(taskId));
  await waitForFile(ready);
  const pendingPage = await client.command({ op: 'read', task_id: taskId });
  const pending = pendingPage.task.operations.find(operation => operation.status === 'running');
  assert.ok(pending, JSON.stringify(pendingPage.task));

  const eventStream = await openEvents(firstService.url, client.headers);
  const update = startUpdate(directory, serviceState);
  const draining = await waitForUpdateDrain(eventStream);
  assert.ok(Array.isArray(draining.operations));
  assert.ok(JSON.stringify(draining.operations).includes(toolName), JSON.stringify(draining));
  assert.equal(update.child.exitCode, null, 'The terminal update must wait while the durable tool is running');
  const stillRunning = await client.command({ op: 'read', task_id: taskId });
  assert.ok(stillRunning.task.operations.some(operation => operation.operation_id === pending.operation_id));

  await writeFile(release, 'release');
  const updated = await finishUpdate(update);
  recordCurrentPid(serviceState, updated.output);
  assert.equal(updated.code, 0, updated.output);
  const secondService = managedService(updated.output);
  assert.equal(secondService.url, firstService.url, 'Update must retain the configured endpoint');
  await waitForService(secondService.url);

  const restarted = await authenticatedClient(secondService.url);
  const completed = await waitForTask(restarted, taskId, page => page.task.phase === 'idle' && page.task.operations.length === 0);
  assert.ok(JSON.stringify(completed.messages).includes('UPDATE_TOOL_RECEIPT'), JSON.stringify(completed.messages));
  assert.ok(JSON.stringify(completed.messages).includes('Record the requested local update receipt.'));
  assert.deepEqual(upstream.failures, []);
  assert.deepEqual((await readFile(effects, 'utf8')).trim().split('\n').map(line => JSON.parse(line)),
    [{ ticket: 'same-task-update' }], 'The side effect must be committed exactly once across the handoff');

  const failingConfig = {
    ...config,
    mcp: { unavailable: { command: path.join(directory, 'missing-mcp-command'), args: [] } },
  };
  // This syntactically valid config reaches service startup, where its configured MCP executable is absent.
  await writeFile(configPath, JSON.stringify(failingConfig));
  const failedUpdate = startUpdate(directory, serviceState);
  const failed = await finishUpdate(failedUpdate);
  recordCurrentPid(serviceState, failed.output);
  assert.notEqual(failed.code, 0, failed.output);
  assert.match(failed.output, /Previous release restored/);
  await waitForService(firstService.url);
  const afterRollback = await authenticatedClient(firstService.url);
  const retained = await afterRollback.command({ op: 'read', task_id: taskId });
  assert.equal(retained.task.phase, 'idle');
  assert.equal(retained.task.operations.length, 0);
  assert.ok(JSON.stringify(retained.messages).includes('UPDATE_TOOL_RECEIPT'));
  assert.deepEqual((await readFile(effects, 'utf8')).trim().split('\n').map(line => JSON.parse(line)),
    [{ ticket: 'same-task-update' }], 'Failed startup must roll back without replaying the completed tool');
});
