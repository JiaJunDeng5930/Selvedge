import Base
import ./side-proof.bend as SideProof
import ../../bendlib/categories.bend as Categories
import ../../bendlib/component.bend as C
import ../DOMAIN.bend as D
import ../workspace/WORKSPACE.bend as Workspace
import ../../bendlib/equality.bend as Same
import ./PROGRAM.bend as Tasks
import ./CONTRACT.bend as Spec
import ../LAWS.bend as Laws
import ../../bendlib/theory.bend as Theory
import ../../bendlib/stdlib.bend as Std
import ../CONTRACT.bend as Concepts
import ../../bendlib/json.bend as J

def output_text_meaning(nonempty: Bool, +text: String, +rest: +List<String>) ->
  {Tasks.output_text(nonempty, text, rest) == Spec.output_text(nonempty, text, rest) : +List<String>}:
  match nonempty:
    case True{}: {==}
    case False{}: {==}

def output_items_meaning(+items: +List<D.ModelItem>) ->
  {Tasks.output_items(items) == Spec.assistant_outputs(Tasks.item_messages(0n, 0n, D.Plain{}, items)) : +List<String>}:
  match items:
    case Nil{}: {==}
    case Con{D.Say{part, +text}, +rest}:
      Equal.trans(+List<String>,
        Tasks.output_text(Bool.not(String.is_empty(text)), text, Tasks.output_items(rest)),
        Tasks.output_text(Bool.not(String.is_empty(text)), text, Spec.assistant_outputs(Tasks.item_messages(0n, 0n, D.Plain{}, rest))),
        Spec.output_text(Bool.not(String.is_empty(text)), text, Spec.assistant_outputs(Tasks.item_messages(0n, 0n, D.Plain{}, rest))),
        Equal.cong(+List<String>, +List<String>, values => Tasks.output_text(Bool.not(String.is_empty(text)), text, values),
          Tasks.output_items(rest), Spec.assistant_outputs(Tasks.item_messages(0n, 0n, D.Plain{}, rest)), output_items_meaning(rest)),
        output_text_meaning(Bool.not(String.is_empty(text)), text, Spec.assistant_outputs(Tasks.item_messages(0n, 0n, D.Plain{}, rest))))
    case Con{D.Invoke{call}, +rest}: output_items_meaning(rest)
    case Con{D.Context{part, value}, +rest}: output_items_meaning(rest)

def normal_outputs_meaning(calls: +List<D.Call>, +items: +List<D.ModelItem>) ->
  {Tasks.normal_output_items(calls, items) == Spec.normal_output_messages(calls, Tasks.item_messages(0n, 0n, D.Plain{}, items)) : +List<String>}:
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

def permitted_outputs_meaning(+accepted: Bool, +outcome: D.Outcome) ->
  {Tasks.permitted_reply_outputs(accepted, outcome) == Spec.permitted_outputs(accepted, outcome) : +List<String>}:
  match accepted:
    case True{}: reply_outputs_meaning(outcome)
    case False{}: {==}

def accepted_reply_outputs_meaning(+outcome: D.Outcome, +allowed: +List<String>, +task: D.Task) ->
  {Tasks.accepted_reply_outputs(outcome, allowed, task) == Spec.accepted_reply_outputs(outcome, allowed, task) : +List<String>}:
  match outcome:
    case D.ModelReply{+items}:
      permitted_outputs_meaning(Tasks.model_reply_permitted(allowed, task, Tasks.ModelReplyCandidate{items}), D.ModelReply{items})
    case D.ModelFailure{message}: {==}
    case D.ContextLimit{}: {==}

def replacement_entry(same: Bool, +previous: D.Task, +task: D.Task) ->
  {Tasks.replacement(same, previous, task) == Spec.required_entry(same, previous, task) : D.Task}:
  match same:
    case True{}: {==}
    case False{}: {==}

def Replacement(tasks: +List<D.Task>) -> Type:
  @+task:D.Task -> {(task, Tasks.replace(tasks, task)) == Spec.required_fold(task, tasks) : (D.Task & +List<D.Task>)}

def replacement_empty() -> Replacement(Nil{}):
  task => {==}

