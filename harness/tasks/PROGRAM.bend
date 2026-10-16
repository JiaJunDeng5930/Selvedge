import Base
import ../../bendlib/categories.bend as Categories
import ../transport/schema.bend as Schema
import ../../bendlib/effects.bend as Effects
import ../../bendlib/component.bend as C
import ../DOMAIN.bend as D
import ../conversation/CODEC.bend as Conversation
import ../approval/HOOKS.bend as Hooks
import ../../bendlib/stdlib.bend as Std
import ../../bendlib/json.bend as J
import ../execution/OPERATIONS.bend as Ops

def has_id(xs: +List<Nat>, +id: Nat) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{head, tail}: Nat.is_eq(head, id) || has_id(tail, id)

def choose_task(same: Bool, task: D.Task, rest: Maybe<&2, D.Task>) -> Maybe<&2, D.Task>:
  match same:
    case True{}: Some{task}
    case False{}: rest

def find(tasks: +List<D.Task>, +id: Nat) -> Maybe<&2, D.Task>:
  match tasks:
    case Nil{}: None{}
    case Con{+task, rest}:
      choose_task(Nat.is_eq(D.task_id(task), id), task, find(rest, id))

def replacement(same: Bool, old: D.Task, replacement: D.Task) -> D.Task:
  match same:
    case True{}: replacement
    case False{}: old

def replace(tasks: +List<D.Task>, +task: D.Task) -> +List<D.Task>:
  match tasks:
    case Nil{}: Nil{}
    case Con{+old, rest}:
      replacement(Nat.is_eq(D.task_id(old), D.task_id(task)), old, task) <> replace(rest, task)

# The storage algorithm depends only on its carrier's task observation and write.

def update_carrier(~S: Data, ~read: S -> +List<D.Task>, ~write: @values:+List<D.Task> -> @state:S -> S,
  task: D.Task, +state: S) -> S:
  write(replace(read(state), task), state)

def update_state(task: D.Task, state: D.State) -> D.State:
  update_carrier(~D.State, ~D.state_tasks, ~D.with_state_tasks, task, state)

def update_world(-StateRest: Data, task: D.Task, world: C.Frame<D.State, StateRest>) -> C.Frame<D.State, StateRest>:
  C.map_local(D.State, StateRest, state => update_state(task, state), world)

def choose_tool(same: Bool, tool: D.Tool, rest: Maybe<&2, D.Tool>) -> Maybe<&2, D.Tool>:
  match same:
    case True{}: Some{tool}
    case False{}: rest

def find_tool(tools: +List<D.Tool>, +name: String) -> Maybe<&2, D.Tool>:
  match tools:
    case Nil{}: None{}
    case Con{+tool, rest}:
      choose_tool(String.eq(D.tool_name(tool), name), tool, find_tool(rest, name))

def available(catalog: +List<D.Tool>, +tool: D.Tool) -> Bool:
  match catalog:
    case Nil{}: False{}
    case Con{+entry, rest}:
      D.tool_same(entry, tool) || available(rest, tool)

def add_name(keep: Bool, name: String, rest: +List<String>) -> +List<String>:
  match keep:
    case True{}: name <> rest
    case False{}: rest

def callable(tools: +List<D.Tool>, +catalog: +List<D.Tool>) -> +List<String>:
  match tools:
    case Nil{}: Nil{}
    case Con{+tool, rest}:
      add_name(available(catalog, tool), D.tool_name(tool), callable(rest, catalog))

def add_count(yes: Bool, count: Nat) -> Nat:
  match yes:
    case True{}: 1n+count
    case False{}: count

def descendant_count(tasks: +List<D.Task>, +ancestor: Nat) -> Nat:
  match tasks:
    case Nil{}: 0n
    case Con{task, rest}:
      add_count(has_id(D.task_lineage(task), ancestor), descendant_count(rest, ancestor))

