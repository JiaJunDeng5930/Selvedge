import Base
import ../typography.bend as T
import ../enclosure.bend as E
import ../space.bend as Space
import ../enclosure-laws.bend as Model
import ../appearance.bend as A
import ../controls.bend as C
import ../design.bend as D
import ../renderer.bend as R
import ../document.bend as Doc
import ../../core/interface.bend as UI
import ../../core/form-fields.bend as Forms
import ../../core/user-input.bend as User
import ../../core/SYSTEM.bend as Core
import ../../core/ui-world.bend as View
import ../../BOARD.bend as Board
import ../enclosure-render-laws.bend as Rule

def queried_properties(mode: Rule.AttributeMode, values: +List<Doc.Property>) -> +List<Doc.Property>:
  match mode:
    case Rule.RawBackground{}: values
    case Rule.PointerBackground{}: R.pointer_styles(values)

def preserved_property(+property: Doc.Property, +rest: +List<Doc.Property>, +name: String, +previous: String,
  different: {String.eq(Rule.property_key(property), name) == False{} : Bool},
  preserved: {R.attr_last(rest, name, previous) == previous : String}) ->
  {R.attr_last(property <> rest, name, previous) == previous : String}:
  Doc.Property{+key, +text} = property
  Equal.trans(String, R.attr_last(rest, name, R.attr_found(String.eq(key, name), text, previous)),
    R.attr_last(rest, name, previous), previous,
    Equal.cong(Bool, String, (same => R.attr_last(rest, name, R.attr_found(same, text, previous))), String.eq(key, name), False{}, different), preserved)

def preserved(+mode: Rule.AttributeMode, +values: +List<Doc.Property>, +previous: String, evidence: Rule.Excluded(mode, values)) ->
  {R.attr_last(queried_properties(mode, values), Rule.background_key(mode), previous) == previous : String}:
  match mode values:
    case Rule.RawBackground{} Nil{}: {==}
    case Rule.PointerBackground{} Nil{}: {==}
    case Rule.RawBackground{} Con{+property, +rest}:
      (different, remaining) = evidence
      preserved_property(property, rest, "background", previous, different, preserved(Rule.RawBackground{}, rest, previous, remaining))
    case Rule.PointerBackground{} Con{Doc.Property{+key, +text}, +rest}:
      (different, remaining) = evidence
      preserved_property(R.pointer_property(key, text), R.pointer_styles(rest), "--native-rest-background", previous, different, preserved(Rule.PointerBackground{}, rest, previous, remaining))

def excluded_append(+mode: Rule.AttributeMode, +first: +List<Doc.Property>, +second: +List<Doc.Property>,
  first_evidence: Rule.Excluded(mode, first), second_evidence: Rule.Excluded(mode, second)) ->
  Rule.Excluded(mode, List.append(&2, Doc.Property, first, second)):
  match first:
    case Nil{}: second_evidence
    case Con{property, +rest}:
      (different, remaining) = first_evidence
      (different, excluded_append(mode, rest, second, remaining, second_evidence))

def excluded_flow(+mode: Rule.AttributeMode, +flow: D.Flow) -> Rule.Excluded(mode, R.flow(flow)):
  match mode flow:
    case Rule.RawBackground{} D.BlockFlow{}: ({==}, Unit{})
    case Rule.RawBackground{} D.ColumnFlow{}: ({==}, ({==}, Unit{}))
    case Rule.RawBackground{} D.RowFlow{}: ({==}, ({==}, Unit{}))
    case Rule.RawBackground{} D.SplitRowFlow{}: ({==}, ({==}, ({==}, Unit{})))
    case Rule.RawBackground{} D.WrapFlow{}: ({==}, ({==}, Unit{}))
    case Rule.RawBackground{} D.InlineControlFlow{alignment}: ({==}, ({==}, ({==}, ({==}, Unit{}))))
    case Rule.RawBackground{} D.ChoiceFlow{}: ({==}, ({==}, ({==}, ({==}, Unit{}))))
    case Rule.PointerBackground{} D.BlockFlow{}: ({==}, Unit{})
    case Rule.PointerBackground{} D.ColumnFlow{}: ({==}, ({==}, Unit{}))
    case Rule.PointerBackground{} D.RowFlow{}: ({==}, ({==}, Unit{}))
    case Rule.PointerBackground{} D.SplitRowFlow{}: ({==}, ({==}, ({==}, Unit{})))
    case Rule.PointerBackground{} D.WrapFlow{}: ({==}, ({==}, Unit{}))
    case Rule.PointerBackground{} D.InlineControlFlow{alignment}: ({==}, ({==}, ({==}, ({==}, Unit{}))))
    case Rule.PointerBackground{} D.ChoiceFlow{}: ({==}, ({==}, ({==}, ({==}, Unit{}))))

def excluded_overflow(+mode: Rule.AttributeMode, +overflow: D.Overflow) -> Rule.Excluded(mode, R.overflow_style(overflow)):
  match mode overflow:
    case Rule.RawBackground{} D.ContentFlow{}: Unit{}
    case Rule.RawBackground{} D.ScrollFlow{}: ({==}, Unit{})
    case Rule.RawBackground{} D.CodeOverflow{}: ({==}, Unit{})
    case Rule.RawBackground{} D.SingleLineOverflow{}: ({==}, ({==}, ({==}, Unit{})))
    case Rule.RawBackground{} D.TextFlow{wrapping}: ({==}, ({==}, ({==}, ({==}, Unit{}))))
    case Rule.PointerBackground{} D.ContentFlow{}: Unit{}
    case Rule.PointerBackground{} D.ScrollFlow{}: ({==}, Unit{})
    case Rule.PointerBackground{} D.CodeOverflow{}: ({==}, Unit{})
    case Rule.PointerBackground{} D.SingleLineOverflow{}: ({==}, ({==}, ({==}, Unit{})))
    case Rule.PointerBackground{} D.TextFlow{wrapping}: ({==}, ({==}, ({==}, ({==}, Unit{}))))

def excluded_shadow(+mode: Rule.AttributeMode, +shadow: Bool) -> Rule.Excluded(mode, R.shadow_style(shadow)):
  match mode shadow:
    case Rule.RawBackground{} False{}: Unit{}
    case Rule.RawBackground{} True{}: ({==}, Unit{})
    case Rule.PointerBackground{} False{}: Unit{}
    case Rule.PointerBackground{} True{}: ({==}, Unit{})

def excluded_alignment(+mode: Rule.AttributeMode, +alignment: D.Alignment) -> Rule.Excluded(mode, R.alignment_style(alignment)):
  match mode alignment:
    case Rule.RawBackground{} D.Stretch{}: ({==}, Unit{})
    case Rule.RawBackground{} D.Leading{}: ({==}, Unit{})
    case Rule.RawBackground{} D.Trailing{}: ({==}, Unit{})
    case Rule.RawBackground{} D.Centered{}: ({==}, ({==}, Unit{}))
    case Rule.PointerBackground{} D.Stretch{}: ({==}, Unit{})
    case Rule.PointerBackground{} D.Leading{}: ({==}, Unit{})
    case Rule.PointerBackground{} D.Trailing{}: ({==}, Unit{})
    case Rule.PointerBackground{} D.Centered{}: ({==}, ({==}, Unit{}))

def excluded_states(+mode: Rule.AttributeMode, +states: D.ControlStates) -> Rule.Excluded(mode, R.states_style(states)):
  match mode states:
    case Rule.RawBackground{} D.Passive{}: Unit{}
    case Rule.RawBackground{} D.Interactive{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}, opacity, ring, width, offset}: ({==}, ({==}, ({==}, ({==}, ({==}, ({==}, ({==}, ({==}, Unit{}))))))))
    case Rule.RawBackground{} D.SurfaceFeedback{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}}: ({==}, ({==}, ({==}, ({==}, Unit{}))))
    case Rule.PointerBackground{} D.Passive{}: Unit{}
    case Rule.PointerBackground{} D.Interactive{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}, opacity, ring, width, offset}: ({==}, ({==}, ({==}, ({==}, ({==}, ({==}, ({==}, ({==}, Unit{}))))))))
    case Rule.PointerBackground{} D.SurfaceFeedback{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}}: ({==}, ({==}, ({==}, ({==}, Unit{}))))

def excluded_details(+mode: Rule.AttributeMode, +shadow: Bool, +alignment: D.Alignment, +states: D.ControlStates) ->
  Rule.Excluded(mode, R.style_details(shadow, alignment, states)):
  excluded_append(mode, R.shadow_style(shadow), List.append(&2, Doc.Property, R.alignment_style(alignment), R.states_style(states)),
    excluded_shadow(mode, shadow), excluded_append(mode, R.alignment_style(alignment), R.states_style(states), excluded_alignment(mode, alignment), excluded_states(mode, states)))

def style_tail(flow: D.Flow, overflow: D.Overflow, shadow: Bool, alignment: D.Alignment, states: D.ControlStates) -> +List<Doc.Property>:
  List.append(&2, Doc.Property, R.flow(flow), List.append(&2, Doc.Property, R.overflow_style(overflow), R.style_details(shadow, alignment, states)))

def excluded_style_tail(+mode: Rule.AttributeMode, +flow: D.Flow, +overflow: D.Overflow, +shadow: Bool, +alignment: D.Alignment, +states: D.ControlStates) ->
  Rule.Excluded(mode, style_tail(flow, overflow, shadow, alignment, states)):
  excluded_append(mode, R.flow(flow), List.append(&2, Doc.Property, R.overflow_style(overflow), R.style_details(shadow, alignment, states)), excluded_flow(mode, flow),
    excluded_append(mode, R.overflow_style(overflow), R.style_details(shadow, alignment, states), excluded_overflow(mode, overflow), excluded_details(mode, shadow, alignment, states)))

