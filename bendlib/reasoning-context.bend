import Base
import ../MODEL.bend as M
import ../REASONING.bend as R
import ./json.bend as J

# These are observations of the one native audit history. There is no host-side
# lease cache, turn counter or mutable copy of the task's reasoning settings.
def recorded(same_owner: Bool, effort: String, remaining: Nat) -> R.Lease:
  match same_owner:
    case True{}: R.Lease{effort, remaining}
    case False{}: R.NoLease{}

def nonzero(code: Maybe<&2, Nat>) -> Bool:
  match code:
    case Some{0n}: False{}
    case Some{1n+rest}: True{}
    case None{}: False{}

def failed_result(error: Bool, value: J.Json) -> Bool:
  error || nonzero(J.natural(J.get(value, "exit_code")))

def valid_after(invalidate: Bool, previous: R.Lease) -> R.Lease:
  match invalidate:
    case True{}: R.NoLease{}
    case False{}: previous

def lease(history: M.History, +owner: Nat) -> R.Lease:
  match history:
    case M.EmptyHistory{}: R.NoLease{}
    case M.HistoryNode{previous, M.ReasoningRecord{other, effort, remaining, sampling}}:
      recorded(Nat.is_eq(owner, other), effort, remaining)
    case M.HistoryNode{previous, M.UserMessage{text}}: R.NoLease{}
    case M.HistoryNode{previous, M.FailureMessage{text}}: R.NoLease{}
    case M.HistoryNode{previous, M.ContextCheckpoint{text}}: R.NoLease{}
    case M.HistoryNode{previous, M.ModelContext{value}}:
      valid_after(M.is_provider_checkpoint(value), lease(previous, owner))
    case M.HistoryNode{previous, M.FunctionOutput{call, value, error}}:
      valid_after(failed_result(error, value), lease(previous, owner))
    case M.HistoryNode{previous, M.OperationResult{operation, call, tool, value, error}}:
      valid_after(failed_result(error, value), lease(previous, owner))
    case M.HistoryNode{previous, M.ToolReceipt{task, operation, call, value, error}}:
      valid_after(failed_result(error, value), lease(previous, owner))
    case M.HistoryNode{previous, other}: lease(previous, owner)

def task_policy(task: M.Task) -> R.Policy:
  M.Task{id, lineage, M.Contract{model, tools, forks, descendants, plugins, context}, status, history, queued, phase, operations, notified} = task
  M.model_reasoning(model)

# Configuration updates are trusted native items, never opaque model output.
# A checkpoint starts a new provider context, so its next generation needs a
# fresh update, even if its selected effort happens to match the old one.
def after_checkpoint(checkpoint: Bool, previous: Maybe<&2, String>) -> Maybe<&2, String>:
  match checkpoint:
    case True{}: None{}
    case False{}: previous

def last_update(history: M.History) -> Maybe<&2, String>:
  match history:
    case M.EmptyHistory{}: None{}
    case M.HistoryNode{previous, M.ConfigurationUpdate{effort}}: Some{effort}
    case M.HistoryNode{previous, M.ContextCheckpoint{summary}}: None{}
    case M.HistoryNode{previous, M.ModelContext{value}}:
      after_checkpoint(M.is_provider_checkpoint(value), last_update(previous))
    case M.HistoryNode{previous, other}: last_update(previous)

def changed(previous: Maybe<&2, String>, effort: String) -> Bool:
  match previous:
    case None{}: True{}
    case Some{old}: Bool.not(String.eq(old, effort))

def trailing_update(history: M.History) -> Bool:
  match history:
    case M.HistoryNode{previous, M.ConfigurationUpdate{effort}}: True{}
    case M.HistoryNode{previous, M.ReasoningRecord{owner, effort, remaining, sampling}}: trailing_update(previous)
    case M.HistoryNode{previous, M.ToolReceipt{owner, operation, call, value, error}}: trailing_update(previous)
    case M.HistoryNode{previous, M.AfterRecord{owner, operation, plugin, outcome}}: trailing_update(previous)
    case M.HistoryNode{previous, M.ApprovalRecord{owner, operation, call, reviewer, outcome}}: trailing_update(previous)
    case _: False{}

def separate(needed: Bool, history: M.History) -> M.History:
  match needed:
    case True{}: M.HistoryNode{history, M.FailureMessage{"The previous generation has no retained output after its configuration update; continuing from the committed request prefix."}}
    case False{}: history

