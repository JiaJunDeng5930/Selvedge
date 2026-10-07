import Base
import ../core/ui-identity.bend as UIIdentity
import ./source.bend as Source
import ./authored-primitives.bend as Factory
import ./iconography.bend as Iconography
import ./controls.bend as Controls
import ./design.bend as Design
import ./physical-space.bend as Model
import ./spatial.bend as Spatial
import ./enclosure.bend as Enclosure
import ./typography.bend as T
import ./document.bend as Doc
import ./editor-layout.bend as EditorLayout
import ../core/interface.bend as InterfaceView
import ../core/ui-world.bend as View
import ../core/form-fields.bend as Forms
import ../core/field-options.bend as FieldOptions
import ../core/user-context.bend as Context
import ../bendlib/domain.bend as Domain
import ../BOARD.bend as Board

def filter_search(value: Board.Filter) -> String:
  match value:
    case Board.Filter{view, search, status, priority, date, assignee, creator, project, label}: search

def origin_text(value: Context.Origin) -> String:
  match value:
    case Context.EnvironmentDefaults{}: "environment"
    case Context.ProjectDefaults{project}: "project/" ++ Nat.show(project)
    case Context.ParentTask{task}: "parent/" ++ Nat.show(task)
    case Context.ProjectForParent{task, project}: "project-for-parent/" ++ Nat.show(task) ++ "/" ++ Nat.show(project)

def approval_text(value: Context.ApprovalValue) -> String:
  Context.approval_option(Context.observed_approval(value))

def workspace_primary(value: Context.WorkspaceValue) -> String:
  match value:
    case Context.InheritedWorkspace{Domain.Workspace{roots, primary}}: FieldOptions.optional_text(primary)
    case Context.EnteredWorkspace{Domain.Workspace{roots, primary}}: FieldOptions.optional_text(primary)

def network_text(value: Context.SandboxValue) -> String:
  match value:
    case Context.InheritedSandbox{Domain.Sandbox{mode, network}}: FieldOptions.boolean(network)
    case Context.ChosenSandbox{Domain.Sandbox{mode, network}}: FieldOptions.boolean(network)

def workspace_field_text(field: Forms.Field, roots: +List<String>, primary: Maybe<&2, String>) -> String:
  match field:
    case Forms.WorkspacePrimary{}: FieldOptions.optional_text(primary)
    case _: FieldOptions.joined(roots)

def context_field_text(field: Forms.Field, origin: Context.Origin, workspace: Context.WorkspaceValue, sandbox: Context.SandboxValue, approval: Context.ApprovalValue) -> String:
  match field:
    case Forms.ContextOrigin{}: origin_text(origin)
    case Forms.WorkspaceDirectories{}: FieldOptions.workspace_text(workspace)
    case Forms.WorkspacePrimary{}: workspace_primary(workspace)
    case Forms.SandboxMode{}: FieldOptions.sandbox_text(sandbox)
    case Forms.NetworkAccess{}: network_text(sandbox)
    case Forms.ApprovalPolicy{}: approval_text(approval)
    case _: ""

def field_text(field: Forms.Field, value: Forms.Observed) -> String:
  match value:
    case Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}}: context_field_text(field, origin, workspace, sandbox, approval)
    case Forms.WorkspaceValue{Domain.Workspace{roots, primary}}: workspace_field_text(field, roots, primary)
    case other: FieldOptions.observed(other)


type CreationParts is Data:
  CreationParts{hero: +List<Doc.Node>, footer: +List<Doc.Node>}

def node_value(value: InterfaceView.Meaning) -> String:
  match value:
    case InterfaceView.Edit{editor, field, entry, observed_value, choices}: field_text(field, observed_value)
    case InterfaceView.BoardSearch{filter}: filter_search(filter)
    case InterfaceView.SearchChoices{query}: query
    case InterfaceView.EnterDirectory{editor, text}: text
    case InterfaceView.DirectoryBrowserLocation{value}: value
    case InterfaceView.BoardProfile{automatic, selected, choices, enabled}: selected
    case _: ""

def parent_font(value: Design.Style) -> T.Presentation:
  Design.Style{text, chrome, alignment, flow, overflow, frame, minimum_height, maximum_width_percent, states} = value
  text

def parent_gap(value: Design.Style) -> Nat:
  Design.Style{text, chrome, alignment, flow, overflow, frame, minimum_height, maximum_width_percent, states} = value
  Enclosure.frame_gap(frame)

