import Base
import ../../MODEL.bend as M
import ../../LAWS.bend as Laws
import ../theory.bend as Theory
import ../architecture.bend as Concepts
import ../json.bend as J
import ../tasks.bend as T

# Local proof obligations for the tasks boundary. No runtime policy lives here.

def Laws.context_recovery_work(task, world):
  {==}

def Laws.context_recovery_ready(task):
  match task:
    case M.Task{id, lineage, contract, status, history, queued, phase, operations, notified}: {==}

def Laws.recover_resumable_summary(ticket):
  {==}

def Laws.checkpoint_consumes_compaction(history, summary):
  {==}

def Laws.checkpoint_is_not_recompacted(id, lineage, contract, status, history, summary, queued, phase, world, operations, notified):
  {==}

def Laws.context_limit_after_checkpoint_stops(allowed, id, lineage, contract, status, history, summary, phase, operations, notified):
  match status:
    case M.Active{}: {==}
    case M.Frozen{}: {==}
    case M.Stopped{}: {==}
    case M.Archived{}: {==}

def Laws.summary_context_limit_stops(resume, id, lineage, contract, status, history, phase, operations, notified):
  match status:
    case M.Active{}: {==}
    case M.Frozen{}: {==}
    case M.Stopped{}: {==}
    case M.Archived{}: {==}

def Laws.checkpoint_preserves_project_contract(task, summary):
  match task:
    case M.Task{id, lineage, contract, status, history, queued, phase, operations, notified}: {==}

def Laws.bash_recovery_blocked(call):
  {==}

def Laws.mcp_recovery_blocked(server, name, call):
  {==}

def Laws.archived_terminal(request):
  match request:
    case M.Freeze{}: {==}
    case M.Unfreeze{}: {==}
    case M.Stop{}: {==}
    case M.Interrupt{}: {==}
    case M.Archive{}: {==}

def Laws.archived_input_unchanged(id, lineage, contract, history, queue, phase, text, operations, notified):
  {==}

def Laws.frozen_no_dispatch(phase):
  {==}

def Laws.stopped_no_model(phase):
  match phase:
    case M.HookPending{ticket, reference, call, pending, remaining}: {==}
    case M.Idle{}: {==}
    case M.CompactionReady{}: {==}
    case M.Ready{Nil{}}: {==}
    case M.Ready{Con{call, rest}}: {==}
    case M.ModelPending{ticket, callable}: {==}
    case M.SummaryPending{ticket, resume}: {==}

def Laws.stopped_input_reactivates():
  {==}

def Laws.interrupt_preserves_contract(task):
  match task:
    case M.Task{id, lineage, contract, status, history, queue, phase, operations, notified}: {==}

def Laws.interrupt_preserves_queue(task):
  match task:
    case M.Task{id, lineage, contract, status, history, queue, phase, operations, notified}: {==}

def Laws.interrupt_settles_phase(task):
  match task:
    case M.Task{id, lineage, contract, status, history, queue, phase, operations, notified}: {==}

def Laws.interrupt_idempotent(task):
  match task:
    case M.Task{id, lineage, contract, status, history, queue, phase, operations, notified}: {==}

def Laws.status_preserves_contract(status, task):
  match task:
    case M.Task{id, lineage, contract, old, history, queued, phase, operations, notified}: {==}

def Laws.phase_preserves_contract(phase, task):
  match task:
    case M.Task{id, lineage, contract, status, history, queued, old, operations, notified}: {==}

def Laws.queue_order(first, second, task):
  match task:
    case M.Task{id, lineage, contract, status, history, +queued, phase, operations, notified}:
      Theory.append_associative(String, queued, [first], [second])

def Laws.child_contract(id, parent, call, branch, remaining, message):
  match parent:
    case M.Task{parent_id, lineage, contract, status, history, queued, phase, operations, notified}: {==}

def Laws.child_history_prefix(id, parent, call, branch, remaining):
  match parent:
    case M.Task{parent_id, lineage, contract, status, history, queued, phase, operations, notified}: {==}