def contract_limit(contract: D.Contract) -> Nat:
  D.Contract{model, tools, max_fork, max_descendants, plugins, context} = contract
  max_descendants

def ancestor_fits(task: Maybe<&2, D.Task>, added: Nat, descendants: Nat) -> Bool:
  match task:
    case None{}: False{}
    case Some{task}:
      Nat.is_le(Nat.add(added, descendants), contract_limit(D.task_contract(task)))

def ancestors_fit(ancestors: +List<Nat>, +tasks: +List<D.Task>, +added: Nat) -> Bool:
  match ancestors:
    case Nil{}: True{}
    case Con{+ancestor, rest}:
      ancestor_fits(find(tasks, ancestor), added, descendant_count(tasks, ancestor)) && ancestors_fit(rest, tasks, added)

def task_tools(contract: D.Contract) -> +List<D.Tool>:
  D.Contract{model, tools, max_fork, max_descendants, plugins, context} = contract
  tools

def task_model(contract: D.Contract) -> D.Model:
  D.Contract{model, tools, max_fork, max_descendants, plugins, context} = contract
  model

def call_id(call: D.Call) -> String:
  D.Call{id, name, arguments} = call
  id

def call_name(call: D.Call) -> String:
  D.Call{id, name, arguments} = call
  name

def call_arguments(call: D.Call) -> J.Json:
  D.Call{id, name, arguments} = call
  arguments

def call_json(call: D.Call) -> J.Json:
  Conversation.call_json(call)

def message_json(message: D.Message) -> J.Json:
  Conversation.message_json(message)

def messages_json(messages: +List<D.Message>) -> +List<J.Json>:
  Conversation.messages_json(messages)

def phase_name(phase: D.Phase) -> String:
  match phase:
    case D.HookPending{ticket, reference, call, pending, remaining}: "hook_pending"
    case D.Idle{}: "idle"
    case D.Ready{calls}: "ready"
    case D.ModelPending{ticket, callable}: "model_pending"
    case D.ReasoningPending{ticket, revision}: "reasoning_pending"

def summary(task: D.Task) -> J.Json:
  D.Task{id, lineage, D.Contract{D.Model{D.Profile{profile, provider, model, policy, options}, reasoning}, tools, max_fork, max_descendants, plugins, context}, +status, history, queued, phase, operations, notified} = task
  J.Object{[J.Field{"id", J.nat(id)}, J.Field{"parent", J.optional_nat(List.head(&2, Nat, lineage))},
    J.Field{"profile", J.Text{profile}}, J.Field{"provider", J.Text{provider}}, J.Field{"model", J.Text{model}}, J.Field{"reasoning", J.Text{reasoning}},
    J.Field{"status", J.Text{D.status_name(status)}}, J.Field{"controls", D.controls(status)},
    J.Field{"phase", J.Text{phase_name(phase)}}, J.Field{"cursor", J.nat(D.history_length(history))},
    J.Field{"queued", J.nat(List.length(&2, String, queued))},
    J.Field{"operations", J.Array{Ops.summaries(operations)}},
    J.Field{"plugins", D.plugins_json(plugins)}, J.Field{"settings", D.task_context_json(context)},
    J.Field{"max_fork", J.nat(max_fork)}, J.Field{"max_descendants", J.nat(max_descendants)}]}

def summaries(tasks: +List<D.Task>) -> +List<J.Json>:
  Std.map(~D.Task, ~J.Json, ~summary, tasks)

def page(+task: D.Task, +after: Nat, +limit: Nat) -> J.Json:
  +history = D.task_history(task)
  +length = D.history_length(history)
  messages = List.take(&2, D.Message, List.drop(&2, D.Message, D.history_messages(history, Nil{}), after), limit)
  J.Object{[J.Field{"task", summary(task)}, J.Field{"after", J.nat(after)},
    J.Field{"cursor", J.nat(length)}, J.Field{"has_more", J.Boolean{Nat.is_lt(Nat.add(after, limit), length)}},
    J.Field{"messages", J.Array{messages_json(messages)}}]}

