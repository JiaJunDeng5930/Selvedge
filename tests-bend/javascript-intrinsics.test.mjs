import test from 'node:test';
import assert from 'node:assert/strict';
import { cp, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { parse } from 'acorn';
import { compileJavaScript } from '../scripts/compile-javascript.mjs';
import { compiledFixture } from './compiler-support.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const client = `import Base
import ../../bendlib/json.bend as Json
import ../../bendlib/string-equality.bend as Equal

def prefix(text: String, prefix: String) -> Bool:
  String.starts_with(text, prefix)

def equal(left: String, right: String, same: Bool) -> Bool:
  Equal.string_equal_acc(left, right, same)

def base_equal(left: String, right: String) -> Bool:
  String.eq(left, right)

def size(text: String, total: Nat) -> Nat:
  Json.utf8_length_acc(text, total)

def escaped(text: String) -> String:
  Json.escape(text)

def reversed(text: String, suffix: String) -> String:
  String.reverse.go(text, suffix)
`;

const outcome = (operation, ...arguments_) => {
  try { return { value: operation(...arguments_) }; }
  catch (error) { return { error: typeof error === 'string' ? error : `${error.name}: ${error.message}` }; }
};

test('native string intrinsics agree with original emitted execution on Unicode, invalid strings and bounded accumulators', async t => {
  const actual = await compiledFixture('javascript-intrinsics', client,
    { prefix: 'prefix', equal: 'equal', baseEqual: 'base_equal', size: 'size', escaped: 'escaped', reversed: 'reversed' });
  const output = path.join(root, '.build/test-javascript-intrinsics/fixture.mjs');
  const manifest = JSON.parse(await readFile(`${output}.json`, 'utf8'));
  assert.deepEqual(new Set(manifest.intrinsics), new Set([
    '$String$eq$', '$String$starts_with$', '$String$reverse$go$', '$bendlib$047string$045equality$string_equal_acc$',
    '$bendlib$047json$utf8_length_acc$', '$bendlib$047json$escape$',
  ]));
  let original = await readFile(output, 'utf8');
  const tree = parse(original, { ecmaVersion: 2024, sourceType: 'module' });
  const removals = [];
  for (const definition of tree.body) {
    if (definition.type !== 'FunctionDeclaration' || !manifest.intrinsics.includes(definition.id?.name)) continue;
    const guard = definition.body.body[0];
    assert.equal(guard.type, 'IfStatement');
    assert.equal(guard.consequent.type, 'ReturnStatement');
    removals.push(guard);
  }
  assert.equal(removals.length, 6);
  // Execute the actual retained compiler bodies, with only the added guards removed.
  for (const guard of removals.sort((a, b) => b.start - a.start)) {
    original = original.slice(0, guard.start) + original.slice(guard.end);
  }
  const directory = await mkdtemp(path.join(tmpdir(), 'selvedge-original-intrinsics-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const baselinePath = path.join(directory, 'original.mjs');
  await writeFile(baselinePath, original);
  const baseline = await import(pathToFileURL(baselinePath).href);
  const values = ['', 'a', 'ab', '中', '😀', '𝄞', '\u{10ffff}', 'e\u0301', 'é',
    '\0\b\t\r\n"\\', '\u007f\u0080\u07ff\u0800\ud7ff\ue000\uffff',
    '\ud800', '\udc00', 'a\ud800b', '😀\ud800', '\\u0000',
    String.fromCharCode(...Array.from({ length: 32 }, (_, index) => index))];
  let seed = 17;
  const random = () => (seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0);
  for (let index = 0; index < 512; index++) {
    let text = '';
    const length = random() % 20;
    for (let offset = 0; offset < length; offset++) {
      const point = random() % 0x110000;
      if (point < 0xd800 || point > 0xdfff) text += String.fromCodePoint(point);
    }
    values.push(text);
  }
  for (const [index, text] of values.entries()) {
    assert.deepEqual(outcome(actual.escaped, text), outcome(baseline.escaped, text));
    const other = values[(index * 23 + 7) % values.length];
    assert.deepEqual(outcome(actual.reversed, text, other), outcome(baseline.reversed, text, other));
    for (const candidate of ['', text, other, text.slice(0, text.length >>> 1)]) {
      assert.deepEqual(outcome(actual.baseEqual, text, candidate), outcome(baseline.baseEqual, text, candidate));
      assert.deepEqual(outcome(actual.prefix, text, candidate), outcome(baseline.prefix, text, candidate));
      for (const same of [false, true]) {
        assert.deepEqual(outcome(actual.equal, text, candidate, same), outcome(baseline.equal, text, candidate, same));
      }
    }
    for (const total of [0n, 7n, 281474976710654n, 281474976710655n]) {
      assert.deepEqual(outcome(actual.size, text, total), outcome(baseline.size, text, total));
    }
    if (text.isWellFormed()) assert.equal(actual.size(text, 7n), BigInt(Buffer.byteLength(text)) + 7n);
  }
  const wellFormed = Object.getOwnPropertyDescriptor(String.prototype, 'isWellFormed');
  try {
    Object.defineProperty(String.prototype, 'isWellFormed', { ...wellFormed, value: undefined });
    assert.deepEqual(outcome(actual.baseEqual, '中😀', '中😀'), outcome(baseline.baseEqual, '中😀', '中😀'));
    assert.deepEqual(outcome(actual.prefix, '中😀', '中'), outcome(baseline.prefix, '中😀', '中'));
    assert.deepEqual(outcome(actual.equal, '中😀', '中😀', true), outcome(baseline.equal, '中😀', '中😀', true));
    assert.deepEqual(outcome(actual.size, '中😀', 7n), outcome(baseline.size, '中😀', 7n));
    assert.deepEqual(outcome(actual.escaped, '中😀\n'), outcome(baseline.escaped, '中😀\n'));
    assert.deepEqual(outcome(actual.reversed, '中😀', 'end'), outcome(baseline.reversed, '中😀', 'end'));
  } finally { Object.defineProperty(String.prototype, 'isWellFormed', wellFormed); }
  const encoder = globalThis.TextEncoder;
  try {
    globalThis.TextEncoder = undefined;
    assert.deepEqual(outcome(actual.size, '中😀', 7n), outcome(baseline.size, '中😀', 7n));
  } finally { globalThis.TextEncoder = encoder; }
  const from = Array.from;
  try {
    Array.from = undefined;
    assert.deepEqual(outcome(actual.reversed, '中😀', 'end'), outcome(baseline.reversed, '中😀', 'end'));
  } finally { Array.from = from; }
});

test('changed definitions execute their new UTF-8 and escaping meanings instead of retaining intrinsics', async t => {
  const directory = await mkdtemp(path.join(tmpdir(), 'selvedge-changed-intrinsics-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  await cp(path.join(root, 'bendlib'), path.join(directory, 'bendlib'), { recursive: true });
  const jsonPath = path.join(directory, 'bendlib/json.bend');
  const json = await readFile(jsonPath, 'utf8');
  const branch = 'case False{} False{} True{}: 3n';
  assert.equal(json.split(branch).length, 2);
  const escaping = String.raw`"\\u00" ++`;
  assert.equal(json.split(escaping).length, 2);
  await writeFile(jsonPath, json.replace(branch, 'case False{} False{} True{}: 5n')
    .replace(escaping, '"changed-" ++'));
  const entry = path.join(directory, 'client.bend');
  const output = path.join(directory, 'client.mjs');
  await writeFile(entry, `import Base
import ./bendlib/json.bend as Json

def size(text: String, total: Nat) -> Nat:
  Json.utf8_length_acc(text, total)

def escaped(text: String) -> String:
  Json.escape(text)
`);
  await compileJavaScript({ entry, output, sourceRoot: directory, exports: { size: 'size', escaped: 'escaped' } });
  const manifest = JSON.parse(await readFile(`${output}.json`, 'utf8'));
  assert.equal(manifest.intrinsics.includes('$bendlib$047json$utf8_length_acc$'), false);
  assert.equal(manifest.intrinsics.includes('$bendlib$047json$escape$'), false);
  const changed = await import(pathToFileURL(output).href);
  assert.equal(changed.size('中', 0n), 5n);
  assert.equal(changed.size('a😀', 0n), 5n);
  assert.equal(changed.escaped('\0'), 'changed-00');
});
