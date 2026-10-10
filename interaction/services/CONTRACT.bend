import Base
import ../../harness/DOMAIN.bend as D
import ./CONTEXT.bend as Context
import ../presentation/PROGRAM.bend as InterfaceView
import ../presentation/VIEW.bend as View
import ../IDENTITY.bend as Identity
import ../../harness/MODEL.bend as M
import ../../harness/reasoning/MODEL.bend as Reasoning
import ../../harness/COMMANDS.bend as Commands
import ../../harness/workspace/PROJECTS.bend as Projects
import ../../harness/features/MODEL.bend as F
import ../../harness/tasks/PROGRAM.bend as Tasks
import ../INPUT.bend as U
import ../session/MODEL.bend as E
import ../presentation/MODEL.bend as V
import ../STATE.bend as Core
import ./MODEL.bend as Services
import ../submission/FIELDS.bend as Forms
import ../presentation/SURFACE.bend as SurfaceTypes
import ../TYPES.bend as InteractionTypes

type PermissionsRequirements is Type:
  PermissionsRequirements{
    unrestricted_filesystem: @mode:D.SandboxMode -> {Context.filesystem_summary(D.Unrestricted{}, mode) == "Full access" : String},
    unrestricted_network: @network:Bool -> {Context.network_summary(D.Unrestricted{}, network) == "Available" : String},
    sandboxed_filesystem: @mode:D.SandboxMode -> {Context.filesystem_summary(D.Sandboxed{}, mode) == D.sandbox_mode_name(mode) : String},
    sandboxed_network: @network:Bool -> {Context.network_summary(D.Sandboxed{}, network) == View.execution_network_summary(network) : String},
    committed_permissions: @task:Nat -> @workspace:D.Workspace -> @mode:D.SandboxMode -> @network:Bool -> @approval:D.ApprovalPolicy -> @project:Maybe<&2, Nat> -> @guidance:D.ProjectContext -> @access:D.ExecutionAccess -> @profiles:+List<D.Profile> ->
      {View.observation_permissions(Context.CommittedExecution{Context.EffectiveContext{task, D.TaskContext{workspace, D.Sandbox{mode, network}, approval, project}, guidance, access}}, profiles) == Context.filesystem_summary(access, mode) ++ "; " ++ Context.network_summary(access, network) ++ "; " ++ View.policy_approval_summary(approval) : String},
    committed_facts: @task:Nat -> @workspace:D.Workspace -> @mode:D.SandboxMode -> @network:Bool -> @approval:D.ApprovalPolicy -> @project:Maybe<&2, Nat> -> @guidance:D.ProjectContext -> @access:D.ExecutionAccess -> @profiles:+List<D.Profile> ->
      {InterfaceView.observation_facts(Context.CommittedExecution{Context.EffectiveContext{task, D.TaskContext{workspace, D.Sandbox{mode, network}, approval, project}, guidance, access}}, profiles) == Context.filesystem_summary(access, mode) ++ "; " ++ Context.network_summary(access, network) ++ "; " ++ View.policy_approval_summary(approval) : String},
    configured_permissions: @origin:Context.Origin -> @project:Maybe<&2, Nat> -> @workspace:Context.WorkspaceValue -> @sandbox:Context.SandboxValue -> @approval:Context.ApprovalValue -> @guidance:Context.GuidancePreview -> @profiles:+List<D.Profile> ->
      {View.observation_permissions(Context.DraftExecution{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}}, profiles) == "Configured: " ++ View.execution_permissions_summary(Context.unwrap_sandbox(sandbox), View.value_approval_summary(approval, profiles)) : String},
    configured_facts: @origin:Context.Origin -> @project:Maybe<&2, Nat> -> @workspace:Context.WorkspaceValue -> @sandbox:Context.SandboxValue -> @approval:Context.ApprovalValue -> @guidance:Context.GuidancePreview -> @profiles:+List<D.Profile> ->
      {InterfaceView.observation_facts(Context.DraftExecution{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}}, profiles) == "Configured: " ++ InterfaceView.sandbox_facts(Context.unwrap_sandbox(sandbox)) ++ "; " ++ View.value_approval_summary(approval, profiles) : String}}

