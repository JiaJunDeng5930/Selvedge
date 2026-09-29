import Base
import ./live-output.bend as Live
import ./form-fields.bend as Forms
import ../MODEL.bend as M
import ../COMMANDS.bend as Commands
import ../PROJECTS.bend as Projects
import ../WORKSPACE.bend as Workspace
import ../BOARD.bend as B
import ../FEATURES.bend as F
import ../bendlib/domain.bend as D
import ../bendlib/association-map.bend as Finite
import ../bendlib/board-state.bend as Board
import ../bendlib/board-filter.bend as Filter
import ../bendlib/conversation.bend as Conversation
import ../bendlib/tasks.bend as Tasks
import ./user-input.bend as U
import ./user-context.bend as Context
import ./user-experience.bend as E
import ./user-conversation.bend as ConversationWorld

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
  CardContentInput{value: B.Draft, projects: +List<ProjectChoice>, agents: +List<Finite.Entry(B.AgentProfile)>,
    stages: +List<B.Stage>, priorities: +List<B.Priority>, owners: +List<B.Owner>}
  CardAssistanceInput{enabled: Bool, profile: String, choices: +List<D.Profile>}
  AgentIdentityInput{name: String, instructions: String, concurrency: Nat}
  ForkInput{count: Nat, messages: +List<String>}
  SummaryInput{summary: Maybe<&2, String>}

type EditorScene is Data:
  EditorScene{identity: U.Editor, revision: Nat, groups: +List<InputGroup>, sections: +List<Forms.Section>,
    submit: ControlDeclaration, feedback: U.Feedback, pending: Bool}

type ComposerScene is Data:
  ComposerScene{identity: U.Editor, revision: Nat, message: U.Text, footer: +List<ControlDeclaration>,
    context: Maybe<&2, Context.Preview>, submit: ControlDeclaration, feedback: U.Feedback, pending: Bool}

type TaskActions is Data:
  TaskActions{details: ControlDeclaration, overflow: +List<ControlDeclaration>}

type TaskEntry is Data:
  TaskEntry{id: Nat, title: String, status: String, selected: Bool, open: ControlDeclaration}

type ProjectEntry is Data:
  ProjectEntry{id: Nat, name: String, workspace: D.Workspace, selected: Bool,
    tasks: +List<TaskEntry>, open: ControlDeclaration, create: ControlDeclaration}

type Navigation is Data:
  Navigation{expanded: Bool, create: ControlDeclaration, destinations: +List<ControlDeclaration>,
    projects: +List<ProjectEntry>, ungrouped_tasks: +List<TaskEntry>, toggle: ControlDeclaration}

type TaskDetails is Data:
  TaskDetails{execution: Context.EffectiveContext, model: D.Model, tools: +List<D.Tool>,
    lineage: +List<Nat>, queued_messages: +List<String>, status: D.Status, phase: D.Phase}

type TaskScene is Data:
  TaskScene{task: Nat, title: String, status: String, context: Context.EffectiveContext,
    timeline: ConversationWorld.Timeline, previews: +List<Live.Output>, composer: Maybe<&2, ComposerScene>, details: TaskDetails, actions: TaskActions}

type ProjectScene is Data:
  ProjectScene{id: Nat, name: String, default_workspace: D.Workspace, guidance: D.ProjectContext,
    tasks: +List<TaskEntry>, actions: +List<ControlDeclaration>}

type CardScene is Data:
  CardScene{id: Nat, value: B.Card, open: ControlDeclaration, actions: +List<ControlDeclaration>, linked_task: Maybe<&2, TaskEntry>,
    destinations: +List<MoveDestination>, link_candidates: +List<ControlDeclaration>}

type MoveDestination is Data:
  MoveDestination{stage: B.Stage, availability: Availability}

type BoardColumn is Data:
  BoardColumn{stage: B.Stage, cards: +List<CardScene>}

type AgentScene is Data:
  AgentScene{id: Nat, value: B.AgentProfile, edit: ControlDeclaration, remove: ControlDeclaration}

type Page is Data:
  StartPage{composer: Maybe<&2, ComposerScene>}
  TaskPage{task: TaskScene}
  ProjectPage{project: ProjectScene}
  ProjectsPage{projects: +List<ProjectScene>, create: ControlDeclaration}
  BoardPage{filter: B.Filter, columns: +List<BoardColumn>, create: ControlDeclaration, automatic: Bool, draft_profile: String,
    automation: ControlDeclaration, assistance_profiles: +List<D.Profile>, archive: ControlDeclaration}
  AgentsPage{agents: +List<AgentScene>, create: ControlDeclaration}
  MissingObject{message: String}

type LayerContent is Data:
  ObjectActions{actions: +List<ControlDeclaration>}
  ArchivedCards{cards: +List<CardScene>}
  ObjectEditor{editor: Maybe<&2, EditorScene>}
  ExecutionSettings{editor: U.Editor, fields: +List<InputGroup>}
  ModelSelection{editor: U.Editor, query: String, fields: +List<InputGroup>}
  DeliverySelection{editor: U.Editor, fields: +List<InputGroup>}
  ExecutionDetails{task: Maybe<&2, TaskScene>}
  Confirmation{title: String, confirm: ControlDeclaration, cancel: ControlDeclaration}