def Laws.child_lineage(id, parent, call, branch, remaining, message):
  match parent:
    case M.Task{parent_id, lineage, contract, status, history, queued, phase, operations, notified}: {==}

def Laws.child_queue_empty(id, parent, call, branch, remaining, message):
  match parent:
    case M.Task{parent_id, lineage, contract, status, history, queued, phase, operations, notified}: {==}

def Laws.unknown_effect_not_repeated(call):
  {==}

def Laws.internal_effect_retry_safe(attempt):
  {==}

def Laws.recover_phase_idempotent(phase):
  match phase:
    case M.HookPending{ticket, reference, call, pending, remaining}: {==}
    case M.Idle{}: {==}
    case M.CompactionReady{}: {==}
    case M.Ready{calls}: {==}
    case M.ModelPending{ticket, callable}: {==}
    case M.SummaryPending{ticket, True{}}: {==}
    case M.SummaryPending{ticket, False{}}: {==}

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
    case M.EmptyHistory{}: {==}
    case M.HistoryNode{+previous, M.UserMessage{+text}}:
      %Laws.retained_users_projected(previous) :
        {M.HistoryNode{M.context_history(M.retained_users(previous)), M.UserMessage{text}} == M.HistoryNode{_, M.UserMessage{text}} : M.History}
      {==}
    case M.HistoryNode{previous, M.AssistantMessage{text}}: Laws.retained_users_projected(previous)
    case M.HistoryNode{previous, M.FunctionCall{call}}: Laws.retained_users_projected(previous)
    case M.HistoryNode{previous, M.FunctionOutput{id, value, error}}: Laws.retained_users_projected(previous)
    case M.HistoryNode{previous, M.OperationResult{ticket, id, tool, value, error}}: Laws.retained_users_projected(previous)
    case M.HistoryNode{previous, M.FailureMessage{text}}: Laws.retained_users_projected(previous)
    case M.HistoryNode{previous, M.ModelContext{value}}: Laws.retained_users_projected(previous)
    case M.HistoryNode{previous, M.ContextCheckpoint{summary}}: Laws.retained_users_projected(previous)
    case M.HistoryNode{previous, M.HookRecord{task, id, plugin, outcome}}: Laws.retained_users_projected(previous)
    case M.HistoryNode{previous, M.ToolReceipt{task, operation, call, value, error}}: Laws.retained_users_projected(previous)
    case M.HistoryNode{previous, M.AfterRecord{task, operation, plugin, outcome}}: Laws.retained_users_projected(previous)
    case M.HistoryNode{previous, M.ForkResult{task, id, branch}}: Laws.retained_users_projected(previous)

def Laws.retained_users_idempotent(history):
  match history:
    case M.EmptyHistory{}: {==}
    case M.HistoryNode{+previous, M.UserMessage{+text}}:
      %Laws.retained_users_idempotent(previous) :
        {M.HistoryNode{M.retained_users(M.retained_users(previous)), M.UserMessage{text}} == M.HistoryNode{_, M.UserMessage{text}} : M.History}
      {==}
    case M.HistoryNode{previous, M.AssistantMessage{text}}: Laws.retained_users_idempotent(previous)
    case M.HistoryNode{previous, M.FunctionCall{call}}: Laws.retained_users_idempotent(previous)
    case M.HistoryNode{previous, M.FunctionOutput{id, value, error}}: Laws.retained_users_idempotent(previous)
    case M.HistoryNode{previous, M.OperationResult{ticket, id, tool, value, error}}: Laws.retained_users_idempotent(previous)
    case M.HistoryNode{previous, M.FailureMessage{text}}: Laws.retained_users_idempotent(previous)
    case M.HistoryNode{previous, M.ModelContext{value}}: Laws.retained_users_idempotent(previous)
    case M.HistoryNode{previous, M.ContextCheckpoint{summary}}: Laws.retained_users_idempotent(previous)
    case M.HistoryNode{previous, M.HookRecord{task, id, plugin, outcome}}: Laws.retained_users_idempotent(previous)
    case M.HistoryNode{previous, M.ToolReceipt{task, operation, call, value, error}}: Laws.retained_users_idempotent(previous)
    case M.HistoryNode{previous, M.AfterRecord{task, operation, plugin, outcome}}: Laws.retained_users_idempotent(previous)
    case M.HistoryNode{previous, M.ForkResult{task, id, branch}}: Laws.retained_users_idempotent(previous)

