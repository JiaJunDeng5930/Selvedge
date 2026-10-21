import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { execFile } from 'node:child_process';
import { access, chmod, lstat, mkdir, readFile, readdir, symlink, unlink, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { promisify } from 'node:util';
import { setTimeout as delay } from 'node:timers/promises';
import { home, shellQuote } from './support.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { imageBytes } from './fixtures/image-data.mjs';
import { answer, filesystemChild, filesystemServer } from './fixtures/filesystem-boundaries-server.mjs';

async function write(filename, contents) {
  await mkdir(path.dirname(filename), { recursive: true });
  await writeFile(filename, contents);
  return filename;
}

async function matchingFiles(directory, bytes) {
  const matches = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const filename = path.join(directory, entry.name);
    if (entry.isDirectory()) matches.push(...await matchingFiles(filename, bytes));
    if (entry.isFile() && (await lstat(filename)).size === bytes.length
        && (await readFile(filename)).equals(bytes)) matches.push(filename);
  }
  return matches;
}

function providerContextContent(request, type, filename, initial) {
  let content;
  for (const item of request.input) {
    if (typeof item.content !== 'string' || !item.content.startsWith('Committed context object ')) continue;
    const lines = item.content.split('\n');
    const key = JSON.parse(lines[1].slice('Context: '.length));
    if (key.type !== type || key.identity.path !== filename) continue;
    if (lines[0] === 'Committed context object introduced.') {
      assert.ok(item.content.includes(`Field: content\n${initial}\n`));
      content = initial;
    } else if (lines[0] === 'Committed context object update.') {
      assert.notEqual(content, undefined, 'An update requires its earlier introduction');
      const field = item.content.split('Field: content\n')[1]?.split('\nField: ')[0];
      if (field === undefined) continue;
      const edits = [...field.matchAll(/^@@ code point (\d+) @@\n- (.+)\n\+ (.+)$/gm)];
      assert.ok(edits.length > 0, 'The public context amendment contains concrete edits');
      // Public amendments index the previous content by Unicode code point.
      const characters = [...content];
      for (const [, position, removed, inserted] of edits.reverse()) {
        const start = Number(position), before = [...JSON.parse(removed)];
        assert.equal(characters.slice(start, start + before.length).join(''), before.join(''));
        characters.splice(start, before.length, ...JSON.parse(inserted));
      }
      content = characters.join('');
    } else if (lines[0] === 'Committed context object removed.') content = undefined;
  }
  return content;
}

test('HTTP attachment reads preserve uploaded bytes and reject changed bytes or a matching symlink', async t => {
  const fixture = await filesystemServer(t);
  const upload = await fetch(`${fixture.running.address}/api/board/attachments?name=evidence.png`, {
    method: 'POST', headers: { ...fixture.headers, 'content-type': 'application/octet-stream' }, body: imageBytes,
  });
  assert.equal(upload.status, 201, await upload.clone().text());
  const attachment = (await upload.json()).result;
  assert.equal(attachment.id, createHash('sha256').update(imageBytes).digest('hex'));
  const read = () => fetch(`${fixture.running.address}/api/board/attachments/${attachment.id}`, { headers: fixture.headers });
  const original = await read();
  assert.equal(original.status, 200);
  assert.deepEqual(Buffer.from(await original.arrayBuffer()), imageBytes);

  // Locate the fixture's persisted bytes without tying the failure to a vault layout.
  const [stored, ...extra] = await matchingFiles(fixture.state, imageBytes);
  assert.ok(stored, 'The upload persists its original bytes');
  assert.deepEqual(extra, []);
  await chmod(stored, 0o600);
  await writeFile(stored, 'changed fixture bytes');
  assert.equal((await read()).ok, false, 'An attachment hash must cover the bytes actually read');

  const external = await write(path.join(fixture.directory, 'external.png'), imageBytes);
  await unlink(stored);
  await symlink(external, stored);
  assert.equal((await read()).ok, false, 'Matching bytes do not authorize following an external symlink');
  const health = await fetch(`${fixture.running.address}/api/health`, { headers: fixture.headers });
  assert.equal(health.status, 200);
});

