import assert from 'node:assert/strict';
import test from 'node:test';
import { mkdir, readFile, realpath, symlink, writeFile, access } from 'node:fs/promises';
import path from 'node:path';
import { canonicalWorkspace, prepareSandbox, seatbeltProfile, seccompFilter } from '../host/sandbox.mjs';
import { runBash } from '../host/process.mjs';
import { home, shellQuote } from './support.mjs';

const limits = { bash_timeout_ms: 3000, bash_default_output_length: 40000,
  bash_max_output_length: 65536, artifact_bytes: 1024 };

async function fixture(t) {
  const base = await realpath(await home(t));
  const roots = [path.join(base, 'first "quoted" root'), path.join(base, 'second')];
  const outside = path.join(base, 'outside');
  await Promise.all([...roots, outside].map(root => mkdir(root)));
  await writeFile(path.join(outside, 'readable'), 'outside read');
  return { base, roots, outside, plan: { access: 'sandboxed',
    workspace: { roots, primary_root: roots[1] }, sandbox: { mode: 'workspace-write', network_access: false } } };
}

test('workspace observations resolve aliases and reject duplicate or foreign primary roots', async t => {
  const { base, roots } = await fixture(t);
  await symlink(roots[0], path.join(base, 'alias'));
  assert.deepEqual(await canonicalWorkspace({ roots, primary_root: roots[1] }), { roots, primary_root: roots[1] });
  assert.deepEqual(await canonicalWorkspace({ roots: [] }), { roots: [], primary_root: null });
  await assert.rejects(canonicalWorkspace({ roots: [roots[0], path.join(base, 'alias')] }), /distinct/);
  await assert.rejects(canonicalWorkspace({ roots, primary_root: base }), /primary root/);
  await assert.rejects(canonicalWorkspace({ roots: ['relative'] }), /absolute/);
});

test('Seatbelt paths are quoted literals and protected ancestors cannot be renamed', () => {
  const profile = seatbeltProfile({ writableRoots: ['/root/with "quotes"\\and\nlines'], scratch: '/private/tmp/safe',
    readOnlyPaths: ['/root/service/private'], networkAccess: false });
  assert.ok(profile.includes('(subpath "/root/with \\"quotes\\"\\\\and\\nlines")'));
  assert.ok(profile.includes('(deny file-write* (subpath "/root/service/private"))'));
  assert.ok(profile.includes('(deny file-write-unlink (literal "/root/service"))'));
  assert.ok(!profile.includes('(allow network-outbound'));
});

// This checks the emitted BPF/ABI boundary, not a replacement for kernel isolation tests.
function evaluate(filter, { architecture, syscall, argument = 0 }) {
  const data = Buffer.alloc(64);
  data.writeUInt32LE(syscall >>> 0, 0);
  data.writeUInt32LE(architecture >>> 0, 4);
  data.writeUInt32LE(argument >>> 0, 16);
  let accumulator = 0;
  for (let pc = 0; pc < filter.length / 8; pc++) {
    const offset = pc * 8;
    const code = filter.readUInt16LE(offset);
    const jt = filter[offset + 2];
    const jf = filter[offset + 3];
    const value = filter.readUInt32LE(offset + 4);
    if (code === 0x20) accumulator = data.readUInt32LE(value);
    else if (code === 0x15) pc += accumulator === value ? jt : jf;
    else if (code === 0x35) pc += accumulator >= value ? jt : jf;
    else if (code === 0x45) pc += (accumulator & value) !== 0 ? jt : jf;
    else if (code === 0x06) return value;
    else assert.fail(`Unknown BPF instruction ${code}`);
  }
  assert.fail('Filter has no return instruction');
}