def excluded_typography(+mode: Rule.AttributeMode, +value: T.Presentation) -> Rule.Excluded(mode, R.text_presentation(value)):
  match mode:
    case Rule.RawBackground{}: ({==}, ({==}, ({==}, ({==}, Unit{}))))
    case Rule.PointerBackground{}: ({==}, ({==}, ({==}, ({==}, Unit{}))))

def typed_style_tail(+value: T.Presentation, flow: D.Flow, overflow: D.Overflow, shadow: Bool, alignment: D.Alignment, states: D.ControlStates) -> +List<Doc.Property>:
  List.append(&2, Doc.Property, style_tail(flow, overflow, shadow, alignment, states), R.text_presentation(value))

def excluded_typed_tail(+mode: Rule.AttributeMode, +value: T.Presentation, +flow: D.Flow, +overflow: D.Overflow, +shadow: Bool, +alignment: D.Alignment, +states: D.ControlStates) -> Rule.Excluded(mode, typed_style_tail(value, flow, overflow, shadow, alignment, states)):
  excluded_append(mode, style_tail(flow, overflow, shadow, alignment, states), R.text_presentation(value), excluded_style_tail(mode, flow, overflow, shadow, alignment, states), excluded_typography(mode, value))

def excluded_geometry(+mode: Rule.AttributeMode, +size: C.Geometry, +visual: D.Style) -> Rule.Excluded(mode, R.action_geometry(size, visual)):
  match mode size visual:
    case Rule.RawBackground{} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon, radius, leading} D.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states}: ({==}, ({==}, ({==}, Unit{})))
    case Rule.PointerBackground{} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon, radius, leading} D.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states}: ({==}, ({==}, ({==}, Unit{})))

def excluded_placement(+mode: Rule.AttributeMode, +placement: C.Placement) -> Rule.Excluded(mode, R.placement_styles(placement)):
  match mode placement:
    case Rule.RawBackground{} C.InFlow{}: Unit{}
    case Rule.RawBackground{} C.ComposerEnd{}: ({==}, Unit{})
    case Rule.RawBackground{} C.PanelHeaderEnd{}: ({==}, Unit{})
    case Rule.RawBackground{} C.CodeToolbar{}: Unit{}
    case Rule.RawBackground{} C.BesideValue{}: Unit{}
    case Rule.RawBackground{} C.GroupHeadingEnd{}: ({==}, Unit{})
    case Rule.PointerBackground{} C.InFlow{}: Unit{}
    case Rule.PointerBackground{} C.ComposerEnd{}: ({==}, Unit{})
    case Rule.PointerBackground{} C.PanelHeaderEnd{}: ({==}, Unit{})
    case Rule.PointerBackground{} C.CodeToolbar{}: Unit{}
    case Rule.PointerBackground{} C.BesideValue{}: Unit{}
    case Rule.PointerBackground{} C.GroupHeadingEnd{}: ({==}, Unit{})

def excluded_extent(+mode: Rule.AttributeMode, +face: C.Face, +size: C.Geometry) -> Rule.Excluded(mode, R.content_extent(face, size)):
  match mode face size:
    case Rule.RawBackground{} C.IconFace{icon} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon, radius, leading}: ({==}, ({==}, ({==}, ({==}, Unit{}))))
    case Rule.RawBackground{} C.TextFace{text} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon, radius, leading}: ({==}, ({==}, Unit{}))
    case Rule.RawBackground{} C.SingleLineFace{text} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon, radius, leading}: ({==}, ({==}, ({==}, ({==}, ({==}, ({==}, Unit{}))))))
    case Rule.RawBackground{} C.IconTextFace{icon, text} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon, radius, leading}: ({==}, ({==}, Unit{}))
    case Rule.RawBackground{} C.PickerFace{leading, text} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon, radius, leading}: ({==}, ({==}, Unit{}))
    case Rule.RawBackground{} C.ChoiceFace{text, description, checked} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon, radius, leading}: ({==}, ({==}, ({==}, Unit{})))
    case Rule.RawBackground{} C.DisclosureFace{text, expanded} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon, radius, leading}: ({==}, ({==}, Unit{}))
    case Rule.RawBackground{} C.PermissionFace{filesystem, network, approval} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon, radius, leading}: ({==}, ({==}, Unit{}))
    case Rule.PointerBackground{} C.IconFace{icon} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon, radius, leading}: ({==}, ({==}, ({==}, ({==}, Unit{}))))
    case Rule.PointerBackground{} C.TextFace{text} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon, radius, leading}: ({==}, ({==}, Unit{}))
    case Rule.PointerBackground{} C.SingleLineFace{text} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon, radius, leading}: ({==}, ({==}, ({==}, ({==}, ({==}, ({==}, Unit{}))))))
    case Rule.PointerBackground{} C.IconTextFace{icon, text} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon, radius, leading}: ({==}, ({==}, Unit{}))
    case Rule.PointerBackground{} C.PickerFace{leading, text} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon, radius, leading}: ({==}, ({==}, Unit{}))
    case Rule.PointerBackground{} C.ChoiceFace{text, description, checked} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon, radius, leading}: ({==}, ({==}, ({==}, Unit{})))
    case Rule.PointerBackground{} C.DisclosureFace{text, expanded} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon, radius, leading}: ({==}, ({==}, Unit{}))
    case Rule.PointerBackground{} C.PermissionFace{filesystem, network, approval} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon, radius, leading}: ({==}, ({==}, Unit{}))

def excluded_anchor(+mode: Rule.AttributeMode, key: String) -> Rule.Excluded(mode, [R.property("anchor-name", R.css_anchor(key))]):
  match mode:
    case Rule.RawBackground{}: ({==}, Unit{})
    case Rule.PointerBackground{}: ({==}, Unit{})

def geometry_tail(+visual: D.Style, +face: C.Face, +size: C.Geometry, placement: C.Placement, key: String) -> +List<Doc.Property>:
  List.append(&2, Doc.Property, R.placement_styles(placement), List.append(&2, Doc.Property, [R.property("anchor-name", R.css_anchor(key))], R.content_geometry(face, size)))

def excluded_geometry_tail(+mode: Rule.AttributeMode, +visual: D.Style, +face: C.Face, +size: C.Geometry, +placement: C.Placement, +key: String) ->
  Rule.Excluded(mode, geometry_tail(visual, face, size, placement, key)):
  excluded_append(mode, R.placement_styles(placement), List.append(&2, Doc.Property, [R.property("anchor-name", R.css_anchor(key))], R.content_geometry(face, size)), excluded_placement(mode, placement),
    excluded_append(mode, [R.property("anchor-name", R.css_anchor(key))], R.content_geometry(face, size), excluded_anchor(mode, key), excluded_extent(mode, face, size)))

def last_append(+first: +List<Doc.Property>, +second: +List<Doc.Property>, +name: String, +previous: String) ->
  {R.attr_last(List.append(&2, Doc.Property, first, second), name, previous) == R.attr_last(second, name, R.attr_last(first, name, previous)) : String}:
  match first:
    case Nil{}: {==}
    case Con{Doc.Property{key, value}, rest}:
      last_append(rest, second, name, R.attr_found(String.eq(key, name), value, previous))

def geometry_pointer(+size: C.Geometry, +visual: D.Style) ->
  {R.pointer_styles(R.action_geometry(size, visual)) == R.action_geometry(size, visual) : +List<Doc.Property>}:
  match size visual:
    case C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon, radius, leading} D.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states}: {==}

