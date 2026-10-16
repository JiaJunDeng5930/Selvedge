import Base
import ../../bendlib/categories.bend as Categories
import ../../interaction/IDENTITY.bend as UIIdentity
import ../document/SOURCE.bend as Source
import ./authored-primitives.bend as Factory
import ../appearance/ICONS.bend as Iconography
import ./PROGRAM.bend as Controls
import ../appearance/DESIGN.bend as Design
import ../layout/physical-space.bend as Model
import ../layout/GEOMETRY.bend as Spatial
import ../layout/enclosure.bend as Enclosure
import ../appearance/TYPOGRAPHY.bend as T
import ../document/MODEL.bend as Doc
import ../editor/MODEL.bend as EditorLayout
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ../../interaction/presentation/MODEL.bend as View
import ../../interaction/submission/FIELDS.bend as Forms
import ../../interaction/submission/field-options.bend as FieldOptions
import ../../interaction/services/CONTEXT.bend as Context
import ../../harness/DOMAIN.bend as Domain
import ../../features/board/MODEL.bend as Board
import ../../interaction/presentation/SURFACE.bend as SurfaceTypes

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

def node_value(value: SurfaceTypes.Meaning) -> String:
  match value:
    case SurfaceTypes.Edit{editor, field, entry, observed_value, choices}: field_text(field, observed_value)
    case SurfaceTypes.BoardSearch{filter}: filter_search(filter)
    case SurfaceTypes.SearchChoices{query}: query
    case SurfaceTypes.EnterDirectory{editor, text}: text
    case SurfaceTypes.DirectoryBrowserLocation{value}: value
    case SurfaceTypes.BoardProfile{automatic, selected, choices, enabled}: selected
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

def field_checked(value: SurfaceTypes.Meaning) -> Bool:
  match value:
    case SurfaceTypes.Edit{editor, field, entry, Forms.ToggleValue{enabled}, choices}: enabled
    case SurfaceTypes.Edit{editor, Forms.AssistedCapture{}, entry, Forms.AssistanceValue{enabled, profile}, choices}: enabled
    case SurfaceTypes.Edit{editor, Forms.NetworkAccess{}, entry, Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, Context.InheritedSandbox{Domain.Sandbox{mode, enabled}}, approval, guidance}}, choices}: enabled
    case SurfaceTypes.Edit{editor, Forms.NetworkAccess{}, entry, Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, Context.ChosenSandbox{Domain.Sandbox{mode, enabled}}, approval, guidance}}, choices}: enabled
    case _: False{}

def checked_attributes(checked: Bool) -> +List<Source.Attribute>:
  match checked:
    case True{}: [Source.CheckedAttribute{}]
    case False{}: Nil{}

def option_values(values: +List<Forms.ChoiceValue>, +selected: String) -> +List<Source.Choice>:
  match values:
    case Nil{}: Nil{}
    case Con{Forms.ChoiceValue{+value, label}, rest}: Source.Choice{value, label, String.eq(value, selected)} <> option_values(rest, selected)

def choices(value: SurfaceTypes.Meaning) -> +List<Source.Choice>:
  match value:
    case SurfaceTypes.BoardProfile{automatic, selected, profiles, enabled}: option_values(FieldOptions.profile_options(profiles), selected)
    case SurfaceTypes.Edit{editor, field, entry, observed, options}: option_values(options, field_text(field, observed))
    case _: Nil{}

def field_placeholder(kind: EditorLayout.FieldKind, name: String) -> String:
  match kind:
    case EditorLayout.WorkTitle{}: name
    case EditorLayout.WorkDescription{}: name
    case _: ""

def semantic_placeholder(value: SurfaceTypes.Meaning, name: String) -> String:
  match value:
    case SurfaceTypes.BoardSearch{filter}: "搜索任务"
    case SurfaceTypes.Edit{editor, Forms.CardLabels{}, entry, observed, choices}: "每行一个标签"
    case other: field_placeholder(EditorLayout.field_kind(other), name)

