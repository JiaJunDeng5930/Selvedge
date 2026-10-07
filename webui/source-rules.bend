import ./controls.bend as Controls
import ./authored.bend as Authored
import ./authored-controls.bend as AuthoredControls
import ../core/ui-world.bend as View
import ../core/field-options.bend as FieldOptions
import ./authored-primitives.bend as Factory
import ./appearance.bend as Appearance
import ./natural-size.bend as NaturalSize
import ../core/interface.bend as UI
import ../core/composition.bend as Composition
import ../core/ui-identity.bend as Identity
import ../BOARD.bend as Board
import Base
import ./source.bend as Source
import ./physical-space.bend as Model
import ./typography.bend as T
import ./design.bend as Design
import ./document.bend as Doc
import ./enclosure.bend as Enclosure
import ./spatial.bend as Spatial

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
      {Source.events_of(node) == first_event <> remaining_events : +List<Doc.Event>}
    case Source.Field{key, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, +first_event, +remaining_events}:
      {Source.events_of(node) == first_event <> remaining_events : +List<Doc.Event>}
    case Source.Box{key, tag, style, attributes, children}:
      {Source.events_of(node) == Nil{} : +List<Doc.Event>}
    case Source.Text{key, value, font, wrapping}:
      {Source.events_of(node) == Nil{} : +List<Doc.Event>}
    case Source.Glyph{key, drawing, style}:
      {Source.events_of(node) == Nil{} : +List<Doc.Event>}
    case Source.NativeAttachment{key, target, attributes, style, children}:
      {Source.events_of(node) == Nil{} : +List<Doc.Event>}
    case Source.RichText{key, style, content, attachments, native_owner}:
      {Source.events_of(node) == Nil{} : +List<Doc.Event>}

# Native code geometry belongs to its rich-content policy. A body policy may
# change presentation only; unsupported independent layout must be rejected.
def native_code_direction_valid(direction: Model.Direction) -> Bool:
  match direction:
    case Model.Horizontal{}: False{}
    case Model.Vertical{}: True{}
    case Model.Layered{}: False{}
    case Model.ResponsiveHorizontal{}: False{}

def native_code_alignment_valid(alignment: Spatial.Alignment) -> Bool:
  match alignment:
    case Spatial.Stretch{}: False{}
    case Spatial.Leading{}: True{}
    case Spatial.Trailing{}: False{}
    case Spatial.Centered{}: False{}

def native_code_size_valid(size: Model.AxisSize) -> Bool:
  match size:
    case Model.NaturalSize{}: True{}
    case Model.StretchSize{}: False{}
    case Model.CappedStretchSize{maximum}: False{}
    case Model.ExactSize{extent}: False{}
    case Model.LimitedSize{minimum, preferred_extra, maximum_extra}: False{}
    case Model.PercentSize{percent}: False{}
    case Model.CappedNaturalSize{maximum_percent}: False{}
    case Model.AdaptiveNaturalSize{preferred_maximum_percent}: False{}

def native_code_scroll_valid(scroll: Model.Scroll) -> Bool:
  match scroll:
    case Model.Confined{}: True{}
    case Model.ScrollHorizontally{}: False{}
    case Model.ScrollVertically{}: False{}
    case Model.ScrollBoth{}: False{}

def native_code_position_valid(position: Spatial.Position) -> Bool:
  match position:
    case Spatial.InFlow{}: True{}
    case Spatial.CenteredLayer{outside}: False{}
    case Spatial.AlignedLayer{outside, horizontal, vertical}: False{}
    case Spatial.AnchoredLayer{anchor_key, anchor, outside, gap, alignment}: False{}

