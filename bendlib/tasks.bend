import Base
import ../HOOKS.bend as Hooks
import ./stdlib.bend as Std
import ./json.bend as J
import ../MODEL.bend as M
import ./operations.bend as Ops

def has_id(xs: +List<Nat>, +id: Nat) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{head, tail}: Nat.is_eq(head, id) || has_id(tail, id)

def has_name(xs: +List<String>, +name: String) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{head, tail}: String.eq(head, name) || has_name(tail, name)

def choose_task(same: Bool, task: M.Task, rest: Maybe<&2, M.Task>) -> Maybe<&2, M.Task>:
  match same:
    case True{}: Some{task}
    case False{}: rest

def find(tasks: +List<M.Task>, +id: Nat) -> Maybe<&2, M.Task>:
  match tasks:
    case Nil{}: None{}
    case Con{+task, rest}:
      choose_task(Nat.is_eq(M.task_id(task), id), task, find(rest, id))

def replacement(same: Bool, old: M.Task, replacement: M.Task) -> M.Task:
  match same:
    case True{}: replacement
    case False{}: old

def replace(tasks: +List<M.Task>, +task: M.Task) -> +List<M.Task>:
  match tasks:
    case Nil{}: Nil{}
    case Con{+old, rest}:
      replacement(Nat.is_eq(M.task_id(old), M.task_id(task)), old, task) <> replace(rest, task)

def choose_tool(same: Bool, tool: M.Tool, rest: Maybe<&2, M.Tool>) -> Maybe<&2, M.Tool>:
  match same:
    case True{}: Some{tool}
    case False{}: rest

def find_tool(tools: +List<M.Tool>, +name: String) -> Maybe<&2, M.Tool>:
  match tools:
    case Nil{}: None{}
    case Con{+tool, rest}:
      choose_tool(String.eq(M.tool_name(tool), name), tool, find_tool(rest, name))

def available(catalog: +List<M.Tool>, +tool: M.Tool) -> Bool:
  match catalog:
    case Nil{}: False{}
    case Con{+entry, rest}:
      (String.eq(M.tool_name(entry), M.tool_name(tool)) && M.source_same(M.tool_source(entry), M.tool_source(tool))) || available(rest, tool)

def add_name(keep: Bool, name: String, rest: +List<String>) -> +List<String>:
  match keep:
    case True{}: name <> rest
    case False{}: rest

def callable(tools: +List<M.Tool>, +catalog: +List<M.Tool>) -> +List<String>:
  match tools:
    case Nil{}: Nil{}
    case Con{+tool, rest}:
      add_name(available(catalog, tool), M.tool_name(tool), callable(rest, catalog))

def add_count(yes: Bool, count: Nat) -> Nat:
  match yes:
    case True{}: 1n+count
    case False{}: count

def descendant_count(tasks: +List<M.Task>, +ancestor: Nat) -> Nat:
  match tasks:
    case Nil{}: 0n
    case Con{task, rest}:
      add_count(has_id(M.task_lineage(task), ancestor), descendant_count(rest, ancestor))

def contract_limit(contract: M.Contract) -> Nat:
  M.Contract{model, tools, max_fork, max_descendants, plugins} = contract
  max_descendants

def ancestor_fits(task: Maybe<&2, M.Task>, added: Nat, descendants: Nat) -> Bool:
  match task:
    case None{}: False{}
    case Some{task}:
      Nat.is_le(Nat.add(added, descendants), contract_limit(M.task_contract(task)))

def ancestors_fit(ancestors: +List<Nat>, +tasks: +List<M.Task>, +added: Nat) -> Bool:
  match ancestors:
    case Nil{}: True{}
    case Con{+ancestor, rest}:
      ancestor_fits(find(tasks, ancestor), added, descendant_count(tasks, ancestor)) && ancestors_fit(rest, tasks, added)

def task_tools(contract: M.Contract) -> +List<M.Tool>:
  M.Contract{model, tools, max_fork, max_descendants, plugins} = contract
  tools

def task_model(contract: M.Contract) -> M.Model:
  M.Contract{model, tools, max_fork, max_descendants, plugins} = contract
  model