type LayerKind is Data:
  ModalDialog{}
  AnchoredMenu{}
  TrailingDetails{}

type Layer is Data:
  Layer{kind: LayerKind, content: LayerContent, initial_attention: String, return_attention: String, close: ControlDeclaration}

# Capacity describes available simultaneous regions, not a device or toolkit.
type Capacity is Data:
  Capacity{navigation_beside_content: Bool, details_beside_timeline: Bool}

type NavigationPlacement is Data:
  LeadingNavigation{}
  ModalNavigation{}
  CollapsedNavigation{}

type MainPlacement is Data:
  CenteredCreation{}
  ConversationWithBottomComposer{}
  ProjectOverview{}
  HorizontalBoard{}
  Collection{}

type ConversationRegion is Data:
  TaskHeading{}
  ReadingTimeline{}
  LiveOutputRegion{}
  PendingDecisions{}
  ReturnToLatest{}
  MessageComposer{}
  ExecutionDetailsRegion{}

type ComposerRegion is Data:
  MessageEntry{}
  ContextAndModelControls{}
  SubmissionControl{}

type SpatialRelation is Data:
  SharedReadableWidth{}
  ComposerAtViewportEnd{}
  DecisionsOutsideCollapsedAudit{}
  DetailsUseRemainingWidth{}
  NavigationPrecedesContent{}

type Arrangement is Data:
  Arrangement{navigation: NavigationPlacement, main: MainPlacement,
    conversation_regions: +List<ConversationRegion>, composer_regions: +List<ComposerRegion>, relations: +List<SpatialRelation>}

type Scene is Data:
  Scene{navigation: Navigation, main: Page, layers: +List<Layer>, arrangement: Arrangement, attention: String}

type FieldSelection is Data:
  ExecutionFields{}
  ModelFields{}
  DeliveryFields{}

def field_selected(selection: FieldSelection, field: InputGroup) -> Bool:
  match selection field:
    case ExecutionFields{} ExecutionInput{configuration, preview, workspace, projects, reviewers}: True{}
    case ModelFields{} ModelInput{profile, reasoning, choices}: True{}
    case DeliveryFields{} DeliveryInput{selected, send, steer}: True{}
    case _ _: False{}

def keep_field(yes: Bool, field: InputGroup, rest: +List<InputGroup>) -> +List<InputGroup>:
  match yes:
    case True{}: field <> rest
    case False{}: rest

def select_fields(fields: +List<InputGroup>, +selection: FieldSelection) -> +List<InputGroup>:
  match fields:
    case Nil{}: Nil{}
    case Con{+field, rest}: keep_field(field_selected(selection, field), field, select_fields(rest, selection))

def selected_fields(editor: Maybe<&2, EditorScene>, selection: FieldSelection) -> +List<InputGroup>:
  match editor:
    case None{}: Nil{}
    case Some{EditorScene{identity, revision, groups, sections, submit, feedback, pending}}: select_fields(groups, selection)

def profile_label(profile: Maybe<&2, D.Profile>, fallback: String) -> String:
  match profile:
    case None{}: fallback
    case Some{D.Profile{key, provider, name, reasoning}}: name

def delivery_label(delivery: U.Delivery) -> String:
  match delivery:
    case U.Send{}: "Send"
    case U.Steer{}: "Steer"

def control(identity: String, label: String, action: U.Action) -> ControlDeclaration:
  ControlDeclaration{identity, label, Secondary{}, U.Activate{action}, Available{}}

def composer_scene(body: U.Body, scene: EditorScene, +world: M.World()) -> Maybe<&2, ComposerScene>:
  match body:
    case U.NewTask{message, +profile, reasoning, context}:
      EditorScene{identity, revision, groups, sections, submit, feedback, pending} = scene
      Some{ComposerScene{identity, revision, message,
        [control("composer/model", profile_label(D.find_profile(Board.profiles(world), profile), profile), U.OpenPanel{U.ModelPicker{U.NewTaskEditor{}}, "composer/model"}),
          control("composer/context", "Workspace and permissions", U.OpenPanel{U.TaskConfiguration{}, "composer/context"})],
        Some{Context.preview(context, world)}, submit, feedback, pending}}
    case U.Message{+task, message, delivery}:
      EditorScene{identity, revision, groups, sections, submit, feedback, pending} = scene
      Some{ComposerScene{identity, revision, message,
        [control("composer/delivery/" ++ Nat.show(task), delivery_label(delivery), U.OpenPanel{U.DeliveryPicker{task}, "composer/delivery/" ++ Nat.show(task)})],
        None{}, submit, feedback, pending}}
    case _: None{}

def project_choices(entries: +List<Finite.Entry(D.Project)>) -> +List<ProjectChoice>:
  match entries:
    case Nil{}: Nil{}
    case Con{(id, D.Project{name, workspace, guidance}), rest}: ProjectChoice{id, name, workspace} <> project_choices(rest)

def projects(world: M.World()) -> +List<ProjectChoice>:
  project_choices(Projects.entries(Projects.registry(F.State(), world)))

