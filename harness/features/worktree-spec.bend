import Base
import ../DOMAIN.bend as D
import ../MODEL.bend as M
import ../tasks/PROGRAM.bend as Tasks
import ../workspace/WORKSPACE.bend as Workspace
import ../../bendlib/component.bend as C
import ../../bendlib/json.bend as J
import ../../bendlib/effects.bend as Effects
import ../../features/worktree/MODEL.bend as W
import ./MODEL.bend as F
import ./worktree-state.bend as State

def completed_task(+primary: String, guidance: D.ProjectContext, +task: D.Task) -> D.Task:
  +selected = D.with_contract(State.selected_contract(primary, D.task_contract(task)), task)
  +configured = D.append_context(D.TaskSettings{D.task_context(selected), D.task_profile(selected), D.task_reasoning(selected)},
    D.selected_project(guidance, selected))
  Tasks.promote(D.with_status(D.Active{}, configured))

def failure_task(message: String, task: D.Task) -> D.Task:
  D.with_phase(D.Idle{}, D.with_status(D.Stopped{}, D.append_message(D.FailureMessage{message}, task)))

def archive_current(available: Bool, +id: Nat, +source: String, +root: String, primary: String, world: M.World()) -> M.Decision():
  match available:
    case False{}:
      State.saved(id, W.Worktree{source, Some{root}, W.ArchiveFailed{}, "Worktree is still used by another task. Archive shared tasks before retrying.", primary}, world, Nil{})
    case True{}:
      State.saved(id, W.Worktree{source, Some{root}, W.Archiving{}, "", primary}, world,
        [Effects.FeatureEffect{F.WorktreeEffect{W.ArchiveTree{id, source, root}}}])

def archive_started(+id: Nat, value: W.Worktree, +world: M.World()) -> M.Decision():
  match value:
    case W.Worktree{source, None{}, status, message, primary}: State.accepted(world, Nil{})
    case W.Worktree{+source, Some{+root}, status, message, primary}:
      archive_current(State.root_unused(id, root, world), id, source, root, primary, world)

def archive_merge(reply: J.Json, before: +List<M.Effect()>, result: M.Decision()) -> M.Decision():
  C.Decision{world, ignored, effects} = result
  C.Decision{world, reply, List.append(&2, M.Effect(), before, effects)}

def archive_eligible(allowed: Bool, id: Nat, value: W.Worktree, world: M.World()) -> M.Decision():
  match allowed:
    case False{}: State.accepted(world, Nil{})
    case True{}: archive_started(id, value, world)

def archive_value(+id: Nat, found: Maybe<&2, W.Worktree>, +world: M.World()) -> M.Decision():
  match found:
    case None{}: State.accepted(world, Nil{})
    case Some{W.Worktree{source, root, W.Creating{}, message, primary}}:
      State.saved(id, W.Worktree{source, root, W.CreatingArchived{}, message, primary}, world, Nil{})
    case Some{+value}: archive_eligible(W.archivable(W.status(value)), id, value, world)

def archive_failed_created(+id: Nat, +failed: W.Worktree, +world: M.World()) -> M.Decision():
  archive_value(id, Some{failed}, State.store(W.put(id, failed, State.registry(world)), world))

def failed_for_status(was_archived: Bool, +id: Nat, value: W.Worktree, root: Maybe<&2, String>, +message: String, task: D.Task, +world: M.World()) -> M.Decision():
  match was_archived:
    case False{}: State.saved(id, W.Worktree{W.source_root(value), root, W.CreateFailed{}, message, ""}, State.replace_task(failure_task(message, task), world), Nil{})
    case True{}: archive_failed_created(id, W.Worktree{W.source_root(value), root, W.CreateFailed{}, message, ""}, world)

def create_failed_found(found: Maybe<&2, D.Task>, +id: Nat, +value: W.Worktree, root: Maybe<&2, String>, +message: String, +world: M.World()) -> M.Decision():
  match found:
    case None{}: State.accepted(world, Nil{})
    case Some{+task}: failed_for_status(State.archived(D.task_status(task)), id, value, root, message, task, world)

def create_failed(+id: Nat, value: W.Worktree, root: Maybe<&2, String>, message: String, +world: M.World()) -> M.Decision():
  create_failed_found(State.task(id, world), id, value, root, message, world)

def created_for_status(was_archived: Bool, +id: Nat, +value: W.Worktree, +root: String, +workspace: D.Workspace,
  guidance: D.ProjectContext, +task: D.Task, +world: M.World()) -> M.Decision():
  match was_archived:
    case True{}: archive_started(id, W.Worktree{W.source_root(value), Some{root}, W.Ready{}, "", State.primary_text(workspace)}, world)
    case False{}:
      State.saved(id, W.Worktree{W.source_root(value), Some{root}, W.Ready{}, "", State.primary_text(workspace)}, State.replace_task(completed_task(State.primary_text(workspace), guidance, task), world), Nil{})

def created_success_found(found: Maybe<&2, D.Task>, +id: Nat, +value: W.Worktree, +root: String, +workspace: D.Workspace, guidance: D.ProjectContext, +world: M.World()) -> M.Decision():
  match found:
    case None{}: State.accepted(world, Nil{})
    case Some{+task}: created_for_status(State.archived(D.task_status(task)), id, value, root, workspace, guidance, task, world)