def call_id(call: M.Call) -> String:
  M.Call{id, name, arguments} = call
  id

def call_name(call: M.Call) -> String:
  M.Call{id, name, arguments} = call
  name

def call_arguments(call: M.Call) -> J.Json:
  M.Call{id, name, arguments} = call
  arguments

def call_json(call: M.Call) -> J.Json:
  M.Call{id, name, arguments} = call
  J.Object{[J.Field{"id", J.Text{id}}, J.Field{"name", J.Text{name}}, J.Field{"arguments", arguments}]}

def message_json(message: M.Message) -> J.Json:
  match message:
    case M.ForkResult{owner, call_id, branch}:
      J.Object{[J.Field{"role", J.Text{"function_output"}}, J.Field{"call_id", J.Text{call_id}},
        J.Field{"content", J.nat(branch)}, J.Field{"is_error", J.Boolean{False{}}}]}
    case M.HookRecord{owner, call_id, plugin, outcome}:
      J.Object{[J.Field{"role", J.Text{"hook_record"}}, J.Field{"task_id", J.nat(owner)}, J.Field{"call_id", J.Text{call_id}},
        J.Field{"plugin", M.plugin_json(plugin)}, J.Field{"content", M.hook_json(outcome)}]}
    case M.ToolReceipt{owner, operation, call, value, error}:
      J.Object{[J.Field{"role", J.Text{"tool_receipt"}}, J.Field{"task_id", J.nat(owner)}, J.Field{"operation_id", J.nat(operation)},
        J.Field{"call", call_json(call)}, J.Field{"content", value}, J.Field{"is_error", J.Boolean{error}}]}
    case M.AfterRecord{owner, operation, plugin, outcome}:
      J.Object{[J.Field{"role", J.Text{"after_record"}}, J.Field{"task_id", J.nat(owner)}, J.Field{"operation_id", J.nat(operation)},
        J.Field{"plugin", M.plugin_json(plugin)}, J.Field{"content", M.after_json(outcome)}]}
    case M.UserMessage{text}:
      J.Object{[J.Field{"role", J.Text{"user"}}, J.Field{"content", J.Text{text}}]}
    case M.AssistantMessage{text}:
      J.Object{[J.Field{"role", J.Text{"assistant"}}, J.Field{"content", J.Text{text}}]}
    case M.FunctionCall{call}:
      J.Object{[J.Field{"role", J.Text{"function_call"}}, J.Field{"content", call_json(call)}]}
    case M.FunctionOutput{call_id, value, error}:
      J.Object{[J.Field{"role", J.Text{"function_output"}}, J.Field{"call_id", J.Text{call_id}},
        J.Field{"content", value}, J.Field{"is_error", J.Boolean{error}}]}
    case M.OperationResult{ticket, call_id, tool, value, error}:
      J.Object{[J.Field{"role", J.Text{"operation_result"}}, J.Field{"operation_id", J.nat(ticket)},
        J.Field{"call_id", J.Text{call_id}}, J.Field{"tool", J.Text{tool}},
        J.Field{"content", value}, J.Field{"is_error", J.Boolean{error}}]}
    case M.FailureMessage{text}:
      J.Object{[J.Field{"role", J.Text{"error"}}, J.Field{"content", J.Text{text}}]}
    case M.ModelContext{value}:
      J.Object{[J.Field{"role", J.Text{"model_context"}}, J.Field{"content", value}]}
    case M.ContextCheckpoint{summary}:
      J.Object{[J.Field{"role", J.Text{"context_summary"}}, J.Field{"content", J.Text{summary}}]}

def messages_json(messages: +List<M.Message>) -> +List<J.Json>:
  match messages:
    case Nil{}: Nil{}
    case Con{message, rest}: message_json(message) <> messages_json(rest)

def strings_json(strings: +List<String>) -> +List<J.Json>:
  match strings:
    case Nil{}: Nil{}
    case Con{text, rest}: J.Text{text} <> strings_json(rest)

def phase_name(phase: M.Phase) -> String:
  match phase:
    case M.HookPending{ticket, reference, call, pending, remaining}: "hook_pending"
    case M.Idle{}: "idle"
    case M.Ready{calls}: "ready"
    case M.CompactionReady{}: "compaction_ready"
    case M.ModelPending{ticket, callable}: "model_pending"
    case M.SummaryPending{ticket, resume}: "summary_pending"

