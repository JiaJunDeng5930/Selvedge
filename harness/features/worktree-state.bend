import Base
import ../../bendlib/json.bend as J
import ../../bendlib/effects.bend as Effects
import ./MODEL.bend as F
import ./operations.bend as O
import ../MODEL.bend as M
import ../DOMAIN.bend as D
import ../tasks/PROGRAM.bend as Tasks
import ../workspace/WORKSPACE.bend as Workspace
import ../../features/worktree/MODEL.bend as W
import ../../bendlib/component.bend as C
import ../../bendlib/association-map.bend as Finite
import ../../bendlib/equality.bend as Same

def registry(world: M.World()) -> W.State:
  F.worktree(C.rest(D.State, F.State(), world))

def store(state: W.State, world: M.World()) -> M.World():
  C.map_rest(D.State, F.State(), features => F.with_worktree(state, features), world)

def selection_primary(selection: Workspace.Selection) -> String:
  Workspace.Selection{context, guidance} = selection
  D.selected_workspace(context)

def task(id: Nat, world: M.World()) -> Maybe<&2, D.Task>:
  Tasks.find(D.state_tasks(C.local(D.State, F.State(), world)), id)

def path_inside(+root: String, +path: String) -> Bool:
  String.eq(path, root) || String.starts_with(path, root ++ "/")

def any_root_inside(roots: +List<String>, +managed: String) -> Bool:
  match roots:
    case Nil{}: False{}
    case Con{root, rest}: path_inside(managed, root) || any_root_inside(rest, managed)

def borrowed_candidate(primary: String, value: W.Worktree) -> Bool:
  match value:
    case W.Worktree{source, Some{root}, status, message, target, backend}: path_inside(root, primary)
    case _: False{}

def choose_effective(selected: Bool, owner: Nat, value: W.Worktree, rest: Maybe<&2, Finite.Entry(W.Worktree)>) -> Maybe<&2, Finite.Entry(W.Worktree)>:
  match selected:
    case False{}: rest
    case True{}: Some{(owner, value)}

def find_effective(entries: +List<Finite.Entry(W.Worktree)>, +primary: String) -> Maybe<&2, Finite.Entry(W.Worktree)>:
  match entries:
    case Nil{}: None{}
    case Con{(owner, +value), rest}: choose_effective(borrowed_candidate(primary, value), owner, value, find_effective(rest, primary))

def frozen_primary(+task: D.Task) -> String:
  D.selected_workspace(D.contract_context(D.task_contract(task)))

def inherited_effective(found: Maybe<&2, D.Task>, entries: +List<Finite.Entry(W.Worktree)>) -> Maybe<&2, Finite.Entry(W.Worktree)>:
  match found:
    case None{}: None{}
    case Some{task}: find_effective(entries, frozen_primary(task))

def effective_found(own: Maybe<&2, W.Worktree>, id: Nat, found: Maybe<&2, D.Task>, entries: +List<Finite.Entry(W.Worktree)>) -> Maybe<&2, Finite.Entry(W.Worktree)>:
  match own:
    case Some{value}: Some{(id, value)}
    case None{}: inherited_effective(found, entries)

def effective(+id: Nat, +world: M.World()) -> Maybe<&2, Finite.Entry(W.Worktree)>:
  effective_found(W.lookup(id, registry(world)), id, task(id, world), W.entries(registry(world)))

def workspace_resource_available(roots: +List<String>, value: W.Worktree) -> Bool:
  match value:
    case W.Worktree{source, Some{root}, W.Ready{}, message, primary, backend}: True{}
    case W.Worktree{source, Some{root}, status, message, primary, backend}: Bool.not(any_root_inside(roots, root))
    case _: True{}

def workspace_entries_available(+roots: +List<String>, entries: +List<Finite.Entry(W.Worktree)>) -> Bool:
  match entries:
    case Nil{}: True{}
    case Con{(owner, value), rest}: workspace_resource_available(roots, value) && workspace_entries_available(roots, rest)

def workspace_available(workspace: D.Workspace, world: M.World()) -> Bool:
  workspace_entries_available(Workspace.roots(workspace), W.entries(registry(world)))

def root_user(status: D.Status, owner: Nat, root: String, +task: D.Task) -> Bool:
  match status:
    case D.Archived{}: False{}
    case _: Bool.not(Nat.is_eq(owner, D.task_id(task))) && any_root_inside(Workspace.roots(Workspace.workspace(D.contract_context(D.task_contract(task)))), root)

