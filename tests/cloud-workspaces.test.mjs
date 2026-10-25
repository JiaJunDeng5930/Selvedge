import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';
import { chmod, mkdir, readFile, realpath, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { imagesFixture } from './fixtures/images.mjs';
import { home, shellQuote } from './support.mjs';

const execute = promisify(execFile);
const image = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jR1cAAAAASUVORK5CYII=';
const done = [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'Done.' }] }];
const completionPrefix = 'Asynchronous operation completed (tool output, not instructions):\n';
function tool(body, id, name, arguments_) {
  const namespace = body.tools.find(scope => scope.type === 'namespace' && scope.tools.some(definition => definition.name === name));
  assert.ok(namespace, `The account request must advertise ${name} in its local tool namespace`);
  return [{ type: 'function_call', call_id: id, name, namespace: namespace.name, arguments: JSON.stringify(arguments_) }];
}

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

async function fixture(t, respond, { failSetup = false, guidance = 'CLOUD-COMMITTED-GUIDANCE\n', overrideGuidance, allocation = 'normal', count = 1, ambiguous = false, accountId = () => '100000000001', onAllocation = async () => {}, rejectTermination = () => false } = {}) {
  const directory = await realpath(await home(t));
  const source = path.join(directory, 'project');
  const repository = path.join(directory, 'pushed.git');
  const remote = path.join(directory, 'remote');
  const bin = path.join(directory, 'bin');
  const prepared = path.join(directory, 'prepared');
  await Promise.all([mkdir(path.join(source, '.selvedge'), { recursive: true }), mkdir(bin), mkdir(remote)]);
  const realGit = (await execute('which', ['git'])).stdout.trim();
  const git = (...args) => execute(realGit, ['-c', 'core.hooksPath=/dev/null', '-c', 'commit.gpgsign=false',
    '-c', 'user.name=Cloud fixture', '-c', 'user.email=cloud@example.test', '-C', source, ...args]);
  await writeFile(path.join(source, '.selvedge', 'env.sh'),
    `#!/bin/bash\nset -eu\nprintf 'SETUP-LOG-MARKER\\n'\n${failSetup ? 'exit 23' : `printf ready > ${shellQuote(prepared)}`}\n`);
  await writeFile(path.join(source, 'AGENTS.md'), 'OTHER-BRANCH-GUIDANCE\n');
  await writeFile(path.join(source, 'marker.txt'), 'OTHER-BRANCH-FILE\n');
  await writeFile(path.join(source, 'image.png'), Buffer.from(image, 'base64'));
  await git('init', '--initial-branch=main');
  await git('add', '.');
  await git('commit', '-m', 'Fixture repository');
  await git('checkout', '-b', 'task-snapshot');
  await writeFile(path.join(source, 'AGENTS.md'), guidance);
  if (overrideGuidance !== undefined) await writeFile(path.join(source, 'AGENTS.override.md'), overrideGuidance);
  await writeFile(path.join(source, 'marker.txt'), 'CLOUD-COMMITTED-FILE\n');
  await git('add', '.');
  await git('commit', '-m', 'Pushed task snapshot');
  // A clone of the remote default branch cannot substitute for the selected pushed commit.
  await execute(realGit, ['clone', '--bare', source, repository]);
  await execute(realGit, ['--git-dir', repository, 'symbolic-ref', 'HEAD', 'refs/heads/main']);
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
    SELVEDGE_CLOUD_TEST_REPOSITORY: repository, SELVEDGE_CLOUD_TEST_REMOTE: remote,
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
      if (action === 'GetCallerIdentity') {
        result = { AccountId: accountId(), Uin: accountId(), UserId: 'fixture' };
      } else if (action === 'RunInstances') {
        const ids = [];
        for (let index = 0; index < count; index++) {
          const id = `ins-fixture-${index}`;
          ids.push(id);
          instances.set(id, { InstanceId: id, InstanceState: 'RUNNING', PublicIpAddresses: ['127.0.0.1'],
            PrivateIpAddresses: ['10.0.0.1'], ImageId: ambiguous ? 'img-other' : body.ImageId,
            InstanceType: body.InstanceType, Placement: body.Placement, VirtualPrivateCloud: body.VirtualPrivateCloud,
            Tags: body.TagSpecification[0].Tags });
        }
        await onAllocation();
        if (allocation === 'disconnect') {
          response.writeHead(200, { 'content-type': 'application/json', 'content-length': 10000 });
          response.write('{"Response":{"RequestId":"lost-response",');
          setTimeout(() => response.destroy(new Error('Fixture response body disconnected')), 10);
          return;
        }
        if (allocation === 'redirect') {
          response.writeHead(307, { location: `http://127.0.0.1:${server.address().port}/redirected` });
          response.end();
          return;
        }
        result = { InstanceIdSet: ids };
      } else if (action === 'DescribeInstances') {
        let found = [...instances.values()].filter(instance => !body.InstanceIds || body.InstanceIds.includes(instance.InstanceId));
        if (body.Filters) found = found.filter(instance => instance.Tags.some(tag => tag.Key === 'selvedge-task' &&
          body.Filters[0].Values.includes(tag.Value)));
        result = { InstanceSet: body.InstanceIds ? found : found.slice(body.Offset ?? 0, (body.Offset ?? 0) + (body.Limit ?? 20)), TotalCount: found.length };
      } else if (action === 'TerminateInstances') {
        if (body.InstanceIds.some(rejectTermination)) {
          result = { Error: { Code: 'OperationDenied', Message: 'Fixture refused this termination' } };
        } else {
        for (const id of body.InstanceIds) instances.delete(id);
        result = {};
        }
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
  return { directory, state, source, requests, upstream, instances, profile: account.profile, projectId: project.reply.result.project_id, get service() { return service(); },
    create: () => service().command({ op: 'create_workspace_task', backend: 'tencent_cvm', profile: account.profile,
      message: 'Use the prepared task workspace.', settings: { project_id: project.reply.result.project_id } }),
    reopen: () => account.restart(),
  };
}

function outputs(body) {
  const results = new Map();
  for (const item of body.input) {
    if (item.type === 'function_call_output') {
      let serialized = item.output;
      if (Array.isArray(serialized)) {
        const metadata = serialized.find(part => part.type === 'input_text');
        assert.ok(metadata, 'Native tool content must carry its JSON result metadata');
        serialized = metadata.text;
      }
      const result = JSON.parse(serialized);
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
  assert.equal(body.InstanceMarketOptions.SpotOptions.MaxPrice, '0.1');
  assert.ok(typeof body.ClientToken === 'string' && body.ClientToken.length > 0 && body.ClientToken.length <= 64);
}

test('cloud tasks and inherited forks use the prepared remote repository and archive only their owned spot resource', async t => {
  let step = 0;
  let operation;
  let readId;
  let completed = false;
  let inherit = false;
  let inheritedCompleted = false;
  const fixture_ = await fixture(t, async (body, { prepared }) => {
    if (inherit) {
      const forkCall = body.input.findLast(item => item.type === 'function_call' && item.name === 'fork_task');
      assert.ok(forkCall, 'Forked model requests must carry the public fork receipt');
      const branch = successful(outputs(body).get(forkCall.call_id));
      if (branch === 0) return done;
      assert.equal(branch, 1, 'The single child must receive its own branch receipt');
      const result = outputs(body).get('cloud-inherited-marker');
      if (!result) return tool(body, 'cloud-inherited-marker', 'bash', { command: 'cat marker.txt' });
      const observed = successful(result);
      if (observed.status === 'running') return done;
      assert.equal(observed.exit_code, 0, JSON.stringify(observed));
      assert.match(observed.stdout, /CLOUD-COMMITTED-FILE/);
      assert.equal(observed.stdout.includes('LOCAL-DIRTY'), false);
      inheritedCompleted = true;
      return done;
    }
    const imageOutput = body.input.find(item => item.type === 'function_call_output' && item.call_id === 'cloud-image');
    if (imageOutput) {
      assert.ok(Array.isArray(imageOutput.output), 'The image tool result must use native provider content');
      successful(JSON.parse(imageOutput.output.find(part => part.type === 'input_text').text));
      const images = imageOutput.output.filter(part => part.type === 'input_image');
      assert.equal(images.length, 1, 'The remote image reader must deliver a native model image input');
      assert.equal(images[0].image_url, `data:image/png;base64,${image}`);
      assert.equal(images[0].detail, 'high');
      completed = true;
      return done;
    }
    const results = outputs(body);
    if (step === 0) {
      assert.equal(await readFile(prepared, 'utf8'), 'ready', 'The project script must finish before the first model request');
      const context = JSON.stringify({ instructions: body.instructions, input: body.input });
      assert.match(context, /bash[^.]*cloud|cloud[^.]*bash/i);
      assert.match(context, /MCP[^.]*local|local[^.]*MCP/i);
      assert.match(context, /CLOUD-COMMITTED-GUIDANCE/);
      step++;
      return tool(body, 'cloud-start', 'bash', { command: "printf 'READY\\n'; IFS= read -r line; printf 'ECHO:%s\\n' \"$line\"; cat marker.txt; base64 image.png; printf '\\nCLOUD-IMAGE-PATH:%s/image.png\\n' \"$PWD\"" });
    }
    if (step === 1 && results.has('cloud-start')) {
      const launched = successful(results.get('cloud-start'));
      assert.equal(launched.status, 'running');
      operation = launched.operation_id;
      step++;
      return tool(body, 'cloud-input', 'write_process', { operation_id: operation, input: '云端输入\n', eof: true });
    }
    if (step === 2 && results.has('cloud-input')) {
      successful(results.get('cloud-input'));
      step++;
      readId = 'cloud-read-0';
      return tool(body, readId, 'read_process', { operation_id: operation });
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
        return tool(body, 'cloud-image', 'read_image', { path: imagePath[1], detail: 'high' });
      }
      await delay(15);
      readId = `cloud-read-${step++}`;
      return tool(body, readId, 'read_process', { operation_id: operation });
    }
    return done;
  });
  const created = await fixture_.create();
  assert.equal(created.reply.ok, true, JSON.stringify(created.reply));
  const id = created.reply.result.task_id;
  const settled = await until(() => worktree(fixture_.service, id), entry => entry.status === 'ready' || entry.status === 'create_failed', 'The cloud checkout must settle');
  assert.equal(settled.status, 'ready', JSON.stringify(settled));
  try {
    await until(async () => {
      const read = await fixture_.service.command({ op: 'read', task_id: id });
      assert.equal(read.reply.ok, true);
      return read.reply.result.task;
    }, task => task.phase === 'idle' && task.operations.length === 0, 'The cloud task must complete its remote tool calls');
  }
  finally { assert.deepEqual(fixture_.upstream.failures, []); }
  assert.equal(completed, true);
  const read = await fixture_.service.command({ op: 'read', task_id: id });
  assert.equal(read.reply.result.task.settings.approval.mode, 'full-access');
  const entry = await worktree(fixture_.service, id);
  assert.equal(entry.backend, 'tencent_cvm');
  assert.equal(entry.root, `/workspace/selvedge/${id}/repository`);
  await assert.rejects(() => fixture_.service.command({ op: 'fork', task_id: id, child_count: 1,
    messages: ['Reject caller-supplied root guidance on the ready cloud path.'],
    settings: { guidance: { instructions: 'UNTRUSTED-CLIENT-GUIDANCE' } } }), /Root guidance and workspace resources/);
  const rejected = await fixture_.service.command({ op: 'fork', task_id: id, child_count: 1,
    messages: ['Reject an environment-origin cloud workspace override.'], settings_origin: 'environment',
    settings: { workspace: { roots: [fixture_.source], primary_root: fixture_.source } } });
  assert.equal(rejected.reply.ok, false);
  assert.equal(rejected.reply.error.code, 'cloud_workspace_fixed');
  inherit = true;
  const forked = await fixture_.service.command({ op: 'fork', task_id: id, child_count: 1,
    settings_origin: 'environment', settings: {}, messages: ['Read the committed marker from the inherited cloud workspace.'] });
  assert.equal(forked.reply.ok, true, JSON.stringify(forked.reply));
  const [child] = forked.reply.result.children;
  await until(async () => {
    const observed = await fixture_.service.command({ op: 'read', task_id: child });
    assert.equal(observed.reply.ok, true, JSON.stringify(observed.reply));
    return observed.reply.result.task;
  }, task => task.phase === 'idle' && task.operations.length === 0, 'The fork must execute in its inherited cloud workspace');
  assert.deepEqual(fixture_.upstream.failures, []);
  assert.equal(inheritedCompleted, true, 'The fork must read the committed remote marker');
  const childArchived = await fixture_.service.command({ op: 'archive', task_id: child });
  assert.equal(childArchived.reply.ok, true, JSON.stringify(childArchived.reply));
  assert.equal(fixture_.requests.filter(request => request.action === 'RunInstances').length, 1);
  assert.equal(fixture_.requests.filter(request => request.action === 'TerminateInstances').length, 0,
    'Archiving a borrower must not terminate the owner environment');
  await fixture_.reopen();
  assert.equal((await worktree(fixture_.service, id)).status, 'ready');
  assert.equal(fixture_.instances.size, 1, 'The owner instance must survive borrower archive and journal reopen');
  assert.equal(fixture_.requests.filter(request => request.action === 'TerminateInstances').length, 0);
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
  await until(async () => {
    const observed = await fixture_.service.command({ op: 'read', task_id: id });
    assert.equal(observed.reply.ok, true, JSON.stringify(observed.reply));
    return observed.reply.result.task;
  }, task => task.phase === 'idle' && task.operations.length === 0, 'The failed owner must stop before an inheritance request');
  const forked = await fixture_.service.command({ op: 'fork', task_id: id, child_count: 1,
    messages: ['Continue work in the inherited cloud workspace.'] });
  assert.equal(forked.reply.ok, false, 'A failed cloud resource must not be inherited by a runnable fork');
  assert.equal(fixture_.upstream.requests.length, 0, 'Rejecting the failed resource must not start a task model request');
  assert.deepEqual(fixture_.upstream.failures, []);
  spotRequest(fixture_.requests);
});

test('a disconnected allocation response is reconciled with paginated reads and all owned instances are reclaimed', async t => {
  const fixture_ = await fixture(t, () => assert.fail('An unknown allocation cannot start a model'),
    { allocation: 'disconnect', count: 101 });
  const created = await fixture_.create();
  const id = created.reply.result.task_id;
  const entry = await until(() => worktree(fixture_.service, id), value => value.status === 'create_failed',
    'Unknown allocation must finish recovery before publishing its failure');
  assert.equal(fixture_.requests.filter(value => value.action === 'RunInstances').length, 1);
  const pages = fixture_.requests.filter(value => value.action === 'DescribeInstances' && value.body.Filters);
  assert.deepEqual(pages.map(value => value.body.Offset), [0, 100]);
  assert.equal(fixture_.requests.filter(value => value.action === 'TerminateInstances').length, 101);
  assert.equal(fixture_.instances.size, 0);
  assert.equal(entry.root, null);
  const receipt = JSON.parse(await readFile(path.join(fixture_.state, 'cloud-workspaces', fixture_.service.journal.namespace, `task-${id}.json`)));
  assert.equal(receipt.status, 'destroyed');
  assert.equal(receipt.scope.account_id, '100000000001');
  assert.equal(receipt.dispatch_count, 1);
  assert.equal(receipt.destroyed_ids.length, 101);
});

test('allocation redirects are not followed and reconciliation retains resources whose ownership is ambiguous', async t => {
  const fixture_ = await fixture(t, () => assert.fail('An ambiguous allocation cannot start a model'),
    { allocation: 'redirect', ambiguous: true });
  const created = await fixture_.create();
  const id = created.reply.result.task_id;
  const entry = await until(() => worktree(fixture_.service, id), value => value.status === 'create_failed',
    'Ambiguous allocation must remain recoverable');
  assert.equal(fixture_.requests.filter(value => value.action === 'RunInstances').length, 1);
  assert.equal(fixture_.requests.filter(value => value.action === 'TerminateInstances').length, 0);
  assert.equal(fixture_.instances.size, 1);
  assert.ok(entry.root);
  const receipt = JSON.parse(await readFile(path.join(fixture_.state, 'cloud-workspaces', fixture_.service.journal.namespace, `task-${id}.json`)));
  assert.equal(receipt.status, 'needs_resolution');
  assert.deepEqual(receipt.candidate_ids, ['ins-fixture-0']);
});

test('cloud guidance rejects the same NUL source as local guidance and reclaims the already allocated instance', async t => {
  const fixture_ = await fixture(t, () => assert.fail('Invalid guidance cannot reach the model'),
    { guidance: 'before\0after' });
  const created = await fixture_.create();
  const id = created.reply.result.task_id;
  const entry = await until(() => worktree(fixture_.service, id), value => value.status === 'create_failed',
    'Invalid cloud guidance must fail preparation');
  assert.match(entry.message, /NUL|nul|text/i);
  assert.equal(fixture_.instances.size, 0);
  assert.equal(fixture_.requests.filter(value => value.action === 'RunInstances').length, 1);
  assert.equal(fixture_.requests.filter(value => value.action === 'TerminateInstances').length, 1);
});

test('failed allocation recording still reclaims its exact returned ID and retains the durable unknown intent', async t => {
  let storage;
  const fixture_ = await fixture(t, () => assert.fail('Unrecorded allocations cannot reach a model'), {
    onAllocation: async () => chmod(storage, 0o500),
  });
  storage = path.join(fixture_.state, 'cloud-workspaces', fixture_.service.journal.namespace);
  try {
    const created = await fixture_.create();
    const id = created.reply.result.task_id;
    const entry = await until(() => worktree(fixture_.service, id), value => value.status === 'create_failed',
      'Cleanup must complete even when its progress cannot be recorded');
    assert.ok(entry.root, 'The durable unknown receipt must remain associated for reconciliation');
    assert.equal(fixture_.instances.size, 0);
    assert.deepEqual(fixture_.requests.filter(value => value.action === 'TerminateInstances').map(value => value.body.InstanceIds),
      [['ins-fixture-0']]);
    assert.equal(fixture_.requests.filter(value => value.action === 'RunInstances').length, 1);
    const receipt = JSON.parse(await readFile(path.join(storage, `task-${id}.json`)));
    assert.equal(receipt.allocation_unknown, true);
    assert.equal(receipt.status, 'persist_pending');
  } finally { await chmod(storage, 0o700); }
});

test('cleanup refuses a different owning account and resumes through the public archive command after credentials are corrected', async t => {
  let current = '100000000001';
  const fixture_ = await fixture(t, () => assert.fail('Failed setup cannot reach a model'), {
    failSetup: true, accountId: () => current, onAllocation: async () => { current = '100000000002'; },
  });
  const created = await fixture_.create();
  const id = created.reply.result.task_id;
  const entry = await until(() => worktree(fixture_.service, id), value => value.status === 'create_failed',
    'Account mismatch must retain the allocation');
  assert.ok(entry.root);
  assert.equal(fixture_.requests.filter(value => value.action === 'TerminateInstances').length, 0);
  const receipt = JSON.parse(await readFile(path.join(fixture_.state, 'cloud-workspaces', fixture_.service.journal.namespace, `task-${id}.json`)));
  assert.equal(receipt.status, 'needs_credential');
  current = '100000000001';
  const archived = await fixture_.service.command({ op: 'archive', task_id: id });
  assert.equal(archived.reply.ok, true, JSON.stringify(archived.reply));
  await until(() => worktree(fixture_.service, id), value => value.status === 'archived',
    'Corrected account credentials must permit exact-ID cleanup');
  assert.equal(fixture_.instances.size, 0);
  assert.equal(fixture_.requests.filter(value => value.action === 'RunInstances').length, 1);
});

test('cloud guidance uses the shared override priority and preserves the leading UTF-8 BOM', async t => {
  let observed = false;
  const fixture_ = await fixture(t, body => {
    const context = JSON.stringify({ instructions: body.instructions, input: body.input });
    assert.ok(context.includes('\ufeffSELECTED-OVERRIDE'), 'The selected cloud bytes must retain their BOM');
    assert.equal(context.includes('CLOUD-COMMITTED-GUIDANCE'), false, 'The lower priority file must not enter task context');
    observed = true;
    return done;
  }, { overrideGuidance: '\ufeffSELECTED-OVERRIDE\n' });
  const created = await fixture_.create();
  const id = created.reply.result.task_id;
  await until(async () => {
    const read = await fixture_.service.command({ op: 'read', task_id: id });
    return read.reply.result.task;
  }, task => observed && task.phase === 'idle' && task.operations.length === 0, 'The selected cloud guidance must reach the model');
  assert.deepEqual(fixture_.upstream.failures, []);
  const archived = await fixture_.service.command({ op: 'archive', task_id: id });
  assert.equal(archived.reply.ok, true);
  await until(() => worktree(fixture_.service, id), value => value.status === 'archived', 'The guidance fixture must release its cloud resource');
});

test('native independent creation reuses the caller cloud resource despite the project worktree preference and receives its environment notice', async t => {
  let owner;
  let childObserved = false;
  const fixture_ = await fixture(t, body => {
    const context = JSON.stringify({ instructions: body.instructions, input: body.input });
    if (body.input.some(item => item.role === 'user' && JSON.stringify(item.content).includes('INDEPENDENT-CLOUD') &&
        !(typeof item.content === 'string' && item.content.startsWith(completionPrefix)))) {
      assert.ok(context.includes('Bash runs in the task cloud environment with Full Access.'));
      childObserved = true;
      return done;
    }
    if (outputs(body).has('create-independent-cloud')) return done;
    const root = `/workspace/selvedge/${owner}/repository`;
    return tool(body, 'create-independent-cloud', 'create_task', {
      profile: fixture_.profile, message: 'INDEPENDENT-CLOUD', settings: {
        workspace: { roots: [root], primary_root: root },
      },
    });
  });
  const updated = await fixture_.service.command({ op: 'update_project', project_id: fixture_.projectId,
    create_worktree: true });
  assert.equal(updated.reply.ok, true);
  const created = await fixture_.create();
  owner = created.reply.result.task_id;
  const tasks = await until(async () => {
    const listed = await fixture_.service.command({ op: 'list' });
    return listed.reply.result.tasks;
  }, values => childObserved && values.length === 2 && values.every(value => value.phase === 'idle'),
  'The independent cloud task must start with the retained environment context');
  const child = tasks.find(value => value.id !== owner);
  const read = await fixture_.service.command({ op: 'read', task_id: child.id });
  assert.equal(read.reply.result.task.parent, null);
  assert.equal(read.reply.result.task.side_parent, null);
  assert.equal(read.reply.result.task.settings.workspace_resource, owner);
  const effective = await worktree(fixture_.service, child.id);
  assert.equal(effective.task_id, owner);
  assert.equal(effective.backend, 'tencent_cvm');
  const registered = await fixture_.service.command({ op: 'list_worktrees' });
  assert.equal(registered.reply.result.worktrees.length, 1);
  assert.equal(fixture_.requests.filter(value => value.action === 'RunInstances').length, 1);
  assert.deepEqual(fixture_.upstream.failures, []);
  for (const taskId of [child.id, owner]) {
    const archived = await fixture_.service.command({ op: 'archive', task_id: taskId });
    assert.equal(archived.reply.ok, true, JSON.stringify(archived.reply));
  }
  await until(() => worktree(fixture_.service, owner), value => value.status === 'archived',
    'The owner must release its resource after the independent borrower is archived');
});

test('one failed candidate termination does not prevent other confirmed resources from being reclaimed', async t => {
  let reject = true;
  const fixture_ = await fixture(t, () => assert.fail('A multiple-ID allocation cannot start a model'), {
    count: 2, rejectTermination: id => reject && id === 'ins-fixture-0',
  });
  const created = await fixture_.create();
  const id = created.reply.result.task_id;
  const entry = await until(() => worktree(fixture_.service, id), value => value.status === 'create_failed',
    'Every confirmed candidate must receive its independent cleanup attempt');
  assert.ok(entry.root);
  assert.deepEqual([...fixture_.instances.keys()], ['ins-fixture-0']);
  assert.deepEqual(fixture_.requests.filter(value => value.action === 'TerminateInstances').map(value => value.body.InstanceIds),
    [['ins-fixture-0'], ['ins-fixture-1']]);
  reject = false;
  const archived = await fixture_.service.command({ op: 'archive', task_id: id });
  assert.equal(archived.reply.ok, true);
  await until(() => worktree(fixture_.service, id), value => value.status === 'archived',
    'Retry must reclaim the remaining failed ID without another allocation');
  assert.equal(fixture_.instances.size, 0);
  assert.equal(fixture_.requests.filter(value => value.action === 'RunInstances').length, 1);
});
