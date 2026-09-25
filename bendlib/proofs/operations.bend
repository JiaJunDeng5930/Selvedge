import Base
import ../../MODEL.bend as M
import ../../LAWS.bend as Laws
import ../architecture.bend as A
import ../operations.bend as Ops
import ../tasks.bend as T
import ../json.bend as J
import ../stdlib.bend as Std
import ../structures.bend as S

# Application correspondence for the operation map. Standard Boolean join and
# fold/iteration laws are imported, not re-established by local proof search.
def choice_correspondence(same: Bool, operation: M.Operation, rest: Maybe<&2, M.Operation>) ->
  {Ops.chosen(same, operation, rest) == S.lookup_choice(M.Operation, same, operation, rest) : Maybe<&2, M.Operation>}:
  match same:
    case True{}: {==}
    case False{}: {==}

def lookup_binding(+operation: M.Operation, +rest: +List<M.Operation>, +id: Nat) ->
  {Ops.find(operation <> rest, id) == S.lookup_choice(M.Operation, Nat.is_eq(Ops.ticket(operation), id), operation, Ops.find(rest, id)) : Maybe<&2, M.Operation>}:
  choice_correspondence(Nat.is_eq(Ops.ticket(operation), id), operation, Ops.find(rest, id))

def retention_correspondence(same: Bool, operation: M.Operation, rest: +List<M.Operation>) ->
  {Ops.retained(same, operation, rest) == S.keep_unmatched(M.Operation, same, operation, rest) : +List<M.Operation>}:
  match same:
    case True{}: {==}
    case False{}: {==}

def erase_binding(+operation: M.Operation, +rest: +List<M.Operation>, +id: Nat) ->
  {Ops.remove(operation <> rest, id) == S.keep_unmatched(M.Operation, Nat.is_eq(Ops.ticket(operation), id), operation, Ops.remove(rest, id)) : +List<M.Operation>}:
  retention_correspondence(Nat.is_eq(Ops.ticket(operation), id), operation, Ops.remove(rest, id))

def Consumed(entries: +List<M.Operation>) -> Type:
  @id:Nat -> {Ops.find(Ops.remove(entries, id), id) == None{} : Maybe<&2, M.Operation>}

def consume_empty(id: Nat) -> {Ops.find(Ops.remove(Nil{}, id), id) == None{} : Maybe<&2, M.Operation>}:
  {==}

def consume_choice(+same: Bool, +operation: M.Operation, +rest: +List<M.Operation>, +id: Nat,
  equality: {Nat.is_eq(Ops.ticket(operation), id) == same : Bool},
  induction: {Ops.find(Ops.remove(rest, id), id) == None{} : Maybe<&2, M.Operation>}) ->
  {Ops.find(Ops.retained(same, operation, Ops.remove(rest, id)), id) == None{} : Maybe<&2, M.Operation>}:
  match same:
    case True{}: induction
    case False{}:
      Equal.trans(Maybe<&2, M.Operation>,
        Ops.find(operation <> Ops.remove(rest, id), id), Ops.find(Ops.remove(rest, id), id), None{},
        Equal.cong(Bool, Maybe<&2, M.Operation>, (same => Ops.chosen(same, operation, Ops.find(Ops.remove(rest, id), id))),
          Nat.is_eq(Ops.ticket(operation), id), False{}, equality), induction)

def consume_step(+operation: M.Operation, +rest: +List<M.Operation>, induction: Consumed(rest), +id: Nat) ->
  {Ops.find(Ops.remove(operation <> rest, id), id) == None{} : Maybe<&2, M.Operation>}:
  consume_choice(Nat.is_eq(Ops.ticket(operation), id), operation, rest, id, {==}, induction(id))

def consumed(entries: +List<M.Operation>, id: Nat) ->
  {Ops.find(Ops.remove(entries, id), id) == None{} : Maybe<&2, M.Operation>}:
  Std.list_ind(~M.Operation, ~Consumed, ~consume_empty,
    ~(operation => rest => induction => id => consume_step(operation, rest, induction, id)), entries)(id)

def A.operation_rights():
  S.AssociationMap{(id => {==}), (operation => rest => id => lookup_binding(operation, rest, id)),
    (id => {==}), (operation => rest => id => erase_binding(operation, rest, id)),
    (entries => id => consumed(entries, id))}

