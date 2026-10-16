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
    case D.Ready{Nil{}}: {==}
    case D.Ready{Con{call, rest}}: {==}
    case D.ContextPending{ticket, revision, purpose}: {==}
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
    case D.Ready{calls}: {==}
    case D.ContextPending{ticket, revision, D.GenerateContext{}}: {==}
    case D.ContextPending{ticket, revision, D.SummaryContext{resume}}: {==}
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

def Laws.summary_failure_promotes_fifo(message, id, lineage, contract, history, first, rest, phase, operations, notified):
  {==}

def Laws.summary_failure_empty_stops(message, id, lineage, contract, status, history, phase, operations, notified):
  match status:
    case D.Active{}: {==}
    case D.Frozen{}: {==}
    case D.Stopped{}: {==}
    case D.Archived{}: {==}


# Initial context admission is shared by every definition; this proof compares
# the production append operation with the independently specified history.
def initial_contexts_meaning(+configured: Maybe<&2, D.HistoryContext>, +global: Maybe<&2, D.HistoryContext>, +project: Maybe<&2, D.HistoryContext>, +history: D.History) ->
  {D.history_initial_context(project, D.history_initial_context(global, D.history_initial_context(configured, history))) ==
    Spec.initial_context(project, Spec.initial_context(global, Spec.initial_context(configured, history))) : D.History}:
  match configured global project:
    case None{} None{} None{}: {==}
    case None{} None{} Some{project}: {==}
    case None{} Some{global} None{}: {==}
    case None{} Some{global} Some{project}: {==}
    case Some{configured} None{} None{}: {==}
    case Some{configured} None{} Some{project}: {==}
    case Some{configured} Some{global} None{}: {==}
    case Some{configured} Some{global} Some{project}: {==}

def initial_history_meaning(+configured: Maybe<&2, D.HistoryContext>, +global: Maybe<&2, D.HistoryContext>, +project: Maybe<&2, D.HistoryContext>,
  +context: D.TaskContext, +profile: D.Profile, +reasoning: String, +message: String, +history: D.History) ->
  {D.HistoryNode{D.HistoryNode{D.history_initial_context(project, D.history_initial_context(global, D.history_initial_context(configured, history))),
    D.ContextMessage{D.TaskSettings{context, D.profile_key(profile), reasoning}}}, D.UserMessage{message}} ==
   D.HistoryNode{D.HistoryNode{Spec.initial_context(project, Spec.initial_context(global, Spec.initial_context(configured, history))),
    D.ContextMessage{D.TaskSettings{context, D.profile_key(profile), reasoning}}}, D.UserMessage{message}} : D.History}:
  Equal.cong(D.History, D.History,
    (prefix => D.HistoryNode{D.HistoryNode{prefix, D.ContextMessage{D.TaskSettings{context, D.profile_key(profile), reasoning}}}, D.UserMessage{message}}),
    D.history_initial_context(project, D.history_initial_context(global, D.history_initial_context(configured, history))),
    Spec.initial_context(project, Spec.initial_context(global, Spec.initial_context(configured, history))),
    initial_contexts_meaning(configured, global, project, history))

def Laws.initial_history_order(instructions, project, message, id, lineage, profile, reasoning, tools, max_fork, max_descendants, plugins, context, status, history, queued, phase, operations, notified):
  match instructions project:
    case D.InitialInstructions{configured, None{}} D.NoProject{}:
      initial_history_meaning(D.configured_context(configured), None{}, None{}, context, profile, reasoning, message, history)
    case D.InitialInstructions{configured, None{}} D.ProjectContext{root, project_revision, project_content}:
      initial_history_meaning(D.configured_context(configured), None{}, D.project_guidance_context(root, project_revision, project_content), context, profile, reasoning, message, history)
    case D.InitialInstructions{configured, Some{D.InstructionSnapshot{path, revision, content}}} D.NoProject{}:
      initial_history_meaning(D.configured_context(configured), D.global_context(path, revision, content), None{}, context, profile, reasoning, message, history)
    case D.InitialInstructions{configured, Some{D.InstructionSnapshot{path, revision, content}}} D.ProjectContext{root, project_revision, project_content}:
      initial_history_meaning(D.configured_context(configured), D.global_context(path, revision, content), D.project_guidance_context(root, project_revision, project_content), context, profile, reasoning, message, history)

def Laws.context_append_preserves_prefix(context, task):
  match task:
    case D.Task{id, lineage, contract, status, history, queued, phase, operations, notified}: {==}

def Laws.recorded_selection_history(changed, selection, parent):
  match changed selection parent:
    case False{} Workspace.Selection{context, guidance} D.Task{id, lineage, D.Contract{D.Model{profile, reasoning}, tools, max_fork, max_descendants, plugins, old_context}, status, history, queued, phase, operations, notified}: {==}
    case True{} Workspace.Selection{context, guidance} D.Task{id, lineage, D.Contract{D.Model{profile, reasoning}, tools, max_fork, max_descendants, plugins, old_context}, status, history, queued, phase, operations, notified}: {==}


def Laws.selected_parent_history(context, guidance, parent):
  Laws.recorded_selection_history(Bool.not(Same.project(guidance, D.task_guidance(parent)) && Same.task_context(context, D.task_context(parent))), Workspace.Selection{context, guidance}, parent)

def Laws.root_initial_history(profile, reasoning, message, context, instructions, project, catalog, profiles, forks, descendants, plugins, state, board):
  match state:
    case D.State{+tasks, +next_task, next_ticket, environment, limits, registry}:
      Equal.cong(D.History, +List<D.Task>,
        (history => List.append(&2, D.Task, tasks, [D.Task{next_task, Nil{}, D.Contract{D.Model{profile, reasoning}, catalog, forks, descendants, plugins, context},
          D.Active{}, history, Nil{}, D.Ready{Nil{}}, Nil{}, True{}}])),
        D.task_history(D.initialize_history(instructions, project, message,
          D.Task{next_task, Nil{}, D.Contract{D.Model{profile, reasoning}, catalog, forks, descendants, plugins, context}, D.Active{}, D.EmptyHistory{}, Nil{}, D.Ready{Nil{}}, Nil{}, True{}})),
        Spec.initial_history(instructions, project, context, profile, reasoning, message, D.EmptyHistory{}),
        Laws.initial_history_order(instructions, project, message, next_task, Nil{}, profile, reasoning, catalog, forks, descendants, plugins,
          context, D.Active{}, D.EmptyHistory{}, Nil{}, D.Ready{Nil{}}, Nil{}, True{}))
