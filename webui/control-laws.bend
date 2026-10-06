import Base
import ../core/ui-identity.bend as UIIdentity
import ./space.bend as Space
import ./typography.bend as T
import ../core/interface.bend as UI
import ../core/SYSTEM.bend as Core
import ../core/user-input.bend as User
import ../core/user-experience.bend as Experience
import ../core/ui-world.bend as View
import ../core/client-services.bend as Services
import ../core/form-fields.bend as Forms
import ../core/code-block.bend as Code
import ../bendlib/domain.bend as Domain
import ./controls.bend as Controls
import ./design.bend as Design
import ./appearance.bend as Appearance

type BoundNode is Data:
  BoundNode{key: UIIdentity.Key, binding: UI.Meaning, children: +List<BoundNode>}

type Bindings is Data:
  Bindings{base: +List<BoundNode>, overlays: +List<BoundNode>}

def source_binding(+meaning: UI.Meaning) -> UI.Meaning:
  match meaning:
    case UI.PageRegion{region, position}: UI.Region{}
    case UI.Region{}: UI.Region{}
    case UI.LayerRegion{dismiss, outside, escape}: UI.Region{}
    case UI.PanelToggle{expanded, input, availability}: UI.Activate{input, availability}
    case UI.ProjectGroup{project, selected, expanded}: UI.Region{}
    case UI.TaskRow{task, status, selected}: UI.Region{}
    case UI.ProjectChooser{selected}: UI.Region{}
    case UI.DirectoryRow{path, primary}: UI.Region{}
    case UI.ContextSummary{observation}: UI.Region{}
    case UI.ChoiceGroup{}: UI.Region{}
    case UI.ComposerAction{subject, input, availability}: UI.Activate{input, availability}
    case UI.Choice{kind, icon, selected, description, input, availability}: UI.Activate{input, availability}
    case UI.BoardLane{stage, count}: UI.Region{}
    case UI.CardArchive{count}: UI.Region{}
    case UI.BoardGroup{grouping}: UI.Region{}
    case UI.ReadOnly{text}: UI.Region{}
    case UI.RichText{source, value}: UI.Region{}
    case UI.TaskFacts{details}: UI.Region{}
    case UI.CodeFacts{view}: UI.Region{}
    case UI.ActivityContent{expanded, audit}: UI.Region{}
    case UI.PageContext{conversation}: UI.Region{}
    case UI.Edit{editor, field, Forms.DirectoryCollection{}, value, choices}: UI.Region{}
    case UI.Edit{editor, field, Forms.FileCollection{}, value, choices}: UI.Region{}
    case _: meaning

def binding(representation: Controls.Representation) -> UI.Meaning:
  match representation:
    case Controls.NoControl{}: UI.Region{}
    case Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback}:
      UI.Activate{input, availability}
    case Controls.Input{meaning, name, widget, label, availability}: meaning
    case Controls.Movable{destinations, face, name, handle, geometry, help}: UI.MovableCard{destinations, face}

def source_nodes(values: +List<UI.Node>) -> +List<BoundNode>:
  match values:
    case Nil{}: Nil{}
    case Con{UI.Node{key, semantic, label, role, meaning, children}, rest}:
      Con{BoundNode{key, source_binding(meaning), source_nodes(children)}, source_nodes(rest)}

def presented_nodes(values: +List<Design.Node>) -> +List<BoundNode>:
  match values:
    case Nil{}: Nil{}
    case Con{Design.Node{key, semantic, label, role, meaning, style, control, children}, rest}:
      Con{BoundNode{key, binding(control), presented_nodes(children)}, presented_nodes(rest)}

def visual_bindings(visuals: Design.Surface) -> Bindings:
  Design.Surface{content, theme, base, overlays, active_scope} = visuals
  Bindings{presented_nodes(base), presented_nodes(overlays)}

def surface_bindings(surface: UI.Surface) -> Bindings:
  UI.Surface{content, base, overlays, active_scope} = surface
  Bindings{source_nodes(base), source_nodes(overlays)}

def expected_icon_help(availability: View.Availability, label: String) -> Controls.Help:
  match availability:
    case View.Available{}: Controls.Tooltip{label, 300n, True{}, True{}, False{}}
    case View.NeedsDirectoryObservation{}: Controls.Tooltip{label, 300n, True{}, True{}, False{}}
    case View.Unavailable{reason}: Controls.Tooltip{reason, 300n, True{}, True{}, False{}}

