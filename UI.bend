import Base
import ./MODEL.bend as M
import ./BOARD.bend as B
import ./bendlib/json.bend as J
import ./core/SYSTEM.bend as Core
import ./core/user-experience.bend as E
import ./core/user-input.bend as U
import ./core/user-context.bend as Context
import ./core/client-services.bend as Services
import ./core/code-block.bend as Code
import ./core/live-output.bend as Live
import ./core/ui-world.bend as View
import ./core/interface.bend as Interface

# Commands and observations name their origin. A renderer can invoke only a
# current product element; runtime receipts cannot impersonate element input.
type Input is Data:
  # Trusted assembled interface commands stay typed through the platform bridge.
  InterfaceInput{input: Core.Input}
  Engine{input: M.Input}
  ProgramObserved{program: M.World()}
  CommandCompleted{program: M.World(), reply: J.Json, completion: E.Completion}
  Element{capacity: View.Capacity, key: String, gesture: Interface.Gesture}
  SubmitComposer{capacity: View.Capacity, editor: U.Editor}
  Reading{task: Nat, generation: Nat, intent: U.ReadingIntent}
  Directories{ticket: Nat, result: Result<&2, &2, String, Context.DirectoryObservation>}
  Clock{now: U32}
  LiveOutput{observation: Live.Observation}
  CodeSource{identity: Code.Identity, source: String}
  ClipboardCompleted{identity: Code.Identity, ticket: Nat, success: Bool}
  ClipboardFeedbackExpired{identity: Code.Identity, ticket: Nat}
  Authenticated{ticket: Nat, result: Result<&2, &2, String, Unit>}
  Disconnected{reason: String}
  Uploaded{ticket: Nat, result: Result<&2, &2, String, B.Attachment>}
  DirectoryListed{ticket: Nat, result: Result<&2, &2, String, Services.DirectoryCatalog>}
  AttachmentRead{ticket: Nat, result: Result<&2, &2, String, String>}

def initial(program: M.World()) -> Core.State:
  Core.initial(program)

def observe(capacity: View.Capacity, state: Core.State) -> Interface.Surface:
  Interface.observe(capacity, state)

def step(input: Input, state: Core.State) -> Core.Decision:
  match input:
    case InterfaceInput{input}: Core.step(input, state)
    case ProgramObserved{program}: Core.step(Core.ApplicationInput{E.ProgramObserved{program}}, state)
    case CommandCompleted{program, result, completion}: Core.step(Core.ApplicationInput{E.CommandCompleted{program, result, completion}}, state)
    case Engine{input}: Core.step(Core.ApplicationInput{E.RuntimeInput{input}}, state)
    case Element{capacity, key, gesture}: Interface.interact(capacity, key, gesture, state)
    case SubmitComposer{capacity, editor}: Interface.submit_composer(capacity, editor, state)
    case Reading{task, generation, intent}: Core.step(Core.ApplicationInput{E.UserInput{U.ReadTimeline{task, generation, intent}}}, state)
    case Directories{ticket, result}: Core.step(Core.ApplicationInput{E.DirectoriesObserved{ticket, result}}, state)
    case Clock{now}: Core.step(Core.ApplicationInput{E.ClockObserved{now}}, state)
    case LiveOutput{observation}: Core.step(Core.ApplicationInput{E.PreviewObserved{observation}}, state)
    case CodeSource{identity, source}: Core.step(Core.ApplicationInput{E.ContentInput{identity, Code.SourceChanged{source}}}, state)
    case ClipboardCompleted{identity, ticket, success}: Core.step(Core.ApplicationInput{E.ContentInput{identity, Code.Copied{ticket, success}}}, state)
    case ClipboardFeedbackExpired{identity, ticket}: Core.step(Core.ApplicationInput{E.ContentInput{identity, Code.ExpireFeedback{ticket}}}, state)
    case Authenticated{ticket, result}: Core.step(Core.ServiceInput{Services.Authenticated{ticket, result}}, state)
    case Disconnected{reason}: Core.step(Core.ServiceInput{Services.Disconnected{reason}}, state)
    case Uploaded{ticket, result}: Core.step(Core.ServiceInput{Services.Uploaded{ticket, result}}, state)
    case DirectoryListed{ticket, result}: Core.step(Core.ServiceInput{Services.DirectoryListed{ticket, result}}, state)
    case AttachmentRead{ticket, result}: Core.step(Core.ServiceInput{Services.Previewed{ticket, result}}, state)

# Preserve the entire Core decision, including every effect channel.
