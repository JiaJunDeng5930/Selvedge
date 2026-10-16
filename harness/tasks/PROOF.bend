import Base
import ../../bendlib/categories.bend as Categories
import ../../bendlib/component.bend as C
import ../DOMAIN.bend as D
import ../workspace/WORKSPACE.bend as Workspace
import ../../bendlib/equality.bend as Same
import ./PROGRAM.bend as Tasks
import ./CONTRACT.bend as Spec
import ../LAWS.bend as Laws
import ../../bendlib/theory.bend as Theory
import ../CONTRACT.bend as Concepts
import ../../bendlib/json.bend as J

def output_text_meaning(nonempty: Bool, +text: String, +rest: +List<String>) ->
  {Tasks.output_text(nonempty, text, rest) == Spec.output_text(nonempty, text, rest) : +List<String>}:
  match nonempty:
    case True{}: {==}
    case False{}: {==}

def output_items_meaning(+items: +List<D.ModelItem>) ->
  {Tasks.output_items(items) == Spec.assistant_outputs(Tasks.item_messages(items)) : +List<String>}:
  match items:
    case Nil{}: {==}
    case Con{D.Say{+text}, +rest}:
      Equal.trans(+List<String>,
        Tasks.output_text(Bool.not(String.is_empty(text)), text, Tasks.output_items(rest)),
        Tasks.output_text(Bool.not(String.is_empty(text)), text, Spec.assistant_outputs(Tasks.item_messages(rest))),
        Spec.output_text(Bool.not(String.is_empty(text)), text, Spec.assistant_outputs(Tasks.item_messages(rest))),
        Equal.cong(+List<String>, +List<String>, values => Tasks.output_text(Bool.not(String.is_empty(text)), text, values),
          Tasks.output_items(rest), Spec.assistant_outputs(Tasks.item_messages(rest)), output_items_meaning(rest)),
        output_text_meaning(Bool.not(String.is_empty(text)), text, Spec.assistant_outputs(Tasks.item_messages(rest))))
    case Con{D.Invoke{call}, +rest}: output_items_meaning(rest)
    case Con{D.Context{value}, +rest}: output_items_meaning(rest)

def normal_outputs_meaning(calls: +List<D.Call>, +items: +List<D.ModelItem>) ->
  {Tasks.normal_output_items(calls, items) == Spec.normal_output_messages(calls, Tasks.item_messages(items)) : +List<String>}:
  match calls:
    case Nil{}: output_items_meaning(items)
    case Con{call, rest}: {==}

def reply_outputs_meaning(+outcome: D.Outcome) ->
  {Tasks.reply_outputs(outcome) == Spec.reply_outputs(outcome) : +List<String>}:
  match outcome:
    case D.ModelReply{+items}:
      normal_outputs_meaning(Tasks.item_calls(items), items)
    case D.ModelFailure{message}: {==}
    case D.ContextLimit{}: {==}

def update_meaning(-R: Data, +task: D.Task, +state: D.State, +rest: R) ->
  {Tasks.update_world(R, task, C.Frame{state, rest}) == C.Frame{Spec.required_update(task, state), rest} : C.Frame<D.State, R>}:
  {==}

def update_frame(-StateRest: Data, task: D.Task, world: C.Frame<D.State, StateRest>) ->
  {C.rest(D.State, StateRest, Tasks.update_world(StateRest, task, world)) == C.rest(D.State, StateRest, world) : StateRest}:
  match world:
    case C.Frame{state, rest}: C.map_frame(D.State, StateRest, value => Tasks.update_state(task, value), state, rest)

# Local proof obligations for the tasks boundary. No runtime policy lives here.

def Laws.context_limit_stops(task):
  {==}

def Laws.summary_recovery_idle(ticket, resume):
  {==}

def Laws.checkpoint_is_not_recompacted(current, id, lineage, contract, status, history, summary, queued, phase, world, operations, notified):
  {==}

def Laws.context_limit_after_checkpoint_stops(current, allowed, id, lineage, contract, status, history, summary, phase, operations, notified):
  match status:
    case D.Active{}: {==}
    case D.Frozen{}: {==}
    case D.Stopped{}: {==}
    case D.Archived{}: {==}

def Laws.summary_context_limit_stops(current, resume, id, lineage, contract, status, history, phase, operations, notified):
  match status:
    case D.Active{}: {==}
    case D.Frozen{}: {==}
    case D.Stopped{}: {==}
    case D.Archived{}: {==}

