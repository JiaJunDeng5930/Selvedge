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
import ./composition.bend as Composition
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
  CardContentInput{value: B.Draft, projects: +List<ProjectChoice>,
    stages: +List<B.Stage>, priorities: +List<B.Priority>, owners: +List<Forms.ChoiceValue>}
  CardAssistanceInput{enabled: Bool, profile: String, choices: +List<D.Profile>}
  AgentIdentityInput{name: String, instructions: String, concurrency: Nat}
  ForkInput{count: Nat, messages: +List<String>}
  SummaryInput{summary: Maybe<&2, String>}

type EditorScene is Data:
  EditorScene{identity: U.Editor, revision: Nat, groups: +List<InputGroup>, sections: +List<Forms.Section>,
    submit: ControlDeclaration, feedback: U.Feedback, pending: Bool}

type ComposerSubject is Data:
  ModelSubject{}
  WorkspaceSubject{}
  PermissionsSubject{}
  DeliverySubject{delivery: U.Delivery}

type ComposerControl is Data:
  ComposerControl{subject: ComposerSubject, declaration: ControlDeclaration}

type ComposerScene is Data:
  ComposerScene{identity: U.Editor, revision: Nat, message: U.Text, footer: +List<ComposerControl>,
    context: Maybe<&2, Context.Observation>, submit: ControlDeclaration, feedback: U.Feedback, pending: Bool}

# Derived from the current composer; this is not another mutable draft.
type CreationIntroduction is Data:
  CreationIntroduction{heading: String, context_summary: String,
    context: Maybe<&2, Context.Preview>, project: Maybe<&2, ProjectChoice>, choose_project: ControlDeclaration}

type TaskActions is Data:
  TaskActions{details: ControlDeclaration, overflow: +List<ControlDeclaration>}

type TaskStatus is Data:
  TaskStatus{lifecycle: D.Status, working: Bool}

def task_status(+task: D.Task) -> TaskStatus:
  TaskStatus{D.task_status(task), Conversation.working(D.task_phase(task), D.task_operations(task))}

def task_status_label(value: TaskStatus) -> String:
  TaskStatus{lifecycle, working} = value
  Conversation.status_label(lifecycle, working)

type TaskEntry is Data:
  TaskEntry{id: Nat, title: String, status: TaskStatus, selected: Bool, open: ControlDeclaration}

type ProjectEntry is Data:
  ProjectEntry{id: Nat, name: String, workspace: D.Workspace, selected: Bool,
    expanded: Bool, tasks: +List<TaskEntry>, open: ControlDeclaration, create: ControlDeclaration, toggle: ControlDeclaration, more: ControlDeclaration}

type Navigation is Data:
  Navigation{expanded: Bool, create: ControlDeclaration, destinations: +List<ControlDeclaration>,
    projects: +List<ProjectEntry>, ungrouped_tasks: +List<TaskEntry>, toggle: ControlDeclaration}

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

type Page is Data:
  StartPage{composer: Maybe<&2, ComposerScene>}
  TaskPage{task: TaskScene}
  ProjectPage{project: ProjectScene}
  ProjectsPage{projects: +List<ProjectScene>, create: ControlDeclaration}
  BoardPage{filter: B.Filter, columns: +List<BoardColumn>, create: ControlDeclaration, working: Nat,
    settings: ControlDeclaration, filters: ControlDeclaration, archive: ControlDeclaration}
  AgentsPage{agents: +List<AgentScene>, create: ControlDeclaration}
  MissingObject{message: String}

type LayerContent is Data:
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

def editor_title(editor: U.Editor) -> String:
  match editor:
    case U.NewTaskEditor{}: "New task"
    case U.MessageEditor{task}: "Message"
    case U.ProjectEditor{None{}}: "New project"
    case U.ProjectEditor{Some{id}}: "Edit project"
    case U.CardEditor{None{}}: "New card"
    case U.CardEditor{Some{id}}: "Edit card"
    case U.AgentEditor{None{}}: "New agent"
    case U.AgentEditor{Some{id}}: "Edit agent"
    case U.ForkEditor{task}: "Fork task"
    case U.CompactEditor{task}: "Compact history"

def layer_title(content: LayerContent) -> String:
  match content:
    case ProjectSelection{query, selected, projects}: "Select project"
    case ObjectActions{actions}: "Actions"
    case ArchivedCards{cards}: "Archived cards"
    case BoardSettings{automatic, draft_profile, assistance_profiles, automation}: "看板设置"
    case BoardFilters{filter}: "筛选任务"
    case CardDetails{card}: "任务详情"
    case ObjectEditor{None{}}: "Editor unavailable"
    case ObjectEditor{Some{EditorScene{identity, revision, groups, sections, submit, feedback, pending}}}: editor_title(identity)
    case WorkspaceSettings{editor, fields}: "Working directories"
    case PermissionSettings{editor, fields}: "Permissions"
    case CommittedContext{context}: "Execution context"
    case ModelSelection{editor, query, fields}: "Choose model"
    case DeliverySelection{editor, fields}: "Delivery options"
    case ExecutionDetails{task}: "Task details"
    case Confirmation{title, confirm, cancel}: title

# Capacity describes available simultaneous regions, not a device or toolkit.
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
    case None{}: "Choose model"
    case Some{D.Profile{key, provider, name, reasoning, options}}: name

def execution_project_source(found: Maybe<&2, D.Project>, project: Nat) -> String:
  match found:
    case None{}: "Project " ++ Nat.show(project) ++ " defaults"
    case Some{D.Project{name, workspace, guidance}}: "Project defaults: " ++ name

def execution_origin_source(origin: Context.Origin, +world: M.World()) -> String:
  match origin:
    case Context.EnvironmentDefaults{}: "Environment defaults"
    case Context.ProjectDefaults{+project}: execution_project_source(Projects.find(Projects.registry(F.State(), world), project), project)
    case Context.ParentTask{task}: "Inherited from task " ++ Nat.show(task)
    case Context.ProjectForParent{task, +project}: "Task " ++ Nat.show(task) ++ "; " ++ execution_project_source(Projects.find(Projects.registry(F.State(), world), project), project)