def uses_root(+owner: Nat, +root: String, tasks: +List<D.Task>) -> Bool:
  match tasks:
    case Nil{}: False{}
    case Con{+task, rest}: root_user(D.task_status(task), owner, root, task) || uses_root(owner, root, rest)

def root_unused(owner: Nat, root: String, world: M.World()) -> Bool:
  Bool.not(uses_root(owner, root, D.state_tasks(C.local(D.State, F.State(), world))))

def archive_available(found: Maybe<&2, W.Worktree>, owner: Nat, world: M.World()) -> Bool:
  match found:
    case Some{W.Worktree{source, Some{root}, status, message, primary, backend}}: root_unused(owner, root, world)
    case _: True{}

def archive_allowed(+id: Nat, +world: M.World()) -> Bool:
  archive_available(W.lookup(id, registry(world)), id, world)

def frozen(status: D.Status) -> Bool:
  match status:
    case D.Frozen{}: True{}
    case _: False{}

def archived(status: D.Status) -> Bool:
  match status:
    case D.Archived{}: True{}
    case _: False{}

def found_pending(found: Maybe<&2, W.Worktree>) -> Bool:
  match found:
    case None{}: False{}
    case Some{value}: W.pending(W.status(value))

def pending(id: Nat, +world: M.World()) -> Bool:
  found_pending(W.lookup(id, registry(world)))

def execution_available(found: Maybe<&2, W.Worktree>) -> Bool:
  match found:
    case Some{W.Worktree{source, root, W.CreateFailed{}, message, primary, backend}}: False{}
    case _: True{}

def execution_allowed(id: Nat, world: M.World()) -> Bool:
  execution_available(W.lookup(id, registry(world)))

def control_allowed(+request: D.Control, +id: Nat, +world: M.World()) -> Bool:
  match request:
    case D.Archive{}: True{}
    case D.Freeze{}: execution_allowed(id, world)
    case _: Bool.not(pending(id, world)) && execution_allowed(id, world)

def retry_found(found: Maybe<&2, W.Worktree>, owner: Maybe<&2, D.Task>) -> Bool:
  match found owner:
    case Some{W.Worktree{source, Some{root}, W.ArchiveFailed{}, message, primary, backend}} Some{task}: archived(D.task_status(task))
    case _ _: False{}

def retry_allowed(+id: Nat, +world: M.World()) -> Bool:
  retry_found(W.lookup(id, registry(world)), task(id, world)) && archive_allowed(id, world)

def root_valid(root: Maybe<&2, String>) -> Bool:
  match root:
    case None{}: True{}
    case Some{path}: Workspace.valid_path(path)

def failure_settled(status: D.Status, phase: D.Phase, operations: +List<D.Operation()>) -> Bool:
  match status phase operations:
    case D.Stopped{} D.Idle{} Nil{}: True{}
    case D.Archived{} D.Idle{} Nil{}: True{}
    case _ _ _: False{}

def status_task(status: W.Status, +task: D.Task) -> Bool:
  match status:
    case W.Creating{}: frozen(D.task_status(task)) && Bool.not(D.operations_pending(D.task_operations(task)))
    case W.CreatingArchived{}: archived(D.task_status(task))
    case W.CreateFailed{}: failure_settled(D.task_status(task), D.task_phase(task), D.task_operations(task))
    case W.Archiving{}: archived(D.task_status(task))
    case W.Archived{}: archived(D.task_status(task))
    case W.ArchiveFailed{}: archived(D.task_status(task))
    case _: True{}

def entry_valid(value: W.Worktree, owner: Maybe<&2, D.Task>) -> Bool:
  match value owner:
    case W.Worktree{source, root, status, message, primary, backend} Some{task}:
      Workspace.valid_path(source) && root_valid(root) && status_task(status, task)
    case _ _: False{}

def entries_valid(entries: +List<Finite.Entry(W.Worktree)>, +world: M.World()) -> Bool:
  match entries:
    case Nil{}: True{}
    case Con{(+id, value), rest}: entry_valid(value, task(id, world)) && entries_valid(rest, world)

def valid(+world: M.World()) -> Bool:
  entries_valid(W.entries(registry(world)), world)

def retained_entry(+previous: W.Worktree, next: Maybe<&2, W.Worktree>) -> Bool:
  match next:
    case None{}: False{}
    case Some{+candidate}: String.eq(W.source_root(previous), W.source_root(candidate)) && W.same_backend(W.backend(previous), W.backend(candidate))