def placeholder(widget: Controls.Widget, meaning: SurfaceTypes.Meaning, name: String) -> String:
  match widget:
    case Controls.MessageInput{}: "Ask anything, or describe a task"
    case _: semantic_placeholder(meaning, name)

def field_metadata(key: UIIdentity.Key, value: SurfaceTypes.Meaning) -> +List<Source.Attribute>:
  match value:
    case SurfaceTypes.Edit{editor, Forms.MessageText{}, entry, observed, choices}: [Source.DataAttribute{"field", Forms.key(Forms.MessageText{})}, Source.EditorBindingAttribute{key}]
    case SurfaceTypes.Edit{editor, field, entry, observed, choices}: [Source.DataAttribute{"field", Forms.key(field)}]
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

def field_input_event(meaning: SurfaceTypes.Meaning, value: Controls.Widget, key: UIIdentity.Key) -> Doc.DOMEvent:
  match meaning:
    case SurfaceTypes.Edit{editor, field, Forms.StructuredText{}, observed, choices}: Doc.EditStructuredText{UIIdentity.encode(key)}
    case _: field_first_event(value, key)

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

type FieldBinding is Data:
  FieldBinding{key: UIIdentity.Key, attributes: +List<Source.Attribute>}

type FieldContent is Data:
  FieldContent{kind: Source.NativeFieldKind, style: Source.Style, value: String,
    placeholder: String, options: +List<Source.Choice>, policy: Source.FieldPolicy, name: String}

type FieldProtocol is Data:
  FieldProtocol{enabled: Bool, first: Doc.DOMEvent, remaining: +List<Doc.DOMEvent>}

type InputFieldRequest is Data:
  InputFieldRequest{binding: FieldBinding, content: FieldContent, protocol: FieldProtocol}

def request_binding(request: InputFieldRequest) -> FieldBinding:
  InputFieldRequest{binding, content, protocol} = request
  binding

def request_content(request: InputFieldRequest) -> FieldContent:
  InputFieldRequest{binding, content, protocol} = request
  content

def request_protocol(request: InputFieldRequest) -> FieldProtocol:
  InputFieldRequest{binding, content, protocol} = request
  protocol

def expected_input_attributes(+key: UIIdentity.Key, input: Controls.FormInput) -> +List<Source.Attribute>:
  Controls.FormInput{+meaning, name, widget, label, availability} = input
  List.append(&2, Source.Attribute, Factory.binding_attributes(key), List.append(&2, Source.Attribute, field_metadata(key, meaning), List.append(&2, Source.Attribute, checked_attributes(field_checked(meaning)), List.append(&2, Source.Attribute, label_attributes(label, key), availability_attributes(availability)))))

def native_input_request(+key: UIIdentity.Key, +input: Controls.FormInput, +visual: Design.Style, parameters: Design.LayoutParameters) -> InputFieldRequest:
  Controls.FormInput{+meaning, +name, +widget, label, availability} = input
  InputFieldRequest{FieldBinding{key, expected_input_attributes(key, input)},
    FieldContent{field_kind(widget), Factory.style(visual, input_width(widget), input_height(widget), Model.Confined{}), node_value(meaning), placeholder(widget, meaning, name), choices(meaning), Source.field_policy(0n, 0n, Nat.sub(maximum_lines(widget, visual, parameters), 1n)), name},
    FieldProtocol{enabled(availability), field_input_event(meaning, widget, key), field_remaining_events(widget, key)}}

def interpret_input_field(label: Controls.LabelPlacement, key: UIIdentity.Key, name: String, visual: Design.Style, request: InputFieldRequest) -> Source.Node:
  InputFieldRequest{binding, content, protocol} = request
  FieldBinding{field_key, attributes} = binding
  FieldContent{kind, style, value, placeholder, options, policy, field_name} = content
  FieldProtocol{enabled, first, remaining} = protocol
  label_field(label, key, name, visual, Source.Field{field_key, kind, style, attributes, value, placeholder, options, policy, field_name, enabled, first, remaining})

