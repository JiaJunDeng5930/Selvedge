import ../layout/ACTIVITY.bend as Activity
import ../../interaction/services/CONTEXT.bend as Workspace
import ../../interaction/experience/MODEL.bend as UXTypes
import ../../interaction/experience/PROGRAM.bend as UX
import ../../interaction/INPUT.bend as User
import ../layout/HIERARCHY.bend as Hierarchy
import ../controls/SURFACES.bend as Surfaces
import ../../interaction/submission/FIELDS.bend as Forms
import ../../interaction/TYPES.bend as InteractionTypes
import ../../interaction/presentation/INFORMATION.bend as Information
import Base
import ../controls/PROGRAM.bend as Controls
import ../controls/MODEL.bend as Authored
import ../controls/CONTROLS.bend as AuthoredControls
import ../../interaction/presentation/MODEL.bend as View
import ../../interaction/submission/field-options.bend as FieldOptions
import ../controls/authored-primitives.bend as Factory
import ../appearance/MODEL.bend as Appearance
import ../layout/natural-size.bend as NaturalSize
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ../../interaction/presentation/COMPOSITION.bend as Composition
import ../../interaction/IDENTITY.bend as Identity
import ../../features/board/MODEL.bend as Board
import ./SOURCE.bend as Source
import ../layout/physical-space.bend as Model
import ../appearance/TYPOGRAPHY.bend as T
import ../appearance/DESIGN.bend as Design
import ./MODEL.bend as Doc
import ../layout/enclosure.bend as Enclosure
import ../layout/GEOMETRY.bend as Spatial
import ../../interaction/presentation/SURFACE.bend as SurfaceTypes

def rule_border(rule: Model.Rule) -> Nat:
  Model.Rule{direction, main_alignment, cross_alignment, frame, border,
    width, height, minimum, scroll, position} = rule
  border

def rule_position(rule: Model.Rule) -> Spatial.Position:
  Model.Rule{direction, main_alignment, cross_alignment, frame, border,
    width, height, minimum, scroll, position} = rule
  position

def position_is_authored(+style: Source.Style, parent: T.Presentation) -> Type:
  Source.Style{layout, font, chrome, states} = style
  Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position} = layout
  {rule_position(Source.physical_rule(Source.resolve_style(style, parent))) == position : Spatial.Position}

def border_is_chrome(+style: Source.Style, parent: T.Presentation) -> Type:
  Source.Style{layout, font, chrome, states} = style
  Design.Chrome{foreground, background, border, border_width, radius, shadow} = chrome
  {rule_border(Source.physical_rule(Source.resolve_style(style, parent))) == border_width : Nat}

def native_field_footprint(+kind: Source.NativeFieldKind, +style: Source.ResolvedStyle) -> Type:
  match kind:
    case Source.ToggleField{}:
      Source.ResolvedStyle{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states} = style
      {Source.native_field_rule(kind, style) == Model.Rule{direction, main, cross, frame, 0n, width, height, minimum, scroll, position} : Model.Rule}
    case Source.TextField{}: {Source.native_field_rule(kind, style) == Source.physical_rule(style) : Model.Rule}
    case Source.MessageField{}: {Source.native_field_rule(kind, style) == Source.physical_rule(style) : Model.Rule}
    case Source.TextAreaField{}: {Source.native_field_rule(kind, style) == Source.physical_rule(style) : Model.Rule}
    case Source.SelectField{}: {Source.native_field_rule(kind, style) == Source.physical_rule(style) : Model.Rule}
    case Source.MultiSelectField{}: {Source.native_field_rule(kind, style) == Source.physical_rule(style) : Model.Rule}
    case Source.NumberField{minimum}: {Source.native_field_rule(kind, style) == Source.physical_rule(style) : Model.Rule}
    case Source.FileField{multiple}: {Source.native_field_rule(kind, style) == Source.physical_rule(style) : Model.Rule}
    case Source.DirectoryField{}: {Source.native_field_rule(kind, style) == Source.physical_rule(style) : Model.Rule}
    case Source.SearchField{}: {Source.native_field_rule(kind, style) == Source.physical_rule(style) : Model.Rule}
    case Source.SecretField{}: {Source.native_field_rule(kind, style) == Source.physical_rule(style) : Model.Rule}

def inherited_font(choice: Source.FontChoice, +parent: T.Presentation) -> Type:
  match choice:
    case Source.InheritFont{}: {Source.resolve_font(Source.InheritFont{}, parent) == parent : T.Presentation}
    case Source.ExplicitFont{+presentation}: {Source.resolve_font(Source.ExplicitFont{presentation}, parent) == presentation : T.Presentation}

def field_policy_is_bounded(policy: Source.FieldPolicy) -> Type:
  {Source.field_policy_valid(policy) == True{} : Bool}

def operation_is_structurally_present(+node: Source.Node) -> Type:
  match node:
    case Source.Control{key, tag, style, attributes, accessible_name, enabled, +first_event, +remaining_events, children}:
      {Source.events_of(node) == first_event <> remaining_events : +List<Doc.DOMEvent>}
    case Source.Field{key, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, +first_event, +remaining_events}:
      {Source.events_of(node) == first_event <> remaining_events : +List<Doc.DOMEvent>}
    case Source.Box{key, tag, style, attributes, children}:
      {Source.events_of(node) == Nil{} : +List<Doc.DOMEvent>}
    case Source.Text{key, value, font, wrapping}:
      {Source.events_of(node) == Nil{} : +List<Doc.DOMEvent>}
    case Source.Glyph{key, drawing, style}:
      {Source.events_of(node) == Nil{} : +List<Doc.DOMEvent>}
    case Source.NativeAttachment{key, target, attributes, style, children}:
      {Source.events_of(node) == Nil{} : +List<Doc.DOMEvent>}
    case Source.RichText{key, style, content, attachments, native_owner}:
      {Source.events_of(node) == Nil{} : +List<Doc.DOMEvent>}

# Native code geometry belongs to its rich-content policy. A body policy may
# change presentation only; unsupported independent layout must be rejected.

def board_controls(visual: Design.Style, position: Composition.Position) -> Type:
  {Authored.region_style(visual, Composition.BoardControls{}, position) == Factory.with_direction(Factory.style(Appearance.with_arrangement(visual, Enclosure.SeparateFrames{Enclosure.ComposerControls{}}), Model.StretchSize{}, Model.NaturalSize{}, Model.Confined{}), Model.ResponsiveHorizontal{}) : Source.Style}

def board_stages(visual: Design.Style, position: Composition.Position) -> Type:
  {Authored.region_style(visual, Composition.BoardStages{}, position) == Factory.with_direction(Factory.style(Appearance.with_arrangement(visual, Enclosure.SeparateFrames{Enclosure.BoardColumns{}}), Model.StretchSize{}, Model.StretchSize{}, Model.ScrollHorizontally{}), Model.Horizontal{}) : Source.Style}

type InformationObservation is Data:
  MissingInformation{}
  ObservedInformation{key: Identity.Key, attributes: +List<Source.Attribute>, value: String, font: Source.FontChoice, wrapping: T.Wrapping}

def information_observation(node: Source.Node) -> InformationObservation:
  match node:
    case Source.Box{key, tag, style, attributes, [Source.Text{text_key, value, font, wrapping}]}: ObservedInformation{key, attributes, value, font, wrapping}
    case _: MissingInformation{}