def retained_entries(entries: +List<Finite.Entry(W.Worktree)>, +candidate: W.State) -> Bool:
  match entries:
    case Nil{}: True{}
    case Con{(id, value), rest}: retained_entry(value, W.lookup(id, candidate)) && retained_entries(rest, candidate)

def evolution(previous: W.State, candidate: W.State) -> Bool:
  retained_entries(W.entries(previous), candidate)

def creation_status(status: W.Status) -> Bool:
  match status:
    case W.Creating{}: True{}
    case W.CreatingArchived{}: True{}
    case _: False{}

def archive_status(status: W.Status) -> Bool:
  match status:
    case W.Archiving{}: True{}
    case _: False{}

def correlate(accepted: Bool, completion: W.Completion) -> Maybe<&2, O.ResolvedEvent>:
  match accepted:
    case False{}: None{}
    case True{}: Some{O.WorktreeResult{completion}}

def completion_current(found: Maybe<&2, W.Worktree>, creating: Bool) -> Bool:
  match found creating:
    case Some{value} True{}: creation_status(W.status(value))
    case Some{value} False{}: archive_status(W.status(value))
    case _ _: False{}

def correlated(+completion: W.Completion, +world: M.World()) -> Maybe<&2, O.ResolvedEvent>:
  match completion:
    case W.Created{+id, ok, root, workspace, guidance, message}: correlate(completion_current(W.lookup(id, registry(world)), True{}), completion)
    case W.ArchivedResult{+id, ok, root, message}: correlate(completion_current(W.lookup(id, registry(world)), False{}), completion)

def create_effect(found: Maybe<&2, W.Worktree>, +backend: W.Backend, +source: String, workspace: D.Workspace) -> Bool:
  match found:
    case Some{+value}: creation_status(W.status(value)) && W.same_backend(backend, W.backend(value)) && String.eq(source, W.source_root(value)) &&
      String.eq(source, D.selected_workspace(D.TaskContext{workspace, D.Sandbox{D.WorkspaceWrite{}, False{}}, D.AskForApproval{}, None{}}))
    case _: False{}

def archive_effect(found: Maybe<&2, W.Worktree>, backend: W.Backend, source: String, root: String) -> Bool:
  match found:
    case Some{W.Worktree{expected_source, Some{expected_root}, W.Archiving{}, message, primary, expected_backend}}:
      W.same_backend(backend, expected_backend) && String.eq(source, expected_source) && String.eq(root, expected_root)
    case _: False{}

def effect_valid(effect: W.Effect, +state: W.State) -> Bool:
  match effect:
    case W.CreateTree{+id, source, workspace, backend}: create_effect(W.lookup(id, state), backend, source, workspace)
    case W.ArchiveTree{+id, source, root, backend}: archive_effect(W.lookup(id, state), backend, source, root)

# Only the pending task's workspace coordinate can finish initialization.
# All other creation-contract fields are still checked by the core comparator.

def selected_root(selected: Bool, original: String, target: String) -> String:
  match selected:
    case False{}: original
    case True{}: target

def replace_roots(roots: +List<String>, +source: String, +target: String) -> +List<String>:
  match roots:
    case Nil{}: Nil{}
    case Con{+root, rest}: selected_root(String.eq(root, source), root, target) <> replace_roots(rest, source, target)

def context_with_primary(+target: String, context: D.TaskContext) -> D.TaskContext:
  match context:
    case D.TaskContext{D.Workspace{roots, Some{source}}, sandbox, approval, project}:
      D.TaskContext{D.Workspace{replace_roots(roots, source, target), Some{target}}, sandbox, approval, project}
    case other: other

def selected_contract(target: String, contract: D.Contract) -> D.Contract:
  D.Contract{model, tools, forks, descendants, plugins, context} = contract
  D.Contract{model, tools, forks, descendants, plugins, context_with_primary(target, context)}

def initialization_selected(allowed: Bool, primary: String) -> Maybe<&2, String>:
  match allowed:
    case False{}: None{}
    case True{}: Some{primary}

def initialization_target(before: Maybe<&2, W.Worktree>, after: Maybe<&2, W.Worktree>) -> Maybe<&2, String>:
  match before after:
    case Some{W.Worktree{source, None{}, W.Creating{}, message, previous, backend}} Some{W.Worktree{next_source, Some{+root}, W.Ready{}, next_message, +primary, next_backend}}:
      initialization_selected(String.eq(source, next_source) && W.same_backend(backend, next_backend) && Workspace.valid_path(primary) &&
        (String.eq(primary, root) || String.starts_with(primary, root ++ "/")), primary)
    case _ _: None{}