def retained_cut_fixed(+history: M.History) ->
  {M.retained_users(M.context_history(M.retained_users(history))) == M.retained_users(history) : M.History}:
  Equal.trans(M.History, M.retained_users(M.context_history(M.retained_users(history))),
    M.retained_users(M.retained_users(history)), M.retained_users(history),
    Equal.cong(M.History, M.History, M.retained_users, M.context_history(M.retained_users(history)),
      M.retained_users(history), Laws.retained_users_projected(history)),
    Laws.retained_users_idempotent(history))

def project_provider_idempotent(+checkpoint: Bool, +previous: M.History, +value: J.Json,
  checked: {M.is_provider_checkpoint(value) == checkpoint : Bool},
  evidence: {M.context_history(M.context_history(previous)) == M.context_history(previous) : M.History}) ->
  {M.context_history(M.provider_context_node(checkpoint, M.context_history(previous), value)) ==
    M.provider_context_node(checkpoint, M.context_history(previous), value) : M.History}:
  match checkpoint:
    case False{}:
      Equal.trans(M.History,
        M.provider_context_node(M.is_provider_checkpoint(value), M.context_history(M.context_history(previous)), value),
        M.HistoryNode{M.context_history(M.context_history(previous)), M.ModelContext{value}},
        M.HistoryNode{M.context_history(previous), M.ModelContext{value}},
        Equal.cong(Bool, M.History, (flag => M.provider_context_node(flag, M.context_history(M.context_history(previous)), value)),
          M.is_provider_checkpoint(value), False{}, checked),
        Equal.cong(M.History, M.History, (history => M.HistoryNode{history, M.ModelContext{value}}),
          M.context_history(M.context_history(previous)), M.context_history(previous), evidence))
    case True{}:
      Equal.trans(M.History,
        M.provider_context_node(M.is_provider_checkpoint(value), M.context_history(M.retained_users(M.context_history(previous))), value),
        M.HistoryNode{M.retained_users(M.context_history(M.retained_users(M.context_history(previous)))), M.ModelContext{value}},
        M.HistoryNode{M.retained_users(M.context_history(previous)), M.ModelContext{value}},
        Equal.cong(Bool, M.History, (flag => M.provider_context_node(flag, M.context_history(M.retained_users(M.context_history(previous))), value)),
          M.is_provider_checkpoint(value), True{}, checked),
        Equal.cong(M.History, M.History, (history => M.HistoryNode{history, M.ModelContext{value}}),
          M.retained_users(M.context_history(M.retained_users(M.context_history(previous)))),
          M.retained_users(M.context_history(previous)), retained_cut_fixed(M.context_history(previous))))

