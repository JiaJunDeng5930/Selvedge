import Base
import ../IDENTITY.bend as Identity
import ./context-laws.bend as Rule
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
import ../STATE.bend as Core
import ../submission/FIELDS.bend as Forms
import ./permissions-laws.bend as RulePermissionsLaws

def draft_composer_context(+message: U.Text, profile: String, reasoning: String, +config: Context.Configuration, scene: V.EditorScene, +world: M.World()) ->
  {Rule.composer_context(V.composer_scene(U.NewTask{message, profile, reasoning, config}, scene, world)) ==
    Some{Context.DraftExecution{Context.preview(config, world)}} : Maybe<&2, Context.Observation>}:
  V.EditorScene{identity, revision, groups, sections, submit, feedback, pending} = scene
  {==}

def message_composer_context(+task: Nat, message: U.Text, delivery: U.Delivery, scene: V.EditorScene, +world: M.World()) ->
  {Rule.composer_context(V.composer_scene(U.Message{task, message, delivery}, scene, world)) ==
    V.committed_observation(V.committed_context(Tasks.find(Commands.entries(world), task))) : Maybe<&2, Context.Observation>}:
  V.EditorScene{identity, revision, groups, sections, submit, feedback, pending} = scene
  {==}

def retained_summary(+value: Context.Observation, parent: Identity.Key, state: Core.State) ->
  {Rule.node_context(InterfaceView.context_summary_node(value, parent, state)) == Some{value} : Maybe<&2, Context.Observation>}:
  Core.State{E.Application{world, session}, services} = state
  {==}

def mode_input(+mode: D.SandboxMode, current: D.SandboxMode, +network: Bool, +editor: U.Editor, parent: Identity.Key, state: Core.State) ->
  {Rule.choice_input(InterfaceView.sandbox_choice(mode, current, network, editor, parent, state)) ==
    Some{Core.ApplicationInput{E.UserInput{U.EditDraft{editor, U.ConfigureContext{Context.SetSandbox{D.Sandbox{mode, network}}}}}}} : Maybe<&2, Core.Input>}:
  Core.State{application, services} = state
  {==}

def network_input(+mode: D.SandboxMode, current: Bool, +target: Bool, +editor: U.Editor, parent: Identity.Key, state: Core.State) ->
  {Rule.choice_input(InterfaceView.network_choice(mode, current, target, editor, parent, state)) ==
    Some{Core.ApplicationInput{E.UserInput{U.EditDraft{editor, U.ConfigureContext{Context.SetSandbox{D.Sandbox{mode, target}}}}}}} : Maybe<&2, Core.Input>}:
  Core.State{application, services} = state
  {==}

def network_selection(mode: D.SandboxMode, +current: Bool, +target: Bool, editor: U.Editor, parent: Identity.Key, state: Core.State) ->
  {Rule.choice_selection(InterfaceView.network_choice(mode, current, target, editor, parent, state)) == Some{Cmp.is_eq(Bool.cmp(current, target))} : Maybe<&2, Bool>}:
  match current target state:
    case False{} False{} Core.State{application, services}: {==}
    case False{} True{} Core.State{application, services}: {==}
    case True{} False{} Core.State{application, services}: {==}
    case True{} True{} Core.State{application, services}: {==}

def approval_input(+choice: Context.ApprovalChoice, current: Context.ApprovalChoice, reviewer: Maybe<&2, D.Profile>, +editor: U.Editor, parent: Identity.Key, state: Core.State) ->
  {Rule.choice_input(InterfaceView.approval_choice_node(choice, current, reviewer, editor, parent, state)) ==
    Some{Core.ApplicationInput{E.UserInput{U.EditDraft{editor, U.ConfigureContext{Context.SetApproval{choice}}}}}} : Maybe<&2, Core.Input>}:
  Core.State{application, services} = state
  {==}

def automatic_selection(+current: String, +next: String, reviewer: Maybe<&2, D.Profile>, editor: U.Editor, parent: Identity.Key, state: Core.State) ->
  {Rule.choice_selection(InterfaceView.approval_choice_node(Context.AutomaticReview{next}, Context.AutomaticReview{current}, reviewer, editor, parent, state)) ==
    Some{String.eq(current, next)} : Maybe<&2, Bool>}:
  Core.State{application, services} = state
  {==}

def no_duplicate_network_reset(config: Context.Configuration) ->
  {InterfaceView.reset_change(config, Forms.NetworkAccess{}) == None{} : Maybe<&2, Context.Change>}:
  Context.Configuration{origin, workspace, sandbox, approval} = config
  {==}

