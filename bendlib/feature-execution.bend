import Base
import ./domain.bend as D
import ../MODEL.bend as M
import ../WORKSPACE.bend as Workspace
import ./feature-operations.bend as O
import ./board.bend as Board
import ./board-state.bend as State
import ./chatgpt.bend as ChatGPT
import ./chatgpt-state.bend as ChatGPTState

def realize(spawn: D.Profile -> String -> String -> Workspace.Selection -> M.World() -> M.Decision(), operation: O.Operation, +world: M.World()) -> M.Decision():
  match operation:
    case O.ChatGPTChange{change}: ChatGPTState.embed(ChatGPT.realize(change, ChatGPTState.registry(world)), world)
    case O.BoardChange{change}: Board.change(change, world)
    case O.StartCard{id, card, now, profile, reasoning, message, selection}:
      Board.started(id, State.task_id(world), card, now, spawn(profile, reasoning, message, selection, world))

def event(event: O.ResolvedEvent, +world: M.World()) -> M.Decision():
  match event:
    case O.ChatGPTResult{change}: ChatGPTState.embed(ChatGPT.realize(change, ChatGPTState.registry(world)), world)
    case O.BoardTextResult{id, card, outcome, retitle}: Board.completed(id, card, outcome, retitle, world)
