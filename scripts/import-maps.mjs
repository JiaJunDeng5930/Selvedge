import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFile, writeFile, mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { decoder, application, substitute, spine, telescope } from './import-stdlib.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const map = 'ExtLib.Data.Map.FMapAList.';
const data = 'Corelib.Init.Datatypes.';
const logic = 'Corelib.Init.Logic.';
const rel = 'ExtLib.Core.RelDec.';
export const mapNames = [map + 'alist_find', map + 'alist_remove', 'Stdlib.Lists.List.filter',
  map + 'remove_eq_alist', 'ExportMaps.removal_absence', 'ExportMaps.boolean_relation',
  'ExportMaps.boolean_decision', 'ExportMaps.boolean_correct'];
const bundlePath = path.join(root, 'theory/rocq-maps.json');
const targetPath = path.join(root, 'bendlib/association-map.bend');
const digest = value => createHash('sha256').update(value).digest('hex');
const variable = name => ({ tag: 'var', name });
const K = { tag: 'ind', name: data + 'nat' }, V = variable('V');
const query = variable('query'), key = variable('key'), value = variable('value'), rest = variable('rest');
const R = variable('relation'), D = variable('decision'), C = variable('correct');
const ctor = (name, index, ...args) => application({ tag: 'ctor', name, index }, args);
const pair = ctor(data + 'prod', 0, K, V, key, value);
const nil = ctor(data + 'list', 0, application({ tag: 'ind', name: data + 'prod' }, [K, V]));
const cons = ctor(data + 'list', 1, application({ tag: 'ind', name: data + 'prod' }, [K, V]), pair, rest);
const same = (left, right) => JSON.stringify(left) === JSON.stringify(right);
function requireShape(condition, message) { if (!condition) throw new Error(`Association-map certificate: ${message}`); }
function alpha(node, bound = []) {
  if (!node || typeof node !== 'object') return node;
  if (Array.isArray(node)) return node.map(value => alpha(value, bound));
  if (node.tag === 'var') return bound.includes(node.name) ? ['bound', bound.indexOf(node.name)] : ['free', node.name];
  if (node.tag === 'lam' || node.tag === 'pi') return [node.tag, alpha(node.type, bound), alpha(node.body, [node.variable.name, ...bound])];
  return Object.fromEntries(Object.entries(node).map(([key, value]) => [key, alpha(value, bound)]));
}
const equivalent = (left, right) => same(alpha(left), alpha(right));
function specialize(type, arguments_) {
  for (const argument of arguments_) {
    requireShape(type.tag === 'pi', 'source type has too few parameters');
    type = substitute(type.body, type.variable.name, argument);
  }
  return type;
}

const constants = new Set([...mapNames, map + 'alist', data + 'list_ind', data + 'fst', data + 'negb',
  rel + 'rel_dec', logic + 'False_ind', logic + 'not', 'ExtLib.Tactics.Consider.Reflect_RelDecCorrect']);
const inductives = { [data + 'nat']: 2, [data + 'bool']: 2, [data + 'list']: 2, [data + 'prod']: 1,
  [data + 'option']: 2, [logic + 'eq']: 1, [logic + 'False']: 0, [logic + 'and']: 1,
  [logic + 'iff']: 1, [rel + 'RelDec']: 1, [rel + 'RelDec_Correct']: 1 };