def workspace_override(value: Context.WorkspaceValue) -> String:
  match value:
    case Context.InheritedWorkspace{workspace}: ""
    case Context.EnteredWorkspace{workspace}: "; custom directories"

def sandbox_override(value: Context.SandboxValue) -> String:
  match value:
    case Context.InheritedSandbox{sandbox}: ""
    case Context.ChosenSandbox{sandbox}: "; custom sandbox"

def approval_override(value: Context.ApprovalValue) -> String:
  match value:
    case Context.InheritedApproval{approval}: ""
    case Context.ChosenApproval{approval}: "; custom approval"

def execution_source_summary(observation: Context.Observation, world: M.World()) -> String:
  match observation:
    case Context.DraftExecution{Context.ContextUnavailable{reason}}: reason
    case Context.DraftExecution{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}}:
      execution_origin_source(origin, world) ++ workspace_override(workspace) ++ sandbox_override(sandbox) ++ approval_override(approval)
    case Context.CommittedExecution{Context.EffectiveContext{task, context, guidance, access}}: "Task settings"

def execution_last_segment(parts: +List<String>, latest: String) -> String:
  match parts:
    case Nil{}: latest
    case Con{"", rest}: execution_last_segment(rest, latest)
    case Con{part, rest}: execution_last_segment(rest, part)

def execution_basename(+path: String) -> String:
  execution_last_segment(String.split(path, '/'), path)

def execution_folder_count(count: Nat) -> String:
  match count:
    case 0n: ""
    case 1n: ""
    case 2n+rest: " + " ++ Nat.show((1n + rest : Nat)) ++ " folders"

def execution_folder(primary: Maybe<&2, String>, count: Nat) -> String:
  match primary:
    case None{}: "No working directory"
    case Some{path}: execution_basename(path) ++ execution_folder_count(count)

def execution_workspace_summary(value: D.Workspace) -> String:
  D.Workspace{roots, primary} = value
  execution_folder(primary, List.length(&2, String, roots))

def automatic_review_summary(found: Maybe<&2, D.Profile>, key: String) -> String:
  match found:
    case None{}: "Automatic review unavailable: " ++ key
    case Some{D.Profile{id, provider, name, reasoning, options}}: "Automatic review: " ++ name

def execution_approval_summary(value: Context.ApprovalChoice, reviewer: Maybe<&2, D.Profile>) -> String:
  match value:
    case Context.Ask{}: "Ask"
    case Context.Unrestricted{}: "Unrestricted"
    case Context.AutomaticReview{profile}: automatic_review_summary(reviewer, profile)

def approval_reviewer(policy: D.ApprovalPolicy) -> Maybe<&2, D.Profile>:
  match policy:
    case D.ApprovalForMe{profile}: Some{profile}
    case _: None{}

def choice_reviewer(choice: Context.ApprovalChoice, profiles: +List<D.Profile>) -> Maybe<&2, D.Profile>:
  match choice:
    case Context.AutomaticReview{key}: D.find_profile(profiles, key)
    case _: None{}

def policy_approval_summary(+policy: D.ApprovalPolicy) -> String:
  execution_approval_summary(Context.approval_choice(policy), approval_reviewer(policy))

def value_approval_summary(value: Context.ApprovalValue, profiles: +List<D.Profile>) -> String:
  match value:
    case Context.InheritedApproval{policy}: policy_approval_summary(policy)
    case Context.ChosenApproval{+choice}: execution_approval_summary(choice, choice_reviewer(choice, profiles))

def execution_network_summary(network: Bool) -> String:
  match network:
    case True{}: "Network enabled"
    case False{}: "Network disabled"

def execution_permissions_summary(sandbox: D.Sandbox, approval: String) -> String:
  D.Sandbox{mode, network} = sandbox
  D.sandbox_mode_name(mode) ++ "; " ++ execution_network_summary(network) ++ "; " ++ approval

def observation_workspace(observation: Context.Observation) -> String:
  match observation:
    case Context.DraftExecution{Context.ContextUnavailable{reason}}: "Workspace unavailable: " ++ reason
    case Context.DraftExecution{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}}: execution_workspace_summary(Context.selected_workspace(workspace))
    case Context.CommittedExecution{Context.EffectiveContext{task, D.TaskContext{workspace, sandbox, approval, project}, guidance, access}}: execution_workspace_summary(workspace)

def observation_permissions(observation: Context.Observation, profiles: +List<D.Profile>) -> String:
  match observation:
    case Context.DraftExecution{Context.ContextUnavailable{reason}}: "Permissions unavailable: " ++ reason
    case Context.DraftExecution{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}}: "Configured: " ++ execution_permissions_summary(Context.unwrap_sandbox(sandbox), value_approval_summary(approval, profiles))
    case Context.CommittedExecution{Context.EffectiveContext{task, D.TaskContext{workspace, D.Sandbox{mode, network}, approval, project}, guidance, +access}}:
      Context.filesystem_summary(access, mode) ++ "; " ++ Context.network_summary(access, network) ++ "; " ++ policy_approval_summary(approval)

def committed_context(found: Maybe<&2, D.Task>) -> Maybe<&2, Context.EffectiveContext>:
  match found:
    case None{}: None{}
    case Some{task}: Some{Context.effective(task)}

def committed_observation(found: Maybe<&2, Context.EffectiveContext>) -> Maybe<&2, Context.Observation>:
  match found:
    case None{}: None{}
    case Some{context}: Some{Context.CommittedExecution{context}}

def creation_project(found: Maybe<&2, D.Project>, id: Nat) -> Maybe<&2, ProjectChoice>:
  match found:
    case None{}: None{}
    case Some{D.Project{name, workspace, guidance}}: Some{ProjectChoice{id, name, workspace}}

