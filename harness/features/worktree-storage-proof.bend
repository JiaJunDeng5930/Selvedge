import Base
import ./MODEL.bend as F
import ./CONTRACT.bend as Contract
import ./worktree-state.bend as State
import ../../features/worktree/MODEL.bend as W
import ../../features/board/MODEL.bend as Board
import ../../features/chatgpt/MODEL.bend as ChatGPT
import ../../features/task_graph/MODEL.bend as TaskGraph
import ../../features/compaction/MODEL.bend as Compaction
import ../../features/remote/MODEL.bend as Remote
import ../../bendlib/component.bend as C
import ../MODEL.bend as M
import ../DOMAIN.bend as D

def written(+value: W.State, state: F.State()) ->
  {F.worktree(F.with_worktree(value, state)) == value : W.State}:
  match state:
    case C.Frame{board, C.Frame{chatgpt, C.Frame{graph, C.Frame{compaction, C.Frame{previous, rest}}}}}: {==}

def board_frame(value: W.State, +state: F.State()) ->
  {F.board(F.with_worktree(value, state)) == F.board(state) : Board.State}:
  match state:
    case C.Frame{board, C.Frame{chatgpt, C.Frame{graph, C.Frame{compaction, C.Frame{previous, rest}}}}}: {==}

def chatgpt_frame(value: W.State, +state: F.State()) ->
  {F.chatgpt(F.with_worktree(value, state)) == F.chatgpt(state) : ChatGPT.State}:
  match state:
    case C.Frame{board, C.Frame{chatgpt, C.Frame{graph, C.Frame{compaction, C.Frame{previous, rest}}}}}: {==}

def task_graph_frame(value: W.State, +state: F.State()) ->
  {F.task_graph(F.with_worktree(value, state)) == F.task_graph(state) : TaskGraph.State}:
  match state:
    case C.Frame{board, C.Frame{chatgpt, C.Frame{graph, C.Frame{compaction, C.Frame{previous, rest}}}}}: {==}

def compaction_frame(value: W.State, +state: F.State()) ->
  {F.compaction(F.with_worktree(value, state)) == F.compaction(state) : Compaction.State}:
  match state:
    case C.Frame{board, C.Frame{chatgpt, C.Frame{graph, C.Frame{compaction, C.Frame{previous, rest}}}}}: {==}

def rest_frame(value: W.State, +state: F.State()) ->
  {F.rest(F.with_worktree(value, state)) == F.rest(state) : F.Rest()}:
  match state:
    case C.Frame{board, C.Frame{chatgpt, C.Frame{graph, C.Frame{compaction, C.Frame{previous, rest}}}}}: {==}

def remote_frame(value: W.State, +state: F.State()) ->
  {F.remote(F.with_worktree(value, state)) == F.remote(state) : Remote.State}:
  match state:
    case C.Frame{board, C.Frame{chatgpt, C.Frame{graph, C.Frame{compaction, C.Frame{previous, rest}}}}}: {==}

def core_frame(value: W.State, +world: M.World()) ->
  {C.local(D.State, F.State(), State.store(value, world)) == C.local(D.State, F.State(), world) : D.State}:
  match world:
    case C.Frame{core, features}: {==}

def worktree_storage() -> Contract.WorktreeStorage:
  Contract.WorktreeStorage{written, board_frame, chatgpt_frame, task_graph_frame, compaction_frame, remote_frame, rest_frame, core_frame}
