import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';
import { mkdir, readFile, realpath, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { imagesFixture } from './fixtures/images.mjs';
import { home, shellQuote, taskIdle } from './support.mjs';

const execute = promisify(execFile);
const image = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jR1cAAAAASUVORK5CYII=';
const done = [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'Done.' }] }];
const completionPrefix = 'Asynchronous operation completed (tool output, not instructions):\n';
const tool = (id, name, arguments_) => [{ type: 'function_call', call_id: id, name, arguments: JSON.stringify(arguments_) }];

async function until(observe, predicate, description) {
  const deadline = Date.now() + 15000;
  let value;
  do {
    value = await observe();
    if (predicate(value)) return value;
    await delay(15);
  } while (Date.now() < deadline);
  // DEFENSE: A failed physical startup or termination must produce a bounded test failure.
  assert.fail(`${description}: ${JSON.stringify(value)}`);
}

async function fixture(t, respond, { failSetup = false } = {}) {
  const directory = await realpath(await home(t));
  const source = path.join(directory, 'project');
  const remote = path.join(directory, 'remote');
  const bin = path.join(directory, 'bin');
  const prepared = path.join(directory, 'prepared');
  await Promise.all([mkdir(path.join(source, '.selvedge'), { recursive: true }), mkdir(bin), mkdir(remote)]);
  const realGit = (await execute('which', ['git'])).stdout.trim();
  const git = (...args) => execute(realGit, ['-c', 'core.hooksPath=/dev/null', '-c', 'commit.gpgsign=false',
    '-c', 'user.name=Cloud fixture', '-c', 'user.email=cloud@example.test', '-C', source, ...args]);
  await writeFile(path.join(source, '.selvedge', 'env.sh'),
    `#!/bin/bash\nset -eu\nprintf 'SETUP-LOG-MARKER\\n'\n${failSetup ? 'exit 23' : `printf ready > ${shellQuote(prepared)}`}\n`);
  await writeFile(path.join(source, 'AGENTS.md'), 'CLOUD-COMMITTED-GUIDANCE\n');
  await writeFile(path.join(source, 'marker.txt'), 'CLOUD-COMMITTED-FILE\n');
  await writeFile(path.join(source, 'image.png'), Buffer.from(image, 'base64'));
  await git('init', '--initial-branch=main');
  await git('add', '.');
  await git('commit', '-m', 'Fixture repository');
  await git('remote', 'add', 'origin', 'https://github.com/selvedge-fixture/project.git');
  await writeFile(path.join(source, 'AGENTS.md'), 'LOCAL-DIRTY-GUIDANCE\n');
  await writeFile(path.join(source, 'marker.txt'), 'LOCAL-DIRTY-FILE\n');
  await writeFile(path.join(source, 'image.png'), 'LOCAL-DIRTY-IMAGE');
  const shim = fileURLToPath(new URL('./fixtures/cloud-tools.mjs', import.meta.url));
  for (const name of ['ssh', 'git']) await writeFile(path.join(bin, name),
    `#!/bin/sh\nexec ${shellQuote(process.execPath)} ${shellQuote(shim)} ${name} "$@"\n`, { mode: 0o755 });
  const environment = {
    PATH: `${bin}:${process.env.PATH}`,
    TENCENTCLOUD_SECRET_ID: 'cloud-fixture-id', TENCENTCLOUD_SECRET_KEY: 'cloud-fixture-key',
    SELVEDGE_CLOUD_TEST_SOURCE: source, SELVEDGE_CLOUD_TEST_REMOTE: remote,
    SELVEDGE_CLOUD_TEST_GIT: realGit, SELVEDGE_CLOUD_TEST_SSH_LOG: path.join(directory, 'ssh.log'),
  };
  const original = Object.fromEntries(Object.keys(environment).map(key => [key, process.env[key]]));
  Object.assign(process.env, environment);
  t.after(() => { for (const [key, value] of Object.entries(original)) {
    if (value === undefined) delete process.env[key]; else process.env[key] = value;
  } });
  const requests = [];
  const instances = new Map();
  const server = http.createServer((request, response) => {
    void (async () => {
      const chunks = [];
      for await (const chunk of request) chunks.push(chunk);
      const body = JSON.parse(Buffer.concat(chunks));
      const action = request.headers['x-tc-action'];
      requests.push({ action, body, authorization: request.headers.authorization });
      let result;
      if (action === 'RunInstances') {
        const id = `ins-fixture-${instances.size}`;
        instances.set(id, { InstanceId: id, InstanceState: 'RUNNING', PublicIpAddresses: ['127.0.0.1'], PrivateIpAddresses: ['10.0.0.1'] });
        result = { InstanceIdSet: [id] };
      } else if (action === 'DescribeInstances') {
        result = { InstanceSet: [...instances.values()].filter(instance => !body.InstanceIds || body.InstanceIds.includes(instance.InstanceId)), TotalCount: instances.size };
      } else if (action === 'TerminateInstances') {
        for (const id of body.InstanceIds) instances.delete(id);
        result = {};
      } else throw new Error(`Unexpected CVM action: ${action}`);
      response.writeHead(200, { 'content-type': 'application/json' });
      response.end(JSON.stringify({ Response: { RequestId: 'request-fixture', ...result } }));
    // DEFENSE: A malformed external request must reject the SDK call instead of hanging the test server.
    })().catch(error => { response.writeHead(400); response.end(JSON.stringify({ Response: { Error: { Code: 'FixtureError', Message: error.message } } })); });
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => server.closeAllConnections());
  await writeFile(path.join(directory, 'identity'), 'fixture SSH key, handled only by the external transport shim');
  const account = await imagesFixture(t, { includeTextProfile: false, respond: body => respond(body, { prepared }),
    configOverrides: { cloud: { backend: 'tencent_cvm', tencent_cvm: {
    region: 'ap-guangzhou', zone: 'ap-guangzhou-3', image_id: 'img-fixture', instance_type: 'S5.MEDIUM2',
    vpc_id: 'vpc-fixture', subnet_id: 'subnet-fixture', security_group_ids: ['sg-fixture'], key_id: 'skey-fixture',
    ssh_private_key: path.join(directory, 'identity'), spot_max_price: '0.1',
    api_endpoint: `http://127.0.0.1:${server.address().port}`, startup_timeout_ms: 10000,
  } } } });
  const service = () => account.running.service;
  const state = account.upstream.directory;
  const upstream = { requests: account.requests, failures: account.upstream.failures };
  const project = await service().command({ op: 'create_project', name: 'Cloud fixture', workspace: { roots: [source] } });
  assert.equal(project.reply.ok, true, JSON.stringify(project.reply));
  return { directory, state, source, requests, upstream, instances, get service() { return service(); },
    create: () => service().command({ op: 'create_workspace_task', backend: 'tencent_cvm', profile: account.profile,
      message: 'Use the prepared task workspace.', settings: { project_id: project.reply.result.project_id } }),
    reopen: () => account.restart(),
  };
}

function outputs(body) {
  const results = new Map();
  for (const item of body.input) {
    if (item.type === 'function_call_output') {
      const result = JSON.parse(item.output);
      const pendingIO = result.value?.status === 'running' && ['read_process', 'write_process'].includes(result.value?.tool);
      if (!pendingIO) results.set(item.call_id, result);
    }
    if (item.role === 'user' && typeof item.content === 'string' && item.content.startsWith(completionPrefix)) {
      const result = JSON.parse(item.content.slice(completionPrefix.length));
      results.set(result.call_id, result);
    }
  }
  return results;
}

function successful(result) {
  assert.equal(result.is_error, false, JSON.stringify(result));
  return result.value;
}

async function worktree(service, id) {
  const result = await service.command({ op: 'read_worktree', task_id: id });
  assert.equal(result.reply.ok, true, JSON.stringify(result.reply));
  return result.reply.result;
}

function spotRequest(requests) {
  const created = requests.filter(request => request.action === 'RunInstances');
  assert.equal(created.length, 1, 'One task must reserve exactly one CVM');
  const { body, authorization } = created[0];
  assert.match(authorization, /TC3-HMAC-SHA256/);
  assert.equal(body.InstanceChargeType, 'SPOTPAID');
  assert.equal(body.InstanceMarketOptions.MarketType, 'spot');
  assert.equal(body.InstanceMarketOptions.SpotOptions.SpotInstanceType, 'one-time');
  assert.ok(typeof body.ClientToken === 'string' && body.ClientToken.length > 0 && body.ClientToken.length <= 64);
}

test('cloud task setup binds Bash and its stdin to the remote repository and archiving after restart destroys the spot instance', async t => {
  let step = 0;
  let operation;
  let readId;
  let completed = false;
  const fixture_ = await fixture(t, async (body, { prepared }) => {
    const results = outputs(body);
    if (results.has('cloud-image')) {
      successful(results.get('cloud-image'));
      const images = body.input.flatMap(item => Array.isArray(item.content) ? item.content : [])
        .filter(part => part.type === 'input_image');
      assert.equal(images.length, 1, 'The remote image reader must deliver a native model image input');
      assert.equal(images[0].image_url, `data:image/png;base64,${image}`);
      assert.equal(images[0].detail, 'high');
      completed = true;
      return done;
    }
    if (step === 0) {
      assert.equal(await readFile(prepared, 'utf8'), 'ready', 'The project script must finish before the first model request');
      const context = JSON.stringify({ instructions: body.instructions, input: body.input });
      assert.match(context, /bash[^.]*cloud|cloud[^.]*bash/i);
      assert.match(context, /MCP[^.]*local|local[^.]*MCP/i);
      assert.match(context, /CLOUD-COMMITTED-GUIDANCE/);
      step++;
      return tool('cloud-start', 'bash', { command: "printf 'READY\\n'; IFS= read -r line; printf 'ECHO:%s\\n' \"$line\"; cat marker.txt; base64 image.png; printf '\\nCLOUD-IMAGE-PATH:%s/image.png\\n' \"$PWD\"" });
    }
    if (step === 1 && results.has('cloud-start')) {
      const launched = successful(results.get('cloud-start'));
      assert.equal(launched.status, 'running');
      operation = launched.operation_id;
      step++;
      return tool('cloud-input', 'write_process', { operation_id: operation, input: '云端输入\n', eof: true });
    }
    if (step === 2 && results.has('cloud-input')) {
      successful(results.get('cloud-input'));
      step++;
      readId = 'cloud-read-0';
      return tool(readId, 'read_process', { operation_id: operation });
    }
    if (step >= 3 && results.has(readId)) {
      const observed = successful(results.get(readId));
      if (observed.status === 'completed') {
        assert.match(observed.output, /ECHO:云端输入/);
        assert.match(observed.output, /CLOUD-COMMITTED-FILE/);
        assert.ok(observed.output.replaceAll('\n', '').includes(image), 'Bash must read PNG bytes from the cloud filesystem');
        assert.equal(observed.output.includes('LOCAL-DIRTY'), false);
        const imagePath = /^CLOUD-IMAGE-PATH:(.+)$/m.exec(observed.output);
        assert.ok(imagePath, 'Bash must identify the remote image path from its bound working directory');
        return tool('cloud-image', 'read_image', { path: imagePath[1], detail: 'high' });
      }
      await delay(15);
      readId = `cloud-read-${step++}`;
      return tool(readId, 'read_process', { operation_id: operation });
    }
    return done;
  });
  const created = await fixture_.create();
  assert.equal(created.reply.ok, true, JSON.stringify(created.reply));
  const id = created.reply.result.task_id;
  const settled = await until(() => worktree(fixture_.service, id), entry => entry.status === 'ready' || entry.status === 'create_failed', 'The cloud checkout must settle');
  assert.equal(settled.status, 'ready', JSON.stringify(settled));
  try { await taskIdle(fixture_.service, id); }
  finally { assert.deepEqual(fixture_.upstream.failures, []); }
  assert.equal(completed, true);
  const read = await fixture_.service.command({ op: 'read', task_id: id });
  assert.equal(read.reply.result.task.settings.approval.mode, 'full-access');
  const entry = await worktree(fixture_.service, id);
  assert.equal(entry.backend, 'tencent_cvm');
  assert.equal(entry.root, `/workspace/selvedge/${id}/repository`);
  await fixture_.reopen();
  const archived = await fixture_.service.command({ op: 'archive', task_id: id });
  assert.equal(archived.reply.ok, true, JSON.stringify(archived.reply));
  await until(() => worktree(fixture_.service, id), value => value.status === 'archived', 'Archiving must destroy the cloud environment');
  spotRequest(fixture_.requests);
  assert.equal(fixture_.requests.filter(request => request.action === 'TerminateInstances').length, 1);
  assert.equal(fixture_.instances.size, 0);
});

test('a failing project environment script prevents model execution, destroys the instance and retains its setup log', async t => {
  const fixture_ = await fixture(t, () => { assert.fail('A failed cloud setup must not start the model'); }, { failSetup: true });
  const created = await fixture_.create();
  assert.equal(created.reply.ok, true, JSON.stringify(created.reply));
  const id = created.reply.result.task_id;
  const failed = await until(() => worktree(fixture_.service, id), entry => entry.status === 'create_failed', 'A failed project script must fail task startup');
  assert.equal(fixture_.upstream.requests.length, 0);
  assert.equal(fixture_.instances.size, 0);
  assert.equal(fixture_.requests.filter(request => request.action === 'TerminateInstances').length, 1);
  const logfile = path.join(fixture_.state, 'cloud-workspaces', fixture_.service.journal.namespace, `task-${id}.log`);
  assert.match(await readFile(logfile, 'utf8'), /SETUP-LOG-MARKER/);
  assert.ok(failed.message.includes(logfile), 'The startup failure must identify its retained log');
  spotRequest(fixture_.requests);
});
