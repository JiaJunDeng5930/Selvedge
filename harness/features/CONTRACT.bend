import Base
import ../../features/compaction/CONTRACT.bend as Compaction
import ../../features/board/CONTRACT.bend as Board
import ../../features/chatgpt/CONTRACT.bend as ChatGPT
import ../../features/task_graph/CONTRACT.bend as TaskGraph
import ../../features/worktree/CONTRACT.bend as Worktree
import ./MODEL.bend as F
import ./graph-state.bend as TaskGraphState
import ./worktree-state.bend as WorktreeState
import ../MODEL.bend as M
import ../DOMAIN.bend as D
import ../../bendlib/component.bend as C
import ../../bendlib/association-map.bend as Finite
import ../workspace/WORKSPACE.bend as Workspace
import ../../features/board/MODEL.bend as BoardModel
import ../../features/chatgpt/MODEL.bend as ChatGPTModel
import ../../features/compaction/MODEL.bend as CompactionModel
import ../../features/task_graph/MODEL.bend as TaskGraphModel
import ../../features/worktree/MODEL.bend as WorktreeModel

type TaskGraphStorage is Type:
  TaskGraphStorage{
    written: @+value:TaskGraphModel.State -> @state:F.State() ->
      {F.task_graph(F.with_task_graph(value, state)) == value : TaskGraphModel.State},
    board: @value:TaskGraphModel.State -> @+state:F.State() ->
      {F.board(F.with_task_graph(value, state)) == F.board(state) : BoardModel.State},
    chatgpt: @value:TaskGraphModel.State -> @+state:F.State() ->
      {F.chatgpt(F.with_task_graph(value, state)) == F.chatgpt(state) : ChatGPTModel.State},
    compaction: @value:TaskGraphModel.State -> @+state:F.State() ->
      {F.compaction(F.with_task_graph(value, state)) == F.compaction(state) : CompactionModel.State},
    worktree: @value:TaskGraphModel.State -> @+state:F.State() ->
      {F.worktree(F.with_task_graph(value, state)) == F.worktree(state) : WorktreeModel.State},
    remainder: @value:TaskGraphModel.State -> @+state:F.State() ->
      {F.rest(F.with_task_graph(value, state)) == F.rest(state) : F.Rest()},
    core: @value:TaskGraphModel.State -> @+world:M.World() ->
      {C.local(D.State, F.State(), TaskGraphState.store(value, world)) == C.local(D.State, F.State(), world) : D.State}
  }

type WorktreeStorage is Type:
  WorktreeStorage{
    written: @+value:WorktreeModel.State -> @state:F.State() ->
      {F.worktree(F.with_worktree(value, state)) == value : WorktreeModel.State},
    board: @value:WorktreeModel.State -> @+state:F.State() ->
      {F.board(F.with_worktree(value, state)) == F.board(state) : BoardModel.State},
    chatgpt: @value:WorktreeModel.State -> @+state:F.State() ->
      {F.chatgpt(F.with_worktree(value, state)) == F.chatgpt(state) : ChatGPTModel.State},
    task_graph: @value:WorktreeModel.State -> @+state:F.State() ->
      {F.task_graph(F.with_worktree(value, state)) == F.task_graph(state) : TaskGraphModel.State},
    compaction: @value:WorktreeModel.State -> @+state:F.State() ->
      {F.compaction(F.with_worktree(value, state)) == F.compaction(state) : CompactionModel.State},
    remainder: @value:WorktreeModel.State -> @+state:F.State() ->
      {F.rest(F.with_worktree(value, state)) == F.rest(state) : F.Rest()},
    core: @value:WorktreeModel.State -> @+world:M.World() ->
      {C.local(D.State, F.State(), WorktreeState.store(value, world)) == C.local(D.State, F.State(), world) : D.State}
  }

type WorktreeInitialization is Type:
  WorktreeInitialization{
    completed_contract: @+primary:String -> @+guidance:D.ProjectContext -> @+task:D.Task ->
      {D.task_contract(WorktreeState.completed_task(primary, guidance, task)) == WorktreeState.selected_contract(primary, D.task_contract(task)) : D.Contract},
    normalization_contract: @+primary:String -> @+task:D.Task ->
      {D.task_contract(WorktreeState.normalize_task(Some{primary}, task)) == WorktreeState.selected_contract(primary, D.task_contract(task)) : D.Contract},
    failed_execution: @source:String -> @root:Maybe<&2, String> -> @message:String -> @primary:String ->
      {WorktreeState.execution_available(Some{WorktreeModel.Worktree{source, root, WorktreeModel.CreateFailed{}, message, primary}}) == False{} : Bool},
    creating_execution: @source:String -> @message:String ->
      {WorktreeState.execution_available(Some{WorktreeModel.Worktree{source, None{}, WorktreeModel.Creating{}, message, ""}}) == True{} : Bool},
    failure_status: @+message:String -> @+task:D.Task ->
      {D.task_status(WorktreeState.failure_task(message, task)) == D.Stopped{} : D.Status}
  }

def ready_worktree_status(status: WorktreeModel.Status) -> Bool:
  match status:
    case WorktreeModel.Ready{}: True{}
    case _: False{}

def inherited_inside(primary: String, found: Maybe<&2, Finite.Entry(WorktreeModel.Worktree)>) -> Bool:
  match found:
    case None{}: True{}
    case Some{(owner, WorktreeModel.Worktree{source, Some{root}, status, message, target})}: WorktreeState.path_inside(root, primary)
    case _: False{}

