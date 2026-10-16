import ../../harness/workspace/WORKSPACE.bend as Workspace
import ../experience/PROGRAM.bend as UX
import ../experience/MODEL.bend as Experience
import ../submission/FIELDS.bend as Forms
import Base
import ../IDENTITY.bend as Identity
import ./CONTRACT.bend as Rule
import ../../bendlib/stdlib.bend as Std
import ../../harness/MODEL.bend as M
import ../../harness/reasoning/MODEL.bend as Reasoning
import ../../harness/COMMANDS.bend as Commands
import ../../harness/DOMAIN.bend as D
import ../../harness/tasks/PROGRAM.bend as Tasks
import ./CONTEXT.bend as Context
import ../INPUT.bend as U
import ../session/MODEL.bend as E
import ../presentation/MODEL.bend as V
import ../presentation/PROGRAM.bend as InterfaceView
import ../presentation/VIEW.bend as View
import ../TYPES.bend as InteractionTypes
import ../presentation/SURFACE.bend as SurfaceTypes

def draft_composer_context(+message: U.Text, profile: String, reasoning: String, +config: Context.Configuration, scene: V.EditorScene, +world: M.World()) ->
  {Rule.composer_context(View.composer_scene(U.NewTask{message, profile, reasoning, config}, scene, world)) ==
    Some{Context.DraftExecution{Context.preview(config, world)}} : Maybe<&2, Context.Observation>}:
  V.EditorScene{identity, revision, groups, sections, assessment, submit, feedback, pending} = scene
  {==}

def message_composer_context(+task: Nat, message: U.Text, delivery: U.Delivery, scene: V.EditorScene, +world: M.World()) ->
  {Rule.composer_context(View.composer_scene(U.Message{task, message, delivery}, scene, world)) ==
    View.committed_observation(View.committed_context(Tasks.find(Commands.entries(world), task))) : Maybe<&2, Context.Observation>}:
  V.EditorScene{identity, revision, groups, sections, assessment, submit, feedback, pending} = scene
  {==}

def retained_summary(+value: Context.Observation, parent: Identity.Key, state: InteractionTypes.State) ->
  {Rule.node_context(InterfaceView.context_summary_node(value, parent, state)) == Some{value} : Maybe<&2, Context.Observation>}:
  InteractionTypes.State{E.Application{world, session}, services} = state
  {==}

def alternative_value(value: Experience.Alternative) -> Experience.Value:
  Experience.Alternative{label, explanation, value} = value
  value

def input_projection(+found: Maybe<&2, U.Input>, +decision: Experience.Decision, +alternative: Experience.Alternative, +parent: Identity.Key, +state: InteractionTypes.State) ->
  {Rule.choice_input(InterfaceView.decision_choice_resolved(found, decision, alternative, parent, state)) == Rule.expected_input(found) : Maybe<&2, InteractionTypes.Input>}:
  match found alternative state:
    case None{} Experience.Alternative{label, explanation, value} InteractionTypes.State{application, services}: {==}
    case Some{input} Experience.Alternative{label, explanation, value} InteractionTypes.State{application, services}: {==}

def selection_projection(+found: Maybe<&2, U.Input>, +decision: Experience.Decision, +alternative: Experience.Alternative, +parent: Identity.Key, +state: InteractionTypes.State) ->
  {Rule.choice_selection(InterfaceView.decision_choice_resolved(found, decision, alternative, parent, state)) == Rule.expected_selection(found, UX.selected(decision, alternative_value(alternative))) : Maybe<&2, Bool>}:
  match found alternative state:
    case None{} Experience.Alternative{label, explanation, value} InteractionTypes.State{application, services}: {==}
    case Some{input} Experience.Alternative{label, explanation, value} InteractionTypes.State{application, services}: {==}