def unavailable_workspace(+reason: String, config: Context.Configuration, controls: V.WorkspaceControls, projects: +List<V.ProjectChoice>, reviewers: +List<D.Profile>, editor: U.Editor, +parent: Identity.Key, state: Core.State) ->
  {InterfaceView.workspace_menu_group(editor, V.ExecutionInput{config, Context.ContextUnavailable{reason}, controls, projects, reviewers}, parent, state) ==
    [InterfaceView.Node{Identity.Part{parent, "unavailable"}, "context/unavailable", reason, InterfaceView.Content{}, InterfaceView.ReadOnly{reason}, Nil{}}] : +List<InterfaceView.Node>}:
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
  {Rule.tree_focusable(List.append(&2, InterfaceView.Node, InterfaceView.committed_working_directory_extra(covered, primary, parent), InterfaceView.committed_directory_nodes(roots, primary, parent))) == False{} : Bool}:
  match covered:
    case True{}: committed_directories_passive(roots, primary, parent)
    case False{}: committed_directories_passive(roots, primary, parent)

def committed_context_passive(+context: Maybe<&2, Context.EffectiveContext>, +parent: Identity.Key, +state: Core.State) ->
  {Rule.tree_focusable(InterfaceView.committed_context_nodes(context, parent, state)) == False{} : Bool}:
  match context:
    case None{}: {==}
    case Some{Context.EffectiveContext{task, D.TaskContext{D.Workspace{+roots, +primary}, sandbox, approval, project}, guidance, access}}:
      Core.State{E.Application{world, session}, services} = state
      committed_extra_directories_passive(Context.member_primary(primary, roots), roots, primary, parent)

def workspace_menu_observation(+editor: U.Editor, config: Context.Configuration, +origin: Context.Origin, +project: Maybe<&2, Nat>, +workspace: Context.WorkspaceValue,
  +sandbox: Context.SandboxValue, +approval: Context.ApprovalValue, +guidance: Context.GuidancePreview,
  controls: V.WorkspaceControls, projects: +List<V.ProjectChoice>, reviewers: +List<D.Profile>, parent: Identity.Key, state: Core.State) ->
  Rule.workspace_menu_source_law(editor, config, origin, project, workspace, sandbox, approval, guidance, controls, projects, reviewers, parent, state):
  V.WorkspaceControls{identity, roots, inherit} = controls
  Core.State{E.Application{world, session}, services} = state
  {==}

def permissions_menu_observation(+editor: U.Editor, config: Context.Configuration, +origin: Context.Origin, +project: Maybe<&2, Nat>, +workspace: Context.WorkspaceValue,
  +sandbox: Context.SandboxValue, +approval: Context.ApprovalValue, +guidance: Context.GuidancePreview,
  controls: V.WorkspaceControls, projects: +List<V.ProjectChoice>, reviewers: +List<D.Profile>, parent: Identity.Key, state: Core.State) ->
  Rule.permissions_menu_source_law(editor, config, origin, project, workspace, sandbox, approval, guidance, controls, projects, reviewers, parent, state):
  Core.State{E.Application{world, session}, services} = state
  {==}

def admitted_task_identity(+task: D.Task) ->
  {Rule.effective_task(Context.effective(task)) == D.task_id(task) : Nat}:
  D.Task{id, lineage, D.Contract{model, tools, max_fork, max_descendants, plugins, context}, status, history, queued, phase, operations, notified} = task
  {==}

def network_group_selection(mode: D.SandboxMode, +network: Bool, editor: U.Editor, parent: Identity.Key, state: Core.State) ->
  {Rule.network_pair(InterfaceView.network_choices(D.Sandbox{mode, network}, editor, parent, state)) == (Some{Bool.not(network)}, Some{network}) : Sigma<&2, &2, Maybe<&2, Bool>, (_ => Maybe<&2, Bool>)>}:
  match network state:
    case False{} Core.State{application, services}: {==}
    case True{} Core.State{application, services}: {==}

def filesystem_write_caption(current: D.SandboxMode, network: Bool, editor: U.Editor, parent: Identity.Key, state: Core.State) ->
  {Rule.choice_caption(InterfaceView.sandbox_choice(D.WorkspaceWrite{}, current, network, editor, parent, state)) == Some{Rule.ChoiceCaption{"Workspace write", "Allow edits in the working directories."}} : Maybe<&2, Rule.ChoiceCaption>}:
  Core.State{application, services} = state
  {==}