def creation_selected_project(context: Maybe<&2, Context.Preview>, world: M.World()) -> Maybe<&2, ProjectChoice>:
  match context:
    case Some{Context.ProspectiveContext{origin, Some{+id}, workspace, sandbox, approval, guidance}}:
      creation_project(Projects.find(Projects.registry(F.State(), world), id), id)
    case _: None{}

def creation_heading(project: Maybe<&2, ProjectChoice>) -> String:
  match project:
    case None{}: "What would you like to build?"
    case Some{ProjectChoice{id, name, workspace}}: "Work on"

def preview_observation(context: Maybe<&2, Context.Preview>) -> Maybe<&2, Context.Observation>:
  match context:
    case None{}: None{}
    case Some{preview}: Some{Context.DraftExecution{preview}}

def draft_preview(observation: Maybe<&2, Context.Observation>) -> Maybe<&2, Context.Preview>:
  match observation:
    case Some{Context.DraftExecution{preview}}: Some{preview}
    case _: None{}

def project_choice_id(project: Maybe<&2, ProjectChoice>) -> Maybe<&2, Nat>:
  match project:
    case None{}: None{}
    case Some{ProjectChoice{id, name, workspace}}: Some{id}

def project_choice_label(project: Maybe<&2, ProjectChoice>) -> String:
  match project:
    case None{}: "Select project"
    case Some{ProjectChoice{id, name, workspace}}: name

def creation_context_summary(context: Maybe<&2, Context.Preview>, world: M.World()) -> String:
  match context:
    case None{}: ""
    case Some{preview}: execution_source_summary(Context.DraftExecution{preview}, world)

def control(identity: String, label: String, action: U.Action) -> ControlDeclaration:
  ControlDeclaration{identity, label, Secondary{}, U.Activate{action}, Available{}}

def context_control(+identity: String, label: String, panel: U.Panel) -> ControlDeclaration:
  control(identity, label, U.OpenPanel{panel, identity})

def creation_introduction_fields(+context: Maybe<&2, Context.Preview>, +world: M.World()) -> CreationIntroduction:
  +project = creation_selected_project(context, world)
  CreationIntroduction{creation_heading(project), creation_context_summary(context, world), context, project,
    context_control("composer/project", project_choice_label(project), U.ProjectPicker{})}

def creation_introduction(composer: Maybe<&2, ComposerScene>, world: M.World()) -> CreationIntroduction:
  match composer:
    case None{}: creation_introduction_fields(None{}, world)
    case Some{ComposerScene{identity, revision, message, footer, context, submit, feedback, pending}}:
      creation_introduction_fields(draft_preview(context), world)

def draft_context_footer(+editor: U.Editor, +observation: Context.Observation, profiles: +List<D.Profile>) -> +List<ComposerControl>:
  [ComposerControl{WorkspaceSubject{}, context_control("composer/workspace/" ++ U.editor_key(editor), observation_workspace(observation), U.WorkspaceConfiguration{editor})},
   ComposerControl{PermissionsSubject{}, context_control("composer/permissions/" ++ U.editor_key(editor), observation_permissions(observation, profiles), U.PermissionsConfiguration{editor})}]

def committed_context_footer(+task: Nat, observation: Maybe<&2, Context.Observation>, profiles: +List<D.Profile>) -> +List<ComposerControl>:
  match observation:
    case None{}: Nil{}
    case Some{+value}:
      [ComposerControl{WorkspaceSubject{}, context_control("composer/workspace/message/" ++ Nat.show(task), observation_workspace(value), U.TaskContext{task})},
       ComposerControl{PermissionsSubject{}, context_control("composer/permissions/message/" ++ Nat.show(task), observation_permissions(value, profiles), U.TaskContext{task})}]

def composer_scene(body: U.Body, scene: EditorScene, +world: M.World()) -> Maybe<&2, ComposerScene>:
  match body:
    case U.NewTask{message, +profile, reasoning, context}:
      EditorScene{identity, revision, groups, sections, submit, feedback, pending} = scene
      +observation: Context.Observation = Context.DraftExecution{Context.preview(context, world)}
      Some{ComposerScene{identity, revision, message,
        ComposerControl{ModelSubject{}, control("composer/model", profile_label(D.find_profile(Board.profiles(world), profile), profile), U.OpenPanel{U.ModelPicker{U.NewTaskEditor{}}, "composer/model"})} <>
          draft_context_footer(U.NewTaskEditor{}, observation, Board.profiles(world)), Some{observation}, submit, feedback, pending}}
    case U.Message{+task, message, +delivery}:
      EditorScene{identity, revision, groups, sections, submit, feedback, pending} = scene
      +observation: Maybe<&2, Context.Observation> = committed_observation(committed_context(Tasks.find(Commands.entries(world), task)))
      Some{ComposerScene{identity, revision, message,
        ComposerControl{DeliverySubject{delivery}, control("composer/delivery/" ++ Nat.show(task), U.delivery_caption(delivery), U.OpenPanel{U.DeliveryPicker{task}, "composer/delivery/" ++ Nat.show(task)})} <>
          committed_context_footer(task, observation, Board.profiles(world)), observation, submit, feedback, pending}}
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

def workspace_inheritance(override: Maybe<&2, D.Workspace>, +identity: U.Editor) -> Maybe<&2, ControlDeclaration>:
  match override:
    case None{}: None{}
    case Some{workspace}: Some{ControlDeclaration{"inherit-workspace/" ++ U.editor_key(identity), "Use inherited workspace", Secondary{},
      U.EditDraft{identity, U.ConfigureContext{Context.UseDefaultWorkspace{}}}, Available{}}}

def configuration_workspace(config: Context.Configuration) -> Maybe<&2, D.Workspace>:
  Context.Configuration{origin, workspace, sandbox, approval} = config
  workspace