def mode_input(+mode: D.SandboxMode, +current: D.SandboxMode, +network: Bool, +editor: U.Editor, +parent: Identity.Key, +state: InteractionTypes.State) ->
  {Rule.choice_input(InterfaceView.sandbox_choice(mode, current, network, editor, parent, state)) == Rule.expected_input(UX.choose(UX.decision(Experience.Subject{editor, Forms.SandboxMode{}}, InterfaceView.field_value(state, editor, Forms.SandboxMode{}), "Filesystem access", [InterfaceView.sandbox_alternative(mode)]), Experience.Filesystem{mode})) : Maybe<&2, InteractionTypes.Input>}:
  input_projection(UX.choose(UX.decision(Experience.Subject{editor, Forms.SandboxMode{}}, InterfaceView.field_value(state, editor, Forms.SandboxMode{}), "Filesystem access", [InterfaceView.sandbox_alternative(mode)]), Experience.Filesystem{mode}), UX.decision(Experience.Subject{editor, Forms.SandboxMode{}}, InterfaceView.field_value(state, editor, Forms.SandboxMode{}), "Filesystem access", [InterfaceView.sandbox_alternative(mode)]), InterfaceView.sandbox_alternative(mode), parent, state)

def network_input(+mode: D.SandboxMode, +current: Bool, +target: Bool, +editor: U.Editor, +parent: Identity.Key, +state: InteractionTypes.State) ->
  {Rule.choice_input(InterfaceView.network_choice(mode, current, target, editor, parent, state)) == Rule.expected_input(UX.choose(UX.decision(Experience.Subject{editor, Forms.NetworkAccess{}}, InterfaceView.field_value(state, editor, Forms.NetworkAccess{}), "Network access", [InterfaceView.network_alternative(target)]), Experience.Network{target})) : Maybe<&2, InteractionTypes.Input>}:
  input_projection(UX.choose(UX.decision(Experience.Subject{editor, Forms.NetworkAccess{}}, InterfaceView.field_value(state, editor, Forms.NetworkAccess{}), "Network access", [InterfaceView.network_alternative(target)]), Experience.Network{target}), UX.decision(Experience.Subject{editor, Forms.NetworkAccess{}}, InterfaceView.field_value(state, editor, Forms.NetworkAccess{}), "Network access", [InterfaceView.network_alternative(target)]), InterfaceView.network_alternative(target), parent, state)

def network_selection(+mode: D.SandboxMode, +current: Bool, +target: Bool, +editor: U.Editor, +parent: Identity.Key, +state: InteractionTypes.State) ->
  {Rule.choice_selection(InterfaceView.network_choice(mode, current, target, editor, parent, state)) == Rule.expected_selection(UX.choose(UX.decision(Experience.Subject{editor, Forms.NetworkAccess{}}, InterfaceView.field_value(state, editor, Forms.NetworkAccess{}), "Network access", [InterfaceView.network_alternative(target)]), Experience.Network{target}), UX.selected(UX.decision(Experience.Subject{editor, Forms.NetworkAccess{}}, InterfaceView.field_value(state, editor, Forms.NetworkAccess{}), "Network access", [InterfaceView.network_alternative(target)]), Experience.Network{target})) : Maybe<&2, Bool>}:
  selection_projection(UX.choose(UX.decision(Experience.Subject{editor, Forms.NetworkAccess{}}, InterfaceView.field_value(state, editor, Forms.NetworkAccess{}), "Network access", [InterfaceView.network_alternative(target)]), Experience.Network{target}), UX.decision(Experience.Subject{editor, Forms.NetworkAccess{}}, InterfaceView.field_value(state, editor, Forms.NetworkAccess{}), "Network access", [InterfaceView.network_alternative(target)]), InterfaceView.network_alternative(target), parent, state)

