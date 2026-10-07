import Base
import ../DOMAIN.bend as D
import ../LAWS.bend as Laws
import ../../bendlib/theory.bend as Theory
import ../CONTRACT.bend as Concepts
import ../../bendlib/json.bend as J
import ./PROGRAM.bend as T

# Local proof obligations for the tasks boundary. No runtime policy lives here.

def Laws.context_recovery_work(task, world):
  {==}

def Laws.context_recovery_ready(task):
  match task:
    case D.Task{id, lineage, contract, status, history, queued, phase, operations, notified}: {==}

def Laws.recover_resumable_summary(ticket):
  {==}

def Laws.checkpoint_consumes_compaction(history, summary):
  {==}

def Laws.checkpoint_is_not_recompacted(id, lineage, contract, status, history, summary, queued, phase, world, operations, notified):
  {==}

def Laws.context_limit_after_checkpoint_stops(allowed, id, lineage, contract, status, history, summary, phase, operations, notified):
  match status:
    case D.Active{}: {==}
    case D.Frozen{}: {==}
    case D.Stopped{}: {==}
    case D.Archived{}: {==}

def Laws.summary_context_limit_stops(resume, id, lineage, contract, status, history, phase, operations, notified):
  match status:
    case D.Active{}: {==}
    case D.Frozen{}: {==}
    case D.Stopped{}: {==}
    case D.Archived{}: {==}

def Laws.checkpoint_preserves_project_contract(task, summary):
  match task:
    case D.Task{id, lineage, contract, status, history, queued, phase, operations, notified}: {==}

def Laws.bash_recovery_blocked(call):
  {==}

def Laws.mcp_recovery_blocked(server, name, call):
  {==}

def Laws.archived_terminal(request):
  match request:
    case D.Freeze{}: {==}
    case D.Unfreeze{}: {==}
    case D.Stop{}: {==}
    case D.Interrupt{}: {==}
    case D.Archive{}: {==}

def Laws.archived_input_unchanged(id, lineage, contract, history, queue, phase, text, operations, notified):
  {==}

def Laws.frozen_no_dispatch(phase):
  {==}

def Laws.stopped_no_model(phase):
  match phase:
    case D.HookPending{ticket, reference, call, pending, remaining}: {==}
    case D.Idle{}: {==}
    case D.CompactionReady{}: {==}
    case D.Ready{Nil{}}: {==}
    case D.Ready{Con{call, rest}}: {==}
    case D.ModelPending{ticket, callable}: {==}
    case D.ReasoningPending{ticket, revision}: {==}
    case D.SummaryPending{ticket, resume}: {==}

def Laws.stopped_input_reactivates():
  {==}

def Laws.interrupt_preserves_contract(task):
  match task:
    case D.Task{id, lineage, contract, status, history, queue, phase, operations, notified}: {==}

def Laws.interrupt_preserves_queue(task):
  match task:
    case D.Task{id, lineage, contract, status, history, queue, phase, operations, notified}: {==}

def Laws.interrupt_settles_phase(task):
  match task:
    case D.Task{id, lineage, contract, status, history, queue, phase, operations, notified}: {==}

def Laws.interrupt_idempotent(task):
  match task:
    case D.Task{id, lineage, contract, status, history, queue, phase, operations, notified}: {==}

def Laws.status_preserves_contract(status, task):
  match task:
    case D.Task{id, lineage, contract, old, history, queued, phase, operations, notified}: {==}

def Laws.phase_preserves_contract(phase, task):
  match task:
    case D.Task{id, lineage, contract, status, history, queued, old, operations, notified}: {==}

def Laws.queue_order(first, second, task):
  match task:
    case D.Task{id, lineage, contract, status, history, +queued, phase, operations, notified}:
      Theory.append_associative(String, queued, [first], [second])

def Laws.child_contract(id, parent, call, branch, remaining, message):
  match parent:
    case D.Task{parent_id, lineage, contract, status, history, queued, phase, operations, notified}: {==}

def Laws.child_history_prefix(id, parent, call, branch, remaining):
  match parent:
    case D.Task{parent_id, lineage, contract, status, history, queued, phase, operations, notified}: {==}

def Laws.child_lineage(id, parent, call, branch, remaining, message):
  match parent:
    case D.Task{parent_id, lineage, contract, status, history, queued, phase, operations, notified}: {==}

def Laws.child_queue_empty(id, parent, call, branch, remaining, message):
  match parent:
    case D.Task{parent_id, lineage, contract, status, history, queued, phase, operations, notified}: {==}

def Laws.unknown_effect_not_repeated(call):
  {==}

