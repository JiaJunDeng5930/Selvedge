import Base
import ../../features/remote/MODEL.bend as Remote
import ../../features/compaction/MODEL.bend as Compaction
import ../DOMAIN.bend as D
import ../../features/board/MODEL.bend as Board
import ../workspace/WORKSPACE.bend as Workspace
import ../../features/board/resolution.bend as Resolution
import ../../features/chatgpt/MODEL.bend as ChatGPT
import ../../features/task_graph/MODEL.bend as TaskGraph

type GraphNode is Data:
  GraphExisting{key: String, task: Nat}
  GraphSpawn{key: String, profile: D.Profile, reasoning: String, message: String, selection: Workspace.Selection}

# These are already resolved feature operations. External callers cannot bypass
# the command resolver by constructing them through the wire protocol.
type Operation is Data:
  RemoteChange{change: Remote.Change}
  ChatGPTChange{change: ChatGPT.Change}
  BoardChange{change: Resolution.Change}
  StartCard{id: Nat, card: Board.Card, now: U32, profile: D.Profile, reasoning: String, message: String, selection: Workspace.Selection}
  InstallGraph{id: Nat, declaration: TaskGraph.Declaration, nodes: +List<GraphNode>}
  DeleteGraph{id: Nat}

type ResolvedEvent is Data:
  CompactionResult{completion: Compaction.Completion}
  ChatGPTResult{change: ChatGPT.Change}
  BoardTextResult{id: Nat, card: Board.Card, outcome: Board.Outcome, retitle: Bool}
