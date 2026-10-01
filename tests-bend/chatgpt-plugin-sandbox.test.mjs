import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdir, writeFile, readFile, symlink, realpath, access } from 'node:fs/promises';
import path from 'node:path';
import { prepareSandbox, seatbeltProfile } from '../host/sandbox.mjs';
import { runBash } from '../host/process.mjs';
import { home, shellQuote } from './support.mjs';

const limits = { bash_timeout_ms: 5000, bash_default_output_length: 4096, bash_max_output_length: 8192, artifact_bytes: 1024 };

test('project-scoped OS execution denies outside reads, symlink aliases, writes, credentials and service state', { timeout: 20_000 }, async t => {
  const base = await realpath(await home(t));
  const root = path.join(base, 'project "root"'), other = path.join(base, 'second'), outside = path.join(base, 'outside');
  const state = path.join(root, 'private-service');
  await Promise.all([root, other, outside].map(directory => mkdir(directory)));
  await mkdir(state);
  await writeFile(path.join(outside, 'secret'), 'OUTSIDE_SECRET');
  await writeFile(path.join(state, 'secret'), 'PRIVATE_SERVICE_SECRET');
  await symlink(outside, path.join(root, 'escape'));
  const name = 'SELVEDGE_PLUGIN_SANDBOX_CREDENTIAL';
  const previous = process.env[name];
  process.env[name] = 'DO_NOT_INHERIT_THIS_CREDENTIAL';
  t.after(() => { if (previous === undefined) delete process.env[name]; else process.env[name] = previous; });
  const plan = { access: 'sandboxed', scope: 'project', workspace: { roots: [root, other], primary_root: root },
    sandbox: { mode: 'workspace-write', network_access: false } };
  const forbidden = [path.join(outside, 'secret'), path.join(root, 'escape', 'secret'), path.join(state, 'secret')];
  if (process.platform === 'darwin') forbidden.push(`/System/Volumes/Data${path.join(outside, 'secret')}`);
  const command = `set -eu; printf local > local; printf second > ${shellQuote(path.join(other, 'second'))}; `
    + `test -z "\${${name}:-}"; printf 'cwd='; pwd; printf 'temp=%s\\n' "$TMPDIR"; `
    + forbidden.map(filename => `if cat ${shellQuote(filename)} 2>/dev/null; then exit 71; fi; `).join('')
    + `if printf bad > ${shellQuote(path.join(outside, 'bad'))}; then exit 72; fi; `
    + `if printf bad > ${shellQuote(path.join(root, 'escape', 'bad'))}; then exit 73; fi; `
    + `if printf bad > ${shellQuote(path.join(state, 'bad'))}; then exit 74; fi; printf passed`;
  const result = await runBash({ command }, limits, { execution: plan, readOnlyPaths: [state] });
  assert.equal(result.error, false, JSON.stringify(result.value));
  assert.ok(result.value.stdout.includes(root));
  assert.ok(result.value.stdout.endsWith('passed'));
  assert.ok(!/OUTSIDE_SECRET|PRIVATE_SERVICE_SECRET|DO_NOT_INHERIT/.test(result.value.stdout));
  assert.equal(await readFile(path.join(root, 'local'), 'utf8'), 'local');
  assert.equal(await readFile(path.join(other, 'second'), 'utf8'), 'second');
  await assert.rejects(access(path.join(outside, 'bad')), { code: 'ENOENT' });
  await assert.rejects(access(path.join(state, 'bad')), { code: 'ENOENT' });
  const scratch = result.value.stdout.match(/^temp=(.+)$/m)?.[1];
  assert.ok(scratch);
  await assert.rejects(access(scratch), { code: 'ENOENT' });
  await assert.rejects(prepareSandbox({ ...plan, access: 'unrestricted' }), /Malformed/);
  await assert.rejects(prepareSandbox(plan, { readOnlyPaths: [base] }), /private service home/);
  const readOnly = await runBash({ command: 'cat local; if printf bad > local; then exit 75; fi' }, limits,
    { execution: { ...plan, sandbox: { mode: 'read-only', network_access: false } }, readOnlyPaths: [state] });
  assert.equal(readOnly.error, false, JSON.stringify(readOnly.value));
  assert.equal(await readFile(path.join(root, 'local'), 'utf8'), 'local');
});

test('project Seatbelt emission never includes blanket data reads and quotes all path literals', () => {
  const profile = seatbeltProfile({ writableRoots: ['/a/"quoted"'], readableRoots: ['/a/"quoted"', '/bin'],
    scratch: '/private/tmp/scratch', readOnlyPaths: ['/a/"quoted"/state'], networkAccess: false });
  assert.ok(!profile.includes('(allow file-read*)'));
  assert.ok(profile.includes('(deny file-read* (subpath "/a/\\"quoted\\"/state"))'));
  assert.ok(!profile.includes('(allow network-outbound'));
  assert.ok(!profile.includes('(allow file-read-metadata (subpath'));
});
