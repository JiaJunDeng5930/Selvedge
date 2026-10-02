import Base
import ../CHATGPT.bend as G
import ../FEATURES.bend as F
import ../MODEL.bend as M
import ./component.bend as C
import ./domain.bend as D
import ./json.bend as J
import ./chatgpt.bend as Actual
import ./chatgpt-spec.bend as Spec
import ./chatgpt-state.bend as State
import ./chatgpt-view.bend as View
import ./association-map.bend as Finite
import ../BOARD.bend as Board

# This boundary is constructed at the root against the actual interpreter and
# assembly. Capabilities have no conversation coordinate. Pure proofs do not
# claim that an OS process can undo a mutation or that a tunnel authenticates.
type Boundary is Type:
  Boundary{
    refinement: @+change:G.Change -> @+state:G.State ->
      {Actual.realize(change, state) == Spec.meaning(change, state) : C.Decision<G.State, G.Effect>},
    assembled: @+change:G.Change -> @+world:M.World() ->
      {State.embed(Actual.realize(change, State.registry(world)), world) ==
       State.embed(Spec.meaning(change, State.registry(world)), world) : M.Decision()},
    written: @+value:G.State -> @+world:M.World() -> {State.registry(State.store(value, world)) == value : G.State},
    core_frame: @+value:G.State -> @+world:M.World() ->
      {C.local(D.State, F.State(), State.store(value, world)) == C.local(D.State, F.State(), world) : D.State},
    board_frame: @+value:G.State -> @+world:M.World() ->
      {F.board(C.rest(D.State, F.State(), State.store(value, world))) == F.board(C.rest(D.State, F.State(), world)) : Board.State},
    rest_frame: @+value:G.State -> @+world:M.World() ->
      {F.rest(C.rest(D.State, F.State(), State.store(value, world))) == F.rest(C.rest(D.State, F.State(), world)) : F.Rest()},
    board_preserves: @+value:Board.State -> @+features:F.State() ->
      {F.chatgpt(F.with_board(value, features)) == F.chatgpt(features) : G.State},
    ownership: @+connection:Nat -> @+project:Nat -> @+owner:Nat -> @+target:Nat -> @+request:String -> @+arguments:J.Json ->
      @+workspace:D.Workspace -> @+sandbox:D.Sandbox -> @+outcome:G.Outcome ->
      {G.owned(connection, project, G.Job{owner, target, request, arguments, workspace, sandbox, outcome}) ==
       (Nat.is_eq(connection, owner) && Nat.is_eq(project, target)) : Bool},
    denied: @+connection:Nat -> @+project:Nat -> @+request:String -> @+arguments:J.Json -> @+projects:D.Projects -> @+state:G.State ->
      {G.run_authorized(None{}, connection, project, request, arguments, projects, state) ==
       G.Refuse{"project_forbidden", "This connection has no grant for that project"} : G.Resolution},
    hidden: @+connection:Nat -> @+project:Nat -> @+id:Nat -> @+state:G.State ->
      {View.read_job(None{}, connection, project, id, state) == View.forbidden() : J.Json},
    removed: @+id:Nat -> @+state:G.State ->
      {Finite.find(~G.Job, G.jobs(Actual.result_state(Actual.realize(G.Remove{id}, state))), id) == None{} : Maybe<&2, G.Job>},
    restarted: @+connection:Nat -> @+project:Nat -> @+request:String -> @+arguments:J.Json -> @+workspace:D.Workspace -> @+sandbox:D.Sandbox ->
      {G.outcome(G.recover_job(G.Job{connection, project, request, arguments, workspace, sandbox, G.Running{}})) ==
       G.Interrupted{"Service restarted; execution may have happened and will not be replayed"} : G.Outcome}}

law boundary:
  Boundary
