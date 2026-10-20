import ../experience/MODEL.bend as Experience
import Base
import ../search/MODEL.bend as Search
import ../conversation/OUTPUT.bend as Live
import ../submission/FIELDS.bend as Forms
import ../../features/board/MODEL.bend as B
import ../../features/task_graph/MODEL.bend as G
import ../../harness/DOMAIN.bend as D
import ../INPUT.bend as U
import ../services/CONTEXT.bend as Context
import ../conversation/MODEL.bend as ConversationWorld

type Availability is Data:
  Available{}
  NeedsDirectoryObservation{}
  Unavailable{reason: String}

type Prominence is Data:
  Primary{}
  Secondary{}
  Destructive{}

type ControlDeclaration is Data:
  ControlDeclaration{identity: String, label: String, prominence: Prominence, input: U.Input, availability: Availability}

type ProjectChoice is Data:
  ProjectChoice{id: Nat, name: String, workspace: D.Workspace}

type WorkspaceRoot is Data:
  WorkspaceRoot{path: String, primary: Bool, choose_primary: ControlDeclaration, remove: ControlDeclaration}

type WorkspaceControls is Data:
  WorkspaceControls{editor: U.Editor, roots: +List<WorkspaceRoot>, inherit: Maybe<&2, ControlDeclaration>}

type InputGroup is Data:
  MessageInput{value: U.Text}
  ModelInput{profile: String, reasoning: String, choices: +List<D.Profile>}
  ExecutionInput{configuration: Context.Configuration, preview: Context.Preview,
    workspace: WorkspaceControls, projects: +List<ProjectChoice>, reviewer_profiles: +List<D.Profile>}
  DeliveryInput{selected: U.Delivery, send: ControlDeclaration, steer: ControlDeclaration}
  ProjectNameInput{name: String}
  ProjectWorkspaceInput{workspace: D.Workspace, controls: WorkspaceControls}
  CardContentInput{value: B.Draft, projects: +List<ProjectChoice>,
    stages: +List<B.Stage>, priorities: +List<B.Priority>, owners: +List<Forms.ChoiceValue>}
  CardAssistanceInput{enabled: Bool, profile: String, choices: +List<D.Profile>}
  AgentIdentityInput{name: String, instructions: String, concurrency: Nat}
  ForkInput{count: Nat, messages: +List<String>}
  SummaryInput{summary: Maybe<&2, String>}
  TaskGraphInput{declaration: String}

type EditorScene is Data:
  EditorScene{identity: U.Editor, revision: Nat, groups: +List<InputGroup>, sections: +List<Forms.Section>,
    assessment: Experience.Assessment, submit: ControlDeclaration, feedback: U.Feedback, pending: Bool}

type ComposerControl is Data:
  ComposerControl{property: Experience.Property, declaration: ControlDeclaration}

type ComposerPhase is Data:
  Creation{}
  Conversation{task: Nat}

type ComposerScene is Data:
  ComposerScene{identity: U.Editor, revision: Nat, message: U.Text, phase: ComposerPhase,
    creation_context: +List<ComposerControl>, execution_controls: +List<ComposerControl>,
    context: Maybe<&2, Context.Observation>, assessment: Experience.Assessment, submit: ControlDeclaration, feedback: U.Feedback, pending: Bool}

# Derived from the current composer; this is not another mutable draft.

type CreationIntroduction is Data:
  CreationIntroduction{heading: String, context_summary: String,
    context: Maybe<&2, Context.Preview>, project: Maybe<&2, ProjectChoice>, choose_project: ControlDeclaration}

type TaskActions is Data:
  TaskActions{details: ControlDeclaration, overflow: +List<ControlDeclaration>}

type TaskStatus is Data:
  TaskStatus{lifecycle: D.Status, working: Bool}

type TaskEntry is Data:
  TaskEntry{id: Nat, title: String, status: TaskStatus, selected: Bool, open: ControlDeclaration}

type WorkChoice is Data:
  WorkChoice{work: Maybe<&2, Nat>, name: String, description: String}

type TaskTree is Data:
  TaskTree{entry: TaskEntry, children: +List<TaskTree>}

type ProjectEntry is Data:
  ProjectEntry{id: Nat, name: String, workspace: D.Workspace, selected: Bool,
    expanded: Bool, tasks: +List<TaskTree>, open: ControlDeclaration, create: ControlDeclaration, toggle: ControlDeclaration, more: ControlDeclaration}

type Navigation is Data:
  Navigation{expanded: Bool, create: ControlDeclaration, destinations: +List<ControlDeclaration>,
    projects: +List<ProjectEntry>, ungrouped_tasks: +List<TaskTree>, toggle: ControlDeclaration}

type TaskDetails is Data:
  TaskDetails{execution: Context.EffectiveContext, model: D.Model, tools: +List<D.Tool>,
    lineage: +List<Nat>, queued_messages: +List<String>, status: D.Status, phase: D.Phase}

