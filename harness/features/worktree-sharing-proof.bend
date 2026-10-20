import Base
import ./MODEL.bend as F
import ./CONTRACT.bend as Contract
import ./worktree-state.bend as State
import ../../features/worktree/MODEL.bend as W
import ../../bendlib/component.bend as C
import ../../bendlib/association-map.bend as Finite
import ../../bendlib/stdlib.bend as Std
import ../../bendlib/logic-proof.bend as Logic
import ../MODEL.bend as M
import ../DOMAIN.bend as D
import ../workspace/WORKSPACE.bend as Workspace

def own_priority(+id: Nat, +value: W.Worktree, +world: M.World(),
  observed: {W.lookup(id, State.registry(world)) == Some{value} : Maybe<&2, W.Worktree>}) ->
  {State.effective(id, world) == Some{(id, value)} : Maybe<&2, Finite.Entry(W.Worktree)>}:
  Equal.cong(Maybe<&2, W.Worktree>, Maybe<&2, Finite.Entry(W.Worktree)>,
    own => State.effective_found(own, id, State.task(id, world), W.entries(State.registry(world))),
    W.lookup(id, State.registry(world)), Some{value}, observed)

def inherited_lookup(id: Nat, +task: D.Task, +entries: +List<Finite.Entry(W.Worktree)>) ->
  {State.effective_found(None{}, id, Some{task}, entries) == State.find_effective(entries, State.frozen_primary(task)) : Maybe<&2, Finite.Entry(W.Worktree)>}:
  {==}

def chosen_owner(+owner: Nat, +value: W.Worktree, rest: Maybe<&2, Finite.Entry(W.Worktree)>) ->
  {State.choose_effective(True{}, owner, value, rest) == Some{(owner, value)} : Maybe<&2, Finite.Entry(W.Worktree)>}:
  {==}

def skipped_owner(owner: Nat, value: W.Worktree, +rest: Maybe<&2, Finite.Entry(W.Worktree)>) ->
  {State.choose_effective(False{}, owner, value, rest) == rest : Maybe<&2, Finite.Entry(W.Worktree)>}:
  {==}

def borrowed_root(backend: W.Backend, +primary: String, source: String, +root: String, status: W.Status, message: String, target: String) ->
  {State.borrowed_candidate(primary, W.Worktree{source, Some{root}, status, message, target, backend}) == State.path_inside(root, primary) : Bool}:
  {==}

def borrowed_missing_root(backend: W.Backend, primary: String, source: String, status: W.Status, message: String, target: String) ->
  {State.borrowed_candidate(primary, W.Worktree{source, None{}, status, message, target, backend}) == False{} : Bool}:
  {==}

def chosen_inside(+selected: Bool, +owner: Nat, +value: W.Worktree, +rest: Maybe<&2, Finite.Entry(W.Worktree)>, +primary: String,
  observed: {State.borrowed_candidate(primary, value) == selected : Bool},
  induction: {Contract.inherited_inside(primary, rest) == True{} : Bool}) ->
  {Contract.inherited_inside(primary, State.choose_effective(selected, owner, value, rest)) == True{} : Bool}:
  match selected:
    case False{}: induction
    case True{}:
      match value:
        case W.Worktree{source, None{}, status, message, target, backend}: Logic.impossible({False{} == True{} : Bool}, observed)
        case W.Worktree{source, Some{root}, status, message, target, backend}: observed

def inherited_inside(+entries: +List<Finite.Entry(W.Worktree)>, +primary: String) ->
  {Contract.inherited_inside(primary, State.find_effective(entries, primary)) == True{} : Bool}:
  match entries:
    case Nil{}: {==}
    case Con{(+owner, +value), +rest}:
      chosen_inside(State.borrowed_candidate(primary, value), owner, value, State.find_effective(rest, primary), primary,
        {==}, inherited_inside(rest, primary))

def archived_ignored(owner: Nat, root: String, task: D.Task) ->
  {State.root_user(D.Archived{}, owner, root, task) == False{} : Bool}:
  {==}

