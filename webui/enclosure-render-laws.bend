import Base
import ./enclosure.bend as E
import ./enclosure-laws.bend as Model
import ./appearance.bend as A
import ./controls.bend as C
import ./design.bend as D
import ./renderer.bend as R
import ./renderer-laws.bend as Renderer
import ./document.bend as Doc
import ./board-spatial-laws.bend as BoardLaws
import ../core/interface.bend as UI
import ../core/form-fields.bend as Forms
import ../core/user-input.bend as User
import ../core/SYSTEM.bend as Core
import ../core/ui-world.bend as View
import ../BOARD.bend as Board

# These witnesses concern only the production renderer's ordered properties.
type AttributeMode is Data:
  RawBackground{}
  PointerBackground{}

def background_key(mode: AttributeMode) -> String:
  match mode:
    case RawBackground{}: "background"
    case PointerBackground{}: "--native-rest-background"

def property_key(value: Doc.Property) -> String:
  Doc.Property{key, text} = value
  key

def pointer(value: Doc.Property) -> Doc.Property:
  Doc.Property{key, text} = value
  R.pointer_property(key, text)

def queried_property(mode: AttributeMode, value: Doc.Property) -> Doc.Property:
  match mode:
    case RawBackground{}: value
    case PointerBackground{}: pointer(value)

def queried_properties(mode: AttributeMode, values: +List<Doc.Property>) -> +List<Doc.Property>:
  match mode:
    case RawBackground{}: values
    case PointerBackground{}: R.pointer_styles(values)

def Excluded(+mode: AttributeMode, values: +List<Doc.Property>) -> Type:
  match values:
    case Nil{}: Unit
    case Con{property, rest}:
      {String.eq(property_key(queried_property(mode, property)), background_key(mode)) == False{} : Bool} & Excluded(mode, rest)

def preserved_property(+property: Doc.Property, +rest: +List<Doc.Property>, +name: String, +previous: String,
  different: {String.eq(property_key(property), name) == False{} : Bool},
  preserved: {R.attr_last(rest, name, previous) == previous : String}) ->
  {R.attr_last(property <> rest, name, previous) == previous : String}:
  Doc.Property{+key, +text} = property
  Equal.trans(String, R.attr_last(rest, name, R.attr_found(String.eq(key, name), text, previous)),
    R.attr_last(rest, name, previous), previous,
    Equal.cong(Bool, String, (same => R.attr_last(rest, name, R.attr_found(same, text, previous))), String.eq(key, name), False{}, different), preserved)

def preserved(+mode: AttributeMode, +values: +List<Doc.Property>, +previous: String, evidence: Excluded(mode, values)) ->
  {R.attr_last(queried_properties(mode, values), background_key(mode), previous) == previous : String}:
  match mode values:
    case RawBackground{} Nil{}: {==}
    case PointerBackground{} Nil{}: {==}
    case RawBackground{} Con{+property, +rest}:
      (different, remaining) = evidence
      preserved_property(property, rest, "background", previous, different, preserved(RawBackground{}, rest, previous, remaining))
    case PointerBackground{} Con{Doc.Property{+key, +text}, +rest}:
      (different, remaining) = evidence
      preserved_property(R.pointer_property(key, text), R.pointer_styles(rest), "--native-rest-background", previous, different, preserved(PointerBackground{}, rest, previous, remaining))

def excluded_append(+mode: AttributeMode, +first: +List<Doc.Property>, +second: +List<Doc.Property>,
  first_evidence: Excluded(mode, first), second_evidence: Excluded(mode, second)) ->
  Excluded(mode, List.append(&2, Doc.Property, first, second)):
  match first:
    case Nil{}: second_evidence
    case Con{property, +rest}:
      (different, remaining) = first_evidence
      (different, excluded_append(mode, rest, second, remaining, second_evidence))

def excluded_flow(+mode: AttributeMode, +flow: D.Flow) -> Excluded(mode, R.flow(flow)):
  match mode flow:
    case RawBackground{} D.BlockFlow{}: ({==}, Unit{})
    case RawBackground{} D.ColumnFlow{}: ({==}, ({==}, Unit{}))
    case RawBackground{} D.RowFlow{}: ({==}, ({==}, Unit{}))
    case RawBackground{} D.SplitRowFlow{}: ({==}, ({==}, ({==}, Unit{})))
    case RawBackground{} D.WrapFlow{}: ({==}, ({==}, Unit{}))
    case PointerBackground{} D.BlockFlow{}: ({==}, Unit{})
    case PointerBackground{} D.ColumnFlow{}: ({==}, ({==}, Unit{}))
    case PointerBackground{} D.RowFlow{}: ({==}, ({==}, Unit{}))
    case PointerBackground{} D.SplitRowFlow{}: ({==}, ({==}, ({==}, Unit{})))
    case PointerBackground{} D.WrapFlow{}: ({==}, ({==}, Unit{}))

def excluded_overflow(+mode: AttributeMode, +overflow: D.Overflow) -> Excluded(mode, R.overflow_style(overflow)):
  match mode overflow:
    case RawBackground{} D.ContentFlow{}: Unit{}
    case RawBackground{} D.ScrollFlow{}: ({==}, Unit{})
    case RawBackground{} D.CodeOverflow{}: ({==}, Unit{})
    case PointerBackground{} D.ContentFlow{}: Unit{}
    case PointerBackground{} D.ScrollFlow{}: ({==}, Unit{})
    case PointerBackground{} D.CodeOverflow{}: ({==}, Unit{})