def first_information(nodes: +List<Source.Node>) -> InformationObservation:
  match nodes:
    case Con{node, rest}: information_observation(node)
    case Nil{}: MissingInformation{}

def required_information_font_role(+role: Information.TextRole, scale: T.Scale) -> T.Presentation:
  match role:
    case Information.IntroductionTitle{}: T.Presentation{T.Display{}, T.Strong{}, scale}
    case Information.SurfaceTitle{}: T.Presentation{T.Title{}, T.Medium{}, scale}
    case Information.GroupTitle{}: T.Presentation{T.Section{}, T.Strong{}, scale}
    case Information.FieldLabel{}: T.Presentation{T.Body{}, T.Medium{}, scale}
    case Information.FieldValue{}: T.Presentation{T.Body{}, T.Regular{}, scale}
    case Information.OptionLabel{}: T.Presentation{T.Body{}, T.Medium{}, scale}
    case Information.Description{}: T.Presentation{T.Support{}, T.Regular{}, scale}
    case Information.Status{}: T.Presentation{T.Support{}, T.Regular{}, scale}

def required_information_font(+role: Information.TextRole, parent: T.Presentation) -> T.Presentation:
  T.Presentation{tier, emphasis, scale} = parent
  required_information_font_role(role, scale)

def required_information(+owner: Identity.Key, +role: Information.TextRole, value: String, visual: Design.Style) -> InformationObservation:
  +key = Identity.part(owner, "@information/" ++ Information.name(role))
  ObservedInformation{key, [Source.IdAttribute{Identity.encode(key)}, Source.DataAttribute{"information-owner", Identity.encode(owner)}, Source.DataAttribute{"information-role", Information.name(role)}], value, Source.ExplicitFont{required_information_font(role, Design.style_text(visual))}, T.NormalWords{}}

def information_alignment(node: Source.Node) -> Maybe<&2, Spatial.Alignment>:
  match node:
    case Source.Box{key, tag, Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states}, attributes, children}: Some{main}
    case _: None{}

def required_alignment(role: Information.TextRole) -> Spatial.Alignment:
  match role:
    case Information.IntroductionTitle{}: Spatial.Centered{}
    case _: Spatial.Leading{}

def owned_alignment(+owner: Identity.Key, +role: Information.TextRole, value: String, visual: Design.Style) -> Type:
  {information_alignment(AuthoredControls.owned_text(owner, role, value, visual)) == Some{required_alignment(role)} : Maybe<&2, Spatial.Alignment>}

def information_width(node: Source.Node) -> Maybe<&2, Model.AxisSize>:
  match node:
    case Source.Box{key, tag, Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states}, attributes, children}: Some{width}
    case _: None{}

def information_foreground(node: Source.Node) -> Maybe<&2, Design.Paint>:
  match node:
    case Source.Box{key, tag, Source.Style{layout, font, Design.Chrome{foreground, background, border, width, radius, shadow}, states}, attributes, children}: Some{foreground}
    case _: None{}

def parent_foreground(visual: Design.Style) -> Design.Paint:
  Design.Style{text, Design.Chrome{foreground, background, border, width, radius, shadow}, alignment, flow, overflow, frame, minimum_height, maximum_width_percent, states} = visual
  foreground

def required_foreground(role: Information.TextRole, visual: Design.Style) -> Design.Paint:
  match role:
    case Information.Description{}: Design.TextForeground{Surfaces.SecondaryText{}}
    case Information.Status{}: Design.TextForeground{Surfaces.SecondaryText{}}
    case _: parent_foreground(visual)

def owned_foreground(+owner: Identity.Key, +role: Information.TextRole, value: String, +visual: Design.Style) -> Type:
  {information_foreground(AuthoredControls.owned_text(owner, role, value, visual)) == Some{required_foreground(role, visual)} : Maybe<&2, Design.Paint>}

def owned_information(+owner: Identity.Key, +role: Information.TextRole, +value: String, +visual: Design.Style) -> Type:
  {information_observation(AuthoredControls.owned_text(owner, role, value, visual)) == required_information(owner, role, value, visual) : InformationObservation}

def scalar_information(+key: Identity.Key, +label: String, +role: SurfaceTypes.Role, +text_role: Information.TextRole, +visual: Design.Style, representation: Controls.Representation, children: +List<Authored.Child>, parameters: Design.LayoutParameters, content: +List<Source.Node>) -> Type:
  {first_information(Source.children_of(Authored.regular_content(key, label, role, SurfaceTypes.InformationText{text_role}, visual, representation, children, parameters, content))) == required_information(key, text_role, label, visual) : InformationObservation}

def field_label(+key: Identity.Key, +label: String, +visual: Design.Style, field: Source.Node) -> Type:
  {first_information(Source.children_of(AuthoredControls.label_field(Controls.AboveInput{}, key, label, visual, field))) == required_information(key, Information.FieldLabel{}, label, visual) : InformationObservation}

def option_text(nodes: +List<Source.Node>) -> InformationObservation:
  match nodes:
    case Con{Source.Glyph{key, drawing, style}, rest}: option_text(rest)
    case Con{Source.Box{key, tag, style, attributes, children}, rest}: first_information(children)
    case _: MissingInformation{}

def option_label(+key: Identity.Key, +label: String, description: Maybe<&2, String>, +icon: Maybe<&2, Controls.Icon>, selected: Bool, +visual: Design.Style, geometry: Controls.Geometry) -> Type:
  {option_text(AuthoredControls.face(key, Controls.ChoiceFace{label, description, icon, selected}, visual, geometry)) == required_information(key, Information.OptionLabel{}, label, visual) : InformationObservation}

def option_description(+key: Identity.Key, +value: String, +visual: Design.Style) -> Type:
  {first_information(AuthoredControls.face_description(Some{value}, key, visual)) == required_information(key, Information.Description{}, value, visual) : InformationObservation}

def group_title(+key: Identity.Key, +label: String, +role: SurfaceTypes.Role, +visual: Design.Style, representation: Controls.Representation, children: +List<Authored.Child>, parameters: Design.LayoutParameters, content: +List<Source.Node>) -> Type:
  {first_information(Source.children_of(Authored.regular_content(key, label, role, SurfaceTypes.ChoiceGroup{}, visual, representation, children, parameters, content))) == required_information(key, Information.GroupTitle{}, label, visual) : InformationObservation}

def panel_title(+key: Identity.Key, +label: String, dismiss: InteractionTypes.Input, outside: Bool, escape: Bool, +visual: Design.Style, representation: Controls.Representation, children: +List<Authored.Child>, parameters: Design.LayoutParameters, content: +List<Source.Node>) -> Type:
  {first_information(Source.children_of(Authored.regular_content(key, label, SurfaceTypes.Menu{}, SurfaceTypes.LayerRegion{dismiss, outside, escape}, visual, representation, children, parameters, content))) == required_information(key, Information.SurfaceTitle{}, label, visual) : InformationObservation}

def dialog_title(+key: Identity.Key, +label: String, +visual: Design.Style, children: +List<Authored.Child>) -> Type:
  {dialog_information(Authored.dialog_content(key, label, visual, children)) == required_information(key, Information.SurfaceTitle{}, label, visual) : InformationObservation}

