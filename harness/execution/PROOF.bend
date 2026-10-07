import Base
import ../features/MODEL.bend as Features
import ../../bendlib/component.bend as C
import ../DOMAIN.bend as D
import ../../features/board/MODEL.bend as B
import ../COMMANDS.bend as Commands
import ../../features/board/scheduling.bend as BoardScheduling
import ../../features/board/scheduling-spec.bend as BoardSchedulingSpec
import ../../bendlib/association-map.bend as Finite
import ../reasoning/CONTRACT.bend as Reasoning
import ../reasoning/PROOF.bend as ReasoningProof
import ../MODEL.bend as M
import ../PROGRAM.bend as P
import ../LAWS.bend as Laws
import ../tasks/PROGRAM.bend as T
import ../../bendlib/stdlib.bend as Std
import ./PROGRAM.bend as Execution
import ../protocol/PROOF.bend as ProtocolProof
import ../CONTRACT.bend as A
import ./OPERATIONS.bend as Ops
import ../../bendlib/json.bend as J

# Local proof obligations for the execution boundary. No runtime policy lives here.

def Laws.execution_semantics(action, world):
  match action world:
    case Execution.Rest{} _: {==}
    case Execution.Idle{task} C.Frame{D.State{tasks, next_task, ticket, environment, limits, projects}, +board}: {==}
    case Execution.Model{task} _: Reasoning.start_meaning(task, world)
    case Execution.Summary{task, resume} C.Frame{D.State{tasks, next_task, ticket, environment, limits, projects}, +board}: {==}
    case Execution.External{tool, call, remaining, task} C.Frame{D.State{tasks, next_task, ticket, environment, limits, projects}, +board}: {==}
    case Execution.Review{reviewer, call, remaining, task} C.Frame{D.State{tasks, next_task, ticket, environment, limits, projects}, +board}: {==}
    case Execution.Granted{reviewer, tool, operation, task} C.Frame{D.State{tasks, next_task, ticket, environment, limits, projects}, +board}: {==}
    case Execution.GrantFailure{operation, task} _: {==}
    case Execution.Hook{reference, pending, tool, call, remaining, task} C.Frame{D.State{tasks, next_task, ticket, environment, limits, projects}, +board}: {==}
    case Execution.Internal{operation, call, remaining, task} _:
      Laws.invocation_semantics(operation, call, remaining, task, world)
    case Execution.Failure{code, reason, call, remaining, task} C.Frame{D.State{tasks, next_task, ticket, environment, limits, projects}, +board}: {==}

def Laws.work_semantics(work, task, world):
  Laws.execution_semantics(Execution.resolve(work, task, world), world)

def combination_semantics(+before: M.Decision(), +after: M.Decision()) ->
  {P.combine(before, after) == Execution.combine(before, after) : M.Decision()}:
  match before after:
    case C.Decision{old, reply, effects} C.Decision{world, ignored, added}: {==}

def combined_work_semantics(+task: D.Task, +decision: M.Decision()) ->
  {P.combine(decision, P.work(D.task_work(task), task, P.decision_world(decision))) ==
    Execution.combine(decision, Execution.work(D.task_work(task), task, Execution.world(decision))) : M.Decision()}:
  +work = D.task_work(task)
  +world = P.decision_world(decision)
  +actual = P.work(work, task, world)
  +expected = Execution.work(work, task, world)
  Equal.trans(M.Decision(), P.combine(decision, actual), Execution.combine(decision, actual), Execution.combine(decision, expected),
    combination_semantics(decision, actual),
    Equal.cong(M.Decision(), M.Decision(), (value => Execution.combine(decision, value)), actual, expected, Laws.work_semantics(work, task, world)))

def Scheduling(fuel: Nat) -> Type:
  @+candidate:Maybe<&2, D.Task> -> @+decision:M.Decision() ->
    {P.schedule(fuel, candidate, decision) == Execution.schedule(fuel, candidate, decision) : M.Decision()}

def scheduling_zero(+candidate: Maybe<&2, D.Task>, +decision: M.Decision()) ->
  {P.schedule(0n, candidate, decision) == Execution.schedule(0n, candidate, decision) : M.Decision()}:
  match candidate decision:
    case None{} _: {==}
    case Some{task} C.Decision{world, reply, effects}: {==}

