import Base
import ../conversation/OUTPUT.bend as Live
import ../submission/FIELDS.bend as Forms
import ../../harness/MODEL.bend as M
import ../../harness/COMMANDS.bend as Commands
import ../../harness/workspace/PROJECTS.bend as Projects
import ../../harness/workspace/WORKSPACE.bend as Workspace
import ../../features/board/MODEL.bend as B
import ../../harness/features/MODEL.bend as F
import ../../harness/DOMAIN.bend as D
import ../../bendlib/association-map.bend as Finite
import ../../features/board/STATE.bend as Board
import ../../features/board/filter.bend as Filter
import ../../harness/conversation/PROGRAM.bend as Conversation
import ../../harness/tasks/PROGRAM.bend as Tasks
import ./COMPOSITION.bend as Composition
import ../INPUT.bend as U
import ../services/CONTEXT.bend as Context
import ../session/MODEL.bend as E
import ../conversation/MODEL.bend as ConversationWorld
import ./MODEL.bend as ViewTypes

def task_status(+task: D.Task) -> ViewTypes.TaskStatus:
  ViewTypes.TaskStatus{D.task_status(task), Conversation.working(D.task_phase(task), D.task_operations(task))}

def task_status_label(value: ViewTypes.TaskStatus) -> String:
  ViewTypes.TaskStatus{lifecycle, working} = value
  Conversation.status_label(lifecycle, working)

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

def layer_title(content: ViewTypes.LayerContent) -> String:
  match content:
    case ViewTypes.ProjectSelection{query, selected, projects}: "Select project"
    case ViewTypes.ObjectActions{actions}: "Actions"
    case ViewTypes.ArchivedCards{cards}: "Archived cards"
    case ViewTypes.BoardSettings{automatic, draft_profile, assistance_profiles, automation}: "看板设置"
    case ViewTypes.BoardFilters{filter}: "筛选任务"
    case ViewTypes.CardDetails{card}: "任务详情"
    case ViewTypes.ObjectEditor{None{}}: "Editor unavailable"
    case ViewTypes.ObjectEditor{Some{ViewTypes.EditorScene{identity, revision, groups, sections, submit, feedback, pending}}}: editor_title(identity)
    case ViewTypes.WorkspaceSettings{editor, fields}: "Working directories"
    case ViewTypes.PermissionSettings{editor, fields}: "Permissions"
    case ViewTypes.CommittedContext{context}: "Execution context"
    case ViewTypes.ModelSelection{editor, query, fields}: "Choose model"
    case ViewTypes.DeliverySelection{editor, fields}: "Delivery options"
    case ViewTypes.ExecutionDetails{task}: "Task details"
    case ViewTypes.Confirmation{title, confirm, cancel}: title

# Capacity describes available simultaneous regions, not a device or toolkit.

def field_selected(selection: ViewTypes.FieldSelection, field: ViewTypes.InputGroup) -> Bool:
  match selection field:
    case ViewTypes.ExecutionFields{} ViewTypes.ExecutionInput{configuration, preview, workspace, projects, reviewers}: True{}
    case ViewTypes.ModelFields{} ViewTypes.ModelInput{profile, reasoning, choices}: True{}
    case ViewTypes.DeliveryFields{} ViewTypes.DeliveryInput{selected, send, steer}: True{}
    case _ _: False{}

def keep_field(yes: Bool, field: ViewTypes.InputGroup, rest: +List<ViewTypes.InputGroup>) -> +List<ViewTypes.InputGroup>:
  match yes:
    case True{}: field <> rest
    case False{}: rest

def select_fields(fields: +List<ViewTypes.InputGroup>, +selection: ViewTypes.FieldSelection) -> +List<ViewTypes.InputGroup>:
  match fields:
    case Nil{}: Nil{}
    case Con{+field, rest}: keep_field(field_selected(selection, field), field, select_fields(rest, selection))

def selected_fields(editor: Maybe<&2, ViewTypes.EditorScene>, selection: ViewTypes.FieldSelection) -> +List<ViewTypes.InputGroup>:
  match editor:
    case None{}: Nil{}
    case Some{ViewTypes.EditorScene{identity, revision, groups, sections, submit, feedback, pending}}: select_fields(groups, selection)

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

def creation_project(found: Maybe<&2, D.Project>, id: Nat) -> Maybe<&2, ViewTypes.ProjectChoice>:
  match found:
    case None{}: None{}
    case Some{D.Project{name, workspace, guidance}}: Some{ViewTypes.ProjectChoice{id, name, workspace}}

def creation_selected_project(context: Maybe<&2, Context.Preview>, world: M.World()) -> Maybe<&2, ViewTypes.ProjectChoice>:
  match context:
    case Some{Context.ProspectiveContext{origin, Some{+id}, workspace, sandbox, approval, guidance}}:
      creation_project(Projects.find(Projects.registry(F.State(), world), id), id)
    case _: None{}

def creation_heading(project: Maybe<&2, ViewTypes.ProjectChoice>) -> String:
  match project:
    case None{}: "What would you like to build?"
    case Some{ViewTypes.ProjectChoice{id, name, workspace}}: "Work on"

def preview_observation(context: Maybe<&2, Context.Preview>) -> Maybe<&2, Context.Observation>:
  match context:
    case None{}: None{}
    case Some{preview}: Some{Context.DraftExecution{preview}}

def draft_preview(observation: Maybe<&2, Context.Observation>) -> Maybe<&2, Context.Preview>:
  match observation:
    case Some{Context.DraftExecution{preview}}: Some{preview}
    case _: None{}

def project_choice_id(project: Maybe<&2, ViewTypes.ProjectChoice>) -> Maybe<&2, Nat>:
  match project:
    case None{}: None{}
    case Some{ViewTypes.ProjectChoice{id, name, workspace}}: Some{id}

def project_choice_label(project: Maybe<&2, ViewTypes.ProjectChoice>) -> String:
  match project:
    case None{}: "Select project"
    case Some{ViewTypes.ProjectChoice{id, name, workspace}}: name

def creation_context_summary(context: Maybe<&2, Context.Preview>, world: M.World()) -> String:
  match context:
    case None{}: ""
    case Some{preview}: execution_source_summary(Context.DraftExecution{preview}, world)