def Laws.checkpoint_preserves_project_contract(task, summary):
  match task:
    case D.Task{id, lineage, contract, current, status, history, queued, phase, operations, notified}: {==}

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

def Laws.archived_input_unchanged(current, id, lineage, contract, history, queue, phase, text, operations, notified):
  {==}

def Laws.frozen_no_dispatch(phase):
  {==}

def Laws.stopped_no_model(phase):
  match phase:
    case D.HookPending{ticket, reference, call, pending, remaining}: {==}
    case D.Idle{}: {==}
    case D.Ready{Nil{}}: {==}
    case D.Ready{Con{call, rest}}: {==}
    case D.ModelPending{ticket, callable}: {==}
    case D.ReasoningPending{ticket, revision}: {==}
    case D.SummaryPending{ticket, resume}: {==}

def Laws.stopped_input_reactivates():
  {==}

def Laws.interrupt_preserves_contract(task):
  match task:
    case D.Task{id, lineage, contract, current, status, history, queue, phase, operations, notified}: {==}

def Laws.interrupt_preserves_queue(task):
  match task:
    case D.Task{id, lineage, contract, current, status, history, queue, phase, operations, notified}: {==}

def Laws.interrupt_settles_phase(task):
  match task:
    case D.Task{id, lineage, contract, current, status, history, queue, phase, operations, notified}: {==}

def Laws.interrupt_idempotent(task):
  match task:
    case D.Task{id, lineage, contract, current, status, history, queue, phase, operations, notified}: {==}

def Laws.status_preserves_contract(status, task):
  match task:
    case D.Task{id, lineage, contract, current, old, history, queued, phase, operations, notified}: {==}

def Laws.phase_preserves_contract(phase, task):
  match task:
    case D.Task{id, lineage, contract, current, status, history, queued, old, operations, notified}: {==}

def Laws.queue_order(first, second, task):
  match task:
    case D.Task{id, lineage, contract, current, status, history, +queued, phase, operations, notified}:
      Theory.append_associative(String, queued, [first], [second])

def Laws.child_contract(id, parent, call, branch, remaining, message):
  match parent:
    case D.Task{parent_id, lineage, contract, current, status, history, queued, phase, operations, notified}: {==}

def Laws.child_execution(id, parent, call, branch, remaining, message):
  {==}

def Laws.child_history_prefix(id, parent, call, branch, remaining):
  match parent:
    case D.Task{parent_id, lineage, contract, current, status, history, queued, phase, operations, notified}: {==}

def Laws.child_lineage(id, parent, call, branch, remaining, message):
  match parent:
    case D.Task{parent_id, lineage, contract, current, status, history, queued, phase, operations, notified}: {==}

def Laws.child_queue_empty(id, parent, call, branch, remaining, message):
  match parent:
    case D.Task{parent_id, lineage, contract, current, status, history, queued, phase, operations, notified}: {==}

def Laws.unknown_effect_not_repeated(call):
  {==}

def Laws.internal_effect_retry_safe(attempt):
  {==}

def Laws.recover_phase_idempotent(phase):
  match phase:
    case D.HookPending{ticket, reference, call, pending, remaining}: {==}
    case D.Idle{}: {==}
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

def Laws.context_projection_idempotent(history):
  {==}

def Laws.full_history_source(history):
  {==}

def Laws.checkpoint_preserves_context(history, summary):
  {==}

def Laws.provider_checkpoint_context(history, value, checked):
  {==}

def provider_summary_result(accepted: Bool, value: J.Json, resume: Bool, task: D.Task) -> D.Task:
  match accepted:
    case True{}: Tasks.provider_summary_calculation(value, resume, task)
    case False{}: Tasks.summary_failure("Compaction failed: expected one nonempty bounded provider checkpoint; original history retained", task)

def provider_summary_checked_meaning(+accepted: Bool, +value: J.Json, +resume: Bool, +task: D.Task,
  checked: {Tasks.provider_checkpoint_permitted(value) == accepted : Bool}) ->
  {Tasks.provider_summary_admission(Categories.admit_checked(J.Json, Tasks.provider_checkpoint_permitted, value, accepted, checked), resume, task) ==
    provider_summary_result(accepted, value, resume, task) : D.Task}:
  match accepted:
    case True{}: {==}
    case False{}: {==}