def scheduling_successor(+fuel: Nat, induction: Scheduling(fuel), +candidate: Maybe<&2, D.Task>, +decision: M.Decision()) ->
  {P.schedule(1n+fuel, candidate, decision) == Execution.schedule(1n+fuel, candidate, decision) : M.Decision()}:
  match candidate:
    case None{}: {==}
    case Some{+task}:
      +work = D.task_work(task)
      +world = P.decision_world(decision)
      +actual = P.combine(decision, P.work(work, task, world))
      +expected = Execution.combine(decision, Execution.work(work, task, world))
      +following = T.runnable(P.tasks(P.decision_world(actual)))
      Equal.trans(M.Decision(), P.schedule(fuel, following, actual), Execution.schedule(fuel, following, actual),
        Execution.schedule(fuel, T.runnable(P.tasks(P.decision_world(expected))), expected), induction(following, actual),
        Equal.cong(M.Decision(), M.Decision(),
          (+value => Execution.schedule(fuel, T.runnable(P.tasks(P.decision_world(value))), value)),
          actual, expected, combined_work_semantics(task, decision)))

def Laws.schedule_semantics(fuel, candidate, decision):
  Std.nat_ind(~Scheduling, ~scheduling_zero,
    ~(fuel => induction => +candidate => +decision => scheduling_successor(fuel, induction, candidate, decision)), fuel)(candidate, decision)

# The bounded board pump invokes the ordinary public command implementation.
# Its independent equation invokes COMMANDS.command instead. The original
# imported induction principle lifts that one-command correspondence to every
# budget and complete decision; no host scheduler or finite replay is assumed.
def board_settlement(+ok: Bool, +id: Nat, +card: B.Card, +before: M.Decision(), +result: M.Decision()) ->
  {BoardScheduling.settled(ok, id, card, before, result) == BoardSchedulingSpec.required_result(ok, id, card, before, result) : M.Decision()}:
  match ok before result:
    case True{} C.Decision{old, reply, effects} C.Decision{world, ignored, added}: {==}
    case False{} C.Decision{C.Frame{D.State{tasks, next_task, ticket, environment, limits, projects}, +board}, reply, effects}
      C.Decision{ignored, failure, discarded}: {==}

def board_attempt(+id: Nat, +card: B.Card, +before: M.Decision()) ->
  {BoardScheduling.attempt(~P.board_dispatch, id, card, before) == BoardSchedulingSpec.required_attempt(id, card, before) : M.Decision()}:
  +command : M.Command = M.FeatureCommand{Features.BoardCommand{B.Run{id, B.revision(card), B.updated(card)}}}
  +world = BoardSchedulingSpec.decision_world(before)
  +actual = P.board_dispatch(command, world)
  +required = Commands.command(command, world)
  Equal.trans(M.Decision(), BoardScheduling.attempt(~P.board_dispatch, id, card, before),
    BoardSchedulingSpec.required_result(BoardSchedulingSpec.result_ok(actual), id, card, before, actual),
    BoardSchedulingSpec.required_attempt(id, card, before),
    board_settlement(BoardSchedulingSpec.result_ok(actual), id, card, before, actual),
    Equal.cong(M.Decision(), M.Decision(),
      (+value => BoardSchedulingSpec.required_result(BoardSchedulingSpec.result_ok(value), id, card, before, value)),
      actual, required, Laws.command_semantics(command, world)))

def BoardPump(fuel: Nat) -> Type:
  @+candidate:Maybe<&2, Finite.Entry(B.Card)> -> @+decision:M.Decision() ->
    {BoardScheduling.pump(~P.board_dispatch, fuel, candidate, decision) == BoardSchedulingSpec.required(fuel, candidate, decision) : M.Decision()}

def board_zero(+candidate: Maybe<&2, Finite.Entry(B.Card)>, +decision: M.Decision()) ->
  {BoardScheduling.pump(~P.board_dispatch, 0n, candidate, decision) == BoardSchedulingSpec.required(0n, candidate, decision) : M.Decision()}:
  {==}

def board_successor(+fuel: Nat, induction: BoardPump(fuel), +candidate: Maybe<&2, Finite.Entry(B.Card)>, +decision: M.Decision()) ->
  {BoardScheduling.pump(~P.board_dispatch, 1n+fuel, candidate, decision) == BoardSchedulingSpec.required(1n+fuel, candidate, decision) : M.Decision()}:
  match candidate:
    case None{}: {==}
    case Some{(+id, +card)}:
      +actual = BoardScheduling.attempt(~P.board_dispatch, id, card, decision)
      +required = BoardSchedulingSpec.required_attempt(id, card, decision)
      +following = BoardSchedulingSpec.next(BoardSchedulingSpec.decision_world(actual))
      Equal.trans(M.Decision(), BoardScheduling.pump(~P.board_dispatch, fuel, following, actual),
        BoardSchedulingSpec.required(fuel, following, actual),
        BoardSchedulingSpec.required(fuel, BoardSchedulingSpec.next(BoardSchedulingSpec.decision_world(required)), required),
        induction(following, actual),
        Equal.cong(M.Decision(), M.Decision(),
          (+value => BoardSchedulingSpec.required(fuel, BoardSchedulingSpec.next(BoardSchedulingSpec.decision_world(value)), value)),
          actual, required, board_attempt(id, card, decision)))