def agents(board: B.State) -> +List<Finite.Entry(B.AgentProfile)>:
  B.State{cards, next_card, agents, next_agent, automatic, profile} = board
  agents

def is_primary(primary: Maybe<&2, String>, path: String) -> Bool:
  match primary:
    case None{}: False{}
    case Some{value}: String.eq(value, path)

def root_controls(roots: +List<String>, +primary: Maybe<&2, String>, +editor: U.Editor) -> +List<WorkspaceRoot>:
  match roots:
    case Nil{}: Nil{}
    case Con{+path, rest}:
      WorkspaceRoot{path, is_primary(primary, path),
        ControlDeclaration{"primary/" ++ U.editor_key(editor) ++ "/" ++ path, "Use as working directory", Secondary{},
          U.EditDraft{editor, U.EditWorkspace{Context.ChoosePrimary{path}}}, Available{}},
        ControlDeclaration{"remove-root/" ++ U.editor_key(editor) ++ "/" ++ path, "Remove directory", Secondary{},
          U.EditDraft{editor, U.EditWorkspace{Context.RemoveRoot{path}}}, Available{}}} <> root_controls(rest, primary, editor)

def workspace_controls(workspace: D.Workspace, +editor: U.Editor, inherit: Maybe<&2, ControlDeclaration>) -> WorkspaceControls:
  D.Workspace{roots, primary} = workspace
  WorkspaceControls{editor, root_controls(roots, primary, editor), inherit}

def preview_workspace(preview: Context.Preview) -> D.Workspace:
  match preview:
    case Context.ContextUnavailable{reason}: D.Workspace{Nil{}, None{}}
    case Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}: Context.selected_workspace(workspace)

def execution_group(+identity: U.Editor, +config: Context.Configuration, +world: M.World()) -> InputGroup:
  ExecutionInput{config, Context.preview(config, world),
    workspace_controls(preview_workspace(Context.preview(config, world)), identity,
      Some{ControlDeclaration{"inherit-workspace/" ++ U.editor_key(identity), "Use inherited workspace", Secondary{},
        U.EditDraft{identity, U.ConfigureContext{Context.UseDefaultWorkspace{}}}, Available{}}}),
    projects(world), List.filter(~D.Profile, (profile => Workspace.valid_reviewer_profile(profile)), Board.profiles(world))}

def delivery_controls(+task: Nat, selected: U.Delivery) -> InputGroup:
  DeliveryInput{selected,
    ControlDeclaration{"choose-send/" ++ Nat.show(task), "Send", Secondary{}, U.EditDraft{U.MessageEditor{task}, U.ChooseDelivery{U.Send{}}}, Available{}},
    ControlDeclaration{"choose-steer/" ++ Nat.show(task), "Steer", Secondary{}, U.EditDraft{U.MessageEditor{task}, U.ChooseDelivery{U.Steer{}}}, Available{}}}

def agent_owners(agents: +List<Finite.Entry(B.AgentProfile)>) -> +List<B.Owner>:
  match agents:
    case Nil{}: Nil{}
    case Con{(id, value), rest}: B.Agent{id} <> agent_owners(rest)

def profile_owners(profiles: +List<D.Profile>, rest: +List<B.Owner>) -> +List<B.Owner>:
  match profiles:
    case Nil{}: rest
    case Con{D.Profile{key, provider, name, policy}, tail}: B.Profile{key} <> profile_owners(tail, rest)
def capture_inputs(id: Maybe<&2, Nat>, assist: Bool, profile: String, world: M.World()) -> +List<InputGroup>:
  match id:
    case None{}: [CardAssistanceInput{assist, profile, Board.profiles(world)}]
    case Some{id}: Nil{}
def input_groups(body: U.Body, +world: M.World()) -> +List<InputGroup>:
  match body:
    case U.NewTask{message, profile, reasoning, context}: [MessageInput{message}, ModelInput{profile, reasoning, Board.profiles(world)}, execution_group(U.NewTaskEditor{}, context, world)]
    case U.Message{task, message, delivery}: [MessageInput{message}, delivery_controls(task, delivery)]
    case U.Project{id, name, +workspace}: [ProjectNameInput{name}, ProjectWorkspaceInput{workspace, workspace_controls(workspace, U.ProjectEditor{id}, None{})}]
    case U.Card{id, revision, value, assist, profile}:
      CardContentInput{value, projects(world), agents(Board.registry(world)), B.stages(),
        [B.NoPriority{}, B.Low{}, B.Medium{}, B.High{}, B.Urgent{}], B.Unassigned{} <> B.Self{} <> profile_owners(Board.profiles(world), agent_owners(agents(Board.registry(world))))} <> capture_inputs(id, assist, profile, world)
    case U.Agent{id, revision, name, profile, reasoning, instructions, context, concurrency}:
      [AgentIdentityInput{name, instructions, concurrency}, ModelInput{profile, reasoning, Board.profiles(world)}, execution_group(U.AgentEditor{id}, context, world)]
    case U.Fork{task, count, messages, context}: [ForkInput{count, messages}, execution_group(U.ForkEditor{task}, context, world)]
    case U.Compact{task, summary}: [SummaryInput{summary}]