def glyph(key: UIIdentity.Key, icon: Controls.Icon, parent: Design.Style, +size: Nat) -> Source.Node:
  Source.Glyph{key, Iconography.drawing(icon, size), Factory.glyph_style(parent, size, size)}

def caption(key: UIIdentity.Key, text: String, parent: Design.Style, wrapping: T.Wrapping) -> Source.Node:
  Factory.text(key, text, Source.ExplicitFont{parent_font(parent)}, wrapping)

def leading_icon(value: Maybe<&2, Controls.Icon>, key: UIIdentity.Key, parent: Design.Style, size: Nat) -> +List<Source.Node>:
  match value:
    case None{}: Nil{}
    case Some{icon}: [glyph(UIIdentity.part(key, "leading"), icon, parent, size)]

def face_description(value: Maybe<&2, String>, key: UIIdentity.Key, parent: Design.Style) -> +List<Source.Node>:
  match value:
    case None{}: Nil{}
    case Some{text}: [Factory.text(UIIdentity.part(key, "description"), text, Source.ExplicitFont{T.supporting(parent_font(parent))}, Controls.description_wrapping())]

def selection(checked: Bool, key: UIIdentity.Key, parent: Design.Style, size: Nat) -> +List<Source.Node>:
  match checked:
    case True{}: [glyph(UIIdentity.part(key, "check"), Controls.Check{}, parent, size)]
    case False{}: Nil{}

def disclosure_icon(expanded: Bool) -> Controls.Icon:
  match expanded:
    case True{}: Controls.ChevronDown{}
    case False{}: Controls.ChevronRight{}

def face_icon_size(value: Controls.Geometry) -> Nat:
  Controls.Geometry{demand, size, radius, slot} = value
  size

def face_leading_slot(value: Controls.Geometry) -> Nat:
  Controls.Geometry{demand, size, radius, slot} = value
  slot

def face_members(+value: Controls.Face, +key: UIIdentity.Key, +parent: Design.Style, +geometry: Controls.Geometry) -> +List<Source.Node>:
  match value:
    case Controls.TextFace{text}: [caption(UIIdentity.part(key, "caption"), text, parent, Controls.caption_wrapping(value))]
    case Controls.UnbrokenFace{text}: [caption(UIIdentity.part(key, "caption"), text, parent, Controls.caption_wrapping(value))]
    case Controls.SingleLineFace{text}: [caption(UIIdentity.part(key, "caption"), text, parent, T.SingleLine{})]
    case Controls.IconFace{icon}: [glyph(UIIdentity.part(key, "icon"), icon, parent, face_icon_size(geometry))]
    case Controls.IconTextFace{icon, text}: [glyph(UIIdentity.part(key, "icon"), icon, parent, face_icon_size(geometry)), caption(UIIdentity.part(key, "caption"), text, parent, Controls.caption_wrapping(value))]
    case Controls.UnbrokenIconTextFace{icon, text}: [glyph(UIIdentity.part(key, "icon"), icon, parent, face_icon_size(geometry)), caption(UIIdentity.part(key, "caption"), text, parent, Controls.caption_wrapping(value))]
    case Controls.PickerFace{leading, text}:
      List.append(&2, Source.Node, leading_icon(leading, key, parent, face_icon_size(geometry)),
      [Source.Box{UIIdentity.part(key, "value"), Source.Span{}, Factory.content_style(parent, Model.Horizontal{}, Model.StretchSize{}, Model.NaturalSize{}, 0n), Nil{}, [caption(UIIdentity.part(key, "caption"), text, parent, Controls.caption_wrapping(value))]}, glyph(UIIdentity.part(key, "chevron"), Controls.ChevronDown{}, parent, face_icon_size(geometry))])
    case Controls.DisclosureFace{text, expanded}:
      [caption(UIIdentity.part(key, "caption"), text, parent, Controls.caption_wrapping(value)), glyph(UIIdentity.part(key, "chevron"), disclosure_icon(expanded), parent, face_icon_size(geometry))]
    case Controls.PermissionFace{filesystem, network, approval}:
      [glyph(UIIdentity.part(key, "filesystem"), filesystem, parent, face_icon_size(geometry)), glyph(UIIdentity.part(key, "network"), network, parent, face_icon_size(geometry)), glyph(UIIdentity.part(key, "approval"), approval, parent, face_icon_size(geometry))]
    case Controls.ChoiceFace{text, details, icon, checked}:
      List.append(&2, Source.Node, leading_icon(icon, key, parent, face_icon_size(geometry)),
      [Source.Box{UIIdentity.part(key, "text"), Source.Span{}, Factory.content_style(parent, Model.Vertical{}, Model.StretchSize{}, Model.NaturalSize{}, parent_gap(parent)), Nil{}, List.append(&2, Source.Node, [caption(UIIdentity.part(key, "caption"), text, parent, Controls.caption_wrapping(value))], face_description(details, key, parent))},
       Source.Box{UIIdentity.part(key, "selection"), Source.Span{}, Factory.with_alignments(Factory.with_minimum(Factory.content_style(parent, Model.Horizontal{}, Model.ExactSize{face_leading_slot(geometry)}, Model.ExactSize{face_leading_slot(geometry)}, 0n), Enclosure.Extent{face_leading_slot(geometry), face_leading_slot(geometry)}), Spatial.Centered{}, Spatial.Centered{}), Nil{}, selection(checked, key, parent, face_icon_size(geometry))}])