def approval_input(+choice: Context.ApprovalChoice, +current: Context.ApprovalChoice, +reviewer: Maybe<&2, D.Profile>, +editor: U.Editor, +parent: Identity.Key, +state: InteractionTypes.State) ->
  {Rule.choice_input(InterfaceView.approval_choice_node(choice, current, reviewer, editor, parent, state)) == Rule.expected_input(UX.choose(UX.decision(Experience.Subject{editor, Forms.ApprovalPolicy{}}, InterfaceView.field_value(state, editor, Forms.ApprovalPolicy{}), "Approval policy", [InterfaceView.approval_alternative(choice, reviewer)]), Experience.Approval{choice})) : Maybe<&2, InteractionTypes.Input>}:
  input_projection(UX.choose(UX.decision(Experience.Subject{editor, Forms.ApprovalPolicy{}}, InterfaceView.field_value(state, editor, Forms.ApprovalPolicy{}), "Approval policy", [InterfaceView.approval_alternative(choice, reviewer)]), Experience.Approval{choice}), UX.decision(Experience.Subject{editor, Forms.ApprovalPolicy{}}, InterfaceView.field_value(state, editor, Forms.ApprovalPolicy{}), "Approval policy", [InterfaceView.approval_alternative(choice, reviewer)]), InterfaceView.approval_alternative(choice, reviewer), parent, state)

def automatic_selection(+current: String, +next: String, +reviewer: Maybe<&2, D.Profile>, +editor: U.Editor, +parent: Identity.Key, +state: InteractionTypes.State) ->
  {Rule.choice_selection(InterfaceView.approval_choice_node(Context.AutomaticReview{next}, Context.AutomaticReview{current}, reviewer, editor, parent, state)) == Rule.expected_selection(UX.choose(UX.decision(Experience.Subject{editor, Forms.ApprovalPolicy{}}, InterfaceView.field_value(state, editor, Forms.ApprovalPolicy{}), "Approval policy", [InterfaceView.approval_alternative(Context.AutomaticReview{next}, reviewer)]), Experience.Approval{Context.AutomaticReview{next}}), UX.selected(UX.decision(Experience.Subject{editor, Forms.ApprovalPolicy{}}, InterfaceView.field_value(state, editor, Forms.ApprovalPolicy{}), "Approval policy", [InterfaceView.approval_alternative(Context.AutomaticReview{next}, reviewer)]), Experience.Approval{Context.AutomaticReview{next}})) : Maybe<&2, Bool>}:
  selection_projection(UX.choose(UX.decision(Experience.Subject{editor, Forms.ApprovalPolicy{}}, InterfaceView.field_value(state, editor, Forms.ApprovalPolicy{}), "Approval policy", [InterfaceView.approval_alternative(Context.AutomaticReview{next}, reviewer)]), Experience.Approval{Context.AutomaticReview{next}}), UX.decision(Experience.Subject{editor, Forms.ApprovalPolicy{}}, InterfaceView.field_value(state, editor, Forms.ApprovalPolicy{}), "Approval policy", [InterfaceView.approval_alternative(Context.AutomaticReview{next}, reviewer)]), InterfaceView.approval_alternative(Context.AutomaticReview{next}, reviewer), parent, state)

def no_duplicate_network_reset(config: Context.Configuration) ->
  {InterfaceView.reset_change(config, Forms.NetworkAccess{}) == None{} : Maybe<&2, Context.Change>}:
  Context.Configuration{origin, workspace, sandbox, approval} = config
  {==}

def unavailable_workspace(+reason: String, config: Context.Configuration, controls: V.WorkspaceControls, projects: +List<V.ProjectChoice>, reviewers: +List<D.Profile>, editor: U.Editor, +parent: Identity.Key, state: InteractionTypes.State) ->
  {InterfaceView.workspace_menu_group(editor, V.ExecutionInput{config, Context.ContextUnavailable{reason}, controls, projects, reviewers}, parent, state) ==
    [SurfaceTypes.Node{Identity.Part{parent, "unavailable"}, "context/unavailable", reason, SurfaceTypes.Content{}, SurfaceTypes.ReadOnly{reason}, Nil{}}] : +List<SurfaceTypes.Node>}:
  V.WorkspaceControls{identity, roots, inherit} = controls
  {==}

def committed_directories_nil(primary: Maybe<&2, String>, parent: Identity.Key) ->
  {Rule.tree_focusable(InterfaceView.committed_directory_nodes(Nil{}, primary, parent)) == False{} : Bool}:
  {==}