def excluded_shadow(+mode: AttributeMode, +shadow: Bool) -> Excluded(mode, R.shadow_style(shadow)):
  match mode shadow:
    case RawBackground{} False{}: Unit{}
    case RawBackground{} True{}: ({==}, Unit{})
    case PointerBackground{} False{}: Unit{}
    case PointerBackground{} True{}: ({==}, Unit{})

def excluded_alignment(+mode: AttributeMode, +alignment: D.Alignment) -> Excluded(mode, R.alignment_style(alignment)):
  match mode alignment:
    case RawBackground{} D.Stretch{}: ({==}, Unit{})
    case RawBackground{} D.Leading{}: ({==}, Unit{})
    case RawBackground{} D.Trailing{}: ({==}, Unit{})
    case RawBackground{} D.Centered{}: ({==}, ({==}, Unit{}))
    case PointerBackground{} D.Stretch{}: ({==}, Unit{})
    case PointerBackground{} D.Leading{}: ({==}, Unit{})
    case PointerBackground{} D.Trailing{}: ({==}, Unit{})
    case PointerBackground{} D.Centered{}: ({==}, ({==}, Unit{}))

def excluded_states(+mode: AttributeMode, +states: D.ControlStates) -> Excluded(mode, R.states_style(states)):
  match mode states:
    case RawBackground{} D.Passive{}: Unit{}
    case RawBackground{} D.Interactive{D.Chrome{hfg, hbg, hb, hw, hr, hs}, D.Chrome{pfg, pbg, pb, pw, pr, ps}, opacity, ring, width, offset}: ({==}, ({==}, ({==}, ({==}, ({==}, ({==}, ({==}, ({==}, Unit{}))))))))
    case PointerBackground{} D.Passive{}: Unit{}
    case PointerBackground{} D.Interactive{D.Chrome{hfg, hbg, hb, hw, hr, hs}, D.Chrome{pfg, pbg, pb, pw, pr, ps}, opacity, ring, width, offset}: ({==}, ({==}, ({==}, ({==}, ({==}, ({==}, ({==}, ({==}, Unit{}))))))))

def excluded_details(+mode: AttributeMode, +shadow: Bool, +alignment: D.Alignment, +states: D.ControlStates) ->
  Excluded(mode, R.style_details(shadow, alignment, states)):
  excluded_append(mode, R.shadow_style(shadow), List.append(&2, Doc.Property, R.alignment_style(alignment), R.states_style(states)),
    excluded_shadow(mode, shadow), excluded_append(mode, R.alignment_style(alignment), R.states_style(states), excluded_alignment(mode, alignment), excluded_states(mode, states)))

def style_tail(flow: D.Flow, overflow: D.Overflow, shadow: Bool, alignment: D.Alignment, states: D.ControlStates) -> +List<Doc.Property>:
  List.append(&2, Doc.Property, R.flow(flow), List.append(&2, Doc.Property, R.overflow_style(overflow), R.style_details(shadow, alignment, states)))

def excluded_style_tail(+mode: AttributeMode, +flow: D.Flow, +overflow: D.Overflow, +shadow: Bool, +alignment: D.Alignment, +states: D.ControlStates) ->
  Excluded(mode, style_tail(flow, overflow, shadow, alignment, states)):
  excluded_append(mode, R.flow(flow), List.append(&2, Doc.Property, R.overflow_style(overflow), R.style_details(shadow, alignment, states)), excluded_flow(mode, flow),
    excluded_append(mode, R.overflow_style(overflow), R.style_details(shadow, alignment, states), excluded_overflow(mode, overflow), excluded_details(mode, shadow, alignment, states)))

def excluded_geometry(+mode: AttributeMode, +size: C.Geometry, +visual: D.Style) -> Excluded(mode, R.action_geometry(size, visual)):
  match mode size visual:
    case RawBackground{} C.Geometry{width, height, icon, radius, leading} D.Style{text, chrome, alignment, flow, overflow, +content_frame, minimum, maximum, states}: ({==}, ({==}, ({==}, ({==}, ({==}, ({==}, ({==}, Unit{})))))))
    case PointerBackground{} C.Geometry{width, height, icon, radius, leading} D.Style{text, chrome, alignment, flow, overflow, +content_frame, minimum, maximum, states}: ({==}, ({==}, ({==}, ({==}, ({==}, ({==}, ({==}, Unit{})))))))

def excluded_placement(+mode: AttributeMode, +placement: C.Placement) -> Excluded(mode, R.placement_styles(placement)):
  match mode placement:
    case RawBackground{} C.InFlow{}: Unit{}
    case RawBackground{} C.ComposerEnd{}: ({==}, Unit{})
    case RawBackground{} C.PanelHeaderEnd{}: ({==}, Unit{})
    case RawBackground{} C.CodeToolbar{}: Unit{}
    case RawBackground{} C.BesideValue{}: Unit{}
    case RawBackground{} C.GroupHeadingEnd{}: ({==}, Unit{})
    case PointerBackground{} C.InFlow{}: Unit{}
    case PointerBackground{} C.ComposerEnd{}: ({==}, Unit{})
    case PointerBackground{} C.PanelHeaderEnd{}: ({==}, Unit{})
    case PointerBackground{} C.CodeToolbar{}: Unit{}
    case PointerBackground{} C.BesideValue{}: Unit{}
    case PointerBackground{} C.GroupHeadingEnd{}: ({==}, Unit{})

