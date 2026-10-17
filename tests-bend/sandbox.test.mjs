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
});