def normalize_task(target: Maybe<&2, String>, +before: D.Task) -> D.Task:
  match target:
    case None{}: before
    case Some{primary}: D.with_contract(selected_contract(primary, D.task_contract(before)), before)

def retained_tasks(tasks: +List<D.Task>, +before: F.State(), +after: F.State()) -> +List<D.Task>:
  match tasks:
    case Nil{}: Nil{}
    case Con{+task, rest}:
      normalize_task(initialization_target(W.lookup(D.task_id(task), F.worktree(before)), W.lookup(D.task_id(task), F.worktree(after))), task) <>
        retained_tasks(rest, before, after)

def replace_task(task: D.Task, world: M.World()) -> M.World():
  Tasks.update_world(F.State(), task, world)

def accepted(world: M.World(), effects: +List<M.Effect()>) -> M.Decision():
  C.Decision{world, D.success(J.Object{[J.Field{"accepted", J.Boolean{True{}}}]}), effects}

def saved(+id: Nat, value: W.Worktree, +world: M.World(), effects: +List<M.Effect()>) -> M.Decision():
  accepted(store(W.put(id, value, registry(world)), world), effects)

def environment_notice(backend: W.Backend, task: D.Task) -> D.Task:
  match backend:
    case W.Local{}: task
    case W.TencentCvm{}: D.append_context(D.EnvironmentNotice{"Bash runs in the task cloud environment with Full Access. MCP tools may return paths on the local host; these paths are not necessarily available in the cloud environment."}, task)

def initialize_environment(backend: W.Backend, found: Maybe<&2, D.Task>, world: M.World()) -> M.World():
  match found:
    case None{}: world
    case Some{task}: replace_task(environment_notice(backend, D.with_status(D.Frozen{}, task)), world)

def initialized_task(found: Maybe<&2, D.Task>, world: M.World()) -> M.World():
  match found:
    case None{}: world
    case Some{task}: replace_task(D.with_status(D.Frozen{}, task), world)

def primary_text(workspace: D.Workspace) -> String:
  match workspace:
    case D.Workspace{roots, None{}}: ""
    case D.Workspace{roots, Some{primary}}: primary

def initialize_backend(+backend: W.Backend, +id: Nat, +workspace: D.Workspace, decision: M.Decision()) -> M.Decision():
  C.Decision{+world, reply, effects} = decision
  +source = primary_text(workspace)
  +next = initialize_environment(backend, task(id, world), world)
  C.Decision{store(W.put(id, W.Worktree{source, None{}, W.Creating{}, "", "", backend}, registry(next)), next), reply,
    List.append(&2, M.Effect(), effects, [Effects.FeatureEffect{F.WorktreeEffect{W.CreateTree{id, source, workspace, backend}}}])}

def initialize(id: Nat, workspace: D.Workspace, decision: M.Decision()) -> M.Decision():
  initialize_backend(W.Local{}, id, workspace, decision)

def workspace_selected(expected: D.Workspace, actual: D.Workspace) -> Bool:
  D.Workspace{roots, primary} = expected
  D.Workspace{other_roots, other_primary} = actual
  Same.strings(roots, other_roots) && Same.optional_string(primary, other_primary)

def completed_workspace(+root: String, +workspace: D.Workspace, +task: D.Task) -> Bool:
  +primary = primary_text(workspace)
  Workspace.valid_path(root) && Workspace.valid(workspace) && D.nonempty(primary) &&
    (String.eq(primary, root) || String.starts_with(primary, root ++ "/")) &&
    workspace_selected(Workspace.workspace(context_with_primary(primary, D.task_context(task))), workspace)

def completed_task(+primary: String, guidance: D.ProjectContext, +task: D.Task) -> D.Task:
  +selected = D.with_contract(selected_contract(primary, D.task_contract(task)), task)
  +configured = D.append_context(D.TaskSettings{D.task_context(selected), D.task_profile(selected), D.task_reasoning(selected)},
    D.selected_project(guidance, selected))
  Tasks.promote(D.with_status(D.Active{}, configured))

def failure_task(message: String, task: D.Task) -> D.Task:
  D.with_phase(D.Idle{}, D.with_status(D.Stopped{}, D.append_message(D.FailureMessage{message}, task)))