law permissions_evidence:
  PermissionsRequirements

def composer_context(value: Maybe<&2, V.ComposerScene>) -> Maybe<&2, Context.Observation>:
  match value:
    case None{}: None{}
    case Some{V.ComposerScene{identity, revision, message, footer, context, submit, feedback, pending}}: context

def node_context(value: SurfaceTypes.Node) -> Maybe<&2, Context.Observation>:
  match value:
    case SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ContextSummary{context}, children}: Some{context}
    case _: None{}

type DirectoryFact is Data:
  DirectoryFact{label: String, path: String, primary: Bool}

def directory_fact(value: SurfaceTypes.Node) -> Maybe<&2, DirectoryFact>:
  match value:
    case SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.DirectoryRow{path, primary}, children}: Some{DirectoryFact{label, path, primary}}
    case _: None{}

def choice_input(value: SurfaceTypes.Node) -> Maybe<&2, InteractionTypes.Input>:
  match value:
    case SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.Choice{kind, icon, selected, description, input, availability}, children}: Some{input}
    case _: None{}

def choice_selection(value: SurfaceTypes.Node) -> Maybe<&2, Bool>:
  match value:
    case SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.Choice{kind, icon, selected, description, input, availability}, children}: Some{selected}
    case _: None{}

def tree_focusable(nodes: +List<SurfaceTypes.Node>) -> Bool:
  match nodes:
    case Nil{}: False{}
    case Con{SurfaceTypes.Node{key, semantic, label, role, meaning, children}, rest}:
      InterfaceView.focusable(meaning) || tree_focusable(children) || tree_focusable(rest)

def first_context(nodes: +List<SurfaceTypes.Node>) -> Maybe<&2, Context.Observation>:
  match nodes:
    case Nil{}: None{}
    case Con{node, rest}: node_context(node)

def workspace_menu_source_law(-editor: U.Editor, -config: Context.Configuration,
  -origin: Context.Origin, -project: Maybe<&2, Nat>, -workspace: Context.WorkspaceValue,
  -sandbox: Context.SandboxValue, -approval: Context.ApprovalValue,
  -guidance: Context.GuidancePreview, -controls: V.WorkspaceControls,
  -projects: +List<V.ProjectChoice>, -reviewers: +List<D.Profile>, -parent: Identity.Key,
  -state: InteractionTypes.State) -> Type:
  {first_context(InterfaceView.workspace_menu_group(editor, V.ExecutionInput{config, Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}, controls, projects, reviewers}, parent, state)) ==
    Some{Context.DraftExecution{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}}} : Maybe<&2, Context.Observation>}

def permissions_menu_source_law(-editor: U.Editor, -config: Context.Configuration,
  -origin: Context.Origin, -project: Maybe<&2, Nat>, -workspace: Context.WorkspaceValue,
  -sandbox: Context.SandboxValue, -approval: Context.ApprovalValue,
  -guidance: Context.GuidancePreview, -controls: V.WorkspaceControls,
  -projects: +List<V.ProjectChoice>, -reviewers: +List<D.Profile>, -parent: Identity.Key,
  -state: InteractionTypes.State) -> Type:
  {first_context(InterfaceView.permission_menu_group(editor, V.ExecutionInput{config, Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}, controls, projects, reviewers}, parent, state)) ==
    Some{Context.DraftExecution{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}}} : Maybe<&2, Context.Observation>}

def effective_task(value: Context.EffectiveContext) -> Nat:
  Context.EffectiveContext{task, context, guidance, access} = value
  task

type ChoiceCaption is Data:
  ChoiceCaption{label: String, description: String}

def choice_caption(value: SurfaceTypes.Node) -> Maybe<&2, ChoiceCaption>:
  match value:
    case SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.Choice{kind, icon, selected, description, input, availability}, children}: Some{ChoiceCaption{label, description}}
    case _: None{}

