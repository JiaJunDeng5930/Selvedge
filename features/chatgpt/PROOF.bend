import Base
import ../../bendlib/categories.bend as Categories
import ../../bendlib/json.bend as J
import ./MODEL.bend as G
import ../../harness/features/MODEL.bend as F
import ../../harness/MODEL.bend as M
import ../../bendlib/component.bend as C
import ../../harness/DOMAIN.bend as D
import ./PROGRAM.bend as Actual
import ./SPEC.bend as Spec
import ./STATE.bend as State
import ./CONTRACT.bend as Boundary
import ../../bendlib/association-map.bend as Finite
import ../board/MODEL.bend as Board

def refinement(+change: G.Change, +state: G.State) ->
  {Actual.realize_calculation(change, state) == Spec.meaning(change, state) : C.Decision<G.State, G.Effect>}:
  match change state:
    case G.SetGrants{entries} G.State{grants, jobs, next}: {==}
    case G.Start{id, job} G.State{grants, jobs, next}: {==}
    case G.Reuse{id, job} G.State{grants, jobs, next}: {==}
    case G.Interrupt{id, job} G.State{grants, jobs, next}: {==}
    case G.Remove{id} G.State{grants, jobs, next}: {==}
    case G.Complete{id, job, value, error} G.State{grants, jobs, next}: {==}

def assembled(+change: G.Change, +world: M.World()) ->
  {State.embed(Actual.realize_calculation(change, State.registry(world)), world) ==
   State.embed(Spec.meaning(change, State.registry(world)), world) : M.Decision()}:
  Equal.cong(C.Decision<G.State, G.Effect>, M.Decision(), decision => State.embed(decision, world),
    Actual.realize_calculation(change, State.registry(world)), Spec.meaning(change, State.registry(world)), refinement(change, State.registry(world)))

def written(+value: G.State, +world: M.World()) ->
  {State.registry(State.store(value, world)) == value : G.State}:
  match world:
    case C.Frame{core, C.Frame{board, C.Frame{previous, rest}}}: {==}

def core_frame(+value: G.State, +world: M.World()) ->
  {C.local(D.State, F.State(), State.store(value, world)) == C.local(D.State, F.State(), world) : D.State}:
  match world:
    case C.Frame{core, C.Frame{board, C.Frame{previous, rest}}}: {==}

def board_frame(+value: G.State, +world: M.World()) ->
  {F.board(C.rest(D.State, F.State(), State.store(value, world))) == F.board(C.rest(D.State, F.State(), world)) : Board.State}:
  match world:
    case C.Frame{core, C.Frame{board, C.Frame{previous, rest}}}: {==}

def removed(+id: Nat, +state: G.State) ->
  {Finite.find(~G.Job, G.jobs(Actual.result_state(Actual.realize_calculation(G.Remove{id}, state))), id) == None{} : Maybe<&2, G.Job>}:
  match state:
    case G.State{grants, jobs, next}: Finite.removal_absence(~G.Job, jobs, id)

def rest_frame(+value: G.State, +world: M.World()) ->
  {F.rest(C.rest(D.State, F.State(), State.store(value, world))) == F.rest(C.rest(D.State, F.State(), world)) : F.Rest()}:
  match world:
    case C.Frame{core, C.Frame{board, C.Frame{previous, rest}}}: {==}

def board_preserves(+value: Board.State, +features: F.State()) ->
  {F.chatgpt(F.with_board(value, features)) == F.chatgpt(features) : G.State}:
  match features:
    case C.Frame{board, modules}: {==}

def ownership(+connection: Nat, +project: Nat, +job: G.Job) ->
  {G.owned(connection, project, job) ==
   (Nat.is_eq(connection, G.job_connection(job)) && Nat.is_eq(project, G.job_project(job))) : Bool}:
  match job:
    case G.Job{owner, target, request, arguments, workspace, sandbox, outcome}: {==}

def restarted(+job: G.Job, running: {G.outcome(job) == G.Running{} : G.Outcome}) ->
  {G.outcome(G.recover_job(job)) ==
   G.Interrupted{"Service restarted; execution may have happened and will not be replayed"} : G.Outcome}:
  G.Job{connection, project, request, arguments, workspace, sandbox, outcome} = job
  Equal.cong(G.Outcome, G.Outcome,
    value => G.outcome(G.recovered(G.pending(value), G.Job{connection, project, request, arguments, workspace, sandbox, outcome})),
    outcome, G.Running{}, running)

def Boundary.boundary():
  Boundary.Boundary{refinement, assembled, written, core_frame, board_frame, rest_frame, board_preserves,
    ownership,
    connection => project => request => arguments => projects => state => {==},
    connection => project => id => state => {==},
    removed,
    restarted}

def command_calculation(construction: Categories.Construction<G.CommandRequest, G.Resolution>) -> C.Decision<G.State, G.Effect>:
  Categories.Construction{G.CommandRequest{command, +state, projects}, resolution} = construction
  Actual.resolution_calculation(G.resolve(command, state, projects), state)

def command_equation(member: G.ConstructedCommand()) ->
  {Actual.realize(member) ==
   command_calculation(Categories.value(Categories.Construction<G.CommandRequest, G.Resolution>,
     Categories.constructed_by(G.CommandRequest, G.Resolution, G.request_resolution), member)) : C.Decision<G.State, G.Effect>}:
  Categories.Membership{Categories.Construction{G.CommandRequest{command, +state, projects}, +resolution}, evidence} = member
  Equal.cong(G.Resolution, C.Decision<G.State, G.Effect>, value => Actual.resolution_calculation(value, state),
    resolution, G.resolve(command, state, projects), evidence)

def constructed_command_equation(+command: G.Command, +state: G.State, +projects: D.Projects) ->
  {Actual.realize(G.construct_command(command, state, projects)) ==
   Actual.resolution_calculation(G.resolve(command, state, projects), state) : C.Decision<G.State, G.Effect>}:
  command_equation(G.construct_command(command, state, projects))

def completion_calculation(construction: Categories.Construction<G.CompletionRequest, Maybe<&2, G.Change>>) -> Maybe<&2, C.Decision<G.State, G.Effect>>:
  Categories.Construction{G.CompletionRequest{+id, value, error, +state}, change} = construction
  Actual.completion_calculation(G.settle(Finite.find(~G.Job, G.jobs(state), id), id, value, error), state)

def completion_equation(member: G.ConstructedCompletion()) ->
  {Actual.realize_completion(member) ==
   completion_calculation(Categories.value(Categories.Construction<G.CompletionRequest, Maybe<&2, G.Change>>,
     Categories.constructed_by(G.CompletionRequest, Maybe<&2, G.Change>, G.completion_resolution), member)) : Maybe<&2, C.Decision<G.State, G.Effect>>}:
  Categories.Membership{Categories.Construction{G.CompletionRequest{+id, value, error, +state}, +change}, evidence} = member
  Equal.cong(Maybe<&2, G.Change>, Maybe<&2, C.Decision<G.State, G.Effect>>,
    value => Actual.completion_calculation(value, state), change,
    G.settle(Finite.find(~G.Job, G.jobs(state), id), id, value, error), evidence)

def constructed_completion_equation(+id: Nat, +value: J.Json, +error: Bool, +state: G.State) ->
  {Actual.realize_completion(G.construct_completion(id, value, error, state)) ==
   Actual.completion_calculation(G.settle(Finite.find(~G.Job, G.jobs(state), id), id, value, error), state) : Maybe<&2, C.Decision<G.State, G.Effect>>}:
  completion_equation(G.construct_completion(id, value, error, state))