test('provider context respects a Git-file boundary and retains accepted guidance when a source becomes a symlink', async t => {
  const directory = await home(t);
  const state = path.join(directory, 'state');
  const repository = path.join(directory, 'checkout');
  const primary = path.join(repository, 'packages', 'app');
  const nested = path.join(primary, 'src');
  const second = path.join(directory, 'second');
  await write(path.join(repository, '.git'), 'gitdir: /not-traversed\n');
  await mkdir(path.join(second, '.git'), { recursive: true });
  await write(path.join(directory, 'AGENTS.md'), 'OUTSIDE-GIT-BOUNDARY');
  const rootGuidance = await write(path.join(repository, 'AGENTS.md'), 'REPOSITORY-ACCEPTED-GUIDANCE');
  await write(path.join(primary, 'AGENTS.md'), 'SUPERSEDED-PRIMARY-GUIDANCE');
  await write(path.join(primary, 'AGENTS.override.md'), 'PRIMARY-OVERRIDE-GUIDANCE');
  const nestedGuidance = await write(path.join(nested, 'AGENTS.md'), 'NESTED-ACCEPTED-GUIDANCE');
  await write(path.join(second, 'AGENTS.md'), 'SECOND-ROOT-GUIDANCE');
  const global = await write(path.join(state, 'AGENTS.md'), 'GLOBAL-ACCEPTED-GUIDANCE');
  const skillContents = '---\nname: fixture\ndescription: Discover fixture metadata\n---\nPRIVATE-SKILL-BODY';
  const explicit = await write(path.join(repository, '.agents', 'skills', 'explicit', 'SKILL.md'), skillContents);
  const automatic = await write(path.join(nested, '.claude', 'skills', 'automatic', 'SKILL.md'), skillContents);
  const userSkill = await write(path.join(state, 'skills', 'user', 'SKILL.md'), skillContents);
  await write(path.join(state, 'config.json'), JSON.stringify({ ...defaultConfig, chatgpt: false, port: 0, skills: [explicit] }));
  const outside = path.join(directory, 'outside');
  await write(path.join(outside, 'AGENTS.md'), 'DIRECTORY-LINK-MUST-NOT-BE-FOLLOWED');
  await symlink(outside, path.join(primary, 'linked'));
  const fixture = await filesystemServer(t, { directory, state, cwd: primary,
    respond: () => answer('Context received.'), config: { skills: [explicit] } });
  const { task_id } = await fixture.command({ op: 'create', profile: fixture.profile, message: 'Observe the workspace.',
    settings: { workspace: { roots: [primary, second], primary_root: primary } } });
  await fixture.idle(task_id);
  assert.equal(fixture.upstream.requests.length, 1);
  const first = JSON.stringify(fixture.upstream.requests[0]);
  for (const text of ['REPOSITORY-ACCEPTED-GUIDANCE', 'NESTED-ACCEPTED-GUIDANCE',
    'PRIMARY-OVERRIDE-GUIDANCE', 'SECOND-ROOT-GUIDANCE', 'GLOBAL-ACCEPTED-GUIDANCE']) assert.ok(first.includes(text), text);
  for (const text of ['OUTSIDE-GIT-BOUNDARY', 'DIRECTORY-LINK-MUST-NOT-BE-FOLLOWED',
    'PRIVATE-SKILL-BODY', 'SUPERSEDED-PRIMARY-GUIDANCE']) assert.equal(first.includes(text), false, text);

  await unlink(nestedGuidance);
  await symlink(rootGuidance, nestedGuidance);
  await writeFile(rootGuidance, 'REPOSITORY-NOT-YET-ACCEPTED-GUIDANCE');
  await writeFile(global, 'GLOBAL-INDEPENDENT-UPDATE');
  await fixture.command({ op: 'send', task_id, message: 'Observe the independently updated global guidance.' });
  await fixture.idle(task_id);
  assert.equal(fixture.upstream.requests.length, 2);
  const next = JSON.stringify(fixture.upstream.requests[1]);
  for (const text of ['REPOSITORY-ACCEPTED-GUIDANCE', 'NESTED-ACCEPTED-GUIDANCE']) {
    assert.ok(next.includes(text), `The actual next provider request must retain ${text}`);
  }
  assert.equal(next.includes('REPOSITORY-NOT-YET-ACCEPTED-GUIDANCE'), false);
  assert.ok(next.includes('Context source observation failed:'));
  assert.equal(providerContextContent(fixture.upstream.requests[1], 'global_agents', global,
    'GLOBAL-ACCEPTED-GUIDANCE'), 'GLOBAL-INDEPENDENT-UPDATE');

  const observeSkills = async () => {
    const response = await fetch(`${fixture.running.address}/api/browser/observation`, { method: 'POST',
      headers: { ...fixture.headers, 'content-type': 'application/json' },
      body: JSON.stringify({ kind: 'skill-catalog', workspace: { roots: [primary, second], primary_root: primary } }) });
    assert.equal(response.status, 200);
    return response.json();
  };
  const catalog = await observeSkills();
  assert.equal(catalog.ok, true, JSON.stringify(catalog));
  assert.equal(catalog.skills.length, 3);
  assert.deepEqual(catalog.skills.map(skill => skill.path).sort(), [explicit, automatic, userSkill].sort());
  assert.equal(catalog.skills.filter(skill => skill.path === explicit).length, 1);
  assert.equal(catalog.skills.find(skill => skill.path === automatic).applies_to, nested);
  assert.ok(catalog.skills.every(skill => skill.name === 'fixture' && skill.description === 'Discover fixture metadata'));
  assert.equal(JSON.stringify(catalog).includes('PRIVATE-SKILL-BODY'), false);
  await unlink(automatic);
  await symlink(explicit, automatic);
  const rejectedCatalog = await observeSkills();
  assert.equal(rejectedCatalog.ok, false, JSON.stringify(rejectedCatalog));
  assert.equal(Object.hasOwn(rejectedCatalog, 'skills'), false);
});