def excluded_extent(+mode: AttributeMode, +face: C.Face, +size: C.Geometry) -> Excluded(mode, R.content_extent(face, size)):
  match mode face size:
    case RawBackground{} C.IconFace{icon} C.Geometry{width, height, icon, radius, leading}: ({==}, ({==}, ({==}, ({==}, Unit{}))))
    case RawBackground{} C.TextFace{text} C.Geometry{width, height, icon, radius, leading}: ({==}, ({==}, ({==}, Unit{})))
    case RawBackground{} C.IconTextFace{icon, text} C.Geometry{width, height, icon, radius, leading}: ({==}, ({==}, ({==}, Unit{})))
    case RawBackground{} C.PickerFace{leading, text} C.Geometry{width, height, icon, radius, leading}: ({==}, ({==}, ({==}, Unit{})))
    case RawBackground{} C.ChoiceFace{text, checked} C.Geometry{width, height, icon, radius, leading}: ({==}, ({==}, ({==}, Unit{})))
    case RawBackground{} C.DisclosureFace{text, expanded} C.Geometry{width, height, icon, radius, leading}: ({==}, ({==}, ({==}, Unit{})))
    case RawBackground{} C.PermissionFace{filesystem, network, approval} C.Geometry{width, height, icon, radius, leading}: ({==}, ({==}, ({==}, Unit{})))
    case PointerBackground{} C.IconFace{icon} C.Geometry{width, height, icon, radius, leading}: ({==}, ({==}, ({==}, ({==}, Unit{}))))
    case PointerBackground{} C.TextFace{text} C.Geometry{width, height, icon, radius, leading}: ({==}, ({==}, ({==}, Unit{})))
    case PointerBackground{} C.IconTextFace{icon, text} C.Geometry{width, height, icon, radius, leading}: ({==}, ({==}, ({==}, Unit{})))
    case PointerBackground{} C.PickerFace{leading, text} C.Geometry{width, height, icon, radius, leading}: ({==}, ({==}, ({==}, Unit{})))
    case PointerBackground{} C.ChoiceFace{text, checked} C.Geometry{width, height, icon, radius, leading}: ({==}, ({==}, ({==}, Unit{})))
    case PointerBackground{} C.DisclosureFace{text, expanded} C.Geometry{width, height, icon, radius, leading}: ({==}, ({==}, ({==}, Unit{})))
    case PointerBackground{} C.PermissionFace{filesystem, network, approval} C.Geometry{width, height, icon, radius, leading}: ({==}, ({==}, ({==}, Unit{})))

def excluded_content_prefix(+mode: AttributeMode, alignment: C.ContentAlignment, gap: Nat) -> Excluded(mode, [R.property("justify-content", R.content_alignment(alignment)), R.property("align-items", "center"), R.property("gap", R.px(gap))]):
  match mode:
    case RawBackground{}: ({==}, ({==}, ({==}, Unit{})))
    case PointerBackground{}: ({==}, ({==}, ({==}, Unit{})))

def excluded_content_layout(+mode: AttributeMode, +face: C.Face, +size: C.Geometry, layout: C.ContentLayout) ->
  Excluded(mode, R.content_geometry_layout(face, size, layout)):
  C.ContentLayout{+alignment, area, +gap} = layout
  excluded_append(mode, [R.property("justify-content", R.content_alignment(alignment)), R.property("align-items", "center"), R.property("gap", R.px(gap))], R.content_extent(face, size),
    excluded_content_prefix(mode, alignment, gap), excluded_extent(mode, face, size))

def excluded_anchor(+mode: AttributeMode, key: String) -> Excluded(mode, [R.property("anchor-name", R.css_anchor(key))]):
  match mode:
    case RawBackground{}: ({==}, Unit{})
    case PointerBackground{}: ({==}, Unit{})

def geometry_tail(+visual: D.Style, +face: C.Face, +size: C.Geometry, placement: C.Placement, key: String) -> +List<Doc.Property>:
  List.append(&2, Doc.Property, R.action_geometry(size, visual), List.append(&2, Doc.Property, R.placement_styles(placement), List.append(&2, Doc.Property, [R.property("anchor-name", R.css_anchor(key))], R.content_geometry(face, size))))

def excluded_geometry_tail(+mode: AttributeMode, +visual: D.Style, +face: C.Face, +size: C.Geometry, +placement: C.Placement, +key: String) ->
  Excluded(mode, geometry_tail(visual, face, size, placement, key)):
  excluded_append(mode, R.action_geometry(size, visual), List.append(&2, Doc.Property, R.placement_styles(placement), List.append(&2, Doc.Property, [R.property("anchor-name", R.css_anchor(key))], R.content_geometry(face, size))), excluded_geometry(mode, size, visual),
    excluded_append(mode, R.placement_styles(placement), List.append(&2, Doc.Property, [R.property("anchor-name", R.css_anchor(key))], R.content_geometry(face, size)), excluded_placement(mode, placement),
      excluded_append(mode, [R.property("anchor-name", R.css_anchor(key))], R.content_geometry(face, size), excluded_anchor(mode, key), excluded_content_layout(mode, face, size, C.content_layout(face)))))