def execution_group(+identity: U.Editor, +config: Context.Configuration, +world: M.World()) -> InputGroup:
  +observed = Context.preview(config, world)
  ExecutionInput{config, observed,
    workspace_controls(preview_workspace(observed), identity,
      workspace_inheritance(configuration_workspace(config), identity)),
    projects(world), List.filter(~D.Profile, (profile => Workspace.valid_reviewer_profile(profile)), Board.profiles(world))}

def delivery_controls(+task: Nat, selected: U.Delivery) -> InputGroup:
  DeliveryInput{selected,
    ControlDeclaration{"choose-send/" ++ Nat.show(task), U.delivery_caption(U.Send{}), Secondary{}, U.EditDraft{U.MessageEditor{task}, U.ChooseDelivery{U.Send{}}}, Available{}},
    ControlDeclaration{"choose-steer/" ++ Nat.show(task), U.delivery_caption(U.Steer{}), Secondary{}, U.EditDraft{U.MessageEditor{task}, U.ChooseDelivery{U.Steer{}}}, Available{}}}

def face_profile_name(found: Maybe<&2, D.Profile>, +key: String) -> String:
  match found:
    case None{}: "配置 " ++ key ++ " 不可用"
    case Some{D.Profile{key, provider, name, reasoning, options}}: name

def face_agent_name(found: Maybe<&2, B.AgentProfile>, id: Nat) -> String:
  match found:
    case None{}: "智能体 #" ++ Nat.show(id) ++ " 不可用"
    case Some{B.AgentProfile{revision, name, profile, reasoning, instructions, settings, concurrency}}: name

def face_owner(+owner: B.Owner, +world: M.World()) -> String:
  match owner:
    case B.Unassigned{}: "未分配"
    case B.Self{}: "我"
    case B.Profile{+key}: face_profile_name(D.find_profile(Board.profiles(world), key), key)
    case B.Agent{+id}: face_agent_name(B.find_agent(Board.registry(world), id), id)

def card_owner_choice(+owner: B.Owner, world: M.World()) -> Forms.ChoiceValue:
  Forms.ChoiceValue{B.owner_name(owner), face_owner(owner, world)}

def card_owner_choices(owners: +List<B.Owner>, +world: M.World()) -> +List<Forms.ChoiceValue>:
  match owners:
    case Nil{}: Nil{}
    case Con{owner, rest}: card_owner_choice(owner, world) <> card_owner_choices(rest, world)

def agent_owners(agents: +List<Finite.Entry(B.AgentProfile)>) -> +List<B.Owner>:
  match agents:
    case Nil{}: Nil{}
    case Con{(id, value), rest}: B.Agent{id} <> agent_owners(rest)

def profile_owners(profiles: +List<D.Profile>, rest: +List<B.Owner>) -> +List<B.Owner>:
  match profiles:
    case Nil{}: rest
    case Con{D.Profile{key, provider, name, policy, options}, tail}: B.Profile{key} <> profile_owners(tail, rest)
def capture_inputs(id: Maybe<&2, Nat>, assist: Bool, profile: String, world: M.World()) -> +List<InputGroup>:
  match id:
    case None{}: [CardAssistanceInput{assist, profile, Board.profiles(world)}]
    case Some{id}: Nil{}
def input_groups(body: U.Body, +world: M.World()) -> +List<InputGroup>:
  match body:
    case U.NewTask{message, profile, reasoning, context}: [MessageInput{message}, ModelInput{profile, reasoning, Board.profiles(world)}, execution_group(U.NewTaskEditor{}, context, world)]
    case U.Message{task, message, delivery}: [MessageInput{message}, delivery_controls(task, delivery)]
    case U.Project{id, name, +workspace}: [ProjectNameInput{name}, ProjectWorkspaceInput{workspace, workspace_controls(workspace, U.ProjectEditor{id}, None{})}]
    case U.Card{id, revision, value, assist, profile, keep_open}:
      CardContentInput{value, projects(world), B.stages(),
        B.priorities(), card_owner_choices(B.Unassigned{} <> B.Self{} <> profile_owners(Board.profiles(world), agent_owners(agents(Board.registry(world)))), world)} <> capture_inputs(id, assist, profile, world)
    case U.Agent{id, revision, name, profile, reasoning, instructions, context, concurrency}:
      [AgentIdentityInput{name, instructions, concurrency}, ModelInput{profile, reasoning, Board.profiles(world)}, execution_group(U.AgentEditor{id}, context, world)]
    case U.Fork{task, count, messages, context}: [ForkInput{count, messages}, execution_group(U.ForkEditor{task}, context, world)]
    case U.Compact{task, summary}: [SummaryInput{summary}]

def submit_label(body: U.Body) -> String:
  match body:
    case U.NewTask{message, profile, reasoning, context}: "Start task"
    case U.Message{task, message, delivery}: U.delivery_caption(delivery)
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
    case True{}: Unavailable{"Submission is pending or the context origin or model selection is invalid"}
    case False{}: preparation_availability(U.required_workspace(body), body, now, world)

def editor_scene(draft: U.Draft, pending: +List<E.Pending>, now: U32, +world: M.World()) -> EditorScene:
  U.Draft{revision, +body, feedback, directory_entry} = draft
  +identity = U.owner(body)
  +waiting = E.busy(pending, identity)
  EditorScene{identity, revision, input_groups(body, world), Forms.structure(body),
    ControlDeclaration{"submit/" ++ U.editor_key(identity), submit_label(body), Primary{}, U.Activate{U.Submit{identity}},
      submit_availability(waiting || Bool.not(U.valid_origin(body)) || Bool.not(U.model_permitted(body, world)), body, now, world)}, feedback, waiting}

def found_composer(found: Maybe<&2, U.Draft>, pending: +List<E.Pending>, now: U32, +world: M.World()) -> Maybe<&2, ComposerScene>:
  match found:
    case None{}: None{}
    case Some{U.Draft{revision, +body, feedback, directory_entry}}: composer_scene(body, editor_scene(U.Draft{revision, body, feedback, directory_entry}, pending, now, world), world)