def committed_directories_step(+path: String, +rest: +List<String>, +primary: Maybe<&2, String>, +parent: Identity.Key,
  ih: {Rule.tree_focusable(InterfaceView.committed_directory_nodes(rest, primary, parent)) == False{} : Bool}) ->
  {Rule.tree_focusable(InterfaceView.committed_directory_nodes(path <> rest, primary, parent)) == False{} : Bool}:
  ih

def committed_directories_passive(+roots: +List<String>, +primary: Maybe<&2, String>, +parent: Identity.Key) ->
  {Rule.tree_focusable(InterfaceView.committed_directory_nodes(roots, primary, parent)) == False{} : Bool}:
  proof: @+selected:Maybe<&2, String> -> @+owner:Identity.Key -> {Rule.tree_focusable(InterfaceView.committed_directory_nodes(roots, selected, owner)) == False{} : Bool} = Std.list_ind(~String,
    ~(values => @+selected:Maybe<&2, String> -> @+owner:Identity.Key -> {Rule.tree_focusable(InterfaceView.committed_directory_nodes(values, selected, owner)) == False{} : Bool}),
    ~(selected => owner => committed_directories_nil(selected, owner)),
    ~(path => rest => ih => selected => owner => committed_directories_step(path, rest, selected, owner, ih(selected, owner))), roots)
  proof(primary, parent)

def committed_extra_directories_passive(covered: Bool, +roots: +List<String>, +primary: Maybe<&2, String>, +parent: Identity.Key) ->
  {Rule.tree_focusable(List.append(&2, SurfaceTypes.Node, InterfaceView.committed_working_directory_extra(covered, primary, parent), InterfaceView.committed_directory_nodes(roots, primary, parent))) == False{} : Bool}:
  match covered:
    case True{}: committed_directories_passive(roots, primary, parent)
    case False{}: committed_directories_passive(roots, primary, parent)

def committed_context_passive(+context: Maybe<&2, Context.EffectiveContext>, +parent: Identity.Key, +state: InteractionTypes.State) ->
  {Rule.tree_focusable(InterfaceView.committed_context_nodes(context, parent, state)) == False{} : Bool}:
  match context:
    case None{}: {==}
    case Some{Context.EffectiveContext{task, D.TaskContext{D.Workspace{+roots, +primary}, sandbox, approval, project}, guidance, access}}:
      InteractionTypes.State{E.Application{world, session}, services} = state
      committed_extra_directories_passive(Context.member_primary(primary, roots), roots, primary, parent)

def workspace_menu_observation(+editor: U.Editor, config: Context.Configuration, +origin: Context.Origin, +project: Maybe<&2, Nat>, +workspace: Context.WorkspaceValue,
  +sandbox: Context.SandboxValue, +approval: Context.ApprovalValue, +guidance: Context.GuidancePreview,
  controls: V.WorkspaceControls, projects: +List<V.ProjectChoice>, reviewers: +List<D.Profile>, parent: Identity.Key, state: InteractionTypes.State) ->
  Rule.workspace_menu_source_law(editor, config, origin, project, workspace, sandbox, approval, guidance, controls, projects, reviewers, parent, state):
  V.WorkspaceControls{identity, roots, inherit} = controls
  InteractionTypes.State{E.Application{world, session}, services} = state
  {==}

def committed_permission_observation(+found: Maybe<&2, Context.EffectiveContext>, +parent: Identity.Key, +state: InteractionTypes.State, +rest: +List<SurfaceTypes.Node>) ->
  {Rule.first_context(List.append(&2, SurfaceTypes.Node, InterfaceView.committed_permission_summary(found, parent, state), rest)) == View.committed_observation(found) : Maybe<&2, Context.Observation>}:
  match found:
    case None{}: {==}
    case Some{context}:
      InteractionTypes.State{E.Application{world, session}, services} = state
      {==}

