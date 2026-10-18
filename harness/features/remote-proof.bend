import Base
import ./MODEL.bend as F
import ./remote.bend as State
import ../../features/remote/MODEL.bend as R
import ../../features/remote/PROGRAM.bend as Remote
import ../../features/board/MODEL.bend as Board
import ../../features/chatgpt/MODEL.bend as ChatGPT
import ../../features/task_graph/MODEL.bend as Graph
import ../../features/compaction/MODEL.bend as Compaction
import ../../features/worktree/MODEL.bend as Worktree
import ../../features/work/MODEL.bend as Work
import ../../bendlib/component.bend as C
import ../../bendlib/json.bend as J
import ../MODEL.bend as M
import ../DOMAIN.bend as D
import ../protocol/COMMIT.bend as Commit

# Local authority writes preserve every other feature and the task machine.
def written(+value: R.State, state: F.State()) ->
  {F.remote(F.with_remote(value, state)) == value : R.State}:
  match state:
    case C.Frame{board, C.Frame{chatgpt, C.Frame{graph, C.Frame{compaction, C.Frame{worktree, C.Frame{previous, rest}}}}}}: {==}

def frame(value: R.State, +state: F.State()) ->
  {(F.board(F.with_remote(value, state)), (F.chatgpt(F.with_remote(value, state)),
    (F.task_graph(F.with_remote(value, state)), (F.compaction(F.with_remote(value, state)),
      (F.worktree(F.with_remote(value, state)), (F.work(F.with_remote(value, state)), F.rest(F.with_remote(value, state)))))))) ==
   (F.board(state), (F.chatgpt(state), (F.task_graph(state), (F.compaction(state), (F.worktree(state), (F.work(state), F.rest(state))))))) :
    Board.State & (ChatGPT.State & (Graph.State & (Compaction.State & (Worktree.State & (Work.State & F.Rest())))))}:
  match state:
    case C.Frame{board, C.Frame{chatgpt, C.Frame{graph, C.Frame{compaction, C.Frame{worktree, C.Frame{previous, rest}}}}}}: {==}

def core(value: R.State, +world: M.World()) ->
  {C.local(D.State, F.State(), State.store(value, world)) == C.local(D.State, F.State(), world) : D.State}:
  match world:
    case C.Frame{tasks, features}: {==}

# Replay and rejection cannot dispatch a model, tool or scheduler action.
def replay(~schedule: Bool -> @+decision:M.Decision() -> M.Decision(), +reply: J.Json,
  request: R.Request, command: M.Command, environment: Maybe<&2, D.Environment>, +world: M.World()) ->
  {Commit.remote_authorized(~schedule, R.Replay{reply}, request, command, environment, world) ==
    C.Decision{world, reply, Nil{}} : M.Decision()}:
  {==}

def refusal(~schedule: Bool -> @+decision:M.Decision() -> M.Decision(), +code: String, +reason: String,
  request: R.Request, command: M.Command, environment: Maybe<&2, D.Environment>, +world: M.World()) ->
  {Commit.remote_authorized(~schedule, R.Denied{code, reason}, request, command, environment, world) ==
    C.Decision{world, D.failure(code, reason), Nil{}} : M.Decision()}:
  {==}

# The reply and ordered effects stay attached to the same world that receives
# its receipt. The outer native commit validates the entire decision together.
def recorded(+request: R.Request, +world: M.World(), +reply: J.Json, +effects: +List<M.Effect()>, previous: M.World()) ->
  {Commit.remote_recorded(True{}, request, C.Decision{world, reply, effects}, previous) ==
    C.Decision{State.store(Remote.remember(request, reply, State.registry(world)), world), reply, effects} : M.Decision()}:
  {==}
