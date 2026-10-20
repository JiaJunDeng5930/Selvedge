import Base
import ../../features/titles/MODEL.bend as Titles
import ../../harness/conversation/TITLE.bend as Title
import ../../features/remote/MODEL.bend as Remote
import ../../features/worktree/MODEL.bend as Worktree
import ../../features/compaction/MODEL.bend as Compaction
import ../DOMAIN.bend as D
import ../../features/board/MODEL.bend as Board
import ../workspace/WORKSPACE.bend as Workspace
import ../../features/board/resolution.bend as Resolution
import ../../features/chatgpt/MODEL.bend as ChatGPT
import ../../features/task_graph/MODEL.bend as TaskGraph
import ../../features/work/MODEL.bend as Work

type GraphNode is Data:
  GraphExisting{key: String, task: Nat}
  GraphSpawn{key: String, profile: D.Profile, reasoning: String, message: D.UserContent, selection: Workspace.Selection}

# These are already resolved feature operations. External callers cannot bypass
# the command resolver by constructing them through the wire protocol.
type Operation is Data:
  WorkChange{change: Work.Change}
  StartWorkTask{work: Nat, profile: D.Profile, reasoning: String, message: D.UserContent, selection: Workspace.Selection}
  StartWorkWorktree{work: Nat, profile: D.Profile, reasoning: String, message: D.UserContent, selection: Workspace.Selection}
  ConfigureTitles{prompts: Title.Prompts}
  RemoteChange{change: Remote.Change}
  StartWorktree{profile: D.Profile, reasoning: String, message: D.UserContent, selection: Workspace.Selection}
  RetryWorktreeArchive{task_id: Nat}
  ChatGPTChange{change: ChatGPT.Change}
  BoardChange{change: Resolution.Change}
  StartCard{id: Nat, card: Board.Card, now: U32, profile: D.Profile, reasoning: String, message: D.UserContent, selection: Workspace.Selection}
  InstallGraph{id: Nat, work: Maybe<&2, Nat>, declaration: TaskGraph.Declaration, nodes: +List<GraphNode>}
  DeleteGraph{id: Nat}

type ResolvedEvent is Data:
  TitleResult{completion: Titles.Completion}
  WorktreeResult{completion: Worktree.Completion}
  CompactionResult{completion: Compaction.Completion}
  ChatGPTResult{change: ChatGPT.Change}
  BoardTextResult{id: Nat, card: Board.Card, outcome: Board.Outcome, retitle: Bool}