def control(identity: String, label: String, action: U.Action) -> ViewTypes.ControlDeclaration:
  ViewTypes.ControlDeclaration{identity, label, ViewTypes.Secondary{}, U.Activate{action}, ViewTypes.Available{}}

def context_control(+identity: String, label: String, panel: U.Panel) -> ViewTypes.ControlDeclaration:
  control(identity, label, U.OpenPanel{panel, identity})

def creation_introduction_fields(+context: Maybe<&2, Context.Preview>, +world: M.World()) -> ViewTypes.CreationIntroduction:
  +project = creation_selected_project(context, world)
  ViewTypes.CreationIntroduction{creation_heading(project), creation_context_summary(context, world), context, project,
    context_control("composer/project", project_choice_label(project), U.ProjectPicker{})}

def creation_introduction(composer: Maybe<&2, ViewTypes.ComposerScene>, world: M.World()) -> ViewTypes.CreationIntroduction:
  match composer:
    case None{}: creation_introduction_fields(None{}, world)
    case Some{ViewTypes.ComposerScene{identity, revision, message, footer, context, submit, feedback, pending}}:
      creation_introduction_fields(draft_preview(context), world)

def draft_context_footer(+editor: U.Editor, +observation: Context.Observation, profiles: +List<D.Profile>) -> +List<ViewTypes.ComposerControl>:
  [ViewTypes.ComposerControl{ViewTypes.WorkspaceSubject{}, context_control("composer/workspace/" ++ U.editor_key(editor), observation_workspace(observation), U.WorkspaceConfiguration{editor})},
   ViewTypes.ComposerControl{ViewTypes.PermissionsSubject{}, context_control("composer/permissions/" ++ U.editor_key(editor), observation_permissions(observation, profiles), U.PermissionsConfiguration{editor})}]

def committed_context_footer(+task: Nat, observation: Maybe<&2, Context.Observation>, profiles: +List<D.Profile>) -> +List<ViewTypes.ComposerControl>:
  match observation:
    case None{}: Nil{}
    case Some{+value}:
      [ViewTypes.ComposerControl{ViewTypes.WorkspaceSubject{}, context_control("composer/workspace/message/" ++ Nat.show(task), observation_workspace(value), U.TaskContext{task})},
       ViewTypes.ComposerControl{ViewTypes.PermissionsSubject{}, context_control("composer/permissions/message/" ++ Nat.show(task), observation_permissions(value, profiles), U.TaskContext{task})}]

def composer_scene(body: U.Body, scene: ViewTypes.EditorScene, +world: M.World()) -> Maybe<&2, ViewTypes.ComposerScene>:
  match body:
    case U.NewTask{message, +profile, reasoning, context}:
      ViewTypes.EditorScene{identity, revision, groups, sections, submit, feedback, pending} = scene
      +observation: Context.Observation = Context.DraftExecution{Context.preview(context, world)}
      Some{ViewTypes.ComposerScene{identity, revision, message,
        ViewTypes.ComposerControl{ViewTypes.ModelSubject{}, control("composer/model", profile_label(D.find_profile(Board.profiles(world), profile), profile), U.OpenPanel{U.ModelPicker{U.NewTaskEditor{}}, "composer/model"})} <>
          draft_context_footer(U.NewTaskEditor{}, observation, Board.profiles(world)), Some{observation}, submit, feedback, pending}}
    case U.Message{+task, message, +delivery}:
      ViewTypes.EditorScene{identity, revision, groups, sections, submit, feedback, pending} = scene
      +observation: Maybe<&2, Context.Observation> = committed_observation(committed_context(Tasks.find(Commands.entries(world), task)))
      Some{ViewTypes.ComposerScene{identity, revision, message,
        ViewTypes.ComposerControl{ViewTypes.DeliverySubject{delivery}, control("composer/delivery/" ++ Nat.show(task), U.delivery_caption(delivery), U.OpenPanel{U.DeliveryPicker{task}, "composer/delivery/" ++ Nat.show(task)})} <>
          committed_context_footer(task, observation, Board.profiles(world)), observation, submit, feedback, pending}}
    case _: None{}

def project_choices(entries: +List<Finite.Entry(D.Project)>) -> +List<ViewTypes.ProjectChoice>:
  match entries:
    case Nil{}: Nil{}
    case Con{(id, D.Project{name, workspace, guidance}), rest}: ViewTypes.ProjectChoice{id, name, workspace} <> project_choices(rest)

def projects(world: M.World()) -> +List<ViewTypes.ProjectChoice>:
  project_choices(Projects.entries(Projects.registry(F.State(), world)))

def agents(board: B.State) -> +List<Finite.Entry(B.AgentProfile)>:
  +agents = B.agents(board)
  agents

def is_primary(primary: Maybe<&2, String>, path: String) -> Bool:
  match primary:
    case None{}: False{}
    case Some{value}: String.eq(value, path)

def root_controls(roots: +List<String>, +primary: Maybe<&2, String>, +editor: U.Editor) -> +List<ViewTypes.WorkspaceRoot>:
  match roots:
    case Nil{}: Nil{}
    case Con{+path, rest}:
      ViewTypes.WorkspaceRoot{path, is_primary(primary, path),
        ViewTypes.ControlDeclaration{"primary/" ++ U.editor_key(editor) ++ "/" ++ path, "Use as working directory", ViewTypes.Secondary{},
          U.EditDraft{editor, U.EditWorkspace{Context.ChoosePrimary{path}}}, ViewTypes.Available{}},
        ViewTypes.ControlDeclaration{"remove-root/" ++ U.editor_key(editor) ++ "/" ++ path, "Remove directory", ViewTypes.Secondary{},
          U.EditDraft{editor, U.EditWorkspace{Context.RemoveRoot{path}}}, ViewTypes.Available{}}} <> root_controls(rest, primary, editor)

def workspace_controls(workspace: D.Workspace, +editor: U.Editor, inherit: Maybe<&2, ViewTypes.ControlDeclaration>) -> ViewTypes.WorkspaceControls:
  D.Workspace{roots, primary} = workspace
  ViewTypes.WorkspaceControls{editor, root_controls(roots, primary, editor), inherit}

def preview_workspace(preview: Context.Preview) -> D.Workspace:
  match preview:
    case Context.ContextUnavailable{reason}: D.Workspace{Nil{}, None{}}
    case Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}: Context.selected_workspace(workspace)

