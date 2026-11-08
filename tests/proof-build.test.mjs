import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { cp, mkdir, stat, symlink, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { home, shellQuote } from './support.mjs';

const execute = promisify(execFile);
const root = fileURLToPath(new URL('../', import.meta.url));

test('a focused proof build works without JavaScript extraction dependencies', { timeout: 120000 }, async t => {
  const directory = await home(t), checkout = path.join(directory, 'source'), bin = path.join(directory, 'bin');
  const listed = await execute('git', ['ls-files', '-z', '--cached', '--others', '--exclude-standard'], { cwd: root });
  await Promise.all(listed.stdout.split('\0').filter(Boolean).map(async filename => {
    const target = path.join(checkout, filename);
    await mkdir(path.dirname(target), { recursive: true });
    await cp(path.join(root, filename), target, { verbatimSymlinks: true });
  }));
  await symlink(path.join(root, 'node_modules'), path.join(checkout, 'node_modules'), 'dir');
  await mkdir(bin);
  const available = ['bun', 'rocq', 'coqdep', 'opam', 'ocamlc', 'ocamlopt', 'ocamlfind']
    .map(name => [name, Bun.which(name)]).filter(([, executable]) => executable !== null);
  assert.ok(available.some(([name]) => name === 'rocq'), 'This scenario requires the real Rocq compiler');
  // Wrappers preserve each real installation prefix while exposing no JavaScript compiler on PATH.
  await Promise.all(available.map(([name, executable]) => writeFile(path.join(bin, name),
    `#!/bin/sh\nexec ${shellQuote(executable)} "$@"\n`, { mode: 0o755 })));
  assert.equal(Bun.which('js_of_ocaml', { PATH: bin }), null);
  await execute(process.execPath, [path.join(checkout, 'scripts/build.mjs'), '--module', 'Requirements.Engineering'], {
    cwd: checkout, env: { ...process.env, PATH: bin }, timeout: 90000,
  });
  assert.ok((await stat(path.join(checkout, 'requirements/Engineering.vo'))).size > 0,
    'The public command must compile the selected real requirement in the clean checkout');
});
