import Base
import ../DOMAIN.bend as D
import ../MODEL.bend as M
import ../workspace/WORKSPACE.bend as Workspace
import ./operations.bend as O
import ../../features/board/SPEC.bend as Board
import ../../features/board/STATE.bend as State
import ../../features/chatgpt/SPEC.bend as ChatGPT
import ../../features/chatgpt/STATE.bend as ChatGPTState

# The caller supplies the independent task-creation specification. The
# executable assembler supplies its implementation to feature-execution.
def meaning(spawn: D.Profile -> String -> String -> Workspace.Selection -> @+world:M.World() -> M.Decision(), operation: O.Operation, +world: M.World()) -> M.Decision():
  match operation:
    case O.ChatGPTChange{change}: ChatGPTState.embed(ChatGPT.meaning(change, ChatGPTState.registry(world)), world)
    case O.BoardChange{change}: Board.change(change, world)
    case O.StartCard{id, card, now, profile, reasoning, message, selection}:
      Board.started(id, State.task_id(world), card, now, spawn(profile, reasoning, message, selection, world))

def event(event: O.ResolvedEvent, +world: M.World()) -> M.Decision():
  match event:
    case O.ChatGPTResult{change}: ChatGPTState.embed(ChatGPT.meaning(change, ChatGPTState.registry(world)), world)
    case O.BoardTextResult{id, card, outcome, retitle}: Board.completed(id, card, outcome, retitle, world)
