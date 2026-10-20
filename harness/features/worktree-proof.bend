import Base
import ../../bendlib/json.bend as J
import ../../bendlib/effects.bend as Effects
import ../DOMAIN.bend as D
import ../tasks/PROGRAM.bend as Tasks
import ../MODEL.bend as M
import ../workspace/WORKSPACE.bend as Workspace
import ../../bendlib/component.bend as C
import ../../features/worktree/MODEL.bend as W
import ./MODEL.bend as F
import ./worktree-state.bend as State
import ./worktree-spec.bend as Spec
import ./worktree-execution.bend as Actual

def initialized_task(+found: Maybe<&2, D.Task>, +world: M.World()) ->
  {State.initialized_task(found, world) == Spec.initialized_task(found, world) : M.World()}:
  match found:
    case None{}: {==}
    case Some{task}: {==}

def initialize_environment(+backend: W.Backend, +found: Maybe<&2, D.Task>, +world: M.World()) ->
  {State.initialize_environment(backend, found, world) == Spec.initialize_environment(backend, found, world) : M.World()}:
  match found:
    case None{}: {==}
    case Some{task}: {==}

def initialized_world(+backend: W.Backend, +id: Nat, +workspace: D.Workspace, +after: M.World(), reply: J.Json, effects: +List<M.Effect()>) -> M.Decision():
  C.Decision{State.store(W.put(id, W.Worktree{State.primary_text(workspace), None{}, W.Creating{}, "", "", backend}, State.registry(after)), after), reply,
    List.append(&2, M.Effect(), effects, [Effects.FeatureEffect{F.WorktreeEffect{W.CreateTree{id, State.primary_text(workspace), workspace, backend}}}])}

def initialize_backend(+backend: W.Backend, +id: Nat, +workspace: D.Workspace, +decision: M.Decision()) ->
  {State.initialize_backend(backend, id, workspace, decision) == Spec.initialize_backend(backend, id, workspace, decision) : M.Decision()}:
  match decision:
    case C.Decision{+world, reply, effects}:
      Equal.cong(M.World(), M.Decision(),
        after => initialized_world(backend, id, workspace, after, reply, effects),
        State.initialize_environment(backend, State.task(id, world), world), Spec.initialize_environment(backend, State.task(id, world), world),
        initialize_environment(backend, State.task(id, world), world))

def initialize(+id: Nat, +workspace: D.Workspace, +decision: M.Decision()) ->
  {State.initialize(id, workspace, decision) == Spec.initialize(id, workspace, decision) : M.Decision()}:
  initialize_backend(W.Local{}, id, workspace, decision)

def start(
  ~actual_spawn: D.Profile -> String -> D.UserContent -> Workspace.Selection -> @+world:M.World() -> M.Decision(),
  ~spec_spawn: D.Profile -> String -> D.UserContent -> Workspace.Selection -> @+world:M.World() -> M.Decision(),
  ~creation: @+profile:D.Profile -> @+reasoning:String -> @+message:D.UserContent -> @+selection:Workspace.Selection -> @+world:M.World() ->
    {actual_spawn(profile, reasoning, message, selection, world) == spec_spawn(profile, reasoning, message, selection, world) : M.Decision()},
  +profile: D.Profile, +reasoning: String, +message: D.UserContent, +selection: Workspace.Selection, +world: M.World()) ->
  {Actual.start(~actual_spawn, profile, reasoning, message, selection, world) == Spec.start(~spec_spawn, profile, reasoning, message, selection, world) : M.Decision()}:
  Workspace.Selection{+context, guidance} = selection
  Equal.trans(M.Decision(),
    State.initialize(D.state_next_task(C.local(D.State, F.State(), world)), Workspace.workspace(context), actual_spawn(profile, reasoning, message, selection, world)),
    State.initialize(D.state_next_task(C.local(D.State, F.State(), world)), Workspace.workspace(context), spec_spawn(profile, reasoning, message, selection, world)),
    Spec.initialize(D.state_next_task(C.local(D.State, F.State(), world)), Workspace.workspace(context), spec_spawn(profile, reasoning, message, selection, world)),
    Equal.cong(M.Decision(), M.Decision(),
      decision => State.initialize(D.state_next_task(C.local(D.State, F.State(), world)), Workspace.workspace(context), decision),
      actual_spawn(profile, reasoning, message, selection, world), spec_spawn(profile, reasoning, message, selection, world),
      creation(profile, reasoning, message, selection, world)),
    initialize(D.state_next_task(C.local(D.State, F.State(), world)), Workspace.workspace(context), spec_spawn(profile, reasoning, message, selection, world)))

