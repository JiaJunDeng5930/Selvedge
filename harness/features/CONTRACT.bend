import Base
import ../../features/compaction/CONTRACT.bend as Compaction
import ../../features/board/CONTRACT.bend as Board
import ../../features/chatgpt/CONTRACT.bend as ChatGPT
import ../../features/task_graph/CONTRACT.bend as TaskGraph
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
    remainder: @value:TaskGraphModel.State -> @+state:F.State() ->
      {F.rest(F.with_task_graph(value, state)) == F.rest(state) : F.Rest()},
    core: @value:TaskGraphModel.State -> @+world:M.World() ->
      {C.local(D.State, F.State(), TaskGraphState.store(value, world)) == C.local(D.State, F.State(), world) : D.State}
  }

# Feature-specific guarantees are assembled without extending every consumer
# of the root harness interface.
type Features is Type:
  Features{board: Board.BoardBoundary, chatgpt: ChatGPT.Boundary, task_graph: TaskGraph.RegistryBoundary, task_graph_storage: TaskGraphStorage, compaction: Compaction.Boundary}