def face(key: UIIdentity.Key, value: Controls.Face, parent: Design.Style, geometry: Controls.Geometry) -> +List<Source.Node>:
  face_members(value, key, parent, geometry)

def enabled(value: View.Availability) -> Bool:
  InterfaceView.available(value)

def availability_attributes(value: View.Availability) -> +List<Source.Attribute>:
  match value:
    case View.Unavailable{reason}: [Source.DataAttribute{"unavailable-reason", reason}]
    case _: Nil{}

def behavior(value: Controls.Behavior) -> +List<Source.Attribute>:
  match value:
    case Controls.Push{}: Nil{}
    case Controls.Toggle{pressed}: [Source.AriaAttribute{"pressed", FieldOptions.boolean(pressed)}]
    case Controls.Radio{checked}: [Source.RoleAttribute{"menuitemradio"}, Source.AriaAttribute{"checked", FieldOptions.boolean(checked)}]
    case Controls.ChoiceRadio{checked}: [Source.RoleAttribute{"radio"}, Source.AriaAttribute{"checked", FieldOptions.boolean(checked)}]
    case Controls.MenuCheckbox{checked}: [Source.RoleAttribute{"menuitemcheckbox"}, Source.AriaAttribute{"checked", FieldOptions.boolean(checked)}]
    case Controls.ChoiceCheckbox{checked}: [Source.RoleAttribute{"checkbox"}, Source.AriaAttribute{"checked", FieldOptions.boolean(checked)}]
    case Controls.Disclosure{expanded}: [Source.AriaAttribute{"expanded", FieldOptions.boolean(expanded)}]
    case Controls.Popup{menu, expanded}: [Source.AriaAttribute{"haspopup", "true"}, Source.AriaAttribute{"expanded", FieldOptions.boolean(expanded)}]
    case Controls.Destination{current}: [Source.AriaAttribute{"current", FieldOptions.boolean(current)}]

def help(value: Controls.Help) -> +List<Source.Attribute>:
  match value:
    case Controls.NoHelp{}: Nil{}
    case Controls.Tooltip{text, delay, pointer, keyboard, focus}:
      [Source.TitleAttribute{text}, Source.DataAttribute{"help-delay", Nat.show(delay)}, Source.DataAttribute{"help-pointer", FieldOptions.boolean(pointer)}, Source.DataAttribute{"help-keyboard", FieldOptions.boolean(keyboard)}, Source.DataAttribute{"help-takes-focus", FieldOptions.boolean(focus)}]

def feedback(value: Controls.Feedback) -> +List<Source.Attribute>:
  match value:
    case Controls.Quiet{}: Nil{}
    case Controls.Working{message}: [Source.AriaAttribute{"busy", "true"}, Source.DataAttribute{"feedback", "working"}, Source.DataAttribute{"feedback-message", message}]
    case Controls.Succeeded{message}: [Source.DataAttribute{"feedback", "succeeded"}, Source.DataAttribute{"feedback-message", message}]
    case Controls.Failed{message}: [Source.AriaAttribute{"invalid", "true"}, Source.DataAttribute{"feedback", "failed"}, Source.DataAttribute{"feedback-message", message}]

