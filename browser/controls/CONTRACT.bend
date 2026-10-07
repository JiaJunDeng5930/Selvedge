import Base
import ../../interaction/IDENTITY.bend as UIIdentity
import ../layout/SPACE.bend as Space
import ../appearance/TYPOGRAPHY.bend as T
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ../../interaction/STATE.bend as Core
import ../../interaction/INPUT.bend as User
import ../../interaction/session/MODEL.bend as Experience
import ../../interaction/presentation/MODEL.bend as View
import ../../interaction/services/MODEL.bend as Services
import ../../interaction/submission/FIELDS.bend as Forms
import ../../interaction/conversation/CODE.bend as Code
import ../../harness/DOMAIN.bend as Domain
import ./PROGRAM.bend as Controls
import ../appearance/DESIGN.bend as Design
import ../appearance/MODEL.bend as Appearance

type BoundNode is Data:
  BoundNode{key: UIIdentity.Key, binding: InterfaceView.Meaning, children: +List<BoundNode>}

type Bindings is Data:
  Bindings{base: +List<BoundNode>, overlays: +List<BoundNode>}

def source_binding(+meaning: InterfaceView.Meaning) -> InterfaceView.Meaning:
  match meaning:
    case InterfaceView.PageRegion{region, position}: InterfaceView.Region{}
    case InterfaceView.Region{}: InterfaceView.Region{}
    case InterfaceView.LayerRegion{dismiss, outside, escape}: InterfaceView.Region{}
    case InterfaceView.PanelToggle{expanded, input, availability}: InterfaceView.Activate{input, availability}
    case InterfaceView.ProjectGroup{project, selected, expanded}: InterfaceView.Region{}
    case InterfaceView.TaskRow{task, status, selected}: InterfaceView.Region{}
    case InterfaceView.ProjectChooser{selected}: InterfaceView.Region{}
    case InterfaceView.DirectoryRow{path, primary}: InterfaceView.Region{}
    case InterfaceView.ContextSummary{observation}: InterfaceView.Region{}
    case InterfaceView.ChoiceGroup{}: InterfaceView.Region{}
    case InterfaceView.ComposerAction{subject, input, availability}: InterfaceView.Activate{input, availability}
    case InterfaceView.Choice{kind, icon, selected, description, input, availability}: InterfaceView.Activate{input, availability}
    case InterfaceView.BoardLane{stage, count}: InterfaceView.Region{}
    case InterfaceView.CardArchive{count}: InterfaceView.Region{}
    case InterfaceView.CardContent{face}: InterfaceView.Region{}
    case InterfaceView.BoardGroup{grouping}: InterfaceView.Region{}
    case InterfaceView.ReadOnly{text}: InterfaceView.Region{}
    case InterfaceView.Fact{value}: InterfaceView.Region{}
    case InterfaceView.RichText{source, value}: InterfaceView.Region{}
    case InterfaceView.TaskFacts{details}: InterfaceView.Region{}
    case InterfaceView.CodeFacts{view}: InterfaceView.Region{}
    case InterfaceView.ActivityContent{expanded, audit}: InterfaceView.Region{}
    case InterfaceView.PageContext{conversation}: InterfaceView.Region{}
    case InterfaceView.Edit{editor, field, Forms.DirectoryCollection{}, value, choices}: InterfaceView.Region{}
    case InterfaceView.Edit{editor, field, Forms.FileCollection{}, value, choices}: InterfaceView.Region{}
    case _: meaning

def binding(representation: Controls.Representation) -> InterfaceView.Meaning:
  match representation:
    case Controls.NoControl{}: InterfaceView.Region{}
    case Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback}:
      InterfaceView.Activate{input, availability}
    case Controls.Input{meaning, name, widget, label, availability}: meaning
    case Controls.Movable{destinations, face, name, handle, geometry, help}: InterfaceView.MovableCard{destinations, face}

def source_nodes(values: +List<InterfaceView.Node>) -> +List<BoundNode>:
  match values:
    case Nil{}: Nil{}
    case Con{InterfaceView.Node{key, semantic, label, role, meaning, children}, rest}:
      Con{BoundNode{key, source_binding(meaning), source_nodes(children)}, source_nodes(rest)}

def presented_nodes(values: +List<Design.Node>) -> +List<BoundNode>:
  match values:
    case Nil{}: Nil{}
    case Con{Design.Node{key, semantic, label, role, meaning, style, control, children}, rest}:
      Con{BoundNode{key, binding(control), presented_nodes(children)}, presented_nodes(rest)}