def action_background_preserved(+key: String, +visual: D.Style, +input: Core.Input, +availability: View.Availability,
  +name: String, +face: C.Face, +behavior: C.Behavior, +geometry: C.Geometry, +placement: C.Placement, +help: C.Help, +feedback: C.Feedback) ->
  {R.attr(Renderer.node_styles(R.action(key, D.Appearance{key, visual, C.NoControl{}, Nil{}}, C.Action{input, availability, name, face, behavior, geometry, placement, help, feedback})), "--native-rest-background") == R.attr(R.style(visual), "background") : String}:
  D.Style{D.TextStyle{+font, +size, +line_height, +weight}, D.Chrome{+foreground, +background, +border, +border_width, +radius, +shadow}, +alignment, +flow, +overflow, +content_frame, +height, +maximum, +states} = visual
  +value: D.Style = D.Style{D.TextStyle{font, size, line_height, weight}, D.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, flow, overflow, content_frame, height, maximum, states}
  +tail: +List<Doc.Property> = style_tail(flow, overflow, shadow, alignment, states)
  +extra: +List<Doc.Property> = geometry_tail(value, face, geometry, placement, key)
  Equal.trans(String,
    R.attr(Renderer.node_styles(R.action(key, D.Appearance{key, value, C.NoControl{}, Nil{}}, C.Action{input, availability, name, face, behavior, geometry, placement, help, feedback})), "--native-rest-background"),
    R.paint(background), R.attr(R.style(value), "background"),
    preserved(PointerBackground{}, List.append(&2, Doc.Property, tail, extra), R.paint(background),
      excluded_append(PointerBackground{}, tail, extra, excluded_style_tail(PointerBackground{}, flow, overflow, shadow, alignment, states), excluded_geometry_tail(PointerBackground{}, value, face, geometry, placement, key))),
    Equal.sym(String, R.attr(R.style(value), "background"), R.paint(background),
      preserved(RawBackground{}, tail, R.paint(background), excluded_style_tail(RawBackground{}, flow, overflow, shadow, alignment, states))))

type Axis is Data:
  Inline{}
  Block{}

def axis_name(axis: Axis) -> String:
  match axis:
    case Inline{}: "padding-inline"
    case Block{}: "padding-block"

def axis_space(axis: Axis, area: E.ContentArea) -> Nat:
  match axis:
    case Inline{}: E.inline(area)
    case Block{}: E.block(area)

def last_append(+first: +List<Doc.Property>, +second: +List<Doc.Property>, +name: String, +previous: String) ->
  {R.attr_last(List.append(&2, Doc.Property, first, second), name, previous) == R.attr_last(second, name, R.attr_last(first, name, previous)) : String}:
  match first:
    case Nil{}: {==}
    case Con{Doc.Property{key, value}, rest}:
      last_append(rest, second, name, R.attr_found(String.eq(key, name), value, previous))
def preserve_flow(+value: D.Flow, +axis: Axis, +previous: String) ->
  {R.attr_last(R.flow(value), axis_name(axis), previous) == previous : String}:
  match value axis:
    case D.BlockFlow{} Inline{}: {==}
    case D.BlockFlow{} Block{}: {==}
    case D.ColumnFlow{} Inline{}: {==}
    case D.ColumnFlow{} Block{}: {==}
    case D.RowFlow{} Inline{}: {==}
    case D.RowFlow{} Block{}: {==}
    case D.SplitRowFlow{} Inline{}: {==}
    case D.SplitRowFlow{} Block{}: {==}
    case D.WrapFlow{} Inline{}: {==}
    case D.WrapFlow{} Block{}: {==}

def preserve_overflow(+value: D.Overflow, +axis: Axis, +previous: String) ->
  {R.attr_last(R.overflow_style(value), axis_name(axis), previous) == previous : String}:
  match value axis:
    case D.ContentFlow{} Inline{}: {==}
    case D.ContentFlow{} Block{}: {==}
    case D.ScrollFlow{} Inline{}: {==}
    case D.ScrollFlow{} Block{}: {==}
    case D.CodeOverflow{} Inline{}: {==}
    case D.CodeOverflow{} Block{}: {==}