def submit_label(body: U.Body) -> String:
  match body:
    case U.NewTask{message, profile, reasoning, context}: "Start task"
    case U.Message{task, message, U.Send{}}: "Send"
    case U.Message{task, message, U.Steer{}}: "Steer"
    case U.Fork{task, count, messages, context}: "Fork task"
    case U.Compact{task, summary}: "Compact history"
    case _: "Save"

def operation_availability(operation: Commands.Operation) -> Availability:
  match operation:
    case Commands.Refuse{code, reason}: Unavailable{reason}
    case _: Available{}

def preparation_availability(workspace: Maybe<&2, D.Workspace>, body: U.Body, now: U32, world: M.World()) -> Availability:
  match workspace:
    case None{}: operation_availability(Commands.resolve(U.command(body, now), world))
    case Some{value}: NeedsDirectoryObservation{}

def submit_availability(blocked: Bool, +body: U.Body, now: U32, world: M.World()) -> Availability:
  match blocked:
    case True{}: Unavailable{"Wait for the pending submission"}
    case False{}: preparation_availability(U.required_workspace(body), body, now, world)

def editor_scene(draft: U.Draft, pending: +List<E.Pending>, now: U32, +world: M.World()) -> EditorScene:
  U.Draft{revision, +body, feedback} = draft
  +identity = U.owner(body)
  +waiting = E.busy(pending, identity)
  EditorScene{identity, revision, input_groups(body, world), Forms.structure(body),
    ControlDeclaration{"submit/" ++ U.editor_key(identity), submit_label(body), Primary{}, U.Activate{U.Submit{identity}},
      submit_availability(waiting || Bool.not(U.valid_origin(body)), body, now, world)}, feedback, waiting}

def found_composer(found: Maybe<&2, U.Draft>, pending: +List<E.Pending>, now: U32, +world: M.World()) -> Maybe<&2, ComposerScene>:
  match found:
    case None{}: None{}
    case Some{U.Draft{revision, +body, feedback}}: composer_scene(body, editor_scene(U.Draft{revision, body, feedback}, pending, now, world), world)

def composer(identity: U.Editor, session: E.Session, world: M.World()) -> Maybe<&2, ComposerScene>:
  E.Session{route, drafts, readers, layers, focus, navigation, filter, now, next, pending, previews, code_blocks} = session
  found_composer(E.find_draft(drafts, identity), pending, now, world)

def action_availability(command: Maybe<&2, M.Command>, world: M.World()) -> Availability:
  match command:
    case None{}: Available{}
    case Some{command}: operation_availability(Commands.resolve(command, world))

def native(identity: String, label: String, prominence: Prominence, +action: U.Action, world: M.World()) -> ControlDeclaration:
  ControlDeclaration{identity, label, prominence, U.Activate{action}, action_availability(U.direct_command(action), world)}

def optional_editor(found: Maybe<&2, U.Draft>, pending: +List<E.Pending>, now: U32, world: M.World()) -> Maybe<&2, EditorScene>:
  match found:
    case None{}: None{}
    case Some{draft}: Some{editor_scene(draft, pending, now, world)}

def editor(identity: U.Editor, session: E.Session, world: M.World()) -> Maybe<&2, EditorScene>:
  E.Session{route, drafts, readers, layers, focus, navigation, filter, now, next, pending, previews, code_blocks} = session
  optional_editor(E.find_draft(drafts, identity), pending, now, world)

def selected_task(route: U.Route, task: Nat) -> Bool:
  match route:
    case U.Conversation{id}: Nat.is_eq(id, task)
    case _: False{}

def selected_project(route: U.Route, project: Nat) -> Bool:
  match route:
    case U.ProjectHome{id}: Nat.is_eq(id, project)
    case _: False{}

def task_entry(+task: D.Task, route: U.Route) -> TaskEntry:
  +id = D.task_id(task)
  TaskEntry{id, Conversation.title(task), Conversation.status(task), selected_task(route, id),
    control("task/" ++ Nat.show(id), Conversation.title(task), U.Navigate{U.Conversation{id}})}

def task_entries(tasks: +List<D.Task>, +route: U.Route) -> +List<TaskEntry>:
  match tasks:
    case Nil{}: Nil{}
    case Con{task, rest}: task_entry(task, route) <> task_entries(rest, route)

def same_project(left: Maybe<&2, Nat>, right: Maybe<&2, Nat>) -> Bool:
  match left right:
    case None{} None{}: True{}
    case Some{left} Some{right}: Nat.is_eq(left, right)
    case _ _: False{}

def keep_task(keep: Bool, task: D.Task, rest: +List<D.Task>) -> +List<D.Task>:
  match keep:
    case True{}: task <> rest
    case False{}: rest

def project_tasks(tasks: +List<D.Task>, +project: Maybe<&2, Nat>) -> +List<D.Task>:
  match tasks:
    case Nil{}: Nil{}
    case Con{+task, rest}: keep_task(same_project(Workspace.project_id(D.task_context(task)), project), task, project_tasks(rest, project))

