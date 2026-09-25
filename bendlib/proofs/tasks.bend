import Base
import ../../MODEL.bend as M
import ../../LAWS.bend as Laws
import ../structures.bend as S
import ../architecture.bend as Concepts

# Local proof obligations for the tasks boundary. No runtime policy lives here.

def Laws.context_recovery_work(task, world):
  {==}

def Laws.context_recovery_ready(task):
  match task:
    case M.Task{id, lineage, contract, status, history, queued, phase}: {==}

def Laws.recover_resumable_summary(ticket):
  {==}

def Laws.checkpoint_consumes_compaction(history, summary):
  {==}

def Laws.checkpoint_is_not_recompacted(id, lineage, contract, status, history, summary, queued, phase, world):
  {==}

def Laws.context_limit_after_checkpoint_stops(allowed, id, lineage, contract, status, history, summary, phase):
  match status:
    case M.Active{}: {==}
    case M.Frozen{}: {==}
    case M.Stopped{}: {==}
    case M.Archived{}: {==}

def Laws.summary_context_limit_stops(resume, id, lineage, contract, status, history, phase):
  match status:
    case M.Active{}: {==}
    case M.Frozen{}: {==}
    case M.Stopped{}: {==}
    case M.Archived{}: {==}

def Laws.checkpoint_preserves_project_contract(task, summary):
  match task:
    case M.Task{id, lineage, contract, status, history, queued, phase}: {==}

def Laws.read_file_recovery_safe(attempt):
  match attempt:
    case M.InitialAttempt{call}: {==}
    case M.RecoveryAttempt{call}: {==}

def Laws.write_file_recovery_blocked(call):
  {==}

def Laws.edit_file_recovery_blocked(call):
  {==}

def Laws.archived_terminal(request):
  match request:
    case M.Freeze{}: {==}
    case M.Unfreeze{}: {==}
    case M.Stop{}: {==}
    case M.Interrupt{}: {==}
    case M.Archive{}: {==}

def Laws.archived_input_unchanged(id, lineage, contract, history, queue, phase, text):
  {==}

def Laws.frozen_no_dispatch(phase):
  {==}

def Laws.stopped_no_model(phase):
  match phase:
    case M.Idle{}: {==}
    case M.CompactionReady{}: {==}
    case M.Ready{Nil{}}: {==}
    case M.Ready{Con{call, rest}}: {==}
    case M.ModelPending{ticket, callable}: {==}
    case M.SummaryPending{ticket, resume}: {==}
    case M.ToolPending{ticket, call, remaining}: {==}

def Laws.stopped_input_reactivates():
  {==}

def Laws.interrupt_preserves_contract(task):
  match task:
    case M.Task{id, lineage, contract, status, history, queue, phase}: {==}

def Laws.interrupt_preserves_queue(task):
  match task:
    case M.Task{id, lineage, contract, status, history, queue, phase}: {==}

def Laws.interrupt_settles_phase(task):
  match task:
    case M.Task{id, lineage, contract, status, history, queue, phase}: {==}

def Laws.interrupt_idempotent(task):
  match task:
    case M.Task{id, lineage, contract, status, history, queue, phase}: {==}

def Laws.status_preserves_contract(status, task):
  match task:
    case M.Task{id, lineage, contract, old, history, queued, phase}: {==}

def Laws.phase_preserves_contract(phase, task):
  match task:
    case M.Task{id, lineage, contract, status, history, queued, old}: {==}

def Laws.queue_order(first, second, task):
  match task:
    case M.Task{id, lineage, contract, status, history, +queued, phase}:
      S.monoid_associative(+List<String>, Nil{}, S.append(String), Concepts.inbox(), queued, [first], [second])

def Laws.child_contract(id, parent, call, branch, remaining, message):
  match parent:
    case M.Task{parent_id, lineage, contract, status, history, queued, phase}: {==}

def Laws.child_history_prefix(id, parent, call, branch, remaining):
  match parent:
    case M.Task{parent_id, lineage, contract, status, history, queued, phase}: {==}

def Laws.child_lineage(id, parent, call, branch, remaining, message):
  match parent:
    case M.Task{parent_id, lineage, contract, status, history, queued, phase}: {==}

def Laws.child_queue_empty(id, parent, call, branch, remaining, message):
  match parent:
    case M.Task{parent_id, lineage, contract, status, history, queued, phase}: {==}

def Laws.unknown_effect_not_repeated(call):
  {==}

def Laws.internal_effect_retry_safe(attempt):
  {==}

def Laws.recover_phase_idempotent(phase):
  match phase:
    case M.Idle{}: {==}
    case M.CompactionReady{}: {==}
    case M.Ready{calls}: {==}
    case M.ModelPending{ticket, callable}: {==}
    case M.SummaryPending{ticket, True{}}: {==}
    case M.SummaryPending{ticket, False{}}: {==}
    case M.ToolPending{ticket, call, remaining}: {==}

def Laws.unmatched_model_result_unchanged(outcome, allowed, task, world):
  {==}

def Laws.unmatched_tool_result_unchanged(call, remaining, value, error, task, world):
  {==}

def Laws.context_has_no_call_authority(value):
  {==}

def project_node_idempotent(+previous: M.History, +message: M.Message,
  evidence: {M.context_history(M.context_history(previous)) == M.context_history(previous) : M.History}) ->
  {M.context_history(M.context_node(M.context_history(previous), message)) == M.context_node(M.context_history(previous), message) : M.History}:
  match message:
    case M.ContextCheckpoint{summary}: {==}
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
    case M.ModelContext{+value}:
      %evidence : {M.HistoryNode{M.context_history(M.context_history(previous)), M.ModelContext{value}} == M.HistoryNode{_, M.ModelContext{value}} : M.History}
      {==}

def Laws.context_projection_idempotent(history):
  match history:
    case M.EmptyHistory{}: {==}
    case M.HistoryNode{+previous, message}:
      project_node_idempotent(previous, message, Laws.context_projection_idempotent(previous))

def Laws.checkpoint_cuts_context(history, summary):
  {==}

def Laws.summary_rejects_invocations(call, rest, resume, task):
  {==}

def Laws.summary_failure_promotes_fifo(message, id, lineage, contract, history, first, rest, phase):
  {==}

def Laws.summary_failure_empty_stops(message, id, lineage, contract, status, history, phase):
  match status:
    case M.Active{}: {==}
    case M.Frozen{}: {==}
    case M.Stopped{}: {==}
    case M.Archived{}: {==}