def user_messages(inputs: +List<String>) -> +List<D.Message>:
  match inputs:
    case Nil{}: Nil{}
    case Con{text, rest}: D.UserMessage{text} <> user_messages(rest)

def drain(task: D.Task) -> D.Task:
  match task:
    case D.Task{id, lineage, contract, status, history, Nil{}, phase, operations, notified}:
      D.Task{id, lineage, contract, status, history, Nil{}, phase, operations, notified}
    case D.Task{id, lineage, contract, status, history, Con{text, rest}, phase, operations, notified}:
      D.Task{id, lineage, contract, status, D.history_append(user_messages(text <> rest), history), Nil{}, D.Ready{Nil{}}, operations, True{}}

def promote_when(status: D.Status, phase: D.Phase, task: D.Task) -> D.Task:
  match status phase:
    case D.Frozen{} _: task
    case D.Archived{} _: task
    case _ D.Idle{}: drain(task)
    case _ D.Ready{Nil{}}: drain(task)
    case _ _: task

def promote(+task: D.Task) -> D.Task:
  promote_when(D.task_status(task), D.task_phase(task), task)

def receive_when(status: D.Status, phase: D.Phase, text: String, task: D.Task) -> D.Task:
  match status phase:
    case D.Archived{} _: task
    case D.Frozen{} _: D.queue_message(text, task)
    case D.Active{} D.Idle{}:
      drain(D.queue_message(text, task))
    case D.Stopped{} D.Idle{}:
      drain(D.queue_message(text, D.with_status(D.Active{}, task)))
    case D.Stopped{} _:
      D.queue_message(text, D.with_status(D.Active{}, task))
    case _ _: D.queue_message(text, task)

def receive(text: String, +task: D.Task) -> D.Task:
  receive_when(D.task_status(task), D.task_phase(task), text, task)

def has_call(calls: +List<D.Call>, +id: String) -> Bool:
  match calls:
    case Nil{}: False{}
    case Con{call, rest}: String.eq(call_id(call), id) || has_call(rest, id)

def history_has_call(history: D.History, +id: String) -> Bool:
  match history:
    case D.EmptyHistory{}: False{}
    case D.HistoryNode{previous, D.FunctionCall{call}}:
      String.eq(call_id(call), id) || history_has_call(previous, id)
    case D.HistoryNode{previous, other}:
      history_has_call(previous, id)

def valid_calls(calls: +List<D.Call>, +allowed: +List<String>, +history: D.History) -> Bool:
  match calls:
    case Nil{}: True{}
    case Con{D.Call{+id, +name, arguments}, +rest}:
      D.nonempty(id) && D.nonempty(name) && Schema.contains(allowed, name) && J.is_object(arguments) &&
        Bool.not(has_call(rest, id)) && Bool.not(history_has_call(history, id)) && valid_calls(rest, allowed, history)

def item_calls(items: +List<D.ModelItem>) -> +List<D.Call>:
  match items:
    case Nil{}: Nil{}
    case Con{D.Invoke{call}, rest}: call <> item_calls(rest)
    case Con{other, rest}: item_calls(rest)

def item_messages(items: +List<D.ModelItem>) -> +List<D.Message>:
  match items:
    case Nil{}: Nil{}
    case Con{D.Say{text}, rest}: D.AssistantMessage{text} <> item_messages(rest)
    case Con{D.Invoke{call}, rest}: D.FunctionCall{call} <> item_messages(rest)
    case Con{D.Context{value}, rest}: D.ModelContext{value} <> item_messages(rest)

def settled_model(notified: Bool, task: D.Task) -> D.Task:
  match notified:
    case True{}: promote(D.with_phase(D.Ready{Nil{}}, task))
    case False{}: promote(D.with_phase(D.Idle{}, task))