def start_backend(
  ~actual_spawn: D.Profile -> String -> D.UserContent -> Workspace.Selection -> @+world:M.World() -> M.Decision(),
  ~spec_spawn: D.Profile -> String -> D.UserContent -> Workspace.Selection -> @+world:M.World() -> M.Decision(),
  ~creation: @+profile:D.Profile -> @+reasoning:String -> @+message:D.UserContent -> @+selection:Workspace.Selection -> @+world:M.World() ->
    {actual_spawn(profile, reasoning, message, selection, world) == spec_spawn(profile, reasoning, message, selection, world) : M.Decision()},
  +backend: W.Backend, +profile: D.Profile, +reasoning: String, +message: D.UserContent, +selection: Workspace.Selection, +world: M.World()) ->
  {Actual.start_backend(~actual_spawn, backend, profile, reasoning, message, selection, world) == Spec.start_backend(~spec_spawn, backend, profile, reasoning, message, selection, world) : M.Decision()}:
  Workspace.Selection{+context, guidance} = selection
  Equal.trans(M.Decision(),
    State.initialize_backend(backend, D.state_next_task(C.local(D.State, F.State(), world)), Workspace.workspace(context), actual_spawn(profile, reasoning, message, selection, world)),
    State.initialize_backend(backend, D.state_next_task(C.local(D.State, F.State(), world)), Workspace.workspace(context), spec_spawn(profile, reasoning, message, selection, world)),
    Spec.initialize_backend(backend, D.state_next_task(C.local(D.State, F.State(), world)), Workspace.workspace(context), spec_spawn(profile, reasoning, message, selection, world)),
    Equal.cong(M.Decision(), M.Decision(),
      decision => State.initialize_backend(backend, D.state_next_task(C.local(D.State, F.State(), world)), Workspace.workspace(context), decision),
      actual_spawn(profile, reasoning, message, selection, world), spec_spawn(profile, reasoning, message, selection, world),
      creation(profile, reasoning, message, selection, world)),
    initialize_backend(backend, D.state_next_task(C.local(D.State, F.State(), world)), Workspace.workspace(context), spec_spawn(profile, reasoning, message, selection, world)))

def archive_current(+available: Bool, +backend: W.Backend, +id: Nat, +source: String, +root: String, +primary: String, +world: M.World()) ->
  {State.archive_current(available, backend, id, source, root, primary, world) == Spec.archive_current(available, backend, id, source, root, primary, world) : M.Decision()}:
  match available:
    case False{}: {==}
    case True{}: {==}

def archive_started(+id: Nat, +value: W.Worktree, +world: M.World()) ->
  {State.archive_started(id, value, world) == Spec.archive_started(id, value, world) : M.Decision()}:
  match value:
    case W.Worktree{source, None{}, status, message, primary, backend}: {==}
    case W.Worktree{+source, Some{+root}, status, message, primary, backend}: archive_current(State.root_unused(id, root, world), backend, id, source, root, primary, world)

def archive_eligible(+allowed: Bool, +id: Nat, +value: W.Worktree, +world: M.World()) ->
  {State.archive_eligible(allowed, id, value, world) == Spec.archive_eligible(allowed, id, value, world) : M.Decision()}:
  match allowed:
    case False{}: {==}
    case True{}: archive_started(id, value, world)

def archive_some(+id: Nat, +value: W.Worktree, +world: M.World()) ->
  {State.archive_value(id, Some{value}, world) == Spec.archive_value(id, Some{value}, world) : M.Decision()}:
  match value:
    case W.Worktree{source, root, W.Creating{}, message, primary, backend}: {==}
    case W.Worktree{source, root, W.CreatingArchived{}, message, primary, backend}: {==}
    case W.Worktree{source, root, W.Ready{}, message, primary, backend}: archive_started(id, W.Worktree{source, root, W.Ready{}, message, primary, backend}, world)
    case W.Worktree{source, root, W.CreateFailed{}, message, primary, backend}: archive_started(id, W.Worktree{source, root, W.CreateFailed{}, message, primary, backend}, world)
    case W.Worktree{source, root, W.Archiving{}, message, primary, backend}: {==}
    case W.Worktree{source, root, W.Archived{}, message, primary, backend}: {==}
    case W.Worktree{source, root, W.ArchiveFailed{}, message, primary, backend}: archive_started(id, W.Worktree{source, root, W.ArchiveFailed{}, message, primary, backend}, world)