def native_code_layout_valid(layout: Source.Layout) -> Bool:
  Source.Layout{direction, main_alignment, cross_alignment, +frame, width, height,
    Enclosure.Extent{minimum_width, minimum_height}, scroll, position} = layout
  native_code_direction_valid(direction)
    && native_code_alignment_valid(main_alignment) && native_code_alignment_valid(cross_alignment)
    && native_code_size_valid(width) && native_code_size_valid(height)
    && Nat.is_eq(minimum_width, 0n) && Nat.is_eq(minimum_height, 0n)
    && native_code_scroll_valid(scroll) && native_code_position_valid(position)
    && Nat.is_eq(Enclosure.inline(Enclosure.frame_content(frame)), 0n)
    && Nat.is_eq(Enclosure.block(Enclosure.frame_content(frame)), 0n)
    && Nat.is_eq(Enclosure.frame_gap(frame), 0n)

def native_code_chrome_valid(chrome: Design.Chrome) -> Bool:
  Design.Chrome{foreground, background, border, border_width, radius, shadow} = chrome
  Nat.is_eq(border_width, 0n)

def native_code_policy_valid(style: Source.ResolvedStyle) -> Bool:
  Source.ResolvedStyle{layout, font, chrome, states} = style
  native_code_layout_valid(layout) && native_code_chrome_valid(chrome)

def board_controls(visual: Design.Style, position: Composition.Position) -> Type:
  {Authored.region_style(visual, Composition.BoardControls{}, position) == Factory.with_direction(Factory.style(Appearance.with_arrangement(visual, Enclosure.SeparateFrames{Enclosure.ComposerControls{}}), Model.StretchSize{}, Model.NaturalSize{}, Model.Confined{}), Model.ResponsiveHorizontal{}) : Source.Style}

def board_stages(visual: Design.Style, position: Composition.Position) -> Type:
  {Authored.region_style(visual, Composition.BoardStages{}, position) == Factory.with_direction(Factory.style(Appearance.with_arrangement(visual, Enclosure.SeparateFrames{Enclosure.BoardColumns{}}), Model.StretchSize{}, Model.StretchSize{}, Model.ScrollHorizontally{}), Model.Horizontal{}) : Source.Style}

def heading_caption(key: Identity.Key, label: String, visual: Design.Style) -> Type:
  {Authored.caption(key, label, UI.Heading{}, visual) == [Factory.text(Identity.part(key, "@title"), label, Source.ExplicitFont{Design.style_text(visual)}, T.NormalAnywhere{})] : +List<Source.Node>}

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
    NaturalSize.Sum{NaturalSize.Product{NaturalSize.Value{advance}, NaturalSize.Value{64n}}, NaturalSize.Product{NaturalSize.Value{2n}, T.scaling_calculation(16n, scale)}},
    T.scaling_calculation(360n, scale),
    NaturalSize.Product{NaturalSize.Value{advance}, NaturalSize.Value{96n}},
    NaturalSize.Product{NaturalSize.Value{advance}, NaturalSize.Value{144n}},
    toolbar, input_minimum, NaturalSize.Maximum{T.scaling_calculation(240n, scale), input_minimum}, leading, balanced, NaturalSize.Sum{NaturalSize.Product{NaturalSize.Value{advance}, NaturalSize.Value{32n}}, NaturalSize.Product{NaturalSize.Value{2n}, T.scaling_calculation(Enclosure.inline(Enclosure.area(Enclosure.Lane{})), scale)}}] : +List<NaturalSize.Calculation>}

def page_region(key: Identity.Key, region: Composition.Region, position: Composition.Position, visual: Design.Style, control: Controls.Representation, children: +List<Authored.Child>, parameters: Design.LayoutParameters, content: +List<Source.Node>) -> Type:
  {Authored.regular_content(key, "", UI.Section{}, UI.PageRegion{region, position}, visual, control, children, parameters, content) == Authored.box(key, Source.Div{}, Authored.region_style(visual, region, position), [Source.DataAttribute{"page-position", Authored.position_name(position)}, Source.DataAttribute{"page-region", Composition.region_name(region)}], content) : Source.Node}