def after_model(calls: +List<D.Call>, +task: D.Task) -> D.Task:
  match calls:
    case Nil{}: settled_model(D.task_notified(task), task)
    case Con{+call, +rest}:
      D.with_phase(D.Ready{D.initial_attempts(call <> rest)}, task)

type ModelReplyCandidate is Data:
  ModelReplyCandidate{items: +List<D.ModelItem>}

def model_reply_permitted(+allowed: +List<String>, +task: D.Task, candidate: ModelReplyCandidate) -> Bool:
  ModelReplyCandidate{items} = candidate
  valid_calls(item_calls(items), allowed, D.task_history(task))

def model_reply_calculation(items: +List<D.ModelItem>, calls: +List<D.Call>, +task: D.Task) -> D.Task:
  after_model(calls, D.with_history(D.history_append(item_messages(items), D.task_history(task)), task))

def model_reply(+allowed: +List<String>, +task: D.Task,
  member: Categories.Membership<ModelReplyCandidate, Categories.holds(ModelReplyCandidate, candidate => model_reply_permitted(allowed, task, candidate))>) -> D.Task:
  Categories.Membership{candidate, evidence} = member
  ModelReplyCandidate{+items} = candidate
  model_reply_calculation(items, item_calls(items), task)

def model_reply_admission(+allowed: +List<String>, +task: D.Task,
  result: Maybe<&1, Categories.Membership<ModelReplyCandidate, Categories.holds(ModelReplyCandidate, candidate => model_reply_permitted(allowed, task, candidate))>>) -> D.Task:
  match result:
    case Some{member}: model_reply(allowed, task, member)
    case None{}:
      settled_model(D.task_notified(task), D.append_message(D.FailureMessage{"invalid model reply: duplicate call identity, unavailable tool, or invalid arguments"}, task))

def context_limit(reducible: Bool, task: D.Task) -> D.Task:
  promote(D.with_phase(D.Idle{}, D.append_message(D.FailureMessage{"Model context limit reached; full task history retained"}, task)))

def model_outcome(outcome: D.Outcome, +allowed: +List<String>, +task: D.Task) -> D.Task:
  match outcome:
    case D.ModelFailure{message}:
      settled_model(D.task_notified(task), D.append_message(D.FailureMessage{message}, task))
    case D.ContextLimit{}:
      context_limit(False{}, task)
    case D.ModelReply{+items}:
      model_reply_admission(allowed, task, Categories.admit(ModelReplyCandidate, candidate => model_reply_permitted(allowed, task, candidate), ModelReplyCandidate{items}))

def complete_tool(call: D.Call, remaining: +List<D.Attempt>, value: J.Json, error: Bool, task: D.Task) -> D.Task:
  promote(D.with_notified(True{}, D.with_phase(D.Ready{remaining}, D.append_message(D.FunctionOutput{call_id(call), value, error}, task))))

def complete_hook(outcome: D.HookOutcome, +task: D.Task) -> D.Task:
  promote(Hooks.complete(D.task_phase(task), outcome, task))

def complete_operation(operation: D.Operation(), value: J.Json, error: Bool, task: D.Task) -> D.Task:
  promote(Ops.completed(operation, value, error, task))

def interrupted_outcome(attempt: D.Attempt) -> J.Json:
  match attempt:
    case D.CheckedAttempt{call, pending}: D.failure("cancelled_before_execution", "This tool was cancelled during its authorization protocol, before dispatch")
    case D.InitialAttempt{call}: D.failure("cancelled_before_execution", "This tool was cancelled before dispatch")
    case D.RecoveryAttempt{call}: D.failure("outcome_unknown", "This tool may already have run; cancellation does not undo it")

def interrupt_attempts(attempts: +List<D.Attempt>, history: D.History) -> D.History:
  match attempts:
    case Nil{}: history
    case Con{+attempt, remaining}:
      interrupt_attempts(remaining, D.HistoryNode{history,
        D.FunctionOutput{call_id(D.attempt_call(attempt)), interrupted_outcome(attempt), True{}}})