def archive_value(+id: Nat, +found: Maybe<&2, W.Worktree>, +world: M.World()) ->
  {State.archive_value(id, found, world) == Spec.archive_value(id, found, world) : M.Decision()}:
  match found:
    case None{}: {==}
    case Some{value}: archive_some(id, value, world)

def failed_for_status(+was_archived: Bool, +id: Nat, +value: W.Worktree, +root: Maybe<&2, String>, +message: String, +task: D.Task, +world: M.World()) ->
  {State.failed_for_status(was_archived, id, value, root, message, task, world) == Spec.failed_for_status(was_archived, id, value, root, message, task, world) : M.Decision()}:
  match was_archived:
    case False{}: {==}
    case True{}:
      archive_some(id, W.Worktree{W.source_root(value), root, W.CreateFailed{}, message, "", W.backend(value)},
        State.store(W.put(id, W.Worktree{W.source_root(value), root, W.CreateFailed{}, message, "", W.backend(value)}, State.registry(world)), world))

def create_failed_found(+found: Maybe<&2, D.Task>, +id: Nat, +value: W.Worktree, +root: Maybe<&2, String>, +message: String, +world: M.World()) ->
  {State.create_failed_found(found, id, value, root, message, world) == Spec.create_failed_found(found, id, value, root, message, world) : M.Decision()}:
  match found:
    case None{}: {==}
    case Some{+task}: failed_for_status(State.archived(D.task_status(task)), id, value, root, message, task, world)

def create_failed(+id: Nat, +value: W.Worktree, +root: Maybe<&2, String>, +message: String, +world: M.World()) ->
  {State.create_failed(id, value, root, message, world) == Spec.create_failed(id, value, root, message, world) : M.Decision()}:
  create_failed_found(State.task(id, world), id, value, root, message, world)

def created_for_status(+was_archived: Bool, +id: Nat, +value: W.Worktree, +root: String, +workspace: D.Workspace,
  +guidance: D.ProjectContext, +task: D.Task, +world: M.World()) ->
  {State.created_for_status(was_archived, id, value, root, workspace, guidance, task, world) == Spec.created_for_status(was_archived, id, value, root, workspace, guidance, task, world) : M.Decision()}:
  match was_archived:
    case True{}: archive_started(id, W.Worktree{W.source_root(value), Some{root}, W.Ready{}, "", State.primary_text(workspace), W.backend(value)}, world)
    case False{}: {==}

def created_success_found(+found: Maybe<&2, D.Task>, +id: Nat, +value: W.Worktree, +root: String, +workspace: D.Workspace, +guidance: D.ProjectContext, +world: M.World()) ->
  {State.created_success_found(found, id, value, root, workspace, guidance, world) == Spec.created_success_found(found, id, value, root, workspace, guidance, world) : M.Decision()}:
  match found:
    case None{}: {==}
    case Some{+task}: created_for_status(State.archived(D.task_status(task)), id, value, root, workspace, guidance, task, world)

def created_success(+id: Nat, +value: W.Worktree, +root: String, +workspace: D.Workspace, +guidance: D.ProjectContext, +world: M.World()) ->
  {State.created_success(id, value, root, workspace, guidance, world) == Spec.created_success(id, value, root, workspace, guidance, world) : M.Decision()}:
  created_success_found(State.task(id, world), id, value, root, workspace, guidance, world)

def created_valid(+allowed: Bool, +id: Nat, +value: W.Worktree, +root: String, +workspace: D.Workspace, +guidance: D.ProjectContext, +world: M.World()) ->
  {State.created_valid(allowed, id, value, root, workspace, guidance, world) == Spec.created_valid(allowed, id, value, root, workspace, guidance, world) : M.Decision()}:
  match allowed:
    case False{}: create_failed(id, value, Some{root}, "Worktree creation returned an invalid workspace or guidance", world)
    case True{}: created_success(id, value, root, workspace, guidance, world)

def created_checked(+found: Maybe<&2, D.Task>, +id: Nat, +value: W.Worktree, +root: String, +workspace: D.Workspace, +guidance: D.ProjectContext, +world: M.World()) ->
  {State.created_checked(found, id, value, root, workspace, guidance, world) == Spec.created_checked(found, id, value, root, workspace, guidance, world) : M.Decision()}:
  match found:
    case None{}: {==}
    case Some{task}: created_valid(State.completed_workspace(root, workspace, task) && Workspace.valid_guidance(guidance) &&
      Workspace.guidance_member(Workspace.primary(workspace), guidance), id, value, root, workspace, guidance, world)