def project_entry(+id: Nat, project: D.Project, tasks: +List<D.Task>, +route: U.Route) -> ProjectEntry:
  D.Project{+name, workspace, guidance} = project
  ProjectEntry{id, name, workspace, selected_project(route, id), task_entries(project_tasks(tasks, Some{id}), route),
    control("project/" ++ Nat.show(id), name, U.Navigate{U.ProjectHome{id}}), control("project/new-task/" ++ Nat.show(id), "New task", U.BeginTask{Some{id}})}

def project_entries(entries: +List<Finite.Entry(D.Project)>, +tasks: +List<D.Task>, +route: U.Route) -> +List<ProjectEntry>:
  match entries:
    case Nil{}: Nil{}
    case Con{(id, project), rest}: project_entry(id, project, tasks, route) <> project_entries(rest, tasks, route)

def navigation(+expanded: Bool, +route: U.Route, +world: M.World()) -> Navigation:
  Navigation{expanded, control("new-task", "New task", U.BeginTask{None{}}),
    [control("board", "Board", U.Navigate{U.TaskBoard{}}), control("projects", "Projects", U.Navigate{U.ProjectCollection{}}), control("agents", "Agents", U.Navigate{U.AgentCollection{}})],
    project_entries(Projects.entries(Projects.registry(F.State(), world)), Commands.entries(world), route), task_entries(project_tasks(Commands.entries(world), None{}), route),
    ControlDeclaration{"navigation/toggle", "Toggle sidebar", Secondary{}, U.SetNavigation{Bool.not(expanded)}, Available{}}}

def task_details(+task: D.Task) -> TaskDetails:
  D.Task{id, lineage, D.Contract{+model, tools, max_fork, max_descendants, plugins, +context}, status, history, queued, phase, operations, notified} = task
  TaskDetails{Context.effective(task), model, tools, lineage, queued, status, phase}

def lifecycle(+id: Nat, +value: D.Control, +label: String, world: M.World()) -> ControlDeclaration:
  native("task/" ++ Nat.show(id) ++ "/" ++ label, label, Secondary{}, U.ControlTask{id, value}, world)

def task_actions(+id: Nat, +world: M.World()) -> TaskActions:
  TaskActions{control("details/" ++ Nat.show(id), "Task details", U.OpenPanel{U.TaskDetails{id}, "details/" ++ Nat.show(id)}),
    [lifecycle(id, D.Interrupt{}, "Interrupt", world), lifecycle(id, D.Freeze{}, "Freeze", world), lifecycle(id, D.Unfreeze{}, "Resume", world),
    lifecycle(id, D.Stop{}, "Stop", world), lifecycle(id, D.Archive{}, "Archive", world),
    control("fork/" ++ Nat.show(id), "Fork", U.ForkTask{id}), control("compact/" ++ Nat.show(id), "Compact", U.CompactTask{id})]}

def task_scene(+task: D.Task, +session: E.Session, +world: M.World()) -> TaskScene:
  E.Session{route, drafts, readers, layers, focus, navigation, filter, now, next, pending, previews, code_blocks} = session
  +id = D.task_id(task)
  TaskScene{id, Conversation.title(task), Conversation.status(task), Context.effective(task), ConversationWorld.timeline(E.reader(readers, id), task, world), Live.for_task(Live.retained(previews, world), id),
    composer(U.MessageEditor{id}, session, world), task_details(task), task_actions(id, world)}

def optional_task(found: Maybe<&2, D.Task>, session: E.Session, world: M.World()) -> Maybe<&2, TaskScene>:
  match found:
    case None{}: None{}
    case Some{task}: Some{task_scene(task, session, world)}

def task_page(found: Maybe<&2, D.Task>, session: E.Session, world: M.World()) -> Page:
  match found:
    case None{}: MissingObject{"This task no longer exists"}
    case Some{task}: TaskPage{task_scene(task, session, world)}

def project_scene(+id: Nat, project: D.Project, route: U.Route, +world: M.World()) -> ProjectScene:
  D.Project{name, workspace, guidance} = project
  ProjectScene{id, name, workspace, guidance, task_entries(project_tasks(Commands.entries(world), Some{id}), route),
    [control("project/new-task/" ++ Nat.show(id), "New task", U.BeginTask{Some{id}}), control("project/edit/" ++ Nat.show(id), "Edit project", U.EditProject{Some{id}}),
      native("project/delete/" ++ Nat.show(id), "Delete project", Destructive{}, U.DeleteProject{id}, world)]}

def project_page(found: Maybe<&2, D.Project>, id: Nat, route: U.Route, world: M.World()) -> Page:
  match found:
    case None{}: MissingObject{"This project no longer exists"}
    case Some{project}: ProjectPage{project_scene(id, project, route, world)}

def project_scenes(entries: +List<Finite.Entry(D.Project)>, +route: U.Route, +world: M.World()) -> +List<ProjectScene>:
  match entries:
    case Nil{}: Nil{}
    case Con{(id, project), rest}: project_scene(id, project, route, world) <> project_scenes(rest, route, world)

