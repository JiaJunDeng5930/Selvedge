import Base
import ../../bendlib/categories.bend as Categories
import ../../bendlib/json.bend as J
import ./MODEL.bend as F
import ./resolution.bend as Resolution
import ./protocol.bend as Protocol
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
  {Actual.realize_calculation(actual_spawn, operation, world) == Spec.meaning(spec_spawn, operation, world) : M.Decision()}:
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
  {Actual.event_calculation(event, world) == Spec.event(event, world) : M.Decision()}:
  match event:
    case O.ChatGPTResult{change}: ChatGPTProof.assembled(change, world)
    case O.BoardTextResult{id, card, outcome, retitle}: Boundary.completion_meaning(id, card, outcome, retitle, world)

def features() -> Architecture.Features:
  Architecture.Features{Boundary.board_boundary(), ChatGPT.boundary()}

def command_calculation(start: String -> String -> String -> J.Json -> @+world:M.World() -> Resolution.Start,
  spawn: D.Profile -> String -> String -> Workspace.Selection -> @+world:M.World() -> M.Decision(),
  construction: Categories.Construction<Resolution.CommandRequest, Resolution.Resolution>) -> M.Decision():
  Categories.Construction{Resolution.CommandRequest{command, +world}, resolution} = construction
  Actual.resolution_calculation(spawn, Resolution.resolve(start, command, world), world)

def command_equation(start: String -> String -> String -> J.Json -> @+world:M.World() -> Resolution.Start,
  spawn: D.Profile -> String -> String -> Workspace.Selection -> @+world:M.World() -> M.Decision(),
  member: Resolution.ConstructedCommand(start)) ->
  {Actual.realize(start, spawn, member) == command_calculation(start, spawn, Categories.value(
    Categories.Construction<Resolution.CommandRequest, Resolution.Resolution>,
    Categories.constructed_by(Resolution.CommandRequest, Resolution.Resolution, Resolution.command_resolution(start)), member)) : M.Decision()}:
  Categories.Membership{Categories.Construction{Resolution.CommandRequest{command, +world}, +resolution}, evidence} = member
  Equal.cong(Resolution.Resolution, M.Decision(), value => Actual.resolution_calculation(spawn, value, world),
    resolution, Resolution.resolve(start, command, world), evidence)

def constructed_command_equation(start: String -> String -> String -> J.Json -> @+world:M.World() -> Resolution.Start,
  spawn: D.Profile -> String -> String -> Workspace.Selection -> @+world:M.World() -> M.Decision(),
  +command: F.Command, +world: M.World()) ->
  {Actual.realize(start, spawn, Resolution.construct_command(start, command, world)) ==
    Actual.resolution_calculation(spawn, Resolution.resolve(start, command, world), world) : M.Decision()}:
  {==}

def completion_calculation(construction: Categories.Construction<Protocol.EventRequest, Maybe<&2, O.ResolvedEvent>>) -> M.Decision():
  Categories.Construction{Protocol.EventRequest{completion, +world}, resolution} = construction
  Actual.event_resolution_calculation(Protocol.resolve(completion, world), world)

def completion_equation(member: Protocol.ConstructedEvent()) ->
  {Actual.event(member) == completion_calculation(Categories.value(
    Categories.Construction<Protocol.EventRequest, Maybe<&2, O.ResolvedEvent>>,
    Categories.constructed_by(Protocol.EventRequest, Maybe<&2, O.ResolvedEvent>, Protocol.event_resolution), member)) : M.Decision()}:
  Categories.Membership{Categories.Construction{Protocol.EventRequest{completion, +world}, +resolution}, evidence} = member
  Equal.cong(Maybe<&2, O.ResolvedEvent>, M.Decision(), value => Actual.event_resolution_calculation(value, world),
    resolution, Protocol.resolve(completion, world), evidence)

def constructed_completion_equation(+completion: F.Completion, +world: M.World()) ->
  {Actual.event(Protocol.construct_event(completion, world)) ==
    Actual.event_resolution_calculation(Protocol.resolve(completion, world), world) : M.Decision()}:
  completion_equation(Protocol.construct_event(completion, world))