def board_pump(+fuel: Nat, +candidate: Maybe<&2, Finite.Entry(B.Card)>, +decision: M.Decision()) ->
  {BoardScheduling.pump(~P.board_dispatch, fuel, candidate, decision) == BoardSchedulingSpec.required(fuel, candidate, decision) : M.Decision()}:
  Std.nat_ind(~BoardPump, ~board_zero,
    ~(fuel => induction => +candidate => +decision => board_successor(fuel, induction, candidate, decision)), fuel)(candidate, decision)

def board_preparation(+decision: M.Decision()) ->
  {BoardScheduling.prepare(~P.board_dispatch, decision) == BoardSchedulingSpec.required_prepare(decision) : M.Decision()}:
  +prepared = BoardSchedulingSpec.synchronize(decision)
  board_pump(8n, BoardSchedulingSpec.next(BoardSchedulingSpec.decision_world(prepared)), prepared)

def prepared_scheduling(+decision: M.Decision()) ->
  {P.scheduled_prepared(decision) == Execution.scheduled_prepared(decision) : M.Decision()}:
  +fuel = P.scheduling_budget(P.decision_world(decision))
  +candidate = T.runnable(P.tasks(P.decision_world(decision)))
  Equal.cong(M.Decision(), M.Decision(), (value => BoardSchedulingSpec.finish(value)),
    P.schedule(fuel, candidate, decision), Execution.schedule(fuel, candidate, decision),
    Laws.schedule_semantics(fuel, candidate, decision))

