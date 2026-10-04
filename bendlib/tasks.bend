import Base
import ./schema.bend as Schema
import ./effects.bend as Effects
import ./component.bend as C
import ./domain.bend as D
import ../HOOKS.bend as Hooks
import ./stdlib.bend as Std
import ./json.bend as J
import ./operations.bend as Ops

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

def update_state(task: D.Task, state: D.State) -> D.State:
  D.State{tasks, next_task, next_ticket, environment, limits, projects} = state
  D.State{replace(tasks, task), next_task, next_ticket, environment, limits, projects}

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
  D.Call{id, name, arguments} = call
  J.Object{[J.Field{"id", J.Text{id}}, J.Field{"name", J.Text{name}}, J.Field{"arguments", arguments}]}

def message_json(message: D.Message) -> J.Json:
  match message:
    case D.ForkResult{owner, call_id, branch}:
      J.Object{[J.Field{"role", J.Text{"function_output"}}, J.Field{"call_id", J.Text{call_id}},
        J.Field{"content", J.nat(branch)}, J.Field{"is_error", J.Boolean{False{}}}]}
    case D.HookRecord{owner, call_id, plugin, outcome}:
      J.Object{[J.Field{"role", J.Text{"hook_record"}}, J.Field{"task_id", J.nat(owner)}, J.Field{"call_id", J.Text{call_id}},
        J.Field{"plugin", D.plugin_json(plugin)}, J.Field{"content", D.hook_json(outcome)}]}
    case D.ToolReceipt{owner, operation, call, value, error}:
      J.Object{[J.Field{"role", J.Text{"tool_receipt"}}, J.Field{"task_id", J.nat(owner)}, J.Field{"operation_id", J.nat(operation)},
        J.Field{"call", call_json(call)}, J.Field{"content", value}, J.Field{"is_error", J.Boolean{error}}]}
    case D.AfterRecord{owner, operation, plugin, outcome}:
      J.Object{[J.Field{"role", J.Text{"after_record"}}, J.Field{"task_id", J.nat(owner)}, J.Field{"operation_id", J.nat(operation)},
        J.Field{"plugin", D.plugin_json(plugin)}, J.Field{"content", D.after_json(outcome)}]}
    case D.ApprovalRecord{owner, operation, call, reviewer, outcome}:
      J.Object{[J.Field{"role", J.Text{"approval_record"}}, J.Field{"task_id", J.nat(owner)}, J.Field{"operation_id", J.nat(operation)},
        J.Field{"call", call_json(call)}, J.Field{"reviewer", D.approval_reviewer_json(reviewer)},
        J.Field{"content", D.approval_outcome_json(outcome)}]}
    case D.UserMessage{text}:
      J.Object{[J.Field{"role", J.Text{"user"}}, J.Field{"content", J.Text{text}}]}
    case D.AssistantMessage{text}:
      J.Object{[J.Field{"role", J.Text{"assistant"}}, J.Field{"content", J.Text{text}}]}
    case D.FunctionCall{call}:
      J.Object{[J.Field{"role", J.Text{"function_call"}}, J.Field{"content", call_json(call)}]}
    case D.FunctionOutput{call_id, value, error}:
      J.Object{[J.Field{"role", J.Text{"function_output"}}, J.Field{"call_id", J.Text{call_id}},
        J.Field{"content", value}, J.Field{"is_error", J.Boolean{error}}]}
    case D.OperationResult{ticket, call_id, tool, value, error}:
      J.Object{[J.Field{"role", J.Text{"operation_result"}}, J.Field{"operation_id", J.nat(ticket)},
        J.Field{"call_id", J.Text{call_id}}, J.Field{"tool", J.Text{tool}},
        J.Field{"content", value}, J.Field{"is_error", J.Boolean{error}}]}
    case D.FailureMessage{text}:
      J.Object{[J.Field{"role", J.Text{"error"}}, J.Field{"content", J.Text{text}}]}
    case D.ModelContext{value}:
      J.Object{[J.Field{"role", J.Text{"model_context"}}, J.Field{"content", value}]}
    case D.ContextCheckpoint{summary}:
      J.Object{[J.Field{"role", J.Text{"context_summary"}}, J.Field{"content", J.Text{summary}}]}
    case D.ReasoningRecord{owner, effort, remaining, sampling}:
      J.Object{[J.Field{"role", J.Text{"reasoning_record"}}, J.Field{"task_id", J.nat(owner)},
        J.Field{"content", J.Object{[J.Field{"effort", J.Text{effort}}, J.Field{"remaining", J.nat(remaining)},
          J.Field{"sampling", J.Boolean{sampling}}]}}]}
    case D.ConfigurationUpdate{effort}:
      J.Object{[J.Field{"role", J.Text{"configuration_update"}}, J.Field{"content", J.Text{effort}}]}