def Laws.internal_effect_retry_safe(attempt):
  {==}

def Laws.recover_phase_idempotent(phase):
  match phase:
    case D.HookPending{ticket, reference, call, pending, remaining}: {==}
    case D.Idle{}: {==}
    case D.CompactionReady{}: {==}
    case D.Ready{calls}: {==}
    case D.ModelPending{ticket, callable}: {==}
    case D.ReasoningPending{ticket, revision}: {==}
    case D.SummaryPending{ticket, True{}}: {==}
    case D.SummaryPending{ticket, False{}}: {==}

def Laws.unmatched_model_result_unchanged(outcome, allowed, task, world):
  {==}

def Laws.unmatched_tool_result_unchanged(operation, value, error, task, world):
  {==}

def Laws.context_has_no_call_authority(value):
  {==}

# These are representation correspondences for the domain's history projection,
# not a second generic filter algebra. Only user-authored requests survive a cut.
def Laws.retained_users_projected(history):
  match history:
    case D.EmptyHistory{}: {==}
    case D.HistoryNode{+previous, D.UserMessage{+text}}:
      %Laws.retained_users_projected(previous) :
        {D.HistoryNode{D.context_history(D.retained_users(previous)), D.UserMessage{text}} == D.HistoryNode{_, D.UserMessage{text}} : D.History}
      {==}
    case D.HistoryNode{previous, D.AssistantMessage{text}}: Laws.retained_users_projected(previous)
    case D.HistoryNode{previous, D.FunctionCall{call}}: Laws.retained_users_projected(previous)
    case D.HistoryNode{previous, D.FunctionOutput{id, value, error}}: Laws.retained_users_projected(previous)
    case D.HistoryNode{previous, D.OperationResult{ticket, id, tool, value, error}}: Laws.retained_users_projected(previous)
    case D.HistoryNode{previous, D.FailureMessage{text}}: Laws.retained_users_projected(previous)
    case D.HistoryNode{previous, D.ModelContext{value}}: Laws.retained_users_projected(previous)
    case D.HistoryNode{previous, D.ContextCheckpoint{summary}}: Laws.retained_users_projected(previous)
    case D.HistoryNode{previous, D.ReasoningRecord{owner, effort, remaining, sampling}}: Laws.retained_users_projected(previous)
    case D.HistoryNode{previous, D.ConfigurationUpdate{effort}}: Laws.retained_users_projected(previous)
    case D.HistoryNode{previous, D.HookRecord{task, id, plugin, outcome}}: Laws.retained_users_projected(previous)
    case D.HistoryNode{previous, D.ToolReceipt{task, operation, call, value, error}}: Laws.retained_users_projected(previous)
    case D.HistoryNode{previous, D.AfterRecord{task, operation, plugin, outcome}}: Laws.retained_users_projected(previous)
    case D.HistoryNode{previous, D.ApprovalRecord{task, operation, call, reviewer, outcome}}: Laws.retained_users_projected(previous)
    case D.HistoryNode{previous, D.ForkResult{task, id, branch}}: Laws.retained_users_projected(previous)

def Laws.retained_users_idempotent(history):
  match history:
    case D.EmptyHistory{}: {==}
    case D.HistoryNode{+previous, D.UserMessage{+text}}:
      %Laws.retained_users_idempotent(previous) :
        {D.HistoryNode{D.retained_users(D.retained_users(previous)), D.UserMessage{text}} == D.HistoryNode{_, D.UserMessage{text}} : D.History}
      {==}
    case D.HistoryNode{previous, D.AssistantMessage{text}}: Laws.retained_users_idempotent(previous)
    case D.HistoryNode{previous, D.FunctionCall{call}}: Laws.retained_users_idempotent(previous)
    case D.HistoryNode{previous, D.FunctionOutput{id, value, error}}: Laws.retained_users_idempotent(previous)
    case D.HistoryNode{previous, D.OperationResult{ticket, id, tool, value, error}}: Laws.retained_users_idempotent(previous)
    case D.HistoryNode{previous, D.FailureMessage{text}}: Laws.retained_users_idempotent(previous)
    case D.HistoryNode{previous, D.ModelContext{value}}: Laws.retained_users_idempotent(previous)
    case D.HistoryNode{previous, D.ContextCheckpoint{summary}}: Laws.retained_users_idempotent(previous)
    case D.HistoryNode{previous, D.ReasoningRecord{owner, effort, remaining, sampling}}: Laws.retained_users_idempotent(previous)
    case D.HistoryNode{previous, D.ConfigurationUpdate{effort}}: Laws.retained_users_idempotent(previous)
    case D.HistoryNode{previous, D.HookRecord{task, id, plugin, outcome}}: Laws.retained_users_idempotent(previous)
    case D.HistoryNode{previous, D.ToolReceipt{task, operation, call, value, error}}: Laws.retained_users_idempotent(previous)
    case D.HistoryNode{previous, D.AfterRecord{task, operation, plugin, outcome}}: Laws.retained_users_idempotent(previous)
    case D.HistoryNode{previous, D.ApprovalRecord{task, operation, call, reviewer, outcome}}: Laws.retained_users_idempotent(previous)
    case D.HistoryNode{previous, D.ForkResult{task, id, branch}}: Laws.retained_users_idempotent(previous)

