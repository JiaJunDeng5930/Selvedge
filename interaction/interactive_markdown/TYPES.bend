import Base
import ../../bendlib/json.bend as J

# Owner.key is constructed by Bend from namespace, producer/viewer task, output
# provenance and fence ordinal. The adapter never chooses this authority.
type Owner is Data:
  Owner{key: String, epoch: Nat}

type Identity is Data:
  Identity{owner: Owner, path: String}

type EventIdentity is Data:
  EventIdentity{component: Identity, occurrence: Nat}

type Ending is Data:
  Open{}
  Complete{}
  Interrupted{}

type Attribute is Data:
  Attribute{name: String, source: String}

type Element is Data:
  Element{tag: String, attributes: +List<Attribute>, children: +List<Element>, closed: Bool}

type Frame is Data:
  Frame{tag: String, attributes: +List<Attribute>, children: +List<Element>}

type Syntax is Data:
  Syntax{roots: +List<Element>, frames: +List<Frame>, tail: String,
    failed: Bool, sealed: Bool, accepted: Nat, characters: Nat, diagnostic: String}

type Diagnostic is Data:
  Diagnostic{path: String, message: String, fatal: Bool}

type StateKind is Data:
  IntegerState{}
  NumberState{}
  BooleanState{}
  StringState{}
  EnumState{}

type StateSchema is Data:
  StateSchema{kind: StateKind, initial: J.Json,
    minimum: Maybe<&2, J.Json>, maximum: Maybe<&2, J.Json>, step: J.Json,
    options: +List<String>, max_length: Nat}

type Local is Data:
  Local{id: String, schema: StateSchema, value: J.Json,
    raw: String, validation: Maybe<&2, String>}

type ActionKind is Data:
  SetAction{}
  ResetAction{}
  DraftAction{}
  SubmitAction{}
  CopyAction{}
  OpenUrlAction{}

type Binding is Data:
  NoBinding{}
  FieldBinding{state_id: String, schema: StateSchema, raw: String,
    canonical: J.Json, validation: Maybe<&2, String>, enabled: Bool}
  ActionBinding{kind: ActionKind, enabled: Bool, pending: Bool}

type ExpandedNode is Data:
  ExpandedNode{identity: Identity, occurrence: Nat, tag: String,
    attributes: J.Json, binding: Binding, children: +List<ExpandedNode>}

type SourceRequest is Data:
  SourceRequest{owner: Owner, name: String, graph_id: Nat}

type ViewCommand is Data:
  GraphZoomIn{}
  GraphZoomOut{}
  GraphPan{dx: String, dy: String}
  GraphFit{}
  GraphSelect{identity: String}
  TableSort{column: String}
  TablePage{page: Nat}

type Feedback is Data:
  Feedback{path: String, ticket: Nat, pending: Bool, message: String}

type Mount is Data:
  Mount{path: String, occurrence: Nat}

type Block is Data:
  Block{owner: Owner, source: String, syntax: Syntax, ending: Ending,
    closed: Bool, external: Bool, locals: +List<Local>, sources: +List<J.Field>,
    views: +List<J.Field>, mounts: +List<Mount>, feedback: +List<Feedback>,
    revision: Nat, next: Nat, edited: Bool, restore_requested: Bool}

type State is Data:
  State{blocks: +List<Block>}

type Input is Data:
  SourceChanged{owner: Owner, source: String, closed: Bool, ending: Ending, external: Bool}
  SourcesChanged{owner: Owner, values: +List<J.Field>}
  ExternalChanged{owner: Owner, allowed: Bool}
  ContinueParsing{owner: Owner}
  FieldEdited{event: EventIdentity, raw: String}
  Activated{event: EventIdentity}
  ViewChanged{event: EventIdentity, command: ViewCommand}
  Restored{owner: Owner, definition: String, payload: J.Json}
  StorageFailed{owner: Owner, message: String}
  EffectCompleted{owner: Owner, path: String, ticket: Nat, success: Bool, message: String}
  Removed{owner: Owner}

type Effect is Data:
  FillDraft{owner: Owner, path: String, message: String}
  SendMessage{owner: Owner, path: String, ticket: Nat, message: String}
  WriteClipboard{owner: Owner, path: String, ticket: Nat, text: String}
  OpenUrl{owner: Owner, path: String, url: String}
  LoadSnapshot{owner: Owner}
  SaveSnapshot{owner: Owner, definition: String, payload: J.Json}
  RemoveSnapshot{owner: Owner}
  ScheduleParse{owner: Owner}
  RestoreFieldBuffer{event: EventIdentity, value: String}

type Decision is Data:
  Decision{state: State, effects: +List<Effect>}

type Scene is Data:
  Scene{owner: Owner, nodes: +List<ExpandedNode>, diagnostics: +List<Diagnostic>,
    complete: Bool, failed: Bool, revision: Nat}