def visual_bindings(visuals: Design.Surface) -> Bindings:
  Design.Surface{content, theme, base, overlays, active_scope} = visuals
  Bindings{presented_nodes(base), presented_nodes(overlays)}

def surface_bindings(surface: InterfaceView.Surface) -> Bindings:
  InterfaceView.Surface{content, base, overlays, active_scope} = surface
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

def message_uses_arrow_law(-key: UIIdentity.Key, -task: Nat, -availability: View.Availability, -label: String, -role: InterfaceView.Role, -selection: Controls.Selection, -code: Maybe<&2, Code.Scene>, -appearance: Services.Appearance, -access: Services.Access, -open: Bool, -layers: +List<View.Layer>) -> Type:
  {Controls.represent(key, InterfaceView.Activate{Core.ApplicationInput{Experience.UserInput{User.Activate{User.Submit{User.MessageEditor{task}}}}}, availability},
      label, role, Controls.Context{Controls.ComposerArea{}, selection, code, appearance, access, open, layers, None{}, Controls.Unscoped{}}) ==
      expected_message(User.MessageEditor{task}, availability, label) : Controls.Representation}

def creation_uses_arrow_law(-key: UIIdentity.Key, -availability: View.Availability, -label: String, -role: InterfaceView.Role, -selection: Controls.Selection, -code: Maybe<&2, Code.Scene>, -appearance: Services.Appearance, -access: Services.Access, -open: Bool, -layers: +List<View.Layer>) -> Type:
  {Controls.represent(key, InterfaceView.Activate{Core.ApplicationInput{Experience.UserInput{User.Activate{User.Submit{User.NewTaskEditor{}}}}}, availability},
      label, role, Controls.Context{Controls.ComposerArea{}, selection, code, appearance, access, open, layers, None{}, Controls.Unscoped{}}) ==
      expected_message(User.NewTaskEditor{}, availability, label) : Controls.Representation}

def menu_text(face: Controls.Face) -> Maybe<&2, String>:
  match face:
    case Controls.IconFace{icon}: None{}
    case Controls.TextFace{text}: Some{text}
    case Controls.UnbrokenFace{text}: Some{text}
    case Controls.SingleLineFace{text}: Some{text}
    case Controls.IconTextFace{icon, text}: Some{text}
    case Controls.UnbrokenIconTextFace{icon, text}: Some{text}
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

def declared_action_face(node: InterfaceView.Node, context: Controls.Context) -> Maybe<&2, Controls.Face>:
  InterfaceView.Node{key, semantic, label, role, meaning, children} = node
  action_face(Controls.represent(key, meaning, label, role, context))

def root_removal_faces(roots: +List<View.WorkspaceRoot>, +parent: UIIdentity.Key, +state: Core.State,
  +context: Controls.Context) -> +List<Maybe<&2, Controls.Face>>:
  match roots:
    case Nil{}: Nil{}
    case Con{View.WorkspaceRoot{path, primary, choose, remove}, rest}:
      declared_action_face(InterfaceView.declared(parent, remove, state), context) <> root_removal_faces(rest, parent, state, context)

def workspace_removal_faces(workspace: View.WorkspaceControls, parent: UIIdentity.Key, state: Core.State,
  context: Controls.Context) -> +List<Maybe<&2, Controls.Face>>:
  View.WorkspaceControls{editor, roots, inherit} = workspace
  root_removal_faces(roots, parent, state, context)