def action_background_preserved(+key: String, +visual: D.Style, +input: Core.Input, +availability: View.Availability,
  +name: String, +face: C.Face, +behavior: C.Behavior, +geometry: C.Geometry, +placement: C.Placement, +help: C.Help, +feedback: C.Feedback) ->
  {R.attr(Doc.element_styles(R.action(key, visual, C.Action{input, availability, name, face, behavior, geometry, placement, help, feedback})), "--native-rest-background") == R.attr(R.style(visual), "background") : String}:
  D.Style{+actual_text, D.Chrome{+foreground, +background, +border, +border_width, +radius, +shadow}, +alignment, +flow, +overflow, +content_frame, +height, +maximum, +states} = visual
  +value: D.Style = D.Style{actual_text, D.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, flow, overflow, content_frame, height, maximum, states}
  +tail: +List<Doc.Property> = typed_style_tail(actual_text, flow, overflow, shadow, alignment, states)
  +extra: +List<Doc.Property> = geometry_tail(value, face, geometry, placement, key)
  +prefix: +List<Doc.Property> = R.pointer_styles(List.append(&2, Doc.Property, R.style(value), extra))
  +geometry_styles: +List<Doc.Property> = R.action_geometry(geometry, value)
  +prefix_evidence: {R.attr(prefix, "--native-rest-background") == R.attr(R.style(value), "background") : String} =
    Equal.trans(String,
      R.attr(prefix, "--native-rest-background"),
      R.paint(background), R.attr(R.style(value), "background"),
      preserved(Rule.PointerBackground{}, List.append(&2, Doc.Property, tail, extra), R.paint(background),
        excluded_append(Rule.PointerBackground{}, tail, extra, excluded_typed_tail(Rule.PointerBackground{}, actual_text, flow, overflow, shadow, alignment, states), excluded_geometry_tail(Rule.PointerBackground{}, value, face, geometry, placement, key))),
      Equal.sym(String, R.attr(R.style(value), "background"), R.paint(background),
        preserved(Rule.RawBackground{}, tail, R.paint(background), excluded_typed_tail(Rule.RawBackground{}, actual_text, flow, overflow, shadow, alignment, states))))
  Equal.trans(String,
    R.attr(List.append(&2, Doc.Property, prefix, geometry_styles), "--native-rest-background"),
    R.attr_last(geometry_styles, "--native-rest-background", R.attr(prefix, "--native-rest-background")), R.attr(R.style(value), "background"),
    last_append(prefix, geometry_styles, "--native-rest-background", ""),
    Equal.trans(String,
      R.attr_last(geometry_styles, "--native-rest-background", R.attr(prefix, "--native-rest-background")),
      R.attr(prefix, "--native-rest-background"), R.attr(R.style(value), "background"),
      Equal.trans(String,
        R.attr_last(geometry_styles, "--native-rest-background", R.attr(prefix, "--native-rest-background")),
        R.attr_last(R.pointer_styles(geometry_styles), "--native-rest-background", R.attr(prefix, "--native-rest-background")), R.attr(prefix, "--native-rest-background"),
        Equal.cong(+List<Doc.Property>, String, (values => R.attr_last(values, "--native-rest-background", R.attr(prefix, "--native-rest-background"))),
          geometry_styles, R.pointer_styles(geometry_styles), Equal.sym(+List<Doc.Property>, R.pointer_styles(geometry_styles), geometry_styles, geometry_pointer(geometry, value))),
        preserved(Rule.PointerBackground{}, geometry_styles, R.attr(prefix, "--native-rest-background"), excluded_geometry(Rule.PointerBackground{}, geometry, value))), prefix_evidence))

def preserve_flow(+value: D.Flow, +axis: Rule.Axis, +previous: String) ->
  {R.attr_last(R.flow(value), Rule.axis_name(axis), previous) == previous : String}:
  match value axis:
    case D.BlockFlow{} Rule.Inline{}: {==}
    case D.BlockFlow{} Rule.Block{}: {==}
    case D.ColumnFlow{} Rule.Inline{}: {==}
    case D.ColumnFlow{} Rule.Block{}: {==}
    case D.RowFlow{} Rule.Inline{}: {==}
    case D.RowFlow{} Rule.Block{}: {==}
    case D.SplitRowFlow{} Rule.Inline{}: {==}
    case D.SplitRowFlow{} Rule.Block{}: {==}
    case D.WrapFlow{} Rule.Inline{}: {==}
    case D.WrapFlow{} Rule.Block{}: {==}
    case D.InlineControlFlow{alignment} Rule.Inline{}: {==}
    case D.InlineControlFlow{alignment} Rule.Block{}: {==}
    case D.ChoiceFlow{} Rule.Inline{}: {==}
    case D.ChoiceFlow{} Rule.Block{}: {==}

def preserve_overflow(+value: D.Overflow, +axis: Rule.Axis, +previous: String) ->
  {R.attr_last(R.overflow_style(value), Rule.axis_name(axis), previous) == previous : String}:
  match value axis:
    case D.ContentFlow{} Rule.Inline{}: {==}
    case D.ContentFlow{} Rule.Block{}: {==}
    case D.ScrollFlow{} Rule.Inline{}: {==}
    case D.ScrollFlow{} Rule.Block{}: {==}
    case D.CodeOverflow{} Rule.Inline{}: {==}
    case D.SingleLineOverflow{} Rule.Inline{}: {==}
    case D.TextFlow{wrapping} Rule.Inline{}: {==}
    case D.CodeOverflow{} Rule.Block{}: {==}
    case D.SingleLineOverflow{} Rule.Block{}: {==}
    case D.TextFlow{wrapping} Rule.Block{}: {==}

def preserve_details(+shadow: Bool, +alignment: D.Alignment, +states: D.ControlStates, +axis: Rule.Axis, +previous: String) ->
  {R.attr_last(R.style_details(shadow, alignment, states), Rule.axis_name(axis), previous) == previous : String}:
  match shadow alignment states axis:
    case False{} D.Stretch{} D.Passive{} Rule.Inline{}: {==}
    case False{} D.Stretch{} D.Passive{} Rule.Block{}: {==}
    case False{} D.Stretch{} D.Interactive{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}, opacity, ring, width, offset} Rule.Inline{}: {==}
    case False{} D.Stretch{} D.SurfaceFeedback{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}} Rule.Inline{}: {==}
    case False{} D.Stretch{} D.Interactive{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}, opacity, ring, width, offset} Rule.Block{}: {==}
    case False{} D.Stretch{} D.SurfaceFeedback{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}} Rule.Block{}: {==}
    case False{} D.Leading{} D.Passive{} Rule.Inline{}: {==}
    case False{} D.Leading{} D.Passive{} Rule.Block{}: {==}
    case False{} D.Leading{} D.Interactive{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}, opacity, ring, width, offset} Rule.Inline{}: {==}
    case False{} D.Leading{} D.SurfaceFeedback{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}} Rule.Inline{}: {==}
    case False{} D.Leading{} D.Interactive{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}, opacity, ring, width, offset} Rule.Block{}: {==}
    case False{} D.Leading{} D.SurfaceFeedback{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}} Rule.Block{}: {==}
    case False{} D.Trailing{} D.Passive{} Rule.Inline{}: {==}
    case False{} D.Trailing{} D.Passive{} Rule.Block{}: {==}
    case False{} D.Trailing{} D.Interactive{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}, opacity, ring, width, offset} Rule.Inline{}: {==}
    case False{} D.Trailing{} D.SurfaceFeedback{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}} Rule.Inline{}: {==}
    case False{} D.Trailing{} D.Interactive{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}, opacity, ring, width, offset} Rule.Block{}: {==}
    case False{} D.Trailing{} D.SurfaceFeedback{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}} Rule.Block{}: {==}
    case False{} D.Centered{} D.Passive{} Rule.Inline{}: {==}
    case False{} D.Centered{} D.Passive{} Rule.Block{}: {==}
    case False{} D.Centered{} D.Interactive{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}, opacity, ring, width, offset} Rule.Inline{}: {==}
    case False{} D.Centered{} D.SurfaceFeedback{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}} Rule.Inline{}: {==}
    case False{} D.Centered{} D.Interactive{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}, opacity, ring, width, offset} Rule.Block{}: {==}
    case False{} D.Centered{} D.SurfaceFeedback{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}} Rule.Block{}: {==}
    case True{} D.Stretch{} D.Passive{} Rule.Inline{}: {==}
    case True{} D.Stretch{} D.Passive{} Rule.Block{}: {==}
    case True{} D.Stretch{} D.Interactive{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}, opacity, ring, width, offset} Rule.Inline{}: {==}
    case True{} D.Stretch{} D.SurfaceFeedback{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}} Rule.Inline{}: {==}
    case True{} D.Stretch{} D.Interactive{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}, opacity, ring, width, offset} Rule.Block{}: {==}
    case True{} D.Stretch{} D.SurfaceFeedback{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}} Rule.Block{}: {==}
    case True{} D.Leading{} D.Passive{} Rule.Inline{}: {==}
    case True{} D.Leading{} D.Passive{} Rule.Block{}: {==}
    case True{} D.Leading{} D.Interactive{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}, opacity, ring, width, offset} Rule.Inline{}: {==}
    case True{} D.Leading{} D.SurfaceFeedback{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}} Rule.Inline{}: {==}
    case True{} D.Leading{} D.Interactive{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}, opacity, ring, width, offset} Rule.Block{}: {==}
    case True{} D.Leading{} D.SurfaceFeedback{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}} Rule.Block{}: {==}
    case True{} D.Trailing{} D.Passive{} Rule.Inline{}: {==}
    case True{} D.Trailing{} D.Passive{} Rule.Block{}: {==}
    case True{} D.Trailing{} D.Interactive{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}, opacity, ring, width, offset} Rule.Inline{}: {==}
    case True{} D.Trailing{} D.SurfaceFeedback{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}} Rule.Inline{}: {==}
    case True{} D.Trailing{} D.Interactive{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}, opacity, ring, width, offset} Rule.Block{}: {==}
    case True{} D.Trailing{} D.SurfaceFeedback{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}} Rule.Block{}: {==}
    case True{} D.Centered{} D.Passive{} Rule.Inline{}: {==}
    case True{} D.Centered{} D.Passive{} Rule.Block{}: {==}
    case True{} D.Centered{} D.Interactive{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}, opacity, ring, width, offset} Rule.Inline{}: {==}
    case True{} D.Centered{} D.SurfaceFeedback{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}} Rule.Inline{}: {==}
    case True{} D.Centered{} D.Interactive{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}, opacity, ring, width, offset} Rule.Block{}: {==}
    case True{} D.Centered{} D.SurfaceFeedback{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}} Rule.Block{}: {==}