def Laws.provider_summary_preserves_record(value, resume, task, kind, valid):
  %Equal.sym(Bool, D.is_provider_checkpoint(value), True{}, kind) :
    {Tasks.summary_context_result(_, value, resume, task) ==
      Tasks.promote(D.with_phase(Tasks.after_summary(resume), D.append_message(D.ModelContext{value}, task))) : D.Task}
  Equal.trans(D.Task,
    Tasks.provider_summary_admission(Categories.admit(J.Json, Tasks.provider_checkpoint_permitted, value), resume, task),
    provider_summary_result(D.valid_provider_checkpoint(value), value, resume, task),
    Tasks.provider_summary_calculation(value, resume, task),
    provider_summary_checked_meaning(D.valid_provider_checkpoint(value), value, resume, task, {==}),
    Equal.cong(Bool, D.Task, accepted => provider_summary_result(accepted, value, resume, task),
      D.valid_provider_checkpoint(value), True{}, valid))

def Laws.summary_rejects_invocations(call, rest, resume, task):
  {==}

def Laws.summary_failure_promotes_fifo(current, message, id, lineage, contract, history, first, rest, phase, operations, notified):
  {==}

def Laws.summary_failure_empty_stops(current, message, id, lineage, contract, status, history, phase, operations, notified):
  match status:
    case D.Active{}: {==}
    case D.Frozen{}: {==}
    case D.Stopped{}: {==}
    case D.Archived{}: {==}

def Laws.execution_configuration_status(configuration, task):
  match task:
    case D.Task{id, lineage, contract, current, status, history, queued, phase, operations, notified}: {==}

def Laws.execution_configuration_creation(configuration, task):
  match task:
    case D.Task{id, lineage, contract, current, status, history, queued, phase, operations, notified}: {==}

def Laws.execution_configuration_current(configuration, task):
  match task:
    case D.Task{id, lineage, contract, current, status, history, queued, phase, operations, notified}: {==}

def Laws.queued_execution_configuration_rejected(id, lineage, contract, current, status, history, first, rest, phase, operations, notified):
  {==}

def Laws.initial_history_order(instructions, project, message, id, lineage, profile, reasoning, tools, max_fork, max_descendants, plugins, context, current, status, history, queued, phase, operations, notified):
  match instructions project:
    case D.InitialInstructions{configured, None{}} D.NoProject{}: {==}
    case D.InitialInstructions{configured, None{}} D.ProjectContext{root, revision, content}: {==}
    case D.InitialInstructions{configured, Some{D.InstructionSnapshot{path, revision, content}}} D.NoProject{}: {==}
    case D.InitialInstructions{configured, Some{D.InstructionSnapshot{path, revision, content}}} D.ProjectContext{root, project_revision, project_content}: {==}

def Laws.context_append_preserves_prefix(context, task):
  match task:
    case D.Task{id, lineage, contract, current, status, history, queued, phase, operations, notified}: {==}

def Laws.recorded_selection_history(changed, selection, parent):
  match changed selection parent:
    case False{} Workspace.Selection{context, guidance} D.Task{id, lineage, contract, current, status, history, queued, phase, operations, notified}: {==}
    case True{} Workspace.Selection{context, guidance} D.Task{id, lineage, contract, D.ExecutionConfiguration{current_profile, current_reasoning, D.Model{profile, reasoning}, sandbox, approval}, status, history, queued, phase, operations, notified}: {==}


def Laws.selected_parent_history(context, guidance, parent):
  Laws.recorded_selection_history(Bool.not(Same.project(guidance, D.task_guidance(parent)) && Same.task_context(context, D.task_context(parent))), Workspace.Selection{context, guidance}, parent)

def Laws.root_initial_history(profile, reasoning, message, context, instructions, project, catalog, profiles, forks, descendants, plugins, state, board):
  match instructions project state:
    case D.InitialInstructions{configured, None{}} D.NoProject{} D.State{tasks, next_task, next_ticket, environment, limits, registry}: {==}
    case D.InitialInstructions{configured, None{}} D.ProjectContext{root, revision, content} D.State{tasks, next_task, next_ticket, environment, limits, registry}: {==}
    case D.InitialInstructions{configured, Some{D.InstructionSnapshot{path, revision, content}}} D.NoProject{} D.State{tasks, next_task, next_ticket, environment, limits, registry}: {==}
    case D.InitialInstructions{configured, Some{D.InstructionSnapshot{path, revision, content}}} D.ProjectContext{root, project_revision, project_content} D.State{tasks, next_task, next_ticket, environment, limits, registry}: {==}