def update(needed: Bool, effort: String, history: M.History) -> M.History:
  match needed:
    case True{}: M.HistoryNode{history, M.ConfigurationUpdate{effort}}
    case False{}: history

def sampling_history(+emit: Bool, +effort: String, remaining: Nat, owner: Nat, +history: M.History) -> M.History:
  update(emit, effort, M.HistoryNode{separate(emit && trailing_update(history), history),
    M.ReasoningRecord{owner, effort, remaining, True{}}})

def generation(+effort: String, remaining: Nat, +task: M.Task) -> M.Task:
  M.with_history(sampling_history(R.uses_updates(task_policy(task)) && changed(last_update(M.task_history(task)), effort),
    effort, remaining, M.task_id(task), M.task_history(task)), task)

def select_record(same: Bool, effort: String, fallback: String) -> String:
  match same:
    case True{}: effort
    case False{}: fallback

def last_record(history: M.History, +owner: Nat, +fallback: String) -> String:
  match history:
    case M.EmptyHistory{}: fallback
    case M.HistoryNode{previous, M.ReasoningRecord{other, effort, remaining, True{}}}:
      select_record(Nat.is_eq(other, owner), effort, fallback)
    case M.HistoryNode{previous, M.ContextCheckpoint{summary}}: fallback
    case M.HistoryNode{previous, M.ModelContext{+value}}:
      select_record(M.is_provider_checkpoint(value), fallback, last_record(previous, owner, fallback))
    case M.HistoryNode{previous, other}: last_record(previous, owner, fallback)

def update_effort(previous: Maybe<&2, String>, baseline: String) -> String:
  match previous:
    case None{}: baseline
    case Some{effort}: effort

def effective(policy: R.Policy, owner: Nat, fixed: String, history: M.History) -> String:
  match policy:
    case R.Adaptive{evaluator, efforts, baseline, R.ConfigurationUpdates{}, maximum}:
      update_effort(last_update(history), baseline)
    case R.Adaptive{evaluator, efforts, baseline, R.RequestEffort{}, maximum}:
      last_record(history, owner, baseline)
    case R.Fixed{}: fixed

def sample_record(history: M.History, +owner: Nat, +policy: R.Policy) -> Bool:
  match history:
    case M.EmptyHistory{}: False{}
    case M.HistoryNode{previous, M.ReasoningRecord{other, effort, remaining, sampling}}:
      Nat.is_eq(owner, other) && sampling && R.allowed(policy, effort) && R.remaining_valid(policy, remaining)
    case M.HistoryNode{previous, other}: sample_record(previous, owner, policy)

def valid_sample(+policy: R.Policy, +owner: Nat, +history: M.History) -> Bool:
  match policy:
    case R.Fixed{}: True{}
    case R.Adaptive{evaluator, efforts, baseline, transport, maximum}:
      sample_record(history, owner, policy) && R.allowed(policy, effective(policy, owner, "", history))

def sampling(owner: Nat, model: M.Model, history: M.History) -> J.Json:
  M.Model{+profile, fixed, project} = model
  +policy = M.profile_reasoning(profile)
  +effort = effective(policy, owner, fixed, history)
  J.Object{[J.Field{"effective_effort", J.Text{effort}}, J.Field{"request_effort", J.Text{R.request_effort(policy, effort)}}]}

# The evaluator never receives encrypted continuation data, model-private
# reasoning or an arbitrary ModelContext object. Only these public text parts
# can cross the evaluator intent boundary. Transport truncation is labelled.
def public_part_named(kind: String, +part: J.Json, rest: +List<J.Json>) -> +List<J.Json>:
  match kind:
    case "output_text": J.Object{[J.Field{"text", J.Text{J.text(J.get(part, "text"))}}]} <> rest
    case "summary_text": J.Object{[J.Field{"text", J.Text{J.text(J.get(part, "text"))}}]} <> rest
    case "refusal": J.Object{[J.Field{"text", J.Text{J.text(J.get(part, "refusal"))}}]} <> rest
    case _: rest

def public_part(+part: J.Json, rest: +List<J.Json>) -> +List<J.Json>:
  public_part_named(J.text(J.get(part, "type")), part, rest)

def public_parts(parts: +List<J.Json>) -> +List<J.Json>:
  match parts:
    case Nil{}: Nil{}
    case Con{part, rest}: public_part(part, public_parts(rest))

