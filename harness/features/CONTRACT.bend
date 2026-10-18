import Base
import ../../features/compaction/CONTRACT.bend as Compaction
import ../../features/board/CONTRACT.bend as Board
import ../../features/chatgpt/CONTRACT.bend as ChatGPT
import ../../features/task_graph/CONTRACT.bend as TaskGraph
import ../../features/work/CONTRACT.bend as Work
import ../../features/work/MODEL.bend as WorkModel
import ./work-state.bend as WorkState
import ./MODEL.bend as F
import ./graph-state.bend as TaskGraphState
import ../MODEL.bend as M
import ../DOMAIN.bend as D
import ../../bendlib/component.bend as C
import ../../features/board/MODEL.bend as BoardModel
import ../../features/chatgpt/MODEL.bend as ChatGPTModel
import ../../features/compaction/MODEL.bend as CompactionModel
import ../../features/task_graph/MODEL.bend as TaskGraphModel

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
    work: @value:TaskGraphModel.State -> @+state:F.State() ->
      {F.work(F.with_task_graph(value, state)) == F.work(state) : WorkModel.State},
    remainder: @value:TaskGraphModel.State -> @+state:F.State() ->
      {F.rest(F.with_task_graph(value, state)) == F.rest(state) : F.Rest()},
    core: @value:TaskGraphModel.State -> @+world:M.World() ->
      {C.local(D.State, F.State(), TaskGraphState.store(value, world)) == C.local(D.State, F.State(), world) : D.State}
  }

type WorkStorage is Type:
  WorkStorage{
    written: @+value:WorkModel.State -> @state:F.State() ->
      {F.work(F.with_work(value, state)) == value : WorkModel.State},
    board: @value:WorkModel.State -> @+state:F.State() ->
      {F.board(F.with_work(value, state)) == F.board(state) : BoardModel.State},
    chatgpt: @value:WorkModel.State -> @+state:F.State() ->
      {F.chatgpt(F.with_work(value, state)) == F.chatgpt(state) : ChatGPTModel.State},
    task_graph: @value:WorkModel.State -> @+state:F.State() ->
      {F.task_graph(F.with_work(value, state)) == F.task_graph(state) : TaskGraphModel.State},
    compaction: @value:WorkModel.State -> @+state:F.State() ->
      {F.compaction(F.with_work(value, state)) == F.compaction(state) : CompactionModel.State},
    remainder: @value:WorkModel.State -> @+state:F.State() ->
      {F.rest(F.with_work(value, state)) == F.rest(state) : F.Rest()},
    core: @value:WorkModel.State -> @+world:M.World() ->
      {C.local(D.State, F.State(), WorkState.store(value, world)) == C.local(D.State, F.State(), world) : D.State},
    board_preserves: @value:BoardModel.State -> @+state:F.State() ->
      {F.work(F.with_board(value, state)) == F.work(state) : WorkModel.State},
    chatgpt_preserves: @value:ChatGPTModel.State -> @+state:F.State() ->
      {F.work(F.with_chatgpt(value, state)) == F.work(state) : WorkModel.State},
    compaction_preserves: @value:CompactionModel.State -> @+state:F.State() ->
      {F.work(F.with_compaction(value, state)) == F.work(state) : WorkModel.State}}

# Feature-specific guarantees are assembled without extending every consumer
# of the root harness interface.
type Features is Type:
  Features{board: Board.BoardBoundary, chatgpt: ChatGPT.Boundary, task_graph: TaskGraph.RegistryBoundary,
    task_graph_storage: TaskGraphStorage, compaction: Compaction.Boundary, work: Work.Boundary, work_storage: WorkStorage}