def dialog_information(nodes: +List<Source.Node>) -> InformationObservation:
  match nodes:
    case Con{Source.Box{header_key, header_tag, header_style, header_attributes, [Source.Box{title_key, title_tag, title_style, title_attributes, title_children}]}, rest}: first_information(title_children)
    case _: MissingInformation{}

def visible_label_reference(+key: Identity.Key) -> Type:
  {AuthoredControls.label_attributes(Controls.AboveInput{}, key) == [Source.AriaAttribute{"labelledby", Identity.encode(Identity.part(key, "@information/field-label"))}] : +List<Source.Attribute>}

def option_reference(+key: Identity.Key, +label: String, +description: Maybe<&2, String>, icon: Maybe<&2, Controls.Icon>, selected: Bool) -> Type:
  {AuthoredControls.choice_association(Controls.ChoiceFace{label, description, icon, selected}, key) == required_option_reference(key, description) : +List<Source.Attribute>}

def required_option_reference(+key: Identity.Key, description: Maybe<&2, String>) -> +List<Source.Attribute>:
  match description:
    case None{}: [Source.AriaAttribute{"labelledby", Identity.encode(Identity.part(key, "@information/option-label"))}]
    case Some{text}: [Source.AriaAttribute{"labelledby", Identity.encode(Identity.part(key, "@information/option-label"))}, Source.AriaAttribute{"describedby", Identity.encode(Identity.part(key, "@information/description"))}]

def compound_label(+key: Identity.Key, +label: String, field: Forms.Field, +visual: Design.Style, children: +List<Source.Node>) -> Type:
  {first_information(Source.children_of(Authored.compound(key, label, field, visual, children))) == required_information(key, Information.FieldLabel{}, label, visual) : InformationObservation}

def heading_caption(key: Identity.Key, label: String, visual: Design.Style) -> Type:
  {first_information(Authored.caption(key, label, SurfaceTypes.Heading{}, visual)) == required_information(key, Information.SurfaceTitle{}, label, visual) : InformationObservation}

def lane_style(key: Identity.Key, label: String, stage: Board.Stage, count: Nat, visual: Design.Style, children: +List<Authored.Child>, parameters: Design.LayoutParameters) -> Type:
  {Authored.layout_of_lane(Authored.lane(key, label, stage, count, visual, children, parameters)) == Some{Factory.with_direction(Factory.style(visual, Model.LimitedSize{Design.lane_minimum_width(parameters), 0n, Design.lane_minimum_width(parameters)}, Model.StretchSize{}, Model.Confined{}), Model.Vertical{})} : Maybe<&2, Source.Style>}

def parameter_source(+capacity: Nat, scale: T.Scale, key: String, minimum: Nat, preferred: Nat, height: Nat, advance: Nat) -> Type:
  {Design.parameters(capacity, scale, T.Metric{key, minimum, preferred, height, advance}) == Design.parameter_values(NaturalSize.evaluate_all(capacity, Design.parameter_calculations(capacity, scale, height, advance))) : Maybe<&2, Design.LayoutParameters>}

def parameter_calculations(+capacity: Nat, +scale: T.Scale, height: Nat, +advance: Nat) -> Type:
  +leading: NaturalSize.Calculation = NaturalSize.Maximum{NaturalSize.Value{T.resolved_line_height(T.resolve(capacity, T.Body{}, T.Regular{}, scale))}, NaturalSize.Value{height}}
  +toolbar: NaturalSize.Calculation = NaturalSize.Maximum{T.scaling_calculation(46n, scale), NaturalSize.Sum{leading, T.scaling_calculation(26n, scale)}}
  +input_minimum: NaturalSize.Calculation = NaturalSize.Maximum{T.scaling_calculation(44n, scale), NaturalSize.Sum{leading, NaturalSize.Product{NaturalSize.Value{2n}, T.scaling_calculation(12n, scale)}}}
  balanced: NaturalSize.Calculation = NaturalSize.Sum{toolbar, NaturalSize.Product{NaturalSize.Value{2n},
    NaturalSize.Sum{NaturalSize.Value{T.resolved_line_height(T.resolve(capacity, T.Display{}, T.Regular{}, scale))},
      NaturalSize.Sum{input_minimum, NaturalSize.Sum{T.scaling_calculation(32n, scale), NaturalSize.Product{NaturalSize.Value{3n}, T.scaling_calculation(16n, scale)}}}}}}
  {Design.parameter_calculations(capacity, scale, height, advance) == [
    T.scaling_calculation(275n, scale),
    NaturalSize.Sum{NaturalSize.Product{NaturalSize.Value{advance}, NaturalSize.Value{40n}}, NaturalSize.Product{NaturalSize.Value{2n}, T.scaling_calculation(16n, scale)}},
    T.scaling_calculation(360n, scale),
    NaturalSize.Product{NaturalSize.Value{advance}, NaturalSize.Value{96n}},
    NaturalSize.Product{NaturalSize.Value{advance}, NaturalSize.Value{144n}},
    toolbar, input_minimum, NaturalSize.Maximum{T.scaling_calculation(240n, scale), input_minimum}, leading, balanced, NaturalSize.Sum{NaturalSize.Product{NaturalSize.Value{advance}, NaturalSize.Value{32n}}, NaturalSize.Product{NaturalSize.Value{2n}, T.scaling_calculation(Enclosure.inline(Enclosure.area(Enclosure.Lane{})), scale)}}] : +List<NaturalSize.Calculation>}

def page_region(key: Identity.Key, region: Composition.Region, position: Composition.Position, visual: Design.Style, control: Controls.Representation, children: +List<Authored.Child>, parameters: Design.LayoutParameters, content: +List<Source.Node>) -> Type:
  {Authored.regular_content(key, "", SurfaceTypes.Section{}, SurfaceTypes.PageRegion{region, position}, visual, control, children, parameters, content) == Authored.box(key, Source.Div{}, Authored.region_style(visual, region, position), [Source.DataAttribute{"page-position", Authored.position_name(position)}, Source.DataAttribute{"page-region", Composition.region_name(region)}], content) : Source.Node}

def board_group(key: Identity.Key, label: String, grouping: SurfaceTypes.BoardGrouping, visual: Design.Style, control: Controls.Representation, children: +List<Authored.Child>, parameters: Design.LayoutParameters, content: +List<Source.Node>) -> Type:
  {Authored.regular_content(key, label, SurfaceTypes.Toolbar{}, SurfaceTypes.BoardGroup{grouping}, visual, control, children, parameters, content) == Authored.box(key, Source.Div{}, Factory.with_direction(Factory.style(visual, Model.StretchSize{}, Model.StretchSize{}, Model.Confined{}), Model.Horizontal{}), [Source.DataAttribute{"board-group", Authored.board_group_name(grouping)}, Source.AriaAttribute{"label", Authored.board_group_label(grouping)}], content) : Source.Node}

def confined_content_minimum(width: Nat, height: Nat) -> Type:
  {Model.viewport_content_minimum(Enclosure.Extent{width, height}, Model.Confined{}) == Enclosure.Extent{width, height} : Enclosure.Extent}

def container_scroll(node: Source.Node) -> Model.Scroll:
  match node:
    case Source.Box{key, tag, Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states}, attributes, children}: scroll
    case _: Model.Confined{}