def preserve_details(+shadow: Bool, +alignment: D.Alignment, +states: D.ControlStates, +axis: Axis, +previous: String) ->
  {R.attr_last(R.style_details(shadow, alignment, states), axis_name(axis), previous) == previous : String}:
  match shadow alignment states axis:
    case False{} D.Stretch{} D.Passive{} Inline{}: {==}
    case False{} D.Stretch{} D.Passive{} Block{}: {==}
    case False{} D.Stretch{} D.Interactive{D.Chrome{hfg, hbg, hb, hw, hr, hs}, D.Chrome{pfg, pbg, pb, pw, pr, ps}, opacity, ring, width, offset} Inline{}: {==}
    case False{} D.Stretch{} D.Interactive{D.Chrome{hfg, hbg, hb, hw, hr, hs}, D.Chrome{pfg, pbg, pb, pw, pr, ps}, opacity, ring, width, offset} Block{}: {==}
    case False{} D.Leading{} D.Passive{} Inline{}: {==}
    case False{} D.Leading{} D.Passive{} Block{}: {==}
    case False{} D.Leading{} D.Interactive{D.Chrome{hfg, hbg, hb, hw, hr, hs}, D.Chrome{pfg, pbg, pb, pw, pr, ps}, opacity, ring, width, offset} Inline{}: {==}
    case False{} D.Leading{} D.Interactive{D.Chrome{hfg, hbg, hb, hw, hr, hs}, D.Chrome{pfg, pbg, pb, pw, pr, ps}, opacity, ring, width, offset} Block{}: {==}
    case False{} D.Trailing{} D.Passive{} Inline{}: {==}
    case False{} D.Trailing{} D.Passive{} Block{}: {==}
    case False{} D.Trailing{} D.Interactive{D.Chrome{hfg, hbg, hb, hw, hr, hs}, D.Chrome{pfg, pbg, pb, pw, pr, ps}, opacity, ring, width, offset} Inline{}: {==}
    case False{} D.Trailing{} D.Interactive{D.Chrome{hfg, hbg, hb, hw, hr, hs}, D.Chrome{pfg, pbg, pb, pw, pr, ps}, opacity, ring, width, offset} Block{}: {==}
    case False{} D.Centered{} D.Passive{} Inline{}: {==}
    case False{} D.Centered{} D.Passive{} Block{}: {==}
    case False{} D.Centered{} D.Interactive{D.Chrome{hfg, hbg, hb, hw, hr, hs}, D.Chrome{pfg, pbg, pb, pw, pr, ps}, opacity, ring, width, offset} Inline{}: {==}
    case False{} D.Centered{} D.Interactive{D.Chrome{hfg, hbg, hb, hw, hr, hs}, D.Chrome{pfg, pbg, pb, pw, pr, ps}, opacity, ring, width, offset} Block{}: {==}
    case True{} D.Stretch{} D.Passive{} Inline{}: {==}
    case True{} D.Stretch{} D.Passive{} Block{}: {==}
    case True{} D.Stretch{} D.Interactive{D.Chrome{hfg, hbg, hb, hw, hr, hs}, D.Chrome{pfg, pbg, pb, pw, pr, ps}, opacity, ring, width, offset} Inline{}: {==}
    case True{} D.Stretch{} D.Interactive{D.Chrome{hfg, hbg, hb, hw, hr, hs}, D.Chrome{pfg, pbg, pb, pw, pr, ps}, opacity, ring, width, offset} Block{}: {==}
    case True{} D.Leading{} D.Passive{} Inline{}: {==}
    case True{} D.Leading{} D.Passive{} Block{}: {==}
    case True{} D.Leading{} D.Interactive{D.Chrome{hfg, hbg, hb, hw, hr, hs}, D.Chrome{pfg, pbg, pb, pw, pr, ps}, opacity, ring, width, offset} Inline{}: {==}
    case True{} D.Leading{} D.Interactive{D.Chrome{hfg, hbg, hb, hw, hr, hs}, D.Chrome{pfg, pbg, pb, pw, pr, ps}, opacity, ring, width, offset} Block{}: {==}
    case True{} D.Trailing{} D.Passive{} Inline{}: {==}
    case True{} D.Trailing{} D.Passive{} Block{}: {==}
    case True{} D.Trailing{} D.Interactive{D.Chrome{hfg, hbg, hb, hw, hr, hs}, D.Chrome{pfg, pbg, pb, pw, pr, ps}, opacity, ring, width, offset} Inline{}: {==}
    case True{} D.Trailing{} D.Interactive{D.Chrome{hfg, hbg, hb, hw, hr, hs}, D.Chrome{pfg, pbg, pb, pw, pr, ps}, opacity, ring, width, offset} Block{}: {==}
    case True{} D.Centered{} D.Passive{} Inline{}: {==}
    case True{} D.Centered{} D.Passive{} Block{}: {==}
    case True{} D.Centered{} D.Interactive{D.Chrome{hfg, hbg, hb, hw, hr, hs}, D.Chrome{pfg, pbg, pb, pw, pr, ps}, opacity, ring, width, offset} Inline{}: {==}
    case True{} D.Centered{} D.Interactive{D.Chrome{hfg, hbg, hb, hw, hr, hs}, D.Chrome{pfg, pbg, pb, pw, pr, ps}, opacity, ring, width, offset} Block{}: {==}

