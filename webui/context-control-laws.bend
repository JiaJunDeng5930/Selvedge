import Base
import ../core/interface.bend as UI
import ../core/SYSTEM.bend as Core
import ../core/ui-world.bend as View
import ../core/user-input.bend as User
import ../core/user-context.bend as Context
import ../bendlib/domain.bend as Domain
import ./controls.bend as Controls
import ./control-laws.bend as Binding
import ./rendered.bend as Observed
import ./renderer.bend as Render
import ./document.bend as Doc
import ./design.bend as Design

def choice_binding(+key: String, +selected: Bool, description: String, +input: Core.Input,
  +availability: View.Availability, +label: String, role: UI.Role, context: Controls.Context) ->
  {Binding.binding(Controls.represent(key, UI.Choice{selected, description, input, availability}, label, role, context)) ==
    UI.Activate{input, availability} : UI.Meaning}:
  Binding.choice_retains_binding(key, selected, input, availability, label, role, context)

def choice_radio(+selected: Bool) ->
  {Render.behavior(Controls.ChoiceRadio{selected}) ==
    [Doc.Property{"role", "radio"}, Doc.Property{"aria-checked", Render.boolean(selected)}] : +List<Doc.Property>}:
  {==}

def choice_interactive(+selected: Bool, description: String, +input: Core.Input, +availability: View.Availability) ->
  {Observed.interactive(UI.Choice{selected, description, input, availability}) == True{} : Bool}:
  {==}

def choice_enabled(+selected: Bool, description: String, +input: Core.Input, +availability: View.Availability) ->
  {Observed.required_enabled(UI.Choice{selected, description, input, availability}) == Observed.enabled(availability) : Bool}:
  {==}

def choice_observed_tabs(+key: String, semantic: String, +label: String, role: UI.Role,
  +selected: Bool, description: String, +input: Core.Input, +availability: View.Availability,
  +elements: +List<Observed.Element>) ->
  {Observed.expected_tabs([UI.Node{key, semantic, label, role, UI.Choice{selected, description, input, availability}, Nil{}}], elements) ==
    Observed.tab_entry(Observed.enabled(availability) && Observed.tab_stop(Observed.find_element(elements, key)), key, Nil{}) : +List<String>}:
  {==}

def workspace_label(+label: String, expanded: Bool) ->
  {Controls.face_for(Controls.WorkspacePicker{expanded}, label, Controls.ComposerArea{}) ==
    Controls.PickerFace{Some{Controls.Folder{}}, label} : Controls.Face}:
  {==}

def permissions_label(+label: String, current: Controls.Face, +execution: Maybe<&2, Context.Observation>) ->
  {Controls.composer_face(View.PermissionsSubject{}, label, current, execution) ==
    Controls.permission_face(execution) : Controls.Face}:
  {==}

def execution_observation(context: Controls.Context) -> Maybe<&2, Context.Observation>:
  Controls.Context{area, selection, code, appearance, access, settings_open, layers, execution, source_family} = context
  execution

def page_observation(content: Core.Scene) -> Maybe<&2, Context.Observation>:
  Core.Scene{View.Scene{navigation, main, layers, arrangement, attention}, settings, transfers, preview, code, directory_picker} = content
  Controls.page_execution(main)

def initial_execution(+content: Core.Scene) ->
  {execution_observation(Controls.initial(content)) == page_observation(content) : Maybe<&2, Context.Observation>}:
  Core.Scene{View.Scene{navigation, main, layers, arrangement, attention}, settings, transfers, preview, code, directory_picker} = content
  Core.Settings{open, access, entered, appearance, open_action, close_action, connect} = settings
  {==}

def draft_permission_face(+origin: Context.Origin, +project: Maybe<&2, Nat>, +workspace: Context.WorkspaceValue,
  +sandbox: Context.SandboxValue, +approval: Context.ApprovalValue, +guidance: Context.GuidancePreview) ->
  {Controls.permission_face(Some{Context.DraftExecution{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}}}) ==
    Controls.permission_values_face(View.execution_sandbox(sandbox), Context.observed_approval(approval)) : Controls.Face}:
  {==}

def committed_permission_face(+task: Nat, +workspace: Domain.Workspace, +sandbox: Domain.Sandbox,
  +approval: Domain.ApprovalPolicy, +project: Maybe<&2, Nat>, +guidance: Domain.ProjectContext, +access: Domain.ExecutionAccess) ->
  {Controls.permission_face(Some{Context.CommittedExecution{Context.EffectiveContext{task, Domain.TaskContext{workspace, sandbox, approval, project}, guidance, access}}}) ==
    Controls.permission_values_face(sandbox, Context.approval_choice(approval)) : Controls.Face}:
  {==}

def unavailable_permission_face(+reason: String) ->
  {Controls.permission_face(Some{Context.DraftExecution{Context.ContextUnavailable{reason}}}) == Controls.IconFace{Controls.Warning{}} : Controls.Face}:
  {==}