def board_group_content_minimum(key: Identity.Key, label: String, grouping: SurfaceTypes.BoardGrouping, visual: Design.Style, control: Controls.Representation, children: +List<Authored.Child>, parameters: Design.LayoutParameters, content: +List<Source.Node>, width: Nat, height: Nat) -> Type:
  {Model.viewport_content_minimum(Enclosure.Extent{width, height}, container_scroll(Authored.regular_content(key, label, SurfaceTypes.Toolbar{}, SurfaceTypes.BoardGroup{grouping}, visual, control, children, parameters, content))) == Enclosure.Extent{width, height} : Enclosure.Extent}

def card_regions(+key: Identity.Key, +face: View.CardFace, +visual: Design.Style, +children: +List<Authored.Child>, +representation: Controls.Representation, +parameters: Design.LayoutParameters, +movable: Bool) -> Type:
  View.CardFace{+id, +title, description, priority, pinned_value, +status, project, labels, owner, updated} = face
  {Authored.card(key, face, visual, children, representation, parameters, movable) ==
    Source.Control{key, Source.ArticleControl{}, Factory.style(visual, Model.StretchSize{}, Model.NaturalSize{}, Model.Confined{}), [Source.DataAttribute{"card-id", Nat.show(id)}, Source.DataAttribute{"card-title", title}, Source.DraggableAttribute{FieldOptions.boolean(movable)}], title, movable, Doc.DragCard{Identity.encode(key)}, [Doc.DropCard{Identity.encode(key)}],
    Authored.append(Authored.append(Authored.card_grip(representation, key, visual), [Authored.group(Identity.part(key, "@metadata"), visual, Model.ResponsiveHorizontal{}, Model.StretchSize{}, Model.NaturalSize{}, Authored.append([Authored.text(Identity.part(key, "@reference"), Board.identifier(id), visual, T.Support{}, T.Regular{}), Authored.text(Identity.part(key, "@priority"), Board.priority_label(priority), visual, T.Support{}, T.Regular{})], Authored.append(Authored.pinned(pinned_value, key, visual), Authored.optional_text(status, key, "status", visual)))),
      Authored.group(Identity.part(key, "@actions"), visual, Model.Horizontal{}, Model.StretchSize{}, Model.NaturalSize{}, [Authored.group(Identity.part(key, "@open"), visual, Model.Horizontal{}, Model.StretchSize{}, Model.NaturalSize{}, Authored.card_title(key, title, visual, Authored.card_actions(children, False{}))), Authored.group(Identity.part(key, "@more"), visual, Model.Horizontal{}, Model.NaturalSize{}, Model.NaturalSize{}, Authored.card_actions(children, True{}))])]),
      Authored.append(Authored.optional_text(description, key, "description", visual), Authored.append([Authored.group(Identity.part(key, "@context"), visual, Model.ResponsiveHorizontal{}, Model.StretchSize{}, Model.NaturalSize{}, Authored.append(Authored.optional_text(project, key, "project", visual), Authored.card_labels(labels, key, 0n, visual)))], [Authored.group(Identity.part(key, "@movement"), visual, Model.Vertical{}, Model.StretchSize{}, Model.NaturalSize{}, Authored.card_movement_nodes(children)), Authored.box(Identity.part(key, "@footer"), Source.Footer{}, Factory.content_style(visual, Model.Horizontal{}, Model.StretchSize{}, Model.NaturalSize{}, AuthoredControls.parent_gap(visual)), [Source.DataAttribute{"card-footer", ""}], Authored.append(Authored.optional_text(owner, key, "owner", visual), Authored.optional_text(updated, key, "updated", visual)))])))} : Source.Node}

def adaptive_user_width_choice(full_width: Bool, percent: Nat) -> Model.AxisSize:
  match full_width:
    case True{}: Model.NaturalSize{}
    case False{}: Model.AdaptiveNaturalSize{percent}

def adaptive_user_width(visual: Design.Style) -> Model.AxisSize:
  Design.Style{text, chrome, alignment, flow, overflow, frame, minimum_height, +percent, states} = visual
  adaptive_user_width_choice(Nat.is_eq(percent, 100n), percent)

def user_message_width(+visual: Design.Style) -> Type:
  {Authored.role_style(visual, SurfaceTypes.UserMessage{}) == Factory.style(visual, adaptive_user_width(visual), Model.NaturalSize{}, Model.Confined{}) : Source.Style}

law movement_field_has_own_identity:
  for +key: Identity.Key
  for +destinations: +List<SurfaceTypes.Placement>
  for face: View.CardFace
  for +name: String
  for handle: Controls.Icon
  for geometry: Controls.Geometry
  for +visual: Design.Style
  for parameters: Design.LayoutParameters
  {AuthoredControls.movable_choices(key, Controls.MovableControl{destinations, face, name, handle, geometry}, visual, parameters) ==
      Source.Field{key, Source.SelectField{}, Factory.style(visual, Model.StretchSize{}, Model.NaturalSize{}, Model.Confined{}), Factory.binding_attributes(key), "", "Move to…",
        Source.Choice{"", "Move to…", True{}} <> AuthoredControls.placement_choices(destinations), Source.FieldPolicy{1n, 1n, 1n}, name, InterfaceView.has_available_destination(destinations), Doc.SelectDestination{Identity.encode(key)}, Nil{}} : Source.Node}

law movement_child_is_authored:
  for key: Identity.Key
  for role: SurfaceTypes.Role
  for destinations: +List<SurfaceTypes.Placement>
  for face: View.CardFace
  for control: Controls.Representation
  for +nodes: +List<Source.Node>
  for rest: +List<Authored.Child>
  {Authored.card_movement_nodes(Authored.Child{key, role, SurfaceTypes.MovableCard{destinations, face}, control, nodes} <> rest) == nodes : +List<Source.Node>}

law card_source_dispatch:
  for +key: Identity.Key
  for label: String
  for role: SurfaceTypes.Role
  for +face: View.CardFace
  for +visual: Design.Style
  for +representation: Controls.Representation
  for +children: +List<Authored.Child>
  for +parameters: Design.LayoutParameters
  for content: +List<Source.Node>
  {Authored.regular_content(key, label, role, SurfaceTypes.CardContent{face}, visual, representation, children, parameters, content) ==
      Authored.card(key, face, visual, children, Authored.card_movement_control(children), parameters, Authored.card_movement_available(children)) : Source.Node}

law movement_source_dispatch:
  for +key: Identity.Key
  for label: String
  for role: SurfaceTypes.Role
  for destinations: +List<SurfaceTypes.Placement>
  for +face: View.CardFace
  for +visual: Design.Style
  for +representation: Controls.Representation
  for +children: +List<Authored.Child>
  for +parameters: Design.LayoutParameters
  for content: +List<Source.Node>
  {Authored.regular_content(key, label, role, SurfaceTypes.MovableCard{destinations, face}, visual, representation, children, parameters, content) == Authored.movable_source(key, representation, visual, parameters) : Source.Node}

def expected_fact_value(empty: Bool, value: String) -> String:
  match empty:
    case True{}: "—"
    case False{}: value

def fact_display_value(+value: String) -> Type:
  {Authored.fact_display_value(value) == expected_fact_value(String.eq(value, ""), value) : String}