// Beta/zeta/iota reduction only. Unknown conditionals remain source cases;
// there is no proof search and no replacement of a leaf by a guessed proof.
function reduce(node) {
  if (!node || typeof node !== 'object') return node;
  if (Array.isArray(node)) return node.map(reduce);
  let result = Object.fromEntries(Object.entries(node).map(([key, value]) => [key, reduce(value)]));
  if (result.tag === 'app') {
    result = application(result.fn, result.args);
    const { fn, args } = spine(result);
    if (fn.tag === 'case') return reduce({ ...fn, branches: fn.branches.map(branch => ({
      ...branch, body: application(branch.body, args),
    })) });
    if (fn.name === data + 'fst') {
      const product = spine(args[2]);
      if (product.fn.name === data + 'prod' && product.fn.tag === 'ctor') return product.args[2];
    }
  }
  if (result.tag === 'case') {
    const { fn, args } = spine(result.value);
    if (fn.tag === 'ctor') {
      const branch = result.branches[fn.index];
      requireShape(branch, 'constructor has no elimination branch');
      let body = branch.body;
      branch.variables.forEach((binder, i) => { body = substitute(body, binder.name, args.at(-1 - i)); });
      return reduce(body);
    }
  }
  return result;
}

function unfold(fixed, args, recursive) {
  requireShape(fixed.tag === 'fix', 'expected the original structural recursor');
  return reduce(application(substitute(fixed.body, fixed.variable.name, variable(recursive)), args));
}
function branches(node, count) {
  requireShape(node.tag === 'case' && node.branches.length === count, 'unexpected source case tree');
  return node.branches;
}

// Reflection is specialized at R(x,y) := same(x,y)=true by ExportMaps.v.
// Repeated reflection on the same comparison is iota reduction in a known
// branch. The original contradiction branch is unreachable, not re-proved.
function reflected(node, known = new Map()) {
  node = reduce(node);
  if (node.tag !== 'case') return node;
  const { fn, args } = spine(node.value);
  requireShape(fn.name === 'ExtLib.Tactics.Consider.Reflect_RelDecCorrect' && args.length === 6,
    'only the original Boolean reflection eliminations are supported');
  const comparison = [args[4], args[5]], identity = JSON.stringify(comparison);
  const alternatives = branches(node, 2);
  const branch = index => {
    requireShape(alternatives[index].variables.length === 1, 'reflection witness arity changed');
    return reflected(alternatives[index].body, new Map([...known, [identity, index]]));
  };
  if (known.has(identity)) return branch(known.get(identity));
  return { tag: 'reflection', comparison, yes: branch(0), no: branch(1) };
}

function emit(node) {
  node = reduce(node);
  if (node.tag === 'var') return node.name;
  const { fn, args } = spine(node);
  if (fn.tag === 'ctor') {
    if (fn.name === logic + 'eq') return '{==}';
    if (fn.name === data + 'option') return fn.index === 1 ? 'None{}' : `Some{${emit(args[1])}}`;
    if (fn.name === data + 'list') return fn.index === 0 ? 'Nil{}' : `${emit(args[1])} <> ${emit(args[2])}`;
    if (fn.name === data + 'prod') return `(${emit(args[2])}, ${emit(args[3])})`;
  }
  if (fn.name === rel + 'rel_dec' && args.length === 5) return `Nat.is_eq(${emit(args[3])}, ${emit(args[4])})`;
  if (fn.name === data + 'negb' && args.length === 1) return `Bool.not(${emit(args[0])})`;
  if (fn.name === 'find_rec') return `find(~V, ${emit(args[1])}, ${emit(args[0])})`;
  if (fn.name === 'remove_rec') return `remove(~V, ${emit(args[0])}, query)`;
  if (fn.name === 'induction') {
    requireShape(args.length === 1 && same(args[0], query), 'induction hypothesis applied at a different key');
    return 'induction';
  }
  throw new Error(`Association-map certificate: unsupported leaf ${JSON.stringify(node)}`);
}

