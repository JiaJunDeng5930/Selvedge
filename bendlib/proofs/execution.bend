import Base
import ../../BOARD.bend as B
import ../../COMMANDS.bend as Commands
import ../board-scheduling.bend as BoardScheduling
import ../board-scheduling-spec.bend as BoardSchedulingSpec
import ../association-map.bend as Finite
import ../reasoning-architecture.bend as Reasoning
import ./reasoning.bend as ReasoningProof
import ../../MODEL.bend as M
import ../../PROGRAM.bend as P
import ../../LAWS.bend as Laws
import ../tasks.bend as T
import ../stdlib.bend as Std
import ../execution.bend as Execution
import ./protocol.bend as ProtocolProof

# Local proof obligations for the execution boundary. No runtime policy lives here.

def Laws.execution_semantics(action, world):
  match action world:
    case Execution.Rest{} _: {==}
    case Execution.Idle{task} M.World{tasks, next_task, ticket, environment, limits, projects, board}: {==}
    case Execution.Model{task} _: Reasoning.start_meaning(task, world)
    case Execution.Summary{task, resume} M.World{tasks, next_task, ticket, environment, limits, projects, board}: {==}
    case Execution.External{tool, call, remaining, task} M.World{tasks, next_task, ticket, environment, limits, projects, board}: {==}
    case Execution.Review{reviewer, call, remaining, task} M.World{tasks, next_task, ticket, environment, limits, projects, board}: {==}
    case Execution.Granted{reviewer, tool, operation, task} M.World{tasks, next_task, ticket, environment, limits, projects, board}: {==}
    case Execution.GrantFailure{operation, task} _: {==}
    case Execution.Hook{reference, pending, tool, call, remaining, task} M.World{tasks, next_task, ticket, environment, limits, projects, board}: {==}
    case Execution.Internal{operation, call, remaining, task} _:
      Laws.invocation_semantics(operation, call, remaining, task, world)
    case Execution.Failure{code, reason, call, remaining, task} M.World{tasks, next_task, ticket, environment, limits, projects, board}: {==}

def Laws.work_semantics(work, task, world):
  Laws.execution_semantics(Execution.resolve(work, task, world), world)

def combination_semantics(+before: M.Decision, +after: M.Decision) ->
  {P.combine(before, after) == Execution.combine(before, after) : M.Decision}:
  match before after:
    case M.Decision{old, reply, effects} M.Decision{world, ignored, added}: {==}

def combined_work_semantics(+task: M.Task, +decision: M.Decision) ->
  {P.combine(decision, P.work(M.task_work(task), task, P.decision_world(decision))) ==
    Execution.combine(decision, Execution.work(M.task_work(task), task, Execution.world(decision))) : M.Decision}:
  +work = M.task_work(task)
  +world = P.decision_world(decision)
  +actual = P.work(work, task, world)
  +expected = Execution.work(work, task, world)
  Equal.trans(M.Decision, P.combine(decision, actual), Execution.combine(decision, actual), Execution.combine(decision, expected),
    combination_semantics(decision, actual),
    Equal.cong(M.Decision, M.Decision, (value => Execution.combine(decision, value)), actual, expected, Laws.work_semantics(work, task, world)))

def Scheduling(fuel: Nat) -> Type:
  @+candidate:Maybe<&2, M.Task> -> @+decision:M.Decision ->
    {P.schedule(fuel, candidate, decision) == Execution.schedule(fuel, candidate, decision) : M.Decision}

def scheduling_zero(+candidate: Maybe<&2, M.Task>, +decision: M.Decision) ->
  {P.schedule(0n, candidate, decision) == Execution.schedule(0n, candidate, decision) : M.Decision}:
  match candidate decision:
    case None{} _: {==}
    case Some{task} M.Decision{world, reply, effects}: {==}

