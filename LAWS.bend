import Base
import ./MODEL.bend as M
import ./PROGRAM.bend as P
import ./bendlib/tasks.bend as T
import ./bendlib/json.bend as J

# These are requirements about the definitions the server actually executes.
# They are deliberately separate from their proofs, so a changed requirement is
# visible in review. They do not claim that an OS, database, or model obeys us.

# Archived tasks are terminal. No later user input changes their history/queue.
law archived_terminal:
  for request: M.Control
  {M.control(M.Archived{}, request) == None{} : Maybe<&2, M.Status>}

law archived_input_unchanged:
  for +id: Nat
  for +lineage: +List<Nat>
  for +contract: M.Contract
  for +history: M.History
  for +queue: +List<String>
  for +phase: M.Phase
  for text: String
  {T.receive(text, M.Task{id, lineage, contract, M.Archived{}, history, queue, phase}) ==
    M.Task{id, lineage, contract, M.Archived{}, history, queue, phase} : M.Task}

# Freeze suspends dispatch; stop permits settlement but never requests a model.
law frozen_no_dispatch:
  for phase: M.Phase
  {M.work(M.Frozen{}, phase) == M.NoWork{} : M.Work}

law stopped_no_model:
  for phase: M.Phase
  {M.is_model_request(M.work(M.Stopped{}, phase)) == False{} : Bool}

law stopped_input_reactivates:
  {M.after_input(M.Stopped{}) == M.Active{} : M.Status}

# The task contract does not change when its lifecycle or work phase changes.
law status_preserves_contract:
  for status: M.Status
  for +task: M.Task
  {M.task_contract(M.with_status(status, task)) == M.task_contract(task) : M.Contract}

law phase_preserves_contract:
  for phase: M.Phase
  for +task: M.Task
  {M.task_contract(M.with_phase(phase, task)) == M.task_contract(task) : M.Contract}

# FIFO is a list-monoid law instantiated by the actual input-queue operation.
law queue_order:
  for +first: String
  for +second: String
  for +task: M.Task
  {M.task_queue(M.queue_message(second, M.queue_message(first, task))) ==
    List.append(&2, String, M.task_queue(task), [first, second]) : +List<String>}

# A child shares the parent's history prefix and immutable contract, has a new
# task-parent edge, and receives no copy of the parent's waiting user messages.
law child_contract:
  for id: Nat
  for +parent: M.Task
  for call: String
  for branch: Nat
  for remaining: +List<M.Attempt>
  for message: Maybe<&2, String>
  {M.task_contract(P.child(id, parent, call, branch, remaining, message)) == M.task_contract(parent) : M.Contract}

law child_history_prefix:
  for id: Nat
  for +parent: M.Task
  for +call: String
  for +branch: Nat
  for remaining: +List<M.Attempt>
  {M.task_history(P.child(id, parent, call, branch, remaining, None{})) ==
    M.branch_history(M.task_history(parent), call, branch) : M.History}

law child_lineage:
  for id: Nat
  for +parent: M.Task
  for call: String
  for branch: Nat
  for remaining: +List<M.Attempt>
  for message: Maybe<&2, String>
  {M.task_lineage(P.child(id, parent, call, branch, remaining, message)) ==
    M.task_id(parent) <> M.task_lineage(parent) : +List<Nat>}

law child_queue_empty:
  for id: Nat
  for parent: M.Task
  for call: String
  for branch: Nat
  for remaining: +List<M.Attempt>
  for message: Maybe<&2, String>
  {M.task_queue(P.child(id, parent, call, branch, remaining, message)) == Nil{} : +List<String>}

# Recovery and inheritance do not grant permission to repeat an external effect.
law unknown_effect_not_repeated:
  for call: M.Call
  {M.may_execute(M.OutcomeUnknown{}, M.RecoveryAttempt{call}) == False{} : Bool}

law internal_effect_retry_safe:
  for attempt: M.Attempt
  {M.may_execute(M.RetrySafe{}, attempt) == True{} : Bool}

law recover_phase_idempotent:
  for +phase: M.Phase
  {T.recover_phase(T.recover_phase(phase)) == T.recover_phase(phase) : M.Phase}

# Rejected correlation leaves state untouched before the scheduling stage.
law unmatched_model_result_unchanged:
  for outcome: M.Outcome
  for allowed: +List<String>
  for task: M.Task
  for +world: M.World
  {P.decision_world(P.model_matched(False{}, outcome, allowed, task, world)) == world : M.World}

law unmatched_tool_result_unchanged:
  for call: M.Call
  for remaining: +List<M.Attempt>
  for value: J.Json
  for error: Bool
  for task: M.Task
  for +world: M.World
  {P.decision_world(P.tool_matched(False{}, call, remaining, value, error, task, world)) == world : M.World}

# History append and journal replay are actions of the list monoid: processing
# concatenated inputs equals processing the first part then the second part.
# Replay uses PROGRAM.next, not a specification-only simulator.
law history_append_composition:
  for +first: +List<M.Message>
  for +second: +List<M.Message>
  for +history: M.History
  {M.history_append(List.append(&2, M.Message, first, second), history) ==
    M.history_append(second, M.history_append(first, history)) : M.History}

law replay_composition:
  for +first: +List<M.Input>
  for +second: +List<M.Input>
  for +world: M.World
  {P.replay(List.append(&2, M.Input, first, second), world) ==
    P.replay(second, P.replay(first, world)) : M.World}

law replay_empty:
  for +world: M.World
  {P.replay(Nil{}, world) == world : M.World}

# All public queries, including invalid pages and failed output admission, leave
# the entire world unchanged and dispatch no effects. They need no journal entry.
law observation_preserves_world:
  for +query: M.Query
  for +world: M.World
  {P.decision_world(P.transition(M.UserCommand{M.Observe{query}}, world)) == world : M.World}

law observation_has_no_effects:
  for +query: M.Query
  for +world: M.World
  {P.decision_effects(P.transition(M.UserCommand{M.Observe{query}}, world)) == Nil{} : +List<M.Effect>}

law observation_not_durable:
  for query: M.Query
  {M.durable(M.UserCommand{M.Observe{query}}) == False{} : Bool}

# Inserting a query anywhere in an input trace preserves its final world.
# Query replies remain observable; this statement concerns task state, not replies.
law observation_replay:
  for +query: M.Query
  for +first: +List<M.Input>
  for +second: +List<M.Input>
  for +world: M.World
  {P.replay(List.append(&2, M.Input, first, M.UserCommand{M.Observe{query}} <> second), world) ==
    P.replay(List.append(&2, M.Input, first, second), world) : M.World}

law rejected_delivery_unchanged:
  for decision: M.Decision
  for +world: M.World
  {P.decision_world(P.output_admitted(False{}, decision, world)) == world : M.World}

law rejected_delivery_no_effects:
  for decision: M.Decision
  for world: M.World
  {P.decision_effects(P.output_admitted(False{}, decision, world)) == Nil{} : +List<M.Effect>}

law context_has_no_call_authority:
  for value: J.Json
  {T.item_calls([M.Context{value}]) == Nil{} : +List<M.Call>}