export function translateMaps(entities) {
  requireShape(Array.isArray(entities) && entities.length === mapNames.length &&
    entities.every((entry, i) => entry[0] === mapNames[i]), 'unexpected entity manifest');
  const decode = decoder({ constants, inductives });
  const source = new Map(entities.map(([name, type, body]) => [name, { type: decode(type), body: decode(body) }]));
  const apply = (name, args) => reduce(application(source.get(name).body, args));

  // Validate the instance as an application of the original theorem. It is
  // not permissible to quote a same-named theorem proved by a local tactic.
  const instance = spine(apply('ExportMaps.removal_absence', [K, V, variable('same'), rest, query]));
  requireShape(instance.fn.name === map + 'remove_eq_alist' && instance.args.length === 7 &&
    same(instance.args[0], K) && same(instance.args[3], V) && same(instance.args[5], rest) && same(instance.args[6], query),
    'instance is not the original theorem at these carriers and endpoints');
  for (const [index, name] of [[1, 'boolean_relation'], [2, 'boolean_decision'], [4, 'boolean_correct']]) {
    const argument = spine(instance.args[index]);
    requireShape(argument.fn.name === `ExportMaps.${name}` && same(argument.args, [K, variable('same')]), 'wrong reflection premise');
  }
  const comparator = variable('same');
  const comparison = application(comparator, [key, query]);
  const truth = { tag: 'ctor', name: data + 'bool', index: 0 };
  const comparisonTrue = application({ tag: 'ind', name: logic + 'eq' }, [{ tag: 'ind', name: data + 'bool' }, comparison, truth]);
  requireShape(equivalent(apply('ExportMaps.boolean_relation', [K, comparator, key, query]), comparisonTrue),
    'Boolean relation is not this comparison equalling true');
  const decision = spine(apply('ExportMaps.boolean_decision', [K, comparator]));
  requireShape(decision.fn.tag === 'ctor' && decision.fn.name === rel + 'RelDec' &&
    equivalent(decision.args, [K, instance.args[1], comparator]), 'decision dictionary changes the comparison');
  const correct = spine(apply('ExportMaps.boolean_correct', [K, comparator]));
  requireShape(correct.fn.tag === 'ctor' && correct.fn.name === rel + 'RelDec_Correct' && correct.args.length === 4 &&
    equivalent(correct.args.slice(0, 3), [K, instance.args[1], instance.args[2]]), 'correctness dictionary changes its relation or decision');
  const witness = variable('witness');
  const identity = { tag: 'lam', variable: witness, type: comparisonTrue, body: witness };
  const implication = { tag: 'pi', variable: witness, type: comparisonTrue, body: comparisonTrue };
  const reflexivity = ctor(logic + 'and', 0, implication, implication, identity, identity);
  requireShape(equivalent(reduce(application(correct.args[3], [key, query])), reflexivity), 'the reflection premise is not the two identity implications');
  // Source type is checked in full after specialization, not inferred from its name.
  const statement = source.get(map + 'remove_eq_alist').type;
  const parameters = telescope(statement).parameters;
  requireShape(parameters.length === 7, 'unexpected theorem premises');
  let goal = statement;
  for (const argument of [K, R, D, V, C, rest, query]) goal = substitute(goal.body, goal.variable.name, argument);
  const equality = spine(goal), lookup = spine(equality.args[1]), erased = spine(lookup.args[5]);
  requireShape(equality.fn.name === logic + 'eq' && equality.args.length === 3 &&
    lookup.fn.name === map + 'alist_find' && same(lookup.args.slice(0, 5), [K, R, D, V, query]) &&
    erased.fn.name === map + 'alist_remove' && same(erased.args, [K, R, D, V, query, rest]) &&
    spine(equality.args[2]).fn.name === data + 'option' && spine(equality.args[2]).fn.index === 1,
    'the source theorem does not state lookup after deletion is absent');
  const actualStatement = specialize(source.get('ExportMaps.removal_absence').type, [K, V, comparator, rest, query]);
  const expectedStatement = substitute(substitute(goal, R.name, instance.args[1]), D.name, instance.args[2]);
  requireShape(equivalent(actualStatement, expectedStatement), 'the instance statement changes the original conclusion');
  const optionalValue = application({ tag: 'ind', name: data + 'option' }, [V]);
  requireShape(equivalent(specialize(source.get(map + 'alist_find').type, [K, R, D, V, query, rest]), optionalValue),
    'lookup has a different codomain');
  requireShape(equivalent(specialize(source.get(map + 'alist_remove').type, [K, R, D, V, query, rest]),
    application({ tag: 'const', name: map + 'alist' }, [K, V])), 'deletion has a different carrier');

  const finder = apply(map + 'alist_find', [K, R, D, V]);
  requireShape(finder.argument === 1, 'lookup does not recurse on its list');
  const findNil = emit(unfold(finder, [query, nil], 'find_rec'));
  const findCons = unfold(finder, [query, cons], 'find_rec');
  const choices = branches(findCons, 2);
  const findCondition = emit(findCons.value);
  const findBody = choices.map(branch => emit(branch.body));

  const removal = spine(apply(map + 'alist_remove', [K, R, D, V, query, rest]));
  requireShape(removal.fn.name === 'Stdlib.Lists.List.filter' && same(removal.args[2], rest), 'removal is not source filtering');
  const filtering = apply('Stdlib.Lists.List.filter', removal.args.slice(0, 2));
  requireShape(filtering.argument === 0, 'filter does not recurse on its list');
  const removeNil = emit(unfold(filtering, [nil], 'remove_rec'));
  const removeCons = unfold(filtering, [cons], 'remove_rec');
  const keep = branches(removeCons, 2);
  const removeCondition = emit(removeCons.value);
  const recursiveRemove = application(variable('remove_rec'), [rest]);
  function shareTail(node) {
    if (same(node, recursiveRemove)) return variable('tail');
    if (!node || typeof node !== 'object') return node;
    if (Array.isArray(node)) return node.map(shareTail);
    return Object.fromEntries(Object.entries(node).map(([key, value]) => [key, shareTail(value)]));
  }
  const keepBody = keep.map(branch => emit(shareTail(branch.body)));

  const proof = spine(apply(map + 'remove_eq_alist', [K, R, D, V, C, rest, query]));
  requireShape(proof.fn.name === data + 'list_ind' && proof.args.length === 6 && same(proof.args[4], rest) && same(proof.args[5], query),
    'the proof is not the original list induction');
  const base = emit(reduce(application(proof.args[2], [query])));
  const step = reflected(application(proof.args[3], [pair, rest, variable('induction'), query]));
  requireShape(step.tag === 'reflection' && same(step.comparison, [query, key]), 'unexpected proof comparison');
  const yes = emit(step.yes), no = emit(step.no);

  return `import Base

# Generated from ExtLib FMapAList definitions and remove_eq_alist's proof body.
# Nat keys use the Boolean-relation instance in scripts/ExportMaps.v.
# Source copyright ExtLib contributors; BSD-2-Clause (theory/EXTLIB-LICENSE).

def Entry(-V: Data) -> Data:
  Sigma<&2, &2, Nat, (_ => V)>

def choose(~V: Data, hit: Bool, value: V, tail: Maybe<&2, V>) -> Maybe<&2, V>:
  match hit:
    case True{}: ${findBody[0]}
    case False{}: ${findBody[1].replace('find(~V, rest, query)', 'tail')}

def find(~V: Data, entries: +List<Entry(V)>, +query: Nat) -> Maybe<&2, V>:
  match entries:
    case Nil{}: ${findNil}
    case Con{(+key, value), rest}: choose(~V, ${findCondition}, value, find(~V, rest, query))

def keep(~V: Data, retained: Bool, key: Nat, value: V, tail: +List<Entry(V)>) -> +List<Entry(V)>:
  match retained:
    case True{}: ${keepBody[0]}
    case False{}: ${keepBody[1]}

def remove(~V: Data, entries: +List<Entry(V)>, +query: Nat) -> +List<Entry(V)>:
  match entries:
    case Nil{}: ${removeNil}
    case Con{(+key, value), rest}: keep(~V, ${removeCondition}, key, value, remove(~V, rest, query))

# A reflected source case becomes a Boolean case plus equality transport.
# Both leaf proofs below are translated source leaves, not a target proof search.
def absence_case(~V: Data, +hit: Bool, +key: Nat, +value: V, +rest: +List<Entry(V)>, +query: Nat,
  observed: {Nat.is_eq(query, key) == hit : Bool},
  induction: {find(~V, remove(~V, rest, query), query) == None{} : Maybe<&2, V>}) ->
  {find(~V, keep(~V, Bool.not(hit), key, value, remove(~V, rest, query)), query) == None{} : Maybe<&2, V>}:
  match hit:
    case True{}: ${yes}
    case False{}:
      backwards = Equal.sym(Bool, Nat.is_eq(query, key), False{}, observed)
      %backwards : {choose(~V, _, value, find(~V, remove(~V, rest, query), query)) == None{} : Maybe<&2, V>}
      ${no}

def removal_absence(~V: Data, entries: +List<Entry(V)>, +query: Nat) ->
  {find(~V, remove(~V, entries, query), query) == None{} : Maybe<&2, V>}:
  match entries:
    case Nil{}: ${base}
    case Con{(+key, value), +rest}:
      absence_case(~V, Nat.is_eq(query, key), key, value, rest, query, {==}, removal_absence(~V, rest, query))
`;
}