def scheduling_successor(+fuel: Nat, induction: Scheduling(fuel), +candidate: Maybe<&2, M.Task>, +decision: M.Decision) ->
  {P.schedule(1n+fuel, candidate, decision) == Execution.schedule(1n+fuel, candidate, decision) : M.Decision}:
  match candidate:
    case None{}: {==}
    case Some{+task}:
      +work = M.task_work(task)
      +world = P.decision_world(decision)
      +actual = P.combine(decision, P.work(work, task, world))
      +expected = Execution.combine(decision, Execution.work(work, task, world))
      +following = T.runnable(P.tasks(P.decision_world(actual)))
      Equal.trans(M.Decision, P.schedule(fuel, following, actual), Execution.schedule(fuel, following, actual),
        Execution.schedule(fuel, T.runnable(P.tasks(P.decision_world(expected))), expected), induction(following, actual),
        Equal.cong(M.Decision, M.Decision,
          (+value => Execution.schedule(fuel, T.runnable(P.tasks(P.decision_world(value))), value)),
          actual, expected, combined_work_semantics(task, decision)))

def Laws.schedule_semantics(fuel, candidate, decision):
  Std.nat_ind(~Scheduling, ~scheduling_zero,
    ~(fuel => induction => +candidate => +decision => scheduling_successor(fuel, induction, candidate, decision)), fuel)(candidate, decision)

# The bounded board pump invokes the ordinary public command implementation.
# Its independent equation invokes COMMANDS.command instead. The original
# imported induction principle lifts that one-command correspondence to every
# budget and complete decision; no host scheduler or finite replay is assumed.
def board_settlement(+ok: Bool, +id: Nat, +card: B.Card, +before: M.Decision, +result: M.Decision) ->
  {BoardScheduling.settled(ok, id, card, before, result) == BoardSchedulingSpec.required_result(ok, id, card, before, result) : M.Decision}:
  match ok before result:
    case True{} M.Decision{old, reply, effects} M.Decision{world, ignored, added}: {==}
    case False{} M.Decision{M.World{tasks, next_task, ticket, environment, limits, projects, board}, reply, effects}
      M.Decision{ignored, failure, discarded}: {==}

def board_attempt(+id: Nat, +card: B.Card, +before: M.Decision) ->
  {BoardScheduling.attempt(~P.board_dispatch, id, card, before) == BoardSchedulingSpec.required_attempt(id, card, before) : M.Decision}:
  +command : M.Command = M.BoardCommand{B.Run{id, B.revision(card), B.updated(card)}}
  +world = BoardSchedulingSpec.decision_world(before)
  +actual = P.board_dispatch(command, world)
  +required = Commands.command(command, world)
  Equal.trans(M.Decision, BoardScheduling.attempt(~P.board_dispatch, id, card, before),
    BoardSchedulingSpec.required_result(BoardSchedulingSpec.result_ok(actual), id, card, before, actual),
    BoardSchedulingSpec.required_attempt(id, card, before),
    board_settlement(BoardSchedulingSpec.result_ok(actual), id, card, before, actual),
    Equal.cong(M.Decision, M.Decision,
      (+value => BoardSchedulingSpec.required_result(BoardSchedulingSpec.result_ok(value), id, card, before, value)),
      actual, required, Laws.command_semantics(command, world)))

def BoardPump(fuel: Nat) -> Type:
  @+candidate:Maybe<&2, Finite.Entry(B.Card)> -> @+decision:M.Decision ->
    {BoardScheduling.pump(~P.board_dispatch, fuel, candidate, decision) == BoardSchedulingSpec.required(fuel, candidate, decision) : M.Decision}

def board_zero(+candidate: Maybe<&2, Finite.Entry(B.Card)>, +decision: M.Decision) ->
  {BoardScheduling.pump(~P.board_dispatch, 0n, candidate, decision) == BoardSchedulingSpec.required(0n, candidate, decision) : M.Decision}:
  {==}

