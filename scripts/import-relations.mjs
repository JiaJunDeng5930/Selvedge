// A syntax-directed, untrusted lowering of quoted relation proofs. Inlining
// specializes the ORIGINAL eliminator; it never searches for a replacement.
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFile, writeFile, mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { decoder, substitute, application, telescope, spine } from './import-stdlib.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const bundlePath = path.join(root, 'theory/relation-certificates.json');
const targetPath = path.join(root, 'bendlib/relations.bend');
const defs = 'Corelib.Relations.Relation_Definitions.';
const ops = 'Stdlib.Relations.Relation_Operators.';
const props = 'Stdlib.Relations.Operators_Properties.';
const closure = `${ops}clos_refl_trans`;
const preorder = `${defs}preorder`;
export const relationNames = [
  `${defs}relation`, `${defs}inclusion`,
  `${ops}clos_refl_trans_ind`, `${props}clos_refl_trans_ind_left`,
  `${props}clos_rt_is_preorder`, `${props}clos_rt_idempotent`,
  'ExportRelations.closure_map', 'ExportRelations.closure_invariant',
];
const dependencies = new Set(relationNames.slice(0, 4));
const digest = value => createHash('sha256').update(value).digest('hex');
const variable = name => ({ tag: 'var', name });
const short = name => name.slice(name.lastIndexOf('.') + 1);

// Equality witnesses reify only the dependent reflexive constructor. All path
// endpoints are erased indices, not arguments inspected before structural
// recursion. This is the exact three-constructor reflexive-transitive closure.
const representation = `import Base

# Generated from quoted Rocq relation proofs; do not edit.
# Source copyright INRIA, CNRS and contributors; LGPL-2.1 (theory/LICENSE).
# Applications in ExportRelations.v only supply an existing theorem's premises.

type Closure<-A: Data, -R: @-x:A -> @-y:A -> Type, -x:A, -y:A> is Type:
  Step{edge: R(x, y)}
  Refl{same: {x == y : A}}
  Trans{-middle: A, left: Closure<A, R, x, middle>, right: Closure<A, R, middle, y>}

type Preorder<-A: Data, -R: @-x:A -> @-y:A -> Type> is Type:
  Preorder{reflexive: @-x:A -> R(x, x),
    transitive: @-x:A -> @-y:A -> @-z:A -> R(x, y) -> R(y, z) -> R(x, z)}

def rt_step(-A: Data, -R: @-x:A -> @-y:A -> Type, -x:A, -y:A, edge:R(x,y)) -> Closure<A,R,x,y>:
  Step{edge}

def rt_refl(-A: Data, -R: @-x:A -> @-y:A -> Type, -x:A) -> Closure<A,R,x,x>:
  Refl{{==}}

def rt_trans(-A: Data, -R: @-x:A -> @-y:A -> Type, -x:A, -y:A, -z:A,
  left:Closure<A,R,x,y>, right:Closure<A,R,y,z>) -> Closure<A,R,x,z>:
  Trans{y, left, right}

`;

// Alpha comparison validates constant arguments removed by specialization.
// Ignoring a changed induction callback would silently change the source proof.
function uses(node, name) {
  if (!node || typeof node !== 'object') return false;
  if (node.tag === 'var') return node.name === name;
  return Object.values(node).some(value => uses(value, name));
}
function alpha(node, bound = []) {
  if (!node || typeof node !== 'object') return node;
  if (Array.isArray(node)) return node.map(x => alpha(x, bound));
  if (node.tag === 'var') {
    const index = bound.indexOf(node.name);
    return index < 0 ? ['free', node.name] : ['bound', index];
  }
  if (node.tag === 'lam' || node.tag === 'pi') {
    // Generalized induction changes the type of its unused prefix witness.
    // Only an unused lambda domain is irrelevant to this specialization; a
    // changed used argument or body is still rejected. Source statements are
    // emitted in full, never compared or weakened by this procedure.
    const domain = node.tag === 'lam' && !uses(node.body, node.variable.name) ? ['unused-domain'] : alpha(node.type, bound);
    return [node.tag, domain, alpha(node.body, [node.variable.name, ...bound])];
  }
  return Object.fromEntries(Object.entries(node).map(([key, value]) => [key, alpha(value, bound)]));
}
const equivalent = (left, right) => JSON.stringify(alpha(left)) === JSON.stringify(alpha(right));