def input_widget_request(+widget: Controls.Widget, +key: UIIdentity.Key, +meaning: SurfaceTypes.Meaning, +name: String, +placement: Controls.LabelPlacement, +availability: View.Availability, +visual: Design.Style, request: InputFieldRequest) -> Source.Node:
  match widget:
    case Controls.PlainValue{}:
      Source.Box{key, Source.Output{}, Factory.content_style(visual, Model.Horizontal{}, Model.StretchSize{}, Model.NaturalSize{}, 0n), Factory.binding_attributes(key), [caption(UIIdentity.part(key, "value"), node_value(meaning), visual, T.NormalAnywhere{})]}
    case +other:
      interpret_input_field(placement, key, name, visual, request)

def input_widget(+widget: Controls.Widget, +key: UIIdentity.Key, +meaning: SurfaceTypes.Meaning, +name: String, +placement: Controls.LabelPlacement, +availability: View.Availability, +visual: Design.Style, parameters: Design.LayoutParameters) -> Source.Node:
  input_widget_request(widget, key, meaning, name, placement, availability, visual, native_input_request(key, Controls.FormInput{meaning, name, widget, placement, availability}, visual, parameters))

def input_source_request(key: UIIdentity.Key, input: Controls.FormInput, visual: Design.Style, request: InputFieldRequest) -> Source.Node:
  Controls.FormInput{meaning, name, widget, label, availability} = input
  input_widget_request(widget, key, meaning, name, label, availability, visual, request)

def input(+key: UIIdentity.Key, +input: Controls.FormInput, +visual: Design.Style, parameters: Design.LayoutParameters) -> Source.Node:
  input_source_request(key, input, visual, native_input_request(key, input, visual, parameters))

def available_placement_choice(enabled: Bool, target: String, label: String, rest: +List<Source.Choice>) -> +List<Source.Choice>:
  match enabled:
    case True{}: Source.Choice{target, label, False{}} <> rest
    case False{}: rest

def placement_choices(values: +List<SurfaceTypes.Placement>) -> +List<Source.Choice>:
  match values:
    case Nil{}: Nil{}
    case Con{SurfaceTypes.Placement{target, label, input, availability}, rest}:
      available_placement_choice(InterfaceView.available(availability), target, label, placement_choices(rest))

def has_available_destination(values: +List<SurfaceTypes.Placement>) -> Bool:
  InterfaceView.has_available_destination(values)

def movable_choices(+key: UIIdentity.Key, control: Controls.MovableControl, +visual: Design.Style, +parameters: Design.LayoutParameters) -> Source.Node:
  Controls.MovableControl{+destinations, face, +name, handle, geometry} = control
  Source.Field{key, Source.SelectField{},
    Factory.style(visual, Model.StretchSize{}, Model.NaturalSize{}, Model.Confined{}),
    Factory.binding_attributes(key), "", "Move to…",
    Source.Choice{"", "Move to…", True{}} <> placement_choices(destinations),
    Source.FieldPolicy{1n, 1n, 1n}, name, has_available_destination(destinations), Doc.SelectDestination{UIIdentity.encode(key)}, Nil{}}


type InputObservation is Data:
  InputObservation{key: UIIdentity.Key, input: Controls.FormInput, visual: Design.Style,
    parameters: Design.LayoutParameters, request: InputFieldRequest, node: Source.Node}

type MovableObservation is Data:
  MovableObservation{key: UIIdentity.Key, control: Controls.MovableControl, visual: Design.Style,
    parameters: Design.LayoutParameters, node: Source.Node}