def replacement_cons(+previous: D.Task, +rest: +List<D.Task>, induction: Replacement(rest)) -> Replacement(previous <> rest):
  +task =>
    +same = Nat.is_eq(D.task_id(previous), D.task_id(task))
    Equal.trans((D.Task & +List<D.Task>),
      (task, Tasks.replacement(same, previous, task) <> Tasks.replace(rest, task)),
      (task, Spec.required_entry(same, previous, task) <> Tasks.replace(rest, task)),
      Spec.required_step(previous, Spec.required_fold(task, rest)),
      Equal.cong(D.Task, (D.Task & +List<D.Task>), head => (task, head <> Tasks.replace(rest, task)),
        Tasks.replacement(same, previous, task), Spec.required_entry(same, previous, task), replacement_entry(same, previous, task)),
      Equal.cong((D.Task & +List<D.Task>), (D.Task & +List<D.Task>), state => Spec.required_step(previous, state),
        (task, Tasks.replace(rest, task)), Spec.required_fold(task, rest), induction(task)))

def replace_meaning(+task: D.Task, +tasks: +List<D.Task>) ->
  {Tasks.replace(tasks, task) == Spec.required_tasks(task, tasks) : +List<D.Task>}:
  Equal.cong((D.Task & +List<D.Task>), +List<D.Task>, Spec.required_entries,
    (task, Tasks.replace(tasks, task)), Spec.required_fold(task, tasks),
    Std.list_ind(~D.Task, ~Replacement, ~replacement_empty(), ~(previous => rest => induction => replacement_cons(previous, rest, induction)), tasks)(task))

def update_meaning(-R: Data, +task: D.Task, +state: D.State, +rest: R) ->
  {Tasks.update_world(R, task, C.Frame{state, rest}) == C.Frame{Spec.required_update(task, state), rest} : C.Frame<D.State, R>}:
  Equal.cong(+List<D.Task>, C.Frame<D.State, R>, tasks => C.Frame{D.with_state_tasks(tasks, state), rest},
    Tasks.replace(D.state_tasks(state), task), Spec.required_tasks(task, D.state_tasks(state)), replace_meaning(task, D.state_tasks(state)))

def update_frame(-StateRest: Data, task: D.Task, world: C.Frame<D.State, StateRest>) ->
  {C.rest(D.State, StateRest, Tasks.update_world(StateRest, task, world)) == C.rest(D.State, StateRest, world) : StateRest}:
  match world:
    case C.Frame{state, rest}: C.map_frame(D.State, StateRest, value => Tasks.update_state(task, value), state, rest)

# Local proof obligations for the tasks boundary. No runtime policy lives here.

def Laws.context_limit_stops(task):
  {==}

def Laws.context_replacement_preserves_project_contract(task, replacement):
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
    case D.ContextPending{ticket, revision, purpose}: {==}
    case D.ModelPending{ticket, callable, mode}: {==}
    case D.ReasoningPending{ticket, revision}: {==}

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
      Theory.append_associative(D.UserContent, queued, [first], [second])

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
    case D.ContextPending{ticket, revision, D.GenerateContext{}}: {==}
    case D.ContextPending{ticket, revision, D.SummaryContext{}}: {==}
    case D.ModelPending{ticket, callable, mode}: {==}
    case D.ReasoningPending{ticket, revision}: {==}

def Laws.unmatched_model_result_unchanged(outcome, allowed, task, world):
  {==}

def Laws.unmatched_tool_result_unchanged(operation, value, error, task, world):
  {==}

def Laws.context_has_no_call_authority(part, value):
  {==}

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
  +context: D.TaskContext, +profile: D.Profile, +reasoning: String, +message: D.UserContent, +history: D.History) ->
  {D.HistoryNode{D.HistoryNode{D.history_initial_context(project, D.history_initial_context(global, D.history_initial_context(configured, history))),
    D.ContextMessage{D.TaskSettings{context, D.profile_key(profile), reasoning}}}, D.UserMessage{message}} ==
   D.HistoryNode{D.HistoryNode{Spec.initial_context(project, Spec.initial_context(global, Spec.initial_context(configured, history))),
    D.ContextMessage{D.TaskSettings{context, D.profile_key(profile), reasoning}}}, D.UserMessage{message}} : D.History}:
  Equal.cong(D.History, D.History,
    (prefix => D.HistoryNode{D.HistoryNode{prefix, D.ContextMessage{D.TaskSettings{context, D.profile_key(profile), reasoning}}}, D.UserMessage{message}}),
    D.history_initial_context(project, D.history_initial_context(global, D.history_initial_context(configured, history))),
    Spec.initial_context(project, Spec.initial_context(global, Spec.initial_context(configured, history))),
    initial_contexts_meaning(configured, global, project, history))