# Message editors share the arrow form across Send/Steer. The action identity,
# name, availability, and disabled explanation remain those of that observation.
def expected_message(+editor: User.Editor, +availability: View.Availability, +label: String) -> Controls.Representation:
  Controls.Action{Core.ApplicationInput{Experience.UserInput{User.Activate{User.Submit{editor}}}},
    availability, label, Controls.IconFace{Controls.ArrowUp{}}, Controls.Push{},
    Controls.Geometry{Space.fixed_demand(32n, 32n), 16n, 16n, 0n}, Controls.ComposerEnd{},
    expected_icon_help(availability, label), Controls.Quiet{}}

def message_uses_arrow_law(-key: UIIdentity.Key, -task: Nat, -availability: View.Availability, -label: String, -role: UI.Role, -selection: Controls.Selection, -code: Maybe<&2, Code.Scene>, -appearance: Services.Appearance, -access: Services.Access, -open: Bool, -layers: +List<View.Layer>) -> Type:
  {Controls.represent(key, UI.Activate{Core.ApplicationInput{Experience.UserInput{User.Activate{User.Submit{User.MessageEditor{task}}}}}, availability},
      label, role, Controls.Context{Controls.ComposerArea{}, selection, code, appearance, access, open, layers, None{}, Controls.Unscoped{}}) ==
      expected_message(User.MessageEditor{task}, availability, label) : Controls.Representation}

def creation_uses_arrow_law(-key: UIIdentity.Key, -availability: View.Availability, -label: String, -role: UI.Role, -selection: Controls.Selection, -code: Maybe<&2, Code.Scene>, -appearance: Services.Appearance, -access: Services.Access, -open: Bool, -layers: +List<View.Layer>) -> Type:
  {Controls.represent(key, UI.Activate{Core.ApplicationInput{Experience.UserInput{User.Activate{User.Submit{User.NewTaskEditor{}}}}}, availability},
      label, role, Controls.Context{Controls.ComposerArea{}, selection, code, appearance, access, open, layers, None{}, Controls.Unscoped{}}) ==
      expected_message(User.NewTaskEditor{}, availability, label) : Controls.Representation}

def menu_text(face: Controls.Face) -> Maybe<&2, String>:
  match face:
    case Controls.IconFace{icon}: None{}
    case Controls.TextFace{text}: Some{text}
    case Controls.SingleLineFace{text}: Some{text}
    case Controls.IconTextFace{icon, text}: Some{text}
    case Controls.PickerFace{icon, text}: Some{text}
    case Controls.ChoiceFace{text, description, icon, checked}: Some{text}
    case Controls.DisclosureFace{text, expanded}: Some{text}
    case Controls.PermissionFace{filesystem, network, approval}: None{}

def required_menu_text(purpose: Controls.Purpose, label: String) -> Maybe<&2, String>:
  match purpose:
    case Controls.Dismiss{}: None{}
    case _: Some{label}

type Choice is Data:
  Choice{face: Controls.Face, behavior: Controls.Behavior}

def choice(representation: Controls.Representation) -> Maybe<&2, Choice>:
  match representation:
    case Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback}:
      Some{Choice{face, behavior}}
    case _: None{}









def action_text(representation: Controls.Representation) -> Maybe<&2, String>:
  match representation:
    case Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback}: menu_text(face)
    case _: None{}

def action_face(representation: Controls.Representation) -> Maybe<&2, Controls.Face>:
  match representation:
    case Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback}: Some{face}
    case _: None{}

def declared_action_face(node: UI.Node, context: Controls.Context) -> Maybe<&2, Controls.Face>:
  UI.Node{key, semantic, label, role, meaning, children} = node
  action_face(Controls.represent(key, meaning, label, role, context))

def root_removal_faces(roots: +List<View.WorkspaceRoot>, +parent: UIIdentity.Key, +state: Core.State,
  +context: Controls.Context) -> +List<Maybe<&2, Controls.Face>>:
  match roots:
    case Nil{}: Nil{}
    case Con{View.WorkspaceRoot{path, primary, choose, remove}, rest}:
      declared_action_face(UI.declared(parent, remove, state), context) <> root_removal_faces(rest, parent, state, context)

