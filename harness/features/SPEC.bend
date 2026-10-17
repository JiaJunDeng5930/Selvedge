import Base
import ../../features/compaction/SPEC.bend as Compaction
import ../DOMAIN.bend as D
import ../MODEL.bend as M
import ../workspace/WORKSPACE.bend as Workspace
import ./operations.bend as O
import ../../features/board/SPEC.bend as Board
import ../../features/board/STATE.bend as State
import ../../features/chatgpt/SPEC.bend as ChatGPT
import ../../features/chatgpt/STATE.bend as ChatGPTState
import ./graph-spec.bend as TaskGraph

# The caller supplies the independent task-creation specification. The
# executable assembler supplies its implementation to feature-execution.
def meaning(~spawn: D.Profile -> String -> String -> Workspace.Selection -> @+world:M.World() -> M.Decision(), operation: O.Operation, +world: M.World()) -> M.Decision():
  match operation:
    case O.ChatGPTChange{change}: ChatGPTState.embed(ChatGPT.meaning(change, ChatGPTState.registry(world)), world)
    case O.BoardChange{change}: Board.change(change, world)
    case O.StartCard{id, card, now, profile, reasoning, message, selection}:
      Board.started(id, State.task_id(world), card, now, spawn(profile, reasoning, message, selection, world))
    case O.InstallGraph{id, declaration, nodes}: TaskGraph.install(~spawn, id, declaration, nodes, world)
    case O.DeleteGraph{id}: TaskGraph.remove(id, world)

def event(event: O.ResolvedEvent, +world: M.World()) -> M.Decision():
  match event:
    case O.CompactionResult{completion}: Compaction.meaning(Compaction.resolve(completion, world), world)
    case O.ChatGPTResult{change}: ChatGPTState.embed(ChatGPT.meaning(change, ChatGPTState.registry(world)), world)
    case O.BoardTextResult{id, card, outcome, retitle}: Board.completed(id, card, outcome, retitle, world)

def react(~send: Nat -> String -> @+world:M.World() -> M.Decision(), source: Nat, output: String, world: M.World()) -> M.Decision():
  TaskGraph.react(~send, source, output, world)

def react_outputs(~send: Nat -> String -> @+world:M.World() -> M.Decision(), source: Nat, outputs: +List<String>, world: M.World()) -> M.Decision():
  TaskGraph.react_outputs(~send, source, outputs, world)