def permissions_menu_observation(+editor: U.Editor, config: Context.Configuration, +origin: Context.Origin, +project: Maybe<&2, Nat>, +workspace: Context.WorkspaceValue,
  +sandbox: Context.SandboxValue, +approval: Context.ApprovalValue, +guidance: Context.GuidancePreview,
  controls: V.WorkspaceControls, projects: +List<V.ProjectChoice>, reviewers: +List<D.Profile>, +parent: Identity.Key, state: InteractionTypes.State) ->
  Rule.permissions_menu_source_law(editor, config, origin, project, workspace, sandbox, approval, guidance, controls, projects, reviewers, parent, state):
  match editor:
    case U.MessageEditor{+task}:
      InteractionTypes.State{E.Application{+world, +session}, +services} = state
      committed_permission_observation(View.committed_context(Tasks.find(Commands.entries(world), task)), parent, InteractionTypes.State{E.Application{world, session}, services},
        InterfaceView.permission_decisions(U.MessageEditor{task}, Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}, reviewers, parent, InteractionTypes.State{E.Application{world, session}, services}))
    case U.NewTaskEditor{}:
      InteractionTypes.State{E.Application{world, session}, services} = state
      {==}
    case U.ProjectEditor{id}:
      InteractionTypes.State{E.Application{world, session}, services} = state
      {==}
    case U.CardEditor{id}:
      InteractionTypes.State{E.Application{world, session}, services} = state
      {==}
    case U.AgentEditor{id}:
      InteractionTypes.State{E.Application{world, session}, services} = state
      {==}
    case U.ForkEditor{id}:
      InteractionTypes.State{E.Application{world, session}, services} = state
      {==}
    case U.CompactEditor{id}:
      InteractionTypes.State{E.Application{world, session}, services} = state
      {==}

def admitted_task_identity(+task: D.Task) ->
  {Rule.effective_task(Context.effective(task)) == D.task_id(task) : Nat}:
  D.Task{id, lineage, D.Contract{model, tools, max_fork, max_descendants, plugins, context}, current, status, history, queued, phase, operations, notified} = task
  {==}

def network_group_selection(+mode: D.SandboxMode, +network: Bool, +editor: U.Editor, +parent: Identity.Key, +state: InteractionTypes.State) ->
  {InterfaceView.network_choices(D.Sandbox{mode, network}, editor, parent, state) == InterfaceView.decision_surface(UX.decision(Experience.Subject{editor, Forms.NetworkAccess{}}, InterfaceView.field_value(state, editor, Forms.NetworkAccess{}), "Network access", [InterfaceView.network_alternative(False{}), InterfaceView.network_alternative(True{})]), parent, state) : SurfaceTypes.Node}:
  match network state:
    case False{} InteractionTypes.State{application, services}: {==}
    case True{} InteractionTypes.State{application, services}: {==}

def filesystem_write_caption(current: D.SandboxMode, network: Bool, editor: U.Editor, parent: Identity.Key, state: InteractionTypes.State) ->
  {Rule.alternative_caption(InterfaceView.sandbox_alternative(D.WorkspaceWrite{})) == Some{Rule.ChoiceCaption{"Workspace write", "Allow edits in the working directories."}} : Maybe<&2, Rule.ChoiceCaption>}:
  InteractionTypes.State{application, services} = state
  {==}

def filesystem_read_caption(current: D.SandboxMode, network: Bool, editor: U.Editor, parent: Identity.Key, state: InteractionTypes.State) ->
  {Rule.alternative_caption(InterfaceView.sandbox_alternative(D.ReadOnly{})) == Some{Rule.ChoiceCaption{"Read only", "Read files without modifying them."}} : Maybe<&2, Rule.ChoiceCaption>}:
  InteractionTypes.State{application, services} = state
  {==}

def network_disabled_caption(mode: D.SandboxMode, current: Bool, editor: U.Editor, parent: Identity.Key, state: InteractionTypes.State) ->
  {Rule.alternative_caption(InterfaceView.network_alternative(False{})) == Some{Rule.ChoiceCaption{"Disabled", "Keep network access off."}} : Maybe<&2, Rule.ChoiceCaption>}:
  InteractionTypes.State{application, services} = state
  {==}

def network_enabled_caption(mode: D.SandboxMode, current: Bool, editor: U.Editor, parent: Identity.Key, state: InteractionTypes.State) ->
  {Rule.alternative_caption(InterfaceView.network_alternative(True{})) == Some{Rule.ChoiceCaption{"Enabled", "Allow network access."}} : Maybe<&2, Rule.ChoiceCaption>}:
  InteractionTypes.State{application, services} = state
  {==}

