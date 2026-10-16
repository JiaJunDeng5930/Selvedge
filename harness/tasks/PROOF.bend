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

def Laws.context_replacement_preserves_project_contract(task, replacement):
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
    case D.ModelPending{ticket, callable}: {==}
    case D.ReasoningPending{ticket, revision}: {==}

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
    case D.ModelPending{ticket, callable}: {==}
    case D.ReasoningPending{ticket, revision}: {==}

def Laws.unmatched_model_result_unchanged(outcome, allowed, task, world):
  {==}

def Laws.unmatched_tool_result_unchanged(operation, value, error, task, world):
  {==}

def Laws.context_has_no_call_authority(value):
  {==}

def Laws.initial_history_order(instructions, project, message, id, lineage, profile, reasoning, tools, max_fork, max_descendants, plugins, context, status, history, queued, phase, operations, notified):
  match instructions project:
    case D.InitialInstructions{configured, None{}} D.NoProject{}: {==}
    case D.InitialInstructions{configured, None{}} D.ProjectContext{root, revision, content}: {==}
    case D.InitialInstructions{configured, Some{D.InstructionSnapshot{path, revision, content}}} D.NoProject{}: {==}
    case D.InitialInstructions{configured, Some{D.InstructionSnapshot{path, revision, content}}} D.ProjectContext{root, project_revision, project_content}: {==}

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
  match instructions project state:
    case D.InitialInstructions{configured, None{}} D.NoProject{} D.State{tasks, next_task, next_ticket, environment, limits, registry}: {==}
    case D.InitialInstructions{configured, None{}} D.ProjectContext{root, revision, content} D.State{tasks, next_task, next_ticket, environment, limits, registry}: {==}
    case D.InitialInstructions{configured, Some{D.InstructionSnapshot{path, revision, content}}} D.NoProject{} D.State{tasks, next_task, next_ticket, environment, limits, registry}: {==}
    case D.InitialInstructions{configured, Some{D.InstructionSnapshot{path, revision, content}}} D.ProjectContext{root, project_revision, project_content} D.State{tasks, next_task, next_ticket, environment, limits, registry}: {==}