def preserve_suffix(+flow: D.Flow, +overflow: D.Overflow, +shadow: Bool, +alignment: D.Alignment, +states: D.ControlStates, +axis: Axis, +previous: String) ->
  {R.attr_last(List.append(&2, Doc.Property, R.flow(flow), List.append(&2, Doc.Property, R.overflow_style(overflow), R.style_details(shadow, alignment, states))), axis_name(axis), previous) == previous : String}:
  Equal.trans(String, R.attr_last(List.append(&2, Doc.Property, R.flow(flow), List.append(&2, Doc.Property, R.overflow_style(overflow), R.style_details(shadow, alignment, states))), axis_name(axis), previous), R.attr_last(List.append(&2, Doc.Property, R.overflow_style(overflow), R.style_details(shadow, alignment, states)), axis_name(axis), R.attr_last(R.flow(flow), axis_name(axis), previous)), previous, last_append(R.flow(flow), List.append(&2, Doc.Property, R.overflow_style(overflow), R.style_details(shadow, alignment, states)), axis_name(axis), previous), Equal.trans(String, R.attr_last(List.append(&2, Doc.Property, R.overflow_style(overflow), R.style_details(shadow, alignment, states)), axis_name(axis), R.attr_last(R.flow(flow), axis_name(axis), previous)), R.attr_last(List.append(&2, Doc.Property, R.overflow_style(overflow), R.style_details(shadow, alignment, states)), axis_name(axis), previous), previous, Equal.cong(String, String, (value => R.attr_last(List.append(&2, Doc.Property, R.overflow_style(overflow), R.style_details(shadow, alignment, states)), axis_name(axis), value)), R.attr_last(R.flow(flow), axis_name(axis), previous), previous, preserve_flow(flow, axis, previous)), Equal.trans(String, R.attr_last(List.append(&2, Doc.Property, R.overflow_style(overflow), R.style_details(shadow, alignment, states)), axis_name(axis), previous), R.attr_last(R.style_details(shadow, alignment, states), axis_name(axis), R.attr_last(R.overflow_style(overflow), axis_name(axis), previous)), previous, last_append(R.overflow_style(overflow), R.style_details(shadow, alignment, states), axis_name(axis), previous), Equal.trans(String, R.attr_last(R.style_details(shadow, alignment, states), axis_name(axis), R.attr_last(R.overflow_style(overflow), axis_name(axis), previous)), R.attr_last(R.style_details(shadow, alignment, states), axis_name(axis), previous), previous, Equal.cong(String, String, (value => R.attr_last(R.style_details(shadow, alignment, states), axis_name(axis), value)), R.attr_last(R.overflow_style(overflow), axis_name(axis), previous), previous, preserve_overflow(overflow, axis, previous)), preserve_details(shadow, alignment, states, axis, previous)))))


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

def option_production(+key: String, +label: String, +selected: Bool, description: String, +geometry: C.Geometry, input: Core.Input) -> Doc.Node:
  +representation: C.Representation = C.Action{input, View.Available{}, label, C.ChoiceFace{label, selected}, C.ChoiceRadio{selected}, geometry, C.InFlow{}, C.NoHelp{}, C.Quiet{}}
  R.choice_node(key, label, selected, description, A.control_style(A.ordinary_button(), representation), representation, Nil{})

def title_production(+key: String, editor: User.Editor, +name: String, +text: String) -> Doc.Node:
  +meaning: UI.Meaning = UI.Edit{editor, Forms.CardTitle{}, Forms.SingleLine{}, Forms.TextValue{text}}
  R.input(key, meaning, C.Input{meaning, name, C.TextInput{}, C.AccessibleOnly{}, View.Available{}}, A.style(UI.Field{}, meaning))

def description_production(+key: String, editor: User.Editor, +name: String, +text: String) -> Doc.Node:
  +meaning: UI.Meaning = UI.Edit{editor, Forms.CardDescription{}, Forms.Multiline{}, Forms.TextValue{text}}
  R.input(key, meaning, C.Input{meaning, name, C.TextArea{}, C.AccessibleOnly{}, View.Available{}}, A.style(UI.Field{}, meaning))

def area_properties(+area: E.ContentArea) ->
  {R.content_area_properties(area) == [R.property("padding-inline", R.px(E.inline(area))), R.property("padding-block", R.px(E.block(area))), R.property("box-sizing", "border-box")] : +List<Doc.Property>}:
  {==}

def style_allocation(+value: D.Style, +axis: Axis) ->
  {R.attr(R.style(value), axis_name(axis)) == R.px(axis_space(axis, Model.area(value))) : String}:
  D.Style{D.TextStyle{font, size, line_height, weight}, D.Chrome{fg, bg, border, border_width, radius, shadow}, alignment, flow, overflow, +content_frame, minimum, maximum, states} = value
  match axis:
    case Inline{}: preserve_suffix(flow, overflow, shadow, alignment, states, Inline{}, R.px(E.inline(E.frame_content(content_frame))))
    case Block{}: preserve_suffix(flow, overflow, shadow, alignment, states, Block{}, R.px(E.block(E.frame_content(content_frame))))

def duplicate(+name: String, +old: String, +new: String) ->
  {R.attr([R.property(name, old), R.property(name, new)], name) == new : String}:
  Equal.cong(Bool, String, (same => duplicate_value(same, old, new)), String.eq(name, name), True{}, same_string(name))

def geometry_height(+size: C.Geometry, +visual: D.Style) ->
  {R.attr(R.action_geometry(size, visual), "min-height") == R.px(Model.minimum(visual)) : String}:
  C.Geometry{width, height, icon, radius, leading} = size
  D.Style{text, chrome, alignment, flow, overflow, +content_frame, minimum, maximum, states} = visual
  {==}

def navigation_header(+selected: Bool) ->
  {(R.attr(R.project_header_styles(selected), "padding-inline"), R.attr(R.project_header_styles(selected), "padding-block")) == ("8px", "4px") : (String & String)}:
  match selected:
    case False{}: {==}
    case True{}: {==}