def ask_caption(current: Context.ApprovalChoice, editor: U.Editor, parent: Identity.Key, state: InteractionTypes.State) ->
  {Rule.alternative_caption(InterfaceView.approval_alternative(Context.Ask{}, None{})) == Some{Rule.ChoiceCaption{"Ask", "Ask before running actions that require approval."}} : Maybe<&2, Rule.ChoiceCaption>}:
  InteractionTypes.State{application, services} = state
  {==}

def unrestricted_caption(current: Context.ApprovalChoice, editor: U.Editor, parent: Identity.Key, state: InteractionTypes.State) ->
  {Rule.alternative_caption(InterfaceView.approval_alternative(Context.Unrestricted{}, None{})) == Some{Rule.ChoiceCaption{"Unrestricted", "Run actions without approval prompts."}} : Maybe<&2, Rule.ChoiceCaption>}:
  InteractionTypes.State{application, services} = state
  {==}

def automatic_caption(+key: String, provider: String, +name: String, reasoning: Reasoning.Policy, options: Maybe<&2, D.ReasoningOptions>, current: Context.ApprovalChoice, editor: U.Editor, parent: Identity.Key, state: InteractionTypes.State) ->
  {Rule.alternative_caption(InterfaceView.approval_alternative(Context.AutomaticReview{key}, Some{D.Profile{key, provider, name, reasoning, options}})) == Some{Rule.ChoiceCaption{"Automatic review: " ++ name, "Use this model to review approval requests."}} : Maybe<&2, Rule.ChoiceCaption>}:
  InteractionTypes.State{application, services} = state
  {==}

def automatic_codec(profile: D.Profile) ->
  {Context.approval_option(Context.observed_approval(Context.InheritedApproval{D.ApprovalForMe{profile}})) == "automatic" : String}:
  D.Profile{key, provider, name, reasoning, options} = profile
  {==}

def Rule.context_evidence():
  Rule.ContextRequirements{
    +project => +world => session => services => parent => {==},
    task => context => guidance => access => world => {==},
    id => +name => workspace => guidance => {==},
    id => {==}, +id => +world => {==}, world => {==},
    primary => parent => {==}, parent => {==},
    mode => network => editor => parent => state => network_group_selection(mode, network, editor, parent, state),
    current => network => editor => parent => state => filesystem_write_caption(current, network, editor, parent, state),
    current => network => editor => parent => state => filesystem_read_caption(current, network, editor, parent, state),
    mode => current => editor => parent => state => network_disabled_caption(mode, current, editor, parent, state),
    mode => current => editor => parent => state => network_enabled_caption(mode, current, editor, parent, state),
    current => editor => parent => state => ask_caption(current, editor, parent, state),
    current => editor => parent => state => unrestricted_caption(current, editor, parent, state),
    key => provider => name => reasoning => options => current => editor => parent => state => automatic_caption(key, provider, name, reasoning, options, current, editor, parent, state),
    key => {==},
    task => admitted_task_identity(task), path => primary => gesture => {==}, value => gesture => {==},
    selected => description => input => {==}, selected => description => input => reason => {==},
    +editor => +observation => +profiles => {==},
    +task => +observation => +world => {==},
    editor => config => origin => project => workspace => sandbox => approval => guidance => controls => projects => reviewers => parent => state => workspace_menu_observation(editor, config, origin, project, workspace, sandbox, approval, guidance, controls, projects, reviewers, parent, state),
    editor => config => origin => project => workspace => sandbox => approval => guidance => controls => projects => reviewers => parent => state => permissions_menu_observation(editor, config, origin, project, workspace, sandbox, approval, guidance, controls, projects, reviewers, parent, state),
    reason => config => controls => projects => reviewers => editor => parent => state => unavailable_workspace(reason, config, controls, projects, reviewers, editor, parent, state),
    +reason => config => controls => projects => reviewers => editor => +parent => state => {==},
    +workspace => +editor => {==},
    origin => workspace => sandbox => approval => {==},
    origin => workspace => sandbox => approval => {==},
    message => profile => reasoning => config => scene => world => draft_composer_context(message, profile, reasoning, config, scene, world),
    task => message => delivery => scene => world => message_composer_context(task, message, delivery, scene, world),
    +task => {==},
    value => parent => state => retained_summary(value, parent, state),
    +path => +collection => parent => state => {==},
    +collection => +path => +parent => +state => {==},
    mode => current => network => editor => parent => state => mode_input(mode, current, network, editor, parent, state),
    mode => current => target => editor => parent => state => network_input(mode, current, target, editor, parent, state),
    mode => current => target => editor => parent => state => network_selection(mode, current, target, editor, parent, state),
    choice => current => reviewer => editor => parent => state => approval_input(choice, current, reviewer, editor, parent, state),
    +policy => {==},
    current => next => reviewer => editor => parent => state => automatic_selection(current, next, reviewer, editor, parent, state),
    {==}, {==}, profile => automatic_codec(profile),
    +origin => +workspace => old => +approval => +next => {==},
    +origin => old => +sandbox => +approval => {==},
    +origin => +workspace => old => +approval => {==},
    +origin => +workspace => +sandbox => old => {==},
    editor => {==},
    origin => workspace => approval => {==},
    origin => workspace => sandbox => {==},
    config => no_duplicate_network_reset(config),
    context => parent => state => committed_context_passive(context, parent, state),
    editor => session => world => {==}, editor => session => world => {==}, task => session => world => {==},
    editor => beside => {==}, editor => beside => {==}, task => beside => {==}}

