import Base
import ../submission/FIELDS.bend as OperationParameters
import ../IDENTITY.bend as Identity
import ../../features/board/MODEL.bend as B
import ../../harness/DOMAIN.bend as D
import ../../features/board/filter.bend as BoardFilter
import ../INPUT.bend as U
import ./MODEL.bend as V
import ./COMPOSITION.bend as Composition
import ../conversation/MODEL.bend as Conversation
import ../services/MODEL.bend as Services
import ../conversation/CODE.bend as Code
import ../services/CONTEXT.bend as Context
import ../TYPES.bend as InteractionTypes

type Role is Data:
  Navigation{}
  NavigationHeader{}
  Main{}
  Heading{}
  PrimaryButton{}
  DestructiveButton{}
  SelectedButton{}
  ComposerActions{}
  DialogActions{}
  Timeline{}
  Activity{}
  UserMessage{}
  AssistantMessage{}
  Composer{}
  Approval{}
  Toolbar{}
  CodeBlock{}
  ApprovalQueue{}
  Section{}
  Dialog{}
  Menu{}
  Details{}
  Card{}
  Button{}
  Field{}
  Content{}
  Alert{}

type Placement is Data:
  Placement{target: String, label: String, input: InteractionTypes.Input, availability: V.Availability}

type BoardGrouping is Data:
  ViewChoices{}
  SearchArea{}
  WorkStatus{}
  SecondaryActions{}
  PrimaryAction{}

type ChoiceKind is Data:
  SingleChoice{}
  MultipleChoice{}

type Meaning is Data:
  LayerRegion{dismiss: InteractionTypes.Input, outside: Bool, escape: Bool}
  DirectoryBrowserLocation{value: String}
  PanelToggle{expanded: Bool, input: InteractionTypes.Input, availability: V.Availability}
  CardContent{face: V.CardFace}
  MovableCard{destinations: +List<Placement>, face: V.CardFace}
  Region{}
  PageContext{conversation: Maybe<&2, Conversation.Identity>}
  ActivityContent{expanded: Bool, audit: +List<Conversation.AuditFace>}
  ProjectGroup{project: Nat, selected: Bool, expanded: Bool}
  TaskRow{task: Nat, status: V.TaskStatus, selected: Bool}
  ProjectChooser{selected: Maybe<&2, Nat>}
  DirectoryRow{path: String, primary: Bool}
  ContextSummary{observation: Context.Observation}
  ChoiceGroup{}
  Choice{kind: ChoiceKind, classification: Maybe<&2, BoardFilter.Classification>, selected: Bool, description: String, input: InteractionTypes.Input, availability: V.Availability}
  PageRegion{region: Composition.Region, position: Composition.Position}
  BoardLane{stage: B.Stage, count: Nat}
  CardArchive{count: Nat}
  BoardSearch{filter: B.Filter}
  BoardGroup{grouping: BoardGrouping}
  ReadOnly{text: String}
  Fact{value: String}
  RichText{source: Code.Source, value: String}
  TaskFacts{details: V.TaskDetails}
  CodeFacts{view: Code.Scene}
  Activate{input: InteractionTypes.Input, availability: V.Availability}
  ComposerAction{subject: V.ComposerSubject, input: InteractionTypes.Input, availability: V.Availability}
  Edit{editor: U.Editor, field: OperationParameters.Field, entry: OperationParameters.Entry, value: OperationParameters.Observed, choices: +List<OperationParameters.ChoiceValue>}
  SearchChoices{query: String}
  EnterCredential{entered: Bool}
  ReceiveFile{editor: U.Editor, enabled: Bool}
  EnterDirectory{editor: U.Editor, text: String}
  BoardProfile{automatic: Bool, selected: String, choices: +List<D.Profile>, enabled: Bool}

type Node is Data:
  Node{key: Identity.Key, semantic: String, label: String, role: Role, meaning: Meaning, children: +List<Node>}

type Surface is Data:
  Surface{content: InteractionTypes.Scene, base: +List<Node>, overlays: +List<Node>, active_scope: Maybe<&2, String>}

type Gesture is Data:
  Place{target: String}
  Press{}
  Change{value: OperationParameters.Value}
  Search{query: String}
  Credential{value: String}
  Filter{value: B.Filter}
  Attach{file: Services.SelectedFile}
  Directory{path: String}
  ConfirmDirectory{}
  SelectBoardProfile{profile: String}

type PersistentTrigger is Data:
  PersistentTrigger{task: Nat, trigger: String}