def linked_entry(found: Maybe<&2, D.Task>, route: U.Route) -> Maybe<&2, TaskEntry>:
  match found:
    case None{}: None{}
    case Some{task}: Some{task_entry(task, route)}

def linked_task(task: Maybe<&2, Nat>, route: U.Route, world: M.World()) -> Maybe<&2, TaskEntry>:
  match task:
    case None{}: None{}
    case Some{id}: linked_entry(Tasks.find(Commands.entries(world), id), route)

def board_control(identity: String, label: String, +command: B.Command, world: M.World()) -> ControlDeclaration:
  native(identity, label, Secondary{}, U.BoardCommand{command}, world)

def move_destinations(stages: +List<B.Stage>, +id: Nat, +revision: Nat, +now: U32, +world: M.World()) -> +List<MoveDestination>:
  match stages:
    case Nil{}: Nil{}
    case Con{+stage, rest}: MoveDestination{stage, operation_availability(Commands.resolve(M.FeatureCommand{F.BoardCommand{B.Move{id, revision, stage, None{}, now}}}, world))} <>
      move_destinations(rest, id, revision, now, world)

def link_candidates(tasks: +List<D.Task>, +id: Nat, +revision: Nat, +now: U32, +world: M.World()) -> +List<ControlDeclaration>:
  match tasks:
    case Nil{}: Nil{}
    case Con{+task, rest}: board_control("card/link/" ++ Nat.show(id) ++ "/" ++ Nat.show(D.task_id(task)), Conversation.title(task),
      B.Link{id, revision, D.task_id(task), now}, world) <> link_candidates(rest, id, revision, now, world)

def card_scene(+id: Nat, +card: B.Card, route: U.Route, +now: U32, +world: M.World()) -> CardScene:
  B.Card{+revision, draft, task, archived, created, updated, enrichment, error, pinned} = card
  CardScene{id, card, control("card/" ++ Nat.show(id), "Open card", U.EditCard{Some{id}}),
    [board_control("card/run/" ++ Nat.show(id), "Run", B.Run{id, revision, now}, world),
      board_control("card/archive/" ++ Nat.show(id), "Archive or restore", B.Archive{id, revision, Bool.not(archived), now}, world),
      board_control("card/pin/" ++ Nat.show(id), "Pin or unpin", B.Pin{id, revision, Bool.not(pinned), now}, world),
      board_control("card/delete/" ++ Nat.show(id), "Delete", B.Delete{id, revision}, world),
      board_control("card/regenerate/" ++ Nat.show(id), "Regenerate title", B.Regenerate{id, revision, B.draft_profile(Board.registry(world)), now}, world)], linked_task(task, route, world),
    move_destinations(B.stages(), id, revision, now, world), link_candidates(Commands.entries(world), id, revision, now, world)}

def archived_card(entry: Finite.Entry(B.Card)) -> Bool:
  (id, card) = entry
  B.archived(card)

def card_scenes(cards: +List<Finite.Entry(B.Card)>, +route: U.Route, +now: U32, +world: M.World()) -> +List<CardScene>:
  match cards:
    case Nil{}: Nil{}
    case Con{(id, card), rest}: card_scene(id, card, route, now, world) <> card_scenes(rest, route, now, world)

def columns(stages: +List<B.Stage>, +cards: +List<Finite.Entry(B.Card)>, +route: U.Route, +now: U32, +world: M.World()) -> +List<BoardColumn>:
  match stages:
    case Nil{}: Nil{}
    case Con{+stage, rest}: BoardColumn{stage, card_scenes(Filter.column(cards, B.stage_name(stage)), route, now, world)} <> columns(rest, cards, route, now, world)

def board_page(board: B.State, +filter: B.Filter, +route: U.Route, +now: U32, +world: M.World()) -> Page:
  B.State{+cards, next_card, agents, next_agent, +automatic, +draft_profile} = board
  BoardPage{filter, columns(B.stages(), Filter.filtered(cards, filter, now, world), route, now, world), control("card/new", "New card", U.EditCard{None{}}), automatic, draft_profile,
    board_control("board/automatic", "Automatic scheduling", B.Settings{Bool.not(automatic), draft_profile}, world), Board.profiles(world),
    control("board/archive", "Archived cards", U.OpenPanel{U.ArchivedCards{}, "board/archive"})}

def archived_cards(board: B.State, route: U.Route, now: U32, world: M.World()) -> +List<CardScene>:
  B.State{cards, next_card, agents, next_agent, automatic, profile} = board
  card_scenes(List.filter(~Finite.Entry(B.Card), archived_card, cards), route, now, world)

def agent_scene(+id: Nat, +agent: B.AgentProfile, world: M.World()) -> AgentScene:
  B.AgentProfile{revision, name, profile, reasoning, instructions, settings, concurrency} = agent
  AgentScene{id, agent, control("agent/edit/" ++ Nat.show(id), "Edit agent", U.EditAgent{Some{id}}), board_control("agent/delete/" ++ Nat.show(id), "Delete agent", B.DeleteAgent{id, revision}, world)}

