import Base
import ../MODEL.bend as M
import ../REASONING.bend as Reasoning
import ../COMMANDS.bend as Commands
import ../PROJECTS.bend as Projects
import ../FEATURES.bend as F
import ../bendlib/domain.bend as D
import ../bendlib/tasks.bend as Tasks
import ./user-context.bend as Context
import ./user-input.bend as U
import ./user-experience.bend as E
import ./ui-world.bend as V
import ./interface.bend as UI
import ./SYSTEM.bend as Core
import ./client-services.bend as Services
import ./form-fields.bend as Forms

def composer_context(value: Maybe<&2, V.ComposerScene>) -> Maybe<&2, Context.Observation>:
  match value:
    case None{}: None{}
    case Some{V.ComposerScene{identity, revision, message, footer, context, submit, feedback, pending}}: context

def node_context(value: UI.Node) -> Maybe<&2, Context.Observation>:
  match value:
    case UI.Node{key, semantic, label, role, UI.ContextSummary{context}, children}: Some{context}
    case _: None{}

type DirectoryFact is Data:
  DirectoryFact{label: String, path: String, primary: Bool}

def directory_fact(value: UI.Node) -> Maybe<&2, DirectoryFact>:
  match value:
    case UI.Node{key, semantic, label, role, UI.DirectoryRow{path, primary}, children}: Some{DirectoryFact{label, path, primary}}
    case _: None{}

def choice_input(value: UI.Node) -> Maybe<&2, Core.Input>:
  match value:
    case UI.Node{key, semantic, label, role, UI.Choice{kind, icon, selected, description, input, availability}, children}: Some{input}
    case _: None{}

def choice_selection(value: UI.Node) -> Maybe<&2, Bool>:
  match value:
    case UI.Node{key, semantic, label, role, UI.Choice{kind, icon, selected, description, input, availability}, children}: Some{selected}
    case _: None{}

def tree_focusable(nodes: +List<UI.Node>) -> Bool:
  match nodes:
    case Nil{}: False{}
    case Con{UI.Node{key, semantic, label, role, meaning, children}, rest}:
      UI.focusable(meaning) || tree_focusable(children) || tree_focusable(rest)

def first_context(nodes: +List<UI.Node>) -> Maybe<&2, Context.Observation>:
  match nodes:
    case Nil{}: None{}
    case Con{node, rest}: node_context(node)

def workspace_menu_source_law(-editor: U.Editor, -config: Context.Configuration,
  -origin: Context.Origin, -project: Maybe<&2, Nat>, -workspace: Context.WorkspaceValue,
  -sandbox: Context.SandboxValue, -approval: Context.ApprovalValue,
  -guidance: Context.GuidancePreview, -controls: V.WorkspaceControls,
  -projects: +List<V.ProjectChoice>, -reviewers: +List<D.Profile>, -parent: String,
  -state: Core.State) -> Type:
  {first_context(UI.workspace_menu_group(editor, V.ExecutionInput{config, Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}, controls, projects, reviewers}, parent, state)) ==
    Some{Context.DraftExecution{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}}} : Maybe<&2, Context.Observation>}

def permissions_menu_source_law(-editor: U.Editor, -config: Context.Configuration,
  -origin: Context.Origin, -project: Maybe<&2, Nat>, -workspace: Context.WorkspaceValue,
  -sandbox: Context.SandboxValue, -approval: Context.ApprovalValue,
  -guidance: Context.GuidancePreview, -controls: V.WorkspaceControls,
  -projects: +List<V.ProjectChoice>, -reviewers: +List<D.Profile>, -parent: String,
  -state: Core.State) -> Type:
  {first_context(UI.permission_menu_group(editor, V.ExecutionInput{config, Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}, controls, projects, reviewers}, parent, state)) ==
    Some{Context.DraftExecution{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}}} : Maybe<&2, Context.Observation>}

def effective_task(value: Context.EffectiveContext) -> Nat:
  Context.EffectiveContext{task, context, guidance, access} = value
  task

type ChoiceCaption is Data:
  ChoiceCaption{label: String, description: String}

