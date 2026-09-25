// This is an untrusted proof-term translator. It never searches for a proof.
// Every result must pass Bend's checker against the translated statement.
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFile, writeFile, mkdir, mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const bundlePath = path.join(root, 'theory/stdlib-certificates.json');
const targetPath = path.join(root, 'bendlib/stdlib.bend');
const names = [
  'Corelib.Init.Datatypes.list_ind',
  'Stdlib.Lists.List.app_nil_r',
  'Stdlib.Lists.List.app_assoc',
  'Stdlib.Lists.List.fold_left_app',
  'Stdlib.Lists.List.map_app',
  'Stdlib.Lists.List.map_map',
  'Stdlib.Lists.List.map_id',
  'Corelib.Init.Datatypes.nat_ind',
  'Stdlib.Arith.PeanoNat.Nat.iter_swap_gen',
  'Stdlib.Arith.PeanoNat.Nat.iter_add',
  'Stdlib.Arith.PeanoNat.Nat.iter_ind',
  'Stdlib.Bool.Bool.orb_assoc',
  'Stdlib.Bool.Bool.orb_comm',
  'Stdlib.Bool.Bool.orb_diag',
  'Stdlib.Bool.Bool.orb_false_l',
  'Stdlib.Bool.Bool.orb_false_r',
  'Stdlib.Bool.Bool.orb_true_r',
];
const intrinsic = new Set([
  'Corelib.Init.Datatypes.app', 'Stdlib.Lists.List.fold_left', 'Corelib.Lists.ListDef.map',
  'Corelib.Init.Logic.f_equal', 'Corelib.Init.Logic.eq_trans',
  'Corelib.Init.Logic.eq_sym', 'Corelib.Init.Logic.eq_ind_r', ...names,
  'Corelib.Init.Nat.iter', 'Corelib.Init.Nat.add',
  'Corelib.Init.Datatypes.orb',
]);
const digest = value => createHash('sha256').update(value).digest('hex');

function run(command, args) {
  const result = spawnSync(command, args, { cwd: root, encoding: 'utf8', timeout: 60_000, maxBuffer: 8 * 1024 * 1024 });
  if (result.error || result.status !== 0) throw new Error(`${command} failed: ${result.error?.message ?? result.stderr ?? result.stdout}`);
  return result.stdout.trim();
}

export function parseExport(output) {
  const entities = [...output.matchAll(/^"SELVEDGE_PROOF:((?:""|[^"])*)"(?:%bs)?$/gm)]
    .map(match => JSON.parse(match[1].replaceAll('""', '"')));
  if (entities.length !== names.length || entities.some((entry, index) => entry[0] !== names[index])) {
    throw new Error('The exporter did not produce exactly the required named entities');
  }
  if ((output.match(/Closed under the global context/g) ?? []).length !== names.length) {
    throw new Error('The standard theorems must be closed under the global context');
  }
  return entities;
}

