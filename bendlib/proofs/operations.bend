import Base
import ../domain.bend as D
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
