import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdir, readFile, realpath, symlink, writeFile, access } from 'node:fs/promises';
import path from 'node:path';
import { runBash } from '../host/process.mjs';
import { home, shellQuote } from './support.mjs';

test('the actual sandbox admits its quoted workspace roots and blocks symlink and service-state writes', async t => {
  const base = await realpath(await home(t));
  const roots = [path.join(base, 'first "quoted" root'), path.join(base, 'second')];
  const outside = path.join(base, 'outside');
  const protectedHome = path.join(roots[1], 'service');
  await Promise.all([...roots, outside].map(root => mkdir(root)));
  await mkdir(protectedHome);
  await writeFile(path.join(outside, 'readable'), 'outside read');
  await writeFile(path.join(protectedHome, 'journal'), 'committed');
  await symlink(outside, path.join(roots[0], 'escape'));
  const plan = { access: 'sandboxed', workspace: { roots, primary_root: roots[1] },
    sandbox: { mode: 'workspace-write', network_access: false } };
  const limits = { bash_timeout_ms: 3000, bash_default_output_length: 40000,
    bash_max_output_length: 65536, artifact_bytes: 1024 };
  const command = `set -e; pwd; cat ${shellQuote(path.join(outside, 'readable'))}; ` +
    `printf one > ${shellQuote(path.join(roots[0], 'one'))}; printf two > two; printf temp > "$TMPDIR/temp"; ` +
    `! (printf bad > ${shellQuote(path.join(roots[0], 'escape', 'bad'))}); ` +
    `! (printf bad > ${shellQuote(path.join(outside, 'bad'))}); ` +
    '! (printf attack > service/journal); ! mv service moved';
  const result = await runBash({ command }, limits, { execution: plan, readOnlyPaths: [protectedHome] });
  assert.equal(result.error, false, JSON.stringify(result.value));
  assert.ok(result.value.stdout.includes(roots[1]));
  assert.ok(result.value.stdout.includes('outside read'));
  assert.equal(await readFile(path.join(roots[0], 'one'), 'utf8'), 'one');
  assert.equal(await readFile(path.join(roots[1], 'two'), 'utf8'), 'two');
  assert.equal(await readFile(path.join(protectedHome, 'journal'), 'utf8'), 'committed');
  await assert.rejects(access(path.join(outside, 'bad')), { code: 'ENOENT' });
  const readonly = await runBash({ command: 'printf no > forbidden' }, limits,
    { execution: { ...plan, sandbox: { ...plan.sandbox, mode: 'read-only' } } });
  assert.equal(readonly.error, true);
  await assert.rejects(access(path.join(roots[1], 'forbidden')), { code: 'ENOENT' });

  // The private home binding must win over a broader workspace, while only
  // this task's selected managed subtree regains write access.
  const serviceHome = path.join(base, 'managed-service');
  const managedRoot = path.join(serviceHome, 'worktrees', 'task-one');
  const selected = path.join(managedRoot, 'project');
  const sibling = path.join(serviceHome, 'worktrees', 'task-two');
  await Promise.all([mkdir(selected, { recursive: true }), mkdir(sibling, { recursive: true })]);
  await writeFile(path.join(serviceHome, 'journal'), 'private state');
  await writeFile(path.join(sibling, 'owned'), 'other task');
  await symlink(serviceHome, path.join(selected, 'private-home'));
  await symlink(sibling, path.join(selected, 'other-task'));
  const managedPlan = { ...plan, workspace: { roots: [base, selected], primary_root: selected } };
  const options = { execution: managedPlan, readOnlyPaths: [serviceHome], managedWorktreeRoot: managedRoot };
  const managedCommand = 'set -e; printf selected > created; ' +
    '! (printf attack > private-home/journal); ! (printf attack > private-home/future-secret); ' +
    '! (printf attack > other-task/owned); ' +
    `! (printf attack > ${shellQuote(path.join(managedRoot, 'unselected'))}); ` +
    `! mv ${shellQuote(serviceHome)} ${shellQuote(path.join(base, 'moved'))}; ` +
    `! mv ${shellQuote(selected)} ${shellQuote(path.join(managedRoot, 'moved'))}`;
  const managed = await runBash({ command: managedCommand }, limits, options);
  assert.equal(managed.error, false, JSON.stringify(managed.value));
  assert.equal(await readFile(path.join(selected, 'created'), 'utf8'), 'selected');
  assert.equal(await readFile(path.join(serviceHome, 'journal'), 'utf8'), 'private state');
  assert.equal(await readFile(path.join(sibling, 'owned'), 'utf8'), 'other task');
  await assert.rejects(access(path.join(serviceHome, 'future-secret')), { code: 'ENOENT' });
  await assert.rejects(access(path.join(managedRoot, 'unselected')), { code: 'ENOENT' });
  const managedReadonly = await runBash({ command: 'printf attack > created' }, limits,
    { ...options, execution: { ...managedPlan, sandbox: { ...plan.sandbox, mode: 'read-only' } } });
  assert.equal(managedReadonly.error, true);
  assert.equal(await readFile(path.join(selected, 'created'), 'utf8'), 'selected');
});
