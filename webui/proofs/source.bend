import ../../core/ui-world.bend as View
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
import ../authored-primitives.bend as Factory
import ./space.bend as Arithmetic

def native_field_footprint(+kind: Source.NativeFieldKind, +style: Source.ResolvedStyle) -> Rule.native_field_footprint(kind, style):
  match kind:
    case Source.ToggleField{}:
      Source.ResolvedStyle{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font,
        Design.Chrome{foreground, background, border, border_width, radius, shadow}, states} = style
      {==}
    case Source.TextField{}: {==}
    case Source.MessageField{}: {==}
    case Source.TextAreaField{}: {==}
    case Source.SelectField{}: {==}
    case Source.MultiSelectField{}: {==}
    case Source.NumberField{minimum}: {==}
    case Source.FileField{multiple}: {==}
    case Source.DirectoryField{}: {==}
    case Source.SearchField{}: {==}
    case Source.SecretField{}: {==}

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

def card_regions(+key: Identity.Key, +face: View.CardFace, +visual: Design.Style, +children: +List<Authored.Child>, +representation: Controls.Representation, +parameters: Design.LayoutParameters, +movable: Bool) -> Rule.card_regions(key, face, visual, children, representation, parameters, movable):
  View.CardFace{id, title, description, priority, pinned, status, project, labels, owner, updated} = face
  {==}


def fact_display_choice(empty: Bool, +value: String) -> {Authored.fact_display_choice(empty, value) == Rule.expected_fact_value(empty, value) : String}:
  match empty:
    case True{}: {==}
    case False{}: {==}

def fact_display_value(+value: String) -> Rule.fact_display_value(value):
  fact_display_choice(String.eq(value, ""), value)

def fact_content(+key: Identity.Key, +label: String, +value: String, +visual: Design.Style) -> Rule.fact_content(key, label, value, visual):
  Equal.cong(String, Source.Node,
    (displayed => Authored.group(key, visual, Model.Vertical{}, Model.StretchSize{}, Model.NaturalSize{}, [Authored.text(Identity.part(key, "label"), label, visual, T.Body{}, T.Strong{}), Authored.text(Identity.part(key, "value"), displayed, visual, T.Body{}, T.Regular{})])),
    Authored.fact_display_value(value), Rule.expected_fact_value(String.eq(value, ""), value), fact_display_value(value))

def fact_source_dispatch(key: Identity.Key, label: String, role: UI.Role, value: String, visual: Design.Style, representation: Controls.Representation, children: +List<Authored.Child>, parameters: Design.LayoutParameters, content: +List<Source.Node>) -> Rule.fact_source_dispatch(key, label, role, value, visual, representation, children, parameters, content): {==}


def user_width_choice(+full_width: Bool, +percent: Nat) -> {Factory.adaptive_width_cap(full_width, percent) == Rule.adaptive_user_width_choice(full_width, percent) : Model.AxisSize}:
  match full_width:
    case True{}: {==}
    case False{}: {==}

def user_width_policy(+visual: Design.Style) -> {Factory.adaptive_natural_width(visual) == Rule.adaptive_user_width(visual) : Model.AxisSize}:
  Design.Style{text, chrome, alignment, flow, overflow, frame, minimum_height, +percent, states} = visual
  user_width_choice(Nat.is_eq(percent, 100n), percent)

def user_message_width(+visual: Design.Style) -> Rule.user_message_width(visual):
  Equal.cong(Model.AxisSize, Source.Style,
    width => Factory.style(visual, width, Model.NaturalSize{}, Model.Confined{}),
    Factory.adaptive_natural_width(visual), Rule.adaptive_user_width(visual), user_width_policy(visual))

def Rule.evidence():
  Rule.Requirements{user_width_policy, user_message_width, fact_display_value, fact_content, fact_source_dispatch, native_field_footprint, card_regions, board_group_content_minimum, board_group, confined_content_minimum, page_region, parameter_calculations, board_controls, board_stages, heading_caption, lane_style, parameter_source, position_of_actual_rule, border_of_actual_rule, font_resolution, event_ownership, bounded_policy_factory}

def Rule.movement_field_has_own_identity(key, destinations, face, name, handle, geometry, help, visual, parameters): {==}
def Rule.movement_child_is_authored(key, role, destinations, face, control, nodes, rest): {==}

def Rule.card_source_dispatch(key, label, role, face, visual, representation, children, parameters, content): {==}
def Rule.movement_source_dispatch(key, label, role, destinations, face, visual, representation, children, parameters, content): {==}
