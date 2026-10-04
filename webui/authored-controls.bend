import Base
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
import ../core/interface.bend as UI
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

def node_value(value: UI.Meaning) -> String:
  match value:
    case UI.Edit{editor, field, entry, observed_value, choices}: field_text(field, observed_value)
    case UI.BoardSearch{filter}: filter_search(filter)
    case UI.SearchChoices{query}: query
    case UI.EnterDirectory{editor, text}: text
    case UI.DirectoryBrowserLocation{value}: value
    case UI.BoardProfile{automatic, selected, choices, enabled}: selected
    case _: ""

def parent_font(value: Design.Style) -> T.Presentation:
  Design.Style{text, chrome, alignment, flow, overflow, frame, minimum_height, maximum_width_percent, states} = value
  text

def parent_gap(value: Design.Style) -> Nat:
  Design.Style{text, chrome, alignment, flow, overflow, frame, minimum_height, maximum_width_percent, states} = value
  Enclosure.frame_gap(frame)

def glyph(key: String, icon: Controls.Icon, parent: Design.Style, +size: Nat) -> Source.Node:
  Source.Glyph{key, Iconography.drawing(icon, size), Factory.glyph_style(parent, size, size)}

def caption(key: String, text: String, parent: Design.Style, wrapping: T.Wrapping) -> Source.Node:
  Factory.text(key, text, Source.ExplicitFont{parent_font(parent)}, wrapping)

def leading_icon(value: Maybe<&2, Controls.Icon>, key: String, parent: Design.Style, size: Nat) -> +List<Source.Node>:
  match value:
    case None{}: Nil{}
    case Some{icon}: [glyph(key ++ "/leading", icon, parent, size)]

def face_description(value: Maybe<&2, String>, key: String, parent: Design.Style) -> +List<Source.Node>:
  match value:
    case None{}: Nil{}
    case Some{text}: [Factory.text(key ++ "/description", text, Source.ExplicitFont{T.supporting(parent_font(parent))}, Controls.description_wrapping())]

def selection(checked: Bool, key: String, parent: Design.Style, size: Nat) -> +List<Source.Node>:
  match checked:
    case True{}: [glyph(key ++ "/check", Controls.Check{}, parent, size)]
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

def face_members(+value: Controls.Face, +key: String, +parent: Design.Style, +geometry: Controls.Geometry) -> +List<Source.Node>:
  match value:
    case Controls.TextFace{text}: [caption(key ++ "/caption", text, parent, Controls.caption_wrapping(value))]
    case Controls.SingleLineFace{text}: [caption(key ++ "/caption", text, parent, T.SingleLine{})]
    case Controls.IconFace{icon}: [glyph(key ++ "/icon", icon, parent, face_icon_size(geometry))]
    case Controls.IconTextFace{icon, text}: [glyph(key ++ "/icon", icon, parent, face_icon_size(geometry)), caption(key ++ "/caption", text, parent, Controls.caption_wrapping(value))]
    case Controls.PickerFace{leading, text}:
      List.append(&2, Source.Node, leading_icon(leading, key, parent, face_icon_size(geometry)),
      [Source.Box{key ++ "/value", Source.Span{}, Factory.content_style(parent, Model.Horizontal{}, Model.StretchSize{}, Model.NaturalSize{}, 0n), Nil{}, [caption(key ++ "/caption", text, parent, Controls.caption_wrapping(value))]}, glyph(key ++ "/chevron", Controls.ChevronDown{}, parent, face_icon_size(geometry))])
    case Controls.DisclosureFace{text, expanded}:
      [caption(key ++ "/caption", text, parent, Controls.caption_wrapping(value)), glyph(key ++ "/chevron", disclosure_icon(expanded), parent, face_icon_size(geometry))]
    case Controls.PermissionFace{filesystem, network, approval}:
      [glyph(key ++ "/filesystem", filesystem, parent, face_icon_size(geometry)), glyph(key ++ "/network", network, parent, face_icon_size(geometry)), glyph(key ++ "/approval", approval, parent, face_icon_size(geometry))]
    case Controls.ChoiceFace{text, details, checked}:
      [Source.Box{key ++ "/text", Source.Span{}, Factory.content_style(parent, Model.Vertical{}, Model.StretchSize{}, Model.NaturalSize{}, parent_gap(parent)), Nil{}, List.append(&2, Source.Node, [caption(key ++ "/caption", text, parent, Controls.caption_wrapping(value))], face_description(details, key, parent))},
       Source.Box{key ++ "/selection", Source.Span{}, Factory.with_alignments(Factory.with_minimum(Factory.content_style(parent, Model.Horizontal{}, Model.ExactSize{face_leading_slot(geometry)}, Model.ExactSize{face_leading_slot(geometry)}, 0n), Enclosure.Extent{face_leading_slot(geometry), face_leading_slot(geometry)}), Spatial.Centered{}, Spatial.Centered{}), Nil{}, selection(checked, key, parent, face_icon_size(geometry))}]