def retained_cut_fixed(+history: D.History) ->
  {D.retained_users(D.context_history(D.retained_users(history))) == D.retained_users(history) : D.History}:
  Equal.trans(D.History, D.retained_users(D.context_history(D.retained_users(history))),
    D.retained_users(D.retained_users(history)), D.retained_users(history),
    Equal.cong(D.History, D.History, D.retained_users, D.context_history(D.retained_users(history)),
      D.retained_users(history), Laws.retained_users_projected(history)),
    Laws.retained_users_idempotent(history))

def project_provider_idempotent(+checkpoint: Bool, +previous: D.History, +value: J.Json,
  checked: {D.is_provider_checkpoint(value) == checkpoint : Bool},
  evidence: {D.context_history(D.context_history(previous)) == D.context_history(previous) : D.History}) ->
  {D.context_history(D.provider_context_node(checkpoint, D.context_history(previous), value)) ==
    D.provider_context_node(checkpoint, D.context_history(previous), value) : D.History}:
  match checkpoint:
    case False{}:
      Equal.trans(D.History,
        D.provider_context_node(D.is_provider_checkpoint(value), D.context_history(D.context_history(previous)), value),
        D.HistoryNode{D.context_history(D.context_history(previous)), D.ModelContext{value}},
        D.HistoryNode{D.context_history(previous), D.ModelContext{value}},
        Equal.cong(Bool, D.History, (flag => D.provider_context_node(flag, D.context_history(D.context_history(previous)), value)),
          D.is_provider_checkpoint(value), False{}, checked),
        Equal.cong(D.History, D.History, (history => D.HistoryNode{history, D.ModelContext{value}}),
          D.context_history(D.context_history(previous)), D.context_history(previous), evidence))
    case True{}:
      Equal.trans(D.History,
        D.provider_context_node(D.is_provider_checkpoint(value), D.context_history(D.retained_users(D.context_history(previous))), value),
        D.HistoryNode{D.retained_users(D.context_history(D.retained_users(D.context_history(previous)))), D.ModelContext{value}},
        D.HistoryNode{D.retained_users(D.context_history(previous)), D.ModelContext{value}},
        Equal.cong(Bool, D.History, (flag => D.provider_context_node(flag, D.context_history(D.retained_users(D.context_history(previous))), value)),
          D.is_provider_checkpoint(value), True{}, checked),
        Equal.cong(D.History, D.History, (history => D.HistoryNode{history, D.ModelContext{value}}),
          D.retained_users(D.context_history(D.retained_users(D.context_history(previous)))),
          D.retained_users(D.context_history(previous)), retained_cut_fixed(D.context_history(previous))))

