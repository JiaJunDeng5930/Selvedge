import { readFile, readdir, realpath } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const defaultRoot = fileURLToPath(new URL('../', import.meta.url));
const configKeys = ['version', 'core_modules', 'application_dependencies',
  'feature_alphabet', 'feature_alphabet_types', 'feature_match_owners', 'model_representations', 'proof_root', 'runtime_root', 'foreign_sources'];

function mask(source) {
  return source.replace(/"(?:\\.|[^"\\])*"|#[^\n]*/g, text => text.replace(/[^\n]/g, ' '));
}

function matchesPattern(filename, pattern) {
  const escaped = pattern.split('*').map(part => part.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('.*');
  return new RegExp(`^${escaped}$`).test(filename);
}

function constructors(source, types) {
  const result = new Set();
  let inside = false;
  for (const line of mask(source).split('\n')) {
    if (/^type /.test(line)) inside = types.includes(line.match(/^type (\w+)/)?.[1]);
    else if (/^\S/.test(line)) inside = false;
    if (inside) {
      const match = line.match(/^  (\w+)\s*\{/);
      if (match) result.add(match[1]);
    }
  }
  return result;
}

function casePatterns(source) {
  const text = mask(source);
  const result = [];
  for (const match of text.matchAll(/^\s*case /gm)) {
    let depth = 0;
    for (let end = match.index + match[0].length; end < text.length; end++) {
      if ('{[('.includes(text[end])) depth++;
      else if ('}])'.includes(text[end])) depth--;
      else if (text[end] === ':' && depth === 0) {
        result.push({ text: text.slice(match.index, end), line: text.slice(0, match.index).split('\n').length });
        break;
      }
    }
  }
  // Constructor destructuring also occurs in bindings, including nested and
  // multiline patterns. Looking only for `case` leaves the same representation
  // dependency available through `F.Constructor{fields} = value`.
  for (const match of text.matchAll(/^[ \t]+(?:\+?[\w.]+\s*\{|\()/gm)) {
    let depth = 0;
    for (let end = match.index; end < text.length; end++) {
      if ('{[('.includes(text[end])) depth++;
      else if ('}])'.includes(text[end])) depth--;
      else if (depth === 0 && text[end] === '=') {
        if (!'=><'.includes(text[end - 1]) && !'=>'.includes(text[end + 1])) {
          result.push({ text: text.slice(match.index, end), line: text.slice(0, match.index).split('\n').length });
        }
        break;
      } else if (depth === 0 && (text[end] === '\n' || text[end] === ':')) break;
    }
  }
  return result;
}

// Constructor syntax is shared by expressions and binding/case patterns. Scan
// every qualified use rather than trying to infer its syntactic role.
// Bend requires the opening brace immediately after the constructor name;
// whitespace can instead separate a type annotation from a proposition body.
function qualifiedConstructors(source) {
  const text = mask(source);
  const result = [];
  let line = 1;
  let previous = 0;
  for (const match of text.matchAll(/\b(\w+)\.(\w+)\{/g)) {
    for (let index = previous; index < match.index; index++) {
      if (text[index] === '\n') line++;
    }
    previous = match.index;
    result.push({ alias: match[1], constructor: match[2], line });
  }
  return result;
}

function modelPolicies(config, sources) {
  if (!Array.isArray(config.model_representations) || !config.model_representations.length) {
    throw new Error('Invalid model representation boundaries');
  }
  const policies = new Map();
  for (const entry of config.model_representations) {
    if (!entry || typeof entry !== 'object' || Array.isArray(entry) ||
        JSON.stringify(Object.keys(entry).sort()) !== JSON.stringify(['constructors', 'module', 'owners'])) {
      throw new Error('Invalid model representation policy shape');
    }
    const { module, constructors: names, owners } = entry;
    if (typeof module !== 'string' || !sources.has(module)) {
      throw new Error(`Missing model representation module: ${module}`);
    }
    if (policies.has(module)) throw new Error(`Duplicate model representation ownership: ${module}`);
    if (!Array.isArray(names) || !names.length || names.some(name => typeof name !== 'string' || !/^\w+$/.test(name)) ||
        new Set(names).size !== names.length) {
      throw new Error(`Invalid model representation constructors: ${module}`);
    }
    if (!Array.isArray(owners) || !owners.length || owners.some(owner => typeof owner !== 'string' ||
        owner.includes('*') || !sources.has(owner)) || new Set(owners).size !== owners.length || !owners.includes(module)) {
      throw new Error(`Invalid model representation owners: ${module}`);
    }
    const source = sources.get(module);
    const types = [...mask(source).matchAll(/^type (\w+)\b/gm)].map(match => match[1]);
    const declared = constructors(source, types);
    for (const name of names) {
      if (!declared.has(name)) throw new Error(`Missing model representation constructor: ${module}:${name}`);
    }
    policies.set(module, { constructors: new Set(names), owners: new Set(owners) });
  }
  return policies;
}

/** Read actual source files, including newly added files not yet staged in Git. */
export async function bendSources(root = defaultRoot) {
  const result = [];
  async function visit(relative) {
    for (const item of await readdir(path.join(root, relative), { withFileTypes: true })) {
      if (item.name.startsWith('.') || ['node_modules', 'target', 'crates'].includes(item.name)) continue;
      const name = path.posix.join(relative, item.name);
      if (item.isDirectory()) await visit(name);
      else if (item.isFile() && name.endsWith('.bend')) result.push(name);
      else if (item.isSymbolicLink()) throw new Error(`Component audit does not accept source symlinks: ${name}`);
    }
  }
  await visit('');
  return result.sort();
}

async function sourceGraph(root, config) {
  const filenames = await bendSources(root);
  const sources = new Map(await Promise.all(filenames.map(async filename => [filename, await readFile(path.join(root, filename), 'utf8')])));
  const graph = new Map();
  const imports = new Map();
  const foreignImports = new Map();
  for (const [filename, source] of sources) {
    const edges = [];
    const bindings = [];
    const foreignEdges = [];
    for (const [index, line] of source.split('\n').entries()) {
      if (!/^\s*import\b/.test(line)) continue;
      const match = line.match(/^\s*import (?:"([^"]+)"|(\S+))(?: as (\w+))?\s*(?:#.*)?$/);
      if (!match) throw new Error(`Unsupported import: ${filename}:${index + 1}`);
      const [, foreign, target, alias] = match;
      if (!foreign && !line.startsWith('import ')) throw new Error(`Module import must be top-level: ${filename}:${index + 1}`);
      if (foreign) {
        const resolved = path.posix.normalize(path.posix.join(path.posix.dirname(filename), foreign));
        if (config.foreign_sources[filename] !== resolved) throw new Error(`Undeclared foreign import: ${filename}:${index + 1}`);
        foreignEdges.push(resolved);
        const actual = await realpath(path.join(root, resolved));
        if (!actual.startsWith(`${root}${path.sep}`)) throw new Error(`Foreign source escapes root: ${resolved}`);
      } else if (target.startsWith('.')) {
        if (!alias) throw new Error(`Local module imports require an explicit alias: ${filename}:${index + 1}`);
        const resolved = path.posix.normalize(path.posix.join(path.posix.dirname(filename), target));
        if (!sources.has(resolved)) throw new Error(`Missing or out-of-root source: ${filename}:${index + 1} -> ${resolved}`);
        edges.push(resolved);
        bindings.push({ target: resolved, alias });
      } else if (target !== 'Base') {
        throw new Error(`Undeclared external module: ${filename}:${index + 1}: ${target}`);
      }
    }
    graph.set(filename, edges);
    imports.set(filename, bindings);
    foreignImports.set(filename, foreignEdges);
  }

  return { filenames, sources, graph, imports, foreignImports };
}

function sourceClosure(graph, start) {
  const seen = new Set();
  const pending = [start];
  while (pending.length) {
    const filename = pending.pop();
    if (seen.has(filename)) continue;
    if (!graph.has(filename)) throw new Error(`Missing entry: ${filename}`);
    seen.add(filename);
    pending.push(...graph.get(filename));
  }
  return seen;
}

/** Exact local and foreign source inputs reachable from one compiler entry. */
export async function entrySources(root, entry) {
  root = await realpath(root);
  const config = JSON.parse(await readFile(path.join(root, 'components.json'), 'utf8'));
  const { graph, foreignImports } = await sourceGraph(root, config);
  const closure = sourceClosure(graph, entry);
  return [...new Set([...closure, ...[...closure].flatMap(filename => foreignImports.get(filename))])].sort();
}

/** This is a structural check, not a function-level dependency or semantic proof. */
export async function auditComponents(root = defaultRoot) {
  root = await realpath(root);
  const config = JSON.parse(await readFile(path.join(root, 'components.json'), 'utf8'));
  if (config.version !== 1 || JSON.stringify(Object.keys(config).sort()) !== JSON.stringify([...configKeys].sort())) {
    throw new Error('Unsupported or incomplete components.json');
  }
  for (const key of ['core_modules', 'feature_alphabet_types', 'feature_match_owners']) {
    if (!Array.isArray(config[key]) || !config[key].length || config[key].some(value => typeof value !== 'string' || !value)) {
      throw new Error(`Invalid component boundary ${key}`);
    }
  }
  if (!config.application_dependencies || Array.isArray(config.application_dependencies) ||
      typeof config.application_dependencies !== 'object' || !Object.keys(config.application_dependencies).length) {
    throw new Error('Invalid application dependency boundaries');
  }
  for (const [filename, dependencies] of Object.entries(config.application_dependencies)) {
    if (!filename || !Array.isArray(dependencies) || dependencies.some(value => typeof value !== 'string' || !value)) {
      throw new Error(`Invalid application dependency boundary: ${filename}`);
    }
  }
  const { filenames, sources, graph, imports } = await sourceGraph(root, config);
  const errors = [];
  const representations = modelPolicies(config, sources);

  for (const [filename, source] of sources) {
    const bindings = new Map(imports.get(filename).map(({ alias, target }) => [alias, target]));
    for (const use of qualifiedConstructors(source)) {
      const module = bindings.get(use.alias);
      const policy = representations.get(module);
      if (policy?.constructors.has(use.constructor) && !policy.owners.has(filename)) {
        errors.push(`Model representation outside its owner boundary: ${filename}:${use.line}: ${use.alias}.${use.constructor} (${module}:${use.constructor})`);
      }
    }
  }

  const core = new Set(config.core_modules);
  for (const filename of core) {
    if (!sources.has(filename)) throw new Error(`Missing core module: ${filename}`);
    for (const target of graph.get(filename)) {
      if (!core.has(target)) errors.push(`Core representation dependency: ${filename} -> ${target}`);
    }
  }
  if (!sources.has(config.feature_alphabet)) throw new Error('Missing component alphabet');
  for (const [filename, dependencies] of Object.entries(config.application_dependencies)) {
    if (!sources.has(filename) || dependencies.some(target => !sources.has(target))) throw new Error(`Missing application boundary source: ${filename}`);
    for (const target of graph.get(filename)) {
      if (!dependencies.includes(target)) errors.push(`Application imports outside its contract: ${filename} -> ${target}`);
    }
  }
  const featureConstructors = constructors(sources.get(config.feature_alphabet), config.feature_alphabet_types);
  if (!featureConstructors.size) throw new Error('Feature alphabet has no recognized constructors');
  for (const [filename, source] of sources) {
    if (config.feature_match_owners.some(owner => matchesPattern(filename, owner))) continue;
    for (const { target, alias } of imports.get(filename)) {
      if (target !== config.feature_alphabet || !alias) continue;
      for (const pattern of casePatterns(source)) {
        for (const constructor of featureConstructors) {
          if (new RegExp(`\\b${alias}\\.${constructor}\\s*\\{`).test(pattern.text)) {
            errors.push(`Feature pattern outside its component/assembly boundary: ${filename}:${pattern.line}: ${alias}.${constructor}`);
          }
        }
      }
    }
  }

  const proof = sourceClosure(graph, config.proof_root);
  const runtime = sourceClosure(graph, config.runtime_root);
  for (const filename of runtime) {
    if (filename !== config.runtime_root && !proof.has(filename)) errors.push(`Pure production module outside proof closure: ${filename}`);
  }
  for (const filename of Object.keys(config.foreign_sources)) {
    if (proof.has(filename)) errors.push(`Foreign boundary in pure proof closure: ${filename}`);
  }
  return { ok: errors.length === 0, scope: 'Actual-source import, constructor-pattern and private model constructor boundaries; no higher-order or semantic dependency analysis.',
    core_modules: [...core].sort(), checked_sources: filenames.length, errors };
}

export async function checkComponents(root = defaultRoot) {
  const result = await auditComponents(root);
  if (!result.ok) throw new Error(`Component boundary check failed:\n${result.errors.join('\n')}`);
  return `Component boundaries check (${result.core_modules.length} core modules; ${result.checked_sources} sources).`;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  console.log(await checkComponents(process.argv[2] ? path.resolve(process.argv[2]) : defaultRoot));
}