def face(key: String, value: Controls.Face, parent: Design.Style, geometry: Controls.Geometry) -> +List<Source.Node>:
  face_members(value, key, parent, geometry)

def enabled(value: View.Availability) -> Bool:
  match value:
    case View.Available{}: True{}
    case _: False{}

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
    case Controls.ChoiceFace{text, description, checked}: Model.StretchSize{}
    case _: Factory.natural_width(visual)

def action_alignment(value: Controls.Face) -> Spatial.Alignment:
  match value:
    case Controls.ChoiceFace{text, description, checked}: Spatial.Leading{}
    case Controls.PickerFace{leading, text}: Spatial.Leading{}
    case _: Spatial.Centered{}

def invalid(+key: String, +visual: Design.Style, +diagnostic: String) -> Source.Node:
  Source.Box{key, Source.Output{}, Factory.content_style(visual, Model.Horizontal{}, Model.NaturalSize{}, Model.NaturalSize{}, 0n), [Source.DataAttribute{"invalid-source", diagnostic}], [caption(key ++ "/diagnostic", diagnostic, visual, T.NormalAnywhere{})]}

def action(+key: String, +visual: Design.Style, representation: Controls.Representation) -> Source.Node:
  match representation:
    case Controls.Action{input, +availability, name, +value, state, +geometry, placement, assistance, response}:
      Source.Control{key, Source.Button{}, Factory.with_alignments(Factory.with_direction(Factory.with_minimum(Factory.style(visual, action_width(value, visual), Model.NaturalSize{}, Model.Confined{}), Enclosure.Extent{Controls.geometry_minimum_width(geometry), Controls.geometry_minimum_height(geometry)}), Model.Horizontal{}), action_alignment(value), Spatial.Centered{}), List.append(&2, Source.Attribute, Factory.binding_attributes(key), List.append(&2, Source.Attribute, availability_attributes(availability), List.append(&2, Source.Attribute, behavior(state), List.append(&2, Source.Attribute, help(assistance), feedback(response))))), name, enabled(availability), Doc.Activate{key}, Nil{}, face(key, value, visual, geometry)}
    case _: invalid(key, visual, "invalid-action-representation")

def field_checked(value: UI.Meaning) -> Bool:
  match value:
    case UI.Edit{editor, field, entry, Forms.ToggleValue{enabled}, choices}: enabled
    case UI.Edit{editor, Forms.AssistedCapture{}, entry, Forms.AssistanceValue{enabled, profile}, choices}: enabled
    case UI.Edit{editor, Forms.NetworkAccess{}, entry, Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, Context.InheritedSandbox{Domain.Sandbox{mode, enabled}}, approval, guidance}}, choices}: enabled
    case UI.Edit{editor, Forms.NetworkAccess{}, entry, Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, Context.ChosenSandbox{Domain.Sandbox{mode, enabled}}, approval, guidance}}, choices}: enabled
    case _: False{}

