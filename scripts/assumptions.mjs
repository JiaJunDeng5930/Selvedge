import { readdir, readFile, writeFile, mkdir } from 'node:fs/promises';
import path from 'node:path';
import { root, run, targets, jsonEntries } from './build-tools.mjs';

async function files(directory) {
  return (await Promise.all((await readdir(path.join(root, directory), { withFileTypes: true })).map(entry => {
    const filename = `${directory}/${entry.name}`;
    return entry.isDirectory() ? files(filename) : filename.endsWith('.v') ? [filename] : [];
  }))).flat().sort();
}
// Comments are removed with nesting, so prose mentioning a theorem is not audited as a declaration.
function withoutComments(source) {
  let result = '', depth = 0;
  for (let index = 0; index < source.length; index++) {
    const pair = source.slice(index, index + 2);
    if (pair === '(*') { depth++; index++; }
    else if (depth && pair === '*)') { depth--; index++; }
    else if (!depth) result += source[index];
  }
  return result;
}
export async function auditAssumptions({ prefixes = [], sources = null, entries = null } = {}) {
  const declarations = [];
  for (const filename of sources ?? await files('theories')) {
    if (filename.startsWith('theories/Derive/')) continue;
    if (prefixes.length && !prefixes.some(prefix => filename.startsWith(`theories/${prefix}/`))) continue;
    const module = `Selvedge.${filename.slice('theories/'.length, -2).replaceAll('/', '.')}`;
    const source = withoutComments(await readFile(path.join(root, filename), 'utf8'));
    if (/^\s*(?:Axiom|Axioms|Admitted)\b/m.test(source)) {
      throw new Error(`Unchecked proof declaration in ${filename}`);
    }
    // Vendored RecordEta checks a theorem inside __test; its name includes that module.
    const scopes = [];
    for (const match of source.matchAll(/^\s*(?:(Module|Section)\s+(?:(?:Import|Export|Type)\s+)?([A-Za-z_][A-Za-z_0-9']*)\s*\.|End\s+([A-Za-z_][A-Za-z_0-9']*)\s*\.|(?:Theorem|Lemma|Corollary|Proposition|Fact)\s+([A-Za-z_][A-Za-z_0-9']*)\b)/gm)) {
      if (match[1]) scopes.push({ kind: match[1], name: match[2] });
      else if (match[3]) scopes.pop();
      else {
        const namespace = scopes.filter(scope => scope.kind === 'Module').map(scope => scope.name);
        declarations.push({ module, name: [module, ...namespace, match[4]].join('.') });
      }
    }
  }
  const theorems = declarations.length;
  const auditedEntries = entries ?? [...Object.values(targets).flatMap(target => target.entry.map(entry => `${target.module}.${entry}`)), ...Object.values(jsonEntries)];
  for (const entry of auditedEntries) {
    if (prefixes.length && !prefixes.some(prefix => entry.startsWith(`${prefix}.`))) continue;
    const module = `Selvedge.${entry.slice(0, entry.lastIndexOf('.'))}`;
    declarations.push({ module, name: `Selvedge.${entry}` });
  }
  if (!declarations.length) throw new Error('No checked declarations found for assumption audit');
  const imports = [...new Set(declarations.map(item => item.module))].map(module => `Require Import ${module}.`).join('\n');
  const commands = declarations.map(item => `Print Assumptions ${item.name}.`).join('\n');
  await mkdir(path.join(root, '.build'), { recursive: true });
  await writeFile(path.join(root, '.build/Assumptions.v'), `${imports}\n${commands}\n`);
  const output = await run('rocq', ['c', '-w', '-register-all', '-Q', 'theories', 'Selvedge', '.build/Assumptions.v']);
  await writeFile(path.join(root, '.build/assumptions.log'), output);
  if (/Axioms:|Assumptions:/.test(output)) throw new Error('Proof depends on axioms; inspect .build/assumptions.log');
  const closed = output.match(/Closed under the global context/g)?.length ?? 0;
  if (closed !== declarations.length) throw new Error(`Incomplete assumption report (${closed}/${declarations.length}); inspect .build/assumptions.log`);
  console.log(`Assumptions: ${theorems} theorems and ${closed - theorems} production entries closed under the global context`);
}
if (process.argv[1]?.endsWith('/assumptions.mjs')) await auditAssumptions({ prefixes: process.argv.slice(2) });