type TaskScene is Data:
  TaskScene{task: Nat, title: String, status: TaskStatus, context: Context.EffectiveContext,
    timeline: ConversationWorld.Timeline, previews: +List<Live.Output>, composer: Maybe<&2, ComposerScene>, details: TaskDetails, actions: TaskActions}

type ProjectScene is Data:
  ProjectScene{id: Nat, name: String, default_workspace: D.Workspace, guidance: D.ProjectContext,
    tasks: +List<TaskEntry>, actions: +List<ControlDeclaration>}

type CardScene is Data:
  CardScene{id: Nat, value: B.Card, open: ControlDeclaration, actions: +List<ControlDeclaration>, linked_task: Maybe<&2, TaskEntry>,
    destinations: +List<MoveDestination>, link_candidates: +List<ControlDeclaration>}

type CardFace is Data:
  CardFace{id: Nat, title: String, description: String, priority: B.Priority, pinned: Bool,
    status: String, project: String, labels: +List<String>, owner: String, updated: String}

type MoveDestination is Data:
  MoveDestination{stage: B.Stage, before: Maybe<&2, Nat>, label: String, availability: Availability}

type BoardColumn is Data:
  BoardColumn{stage: B.Stage, cards: +List<CardScene>, create: ControlDeclaration}

type AgentScene is Data:
  AgentScene{id: Nat, value: B.AgentProfile, edit: ControlDeclaration, remove: ControlDeclaration}

type TaskGraphNode is Data:
  TaskGraphNode{key: String, task: Nat, entry: Maybe<&2, TaskEntry>}

type TaskGraphScene is Data:
  TaskGraphScene{id: Nat, value: G.Graph, nodes: +List<TaskGraphNode>, edit: ControlDeclaration, remove: ControlDeclaration}

type Page is Data:
  SharedUIPage{work: Nat, name: String, source: String}
  StartPage{composer: Maybe<&2, ComposerScene>}
  TaskPage{task: TaskScene}
  ProjectPage{project: ProjectScene}
  ProjectsPage{projects: +List<ProjectScene>, create: ControlDeclaration}
  BoardPage{filter: B.Filter, columns: +List<BoardColumn>, create: ControlDeclaration, working: Nat,
    settings: ControlDeclaration, filters: ControlDeclaration, archive: ControlDeclaration}
  AgentsPage{agents: +List<AgentScene>, create: ControlDeclaration}
  TaskGraphsPage{graphs: +List<TaskGraphScene>, create: ControlDeclaration}
  HistorySearchPage{search: Search.State, projects: +List<Search.Choice>, works: +List<Search.Choice>}
  MissingObject{message: String}

type LayerContent is Data:
  GlobalNavigation{route: U.Route, destinations: +List<ControlDeclaration>}
  WorkSelection{selected: Maybe<&2, Nat>, works: +List<WorkChoice>}
  PropertySource{origin: LayerContent}
  ProjectSelection{query: String, selected: Maybe<&2, Nat>, projects: +List<ProjectChoice>}
  ObjectActions{actions: +List<ControlDeclaration>}
  ArchivedCards{cards: +List<CardScene>}
  BoardSettings{automatic: Bool, draft_profile: String, assistance_profiles: +List<D.Profile>, automation: ControlDeclaration}
  BoardFilters{filter: B.Filter}
  CardDetails{card: Maybe<&2, CardScene>}
  ObjectEditor{editor: Maybe<&2, EditorScene>}
  WorkspaceSettings{editor: U.Editor, fields: +List<InputGroup>}
  PermissionSettings{editor: U.Editor, fields: +List<InputGroup>}
  CommittedContext{context: Maybe<&2, Context.EffectiveContext>}
  ModelSelection{editor: U.Editor, query: String, fields: +List<InputGroup>}
  DeliverySelection{editor: U.Editor, fields: +List<InputGroup>}
  ExecutionDetails{task: Maybe<&2, TaskScene>}
  SideConversation{task: Nat, parent: Maybe<&2, Nat>, conversation: Maybe<&2, TaskScene>, return_content: ControlDeclaration, close: ControlDeclaration}
  Confirmation{title: String, confirm: ControlDeclaration, cancel: ControlDeclaration}

type LayerKind is Data:
  ModalDialog{}
  AnchoredMenu{}
  TrailingDetails{}

type Dismissal is Data:
  OutsideOrEscape{action: U.Action}
  ByTrigger{action: U.Action}

type Layer is Data:
  Layer{kind: LayerKind, content: LayerContent, initial_attention: String, return_attention: String, dismissal: Dismissal}

type Capacity is Data:
  Capacity{navigation_beside_content: Bool, details_beside_timeline: Bool}

type NavigationPlacement is Data:
  LeadingNavigation{}
  ModalNavigation{}
  CollapsedNavigation{}

type Arrangement is Data:
  Arrangement{navigation: NavigationPlacement}

type Scene is Data:
  Scene{navigation: Navigation, main: Page, layers: +List<Layer>, arrangement: Arrangement, attention: String}

type FieldSelection is Data:
  ExecutionFields{}
  ModelFields{}
  DeliveryFields{}
