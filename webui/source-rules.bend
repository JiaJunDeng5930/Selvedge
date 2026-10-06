import ./controls.bend as Controls
import ./authored.bend as Authored
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

type Requirements is Type:
  Requirements{
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
