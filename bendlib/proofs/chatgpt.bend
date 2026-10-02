import Base
import ../../CHATGPT.bend as G
import ../../FEATURES.bend as F
import ../../MODEL.bend as M
import ../component.bend as C
import ../domain.bend as D
import ../chatgpt.bend as Actual
import ../chatgpt-spec.bend as Spec
import ../chatgpt-state.bend as State
import ../chatgpt-architecture.bend as Boundary
import ../association-map.bend as Finite
import ../../BOARD.bend as Board

def refinement(+change: G.Change, +state: G.State) ->
  {Actual.realize(change, state) == Spec.meaning(change, state) : C.Decision<G.State, G.Effect>}:
  match change state:
    case G.SetGrants{entries} G.State{grants, jobs, next}: {==}
    case G.Start{id, job} G.State{grants, jobs, next}: {==}
    case G.Reuse{id, job} G.State{grants, jobs, next}: {==}
    case G.Interrupt{id, job} G.State{grants, jobs, next}: {==}
    case G.Remove{id} G.State{grants, jobs, next}: {==}
    case G.Complete{id, job, value, error} G.State{grants, jobs, next}: {==}

def assembled(+change: G.Change, +world: M.World()) ->
  {State.embed(Actual.realize(change, State.registry(world)), world) ==
   State.embed(Spec.meaning(change, State.registry(world)), world) : M.Decision()}:
  Equal.cong(C.Decision<G.State, G.Effect>, M.Decision(), decision => State.embed(decision, world),
    Actual.realize(change, State.registry(world)), Spec.meaning(change, State.registry(world)), refinement(change, State.registry(world)))

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
  {Finite.find(~G.Job, G.jobs(Actual.result_state(Actual.realize(G.Remove{id}, state))), id) == None{} : Maybe<&2, G.Job>}:
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

def Boundary.boundary():
  Boundary.Boundary{refinement, assembled, written, core_frame, board_frame, rest_frame, board_preserves,
    connection => project => owner => target => request => arguments => workspace => sandbox => outcome => {==},
    connection => project => request => arguments => projects => state => {==},
    connection => project => id => state => {==},
    removed,
    connection => project => request => arguments => workspace => sandbox => {==}}