def action_width(value: Controls.Face, visual: Design.Style) -> Model.AxisSize:
  match value:
    case Controls.ChoiceFace{text, description, icon, checked}: Model.StretchSize{}
    case _: Factory.natural_width(visual)

def action_alignment(value: Controls.Face) -> Spatial.Alignment:
  match value:
    case Controls.ChoiceFace{text, description, icon, checked}: Spatial.Leading{}
    case Controls.PickerFace{leading, text}: Spatial.Leading{}
    case _: Spatial.Centered{}

def invalid(+key: UIIdentity.Key, +visual: Design.Style, +diagnostic: String) -> Source.Node:
  Source.Box{key, Source.Output{}, Factory.content_style(visual, Model.Horizontal{}, Model.NaturalSize{}, Model.NaturalSize{}, 0n), [Source.DataAttribute{"invalid-source", diagnostic}], [caption(UIIdentity.part(key, "diagnostic"), diagnostic, visual, T.NormalAnywhere{})]}

def action(+key: UIIdentity.Key, +visual: Design.Style, representation: Controls.Representation) -> Source.Node:
  match representation:
    case Controls.Action{input, +availability, name, +value, state, +geometry, placement, assistance, response}:
      Source.Control{key, Source.Button{}, Factory.with_alignments(Factory.with_direction(Factory.with_minimum(Factory.style(visual, action_width(value, visual), Model.NaturalSize{}, Model.Confined{}), Enclosure.Extent{Controls.geometry_minimum_width(geometry), Controls.geometry_minimum_height(geometry)}), Model.Horizontal{}), action_alignment(value), Spatial.Centered{}), List.append(&2, Source.Attribute, Factory.binding_attributes(key), List.append(&2, Source.Attribute, availability_attributes(availability), List.append(&2, Source.Attribute, behavior(state), List.append(&2, Source.Attribute, help(assistance), feedback(response))))), name, enabled(availability), Doc.Activate{UIIdentity.encode(key)}, Nil{}, face(key, value, visual, geometry)}
    case _: invalid(key, visual, "invalid-action-representation")

def field_checked(value: InterfaceView.Meaning) -> Bool:
  match value:
    case InterfaceView.Edit{editor, field, entry, Forms.ToggleValue{enabled}, choices}: enabled
    case InterfaceView.Edit{editor, Forms.AssistedCapture{}, entry, Forms.AssistanceValue{enabled, profile}, choices}: enabled
    case InterfaceView.Edit{editor, Forms.NetworkAccess{}, entry, Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, Context.InheritedSandbox{Domain.Sandbox{mode, enabled}}, approval, guidance}}, choices}: enabled
    case InterfaceView.Edit{editor, Forms.NetworkAccess{}, entry, Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, Context.ChosenSandbox{Domain.Sandbox{mode, enabled}}, approval, guidance}}, choices}: enabled
    case _: False{}

def checked_attributes(checked: Bool) -> +List<Source.Attribute>:
  match checked:
    case True{}: [Source.CheckedAttribute{}]
    case False{}: Nil{}

def option_values(values: +List<Forms.ChoiceValue>, +selected: String) -> +List<Source.Choice>:
  match values:
    case Nil{}: Nil{}
    case Con{Forms.ChoiceValue{+value, label}, rest}: Source.Choice{value, label, String.eq(value, selected)} <> option_values(rest, selected)

def choices(value: InterfaceView.Meaning) -> +List<Source.Choice>:
  match value:
    case InterfaceView.BoardProfile{automatic, selected, profiles, enabled}: option_values(FieldOptions.profile_options(profiles), selected)
    case InterfaceView.Edit{editor, field, entry, observed, options}: option_values(options, field_text(field, observed))
    case _: Nil{}

def field_placeholder(kind: EditorLayout.FieldKind, name: String) -> String:
  match kind:
    case EditorLayout.WorkTitle{}: name
    case EditorLayout.WorkDescription{}: name
    case _: ""

def semantic_placeholder(value: InterfaceView.Meaning, name: String) -> String:
  match value:
    case InterfaceView.BoardSearch{filter}: "搜索任务"
    case InterfaceView.Edit{editor, Forms.CardLabels{}, entry, observed, choices}: "每行一个标签"
    case other: field_placeholder(EditorLayout.field_kind(other), name)