def preserve_suffix(+flow: D.Flow, +overflow: D.Overflow, +shadow: Bool, +alignment: D.Alignment, +states: D.ControlStates, +axis: Rule.Axis, +previous: String) ->
  {R.attr_last(List.append(&2, Doc.Property, R.flow(flow), List.append(&2, Doc.Property, R.overflow_style(overflow), R.style_details(shadow, alignment, states))), Rule.axis_name(axis), previous) == previous : String}:
  Equal.trans(String, R.attr_last(List.append(&2, Doc.Property, R.flow(flow), List.append(&2, Doc.Property, R.overflow_style(overflow), R.style_details(shadow, alignment, states))), Rule.axis_name(axis), previous), R.attr_last(List.append(&2, Doc.Property, R.overflow_style(overflow), R.style_details(shadow, alignment, states)), Rule.axis_name(axis), R.attr_last(R.flow(flow), Rule.axis_name(axis), previous)), previous, last_append(R.flow(flow), List.append(&2, Doc.Property, R.overflow_style(overflow), R.style_details(shadow, alignment, states)), Rule.axis_name(axis), previous), Equal.trans(String, R.attr_last(List.append(&2, Doc.Property, R.overflow_style(overflow), R.style_details(shadow, alignment, states)), Rule.axis_name(axis), R.attr_last(R.flow(flow), Rule.axis_name(axis), previous)), R.attr_last(List.append(&2, Doc.Property, R.overflow_style(overflow), R.style_details(shadow, alignment, states)), Rule.axis_name(axis), previous), previous, Equal.cong(String, String, (value => R.attr_last(List.append(&2, Doc.Property, R.overflow_style(overflow), R.style_details(shadow, alignment, states)), Rule.axis_name(axis), value)), R.attr_last(R.flow(flow), Rule.axis_name(axis), previous), previous, preserve_flow(flow, axis, previous)), Equal.trans(String, R.attr_last(List.append(&2, Doc.Property, R.overflow_style(overflow), R.style_details(shadow, alignment, states)), Rule.axis_name(axis), previous), R.attr_last(R.style_details(shadow, alignment, states), Rule.axis_name(axis), R.attr_last(R.overflow_style(overflow), Rule.axis_name(axis), previous)), previous, last_append(R.overflow_style(overflow), R.style_details(shadow, alignment, states), Rule.axis_name(axis), previous), Equal.trans(String, R.attr_last(R.style_details(shadow, alignment, states), Rule.axis_name(axis), R.attr_last(R.overflow_style(overflow), Rule.axis_name(axis), previous)), R.attr_last(R.style_details(shadow, alignment, states), Rule.axis_name(axis), previous), previous, Equal.cong(String, String, (value => R.attr_last(R.style_details(shadow, alignment, states), Rule.axis_name(axis), value)), R.attr_last(R.overflow_style(overflow), Rule.axis_name(axis), previous), previous, preserve_overflow(overflow, axis, previous)), preserve_details(shadow, alignment, states, axis, previous)))))

def duplicate_value(+same: Bool, old: String, new: String) -> String:
  R.attr_found(same, new, R.attr_found(same, old, ""))
# Duplicate-name lookup requires reflexivity of the exact Base comparator.

def same_bit(+value: Bool) -> {Bool.cmp(value, value) == EQ{} : Cmp}:
  match value:
    case False{}: {==}
    case True{}: {==}

def same_word(+size: Nat, +value: Word(size)) -> {Word.cmp(size, value, value) == EQ{} : Cmp}:
  match size:
    case 0n: {==}
    case 1n+rest:
      match value:
        case WCon{+head, +tail}:
          Equal.trans(Cmp, Word.cmp.fin(head, head, Word.cmp(rest, tail, tail)), Word.cmp.fin(head, head, EQ{}), EQ{},
            Equal.cong(Cmp, Cmp, (order => Word.cmp.fin(head, head, order)), Word.cmp(rest, tail, tail), EQ{}, same_word(rest, tail)), same_bit(head))

def same_character(+code: U32) -> {Char.cmp(Chr{code}, Chr{code}) == ((Chr{code}, Chr{code}), EQ{}) : (Char & Char) & Cmp}:
  match code:
    case U32{+value}:
      Equal.cong(Cmp, (Char & Char) & Cmp, (order => ((Chr{U32{value}}, Chr{U32{value}}), order)), Word.cmp(32n, value, value), EQ{}, same_word(32n, value))

def same_comparison(+text: String) -> {String.cmp(text, text) == ((text, text), EQ{}) : (String & String) & Cmp}:
  match text:
    case SNil{}: {==}
    case SCon{Chr{+code}, +rest}:
      Equal.trans((String & String) & Cmp,
        String.cmp(SCon{Chr{code}, rest}, SCon{Chr{code}, rest}),
        String.cmp.rec(Chr{code}, Chr{code}, String.cmp(rest, rest)),
        ((SCon{Chr{code}, rest}, SCon{Chr{code}, rest}), EQ{}),
        Equal.cong((Char & Char) & Cmp, (String & String) & Cmp,
          (heads => String.cmp.fin(rest, rest, heads)), Char.cmp(Chr{code}, Chr{code}), ((Chr{code}, Chr{code}), EQ{}), same_character(code)),
        Equal.cong((String & String) & Cmp, (String & String) & Cmp,
          (compared => String.cmp.rec(Chr{code}, Chr{code}, compared)), String.cmp(rest, rest), ((rest, rest), EQ{}), same_comparison(rest)))

def same_string(+text: String) -> {String.eq(text, text) == True{} : Bool}:
  Equal.cong((String & String) & Cmp, Bool, (compared => String.eq.fin(compared)), String.cmp(text, text), ((text, text), EQ{}), same_comparison(text))

def preserve_typography(+value: T.Presentation, +axis: Rule.Axis, +previous: String) ->
  {R.attr_last(R.text_presentation(value), Rule.axis_name(axis), previous) == previous : String}:
  match axis:
    case Rule.Inline{}: {==}
    case Rule.Block{}: {==}

def preserve_typed_suffix(+value: T.Presentation, +flow: D.Flow, +overflow: D.Overflow, +shadow: Bool, +alignment: D.Alignment, +states: D.ControlStates, +axis: Rule.Axis, +previous: String) ->
  {R.attr_last(typed_style_tail(value, flow, overflow, shadow, alignment, states), Rule.axis_name(axis), previous) == previous : String}:
  Equal.trans(String, R.attr_last(typed_style_tail(value, flow, overflow, shadow, alignment, states), Rule.axis_name(axis), previous),
    R.attr_last(R.text_presentation(value), Rule.axis_name(axis), R.attr_last(style_tail(flow, overflow, shadow, alignment, states), Rule.axis_name(axis), previous)), previous,
    last_append(style_tail(flow, overflow, shadow, alignment, states), R.text_presentation(value), Rule.axis_name(axis), previous),
    Equal.trans(String, R.attr_last(R.text_presentation(value), Rule.axis_name(axis), R.attr_last(style_tail(flow, overflow, shadow, alignment, states), Rule.axis_name(axis), previous)), R.attr_last(style_tail(flow, overflow, shadow, alignment, states), Rule.axis_name(axis), previous), previous,
      preserve_typography(value, axis, R.attr_last(style_tail(flow, overflow, shadow, alignment, states), Rule.axis_name(axis), previous)), preserve_suffix(flow, overflow, shadow, alignment, states, axis, previous)))

def style_allocation(+value: D.Style, +axis: Rule.Axis) ->
  {R.attr(R.style(value), Rule.axis_name(axis)) == R.px(Rule.axis_space(axis, Model.area(value))) : String}:
  D.Style{actual_text, D.Chrome{fg, bg, border, border_width, radius, shadow}, alignment, flow, overflow, +content_frame, minimum, maximum, states} = value
  match axis:
    case Rule.Inline{}: preserve_typed_suffix(actual_text, flow, overflow, shadow, alignment, states, Rule.Inline{}, R.px(E.inline(E.frame_content(content_frame))))
    case Rule.Block{}: preserve_typed_suffix(actual_text, flow, overflow, shadow, alignment, states, Rule.Block{}, R.px(E.block(E.frame_content(content_frame))))

def duplicate(+name: String, +old: String, +new: String) ->
  {R.attr([R.property(name, old), R.property(name, new)], name) == new : String}:
  Equal.cong(Bool, String, (same => duplicate_value(same, old, new)), String.eq(name, name), True{}, same_string(name))

# These parent properties are emitted by Style; control decoration preserves them.

def parent_properties(pointer: Bool, values: +List<Doc.Property>) -> +List<Doc.Property>:
  match pointer:
    case False{}: values
    case True{}: R.pointer_styles(values)

def parent_properties_append(+pointer: Bool, +first: +List<Doc.Property>, +second: +List<Doc.Property>) ->
  {parent_properties(pointer, List.append(&2, Doc.Property, first, second)) == List.append(&2, Doc.Property, parent_properties(pointer, first), parent_properties(pointer, second)) : +List<Doc.Property>}:
  match pointer first:
    case False{} _: {==}
    case True{} Nil{}: {==}
    case True{} Con{Doc.Property{+name, +value}, +rest}:
      Equal.cong(+List<Doc.Property>, +List<Doc.Property>, (tail => R.pointer_property(name, value) <> tail),
        parent_properties(True{}, List.append(&2, Doc.Property, rest, second)), List.append(&2, Doc.Property, parent_properties(True{}, rest), parent_properties(True{}, second)),
        parent_properties_append(True{}, rest, second))

