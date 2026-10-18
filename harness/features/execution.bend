import Base
import ../../features/compaction/PROGRAM.bend as Compaction
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
import ./graph-execution.bend as TaskGraph
import ../../features/work/PROGRAM.bend as Work
import ./work-state.bend as WorkState
import ./MODEL.bend as F

def operation_calculation(~spawn: D.Profile -> String -> String -> Workspace.Selection -> @+world:M.World() -> M.Decision(), operation: O.Operation, +world: M.World()) -> M.Decision():
  match operation:
    case O.WorkChange{change}: WorkState.embed(Work.realize_calculation(change, WorkState.registry(world)), world)
    case O.StartWorkTask{work, profile, reasoning, message, selection}:
      WorkState.born(work, D.state_next_task(C.local(D.State, F.State(), world)), world, spawn(profile, reasoning, message, selection, world))
    case O.ChatGPTChange{change}: ChatGPTState.embed(ChatGPT.realize_calculation(change, ChatGPTState.registry(world)), world)
    case O.BoardChange{change}: Board.change_calculation(change, world)
    case O.StartCard{id, card, now, profile, reasoning, message, selection}:
      Board.started(id, State.task_id(world), card, now, spawn(profile, reasoning, message, selection, world))
    case O.InstallGraph{id, work, declaration, nodes}: TaskGraph.install(~spawn, id, work, declaration, nodes, world)
    case O.DeleteGraph{id}: TaskGraph.remove(id, world)

def resolved_event_calculation(event: O.ResolvedEvent, +world: M.World()) -> M.Decision():
  match event:
    case O.CompactionResult{completion}: Compaction.complete(completion, world)
    case O.ChatGPTResult{change}: ChatGPTState.embed(ChatGPT.realize_calculation(change, ChatGPTState.registry(world)), world)
    case O.BoardTextResult{id, card, outcome, retitle}: Board.completed(id, card, outcome, retitle, world)

type OperationRequest is Data:
  OperationRequest{operation: O.Operation, world: M.World()}

def operation_result(~spawn: D.Profile -> String -> String -> Workspace.Selection -> @+world:M.World() -> M.Decision(), request: OperationRequest) -> M.Decision():
  OperationRequest{operation, world} = request
  operation_calculation(~spawn, operation, world)

def ConstructedOperation(~spawn: D.Profile -> String -> String -> Workspace.Selection -> @+world:M.World() -> M.Decision()) -> Type:
  Categories.Membership<Categories.Construction<OperationRequest, M.Decision()>,
    Categories.constructed_by(OperationRequest, M.Decision(), operation_result(~spawn))>

def construct_operation(~spawn: D.Profile -> String -> String -> Workspace.Selection -> @+world:M.World() -> M.Decision(), operation: O.Operation, world: M.World()) -> ConstructedOperation(~spawn):
  Categories.construct(OperationRequest, M.Decision(), operation_result(~spawn), OperationRequest{operation, world})

def operation_value(~spawn: D.Profile -> String -> String -> Workspace.Selection -> @+world:M.World() -> M.Decision(), member: ConstructedOperation(~spawn)) -> M.Decision():
  Categories.Membership{Categories.Construction{request, result}, evidence} = member
  result

def realize_calculation(~spawn: D.Profile -> String -> String -> Workspace.Selection -> @+world:M.World() -> M.Decision(), operation: O.Operation, +world: M.World()) -> M.Decision():
  operation_value(~spawn, construct_operation(~spawn, operation, world))

type ResolvedEventRequest is Data:
  ResolvedEventRequest{event: O.ResolvedEvent, world: M.World()}

def resolved_event_result(request: ResolvedEventRequest) -> M.Decision():
  ResolvedEventRequest{event, world} = request
  resolved_event_calculation(event, world)

def ConstructedResolvedEvent() -> Type:
  Categories.Membership<Categories.Construction<ResolvedEventRequest, M.Decision()>,
    Categories.constructed_by(ResolvedEventRequest, M.Decision(), resolved_event_result)>

def construct_resolved_event(event: O.ResolvedEvent, world: M.World()) -> ConstructedResolvedEvent():
  Categories.construct(ResolvedEventRequest, M.Decision(), resolved_event_result, ResolvedEventRequest{event, world})

def resolved_event_value(member: ConstructedResolvedEvent()) -> M.Decision():
  Categories.Membership{Categories.Construction{request, result}, evidence} = member
  result

def event_calculation(event: O.ResolvedEvent, +world: M.World()) -> M.Decision():
  resolved_event_value(construct_resolved_event(event, world))

def resolution_calculation(~spawn: D.Profile -> String -> String -> Workspace.Selection -> @+world:M.World() -> M.Decision(), resolution: Resolution.Resolution, world: M.World()) -> M.Decision():
  match resolution:
    case Resolution.Refuse{code, reason}: C.Decision{world, D.failure(code, reason), Nil{}}
    case Resolution.Accept{operation}: realize_calculation(~spawn, operation, world)

def realize(~start: String -> String -> String -> J.Json -> @+world:M.World() -> Resolution.Start,
  ~spawn: D.Profile -> String -> String -> Workspace.Selection -> @+world:M.World() -> M.Decision(),
  member: Resolution.ConstructedCommand(~start)) -> M.Decision():
  Categories.Membership{Categories.Construction{Resolution.CommandRequest{command, world}, resolution}, evidence} = member
  resolution_calculation(~spawn, resolution, world)

def event_resolution_calculation(resolution: Maybe<&2, O.ResolvedEvent>, world: M.World()) -> M.Decision():
  match resolution:
    case None{}: C.Decision{world, D.success(J.Object{[J.Field{"accepted", J.Boolean{False{}}}]}), Nil{}}
    case Some{event}: event_calculation(event, world)

def event(member: Protocol.ConstructedEvent()) -> M.Decision():
  Categories.Membership{Categories.Construction{Protocol.EventRequest{completion, world}, resolution}, evidence} = member
  event_resolution_calculation(resolution, world)

def react(~send: Nat -> String -> @+world:M.World() -> M.Decision(), source: Nat, output: String, world: M.World()) -> M.Decision():
  TaskGraph.react(~send, source, output, world)

def react_outputs(~send: Nat -> String -> @+world:M.World() -> M.Decision(), source: Nat, outputs: +List<String>, world: M.World()) -> M.Decision():
  TaskGraph.react_outputs(~send, source, outputs, world)