def summary(task: M.Task) -> J.Json:
  M.Task{id, lineage, M.Contract{M.Model{M.Profile{profile, provider, model}, reasoning, project}, tools, max_fork, max_descendants, plugins}, +status, history, queued, phase, operations, notified} = task
  J.Object{[J.Field{"id", J.nat(id)}, J.Field{"parent", J.optional_nat(List.head(&2, Nat, lineage))},
    J.Field{"profile", J.Text{profile}}, J.Field{"provider", J.Text{provider}}, J.Field{"model", J.Text{model}}, J.Field{"reasoning", J.Text{reasoning}},
    J.Field{"status", J.Text{M.status_name(status)}}, J.Field{"controls", M.controls(status)},
    J.Field{"phase", J.Text{phase_name(phase)}}, J.Field{"cursor", J.nat(M.history_length(history))},
    J.Field{"queued", J.nat(List.length(&2, String, queued))},
    J.Field{"operations", J.Array{Ops.summaries(operations)}},
    J.Field{"plugins", M.plugins_json(plugins)},
    J.Field{"max_fork", J.nat(max_fork)}, J.Field{"max_descendants", J.nat(max_descendants)}]}

def summaries(tasks: +List<M.Task>) -> +List<J.Json>:
  Std.map(~M.Task, ~J.Json, ~summary, tasks)

def page(+task: M.Task, +after: Nat, +limit: Nat) -> J.Json:
  +history = M.task_history(task)
  +length = M.history_length(history)
  messages = List.take(&2, M.Message, List.drop(&2, M.Message, M.history_messages(history, Nil{}), after), limit)
  J.Object{[J.Field{"task", summary(task)}, J.Field{"after", J.nat(after)},
    J.Field{"cursor", J.nat(length)}, J.Field{"has_more", J.Boolean{Nat.is_lt(Nat.add(after, limit), length)}},
    J.Field{"messages", J.Array{messages_json(messages)}}]}

def user_messages(inputs: +List<String>) -> +List<M.Message>:
  match inputs:
    case Nil{}: Nil{}
    case Con{text, rest}: M.UserMessage{text} <> user_messages(rest)

def drain(task: M.Task) -> M.Task:
  match task:
    case M.Task{id, lineage, contract, status, history, Nil{}, phase, operations, notified}:
      M.Task{id, lineage, contract, status, history, Nil{}, phase, operations, notified}
    case M.Task{id, lineage, contract, status, history, Con{text, rest}, phase, operations, notified}:
      M.Task{id, lineage, contract, status, M.history_append(user_messages(text <> rest), history), Nil{}, M.Ready{Nil{}}, operations, True{}}

def promote_when(status: M.Status, phase: M.Phase, task: M.Task) -> M.Task:
  match status phase:
    case M.Frozen{} _: task
    case M.Archived{} _: task
    case _ M.Idle{}: drain(task)
    case _ M.Ready{Nil{}}: drain(task)
    case _ _: task

def promote(+task: M.Task) -> M.Task:
  promote_when(M.task_status(task), M.task_phase(task), task)

def receive_when(status: M.Status, phase: M.Phase, text: String, task: M.Task) -> M.Task:
  match status phase:
    case M.Archived{} _: task
    case M.Frozen{} _: M.queue_message(text, task)
    case M.Active{} M.Idle{}:
      drain(M.queue_message(text, task))
    case M.Stopped{} M.Idle{}:
      drain(M.queue_message(text, M.with_status(M.Active{}, task)))
    case M.Stopped{} _:
      M.queue_message(text, M.with_status(M.Active{}, task))
    case _ _: M.queue_message(text, task)

def receive(text: String, +task: M.Task) -> M.Task:
  receive_when(M.task_status(task), M.task_phase(task), text, task)

def has_call(calls: +List<M.Call>, +id: String) -> Bool:
  match calls:
    case Nil{}: False{}
    case Con{call, rest}: String.eq(call_id(call), id) || has_call(rest, id)