def workspace_inheritance(override: Maybe<&2, D.Workspace>, +identity: U.Editor) -> Maybe<&2, ViewTypes.ControlDeclaration>:
  match override:
    case None{}: None{}
    case Some{workspace}: Some{ViewTypes.ControlDeclaration{"inherit-workspace/" ++ U.editor_key(identity), "Use inherited workspace", ViewTypes.Secondary{},
      U.EditDraft{identity, U.ConfigureContext{Context.UseDefaultWorkspace{}}}, ViewTypes.Available{}}}

def configuration_workspace(config: Context.Configuration) -> Maybe<&2, D.Workspace>:
  Context.Configuration{origin, workspace, sandbox, approval} = config
  workspace

def execution_group(+identity: U.Editor, +config: Context.Configuration, +world: M.World()) -> ViewTypes.InputGroup:
  +observed = Context.preview(config, world)
  ViewTypes.ExecutionInput{config, observed,
    workspace_controls(preview_workspace(observed), identity,
      workspace_inheritance(configuration_workspace(config), identity)),
    projects(world), List.filter(~D.Profile, (profile => Workspace.valid_reviewer_profile(profile)), Board.profiles(world))}

def delivery_controls(+task: Nat, selected: U.Delivery) -> ViewTypes.InputGroup:
  ViewTypes.DeliveryInput{selected,
    ViewTypes.ControlDeclaration{"choose-send/" ++ Nat.show(task), U.delivery_caption(U.Send{}), ViewTypes.Secondary{}, U.EditDraft{U.MessageEditor{task}, U.ChooseDelivery{U.Send{}}}, ViewTypes.Available{}},
    ViewTypes.ControlDeclaration{"choose-steer/" ++ Nat.show(task), U.delivery_caption(U.Steer{}), ViewTypes.Secondary{}, U.EditDraft{U.MessageEditor{task}, U.ChooseDelivery{U.Steer{}}}, ViewTypes.Available{}}}

def face_profile_name(found: Maybe<&2, D.Profile>, +key: String) -> String:
  match found:
    case None{}: "配置 " ++ key ++ " 不可用"
    case Some{D.Profile{key, provider, name, reasoning, options}}: name

def face_agent_name(found: Maybe<&2, B.AgentProfile>, id: Nat) -> String:
  match found:
    case None{}: "智能体 #" ++ Nat.show(id) ++ " 不可用"
    case Some{+agent}: B.agent_name(agent)

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

def capture_inputs(id: Maybe<&2, Nat>, assist: Bool, profile: String, world: M.World()) -> +List<ViewTypes.InputGroup>:
  match id:
    case None{}: [ViewTypes.CardAssistanceInput{assist, profile, Board.profiles(world)}]
    case Some{id}: Nil{}

def input_groups(body: U.Body, +world: M.World()) -> +List<ViewTypes.InputGroup>:
  match body:
    case U.NewTask{message, profile, reasoning, context}: [ViewTypes.MessageInput{message}, ViewTypes.ModelInput{profile, reasoning, Board.profiles(world)}, execution_group(U.NewTaskEditor{}, context, world)]
    case U.Message{task, message, delivery}: [ViewTypes.MessageInput{message}, delivery_controls(task, delivery)]
    case U.Project{id, name, +workspace}: [ViewTypes.ProjectNameInput{name}, ViewTypes.ProjectWorkspaceInput{workspace, workspace_controls(workspace, U.ProjectEditor{id}, None{})}]
    case U.Card{id, revision, value, assist, profile, keep_open}:
      ViewTypes.CardContentInput{value, projects(world), B.stages(),
        B.priorities(), card_owner_choices(B.Unassigned{} <> B.Self{} <> profile_owners(Board.profiles(world), agent_owners(agents(Board.registry(world)))), world)} <> capture_inputs(id, assist, profile, world)
    case U.Agent{id, revision, name, profile, reasoning, instructions, context, concurrency}:
      [ViewTypes.AgentIdentityInput{name, instructions, concurrency}, ViewTypes.ModelInput{profile, reasoning, Board.profiles(world)}, execution_group(U.AgentEditor{id}, context, world)]
    case U.Fork{task, count, messages, context}: [ViewTypes.ForkInput{count, messages}, execution_group(U.ForkEditor{task}, context, world)]
    case U.Compact{task, summary}: [ViewTypes.SummaryInput{summary}]

def submit_label(body: U.Body) -> String:
  match body:
    case U.NewTask{message, profile, reasoning, context}: "Start task"
    case U.Message{task, message, delivery}: U.delivery_caption(delivery)
    case U.Fork{task, count, messages, context}: "Fork task"
    case U.Compact{task, summary}: "Compact history"
    case _: "Save"

def operation_availability(operation: Commands.Operation) -> ViewTypes.Availability:
  match operation:
    case Commands.Refuse{code, reason}: ViewTypes.Unavailable{reason}
    case _: ViewTypes.Available{}

def preparation_availability(workspace: Maybe<&2, D.Workspace>, body: U.Body, now: U32, world: M.World()) -> ViewTypes.Availability:
  match workspace:
    case None{}: operation_availability(Commands.resolve(U.command(body, now), world))
    case Some{value}: ViewTypes.NeedsDirectoryObservation{}

def submit_availability(blocked: Bool, +body: U.Body, now: U32, world: M.World()) -> ViewTypes.Availability:
  match blocked:
    case True{}: ViewTypes.Unavailable{"Submission is pending or the context origin or model selection is invalid"}
    case False{}: preparation_availability(U.required_workspace(body), body, now, world)

def editor_scene(draft: U.Draft, pending: +List<E.Pending>, now: U32, +world: M.World()) -> ViewTypes.EditorScene:
  U.Draft{revision, +body, feedback, directory_entry} = draft
  +identity = U.owner(body)
  +waiting = E.busy(pending, identity)
  ViewTypes.EditorScene{identity, revision, input_groups(body, world), Forms.structure(body),
    ViewTypes.ControlDeclaration{"submit/" ++ U.editor_key(identity), submit_label(body), ViewTypes.Primary{}, U.Activate{U.Submit{identity}},
      submit_availability(waiting || Bool.not(U.valid_origin(body)) || Bool.not(U.model_permitted(body, world)), body, now, world)}, feedback, waiting}

