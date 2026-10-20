import Base
import ../DOMAIN.bend as D
import ../MODEL.bend as M
import ../workspace/WORKSPACE.bend as Workspace
import ../../bendlib/component.bend as C
import ../../features/worktree/MODEL.bend as W
import ./MODEL.bend as F
import ./worktree-state.bend as State

def created_current(current: Bool, id: Nat, value: W.Worktree, ok: Bool, root: Maybe<&2, String>, workspace: D.Workspace, guidance: D.ProjectContext, message: String, world: M.World()) -> M.Decision():
  match current:
    case False{}: State.accepted(world, Nil{})
    case True{}: State.created_result(id, value, ok, root, workspace, guidance, message, world)

def archived_current(current: Bool, id: Nat, value: W.Worktree, ok: Bool, root: String, message: String, world: M.World()) -> M.Decision():
  match current:
    case False{}: State.accepted(world, Nil{})
    case True{}: State.archive_result(id, value, ok, root, message, world)

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
  State.archive_value(id, W.lookup(id, State.registry(world)), world)

def start(~spawn: D.Profile -> String -> D.UserContent -> Workspace.Selection -> @+world:M.World() -> M.Decision(), profile: D.Profile, reasoning: String, message: D.UserContent, +selection: Workspace.Selection, +world: M.World()) -> M.Decision():
  Workspace.Selection{context, guidance} = selection
  State.initialize(D.state_next_task(C.local(D.State, F.State(), world)), Workspace.workspace(context), spawn(profile, reasoning, message, selection, world))

def start_backend(~spawn: D.Profile -> String -> D.UserContent -> Workspace.Selection -> @+world:M.World() -> M.Decision(),
  +backend: W.Backend, profile: D.Profile, reasoning: String, message: D.UserContent, +selection: Workspace.Selection, +world: M.World()) -> M.Decision():
  Workspace.Selection{context, guidance} = selection
  State.initialize_backend(backend, D.state_next_task(C.local(D.State, F.State(), world)), Workspace.workspace(context), spawn(profile, reasoning, message, selection, world))