def created_success(+id: Nat, value: W.Worktree, root: String, workspace: D.Workspace, guidance: D.ProjectContext, +world: M.World()) -> M.Decision():
  created_success_found(State.task(id, world), id, value, root, workspace, guidance, world)

def created_valid(allowed: Bool, id: Nat, value: W.Worktree, root: String, workspace: D.Workspace, guidance: D.ProjectContext, world: M.World()) -> M.Decision():
  match allowed:
    case False{}: create_failed(id, value, Some{root}, "Worktree creation returned an invalid workspace or guidance", world)
    case True{}: created_success(id, value, root, workspace, guidance, world)

def created_checked(found: Maybe<&2, D.Task>, id: Nat, value: W.Worktree, +root: String, +workspace: D.Workspace, +guidance: D.ProjectContext, world: M.World()) -> M.Decision():
  match found:
    case None{}: State.accepted(world, Nil{})
    case Some{task}: created_valid(State.completed_workspace(root, workspace, task) && Workspace.valid_guidance(guidance) &&
      Workspace.guidance_member(Workspace.primary(workspace), guidance), id, value, root, workspace, guidance, world)

def created_result(+id: Nat, +value: W.Worktree, ok: Bool, root: Maybe<&2, String>, +workspace: D.Workspace, +guidance: D.ProjectContext, message: String, +world: M.World()) -> M.Decision():
  match ok root:
    case True{} Some{+root}: created_checked(State.task(id, world), id, value, root, workspace, guidance, world)
    case True{} None{}: create_failed(id, value, None{}, "Worktree creation succeeded without a managed root", world)
    case False{} root: create_failed(id, value, root, message, world)

def archive_result(+id: Nat, +value: W.Worktree, ok: Bool, root: String, message: String, world: M.World()) -> M.Decision():
  match ok:
    case True{}: State.saved(id, W.Worktree{W.source_root(value), Some{root}, W.Archived{}, "", W.target_primary(value)}, world, Nil{})
    case False{}: State.saved(id, W.with_status(W.ArchiveFailed{}, message, value), world, Nil{})

def created_current(current: Bool, id: Nat, value: W.Worktree, ok: Bool, root: Maybe<&2, String>, workspace: D.Workspace, guidance: D.ProjectContext, message: String, world: M.World()) -> M.Decision():
  match current:
    case False{}: State.accepted(world, Nil{})
    case True{}: created_result(id, value, ok, root, workspace, guidance, message, world)

def archived_current(current: Bool, id: Nat, value: W.Worktree, ok: Bool, root: String, message: String, world: M.World()) -> M.Decision():
  match current:
    case False{}: State.accepted(world, Nil{})
    case True{}: archive_result(id, value, ok, root, message, world)

def created_found(found: Maybe<&2, W.Worktree>, id: Nat, ok: Bool, root: Maybe<&2, String>, workspace: D.Workspace, guidance: D.ProjectContext, message: String, world: M.World()) -> M.Decision():
  match found:
    case None{}: State.accepted(world, Nil{})
    case Some{+value}: created_current(State.creation_status(W.status(value)), id, value, ok, root, workspace, guidance, message, world)

def archived_found(found: Maybe<&2, W.Worktree>, id: Nat, ok: Bool, root: String, message: String, world: M.World()) -> M.Decision():
  match found:
    case None{}: State.accepted(world, Nil{})
    case Some{+value}: archived_current(State.archive_status(W.status(value)), id, value, ok, root, message, world)

def complete(completion: W.Completion, +world: M.World()) -> M.Decision():
  match completion:
    case W.Created{+id, ok, root, workspace, guidance, message}:
      created_found(W.lookup(id, State.registry(world)), id, ok, root, workspace, guidance, message, world)
    case W.ArchivedResult{+id, ok, root, message}:
      archived_found(W.lookup(id, State.registry(world)), id, ok, root, message, world)

def retry_archive(+id: Nat, +world: M.World()) -> M.Decision():
  archive_value(id, W.lookup(id, State.registry(world)), world)

def initialized_task(found: Maybe<&2, D.Task>, world: M.World()) -> M.World():
  match found:
    case None{}: world
    case Some{task}: State.replace_task(D.with_status(D.Frozen{}, task), world)

def initialize(+id: Nat, +workspace: D.Workspace, decision: M.Decision()) -> M.Decision():
  C.Decision{+world, reply, effects} = decision
  +source = State.primary_text(workspace)
  +next = initialized_task(State.task(id, world), world)
  C.Decision{State.store(W.put(id, W.Worktree{source, None{}, W.Creating{}, "", ""}, State.registry(next)), next), reply,
    List.append(&2, M.Effect(), effects, [Effects.FeatureEffect{F.WorktreeEffect{W.CreateTree{id, source, workspace}}}])}

def start(~spawn: D.Profile -> String -> D.UserContent -> Workspace.Selection -> @+world:M.World() -> M.Decision(), profile: D.Profile, reasoning: String, message: D.UserContent, +selection: Workspace.Selection, +world: M.World()) -> M.Decision():
  Workspace.Selection{context, guidance} = selection
  initialize(D.state_next_task(C.local(D.State, F.State(), world)), Workspace.workspace(context), spawn(profile, reasoning, message, selection, world))
