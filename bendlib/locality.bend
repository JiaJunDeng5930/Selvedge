import Base
import ./task-laws.bend as TaskSpec
import ./component.bend as C
import ./domain.bend as D
import ./effects.bend as E
import ./tasks.bend as Tasks
import ./reasoning.bend as Reasoning
import ./reasoning-spec.bend as Spec
import ../FEATURES.bend as F
import ../BOARD.bend as Board
import ../MODEL.bend as M
import ../PROGRAM.bend as P
import ./board-state.bend as BoardState

# Quantification over the remainder type is essential: none of these proofs
# lists the fields or constructors of a particular assembled application.
type TaskStorage is Type:
  TaskStorage{
    task_meaning: @-R:Data -> @+task:D.Task -> @+state:D.State -> @+rest:R ->
      {Tasks.update_world(R, task, C.Frame{state, rest}) == C.Frame{TaskSpec.required_update(task, state), rest} : C.Frame<D.State, R>},
    task_update: @-R:Data -> @task:D.Task -> @world:C.Frame<D.State, R> ->
      {C.rest(D.State, R, Tasks.update_world(R, task, world)) == C.rest(D.State, R, world) : R},
    task_dispatch: @task:D.Task -> @world:M.World() ->
      {P.store(task, world) == Tasks.update_world(F.State(), task, world) : M.World()}
  }

type ReasoningComponent is Type:
  ReasoningComponent{
    reasoning_meaning: @-R:Data -> @-X:Data -> @+task:D.Task -> @+world:C.Frame<D.State, R> ->
      {Reasoning.start(R, X, task, world) == Spec.start(R, X, task, world) : C.Decision<C.Frame<D.State, R>, E.Effect<X>>},
    reasoning_frame: @-R:Data -> @-X:Data -> @task:D.Task -> @world:C.Frame<D.State, R> ->
      {C.remaining(D.State, R, E.Effect<X>, Reasoning.start(R, X, task, world)) == C.rest(D.State, R, world) : R},
    production_reasoning: @task:D.Task -> @world:M.World() ->
      {C.remaining(D.State, F.State(), M.Effect(), P.model_request_direct(task, world)) == C.rest(D.State, F.State(), world) : F.State()}
  }

type BoardStorage is Type:
  BoardStorage{
    board_written: @+value:Board.State -> @state:F.State() ->
      {F.board(F.with_board(value, state)) == value : Board.State},
    board_frame: @value:Board.State -> @world:M.World() ->
      {F.rest(C.rest(D.State, F.State(), BoardState.store(value, world))) == F.rest(C.rest(D.State, F.State(), world)) : F.Rest()},
    board_core_frame: @value:Board.State -> @world:M.World() ->
      {C.local(D.State, F.State(), BoardState.store(value, world)) == C.local(D.State, F.State(), world) : D.State}
  }

type Locality is Type:
  Locality{
    tasks: TaskStorage,
    reasoning: ReasoningComponent,
    board: BoardStorage
  }