// Commute an application through an existing case, retaining every source
// branch. This exposes beta-redexes in generalized induction, not new cases.
function reduce(node) {
  if (!node || typeof node !== 'object') return node;
  if (Array.isArray(node)) return node.map(reduce);
  let result = Object.fromEntries(Object.entries(node).map(([key, value]) => [key, reduce(value)]));
  if (result.tag === 'app') {
    result = application(result.fn, result.args);
    if (result.tag === 'app' && result.fn.tag === 'case') {
      return reduce({ ...result.fn, branches: result.fn.branches.map(branch => ({
        ...branch, body: application(branch.body, result.args),
      })) });
    }
  }
  return result;
}

function compile([name, sourceType, sourceBody], entities) {
  const decode = decoder({ constants: new Set(relationNames), inductives: { [closure]: 3, [preorder]: 1 } });
  const source = new Map(entities.map(entry => [entry[0], entry]));
  function expand(node, stack = []) {
    if (!node || typeof node !== 'object') return node;
    if (Array.isArray(node)) return node.map(x => expand(x, stack));
    if (node.tag === 'const' && dependencies.has(node.name)) {
      if (stack.includes(node.name)) throw new Error('Cyclic source proof dependency');
      return expand(decode(source.get(node.name)[2]), [...stack, node.name]);
    }
    return Object.fromEntries(Object.entries(node).map(([key, value]) => [key, expand(value, stack)]));
  }
  const { parameters, result } = telescope(reduce(expand(decode(sourceType))));
  const types = new Map(parameters.map(p => [p.variable.name, p.type]));
  const carriers = new Set(parameters.filter(p => p.type.tag === 'sort' && p.type.kind === 'Type').map(p => p.variable.name));
  const data = type => type.tag === 'var' && carriers.has(type.name);
  function logical(type) {
    if (type.tag === 'pi') return logical(type.body);
    if (type.tag === 'sort') return type.kind === 'Prop';
    if (type.tag === 'var') return types.get(type.name)?.kind === 'Prop';
    if (type.tag === 'app') {
      if (type.fn.tag === 'ind') return [closure, preorder].includes(type.fn.name);
      if (type.fn.tag === 'var') {
        const signature = types.get(type.fn.name);
        return signature ? logical(signature) : false;
      }
    }
    return false;
  }
  const templates = parameters.filter(p => p.type.tag === 'sort' || p.type.tag === 'pi');
  const ordinary = parameters.filter(p => !templates.includes(p));
  const ordered = [...templates, ...ordinary];
  const method = short(name);
  let recursion;

  function emit(node) {
    if (node.tag === 'var') return node.name;
    if (node.tag === 'sort') return node.kind === 'Type' ? 'Data' : 'Type';
    if (node.tag === 'pi') {
      return `@${data(node.type) && logical(node) ? '-' : ''}${node.variable.name}:${emit(node.type)} -> ${emit(node.body)}`;
    }
    if (node.tag === 'lam') {
      return `(${node.variable.name} => ${emit(node.body)})`;
    }
    if (node.tag !== 'app') throw new Error(`Unsupported relation expression: ${node.tag}`);
    const { fn, args } = node;
    if (fn.tag === 'var' && recursion?.name === fn.name) {
      if (args.length !== recursion.args.length) throw new Error('Partially applied relation recursion');
      for (let index = 0; index < args.length; index++) {
        if (!recursion.slots.has(index) && !equivalent(args[index], recursion.args[index])) {
          throw new Error(`${method}: a specialized relation recursion changes its captured argument ${index}`);
        }
      }
      return `${method}(${ordered.map(p => {
        const slot = recursion.parameters.get(p.variable.name);
        const value = slot === undefined ? p.variable : args[slot];
        return `${templates.includes(p) ? '~' : ''}${emit(value)}`;
      }).join(', ')})`;
    }
    const e = args.map(emit);
    if (fn.tag === 'ind' && fn.name === closure) {
      if (args.length === 4) return `Closure<${e.join(', ')}>`;
      if (args.length === 2) return `(closure_x => closure_y => Closure<${e.join(', ')}, closure_x, closure_y>)`;
      if (args.length === 3) return `(closure_y => Closure<${e.join(', ')}, closure_y>)`;
    }
    if (fn.tag === 'ind' && fn.name === preorder && e.length === 2) return `Preorder<${e.join(', ')}>`;
    if (fn.tag === 'ctor' && fn.name === closure) {
      const method = ['rt_step', 'rt_refl', 'rt_trans'][fn.index];
      const arity = [5, 3, 7][fn.index];
      if (e.length >= 2 && e.length <= arity) return `${method}(${e.join(', ')})`;
    }
    if (fn.tag === 'ctor' && fn.name === preorder && e.length === 4) return `Preorder{${e[2]}, ${e[3]}}`;
    if (fn.tag === 'var' || fn.tag === 'lam' || fn.tag === 'app') return `${emit(fn)}(${e.join(', ')})`;
    throw new Error(`Unmapped relation application: ${fn.name ?? fn.tag}`);
  }

  let body = reduce(application(reduce(expand(decode(sourceBody))), parameters.map(p => p.variable)));
  const head = spine(body);
  let code;
  if (head.fn.tag === 'fix') {
    const fixed = head.fn;
    const signature = telescope(fixed.type);
    if (fixed.argument !== 2 || signature.parameters.length < 3 || head.args.length < 3) {
      throw new Error('Unsupported relation eliminator: expected structural recursion on a path');
    }
    const pathType = signature.parameters[2].type;
    if (pathType.tag !== 'app' || pathType.fn.tag !== 'ind' || pathType.fn.name !== closure || pathType.args.length !== 4) {
      throw new Error('A relation eliminator must consume the declared closure');
    }
    const slots = new Map();
    const parameterSlots = new Map();
    head.args.forEach((arg, index) => {
      if (arg.tag === 'var' && ordinary.some(p => p.variable.name === arg.name)) {
        if (parameterSlots.has(arg.name)) throw new Error('Ambiguous relation recursion environment');
        slots.set(index, arg.name);
        parameterSlots.set(arg.name, index);
      }
    });
    if (ordinary.some(p => !parameterSlots.has(p.variable.name))) throw new Error('Unthreaded relation recursion environment');
    recursion = { name: fixed.variable.name, args: head.args, slots, parameters: parameterSlots };
    body = reduce(application(fixed.body, head.args));
    if (body.tag !== 'case' || body.value.tag !== 'var' || body.value.name !== head.args[2].name ||
        body.branches.length !== 3 || body.branches.some((branch, index) => branch.variables.length !== [2, 0, 4][index])) {
      throw new Error('Unsupported relation eliminator branches');
    }
    const [start, end] = head.args;
    if (start.tag !== 'var' || end.tag !== 'var' || !ordinary.some(p => p.variable.name === start.name && data(p.type)) ||
        !ordinary.some(p => p.variable.name === end.name && data(p.type))) throw new Error('Unbound relation endpoints');
    const [edge, endpoint] = body.branches[0].variables;
    const [right, left, last, middle] = body.branches[2].variables;
    const step = reduce(substitute(body.branches[0].body, endpoint.name, end));
    const join = reduce(substitute(body.branches[2].body, last.name, end));
    code = `  match ${emit(body.value)}:\n` +
      `    case Step{${edge.name}}: ${emit(step)}\n` +
      `    case Refl{endpoint_equality}:\n` +
      `      %endpoint_equality : ${emit(substitute(result, end.name, variable('_')))}\n` +
      `      ${emit(body.branches[1].body)}\n` +
      `    case Trans{${middle.name}, ${left.name}, ${right.name}}: ${emit(join)}`;
  } else code = `  ${emit(body)}`;
  const declarations = ordered.map(p => `${templates.includes(p) ? '~' : data(p.type) ? '-' : ''}${p.variable.name}: ${emit(p.type)}`);
  const origin = dependencies.has(name) || name.startsWith('Stdlib.') ? 'Original source theorem' : 'Source theorem application';
  return `# ${origin}: ${name}\ndef ${method}(${declarations.join(', ')}) ->\n  ${emit(result)}:\n${code}\n`;
}

