import test from 'node:test';
import { beforeAll, afterAll } from 'bun:test';
import assert from 'node:assert/strict';
import { mkdir, mkdtemp, writeFile, rm } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { compileJavaScript } from '../scripts/compile-javascript.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const executionFields = 'initial, valid, run, meaning, world, reply, effects, durable, replay';
const executionEvidence = 'Categories.Intersection{Model.ExecutionSafety{initial_valid, preserves_valid}, Categories.Intersection{Model.ExecutionRefinement{refinement}, Categories.Intersection{Model.ExecutionObservation{query_world, query_effects, query_not_durable}, Model.ExecutionHistory{replay_valid, query_replay}}}}';
const applicationFields = 'initial, user, snapshot_event, completed_event, run, state, effects, finish, program, sequence, lookup, snapshot, settle, observe';
const applicationEvidence = 'Categories.Intersection{Model.ApplicationInitialization{initial_program}, Categories.Intersection{Model.ApplicationCorrelation{snapshot_dispatch, completion_dispatch}, Model.ApplicationOrdering{stale_snapshot, unknown_completion}}}';
const imports = `import Base
import ../../MODEL.bend as Model
import ../../PROOF.bend as Proof
import ../../harness/MODEL.bend as Commands
import ../../bendlib/json.bend as Json
import ../../bendlib/categories.bend as Categories
`;
const unpackSystem = `  (World, (Decision, system)) = packed
  Model.System{execution, packed_interface, host_adapters} = system`;
const unpackInterface = `  (State, (Input, (Result, (Pending, (Effect, interface))))) = packed_interface
  Model.Interface{application, packed_display} = interface`;

// This client stays generic even when main supplies the concrete production instance.
const client = `${imports}
def is_empty(-Element: Data, values: +List<Element>) -> Bool:
  match values:
    case Nil{}: True{}
    case Con{head, tail}: False{}

def execution_client_plain(-World: Data, -Decision: Data, execution: Categories.Membership<Model.ExecutionOperations<World, Decision>, Model.execution(World, Decision)>) -> World & Bool:
  Categories.Membership{Model.ExecutionOperations{${executionFields}}, ${executionEvidence}} = execution
  +initial_world = initial
  +read_only_query = {Commands.UserCommand{Commands.Observe{Commands.ListProjects{}}} : Commands.Input}
  query_empty = is_empty(Commands.Effect(), effects(run(read_only_query, initial_world)))
  +replayed_world = replay({read_only_query <> read_only_query <> Nil{} : +List<Commands.Input>}, initial_world)
  (replayed_world, Bool.and(valid(replayed_world), query_empty))

def execution_client(-World: Data, -Decision: Data, execution: Model.Execution(World, Decision)) -> World & Bool:
  execution_client_plain(World, Decision, Model.execution_operations(World, Decision, execution))

def application_decision(-World: Data, -State: Data, -Decision: Data, -Pending: Data,
  snapshot: @serial:Nat -> @world:World -> @state:State -> Decision,
  settle: @pending:+Maybe<Pending> -> @serial:Nat -> @world:World -> @reply:Json.Json -> @state:State -> Decision,
  +initial_world: World, +application_state: State, mode: Bool) -> Decision:
  match mode:
    case True{}: snapshot(0n, initial_world, application_state)
    case False{}: settle(None{}, 0n, initial_world, Json.Null{}, application_state)

def application_client_plain(-World: Data, -State: Data, -Input: Data, -Decision: Data, -Pending: Data, -Effect: Data,
  application: Categories.Membership<Model.ApplicationOperations<World, State, Input, Decision, Pending, Effect>, Model.application(World, State, Input, Decision, Pending, Effect)>, +initial_world: World, mode: Bool) -> Bool:
  Categories.Membership{Model.ApplicationOperations{${applicationFields}}, ${applicationEvidence}} = application
  +application_state = initial(initial_world, 1n)
  decision = application_decision(World, State, Decision, Pending, snapshot, settle, initial_world, application_state, mode)
  is_empty(Effect, effects(decision))

def application_client(-World: Data, -State: Data, -Input: Data, -Decision: Data, -Pending: Data, -Effect: Data,
  application: Model.Application(World, State, Input, Decision, Pending, Effect), +initial_world: World, mode: Bool) -> Bool:
  application_client_plain(World, State, Input, Decision, Pending, Effect,
    Model.application_operations(World, State, Input, Decision, Pending, Effect, application), initial_world, mode)

def apply_client(-World: Data, -State: Data, -Input: Data, -Decision: Data, -Pending: Data, -Effect: Data,
  result: World & Bool, application: Model.Application(World, State, Input, Decision, Pending, Effect), mode: Bool) -> Bool:
  (initial_world, execution_valid) = result
  Bool.and(execution_valid, application_client(World, State, Input, Decision, Pending, Effect, application, initial_world, mode))

def client(packed: Model.SystemModel(), mode: Bool) -> Bool:
${unpackSystem}
${unpackInterface}
  apply_client(World, State, Input, Result, Pending, Effect, execution_client(World, Decision, execution), application, mode)

def main() -> Bool:
  Bool.and(client(Proof.system(), True{}), client(Proof.system(), False{}))
`;

let main;
beforeAll(async () => {
  const build = path.join(root, '.build');
  await mkdir(build, { recursive: true });
  const directory = await mkdtemp(path.join(build, 'model-abstraction-'));
  afterAll(() => rm(directory, { recursive: true, force: true }));
  const entry = path.join(directory, 'client.bend');
  const output = path.join(directory, 'client.mjs');
  await writeFile(entry, client);
  // Use the production emitter to execute operations without normalizing the dependent system.
  await compileJavaScript({ entry, output, exports: { main: 'main' } });
  ({ main } = await import(pathToFileURL(output).href));
}, 900_000);

test('generic operational clients use production fields and laws while carriers remain abstract', { timeout: 300_000 }, () => {
  assert.equal(main(), true);
});
