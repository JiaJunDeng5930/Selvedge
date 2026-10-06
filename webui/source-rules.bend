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

type Requirements is Type:
  Requirements{
    position_of_actual_rule: @+style:Source.Style -> @parent:T.Presentation -> position_is_authored(style, parent),
    border_of_actual_rule: @+style:Source.Style -> @parent:T.Presentation -> border_is_chrome(style, parent),
    font_resolution: @choice:Source.FontChoice -> @+parent:T.Presentation -> inherited_font(choice, parent),
    event_ownership: @+node:Source.Node -> operation_is_structurally_present(node),
    bounded_policy_factory: @columns_extra:Nat -> @+lines_extra:Nat -> @additional_lines:Nat ->
      field_policy_is_bounded(Source.field_policy(columns_extra, lines_extra, additional_lines))}

law evidence:
  Requirements