# Observe only the field position declared by the label construction syntax.
def selected_field(label: Controls.LabelPlacement, node: Source.Node) -> Maybe<&2, Source.Node>:
  match label:
    case Controls.AccessibleOnly{}:
      match node:
        case Source.Field{key, kind, style, attributes, value, placeholder, options, policy, name, enabled, first, remaining}: Some{Source.Field{key, kind, style, attributes, value, placeholder, options, policy, name, enabled, first, remaining}}
        case _: None{}
    case _:
      match node:
        case Source.Box{key, tag, style, attributes, Con{caption, Con{Source.Field{field_key, kind, field_style, field_attributes, value, placeholder, options, policy, name, enabled, first, remaining}, Nil{}}}}:
          Some{Source.Field{field_key, kind, field_style, field_attributes, value, placeholder, options, policy, name, enabled, first, remaining}}
        case _: None{}

def observed_binding(field: Maybe<&2, Source.Node>) -> Maybe<&2, FieldBinding>:
  match field:
    case Some{Source.Field{key, kind, style, attributes, value, placeholder, options, policy, name, enabled, first, remaining}}: Some{FieldBinding{key, attributes}}
    case _: None{}

def observed_content(field: Maybe<&2, Source.Node>) -> Maybe<&2, FieldContent>:
  match field:
    case Some{Source.Field{key, kind, style, attributes, value, placeholder, options, policy, name, enabled, first, remaining}}: Some{FieldContent{kind, style, value, placeholder, options, policy, name}}
    case _: None{}

def observed_protocol(field: Maybe<&2, Source.Node>) -> Maybe<&2, FieldProtocol>:
  match field:
    case Some{Source.Field{key, kind, style, attributes, value, placeholder, options, policy, name, enabled, first, remaining}}: Some{FieldProtocol{enabled, first, remaining}}
    case _: None{}

def output_binding(node: Source.Node) -> Maybe<&2, FieldBinding>:
  match node:
    case Source.Box{key, Source.Output{}, style, attributes, children}: Some{FieldBinding{key, attributes}}
    case _: None{}

type OutputContent is Data:
  OutputContent{style: Source.Style, key: UIIdentity.Key, value: String, font: Source.FontChoice, wrapping: T.Wrapping}

def output_content(node: Source.Node) -> Maybe<&2, OutputContent>:
  match node:
    case Source.Box{key, Source.Output{}, style, attributes, Con{Source.Text{caption_key, value, font, wrapping}, Nil{}}}: Some{OutputContent{style, caption_key, value, font, wrapping}}
    case _: None{}

def expected_input_content(key: UIIdentity.Key, input: Controls.FormInput, visual: Design.Style, parameters: Design.LayoutParameters) -> FieldContent:
  request_content(native_input_request(key, input, visual, parameters))

def input_binding(observation: InputObservation) -> Type:
  InputObservation{+key, +input, +visual, parameters, request, node} = observation
  Controls.FormInput{meaning, name, widget, label, availability} = input
  match widget:
    case Controls.PlainValue{}: {output_binding(node) == Some{FieldBinding{key, Factory.binding_attributes(key)}} : Maybe<&2, FieldBinding>}
    case _: {observed_binding(selected_field(label, node)) == Some{request_binding(request)} : Maybe<&2, FieldBinding>}

def input_content(observation: InputObservation) -> Type:
  InputObservation{+key, +input, +visual, parameters, request, node} = observation
  Controls.FormInput{meaning, name, widget, label, availability} = input
  match widget:
    case Controls.PlainValue{}: {output_content(node) == Some{OutputContent{Factory.content_style(visual, Model.Horizontal{}, Model.StretchSize{}, Model.NaturalSize{}, 0n), UIIdentity.part(key, "value"), node_value(meaning), Source.ExplicitFont{parent_font(visual)}, T.NormalAnywhere{}}} : Maybe<&2, OutputContent>}
    case _: {observed_content(selected_field(label, node)) == Some{request_content(request)} : Maybe<&2, FieldContent>}