def found_composer(found: Maybe<&2, U.Draft>, pending: +List<E.Pending>, now: U32, +world: M.World()) -> Maybe<&2, ViewTypes.ComposerScene>:
  match found:
    case None{}: None{}
    case Some{U.Draft{revision, +body, feedback, directory_entry}}: composer_scene(body, editor_scene(U.Draft{revision, body, feedback, directory_entry}, pending, now, world), world)

def composer(identity: U.Editor, +session: E.Session, world: M.World()) -> Maybe<&2, ViewTypes.ComposerScene>:
  drafts = E.drafts(session)
  now = E.now(session)
  pending = E.pending(session)
  found_composer(E.find_draft(drafts, identity), pending, now, world)

def action_availability(command: Maybe<&2, M.Command>, world: M.World()) -> ViewTypes.Availability:
  match command:
    case None{}: ViewTypes.Available{}
    case Some{command}: operation_availability(Commands.resolve(command, world))

def native(identity: String, label: String, prominence: ViewTypes.Prominence, +action: U.Action, world: M.World()) -> ViewTypes.ControlDeclaration:
  ViewTypes.ControlDeclaration{identity, label, prominence, U.Activate{action}, action_availability(U.direct_command(action), world)}

def optional_editor(found: Maybe<&2, U.Draft>, pending: +List<E.Pending>, now: U32, world: M.World()) -> Maybe<&2, ViewTypes.EditorScene>:
  match found:
    case None{}: None{}
    case Some{draft}: Some{editor_scene(draft, pending, now, world)}

def editor(identity: U.Editor, +session: E.Session, world: M.World()) -> Maybe<&2, ViewTypes.EditorScene>:
  drafts = E.drafts(session)
  now = E.now(session)
  pending = E.pending(session)
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
  drafts = E.drafts(session)
  route_project(route, drafts, world)

def same_project(left: Maybe<&2, Nat>, right: Maybe<&2, Nat>) -> Bool:
  match left right:
    case None{} None{}: True{}
    case Some{left} Some{right}: Nat.is_eq(left, right)
    case _ _: False{}

def selected_project(selected: Maybe<&2, Nat>, project: Nat) -> Bool:
  same_project(selected, Some{project})

def task_entry(+task: D.Task, route: U.Route) -> ViewTypes.TaskEntry:
  +id = D.task_id(task)
  ViewTypes.TaskEntry{id, Conversation.title(task), task_status(task), U.route_owns(route, id),
    control("task/" ++ Nat.show(id), Conversation.title(task), U.Navigate{U.Conversation{id}})}

def task_entries(tasks: +List<D.Task>, +route: U.Route) -> +List<ViewTypes.TaskEntry>:
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

def project_entry(+id: Nat, project: D.Project, tasks: +List<D.Task>, +route: U.Route, selected: Maybe<&2, Nat>, navigation: E.NavigationState) -> ViewTypes.ProjectEntry:
  D.Project{+name, workspace, guidance} = project
  ViewTypes.ProjectEntry{id, name, workspace, selected_project(selected, id), Bool.not(E.project_collapsed(navigation, id)), task_entries(project_tasks(tasks, Some{id}), route),
    control("project/" ++ Nat.show(id), name, U.SelectProject{Some{id}}), control("project/new-task/" ++ Nat.show(id), "New task", U.BeginTask{Some{id}}),
    control("project/toggle/" ++ Nat.show(id), "Toggle project tasks", U.ToggleProjectGroup{id}),
    context_control("project/more/" ++ Nat.show(id), "More", U.ObjectActions{U.ProjectSubject{id}})}

def project_entries(entries: +List<Finite.Entry(D.Project)>, +tasks: +List<D.Task>, +route: U.Route, +selected: Maybe<&2, Nat>, +navigation: E.NavigationState) -> +List<ViewTypes.ProjectEntry>:
  match entries:
    case Nil{}: Nil{}
    case Con{(id, project), rest}: project_entry(id, project, tasks, route, selected, navigation) <> project_entries(rest, tasks, route, selected, navigation)

def navigation(+expanded: Bool, +route: U.Route, +world: M.World(), +session: E.Session) -> ViewTypes.Navigation:
  +nav = E.navigation(session)
  ViewTypes.Navigation{expanded, control("new-task", "新任务", U.BeginTask{None{}}),
    [control("board", "任务看板", U.Navigate{U.TaskBoard{}}), control("projects", "项目", U.Navigate{U.ProjectCollection{}}), control("agents", "智能体", U.Navigate{U.AgentCollection{}})],
    project_entries(Projects.entries(Projects.registry(F.State(), world)), Commands.entries(world), route, active_project(route, session, world), nav), task_entries(project_tasks(Commands.entries(world), None{}), route),
    ViewTypes.ControlDeclaration{"navigation/toggle", "Toggle sidebar", ViewTypes.Secondary{}, U.SetNavigation{Bool.not(expanded)}, ViewTypes.Available{}}}

def task_details(+task: D.Task) -> ViewTypes.TaskDetails:
  D.Task{id, lineage, D.Contract{+model, tools, max_fork, max_descendants, plugins, +context}, status, history, queued, phase, operations, notified} = task
  ViewTypes.TaskDetails{Context.effective(task), model, tools, lineage, queued, status, phase}

def lifecycle(+id: Nat, +value: D.Control, +label: String, world: M.World()) -> ViewTypes.ControlDeclaration:
  native("task/" ++ Nat.show(id) ++ "/" ++ label, label, ViewTypes.Secondary{}, U.ControlTask{id, value}, world)

def task_actions(+id: Nat, +world: M.World()) -> ViewTypes.TaskActions:
  ViewTypes.TaskActions{control("details/" ++ Nat.show(id), "Task details", U.TogglePanel{U.TaskDetails{id}, "details/" ++ Nat.show(id)}),
    [lifecycle(id, D.Interrupt{}, "Interrupt", world), lifecycle(id, D.Freeze{}, "Freeze", world), lifecycle(id, D.Unfreeze{}, "Resume", world),
    lifecycle(id, D.Stop{}, "Stop", world), lifecycle(id, D.Archive{}, "Archive", world),
    control("fork/" ++ Nat.show(id), "Fork", U.ForkTask{id}), control("compact/" ++ Nat.show(id), "Compact", U.CompactTask{id})]}

