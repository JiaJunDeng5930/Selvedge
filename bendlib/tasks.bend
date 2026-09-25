import Base
import ./json.bend as J
import ../MODEL.bend as M

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
  M.Contract{model, tools, max_fork, max_descendants} = contract
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
  M.Contract{model, tools, max_fork, max_descendants} = contract
  tools

def task_model(contract: M.Contract) -> M.Model:
  M.Contract{model, tools, max_fork, max_descendants} = contract
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
    case M.UserMessage{text}:
      J.Object{[J.Field{"role", J.Text{"user"}}, J.Field{"content", J.Text{text}}]}
    case M.AssistantMessage{text}:
      J.Object{[J.Field{"role", J.Text{"assistant"}}, J.Field{"content", J.Text{text}}]}
    case M.FunctionCall{call}:
      J.Object{[J.Field{"role", J.Text{"function_call"}}, J.Field{"content", call_json(call)}]}
    case M.FunctionOutput{call_id, value, error}:
      J.Object{[J.Field{"role", J.Text{"function_output"}}, J.Field{"call_id", J.Text{call_id}},
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
    case M.Idle{}: "idle"
    case M.Ready{calls}: "ready"
    case M.ModelPending{ticket, callable}: "model_pending"
    case M.SummaryPending{ticket, resume}: "summary_pending"
    case M.ToolPending{ticket, call, remaining}: "tool_pending"

def summary(task: M.Task) -> J.Json:
  M.Task{id, lineage, M.Contract{M.Model{M.Profile{profile, provider, model}, reasoning}, tools, max_fork, max_descendants}, +status, history, queued, phase} = task
  J.Object{[J.Field{"id", J.nat(id)}, J.Field{"parent", J.optional_nat(List.head(&2, Nat, lineage))},
    J.Field{"profile", J.Text{profile}}, J.Field{"provider", J.Text{provider}}, J.Field{"model", J.Text{model}}, J.Field{"reasoning", J.Text{reasoning}},
    J.Field{"status", J.Text{M.status_name(status)}}, J.Field{"controls", M.controls(status)},
    J.Field{"phase", J.Text{phase_name(phase)}}, J.Field{"cursor", J.nat(M.history_length(history))},
    J.Field{"queued", J.nat(List.length(&2, String, queued))},
    J.Field{"max_fork", J.nat(max_fork)}, J.Field{"max_descendants", J.nat(max_descendants)}]}

def summaries(tasks: +List<M.Task>) -> +List<J.Json>:
  match tasks:
    case Nil{}: Nil{}
    case Con{task, rest}: summary(task) <> summaries(rest)

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
    case M.Task{id, lineage, contract, status, history, Nil{}, phase}:
      M.Task{id, lineage, contract, status, history, Nil{}, phase}
    case M.Task{id, lineage, contract, status, history, Con{text, rest}, phase}:
      M.Task{id, lineage, contract, status, M.history_append(user_messages(text <> rest), history), Nil{}, M.Ready{Nil{}}}

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

def after_model(calls: +List<M.Call>, task: M.Task) -> M.Task:
  match calls:
    case Nil{}: promote(M.with_phase(M.Idle{}, task))
    case Con{+call, +rest}:
      M.with_phase(M.Ready{M.initial_attempts(call <> rest)}, task)

def model_reply(valid: Bool, items: +List<M.ModelItem>, calls: +List<M.Call>, +task: M.Task) -> M.Task:
  match valid:
    case True{}:
      after_model(calls, M.with_history(M.history_append(item_messages(items), M.task_history(task)), task))
    case False{}:
      promote(M.with_phase(M.Idle{}, M.append_message(M.FailureMessage{"invalid model reply: duplicate call identity, unavailable tool, or invalid arguments"}, task)))

def model_outcome(outcome: M.Outcome, allowed: +List<String>, +task: M.Task) -> M.Task:
  match outcome:
    case M.ModelFailure{message}:
      promote(M.with_phase(M.Idle{}, M.append_message(M.FailureMessage{message}, task)))
    case M.ModelReply{+items}:
      +calls = item_calls(items)
      model_reply(valid_calls(calls, allowed, M.task_history(task)), items, calls, task)

def complete_tool(call: M.Call, remaining: +List<M.Attempt>, value: J.Json, error: Bool, task: M.Task) -> M.Task:
  promote(M.with_phase(M.Ready{remaining}, M.append_message(M.FunctionOutput{call_id(call), value, error}, task)))

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

def after_summary(resume: Bool) -> M.Phase:
  match resume:
    case True{}: M.Ready{Nil{}}
    case False{}: M.Idle{}

def summary_checked(valid: Bool, summary: String, resume: Bool, task: M.Task) -> M.Task:
  match valid:
    case True{}:
      promote(M.with_phase(after_summary(resume), M.append_message(M.ContextCheckpoint{summary}, task)))
    case False{}:
      M.with_phase(M.Idle{}, M.append_message(M.FailureMessage{"Compaction failed: expected a nonempty bounded summary without tool calls; original history retained"}, task))

def summary_outcome(outcome: M.Outcome, resume: Bool, task: M.Task) -> M.Task:
  match outcome:
    case M.ModelFailure{message}: M.with_phase(M.Idle{}, M.append_message(M.FailureMessage{message}, task))
    case M.ModelReply{+items}:
      +summary = summary_text(items)
      summary_checked(Bool.not(has_invocation(items)) && M.valid_summary(summary), summary, resume, task)

def interrupted_outcome(attempt: M.Attempt) -> J.Json:
  match attempt:
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
    case M.Idle{}: history
    case M.ModelPending{ticket, callable}:
      M.HistoryNode{history, M.FailureMessage{"Model request interrupted by the user"}}
    case M.SummaryPending{ticket, resume}:
      M.HistoryNode{history, M.FailureMessage{"Context summary interrupted; original history retained"}}
    case M.Ready{attempts}: interrupt_attempts(attempts, history)
    case M.ToolPending{ticket, +call, remaining}:
      interrupt_attempts(remaining, M.HistoryNode{history, M.FunctionOutput{call_id(call),
        interrupted_outcome(M.RecoveryAttempt{call}), True{}}})

def interrupt(task: M.Task) -> M.Task:
  M.Task{id, lineage, contract, status, history, queued, phase} = task
  M.Task{id, lineage, contract, M.Stopped{}, interrupted_history(phase, history), queued, M.Idle{}}

def recover_phase(phase: M.Phase) -> M.Phase:
  match phase:
    case M.ModelPending{ticket, callable}: M.Ready{Nil{}}
    case M.SummaryPending{ticket, resume}: after_summary(resume)
    case M.ToolPending{ticket, call, remaining}: M.Ready{M.RecoveryAttempt{call} <> remaining}
    case other: other

def recover(status: M.Status, +task: M.Task) -> M.Task:
  match status:
    case M.Archived{}: task
    case _: M.with_phase(recover_phase(M.task_phase(task)), task)

def runnable(tasks: +List<M.Task>) -> Maybe<&2, M.Task>:
  match tasks:
    case Nil{}: None{}
    case Con{+task, rest}:
      choose_task(M.has_work(M.work(M.task_status(task), M.task_phase(task))), task, runnable(rest))