// Give every binder a unique name before beta/zeta reduction. Substitution is
// capture-free; unsupported source constructs and constants fail closed.
function decoder() {
  let serial = 0;
  const fresh = hint => `${hint.replaceAll("'", '_prime').replace(/[^a-zA-Z0-9_]/g, '_') || 'v'}_${serial++}`;
  function decode(node, scope = []) {
    if (!Array.isArray(node)) throw new Error('Malformed certificate node');
    const [tag, ...args] = node;
    if (tag === 'rel') {
      if (!Number.isSafeInteger(args[0]) || !scope[args[0]]) throw new Error('Unbound certificate variable');
      return scope[args[0]];
    }
    if (tag === 'sort') {
      if (!['Type', 'Prop'].includes(args[0])) throw new Error('Unsupported source universe');
      return { tag, kind: args[0] };
    }
    if (tag === 'const') {
      if (!intrinsic.has(args[0])) throw new Error(`Unmapped source constant: ${args[0]}`);
      return { tag, name: args[0] };
    }
    if (tag === 'ind' || tag === 'ctor') {
      if (!['Corelib.Init.Datatypes.list', 'Corelib.Init.Datatypes.nat', 'Corelib.Init.Datatypes.bool', 'Corelib.Init.Logic.eq'].includes(args[0]) || args[1] !== 0 ||
          (tag === 'ctor' && ![0, ...(!args[0].endsWith('.eq') ? [1] : [])].includes(args[2]))) {
        throw new Error('Unmapped source inductive');
      }
      return { tag, name: args[0], index: args[2] };
    }
    if (tag === 'cast') return decode(args[0], scope);
    if (tag === 'let') return decode(args[3], [decode(args[1], scope), ...scope]);
    if (tag === 'app') return application(decode(args[0], scope), args[1].map(x => decode(x, scope)));
    if (tag === 'lam' || tag === 'pi') {
      const variable = { tag: 'var', name: fresh(args[0]) };
      return { tag, variable, type: decode(args[1], scope), body: decode(args[2], [variable, ...scope]) };
    }
    if (tag === 'fix') {
      if (args[0] !== 0 || args[1].length !== 1) throw new Error('Only a single structural recursor is supported');
      const [hint, type, body, argument] = args[1][0];
      const variable = { tag: 'var', name: fresh(hint) };
      return { tag, variable, type: decode(type, scope), body: decode(body, [variable, ...scope]), argument };
    }
    if (tag === 'case') {
      const branches = args[3].map(([hints, body]) => {
        const variables = hints.map(hint => ({ tag: 'var', name: fresh(hint) }));
        return { variables, body: decode(body, [...variables, ...scope]) };
      });
      return { tag, value: decode(args[0], scope), branches };
    }
    throw new Error(`Unsupported certificate syntax: ${tag}`);
  }
  return decode;
}

function substitute(node, name, value) {
  if (!node || typeof node !== 'object') return node;
  if (Array.isArray(node)) return node.map(x => substitute(x, name, value));
  if (node.tag === 'var') return node.name === name ? value : node;
  return Object.fromEntries(Object.entries(node).map(([key, x]) => [key, substitute(x, name, value)]));
}

function application(fn, args) {
  if (fn.tag === 'app') return application(fn.fn, [...fn.args, ...args]);
  while (args.length && fn.tag === 'lam') {
    fn = normalize(substitute(fn.body, fn.variable.name, args[0]));
    args = args.slice(1);
  }
  if (!args.length) return fn;
  // These eliminations only reduce reflexive equality certificates. Bend still
  // checks the resulting equality; this is not an equality oracle.
  if (fn.tag === 'const' && fn.name.endsWith('.f_equal') && args.length === 6 && isRefl(args[5])) return { tag: 'refl' };
  if (fn.tag === 'const' && fn.name.endsWith('.eq_trans') && args.length === 6) {
    if (isRefl(args[4])) return args[5];
    if (isRefl(args[5])) return args[4];
  }
  return { tag: 'app', fn, args };
}
function isRefl(node) {
  return node.tag === 'refl' || (node.tag === 'app' && node.fn.tag === 'ctor' && node.fn.name.endsWith('.eq') && node.fn.index === 0);
}
function normalize(node) {
  if (!node || typeof node !== 'object') return node;
  if (Array.isArray(node)) return node.map(normalize);
  const result = Object.fromEntries(Object.entries(node).map(([key, x]) => [key, normalize(x)]));
  return result.tag === 'app' ? application(result.fn, result.args) : result;
}

const short = name => name.slice(name.lastIndexOf('.') + 1);
const templateSlots = { list_ind: [0, 1, 2, 3], app_nil_r: [], app_assoc: [], fold_left_app: [0, 1, 2],
  map_app: [0, 1, 2], map_map: [0, 1, 2, 3, 4], map_id: [0], nat_ind: [0, 1, 2],
  iter_swap_gen: [0, 1, 2, 3, 4, 5], iter_add: [2, 3], iter_ind: [0, 1, 3, 5],
  orb_assoc: [], orb_comm: [], orb_diag: [], orb_false_l: [], orb_false_r: [], orb_true_r: [] };
const parameterOrder = (method, length) => {
  const slots = templateSlots[method];
  return [...slots, ...Array.from({ length }, (_, i) => i).filter(i => !slots.includes(i))];
};
function dataType(type) {
  return type.tag === 'var' || (type.tag === 'ind' && ['Corelib.Init.Datatypes.nat', 'Corelib.Init.Datatypes.bool'].includes(type.name)) ||
    (type.tag === 'app' && type.fn.tag === 'ind' && type.fn.name.endsWith('.list'));
}
function templateType(type) { return type.tag === 'sort' || type.tag === 'pi'; }