type WorktreeSharing is Type:
  WorktreeSharing{
    own_priority: @+id:Nat -> @+value:WorktreeModel.Worktree -> @+world:M.World() ->
      @observed:{WorktreeModel.lookup(id, WorktreeState.registry(world)) == Some{value} : Maybe<&2, WorktreeModel.Worktree>} ->
      {WorktreeState.effective(id, world) == Some{(id, value)} : Maybe<&2, Finite.Entry(WorktreeModel.Worktree)>},
    inherited_lookup: @id:Nat -> @+task:D.Task -> @+entries:+List<Finite.Entry(WorktreeModel.Worktree)> ->
      {WorktreeState.effective_found(None{}, id, Some{task}, entries) == WorktreeState.find_effective(entries, WorktreeState.frozen_primary(task)) : Maybe<&2, Finite.Entry(WorktreeModel.Worktree)>},
    chosen_owner: @+owner:Nat -> @+value:WorktreeModel.Worktree -> @rest:Maybe<&2, Finite.Entry(WorktreeModel.Worktree)> ->
      {WorktreeState.choose_effective(True{}, owner, value, rest) == Some{(owner, value)} : Maybe<&2, Finite.Entry(WorktreeModel.Worktree)>},
    skipped_owner: @owner:Nat -> @value:WorktreeModel.Worktree -> @+rest:Maybe<&2, Finite.Entry(WorktreeModel.Worktree)> ->
      {WorktreeState.choose_effective(False{}, owner, value, rest) == rest : Maybe<&2, Finite.Entry(WorktreeModel.Worktree)>},
    borrowed_root: @+primary:String -> @source:String -> @+root:String -> @status:WorktreeModel.Status -> @message:String -> @target:String ->
      {WorktreeState.borrowed_candidate(primary, WorktreeModel.Worktree{source, Some{root}, status, message, target}) == WorktreeState.path_inside(root, primary) : Bool},
    borrowed_missing_root: @primary:String -> @source:String -> @status:WorktreeModel.Status -> @message:String -> @target:String ->
      {WorktreeState.borrowed_candidate(primary, WorktreeModel.Worktree{source, None{}, status, message, target}) == False{} : Bool},
    inherited_inside: @+entries:+List<Finite.Entry(WorktreeModel.Worktree)> -> @+primary:String ->
      {inherited_inside(primary, WorktreeState.find_effective(entries, primary)) == True{} : Bool},
    archived_ignored: @owner:Nat -> @root:String -> @task:D.Task ->
      {WorktreeState.root_user(D.Archived{}, owner, root, task) == False{} : Bool},
    live_root_user: @+status:D.Status -> @+owner:Nat -> @+root:String -> @+task:D.Task ->
      @live:{WorktreeState.archived(status) == False{} : Bool} ->
      {WorktreeState.root_user(status, owner, root, task) ==
        (Bool.not(Nat.is_eq(owner, D.task_id(task))) && WorktreeState.any_root_inside(Workspace.roots(Workspace.workspace(D.contract_context(D.task_contract(task)))), root)) : Bool},
    archive_root: @source:String -> @+root:String -> @status:WorktreeModel.Status -> @message:String -> @primary:String -> @+owner:Nat -> @+world:M.World() ->
      {WorktreeState.archive_available(Some{WorktreeModel.Worktree{source, Some{root}, status, message, primary}}, owner, world) ==
        Bool.not(WorktreeState.uses_root(owner, root, D.state_tasks(C.local(D.State, F.State(), world)))) : Bool},
    archive_missing: @owner:Nat -> @world:M.World() ->
      {WorktreeState.archive_available(None{}, owner, world) == True{} : Bool},
    blocked_root: @+owner:Nat -> @+root:String -> @+world:M.World() ->
      @blocked:{WorktreeState.uses_root(owner, root, D.state_tasks(C.local(D.State, F.State(), world))) == True{} : Bool} ->
      {WorktreeState.root_unused(owner, root, world) == False{} : Bool},
    workspace_ready: @roots:+List<String> -> @source:String -> @root:String -> @message:String -> @primary:String ->
      {WorktreeState.workspace_resource_available(roots, WorktreeModel.Worktree{source, Some{root}, WorktreeModel.Ready{}, message, primary}) == True{} : Bool},
    workspace_protected: @+roots:+List<String> -> @source:String -> @+root:String -> @+status:WorktreeModel.Status -> @message:String -> @primary:String ->
      @nonready:{ready_worktree_status(status) == False{} : Bool} ->
      {WorktreeState.workspace_resource_available(roots, WorktreeModel.Worktree{source, Some{root}, status, message, primary}) == Bool.not(WorktreeState.any_root_inside(roots, root)) : Bool},
    unowned_archive: @id:Nat -> @+decision:M.Decision() ->
      {WorktreeState.archive_found(id, None{}, decision) == decision : M.Decision()}
  }

# Feature-specific guarantees are assembled without extending every consumer
# of the root harness interface.
type Features is Type:
  Features{board: Board.BoardBoundary, chatgpt: ChatGPT.Boundary, task_graph: TaskGraph.RegistryBoundary, task_graph_storage: TaskGraphStorage, compaction: Compaction.Boundary, worktree_storage: WorktreeStorage, worktree_registry: Worktree.Boundary, worktree_initialization: WorktreeInitialization, worktree_sharing: WorktreeSharing}