def sandboxed_network(network: Bool) -> {Context.network_summary(D.Sandboxed{}, network) == View.execution_network_summary(network) : String}:
  match network:
    case True{}: {==}
    case False{}: {==}

def Rule.permissions_evidence():
  Rule.PermissionsRequirements{
    mode => {==},
    network => {==},
    mode => {==},
    sandboxed_network,
    task => workspace => mode => network => approval => project => guidance => access => profiles => {==},
    +task => +workspace => +mode => +network => +approval => +project => +guidance => +access => {==},
    origin => project => workspace => sandbox => approval => guidance => profiles => {==},
    +origin => +project => +workspace => +sandbox => +approval => +guidance => {==}}

def preview_policy_access_bridge(workspace: D.Workspace, sandbox: D.Sandbox, +approval: D.ApprovalPolicy, project: Maybe<&2, Nat>) ->
  {Context.approval_access(Context.approval_choice(approval)) == Workspace.default_access(D.TaskContext{workspace, sandbox, approval, project}) : D.ExecutionAccess}:
  match approval:
    case D.AskForApproval{}: {==}
    case D.FullAccess{}: {==}
    case D.ApprovalForMe{D.Profile{key, provider, name, reasoning, options}}: {==}

def unrestricted_execution_parts_agreement(sandbox: D.Sandbox) ->
  {UX.unrestricted_execution_parts(sandbox) == ["Full access", "Network available", "No approval"] : +List<String>}:
  match sandbox:
    case D.Sandbox{mode, network}: {==}

def draft_permission_observation_agreement(+preview: Context.Preview) ->
  {UX.permission_summary_parts(Context.DraftExecution{preview}) == UX.preview_permission_parts(preview) : +List<String>}:
  match preview:
    case Context.ContextUnavailable{reason}: {==}
    case Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}: {==}

def Rule.preview_access_evidence():
  Rule.PreviewAccessRequirements{
    workspace => sandbox => approval => project => preview_policy_access_bridge(workspace, sandbox, approval, project),
    reason => {==},
    origin => project => workspace => sandbox => approval => guidance => {==},
    origin => project => workspace => sandbox => guidance => unrestricted_execution_parts_agreement(Context.unwrap_sandbox(sandbox)),
    origin => project => workspace => sandbox => guidance => unrestricted_execution_parts_agreement(Context.unwrap_sandbox(sandbox)),
    preview => draft_permission_observation_agreement(preview)}