export function translateRelations(entities) {
  if (!Array.isArray(entities) || entities.length !== relationNames.length || entities.some((entry, i) => entry[0] !== relationNames[i])) {
    throw new Error('Unexpected relation certificate manifest');
  }
  return representation + entities.filter(([name]) => !dependencies.has(name)).map(entity => compile(entity, entities)).join('\n');
}

function run(command, args) {
  const result = spawnSync(command, args, { cwd: root, encoding: 'utf8', timeout: 60_000, maxBuffer: 8 * 1024 * 1024 });
  if (result.error || result.status !== 0) throw new Error(`${command} failed: ${result.error?.message ?? result.stderr ?? result.stdout}`);
  return result.stdout.trim();
}

async function refresh() {
  const temporary = await mkdtemp(path.join(tmpdir(), 'selvedge-relations-'));
  try {
    const output = run('rocq', ['c', '-o', path.join(temporary, 'ExportRelations.vo'), 'scripts/ExportRelations.v']);
    const entities = [...output.matchAll(/^"SELVEDGE_PROOF:((?:""|[^"])*)"(?:%bs)?$/gm)]
      .map(match => JSON.parse(match[1].replaceAll('""', '"')));
    if ((output.match(/Closed under the global context/g) ?? []).length !== relationNames.length) {
      throw new Error('Relation certificates must be closed under the global context');
    }
    const translated = translateRelations(entities);
    const library = run('rocq', ['c', '-where']);
    const sources = {};
    for (const [name, relative] of [
      ['Corelib.Relations.Relation_Definitions', 'theories/Relations/Relation_Definitions.v'],
      ['Stdlib.Relations.Relation_Operators', 'user-contrib/Stdlib/Relations/Relation_Operators.v'],
      ['Stdlib.Relations.Operators_Properties', 'user-contrib/Stdlib/Relations/Operators_Properties.v'],
    ]) sources[name] = digest(await readFile(path.join(library, relative)));
    const bundle = { format: 'rocq-relation-certificates-1',
      rocq: run('rocq', ['--version']).split('\n')[0], stdlib: run('opam', ['var', 'rocq-stdlib:version']),
      metarocq: run('opam', ['var', 'rocq-metarocq-template:version']),
      source: 'https://github.com/rocq-prover/stdlib', sources,
      applicationsSha256: digest(await readFile(path.join(root, 'scripts/ExportRelations.v'))),
      entitiesSha256: digest(JSON.stringify(entities)), entities };
    await writeFile(bundlePath, JSON.stringify(bundle, null, 2) + '\n');
    await writeFile(targetPath, translated);
  } finally { await rm(temporary, { recursive: true, force: true }); }
}

export async function checkRelations() {
  const bundle = JSON.parse(await readFile(bundlePath, 'utf8'));
  if (bundle.format !== 'rocq-relation-certificates-1' || bundle.entitiesSha256 !== digest(JSON.stringify(bundle.entities)) ||
      bundle.applicationsSha256 !== digest(await readFile(path.join(root, 'scripts/ExportRelations.v')))) {
    throw new Error('The relation proof bundle has an invalid format, digest or theorem application');
  }
  if (await readFile(targetPath, 'utf8') !== translateRelations(bundle.entities)) throw new Error('The relation certificates differ from their quoted proof terms');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (process.argv.includes('--refresh')) await refresh();
  else await checkRelations();
  console.log('Relation certificate translation is reproducible.');
}