def composer(identity: U.Editor, session: E.Session, world: M.World()) -> Maybe<&2, ComposerScene>:
  E.Session{route, drafts, readers, layers, focus, navigation, filter, now, next, pending, previews, code_blocks, next_layer} = session
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
  E.Session{route, drafts, readers, layers, focus, navigation, filter, now, next, pending, previews, code_blocks, next_layer} = session
  optional_editor(E.find_draft(drafts, identity), pending, now, world)


def registered_project(found: Maybe<&2, D.Project>, id: Nat) -> Maybe<&2, Nat>:
  match found:
    case None{}: None{}
    case Some{project}: Some{id}

def validate_project(selected: Maybe<&2, Nat>, world: M.World()) -> Maybe<&2, Nat>:
  match selected:
    case None{}: None{}
    case Some{+id}: registered_project(Projects.find(Projects.registry(F.State(), world), id), id)

def task_project(found: Maybe<&2, D.Task>) -> Maybe<&2, Nat>:
  match found:
    case None{}: None{}
    case Some{task}: Workspace.project_id(D.task_context(task))

def draft_project(found: Maybe<&2, U.Draft>, +world: M.World()) -> Maybe<&2, Nat>:
  match found:
    case Some{U.Draft{revision, U.NewTask{message, profile, reasoning, configuration}, feedback, directory_entry}}:
      project_choice_id(creation_selected_project(Some{Context.preview(configuration, world)}, world))
    case _: None{}

def route_project(route: U.Route, drafts: +List<U.Draft>, +world: M.World()) -> Maybe<&2, Nat>:
  match route:
    case U.ProjectHome{id}: validate_project(Some{id}, world)
    case U.Conversation{id}: validate_project(task_project(Tasks.find(Commands.entries(world), id)), world)
    case U.Start{}: draft_project(E.find_draft(drafts, U.NewTaskEditor{}), world)
    case _: None{}

def active_project(route: U.Route, session: E.Session, world: M.World()) -> Maybe<&2, Nat>:
  E.Session{r, drafts, readers, layers, focus, navigation, filter, now, next, pending, previews, code, next_layer} = session
  route_project(route, drafts, world)

def same_project(left: Maybe<&2, Nat>, right: Maybe<&2, Nat>) -> Bool:
  match left right:
    case None{} None{}: True{}
    case Some{left} Some{right}: Nat.is_eq(left, right)
    case _ _: False{}

def selected_project(selected: Maybe<&2, Nat>, project: Nat) -> Bool:
  same_project(selected, Some{project})

def task_entry(+task: D.Task, route: U.Route) -> TaskEntry:
  +id = D.task_id(task)
  TaskEntry{id, Conversation.title(task), task_status(task), U.route_owns(route, id),
    control("task/" ++ Nat.show(id), Conversation.title(task), U.Navigate{U.Conversation{id}})}

def task_entries(tasks: +List<D.Task>, +route: U.Route) -> +List<TaskEntry>:
  match tasks:
    case Nil{}: Nil{}
    case Con{task, rest}: task_entry(task, route) <> task_entries(rest, route)

def keep_task(keep: Bool, task: D.Task, rest: +List<D.Task>) -> +List<D.Task>:
  match keep:
    case True{}: task <> rest
    case False{}: rest

def project_tasks(tasks: +List<D.Task>, +project: Maybe<&2, Nat>) -> +List<D.Task>:
  match tasks:
    case Nil{}: Nil{}
    case Con{+task, rest}: keep_task(same_project(Workspace.project_id(D.task_context(task)), project), task, project_tasks(rest, project))

def project_entry(+id: Nat, project: D.Project, tasks: +List<D.Task>, +route: U.Route, selected: Maybe<&2, Nat>, navigation: E.NavigationState) -> ProjectEntry:
  D.Project{+name, workspace, guidance} = project
  ProjectEntry{id, name, workspace, selected_project(selected, id), Bool.not(E.project_collapsed(navigation, id)), task_entries(project_tasks(tasks, Some{id}), route),
    control("project/" ++ Nat.show(id), name, U.SelectProject{Some{id}}), control("project/new-task/" ++ Nat.show(id), "New task", U.BeginTask{Some{id}}),
    control("project/toggle/" ++ Nat.show(id), "Toggle project tasks", U.ToggleProjectGroup{id}),
    context_control("project/more/" ++ Nat.show(id), "More", U.ObjectActions{U.ProjectSubject{id}})}

def project_entries(entries: +List<Finite.Entry(D.Project)>, +tasks: +List<D.Task>, +route: U.Route, +selected: Maybe<&2, Nat>, +navigation: E.NavigationState) -> +List<ProjectEntry>:
  match entries:
    case Nil{}: Nil{}
    case Con{(id, project), rest}: project_entry(id, project, tasks, route, selected, navigation) <> project_entries(rest, tasks, route, selected, navigation)

def navigation(+expanded: Bool, +route: U.Route, +world: M.World(), +session: E.Session) -> Navigation:
  E.Session{r, drafts, readers, layers, attention, +nav, filter, now, next, pending, previews, code, next_layer} = session
  Navigation{expanded, control("new-task", "新任务", U.BeginTask{None{}}),
    [control("board", "任务看板", U.Navigate{U.TaskBoard{}}), control("projects", "项目", U.Navigate{U.ProjectCollection{}}), control("agents", "智能体", U.Navigate{U.AgentCollection{}})],
    project_entries(Projects.entries(Projects.registry(F.State(), world)), Commands.entries(world), route, active_project(route, session, world), nav), task_entries(project_tasks(Commands.entries(world), None{}), route),
    ControlDeclaration{"navigation/toggle", "Toggle sidebar", Secondary{}, U.SetNavigation{Bool.not(expanded)}, Available{}}}

def task_details(+task: D.Task) -> TaskDetails:
  D.Task{id, lineage, D.Contract{+model, tools, max_fork, max_descendants, plugins, +context}, status, history, queued, phase, operations, notified} = task
  TaskDetails{Context.effective(task), model, tools, lineage, queued, status, phase}