function occurrences(node, name) {
  if (!node || typeof node !== 'object') return 0;
  if (node.tag === 'var') return Number(node.name === name);
  return Object.values(node).reduce((count, child) => count + occurrences(child, name), 0);
}

function emit(node, recursive = new Map()) {
  if (node.tag === 'var') return node.name;
  if (node.tag === 'ind' && node.name === 'Corelib.Init.Datatypes.nat') return 'Nat';
  if (node.tag === 'ind' && node.name === 'Corelib.Init.Datatypes.bool') return 'Bool';
  if (node.tag === 'ctor' && node.name === 'Corelib.Init.Datatypes.bool') return node.index === 0 ? 'True{}' : 'False{}';
  if (node.tag === 'ctor' && node.name === 'Corelib.Init.Datatypes.nat' && node.index === 0) return '0n';
  if (node.tag === 'sort') return node.kind === 'Prop' ? 'Type' : 'Data';
  if (node.tag === 'refl') return '{==}';
  if (node.tag === 'pi') return `@${node.variable.name}:${emit(node.type)} -> ${emit(node.body)}`;
  if (node.tag === 'lam') return `(${dataType(node.type) && occurrences(node.body, node.variable.name) > 1 ? '+' : ''}${node.variable.name} => ${emit(node.body, recursive)})`;
  if (node.tag === 'const' && names.includes(node.name)) return short(node.name);
  if (node.tag !== 'app') throw new Error(`Cannot emit ${node.tag} as a Bend expression`);
  const { fn, args } = node;
  const e = args.map(arg => emit(arg, recursive));
  if (fn.tag === 'fix' && fn.argument === 0 && args.length === 1) {
    // Rocq sometimes delta-reduces Nat.iter inside an existing proof. Recognize
    // its exact structural body, not its local name or the desired conclusion.
    const type = telescope(fn.type);
    const body = fn.body;
    const cases = body.tag === 'lam' ? body.body : undefined;
    const branch = cases?.tag === 'case' ? cases.branches[1] : undefined;
    const step = branch?.body;
    const recursiveCall = step?.tag === 'app' && step.args.length === 1 ? step.args[0] : undefined;
    if (type.parameters.length === 1 && type.parameters[0].type.tag === 'ind' &&
        type.parameters[0].type.name === 'Corelib.Init.Datatypes.nat' &&
        cases?.tag === 'case' && cases.value.tag === 'var' && cases.value.name === body.variable.name &&
        cases.branches.length === 2 && cases.branches[0].variables.length === 0 && branch.variables.length === 1 &&
        recursiveCall?.tag === 'app' && recursiveCall.fn.tag === 'var' && recursiveCall.fn.name === fn.variable.name &&
        recursiveCall.args.length === 1 && recursiveCall.args[0].tag === 'var' && recursiveCall.args[0].name === branch.variables[0].name &&
        [fn.variable.name, body.variable.name, branch.variables[0].name].every(name =>
          occurrences(step.fn, name) === 0 && occurrences(cases.branches[0].body, name) === 0)) {
      return `iter(~${emit(type.result)}, ~${emit(step.fn)}, ${e[0]}, ${emit(cases.branches[0].body)})`;
    }
    throw new Error('Unsupported unfolded iterator in certificate');
  }
  if (fn.tag === 'ind') {
    if (fn.name.endsWith('.list') && e.length === 1) return `+List<${e[0]}>`;
    if (fn.name.endsWith('.eq') && e.length === 3) return `{${e[1]} == ${e[2]} : ${e[0]}}`;
  }
  if (fn.tag === 'ctor') {
    if (fn.name === 'Corelib.Init.Datatypes.nat' && fn.index === 1 && e.length === 1) return `(1n+${e[0]})`;
    if (fn.name.endsWith('.eq') && fn.index === 0) return '{==}';
    if (fn.name.endsWith('.list') && fn.index === 0 && e.length === 1) return 'Nil{}';
    if (fn.name.endsWith('.list') && fn.index === 1 && e.length === 3) return `(${e[1]} <> ${e[2]})`;
    if (fn.name.endsWith('.list') && fn.index === 1 && e.length === 2) return `(tail => (${e[1]} <> tail))`;
  }
  if (fn.tag === 'const') {
    if (fn.name === 'Corelib.Init.Datatypes.orb' && e.length === 2) return `Bool.or(${e.join(', ')})`;
    if (fn.name === 'Corelib.Init.Nat.iter' && e.length === 4) return `iter(~${e[1]}, ~${e[2]}, ${e[0]}, ${e[3]})`;
    if (fn.name === 'Corelib.Init.Nat.add' && e.length === 2) return `Nat.add(${e.join(', ')})`;
    if (fn.name === 'Corelib.Init.Datatypes.app' && e.length === 3) return `List.append(&2, ${e.join(', ')})`;
    if (fn.name === 'Stdlib.Lists.List.fold_left' && e.length === 5) return `List.foldl(~&2, ~${e[1]}, ~${e[0]}, ~${e[2]}, ${e[3]}, ${e[4]})`;
    if (fn.name === 'Corelib.Lists.ListDef.map' && e.length === 4) return `map(~${e[0]}, ~${e[1]}, ~${e[2]}, ${e[3]})`;
    if (fn.name === 'Corelib.Init.Logic.eq_ind_r' && e.length === 6) return `transport(${e.join(', ')})`;
    const equal = { f_equal: 'cong', eq_trans: 'trans', eq_sym: 'sym' }[short(fn.name)];
    if (equal) return `Equal.${equal}(${e.join(', ')})`;
    if (names.includes(fn.name)) {
      const mask = templateSlots[short(fn.name)];
      return `${short(fn.name)}(${parameterOrder(short(fn.name), e.length).map(index => mask.includes(index) ? `~${e[index]}` : e[index]).join(', ')})`;
    }
  }
  if (fn.tag === 'var' && recursive.has(fn.name)) return `${recursive.get(fn.name)}${e.join(', ')})`;
  if (fn.tag === 'var' || fn.tag === 'app' || fn.tag === 'lam') return `${emit(fn, recursive)}(${e.join(', ')})`;
  throw new Error(`Unmapped certificate application: ${fn.name ?? fn.tag}`);
}

