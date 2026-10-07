import { mkdirSync, readdirSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { isProofSource } from './check-components.mjs';

function mask(source) {
  return source.replace(/"(?:\\.|[^"\\])*"|#[^\n]*/g, text => text.replace(/[^\n]/g, ' '));
}

function inventory(root) {
  const sources = new Map();
  function visit(directory) {
    for (const entry of readdirSync(path.join(root, directory), { withFileTypes: true })) {
      if (entry.name.startsWith('.') || ['node_modules', 'target', 'crates'].includes(entry.name)) continue;
      const filename = path.posix.join(directory, entry.name);
      if (entry.isSymbolicLink()) throw new Error(`UI verification refuses source symlinks: ${filename}`);
      if (entry.isDirectory()) visit(filename);
      else if (entry.isFile() && filename.endsWith('.bend')) sources.set(filename, readFileSync(path.join(root, filename), 'utf8'));
    }
  }
  visit('');
  return sources;
}

function isRule(filename, source) {
  if (!/^(interaction|browser)\//.test(filename) || isProofSource(filename)) return false;
  return /(?:^|\/)(?:laws|[^/]+-(?:laws|rules))\.bend$/.test(filename)
    || filename === 'interaction/CONTRACT.bend' || filename === 'browser/document/SPEC.bend'
    || declarations(filename, source).some(declaration => declaration.kind === 'law'
      || (declaration.kind === 'type' && /Requirements?$/.test(declaration.name)));
}

function imports(filename, source) {
  const aliases = new Map();
  const targets = [];
  for (const [index, line] of source.split('\n').entries()) {
    if (!/^\s*import\b/.test(line)) continue;
    if (/^\s*import\s+"/.test(line)) continue;
    const match = line.match(/^import\s+(\S+)(?:\s+as\s+(\w+))?\s*(?:#.*)?$/);
    if (!match) throw new Error(`Unsupported UI verification import: ${filename}:${index + 1}`);
    if (match[1] === 'Base' && !match[2]) continue;
    if (!match[1].startsWith('.') || !match[2]) throw new Error(`UI verification requires a relative aliased import: ${filename}:${index + 1}`);
    const target = path.posix.normalize(path.posix.join(path.posix.dirname(filename), match[1]));
    aliases.set(match[2], target);
    targets.push(target);
  }
  return { aliases, targets };
}

// Only declaration heads participate in separation; equality in a predicate's
// body or parameter does not make that predicate a proof implementation.
function declarations(filename, source) {
  const text = mask(source);
  const result = [];
  for (const match of text.matchAll(/^(def|law|type)\s+([A-Za-z_][\w.]*)/gm)) {
    let depth = 0;
    let end = match.index + match[0].length;
    for (; end < text.length; end++) {
      const char = text[end];
      if ('([{'.includes(char)) depth++;
      else if (')]}'.includes(char)) depth--;
      else if (char === ':' && depth === 0) break;
    }
    if (end === text.length) throw new Error(`Missing declaration head delimiter: ${filename}:${match[2]}`);
    const head = text.slice(match.index, end);
    let signature = '';
    if (match[1] === 'def') {
      let parameterDepth = 0;
      const start = head.indexOf('(');
      for (let index = start; index >= 0 && index < head.length; index++) {
        if (head[index] === '(') parameterDepth++;
        else if (head[index] === ')' && --parameterDepth === 0) {
          signature = head.slice(index + 1).trim();
          break;
        }
      }
    }
    result.push({ kind: match[1], name: match[2], signature,
      line: text.slice(0, match.index).split('\n').length + 1 });
  }
  return result;
}

function canonical(filename, name, aliases) {
  const dot = name.indexOf('.');
  if (dot !== -1 && aliases.has(name.slice(0, dot))) {
    return `${aliases.get(name.slice(0, dot)).slice(0, -5)}.${name.slice(dot + 1)}`;
  }
  return `${filename.slice(0, -5)}.${name}`;
}

function lawProviders(proofs, modules, laws) {
  const providers = new Map([...laws].map(law => [law, []]));
  for (const filename of proofs) {
    const module = modules.get(filename);
    for (const declaration of module.declarations) {
      if (declaration.kind !== 'def') continue;
      providers.get(canonical(filename, declaration.name, module.aliases))?.push(filename);
    }
  }
  return providers;
}

function inspect(root) {
  const sources = inventory(root);
  const modules = new Map([...sources].map(([filename, source]) => [filename, {
    ...imports(filename, source), declarations: declarations(filename, source),
  }]));
  const rules = [...sources.keys()].filter(filename => isRule(filename, sources.get(filename))).sort();
  const proofs = [...sources.keys()].filter(filename => /^(interaction|browser)\//.test(filename) && isProofSource(filename)).sort();
  const witnesses = new Set();
  const laws = new Set();
  for (const rule of rules) {
    for (const declaration of modules.get(rule).declarations) {
      if (declaration.kind === 'type' && /Requirements?$/.test(declaration.name)) witnesses.add(canonical(rule, declaration.name, new Map()));
      if (declaration.kind === 'law') laws.add(canonical(rule, declaration.name, new Map()));
    }
  }
  const providers = lawProviders(proofs, modules, laws);
  const errors = [];
  for (const [filename, module] of modules) {
    if (!/^(interaction|browser)\//.test(filename) || isProofSource(filename)) continue;
    const seen = new Set();
    const pending = [filename];
    while (pending.length) {
      const current = pending.pop();
      if (seen.has(current)) continue;
      seen.add(current);
      if (isProofSource(current)) {
        errors.push(`UI model/rule imports a proof provider: ${filename} -> ${current}`);
        continue;
      }
      const imported = modules.get(current);
      if (!imported) throw new Error(`Missing UI verification source: ${current}`);
      pending.push(...imported.targets);
    }
    for (const declaration of module.declarations) {
      if (declaration.kind !== 'def') continue;
      const name = canonical(filename, declaration.name, module.aliases);
      if (laws.has(name)) errors.push(`UI law implementation outside proofs: ${filename}:${declaration.line}: ${declaration.name}`);
      if (declaration.signature.includes('==') || declaration.signature.includes('!=')) {
        errors.push(`UI equality witness outside proofs: ${filename}:${declaration.line}: ${declaration.name}`);
      }
      for (const token of declaration.signature.matchAll(/\b[A-Za-z_][\w.]*/g)) {
        if (witnesses.has(canonical(filename, token[0], module.aliases))) {
          errors.push(`UI contract witness outside proofs: ${filename}:${declaration.line}: ${declaration.name}`);
          break;
        }
      }
    }
  }
  for (const rule of rules) {
    const moduleDeclarations = modules.get(rule).declarations;
    const declarations = moduleDeclarations.filter(declaration => declaration.kind === 'law');
    if (!declarations.length) {
      const contracts = moduleDeclarations.filter(declaration =>
        declaration.kind === 'type' && /Requirements?$/.test(declaration.name));
      // This existing aggregate is committed by architecture.surface and filled
      // by interaction/PROOF; it does not declare a second facade-local evidence law.
      if (contracts.length && rule !== 'interaction/CONTRACT.bend') {
        errors.push(`UI contract has no public law committing its requirements: ${rule}: ${contracts.map(declaration => declaration.name).join(', ')}`);
      }
      continue;
    }
    for (const declaration of declarations) {
      const implementations = providers.get(canonical(rule, declaration.name, new Map()));
      if (!implementations.length) {
        errors.push(`UI proof does not fill its rule law: ${rule}:${declaration.name}`);
        continue;
      }
      if (implementations.length !== 1) {
        errors.push(`UI rule law has multiple proof providers: ${rule}:${declaration.name}: ${implementations.join(', ')}`);
        continue;
      }
      const [provider] = implementations;
      if (!modules.get(provider).targets.includes(rule)) {
        errors.push(`UI proof must import its rule: ${provider} -> ${rule}`);
      }
    }
  }
  if (errors.length) throw new Error(`UI verification separation failed:\n${errors.join('\n')}`);
  return { discovered: [...new Set([...rules, ...proofs])].sort(), providers };
}

export function checkUiSeparation(root) {
  return inspect(realpathSync(root)).discovered;
}

function orderProofs(root, discovered, providers) {
  const proofs = discovered.filter(isProofSource);
  const dependencies = new Map(proofs.map(filename => [filename, new Set()]));
  for (const filename of proofs) {
    const source = readFileSync(path.join(root, filename), 'utf8');
    const module = imports(filename, source);
    const required = dependencies.get(filename);
    for (const target of module.targets) {
      if (target !== filename && dependencies.has(target)) required.add(target);
    }
    // A law binding declares its own provider; only references need an earlier
    // body, because Bend clears values before replaying the declaration order.
    const body = mask(source).replace(/^def\s+[A-Za-z_][\w.]*/gm, '');
    for (const match of body.matchAll(/\b([A-Za-z_][\w]*)\.([A-Za-z_][\w.]*)/g)) {
      const implementations = providers.get(canonical(filename, match[0], module.aliases));
      if (!implementations) continue;
      const [provider] = implementations;
      if (provider !== filename) required.add(provider);
    }
  }
  const ordered = [];
  const pending = new Set(proofs);
  while (pending.size) {
    const ready = [...pending].sort().find(filename =>
      [...dependencies.get(filename)].every(provider => !pending.has(provider)));
    if (ready) {
      pending.delete(ready);
      ordered.push(ready);
      continue;
    }
    const visiting = [];
    const visited = new Set();
    function findCycle(filename) {
      const index = visiting.indexOf(filename);
      if (index !== -1) return [...visiting.slice(index), filename];
      if (visited.has(filename)) return;
      visiting.push(filename);
      for (const provider of [...dependencies.get(filename)].sort()) {
        if (!pending.has(provider)) continue;
        const cycle = findCycle(provider);
        if (cycle) return cycle;
      }
      visiting.pop();
      visited.add(filename);
    }
    for (const filename of [...pending].sort()) {
      const cycle = findCycle(filename);
      if (cycle) throw new Error(`UI verification proof dependency cycle: ${cycle.join(' -> ')}`);
    }
    throw new Error('UI verification proof dependency ordering failed');
  }
  return ordered;
}

export function prepareUiVerification(root) {
  root = realpathSync(root);
  const { discovered, providers } = inspect(root);
  const sources = [...new Set(['PROOF.bend', 'BROWSER.bend', ...discovered])].sort();
  const entries = ['PROOF.bend', 'BROWSER.bend'];
  const ordered = [...discovered.filter(filename => isRule(filename, readFileSync(path.join(root, filename), 'utf8'))), ...orderProofs(root, discovered, providers), ...entries];
  const imports = ['import Base', ...ordered
    .map((filename, index) => `import ../${filename} as Verification${index}`)];
  const entry = '.build/ui-verification.bend';
  const source = `${imports.join('\n')}\n`;
  mkdirSync(path.join(root, '.build'), { recursive: true });
  let previous;
  try { previous = readFileSync(path.join(root, entry), 'utf8'); } catch (error) { if (error.code !== 'ENOENT') throw error; }
  if (previous !== source) writeFileSync(path.join(root, entry), source);
  return { entry, browserPrefix: 'BROWSER.', sources };
}