def created_result(+id: Nat, +value: W.Worktree, +ok: Bool, +root: Maybe<&2, String>, +workspace: D.Workspace,
  +guidance: D.ProjectContext, +message: String, +world: M.World()) ->
  {State.created_result(id, value, ok, root, workspace, guidance, message, world) == Spec.created_result(id, value, ok, root, workspace, guidance, message, world) : M.Decision()}:
  match ok root:
    case True{} Some{root}: created_checked(State.task(id, world), id, value, root, workspace, guidance, world)
    case True{} None{}: create_failed(id, value, None{}, "Worktree creation succeeded without a managed root", world)
    case False{} root: create_failed(id, value, root, message, world)

def archive_result(+id: Nat, +value: W.Worktree, +ok: Bool, +root: String, +message: String, +world: M.World()) ->
  {State.archive_result(id, value, ok, root, message, world) == Spec.archive_result(id, value, ok, root, message, world) : M.Decision()}:
  match ok:
    case True{}: {==}
    case False{}: {==}

def created_current(+current: Bool, +id: Nat, +value: W.Worktree, +ok: Bool, +root: Maybe<&2, String>, +workspace: D.Workspace, +guidance: D.ProjectContext, +message: String, +world: M.World()) ->
  {Actual.created_current(current, id, value, ok, root, workspace, guidance, message, world) == Spec.created_current(current, id, value, ok, root, workspace, guidance, message, world) : M.Decision()}:
  match current:
    case False{}: {==}
    case True{}: created_result(id, value, ok, root, workspace, guidance, message, world)

def archived_current(+current: Bool, +id: Nat, +value: W.Worktree, +ok: Bool, +root: String, +message: String, +world: M.World()) ->
  {Actual.archived_current(current, id, value, ok, root, message, world) == Spec.archived_current(current, id, value, ok, root, message, world) : M.Decision()}:
  match current:
    case False{}: {==}
    case True{}: archive_result(id, value, ok, root, message, world)

def created_found(+found: Maybe<&2, W.Worktree>, +id: Nat, +ok: Bool, +root: Maybe<&2, String>, +workspace: D.Workspace,
  +guidance: D.ProjectContext, +message: String, +world: M.World()) ->
  {Actual.created_found(found, id, ok, root, workspace, guidance, message, world) == Spec.created_found(found, id, ok, root, workspace, guidance, message, world) : M.Decision()}:
  match found:
    case None{}: {==}
    case Some{+value}: created_current(State.creation_status(W.status(value)), id, value, ok, root, workspace, guidance, message, world)

def archived_found(+found: Maybe<&2, W.Worktree>, +id: Nat, +ok: Bool, +root: String, +message: String, +world: M.World()) ->
  {Actual.archived_found(found, id, ok, root, message, world) == Spec.archived_found(found, id, ok, root, message, world) : M.Decision()}:
  match found:
    case None{}: {==}
    case Some{+value}: archived_current(State.archive_status(W.status(value)), id, value, ok, root, message, world)

def complete(+completion: W.Completion, +world: M.World()) ->
  {Actual.complete(completion, world) == Spec.complete(completion, world) : M.Decision()}:
  match completion:
    case W.Created{+id, ok, root, workspace, guidance, message}: created_found(W.lookup(id, State.registry(world)), id, ok, root, workspace, guidance, message, world)
    case W.ArchivedResult{+id, ok, root, message}: archived_found(W.lookup(id, State.registry(world)), id, ok, root, message, world)

def retry_archive(+id: Nat, +world: M.World()) ->
  {Actual.retry_archive(id, world) == Spec.retry_archive(id, world) : M.Decision()}:
  archive_value(id, W.lookup(id, State.registry(world)), world)

def drain_contract(+task: D.Task) ->
  {D.task_contract(Tasks.drain(task)) == D.task_contract(task) : D.Contract}:
  match task:
    case D.Task{id, lineage, contract, current, status, history, Nil{}, phase, operations, notified}: {==}
    case D.Task{id, lineage, contract, current, status, history, Con{text, rest}, phase, operations, notified}: {==}