def filesystem_read_caption(current: D.SandboxMode, network: Bool, editor: U.Editor, parent: Identity.Key, state: Core.State) ->
  {Rule.choice_caption(InterfaceView.sandbox_choice(D.ReadOnly{}, current, network, editor, parent, state)) == Some{Rule.ChoiceCaption{"Read only", "Read files without modifying them."}} : Maybe<&2, Rule.ChoiceCaption>}:
  Core.State{application, services} = state
  {==}

def network_disabled_caption(mode: D.SandboxMode, current: Bool, editor: U.Editor, parent: Identity.Key, state: Core.State) ->
  {Rule.choice_caption(InterfaceView.network_choice(mode, current, False{}, editor, parent, state)) == Some{Rule.ChoiceCaption{"Disabled", "Keep network access off."}} : Maybe<&2, Rule.ChoiceCaption>}:
  Core.State{application, services} = state
  {==}

def network_enabled_caption(mode: D.SandboxMode, current: Bool, editor: U.Editor, parent: Identity.Key, state: Core.State) ->
  {Rule.choice_caption(InterfaceView.network_choice(mode, current, True{}, editor, parent, state)) == Some{Rule.ChoiceCaption{"Enabled", "Allow network access."}} : Maybe<&2, Rule.ChoiceCaption>}:
  Core.State{application, services} = state
  {==}

def ask_caption(current: Context.ApprovalChoice, editor: U.Editor, parent: Identity.Key, state: Core.State) ->
  {Rule.choice_caption(InterfaceView.approval_choice_node(Context.Ask{}, current, None{}, editor, parent, state)) == Some{Rule.ChoiceCaption{"Ask", "Ask before running actions that require approval."}} : Maybe<&2, Rule.ChoiceCaption>}:
  Core.State{application, services} = state
  {==}

def unrestricted_caption(current: Context.ApprovalChoice, editor: U.Editor, parent: Identity.Key, state: Core.State) ->
  {Rule.choice_caption(InterfaceView.approval_choice_node(Context.Unrestricted{}, current, None{}, editor, parent, state)) == Some{Rule.ChoiceCaption{"Unrestricted", "Run actions without approval prompts."}} : Maybe<&2, Rule.ChoiceCaption>}:
  Core.State{application, services} = state
  {==}

def automatic_caption(+key: String, provider: String, +name: String, reasoning: Reasoning.Policy, options: Maybe<&2, D.ReasoningOptions>, current: Context.ApprovalChoice, editor: U.Editor, parent: Identity.Key, state: Core.State) ->
  {Rule.choice_caption(InterfaceView.approval_choice_node(Context.AutomaticReview{key}, current, Some{D.Profile{key, provider, name, reasoning, options}}, editor, parent, state)) == Some{Rule.ChoiceCaption{"Automatic review: " ++ name, "Use this model to review approval requests."}} : Maybe<&2, Rule.ChoiceCaption>}:
  Core.State{application, services} = state
  {==}

def automatic_codec(profile: D.Profile) ->
  {Context.approval_option(Context.observed_approval(Context.InheritedApproval{D.ApprovalForMe{profile}})) == "automatic" : String}:
  D.Profile{key, provider, name, reasoning, options} = profile
  {==}

def Rule.evidence():
  Rule.Requirements{
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
    key => provider => name => reasoning => current => editor => parent => state => automatic_caption(key, provider, name, reasoning, current, editor, parent, state),
    key => {==},
    task => admitted_task_identity(task), path => primary => gesture => {==}, value => gesture => {==},
    selected => description => input => {==}, selected => description => input => reason => {==},
    +editor => +observation => +profiles => {==},
    +task => +observation => +profiles => {==},
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
    +path => +primary => choose => remove => parent => state => {==},
    +path => +rest => +primary => +editor => {==},
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

def sandboxed_network(network: Bool) -> {Context.network_summary(D.Sandboxed{}, network) == V.execution_network_summary(network) : String}:
  match network:
    case True{}: {==}
    case False{}: {==}

def RulePermissionsLaws.evidence():
  RulePermissionsLaws.Requirements{
    mode => {==},
    network => {==},
    mode => {==},
    sandboxed_network,
    task => workspace => mode => network => approval => project => guidance => access => profiles => {==},
    task => workspace => mode => network => approval => project => guidance => access => profiles => {==},
    origin => project => workspace => sandbox => approval => guidance => profiles => {==},
    origin => project => workspace => sandbox => approval => guidance => profiles => {==}}
