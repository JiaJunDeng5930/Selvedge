import Base
import ./task-laws.bend as TaskProof
import ./feature-frame.bend as FrameProof
import ./feature-ui-laws.bend as FeatureUIProof
import ./component.bend as C
import ./domain.bend as D
import ./effects.bend as E
import ./tasks.bend as Tasks
import ./reasoning.bend as Reasoning
import ./reasoning-spec.bend as Spec
import ./reasoning-laws.bend as ReasoningProof
import ../FEATURES.bend as F
import ../BOARD.bend as Board
import ../MODEL.bend as M
import ../PROGRAM.bend as P
import ../UI.bend as UI
import ./board-state.bend as BoardState
import ./feature-ui.bend as FeatureUI
import ./json.bend as J

# Quantification over the remainder type is essential: none of these proofs
# lists the fields or constructors of a particular assembled application.
type Locality is Type:
  Locality{
    task_meaning: @-R:Data -> @+task:D.Task -> @+state:D.State -> @+rest:R ->
      {Tasks.update_world(R, task, C.Frame{state, rest}) == C.Frame{TaskProof.required_update(task, state), rest} : C.Frame<D.State, R>},
    task_update: @-R:Data -> @task:D.Task -> @world:C.Frame<D.State, R> ->
      {C.rest(D.State, R, Tasks.update_world(R, task, world)) == C.rest(D.State, R, world) : R},
    reasoning_meaning: @-R:Data -> @-X:Data -> @+task:D.Task -> @+world:C.Frame<D.State, R> ->
      {Reasoning.start(R, X, task, world) == Spec.start(R, X, task, world) : C.Decision<C.Frame<D.State, R>, E.Effect<X>>},
    reasoning_frame: @-R:Data -> @-X:Data -> @task:D.Task -> @world:C.Frame<D.State, R> ->
      {C.remaining(D.State, R, E.Effect<X>, Reasoning.start(R, X, task, world)) == C.rest(D.State, R, world) : R},
    task_dispatch: @task:D.Task -> @world:M.World() ->
      {P.store(task, world) == Tasks.update_world(F.State(), task, world) : M.World()},
    production_reasoning: @task:D.Task -> @world:M.World() ->
      {C.remaining(D.State, F.State(), M.Effect(), P.model_request_direct(task, world)) == C.rest(D.State, F.State(), world) : F.State()},
    board_written: @+value:Board.State -> @state:F.State() ->
      {F.board(F.with_board(value, state)) == value : Board.State},
    cursor_written: @+value:Board.Cursor -> @cursor:F.Cursor() ->
      {F.board_cursor(F.with_board_cursor(value, cursor)) == value : Board.Cursor},
    board_frame: @value:Board.State -> @world:M.World() ->
      {F.rest(C.rest(D.State, F.State(), BoardState.store(value, world))) == F.rest(C.rest(D.State, F.State(), world)) : F.Rest()},
    board_core_frame: @value:Board.State -> @world:M.World() ->
      {C.local(D.State, F.State(), BoardState.store(value, world)) == C.local(D.State, F.State(), world) : D.State},
    navigation_frame: @event:Board.Navigation -> @previous:M.ViewState -> @reply:J.Json ->
      {FeatureUI.remainder(UI.navigate(M.FeatureEvent{F.BoardEvent{event}}, previous, reply)) == FeatureUI.remainder(previous) : F.CursorRest()},
    submission_frame: @command:Board.Command -> @+reply:J.Json -> @previous:M.ViewState ->
      {FeatureUI.remainder(UI.navigate(M.Submit{M.FeatureCommand{F.BoardCommand{command}}}, previous, reply)) == FeatureUI.remainder(previous) : F.CursorRest()}}

def board_frame(value: Board.State, world: M.World()) ->
  {F.rest(C.rest(D.State, F.State(), BoardState.store(value, world))) == F.rest(C.rest(D.State, F.State(), world)) : F.Rest()}:
  match world:
    case C.Frame{core, state}: FrameProof.board_frame(value, state)

def board_core_frame(value: Board.State, world: M.World()) ->
  {C.local(D.State, F.State(), BoardState.store(value, world)) == C.local(D.State, F.State(), world) : D.State}:
  match world:
    case C.Frame{core, state}: {==}

def locality() -> Locality:
  Locality{
    R => +task => +state => +rest => TaskProof.update_meaning(R, task, state, rest),
    R => task => world => TaskProof.update_frame(R, task, world),
    R => X => +task => +world => ReasoningProof.start_meaning(R, X, task, world),
    R => X => task => world => ReasoningProof.start_frame(R, X, task, world),
    task => world => {==},
    task => world => ReasoningProof.start_frame(F.State(), F.Effect, task, world),
    +value => state => FrameProof.board_written(value, state),
    +value => cursor => FrameProof.cursor_written(value, cursor),
    value => world => board_frame(value, world),
    value => world => board_core_frame(value, world),
    event => previous => reply => FeatureUIProof.navigation_frame(event, previous),
    command => +reply => previous => FeatureUIProof.submission_frame(command, reply, previous)}
