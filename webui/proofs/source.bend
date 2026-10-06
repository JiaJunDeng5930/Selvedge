import ../controls.bend as Controls
import ../authored.bend as Authored
import ../physical-space.bend as Model
import ../enclosure.bend as Enclosure
import ../../core/interface.bend as UI
import ../../core/composition.bend as Composition
import ../../core/ui-identity.bend as Identity
import ../../BOARD.bend as Board
import Base
import ../source.bend as Source
import ../source-rules.bend as Rule
import ../typography.bend as T
import ../design.bend as Design
import ./space.bend as Arithmetic

def position_of_actual_rule(+style: Source.Style, parent: T.Presentation) -> Rule.position_is_authored(style, parent):
  match style:
    case Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font,
      Design.Chrome{foreground, background, border, border_width, radius, shadow}, states}:
      {==}

def border_of_actual_rule(+style: Source.Style, parent: T.Presentation) -> Rule.border_is_chrome(style, parent):
  match style:
    case Source.Style{Source.Layout{direction, main_alignment, cross_alignment, frame, width, height, minimum, scroll, position}, font,
      Design.Chrome{foreground, background, border, border_width, radius, shadow}, states}:
      {==}

def font_resolution(choice: Source.FontChoice, +parent: T.Presentation) -> Rule.inherited_font(choice, parent):
  match choice:
    case Source.InheritFont{}: {==}
    case Source.ExplicitFont{presentation}: {==}

def event_ownership(+node: Source.Node) -> Rule.operation_is_structurally_present(node):
  match node:
    case Source.Box{key, tag, style, attributes, children}: {==}
    case Source.Control{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}: {==}
    case Source.Text{key, value, font, wrapping}: {==}
    case Source.Glyph{key, drawing, style}: {==}
    case Source.Field{key, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}: {==}
    case Source.RichText{key, style, content, attachments, native_owner}: {==}
    case Source.NativeAttachment{key, target, attributes, style, children}: {==}

def bounded_policy_factory(columns_extra: Nat, +lines_extra: Nat, additional_lines: Nat) ->
  Rule.field_policy_is_bounded(Source.field_policy(columns_extra, lines_extra, additional_lines)):
  %Equal.sym(Bool, Nat.is_le(0n, columns_extra), True{}, Arithmetic.zero_le(columns_extra)) :
    {_ && Nat.is_le(1n, 1n+lines_extra) && Nat.is_le(1n+lines_extra, Nat.add(1n+lines_extra, additional_lines)) == True{} : Bool}
  %Equal.sym(Bool, Nat.is_le(0n, lines_extra), True{}, Arithmetic.zero_le(lines_extra)) :
    {True{} && _ && Nat.is_le(1n+lines_extra, Nat.add(1n+lines_extra, additional_lines)) == True{} : Bool}
  %Equal.sym(Bool, Nat.is_le(1n+lines_extra, Nat.add(1n+lines_extra, additional_lines)), True{},
    Arithmetic.le_add(1n+lines_extra, additional_lines)) :
    {True{} && True{} && _ == True{} : Bool}
  {==}

def board_controls(visual: Design.Style, position: Composition.Position) -> Rule.board_controls(visual, position): {==}
def board_stages(visual: Design.Style, position: Composition.Position) -> Rule.board_stages(visual, position): {==}
def heading_caption(key: Identity.Key, label: String, visual: Design.Style) -> Rule.heading_caption(key, label, visual): {==}
def lane_style(key: Identity.Key, label: String, stage: Board.Stage, count: Nat, visual: Design.Style, children: +List<Authored.Child>, parameters: Design.LayoutParameters) -> Rule.lane_style(key, label, stage, count, visual, children, parameters): {==}
def parameter_source(+capacity: Nat, scale: T.Scale, key: String, minimum: Nat, preferred: Nat, height: Nat, advance: Nat) -> Rule.parameter_source(capacity, scale, key, minimum, preferred, height, advance): {==}

def parameter_calculations(+capacity: Nat, +scale: T.Scale, height: Nat, +advance: Nat) -> Rule.parameter_calculations(capacity, scale, height, advance): {==}

def page_region(key: Identity.Key, region: Composition.Region, position: Composition.Position, visual: Design.Style, control: Controls.Representation, children: +List<Authored.Child>, parameters: Design.LayoutParameters, content: +List<Source.Node>) -> Rule.page_region(key, region, position, visual, control, children, parameters, content): {==}

def board_group(key: Identity.Key, label: String, grouping: UI.BoardGrouping, visual: Design.Style, control: Controls.Representation, children: +List<Authored.Child>, parameters: Design.LayoutParameters, content: +List<Source.Node>) -> Rule.board_group(key, label, grouping, visual, control, children, parameters, content): {==}

def confined_content_minimum(width: Nat, height: Nat) -> Rule.confined_content_minimum(width, height): {==}

def board_group_content_minimum(key: Identity.Key, label: String, grouping: UI.BoardGrouping, visual: Design.Style, control: Controls.Representation, children: +List<Authored.Child>, parameters: Design.LayoutParameters, content: +List<Source.Node>, width: Nat, height: Nat) -> Rule.board_group_content_minimum(key, label, grouping, visual, control, children, parameters, content, width, height):
  Design.Style{text, chrome, alignment, flow, overflow, frame, minimum_height, maximum_width_percent, states} = visual
  {==}

def Rule.evidence():
  Rule.Requirements{board_group_content_minimum, board_group, confined_content_minimum, page_region, parameter_calculations, board_controls, board_stages, heading_caption, lane_style, parameter_source, position_of_actual_rule, border_of_actual_rule, font_resolution, event_ownership, bounded_policy_factory}