def network_pair(value: SurfaceTypes.Node) -> Sigma<&2, &2, Maybe<&2, Bool>, (_ => Maybe<&2, Bool>)>:
  match value:
    case SurfaceTypes.Node{key, semantic, label, role, meaning, Con{disabled, Con{enabled, Nil{}}}}: (choice_selection(disabled), choice_selection(enabled))
    case _: (None{}, None{})

type ContextRequirements is Type:
  ContextRequirements{
    committed_project_node_world: @+project:Maybe<&2, Nat> -> @+world:M.World() -> @session:E.Session -> @services:Services.State -> @parent: Identity.Key ->
      {InterfaceView.node_label(InterfaceView.committed_project_node(project, parent, Core.from_application(E.from_program(world, session), services))) == InterfaceView.committed_project_text(project, world) : String},
    committed_source_label: @task:Nat -> @context:D.TaskContext -> @guidance:D.ProjectContext -> @access:D.ExecutionAccess -> @world:M.World() ->
      {View.execution_source_summary(Context.CommittedExecution{Context.EffectiveContext{task, context, guidance, access}}, world) == "Task settings" : String},
    committed_project_name: @id:Nat -> @+name:String -> @workspace:D.Workspace -> @guidance:D.ProjectContext ->
      {InterfaceView.committed_project_name(Some{D.Project{name, workspace, guidance}}, id) == name : String},
    committed_project_missing: @+id:Nat -> {InterfaceView.committed_project_name(None{}, id) == "Project unavailable (ID " ++ Nat.show(id) ++ ")" : String},
    committed_project_lookup: @+id:Nat -> @+world:M.World() ->
      {InterfaceView.committed_project_text(Some{id}, world) == InterfaceView.committed_project_name(Projects.find(Projects.registry(F.State(), world), id), id) : String},
    projectless_context: @world:M.World() -> {InterfaceView.committed_project_text(None{}, world) == "Projectless task" : String},
    primary_directory_no_duplicate: @primary:Maybe<&2, String> -> @parent: Identity.Key ->
      {InterfaceView.committed_working_directory_extra(True{}, primary, parent) == Nil{} : +List<SurfaceTypes.Node>},
    absent_primary_directory_fact: @+parent: Identity.Key ->
      {InterfaceView.committed_working_directory_extra(False{}, None{}, parent) == [SurfaceTypes.Node{Identity.Part{parent, "working-directory"}, "context/working-directory", "No working directory", SurfaceTypes.Content{}, SurfaceTypes.ReadOnly{"No working directory"}, Nil{}}] : +List<SurfaceTypes.Node>},
    network_group_selection: @mode:D.SandboxMode -> @+network:Bool -> @editor:U.Editor -> @parent: Identity.Key -> @state:InteractionTypes.State ->
      {network_pair(InterfaceView.network_choices(D.Sandbox{mode, network}, editor, parent, state)) == (Some{Bool.not(network)}, Some{network}) : Sigma<&2, &2, Maybe<&2, Bool>, (_ => Maybe<&2, Bool>)>},
    filesystem_write_caption: @current:D.SandboxMode -> @network:Bool -> @editor:U.Editor -> @parent: Identity.Key -> @state:InteractionTypes.State -> {choice_caption(InterfaceView.sandbox_choice(D.WorkspaceWrite{}, current, network, editor, parent, state)) == Some{ChoiceCaption{"Workspace write", "Allow edits in the working directories."}} : Maybe<&2, ChoiceCaption>},
    filesystem_read_caption: @current:D.SandboxMode -> @network:Bool -> @editor:U.Editor -> @parent: Identity.Key -> @state:InteractionTypes.State -> {choice_caption(InterfaceView.sandbox_choice(D.ReadOnly{}, current, network, editor, parent, state)) == Some{ChoiceCaption{"Read only", "Read files without modifying them."}} : Maybe<&2, ChoiceCaption>},
    network_disabled_caption: @mode:D.SandboxMode -> @current:Bool -> @editor:U.Editor -> @parent: Identity.Key -> @state:InteractionTypes.State -> {choice_caption(InterfaceView.network_choice(mode, current, False{}, editor, parent, state)) == Some{ChoiceCaption{"Disabled", "Keep network access off."}} : Maybe<&2, ChoiceCaption>},
    network_enabled_caption: @mode:D.SandboxMode -> @current:Bool -> @editor:U.Editor -> @parent: Identity.Key -> @state:InteractionTypes.State -> {choice_caption(InterfaceView.network_choice(mode, current, True{}, editor, parent, state)) == Some{ChoiceCaption{"Enabled", "Allow network access."}} : Maybe<&2, ChoiceCaption>},
    ask_caption: @current:Context.ApprovalChoice -> @editor:U.Editor -> @parent: Identity.Key -> @state:InteractionTypes.State -> {choice_caption(InterfaceView.approval_choice_node(Context.Ask{}, current, None{}, editor, parent, state)) == Some{ChoiceCaption{"Ask", "Ask before running actions that require approval."}} : Maybe<&2, ChoiceCaption>},
    unrestricted_caption: @current:Context.ApprovalChoice -> @editor:U.Editor -> @parent: Identity.Key -> @state:InteractionTypes.State -> {choice_caption(InterfaceView.approval_choice_node(Context.Unrestricted{}, current, None{}, editor, parent, state)) == Some{ChoiceCaption{"Unrestricted", "Run actions without approval prompts."}} : Maybe<&2, ChoiceCaption>},
    automatic_caption: @+key: String -> @provider:String -> @+name:String -> @reasoning:Reasoning.Policy -> @options:Maybe<&2, D.ReasoningOptions> -> @current:Context.ApprovalChoice -> @editor:U.Editor -> @parent: Identity.Key -> @state:InteractionTypes.State -> {choice_caption(InterfaceView.approval_choice_node(Context.AutomaticReview{key}, current, Some{D.Profile{key, provider, name, reasoning, options}}, editor, parent, state)) == Some{ChoiceCaption{"Automatic review: " ++ name, "Use this model to review approval requests."}} : Maybe<&2, ChoiceCaption>},
    unavailable_profile_caption: @+key: String -> {View.automatic_review_summary(None{}, key) == "Automatic review unavailable: " ++ key: String},
    admitted_task_identity: @+task:D.Task -> {effective_task(Context.effective(task)) == D.task_id(task) : Nat},
    passive_directory: @path:String -> @primary:Bool -> @gesture:SurfaceTypes.Gesture -> {InterfaceView.bind(SurfaceTypes.DirectoryRow{path, primary}, gesture) == None{} : Maybe<&2, InteractionTypes.Input>},
    passive_summary: @value:Context.Observation -> @gesture:SurfaceTypes.Gesture -> {InterfaceView.bind(SurfaceTypes.ContextSummary{value}, gesture) == None{} : Maybe<&2, InteractionTypes.Input>},
    available_choice: @selected:Bool -> @description:String -> @+input:InteractionTypes.Input -> {InterfaceView.bind(SurfaceTypes.Choice{SurfaceTypes.SingleChoice{}, None{}, selected, description, input, V.Available{}}, SurfaceTypes.Press{}) == Some{input} : Maybe<&2, InteractionTypes.Input>},
    unavailable_choice: @selected:Bool -> @description:String -> @input:InteractionTypes.Input -> @reason:String -> {InterfaceView.bind(SurfaceTypes.Choice{SurfaceTypes.SingleChoice{}, None{}, selected, description, input, V.Unavailable{reason}}, SurfaceTypes.Press{}) == None{} : Maybe<&2, InteractionTypes.Input>},
    draft_footer: @+editor:U.Editor -> @+observation:Context.Observation -> @+profiles:+List<D.Profile> ->
      {View.draft_context_footer(editor, observation, profiles) ==
        [V.ComposerControl{V.WorkspaceSubject{}, V.ControlDeclaration{"composer/workspace/" ++ U.editor_key(editor), View.observation_workspace(observation), V.Secondary{},
          U.Activate{U.OpenPanel{U.WorkspaceConfiguration{editor}, "composer/workspace/" ++ U.editor_key(editor)}}, V.Available{}}},
         V.ComposerControl{V.PermissionsSubject{}, V.ControlDeclaration{"composer/permissions/" ++ U.editor_key(editor), View.observation_permissions(observation, profiles), V.Secondary{},
          U.Activate{U.OpenPanel{U.PermissionsConfiguration{editor}, "composer/permissions/" ++ U.editor_key(editor)}}, V.Available{}}}] : +List<V.ComposerControl>},
    committed_footer: @+task:Nat -> @+observation:Context.Observation -> @+profiles:+List<D.Profile> ->
      {View.committed_context_footer(task, Some{observation}, profiles) ==
        [V.ComposerControl{V.WorkspaceSubject{}, V.ControlDeclaration{"composer/workspace/message/" ++ Nat.show(task), View.observation_workspace(observation), V.Secondary{},
          U.Activate{U.OpenPanel{U.TaskContext{task}, "composer/workspace/message/" ++ Nat.show(task)}}, V.Available{}}},
         V.ComposerControl{V.PermissionsSubject{}, V.ControlDeclaration{"composer/permissions/message/" ++ Nat.show(task), View.observation_permissions(observation, profiles), V.Secondary{},
          U.Activate{U.OpenPanel{U.TaskContext{task}, "composer/permissions/message/" ++ Nat.show(task)}}, V.Available{}}}] : +List<V.ComposerControl>},
    workspace_menu_source: @+editor:U.Editor -> @config:Context.Configuration -> @+origin:Context.Origin -> @+project:Maybe<&2, Nat> -> @+workspace:Context.WorkspaceValue -> @+sandbox:Context.SandboxValue -> @+approval:Context.ApprovalValue -> @+guidance:Context.GuidancePreview -> @controls:V.WorkspaceControls -> @projects:+List<V.ProjectChoice> -> @reviewers:+List<D.Profile> -> @parent: Identity.Key -> @state:InteractionTypes.State ->
      workspace_menu_source_law(editor, config, origin, project, workspace, sandbox, approval, guidance, controls, projects, reviewers, parent, state),
    permissions_menu_source: @+editor:U.Editor -> @config:Context.Configuration -> @+origin:Context.Origin -> @+project:Maybe<&2, Nat> -> @+workspace:Context.WorkspaceValue -> @+sandbox:Context.SandboxValue -> @+approval:Context.ApprovalValue -> @+guidance:Context.GuidancePreview -> @controls:V.WorkspaceControls -> @projects:+List<V.ProjectChoice> -> @reviewers:+List<D.Profile> -> @parent: Identity.Key -> @state:InteractionTypes.State ->
      permissions_menu_source_law(editor, config, origin, project, workspace, sandbox, approval, guidance, controls, projects, reviewers, parent, state),
    unavailable_workspace: @+reason:String -> @config:Context.Configuration -> @controls:V.WorkspaceControls -> @projects:+List<V.ProjectChoice> -> @reviewers:+List<D.Profile> -> @editor:U.Editor -> @+parent: Identity.Key -> @state:InteractionTypes.State ->
      {InterfaceView.workspace_menu_group(editor, V.ExecutionInput{config, Context.ContextUnavailable{reason}, controls, projects, reviewers}, parent, state) == [SurfaceTypes.Node{Identity.Part{parent, "unavailable"}, "context/unavailable", reason, SurfaceTypes.Content{}, SurfaceTypes.ReadOnly{reason}, Nil{}}] : +List<SurfaceTypes.Node>},
    unavailable_permissions: @+reason:String -> @config:Context.Configuration -> @controls:V.WorkspaceControls -> @projects:+List<V.ProjectChoice> -> @reviewers:+List<D.Profile> -> @editor:U.Editor -> @+parent: Identity.Key -> @state:InteractionTypes.State ->
      {InterfaceView.permission_menu_group(editor, V.ExecutionInput{config, Context.ContextUnavailable{reason}, controls, projects, reviewers}, parent, state) == [SurfaceTypes.Node{Identity.Part{parent, "unavailable"}, "context/unavailable", reason, SurfaceTypes.Content{}, SurfaceTypes.ReadOnly{reason}, Nil{}}] : +List<SurfaceTypes.Node>},
    overridden_workspace_reset: @+workspace:D.Workspace -> @+editor:U.Editor -> {View.workspace_inheritance(Some{workspace}, editor) == Some{V.ControlDeclaration{"inherit-workspace/" ++ U.editor_key(editor), "Use inherited workspace", V.Secondary{}, U.EditDraft{editor, U.ConfigureContext{Context.UseDefaultWorkspace{}}}, V.Available{}}} : Maybe<&2, V.ControlDeclaration>},
    overridden_sandbox_reset: @origin:Context.Origin -> @workspace:Maybe<&2, D.Workspace> -> @sandbox:D.Sandbox -> @approval:Maybe<&2, Context.ApprovalChoice> -> {InterfaceView.reset_change(Context.Configuration{origin, workspace, Some{sandbox}, approval}, Forms.SandboxMode{}) == Some{Context.UseDefaultSandbox{}} : Maybe<&2, Context.Change>},
    overridden_approval_reset: @origin:Context.Origin -> @workspace:Maybe<&2, D.Workspace> -> @sandbox:Maybe<&2, D.Sandbox> -> @approval:Context.ApprovalChoice -> {InterfaceView.reset_change(Context.Configuration{origin, workspace, sandbox, Some{approval}}, Forms.ApprovalPolicy{}) == Some{Context.UseDefaultApproval{}} : Maybe<&2, Context.Change>},
    draft_source: @+message:U.Text -> @profile:String -> @reasoning:String -> @+config:Context.Configuration -> @scene:V.EditorScene -> @+world:M.World() ->
      {composer_context(View.composer_scene(U.NewTask{message, profile, reasoning, config}, scene, world)) == Some{Context.DraftExecution{Context.preview(config, world)}} : Maybe<&2, Context.Observation>},
    committed_source: @+task:Nat -> @message:U.Text -> @delivery:U.Delivery -> @scene:V.EditorScene -> @+world:M.World() ->
      {composer_context(View.composer_scene(U.Message{task, message, delivery}, scene, world)) == View.committed_observation(View.committed_context(Tasks.find(Commands.entries(world), task))) : Maybe<&2, Context.Observation>},
    admitted_contract: @+task:D.Task -> {View.committed_context(Some{task}) == Some{Context.effective(task)} : Maybe<&2, Context.EffectiveContext>},
    retained_source: @+value:Context.Observation -> @parent: Identity.Key -> @state:InteractionTypes.State ->
      {node_context(InterfaceView.context_summary_node(value, parent, state)) == Some{value} : Maybe<&2, Context.Observation>},
    directory_label: @+path:String -> @+primary:Bool -> @choose:V.ControlDeclaration -> @remove:V.ControlDeclaration -> @parent: Identity.Key -> @state:InteractionTypes.State ->
      {directory_fact(InterfaceView.directory_node(V.WorkspaceRoot{path, primary, choose, remove}, parent, state)) == Some{DirectoryFact{path, path, primary}} : Maybe<&2, DirectoryFact>},
    directory_commands: @+path:String -> @+rest:+List<String> -> @+primary:Maybe<&2, String> -> @+editor:U.Editor ->
      {View.root_controls(path <> rest, primary, editor) ==
        V.WorkspaceRoot{path, View.is_primary(primary, path),
          V.ControlDeclaration{"primary/" ++ U.editor_key(editor) ++ "/" ++ path, "Use as working directory", V.Secondary{},
            U.EditDraft{editor, U.EditWorkspace{Context.ChoosePrimary{path}}}, V.Available{}},
          V.ControlDeclaration{"remove-root/" ++ U.editor_key(editor) ++ "/" ++ path, "Remove directory", V.Secondary{},
            U.EditDraft{editor, U.EditWorkspace{Context.RemoveRoot{path}}}, V.Available{}}} <>
          View.root_controls(rest, primary, editor) : +List<V.WorkspaceRoot>},
    filesystem_preserves_network: @+mode:D.SandboxMode -> @current:D.SandboxMode -> @+network:Bool -> @+editor:U.Editor -> @parent: Identity.Key -> @state:InteractionTypes.State ->
      {choice_input(InterfaceView.sandbox_choice(mode, current, network, editor, parent, state)) == Some{InteractionTypes.ApplicationInput{E.UserInput{U.EditDraft{editor, U.ConfigureContext{Context.SetSandbox{D.Sandbox{mode, network}}}}}}} : Maybe<&2, InteractionTypes.Input>},
    network_preserves_filesystem: @+mode:D.SandboxMode -> @current:Bool -> @+target:Bool -> @+editor:U.Editor -> @parent: Identity.Key -> @state:InteractionTypes.State ->
      {choice_input(InterfaceView.network_choice(mode, current, target, editor, parent, state)) == Some{InteractionTypes.ApplicationInput{E.UserInput{U.EditDraft{editor, U.ConfigureContext{Context.SetSandbox{D.Sandbox{mode, target}}}}}}} : Maybe<&2, InteractionTypes.Input>},
    network_selected: @mode:D.SandboxMode -> @+current:Bool -> @+target:Bool -> @editor:U.Editor -> @parent: Identity.Key -> @state:InteractionTypes.State ->
      {choice_selection(InterfaceView.network_choice(mode, current, target, editor, parent, state)) == Some{Cmp.is_eq(Bool.cmp(current, target))} : Maybe<&2, Bool>},
    approval_action: @+choice:Context.ApprovalChoice -> @current:Context.ApprovalChoice -> @reviewer:Maybe<&2, D.Profile> -> @+editor:U.Editor -> @parent: Identity.Key -> @state:InteractionTypes.State ->
      {choice_input(InterfaceView.approval_choice_node(choice, current, reviewer, editor, parent, state)) == Some{InteractionTypes.ApplicationInput{E.UserInput{U.EditDraft{editor, U.ConfigureContext{Context.SetApproval{choice}}}}}} : Maybe<&2, InteractionTypes.Input>},
    approval_normalization: @+policy:D.ApprovalPolicy ->
      {Context.observed_approval(Context.InheritedApproval{policy}) == Context.observed_approval(Context.ChosenApproval{Context.approval_choice(policy)}) : Context.ApprovalChoice},
    automatic_selection: @+current:String -> @+next:String -> @reviewer:Maybe<&2, D.Profile> -> @editor:U.Editor -> @parent: Identity.Key -> @state:InteractionTypes.State ->
      {choice_selection(InterfaceView.approval_choice_node(Context.AutomaticReview{next}, Context.AutomaticReview{current}, reviewer, editor, parent, state)) == Some{String.eq(current, next)} : Maybe<&2, Bool>},
    ask_codec: {Context.approval_option(Context.observed_approval(Context.InheritedApproval{D.AskForApproval{}})) == "ask" : String},
    unrestricted_codec: {Context.approval_option(Context.observed_approval(Context.InheritedApproval{D.FullAccess{}})) == "full-access" : String},
    automatic_codec: @profile:D.Profile -> {Context.approval_option(Context.observed_approval(Context.InheritedApproval{D.ApprovalForMe{profile}})) == "automatic" : String},
    sandbox_facets: @+origin:Context.Origin -> @+workspace:Maybe<&2, D.Workspace> -> @old:Maybe<&2, D.Sandbox> -> @+approval:Maybe<&2, Context.ApprovalChoice> -> @+next:D.Sandbox ->
      {Context.edit(Context.Configuration{origin, workspace, old, approval}, Context.SetSandbox{next}) == Context.Configuration{origin, workspace, Some{next}, approval} : Context.Configuration},
    reset_workspace: @+origin:Context.Origin -> @old:Maybe<&2, D.Workspace> -> @+sandbox:Maybe<&2, D.Sandbox> -> @+approval:Maybe<&2, Context.ApprovalChoice> ->
      {Context.edit(Context.Configuration{origin, old, sandbox, approval}, Context.UseDefaultWorkspace{}) == Context.Configuration{origin, None{}, sandbox, approval} : Context.Configuration},
    reset_sandbox: @+origin:Context.Origin -> @+workspace:Maybe<&2, D.Workspace> -> @old:Maybe<&2, D.Sandbox> -> @+approval:Maybe<&2, Context.ApprovalChoice> ->
      {Context.edit(Context.Configuration{origin, workspace, old, approval}, Context.UseDefaultSandbox{}) == Context.Configuration{origin, workspace, None{}, approval} : Context.Configuration},
    reset_approval: @+origin:Context.Origin -> @+workspace:Maybe<&2, D.Workspace> -> @+sandbox:Maybe<&2, D.Sandbox> -> @old:Maybe<&2, Context.ApprovalChoice> ->
      {Context.edit(Context.Configuration{origin, workspace, sandbox, old}, Context.UseDefaultApproval{}) == Context.Configuration{origin, workspace, sandbox, None{}} : Context.Configuration},
    inherited_workspace_reset: @editor:U.Editor -> {View.workspace_inheritance(None{}, editor) == None{} : Maybe<&2, V.ControlDeclaration>},
    inherited_sandbox_reset: @origin:Context.Origin -> @workspace:Maybe<&2, D.Workspace> -> @approval:Maybe<&2, Context.ApprovalChoice> ->
      {InterfaceView.reset_change(Context.Configuration{origin, workspace, None{}, approval}, Forms.SandboxMode{}) == None{} : Maybe<&2, Context.Change>},
    inherited_approval_reset: @origin:Context.Origin -> @workspace:Maybe<&2, D.Workspace> -> @sandbox:Maybe<&2, D.Sandbox> ->
      {InterfaceView.reset_change(Context.Configuration{origin, workspace, sandbox, None{}}, Forms.ApprovalPolicy{}) == None{} : Maybe<&2, Context.Change>},
    shared_sandbox_reset: @config:Context.Configuration -> {InterfaceView.reset_change(config, Forms.NetworkAccess{}) == None{} : Maybe<&2, Context.Change>},
    committed_read_only: @+context:Maybe<&2, Context.EffectiveContext> -> @+parent: Identity.Key -> @+state:InteractionTypes.State ->
      {tree_focusable(InterfaceView.committed_context_nodes(context, parent, state)) == False{} : Bool},
    workspace_layer: @+editor:U.Editor -> @+session:E.Session -> @+world:M.World() ->
      {View.layer_content(U.WorkspaceConfiguration{editor}, session, world) == V.WorkspaceSettings{editor, View.selected_fields(View.editor(editor, session, world), V.ExecutionFields{})} : V.LayerContent},
    permissions_layer: @+editor:U.Editor -> @+session:E.Session -> @+world:M.World() ->
      {View.layer_content(U.PermissionsConfiguration{editor}, session, world) == V.PermissionSettings{editor, View.selected_fields(View.editor(editor, session, world), V.ExecutionFields{})} : V.LayerContent},
    committed_layer: @+task:Nat -> @session:E.Session -> @+world:M.World() ->
      {View.layer_content(U.TaskContext{task}, session, world) == V.CommittedContext{View.committed_context(Tasks.find(Commands.entries(world), task))} : V.LayerContent},
    workspace_menu_kind: @editor:U.Editor -> @beside:Bool -> {View.layer_kind(U.WorkspaceConfiguration{editor}, beside) == V.AnchoredMenu{} : V.LayerKind},
    permissions_menu_kind: @editor:U.Editor -> @beside:Bool -> {View.layer_kind(U.PermissionsConfiguration{editor}, beside) == V.AnchoredMenu{} : V.LayerKind},
    committed_dialog_kind: @task:Nat -> @beside:Bool -> {View.layer_kind(U.TaskContext{task}, beside) == V.ModalDialog{} : V.LayerKind}}

law context_evidence:
  ContextRequirements