def parent_append(+pointer: Bool, +property: Rule.ParentProperty, +first: +List<Doc.Property>, +second: +List<Doc.Property>, +previous: String, +next: String,
  first_evidence: {R.attr_last(parent_properties(pointer, first), Rule.parent_name(property), previous) == next : String},
  second_evidence: {R.attr_last(parent_properties(pointer, second), Rule.parent_name(property), next) == next : String}) ->
  {R.attr_last(parent_properties(pointer, List.append(&2, Doc.Property, first, second)), Rule.parent_name(property), previous) == next : String}:
  Equal.trans(String,
    R.attr_last(parent_properties(pointer, List.append(&2, Doc.Property, first, second)), Rule.parent_name(property), previous),
    R.attr_last(List.append(&2, Doc.Property, parent_properties(pointer, first), parent_properties(pointer, second)), Rule.parent_name(property), previous), next,
    Equal.cong(+List<Doc.Property>, String, (values => R.attr_last(values, Rule.parent_name(property), previous)),
      parent_properties(pointer, List.append(&2, Doc.Property, first, second)), List.append(&2, Doc.Property, parent_properties(pointer, first), parent_properties(pointer, second)),
      parent_properties_append(pointer, first, second)),
    Equal.trans(String,
      R.attr_last(List.append(&2, Doc.Property, parent_properties(pointer, first), parent_properties(pointer, second)), Rule.parent_name(property), previous),
      R.attr_last(parent_properties(pointer, second), Rule.parent_name(property), R.attr_last(parent_properties(pointer, first), Rule.parent_name(property), previous)), next,
      last_append(parent_properties(pointer, first), parent_properties(pointer, second), Rule.parent_name(property), previous),
      Equal.trans(String,
        R.attr_last(parent_properties(pointer, second), Rule.parent_name(property), R.attr_last(parent_properties(pointer, first), Rule.parent_name(property), previous)),
        R.attr_last(parent_properties(pointer, second), Rule.parent_name(property), next), next,
        Equal.cong(String, String, (old => R.attr_last(parent_properties(pointer, second), Rule.parent_name(property), old)),
          R.attr_last(parent_properties(pointer, first), Rule.parent_name(property), previous), next, first_evidence), second_evidence)))

def parent_flow(+pointer: Bool, +property: Rule.ParentProperty, value: D.Flow, +previous: String) ->
  {R.attr_last(parent_properties(pointer, R.flow(value)), Rule.parent_name(property), previous) == previous : String}:
  match pointer property value:
    case False{} Rule.FrameGap{} D.BlockFlow{}: {==}
    case False{} Rule.FrameGap{} D.ColumnFlow{}: {==}
    case False{} Rule.FrameGap{} D.RowFlow{}: {==}
    case False{} Rule.FrameGap{} D.SplitRowFlow{}: {==}
    case False{} Rule.FrameGap{} D.WrapFlow{}: {==}
    case False{} Rule.FrameGap{} D.InlineControlFlow{alignment}: {==}
    case False{} Rule.FrameGap{} D.ChoiceFlow{}: {==}
    case False{} Rule.MinimumHeight{} D.BlockFlow{}: {==}
    case False{} Rule.MinimumHeight{} D.ColumnFlow{}: {==}
    case False{} Rule.MinimumHeight{} D.RowFlow{}: {==}
    case False{} Rule.MinimumHeight{} D.SplitRowFlow{}: {==}
    case False{} Rule.MinimumHeight{} D.WrapFlow{}: {==}
    case False{} Rule.MinimumHeight{} D.InlineControlFlow{alignment}: {==}
    case False{} Rule.MinimumHeight{} D.ChoiceFlow{}: {==}
    case False{} Rule.BorderRadius{} D.BlockFlow{}: {==}
    case False{} Rule.BorderRadius{} D.ColumnFlow{}: {==}
    case False{} Rule.BorderRadius{} D.RowFlow{}: {==}
    case False{} Rule.BorderRadius{} D.SplitRowFlow{}: {==}
    case False{} Rule.BorderRadius{} D.WrapFlow{}: {==}
    case False{} Rule.BorderRadius{} D.InlineControlFlow{alignment}: {==}
    case False{} Rule.BorderRadius{} D.ChoiceFlow{}: {==}
    case True{} Rule.FrameGap{} D.BlockFlow{}: {==}
    case True{} Rule.FrameGap{} D.ColumnFlow{}: {==}
    case True{} Rule.FrameGap{} D.RowFlow{}: {==}
    case True{} Rule.FrameGap{} D.SplitRowFlow{}: {==}
    case True{} Rule.FrameGap{} D.WrapFlow{}: {==}
    case True{} Rule.FrameGap{} D.InlineControlFlow{alignment}: {==}
    case True{} Rule.FrameGap{} D.ChoiceFlow{}: {==}
    case True{} Rule.MinimumHeight{} D.BlockFlow{}: {==}
    case True{} Rule.MinimumHeight{} D.ColumnFlow{}: {==}
    case True{} Rule.MinimumHeight{} D.RowFlow{}: {==}
    case True{} Rule.MinimumHeight{} D.SplitRowFlow{}: {==}
    case True{} Rule.MinimumHeight{} D.WrapFlow{}: {==}
    case True{} Rule.MinimumHeight{} D.InlineControlFlow{alignment}: {==}
    case True{} Rule.MinimumHeight{} D.ChoiceFlow{}: {==}
    case True{} Rule.BorderRadius{} D.BlockFlow{}: {==}
    case True{} Rule.BorderRadius{} D.ColumnFlow{}: {==}
    case True{} Rule.BorderRadius{} D.RowFlow{}: {==}
    case True{} Rule.BorderRadius{} D.SplitRowFlow{}: {==}
    case True{} Rule.BorderRadius{} D.WrapFlow{}: {==}
    case True{} Rule.BorderRadius{} D.InlineControlFlow{alignment}: {==}
    case True{} Rule.BorderRadius{} D.ChoiceFlow{}: {==}

def parent_overflow(+pointer: Bool, +property: Rule.ParentProperty, value: D.Overflow, +previous: String) ->
  {R.attr_last(parent_properties(pointer, R.overflow_style(value)), Rule.parent_name(property), previous) == previous : String}:
  match pointer property value:
    case False{} Rule.FrameGap{} D.ContentFlow{}: {==}
    case False{} Rule.FrameGap{} D.ScrollFlow{}: {==}
    case False{} Rule.FrameGap{} D.CodeOverflow{}: {==}
    case False{} Rule.FrameGap{} D.SingleLineOverflow{}: {==}
    case False{} Rule.FrameGap{} D.TextFlow{wrapping}: {==}
    case False{} Rule.MinimumHeight{} D.ContentFlow{}: {==}
    case False{} Rule.MinimumHeight{} D.ScrollFlow{}: {==}
    case False{} Rule.MinimumHeight{} D.CodeOverflow{}: {==}
    case False{} Rule.MinimumHeight{} D.SingleLineOverflow{}: {==}
    case False{} Rule.MinimumHeight{} D.TextFlow{wrapping}: {==}
    case False{} Rule.BorderRadius{} D.ContentFlow{}: {==}
    case False{} Rule.BorderRadius{} D.ScrollFlow{}: {==}
    case False{} Rule.BorderRadius{} D.CodeOverflow{}: {==}
    case False{} Rule.BorderRadius{} D.SingleLineOverflow{}: {==}
    case False{} Rule.BorderRadius{} D.TextFlow{wrapping}: {==}
    case True{} Rule.FrameGap{} D.ContentFlow{}: {==}
    case True{} Rule.FrameGap{} D.ScrollFlow{}: {==}
    case True{} Rule.FrameGap{} D.CodeOverflow{}: {==}
    case True{} Rule.FrameGap{} D.SingleLineOverflow{}: {==}
    case True{} Rule.FrameGap{} D.TextFlow{wrapping}: {==}
    case True{} Rule.MinimumHeight{} D.ContentFlow{}: {==}
    case True{} Rule.MinimumHeight{} D.ScrollFlow{}: {==}
    case True{} Rule.MinimumHeight{} D.CodeOverflow{}: {==}
    case True{} Rule.MinimumHeight{} D.SingleLineOverflow{}: {==}
    case True{} Rule.MinimumHeight{} D.TextFlow{wrapping}: {==}
    case True{} Rule.BorderRadius{} D.ContentFlow{}: {==}
    case True{} Rule.BorderRadius{} D.ScrollFlow{}: {==}
    case True{} Rule.BorderRadius{} D.CodeOverflow{}: {==}
    case True{} Rule.BorderRadius{} D.SingleLineOverflow{}: {==}
    case True{} Rule.BorderRadius{} D.TextFlow{wrapping}: {==}

def parent_shadow(+pointer: Bool, +property: Rule.ParentProperty, value: Bool, +previous: String) ->
  {R.attr_last(parent_properties(pointer, R.shadow_style(value)), Rule.parent_name(property), previous) == previous : String}:
  match pointer property value:
    case False{} Rule.FrameGap{} False{}: {==}
    case False{} Rule.FrameGap{} True{}: {==}
    case False{} Rule.MinimumHeight{} False{}: {==}
    case False{} Rule.MinimumHeight{} True{}: {==}
    case False{} Rule.BorderRadius{} False{}: {==}
    case False{} Rule.BorderRadius{} True{}: {==}
    case True{} Rule.FrameGap{} False{}: {==}
    case True{} Rule.FrameGap{} True{}: {==}
    case True{} Rule.MinimumHeight{} False{}: {==}
    case True{} Rule.MinimumHeight{} True{}: {==}
    case True{} Rule.BorderRadius{} False{}: {==}
    case True{} Rule.BorderRadius{} True{}: {==}