def placeholder(widget: Controls.Widget, meaning: InterfaceView.Meaning, name: String) -> String:
  match widget:
    case Controls.MessageInput{}: "Ask anything, or describe a task"
    case _: semantic_placeholder(meaning, name)

def field_metadata(key: UIIdentity.Key, value: InterfaceView.Meaning) -> +List<Source.Attribute>:
  match value:
    case InterfaceView.Edit{editor, Forms.MessageText{}, entry, observed, choices}: [Source.DataAttribute{"field", Forms.key(Forms.MessageText{})}, Source.EditorBindingAttribute{key}]
    case InterfaceView.Edit{editor, field, entry, observed, choices}: [Source.DataAttribute{"field", Forms.key(field)}]
    case _: Nil{}

def field_kind(value: Controls.Widget) -> Source.NativeFieldKind:
  match value:
    case Controls.TextInput{}: Source.TextField{}
    case Controls.MessageInput{}: Source.MessageField{}
    case Controls.TextArea{}: Source.TextAreaField{}
    case Controls.DirectoryList{}: Source.TextAreaField{}
    case Controls.SelectInput{}: Source.SelectField{}
    case Controls.MultiSelectInput{}: Source.MultiSelectField{}
    case Controls.ToggleInput{}: Source.ToggleField{}
    case Controls.NumberInput{minimum}: Source.NumberField{minimum}
    case Controls.FileChooser{face}: Source.FileField{False{}}
    case Controls.AttachmentList{}: Source.FileField{True{}}
    case Controls.DirectoryChooser{face}: Source.DirectoryField{}
    case Controls.SearchInput{}: Source.SearchField{}
    case Controls.SecretInput{}: Source.SecretField{}
    case Controls.PlainValue{}: Source.TextField{}

def field_first_event(value: Controls.Widget, key: UIIdentity.Key) -> Doc.DOMEvent:
  match value:
    case Controls.ToggleInput{}: Doc.EditToggle{UIIdentity.encode(key)}
    case Controls.FileChooser{face}: Doc.SelectFiles{UIIdentity.encode(key)}
    case Controls.AttachmentList{}: Doc.SelectFiles{UIIdentity.encode(key)}
    case _: Doc.EditText{UIIdentity.encode(key)}

def field_remaining_events(value: Controls.Widget, key: UIIdentity.Key) -> +List<Doc.DOMEvent>:
  match value:
    case Controls.DirectoryChooser{face}: [Doc.ConfirmText{UIIdentity.encode(key)}]
    case _: Nil{}

def maximum_lines(value: Controls.Widget, visual: Design.Style, parameters: Design.LayoutParameters) -> Nat:
  match value:
    case Controls.MessageInput{}: Nat.max(1n, Nat.div(Design.input_maximum_height(parameters), Nat.max(1n, T.resolved_line_height(T.resolved(parent_font(visual))))))
    case Controls.TextArea{}: Nat.max(1n, Nat.div(Design.input_maximum_height(parameters), Nat.max(1n, T.resolved_line_height(T.resolved(parent_font(visual))))))
    case Controls.DirectoryList{}: Nat.max(1n, Nat.div(Design.input_maximum_height(parameters), Nat.max(1n, T.resolved_line_height(T.resolved(parent_font(visual))))))
    case _: 1n

def label_attributes(value: Controls.LabelPlacement, key: UIIdentity.Key) -> +List<Source.Attribute>:
  match value:
    case Controls.AccessibleOnly{}: Nil{}
    case _: [Source.AriaAttribute{"labelledby", UIIdentity.encode(UIIdentity.part(key, "label"))}]

def label_direction(value: Controls.LabelPlacement) -> Model.Direction:
  match value:
    case Controls.BesideInput{}: Model.Horizontal{}
    case _: Model.Vertical{}

def label_tag(value: Controls.LabelPlacement) -> Source.BoxTag:
  match value:
    case Controls.BesideInput{}: Source.Label{}
    case _: Source.Div{}

def label_width(value: Controls.LabelPlacement) -> Model.AxisSize:
  match value:
    case Controls.BesideInput{}: Model.StretchSize{}
    case _: Model.NaturalSize{}

def input_width(value: Controls.Widget) -> Model.AxisSize:
  match value:
    case Controls.ToggleInput{}: Model.ExactSize{Source.toggle_target_size(Source.native_toggle_geometry())}
    case _: Model.StretchSize{}