def messages_json(messages: +List<D.Message>) -> +List<J.Json>:
  match messages:
    case Nil{}: Nil{}
    case Con{message, rest}: message_json(message) <> messages_json(rest)

def phase_name(phase: D.Phase) -> String:
  match phase:
    case D.HookPending{ticket, reference, call, pending, remaining}: "hook_pending"
    case D.Idle{}: "idle"
    case D.Ready{calls}: "ready"
    case D.CompactionReady{}: "compaction_ready"
    case D.ModelPending{ticket, callable}: "model_pending"
    case D.ReasoningPending{ticket, revision}: "reasoning_pending"
    case D.SummaryPending{ticket, resume}: "summary_pending"

def summary(task: D.Task) -> J.Json:
  D.Task{id, lineage, D.Contract{D.Model{D.Profile{profile, provider, model, policy}, reasoning, project}, tools, max_fork, max_descendants, plugins, context}, +status, history, queued, phase, operations, notified} = task
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

def model_reply(valid: Bool, items: +List<D.ModelItem>, calls: +List<D.Call>, +task: D.Task) -> D.Task:
  match valid:
    case True{}:
      after_model(calls, D.with_history(D.history_append(item_messages(items), D.task_history(task)), task))
    case False{}:
      settled_model(D.task_notified(task), D.append_message(D.FailureMessage{"invalid model reply: duplicate call identity, unavailable tool, or invalid arguments"}, task))

def context_limit(reducible: Bool, task: D.Task) -> D.Task:
  match reducible:
    case True{}:
      D.with_phase(D.CompactionReady{}, D.append_message(D.FailureMessage{"Model context limit reached; requesting one checkpoint before retry"}, task))
    case False{}:
      promote(D.with_phase(D.Idle{}, D.append_message(D.FailureMessage{"Model context limit persists after compaction; reduce the request, project guidance or tool catalog before resuming"}, task)))

def model_outcome(outcome: D.Outcome, allowed: +List<String>, +task: D.Task) -> D.Task:
  match outcome:
    case D.ModelFailure{message}:
      settled_model(D.task_notified(task), D.append_message(D.FailureMessage{message}, task))
    case D.ContextLimit{}:
      context_limit(D.compactable(D.context_history(D.task_history(task))), task)
    case D.ModelReply{+items}:
      +calls = item_calls(items)
      model_reply(valid_calls(calls, allowed, D.task_history(task)), items, calls, task)

def complete_tool(call: D.Call, remaining: +List<D.Attempt>, value: J.Json, error: Bool, task: D.Task) -> D.Task:
  promote(D.with_notified(True{}, D.with_phase(D.Ready{remaining}, D.append_message(D.FunctionOutput{call_id(call), value, error}, task))))

def complete_hook(outcome: D.HookOutcome, +task: D.Task) -> D.Task:
  promote(Hooks.complete(D.task_phase(task), outcome, task))

def complete_operation(operation: D.Operation(), value: J.Json, error: Bool, task: D.Task) -> D.Task:
  promote(Ops.completed(operation, value, error, task))

def summary_parts(parts: +List<J.Json>) -> String:
  match parts:
    case Nil{}: ""
    case Con{part, rest}: J.text(J.get(part, "text")) ++ summary_parts(rest)

def summary_context(value: J.Json) -> String:
  summary_parts(J.items(J.get(value, "content")))

def summary_text(items: +List<D.ModelItem>) -> String:
  match items:
    case Nil{}: ""
    case Con{D.Say{text}, rest}: text ++ summary_text(rest)
    case Con{D.Context{value}, rest}: summary_context(value) ++ summary_text(rest)
    case Con{D.Invoke{call}, rest}: summary_text(rest)