def parent_alignment(+pointer: Bool, +property: Rule.ParentProperty, value: D.Alignment, +previous: String) ->
  {R.attr_last(parent_properties(pointer, R.alignment_style(value)), Rule.parent_name(property), previous) == previous : String}:
  match pointer property value:
    case False{} Rule.FrameGap{} D.Stretch{}: {==}
    case False{} Rule.FrameGap{} D.Leading{}: {==}
    case False{} Rule.FrameGap{} D.Trailing{}: {==}
    case False{} Rule.FrameGap{} D.Centered{}: {==}
    case False{} Rule.MinimumHeight{} D.Stretch{}: {==}
    case False{} Rule.MinimumHeight{} D.Leading{}: {==}
    case False{} Rule.MinimumHeight{} D.Trailing{}: {==}
    case False{} Rule.MinimumHeight{} D.Centered{}: {==}
    case False{} Rule.BorderRadius{} D.Stretch{}: {==}
    case False{} Rule.BorderRadius{} D.Leading{}: {==}
    case False{} Rule.BorderRadius{} D.Trailing{}: {==}
    case False{} Rule.BorderRadius{} D.Centered{}: {==}
    case True{} Rule.FrameGap{} D.Stretch{}: {==}
    case True{} Rule.FrameGap{} D.Leading{}: {==}
    case True{} Rule.FrameGap{} D.Trailing{}: {==}
    case True{} Rule.FrameGap{} D.Centered{}: {==}
    case True{} Rule.MinimumHeight{} D.Stretch{}: {==}
    case True{} Rule.MinimumHeight{} D.Leading{}: {==}
    case True{} Rule.MinimumHeight{} D.Trailing{}: {==}
    case True{} Rule.MinimumHeight{} D.Centered{}: {==}
    case True{} Rule.BorderRadius{} D.Stretch{}: {==}
    case True{} Rule.BorderRadius{} D.Leading{}: {==}
    case True{} Rule.BorderRadius{} D.Trailing{}: {==}
    case True{} Rule.BorderRadius{} D.Centered{}: {==}

def parent_states(+pointer: Bool, +property: Rule.ParentProperty, value: D.ControlStates, +previous: String) ->
  {R.attr_last(parent_properties(pointer, R.states_style(value)), Rule.parent_name(property), previous) == previous : String}:
  match pointer property value:
    case False{} Rule.FrameGap{} D.Passive{}: {==}
    case False{} Rule.FrameGap{} D.Interactive{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}, opacity, ring, width, offset}: {==}
    case False{} Rule.FrameGap{} D.SurfaceFeedback{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}}: {==}
    case False{} Rule.MinimumHeight{} D.Passive{}: {==}
    case False{} Rule.MinimumHeight{} D.Interactive{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}, opacity, ring, width, offset}: {==}
    case False{} Rule.MinimumHeight{} D.SurfaceFeedback{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}}: {==}
    case False{} Rule.BorderRadius{} D.Passive{}: {==}
    case False{} Rule.BorderRadius{} D.Interactive{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}, opacity, ring, width, offset}: {==}
    case False{} Rule.BorderRadius{} D.SurfaceFeedback{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}}: {==}
    case True{} Rule.FrameGap{} D.Passive{}: {==}
    case True{} Rule.FrameGap{} D.Interactive{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}, opacity, ring, width, offset}: {==}
    case True{} Rule.FrameGap{} D.SurfaceFeedback{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}}: {==}
    case True{} Rule.MinimumHeight{} D.Passive{}: {==}
    case True{} Rule.MinimumHeight{} D.Interactive{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}, opacity, ring, width, offset}: {==}
    case True{} Rule.MinimumHeight{} D.SurfaceFeedback{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}}: {==}
    case True{} Rule.BorderRadius{} D.Passive{}: {==}
    case True{} Rule.BorderRadius{} D.Interactive{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}, opacity, ring, width, offset}: {==}
    case True{} Rule.BorderRadius{} D.SurfaceFeedback{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}}: {==}

def parent_placement(+pointer: Bool, +property: Rule.ParentProperty, value: C.Placement, +previous: String) ->
  {R.attr_last(parent_properties(pointer, R.placement_styles(value)), Rule.parent_name(property), previous) == previous : String}:
  match pointer property value:
    case False{} Rule.FrameGap{} C.InFlow{}: {==}
    case False{} Rule.FrameGap{} C.ComposerEnd{}: {==}
    case False{} Rule.FrameGap{} C.PanelHeaderEnd{}: {==}
    case False{} Rule.FrameGap{} C.CodeToolbar{}: {==}
    case False{} Rule.FrameGap{} C.BesideValue{}: {==}
    case False{} Rule.FrameGap{} C.GroupHeadingEnd{}: {==}
    case False{} Rule.MinimumHeight{} C.InFlow{}: {==}
    case False{} Rule.MinimumHeight{} C.ComposerEnd{}: {==}
    case False{} Rule.MinimumHeight{} C.PanelHeaderEnd{}: {==}
    case False{} Rule.MinimumHeight{} C.CodeToolbar{}: {==}
    case False{} Rule.MinimumHeight{} C.BesideValue{}: {==}
    case False{} Rule.MinimumHeight{} C.GroupHeadingEnd{}: {==}
    case False{} Rule.BorderRadius{} C.InFlow{}: {==}
    case False{} Rule.BorderRadius{} C.ComposerEnd{}: {==}
    case False{} Rule.BorderRadius{} C.PanelHeaderEnd{}: {==}
    case False{} Rule.BorderRadius{} C.CodeToolbar{}: {==}
    case False{} Rule.BorderRadius{} C.BesideValue{}: {==}
    case False{} Rule.BorderRadius{} C.GroupHeadingEnd{}: {==}
    case True{} Rule.FrameGap{} C.InFlow{}: {==}
    case True{} Rule.FrameGap{} C.ComposerEnd{}: {==}
    case True{} Rule.FrameGap{} C.PanelHeaderEnd{}: {==}
    case True{} Rule.FrameGap{} C.CodeToolbar{}: {==}
    case True{} Rule.FrameGap{} C.BesideValue{}: {==}
    case True{} Rule.FrameGap{} C.GroupHeadingEnd{}: {==}
    case True{} Rule.MinimumHeight{} C.InFlow{}: {==}
    case True{} Rule.MinimumHeight{} C.ComposerEnd{}: {==}
    case True{} Rule.MinimumHeight{} C.PanelHeaderEnd{}: {==}
    case True{} Rule.MinimumHeight{} C.CodeToolbar{}: {==}
    case True{} Rule.MinimumHeight{} C.BesideValue{}: {==}
    case True{} Rule.MinimumHeight{} C.GroupHeadingEnd{}: {==}
    case True{} Rule.BorderRadius{} C.InFlow{}: {==}
    case True{} Rule.BorderRadius{} C.ComposerEnd{}: {==}
    case True{} Rule.BorderRadius{} C.PanelHeaderEnd{}: {==}
    case True{} Rule.BorderRadius{} C.CodeToolbar{}: {==}
    case True{} Rule.BorderRadius{} C.BesideValue{}: {==}
    case True{} Rule.BorderRadius{} C.GroupHeadingEnd{}: {==}

def parent_details(+pointer: Bool, +property: Rule.ParentProperty, +shadow: Bool, +alignment: D.Alignment, +states: D.ControlStates, +previous: String) ->
  {R.attr_last(parent_properties(pointer, R.style_details(shadow, alignment, states)), Rule.parent_name(property), previous) == previous : String}:
  parent_append(pointer, property, R.shadow_style(shadow), List.append(&2, Doc.Property, R.alignment_style(alignment), R.states_style(states)), previous, previous,
    parent_shadow(pointer, property, shadow, previous),
    parent_append(pointer, property, R.alignment_style(alignment), R.states_style(states), previous, previous,
      parent_alignment(pointer, property, alignment, previous), parent_states(pointer, property, states, previous)))

def parent_suffix(+pointer: Bool, +property: Rule.ParentProperty, +flow: D.Flow, +overflow: D.Overflow, +shadow: Bool, +alignment: D.Alignment, +states: D.ControlStates, +previous: String) ->
  {R.attr_last(parent_properties(pointer, style_tail(flow, overflow, shadow, alignment, states)), Rule.parent_name(property), previous) == previous : String}:
  parent_append(pointer, property, R.flow(flow), List.append(&2, Doc.Property, R.overflow_style(overflow), R.style_details(shadow, alignment, states)), previous, previous,
    parent_flow(pointer, property, flow, previous),
    parent_append(pointer, property, R.overflow_style(overflow), R.style_details(shadow, alignment, states), previous, previous,
      parent_overflow(pointer, property, overflow, previous), parent_details(pointer, property, shadow, alignment, states, previous)))

def parent_typography(+pointer: Bool, +property: Rule.ParentProperty, +value: T.Presentation, +previous: String) ->
  {R.attr_last(parent_properties(pointer, R.text_presentation(value)), Rule.parent_name(property), previous) == previous : String}:
  match pointer property:
    case False{} Rule.FrameGap{}: {==}
    case False{} Rule.MinimumHeight{}: {==}
    case False{} Rule.BorderRadius{}: {==}
    case True{} Rule.FrameGap{}: {==}
    case True{} Rule.MinimumHeight{}: {==}
    case True{} Rule.BorderRadius{}: {==}

def parent_typed_suffix(+pointer: Bool, +property: Rule.ParentProperty, +value: T.Presentation, +flow: D.Flow, +overflow: D.Overflow, +shadow: Bool, +alignment: D.Alignment, +states: D.ControlStates, +previous: String) ->
  {R.attr_last(parent_properties(pointer, typed_style_tail(value, flow, overflow, shadow, alignment, states)), Rule.parent_name(property), previous) == previous : String}:
  parent_append(pointer, property, style_tail(flow, overflow, shadow, alignment, states), R.text_presentation(value), previous, previous,
    parent_suffix(pointer, property, flow, overflow, shadow, alignment, states, previous), parent_typography(pointer, property, value, previous))

