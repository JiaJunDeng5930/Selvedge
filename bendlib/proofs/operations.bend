import Base
import ../../MODEL.bend as M
import ../../LAWS.bend as Laws
import ../architecture.bend as A
import ../operations.bend as Ops
import ../tasks.bend as T
import ../json.bend as J
import ../stdlib.bend as Std
import ../association-map.bend as Finite

# Stable operation identity is the association-list key. The project proves
# only the value adapter; deletion absence is the original ExtLib theorem.
def A.operation_rights():
  A.OperationRights{
    (operations => id => {==}),
    (operations => id => {==}),
    (+operations => +id => Equal.cong(Maybe<&2, M.OperationBody>, Maybe<&2, M.Operation()>,
      (found => Ops.binding(found, id)), Finite.find(~M.OperationBody, Finite.remove(~M.OperationBody, operations, id), id),
      None{}, Finite.removal_absence(~M.OperationBody, operations, id)))}

def announce_projection(operation: M.Operation()) ->
  {Ops.announce(Ops.announce(operation)) == Ops.announce(operation) : M.Operation()}:
  (ticket, M.OperationBody{call, announced, stage}) = operation
  {==}

def announce_ticket(+operation: M.Operation()) -> {Ops.ticket(Ops.announce(operation)) == Ops.ticket(operation) : Nat}:
  (ticket, M.OperationBody{call, announced, stage}) = operation
  {==}

def announce_call(+operation: M.Operation()) -> {Ops.call(Ops.announce(operation)) == Ops.call(operation) : M.Call}:
  (ticket, M.OperationBody{call, announced, stage}) = operation
  {==}

def announce_status(operation: M.Operation()) -> {Ops.announced(Ops.announce(operation)) == True{} : Bool}:
  (ticket, M.OperationBody{call, announced, stage}) = operation
  {==}

def A.announcement():
  A.Announcement{(operation => announce_projection(operation)),
    (operation => announce_ticket(operation)), (operation => announce_call(operation)),
    (operation => announce_status(operation))}

def notification_join(+task: M.Task) ->
  {M.task_notified(M.notify(task)) == Bool.or(M.task_notified(task), True{}) : Bool}:
  M.Task{id, lineage, contract, status, history, queued, phase, operations, notified} = task
  {==}

def notification_sticky(+task: M.Task) -> {M.task_notified(M.notify(task)) == True{} : Bool}:
  Equal.trans(Bool, M.task_notified(M.notify(task)), Bool.or(M.task_notified(task), True{}), True{},
    notification_join(task), Std.orb_true_r(M.task_notified(task)))

def notification_consumed(task: M.Task) -> {M.task_notified(Ops.publish(task)) == False{} : Bool}:
  M.Task{id, lineage, contract, status, history, queued, phase, operations, notified} = task
  {==}

def A.notifications():
  A.Notifications{ (task => notification_join(task)),
    (task => notification_sticky(task)), (task => notification_consumed(task))}

def settlement_phase(operation: M.Operation(), value: J.Json, error: Bool, +task: M.Task) ->
  {M.task_phase(Ops.completed(operation, value, error, task)) == M.wake_phase(M.task_phase(task)) : M.Phase}:
  M.Task{id, lineage, contract, status, history, queued, phase, operations, notified} = task
  {==}

def settlement_rights(+operation: M.Operation(), value: J.Json, error: Bool, +task: M.Task) ->
  {M.task_operations(Ops.completed(operation, value, error, task)) == Ops.remove(M.task_operations(task), Ops.ticket(operation)) : +List<M.Operation()>}:
  M.Task{id, lineage, contract, status, history, queued, phase, operations, notified} = task
  {==}

def settlement_notifies(+operation: M.Operation(), value: J.Json, error: Bool, +task: M.Task) ->
  {M.task_notified(Ops.completed(operation, value, error, task)) == True{} : Bool}:
  notification_sticky(M.with_operations(Ops.remove(M.task_operations(task), Ops.ticket(operation)),
    M.append_message(Ops.result(operation, value, error), task)))

def steering_rights(message: String, +task: M.Task) ->
  {M.task_operations(T.steer(message, task)) == M.task_operations(task) : +List<M.Operation()>}:
  M.Task{id, lineage, contract, status, history, queued, phase, operations, notified} = task
  {==}

def steering_queue(message: String, +task: M.Task) ->
  {M.task_queue(T.steer(message, task)) == M.task_queue(task) : +List<String>}:
  M.Task{id, lineage, contract, status, history, queued, phase, operations, notified} = task
  {==}

def abandonment(task: M.Task) -> {M.task_operations(Ops.abandoned(task)) == Nil{} : +List<M.Operation()>}:
  M.Task{id, lineage, contract, status, history, queued, phase, operations, notified} = task
  {==}

def publication(+task: M.Task) ->
  {M.task_operations(Ops.publish(task)) == Std.map(~M.Operation(), ~M.Operation(), ~Ops.announce, M.task_operations(task)) : +List<M.Operation()>}:
  M.Task{id, lineage, contract, status, history, queued, phase, operations, notified} = task
  {==}

def final_output(ticket: Nat, +call: M.Call, +value: J.Json, +error: Bool) ->
  {Ops.result((ticket, M.OperationBody{call, False{}, M.Executing{}}), value, error) == M.FunctionOutput{T.call_id(call), value, error} : M.Message}:
  M.Call{id, name, arguments} = call
  {==}

def later_output(+operation: M.Operation(), +value: J.Json, +error: Bool) ->
  {Ops.result(Ops.announce(operation), value, error) ==
    M.OperationResult{Ops.ticket(operation), T.call_id(Ops.call(operation)), T.call_name(Ops.call(operation)), value, error} : M.Message}:
  (ticket, M.OperationBody{M.Call{id, name, arguments}, announced, stage}) = operation
  {==}

def pending_model(id: Nat, lineage: +List<Nat>, contract: M.Contract, status: M.Status,
  history: M.History, queued: +List<String>, +ticket: Nat, +allowed: +List<String>, operations: +List<M.Operation()>,
  notified: Bool, operation: M.Operation(), value: J.Json, error: Bool) ->
  {M.task_phase(T.complete_operation(operation, value, error,
    M.Task{id, lineage, contract, status, history, queued, M.ModelPending{ticket, allowed}, operations, notified})) ==
    M.ModelPending{ticket, allowed} : M.Phase}:
  match status:
    case M.Active{}: {==}
    case M.Frozen{}: {==}
    case M.Stopped{}: {==}
    case M.Archived{}: {==}

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