def fact_content(+key: Identity.Key, +label: String, +value: String, +visual: Design.Style) -> Type:
  +displayed: String = expected_fact_value(String.eq(value, ""), value)
  {Authored.fact(key, label, value, visual) == Authored.group(key, visual, Model.Vertical{}, Model.StretchSize{}, Model.NaturalSize{}, [Authored.text(Identity.part(key, "label"), label, visual, T.Body{}, T.Strong{}), Authored.text(Identity.part(key, "value"), displayed, visual, T.Body{}, T.Regular{})]) : Source.Node}

def fact_source_dispatch(key: Identity.Key, label: String, role: SurfaceTypes.Role, value: String, visual: Design.Style, representation: Controls.Representation, children: +List<Authored.Child>, parameters: Design.LayoutParameters, content: +List<Source.Node>) -> Type:
  {Authored.regular_content(key, label, role, SurfaceTypes.Fact{value}, visual, representation, children, parameters, content) == Authored.fact(key, label, value, visual) : Source.Node}

def experience_source(+key: Identity.Key, +label: String, +role: SurfaceTypes.Role, +meaning: SurfaceTypes.Meaning, +visual: Design.Style, +representation: Controls.Representation, +children: +List<Authored.Child>, +parameters: Design.LayoutParameters, +content: +List<Source.Node>) -> Type:
  match meaning:
    case SurfaceTypes.DecisionGroup{decision}: {Authored.regular_content(key, label, role, meaning, visual, representation, children, parameters, content) == Authored.owned_group(key, UX.decision_question(decision), visual, Source.RoleAttribute{"radiogroup"} <> Authored.subject_attributes(UX.decision_subject(decision)), content) : Source.Node}
    case SurfaceTypes.ObjectGroup{object}: {Authored.regular_content(key, label, role, meaning, visual, representation, children, parameters, content) == Authored.object_group(key, object, label, visual, content) : Source.Node}
    case SurfaceTypes.WorkspaceCollection{collection}: {Authored.regular_content(key, label, role, meaning, visual, representation, children, parameters, content) == Authored.owned_group(key, label, visual, Source.TabIndexAttribute{"-1"} <> Authored.subject_attributes(UXTypes.Subject{UX.collection_editor(collection), Forms.WorkspaceDirectories{}}), content) : Source.Node}
    case SurfaceTypes.WorkspaceMember{collection, path}: {Authored.regular_content(key, label, role, meaning, visual, representation, children, parameters, content) == Authored.workspace_member(key, collection, path, visual, content) : Source.Node}
    case SurfaceTypes.ActionUnit{action}: {Authored.regular_content(key, label, role, meaning, visual, representation, children, parameters, content) == Authored.action_unit(key, action, visual, content) : Source.Node}
    case SurfaceTypes.SupportingControl{support, property, input, availability}: {Authored.regular_content(key, label, role, meaning, visual, representation, children, parameters, content) == Authored.supporting_control_visible(UX.support_visible(support), key, support, property, label, visual, representation) : Source.Node}
    case SurfaceTypes.ActionExplanation{assessment}: {Authored.regular_content(key, label, role, meaning, visual, representation, children, parameters, content) == Authored.action_explanation(key, assessment, visual) : Source.Node}
    case SurfaceTypes.ActionCommit{assessment, input, availability}: {Authored.regular_content(key, label, role, meaning, visual, representation, children, parameters, content) == Authored.add_attributes(Authored.button_source(key, visual, representation), [Source.DataAttribute{"action-owner", UX.action_key(UX.assessment_identity(assessment))}, Source.TitleAttribute{Controls.assessment_help(UX.assessment_obstructions(assessment))}]) : Source.Node}
    case SurfaceTypes.ActionFeedback{feedback}: {Authored.regular_content(key, label, role, meaning, visual, representation, children, parameters, content) == Authored.action_feedback(key, feedback, visual, content) : Source.Node}
    case _: {content == content : +List<Source.Node>}

def owned_group_source(+key: Identity.Key, +label: String, +visual: Design.Style, +attributes: +List<Source.Attribute>, +content: +List<Source.Node>) -> Type:
  {Authored.owned_group(key, label, visual, attributes, content) == Source.Box{key, Source.Section{}, Factory.with_frame(Factory.style(visual, Model.StretchSize{}, Model.NaturalSize{}, Model.Confined{}), Hierarchy.heading_frame(Hierarchy.initial())), Source.AriaAttribute{"labelledby", Identity.encode(AuthoredControls.information_key(key, Information.GroupTitle{}))} <> attributes,
    [AuthoredControls.owned_text(key, Information.GroupTitle{}, label, visual), Source.Box{Identity.part(key, "@members"), Source.Div{}, Factory.with_frame(Factory.style(visual, Model.StretchSize{}, Model.NaturalSize{}, Model.Confined{}), Hierarchy.member_frame(Hierarchy.initial())), Nil{}, content}]} : Source.Node}

def property_source(+editor: User.Editor, +field: Forms.Field, +key: Identity.Key, entry: Forms.Entry, observed: Forms.Observed, choices: +List<Forms.ChoiceValue>) -> Type:
  {AuthoredControls.field_metadata(key, SurfaceTypes.Edit{editor, field, entry, observed, choices}) == List.append(&2, Source.Attribute, [Source.DataAttribute{"field", Forms.key(field)}, Source.DataAttribute{"property", UX.subject_key(UXTypes.Subject{editor, field})}, Source.DataAttribute{"object-owner", UX.object_key(UX.owner(UXTypes.Subject{editor, field}))}], AuthoredControls.message_binding(field, key)) : +List<Source.Attribute>}

def subject_source(+subject: UXTypes.Subject) -> Type:
  UXTypes.Subject{editor, +field} = subject
  {Authored.subject_attributes(subject) == [Source.DataAttribute{"property", UX.subject_key(subject)}, Source.DataAttribute{"object-owner", UX.object_key(UX.owner(subject))}, Source.DataAttribute{"field", Forms.key(field)}] : +List<Source.Attribute>}

def selected_marker(+selected: Bool, +key: Identity.Key, +visual: Design.Style, +size: Nat) -> Type:
  match selected:
    case True{}: {AuthoredControls.selection(selected, key, visual, size) == [AuthoredControls.glyph(Identity.part(key, "check"), Controls.Check{}, visual, size)] : +List<Source.Node>}
    case False{}: {AuthoredControls.selection(selected, key, visual, size) == Nil{} : +List<Source.Node>}

def slot_emphasis(+scale: T.Scale) -> Type:
  {T.information_role(Information.GroupTitle{}, scale) == T.Presentation{T.Section{}, T.Strong{}, scale} : T.Presentation}

def member_source(+key: Identity.Key, +collection: UXTypes.Collection, +path: String, +visual: Design.Style, +content: +List<Source.Node>) -> Type:
  {Authored.workspace_member(key, collection, path, visual, content) == Authored.box(key, Source.Div{}, Factory.style(visual, Model.StretchSize{}, Model.NaturalSize{}, Model.Confined{}),
    List.append(&2, Source.Attribute, Authored.subject_attributes(Authored.collection_subject(collection)), [Source.AriaAttribute{"label", path}, Source.DataAttribute{"member", path}, Source.DataAttribute{"reference-property", UX.subject_key(UXTypes.Subject{UX.collection_editor(collection), Forms.WorkspacePrimary{}})}, Source.DataAttribute{"primary", FieldOptions.boolean(UX.is_primary(collection, path))}]),
    [Authored.box(Identity.part(key, "path"), Source.Span{}, Factory.content_style(visual, Model.Horizontal{}, Model.StretchSize{}, Model.NaturalSize{}, 0n), [Source.TitleAttribute{path}], [Authored.text(Identity.part(Identity.part(key, "path"), "text"), path, visual, T.Body{}, T.Regular{})]), Authored.group(Identity.part(key, "controls"), visual, Model.Horizontal{}, Model.NaturalSize{}, Model.NaturalSize{}, content)]) : Source.Node}

