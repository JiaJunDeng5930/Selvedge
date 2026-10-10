import Base
import ../../bendlib/categories.bend as Categories
import ../../bendlib/component.bend as C
import ../../bendlib/json.bend as J
import ./resolution.bend as Resolution
import ./protocol.bend as Protocol
import ../DOMAIN.bend as D
import ../MODEL.bend as M
import ../workspace/WORKSPACE.bend as Workspace
import ./operations.bend as O
import ../../features/board/PROGRAM.bend as Board
import ../../features/board/STATE.bend as State
import ../../features/chatgpt/PROGRAM.bend as ChatGPT
import ../../features/chatgpt/STATE.bend as ChatGPTState

def realize_calculation(spawn: D.Profile -> String -> String -> Workspace.Selection -> @+world:M.World() -> M.Decision(), operation: O.Operation, +world: M.World()) -> M.Decision():
  match operation:
    case O.ChatGPTChange{change}: ChatGPTState.embed(ChatGPT.realize_calculation(change, ChatGPTState.registry(world)), world)
    case O.BoardChange{change}: Board.change_calculation(change, world)
    case O.StartCard{id, card, now, profile, reasoning, message, selection}:
      Board.started(id, State.task_id(world), card, now, spawn(profile, reasoning, message, selection, world))

def event_calculation(event: O.ResolvedEvent, +world: M.World()) -> M.Decision():
  match event:
    case O.ChatGPTResult{change}: ChatGPTState.embed(ChatGPT.realize_calculation(change, ChatGPTState.registry(world)), world)
    case O.BoardTextResult{id, card, outcome, retitle}: Board.completed(id, card, outcome, retitle, world)

def resolution_calculation(spawn: D.Profile -> String -> String -> Workspace.Selection -> @+world:M.World() -> M.Decision(), resolution: Resolution.Resolution, world: M.World()) -> M.Decision():
  match resolution:
    case Resolution.Refuse{code, reason}: C.Decision{world, D.failure(code, reason), Nil{}}
    case Resolution.Accept{operation}: realize_calculation(spawn, operation, world)

def realize(-start: String -> String -> String -> J.Json -> @+world:M.World() -> Resolution.Start,
  spawn: D.Profile -> String -> String -> Workspace.Selection -> @+world:M.World() -> M.Decision(),
  member: Resolution.ConstructedCommand(start)) -> M.Decision():
  Categories.Membership{Categories.Construction{Resolution.CommandRequest{command, world}, resolution}, evidence} = member
  resolution_calculation(spawn, resolution, world)

def event_resolution_calculation(resolution: Maybe<&2, O.ResolvedEvent>, world: M.World()) -> M.Decision():
  match resolution:
    case None{}: C.Decision{world, D.success(J.Object{[J.Field{"accepted", J.Boolean{False{}}}]}), Nil{}}
    case Some{event}: event_calculation(event, world)

def event(member: Protocol.ConstructedEvent()) -> M.Decision():
  Categories.Membership{Categories.Construction{Protocol.EventRequest{completion, world}, resolution}, evidence} = member
  event_resolution_calculation(resolution, world)