def board_successor(+fuel: Nat, induction: BoardPump(fuel), +candidate: Maybe<&2, Finite.Entry(B.Card)>, +decision: M.Decision) ->
  {BoardScheduling.pump(~P.board_dispatch, 1n+fuel, candidate, decision) == BoardSchedulingSpec.required(1n+fuel, candidate, decision) : M.Decision}:
  match candidate:
    case None{}: {==}
    case Some{(+id, +card)}:
      +actual = BoardScheduling.attempt(~P.board_dispatch, id, card, decision)
      +required = BoardSchedulingSpec.required_attempt(id, card, decision)
      +following = BoardSchedulingSpec.next(BoardSchedulingSpec.decision_world(actual))
      Equal.trans(M.Decision, BoardScheduling.pump(~P.board_dispatch, fuel, following, actual),
        BoardSchedulingSpec.required(fuel, following, actual),
        BoardSchedulingSpec.required(fuel, BoardSchedulingSpec.next(BoardSchedulingSpec.decision_world(required)), required),
        induction(following, actual),
        Equal.cong(M.Decision, M.Decision,
          (+value => BoardSchedulingSpec.required(fuel, BoardSchedulingSpec.next(BoardSchedulingSpec.decision_world(value)), value)),
          actual, required, board_attempt(id, card, decision)))

def board_pump(+fuel: Nat, +candidate: Maybe<&2, Finite.Entry(B.Card)>, +decision: M.Decision) ->
  {BoardScheduling.pump(~P.board_dispatch, fuel, candidate, decision) == BoardSchedulingSpec.required(fuel, candidate, decision) : M.Decision}:
  Std.nat_ind(~BoardPump, ~board_zero,
    ~(fuel => induction => +candidate => +decision => board_successor(fuel, induction, candidate, decision)), fuel)(candidate, decision)

def board_preparation(+decision: M.Decision) ->
  {BoardScheduling.prepare(~P.board_dispatch, decision) == BoardSchedulingSpec.required_prepare(decision) : M.Decision}:
  +prepared = BoardSchedulingSpec.synchronize(decision)
  board_pump(8n, BoardSchedulingSpec.next(BoardSchedulingSpec.decision_world(prepared)), prepared)

def prepared_scheduling(+decision: M.Decision) ->
  {P.scheduled_prepared(decision) == Execution.scheduled_prepared(decision) : M.Decision}:
  +fuel = P.scheduling_budget(P.decision_world(decision))
  +candidate = T.runnable(P.tasks(P.decision_world(decision)))
  Equal.cong(M.Decision, M.Decision, (value => BoardSchedulingSpec.finish(value)),
    P.schedule(fuel, candidate, decision), Execution.schedule(fuel, candidate, decision),
    Laws.schedule_semantics(fuel, candidate, decision))

def Laws.scheduling_semantics(enabled, decision):
  match enabled:
    case False{}: {==}
    case True{}:
      +prepared = BoardScheduling.prepare(~P.board_dispatch, decision)
      +required = BoardSchedulingSpec.required_prepare(decision)
      Equal.trans(M.Decision, P.scheduled(True{}, decision), Execution.scheduled_prepared(prepared),
        Execution.scheduled(True{}, decision), prepared_scheduling(prepared),
        Equal.cong(M.Decision, M.Decision, (value => Execution.scheduled_prepared(value)),
          prepared, required, board_preparation(decision)))

def Laws.scheduling_disabled(decision):
  {==}

def Laws.scheduling_enabled(decision):
  Laws.scheduling_semantics(True{}, decision)

def Laws.scheduling_idle(fuel, decision):
  match fuel:
    case 0n: {==}
    case 1n+p: {==}

def Laws.scheduling_exhausted(task, world, reply, effects):
  {==}

def Laws.scheduling_progress(fuel, task, decision):
  {==}

def Laws.scheduling_combines_outputs(old, reply, effects, next, ignored, added):
  {==}

def Laws.model_work(task, world):
  {==}

def Laws.tool_work(task, world):
  {==}

def Laws.idle_work(task, world):
  match world:
    case M.World{tasks, next_task, next_ticket, environment, limits, projects, board}: {==}

def Laws.no_work(task, world):
  {==}

def Laws.tool_dispatch(board, tool, call, remaining, task, tasks, next_task, ticket, environment, limits, projects):
  {==}

def Laws.small_context_dispatch(task, world):
  {==}

def Laws.large_context_dispatch(task, world):
  {==}

def Laws.oversized_operation_barrier(task):
  {==}