def public_context_named(kind: String, +value: J.Json, rest: +List<J.Json>) -> +List<J.Json>:
  match kind:
    case "message":
      J.Object{[J.Field{"role", J.Text{"assistant"}}, J.Field{"content", J.Array{public_parts(J.items(J.get(value, "content")))}}]} <> rest
    case "reasoning":
      J.Object{[J.Field{"role", J.Text{"reasoning_summary"}}, J.Field{"content", J.Array{public_parts(J.items(J.get(value, "summary")))}}]} <> rest
    case _: rest

# read_task can return another task's provider items inside ordinary tool JSON.
# Project public structure recursively before it becomes evaluator text. This
# also handles structured MCP results; it does not guess at arbitrary strings.
def public_field(name: String, value: J.Json) -> J.Field:
  match name:
    case "encrypted_content": J.Field{"encrypted_content", J.Text{"[Private provider continuation omitted]"}}
    case _: J.Field{name, value}

def public_object(kind: String, source: J.Json, projected: J.Json) -> J.Json:
  match kind:
    case "reasoning": J.Object{[J.Field{"type", J.Text{"reasoning"}},
      J.Field{"summary", J.Array{public_parts(J.items(J.get(source, "summary")))}}]}
    case "compaction": J.Object{[J.Field{"type", J.Text{"compaction"}}, J.Field{"omitted", J.Text{"Opaque provider checkpoint"}}]}
    case _: projected

def public_object_prepend(field: J.Field, rest: J.Json) -> J.Json:
  match rest:
    case J.Object{fields}: J.Object{field <> fields}
    case other: J.Object{[field, J.Field{"__selvedge_preview__", other}]}

def public_array_prepend(value: J.Json, rest: J.Json) -> J.Json:
  match rest:
    case J.Array{items}: J.Array{value <> items}
    case other: J.Array{[value, other]}

def public_value(+fuel: Nat, +value: J.Json) -> J.Json:
  match fuel value:
    case 0n _: J.Text{"[Evaluator JSON preview: nesting or field limit reached]"}
    case 1n+p J.Array{Con{item, rest}}:
      public_array_prepend(public_value(p, item), public_value(p, J.Array{rest}))
    case 1n+p J.Object{Con{J.Field{name, item}, rest}}:
      public_object(J.text(J.get(value, "type")), value,
        public_object_prepend(public_field(name, public_value(p, item)), public_value(p, J.Object{rest})))
    case _ _: value

def public_message(message: M.Message, rest: +List<J.Json>) -> +List<J.Json>:
  match message:
    case M.UserMessage{text}: J.Object{[J.Field{"role", J.Text{"user"}}, J.Field{"content", J.Text{text}}]} <> rest
    case M.AssistantMessage{text}: J.Object{[J.Field{"role", J.Text{"assistant"}}, J.Field{"content", J.Text{text}}]} <> rest
    case M.FailureMessage{text}: J.Object{[J.Field{"role", J.Text{"error"}}, J.Field{"content", J.Text{text}}]} <> rest
    case M.ContextCheckpoint{text}: J.Object{[J.Field{"role", J.Text{"context_summary"}}, J.Field{"content", J.Text{text}}]} <> rest
    case M.ModelContext{+value}: public_context_named(J.text(J.get(value, "type")), value, rest)
    case M.FunctionCall{M.Call{id, name, arguments}}:
      J.Object{[J.Field{"role", J.Text{"function_call"}}, J.Field{"call_id", J.Text{id}},
        J.Field{"name", J.Text{name}}, J.Field{"arguments", public_value(512n, arguments)}]} <> rest
    case M.FunctionOutput{id, value, error}:
      J.Object{[J.Field{"role", J.Text{"function_output"}}, J.Field{"call_id", J.Text{id}},
        J.Field{"content", public_value(512n, value)}, J.Field{"is_error", J.Boolean{error}}]} <> rest
    case M.OperationResult{operation, id, tool, value, error}:
      J.Object{[J.Field{"role", J.Text{"function_output"}}, J.Field{"call_id", J.Text{id}}, J.Field{"name", J.Text{tool}},
        J.Field{"content", public_value(512n, value)}, J.Field{"is_error", J.Boolean{error}}]} <> rest
    case _: rest

def public_history(history: M.History, tail: +List<J.Json>) -> +List<J.Json>:
  match history:
    case M.EmptyHistory{}: tail
    case M.HistoryNode{previous, message}: public_history(previous, public_message(message, tail))