def Laws.initial_history_order(instructions, project, message, id, lineage, profile, reasoning, tools, max_fork, max_descendants, plugins, context, current, status, history, queued, phase, operations, notified):
  match instructions project:
    case D.InitialInstructions{configured, None{}} D.NoProject{}:
      initial_history_meaning(D.configured_context(configured), None{}, None{}, context, profile, reasoning, message, history)
    case D.InitialInstructions{configured, None{}} D.ProjectContext{root, project_path, project_revision, project_content}:
      initial_history_meaning(D.configured_context(configured), None{}, D.project_guidance_context(root, project_path, project_revision, project_content), context, profile, reasoning, message, history)
    case D.InitialInstructions{configured, Some{D.InstructionSnapshot{path, revision, content}}} D.NoProject{}:
      initial_history_meaning(D.configured_context(configured), D.global_context(path, revision, content), None{}, context, profile, reasoning, message, history)
    case D.InitialInstructions{configured, Some{D.InstructionSnapshot{path, revision, content}}} D.ProjectContext{root, project_path, project_revision, project_content}:
      initial_history_meaning(D.configured_context(configured), D.global_context(path, revision, content), D.project_guidance_context(root, project_path, project_revision, project_content), context, profile, reasoning, message, history)

def Laws.context_append_preserves_prefix(context, task):
  match task:
    case D.Task{id, lineage, contract, current, status, history, queued, phase, operations, notified}: {==}

def Laws.recorded_selection_history(changed, selection, parent):
  match changed selection parent:
    case False{} Workspace.Selection{context, guidance} D.Task{id, lineage, contract, current, status, history, queued, phase, operations, notified}: {==}
    case True{} Workspace.Selection{D.TaskContext{workspace, selected_sandbox, selected_approval, project}, guidance} D.Task{id, lineage, D.Contract{created_model, tools, max_fork, max_descendants, plugins, previous_context}, D.ExecutionConfiguration{D.Model{profile, reasoning}, sandbox, approval}, status, history, queued, phase, operations, notified}: {==}


def Laws.selected_parent_history(context, guidance, parent):
  Laws.recorded_selection_history(Bool.not(Same.project(guidance, D.task_guidance(parent)) && Same.task_context(context, D.task_context(parent))), Workspace.Selection{context, guidance}, parent)

def Laws.root_initial_history(profile, reasoning, message, context, instructions, project, catalog, profiles, forks, descendants, plugins, state, board):
  match state:
    case D.State{+tasks, +next_task, next_ticket, environment, limits, registry}:
      Equal.cong(D.History, +List<D.Task>,
        (history => List.append(&2, D.Task, tasks, [D.Task{next_task, Nil{}, D.Contract{D.Model{profile, reasoning}, catalog, forks, descendants, plugins, context},
          D.execution_configuration(D.Contract{D.Model{profile, reasoning}, catalog, forks, descendants, plugins, context}), D.Active{}, history, Nil{}, D.Ready{Nil{}}, Nil{}, True{}}])),
        D.task_history(D.initialize_history(instructions, project, message,
          D.Task{next_task, Nil{}, D.Contract{D.Model{profile, reasoning}, catalog, forks, descendants, plugins, context}, D.execution_configuration(D.Contract{D.Model{profile, reasoning}, catalog, forks, descendants, plugins, context}), D.Active{}, D.EmptyHistory{}, Nil{}, D.Ready{Nil{}}, Nil{}, True{}})),
        Spec.initial_history(instructions, project, context, profile, reasoning, message, D.EmptyHistory{}),
        Laws.initial_history_order(instructions, project, message, next_task, Nil{}, profile, reasoning, catalog, forks, descendants, plugins,
          context, D.execution_configuration(D.Contract{D.Model{profile, reasoning}, catalog, forks, descendants, plugins, context}), D.Active{}, D.EmptyHistory{}, Nil{}, D.Ready{Nil{}}, Nil{}, True{}))