def input_protocol(observation: InputObservation) -> Type:
  InputObservation{+key, +input, +visual, parameters, request, node} = observation
  Controls.FormInput{meaning, name, widget, label, availability} = input
  match widget:
    case Controls.PlainValue{}: {Source.events_of(node) == Nil{} : +List<Doc.DOMEvent>}
    case _: {observed_protocol(selected_field(label, node)) == Some{request_protocol(request)} : Maybe<&2, FieldProtocol>}

def input_content_protocol(observation: InputObservation) -> Type:
  Categories.intersection(InputObservation, input_content, input_protocol, observation)

def input_requested(observation: InputObservation) -> Type:
  InputObservation{key, input, visual, parameters, request, node} = observation
  {request == native_input_request(key, input, visual, parameters) : InputFieldRequest}

def input_bound_content_protocol(observation: InputObservation) -> Type:
  Categories.intersection(InputObservation, input_binding, input_content_protocol, observation)

def authored_input(observation: InputObservation) -> Type:
  Categories.intersection(InputObservation, input_requested, input_bound_content_protocol, observation)

def input_is_requested() -> Categories.Inclusion<InputObservation, authored_input, input_requested>:
  Categories.intersection_first(InputObservation, input_requested, input_bound_content_protocol)

def input_is_bound() -> Categories.Inclusion<InputObservation, authored_input, input_binding>:
  Categories.inclusion_compose(InputObservation, authored_input, input_bound_content_protocol, input_binding,
    Categories.intersection_second(InputObservation, input_requested, input_bound_content_protocol),
    Categories.intersection_first(InputObservation, input_binding, input_content_protocol))

def input_is_content() -> Categories.Inclusion<InputObservation, authored_input, input_content>:
  Categories.inclusion_compose(InputObservation, authored_input, input_bound_content_protocol, input_content,
    Categories.intersection_second(InputObservation, input_requested, input_bound_content_protocol),
    Categories.inclusion_compose(InputObservation, input_bound_content_protocol, input_content_protocol, input_content,
      Categories.intersection_second(InputObservation, input_binding, input_content_protocol),
      Categories.intersection_first(InputObservation, input_content, input_protocol)))

def input_is_protocol() -> Categories.Inclusion<InputObservation, authored_input, input_protocol>:
  Categories.inclusion_compose(InputObservation, authored_input, input_bound_content_protocol, input_protocol,
    Categories.intersection_second(InputObservation, input_requested, input_bound_content_protocol),
    Categories.inclusion_compose(InputObservation, input_bound_content_protocol, input_content_protocol, input_protocol,
      Categories.intersection_second(InputObservation, input_binding, input_content_protocol),
      Categories.intersection_second(InputObservation, input_content, input_protocol)))

type MovableDestinations is Data:
  MovableDestinations{options: +List<Source.Choice>, enabled: Bool}

def observed_destinations(node: Source.Node) -> Maybe<&2, MovableDestinations>:
  match node:
    case Source.Field{key, kind, style, attributes, value, placeholder, options, policy, name, enabled, first, remaining}: Some{MovableDestinations{options, enabled}}
    case _: None{}

def movable_destinations(observation: MovableObservation) -> Type:
  MovableObservation{key, Controls.MovableControl{+destinations, face, name, handle, geometry}, visual, parameters, node} = observation
  {observed_destinations(node) == Some{MovableDestinations{Source.Choice{"", "Move to…", True{}} <> placement_choices(destinations), has_available_destination(destinations)}} : Maybe<&2, MovableDestinations>}

def movable_protocol_binding(observation: MovableObservation) -> Type:
  MovableObservation{+key, control, visual, parameters, node} = observation
  {observed_binding(Some{node}) == Some{FieldBinding{key, Factory.binding_attributes(key)}} : Maybe<&2, FieldBinding>}

