import Base
import ../DOMAIN.bend as D
import ../MODEL.bend as M
import ../workspace/WORKSPACE.bend as Workspace
import ./operations.bend as O
import ./SPEC.bend as Spec
import ./execution.bend as Actual
import ../../features/board/PROGRAM.bend as Board
import ../../features/board/SPEC.bend as BoardSpec
import ../../features/board/STATE.bend as State
import ../../features/board/CONTRACT.bend as Boundary
import ../../features/board/PROOF.bend as BoardProof
import ./CONTRACT.bend as Architecture
import ../../features/chatgpt/CONTRACT.bend as ChatGPT
import ../../features/chatgpt/PROOF.bend as ChatGPTProof

# Task creation is an actual interaction boundary. Its complete-decision proof
# is an explicit premise; no callback silently substitutes for that premise.
def meaning(
  actual_spawn: D.Profile -> String -> String -> Workspace.Selection -> @+world:M.World() -> M.Decision(),
  spec_spawn: D.Profile -> String -> String -> Workspace.Selection -> @+world:M.World() -> M.Decision(),
  creation: @+profile:D.Profile -> @+reasoning:String -> @+message:String -> @+selection:Workspace.Selection -> @+world:M.World() ->
    {actual_spawn(profile, reasoning, message, selection, world) == spec_spawn(profile, reasoning, message, selection, world) : M.Decision()},
  operation: O.Operation, +world: M.World()) ->
  {Actual.realize(actual_spawn, operation, world) == Spec.meaning(spec_spawn, operation, world) : M.Decision()}:
  match operation:
    case O.ChatGPTChange{change}: ChatGPTProof.assembled(change, world)
    case O.BoardChange{change}: Boundary.change_meaning(change, world)
    case O.StartCard{+id, +card, +now, +profile, +reasoning, +message, +selection}:
      Equal.trans(M.Decision(),
        Board.started(id, State.task_id(world), card, now, actual_spawn(profile, reasoning, message, selection, world)),
        Board.started(id, State.task_id(world), card, now, spec_spawn(profile, reasoning, message, selection, world)),
        BoardSpec.started(id, State.task_id(world), card, now, spec_spawn(profile, reasoning, message, selection, world)),
        Equal.cong(M.Decision(), M.Decision(), value => Board.started(id, State.task_id(world), card, now, value),
          actual_spawn(profile, reasoning, message, selection, world), spec_spawn(profile, reasoning, message, selection, world),
          creation(profile, reasoning, message, selection, world)),
        Boundary.birth_meaning(id, State.task_id(world), card, now, spec_spawn(profile, reasoning, message, selection, world)))

def event(event: O.ResolvedEvent, world: M.World()) ->
  {Actual.event(event, world) == Spec.event(event, world) : M.Decision()}:
  match event:
    case O.ChatGPTResult{change}: ChatGPTProof.assembled(change, world)
    case O.BoardTextResult{id, card, outcome, retitle}: Boundary.completion_meaning(id, card, outcome, retitle, world)

def features() -> Architecture.Features:
  Architecture.Features{Boundary.board_boundary(), ChatGPT.boundary()}