def checked_attributes(checked: Bool) -> +List<Source.Attribute>:
  match checked:
    case True{}: [Source.CheckedAttribute{}]
    case False{}: Nil{}

def option_values(values: +List<Forms.ChoiceValue>, +selected: String) -> +List<Source.Choice>:
  match values:
    case Nil{}: Nil{}
    case Con{Forms.ChoiceValue{+value, label}, rest}: Source.Choice{value, label, String.eq(value, selected)} <> option_values(rest, selected)

def choices(value: UI.Meaning) -> +List<Source.Choice>:
  match value:
    case UI.BoardProfile{automatic, selected, profiles, enabled}: option_values(FieldOptions.profile_options(profiles), selected)
    case UI.Edit{editor, field, entry, observed, options}: option_values(options, field_text(field, observed))
    case _: Nil{}

def field_placeholder(kind: EditorLayout.FieldKind, name: String) -> String:
  match kind:
    case EditorLayout.WorkTitle{}: name
    case EditorLayout.WorkDescription{}: name
    case _: ""

def semantic_placeholder(value: UI.Meaning, name: String) -> String:
  match value:
    case UI.BoardSearch{filter}: "搜索任务"
    case UI.Edit{editor, Forms.CardLabels{}, entry, observed, choices}: "每行一个标签"
    case other: field_placeholder(EditorLayout.field_kind(other), name)

def placeholder(widget: Controls.Widget, meaning: UI.Meaning, name: String) -> String:
  match widget:
    case Controls.MessageInput{}: "Ask anything, or describe a task"
    case _: semantic_placeholder(meaning, name)

def field_metadata(value: UI.Meaning) -> +List<Source.Attribute>:
  match value:
    case UI.Edit{editor, field, entry, observed, choices}: [Source.DataAttribute{"field", Forms.key(field)}]
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

def field_first_event(value: Controls.Widget, key: String) -> Doc.Event:
  match value:
    case Controls.ToggleInput{}: Doc.EditToggle{key}
    case Controls.FileChooser{face}: Doc.SelectFiles{key}
    case Controls.AttachmentList{}: Doc.SelectFiles{key}
    case _: Doc.EditText{key}

def field_remaining_events(value: Controls.Widget, key: String) -> +List<Doc.Event>:
  match value:
    case Controls.DirectoryChooser{face}: [Doc.ConfirmText{key}]
    case _: Nil{}

def maximum_lines(value: Controls.Widget, visual: Design.Style, parameters: Design.LayoutParameters) -> Nat:
  match value:
    case Controls.MessageInput{}: Nat.max(1n, Nat.div(Design.input_maximum_height(parameters), Nat.max(1n, T.resolved_line_height(T.resolved(parent_font(visual))))))
    case Controls.TextArea{}: Nat.max(1n, Nat.div(Design.input_maximum_height(parameters), Nat.max(1n, T.resolved_line_height(T.resolved(parent_font(visual))))))
    case Controls.DirectoryList{}: Nat.max(1n, Nat.div(Design.input_maximum_height(parameters), Nat.max(1n, T.resolved_line_height(T.resolved(parent_font(visual))))))
    case _: 1n

def label_attributes(value: Controls.LabelPlacement, key: String) -> +List<Source.Attribute>:
  match value:
    case Controls.AccessibleOnly{}: Nil{}
    case _: [Source.AriaAttribute{"labelledby", key ++ "/label"}]

def label_direction(value: Controls.LabelPlacement) -> Model.Direction:
  match value:
    case Controls.BesideInput{}: Model.Horizontal{}
    case _: Model.Vertical{}