def movable_protocol_content(observation: MovableObservation) -> Type:
  MovableObservation{key, Controls.MovableControl{+destinations, face, name, handle, geometry}, visual, parameters, node} = observation
  {observed_content(Some{node}) == Some{FieldContent{Source.SelectField{}, Factory.style(visual, Model.StretchSize{}, Model.NaturalSize{}, Model.Confined{}), "", "Move to…", Source.Choice{"", "Move to…", True{}} <> placement_choices(destinations), Source.FieldPolicy{1n, 1n, 1n}, name}} : Maybe<&2, FieldContent>}

def movable_protocol_events(observation: MovableObservation) -> Type:
  MovableObservation{key, Controls.MovableControl{destinations, face, name, handle, geometry}, visual, parameters, node} = observation
  {Source.events_of(node) == [Doc.SelectDestination{UIIdentity.encode(key)}] : +List<Doc.DOMEvent>}

type MovableProtocol<-observation: MovableObservation> is Type:
  MovableProtocol{binding: movable_protocol_binding(observation), content: movable_protocol_content(observation), events: movable_protocol_events(observation)}

def movable_protocol(observation: MovableObservation) -> Type:
  MovableProtocol<observation>

def authored_movable(observation: MovableObservation) -> Type:
  Categories.intersection(MovableObservation, movable_destinations, movable_protocol, observation)

def movable_is_destinations() -> Categories.Inclusion<MovableObservation, authored_movable, movable_destinations>:
  Categories.intersection_first(MovableObservation, movable_destinations, movable_protocol)

def movable_is_protocol() -> Categories.Inclusion<MovableObservation, authored_movable, movable_protocol>:
  Categories.intersection_second(MovableObservation, movable_destinations, movable_protocol)

law input_evidence:
  @+key:UIIdentity.Key -> @+syntax:Controls.FormInput -> @+visual:Design.Style -> @+parameters:Design.LayoutParameters -> @+request:InputFieldRequest -> input_requested(InputObservation{key, syntax, visual, parameters, request, input_source_request(key, syntax, visual, request)}) -> authored_input(InputObservation{key, syntax, visual, parameters, request, input_source_request(key, syntax, visual, request)})

law movable_evidence:
  @+key:UIIdentity.Key -> @+syntax:Controls.MovableControl -> @+visual:Design.Style -> @+parameters:Design.LayoutParameters -> authored_movable(MovableObservation{key, syntax, visual, parameters, movable_choices(key, syntax, visual, parameters)})

law construct_input:
  @+key:UIIdentity.Key -> @+syntax:Controls.FormInput -> @+visual:Design.Style -> @+parameters:Design.LayoutParameters -> Categories.Membership<InputObservation, authored_input>

law construct_movable:
  @+key:UIIdentity.Key -> @+syntax:Controls.MovableControl -> @+visual:Design.Style -> @+parameters:Design.LayoutParameters -> Categories.Membership<MovableObservation, authored_movable>

def constructed_input_node(constructed: Categories.Membership<InputObservation, authored_input>) -> Source.Node:
  Categories.Membership{InputObservation{key, input, visual, parameters, request, node}, evidence} = constructed
  node

def constructed_movable_node(constructed: Categories.Membership<MovableObservation, authored_movable>) -> Source.Node:
  Categories.Membership{MovableObservation{key, control, visual, parameters, node}, evidence} = constructed
  node

law input_constructor_correspondence:
  @+key:UIIdentity.Key -> @+syntax:Controls.FormInput -> @+visual:Design.Style -> @+parameters:Design.LayoutParameters -> {constructed_input_node(construct_input(key, syntax, visual, parameters)) == input(key, syntax, visual, parameters) : Source.Node}

law movable_constructor_correspondence:
  @+key:UIIdentity.Key -> @+syntax:Controls.MovableControl -> @+visual:Design.Style -> @+parameters:Design.LayoutParameters -> {constructed_movable_node(construct_movable(key, syntax, visual, parameters)) == movable_choices(key, syntax, visual, parameters) : Source.Node}