def navigation_task(+selected: Bool, +key: String, +task: Nat, +status: String, +children: +List<Doc.Node>, +appearances: +List<D.Appearance>) ->
  {(R.attr(Renderer.node_styles(R.task_row_node(key, task, status, selected, children, appearances)), "padding-inline"), R.attr(Renderer.node_styles(R.task_row_node(key, task, status, selected, children, appearances)), "padding-block")) == ("8px", "4px") : (String & String)}:
  match selected:
    case False{}: {==}
    case True{}: {==}

def embedded_name() ->
  {(R.attr(R.project_name_styles(), "padding-inline"), R.attr(R.project_name_styles(), "padding-block")) == ("0px", "0px") : (String & String)}:
  {==}

def icon_control(+width: String) ->
  {(R.attr(R.project_icon_styles(width), "padding-inline"), R.attr(R.project_icon_styles(width), "padding-block")) == ("4px", "4px") : (String & String)}:
  {==}

def card_title() ->
  {(R.attr(BoardLaws.title_production_styles(), "padding-inline"), R.attr(BoardLaws.title_production_styles(), "padding-block")) == ("8px", "4px") : (String & String)}:
  {==}

def search(+filter: Board.Filter) ->
  {(R.attr(R.input_style_for(UI.BoardSearch{filter}, C.SearchInput{}), "padding-inline"), R.attr(R.input_style_for(UI.BoardSearch{filter}, C.SearchInput{}), "padding-block")) == ("8px", "4px") : (String & String)}:
  {==}

def dialog_header() ->
  {(R.attr(R.dialog_header_styles(), "padding-inline"), R.attr(R.dialog_header_styles(), "padding-block")) == ("24px", "14px") : (String & String)}:
  {==}

def dialog_body() ->
  {(R.attr(R.dialog_body_styles(), "padding-inline"), R.attr(R.dialog_body_styles(), "padding-block")) == ("24px", "20px") : (String & String)}:
  {==}

def dialog_footer() ->
  {(R.attr(R.dialog_footer_styles(), "padding-inline"), R.attr(R.dialog_footer_styles(), "padding-block")) == ("24px", "12px") : (String & String)}:
  {==}

def empty_overwrite(+name: String, +old: String) ->
  {R.attr([R.property(name, old), R.property(name, "")], name) == "" : String}:
  duplicate(name, old, "")

def option_production_insets(+key: String, +label: String, +selected: Bool, +description: String, +geometry: C.Geometry, +input: Core.Input) ->
  {(R.attr(Renderer.node_styles(option_production(key, label, selected, description, geometry, input)), "padding-inline"), R.attr(Renderer.node_styles(option_production(key, label, selected, description, geometry, input)), "padding-block")) == ("8px", "8px") : (String & String)}:
  match selected geometry:
    case False{} C.Geometry{width, height, icon, radius, leading}: {==}
    case True{} C.Geometry{width, height, icon, radius, leading}: {==}

def title_production_insets(+key: String, +editor: User.Editor, +name: String, +text: String) ->
  {(R.attr(Renderer.node_styles(title_production(key, editor, name, text)), "padding-inline"), R.attr(Renderer.node_styles(title_production(key, editor, name, text)), "padding-block")) == ("8px", "6px") : (String & String)}:
  match editor:
    case User.NewTaskEditor{}: {==}
    case User.MessageEditor{task}: {==}
    case User.ProjectEditor{project}: {==}
    case User.CardEditor{card}: {==}
    case User.AgentEditor{agent}: {==}
    case User.ForkEditor{task}: {==}
    case User.CompactEditor{task}: {==}

def description_production_insets(+key: String, +editor: User.Editor, +name: String, +text: String) ->
  {(R.attr(Renderer.node_styles(description_production(key, editor, name, text)), "padding-inline"), R.attr(Renderer.node_styles(description_production(key, editor, name, text)), "padding-block")) == ("8px", "6px") : (String & String)}:
  match editor:
    case User.NewTaskEditor{}: {==}
    case User.MessageEditor{task}: {==}
    case User.ProjectEditor{project}: {==}
    case User.CardEditor{card}: {==}
    case User.AgentEditor{agent}: {==}
    case User.ForkEditor{task}: {==}
    case User.CompactEditor{task}: {==}

def dialog_outer() ->
  {(R.attr(R.style(A.style(UI.Dialog{}, UI.Region{})), "padding-inline"), R.attr(R.style(A.style(UI.Dialog{}, UI.Region{})), "padding-block")) == ("0px", "0px") : (String & String)}:
  {==}

def geometry_complete(+width: Nat, +height: Nat, +icon: Nat, +radius: Nat, +leading: Nat, +visual: D.Style) ->
  {R.action_geometry(C.Geometry{width, height, icon, radius, leading}, visual) == [R.property("min-width", R.px(width)), R.property("min-height", R.px(Model.minimum(visual))), R.property("border-radius", R.px(radius)), R.property("display", "inline-flex"), R.property("align-items", "center"), R.property("--native-icon-size", R.px(icon)), R.property("--native-leading-slot", R.px(leading))] : +List<Doc.Property>}:
  D.Style{text, chrome, alignment, flow, overflow, +content_frame, minimum, maximum, states} = visual
  {==}