def has_invocation(items: +List<D.ModelItem>) -> Bool:
  match items:
    case Nil{}: False{}
    case Con{D.Invoke{call}, rest}: True{}
    case Con{other, rest}: has_invocation(rest)

def has_provider_checkpoint(items: +List<D.ModelItem>) -> Bool:
  match items:
    case Nil{}: False{}
    case Con{D.Context{value}, rest}: D.is_provider_checkpoint(value) || has_provider_checkpoint(rest)
    case Con{other, rest}: has_provider_checkpoint(rest)

def after_summary(resume: Bool) -> D.Phase:
  match resume:
    case True{}: D.Ready{Nil{}}
    case False{}: D.Idle{}

# Failure ends this summary attempt, not independently queued user requests.
# With no new input the task stays idle; frozen input stays queued. This never
# installs a partial checkpoint or an invocation from the rejected summary.
def summary_failure(message: String, task: D.Task) -> D.Task:
  promote(D.with_phase(D.Idle{}, D.append_message(D.FailureMessage{message}, task)))

def summary_checked(valid: Bool, summary: String, resume: Bool, task: D.Task) -> D.Task:
  match valid:
    case True{}:
      promote(D.with_phase(after_summary(resume), D.append_message(D.ContextCheckpoint{summary}, task)))
    case False{}:
      summary_failure("Compaction failed: expected a nonempty bounded summary without tool calls; original history retained", task)

def provider_summary_checked(valid: Bool, value: J.Json, resume: Bool, task: D.Task) -> D.Task:
  match valid:
    case True{}:
      promote(D.with_phase(after_summary(resume), D.append_message(D.ModelContext{value}, task)))
    case False{}:
      summary_failure("Compaction failed: expected one nonempty bounded provider checkpoint; original history retained", task)

def summary_context_result(checkpoint: Bool, +value: J.Json, resume: Bool, task: D.Task) -> D.Task:
  match checkpoint:
    case True{}: provider_summary_checked(D.valid_provider_checkpoint(value), value, resume, task)
    case False{}:
      +summary = summary_context(value)
      summary_checked(D.valid_summary(summary), summary, resume, task)

def summary_reply(items: +List<D.ModelItem>, resume: Bool, task: D.Task) -> D.Task:
  match items:
    case Con{D.Context{+value}, Nil{}}:
      summary_context_result(D.is_provider_checkpoint(value), value, resume, task)
    case +other:
      +summary = summary_text(other)
      summary_checked(Bool.not(has_invocation(other)) && Bool.not(has_provider_checkpoint(other)) &&
        D.valid_summary(summary), summary, resume, task)

def summary_outcome(outcome: D.Outcome, resume: Bool, task: D.Task) -> D.Task:
  match outcome:
    case D.ContextLimit{}:
      summary_failure("The summary request exceeded the model context limit; supply a bounded checkpoint with compact", task)
    case D.ModelFailure{message}: summary_failure(message, task)
    case D.ModelReply{items}: summary_reply(items, resume, task)

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
    case D.CompactionReady{}:
      D.HistoryNode{history, D.FailureMessage{"Context recovery cancelled before dispatch; original history retained"}}
    case D.ModelPending{ticket, callable}:
      D.HistoryNode{history, D.FailureMessage{"Model request interrupted by the user"}}
    case D.ReasoningPending{ticket, revision}:
      D.HistoryNode{history, D.FailureMessage{"Reasoning evaluation interrupted by the user; no model request was sent"}}
    case D.SummaryPending{ticket, resume}:
      D.HistoryNode{history, D.FailureMessage{"Context summary interrupted; original history retained"}}
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
    case D.SummaryPending{ticket, resume}: [Effects.CancelTicket{id, ticket}]
    case _: Nil{}

def recover_summary(resume: Bool) -> D.Phase:
  match resume:
    case True{}: D.CompactionReady{}
    case False{}: D.Idle{}

def recover_phase(phase: D.Phase) -> D.Phase:
  match phase:
    case D.ModelPending{ticket, callable}: D.Ready{Nil{}}
    case D.ReasoningPending{ticket, revision}: D.Ready{Nil{}}
    case D.SummaryPending{ticket, resume}: recover_summary(resume)
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