def label_field(value: Controls.LabelPlacement, +key: String, name: String, +visual: Design.Style, field: Source.Node) -> Source.Node:
  match value:
    case Controls.AccessibleOnly{}: field
    case other:
      Source.Box{key ++ "/field-wrapper", Source.Div{}, Factory.content_style(visual, label_direction(other), Model.StretchSize{}, Model.NaturalSize{}, parent_gap(visual)), Nil{},
        [Source.Box{key ++ "/label", Source.Span{}, Factory.content_style(visual, Model.Horizontal{}, Model.NaturalSize{}, Model.NaturalSize{}, 0n), Nil{}, [caption(key ++ "/label/text", name, visual, T.NormalAnywhere{})]}, field]}

def input_widget(+widget: Controls.Widget, +key: String, +meaning: UI.Meaning, +name: String, +placement: Controls.LabelPlacement, +availability: View.Availability, +visual: Design.Style, parameters: Design.LayoutParameters) -> Source.Node:
  match widget:
    case Controls.PlainValue{}:
      Source.Box{key, Source.Output{}, Factory.content_style(visual, Model.Horizontal{}, Model.StretchSize{}, Model.NaturalSize{}, 0n), Factory.binding_attributes(key), [caption(key ++ "/value", node_value(meaning), visual, T.NormalAnywhere{})]}
    case +other:
      label_field(placement, key, name, visual, Source.Field{key, field_kind(other), Factory.style(visual, Model.StretchSize{}, Model.NaturalSize{}, Model.Confined{}), List.append(&2, Source.Attribute, Factory.binding_attributes(key), List.append(&2, Source.Attribute, field_metadata(meaning), List.append(&2, Source.Attribute, checked_attributes(field_checked(meaning)), List.append(&2, Source.Attribute, label_attributes(placement, key), availability_attributes(availability))))), node_value(meaning), placeholder(other, meaning, name), choices(meaning), Source.field_policy(0n, 0n, Nat.sub(maximum_lines(other, visual, parameters), 1n)), name, enabled(availability), field_first_event(other, key), field_remaining_events(other, key)})

def input(key: String, meaning: UI.Meaning, representation: Controls.Representation, visual: Design.Style, parameters: Design.LayoutParameters) -> Source.Node:
  match representation:
    case Controls.Input{binding, name, widget, label, availability}: input_widget(widget, key, meaning, name, label, availability, visual, parameters)
    case _: invalid(key, visual, "invalid-input-representation")


def available_placement_choice(enabled: Bool, target: String, label: String, rest: +List<Source.Choice>) -> +List<Source.Choice>:
  match enabled:
    case True{}: Source.Choice{target, label, False{}} <> rest
    case False{}: rest

def placement_choices(values: +List<UI.Placement>) -> +List<Source.Choice>:
  match values:
    case Nil{}: Nil{}
    case Con{UI.Placement{target, label, input, availability}, rest}:
      available_placement_choice(UI.available(availability), target, label, placement_choices(rest))

def has_available_destination(values: +List<UI.Placement>) -> Bool:
  match values:
    case Nil{}: False{}
    case Con{UI.Placement{target, label, input, availability}, rest}:
      UI.available(availability) || has_available_destination(rest)

def movable_choices(+key: String, +representation: Controls.Representation, +visual: Design.Style, +parameters: Design.LayoutParameters) -> Source.Node:
  match representation:
    case Controls.Movable{+destinations, face, +name, handle, geometry, help}:
      Source.Field{key ++ "/destinations", Source.SelectField{},
        Factory.with_minimum(Factory.style(visual, Model.StretchSize{}, Model.NaturalSize{}, Model.Confined{}), Enclosure.Extent{32n, 32n}),
        Factory.binding_attributes(key), "", name,
        Source.Choice{"", name, True{}} <> placement_choices(destinations),
        Source.FieldPolicy{1n, 1n, 1n}, name, has_available_destination(destinations), Doc.SelectDestination{key}, Nil{}}
    case _: invalid(key, visual, "invalid-movable-representation")