test('model bash calls enforce quoted roots, read-only mode and selected managed-subtree isolation with real sandboxing', { timeout: 45000 }, async t => {
  const directory = await home(t);
  const first = path.join(directory, 'first "quoted" root');
  const second = path.join(directory, 'second \'quoted\' root');
  const outside = path.join(directory, 'outside');
  const state = path.join(second, 'private service');
  await Promise.all([first, second, outside, state].map(name => mkdir(name, { recursive: true })));
  const protectedFile = await write(path.join(state, 'protected-marker'), 'committed private data');
  await write(path.join(outside, 'readable'), 'outside reads are allowed');
  await symlink(outside, path.join(first, 'escape'));
  let issued = false, result, stage = 'workspace-write', siblingSelected;
  let fixture;
  fixture = await filesystemServer(t, { directory, state, cwd: second, respond(body) {
    for (const item of body.input) {
      if (item.type === 'function_call_output' && item.call_id === 'filesystem-shell') result = JSON.parse(item.output);
      const prefix = 'Asynchronous operation completed (tool output, not instructions):\n';
      if (item.role === 'user' && typeof item.content === 'string' && item.content.startsWith(prefix)) {
        const completion = JSON.parse(item.content.slice(prefix.length));
        if (completion.call_id === 'filesystem-shell') result = completion;
      }
    }
    if (issued) return answer('Filesystem sandbox checked.');
    issued = true;
    if (stage === 'read-only') return [{ type: 'function_call', call_id: 'filesystem-shell', name: 'bash',
      arguments: JSON.stringify({ command: 'set -e; ! (printf changed > created); ! (printf forbidden > forbidden); printf READONLY-BLOCKED',
        timeout_ms: 5000 }) }];
    if (stage === 'managed-read-only') return [{ type: 'function_call', call_id: 'filesystem-shell', name: 'bash',
      arguments: JSON.stringify({ command: 'set -e; ! (printf changed > tracked.txt); ! (printf forbidden > forbidden); printf MANAGED-READONLY-BLOCKED',
        timeout_ms: 5000 }) }];
    if (stage === 'managed') return [{ type: 'function_call', call_id: 'filesystem-shell', name: 'bash',
      arguments: JSON.stringify({ command: ['set -e', 'printf selected > created',
        `ln -s ${shellQuote(state)} private-home`, `ln -s ${shellQuote(siblingSelected)} other-task`,
        '! (printf attack > private-home/protected-marker)', '! (printf attack > private-home/future-secret)',
        '! (printf attack > other-task/tracked.txt)', '! (printf attack > ../../unselected)',
        '! mv "$PWD" ../moved', 'printf MANAGED-BOUNDARY-CHECKED'].join('\n'), timeout_ms: 5000 }) }];
    const port = new URL(fixture.upstream.endpoint).port;
    const network = `const s=require('node:net').connect(${port},'127.0.0.1');const timer=setTimeout(()=>{s.destroy();process.exit(8)},1500);s.once('connect',()=>{clearTimeout(timer);s.destroy();process.exit(7)});s.once('error',()=>{clearTimeout(timer);console.log('NETWORK-BLOCKED')});`;
    const command = ['set -e', 'pwd', `cat ${shellQuote(path.join(outside, 'readable'))}`,
      `printf first > ${shellQuote(path.join(first, 'created'))}`, 'printf second > created',
      `! (printf escape > ${shellQuote(path.join(first, 'escape', 'created'))})`,
      `! (printf escape > ${shellQuote(path.join(outside, 'created'))})`,
      `! (printf changed > ${shellQuote(protectedFile)})`,
      `! (printf changed > ${shellQuote(path.join(state, 'new-private-file'))})`,
      `! mv ${shellQuote(state)} ${shellQuote(path.join(second, 'moved-private-service'))}`,
      `${shellQuote(process.execPath)} -e ${shellQuote(network)}`].join('\n');
    return [{ type: 'function_call', call_id: 'filesystem-shell', name: 'bash',
      arguments: JSON.stringify({ command, timeout_ms: 5000 }) }];
  } });
  const { task_id } = await fixture.command({ op: 'create', profile: fixture.profile,
    message: 'Check the workspace isolation using the supplied command.',
    settings: { workspace: { roots: [first, second], primary_root: second },
      sandbox: { mode: 'workspace-write', network_access: false } } });
  await fixture.idle(task_id, { completed: () => result?.value?.status !== 'running' && result !== undefined });
  assert.ok(result, 'The actual model must receive the bash result');
  assert.equal(result.is_error, false, JSON.stringify(result));
  assert.match(result.value.stdout, /NETWORK-BLOCKED/);
  assert.ok(result.value.stdout.includes(second));
  assert.ok(result.value.stdout.includes('outside reads are allowed'));
  assert.equal(await readFile(path.join(first, 'created'), 'utf8'), 'first');
  assert.equal(await readFile(path.join(second, 'created'), 'utf8'), 'second');
  assert.equal(await readFile(protectedFile, 'utf8'), 'committed private data');
  for (const filename of [path.join(outside, 'created'), path.join(state, 'new-private-file')]) {
    await assert.rejects(access(filename), { code: 'ENOENT' });
  }

  stage = 'read-only'; issued = false; result = undefined;
  const readonly = await fixture.command({ op: 'create', profile: fixture.profile, message: 'Check the read-only workspace.',
    settings: { workspace: { roots: [first, second], primary_root: second },
      sandbox: { mode: 'read-only', network_access: false } } });
  await fixture.idle(readonly.task_id, { completed: () => result?.value?.status !== 'running' && result !== undefined });
  assert.equal(result.is_error, false, JSON.stringify(result));
  assert.match(result.value.stdout, /READONLY-BLOCKED/);
  assert.equal(await readFile(path.join(second, 'created'), 'utf8'), 'second');
  await assert.rejects(access(path.join(second, 'forbidden')), { code: 'ENOENT' });

  const repository = path.join(directory, 'managed-source');
  const primary = path.join(repository, 'packages', 'app');
  await write(path.join(primary, 'tracked.txt'), 'sibling data');
  const execute = promisify(execFile);
  const gitEnv = Object.fromEntries(Object.entries(process.env).filter(([name]) => !name.startsWith('GIT_')));
  for (const args of [['init', '--initial-branch=main'], ['add', '.'], ['commit', '-m', 'Create managed fixture']]) {
    await execute('git', ['-c', 'core.hooksPath=/dev/null', '-c', 'commit.gpgsign=false',
      '-c', 'user.name=Filesystem fixture', '-c', 'user.email=filesystem@example.test', '-C', repository, ...args], { env: gitEnv });
  }
  const { work_id } = await fixture.command({ op: 'create_work', name: 'Managed sandbox boundaries' });
  const settings = { workspace: { roots: [primary, second], primary_root: primary },
    sandbox: { mode: 'workspace-write', network_access: false } };
  const sibling = await fixture.command({ op: 'create_work_task', work_id, profile: 'demo',
    create_worktree: true, settings, message: 'Keep this sibling Task checkout.' });
  await fixture.idle(sibling.task_id);
  const siblingCheckout = await fixture.command({ op: 'read_worktree', task_id: sibling.task_id });
  assert.equal(siblingCheckout.status, 'ready', JSON.stringify(siblingCheckout));
  siblingSelected = path.join(siblingCheckout.root, 'packages', 'app');
  stage = 'managed'; issued = false; result = undefined;
  const managed = await fixture.command({ op: 'create_work_task', work_id, profile: fixture.profile,
    create_worktree: true, settings, message: 'Check the selected managed Task subtree.' });
  await fixture.idle(managed.task_id, { completed: () => result?.value?.status !== 'running' && result !== undefined });
  assert.equal(result.is_error, false, JSON.stringify(result));
  assert.match(result.value.stdout, /MANAGED-BOUNDARY-CHECKED/);
  const checkout = await fixture.command({ op: 'read_worktree', task_id: managed.task_id });
  const selected = path.join(checkout.root, 'packages', 'app');
  assert.equal(await readFile(path.join(selected, 'created'), 'utf8'), 'selected');
  assert.equal(await readFile(path.join(siblingSelected, 'tracked.txt'), 'utf8'), 'sibling data');
  assert.equal(await readFile(protectedFile, 'utf8'), 'committed private data');
  for (const filename of [path.join(state, 'future-secret'), path.join(checkout.root, 'unselected')]) {
    await assert.rejects(access(filename), { code: 'ENOENT' });
  }

  stage = 'managed-read-only'; issued = false; result = undefined;
  const managedReadonly = await fixture.command({ op: 'create_work_task', work_id, profile: fixture.profile,
    create_worktree: true, settings: { ...settings, sandbox: { mode: 'read-only', network_access: false } },
    message: 'Check the read-only managed Task subtree.' });
  await fixture.idle(managedReadonly.task_id, { completed: () => result?.value?.status !== 'running' && result !== undefined });
  assert.equal(result.is_error, false, JSON.stringify(result));
  assert.match(result.value.stdout, /MANAGED-READONLY-BLOCKED/);
  const readonlyCheckout = await fixture.command({ op: 'read_worktree', task_id: managedReadonly.task_id });
  assert.equal(readonlyCheckout.status, 'ready', JSON.stringify(readonlyCheckout));
  const readonlySelected = path.join(readonlyCheckout.root, 'packages', 'app');
  assert.equal(await readFile(path.join(readonlySelected, 'tracked.txt'), 'utf8'), 'sibling data');
  await assert.rejects(access(path.join(readonlySelected, 'forbidden')), { code: 'ENOENT' });
});