def parent_style(+pointer: Bool, +property: Rule.ParentProperty, +value: D.Style) ->
  {R.attr(parent_properties(pointer, R.style(value)), Rule.parent_name(property)) == Rule.parent_value(value, property) : String}:
  match pointer property value:
    case False{} Rule.FrameGap{} D.Style{actual_text, D.Chrome{fg, bg, border, border_width, radius, +shadow}, +alignment, +flow, +overflow, +frame, minimum, maximum, +states}:
      parent_typed_suffix(False{}, Rule.FrameGap{}, actual_text, flow, overflow, shadow, alignment, states, R.px(E.frame_gap(frame)))
    case False{} Rule.MinimumHeight{} D.Style{actual_text, D.Chrome{fg, bg, border, border_width, radius, +shadow}, +alignment, +flow, +overflow, +frame, minimum, maximum, +states}:
      parent_typed_suffix(False{}, Rule.MinimumHeight{}, actual_text, flow, overflow, shadow, alignment, states, R.px(minimum))
    case False{} Rule.BorderRadius{} D.Style{actual_text, D.Chrome{fg, bg, border, border_width, radius, +shadow}, +alignment, +flow, +overflow, +frame, minimum, maximum, +states}:
      parent_typed_suffix(False{}, Rule.BorderRadius{}, actual_text, flow, overflow, shadow, alignment, states, R.px(radius))
    case True{} Rule.FrameGap{} D.Style{actual_text, D.Chrome{fg, bg, border, border_width, radius, +shadow}, +alignment, +flow, +overflow, +frame, minimum, maximum, +states}:
      parent_typed_suffix(True{}, Rule.FrameGap{}, actual_text, flow, overflow, shadow, alignment, states, R.px(E.frame_gap(frame)))
    case True{} Rule.MinimumHeight{} D.Style{actual_text, D.Chrome{fg, bg, border, border_width, radius, +shadow}, +alignment, +flow, +overflow, +frame, minimum, maximum, +states}:
      parent_typed_suffix(True{}, Rule.MinimumHeight{}, actual_text, flow, overflow, shadow, alignment, states, R.px(minimum))
    case True{} Rule.BorderRadius{} D.Style{actual_text, D.Chrome{fg, bg, border, border_width, radius, +shadow}, +alignment, +flow, +overflow, +frame, minimum, maximum, +states}:
      parent_typed_suffix(True{}, Rule.BorderRadius{}, actual_text, flow, overflow, shadow, alignment, states, R.px(radius))

def parent_geometry(+pointer: Bool, +property: Rule.ParentProperty, +size: C.Geometry, +visual: D.Style, +previous: String) ->
  {R.attr_last(parent_properties(pointer, R.action_geometry(size, visual)), Rule.parent_name(property), previous) == previous : String}:
  match pointer property size visual:
    case False{} Rule.FrameGap{} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon, radius, leading} D.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states}: {==}
    case False{} Rule.MinimumHeight{} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon, radius, leading} D.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states}: {==}
    case False{} Rule.BorderRadius{} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon, radius, leading} D.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states}: {==}
    case True{} Rule.FrameGap{} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon, radius, leading} D.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states}: {==}
    case True{} Rule.MinimumHeight{} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon, radius, leading} D.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states}: {==}
    case True{} Rule.BorderRadius{} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon, radius, leading} D.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states}: {==}

def parent_content(+pointer: Bool, +property: Rule.ParentProperty, +face: C.Face, +size: C.Geometry, +previous: String) ->
  {R.attr_last(parent_properties(pointer, R.content_geometry(face, size)), Rule.parent_name(property), previous) == previous : String}:
  match pointer property face size:
    case False{} Rule.FrameGap{} C.IconFace{icon} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon_size, radius, slot}: {==}
    case False{} Rule.FrameGap{} C.TextFace{text} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon_size, radius, slot}: {==}
    case False{} Rule.FrameGap{} C.SingleLineFace{text} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon_size, radius, slot}: {==}
    case False{} Rule.FrameGap{} C.IconTextFace{icon, text} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon_size, radius, slot}: {==}
    case False{} Rule.FrameGap{} C.PickerFace{leading, text} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon_size, radius, slot}: {==}
    case False{} Rule.FrameGap{} C.ChoiceFace{text, description, checked} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon_size, radius, slot}: {==}
    case False{} Rule.FrameGap{} C.DisclosureFace{text, expanded} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon_size, radius, slot}: {==}
    case False{} Rule.FrameGap{} C.PermissionFace{filesystem, network, approval} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon_size, radius, slot}: {==}
    case False{} Rule.MinimumHeight{} C.IconFace{icon} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon_size, radius, slot}: {==}
    case False{} Rule.MinimumHeight{} C.TextFace{text} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon_size, radius, slot}: {==}
    case False{} Rule.MinimumHeight{} C.SingleLineFace{text} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon_size, radius, slot}: {==}
    case False{} Rule.MinimumHeight{} C.IconTextFace{icon, text} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon_size, radius, slot}: {==}
    case False{} Rule.MinimumHeight{} C.PickerFace{leading, text} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon_size, radius, slot}: {==}
    case False{} Rule.MinimumHeight{} C.ChoiceFace{text, description, checked} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon_size, radius, slot}: {==}
    case False{} Rule.MinimumHeight{} C.DisclosureFace{text, expanded} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon_size, radius, slot}: {==}
    case False{} Rule.MinimumHeight{} C.PermissionFace{filesystem, network, approval} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon_size, radius, slot}: {==}
    case False{} Rule.BorderRadius{} C.IconFace{icon} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon_size, radius, slot}: {==}
    case False{} Rule.BorderRadius{} C.TextFace{text} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon_size, radius, slot}: {==}
    case False{} Rule.BorderRadius{} C.SingleLineFace{text} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon_size, radius, slot}: {==}
    case False{} Rule.BorderRadius{} C.IconTextFace{icon, text} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon_size, radius, slot}: {==}
    case False{} Rule.BorderRadius{} C.PickerFace{leading, text} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon_size, radius, slot}: {==}
    case False{} Rule.BorderRadius{} C.ChoiceFace{text, description, checked} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon_size, radius, slot}: {==}
    case False{} Rule.BorderRadius{} C.DisclosureFace{text, expanded} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon_size, radius, slot}: {==}
    case False{} Rule.BorderRadius{} C.PermissionFace{filesystem, network, approval} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon_size, radius, slot}: {==}
    case True{} Rule.FrameGap{} C.IconFace{icon} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon_size, radius, slot}: {==}
    case True{} Rule.FrameGap{} C.TextFace{text} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon_size, radius, slot}: {==}
    case True{} Rule.FrameGap{} C.SingleLineFace{text} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon_size, radius, slot}: {==}
    case True{} Rule.FrameGap{} C.IconTextFace{icon, text} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon_size, radius, slot}: {==}
    case True{} Rule.FrameGap{} C.PickerFace{leading, text} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon_size, radius, slot}: {==}
    case True{} Rule.FrameGap{} C.ChoiceFace{text, description, checked} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon_size, radius, slot}: {==}
    case True{} Rule.FrameGap{} C.DisclosureFace{text, expanded} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon_size, radius, slot}: {==}
    case True{} Rule.FrameGap{} C.PermissionFace{filesystem, network, approval} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon_size, radius, slot}: {==}
    case True{} Rule.MinimumHeight{} C.IconFace{icon} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon_size, radius, slot}: {==}
    case True{} Rule.MinimumHeight{} C.TextFace{text} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon_size, radius, slot}: {==}
    case True{} Rule.MinimumHeight{} C.SingleLineFace{text} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon_size, radius, slot}: {==}
    case True{} Rule.MinimumHeight{} C.IconTextFace{icon, text} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon_size, radius, slot}: {==}
    case True{} Rule.MinimumHeight{} C.PickerFace{leading, text} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon_size, radius, slot}: {==}
    case True{} Rule.MinimumHeight{} C.ChoiceFace{text, description, checked} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon_size, radius, slot}: {==}
    case True{} Rule.MinimumHeight{} C.DisclosureFace{text, expanded} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon_size, radius, slot}: {==}
    case True{} Rule.MinimumHeight{} C.PermissionFace{filesystem, network, approval} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon_size, radius, slot}: {==}
    case True{} Rule.BorderRadius{} C.IconFace{icon} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon_size, radius, slot}: {==}
    case True{} Rule.BorderRadius{} C.TextFace{text} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon_size, radius, slot}: {==}
    case True{} Rule.BorderRadius{} C.SingleLineFace{text} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon_size, radius, slot}: {==}
    case True{} Rule.BorderRadius{} C.IconTextFace{icon, text} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon_size, radius, slot}: {==}
    case True{} Rule.BorderRadius{} C.PickerFace{leading, text} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon_size, radius, slot}: {==}
    case True{} Rule.BorderRadius{} C.ChoiceFace{text, description, checked} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon_size, radius, slot}: {==}
    case True{} Rule.BorderRadius{} C.DisclosureFace{text, expanded} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon_size, radius, slot}: {==}
    case True{} Rule.BorderRadius{} C.PermissionFace{filesystem, network, approval} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon_size, radius, slot}: {==}

