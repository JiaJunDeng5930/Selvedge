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
      // DEFENSE: A Bend source symlink can resolve outside the enumerated proof inventory; unrelated links are not compiler inputs.
      if (entry.isSymbolicLink() && filename.endsWith('.bend')) throw new Error(`UI verification refuses source symlinks: ${filename}`);
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
    // DEFENSE: Edited Bend source can contain imports this source-boundary scanner cannot resolve.
    if (!match) throw new Error(`Unsupported UI verification import: ${filename}:${index + 1}`);
    if (match[1] === 'Base' && !match[2]) continue;
    // DEFENSE: An unaliased or non-relative import cannot be resolved to the concept that owns its declarations.
    if (!match[1].startsWith('.') || !match[2]) throw new Error(`UI verification requires a relative aliased import: ${filename}:${index + 1}`);
    const target = path.posix.normalize(path.posix.join(path.posix.dirname(filename), match[1]));
    aliases.set(match[2], target);
    targets.push(target);
  }
  return { aliases, targets };
}

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
    // DEFENSE: An incomplete edited Bend declaration has no head delimiter for the proof inventory scanner.
    if (end === text.length) throw new Error(`Missing declaration head delimiter: ${filename}:${match[2]}`);
    result.push({ kind: match[1], name: match[2] });
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

function lawProviders(modules, laws) {
  const providers = new Map([...laws].map(law => [law, []]));
  for (const [filename, module] of modules) {
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
  const laws = new Set();
  for (const rule of rules) {
    for (const declaration of modules.get(rule).declarations) {
      if (declaration.kind === 'law') laws.add(canonical(rule, declaration.name, new Map()));
    }
  }
  const providers = lawProviders(modules, laws);
  const errors = [];
  for (const rule of rules) {
    const declarations = modules.get(rule).declarations.filter(declaration => declaration.kind === 'law');
    for (const declaration of declarations) {
      const implementations = providers.get(canonical(rule, declaration.name, new Map()));
      // DEFENSE: Editing a UI law or its implementation can leave that public law with no provider.
      if (!implementations.length) {
        errors.push(`UI proof does not fill its rule law: ${rule}:${declaration.name}`);
        continue;
      }
      // DEFENSE: Multiple source definitions can fill the same UI law, leaving the provider ordering ambiguous.
      if (implementations.length !== 1) {
        errors.push(`UI rule law has multiple proof providers: ${rule}:${declaration.name}: ${implementations.join(', ')}`);
        continue;
      }
      const [provider] = implementations;
      // DEFENSE: A source implementation can fill a qualified law without importing the contract whose declaration it must check against.
      if (provider !== rule && !modules.get(provider).targets.includes(rule)) {
        errors.push(`UI proof must import its rule: ${provider} -> ${rule}`);
      }
    }
  }
  // DEFENSE: Missing, duplicate or unbound UI law implementations cannot establish the checked public law providers.
  if (errors.length) throw new Error(`UI law provider check failed:\n${errors.join('\n')}`);
  return { discovered: [...new Set([...rules, ...proofs, ...[...providers.values()].flat()])].sort(), providers };
}

export function checkUiLawProviders(root) {
  return inspect(realpathSync(root)).discovered;
}

function orderProviders(root, discovered, providers) {
  const dependencies = new Map(discovered.map(filename => [filename, new Set()]));
  for (const filename of discovered) {
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
  const pending = new Set(discovered);
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
    const cycle = findCycle([...pending].sort()[0]);
    // DEFENSE: With no ready provider, the finite pending dependency graph contains an edited source import or law-reference cycle.
    throw new Error(`UI verification proof dependency cycle: ${cycle.join(' -> ')}`);
  }
  return ordered;
}

export function prepareUiVerification(root) {
  root = realpathSync(root);
  const { discovered, providers } = inspect(root);
  const sources = [...new Set(['PROOF.bend', 'BROWSER.bend', ...discovered])].sort();
  const entries = ['PROOF.bend', 'BROWSER.bend'];
  const ordered = [...orderProviders(root, discovered, providers), ...entries];
  const imports = ['import Base', ...ordered
    .map((filename, index) => `import ../${filename} as Verification${index}`)];
  const entry = '.build/ui-verification.bend';
  const source = `${imports.join('\n')}\n`;
  mkdirSync(path.join(root, '.build'), { recursive: true });
  let previous;
  // DEFENSE: A clean build directory has no generated proof entry to compare before writing it.
  try { previous = readFileSync(path.join(root, entry), 'utf8'); } catch (error) { if (error.code !== 'ENOENT') throw error; }
  if (previous !== source) writeFileSync(path.join(root, entry), source);
  const runtimeEntry = '.build/ui-runtime.bend';
  const runtimeSource = `${['import Base', ...ordered
    .flatMap((filename, index) => filename === 'PROOF.bend' ? [] : [`import ../${filename} as Verification${index}`]),
  'import ../harness/approval/PROOF.bend as RuntimeApprovalProof'].join('\n')}\n`;
  let previousRuntime;
  // DEFENSE: A clean build directory has no generated runtime entry to compare before writing it.
  try { previousRuntime = readFileSync(path.join(root, runtimeEntry), 'utf8'); } catch (error) { if (error.code !== 'ENOENT') throw error; }
  if (previousRuntime !== runtimeSource) writeFileSync(path.join(root, runtimeEntry), runtimeSource);
  return { entry, runtimeEntry, browserPrefix: 'BROWSER.', sources };
}
