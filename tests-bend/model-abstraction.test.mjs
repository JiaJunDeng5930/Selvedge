import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdir, mkdtemp, writeFile, rm } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { compiler } from '../scripts/toolchain.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const bend = compiler();
const executionFields = 'initial, valid, run, meaning, world, reply, effects, durable, initial_valid, preserves_valid, refinement, query_world, query_effects, query_not_durable, replay, replay_valid, query_replay';
const applicationFields = 'initial, user, snapshot_event, completed_event, run, state, effects, finish, program, sequence, lookup, snapshot, settle, observe, initial_program, snapshot_dispatch, completion_dispatch, stale_snapshot, unknown_completion';
const displayFields = 'initial, application, program, run, state, effects, observe, publication, pending, updates, retain, initial_application, program_projection, pending_retention';
const imports = `import Base
import ../../MODEL.bend as Model
import ../../PROOF.bend as Proof
import ../../harness/MODEL.bend as Commands
import ../../bendlib/json.bend as Json
`;
const unpackSystem = `  (World, (Decision, system)) = packed
  Model.System{execution, packed_interface} = system`;
const unpackInterface = `  (State, (Input, (Result, (Pending, (Effect, interface))))) = packed_interface
  Model.Interface{application, packed_display} = interface`;

// This client stays generic even when main supplies the concrete production instance.
const client = `${imports}
def is_empty(-Element: Data, values: +List<Element>) -> Bool:
  match values:
    case Nil{}: True{}
    case Con{head, tail}: False{}

def query_effects(-World: Data, -Decision: Data, execution: Model.Execution<World, Decision>, query: Commands.Query, state: World) -> +List<Commands.Effect()>:
  Model.Execution{${executionFields}} = execution
  effects(run(Commands.UserCommand{Commands.Observe{query}}, state))

def query_law(-World: Data, -Decision: Data, execution: Model.Execution<World, Decision>) ->
  @+query:Commands.Query -> @+state:World ->
  {query_effects(World, Decision, execution, query, state) == Nil{} : +List<Commands.Effect()>}:
  Model.Execution{${executionFields}} = execution
  query_effects

def execution_client(-World: Data, -Decision: Data, execution: Model.Execution<World, Decision>) -> World & Bool:
  Model.Execution{${executionFields}} = execution
  +initial_world = initial
  +read_only_query = {Commands.UserCommand{Commands.Observe{Commands.ListProjects{}}} : Commands.Input}
  query_empty = is_empty(Commands.Effect(), effects(run(read_only_query, initial_world)))
  +replayed_world = replay({read_only_query <> read_only_query <> Nil{} : +List<Commands.Input>}, initial_world)
  (replayed_world, Bool.and(valid(replayed_world), query_empty))

def application_decision(-World: Data, -State: Data, -Decision: Data, -Pending: Data,
  snapshot: @serial:Nat -> @world:World -> @state:State -> Decision,
  settle: @pending:+Maybe<Pending> -> @serial:Nat -> @world:World -> @reply:Json.Json -> @state:State -> Decision,
  +initial_world: World, +application_state: State, mode: Bool) -> Decision:
  match mode:
    case True{}: snapshot(0n, initial_world, application_state)
    case False{}: settle(None{}, 0n, initial_world, Json.Null{}, application_state)

def application_client(-World: Data, -State: Data, -Input: Data, -Decision: Data, -Pending: Data, -Effect: Data,
  application: Model.Application<World, State, Input, Decision, Pending, Effect>, +initial_world: World, mode: Bool) -> Bool:
  Model.Application{${applicationFields}} = application
  +application_state = initial(initial_world, 1n)
  decision = application_decision(World, State, Decision, Pending, snapshot, settle, initial_world, application_state, mode)
  is_empty(Effect, effects(decision))

def apply_client(-World: Data, -State: Data, -Input: Data, -Decision: Data, -Pending: Data, -Effect: Data,
  result: World & Bool, application: Model.Application<World, State, Input, Decision, Pending, Effect>, mode: Bool) -> Bool:
  (initial_world, execution_valid) = result
  Bool.and(execution_valid, application_client(World, State, Input, Decision, Pending, Effect, application, initial_world, mode))

def client(packed: Model.SystemModel(), mode: Bool) -> Bool:
${unpackSystem}
${unpackInterface}
  (DisplayState, (DisplayDecision, (Publication, (Fields, (Document, display))))) = packed_display
  Model.Display{${displayFields.split(', ').map(name => `display_${name}`).join(', ')}} = display
  apply_client(World, State, Input, Result, Pending, Effect, execution_client(World, Decision, execution), application, mode)

def main() -> Bool:
  Bool.and(client(Model.system(), True{}), client(Model.system(), False{}))
`;

function leakageProbe(kind) {
  const world = kind === 'world';
  return `${imports}import ../../${world ? 'bendlib/component' : 'browser/runtime/SEMANTICS'}.bend as Concrete
${world ? '' : `
def expose_application(-State: Data, state: State) -> Bool:
  Concrete.State{web, sequence, next_ticket, pending, receipt} = state
  True{}
`}

def expose(packed: Model.SystemModel()) -> Bool:
${unpackSystem}
  Model.Execution{${world ? executionFields : executionFields.replace(/^initial,/, 'execution_initial,')}} = execution
${world ? `  Concrete.Frame{local, rest} = initial` : `${unpackInterface}
  Model.Application{${applicationFields}} = application
  expose_application(State, initial(execution_initial, 0n))`}
${world ? '  True{}' : ''}

def main() -> Bool:
  expose(Model.system())
`;
}

test('generic operational clients use production fields and laws while carriers remain abstract', { timeout: 300_000 }, async t => {
  const build = path.join(root, '.build');
  await mkdir(build, { recursive: true });
  const directory = await mkdtemp(path.join(build, 'model-abstraction-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const compile = (filename, checkOnly = true) => spawnSync(bend, [filename, ...(checkOnly ? ['--check-only'] : [])], {
    cwd: directory, encoding: 'utf8', timeout: 60_000, maxBuffer: 8 * 1024 * 1024,
    env: { ...process.env, BEND_NO_TELEMETRY: '1', NO_COLOR: '1' },
  });
  await writeFile(path.join(directory, 'client.bend'), client);
  const baseline = compile('client.bend');
  assert.equal(baseline.error, undefined);
  assert.equal(baseline.status, 0, baseline.stdout + baseline.stderr);
  assert.match(baseline.stdout, /ALL PROOFS CHECK/);
  const executed = compile('client.bend', false);
  assert.equal(executed.error, undefined);
  assert.equal(executed.status, 0, executed.stdout + executed.stderr);
  assert.match(executed.stdout, /\bTrue\{\}/);
  for (const kind of ['world', 'application']) {
    const filename = `${kind}-leak.bend`;
    await writeFile(path.join(directory, filename), leakageProbe(kind));
    const rejected = compile(filename);
    const diagnostic = rejected.stdout + rejected.stderr;
    await writeFile(path.join(directory, `${kind}-leak.log`), diagnostic);
    assert.equal(rejected.error, undefined, 'A timeout does not establish abstraction');
    assert.notEqual(rejected.status, 0, `The opaque ${kind} carrier accepted a concrete constructor`);
    assert.match(diagnostic, /type mismatch|types? (?:do not|don't) match|expected type|type error|expected : a datatype\s+- observed : (?:World|State)\b/i);
    assert.doesNotMatch(diagnostic, /undefined (?:reference|name)|unresolved import|cannot (?:find|resolve).*import|unsupported syntax|syntax error/i);
  }
});