function telescope(type) {
  const parameters = [];
  while (type.tag === 'pi') { parameters.push(type); type = type.body; }
  return { parameters, result: type };
}

function spine(node) {
  const args = [];
  while (node.tag === 'app') { args.unshift(...node.args); node = node.fn; }
  return { fn: node, args };
}

// Specialize the imported list eliminator instead of capturing affine local
// values in a Bend template. The nil/cons proofs below are the source terms;
// this routine only lowers their eliminator and threads its environment.
function lowerInduction(name, parameters, node) {
  const { fn, args } = spine(node);
  if (fn.tag !== 'const') return null;
  const isList = fn.name === names[0];
  if ((!isList && fn.name !== 'Corelib.Init.Datatypes.nat_ind') || args.length < (isList ? 5 : 4)) return null;
  const [predicate, base, step, list, ...applied] = isList ? args.slice(1) : args;
  if (list.tag !== 'var' || !parameters.some(p => p.variable.name === list.name) || applied.some(x => x.tag !== 'var')) {
    throw new Error('The induction environment is outside the certificate subset');
  }
  const item = { tag: 'var', name: 'imported_item' };
  const rest = { tag: 'var', name: 'imported_rest' };
  const goal = telescope(application(predicate, [rest]));
  if (goal.parameters.length !== applied.length) throw new Error('An induction application is not fully eta-expanded');
  let recursiveArguments = parameters.map(p => p.variable.name === list.name ? rest : p.variable);
  for (let i = 0; i < applied.length; i++) {
    if (!parameters.some(p => p.variable.name === applied[i].name)) throw new Error('A generalized induction argument is not a parameter');
    recursiveArguments = recursiveArguments.map(arg => substitute(arg, applied[i].name, goal.parameters[i].variable));
  }
  let induction = application({ tag: 'const', name }, recursiveArguments);
  for (const p of goal.parameters.toReversed()) induction = { ...p, tag: 'lam', body: induction };
  const zero = application(base, applied);
  const successor = application(step, [...(isList ? [item] : []), rest, induction, ...applied]);
  return `  match ${emit(list)}:\n    case ${isList ? 'Nil{}' : '0n'}: ${emit(zero)}\n` +
    `    case ${isList ? `Con{+${item.name}, +${rest.name}}` : `1n+${rest.name}`}: ${emit(successor)}`;
}