test('Linux seccomp rejects ABI switches, host Unix sockets and namespace creation on both supported architectures', () => {
  const deny = 0x00050001;
  const allow = 0x7fff0000;
  for (const [arch, audit, socket, clone, write, ptrace] of [
    ['x64', 0xc000003e, 41, 56, 1, 101], ['arm64', 0xc00000b7, 198, 220, 64, 117],
  ]) {
    for (const network of [true, false]) {
      const filter = seccompFilter(arch, network);
      const run = (syscall, argument = 0) => evaluate(filter, { architecture: audit, syscall, argument });
      assert.equal(run(write), allow);
      assert.equal(run(ptrace), deny);
      assert.equal(run(435), 0x00050026);
      assert.equal(run(clone, 0x10000000), deny);
      assert.equal(run(clone, 17), allow);
      assert.equal(run(socket, 1), deny);
      assert.equal(run(socket, 2), network ? allow : deny);
      assert.equal(run(socket, 10), network ? allow : deny);
      assert.equal(evaluate(filter, { architecture: 0, syscall: write }), 0x80000000);
      if (arch === 'x64') assert.equal(run(write + 0x40000000), deny);
    }
  }
  assert.throws(() => seccompFilter('unknown', false), /architecture/);
});

test('unsupported hosts and changed roots fail closed before process creation', async t => {
  const { base, plan, roots } = await fixture(t);
  await assert.rejects(prepareSandbox(plan, { platform: 'win32' }), /Linux and macOS/);
  await symlink(roots[0], path.join(base, 'alias'));
  await assert.rejects(prepareSandbox({ ...plan, workspace: { roots: [path.join(base, 'alias')], primary_root: path.join(base, 'alias') } }), /changed after/);
});

test('OS sandbox writes both roots, uses the primary cwd, reads outside and blocks traversal and symlink writes', async t => {
  const { roots, outside, plan } = await fixture(t);
  await symlink(outside, path.join(roots[0], 'escape'));
  const result = await runBash({ command: `pwd; cat ${shellQuote(path.join(outside, 'readable'))}; ` +
    `printf one > ${shellQuote(path.join(roots[0], 'one'))}; printf two > two; ` +
    `printf temp > "$TMPDIR/temp"; ` +
    `! (printf bad > ${shellQuote(path.join(roots[0], 'escape', 'bad'))}); ` +
    `! (printf bad > ${shellQuote(path.join(outside, 'bad'))})` }, limits, { execution: plan });
  assert.equal(result.error, false, JSON.stringify(result.value));
  assert.ok(result.value.stdout.includes(roots[1]));
  assert.ok(result.value.stdout.includes('outside read'));
  assert.equal(await readFile(path.join(roots[0], 'one'), 'utf8'), 'one');
  assert.equal(await readFile(path.join(roots[1], 'two'), 'utf8'), 'two');
  await assert.rejects(access(path.join(outside, 'bad')), { code: 'ENOENT' });
});

test('read-only workspace is enforced while an explicit unrestricted grant can write outside', async t => {
  const { roots, outside, plan } = await fixture(t);
  const readonly = await runBash({ command: 'printf no > forbidden' }, limits, {
    execution: { ...plan, sandbox: { ...plan.sandbox, mode: 'read-only' } },
  });
  assert.equal(readonly.error, true);
  await assert.rejects(access(path.join(roots[1], 'forbidden')), { code: 'ENOENT' });
  const allowed = await runBash({ command: `printf granted > ${shellQuote(path.join(outside, 'allowed'))}` }, limits, {
    execution: { ...plan, access: 'unrestricted' },
  });
  assert.equal(allowed.error, false, JSON.stringify(allowed.value));
  assert.equal(await readFile(path.join(outside, 'allowed'), 'utf8'), 'granted');
});

test('the service journal subtree stays read-only even when a workspace contains it', async t => {
  const { roots, plan } = await fixture(t);
  const protectedHome = path.join(roots[1], 'service');
  await mkdir(protectedHome);
  await writeFile(path.join(protectedHome, 'journal'), 'committed');
  const result = await runBash({ command: 'printf attack > service/journal; mv service moved' }, limits,
    { execution: plan, readOnlyPaths: [protectedHome] });
  assert.equal(result.error, true);
  assert.equal(await readFile(path.join(protectedHome, 'journal'), 'utf8'), 'committed');
});