def archive_current(available: Bool, +backend: W.Backend, +id: Nat, +source: String, +root: String, primary: String, world: M.World()) -> M.Decision():
  match available:
    case False{}:
      saved(id, W.Worktree{source, Some{root}, W.ArchiveFailed{}, "Worktree is still used by another task. Archive shared tasks before retrying.", primary, backend}, world, Nil{})
    case True{}:
      saved(id, W.Worktree{source, Some{root}, W.Archiving{}, "", primary, backend}, world,
        [Effects.FeatureEffect{F.WorktreeEffect{W.ArchiveTree{id, source, root, backend}}}])

def archive_started(+id: Nat, value: W.Worktree, +world: M.World()) -> M.Decision():
  match value:
    case W.Worktree{source, None{}, status, message, primary, backend}: accepted(world, Nil{})
    case W.Worktree{+source, Some{+root}, status, message, primary, backend}:
      archive_current(root_unused(id, root, world), backend, id, source, root, primary, world)

def archive_merge(reply: J.Json, before: +List<M.Effect()>, result: M.Decision()) -> M.Decision():
  C.Decision{world, ignored, effects} = result
  C.Decision{world, reply, List.append(&2, M.Effect(), before, effects)}

def archive_eligible(allowed: Bool, id: Nat, value: W.Worktree, world: M.World()) -> M.Decision():
  match allowed:
    case False{}: accepted(world, Nil{})
    case True{}: archive_started(id, value, world)

def archive_value(+id: Nat, found: Maybe<&2, W.Worktree>, +world: M.World()) -> M.Decision():
  match found:
    case None{}: accepted(world, Nil{})
    case Some{W.Worktree{source, root, W.Creating{}, message, primary, backend}}:
      saved(id, W.Worktree{source, root, W.CreatingArchived{}, message, primary, backend}, world, Nil{})
    case Some{+value}: archive_eligible(W.archivable(W.status(value)), id, value, world)

def archive_found(+id: Nat, found: Maybe<&2, W.Worktree>, decision: M.Decision()) -> M.Decision():
  C.Decision{+world, reply, effects} = decision
  archive_merge(reply, effects, archive_value(id, found, world))

def archived_decision(+id: Nat, +decision: M.Decision()) -> M.Decision():
  C.Decision{+world, reply, effects} = decision
  archive_found(id, W.lookup(id, registry(world)), decision)

def archive_failed_created(+id: Nat, +failed: W.Worktree, +world: M.World()) -> M.Decision():
  archive_value(id, Some{failed}, store(W.put(id, failed, registry(world)), world))

def failed_for_status(was_archived: Bool, +id: Nat, +value: W.Worktree, root: Maybe<&2, String>, +message: String, task: D.Task, +world: M.World()) -> M.Decision():
  match was_archived:
    case False{}: saved(id, W.Worktree{W.source_root(value), root, W.CreateFailed{}, message, "", W.backend(value)}, replace_task(failure_task(message, task), world), Nil{})
    case True{}: archive_failed_created(id, W.Worktree{W.source_root(value), root, W.CreateFailed{}, message, "", W.backend(value)}, world)

def create_failed_found(found: Maybe<&2, D.Task>, +id: Nat, +value: W.Worktree, root: Maybe<&2, String>, +message: String, +world: M.World()) -> M.Decision():
  match found:
    case None{}: accepted(world, Nil{})
    case Some{+task}: failed_for_status(archived(D.task_status(task)), id, value, root, message, task, world)

def create_failed(+id: Nat, value: W.Worktree, root: Maybe<&2, String>, message: String, +world: M.World()) -> M.Decision():
  create_failed_found(task(id, world), id, value, root, message, world)

def created_for_status(was_archived: Bool, +id: Nat, +value: W.Worktree, +root: String, +workspace: D.Workspace,
  guidance: D.ProjectContext, +task: D.Task, +world: M.World()) -> M.Decision():
  match was_archived:
    case True{}: archive_started(id, W.Worktree{W.source_root(value), Some{root}, W.Ready{}, "", primary_text(workspace), W.backend(value)}, world)
    case False{}:
      saved(id, W.Worktree{W.source_root(value), Some{root}, W.Ready{}, "", primary_text(workspace), W.backend(value)}, replace_task(completed_task(primary_text(workspace), guidance, task), world), Nil{})