// Preserve the original proof's Boolean eliminations. Only declared Boolean
// parameters and the two nullary constructors belong to this subset; a source
// case is not replaced by a locally generated truth-table proof.
function lowerBooleanCases(node, parameters) {
  if (node.tag !== 'case') return `  ${emit(node)}`;
  const columns = [];
  const leaves = [];
  function flatten(term, bindings) {
    if (term.tag !== 'case') { leaves.push({ term, bindings }); return; }
    if (term.value.tag !== 'var' || bindings.has(term.value.name) ||
        !parameters.some(p => p.variable.name === term.value.name && p.type.tag === 'ind' &&
          p.type.name === 'Corelib.Init.Datatypes.bool') || term.branches.length !== 2 ||
        term.branches.some(branch => branch.variables.length !== 0)) {
      throw new Error('Unsupported Boolean certificate elimination');
    }
    if (!columns.includes(term.value.name)) columns.push(term.value.name);
    term.branches.forEach((branch, index) => flatten(branch.body, new Map([...bindings, [term.value.name, index]])));
  }
  flatten(node, new Map());
  columns.sort((left, right) => parameters.findIndex(p => p.variable.name === left) -
    parameters.findIndex(p => p.variable.name === right));
  // Bend consumes unmatched local parameters at a match boundary. Flatten only
  // the existing source branches into a multi-pattern match; do not invent new
  // cases or solve a leaf. Each leaf remains the original specialized proof.
  return `  match ${columns.join(' ')}:\n` + leaves.map(({ term, bindings }) => {
    const patterns = columns.map(name => {
      const index = bindings.get(name);
      const replacement = index === undefined ? { tag: 'var', name: `imported_${name}` } :
        { tag: 'ctor', name: 'Corelib.Init.Datatypes.bool', index };
      term = substitute(term, name, replacement);
      return index === undefined ? `+${replacement.name}` : index === 0 ? 'True{}' : 'False{}';
    });
    return `    case ${patterns.join(' ')}: ${emit(normalize(term))}`;
  }).join('\n');
}

function compileEntity([name, sourceType, sourceBody]) {
  const decode = decoder();
  const { parameters, result } = telescope(decode(sourceType));
  let body = application(decode(sourceBody), parameters.map(p => p.variable));
  const method = short(name);
  const declarations = parameterOrder(method, parameters.length).map(i => {
    const p = parameters[i];
    const isTemplate = templateSlots[method].includes(i);
    return `${isTemplate ? '~' : p.type.tag === 'sort' ? '-' : dataType(p.type) ? '+' : ''}${p.variable.name}: ${emit(p.type)}`;
  });
  let code;
  if (method === 'list_ind' || method === 'nat_ind') {
    if (body.tag !== 'app' || body.fn.tag !== 'fix' || body.fn.argument !== 0 || body.args.length !== 1) {
      throw new Error('The imported list recursor has changed shape');
    }
    const fixed = body.fn;
    body = application(fixed.body, body.args);
    const isList = method === 'list_ind';
    if (body.tag !== 'case' || body.branches.length !== 2 || body.branches[0].variables.length !== 0 || body.branches[1].variables.length !== (isList ? 2 : 1)) {
      throw new Error('Unsupported recursor branches');
    }
    const recursive = new Map([[fixed.variable.name, `${method}(${parameters.slice(0, isList ? 4 : 3).map(p => `~${p.variable.name}`).join(', ')}, `]]);
    const [tail, head] = body.branches[1].variables;
    code = `  match ${emit(body.value)}:\n    case ${isList ? 'Nil{}' : '0n'}: ${emit(body.branches[0].body, recursive)}\n` +
      `    case ${isList ? `Con{+${head.name}, +${tail.name}}` : `1n+${tail.name}`}: ${emit(body.branches[1].body, recursive)}`;
  } else code = lowerInduction(name, parameters, body) ?? lowerBooleanCases(body, parameters);
  return `# Imported proof term: ${name}\ndef ${method}(${declarations.join(', ')}) ->\n  ${emit(result)}:\n${code}\n`;
}

