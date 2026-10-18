import Base
import ./MODEL.bend as F
import ../../features/board/MODEL.bend as Board
import ../../bendlib/component.bend as C
import ../../features/chatgpt/MODEL.bend as ChatGPT
import ../../features/compaction/MODEL.bend as Compaction
import ../../features/task_graph/MODEL.bend as TaskGraph
import ./CONTRACT.bend as Contract
import ./graph-state.bend as TaskGraphState
import ../MODEL.bend as M
import ../DOMAIN.bend as D
import ../../features/work/MODEL.bend as Work
import ./work-state.bend as WorkState

def board_written(+value: Board.State, state: F.State()) ->
  {F.board(F.with_board(value, state)) == value : Board.State}:
  match state:
    case C.Frame{previous, rest}: {==}

def board_frame(value: Board.State, state: F.State()) ->
  {F.modules(F.with_board(value, state)) == F.modules(state) : F.Modules()}:
  C.replace_frame(Board.State, F.Modules(), value, state)

def task_graph_written(+value: TaskGraph.State, state: F.State()) ->
  {F.task_graph(F.with_task_graph(value, state)) == value : TaskGraph.State}:
  match state:
    case C.Frame{board, C.Frame{chatgpt, C.Frame{previous, C.Frame{compaction, rest}}}}: {==}

def task_graph_board_frame(value: TaskGraph.State, +state: F.State()) ->
  {F.board(F.with_task_graph(value, state)) == F.board(state) : Board.State}:
  match state:
    case C.Frame{board, C.Frame{chatgpt, C.Frame{previous, C.Frame{compaction, rest}}}}: {==}

def task_graph_chatgpt_frame(value: TaskGraph.State, +state: F.State()) ->
  {F.chatgpt(F.with_task_graph(value, state)) == F.chatgpt(state) : ChatGPT.State}:
  match state:
    case C.Frame{board, C.Frame{chatgpt, C.Frame{previous, C.Frame{compaction, rest}}}}: {==}

def task_graph_compaction_frame(value: TaskGraph.State, +state: F.State()) ->
  {F.compaction(F.with_task_graph(value, state)) == F.compaction(state) : Compaction.State}:
  match state:
    case C.Frame{board, C.Frame{chatgpt, C.Frame{previous, C.Frame{compaction, rest}}}}: {==}

def task_graph_rest_frame(value: TaskGraph.State, +state: F.State()) ->
  {F.rest(F.with_task_graph(value, state)) == F.rest(state) : F.Rest()}:
  match state:
    case C.Frame{board, C.Frame{chatgpt, C.Frame{previous, C.Frame{compaction, rest}}}}: {==}

def task_graph_work_frame(value: TaskGraph.State, +state: F.State()) ->
  {F.work(F.with_task_graph(value, state)) == F.work(state) : Work.State}:
  match state:
    case C.Frame{board, C.Frame{chatgpt, C.Frame{previous, C.Frame{compaction, rest}}}}: {==}

def task_graph_core_frame(value: TaskGraph.State, +world: M.World()) ->
  {C.local(D.State, F.State(), TaskGraphState.store(value, world)) == C.local(D.State, F.State(), world) : D.State}:
  match world:
    case C.Frame{core, features}: {==}

def task_graph_storage() -> Contract.TaskGraphStorage:
  Contract.TaskGraphStorage{task_graph_written, task_graph_board_frame, task_graph_chatgpt_frame, task_graph_compaction_frame, task_graph_work_frame, task_graph_rest_frame, task_graph_core_frame}

def work_written(+value: Work.State, state: F.State()) ->
  {F.work(F.with_work(value, state)) == value : Work.State}:
  match state:
    case C.Frame{board, C.Frame{chatgpt, C.Frame{graph, C.Frame{compaction, C.Frame{previous, rest}}}}}: {==}

def work_board_frame(value: Work.State, +state: F.State()) ->
  {F.board(F.with_work(value, state)) == F.board(state) : Board.State}:
  match state:
    case C.Frame{board, C.Frame{chatgpt, C.Frame{graph, C.Frame{compaction, C.Frame{previous, rest}}}}}: {==}

def work_chatgpt_frame(value: Work.State, +state: F.State()) ->
  {F.chatgpt(F.with_work(value, state)) == F.chatgpt(state) : ChatGPT.State}:
  match state:
    case C.Frame{board, C.Frame{chatgpt, C.Frame{graph, C.Frame{compaction, C.Frame{previous, rest}}}}}: {==}

def work_task_graph_frame(value: Work.State, +state: F.State()) ->
  {F.task_graph(F.with_work(value, state)) == F.task_graph(state) : TaskGraph.State}:
  match state:
    case C.Frame{board, C.Frame{chatgpt, C.Frame{graph, C.Frame{compaction, C.Frame{previous, rest}}}}}: {==}

def work_compaction_frame(value: Work.State, +state: F.State()) ->
  {F.compaction(F.with_work(value, state)) == F.compaction(state) : Compaction.State}:
  match state:
    case C.Frame{board, C.Frame{chatgpt, C.Frame{graph, C.Frame{compaction, C.Frame{previous, rest}}}}}: {==}

def work_rest_frame(value: Work.State, +state: F.State()) ->
  {F.rest(F.with_work(value, state)) == F.rest(state) : F.Rest()}:
  match state:
    case C.Frame{board, C.Frame{chatgpt, C.Frame{graph, C.Frame{compaction, C.Frame{previous, rest}}}}}: {==}

def work_core_frame(value: Work.State, +world: M.World()) ->
  {C.local(D.State, F.State(), WorkState.store(value, world)) == C.local(D.State, F.State(), world) : D.State}:
  match world:
    case C.Frame{core, features}: {==}

def board_work_frame(value: Board.State, +state: F.State()) ->
  {F.work(F.with_board(value, state)) == F.work(state) : Work.State}:
  match state:
    case C.Frame{board, C.Frame{chatgpt, C.Frame{graph, C.Frame{compaction, C.Frame{previous, rest}}}}}: {==}

def chatgpt_work_frame(value: ChatGPT.State, +state: F.State()) ->
  {F.work(F.with_chatgpt(value, state)) == F.work(state) : Work.State}:
  match state:
    case C.Frame{board, C.Frame{chatgpt, C.Frame{graph, C.Frame{compaction, C.Frame{previous, rest}}}}}: {==}

def compaction_work_frame(value: Compaction.State, +state: F.State()) ->
  {F.work(F.with_compaction(value, state)) == F.work(state) : Work.State}:
  match state:
    case C.Frame{board, C.Frame{chatgpt, C.Frame{graph, C.Frame{compaction, C.Frame{previous, rest}}}}}: {==}

def work_storage() -> Contract.WorkStorage:
  Contract.WorkStorage{work_written, work_board_frame, work_chatgpt_frame, work_task_graph_frame, work_compaction_frame, work_rest_frame, work_core_frame,
    board_work_frame, chatgpt_work_frame, compaction_work_frame}