def board_group(key: Identity.Key, label: String, grouping: UI.BoardGrouping, visual: Design.Style, control: Controls.Representation, children: +List<Authored.Child>, parameters: Design.LayoutParameters, content: +List<Source.Node>) -> Type:
  {Authored.regular_content(key, label, UI.Toolbar{}, UI.BoardGroup{grouping}, visual, control, children, parameters, content) == Authored.box(key, Source.Div{}, Factory.with_direction(Factory.style(visual, Model.StretchSize{}, Model.StretchSize{}, Model.Confined{}), Model.Horizontal{}), [Source.DataAttribute{"board-group", Authored.board_group_name(grouping)}, Source.AriaAttribute{"label", Authored.board_group_label(grouping)}], content) : Source.Node}

def confined_content_minimum(width: Nat, height: Nat) -> Type:
  {Model.viewport_content_minimum(Enclosure.Extent{width, height}, Model.Confined{}) == Enclosure.Extent{width, height} : Enclosure.Extent}

def container_scroll(node: Source.Node) -> Model.Scroll:
  match node:
    case Source.Box{key, tag, Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states}, attributes, children}: scroll
    case _: Model.Confined{}

def board_group_content_minimum(key: Identity.Key, label: String, grouping: UI.BoardGrouping, visual: Design.Style, control: Controls.Representation, children: +List<Authored.Child>, parameters: Design.LayoutParameters, content: +List<Source.Node>, width: Nat, height: Nat) -> Type:
  {Model.viewport_content_minimum(Enclosure.Extent{width, height}, container_scroll(Authored.regular_content(key, label, UI.Toolbar{}, UI.BoardGroup{grouping}, visual, control, children, parameters, content))) == Enclosure.Extent{width, height} : Enclosure.Extent}

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
  {Authored.role_style(visual, UI.UserMessage{}) == Factory.style(visual, adaptive_user_width(visual), Model.NaturalSize{}, Model.Confined{}) : Source.Style}

