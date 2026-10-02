import Base
import ./domain.bend as D
import ../BOARD.bend as Board
import ../WORKSPACE.bend as Workspace
import ./board-resolution.bend as Resolution
import ../CHATGPT.bend as ChatGPT

# These are already resolved feature operations. External callers cannot bypass
# the command resolver by constructing them through the wire protocol.
type Operation is Data:
  ChatGPTChange{change: ChatGPT.Change}
  BoardChange{change: Resolution.Change}
  StartCard{id: Nat, card: Board.Card, now: U32, profile: D.Profile, reasoning: String, message: String, selection: Workspace.Selection}

type ResolvedEvent is Data:
  ChatGPTResult{change: ChatGPT.Change}
  BoardTextResult{id: Nat, card: Board.Card, outcome: Board.Outcome, retitle: Bool}