def action_source(+key: Identity.Key, +action: UXTypes.ActionUnit, +visual: Design.Style, +content: +List<Source.Node>) -> Type:
  {Authored.action_unit(key, action, visual, content) == Authored.box(key, Source.Section{}, Factory.style(visual, Model.StretchSize{}, Model.NaturalSize{}, Model.Confined{}),
    List.append(&2, Source.Attribute, [Source.DataAttribute{"action-owner", UX.action_key(UX.identity(action))}], List.append(&2, Source.Attribute, Authored.subject_attributes(UX.content_subject(action)), AuthoredControls.focus_attributes(AuthoredControls.AggregateFocus{}))), content) : Source.Node}

def feedback_source(+key: Identity.Key, +feedback: UXTypes.Feedback, +visual: Design.Style, +content: +List<Source.Node>) -> Type:
  UXTypes.Feedback{+editor, +revision, +reason} = feedback
  {Authored.action_feedback(key, feedback, visual, content) == Authored.box(key, Source.Div{}, Factory.style(visual, Model.StretchSize{}, Model.NaturalSize{}, Model.Confined{}), [Source.RoleAttribute{"alert"}, Source.DataAttribute{"action-owner", UX.action_key(UXTypes.ActionIdentity{editor, revision})}, Source.DataAttribute{"action-revision", Nat.show(revision)}, Source.DataAttribute{"action-reason", reason}], Authored.text(Identity.part(key, "text"), reason, visual, T.Body{}, T.Regular{}) <> content) : Source.Node}

def aggregate_focus(+visual: Design.Style) -> Type:
  Design.Style{+text, +chrome, +alignment, +flow, +overflow, +frame, +minimum, +maximum, +states} = visual
  {Appearance.action_unit_style(visual) == Design.Style{text, chrome, alignment, flow, overflow, Activity.frame(Activity.initial()), minimum, maximum, Appearance.action_focus_states(chrome, states)} : Design.Style}

def grouped_menu_source(+key: Identity.Key, +tag: Source.BoxTag, +style: Source.Style, +attributes: +List<Source.Attribute>, +content: +List<Source.Node>) -> Type:
  Source.Style{Source.Layout{direction, main, cross, +frame, width, height, minimum, scroll, position}, font, chrome, states} = style
  {Authored.grouped_menu_visible(SurfaceTypes.Menu{}, True{}, Source.Box{key, tag, style, attributes, content}) == Source.Box{key, tag, Factory.with_frame(style, Hierarchy.grouped_frame(Hierarchy.initial(), Enclosure.frame_content(frame))), attributes, content} : Source.Node}

def support_source(visible: Bool, +key: Identity.Key, +support: UXTypes.Support, +property: UXTypes.Property, +label: String, +visual: Design.Style, +representation: Controls.Representation) -> Type:
  match visible:
    case False{}: {Authored.supporting_control_visible(visible, key, support, property, label, visual, representation) == Source.Box{key, Source.Span{}, Factory.style(visual, Model.NaturalSize{}, Model.NaturalSize{}, Model.Confined{}), [Source.DataAttribute{"action-owner", UX.action_key(UX.support_identity(support))}], Nil{}} : Source.Node}
    case True{}: {Authored.supporting_control_visible(visible, key, support, property, label, visual, representation) == Authored.add_attributes(Authored.button_source(key, visual, representation), List.append(&2, Source.Attribute, [Source.DataAttribute{"action-owner", UX.action_key(UX.support_identity(support))}, Source.TitleAttribute{UX.property_help(property)}], List.append(&2, Source.Attribute, [Source.DataAttribute{"support-properties", Authored.support_property_keys(UX.support_subjects(support))}], [Source.DataAttribute{"object-owner", UX.object_key(UX.property_owner(property))}, Source.DataAttribute{"source-owner", UX.property_source_key(property)}]))) : Source.Node}

def typed_action_style(+key: Identity.Key, +action: UXTypes.ActionUnit, family: Controls.SourceFamily, representation: Controls.Representation, +visual: Design.Style, typography: T.Presentation) -> Type:
  {Appearance.family_style(key, SurfaceTypes.ActionUnit{action}, family, representation, visual, typography) == Appearance.action_unit_style(visual) : Design.Style}

def action_focus_states(+chrome: Design.Chrome, +states: Design.ControlStates) -> Type:
  Design.Chrome{+foreground, +background, +border, width, radius, shadow} = chrome
  match states:
    case Design.Passive{}: {Appearance.action_focus_states(chrome, states) == Design.Interactive{Design.PhasePaint{foreground, background}, Design.PhasePaint{foreground, background}, 40n, Design.FocusIndicator{border, 1n, 0n}} : Design.ControlStates}
    case Design.SurfaceFeedback{+hover, +pressed}: {Appearance.action_focus_states(chrome, states) == Design.Interactive{hover, pressed, 40n, Design.FocusIndicator{border, 1n, 0n}} : Design.ControlStates}
    case Design.Interactive{+hover, +pressed, +opacity, focus}: {Appearance.action_focus_states(chrome, states) == Design.Interactive{hover, pressed, opacity, Design.FocusIndicator{border, 1n, 0n}} : Design.ControlStates}