def input_height(value: Controls.Widget) -> Model.AxisSize:
  match value:
    case Controls.ToggleInput{}: Model.ExactSize{Source.toggle_target_size(Source.native_toggle_geometry())}
    case _: Model.NaturalSize{}

def label_field(+value: Controls.LabelPlacement, +key: UIIdentity.Key, name: String, +visual: Design.Style, field: Source.Node) -> Source.Node:
  match value:
    case Controls.AccessibleOnly{}: field
    case +other:
      Source.Box{UIIdentity.part(key, "field-wrapper"), label_tag(other), Factory.content_style(visual, label_direction(other), Model.StretchSize{}, Model.NaturalSize{}, parent_gap(visual)), Nil{},
        [Source.Box{UIIdentity.part(key, "label"), Source.Span{}, Factory.content_style(visual, Model.Horizontal{}, label_width(other), Model.NaturalSize{}, 0n), Nil{}, [caption(UIIdentity.part(UIIdentity.part(key, "label"), "text"), name, visual, T.NormalAnywhere{})]}, field]}

def input_widget(+widget: Controls.Widget, +key: UIIdentity.Key, +meaning: InterfaceView.Meaning, +name: String, +placement: Controls.LabelPlacement, +availability: View.Availability, +visual: Design.Style, parameters: Design.LayoutParameters) -> Source.Node:
  match widget:
    case Controls.PlainValue{}:
      Source.Box{key, Source.Output{}, Factory.content_style(visual, Model.Horizontal{}, Model.StretchSize{}, Model.NaturalSize{}, 0n), Factory.binding_attributes(key), [caption(UIIdentity.part(key, "value"), node_value(meaning), visual, T.NormalAnywhere{})]}
    case +other:
      label_field(placement, key, name, visual, Source.Field{key, field_kind(other), Factory.style(visual, input_width(other), input_height(other), Model.Confined{}), List.append(&2, Source.Attribute, Factory.binding_attributes(key), List.append(&2, Source.Attribute, field_metadata(key, meaning), List.append(&2, Source.Attribute, checked_attributes(field_checked(meaning)), List.append(&2, Source.Attribute, label_attributes(placement, key), availability_attributes(availability))))), node_value(meaning), placeholder(other, meaning, name), choices(meaning), Source.field_policy(0n, 0n, Nat.sub(maximum_lines(other, visual, parameters), 1n)), name, enabled(availability), field_first_event(other, key), field_remaining_events(other, key)})

def input(key: UIIdentity.Key, meaning: InterfaceView.Meaning, representation: Controls.Representation, visual: Design.Style, parameters: Design.LayoutParameters) -> Source.Node:
  match representation:
    case Controls.Input{binding, name, widget, label, availability}: input_widget(widget, key, meaning, name, label, availability, visual, parameters)
    case _: invalid(key, visual, "invalid-input-representation")


def available_placement_choice(enabled: Bool, target: String, label: String, rest: +List<Source.Choice>) -> +List<Source.Choice>:
  match enabled:
    case True{}: Source.Choice{target, label, False{}} <> rest
    case False{}: rest

def placement_choices(values: +List<InterfaceView.Placement>) -> +List<Source.Choice>:
  match values:
    case Nil{}: Nil{}
    case Con{InterfaceView.Placement{target, label, input, availability}, rest}:
      available_placement_choice(InterfaceView.available(availability), target, label, placement_choices(rest))

def has_available_destination(values: +List<InterfaceView.Placement>) -> Bool:
  InterfaceView.has_available_destination(values)

def movable_choices(+key: UIIdentity.Key, +representation: Controls.Representation, +visual: Design.Style, +parameters: Design.LayoutParameters) -> Source.Node:
  match representation:
    case Controls.Movable{+destinations, face, +name, handle, geometry, help}:
      Source.Field{key, Source.SelectField{},
        Factory.style(visual, Model.StretchSize{}, Model.NaturalSize{}, Model.Confined{}),
        Factory.binding_attributes(key), "", "Move to…",
        Source.Choice{"", "Move to…", True{}} <> placement_choices(destinations),
        Source.FieldPolicy{1n, 1n, 1n}, name, has_available_destination(destinations), Doc.SelectDestination{UIIdentity.encode(key)}, Nil{}}
    case _: invalid(key, visual, "invalid-movable-representation")