type Requirements is Type:
  Requirements{area_properties: @+area:E.ContentArea -> {R.content_area_properties(area) == [R.property("padding-inline", R.px(E.inline(area))), R.property("padding-block", R.px(E.block(area))), R.property("box-sizing", "border-box")] : +List<Doc.Property>},
    style_allocation: @+value:D.Style -> @+axis:Axis -> {R.attr(R.style(value), axis_name(axis)) == R.px(axis_space(axis, Model.area(value))) : String},
    duplicate: @+name:String -> @+old:String -> @+new:String -> {R.attr([R.property(name, old), R.property(name, new)], name) == new : String},
    geometry_height: @+size:C.Geometry -> @+visual:D.Style -> {R.attr(R.action_geometry(size, visual), "min-height") == R.px(Model.minimum(visual)) : String},
    navigation_header: @+selected:Bool -> {(R.attr(R.project_header_styles(selected), "padding-inline"), R.attr(R.project_header_styles(selected), "padding-block")) == ("8px", "4px") : (String & String)},
    navigation_task: @+selected:Bool -> @+key:String -> @+task:Nat -> @+status:String -> @+children:+List<Doc.Node> -> @+appearances:+List<D.Appearance> -> {(R.attr(Renderer.node_styles(R.task_row_node(key, task, status, selected, children, appearances)), "padding-inline"), R.attr(Renderer.node_styles(R.task_row_node(key, task, status, selected, children, appearances)), "padding-block")) == ("8px", "4px") : (String & String)},
    embedded_name: {(R.attr(R.project_name_styles(), "padding-inline"), R.attr(R.project_name_styles(), "padding-block")) == ("0px", "0px") : (String & String)},
    icon_control: @+width:String -> {(R.attr(R.project_icon_styles(width), "padding-inline"), R.attr(R.project_icon_styles(width), "padding-block")) == ("4px", "4px") : (String & String)},
    card_title: {(R.attr(BoardLaws.title_production_styles(), "padding-inline"), R.attr(BoardLaws.title_production_styles(), "padding-block")) == ("8px", "4px") : (String & String)},
    search: @+filter:Board.Filter -> {(R.attr(R.input_style_for(UI.BoardSearch{filter}, C.SearchInput{}), "padding-inline"), R.attr(R.input_style_for(UI.BoardSearch{filter}, C.SearchInput{}), "padding-block")) == ("8px", "4px") : (String & String)},
    dialog_header: {(R.attr(R.dialog_header_styles(), "padding-inline"), R.attr(R.dialog_header_styles(), "padding-block")) == ("24px", "14px") : (String & String)},
    dialog_body: {(R.attr(R.dialog_body_styles(), "padding-inline"), R.attr(R.dialog_body_styles(), "padding-block")) == ("24px", "20px") : (String & String)},
    dialog_footer: {(R.attr(R.dialog_footer_styles(), "padding-inline"), R.attr(R.dialog_footer_styles(), "padding-block")) == ("24px", "12px") : (String & String)},
    empty_overwrite: @+name:String -> @+old:String -> {R.attr([R.property(name, old), R.property(name, "")], name) == "" : String},
    option_production_insets: @+key:String -> @+label:String -> @+selected:Bool -> @+description:String -> @+geometry:C.Geometry -> @+input:Core.Input -> {(R.attr(Renderer.node_styles(option_production(key, label, selected, description, geometry, input)), "padding-inline"), R.attr(Renderer.node_styles(option_production(key, label, selected, description, geometry, input)), "padding-block")) == ("8px", "8px") : (String & String)},
    title_production_insets: @+key:String -> @+editor:User.Editor -> @+name:String -> @+text:String -> {(R.attr(Renderer.node_styles(title_production(key, editor, name, text)), "padding-inline"), R.attr(Renderer.node_styles(title_production(key, editor, name, text)), "padding-block")) == ("8px", "6px") : (String & String)},
    description_production_insets: @+key:String -> @+editor:User.Editor -> @+name:String -> @+text:String -> {(R.attr(Renderer.node_styles(description_production(key, editor, name, text)), "padding-inline"), R.attr(Renderer.node_styles(description_production(key, editor, name, text)), "padding-block")) == ("8px", "6px") : (String & String)},
    dialog_outer: {(R.attr(R.style(A.style(UI.Dialog{}, UI.Region{})), "padding-inline"), R.attr(R.style(A.style(UI.Dialog{}, UI.Region{})), "padding-block")) == ("0px", "0px") : (String & String)},
    geometry_complete: @+width:Nat -> @+height:Nat -> @+icon:Nat -> @+radius:Nat -> @+leading:Nat -> @+visual:D.Style -> {R.action_geometry(C.Geometry{width, height, icon, radius, leading}, visual) == [R.property("min-width", R.px(width)), R.property("min-height", R.px(Model.minimum(visual))), R.property("border-radius", R.px(radius)), R.property("display", "inline-flex"), R.property("align-items", "center"), R.property("--native-icon-size", R.px(icon)), R.property("--native-leading-slot", R.px(leading))] : +List<Doc.Property>}}

def evidence() -> Requirements:
  Requirements{area_properties, style_allocation, duplicate, geometry_height, navigation_header, navigation_task, embedded_name(), icon_control, card_title(), search, dialog_header(), dialog_body(), dialog_footer(), empty_overwrite, option_production_insets, title_production_insets, description_production_insets, dialog_outer(), geometry_complete}