def live_root_user(+status: D.Status, +owner: Nat, +root: String, +task: D.Task,
  live: {State.archived(status) == False{} : Bool}) ->
  {State.root_user(status, owner, root, task) ==
    (Bool.not(Nat.is_eq(owner, D.task_id(task))) && State.any_root_inside(Workspace.roots(Workspace.workspace(D.contract_context(D.task_contract(task)))), root)) : Bool}:
  match status:
    case D.Active{}: {==}
    case D.Frozen{}: {==}
    case D.Stopped{}: {==}
    case D.Archived{}:
      Logic.impossible({State.root_user(D.Archived{}, owner, root, task) ==
        (Bool.not(Nat.is_eq(owner, D.task_id(task))) && State.any_root_inside(Workspace.roots(Workspace.workspace(D.contract_context(D.task_contract(task)))), root)) : Bool},
        Equal.sym(Bool, True{}, False{}, live))

def archive_root(backend: W.Backend, source: String, +root: String, status: W.Status, message: String, primary: String, +owner: Nat, +world: M.World()) ->
  {State.archive_available(Some{W.Worktree{source, Some{root}, status, message, primary, backend}}, owner, world) ==
    Bool.not(State.uses_root(owner, root, D.state_tasks(C.local(D.State, F.State(), world)))) : Bool}:
  {==}

def archive_missing(owner: Nat, world: M.World()) ->
  {State.archive_available(None{}, owner, world) == True{} : Bool}:
  {==}

def blocked_root(+owner: Nat, +root: String, +world: M.World(),
  blocked: {State.uses_root(owner, root, D.state_tasks(C.local(D.State, F.State(), world))) == True{} : Bool}) ->
  {State.root_unused(owner, root, world) == False{} : Bool}:
  Equal.cong(Bool, Bool, value => Bool.not(value),
    State.uses_root(owner, root, D.state_tasks(C.local(D.State, F.State(), world))), True{}, blocked)

def workspace_ready(backend: W.Backend, roots: +List<String>, source: String, root: String, message: String, primary: String) ->
  {State.workspace_resource_available(roots, W.Worktree{source, Some{root}, W.Ready{}, message, primary, backend}) == True{} : Bool}:
  {==}

def workspace_protected(backend: W.Backend, +roots: +List<String>, source: String, +root: String, +status: W.Status, message: String, primary: String,
  nonready: {Contract.ready_worktree_status(status) == False{} : Bool}) ->
  {State.workspace_resource_available(roots, W.Worktree{source, Some{root}, status, message, primary, backend}) == Bool.not(State.any_root_inside(roots, root)) : Bool}:
  match status:
    case W.Creating{}: {==}
    case W.CreatingArchived{}: {==}
    case W.Ready{}:
      Logic.impossible({State.workspace_resource_available(roots, W.Worktree{source, Some{root}, W.Ready{}, message, primary, backend}) == Bool.not(State.any_root_inside(roots, root)) : Bool},
        Equal.sym(Bool, True{}, False{}, nonready))
    case W.CreateFailed{}: {==}
    case W.Archiving{}: {==}
    case W.Archived{}: {==}
    case W.ArchiveFailed{}: {==}

def unowned_archive(id: Nat, +decision: M.Decision()) ->
  {State.archive_found(id, None{}, decision) == decision : M.Decision()}:
  C.Decision{+world, +reply, +effects} = decision
  Equal.cong(+List<M.Effect()>, M.Decision(), values => C.Decision{world, reply, values},
    List.append(&2, M.Effect(), effects, Nil{}), effects, Std.app_nil_r(M.Effect(), effects))

def boundary() -> Contract.WorktreeSharing:
  Contract.WorktreeSharing{own_priority, inherited_lookup, chosen_owner, skipped_owner, borrowed_root, borrowed_missing_root,
    inherited_inside, archived_ignored, live_root_user, archive_root, archive_missing, blocked_root, workspace_ready, workspace_protected, unowned_archive}