def task_scene(+task: D.Task, +session: E.Session, +world: M.World()) -> ViewTypes.TaskScene:
  readers = E.readers(session)
  previews = E.previews(session)
  +id = D.task_id(task)
  ViewTypes.TaskScene{id, Conversation.title(task), task_status(task), Context.effective(task), ConversationWorld.timeline(E.reader(readers, id), task, world), Live.for_task(Live.retained(previews, world), id),
    composer(U.MessageEditor{id}, session, world), task_details(task), task_actions(id, world)}

def optional_task(found: Maybe<&2, D.Task>, session: E.Session, world: M.World()) -> Maybe<&2, ViewTypes.TaskScene>:
  match found:
    case None{}: None{}
    case Some{task}: Some{task_scene(task, session, world)}

def task_page(found: Maybe<&2, D.Task>, session: E.Session, world: M.World()) -> ViewTypes.Page:
  match found:
    case None{}: ViewTypes.MissingObject{"This task no longer exists"}
    case Some{task}: ViewTypes.TaskPage{task_scene(task, session, world)}

def project_scene(+id: Nat, project: D.Project, route: U.Route, +world: M.World()) -> ViewTypes.ProjectScene:
  D.Project{name, workspace, guidance} = project
  ViewTypes.ProjectScene{id, name, workspace, guidance, task_entries(project_tasks(Commands.entries(world), Some{id}), route),
    [control("project/new-task/" ++ Nat.show(id), "New task", U.BeginTask{Some{id}}), control("project/edit/" ++ Nat.show(id), "Edit project", U.EditProject{Some{id}}),
      native("project/delete/" ++ Nat.show(id), "Delete project", ViewTypes.Destructive{}, U.DeleteProject{id}, world)]}

def project_page(found: Maybe<&2, D.Project>, id: Nat, route: U.Route, world: M.World()) -> ViewTypes.Page:
  match found:
    case None{}: ViewTypes.MissingObject{"This project no longer exists"}
    case Some{project}: ViewTypes.ProjectPage{project_scene(id, project, route, world)}

def project_scenes(entries: +List<Finite.Entry(D.Project)>, +route: U.Route, +world: M.World()) -> +List<ViewTypes.ProjectScene>:
  match entries:
    case Nil{}: Nil{}
    case Con{(id, project), rest}: project_scene(id, project, route, world) <> project_scenes(rest, route, world)

def linked_entry(found: Maybe<&2, D.Task>, route: U.Route) -> Maybe<&2, ViewTypes.TaskEntry>:
  match found:
    case None{}: None{}
    case Some{task}: Some{task_entry(task, route)}

def linked_task(task: Maybe<&2, Nat>, route: U.Route, world: M.World()) -> Maybe<&2, ViewTypes.TaskEntry>:
  match task:
    case None{}: None{}
    case Some{id}: linked_entry(Tasks.find(Commands.entries(world), id), route)

def board_control(identity: String, label: String, +command: B.Command, world: M.World()) -> ViewTypes.ControlDeclaration:
  native(identity, label, ViewTypes.Secondary{}, U.BoardCommand{command}, world)

def move_destinations(stages: +List<B.Stage>, +id: Nat, +revision: Nat, +now: U32, +world: M.World()) -> +List<ViewTypes.MoveDestination>:
  match stages:
    case Nil{}: Nil{}
    case Con{+stage, rest}: ViewTypes.MoveDestination{stage, None{}, "Move to end of " ++ B.stage_label(stage), operation_availability(Commands.resolve(M.FeatureCommand{F.BoardCommand{B.MoveCard{id, revision, stage, None{}, now}}}, world))} <>
      move_destinations(rest, id, revision, now, world)

def link_candidates(tasks: +List<D.Task>, +id: Nat, +revision: Nat, +now: U32, +world: M.World()) -> +List<ViewTypes.ControlDeclaration>:
  match tasks:
    case Nil{}: Nil{}
    case Con{+task, rest}: board_control("card/link/" ++ Nat.show(id) ++ "/" ++ Nat.show(D.task_id(task)), Conversation.title(task),
      B.Link{id, revision, D.task_id(task), now}, world) <> link_candidates(rest, id, revision, now, world)

def before_destination(eligible: Bool, +target: Nat, +value: B.Card, id: Nat, revision: Nat, now: U32, world: M.World()) -> +List<ViewTypes.MoveDestination>:
  match eligible:
    case False{}: Nil{}
    case True{}:
      [ViewTypes.MoveDestination{B.card_stage(B.draft(value)), Some{target}, "Move before " ++ B.title(B.draft(value)),
        operation_availability(Commands.resolve(M.FeatureCommand{F.BoardCommand{B.MoveCard{id, revision, B.card_stage(B.draft(value)), Some{target}, now}}}, world))}]

def before_destinations(cards: +List<Finite.Entry(B.Card)>, +id: Nat, +revision: Nat, +now: U32, +world: M.World()) -> +List<ViewTypes.MoveDestination>:
  match cards:
    case Nil{}: Nil{}
    case Con{(+target, +value), rest}:
      List.append(&2, ViewTypes.MoveDestination, before_destination(Bool.not(B.archived(value)) && Bool.not(Nat.is_eq(target, id)), target, value, id, revision, now, world), before_destinations(rest, id, revision, now, world))

def card_scene(+id: Nat, +card: B.Card, route: U.Route, +now: U32, +world: M.World()) -> ViewTypes.CardScene:
  +revision = B.revision(card)
  task = B.task(card)
  archived = B.archived(card)
  pinned = B.pinned(card)
  ViewTypes.CardScene{id, card, control("card/" ++ Nat.show(id), "打开 " ++ B.title(B.draft(card)), U.OpenPanel{U.CardDetails{id}, "card/" ++ Nat.show(id)}),
    [board_control("card/run/" ++ Nat.show(id), "Run", B.Run{id, revision, now}, world),
      board_control("card/archive/" ++ Nat.show(id), "Archive or restore", B.Archive{id, revision, Bool.not(archived), now}, world),
      board_control("card/pin/" ++ Nat.show(id), "Pin or unpin", B.Pin{id, revision, Bool.not(pinned), now}, world),
      board_control("card/delete/" ++ Nat.show(id), "Delete", B.Delete{id, revision}, world),
      board_control("card/regenerate/" ++ Nat.show(id), "Regenerate title", B.Regenerate{id, revision, B.draft_profile(Board.registry(world)), now}, world)], linked_task(task, route, world),
    List.append(&2, ViewTypes.MoveDestination, move_destinations(B.stages(), id, revision, now, world), before_destinations(B.cards(Board.registry(world)), id, revision, now, world)), link_candidates(Commands.entries(world), id, revision, now, world)}