def announce_projection(operation: M.Operation) ->
  {Ops.announce(Ops.announce(operation)) == Ops.announce(operation) : M.Operation}:
  M.Operation{ticket, call, announced} = operation
  {==}

def announce_ticket(+operation: M.Operation) -> {Ops.ticket(Ops.announce(operation)) == Ops.ticket(operation) : Nat}:
  M.Operation{ticket, call, announced} = operation
  {==}

def announce_call(+operation: M.Operation) -> {Ops.call(Ops.announce(operation)) == Ops.call(operation) : M.Call}:
  M.Operation{ticket, call, announced} = operation
  {==}

def announce_status(operation: M.Operation) -> {Ops.announced(Ops.announce(operation)) == True{} : Bool}:
  M.Operation{ticket, call, announced} = operation
  {==}

def A.announcement():
  A.Announcement{S.Projection{(operation => announce_projection(operation))},
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
  A.Notifications{S.boolean_join(), (task => notification_join(task)),
    (task => notification_sticky(task)), (task => notification_consumed(task))}

def settlement_phase(operation: M.Operation, value: J.Json, error: Bool, +task: M.Task) ->
  {M.task_phase(Ops.completed(operation, value, error, task)) == M.wake_phase(M.task_phase(task)) : M.Phase}:
  M.Task{id, lineage, contract, status, history, queued, phase, operations, notified} = task
  {==}

def settlement_rights(+operation: M.Operation, value: J.Json, error: Bool, +task: M.Task) ->
  {M.task_operations(Ops.completed(operation, value, error, task)) == Ops.remove(M.task_operations(task), Ops.ticket(operation)) : +List<M.Operation>}:
  M.Task{id, lineage, contract, status, history, queued, phase, operations, notified} = task
  {==}

def settlement_notifies(+operation: M.Operation, value: J.Json, error: Bool, +task: M.Task) ->
  {M.task_notified(Ops.completed(operation, value, error, task)) == True{} : Bool}:
  notification_sticky(M.with_operations(Ops.remove(M.task_operations(task), Ops.ticket(operation)),
    M.append_message(Ops.result(operation, value, error), task)))

def steering_rights(message: String, +task: M.Task) ->
  {M.task_operations(T.steer(message, task)) == M.task_operations(task) : +List<M.Operation>}:
  M.Task{id, lineage, contract, status, history, queued, phase, operations, notified} = task
  {==}

def steering_queue(message: String, +task: M.Task) ->
  {M.task_queue(T.steer(message, task)) == M.task_queue(task) : +List<String>}:
  M.Task{id, lineage, contract, status, history, queued, phase, operations, notified} = task
  {==}

def abandonment(task: M.Task) -> {M.task_operations(Ops.abandoned(task)) == Nil{} : +List<M.Operation>}:
  M.Task{id, lineage, contract, status, history, queued, phase, operations, notified} = task
  {==}

def publication(+task: M.Task) ->
  {M.task_operations(Ops.publish(task)) == Std.map(~M.Operation, ~M.Operation, ~Ops.announce, M.task_operations(task)) : +List<M.Operation>}:
  M.Task{id, lineage, contract, status, history, queued, phase, operations, notified} = task
  {==}

def final_output(ticket: Nat, +call: M.Call, +value: J.Json, +error: Bool) ->
  {Ops.result(M.Operation{ticket, call, False{}}, value, error) == M.FunctionOutput{T.call_id(call), value, error} : M.Message}:
  M.Call{id, name, arguments} = call
  {==}

def later_output(+operation: M.Operation, +value: J.Json, +error: Bool) ->
  {Ops.result(Ops.announce(operation), value, error) ==
    M.OperationResult{Ops.ticket(operation), T.call_id(Ops.call(operation)), T.call_name(Ops.call(operation)), value, error} : M.Message}:
  M.Operation{ticket, M.Call{id, name, arguments}, announced} = operation
  {==}

def pending_model(id: Nat, lineage: +List<Nat>, contract: M.Contract, status: M.Status,
  history: M.History, queued: +List<String>, +ticket: Nat, +allowed: +List<String>, operations: +List<M.Operation>,
  notified: Bool, operation: M.Operation, value: J.Json, error: Bool) ->
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