def lifecycle(+id: Nat, +value: D.Control, +label: String, world: M.World()) -> ControlDeclaration:
  native("task/" ++ Nat.show(id) ++ "/" ++ label, label, Secondary{}, U.ControlTask{id, value}, world)

def task_actions(+id: Nat, +world: M.World()) -> TaskActions:
  TaskActions{control("details/" ++ Nat.show(id), "Task details", U.TogglePanel{U.TaskDetails{id}, "details/" ++ Nat.show(id)}),
    [lifecycle(id, D.Interrupt{}, "Interrupt", world), lifecycle(id, D.Freeze{}, "Freeze", world), lifecycle(id, D.Unfreeze{}, "Resume", world),
    lifecycle(id, D.Stop{}, "Stop", world), lifecycle(id, D.Archive{}, "Archive", world),
    control("fork/" ++ Nat.show(id), "Fork", U.ForkTask{id}), control("compact/" ++ Nat.show(id), "Compact", U.CompactTask{id})]}

def task_scene(+task: D.Task, +session: E.Session, +world: M.World()) -> TaskScene:
  E.Session{route, drafts, readers, layers, focus, navigation, filter, now, next, pending, previews, code_blocks, next_layer} = session
  +id = D.task_id(task)
  TaskScene{id, Conversation.title(task), task_status(task), Context.effective(task), ConversationWorld.timeline(E.reader(readers, id), task, world), Live.for_task(Live.retained(previews, world), id),
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
    case Con{+stage, rest}: MoveDestination{stage, None{}, "Move to end of " ++ B.stage_label(stage), operation_availability(Commands.resolve(M.FeatureCommand{F.BoardCommand{B.Move{id, revision, stage, None{}, now}}}, world))} <>
      move_destinations(rest, id, revision, now, world)

def link_candidates(tasks: +List<D.Task>, +id: Nat, +revision: Nat, +now: U32, +world: M.World()) -> +List<ControlDeclaration>:
  match tasks:
    case Nil{}: Nil{}
    case Con{+task, rest}: board_control("card/link/" ++ Nat.show(id) ++ "/" ++ Nat.show(D.task_id(task)), Conversation.title(task),
      B.Link{id, revision, D.task_id(task), now}, world) <> link_candidates(rest, id, revision, now, world)

def before_destination(eligible: Bool, +target: Nat, +value: B.Card, id: Nat, revision: Nat, now: U32, world: M.World()) -> +List<MoveDestination>:
  match eligible:
    case False{}: Nil{}
    case True{}:
      [MoveDestination{B.card_stage(B.draft(value)), Some{target}, "Move before " ++ B.title(B.draft(value)),
        operation_availability(Commands.resolve(M.FeatureCommand{F.BoardCommand{B.Move{id, revision, B.card_stage(B.draft(value)), Some{target}, now}}}, world))}]

def before_destinations(cards: +List<Finite.Entry(B.Card)>, +id: Nat, +revision: Nat, +now: U32, +world: M.World()) -> +List<MoveDestination>:
  match cards:
    case Nil{}: Nil{}
    case Con{(+target, +value), rest}:
      List.append(&2, MoveDestination, before_destination(Bool.not(B.archived(value)) && Bool.not(Nat.is_eq(target, id)), target, value, id, revision, now, world), before_destinations(rest, id, revision, now, world))
def card_scene(+id: Nat, +card: B.Card, route: U.Route, +now: U32, +world: M.World()) -> CardScene:
  B.Card{+revision, draft, task, archived, created, updated, enrichment, error, pinned} = card
  CardScene{id, card, control("card/" ++ Nat.show(id), "打开 " ++ B.title(B.draft(card)), U.OpenPanel{U.CardDetails{id}, "card/" ++ Nat.show(id)}),
    [board_control("card/run/" ++ Nat.show(id), "Run", B.Run{id, revision, now}, world),
      board_control("card/archive/" ++ Nat.show(id), "Archive or restore", B.Archive{id, revision, Bool.not(archived), now}, world),
      board_control("card/pin/" ++ Nat.show(id), "Pin or unpin", B.Pin{id, revision, Bool.not(pinned), now}, world),
      board_control("card/delete/" ++ Nat.show(id), "Delete", B.Delete{id, revision}, world),
      board_control("card/regenerate/" ++ Nat.show(id), "Regenerate title", B.Regenerate{id, revision, B.draft_profile(Board.registry(world)), now}, world)], linked_task(task, route, world),
    List.append(&2, MoveDestination, move_destinations(B.stages(), id, revision, now, world), before_destinations(B.cards(Board.registry(world)), id, revision, now, world)), link_candidates(Commands.entries(world), id, revision, now, world)}

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
    case Con{+stage, rest}: BoardColumn{stage, card_scenes(Filter.column(cards, B.stage_name(stage)), route, now, world),
      control("card/new", "新建任务", U.NewCard{stage})} <> columns(rest, cards, route, now, world)

def face_project_name(found: Maybe<&2, D.Project>, id: Nat) -> String:
  match found:
    case None{}: "项目 #" ++ Nat.show(id) ++ " 不可用"
    case Some{D.Project{name, workspace, guidance}}: name

def face_project(found: Maybe<&2, Nat>, +world: M.World()) -> String:
  match found:
    case None{}: ""
    case Some{+id}: face_project_name(Projects.find(Projects.registry(F.State(), world), id), id)

def elapsed_label_days(recent: Bool, +seconds: U32) -> String:
  match recent:
    case True{}: U32.show(U32.div(seconds, 3600)) ++ "小时前"
    case False{}: U32.show(U32.div(seconds, 86400)) ++ "天前"

def elapsed_label_hours(recent: Bool, +seconds: U32) -> String:
  match recent:
    case True{}: U32.show(U32.div(seconds, 60)) ++ "分钟前"
    case False{}: elapsed_label_days(U32.is_lt(seconds, 86400), seconds)

def elapsed_label_minutes(recent: Bool, +seconds: U32) -> String:
  match recent:
    case True{}: "刚刚"
    case False{}: elapsed_label_hours(U32.is_lt(seconds, 3600), seconds)

def elapsed_label(+seconds: U32) -> String:
  elapsed_label_minutes(U32.is_lt(seconds, 60), seconds)

def card_face(+id: Nat, +card: B.Card, +now: U32, +world: M.World()) -> CardFace:
  +draft = B.draft(card)
  CardFace{id, B.title(draft), B.description(draft), B.card_priority(draft), B.pinned(card),
    Board.activity_label(Board.activity(card, world)), face_project(B.project(draft), world), B.labels(draft),
    face_owner(B.card_owner(draft), world), elapsed_label(Filter.elapsed(now, B.updated(card)))}

def archived_cards(board: B.State, route: U.Route, now: U32, world: M.World()) -> +List<CardScene>:
  B.State{cards, next_card, agents, next_agent, automatic, profile} = board
  card_scenes(List.filter(~Finite.Entry(B.Card), archived_card, cards), route, now, world)

def board_page(+board: B.State, +filter: B.Filter, +route: U.Route, +now: U32, +world: M.World()) -> Page:
  BoardPage{filter, columns(B.stages(), Filter.filtered(Board.display_cards(board), filter, now, world), route, now, world),
    ControlDeclaration{"card/new", "新建任务", Primary{}, U.Activate{U.NewCard{B.Todo{}}}, Available{}},
    Filter.working(B.cards(Board.registry(world)), world),
    control("board/settings", "看板设置", U.OpenPanel{U.BoardSettings{}, "board/settings"}),
    control("board/filters", "筛选任务", U.OpenPanel{U.BoardFilters{}, "board/filters"}),
    control("board/archive", "归档任务 " ++ Nat.show(List.length(&2, CardScene, archived_cards(board, route, now, world))), U.OpenPanel{U.ArchivedCards{}, "board/archive"})}

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
      E.Session{old_route, drafts, readers, layers, focus, navigation, filter, now, next, pending, previews, code_blocks, next_layer} = session
      board_page(Board.registry(world), filter, route, now, world)
    case U.AgentCollection{}: AgentsPage{agent_scenes(agents(Board.registry(world)), world), control("agent/new", "New agent", U.EditAgent{None{}})}

def task_menu(actions: TaskActions) -> +List<ControlDeclaration>:
  TaskActions{details, overflow} = actions
  overflow

def card_moves(values: +List<MoveDestination>, +id: Nat, +revision: Nat, +now: U32, +world: M.World()) -> +List<ControlDeclaration>:
  match values:
    case Nil{}: Nil{}
    case Con{MoveDestination{+stage, +before, label, availability}, rest}:
      board_control("card/move/" ++ B.stage_name(stage) ++ "/" ++ U.optional_key(before), label, B.Move{id, revision, stage, before, now}, world) <> card_moves(rest, id, revision, now, world)
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
    case U.ProjectSubject{+id}: [control("project/details/" ++ Nat.show(id), "Project details", U.Navigate{U.ProjectHome{id}}), control("project/edit/" ++ Nat.show(id), "Edit project", U.EditProject{Some{id}}),
      native("project/delete/" ++ Nat.show(id), "Delete project", Destructive{}, U.DeleteProject{id}, world)]
    case U.CardSubject{+id}: card_menu(Finite.find(~B.Card, board_cards(Board.registry(world)), id), id, now, world)
    case U.AgentSubject{+id}: agent_menu(Finite.find(~B.AgentProfile, agents(Board.registry(world)), id), id, world)

def subject_actions(subject: U.Subject, session: E.Session, world: M.World()) -> +List<ControlDeclaration>:
  E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer} = session
  subject_controls(subject, now, world)