def parent_anchor(+pointer: Bool, +property: Rule.ParentProperty, key: String, +previous: String) ->
  {R.attr_last(parent_properties(pointer, [R.property("anchor-name", R.css_anchor(key))]), Rule.parent_name(property), previous) == previous : String}:
  match pointer property:
    case False{} Rule.FrameGap{}: {==}
    case False{} Rule.MinimumHeight{}: {==}
    case False{} Rule.BorderRadius{}: {==}
    case True{} Rule.FrameGap{}: {==}
    case True{} Rule.MinimumHeight{}: {==}
    case True{} Rule.BorderRadius{}: {==}

def parent_action_tail(+pointer: Bool, +property: Rule.ParentProperty, +visual: D.Style, +face: C.Face, +size: C.Geometry, +placement: C.Placement, +key: String, +previous: String) ->
  {R.attr_last(parent_properties(pointer, geometry_tail(visual, face, size, placement, key)), Rule.parent_name(property), previous) == previous : String}:
  parent_append(pointer, property, R.placement_styles(placement), List.append(&2, Doc.Property, [R.property("anchor-name", R.css_anchor(key))], R.content_geometry(face, size)), previous, previous,
    parent_placement(pointer, property, placement, previous),
    parent_append(pointer, property, [R.property("anchor-name", R.css_anchor(key))], R.content_geometry(face, size), previous, previous,
      parent_anchor(pointer, property, key, previous), parent_content(pointer, property, face, size, previous)))

def parent_action(+property: Rule.ParentProperty, +key: String, +visual: D.Style, +input: Core.Input, +availability: View.Availability, +name: String,
  +face: C.Face, +behavior: C.Behavior, +size: C.Geometry, +placement: C.Placement, +help: C.Help, +feedback: C.Feedback) -> Rule.parent_action_law(property, key, visual, input, availability, name, face, behavior, size, placement, help, feedback):
  +prefix: +List<Doc.Property> = R.pointer_styles(List.append(&2, Doc.Property, R.style(visual), geometry_tail(visual, face, size, placement, key)))
  +geometry_styles: +List<Doc.Property> = R.action_geometry(size, visual)
  Equal.trans(String,
    R.attr(List.append(&2, Doc.Property, prefix, geometry_styles), Rule.parent_name(property)),
    R.attr_last(geometry_styles, Rule.parent_name(property), R.attr(prefix, Rule.parent_name(property))), Rule.parent_value(visual, property),
    last_append(prefix, geometry_styles, Rule.parent_name(property), ""),
    Equal.trans(String,
      R.attr_last(geometry_styles, Rule.parent_name(property), R.attr(prefix, Rule.parent_name(property))),
      R.attr(prefix, Rule.parent_name(property)), Rule.parent_value(visual, property),
      parent_geometry(False{}, property, size, visual, R.attr(prefix, Rule.parent_name(property))),
      parent_append(True{}, property, R.style(visual), geometry_tail(visual, face, size, placement, key), "", Rule.parent_value(visual, property),
        parent_style(True{}, property, visual), parent_action_tail(True{}, property, visual, face, size, placement, key, Rule.parent_value(visual, property)))))

def parent_minimum(+value: D.Style) ->
  {Rule.parent_value(value, Rule.MinimumHeight{}) == R.px(D.style_minimum_height(value)) : String}:
  D.Style{text, D.Chrome{fg, bg, border, width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = value
  {==}

def navigation_header(+selected: Bool, +typography: T.Presentation) ->
  {(R.attr(R.style(A.navigation_family_style(selected, 2n, 6n, typography)), "padding-inline"), R.attr(R.style(A.navigation_family_style(selected, 2n, 6n, typography)), "padding-block")) == ("8px", "4px") : (String & String)}:
  match selected:
    case False{}: {==}
    case True{}: {==}

def navigation_task(+selected: Bool, +key: String, +task: Nat, +status: String, +children: +List<R.Child>, +typography: T.Presentation) ->
  {(R.attr(Doc.element_styles(R.task_row_node(key, task, status, selected, A.navigation_family_style(selected, 6n, 5n, typography), children, typography)), "padding-inline"), R.attr(Doc.element_styles(R.task_row_node(key, task, status, selected, A.navigation_family_style(selected, 6n, 5n, typography), children, typography)), "padding-block")) == ("8px", "4px") : (String & String)}:
  match selected:
    case False{}: {==}
    case True{}: {==}

def search(+filter: Board.Filter, +typography: T.Presentation) ->
  {(R.attr(R.style(A.field_style(UI.BoardSearch{filter}, typography)), "padding-inline"), R.attr(R.style(A.field_style(UI.BoardSearch{filter}, typography)), "padding-block")) == ("8px", "4px") : (String & String)}:
  {==}

def option_production_insets(+key: String, +label: String, +selected: Bool, +description: String, +geometry: C.Geometry, +input: Core.Input, +typography: T.Presentation) ->
  {(R.attr(Doc.element_styles(Rule.option_production(key, label, selected, description, geometry, input, typography)), "padding-inline"), R.attr(Doc.element_styles(Rule.option_production(key, label, selected, description, geometry, input, typography)), "padding-block")) == ("8px", "8px") : (String & String)}:
  match selected geometry:
    case False{} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon, radius, leading}: {==}
    case True{} C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon, radius, leading}: {==}

def title_production_insets(+key: String, +editor: User.Editor, +name: String, +text: String, choices: +List<Forms.ChoiceValue>, +typography: T.Presentation) ->
  {(R.attr(Doc.element_styles(Rule.title_production(key, editor, name, text, choices, typography)), "padding-inline"), R.attr(Doc.element_styles(Rule.title_production(key, editor, name, text, choices, typography)), "padding-block")) == ("8px", "6px") : (String & String)}:
  match editor:
    case User.NewTaskEditor{}: {==}
    case User.MessageEditor{task}: {==}
    case User.ProjectEditor{project}: {==}
    case User.CardEditor{card}: {==}
    case User.AgentEditor{agent}: {==}
    case User.ForkEditor{task}: {==}
    case User.CompactEditor{task}: {==}

def description_production_insets(+key: String, +editor: User.Editor, +name: String, +text: String, choices: +List<Forms.ChoiceValue>, +typography: T.Presentation) ->
  {(R.attr(Doc.element_styles(Rule.description_production(key, editor, name, text, choices, typography)), "padding-inline"), R.attr(Doc.element_styles(Rule.description_production(key, editor, name, text, choices, typography)), "padding-block")) == ("8px", "6px") : (String & String)}:
  match editor:
    case User.NewTaskEditor{}: {==}
    case User.MessageEditor{task}: {==}
    case User.ProjectEditor{project}: {==}
    case User.CardEditor{card}: {==}
    case User.AgentEditor{agent}: {==}
    case User.ForkEditor{task}: {==}
    case User.CompactEditor{task}: {==}

def geometry_complete(+width: Nat, +height: Nat, +preferred_width: Nat, +preferred_height: Nat, +icon: Nat, +radius: Nat, +leading: Nat, +visual: D.Style) -> Rule.geometry_complete_law(width, height, preferred_width, preferred_height, icon, radius, leading, visual):
  D.Style{text, chrome, alignment, flow, overflow, +content_frame, minimum, maximum, states} = visual
  {==}

def action_minimum(+key: String, +visual: D.Style, +input: Core.Input, +availability: View.Availability, +name: String,
  +face: C.Face, +behavior: C.Behavior, +width: Nat, +height: Nat, +preferred_width: Nat, +preferred_height: Nat, +icon: Nat, +radius: Nat, +leading: Nat, +placement: C.Placement, +help: C.Help, +feedback: C.Feedback) ->
  Rule.action_minimum_law(key, visual, input, availability, name, face, behavior, width, height, preferred_width, preferred_height, icon, radius, leading, placement, help, feedback):
  +size: C.Geometry = C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon, radius, leading}
  +prefix: +List<Doc.Property> = R.pointer_styles(List.append(&2, Doc.Property, R.style(visual), geometry_tail(visual, face, size, placement, key)))
  last_append(prefix, R.action_geometry(size, visual), "min-width", "")

def Rule.evidence():
  Rule.Requirements{parent_action, +area => {==}, style_allocation, duplicate, +size => +visual =>
      Equal.trans(String, R.attr(List.append(&2, Doc.Property, R.style(visual), R.action_geometry(size, visual)), "min-height"),
        Rule.parent_value(visual, Rule.MinimumHeight{}), R.px(D.style_minimum_height(visual)),
        parent_append(False{}, Rule.MinimumHeight{}, R.style(visual), R.action_geometry(size, visual), "", Rule.parent_value(visual, Rule.MinimumHeight{}),
          parent_style(False{}, Rule.MinimumHeight{}, visual), parent_geometry(False{}, Rule.MinimumHeight{}, size, visual, Rule.parent_value(visual, Rule.MinimumHeight{}))),
        parent_minimum(visual))
    ,
    +typography => +selected => navigation_header(selected, typography),
    +typography => +selected => +key => +task => +status => +children => navigation_task(selected, key, task, status, children, typography),
    +typography => {==},
    +typography => +width => {==},
    +typography => {==},
    +typography => +filter => search(filter, typography), {==}, {==}, {==}, +name => +old => duplicate(name, old, ""),
    +typography => +key => +label => +selected => +description => +geometry => +input => option_production_insets(key, label, selected, description, geometry, input, typography),
    +typography => +key => +editor => +name => +text => choices => title_production_insets(key, editor, name, text, choices, typography),
    +typography => +key => +editor => +name => +text => choices => description_production_insets(key, editor, name, text, choices, typography),
    +typography => {==}, action_minimum, geometry_complete}