def interrupted_history(phase: D.Phase, history: D.History) -> D.History:
  match phase:
    case D.HookPending{ticket, plugin, call, pending, remaining}:
      interrupt_attempts(remaining, D.HistoryNode{history,
        D.FunctionOutput{call_id(call), D.failure("hook_cancelled", "Authorization was interrupted; the tool was not dispatched. The plugin callback may already have run."), True{}}})
    case D.Idle{}: history
    case D.ModelPending{ticket, callable}:
      D.HistoryNode{history, D.FailureMessage{"Model request interrupted by the user"}}
    case D.ReasoningPending{ticket, revision}:
      D.HistoryNode{history, D.FailureMessage{"Reasoning evaluation interrupted by the user; no model request was sent"}}
    case D.Ready{attempts}: interrupt_attempts(attempts, history)

def interrupted_task(task: D.Task) -> D.Task:
  D.Task{id, lineage, contract, status, history, queued, phase, operations, notified} = task
  D.Task{id, lineage, contract, D.Stopped{}, interrupted_history(phase, history), queued, D.Idle{}, Nil{}, False{}}

def interrupt(task: D.Task) -> D.Task:
  interrupted_task(Ops.abandoned(task))

def archive_history(phase: D.Phase, +task: D.Task) -> D.Task:
  match phase:
    case D.HookPending{ticket, plugin, call, pending, remaining}:
      D.with_history(interrupted_history(D.HookPending{ticket, plugin, call, pending, remaining}, D.task_history(task)), task)
    case _: task

def archive(+task: D.Task) -> D.Task:
  D.with_notified(False{}, D.with_phase(D.Idle{}, D.with_status(D.Archived{}, Ops.abandoned(archive_history(D.task_phase(task), task)))))

def steering_status(status: D.Status) -> D.Status:
  match status:
    case D.Stopped{}: D.Active{}
    case other: other

def steer(text: String, task: D.Task) -> D.Task:
  D.Task{id, lineage, contract, status, history, queued, phase, operations, notified} = task
  D.Task{id, lineage, contract, steering_status(status),
    D.HistoryNode{interrupted_history(phase, history), D.UserMessage{text}}, queued,
    D.Ready{Nil{}}, operations, True{}}

def steering_effects(-EffectRest: Data, phase: D.Phase, id: Nat) -> +List<Effects.Effect<EffectRest>>:
  match phase:
    case D.HookPending{ticket, plugin, call, pending, remaining}: [Effects.CancelTicket{id, ticket}]
    case D.ModelPending{ticket, allowed}: [Effects.CancelTicket{id, ticket}]
    case D.ReasoningPending{ticket, revision}: [Effects.CancelTicket{id, ticket}]
    case _: Nil{}

def recover_phase(phase: D.Phase) -> D.Phase:
  match phase:
    case D.ModelPending{ticket, callable}: D.Ready{Nil{}}
    case D.ReasoningPending{ticket, revision}: D.Ready{Nil{}}
    case other: other

def recovered_operations(pending: Bool, task: D.Task) -> D.Task:
  match pending:
    case True{}: D.notify(Ops.abandoned(task))
    case False{}: task

def recover_running(+task: D.Task) -> D.Task:
  recovered_operations(D.operations_pending(D.task_operations(task)), D.with_phase(recover_phase(D.task_phase(task)), task))

def recover(status: D.Status, task: D.Task) -> D.Task:
  match status:
    case D.Archived{}: D.with_phase(D.Idle{}, Ops.abandoned(task))
    case _:
      recover_running(Hooks.recovered(task))

def runnable(tasks: +List<D.Task>) -> Maybe<&2, D.Task>:
  match tasks:
    case Nil{}: None{}
    case Con{+task, rest}:
      choose_task(D.has_work(D.task_work(task)), task, runnable(rest))
