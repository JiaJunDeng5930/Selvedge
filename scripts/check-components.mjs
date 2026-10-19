import { readFile, readdir, realpath } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const defaultRoot = fileURLToPath(new URL('../', import.meta.url));
const configKeys = ['version', 'core_roots', 'core_forbidden_dependencies',
  'feature_alphabet', 'feature_alphabet_types', 'feature_match_owners', 'model_representations', 'proof_root', 'runtime_roots', 'foreign_sources'];

export function isProofSource(filename) {
  const name = path.posix.basename(filename);
  return name === 'PROOF.bend' || name.endsWith('-proof.bend');
}

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
  // DEFENSE: components.json can omit the private model ownership policy required by the source boundary check.
  if (!Array.isArray(config.model_representations) || !config.model_representations.length) {
    throw new Error('Invalid model representation boundaries');
  }
  const policies = new Map();
  for (const entry of config.model_representations) {
    // DEFENSE: A private model policy read from components.json can contain missing or extra ownership fields.
    if (!entry || typeof entry !== 'object' || Array.isArray(entry) ||
        JSON.stringify(Object.keys(entry).sort()) !== JSON.stringify(['constructors', 'module', 'owners'])) {
      throw new Error('Invalid model representation policy shape');
    }
    const { module, constructors: names, owners } = entry;
    // DEFENSE: A configured private model module may be removed or renamed in the source tree.
    if (typeof module !== 'string' || !sources.has(module)) {
      throw new Error(`Missing model representation module: ${module}`);
    }
    // DEFENSE: components.json can assign the same model module more than one private ownership policy.
    if (policies.has(module)) throw new Error(`Duplicate model representation ownership: ${module}`);
    // DEFENSE: Configured private constructors can be missing, empty or duplicated, leaving the boundary check incomplete.
    if (!Array.isArray(names) || !names.length || names.some(name => typeof name !== 'string' || !/^\w+$/.test(name)) ||
        new Set(names).size !== names.length) {
      throw new Error(`Invalid model representation constructors: ${module}`);
    }
    // DEFENSE: Configured model owners can be missing or malformed, leaving private constructors without an enforceable boundary.
    if (!Array.isArray(owners) || !owners.length || owners.some(owner => typeof owner !== 'string' ||
        owner.includes('*') || !sources.has(owner)) || new Set(owners).size !== owners.length || !owners.includes(module)) {
      throw new Error(`Invalid model representation owners: ${module}`);
    }
    const source = sources.get(module);
    const types = [...mask(source).matchAll(/^type (\w+)\b/gm)].map(match => match[1]);
    const declared = constructors(source, types);
    for (const name of names) {
      // DEFENSE: A configured private constructor may no longer exist in the model source.
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
      else if (item.isFile() && name.endsWith('.bend')) {
        // DEFENSE: New source files can exceed the repository's two-level concept directory contract.
        if (name.split('/').length > 3) throw new Error(`Bend source exceeds two directory levels: ${name}`);
        result.push(name);
      }
      // DEFENSE: A Bend source symlink can resolve outside the audited ownership and proof inventory; unrelated links are not compiler inputs.
      else if (item.isSymbolicLink() && name.endsWith('.bend')) {
        throw new Error(`Component audit does not accept source symlinks: ${name}`);
      }
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
      // DEFENSE: Edited Bend source can contain imports this source-boundary scanner cannot resolve.
      if (!match) throw new Error(`Unsupported import: ${filename}:${index + 1}`);
      const [, foreign, target, alias] = match;
      // DEFENSE: An indented module import would escape the source-boundary scanner's top-level import contract.
      if (!foreign && !line.startsWith('import ')) throw new Error(`Module import must be top-level: ${filename}:${index + 1}`);
      if (foreign) {
        const resolved = path.posix.normalize(path.posix.join(path.posix.dirname(filename), foreign));
        // DEFENSE: An edited source can introduce a foreign import absent from components.json's explicit IO boundary.
        if (config.foreign_sources[filename] !== resolved) throw new Error(`Undeclared foreign import: ${filename}:${index + 1}`);
        foreignEdges.push(resolved);
        const actual = await realpath(path.join(root, resolved));
        // DEFENSE: A foreign import can resolve through a symlink outside the audited repository root.
        if (!actual.startsWith(`${root}${path.sep}`)) throw new Error(`Foreign source escapes root: ${resolved}`);
      } else if (target.startsWith('.')) {
        // DEFENSE: An unaliased or non-relative import cannot be resolved to the concept that owns its declarations.
        if (!alias) throw new Error(`Local module imports require an explicit alias: ${filename}:${index + 1}`);
        const resolved = path.posix.normalize(path.posix.join(path.posix.dirname(filename), target));
        // DEFENSE: An edited relative import can name a missing file or escape the audited repository.
        if (!sources.has(resolved)) throw new Error(`Missing or out-of-root source: ${filename}:${index + 1} -> ${resolved}`);
        edges.push(resolved);
        bindings.push({ target: resolved, alias });
      // DEFENSE: A new external import can bypass the declared component and pure-proof dependency closure.
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
    // DEFENSE: An entry configured in components.json may be absent from the current source graph.
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
  // DEFENSE: The on-disk component configuration can omit fields required by the current core-root boundary contract.
  if (config.version !== 2 || JSON.stringify(Object.keys(config).sort()) !== JSON.stringify([...configKeys].sort())) {
    throw new Error('Unsupported or incomplete components.json');
  }
  for (const key of ['core_roots', 'core_forbidden_dependencies', 'feature_alphabet_types', 'feature_match_owners', 'runtime_roots']) {
    // DEFENSE: A configured source root, forbidden dependency pattern or ownership list can contain entries the boundary scanner cannot audit.
    if (!Array.isArray(config[key]) || !config[key].length || config[key].some(value => typeof value !== 'string' || !value)) {
      throw new Error(`Invalid component boundary ${key}`);
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

  const core = new Set();
  for (const entry of config.core_roots) {
    for (const filename of sourceClosure(graph, entry)) {
      core.add(filename);
      // DEFENSE: A new transitive import can pull application assembly or feature ownership into an otherwise independent core root.
      if (config.core_forbidden_dependencies.some(pattern => matchesPattern(filename, pattern))) {
        errors.push(`Core depends on application assembly or feature ownership: ${entry} -> ${filename}`);
      }
    }
  }
  // DEFENSE: The configured feature alphabet can be removed or renamed, disabling feature ownership checks.
  if (!sources.has(config.feature_alphabet)) throw new Error('Missing component alphabet');
  const featureConstructors = constructors(sources.get(config.feature_alphabet), config.feature_alphabet_types);
  // DEFENSE: An edited feature alphabet with no recognized constructors would make feature-pattern checks vacuous.
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
  for (const runtimeRoot of config.runtime_roots) {
    for (const filename of sourceClosure(graph, runtimeRoot)) {
      if (filename !== runtimeRoot && !proof.has(filename)) errors.push(`Pure production module outside proof closure: ${filename}`);
    }
  }
  for (const filename of Object.keys(config.foreign_sources)) {
    if (proof.has(filename)) errors.push(`Foreign boundary in pure proof closure: ${filename}`);
  }
  return { ok: errors.length === 0, scope: 'Actual-source import, constructor-pattern and private model constructor boundaries; no higher-order or semantic dependency analysis.',
    core_modules: [...core].sort(), checked_sources: filenames.length, errors };
}

export async function checkComponents(root = defaultRoot) {
  const result = await auditComponents(root);
  // DEFENSE: Actual source imports or constructor patterns can violate the configured component ownership rules.
  if (!result.ok) throw new Error(`Component boundary check failed:\n${result.errors.join('\n')}`);
  return `Component boundaries check (${result.core_modules.length} core modules; ${result.checked_sources} sources).`;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  console.log(await checkComponents(process.argv[2] ? path.resolve(process.argv[2]) : defaultRoot));
}