def choice_caption(value: UI.Node) -> Maybe<&2, ChoiceCaption>:
  match value:
    case UI.Node{key, semantic, label, role, UI.Choice{kind, icon, selected, description, input, availability}, children}: Some{ChoiceCaption{label, description}}
    case _: None{}

def network_pair(value: UI.Node) -> Sigma<&2, &2, Maybe<&2, Bool>, (_ => Maybe<&2, Bool>)>:
  match value:
    case UI.Node{key, semantic, label, role, meaning, Con{disabled, Con{enabled, Nil{}}}}: (choice_selection(disabled), choice_selection(enabled))
    case _: (None{}, None{})

type Requirements is Type:
  Requirements{
    committed_project_node_world: @+project:Maybe<&2, Nat> -> @+world:M.World() -> @session:E.Session -> @services:Services.State -> @parent:String ->
      {UI.node_label(UI.committed_project_node(project, parent, Core.State{E.Application{world, session}, services})) == UI.committed_project_text(project, world) : String},
    committed_source_label: @task:Nat -> @context:D.TaskContext -> @guidance:D.ProjectContext -> @access:D.ExecutionAccess -> @world:M.World() ->
      {V.execution_source_summary(Context.CommittedExecution{Context.EffectiveContext{task, context, guidance, access}}, world) == "Task settings" : String},
    committed_project_name: @id:Nat -> @+name:String -> @workspace:D.Workspace -> @guidance:D.ProjectContext ->
      {UI.committed_project_name(Some{D.Project{name, workspace, guidance}}, id) == name : String},
    committed_project_missing: @+id:Nat -> {UI.committed_project_name(None{}, id) == "Project unavailable (ID " ++ Nat.show(id) ++ ")" : String},
    committed_project_lookup: @+id:Nat -> @+world:M.World() ->
      {UI.committed_project_text(Some{id}, world) == UI.committed_project_name(Projects.find(Projects.registry(F.State(), world), id), id) : String},
    projectless_context: @world:M.World() -> {UI.committed_project_text(None{}, world) == "Projectless task" : String},
    primary_directory_no_duplicate: @primary:Maybe<&2, String> -> @parent:String ->
      {UI.committed_working_directory_extra(True{}, primary, parent) == Nil{} : +List<UI.Node>},
    absent_primary_directory_fact: @+parent:String ->
      {UI.committed_working_directory_extra(False{}, None{}, parent) == [UI.Node{parent ++ "/working-directory", "context/working-directory", "No working directory", UI.Content{}, UI.ReadOnly{"No working directory"}, Nil{}}] : +List<UI.Node>},
    network_group_selection: @mode:D.SandboxMode -> @+network:Bool -> @editor:U.Editor -> @parent:String -> @state:Core.State ->
      {network_pair(UI.network_choices(D.Sandbox{mode, network}, editor, parent, state)) == (Some{Bool.not(network)}, Some{network}) : Sigma<&2, &2, Maybe<&2, Bool>, (_ => Maybe<&2, Bool>)>},
    filesystem_write_caption: @current:D.SandboxMode -> @network:Bool -> @editor:U.Editor -> @parent:String -> @state:Core.State -> {choice_caption(UI.sandbox_choice(D.WorkspaceWrite{}, current, network, editor, parent, state)) == Some{ChoiceCaption{"Workspace write", "Allow edits in the working directories."}} : Maybe<&2, ChoiceCaption>},
    filesystem_read_caption: @current:D.SandboxMode -> @network:Bool -> @editor:U.Editor -> @parent:String -> @state:Core.State -> {choice_caption(UI.sandbox_choice(D.ReadOnly{}, current, network, editor, parent, state)) == Some{ChoiceCaption{"Read only", "Read files without modifying them."}} : Maybe<&2, ChoiceCaption>},
    network_disabled_caption: @mode:D.SandboxMode -> @current:Bool -> @editor:U.Editor -> @parent:String -> @state:Core.State -> {choice_caption(UI.network_choice(mode, current, False{}, editor, parent, state)) == Some{ChoiceCaption{"Disabled", "Keep network access off."}} : Maybe<&2, ChoiceCaption>},
    network_enabled_caption: @mode:D.SandboxMode -> @current:Bool -> @editor:U.Editor -> @parent:String -> @state:Core.State -> {choice_caption(UI.network_choice(mode, current, True{}, editor, parent, state)) == Some{ChoiceCaption{"Enabled", "Allow network access."}} : Maybe<&2, ChoiceCaption>},
    ask_caption: @current:Context.ApprovalChoice -> @editor:U.Editor -> @parent:String -> @state:Core.State -> {choice_caption(UI.approval_choice_node(Context.Ask{}, current, None{}, editor, parent, state)) == Some{ChoiceCaption{"Ask", "Ask before running actions that require approval."}} : Maybe<&2, ChoiceCaption>},
    unrestricted_caption: @current:Context.ApprovalChoice -> @editor:U.Editor -> @parent:String -> @state:Core.State -> {choice_caption(UI.approval_choice_node(Context.Unrestricted{}, current, None{}, editor, parent, state)) == Some{ChoiceCaption{"Unrestricted", "Run actions without approval prompts."}} : Maybe<&2, ChoiceCaption>},
    automatic_caption: @+key:String -> @provider:String -> @+name:String -> @reasoning:Reasoning.Policy -> @current:Context.ApprovalChoice -> @editor:U.Editor -> @parent:String -> @state:Core.State -> {choice_caption(UI.approval_choice_node(Context.AutomaticReview{key}, current, Some{D.Profile{key, provider, name, reasoning}}, editor, parent, state)) == Some{ChoiceCaption{"Automatic review: " ++ name, "Use this model to review approval requests."}} : Maybe<&2, ChoiceCaption>},
    unavailable_profile_caption: @+key:String -> {V.automatic_review_summary(None{}, key) == "Automatic review unavailable: " ++ key : String},
    admitted_task_identity: @+task:D.Task -> {effective_task(Context.effective(task)) == D.task_id(task) : Nat},
    passive_directory: @path:String -> @primary:Bool -> @gesture:UI.Gesture -> {UI.bind(UI.DirectoryRow{path, primary}, gesture) == None{} : Maybe<&2, Core.Input>},
    passive_summary: @value:Context.Observation -> @gesture:UI.Gesture -> {UI.bind(UI.ContextSummary{value}, gesture) == None{} : Maybe<&2, Core.Input>},
    available_choice: @selected:Bool -> @description:String -> @+input:Core.Input -> {UI.bind(UI.Choice{UI.SingleChoice{}, None{}, selected, description, input, V.Available{}}, UI.Press{}) == Some{input} : Maybe<&2, Core.Input>},
    unavailable_choice: @selected:Bool -> @description:String -> @input:Core.Input -> @reason:String -> {UI.bind(UI.Choice{UI.SingleChoice{}, None{}, selected, description, input, V.Unavailable{reason}}, UI.Press{}) == None{} : Maybe<&2, Core.Input>},
    draft_footer: @+editor:U.Editor -> @+observation:Context.Observation -> @+profiles:+List<D.Profile> ->
      {V.draft_context_footer(editor, observation, profiles) ==
        [V.ComposerControl{V.WorkspaceSubject{}, V.ControlDeclaration{"composer/workspace/" ++ U.editor_key(editor), V.observation_workspace(observation), V.Secondary{},
          U.Activate{U.OpenPanel{U.WorkspaceConfiguration{editor}, "composer/workspace/" ++ U.editor_key(editor)}}, V.Available{}}},
         V.ComposerControl{V.PermissionsSubject{}, V.ControlDeclaration{"composer/permissions/" ++ U.editor_key(editor), V.observation_permissions(observation, profiles), V.Secondary{},
          U.Activate{U.OpenPanel{U.PermissionsConfiguration{editor}, "composer/permissions/" ++ U.editor_key(editor)}}, V.Available{}}}] : +List<V.ComposerControl>},
    committed_footer: @+task:Nat -> @+observation:Context.Observation -> @+profiles:+List<D.Profile> ->
      {V.committed_context_footer(task, Some{observation}, profiles) ==
        [V.ComposerControl{V.WorkspaceSubject{}, V.ControlDeclaration{"composer/workspace/message/" ++ Nat.show(task), V.observation_workspace(observation), V.Secondary{},
          U.Activate{U.OpenPanel{U.TaskContext{task}, "composer/workspace/message/" ++ Nat.show(task)}}, V.Available{}}},
         V.ComposerControl{V.PermissionsSubject{}, V.ControlDeclaration{"composer/permissions/message/" ++ Nat.show(task), V.observation_permissions(observation, profiles), V.Secondary{},
          U.Activate{U.OpenPanel{U.TaskContext{task}, "composer/permissions/message/" ++ Nat.show(task)}}, V.Available{}}}] : +List<V.ComposerControl>},
    workspace_menu_source: @+editor:U.Editor -> @config:Context.Configuration -> @+origin:Context.Origin -> @+project:Maybe<&2, Nat> -> @+workspace:Context.WorkspaceValue -> @+sandbox:Context.SandboxValue -> @+approval:Context.ApprovalValue -> @+guidance:Context.GuidancePreview -> @controls:V.WorkspaceControls -> @projects:+List<V.ProjectChoice> -> @reviewers:+List<D.Profile> -> @parent:String -> @state:Core.State ->
      workspace_menu_source_law(editor, config, origin, project, workspace, sandbox, approval, guidance, controls, projects, reviewers, parent, state),
    permissions_menu_source: @+editor:U.Editor -> @config:Context.Configuration -> @+origin:Context.Origin -> @+project:Maybe<&2, Nat> -> @+workspace:Context.WorkspaceValue -> @+sandbox:Context.SandboxValue -> @+approval:Context.ApprovalValue -> @+guidance:Context.GuidancePreview -> @controls:V.WorkspaceControls -> @projects:+List<V.ProjectChoice> -> @reviewers:+List<D.Profile> -> @parent:String -> @state:Core.State ->
      permissions_menu_source_law(editor, config, origin, project, workspace, sandbox, approval, guidance, controls, projects, reviewers, parent, state),
    unavailable_workspace: @+reason:String -> @config:Context.Configuration -> @controls:V.WorkspaceControls -> @projects:+List<V.ProjectChoice> -> @reviewers:+List<D.Profile> -> @editor:U.Editor -> @+parent:String -> @state:Core.State ->
      {UI.workspace_menu_group(editor, V.ExecutionInput{config, Context.ContextUnavailable{reason}, controls, projects, reviewers}, parent, state) == [UI.Node{parent ++ "/unavailable", "context/unavailable", reason, UI.Content{}, UI.ReadOnly{reason}, Nil{}}] : +List<UI.Node>},
    unavailable_permissions: @+reason:String -> @config:Context.Configuration -> @controls:V.WorkspaceControls -> @projects:+List<V.ProjectChoice> -> @reviewers:+List<D.Profile> -> @editor:U.Editor -> @+parent:String -> @state:Core.State ->
      {UI.permission_menu_group(editor, V.ExecutionInput{config, Context.ContextUnavailable{reason}, controls, projects, reviewers}, parent, state) == [UI.Node{parent ++ "/unavailable", "context/unavailable", reason, UI.Content{}, UI.ReadOnly{reason}, Nil{}}] : +List<UI.Node>},
    overridden_workspace_reset: @+workspace:D.Workspace -> @+editor:U.Editor -> {V.workspace_inheritance(Some{workspace}, editor) == Some{V.ControlDeclaration{"inherit-workspace/" ++ U.editor_key(editor), "Use inherited workspace", V.Secondary{}, U.EditDraft{editor, U.ConfigureContext{Context.UseDefaultWorkspace{}}}, V.Available{}}} : Maybe<&2, V.ControlDeclaration>},
    overridden_sandbox_reset: @origin:Context.Origin -> @workspace:Maybe<&2, D.Workspace> -> @sandbox:D.Sandbox -> @approval:Maybe<&2, Context.ApprovalChoice> -> {UI.reset_change(Context.Configuration{origin, workspace, Some{sandbox}, approval}, Forms.SandboxMode{}) == Some{Context.UseDefaultSandbox{}} : Maybe<&2, Context.Change>},
    overridden_approval_reset: @origin:Context.Origin -> @workspace:Maybe<&2, D.Workspace> -> @sandbox:Maybe<&2, D.Sandbox> -> @approval:Context.ApprovalChoice -> {UI.reset_change(Context.Configuration{origin, workspace, sandbox, Some{approval}}, Forms.ApprovalPolicy{}) == Some{Context.UseDefaultApproval{}} : Maybe<&2, Context.Change>},
    draft_source: @+message:U.Text -> @profile:String -> @reasoning:String -> @+config:Context.Configuration -> @scene:V.EditorScene -> @+world:M.World() ->
      {composer_context(V.composer_scene(U.NewTask{message, profile, reasoning, config}, scene, world)) == Some{Context.DraftExecution{Context.preview(config, world)}} : Maybe<&2, Context.Observation>},
    committed_source: @+task:Nat -> @message:U.Text -> @delivery:U.Delivery -> @scene:V.EditorScene -> @+world:M.World() ->
      {composer_context(V.composer_scene(U.Message{task, message, delivery}, scene, world)) == V.committed_observation(V.committed_context(Tasks.find(Commands.entries(world), task))) : Maybe<&2, Context.Observation>},
    admitted_contract: @+task:D.Task -> {V.committed_context(Some{task}) == Some{Context.effective(task)} : Maybe<&2, Context.EffectiveContext>},
    retained_source: @+value:Context.Observation -> @parent:String -> @state:Core.State ->
      {node_context(UI.context_summary_node(value, parent, state)) == Some{value} : Maybe<&2, Context.Observation>},
    directory_label: @+path:String -> @+primary:Bool -> @choose:V.ControlDeclaration -> @remove:V.ControlDeclaration -> @parent:String -> @state:Core.State ->
      {directory_fact(UI.directory_node(V.WorkspaceRoot{path, primary, choose, remove}, parent, state)) == Some{DirectoryFact{path, path, primary}} : Maybe<&2, DirectoryFact>},
    directory_commands: @+path:String -> @+rest:+List<String> -> @+primary:Maybe<&2, String> -> @+editor:U.Editor ->
      {V.root_controls(path <> rest, primary, editor) ==
        V.WorkspaceRoot{path, V.is_primary(primary, path),
          V.ControlDeclaration{"primary/" ++ U.editor_key(editor) ++ "/" ++ path, "Use as working directory", V.Secondary{},
            U.EditDraft{editor, U.EditWorkspace{Context.ChoosePrimary{path}}}, V.Available{}},
          V.ControlDeclaration{"remove-root/" ++ U.editor_key(editor) ++ "/" ++ path, "Remove directory", V.Secondary{},
            U.EditDraft{editor, U.EditWorkspace{Context.RemoveRoot{path}}}, V.Available{}}} <>
          V.root_controls(rest, primary, editor) : +List<V.WorkspaceRoot>},
    filesystem_preserves_network: @+mode:D.SandboxMode -> @current:D.SandboxMode -> @+network:Bool -> @+editor:U.Editor -> @parent:String -> @state:Core.State ->
      {choice_input(UI.sandbox_choice(mode, current, network, editor, parent, state)) == Some{Core.ApplicationInput{E.UserInput{U.EditDraft{editor, U.ConfigureContext{Context.SetSandbox{D.Sandbox{mode, network}}}}}}} : Maybe<&2, Core.Input>},
    network_preserves_filesystem: @+mode:D.SandboxMode -> @current:Bool -> @+target:Bool -> @+editor:U.Editor -> @parent:String -> @state:Core.State ->
      {choice_input(UI.network_choice(mode, current, target, editor, parent, state)) == Some{Core.ApplicationInput{E.UserInput{U.EditDraft{editor, U.ConfigureContext{Context.SetSandbox{D.Sandbox{mode, target}}}}}}} : Maybe<&2, Core.Input>},
    network_selected: @mode:D.SandboxMode -> @+current:Bool -> @+target:Bool -> @editor:U.Editor -> @parent:String -> @state:Core.State ->
      {choice_selection(UI.network_choice(mode, current, target, editor, parent, state)) == Some{Cmp.is_eq(Bool.cmp(current, target))} : Maybe<&2, Bool>},
    approval_action: @+choice:Context.ApprovalChoice -> @current:Context.ApprovalChoice -> @reviewer:Maybe<&2, D.Profile> -> @+editor:U.Editor -> @parent:String -> @state:Core.State ->
      {choice_input(UI.approval_choice_node(choice, current, reviewer, editor, parent, state)) == Some{Core.ApplicationInput{E.UserInput{U.EditDraft{editor, U.ConfigureContext{Context.SetApproval{choice}}}}}} : Maybe<&2, Core.Input>},
    approval_normalization: @+policy:D.ApprovalPolicy ->
      {Context.observed_approval(Context.InheritedApproval{policy}) == Context.observed_approval(Context.ChosenApproval{Context.approval_choice(policy)}) : Context.ApprovalChoice},
    automatic_selection: @+current:String -> @+next:String -> @reviewer:Maybe<&2, D.Profile> -> @editor:U.Editor -> @parent:String -> @state:Core.State ->
      {choice_selection(UI.approval_choice_node(Context.AutomaticReview{next}, Context.AutomaticReview{current}, reviewer, editor, parent, state)) == Some{String.eq(current, next)} : Maybe<&2, Bool>},
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
    inherited_workspace_reset: @editor:U.Editor -> {V.workspace_inheritance(None{}, editor) == None{} : Maybe<&2, V.ControlDeclaration>},
    inherited_sandbox_reset: @origin:Context.Origin -> @workspace:Maybe<&2, D.Workspace> -> @approval:Maybe<&2, Context.ApprovalChoice> ->
      {UI.reset_change(Context.Configuration{origin, workspace, None{}, approval}, Forms.SandboxMode{}) == None{} : Maybe<&2, Context.Change>},
    inherited_approval_reset: @origin:Context.Origin -> @workspace:Maybe<&2, D.Workspace> -> @sandbox:Maybe<&2, D.Sandbox> ->
      {UI.reset_change(Context.Configuration{origin, workspace, sandbox, None{}}, Forms.ApprovalPolicy{}) == None{} : Maybe<&2, Context.Change>},
    shared_sandbox_reset: @config:Context.Configuration -> {UI.reset_change(config, Forms.NetworkAccess{}) == None{} : Maybe<&2, Context.Change>},
    committed_read_only: @+context:Maybe<&2, Context.EffectiveContext> -> @+parent:String -> @+state:Core.State ->
      {tree_focusable(UI.committed_context_nodes(context, parent, state)) == False{} : Bool},
    workspace_layer: @+editor:U.Editor -> @+session:E.Session -> @+world:M.World() ->
      {V.layer_content(U.WorkspaceConfiguration{editor}, session, world) == V.WorkspaceSettings{editor, V.selected_fields(V.editor(editor, session, world), V.ExecutionFields{})} : V.LayerContent},
    permissions_layer: @+editor:U.Editor -> @+session:E.Session -> @+world:M.World() ->
      {V.layer_content(U.PermissionsConfiguration{editor}, session, world) == V.PermissionSettings{editor, V.selected_fields(V.editor(editor, session, world), V.ExecutionFields{})} : V.LayerContent},
    committed_layer: @+task:Nat -> @session:E.Session -> @+world:M.World() ->
      {V.layer_content(U.TaskContext{task}, session, world) == V.CommittedContext{V.committed_context(Tasks.find(Commands.entries(world), task))} : V.LayerContent},
    workspace_menu_kind: @editor:U.Editor -> @beside:Bool -> {V.layer_kind(U.WorkspaceConfiguration{editor}, beside) == V.AnchoredMenu{} : V.LayerKind},
    permissions_menu_kind: @editor:U.Editor -> @beside:Bool -> {V.layer_kind(U.PermissionsConfiguration{editor}, beside) == V.AnchoredMenu{} : V.LayerKind},
    committed_dialog_kind: @task:Nat -> @beside:Bool -> {V.layer_kind(U.TaskContext{task}, beside) == V.ModalDialog{} : V.LayerKind}}

law evidence:
  Requirements