def history_has_call(history: M.History, +id: String) -> Bool:
  match history:
    case M.EmptyHistory{}: False{}
    case M.HistoryNode{previous, M.FunctionCall{call}}:
      String.eq(call_id(call), id) || history_has_call(previous, id)
    case M.HistoryNode{previous, other}:
      history_has_call(previous, id)

def valid_calls(calls: +List<M.Call>, +allowed: +List<String>, +history: M.History) -> Bool:
  match calls:
    case Nil{}: True{}
    case Con{M.Call{+id, +name, arguments}, +rest}:
      M.nonempty(id) && M.nonempty(name) && has_name(allowed, name) && J.is_object(arguments) &&
        Bool.not(has_call(rest, id)) && Bool.not(history_has_call(history, id)) && valid_calls(rest, allowed, history)

def item_calls(items: +List<M.ModelItem>) -> +List<M.Call>:
  match items:
    case Nil{}: Nil{}
    case Con{M.Invoke{call}, rest}: call <> item_calls(rest)
    case Con{other, rest}: item_calls(rest)

def item_messages(items: +List<M.ModelItem>) -> +List<M.Message>:
  match items:
    case Nil{}: Nil{}
    case Con{M.Say{text}, rest}: M.AssistantMessage{text} <> item_messages(rest)
    case Con{M.Invoke{call}, rest}: M.FunctionCall{call} <> item_messages(rest)
    case Con{M.Context{value}, rest}: M.ModelContext{value} <> item_messages(rest)

def settled_model(notified: Bool, task: M.Task) -> M.Task:
  match notified:
    case True{}: promote(M.with_phase(M.Ready{Nil{}}, task))
    case False{}: promote(M.with_phase(M.Idle{}, task))

def after_model(calls: +List<M.Call>, +task: M.Task) -> M.Task:
  match calls:
    case Nil{}: settled_model(M.task_notified(task), task)
    case Con{+call, +rest}:
      M.with_phase(M.Ready{M.initial_attempts(call <> rest)}, task)

def model_reply(valid: Bool, items: +List<M.ModelItem>, calls: +List<M.Call>, +task: M.Task) -> M.Task:
  match valid:
    case True{}:
      after_model(calls, M.with_history(M.history_append(item_messages(items), M.task_history(task)), task))
    case False{}:
      settled_model(M.task_notified(task), M.append_message(M.FailureMessage{"invalid model reply: duplicate call identity, unavailable tool, or invalid arguments"}, task))

def context_limit(reducible: Bool, task: M.Task) -> M.Task:
  match reducible:
    case True{}:
      M.with_phase(M.CompactionReady{}, M.append_message(M.FailureMessage{"Model context limit reached; requesting one checkpoint before retry"}, task))
    case False{}:
      promote(M.with_phase(M.Idle{}, M.append_message(M.FailureMessage{"Model context limit persists after compaction; reduce the request, project guidance or tool catalog before resuming"}, task)))

def model_outcome(outcome: M.Outcome, allowed: +List<String>, +task: M.Task) -> M.Task:
  match outcome:
    case M.ModelFailure{message}:
      settled_model(M.task_notified(task), M.append_message(M.FailureMessage{message}, task))
    case M.ContextLimit{}:
      context_limit(M.compactable(M.context_history(M.task_history(task))), task)
    case M.ModelReply{+items}:
      +calls = item_calls(items)
      model_reply(valid_calls(calls, allowed, M.task_history(task)), items, calls, task)

def complete_tool(call: M.Call, remaining: +List<M.Attempt>, value: J.Json, error: Bool, task: M.Task) -> M.Task:
  promote(M.with_notified(True{}, M.with_phase(M.Ready{remaining}, M.append_message(M.FunctionOutput{call_id(call), value, error}, task))))

def complete_hook(outcome: M.HookOutcome, +task: M.Task) -> M.Task:
  promote(Hooks.complete(M.task_phase(task), outcome, task))

def complete_operation(operation: M.Operation(), value: J.Json, error: Bool, task: M.Task) -> M.Task:
  promote(Ops.completed(operation, value, error, task))

def summary_parts(parts: +List<J.Json>) -> String:
  match parts:
    case Nil{}: ""
    case Con{part, rest}: J.text(J.get(part, "text")) ++ summary_parts(rest)