def permission_accessible_name(+label: String) ->
  {Controls.composer_name(View.PermissionsSubject{}, label) == "Permissions: " ++ label : String}:
  {==}

def permission_help(+filesystem: Controls.Icon, +network: Controls.Icon, +approval: Controls.Icon, +name: String) ->
  {Controls.help_for(Controls.PermissionFace{filesystem, network, approval}, View.Available{}, Controls.Quiet{}, name) ==
    Controls.tooltip(name) : Controls.Help}:
  {==}

def delivery_send_face(+label: String, current: Controls.Face, execution: Maybe<&2, Context.Observation>) ->
  {Controls.composer_face(View.DeliverySubject{User.Send{}}, label, current, execution) == Controls.IconFace{Controls.ArrowUp{}} : Controls.Face}:
  {==}

def delivery_steer_face(+label: String, current: Controls.Face, execution: Maybe<&2, Context.Observation>) ->
  {Controls.composer_face(View.DeliverySubject{User.Steer{}}, label, current, execution) == Controls.IconFace{Controls.Branch{}} : Controls.Face}:
  {==}





def choice_native_event_law(-key: String, -label: String, -selected: Bool, -description: String, -visual: Design.Style, -input: Core.Input, -availability: View.Availability, -name: String, -face: Controls.Face, -behavior: Controls.Behavior, -geometry: Controls.Geometry, -placement: Controls.Placement, -help: Controls.Help, -feedback: Controls.Feedback, -visual_children: +List<Design.Appearance>) -> Type:
  {Doc.element_events(Render.choice_node(key, label, selected, description, visual,
      Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback}, visual_children)) ==
      [Doc.Activate{key}] : +List<Doc.Event>}

def choice_native_event(+key: String, label: String, selected: Bool, description: String, +visual: Design.Style,
  input: Core.Input, availability: View.Availability, name: String, face: Controls.Face,
  behavior: Controls.Behavior, geometry: Controls.Geometry, placement: Controls.Placement,
  help: Controls.Help, feedback: Controls.Feedback, visual_children: +List<Design.Appearance>) -> choice_native_event_law(key, label, selected, description, visual, input, availability, name, face, behavior, geometry, placement, help, feedback, visual_children):
  Controls.Geometry{width, height, icon, radius, leading} = geometry
  {==}

def filesystem_write_icon() -> {Controls.filesystem_icon(Domain.WorkspaceWrite{}) == Controls.Pencil{} : Controls.Icon}:
  {==}

def filesystem_read_icon() -> {Controls.filesystem_icon(Domain.ReadOnly{}) == Controls.Eye{} : Controls.Icon}:
  {==}

def network_enabled_icon() -> {Controls.network_icon(True{}) == Controls.Globe{} : Controls.Icon}:
  {==}

def network_disabled_icon() -> {Controls.network_icon(False{}) == Controls.GlobeOff{} : Controls.Icon}:
  {==}

def ask_approval_icon() -> {Controls.approval_icon(Context.Ask{}) == Controls.Hand{} : Controls.Icon}:
  {==}

def unrestricted_approval_icon() -> {Controls.approval_icon(Context.Unrestricted{}) == Controls.Shield{} : Controls.Icon}:
  {==}

def automatic_approval_icon(+profile: String) -> {Controls.approval_icon(Context.AutomaticReview{profile}) == Controls.ShieldCode{} : Controls.Icon}:
  {==}

