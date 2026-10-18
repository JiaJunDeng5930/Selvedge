import { createHash } from 'node:crypto';
import path from 'node:path';
import { parse } from 'acorn';

const digest = text => createHash('sha256').update(text).digest('hex');
const baseSha256 = 'c742fae9c49b14f0cc9128429a2c6109364c8a933a142f2c90b9f2e5fd976661';

// These are compiler intrinsics, bound to both the complete defining source and
// the pinned emitter's function. Changed definitions retain the original code.
const intrinsics = new Map([
  ['$String$eq$', {
    functionSha256: '9879c7a2170260e74e4db58931ccf0dfac67a5d8246d6614372e6f95d22a695b',
    parameters: 2,
    fast: ([left, right]) => `if (${strings(left, right)}) return ${left} === ${right};`,
  }],
  ['$String$starts_with$', {
    functionSha256: 'ce86b27f8daa08853a3dee7714c262f60b2316295907d6c2dec20eaee411427e',
    parameters: 3,
    fast: ([text, prefix]) => `if (${strings(text, prefix)}) return ${text}.startsWith(${prefix});`,
  }],
  ['$String$reverse$go$', {
    functionSha256: '76bbc84ff5028ee7ac5868076ad2b56d0efbc7538aca783a2dae8b01c9406370',
    parameters: 2,
    fast: ([text, suffix]) => `if (${strings(text, suffix)} && typeof Array.from === "function") return Array.from(${text}).reverse().join("") + ${suffix};`,
  }],
  ['$bendlib$047string$045equality$string_equal_acc$', {
    source: 'bendlib/string-equality.bend',
    sourceSha256: 'f4f9998250553e4809779670fde337eefb234e6763b2380ccfe51ed8d727b703',
    functionSha256: '823d63f36c14e3c0440042f46bc534f497baeed1a6db4e109a5493f11dc3fe54',
    parameters: 3,
    fast: ([left, right, same]) => `if (${strings(left, right)} && typeof ${same} === "boolean") return ${same} && ${left} === ${right};`,
  }],
  ['$bendlib$047json$escape$', {
    source: 'bendlib/json.bend',
    sourceSha256: '39fa5b29cd018a8c7f4a757ff1d3fb6a9ba7b3dac2637fad6b3828aba4b11f40',
    functionSha256: 'd398f323e7eca1ce28e5c970998c0cf4282437ea940df508bbc0eb53f0ba69d0',
    parameters: 1,
    fast: ([text]) => escaped(text),
  }],
  ['$bendlib$047json$utf8_length_acc$', {
    source: 'bendlib/json.bend',
    sourceSha256: '39fa5b29cd018a8c7f4a757ff1d3fb6a9ba7b3dac2637fad6b3828aba4b11f40',
    functionSha256: '8e761574bde712dd71c10e9050e36be96e2125fbaeb97909598eec205b50eb39',
    parameters: 2,
    fast: ([text, total]) => `if (${strings(text)} && typeof TextEncoder === "function" && Number.isSafeInteger(${total}) && !Object.is(${total}, -0) && ${total} >= 0 && ${total} <= 281474976710655) return nat_chk(${total} + new TextEncoder().encode(${text}).byteLength);`,
  }],
]);

function escaped(text) {
  // Bend uses six-character lowercase escapes for every control character.
  // JSON.stringify's abbreviated control escapes would change the wire bytes.
  const pattern = String.raw`/["\\\u0000-\u001f]/g`;
  return `if (${strings(text)}) return ${text}.replace(${pattern}, character => character === ${JSON.stringify('"')} ? ${JSON.stringify('\\"')} : character === ${JSON.stringify('\\')} ? ${JSON.stringify('\\\\')} : ${JSON.stringify('\\u00')} + character.charCodeAt(0).toString(16).padStart(2, "0"));`;
}

function strings(...names) {
  // Keep the generated behavior for malformed JS strings and older browsers.
  return names.map(name => `typeof ${name} === "string"`).join(' && ')
    + ` && typeof ${names[0]}.isWellFormed === "function"`
    + names.map(name => ` && ${name}.isWellFormed()`).join('');
}

export function optimizeJavaScript(source, { sourceHashes, sourceRoot, basePath }) {
  if (sourceHashes.get(basePath) !== baseSha256) return { source, intrinsics: [] };
  const tree = parse(source, { ecmaVersion: 2024, sourceType: 'module' });
  const edits = [];
  const applied = [];
  for (const definition of tree.body) {
    if (definition.type !== 'FunctionDeclaration') continue;
    const intrinsic = intrinsics.get(definition.id?.name);
    if (!intrinsic || definition.params.length !== intrinsic.parameters
      || definition.params.some(parameter => parameter.type !== 'Identifier')) continue;
    if (intrinsic.source && sourceHashes.get(path.join(sourceRoot, intrinsic.source)) !== intrinsic.sourceSha256) continue;
    if (digest(source.slice(definition.start, definition.end)) !== intrinsic.functionSha256) continue;
    const fast = intrinsic.fast(definition.params.map(parameter => parameter.name));
    edits.push({ offset: definition.body.start + 1, text: `\n  ${fast}\n` });
    applied.push(definition.id.name);
  }
  // The original body remains the fallback. No function, check or source is removed.
  for (const { offset, text } of edits.sort((a, b) => b.offset - a.offset)) {
    source = source.slice(0, offset) + text + source.slice(offset);
  }
  return { source, intrinsics: applied };
}