def board_settings(board: B.State, +world: M.World()) -> LayerContent:
  B.State{cards, next_card, agents, next_agent, +automatic, +draft_profile} = board
  BoardSettings{automatic, draft_profile, Board.profiles(world),
    board_control("board/automatic", "自动排期", B.Settings{Bool.not(automatic), draft_profile}, world)}

def found_card_details(found: Maybe<&2, B.Card>, id: Nat, route: U.Route, now: U32, world: M.World()) -> Maybe<&2, CardScene>:
  match found:
    case None{}: None{}
    case Some{card}: Some{card_scene(id, card, route, now, world)}

def layer_content(panel: U.Panel, +session: E.Session, +world: M.World()) -> LayerContent:
  match panel:
    case U.ProjectPicker{}:
      E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code, next_layer} = session
      ProjectSelection{"", draft_project(E.find_draft(drafts, U.NewTaskEditor{}), world), project_choices(Projects.entries(Projects.registry(F.State(), world)))}
    case U.ObjectActions{subject}: ObjectActions{subject_actions(subject, session, world)}
    case U.ArchivedCards{}:
      E.Session{route, drafts, readers, layers, focus, navigation, filter, now, next, pending, previews, code_blocks, next_layer} = session
      ArchivedCards{archived_cards(Board.registry(world), route, now, world)}
    case U.CardDetails{+card}:
      E.Session{+route, drafts, readers, layers, attention, navigation, filter, +now, next, pending, previews, code, next_layer} = session
      CardDetails{found_card_details(B.find(Board.registry(world), card), card, route, now, world)}
    case U.BoardSettings{}: board_settings(Board.registry(world), world)
    case U.BoardFilters{}:
      E.Session{route, drafts, readers, layers, attention, navigation, +filter, now, next, pending, previews, code_blocks, next_layer} = session
      BoardFilters{filter}
    case U.EditObject{id}: ObjectEditor{editor(id, session, world)}
    case U.TaskDetails{task}: ExecutionDetails{optional_task(Tasks.find(Commands.entries(world), task), session, world)}
    case U.WorkspaceConfiguration{+id}: WorkspaceSettings{id, selected_fields(editor(id, session, world), ExecutionFields{})}
    case U.PermissionsConfiguration{+id}: PermissionSettings{id, selected_fields(editor(id, session, world), ExecutionFields{})}
    case U.TaskContext{task}: CommittedContext{committed_context(Tasks.find(Commands.entries(world), task))}
    case U.ModelPicker{+id}: ModelSelection{id, "", selected_fields(editor(id, session, world), ModelFields{})}
    case U.DeliveryPicker{+task}: DeliverySelection{U.MessageEditor{task}, selected_fields(editor(U.MessageEditor{task}, session, world), DeliveryFields{})}
    case U.Confirm{command, title, destination}: Confirmation{title,
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
    case U.WorkspaceConfiguration{editor}: AnchoredMenu{}
    case U.PermissionsConfiguration{editor}: AnchoredMenu{}
    case U.TaskDetails{task}: details_kind(beside)
    case _: ModalDialog{}

def profile_matches(profile: D.Profile, query: String) -> Bool:
  D.Profile{key, provider, name, policy, options} = profile
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

def project_search_paths(values: +List<String>) -> String:
  match values:
    case Nil{}: ""
    case Con{path, rest}: path ++ " " ++ project_search_paths(rest)

def project_primary_text(primary: Maybe<&2, String>) -> String:
  match primary:
    case None{}: "No primary directory"
    case Some{path}: path

def project_folder_description(workspace: D.Workspace) -> String:
  D.Workspace{roots, primary} = workspace
  project_primary_text(primary)

def project_matches(project: ProjectChoice, query: String) -> Bool:
  ProjectChoice{id, name, D.Workspace{roots, primary}} = project
  String.contains(String.to_lower(name ++ " " ++ project_search_paths(roots) ++ " " ++ project_primary_text(primary)), String.to_lower(String.trim(query)))

def keep_project_choice(matches: Bool, project: ProjectChoice, rest: +List<ProjectChoice>) -> +List<ProjectChoice>:
  match matches:
    case True{}: project <> rest
    case False{}: rest

def matching_projects(projects: +List<ProjectChoice>, +query: String) -> +List<ProjectChoice>:
  match projects:
    case Nil{}: Nil{}
    case Con{+project, rest}: keep_project_choice(project_matches(project, query), project, matching_projects(rest, query))

def search_content(content: LayerContent, +query: String) -> LayerContent:
  match content:
    case ProjectSelection{old, selected, projects}: ProjectSelection{query, selected, matching_projects(projects, query)}
    case ModelSelection{editor, old, fields}: ModelSelection{editor, query, search_fields(fields, query)}
    case other: other
def layer_dismissal(panel: U.Panel, trigger: String) -> Dismissal:
  match panel:
    case U.TaskDetails{task}: ByTrigger{U.TogglePanel{U.TaskDetails{task}, trigger}}
    case _: OutsideOrEscape{U.ClosePanel{}}

def layers(entries: +List<E.Layer>, +session: E.Session, +world: M.World(), +beside: Bool) -> +List<Layer>:
  match entries:
    case Nil{}: Nil{}
    case Con{E.Layer{+panel, +trigger, initial, +query, layer_occurrence}, rest}:
      Layer{layer_kind(panel, beside), search_content(layer_content(panel, session, world), query), initial, trigger, layer_dismissal(panel, trigger)} <> layers(rest, session, world, beside)

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

def has_composer(composer: Maybe<&2, ComposerScene>) -> Bool:
  match composer:
    case None{}: False{}
    case Some{scene}: True{}

def has_decisions(decisions: +List<ConversationWorld.DecisionRequest>) -> Bool:
  match decisions:
    case Nil{}: False{}
    case Con{decision, rest}: True{}

def has_return_latest(action: Maybe<&2, U.Input>) -> Bool:
  match action:
    case None{}: False{}
    case Some{input}: True{}

def page_composition(page: Page) -> Composition.Page:
  match page:
    case StartPage{composer}: Composition.Creation{has_composer(composer)}
    case TaskPage{task}:
      TaskScene{task_id, title, status, context, timeline, previews, composer, details, actions} = task
      ConversationWorld.Timeline{id, generation, groups, operations, decisions, reading, return_to_latest} = timeline
      Composition.Conversation{has_composer(composer), has_decisions(decisions), has_return_latest(return_to_latest)}
    case ProjectPage{project}: Composition.ProjectOverview{}
    case ProjectsPage{projects, create}: Composition.ProjectCollection{}
    case BoardPage{filter, columns, create, working, settings, filters, archive}: Composition.TaskBoard{}
    case AgentsPage{agents, create}: Composition.AgentCollection{}
    case MissingObject{message}: Composition.Unavailable{}

def arrangement(beside: Bool, expanded: Bool) -> Arrangement:
  Arrangement{navigation_placement(beside, expanded)}

def scene_page(scene: Scene) -> Composition.Page:
  Scene{navigation, +main, layers, arrangement, attention} = scene
  page_composition(main)

def finish_scene(navigation: Navigation, +main: Page, +layers: +List<Layer>, beside: Bool, expanded: Bool, attention: String) -> Scene:
  Scene{navigation, main, layers, arrangement(beside, expanded), attention}

def observe_session(capacity: Capacity, +program: M.World(), +session: E.Session) -> Scene:
  Capacity{+navigation_beside, details_beside} = capacity
  E.Session{+route, drafts, readers, open_layers, focus, +expanded, filter, now, next, pending, previews, code_blocks, next_layer} = session
  +visible = navigation_visible(E.navigation_visibility(expanded), navigation_beside)
  +main = page(route, session, program)
  finish_scene(navigation(visible, route, program, session), main, layers(open_layers, session, program, details_beside), navigation_beside, visible, focus)

def observe(capacity: Capacity, application: E.Application) -> Scene:
  E.Application{+program, +session} = application
  observe_session(capacity, program, session)