type Requirements is Type:
  Requirements{
    user_width_policy: @+visual:Design.Style -> {Factory.adaptive_natural_width(visual) == adaptive_user_width(visual) : Model.AxisSize},
    user_message_width: @+visual:Design.Style -> user_message_width(visual),
    fact_display_value: @+value:String -> fact_display_value(value),
    fact_content: @+key:Identity.Key -> @+label:String -> @+value:String -> @+visual:Design.Style -> fact_content(key, label, value, visual),
    fact_source_dispatch: @key:Identity.Key -> @label:String -> @role:UI.Role -> @value:String -> @visual:Design.Style -> @representation:Controls.Representation -> @children:+List<Authored.Child> -> @parameters:Design.LayoutParameters -> @content:+List<Source.Node> -> fact_source_dispatch(key, label, role, value, visual, representation, children, parameters, content),
    native_field_footprint: @+kind:Source.NativeFieldKind -> @+style:Source.ResolvedStyle -> native_field_footprint(kind, style),
    card_regions: @+key:Identity.Key -> @+face:View.CardFace -> @+visual:Design.Style -> @+children:+List<Authored.Child> -> @+representation:Controls.Representation -> @+parameters:Design.LayoutParameters -> @+movable:Bool -> card_regions(key, face, visual, children, representation, parameters, movable),
    board_group_content_minimum: @key:Identity.Key -> @label:String -> @grouping:UI.BoardGrouping -> @visual:Design.Style -> @control:Controls.Representation -> @children:+List<Authored.Child> -> @parameters:Design.LayoutParameters -> @content:+List<Source.Node> -> @width:Nat -> @height:Nat -> board_group_content_minimum(key, label, grouping, visual, control, children, parameters, content, width, height),
    board_group: @key:Identity.Key -> @label:String -> @grouping:UI.BoardGrouping -> @visual:Design.Style -> @control:Controls.Representation -> @children:+List<Authored.Child> -> @parameters:Design.LayoutParameters -> @content:+List<Source.Node> -> board_group(key, label, grouping, visual, control, children, parameters, content),
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

law movement_field_has_own_identity:
  for +key: Identity.Key
  for +destinations: +List<UI.Placement>
  for face: View.CardFace
  for +name: String
  for handle: Controls.Icon
  for geometry: Controls.Geometry
  for help: Controls.Help
  for +visual: Design.Style
  for parameters: Design.LayoutParameters
  {AuthoredControls.movable_choices(key, Controls.Movable{destinations, face, name, handle, geometry, help}, visual, parameters) ==
      Source.Field{key, Source.SelectField{}, Factory.style(visual, Model.StretchSize{}, Model.NaturalSize{}, Model.Confined{}), Factory.binding_attributes(key), "", "Move to…",
        Source.Choice{"", "Move to…", True{}} <> AuthoredControls.placement_choices(destinations), Source.FieldPolicy{1n, 1n, 1n}, name, UI.has_available_destination(destinations), Doc.SelectDestination{Identity.encode(key)}, Nil{}} : Source.Node}

law movement_child_is_authored:
  for key: Identity.Key
  for role: UI.Role
  for destinations: +List<UI.Placement>
  for face: View.CardFace
  for control: Controls.Representation
  for +nodes: +List<Source.Node>
  for rest: +List<Authored.Child>
  {Authored.card_movement_nodes(Authored.Child{key, role, UI.MovableCard{destinations, face}, control, nodes} <> rest) == nodes : +List<Source.Node>}

law card_source_dispatch:
  for +key: Identity.Key
  for label: String
  for role: UI.Role
  for +face: View.CardFace
  for +visual: Design.Style
  for +representation: Controls.Representation
  for +children: +List<Authored.Child>
  for +parameters: Design.LayoutParameters
  for content: +List<Source.Node>
  {Authored.regular_content(key, label, role, UI.CardContent{face}, visual, representation, children, parameters, content) ==
      Authored.card(key, face, visual, children, Authored.card_movement_control(children), parameters, Authored.card_movement_available(children)) : Source.Node}

law movement_source_dispatch:
  for +key: Identity.Key
  for label: String
  for role: UI.Role
  for destinations: +List<UI.Placement>
  for +face: View.CardFace
  for +visual: Design.Style
  for +representation: Controls.Representation
  for +children: +List<Authored.Child>
  for +parameters: Design.LayoutParameters
  for content: +List<Source.Node>
  {Authored.regular_content(key, label, role, UI.MovableCard{destinations, face}, visual, representation, children, parameters, content) == AuthoredControls.movable_choices(key, representation, visual, parameters) : Source.Node}


def expected_fact_value(empty: Bool, value: String) -> String:
  match empty:
    case True{}: "—"
    case False{}: value

def fact_display_value(+value: String) -> Type:
  {Authored.fact_display_value(value) == expected_fact_value(String.eq(value, ""), value) : String}

def fact_content(+key: Identity.Key, +label: String, +value: String, +visual: Design.Style) -> Type:
  +displayed: String = expected_fact_value(String.eq(value, ""), value)
  {Authored.fact(key, label, value, visual) == Authored.group(key, visual, Model.Vertical{}, Model.StretchSize{}, Model.NaturalSize{}, [Authored.text(Identity.part(key, "label"), label, visual, T.Body{}, T.Strong{}), Authored.text(Identity.part(key, "value"), displayed, visual, T.Body{}, T.Regular{})]) : Source.Node}

def fact_source_dispatch(key: Identity.Key, label: String, role: UI.Role, value: String, visual: Design.Style, representation: Controls.Representation, children: +List<Authored.Child>, parameters: Design.LayoutParameters, content: +List<Source.Node>) -> Type:
  {Authored.regular_content(key, label, role, UI.Fact{value}, visual, representation, children, parameters, content) == Authored.fact(key, label, value, visual) : Source.Node}