def project_node_idempotent(+previous: D.History, +message: D.Message,
  evidence: {D.context_history(D.context_history(previous)) == D.context_history(previous) : D.History}) ->
  {D.context_history(D.context_node(D.context_history(previous), message)) == D.context_node(D.context_history(previous), message) : D.History}:
  match message:
    case D.ContextCheckpoint{summary}: {==}
    case D.ReasoningRecord{+owner, +effort, +remaining, +sampling}:
      %evidence : {D.HistoryNode{D.context_history(D.context_history(previous)), D.ReasoningRecord{owner, effort, remaining, sampling}} ==
        D.HistoryNode{_, D.ReasoningRecord{owner, effort, remaining, sampling}} : D.History}
      {==}
    case D.ConfigurationUpdate{+effort}:
      %evidence : {D.HistoryNode{D.context_history(D.context_history(previous)), D.ConfigurationUpdate{effort}} ==
        D.HistoryNode{_, D.ConfigurationUpdate{effort}} : D.History}
      {==}
    case D.ToolReceipt{owner, operation, call, value, error}: evidence
    case D.AfterRecord{owner, operation, plugin, outcome}: evidence
    case D.ApprovalRecord{owner, operation, call, reviewer, outcome}: evidence
    case D.ForkResult{+owner, +id, +branch}:
      %evidence : {D.HistoryNode{D.context_history(D.context_history(previous)), D.ForkResult{owner, id, branch}} == D.HistoryNode{_, D.ForkResult{owner, id, branch}} : D.History}
      {==}
    case D.HookRecord{+owner, +id, +reference, +outcome}:
      %evidence : {D.HistoryNode{D.context_history(D.context_history(previous)), D.HookRecord{owner, id, reference, outcome}} == D.HistoryNode{_, D.HookRecord{owner, id, reference, outcome}} : D.History}
      {==}
    case D.UserMessage{+text}:
      %evidence : {D.HistoryNode{D.context_history(D.context_history(previous)), D.UserMessage{text}} == D.HistoryNode{_, D.UserMessage{text}} : D.History}
      {==}
    case D.AssistantMessage{+text}:
      %evidence : {D.HistoryNode{D.context_history(D.context_history(previous)), D.AssistantMessage{text}} == D.HistoryNode{_, D.AssistantMessage{text}} : D.History}
      {==}
    case D.FailureMessage{+text}:
      %evidence : {D.HistoryNode{D.context_history(D.context_history(previous)), D.FailureMessage{text}} == D.HistoryNode{_, D.FailureMessage{text}} : D.History}
      {==}
    case D.FunctionCall{+call}:
      %evidence : {D.HistoryNode{D.context_history(D.context_history(previous)), D.FunctionCall{call}} == D.HistoryNode{_, D.FunctionCall{call}} : D.History}
      {==}
    case D.FunctionOutput{+id, +value, +error}:
      %evidence : {D.HistoryNode{D.context_history(D.context_history(previous)), D.FunctionOutput{id, value, error}} == D.HistoryNode{_, D.FunctionOutput{id, value, error}} : D.History}
      {==}
    case D.OperationResult{+ticket, +id, +tool, +value, +error}:
      %evidence : {D.HistoryNode{D.context_history(D.context_history(previous)), D.OperationResult{ticket, id, tool, value, error}} == D.HistoryNode{_, D.OperationResult{ticket, id, tool, value, error}} : D.History}
      {==}
    case D.ModelContext{+value}:
      project_provider_idempotent(D.is_provider_checkpoint(value), previous, value, {==}, evidence)

def Laws.context_projection_idempotent(history):
  match history:
    case D.EmptyHistory{}: {==}
    case D.HistoryNode{+previous, message}:
      project_node_idempotent(previous, message, Laws.context_projection_idempotent(previous))

def Laws.checkpoint_cuts_context(history, summary):
  {==}

def Laws.provider_checkpoint_context(history, value, checked):
  %checked : {D.provider_context_node(D.is_provider_checkpoint(value), D.context_history(history), value) ==
    D.provider_context_node(_, D.context_history(history), value) : D.History}
  {==}

def Laws.provider_checkpoint_consumes_compaction(history, value, checked):
  Equal.trans(Bool,
    D.compactable(D.provider_context_node(D.is_provider_checkpoint(value), D.context_history(history), value)),
    Bool.not(D.is_provider_checkpoint(value)), False{},
    Equal.cong(Bool, Bool, (flag => D.compactable(D.provider_context_node(flag, D.context_history(history), value))),
      D.is_provider_checkpoint(value), True{}, checked),
    Equal.cong(Bool, Bool, Bool.not, D.is_provider_checkpoint(value), True{}, checked))

def Laws.provider_summary_preserves_record(value, resume, task, kind, valid):
  %Equal.sym(Bool, D.is_provider_checkpoint(value), True{}, kind) :
    {T.summary_context_result(_, value, resume, task) ==
      T.promote(D.with_phase(T.after_summary(resume), D.append_message(D.ModelContext{value}, task))) : D.Task}
  %Equal.sym(Bool, D.valid_provider_checkpoint(value), True{}, valid) :
    {T.provider_summary_checked(_, value, resume, task) ==
      T.promote(D.with_phase(T.after_summary(resume), D.append_message(D.ModelContext{value}, task))) : D.Task}
  {==}

def Laws.summary_rejects_invocations(call, rest, resume, task):
  {==}

def Laws.summary_failure_promotes_fifo(message, id, lineage, contract, history, first, rest, phase, operations, notified):
  {==}

def Laws.summary_failure_empty_stops(message, id, lineage, contract, status, history, phase, operations, notified):
  match status:
    case D.Active{}: {==}
    case D.Frozen{}: {==}
    case D.Stopped{}: {==}
    case D.Archived{}: {==}