type Requirements is Type:
  Requirements{
    choice_native_event: @+key:String -> @label:String -> @selected:Bool -> @description:String -> @+visual:Design.Style ->
      @input:Core.Input -> @availability:View.Availability -> @name:String -> @face:Controls.Face -> @behavior:Controls.Behavior -> @geometry:Controls.Geometry -> @placement:Controls.Placement -> @help:Controls.Help -> @feedback:Controls.Feedback -> @visual_children:+List<Design.Appearance> ->
      choice_native_event_law(key, label, selected, description, visual, input, availability, name, face, behavior, geometry, placement, help, feedback, visual_children),
    choice_binding: @+key:String -> @+selected:Bool -> @description:String -> @+input:Core.Input -> @+availability:View.Availability -> @+label:String -> @role:UI.Role -> @context:Controls.Context ->
      {Binding.binding(Controls.represent(key, UI.Choice{selected, description, input, availability}, label, role, context)) == UI.Activate{input, availability} : UI.Meaning},
    choice_radio: @+selected:Bool -> {Render.behavior(Controls.ChoiceRadio{selected}) == [Doc.Property{"role", "radio"}, Doc.Property{"aria-checked", Render.boolean(selected)}] : +List<Doc.Property>},
    choice_interactive: @+selected:Bool -> @description:String -> @+input:Core.Input -> @+availability:View.Availability -> {Observed.interactive(UI.Choice{selected, description, input, availability}) == True{} : Bool},
    choice_enabled: @+selected:Bool -> @description:String -> @+input:Core.Input -> @+availability:View.Availability -> {Observed.required_enabled(UI.Choice{selected, description, input, availability}) == Observed.enabled(availability) : Bool},
    choice_observed_tabs: @+key:String -> @semantic:String -> @+label:String -> @role:UI.Role -> @+selected:Bool -> @description:String -> @+input:Core.Input -> @+availability:View.Availability -> @+elements:+List<Observed.Element> ->
      {Observed.expected_tabs([UI.Node{key, semantic, label, role, UI.Choice{selected, description, input, availability}, Nil{}}], elements) == Observed.tab_entry(Observed.enabled(availability) && Observed.tab_stop(Observed.find_element(elements, key)), key, Nil{}) : +List<String>},
    workspace_label: @+label:String -> @expanded:Bool -> {Controls.face_for(Controls.WorkspacePicker{expanded}, label, Controls.ComposerArea{}) == Controls.PickerFace{Some{Controls.Folder{}}, label} : Controls.Face},
    permissions_label: @+label:String -> @current:Controls.Face -> @+execution:Maybe<&2,Context.Observation> -> {Controls.composer_face(View.PermissionsSubject{}, label, current, execution) == Controls.permission_face(execution) : Controls.Face},
    initial_execution: @+content:Core.Scene -> {execution_observation(Controls.initial(content)) == page_observation(content) : Maybe<&2,Context.Observation>},
    draft_permission_face: @+origin:Context.Origin -> @+project:Maybe<&2,Nat> -> @+workspace:Context.WorkspaceValue -> @+sandbox:Context.SandboxValue -> @+approval:Context.ApprovalValue -> @+guidance:Context.GuidancePreview -> {Controls.permission_face(Some{Context.DraftExecution{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}}}) == Controls.permission_values_face(View.execution_sandbox(sandbox), Context.observed_approval(approval)) : Controls.Face},
    committed_permission_face: @+task:Nat -> @+workspace:Domain.Workspace -> @+sandbox:Domain.Sandbox -> @+approval:Domain.ApprovalPolicy -> @+project:Maybe<&2,Nat> -> @+guidance:Domain.ProjectContext -> @+access:Domain.ExecutionAccess -> {Controls.permission_face(Some{Context.CommittedExecution{Context.EffectiveContext{task, Domain.TaskContext{workspace, sandbox, approval, project}, guidance, access}}}) == Controls.permission_values_face(sandbox, Context.approval_choice(approval)) : Controls.Face},
    unavailable_permission_face: @+reason:String -> {Controls.permission_face(Some{Context.DraftExecution{Context.ContextUnavailable{reason}}}) == Controls.IconFace{Controls.Warning{}} : Controls.Face},
    permission_accessible_name: @+label:String -> {Controls.composer_name(View.PermissionsSubject{}, label) == "Permissions: " ++ label : String},
    permission_help: @+filesystem:Controls.Icon -> @+network:Controls.Icon -> @+approval:Controls.Icon -> @+name:String -> {Controls.help_for(Controls.PermissionFace{filesystem, network, approval}, View.Available{}, Controls.Quiet{}, name) == Controls.tooltip(name) : Controls.Help},
    delivery_send_face: @+label:String -> @current:Controls.Face -> @execution:Maybe<&2,Context.Observation> -> {Controls.composer_face(View.DeliverySubject{User.Send{}}, label, current, execution) == Controls.IconFace{Controls.ArrowUp{}} : Controls.Face},
    delivery_steer_face: @+label:String -> @current:Controls.Face -> @execution:Maybe<&2,Context.Observation> -> {Controls.composer_face(View.DeliverySubject{User.Steer{}}, label, current, execution) == Controls.IconFace{Controls.Branch{}} : Controls.Face},
    filesystem_write_icon: {Controls.filesystem_icon(Domain.WorkspaceWrite{}) == Controls.Pencil{} : Controls.Icon},
    filesystem_read_icon: {Controls.filesystem_icon(Domain.ReadOnly{}) == Controls.Eye{} : Controls.Icon},
    network_enabled_icon: {Controls.network_icon(True{}) == Controls.Globe{} : Controls.Icon},
    network_disabled_icon: {Controls.network_icon(False{}) == Controls.GlobeOff{} : Controls.Icon},
    ask_approval_icon: {Controls.approval_icon(Context.Ask{}) == Controls.Hand{} : Controls.Icon},
    unrestricted_approval_icon: {Controls.approval_icon(Context.Unrestricted{}) == Controls.Shield{} : Controls.Icon},
    automatic_approval_icon: @+profile:String -> {Controls.approval_icon(Context.AutomaticReview{profile}) == Controls.ShieldCode{} : Controls.Icon}}

def evidence() -> Requirements:
  Requirements{choice_native_event, choice_binding, choice_radio, choice_interactive, choice_enabled, choice_observed_tabs, workspace_label, permissions_label, initial_execution, draft_permission_face, committed_permission_face, unavailable_permission_face, permission_accessible_name, permission_help, delivery_send_face, delivery_steer_face, filesystem_write_icon, filesystem_read_icon, network_enabled_icon, network_disabled_icon, ask_approval_icon, unrestricted_approval_icon, automatic_approval_icon}