def project_node_idempotent(+previous: M.History, +message: M.Message,
  evidence: {M.context_history(M.context_history(previous)) == M.context_history(previous) : M.History}) ->
  {M.context_history(M.context_node(M.context_history(previous), message)) == M.context_node(M.context_history(previous), message) : M.History}:
  match message:
    case M.ContextCheckpoint{summary}: {==}
    case M.ToolReceipt{owner, operation, call, value, error}: evidence
    case M.AfterRecord{owner, operation, plugin, outcome}: evidence
    case M.ForkResult{+owner, +id, +branch}:
      %evidence : {M.HistoryNode{M.context_history(M.context_history(previous)), M.ForkResult{owner, id, branch}} == M.HistoryNode{_, M.ForkResult{owner, id, branch}} : M.History}
      {==}
    case M.HookRecord{+owner, +id, +reference, +outcome}:
      %evidence : {M.HistoryNode{M.context_history(M.context_history(previous)), M.HookRecord{owner, id, reference, outcome}} == M.HistoryNode{_, M.HookRecord{owner, id, reference, outcome}} : M.History}
      {==}
    case M.UserMessage{+text}:
      %evidence : {M.HistoryNode{M.context_history(M.context_history(previous)), M.UserMessage{text}} == M.HistoryNode{_, M.UserMessage{text}} : M.History}
      {==}
    case M.AssistantMessage{+text}:
      %evidence : {M.HistoryNode{M.context_history(M.context_history(previous)), M.AssistantMessage{text}} == M.HistoryNode{_, M.AssistantMessage{text}} : M.History}
      {==}
    case M.FailureMessage{+text}:
      %evidence : {M.HistoryNode{M.context_history(M.context_history(previous)), M.FailureMessage{text}} == M.HistoryNode{_, M.FailureMessage{text}} : M.History}
      {==}
    case M.FunctionCall{+call}:
      %evidence : {M.HistoryNode{M.context_history(M.context_history(previous)), M.FunctionCall{call}} == M.HistoryNode{_, M.FunctionCall{call}} : M.History}
      {==}
    case M.FunctionOutput{+id, +value, +error}:
      %evidence : {M.HistoryNode{M.context_history(M.context_history(previous)), M.FunctionOutput{id, value, error}} == M.HistoryNode{_, M.FunctionOutput{id, value, error}} : M.History}
      {==}
    case M.OperationResult{+ticket, +id, +tool, +value, +error}:
      %evidence : {M.HistoryNode{M.context_history(M.context_history(previous)), M.OperationResult{ticket, id, tool, value, error}} == M.HistoryNode{_, M.OperationResult{ticket, id, tool, value, error}} : M.History}
      {==}
    case M.ModelContext{+value}:
      project_provider_idempotent(M.is_provider_checkpoint(value), previous, value, {==}, evidence)

def Laws.context_projection_idempotent(history):
  match history:
    case M.EmptyHistory{}: {==}
    case M.HistoryNode{+previous, message}:
      project_node_idempotent(previous, message, Laws.context_projection_idempotent(previous))

def Laws.checkpoint_cuts_context(history, summary):
  {==}

def Laws.provider_checkpoint_context(history, value, checked):
  %checked : {M.provider_context_node(M.is_provider_checkpoint(value), M.context_history(history), value) ==
    M.provider_context_node(_, M.context_history(history), value) : M.History}
  {==}

def Laws.provider_checkpoint_consumes_compaction(history, value, checked):
  Equal.trans(Bool,
    M.compactable(M.provider_context_node(M.is_provider_checkpoint(value), M.context_history(history), value)),
    Bool.not(M.is_provider_checkpoint(value)), False{},
    Equal.cong(Bool, Bool, (flag => M.compactable(M.provider_context_node(flag, M.context_history(history), value))),
      M.is_provider_checkpoint(value), True{}, checked),
    Equal.cong(Bool, Bool, Bool.not, M.is_provider_checkpoint(value), True{}, checked))

def Laws.provider_summary_preserves_record(value, resume, task, kind, valid):
  %Equal.sym(Bool, M.is_provider_checkpoint(value), True{}, kind) :
    {T.summary_context_result(_, value, resume, task) ==
      T.promote(M.with_phase(T.after_summary(resume), M.append_message(M.ModelContext{value}, task))) : M.Task}
  %Equal.sym(Bool, M.valid_provider_checkpoint(value), True{}, valid) :
    {T.provider_summary_checked(_, value, resume, task) ==
      T.promote(M.with_phase(T.after_summary(resume), M.append_message(M.ModelContext{value}, task))) : M.Task}
  {==}

def Laws.summary_rejects_invocations(call, rest, resume, task):
  {==}

def Laws.summary_failure_promotes_fifo(message, id, lineage, contract, history, first, rest, phase, operations, notified):
  {==}

def Laws.summary_failure_empty_stops(message, id, lineage, contract, status, history, phase, operations, notified):
  match status:
    case M.Active{}: {==}
    case M.Frozen{}: {==}
    case M.Stopped{}: {==}
    case M.Archived{}: {==}