def workspace_removal_faces(workspace: View.WorkspaceControls, parent: UIIdentity.Key, state: Core.State,
  context: Controls.Context) -> +List<Maybe<&2, Controls.Face>>:
  View.WorkspaceControls{editor, roots, inherit} = workspace
  root_removal_faces(roots, parent, state, context)

def approval_keeps_label_law(-key: UIIdentity.Key, -task: Nat, -operation: Nat, -allow: Bool, -reason: String, -availability: View.Availability, -label: String, -role: UI.Role, -selection: Controls.Selection, -code: Maybe<&2, Code.Scene>, -appearance: Services.Appearance, -access: Services.Access, -open: Bool, -layers: +List<View.Layer>) -> Type:
  {action_text(Controls.represent(key, UI.Activate{Core.ApplicationInput{Experience.UserInput{
      User.Activate{User.ReviewApproval{task, operation, allow, reason}}}}, availability}, label, role,
      Controls.Context{Controls.ApprovalArea{}, selection, code, appearance, access, open, layers, None{}, Controls.Unscoped{}})) ==
      Some{label} : Maybe<&2, String>}

type HelpAccess is Data:
  HelpAccess{pointer: Bool, keyboard: Bool, takes_focus: Bool}

def help_access(help: Controls.Help) -> HelpAccess:
  match help:
    case Controls.NoHelp{}: HelpAccess{False{}, False{}, False{}}
    case Controls.Tooltip{text, delay, pointer, keyboard, takes_focus}:
      HelpAccess{pointer, keyboard, takes_focus}