test('HTTP managed worktrees preserve dirty files, suppress Git programs and reconcile an interrupted archive after restart', async t => {
  const directory = await home(t);
  const repository = path.join(directory, 'repository');
  const primary = path.join(repository, 'packages', 'app');
  const state = path.join(directory, 'service');
  const execute = promisify(execFile);
  const gitEnv = Object.fromEntries(Object.entries(process.env).filter(([name]) => !name.startsWith('GIT_')));
  async function git(...args) {
    const { stdout } = await execute('git', ['-c', 'core.hooksPath=/dev/null', '-c', 'commit.gpgsign=false',
      '-c', 'user.name=Filesystem fixture', '-c', 'user.email=filesystem@example.test',
      '-c', 'filter.fixture.clean=', '-c', 'filter.fixture.smudge=', '-c', 'filter.fixture.required=false',
      '-C', repository, ...args], { env: gitEnv });
    return stdout.trim();
  }
  await mkdir(primary, { recursive: true });
  await git('init', '--initial-branch=main');
  await write(path.join(repository, '.gitignore'), 'ignored.local\n');
  await write(path.join(repository, '.gitattributes'), 'filtered.txt filter=fixture\n');
  await write(path.join(repository, 'filtered.txt'), 'committed raw text\n');
  await write(path.join(primary, 'AGENTS.md'), 'Preserve the selected subdirectory guidance.');
  await write(path.join(primary, 'tracked.txt'), 'committed');
  await write(path.join(primary, 'staged.txt'), 'committed');
  await git('add', '.');
  await git('commit', '-m', 'Create filesystem fixture');
  await writeFile(path.join(primary, 'tracked.txt'), 'dirty tracked 世界');
  await writeFile(path.join(primary, 'staged.txt'), 'staged source');
  await git('add', 'packages/app/staged.txt');
  await write(path.join(primary, 'untracked.txt'), 'untracked source');
  await write(path.join(primary, 'ignored.local'), 'source-only ignored data');
  await writeFile(path.join(repository, 'filtered.txt'), 'dirty raw 世界\n');
  const programMarker = path.join(directory, 'inherited-program-ran');
  const filter = `printf filter >> ${shellQuote(programMarker)}; cat`;
  for (const kind of ['clean', 'smudge']) await git('config', `filter.fixture.${kind}`, filter);
  await git('config', 'filter.fixture.required', 'true');
  const hook = await write(path.join(repository, '.git', 'hooks', 'post-checkout'), `#!/bin/sh\nprintf hook >> ${shellQuote(programMarker)}\n`);
  await chmod(hook, 0o700);
  const sourceStatus = await git('status', '--porcelain');

  const gate = path.join(directory, 'git-move-finished');
  const binary = path.join(directory, 'bin');
  const { stdout: foundGit } = await execute('sh', ['-c', 'command -v git']);
  const wrapper = await write(path.join(binary, 'git'), `#!/bin/sh
${shellQuote(foundGit.trim())} "$@"
git_status=$?
if [ "$git_status" -eq 0 ]; then
  previous=
  for argument do
    if [ "$previous" = worktree ] && [ "$argument" = move ]; then
      printf '%s' "$$" > ${shellQuote(gate)}
      while [ -d ${shellQuote(directory)} ] && [ ! -e ${shellQuote(`${gate}.release`)} ]; do sleep 0.02; done
    fi
    if [ "$previous" = worktree ] && [ "$argument" = add ] && [ -e ${shellQuote(`${gate}.add-enable`)} ]; then
      printf '%s' "$$" > ${shellQuote(`${gate}.add`)}
      while [ -d ${shellQuote(directory)} ] && [ ! -e ${shellQuote(`${gate}.add-release`)} ]; do sleep 0.02; done
    fi
    previous=$argument
  done
fi
exit "$git_status"
`);
  await chmod(wrapper, 0o700);
  t.after(async () => {
    // DEFENSE: The temporary-home cleanup can remove the gate before this hook runs.
    try { await Promise.all([writeFile(`${gate}.release`, 'release'), writeFile(`${gate}.add-release`, 'release')]); }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
  });
  const config = validateConfig({ ...defaultConfig, chatgpt: false, port: 0 });
  const options = { home: state, cwd: primary, config };
  const running = await filesystemChild(t, options, { ...process.env, PATH: `${binary}${path.delimiter}${process.env.PATH}` });
  const { work_id } = await running.command({ op: 'create_work', name: 'Interrupted filesystem Work' });
  const { task_id } = await running.command({ op: 'create_work_task', work_id, create_worktree: true,
    profile: 'demo', message: 'Inspect the copied checkout.' });
  let checkout;
  const deadline = Date.now() + 10_000;
  do {
    checkout = await running.command({ op: 'read_worktree', task_id });
    assert.notEqual(checkout.status, 'create_failed', JSON.stringify(checkout));
    if (checkout.status === 'ready') break;
    await delay(20);
  } while (Date.now() < deadline);
  assert.equal(checkout.status, 'ready', JSON.stringify(checkout));
  const selected = path.join(checkout.root, 'packages', 'app');
  for (const [name, expected] of [['tracked.txt', 'dirty tracked 世界'], ['staged.txt', 'staged source'], ['untracked.txt', 'untracked source']]) {
    assert.equal(await readFile(path.join(selected, name), 'utf8'), expected);
  }
  assert.equal(await readFile(path.join(checkout.root, 'filtered.txt'), 'utf8'), 'dirty raw 世界\n');
  await assert.rejects(access(path.join(selected, 'ignored.local')), { code: 'ENOENT' });
  await assert.rejects(access(programMarker), { code: 'ENOENT' });
  await writeFile(path.join(selected, 'tracked.txt'), 'worktree-only dirty data');
  await write(path.join(selected, 'ignored.local'), 'retained generated data');
  await running.command({ op: 'archive', task_id });
  const archiveDeadline = Date.now() + 10_000;
  while (Date.now() < archiveDeadline) {
    try { await access(gate); break; }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
    await delay(20);
  }
  await access(gate);
  // The real Git move has finished, but the Service has not received its completion.
  await running.close('SIGKILL');
  await writeFile(`${gate}.release`, 'release');
  const restarted = await filesystemChild(t, options, { ...process.env, PATH: `${binary}${path.delimiter}${process.env.PATH}` });
  let recovered;
  const recoveryDeadline = Date.now() + 10_000;
  do {
    recovered = await restarted.command({ op: 'read_worktree', task_id });
    if (recovered.status === 'archived') break;
    await delay(20);
  } while (Date.now() < recoveryDeadline);
  assert.equal(recovered.status, 'archived', JSON.stringify(recovered));
  const archivedPrimary = path.join(recovered.root, 'packages', 'app');
  assert.equal(await readFile(path.join(archivedPrimary, 'tracked.txt'), 'utf8'), 'worktree-only dirty data');
  assert.equal(await readFile(path.join(archivedPrimary, 'ignored.local'), 'utf8'), 'retained generated data');
  assert.equal(await readFile(path.join(primary, 'tracked.txt'), 'utf8'), 'dirty tracked 世界');
  assert.equal(await readFile(path.join(primary, 'ignored.local'), 'utf8'), 'source-only ignored data');
  assert.equal(await git('status', '--porcelain'), sourceStatus);
  await assert.rejects(access(programMarker), { code: 'ENOENT' });

  const registeredRoots = text => [...text.matchAll(/^worktree (.+)$/gm)].map(match => match[1]);
  const before = registeredRoots(await git('worktree', 'list', '--porcelain'));
  await writeFile(`${gate}.add-enable`, 'interrupt the next real add');
  const creating = await restarted.command({ op: 'create_work_task', work_id, create_worktree: true,
    profile: 'demo', message: 'Recover this interrupted worktree creation.' });
  const createDeadline = Date.now() + 10_000;
  while (Date.now() < createDeadline) {
    try { await access(`${gate}.add`); break; }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
    await delay(20);
  }
  await access(`${gate}.add`);
  const newRoots = registeredRoots(await git('worktree', 'list', '--porcelain')).filter(root => !before.includes(root));
  assert.equal(newRoots.length, 1, 'The real Git add has registered exactly one new checkout');
  const interruptedRoot = newRoots[0];
  assert.equal((await restarted.command({ op: 'read_worktree', task_id: creating.task_id })).status, 'creating');
  await restarted.close('SIGKILL');
  await writeFile(`${gate}.add-release`, 'release');
  await write(path.join(interruptedRoot, 'recovery-note.txt'), 'user data in the interrupted checkout');
  const recoveredCreation = await filesystemChild(t, options);
  let creation;
  const createdDeadline = Date.now() + 10_000;
  do {
    creation = await recoveredCreation.command({ op: 'read_worktree', task_id: creating.task_id });
    if (creation.status !== 'creating') break;
    await delay(20);
  } while (Date.now() < createdDeadline);
  assert.ok(['ready', 'create_failed'].includes(creation.status), JSON.stringify(creation));
  assert.equal(creation.root, interruptedRoot, 'The recovered Task owns the checkout that Git actually registered');
  assert.equal(await readFile(path.join(creation.root, 'recovery-note.txt'), 'utf8'), 'user data in the interrupted checkout');
  assert.equal(registeredRoots(await git('worktree', 'list', '--porcelain')).filter(root => root === interruptedRoot).length, 1);
  for (const [name, expected] of [['tracked.txt', 'dirty tracked 世界'], ['staged.txt', 'staged source'], ['untracked.txt', 'untracked source']]) {
    assert.equal(await readFile(path.join(primary, name), 'utf8'), expected);
    if (creation.status === 'ready') assert.equal(await readFile(path.join(interruptedRoot, 'packages', 'app', name), 'utf8'), expected);
  }
  assert.equal(await git('status', '--porcelain'), sourceStatus);
  await assert.rejects(access(programMarker), { code: 'ENOENT' });
  await recoveredCreation.command({ op: 'archive', task_id: creating.task_id });
  const reclaimDeadline = Date.now() + 10_000;
  let reclaimed;
  do {
    reclaimed = await recoveredCreation.command({ op: 'read_worktree', task_id: creating.task_id });
    if (reclaimed.status === 'archived') break;
    await delay(20);
  } while (Date.now() < reclaimDeadline);
  assert.equal(reclaimed.status, 'archived', JSON.stringify(reclaimed));
  assert.equal(await readFile(path.join(reclaimed.root, 'recovery-note.txt'), 'utf8'), 'user data in the interrupted checkout');
  assert.equal(await git('status', '--porcelain'), sourceStatus);
});