def summary_context(value: J.Json) -> String:
  summary_parts(J.items(J.get(value, "content")))

def summary_text(items: +List<M.ModelItem>) -> String:
  match items:
    case Nil{}: ""
    case Con{M.Say{text}, rest}: text ++ summary_text(rest)
    case Con{M.Context{value}, rest}: summary_context(value) ++ summary_text(rest)
    case Con{M.Invoke{call}, rest}: summary_text(rest)

def has_invocation(items: +List<M.ModelItem>) -> Bool:
  match items:
    case Nil{}: False{}
    case Con{M.Invoke{call}, rest}: True{}
    case Con{other, rest}: has_invocation(rest)

def has_provider_checkpoint(items: +List<M.ModelItem>) -> Bool:
  match items:
    case Nil{}: False{}
    case Con{M.Context{value}, rest}: M.is_provider_checkpoint(value) || has_provider_checkpoint(rest)
    case Con{other, rest}: has_provider_checkpoint(rest)

def after_summary(resume: Bool) -> M.Phase:
  match resume:
    case True{}: M.Ready{Nil{}}
    case False{}: M.Idle{}

# Failure ends this summary attempt, not independently queued user requests.
# With no new input the task stays idle; frozen input stays queued. This never
# installs a partial checkpoint or an invocation from the rejected summary.
def summary_failure(message: String, task: M.Task) -> M.Task:
  promote(M.with_phase(M.Idle{}, M.append_message(M.FailureMessage{message}, task)))

def summary_checked(valid: Bool, summary: String, resume: Bool, task: M.Task) -> M.Task:
  match valid:
    case True{}:
      promote(M.with_phase(after_summary(resume), M.append_message(M.ContextCheckpoint{summary}, task)))
    case False{}:
      summary_failure("Compaction failed: expected a nonempty bounded summary without tool calls; original history retained", task)

def provider_summary_checked(valid: Bool, value: J.Json, resume: Bool, task: M.Task) -> M.Task:
  match valid:
    case True{}:
      promote(M.with_phase(after_summary(resume), M.append_message(M.ModelContext{value}, task)))
    case False{}:
      summary_failure("Compaction failed: expected one nonempty bounded provider checkpoint; original history retained", task)

def summary_context_result(checkpoint: Bool, +value: J.Json, resume: Bool, task: M.Task) -> M.Task:
  match checkpoint:
    case True{}: provider_summary_checked(M.valid_provider_checkpoint(value), value, resume, task)
    case False{}:
      +summary = summary_context(value)
      summary_checked(M.valid_summary(summary), summary, resume, task)

def summary_reply(items: +List<M.ModelItem>, resume: Bool, task: M.Task) -> M.Task:
  match items:
    case Con{M.Context{+value}, Nil{}}:
      summary_context_result(M.is_provider_checkpoint(value), value, resume, task)
    case +other:
      +summary = summary_text(other)
      summary_checked(Bool.not(has_invocation(other)) && Bool.not(has_provider_checkpoint(other)) &&
        M.valid_summary(summary), summary, resume, task)

def summary_outcome(outcome: M.Outcome, resume: Bool, task: M.Task) -> M.Task:
  match outcome:
    case M.ContextLimit{}:
      summary_failure("The summary request exceeded the model context limit; supply a bounded checkpoint with compact", task)
    case M.ModelFailure{message}: summary_failure(message, task)
    case M.ModelReply{items}: summary_reply(items, resume, task)

def interrupted_outcome(attempt: M.Attempt) -> J.Json:
  match attempt:
    case M.CheckedAttempt{call, pending}: M.failure("cancelled_before_execution", "This tool was cancelled during its authorization protocol, before dispatch")
    case M.InitialAttempt{call}: M.failure("cancelled_before_execution", "This tool was cancelled before dispatch")
    case M.RecoveryAttempt{call}: M.failure("outcome_unknown", "This tool may already have run; cancellation does not undo it")

def interrupt_attempts(attempts: +List<M.Attempt>, history: M.History) -> M.History:
  match attempts:
    case Nil{}: history
    case Con{+attempt, remaining}:
      interrupt_attempts(remaining, M.HistoryNode{history,
        M.FunctionOutput{call_id(M.attempt_call(attempt)), interrupted_outcome(attempt), True{}}})

