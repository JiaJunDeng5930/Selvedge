import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, writeFile, rm, symlink, unlink, mkdir, cp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { spawnSync } from 'node:child_process';
import { compileJavaScript, compileJavaScriptBatch } from '../scripts/compile-javascript.mjs';
import { compiledFixture } from './compiler-support.mjs';

function executeLibrary(filename, exported = 'run', argument) {
  // A fresh runtime also avoids Bun retaining an overwritten module in its loader cache.
  const child = spawnSync(process.execPath, ['--eval', `import library from ${JSON.stringify(pathToFileURL(filename).href)}; console.log(JSON.stringify({ value: library[${JSON.stringify(exported)}](${argument === undefined ? '' : JSON.stringify(argument)}).toString(), exports: Object.keys(library) }));`], { encoding: 'utf8' });
  assert.equal(child.status, 0, child.stderr);
  return JSON.parse(child.stdout);
}

// Cache evidence is generated execution, including mutations that must change it.
test('JavaScript compilation reuses exact inputs and executes changed dependency closures', { timeout: 180_000 }, async t => {
  const directory = await mkdtemp(path.join(tmpdir(), 'selvedge-javascript-cache-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const entry = path.join(directory, 'entry.bend');
  const dependency = path.join(directory, 'dependency.bend');
  const output = path.join(directory, 'compiled.mjs');
  const request = { entry, output, sourceRoot: directory, exports: { run: 'run' } };
  const source = 'import Base\nimport ./dependency.bend as Dependency\n\ndef run() -> Nat:\n  Dependency.value()\n';
  const number = value => `import Base\n\ndef value() -> Nat:\n  ${value}n\n`;
  async function execute(expected, cached, options = request) {
    const result = await compileJavaScript(options);
    assert.equal(result.cached, cached);
    assert.equal(executeLibrary(options.output).value, String(expected));
    return result;
  }
  await writeFile(entry, source);
  await writeFile(dependency, number(3));
  const first = await execute(3, false);
  assert.equal((await execute(3, true)).fingerprint, first.fingerprint);

  await writeFile(dependency, number(7));
  await execute(7, false);
  await execute(7, true);

  const added = path.join(directory, 'added.bend');
  await writeFile(added, number(11));
  await writeFile(entry, source.replace('import Base', 'import Base\nimport ./added.bend as Added').replace('Dependency.value()', 'Nat.add(Dependency.value(), Added.value())'));
  await execute(18, false);
  await writeFile(added, number(13));
  await execute(20, false);
  await writeFile(entry, source);
  await unlink(added);
  await execute(7, false);

  // A retargeted symlink is a different compiler input even if the old file survives.
  const alternative = path.join(directory, 'alternative.bend');
  await writeFile(alternative, number(19));
  const link = path.join(directory, 'selected.bend');
  await symlink(dependency, link);
  await writeFile(entry, source.replace('./dependency.bend', './selected.bend'));
  await execute(7, false);
  await unlink(link);
  await symlink(alternative, link);
  await execute(19, false);

  await writeFile(output, 'export const run = () => -1n;\n');
  await execute(19, false);
  const metadata = `${output}.json`;
  await writeFile(metadata, '{broken');
  await execute(19, false);
  for (const mutate of [
    manifest => { manifest.compiler.version = 'different'; },
    manifest => { manifest.compiler.runtime.version = 'different'; },
    manifest => { manifest.compiler.runtime.sha256 = 'different'; },
    manifest => { manifest.compiler.driverSha256 = 'different'; },
    manifest => { manifest.compiler.optimizerSha256 = 'different'; },
    manifest => { manifest.compiler.modulesSha256 = 'different'; },
    manifest => { manifest.compiler.parserSha256 = 'different'; },
    manifest => { manifest.compiler.sourceSha256 = 'different'; },
    manifest => { manifest.compiler.adapterSha256 = 'different'; },
    manifest => { manifest.compiler.transpiler.sha256 = 'different'; },
    manifest => { manifest.sources = []; },
    manifest => { manifest.exports = { other: 'run' }; },
    manifest => { manifest.sourceRoot = '/different'; },
  ]) {
    const manifest = JSON.parse(await readFile(metadata, 'utf8'));
    mutate(manifest);
    await writeFile(metadata, JSON.stringify(manifest));
    await execute(19, false);
  }

  const renamed = { ...request, exports: { current: 'run' } };
  const changedExports = await compileJavaScript(renamed);
  assert.equal(changedExports.cached, false);
  const renamedLibrary = executeLibrary(output, 'current');
  assert.equal(renamedLibrary.value, '19');
  assert.deepEqual(renamedLibrary.exports, ['current']);

  const copy = path.join(directory, 'copy');
  await mkdir(copy);
  await writeFile(path.join(copy, 'dependency.bend'), number(23));
  await writeFile(path.join(copy, 'entry.bend'), source);
  await cp(output, path.join(copy, 'compiled.mjs'));
  await cp(metadata, path.join(copy, 'compiled.mjs.json'));
  await execute(23, false, { ...request, entry: path.join(copy, 'entry.bend'), output: path.join(copy, 'compiled.mjs'), sourceRoot: copy });
});

test('compiled fixtures execute changed code in the same test process', { timeout: 30_000 }, async () => {
  const source = value => `import Base\n\ndef run() -> Nat:\n  ${value}n\n`;
  const first = await compiledFixture('cache-execution', source(3), { run: 'run' });
  const changed = await compiledFixture('cache-execution', source(7), { run: 'run' });
  const restored = await compiledFixture('cache-execution', source(3), { run: 'run' });
  assert.equal(first.run(), 3n);
  assert.equal(changed.run(), 7n);
  assert.equal(restored.run(), 3n);
});

test('shared checked prefixes retain independent entry execution and invalidate every affected artifact', { timeout: 180_000 }, async t => {
  const directory = await mkdtemp(path.join(tmpdir(), 'selvedge-javascript-prefix-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const prefix = path.join(directory, 'prefix.bend');
  const provider = path.join(directory, 'provider.bend');
  await writeFile(path.join(directory, 'contract.bend'), 'import Base\n\nlaw value:\n  Nat\n');
  const implementation = value => `import Base\nimport ./contract.bend as Contract\n\ndef Contract.value():\n  ${value}n\n`;
  await writeFile(provider, implementation(3));
  const prefixSource = offset => `import Base\nimport ./provider.bend as Provider\n\ndef offset() -> Nat:\n  ${offset}n\n`;
  await writeFile(prefix, prefixSource(2));
  const requests = [];
  for (const [name, expression] of [['first', 'Contract.value()'], ['second', 'Nat.add(Contract.value(), Prefix.offset())']]) {
    const entry = path.join(directory, `${name}.bend`);
    await writeFile(entry, `import Base\nimport ./contract.bend as Contract\n${name === 'second' ? 'import ./prefix.bend as Prefix\n' : ''}\ndef run() -> Nat:\n  ${expression}\n`);
    requests.push({ entry, sourceRoot: directory, output: path.join(directory, `${name}.mjs`), exports: { run: 'run' } });
  }
  const compile = () => compileJavaScriptBatch({ prefix, requests });
  const values = () => requests.map(request => executeLibrary(request.output).value);
  const first = await compile();
  assert.deepEqual(first.map(result => result.cached), [false, false]);
  assert.deepEqual(values(), ['3', '5']);
  assert.deepEqual((await compile()).map(result => result.cached), [true, true]);
  assert.equal((await compileJavaScript(requests[0])).cached, true);
  const metadata = `${requests[0].output}.json`;
  const manifest = JSON.parse(await readFile(metadata, 'utf8'));
  assert.equal(manifest.checkedPrefix, 'prefix.bend');
  assert.deepEqual(manifest.jointEntries, ['first.bend', 'second.bend']);
  assert.ok(manifest.sources.some(source => path.resolve(source.path).endsWith('/provider.bend')));
  manifest.checkedPrefix = '../prefix.bend';
  await writeFile(metadata, JSON.stringify(manifest));
  assert.deepEqual((await compile()).map(result => result.cached), [false, true]);
  assert.deepEqual(values(), ['3', '5']);
  await writeFile(provider, implementation(7));
  const changed = await compile();
  assert.deepEqual(changed.map(result => result.cached), [false, false]);
  assert.ok(changed.every((result, index) => result.fingerprint !== first[index].fingerprint));
  assert.deepEqual(values(), ['7', '9']);
  await writeFile(prefix, prefixSource(11));
  assert.deepEqual((await compile()).map(result => result.cached), [false, false]);
  assert.deepEqual(values(), ['7', '18']);
});

test('joint modules execute separate recursive and higher-order entry functions, and preserve public constructors', { timeout: 180_000 }, async t => {
  const directory = await mkdtemp(path.join(tmpdir(), 'selvedge-javascript-joint-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const prefix = path.join(directory, 'prefix.bend');
  await writeFile(prefix, 'import Base\n');
  await writeFile(path.join(directory, 'shared.bend'), `import Base

def sum(values: +List<Nat>) -> Nat:
  match values:
    case Nil{}: 0n
    case Con{head, tail}: Nat.add(head, sum(tail))

def apply(operation: Nat -> Nat, value: Nat) -> Nat:
  operation(value)
`);
  const source = (offset, value) => `import Base
import ./shared.bend as Shared

def helper(value: Nat) -> Nat:
  Nat.add(value, ${offset}n)

def run(value: Nat) -> Nat:
  Shared.apply(helper, Shared.sum([value, ${value}n, 3n]))
`;
  const requests = ['first', 'second'].map(name => ({ entry: path.join(directory, `${name}.bend`),
    output: path.join(directory, `${name}.mjs`), sourceRoot: directory, exports: { run: 'run', increment: 'helper' } }));
  await writeFile(requests[0].entry, source(1, 2));
  await writeFile(requests[1].entry, source(10, 2));
  const compile = () => compileJavaScriptBatch({ prefix, requests });
  assert.deepEqual((await compile()).map(result => result.cached), [false, false]);
  for (const [index, expected] of [8, 17].entries()) {
    assert.deepEqual(executeLibrary(requests[index].output, 'run', 2), { value: String(expected), exports: ['increment', 'run'] });
    assert.equal(executeLibrary(requests[index].output, 'increment', 2).value, String(index ? 12 : 3));
    const manifest = JSON.parse(await readFile(`${requests[index].output}.json`, 'utf8'));
    assert.deepEqual(manifest.jointEntries, ['first.bend', 'second.bend']);
    // Each module loads on its own, and contains no other entry's wrapper.
    const emitted = await readFile(requests[index].output, 'utf8');
    assert.equal(emitted.includes(`function $${index ? 'first' : 'second'}$run$(`), false);
  }
  assert.deepEqual((await compile()).map(result => result.cached), [true, true]);
  await writeFile(requests[0].entry, source(4, 2));
  assert.deepEqual((await compile()).map(result => result.cached), [false, false]);
  assert.equal(executeLibrary(requests[0].output, 'run', 2).value, '11');
  assert.equal(executeLibrary(requests[1].output, 'run', 2).value, '17');
  const alternate = { ...requests[0], output: path.join(directory, 'alternate.mjs'), exports: { current: 'helper' } };
  await rm(`${requests[0].output}.json`);
  await compileJavaScriptBatch({ prefix, requests: [requests[0], alternate] });
  assert.deepEqual(executeLibrary(alternate.output, 'current', 2), { value: '6', exports: ['current'] });
  assert.deepEqual(JSON.parse(await readFile(`${alternate.output}.json`, 'utf8')).jointEntries, ['first.bend']);
  assert.equal((await compileJavaScript(alternate)).cached, true);
  const metadata = `${requests[0].output}.json`;
  const manifest = JSON.parse(await readFile(metadata, 'utf8'));
  manifest.jointEntries = ['../first.bend'];
  await writeFile(metadata, JSON.stringify(manifest));
  assert.deepEqual((await compile()).map(result => result.cached), [false, true]);
  assert.equal(executeLibrary(requests[0].output, 'run', 2).value, '11');

  // A root-owned constructor keeps its historical unqualified wire identity.
  await writeFile(requests[0].entry, `import Base

type Box is Data:
  Box{value: Nat}

def run(value: Nat) -> Nat:
  value

def boxed() -> Box:
  Box{7n}
`);
  requests[0].exports = { run: 'run', boxed: 'boxed' };
  await writeFile(requests[1].entry, `import Base
import ./first.bend as First

def run(value: Nat) -> Nat:
  Nat.add(First.run(value), 15n)
`);
  requests[1].exports = { run: 'run' };
  // Load the data-owning entry through the other entry before its own request.
  await compileJavaScriptBatch({ prefix, requests: [requests[1], requests[0]] });
  const child = spawnSync(process.execPath, ['--eval', `import library from ${JSON.stringify(pathToFileURL(requests[0].output).href)}; console.log(JSON.stringify(library.boxed(), (_, value) => typeof value === 'bigint' ? value.toString() : value));`], { encoding: 'utf8' });
  assert.equal(child.status, 0, child.stderr);
  assert.deepEqual(JSON.parse(child.stdout), { $: 'Box', value: '7' });
  assert.equal(executeLibrary(requests[1].output, 'run', 2).value, '17');
  assert.equal(JSON.parse(await readFile(metadata, 'utf8')).jointEntries, undefined);
});