def archived_card(entry: Finite.Entry(B.Card)) -> Bool:
  (id, card) = entry
  B.archived(card)

def card_scenes(cards: +List<Finite.Entry(B.Card)>, +route: U.Route, +now: U32, +world: M.World()) -> +List<ViewTypes.CardScene>:
  match cards:
    case Nil{}: Nil{}
    case Con{(id, card), rest}: card_scene(id, card, route, now, world) <> card_scenes(rest, route, now, world)

def columns(stages: +List<B.Stage>, +cards: +List<Finite.Entry(B.Card)>, +route: U.Route, +now: U32, +world: M.World()) -> +List<ViewTypes.BoardColumn>:
  match stages:
    case Nil{}: Nil{}
    case Con{+stage, rest}: ViewTypes.BoardColumn{stage, card_scenes(Filter.column(cards, B.stage_name(stage)), route, now, world),
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

def card_face(+id: Nat, +card: B.Card, +now: U32, +world: M.World()) -> ViewTypes.CardFace:
  +draft = B.draft(card)
  ViewTypes.CardFace{id, B.title(draft), B.description(draft), B.card_priority(draft), B.pinned(card),
    Board.activity_label(Board.activity(card, world)), face_project(B.project(draft), world), B.labels(draft),
    face_owner(B.card_owner(draft), world), elapsed_label(Filter.elapsed(now, B.updated(card)))}

def archived_cards(board: B.State, route: U.Route, now: U32, world: M.World()) -> +List<ViewTypes.CardScene>:
  cards = B.cards(board)
  card_scenes(List.filter(~Finite.Entry(B.Card), archived_card, cards), route, now, world)

def board_page(+board: B.State, +filter: B.Filter, +route: U.Route, +now: U32, +world: M.World()) -> ViewTypes.Page:
  ViewTypes.BoardPage{filter, columns(B.stages(), Filter.filtered(Board.display_cards(board), filter, now, world), route, now, world),
    ViewTypes.ControlDeclaration{"card/new", "新建任务", ViewTypes.Primary{}, U.Activate{U.NewCard{B.Todo{}}}, ViewTypes.Available{}},
    Filter.working(B.cards(Board.registry(world)), world),
    control("board/settings", "看板设置", U.OpenPanel{U.BoardSettings{}, "board/settings"}),
    control("board/filters", "筛选任务", U.OpenPanel{U.BoardFilters{}, "board/filters"}),
    control("board/archive", "归档任务 " ++ Nat.show(List.length(&2, ViewTypes.CardScene, archived_cards(board, route, now, world))), U.OpenPanel{U.ArchivedCards{}, "board/archive"})}

def agent_scene(+id: Nat, +agent: B.AgentProfile, world: M.World()) -> ViewTypes.AgentScene:
  revision = B.agent_revision(agent)
  ViewTypes.AgentScene{id, agent, control("agent/edit/" ++ Nat.show(id), "Edit agent", U.EditAgent{Some{id}}), board_control("agent/delete/" ++ Nat.show(id), "Delete agent", B.DeleteAgent{id, revision}, world)}

def agent_scenes(agents: +List<Finite.Entry(B.AgentProfile)>, +world: M.World()) -> +List<ViewTypes.AgentScene>:
  match agents:
    case Nil{}: Nil{}
    case Con{(id, agent), rest}: agent_scene(id, agent, world) <> agent_scenes(rest, world)

def page(+route: U.Route, +session: E.Session, +world: M.World()) -> ViewTypes.Page:
  match route:
    case U.Start{}: ViewTypes.StartPage{composer(U.NewTaskEditor{}, session, world)}
    case U.Conversation{id}: task_page(Tasks.find(Commands.entries(world), id), session, world)
    case U.ProjectHome{+id}: project_page(Projects.find(Projects.registry(F.State(), world), id), id, route, world)
    case U.ProjectCollection{}: ViewTypes.ProjectsPage{project_scenes(Projects.entries(Projects.registry(F.State(), world)), route, world), control("project/new", "New project", U.EditProject{None{}})}
    case U.TaskBoard{}:
      filter = E.filter(session)
      now = E.now(session)
      board_page(Board.registry(world), filter, route, now, world)
    case U.AgentCollection{}: ViewTypes.AgentsPage{agent_scenes(agents(Board.registry(world)), world), control("agent/new", "New agent", U.EditAgent{None{}})}

def task_menu(actions: ViewTypes.TaskActions) -> +List<ViewTypes.ControlDeclaration>:
  ViewTypes.TaskActions{details, overflow} = actions
  overflow

def card_moves(values: +List<ViewTypes.MoveDestination>, +id: Nat, +revision: Nat, +now: U32, +world: M.World()) -> +List<ViewTypes.ControlDeclaration>:
  match values:
    case Nil{}: Nil{}
    case Con{ViewTypes.MoveDestination{+stage, +before, label, availability}, rest}:
      board_control("card/move/" ++ B.stage_name(stage) ++ "/" ++ U.optional_key(before), label, B.MoveCard{id, revision, stage, before, now}, world) <> card_moves(rest, id, revision, now, world)

def card_menu_items(card: ViewTypes.CardScene, now: U32, world: M.World()) -> +List<ViewTypes.ControlDeclaration>:
  ViewTypes.CardScene{id, value, open, actions, linked, destinations, candidates} = card
  List.append(&2, ViewTypes.ControlDeclaration, actions, List.append(&2, ViewTypes.ControlDeclaration, card_moves(destinations, id, B.revision(value), now, world), candidates))

def card_menu(found: Maybe<&2, B.Card>, id: Nat, +now: U32, +world: M.World()) -> +List<ViewTypes.ControlDeclaration>:
  match found:
    case None{}: Nil{}
    case Some{card}: card_menu_items(card_scene(id, card, U.TaskBoard{}, now, world), now, world)

def agent_menu_items(agent: ViewTypes.AgentScene) -> +List<ViewTypes.ControlDeclaration>:
  ViewTypes.AgentScene{id, value, edit, remove} = agent
  [edit, remove]

def agent_menu(found: Maybe<&2, B.AgentProfile>, id: Nat, world: M.World()) -> +List<ViewTypes.ControlDeclaration>:
  match found:
    case None{}: Nil{}
    case Some{agent}: agent_menu_items(agent_scene(id, agent, world))

def board_cards(board: B.State) -> +List<Finite.Entry(B.Card)>:
  cards = B.cards(board)
  cards

def subject_controls(subject: U.Subject, now: U32, +world: M.World()) -> +List<ViewTypes.ControlDeclaration>:
  match subject:
    case U.TaskSubject{+id}: task_menu(task_actions(id, world))
    case U.ProjectSubject{+id}: [control("project/details/" ++ Nat.show(id), "Project details", U.Navigate{U.ProjectHome{id}}), control("project/edit/" ++ Nat.show(id), "Edit project", U.EditProject{Some{id}}),
      native("project/delete/" ++ Nat.show(id), "Delete project", ViewTypes.Destructive{}, U.DeleteProject{id}, world)]
    case U.CardSubject{+id}: card_menu(Finite.find(~B.Card, board_cards(Board.registry(world)), id), id, now, world)
    case U.AgentSubject{+id}: agent_menu(Finite.find(~B.AgentProfile, agents(Board.registry(world)), id), id, world)

def subject_actions(subject: U.Subject, session: E.Session, world: M.World()) -> +List<ViewTypes.ControlDeclaration>:
  now = E.now(session)
  subject_controls(subject, now, world)

def board_settings(+board: B.State, +world: M.World()) -> ViewTypes.LayerContent:
  +automatic = B.automatic(board)
  +draft_profile = B.draft_profile(board)
  ViewTypes.BoardSettings{automatic, draft_profile, Board.profiles(world),
    board_control("board/automatic", "自动排期", B.Settings{Bool.not(automatic), draft_profile}, world)}

def found_card_details(found: Maybe<&2, B.Card>, id: Nat, route: U.Route, now: U32, world: M.World()) -> Maybe<&2, ViewTypes.CardScene>:
  match found:
    case None{}: None{}
    case Some{card}: Some{card_scene(id, card, route, now, world)}

def layer_content(panel: U.Panel, +session: E.Session, +world: M.World()) -> ViewTypes.LayerContent:
  match panel:
    case U.ProjectPicker{}:
      +route = E.route(session)
      +drafts = E.drafts(session)
      +readers = E.readers(session)
      +layers = E.layers(session)
      +attention = E.attention(session)
      +navigation = E.navigation(session)
      +filter = E.filter(session)
      +now = E.now(session)
      +next = E.next_ticket(session)
      +pending = E.pending(session)
      +previews = E.previews(session)
      code = E.code_blocks(session)
      +next_layer = E.next_layer(session)
      ViewTypes.ProjectSelection{"", draft_project(E.find_draft(drafts, U.NewTaskEditor{}), world), project_choices(Projects.entries(Projects.registry(F.State(), world)))}
    case U.ObjectActions{subject}: ViewTypes.ObjectActions{subject_actions(subject, session, world)}
    case U.ArchivedCards{}:
      +route = E.route(session)
      +drafts = E.drafts(session)
      +readers = E.readers(session)
      +layers = E.layers(session)
      +navigation = E.navigation(session)
      +filter = E.filter(session)
      +now = E.now(session)
      +next = E.next_ticket(session)
      +pending = E.pending(session)
      +previews = E.previews(session)
      code_blocks = E.code_blocks(session)
      +next_layer = E.next_layer(session)
      ViewTypes.ArchivedCards{archived_cards(Board.registry(world), route, now, world)}
    case U.CardDetails{+card}:
      +route = E.route(session)
      +drafts = E.drafts(session)
      +readers = E.readers(session)
      +layers = E.layers(session)
      +attention = E.attention(session)
      +navigation = E.navigation(session)
      +filter = E.filter(session)
      +now = E.now(session)
      +next = E.next_ticket(session)
      +pending = E.pending(session)
      +previews = E.previews(session)
      code = E.code_blocks(session)
      +next_layer = E.next_layer(session)
      ViewTypes.CardDetails{found_card_details(B.find(Board.registry(world), card), card, route, now, world)}
    case U.BoardSettings{}: board_settings(Board.registry(world), world)
    case U.BoardFilters{}:
      +route = E.route(session)
      +drafts = E.drafts(session)
      +readers = E.readers(session)
      +layers = E.layers(session)
      +attention = E.attention(session)
      +navigation = E.navigation(session)
      +filter = E.filter(session)
      +now = E.now(session)
      +next = E.next_ticket(session)
      +pending = E.pending(session)
      +previews = E.previews(session)
      code_blocks = E.code_blocks(session)
      +next_layer = E.next_layer(session)
      ViewTypes.BoardFilters{filter}
    case U.EditObject{id}: ViewTypes.ObjectEditor{editor(id, session, world)}
    case U.TaskDetails{task}: ViewTypes.ExecutionDetails{optional_task(Tasks.find(Commands.entries(world), task), session, world)}
    case U.WorkspaceConfiguration{+id}: ViewTypes.WorkspaceSettings{id, selected_fields(editor(id, session, world), ViewTypes.ExecutionFields{})}
    case U.PermissionsConfiguration{+id}: ViewTypes.PermissionSettings{id, selected_fields(editor(id, session, world), ViewTypes.ExecutionFields{})}
    case U.TaskContext{task}: ViewTypes.CommittedContext{committed_context(Tasks.find(Commands.entries(world), task))}
    case U.ModelPicker{+id}: ViewTypes.ModelSelection{id, "", selected_fields(editor(id, session, world), ViewTypes.ModelFields{})}
    case U.DeliveryPicker{+task}: ViewTypes.DeliverySelection{U.MessageEditor{task}, selected_fields(editor(U.MessageEditor{task}, session, world), ViewTypes.DeliveryFields{})}
    case U.Confirm{command, title, destination}: ViewTypes.Confirmation{title,
      ViewTypes.ControlDeclaration{"confirm", "Confirm", ViewTypes.Destructive{}, U.Activate{U.ConfirmAction{}}, operation_availability(Commands.resolve(command, world))}, control("confirm/cancel", "Cancel", U.ClosePanel{})}

def details_kind(beside: Bool) -> ViewTypes.LayerKind:
  match beside:
    case True{}: ViewTypes.TrailingDetails{}
    case False{}: ViewTypes.ModalDialog{}

def layer_kind(panel: U.Panel, beside: Bool) -> ViewTypes.LayerKind:
  match panel:
    case U.ObjectActions{subject}: ViewTypes.AnchoredMenu{}
    case U.ModelPicker{editor}: ViewTypes.AnchoredMenu{}
    case U.DeliveryPicker{task}: ViewTypes.AnchoredMenu{}
    case U.WorkspaceConfiguration{editor}: ViewTypes.AnchoredMenu{}
    case U.PermissionsConfiguration{editor}: ViewTypes.AnchoredMenu{}
    case U.TaskDetails{task}: details_kind(beside)
    case _: ViewTypes.ModalDialog{}

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

def search_fields(fields: +List<ViewTypes.InputGroup>, +query: String) -> +List<ViewTypes.InputGroup>:
  match fields:
    case Nil{}: Nil{}
    case Con{ViewTypes.ModelInput{profile, reasoning, choices}, rest}: ViewTypes.ModelInput{profile, reasoning, matching_profiles(choices, query)} <> search_fields(rest, query)
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

def project_matches(project: ViewTypes.ProjectChoice, query: String) -> Bool:
  ViewTypes.ProjectChoice{id, name, D.Workspace{roots, primary}} = project
  String.contains(String.to_lower(name ++ " " ++ project_search_paths(roots) ++ " " ++ project_primary_text(primary)), String.to_lower(String.trim(query)))

def keep_project_choice(matches: Bool, project: ViewTypes.ProjectChoice, rest: +List<ViewTypes.ProjectChoice>) -> +List<ViewTypes.ProjectChoice>:
  match matches:
    case True{}: project <> rest
    case False{}: rest

def matching_projects(projects: +List<ViewTypes.ProjectChoice>, +query: String) -> +List<ViewTypes.ProjectChoice>:
  match projects:
    case Nil{}: Nil{}
    case Con{+project, rest}: keep_project_choice(project_matches(project, query), project, matching_projects(rest, query))

def search_content(content: ViewTypes.LayerContent, +query: String) -> ViewTypes.LayerContent:
  match content:
    case ViewTypes.ProjectSelection{old, selected, projects}: ViewTypes.ProjectSelection{query, selected, matching_projects(projects, query)}
    case ViewTypes.ModelSelection{editor, old, fields}: ViewTypes.ModelSelection{editor, query, search_fields(fields, query)}
    case other: other

def layer_dismissal(panel: U.Panel, trigger: String) -> ViewTypes.Dismissal:
  match panel:
    case U.TaskDetails{task}: ViewTypes.ByTrigger{U.TogglePanel{U.TaskDetails{task}, trigger}}
    case _: ViewTypes.OutsideOrEscape{U.ClosePanel{}}

def layers(entries: +List<E.Layer>, +session: E.Session, +world: M.World(), +beside: Bool) -> +List<ViewTypes.Layer>:
  match entries:
    case Nil{}: Nil{}
    case Con{E.Layer{+panel, +trigger, initial, +query, layer_occurrence}, rest}:
      ViewTypes.Layer{layer_kind(panel, beside), search_content(layer_content(panel, session, world), query), initial, trigger, layer_dismissal(panel, trigger)} <> layers(rest, session, world, beside)

def navigation_visible(intent: E.NavigationIntent, beside: Bool) -> Bool:
  match intent:
    case E.AutomaticNavigation{}: beside
    case E.OpenNavigation{}: True{}
    case E.ClosedNavigation{}: False{}

def navigation_placement(beside: Bool, expanded: Bool) -> ViewTypes.NavigationPlacement:
  match beside expanded:
    case True{} True{}: ViewTypes.LeadingNavigation{}
    case False{} True{}: ViewTypes.ModalNavigation{}
    case _ False{}: ViewTypes.CollapsedNavigation{}

def has_composer(composer: Maybe<&2, ViewTypes.ComposerScene>) -> Bool:
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

def page_composition(page: ViewTypes.Page) -> Composition.Page:
  match page:
    case ViewTypes.StartPage{composer}: Composition.Creation{has_composer(composer)}
    case ViewTypes.TaskPage{task}:
      ViewTypes.TaskScene{task_id, title, status, context, timeline, previews, composer, details, actions} = task
      ConversationWorld.Timeline{id, generation, groups, operations, decisions, reading, return_to_latest} = timeline
      Composition.Conversation{has_composer(composer), has_decisions(decisions), has_return_latest(return_to_latest)}
    case ViewTypes.ProjectPage{project}: Composition.ProjectOverview{}
    case ViewTypes.ProjectsPage{projects, create}: Composition.ProjectCollection{}
    case ViewTypes.BoardPage{filter, columns, create, working, settings, filters, archive}: Composition.TaskBoard{}
    case ViewTypes.AgentsPage{agents, create}: Composition.AgentCollection{}
    case ViewTypes.MissingObject{message}: Composition.Unavailable{}

def arrangement(beside: Bool, expanded: Bool) -> ViewTypes.Arrangement:
  ViewTypes.Arrangement{navigation_placement(beside, expanded)}

def scene_page(scene: ViewTypes.Scene) -> Composition.Page:
  ViewTypes.Scene{navigation, +main, layers, arrangement, attention} = scene
  page_composition(main)

def finish_scene(navigation: ViewTypes.Navigation, +main: ViewTypes.Page, +layers: +List<ViewTypes.Layer>, beside: Bool, expanded: Bool, attention: String) -> ViewTypes.Scene:
  ViewTypes.Scene{navigation, main, layers, arrangement(beside, expanded), attention}

def observe_session(capacity: ViewTypes.Capacity, +program: M.World(), +session: E.Session) -> ViewTypes.Scene:
  ViewTypes.Capacity{+navigation_beside, details_beside} = capacity
  +route = E.route(session)
  open_layers = E.layers(session)
  focus = E.attention(session)
  +expanded = E.navigation(session)
  +visible = navigation_visible(E.navigation_visibility(expanded), navigation_beside)
  +main = page(route, session, program)
  finish_scene(navigation(visible, route, program, session), main, layers(open_layers, session, program, details_beside), navigation_beside, visible, focus)

def observe(capacity: ViewTypes.Capacity, +application: E.Application) -> ViewTypes.Scene:
  +program = E.program(application)
  +session = E.session(application)
  observe_session(capacity, program, session)