def interrupted_history(phase: M.Phase, history: M.History) -> M.History:
  match phase:
    case M.HookPending{ticket, plugin, call, pending, remaining}:
      interrupt_attempts(remaining, M.HistoryNode{history,
        M.FunctionOutput{call_id(call), M.failure("hook_cancelled", "Authorization was interrupted; the tool was not dispatched. The plugin callback may already have run."), True{}}})
    case M.Idle{}: history
    case M.CompactionReady{}:
      M.HistoryNode{history, M.FailureMessage{"Context recovery cancelled before dispatch; original history retained"}}
    case M.ModelPending{ticket, callable}:
      M.HistoryNode{history, M.FailureMessage{"Model request interrupted by the user"}}
    case M.SummaryPending{ticket, resume}:
      M.HistoryNode{history, M.FailureMessage{"Context summary interrupted; original history retained"}}
    case M.Ready{attempts}: interrupt_attempts(attempts, history)

def interrupted_task(task: M.Task) -> M.Task:
  M.Task{id, lineage, contract, status, history, queued, phase, operations, notified} = task
  M.Task{id, lineage, contract, M.Stopped{}, interrupted_history(phase, history), queued, M.Idle{}, Nil{}, False{}}

def interrupt(task: M.Task) -> M.Task:
  interrupted_task(Ops.abandoned(task))

def archive_history(phase: M.Phase, +task: M.Task) -> M.Task:
  match phase:
    case M.HookPending{ticket, plugin, call, pending, remaining}:
      M.with_history(interrupted_history(M.HookPending{ticket, plugin, call, pending, remaining}, M.task_history(task)), task)
    case _: task

def archive(+task: M.Task) -> M.Task:
  M.with_notified(False{}, M.with_phase(M.Idle{}, M.with_status(M.Archived{}, Ops.abandoned(archive_history(M.task_phase(task), task)))))

def steering_status(status: M.Status) -> M.Status:
  match status:
    case M.Stopped{}: M.Active{}
    case other: other

def steer(text: String, task: M.Task) -> M.Task:
  M.Task{id, lineage, contract, status, history, queued, phase, operations, notified} = task
  M.Task{id, lineage, contract, steering_status(status),
    M.HistoryNode{interrupted_history(phase, history), M.UserMessage{text}}, queued,
    M.Ready{Nil{}}, operations, True{}}

def steering_effects(phase: M.Phase, id: Nat) -> +List<M.Effect>:
  match phase:
    case M.HookPending{ticket, plugin, call, pending, remaining}: [M.CancelTicket{id, ticket}]
    case M.ModelPending{ticket, allowed}: [M.CancelTicket{id, ticket}]
    case M.SummaryPending{ticket, resume}: [M.CancelTicket{id, ticket}]
    case _: Nil{}

def recover_summary(resume: Bool) -> M.Phase:
  match resume:
    case True{}: M.CompactionReady{}
    case False{}: M.Idle{}

def recover_phase(phase: M.Phase) -> M.Phase:
  match phase:
    case M.ModelPending{ticket, callable}: M.Ready{Nil{}}
    case M.SummaryPending{ticket, resume}: recover_summary(resume)
    case other: other

def recovered_operations(pending: Bool, task: M.Task) -> M.Task:
  match pending:
    case True{}: M.notify(Ops.abandoned(task))
    case False{}: task

def recover_running(+task: M.Task) -> M.Task:
  recovered_operations(M.operations_pending(M.task_operations(task)), M.with_phase(recover_phase(M.task_phase(task)), task))

def recover(status: M.Status, task: M.Task) -> M.Task:
  match status:
    case M.Archived{}: M.with_phase(M.Idle{}, Ops.abandoned(task))
    case _:
      recover_running(Hooks.recovered(task))

def runnable(tasks: +List<M.Task>) -> Maybe<&2, M.Task>:
  match tasks:
    case Nil{}: None{}
    case Con{+task, rest}:
      choose_task(M.has_work(M.task_work(task)), task, runnable(rest))