type Requirements is Type:
  Requirements{
    present_retains_bindings: @+scale:T.Scale -> @surface:UI.Surface -> @system_dark:Bool ->
      {visual_bindings(Appearance.present(surface, system_dark, scale)) == surface_bindings(surface) : Bindings},
    message_uses_arrow: @+key:UIIdentity.Key -> @task:Nat -> @+availability:View.Availability -> @+label:String -> @role:UI.Role ->
      @selection:Controls.Selection -> @code:Maybe<&2, Code.Scene> -> @appearance:Services.Appearance ->
      @access:Services.Access -> @open:Bool -> @layers:+List<View.Layer> ->
      message_uses_arrow_law(key, task, availability, label, role, selection, code, appearance, access, open, layers),
    creation_uses_arrow: @+key:UIIdentity.Key -> @+availability:View.Availability -> @+label:String -> @role:UI.Role ->
      @selection:Controls.Selection -> @code:Maybe<&2, Code.Scene> -> @appearance:Services.Appearance ->
      @access:Services.Access -> @open:Bool -> @layers:+List<View.Layer> ->
      creation_uses_arrow_law(key, availability, label, role, selection, code, appearance, access, open, layers),
    menu_preserves_labels: @+purpose:Controls.Purpose -> @+label:String ->
      {menu_text(Controls.face_for(purpose, label, Controls.MenuArea{})) == required_menu_text(purpose, label) : Maybe<&2, String>},
    copy_keeps_space: @state:Code.CopyState ->
      {Controls.geometry_for(Controls.CopyCode{state}, Controls.face_for(Controls.CopyCode{state}, "Copy code", Controls.CodeArea{}), Controls.CodeArea{}) ==
        Controls.Geometry{Space.fixed_demand(32n, 32n), 16n, 8n, 0n} : Controls.Geometry},
    radio_reserves_check: @label:String -> @checked:Bool ->
      {Controls.geometry_for(Controls.SelectedOption{checked}, Controls.ChoiceFace{label, None{}, None{}, checked}, Controls.MenuArea{}) ==
        Controls.Geometry{Space.fixed_demand(0n, 28n), 16n, 6n, 20n} : Controls.Geometry},
    model_option_marks_current: @+key:UIIdentity.Key -> @editor:User.Editor -> @+profile:String -> @reasoning:String ->
      @+current:String -> @+label:String -> @role:UI.Role -> @code:Maybe<&2, Code.Scene> ->
      @appearance:Services.Appearance -> @access:Services.Access -> @open:Bool -> @layers:+List<View.Layer> ->
      {choice(Controls.represent(key, UI.Activate{Core.ApplicationInput{Experience.UserInput{
          User.EditDraft{editor, User.ChooseModel{profile, reasoning}}}}, View.Available{}}, label, role,
          Controls.Context{Controls.MenuArea{}, Controls.ModelSelection{current}, code, appearance, access, open, layers, None{}, Controls.Unscoped{}})) ==
          Some{Choice{Controls.ChoiceFace{label, None{}, None{}, String.eq(profile, current)}, Controls.Radio{String.eq(profile, current)}}} : Maybe<&2, Choice>},
    delivery_option_marks_current: @+key:UIIdentity.Key -> @task:Nat -> @+delivery:User.Delivery -> @+current:User.Delivery ->
      @+label:String -> @role:UI.Role -> @code:Maybe<&2, Code.Scene> -> @appearance:Services.Appearance ->
      @access:Services.Access -> @open:Bool -> @layers:+List<View.Layer> ->
      {choice(Controls.represent(key, UI.Activate{Core.ApplicationInput{Experience.UserInput{
          User.EditDraft{User.MessageEditor{task}, User.ChooseDelivery{delivery}}}}, View.Available{}}, label, role,
          Controls.Context{Controls.MenuArea{}, Controls.DeliverySelection{current}, code, appearance, access, open, layers, None{}, Controls.Unscoped{}})) ==
          Some{Choice{Controls.ChoiceFace{label, None{}, None{}, Controls.same_delivery(delivery, current)},
            Controls.Radio{Controls.same_delivery(delivery, current)}}} : Maybe<&2, Choice>},
    approval_keeps_label: @key:UIIdentity.Key -> @task:Nat -> @operation:Nat -> @allow:Bool -> @reason:String ->
      @availability:View.Availability -> @+label:String -> @role:UI.Role -> @selection:Controls.Selection ->
      @code:Maybe<&2, Code.Scene> -> @appearance:Services.Appearance -> @access:Services.Access -> @open:Bool -> @layers:+List<View.Layer> ->
      approval_keeps_label_law(key, task, operation, allow, reason, availability, label, role, selection, code, appearance, access, open, layers),
    icon_help_supports_focus: @icon:Controls.Icon -> @availability:View.Availability -> @feedback:Controls.Feedback -> @label:String ->
      {help_access(Controls.help_for(Controls.IconFace{icon}, availability, feedback, label)) ==
        HelpAccess{True{}, True{}, False{}} : HelpAccess},
    input_label_is_accessible_only: @value:Forms.Observed ->
      {Controls.label_placement(Controls.widget_for(Forms.Multiline{}, Forms.MessageText{}, value)) ==
        Controls.AccessibleOnly{} : Controls.LabelPlacement},
    settings_uses_gear: @expanded:Bool -> @label:String ->
      {Controls.face_for(Controls.OpenPanel{Controls.Settings{}, False{}, expanded}, label, Controls.PageArea{}) == Controls.IconFace{Controls.Settings{}} : Controls.Face},
    introduction_uses_context_label: @expanded:Bool -> @+label:String ->
      {Controls.face_for(Controls.WorkspacePicker{expanded}, label, Controls.ComposerArea{}) == Controls.PickerFace{Some{Controls.Folder{}}, label} : Controls.Face},
    directory_removal_uses_cross: @+parent:UIIdentity.Key -> @+editor:User.Editor -> @+path:String ->
      @primary:Maybe<&2, String> -> @state:Core.State -> @context:Controls.Context ->
      {workspace_removal_faces(View.workspace_controls(Domain.Workspace{[path], primary}, editor, None{}),
        parent, state, context) == [Some{Controls.IconFace{Controls.CloseCross{}}}] : +List<Maybe<&2, Controls.Face>>},
    directory_parent_has_no_control: @choices:+List<Forms.ChoiceValue> -> @key:UIIdentity.Key -> @editor:User.Editor -> @field:Forms.Field -> @value:Forms.Observed -> @label:String -> @role:UI.Role -> @context:Controls.Context ->
      {Controls.represent(key, UI.Edit{editor, field, Forms.DirectoryCollection{}, value, choices}, label, role, context) == Controls.NoControl{} : Controls.Representation},
    file_parent_has_no_control: @choices:+List<Forms.ChoiceValue> -> @key:UIIdentity.Key -> @editor:User.Editor -> @field:Forms.Field -> @value:Forms.Observed -> @label:String -> @role:UI.Role -> @context:Controls.Context ->
      {Controls.represent(key, UI.Edit{editor, field, Forms.FileCollection{}, value, choices}, label, role, context) == Controls.NoControl{} : Controls.Representation}
  }

law evidence:
  Requirements