function run(command, args) {
  const result = spawnSync(command, args, { cwd: root, encoding: 'utf8', timeout: 60_000, maxBuffer: 8 * 1024 * 1024 });
  if (result.error || result.status !== 0) throw new Error(`${command}: ${result.error?.message ?? result.stderr ?? result.stdout}`);
  return result.stdout.trim();
}
async function refresh() {
  const directory = await mkdtemp(path.join(tmpdir(), 'selvedge-maps-'));
  try {
    const output = run('rocq', ['c', '-o', path.join(directory, 'ExportMaps.vo'), 'scripts/ExportMaps.v']);
    const entities = [...output.matchAll(/^"SELVEDGE_PROOF:((?:""|[^"])*)"(?:%bs)?$/gm)].map(match => JSON.parse(match[1].replaceAll('""', '"')));
    requireShape((output.match(/Closed under the global context/g) ?? []).length === mapNames.length, 'source assumptions are not closed');
    const library = run('rocq', ['c', '-where']), sources = {};
    for (const name of ['ExtLib/Data/Map/FMapAList', 'ExtLib/Core/RelDec', 'ExtLib/Tactics/Consider', 'Stdlib/Lists/List']) {
      sources[name] = digest(await readFile(path.join(library, 'user-contrib', name + '.v')));
    }
    const target = translateMaps(entities);
    await writeFile(bundlePath, JSON.stringify({ format: 'rocq-template-certificates-2',
      rocq: run('rocq', ['--version']).split('\n')[0], extlib: run('opam', ['var', 'coq-ext-lib:version']),
      stdlib: run('opam', ['var', 'rocq-stdlib:version']), metarocq: run('opam', ['var', 'rocq-metarocq-template:version']),
      source: 'https://github.com/coq-community/coq-ext-lib',
      sources, entitiesSha256: digest(JSON.stringify(entities)), entities }, null, 2) + '\n');
    await writeFile(targetPath, target);
  } finally { await rm(directory, { recursive: true, force: true }); }
}
export async function checkMaps() {
  const bundle = JSON.parse(await readFile(bundlePath, 'utf8'));
  requireShape(bundle.format === 'rocq-template-certificates-2' && bundle.entitiesSha256 === digest(JSON.stringify(bundle.entities)), 'invalid format or digest');
  requireShape(await readFile(targetPath, 'utf8') === translateMaps(bundle.entities), 'target differs from its pinned source terms');
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (process.argv.includes('--refresh')) await refresh();
  else await checkMaps();
}