def Laws.scheduling_semantics(enabled, decision):
  match enabled:
    case False{}: {==}
    case True{}:
      +prepared = BoardScheduling.prepare(~P.board_dispatch, decision)
      +required = BoardSchedulingSpec.required_prepare(decision)
      Equal.trans(M.Decision(), P.scheduled(True{}, decision), Execution.scheduled_prepared(prepared),
        Execution.scheduled(True{}, decision), prepared_scheduling(prepared),
        Equal.cong(M.Decision(), M.Decision(), (value => Execution.scheduled_prepared(value)),
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
    case C.Frame{D.State{tasks, next_task, next_ticket, environment, limits, projects}, +board}: {==}

def Laws.no_work(task, world):
  {==}

def Laws.tool_dispatch(board, tool, call, remaining, task, state):
  D.State{tasks, next_task, ticket, environment, limits, projects} = state
  {==}

def Laws.small_context_dispatch(task, world):
  {==}

def Laws.large_context_dispatch(task, world):
  {==}

def Laws.oversized_operation_barrier(task):
  {==}

# Stable operation identity is the association-list key. The project proves
# only the value adapter; deletion absence is the original ExtLib theorem.
def A.operation_rights():
  A.OperationRights{
    (operations => id => {==}),
    (operations => id => {==}),
    (+operations => +id => Equal.cong(Maybe<&2, D.OperationBody>, Maybe<&2, D.Operation()>,
      (found => Ops.binding(found, id)), Finite.find(~D.OperationBody, Finite.remove(~D.OperationBody, operations, id), id),
      None{}, Finite.removal_absence(~D.OperationBody, operations, id)))}

def announce_projection(operation: D.Operation()) ->
  {Ops.announce(Ops.announce(operation)) == Ops.announce(operation) : D.Operation()}:
  (ticket, D.OperationBody{call, announced, stage}) = operation
  {==}

def announce_ticket(+operation: D.Operation()) -> {Ops.ticket(Ops.announce(operation)) == Ops.ticket(operation) : Nat}:
  (ticket, D.OperationBody{call, announced, stage}) = operation
  {==}

def announce_call(+operation: D.Operation()) -> {Ops.call(Ops.announce(operation)) == Ops.call(operation) : D.Call}:
  (ticket, D.OperationBody{call, announced, stage}) = operation
  {==}

def announce_status(operation: D.Operation()) -> {Ops.announced(Ops.announce(operation)) == True{} : Bool}:
  (ticket, D.OperationBody{call, announced, stage}) = operation
  {==}

def A.announcement():
  A.Announcement{(operation => announce_projection(operation)),
    (operation => announce_ticket(operation)), (operation => announce_call(operation)),
    (operation => announce_status(operation))}

def notification_join(+task: D.Task) ->
  {D.task_notified(D.notify(task)) == Bool.or(D.task_notified(task), True{}) : Bool}:
  D.Task{id, lineage, contract, status, history, queued, phase, operations, notified} = task
  {==}

def notification_sticky(+task: D.Task) -> {D.task_notified(D.notify(task)) == True{} : Bool}:
  Equal.trans(Bool, D.task_notified(D.notify(task)), Bool.or(D.task_notified(task), True{}), True{},
    notification_join(task), Std.orb_true_r(D.task_notified(task)))

def notification_consumed(task: D.Task) -> {D.task_notified(Ops.publish(task)) == False{} : Bool}:
  D.Task{id, lineage, contract, status, history, queued, phase, operations, notified} = task
  {==}

def A.notifications():
  A.Notifications{ (task => notification_join(task)),
    (task => notification_sticky(task)), (task => notification_consumed(task))}

def settlement_phase(operation: D.Operation(), value: J.Json, error: Bool, +task: D.Task) ->
  {D.task_phase(Ops.completed(operation, value, error, task)) == D.wake_phase(D.task_phase(task)) : D.Phase}:
  D.Task{id, lineage, contract, status, history, queued, phase, operations, notified} = task
  {==}

def settlement_rights(+operation: D.Operation(), value: J.Json, error: Bool, +task: D.Task) ->
  {D.task_operations(Ops.completed(operation, value, error, task)) == Ops.remove(D.task_operations(task), Ops.ticket(operation)) : +List<D.Operation()>}:
  D.Task{id, lineage, contract, status, history, queued, phase, operations, notified} = task
  {==}

def settlement_notifies(+operation: D.Operation(), value: J.Json, error: Bool, +task: D.Task) ->
  {D.task_notified(Ops.completed(operation, value, error, task)) == True{} : Bool}:
  notification_sticky(D.with_operations(Ops.remove(D.task_operations(task), Ops.ticket(operation)),
    D.append_message(Ops.result(operation, value, error), task)))

def steering_rights(message: String, +task: D.Task) ->
  {D.task_operations(T.steer(message, task)) == D.task_operations(task) : +List<D.Operation()>}:
  D.Task{id, lineage, contract, status, history, queued, phase, operations, notified} = task
  {==}

def steering_queue(message: String, +task: D.Task) ->
  {D.task_queue(T.steer(message, task)) == D.task_queue(task) : +List<String>}:
  D.Task{id, lineage, contract, status, history, queued, phase, operations, notified} = task
  {==}

def abandonment(task: D.Task) -> {D.task_operations(Ops.abandoned(task)) == Nil{} : +List<D.Operation()>}:
  D.Task{id, lineage, contract, status, history, queued, phase, operations, notified} = task
  {==}

def publication(+task: D.Task) ->
  {D.task_operations(Ops.publish(task)) == Std.map(~D.Operation(), ~D.Operation(), ~Ops.announce, D.task_operations(task)) : +List<D.Operation()>}:
  D.Task{id, lineage, contract, status, history, queued, phase, operations, notified} = task
  {==}

def final_output(ticket: Nat, +call: D.Call, +value: J.Json, +error: Bool) ->
  {Ops.result((ticket, D.OperationBody{call, False{}, D.Executing{}}), value, error) == D.FunctionOutput{T.call_id(call), value, error} : D.Message}:
  D.Call{id, name, arguments} = call
  {==}

def later_output(+operation: D.Operation(), +value: J.Json, +error: Bool) ->
  {Ops.result(Ops.announce(operation), value, error) ==
    D.OperationResult{Ops.ticket(operation), T.call_id(Ops.call(operation)), T.call_name(Ops.call(operation)), value, error} : D.Message}:
  (ticket, D.OperationBody{D.Call{id, name, arguments}, announced, stage}) = operation
  {==}

def pending_model(id: Nat, lineage: +List<Nat>, contract: D.Contract, status: D.Status,
  history: D.History, queued: +List<String>, +ticket: Nat, +allowed: +List<String>, operations: +List<D.Operation()>,
  notified: Bool, operation: D.Operation(), value: J.Json, error: Bool) ->
  {D.task_phase(T.complete_operation(operation, value, error,
    D.Task{id, lineage, contract, status, history, queued, D.ModelPending{ticket, allowed}, operations, notified})) ==
    D.ModelPending{ticket, allowed} : D.Phase}:
  match status:
    case D.Active{}: {==}
    case D.Frozen{}: {==}
    case D.Stopped{}: {==}
    case D.Archived{}: {==}

def A.coordination():
  A.Coordination{(operation => value => error => task => settlement_phase(operation, value, error, task)),
    (operation => value => error => task => settlement_rights(operation, value, error, task)),
    (operation => value => error => task => settlement_notifies(operation, value, error, task)),
    (message => task => steering_rights(message, task)), (message => task => steering_queue(message, task)),
    (task => abandonment(task)), (task => publication(task)),
    (ticket => call => value => error => final_output(ticket, call, value, error)),
    (operation => value => error => later_output(operation, value, error)),
    (id => lineage => contract => status => history => queued => ticket => allowed => operations => notified => operation => value => error =>
      pending_model(id, lineage, contract, status, history, queued, ticket, allowed, operations, notified, operation, value, error))}