def promote_when_contract(+status: D.Status, +phase: D.Phase, +task: D.Task) ->
  {D.task_contract(Tasks.promote_when(status, phase, task)) == D.task_contract(task) : D.Contract}:
  match status phase:
    case D.Frozen{} D.Idle{}: {==}
    case D.Frozen{} D.Ready{Nil{}}: {==}
    case D.Frozen{} D.Ready{Con{first, rest}}: {==}
    case D.Frozen{} D.ContextPending{ticket, revision, purpose}: {==}
    case D.Frozen{} D.ModelPending{ticket, callable, mode}: {==}
    case D.Frozen{} D.ReasoningPending{ticket, revision}: {==}
    case D.Frozen{} D.HookPending{ticket, plugin, call, pending, remaining}: {==}
    case D.Archived{} D.Idle{}: {==}
    case D.Archived{} D.Ready{Nil{}}: {==}
    case D.Archived{} D.Ready{Con{first, rest}}: {==}
    case D.Archived{} D.ContextPending{ticket, revision, purpose}: {==}
    case D.Archived{} D.ModelPending{ticket, callable, mode}: {==}
    case D.Archived{} D.ReasoningPending{ticket, revision}: {==}
    case D.Archived{} D.HookPending{ticket, plugin, call, pending, remaining}: {==}
    case D.Active{} D.Idle{}: drain_contract(task)
    case D.Active{} D.Ready{Nil{}}: drain_contract(task)
    case D.Active{} D.Ready{Con{first, rest}}: {==}
    case D.Active{} D.ContextPending{ticket, revision, purpose}: {==}
    case D.Active{} D.ModelPending{ticket, callable, mode}: {==}
    case D.Active{} D.ReasoningPending{ticket, revision}: {==}
    case D.Active{} D.HookPending{ticket, plugin, call, pending, remaining}: {==}
    case D.Stopped{} D.Idle{}: drain_contract(task)
    case D.Stopped{} D.Ready{Nil{}}: drain_contract(task)
    case D.Stopped{} D.Ready{Con{first, rest}}: {==}
    case D.Stopped{} D.ContextPending{ticket, revision, purpose}: {==}
    case D.Stopped{} D.ModelPending{ticket, callable, mode}: {==}
    case D.Stopped{} D.ReasoningPending{ticket, revision}: {==}
    case D.Stopped{} D.HookPending{ticket, plugin, call, pending, remaining}: {==}

def promote_contract(+task: D.Task) ->
  {D.task_contract(Tasks.promote(task)) == D.task_contract(task) : D.Contract}:
  promote_when_contract(D.task_status(task), D.task_phase(task), task)

def selected_completion(+primary: String, guidance: D.ProjectContext, +task: D.Task) -> D.Task:
  +selected = D.with_contract(State.selected_contract(primary, D.task_contract(task)), task)
  +configured = D.append_context(D.TaskSettings{D.task_context(selected), D.task_profile(selected), D.task_reasoning(selected)},
    D.selected_project(guidance, selected))
  D.with_status(D.Active{}, configured)

def selected_completion_contract(+primary: String, +guidance: D.ProjectContext, +task: D.Task) ->
  {D.task_contract(selected_completion(primary, guidance, task)) == State.selected_contract(primary, D.task_contract(task)) : D.Contract}:
  match task:
    case D.Task{id, lineage, contract, current, status, history, queued, phase, operations, notified}: {==}

def completed_contract(+primary: String, +guidance: D.ProjectContext, +task: D.Task) ->
  {D.task_contract(State.completed_task(primary, guidance, task)) == State.selected_contract(primary, D.task_contract(task)) : D.Contract}:
  Equal.trans(D.Contract, D.task_contract(State.completed_task(primary, guidance, task)),
    D.task_contract(selected_completion(primary, guidance, task)), State.selected_contract(primary, D.task_contract(task)),
    promote_contract(selected_completion(primary, guidance, task)), selected_completion_contract(primary, guidance, task))

def failed_status(+message: String, +task: D.Task) ->
  {D.task_status(State.failure_task(message, task)) == D.Stopped{} : D.Status}:
  match task:
    case D.Task{id, lineage, contract, current, status, history, queued, phase, operations, notified}: {==}

def normalization_contract(+primary: String, +task: D.Task) ->
  {D.task_contract(State.normalize_task(Some{primary}, task)) == State.selected_contract(primary, D.task_contract(task)) : D.Contract}:
  match task:
    case D.Task{id, lineage, contract, current, status, history, queued, phase, operations, notified}: {==}