def agent_scenes(agents: +List<Finite.Entry(B.AgentProfile)>, +world: M.World()) -> +List<AgentScene>:
  match agents:
    case Nil{}: Nil{}
    case Con{(id, agent), rest}: agent_scene(id, agent, world) <> agent_scenes(rest, world)

def page(+route: U.Route, +session: E.Session, +world: M.World()) -> Page:
  match route:
    case U.Start{}: StartPage{composer(U.NewTaskEditor{}, session, world)}
    case U.Conversation{id}: task_page(Tasks.find(Commands.entries(world), id), session, world)
    case U.ProjectHome{+id}: project_page(Projects.find(Projects.registry(F.State(), world), id), id, route, world)
    case U.ProjectCollection{}: ProjectsPage{project_scenes(Projects.entries(Projects.registry(F.State(), world)), route, world), control("project/new", "New project", U.EditProject{None{}})}
    case U.TaskBoard{}:
      E.Session{old_route, drafts, readers, layers, focus, navigation, filter, now, next, pending, previews, code_blocks} = session
      board_page(Board.registry(world), filter, route, now, world)
    case U.AgentCollection{}: AgentsPage{agent_scenes(agents(Board.registry(world)), world), control("agent/new", "New agent", U.EditAgent{None{}})}

def task_menu(actions: TaskActions) -> +List<ControlDeclaration>:
  TaskActions{details, overflow} = actions
  overflow

def card_moves(values: +List<MoveDestination>, +id: Nat, +revision: Nat, +now: U32, +world: M.World()) -> +List<ControlDeclaration>:
  match values:
    case Nil{}: Nil{}
    case Con{MoveDestination{+stage, availability}, rest}:
      board_control("card/move/" ++ B.stage_name(stage), "Move to " ++ B.stage_label(stage), B.Move{id, revision, stage, None{}, now}, world) <> card_moves(rest, id, revision, now, world)
def card_menu_items(card: CardScene, now: U32, world: M.World()) -> +List<ControlDeclaration>:
  CardScene{id, value, open, actions, linked, destinations, candidates} = card
  List.append(&2, ControlDeclaration, actions, List.append(&2, ControlDeclaration, card_moves(destinations, id, B.revision(value), now, world), candidates))

def card_menu(found: Maybe<&2, B.Card>, id: Nat, +now: U32, +world: M.World()) -> +List<ControlDeclaration>:
  match found:
    case None{}: Nil{}
    case Some{card}: card_menu_items(card_scene(id, card, U.TaskBoard{}, now, world), now, world)

def agent_menu_items(agent: AgentScene) -> +List<ControlDeclaration>:
  AgentScene{id, value, edit, remove} = agent
  [edit, remove]

def agent_menu(found: Maybe<&2, B.AgentProfile>, id: Nat, world: M.World()) -> +List<ControlDeclaration>:
  match found:
    case None{}: Nil{}
    case Some{agent}: agent_menu_items(agent_scene(id, agent, world))

def board_cards(board: B.State) -> +List<Finite.Entry(B.Card)>:
  B.State{cards, next_card, agents, next_agent, automatic, profile} = board
  cards
def subject_controls(subject: U.Subject, now: U32, +world: M.World()) -> +List<ControlDeclaration>:
  match subject:
    case U.TaskSubject{+id}: task_menu(task_actions(id, world))
    case U.ProjectSubject{+id}: [control("project/edit/" ++ Nat.show(id), "Edit project", U.EditProject{Some{id}}),
      native("project/delete/" ++ Nat.show(id), "Delete project", Destructive{}, U.DeleteProject{id}, world)]
    case U.CardSubject{+id}: card_menu(Finite.find(~B.Card, board_cards(Board.registry(world)), id), id, now, world)
    case U.AgentSubject{+id}: agent_menu(Finite.find(~B.AgentProfile, agents(Board.registry(world)), id), id, world)

def subject_actions(subject: U.Subject, session: E.Session, world: M.World()) -> +List<ControlDeclaration>:
  E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks} = session
  subject_controls(subject, now, world)

def layer_content(panel: U.Panel, +session: E.Session, +world: M.World()) -> LayerContent:
  match panel:
    case U.ObjectActions{subject}: ObjectActions{subject_actions(subject, session, world)}
    case U.ArchivedCards{}:
      E.Session{route, drafts, readers, layers, focus, navigation, filter, now, next, pending, previews, code_blocks} = session
      ArchivedCards{archived_cards(Board.registry(world), route, now, world)}
    case U.EditObject{id}: ObjectEditor{editor(id, session, world)}
    case U.TaskDetails{task}: ExecutionDetails{optional_task(Tasks.find(Commands.entries(world), task), session, world)}
    case U.TaskConfiguration{}: ExecutionSettings{U.NewTaskEditor{}, selected_fields(editor(U.NewTaskEditor{}, session, world), ExecutionFields{})}
    case U.ModelPicker{+id}: ModelSelection{id, "", selected_fields(editor(id, session, world), ModelFields{})}
    case U.DeliveryPicker{+task}: DeliverySelection{U.MessageEditor{task}, selected_fields(editor(U.MessageEditor{task}, session, world), DeliveryFields{})}
    case U.Confirm{command, title}: Confirmation{title,
      ControlDeclaration{"confirm", "Confirm", Destructive{}, U.Activate{U.ConfirmAction{}}, operation_availability(Commands.resolve(command, world))}, control("confirm/cancel", "Cancel", U.ClosePanel{})}

