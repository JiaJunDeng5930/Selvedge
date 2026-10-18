import Base
import ../experience/MODEL.bend as Experience
import ../experience/ACTIVITY.bend as Activity
import ./INFORMATION.bend as Information
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
import ../interactive_markdown/TYPES.bend as IM

type Role is Data:
  GlobalNavigation{compact: Bool}
  GlobalNavigationEntry{selected: Bool, compact: Bool}
  CompactHeader{}
  CompactWorkScope{title: String, count: Nat}
  CompactNavigationMenu{}
  CompactNavigationEntry{selected: Bool}
  WorkTabs{}
  WorkTab{selected: Bool}
  WorkTabGroup{}
  WorkOverviewButton{count: Nat}
  WorkChoiceRow{}
  Navigation{}
  NavigationHeader{}
  NavigationEntry{selected: Bool}
  NavigationCollection{}
  NavigationSection{}
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

# A physical row preserves the meanings and actions of its actual descendants.
type ActivityRowRole is Data:
  ChoiceRow{}
  DependencyRow{}
  InspectionRow{}
  SupportingRow{}
  MemberRow{}
  TerminalRow{}
  ObjectHeading{}
  NavigationRow{}

type Meaning is Data:
  SettingEntry{subject: Experience.Subject, value: String, input: InteractionTypes.Input, availability: V.Availability}
  ActivityRow{role: ActivityRowRole}
  ActivityGroup{activity: Activity.Activity, dismiss: InteractionTypes.Input, outside: Bool, escape: Bool}
  DecisionGroup{decision: Experience.Decision}
  WorkspaceCollection{collection: Experience.Collection}
  WorkspaceMember{collection: Experience.Collection, path: String}
  ActionUnit{action: Experience.ActionUnit}
  ActionFeedback{feedback: Experience.Feedback}
  ActionExplanation{assessment: Experience.Assessment}
  ActionCommit{assessment: Experience.Assessment, input: InteractionTypes.Input, availability: V.Availability}
  ObjectGroup{object: Experience.Object}
  SupportingControl{support: Experience.Support, property: Experience.Property, input: InteractionTypes.Input, availability: V.Availability}
  InformationText{role: Information.TextRole}
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
  TaskChildren{task: Nat}
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
  InteractiveRegion{identity: Code.Identity, source_visible: Bool}
  InteractiveNode{node: IM.ExpandedNode}
  InteractiveView{event: IM.EventIdentity, command: IM.ViewCommand, label: String, enabled: Bool}
  Activate{input: InteractionTypes.Input, availability: V.Availability}
  Edit{editor: U.Editor, field: OperationParameters.Field, entry: OperationParameters.Entry, value: OperationParameters.Observed, choices: +List<OperationParameters.ChoiceValue>}
  SearchChoices{query: String}
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
  Filter{value: B.Filter}
  Attach{file: Services.SelectedFile}
  Directory{path: String}
  ConfirmDirectory{}
  SelectBoardProfile{profile: String}

type PersistentTrigger is Data:
  PersistentTrigger{task: Nat, trigger: String}

# A layer's interaction is independent of the activity organizing its content.
type LayerBehavior is Data:
  LayerBehavior{dismiss: InteractionTypes.Input, outside: Bool, escape: Bool}

def layer_region(meaning: Meaning) -> Maybe<&2, LayerBehavior>:
  match meaning:
    case LayerRegion{dismiss, outside, escape}: Some{LayerBehavior{dismiss, outside, escape}}
    case ActivityGroup{activity, dismiss, outside, escape}: Some{LayerBehavior{dismiss, outside, escape}}
    case _: None{}

def layer_region_meaning(meaning: Meaning) -> Maybe<&2, LayerBehavior>:
  match meaning:
    case LayerRegion{dismiss, outside, escape}: Some{LayerBehavior{dismiss, outside, escape}}
    case ActivityGroup{activity, dismiss, outside, escape}: Some{LayerBehavior{dismiss, outside, escape}}
    case _: None{}

type LayerRegionRequirements is Type:
  LayerRegionRequirements{
    complete: @+meaning:Meaning -> {layer_region(meaning) == layer_region_meaning(meaning) : Maybe<&2, LayerBehavior>},
    layer: @+dismiss:InteractionTypes.Input -> @+outside:Bool -> @+escape:Bool ->
      {layer_region(LayerRegion{dismiss, outside, escape}) == Some{LayerBehavior{dismiss, outside, escape}} : Maybe<&2, LayerBehavior>},
    activity: @activity:Activity.Activity -> @+dismiss:InteractionTypes.Input -> @+outside:Bool -> @+escape:Bool ->
      {layer_region(ActivityGroup{activity, dismiss, outside, escape}) == Some{LayerBehavior{dismiss, outside, escape}} : Maybe<&2, LayerBehavior>}}

law layer_region_evidence:
  LayerRegionRequirements