export function translate(entities) {
  if (!Array.isArray(entities) || entities.length !== names.length || entities.some((entry, i) => entry[0] !== names[i])) {
    throw new Error('Unexpected certificate manifest');
  }
  return `import Base\n\n# Generated by scripts/import-stdlib.mjs from existing Rocq Stdlib proof terms.\n` +
    `# Do not edit. No axioms, proof search, or unchecked recursion are emitted.\n` +
    `# Source copyright INRIA, CNRS and contributors; LGPL-2.1 (theory/LICENSE).\n\n` +
    `# Exact Corelib Nat.iter correspondence: zero is the seed; successor applies f.\n` +
    `def iter(~A: Data, ~f: A -> A, count: Nat, seed: A) -> A:\n` +
    `  match count:\n    case 0n: seed\n    case 1n+rest: f(iter(~A, ~f, rest, seed))\n\n` +
    `# Source List.map corresponds to Base.foldr on duplicable lists. Base.map\n` +
    `# itself operates on affine lists; changing the list multiplicity is not a cast.\n` +
    `def map(~A: Data, ~B: Data, ~f: A -> B, items: +List<A>) -> +List<B>:\n` +
    `  List.foldr(~&2, ~A, ~(+List<B>), ~(item => tail => f(item) <> tail), items, Nil{})\n\n` +
    `# Source equality elimination maps to the checker's equality rewrite rule.\n` +
    `def transport(-A: Data, -x: A, -predicate: A -> Type, value: predicate(x), -y: A, evidence: {y == x : A}) -> predicate(y):\n` +
    `  backwards = Equal.sym(A, y, x, evidence)\n` +
    `  %backwards : predicate(_)\n` +
    `  value\n\n` +
    entities.map(compileEntity).join('\n');
}

async function refresh() {
  const temporary = await mkdtemp(path.join(tmpdir(), 'selvedge-stdlib-'));
  try {
    const output = run('rocq', ['c', '-o', path.join(temporary, 'ExportStdlib.vo'), 'scripts/ExportStdlib.v']);
    const entities = parseExport(output);
    const library = run('rocq', ['c', '-where']);
    const sources = {};
    for (const [name, relative] of [
      ['Corelib.Init.Datatypes', 'theories/Init/Datatypes.v'],
      ['Stdlib.Lists.List', 'user-contrib/Stdlib/Lists/List.v'],
      ['Corelib.Init.Nat', 'theories/Init/Nat.v'],
      ['Stdlib.Arith.PeanoNat', 'user-contrib/Stdlib/Arith/PeanoNat.v'],
      ['Stdlib.Bool.Bool', 'user-contrib/Stdlib/Bool/Bool.v'],
    ]) sources[name] = digest(await readFile(path.join(library, relative)));
    const bundle = {
      format: 'rocq-template-certificates-2',
      rocq: run('rocq', ['--version']).split('\n')[0],
      stdlib: run('opam', ['var', 'rocq-stdlib:version']),
      metarocq: run('opam', ['var', 'rocq-metarocq-template:version']),
      source: 'https://github.com/rocq-prover/stdlib',
      sources,
      entitiesSha256: digest(JSON.stringify(entities)),
      entities,
    };
    const translated = translate(entities);
    await mkdir(path.dirname(bundlePath), { recursive: true });
    await writeFile(bundlePath, JSON.stringify(bundle, null, 2) + '\n');
    await writeFile(targetPath, translated);
  } finally { await rm(temporary, { recursive: true, force: true }); }
}

export async function checkBundle() {
  const bundle = JSON.parse(await readFile(bundlePath, 'utf8'));
  if (bundle.format !== 'rocq-template-certificates-2' || bundle.entitiesSha256 !== digest(JSON.stringify(bundle.entities))) {
    throw new Error('The pinned proof bundle has an invalid format or digest');
  }
  const expected = translate(bundle.entities);
  if (await readFile(targetPath, 'utf8') !== expected) throw new Error('The Bend certificates differ from their pinned source proof terms');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (process.argv.includes('--refresh')) await refresh();
  else if (process.argv.includes('--generate')) {
    const bundle = JSON.parse(await readFile(bundlePath, 'utf8'));
    if (bundle.entitiesSha256 !== digest(JSON.stringify(bundle.entities))) throw new Error('Invalid source certificate digest');
    await writeFile(targetPath, translate(bundle.entities));
  }
  else await checkBundle();
  console.log('Standard-library certificate translation is reproducible.');
}
