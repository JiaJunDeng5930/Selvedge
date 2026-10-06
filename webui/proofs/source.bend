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

def Rule.evidence():
  Rule.Requirements{position_of_actual_rule, border_of_actual_rule, font_resolution, event_ownership, bounded_policy_factory}