def created_success_found(found: Maybe<&2, D.Task>, +id: Nat, +value: W.Worktree, +root: String, +workspace: D.Workspace, guidance: D.ProjectContext, +world: M.World()) -> M.Decision():
  match found:
    case None{}: accepted(world, Nil{})
    case Some{+task}: created_for_status(archived(D.task_status(task)), id, value, root, workspace, guidance, task, world)

def created_success(+id: Nat, value: W.Worktree, root: String, workspace: D.Workspace, guidance: D.ProjectContext, +world: M.World()) -> M.Decision():
  created_success_found(task(id, world), id, value, root, workspace, guidance, world)

def created_valid(allowed: Bool, id: Nat, value: W.Worktree, root: String, workspace: D.Workspace, guidance: D.ProjectContext, world: M.World()) -> M.Decision():
  match allowed:
    case False{}: create_failed(id, value, Some{root}, "Worktree creation returned an invalid workspace or guidance", world)
    case True{}: created_success(id, value, root, workspace, guidance, world)

def created_checked(found: Maybe<&2, D.Task>, id: Nat, value: W.Worktree, +root: String, +workspace: D.Workspace, +guidance: D.ProjectContext, world: M.World()) -> M.Decision():
  match found:
    case None{}: accepted(world, Nil{})
    case Some{task}: created_valid(completed_workspace(root, workspace, task) && Workspace.valid_guidance(guidance) &&
      Workspace.guidance_member(Workspace.primary(workspace), guidance), id, value, root, workspace, guidance, world)

def created_result(+id: Nat, +value: W.Worktree, ok: Bool, root: Maybe<&2, String>, +workspace: D.Workspace, +guidance: D.ProjectContext, message: String, +world: M.World()) -> M.Decision():
  match ok root:
    case True{} Some{+root}: created_checked(task(id, world), id, value, root, workspace, guidance, world)
    case True{} None{}: create_failed(id, value, None{}, "Worktree creation succeeded without a managed root", world)
    case False{} root: create_failed(id, value, root, message, world)

def archive_result(+id: Nat, +value: W.Worktree, ok: Bool, root: String, message: String, world: M.World()) -> M.Decision():
  match ok:
    case True{}: saved(id, W.Worktree{W.source_root(value), Some{root}, W.Archived{}, "", W.target_primary(value), W.backend(value)}, world, Nil{})
    case False{}: saved(id, W.with_status(W.ArchiveFailed{}, message, value), world, Nil{})

def cloud_selection(selection: Workspace.Selection) -> Workspace.Selection:
  Workspace.Selection{D.TaskContext{workspace, sandbox, approval, project}, guidance} = selection
  Workspace.Selection{D.TaskContext{workspace, D.Sandbox{D.WorkspaceWrite{}, True{}}, D.FullAccess{}, project}, guidance}

def primary_workspace(workspace: D.Workspace) -> D.Workspace:
  match workspace:
    case D.Workspace{roots, None{}}: D.Workspace{Nil{}, None{}}
    case D.Workspace{roots, Some{+primary}}: D.Workspace{[primary], Some{primary}}

def primary_selection(selection: Workspace.Selection) -> Workspace.Selection:
  Workspace.Selection{D.TaskContext{workspace, sandbox, approval, project}, guidance} = selection
  Workspace.Selection{D.TaskContext{primary_workspace(workspace), sandbox, approval, project}, guidance}

def backend_selection(backend: W.Backend, selection: Workspace.Selection) -> Workspace.Selection:
  match backend:
    case W.Local{}: selection
    case W.TencentCvm{}: cloud_selection(primary_selection(selection))

def cloud_entry(found: Maybe<&2, Finite.Entry(W.Worktree)>) -> Bool:
  match found:
    case None{}: False{}
    case Some{(owner, value)}: W.cloud(W.backend(value))

def cloud_task(id: Nat, world: M.World()) -> Bool:
  cloud_entry(effective(id, world))

def bound_selection(selection: Result<&2, &2, String, Workspace.Selection>, +world: M.World()) -> Result<&2, &2, String, Workspace.Selection>:
  match selection:
    case Fail{reason}: Fail{reason}
    case Done{+selection}: Done{Bool.pick(Workspace.Selection,
      cloud_entry(find_effective(W.entries(registry(world)), selection_primary(selection))), cloud_selection(selection), selection)}

def cloud_options_allowed(id: Nat, +options: J.Json, world: M.World()) -> Bool:
  Bool.not(cloud_task(id, world)) ||
    (Workspace.absent(J.get(options, "workspace")) && Workspace.absent(J.get(options, "project_id")))