def rest_background(style: Design.Style) -> Design.Paint:
  Design.Style{text, Design.Chrome{foreground, background, border, width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = style
  background

def style_states(style: Design.Style) -> Design.ControlStates:
  Design.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = style
  states

def alternative_rest(+typography: T.Presentation) -> Type:
  {rest_background(Appearance.alternative_button(True{}, typography)) == Design.Transparent{} : Design.Paint}

def alternative_states(+typography: T.Presentation) -> Type:
  {style_states(Appearance.alternative_button(True{}, typography)) == style_states(Appearance.choice_button(True{}, typography)) : Design.ControlStates}

def object_source(+key: Identity.Key, +object: UXTypes.Object, +label: String, +visual: Design.Style, +content: +List<Source.Node>) -> Type:
  {Authored.object_group(key, object, label, visual, content) == Source.Box{key, Source.Section{}, Factory.with_frame(Factory.style(visual, Model.StretchSize{}, Model.NaturalSize{}, Model.Confined{}), Hierarchy.heading_frame(Hierarchy.initial())), [Source.AriaAttribute{"labelledby", Identity.encode(AuthoredControls.information_key(key, Information.GroupTitle{}))}, Source.DataAttribute{"object-owner", UX.object_key(object)}],
    [AuthoredControls.owned_text(key, Information.GroupTitle{}, label, visual), Source.Box{Identity.part(key, "@members"), Source.Div{}, Factory.with_frame(Factory.style(visual, Model.StretchSize{}, Model.NaturalSize{}, Model.Confined{}), Hierarchy.grouped_frame(Hierarchy.initial(), Enclosure.frame_content(Hierarchy.member_frame(Hierarchy.initial())))), Nil{}, content}]} : Source.Node}

def compound_directory_source(+field: Forms.Field, +value: Forms.Observed, +key: Identity.Key, +label: String, +visual: Design.Style, +children: +List<Source.Node>) -> Type:
  match field value:
    case Forms.WorkspaceDirectories{} Forms.WorkspaceValue{workspace}: {Authored.compound_directory(field, value, key, label, visual, children) == Source.Box{key, Source.Section{}, Factory.style(visual, Model.StretchSize{}, Model.NaturalSize{}, Model.Confined{}), [Source.AriaAttribute{"label", label}, Source.DataAttribute{"field", Forms.key(field)}, Source.TabIndexAttribute{"-1"}], children} : Source.Node}
    case Forms.WorkspaceDirectories{} Forms.ContextValue{Workspace.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}}: {Authored.compound_directory(field, value, key, label, visual, children) == Source.Box{key, Source.Section{}, Factory.style(visual, Model.StretchSize{}, Model.NaturalSize{}, Model.Confined{}), [Source.AriaAttribute{"label", label}, Source.DataAttribute{"field", Forms.key(field)}, Source.TabIndexAttribute{"-1"}], children} : Source.Node}
    case _ _: {Authored.compound_directory(field, value, key, label, visual, children) == Authored.compound(key, label, field, visual, children) : Source.Node}

def directory_source(+editor: User.Editor, +field: Forms.Field, value: Forms.Observed, choices: +List<Forms.ChoiceValue>, +key: Identity.Key, label: String, role: SurfaceTypes.Role, visual: Design.Style, representation: Controls.Representation, children: +List<Authored.Child>, parameters: Design.LayoutParameters, content: +List<Source.Node>) -> Type:
  {Authored.regular_content(key, label, role, SurfaceTypes.Edit{editor, field, Forms.DirectoryCollection{}, value, choices}, visual, representation, children, parameters, content) == Authored.add_attributes(Authored.compound_directory(field, value, key, label, visual, content), [Source.DataAttribute{"property", UX.subject_key(UXTypes.Subject{editor, field})}, Source.DataAttribute{"object-owner", UX.object_key(UX.owner(UXTypes.Subject{editor, field}))}]) : Source.Node}

type Requirements is Type:
  Requirements{
    compound_directory_source: @+field:Forms.Field -> @+value:Forms.Observed -> @+key:Identity.Key -> @+label:String -> @+visual:Design.Style -> @+children:+List<Source.Node> -> compound_directory_source(field, value, key, label, visual, children),
    directory_source: @+editor:User.Editor -> @+field:Forms.Field -> @value:Forms.Observed -> @choices:+List<Forms.ChoiceValue> -> @+key:Identity.Key -> @label:String -> @role:SurfaceTypes.Role -> @visual:Design.Style -> @representation:Controls.Representation -> @children:+List<Authored.Child> -> @parameters:Design.LayoutParameters -> @content:+List<Source.Node> -> directory_source(editor, field, value, choices, key, label, role, visual, representation, children, parameters, content),
    object_source: @+key:Identity.Key -> @+object:UXTypes.Object -> @+label:String -> @+visual:Design.Style -> @+content:+List<Source.Node> -> object_source(key, object, label, visual, content),
    support_source: @visible:Bool -> @+key:Identity.Key -> @+support:UXTypes.Support -> @+property:UXTypes.Property -> @+label:String -> @+visual:Design.Style -> @+representation:Controls.Representation -> support_source(visible, key, support, property, label, visual, representation),
    typed_action_style: @+key:Identity.Key -> @+action:UXTypes.ActionUnit -> @family:Controls.SourceFamily -> @representation:Controls.Representation -> @+visual:Design.Style -> @typography:T.Presentation -> typed_action_style(key, action, family, representation, visual, typography),
    action_focus_states: @+chrome:Design.Chrome -> @+states:Design.ControlStates -> action_focus_states(chrome, states),
    alternative_rest: @+typography:T.Presentation -> alternative_rest(typography),
    alternative_states: @+typography:T.Presentation -> alternative_states(typography),
    member_source: @+key: Identity.Key -> @+collection: UXTypes.Collection -> @+path: String -> @+visual: Design.Style -> @+content: +List<Source.Node> -> member_source(key, collection, path, visual, content),
    action_source: @+key: Identity.Key -> @+action: UXTypes.ActionUnit -> @+visual: Design.Style -> @+content: +List<Source.Node> -> action_source(key, action, visual, content),
    feedback_source: @+key: Identity.Key -> @+feedback: UXTypes.Feedback -> @+visual: Design.Style -> @+content: +List<Source.Node> -> feedback_source(key, feedback, visual, content),
    aggregate_focus: @+visual:Design.Style -> aggregate_focus(visual),
    grouped_menu_source: @+key:Identity.Key -> @+tag:Source.BoxTag -> @+style:Source.Style -> @+attributes:+List<Source.Attribute> -> @+content:+List<Source.Node> -> grouped_menu_source(key, tag, style, attributes, content),
    experience_source: @+key:Identity.Key -> @+label:String -> @+role:SurfaceTypes.Role -> @+meaning:SurfaceTypes.Meaning -> @+visual:Design.Style -> @+representation:Controls.Representation -> @+children:+List<Authored.Child> -> @+parameters:Design.LayoutParameters -> @+content:+List<Source.Node> -> experience_source(key, label, role, meaning, visual, representation, children, parameters, content),
    owned_group_source: @+key:Identity.Key -> @+label:String -> @+visual:Design.Style -> @+attributes:+List<Source.Attribute> -> @+content:+List<Source.Node> -> owned_group_source(key, label, visual, attributes, content),
    property_source: @+editor:User.Editor -> @+field:Forms.Field -> @+key:Identity.Key -> @entry:Forms.Entry -> @observed:Forms.Observed -> @choices:+List<Forms.ChoiceValue> -> property_source(editor, field, key, entry, observed, choices),
    subject_source: @+subject:UXTypes.Subject -> subject_source(subject),
    selected_marker: @+selected:Bool -> @+key:Identity.Key -> @+visual:Design.Style -> @+size:Nat -> selected_marker(selected, key, visual, size),
    slot_emphasis: @+scale:T.Scale -> slot_emphasis(scale),
    owned_alignment: @+owner:Identity.Key -> @+role:Information.TextRole -> @value:String -> @visual:Design.Style -> owned_alignment(owner, role, value, visual),
    owned_width: @owner:Identity.Key -> @role:Information.TextRole -> @value:String -> @visual:Design.Style -> {information_width(AuthoredControls.owned_text(owner, role, value, visual)) == Some{Model.StretchSize{}} : Maybe<&2, Model.AxisSize>},
    owned_foreground: @+owner:Identity.Key -> @+role:Information.TextRole -> @value:String -> @+visual:Design.Style -> owned_foreground(owner, role, value, visual),
    id_property: @+value:String -> {Source.attribute_properties(Source.IdAttribute{value}) == [Doc.Property{"id", value}] : +List<Doc.Property>},
    owned_information: @+owner:Identity.Key -> @+role:Information.TextRole -> @+value:String -> @+visual:Design.Style -> owned_information(owner, role, value, visual),
    scalar_information: @+key:Identity.Key -> @+label:String -> @+role:SurfaceTypes.Role -> @+text_role:Information.TextRole -> @+visual:Design.Style -> @representation:Controls.Representation -> @children:+List<Authored.Child> -> @parameters:Design.LayoutParameters -> @content:+List<Source.Node> -> scalar_information(key, label, role, text_role, visual, representation, children, parameters, content),
    field_label: @+key:Identity.Key -> @+label:String -> @+visual:Design.Style -> @field:Source.Node -> field_label(key, label, visual, field),
    option_label: @+key:Identity.Key -> @+label:String -> @description:Maybe<&2, String> -> @+icon:Maybe<&2, Controls.Icon> -> @selected:Bool -> @+visual:Design.Style -> @geometry:Controls.Geometry -> option_label(key, label, description, icon, selected, visual, geometry),
    option_description: @+key:Identity.Key -> @+value:String -> @+visual:Design.Style -> option_description(key, value, visual),
    group_title: @+key:Identity.Key -> @+label:String -> @+role:SurfaceTypes.Role -> @+visual:Design.Style -> @representation:Controls.Representation -> @children:+List<Authored.Child> -> @parameters:Design.LayoutParameters -> @content:+List<Source.Node> -> group_title(key, label, role, visual, representation, children, parameters, content),
    panel_title: @+key:Identity.Key -> @+label:String -> @dismiss:InteractionTypes.Input -> @outside:Bool -> @escape:Bool -> @+visual:Design.Style -> @representation:Controls.Representation -> @children:+List<Authored.Child> -> @parameters:Design.LayoutParameters -> @content:+List<Source.Node> -> panel_title(key, label, dismiss, outside, escape, visual, representation, children, parameters, content),
    dialog_title: @+key:Identity.Key -> @+label:String -> @+visual:Design.Style -> @children:+List<Authored.Child> -> dialog_title(key, label, visual, children),
    visible_label_reference: @+key:Identity.Key -> visible_label_reference(key),
    option_reference: @+key:Identity.Key -> @+label:String -> @+description:Maybe<&2, String> -> @icon:Maybe<&2, Controls.Icon> -> @selected:Bool -> option_reference(key, label, description, icon, selected),
    compound_label: @+key:Identity.Key -> @+label:String -> @field:Forms.Field -> @+visual:Design.Style -> @children:+List<Source.Node> -> compound_label(key, label, field, visual, children),
    choice_group_scope: @role:SurfaceTypes.Role -> @area:Controls.Area -> {Controls.area_for_node(role, SurfaceTypes.ChoiceGroup{}, area) == Controls.ChoiceGroupArea{} : Controls.Area},
    choice_group_radio: @selected:Bool -> {AuthoredControls.behavior(Controls.choice_behavior(SurfaceTypes.SingleChoice{}, Controls.ChoiceGroupArea{}, selected)) == [Source.RoleAttribute{"radio"}, Source.AriaAttribute{"checked", FieldOptions.boolean(selected)}] : +List<Source.Attribute>},
    user_width_policy: @+visual:Design.Style -> {Factory.adaptive_natural_width(visual) == adaptive_user_width(visual) : Model.AxisSize},
    user_message_width: @+visual:Design.Style -> user_message_width(visual),
    fact_display_value: @+value:String -> fact_display_value(value),
    fact_content: @+key:Identity.Key -> @+label:String -> @+value:String -> @+visual:Design.Style -> fact_content(key, label, value, visual),
    fact_source_dispatch: @key:Identity.Key -> @label:String -> @role:SurfaceTypes.Role -> @value:String -> @visual:Design.Style -> @representation:Controls.Representation -> @children:+List<Authored.Child> -> @parameters:Design.LayoutParameters -> @content:+List<Source.Node> -> fact_source_dispatch(key, label, role, value, visual, representation, children, parameters, content),
    native_field_footprint: @+kind:Source.NativeFieldKind -> @+style:Source.ResolvedStyle -> native_field_footprint(kind, style),
    card_regions: @+key:Identity.Key -> @+face:View.CardFace -> @+visual:Design.Style -> @+children:+List<Authored.Child> -> @+representation:Controls.Representation -> @+parameters:Design.LayoutParameters -> @+movable:Bool -> card_regions(key, face, visual, children, representation, parameters, movable),
    board_group_content_minimum: @key:Identity.Key -> @label:String -> @grouping:SurfaceTypes.BoardGrouping -> @visual:Design.Style -> @control:Controls.Representation -> @children:+List<Authored.Child> -> @parameters:Design.LayoutParameters -> @content:+List<Source.Node> -> @width:Nat -> @height:Nat -> board_group_content_minimum(key, label, grouping, visual, control, children, parameters, content, width, height),
    board_group: @key:Identity.Key -> @label:String -> @grouping:SurfaceTypes.BoardGrouping -> @visual:Design.Style -> @control:Controls.Representation -> @children:+List<Authored.Child> -> @parameters:Design.LayoutParameters -> @content:+List<Source.Node> -> board_group(key, label, grouping, visual, control, children, parameters, content),
    confined_content_minimum: @width:Nat -> @height:Nat -> confined_content_minimum(width, height),
    page_region: @key:Identity.Key -> @region:Composition.Region -> @position:Composition.Position -> @visual:Design.Style -> @control:Controls.Representation -> @children:+List<Authored.Child> -> @parameters:Design.LayoutParameters -> @content:+List<Source.Node> -> page_region(key, region, position, visual, control, children, parameters, content),
    parameter_calculations: @+capacity:Nat -> @+scale:T.Scale -> @height:Nat -> @+advance:Nat -> parameter_calculations(capacity, scale, height, advance),
    board_controls: @visual:Design.Style -> @position:Composition.Position -> board_controls(visual, position),
    board_stages: @visual:Design.Style -> @position:Composition.Position -> board_stages(visual, position),
    heading_caption: @key:Identity.Key -> @label:String -> @visual:Design.Style -> heading_caption(key, label, visual),
    lane_style: @key:Identity.Key -> @label:String -> @stage:Board.Stage -> @count:Nat -> @visual:Design.Style -> @children:+List<Authored.Child> -> @parameters:Design.LayoutParameters -> lane_style(key, label, stage, count, visual, children, parameters),
    parameter_source: @+capacity:Nat -> @scale:T.Scale -> @key:String -> @minimum:Nat -> @preferred:Nat -> @height:Nat -> @advance:Nat -> parameter_source(capacity, scale, key, minimum, preferred, height, advance),
    position_of_actual_rule: @+style:Source.Style -> @parent:T.Presentation -> position_is_authored(style, parent),
    border_of_actual_rule: @+style:Source.Style -> @parent:T.Presentation -> border_is_chrome(style, parent),
    font_resolution: @choice:Source.FontChoice -> @+parent:T.Presentation -> inherited_font(choice, parent),
    event_ownership: @+node:Source.Node -> operation_is_structurally_present(node),
    bounded_policy_factory: @columns_extra:Nat -> @+lines_extra:Nat -> @additional_lines:Nat ->
      field_policy_is_bounded(Source.field_policy(columns_extra, lines_extra, additional_lines))}

law evidence:
  Requirements