def details_kind(beside: Bool) -> LayerKind:
  match beside:
    case True{}: TrailingDetails{}
    case False{}: ModalDialog{}

def layer_kind(panel: U.Panel, beside: Bool) -> LayerKind:
  match panel:
    case U.ObjectActions{subject}: AnchoredMenu{}
    case U.ModelPicker{editor}: AnchoredMenu{}
    case U.DeliveryPicker{task}: AnchoredMenu{}
    case U.TaskDetails{task}: details_kind(beside)
    case _: ModalDialog{}

def profile_matches(profile: D.Profile, query: String) -> Bool:
  D.Profile{key, provider, name, policy} = profile
  String.contains(String.to_lower(key ++ " " ++ name), String.to_lower(String.trim(query)))

def keep_profile(matches: Bool, profile: D.Profile, rest: +List<D.Profile>) -> +List<D.Profile>:
  match matches:
    case True{}: profile <> rest
    case False{}: rest

def matching_profiles(profiles: +List<D.Profile>, +query: String) -> +List<D.Profile>:
  match profiles:
    case Nil{}: Nil{}
    case Con{+profile, rest}: keep_profile(profile_matches(profile, query), profile, matching_profiles(rest, query))

def search_fields(fields: +List<InputGroup>, +query: String) -> +List<InputGroup>:
  match fields:
    case Nil{}: Nil{}
    case Con{ModelInput{profile, reasoning, choices}, rest}: ModelInput{profile, reasoning, matching_profiles(choices, query)} <> search_fields(rest, query)
    case Con{other, rest}: other <> search_fields(rest, query)

def search_content(content: LayerContent, +query: String) -> LayerContent:
  match content:
    case ModelSelection{editor, old, fields}: ModelSelection{editor, query, search_fields(fields, query)}
    case other: other
def layers(entries: +List<E.Layer>, +session: E.Session, +world: M.World(), +beside: Bool) -> +List<Layer>:
  match entries:
    case Nil{}: Nil{}
    case Con{E.Layer{+panel, trigger, initial, +query}, rest}:
      Layer{layer_kind(panel, beside), search_content(layer_content(panel, session, world), query), initial, trigger, control("close-layer", "Close", U.ClosePanel{})} <> layers(rest, session, world, beside)

def navigation_visible(intent: E.NavigationIntent, beside: Bool) -> Bool:
  match intent:
    case E.AutomaticNavigation{}: beside
    case E.OpenNavigation{}: True{}
    case E.ClosedNavigation{}: False{}

def navigation_placement(beside: Bool, expanded: Bool) -> NavigationPlacement:
  match beside expanded:
    case True{} True{}: LeadingNavigation{}
    case False{} True{}: ModalNavigation{}
    case _ False{}: CollapsedNavigation{}

def main_placement(route: U.Route) -> MainPlacement:
  match route:
    case U.Start{}: CenteredCreation{}
    case U.Conversation{task}: ConversationWithBottomComposer{}
    case U.ProjectHome{project}: ProjectOverview{}
    case U.TaskBoard{}: HorizontalBoard{}
    case _: Collection{}

def conversation_regions(route: U.Route) -> +List<ConversationRegion>:
  match route:
    case U.Conversation{task}: [TaskHeading{}, ReadingTimeline{}, LiveOutputRegion{}, PendingDecisions{}, ReturnToLatest{}, MessageComposer{}, ExecutionDetailsRegion{}]
    case _: Nil{}

def composer_regions(route: U.Route) -> +List<ComposerRegion>:
  match route:
    case U.Start{}: [MessageEntry{}, ContextAndModelControls{}, SubmissionControl{}]
    case U.Conversation{task}: [MessageEntry{}, ContextAndModelControls{}, SubmissionControl{}]
    case _: Nil{}

def spatial_relations(route: U.Route) -> +List<SpatialRelation>:
  match route:
    case U.Conversation{task}: [SharedReadableWidth{}, ComposerAtViewportEnd{}, DecisionsOutsideCollapsedAudit{}, DetailsUseRemainingWidth{}, NavigationPrecedesContent{}]
    case _: [NavigationPrecedesContent{}]

def arrangement(beside: Bool, +route: U.Route, expanded: Bool) -> Arrangement:
  Arrangement{navigation_placement(beside, expanded), main_placement(route), conversation_regions(route), composer_regions(route), spatial_relations(route)}

def observe(capacity: Capacity, application: E.Application) -> Scene:
  Capacity{+navigation_beside, details_beside} = capacity
  E.Application{+program, +session} = application
  E.Session{+route, drafts, readers, open_layers, focus, +expanded, filter, now, next, pending, previews, code_blocks} = session
  +visible = navigation_visible(expanded, navigation_beside)
  Scene{navigation(visible, route, program), page(route, session, program), layers(open_layers, session, program, details_beside), arrangement(navigation_beside, route, visible), focus}