def approval_keeps_label_law(-key: UIIdentity.Key, -task: Nat, -operation: Nat, -allow: Bool, -reason: String, -availability: View.Availability, -label: String, -role: InterfaceView.Role, -selection: Controls.Selection, -code: Maybe<&2, Code.Scene>, -appearance: Services.Appearance, -access: Services.Access, -open: Bool, -layers: +List<View.Layer>) -> Type:
  {action_text(Controls.represent(key, InterfaceView.Activate{Core.ApplicationInput{Experience.UserInput{
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
    present_retains_bindings: @+scale:T.Scale -> @surface:InterfaceView.Surface -> @system_dark:Bool ->
      {visual_bindings(Appearance.present(surface, system_dark, scale)) == surface_bindings(surface) : Bindings},
    message_uses_arrow: @+key:UIIdentity.Key -> @task:Nat -> @+availability:View.Availability -> @+label:String -> @role:InterfaceView.Role ->
      @selection:Controls.Selection -> @code:Maybe<&2, Code.Scene> -> @appearance:Services.Appearance ->
      @access:Services.Access -> @open:Bool -> @layers:+List<View.Layer> ->
      message_uses_arrow_law(key, task, availability, label, role, selection, code, appearance, access, open, layers),
    creation_uses_arrow: @+key:UIIdentity.Key -> @+availability:View.Availability -> @+label:String -> @role:InterfaceView.Role ->
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
      @+current:String -> @+label:String -> @role:InterfaceView.Role -> @code:Maybe<&2, Code.Scene> ->
      @appearance:Services.Appearance -> @access:Services.Access -> @open:Bool -> @layers:+List<View.Layer> ->
      {choice(Controls.represent(key, InterfaceView.Activate{Core.ApplicationInput{Experience.UserInput{
          User.EditDraft{editor, User.ChooseModel{profile, reasoning}}}}, View.Available{}}, label, role,
          Controls.Context{Controls.MenuArea{}, Controls.ModelSelection{current}, code, appearance, access, open, layers, None{}, Controls.Unscoped{}})) ==
          Some{Choice{Controls.ChoiceFace{label, None{}, None{}, String.eq(profile, current)}, Controls.Radio{String.eq(profile, current)}}} : Maybe<&2, Choice>},
    delivery_option_marks_current: @+key:UIIdentity.Key -> @task:Nat -> @+delivery:User.Delivery -> @+current:User.Delivery ->
      @+label:String -> @role:InterfaceView.Role -> @code:Maybe<&2, Code.Scene> -> @appearance:Services.Appearance ->
      @access:Services.Access -> @open:Bool -> @layers:+List<View.Layer> ->
      {choice(Controls.represent(key, InterfaceView.Activate{Core.ApplicationInput{Experience.UserInput{
          User.EditDraft{User.MessageEditor{task}, User.ChooseDelivery{delivery}}}}, View.Available{}}, label, role,
          Controls.Context{Controls.MenuArea{}, Controls.DeliverySelection{current}, code, appearance, access, open, layers, None{}, Controls.Unscoped{}})) ==
          Some{Choice{Controls.ChoiceFace{label, None{}, None{}, Controls.same_delivery(delivery, current)},
            Controls.Radio{Controls.same_delivery(delivery, current)}}} : Maybe<&2, Choice>},
    approval_keeps_label: @key:UIIdentity.Key -> @task:Nat -> @operation:Nat -> @allow:Bool -> @reason:String ->
      @availability:View.Availability -> @+label:String -> @role:InterfaceView.Role -> @selection:Controls.Selection ->
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
    directory_parent_has_no_control: @choices:+List<Forms.ChoiceValue> -> @key:UIIdentity.Key -> @editor:User.Editor -> @field:Forms.Field -> @value:Forms.Observed -> @label:String -> @role:InterfaceView.Role -> @context:Controls.Context ->
      {Controls.represent(key, InterfaceView.Edit{editor, field, Forms.DirectoryCollection{}, value, choices}, label, role, context) == Controls.NoControl{} : Controls.Representation},
    file_parent_has_no_control: @choices:+List<Forms.ChoiceValue> -> @key:UIIdentity.Key -> @editor:User.Editor -> @field:Forms.Field -> @value:Forms.Observed -> @label:String -> @role:InterfaceView.Role -> @context:Controls.Context ->
      {Controls.represent(key, InterfaceView.Edit{editor, field, Forms.FileCollection{}, value, choices}, label, role, context) == Controls.NoControl{} : Controls.Representation}
  }

law evidence:
  Requirements

law card_content_source_family:
  for +key: UIIdentity.Key
  for +semantic: String
  for +label: String
  for +role: InterfaceView.Role
  for +face: View.CardFace
  for +children: +List<InterfaceView.Node>
  for inherited: Controls.SourceFamily
  {Controls.source_family_at(InterfaceView.Node{key, semantic, label, role, InterfaceView.CardContent{face}, children}, inherited) == Controls.SourceFamily{InterfaceView.Node{key, semantic, label, role, InterfaceView.CardContent{face}, children}} : Controls.SourceFamily}

law card_content_has_no_input:
  for key: UIIdentity.Key
  for face: View.CardFace
  for label: String
  for role: InterfaceView.Role
  for context: Controls.Context
  {Controls.represent(key, InterfaceView.CardContent{face}, label, role, context) == Controls.NoControl{} : Controls.Representation}
