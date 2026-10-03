import Base
import ./typography.bend as T
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
    case RawBackground{} D.InlineControlFlow{alignment}: ({==}, ({==}, ({==}, ({==}, Unit{}))))
    case RawBackground{} D.ChoiceFlow{}: ({==}, ({==}, ({==}, ({==}, Unit{}))))
    case PointerBackground{} D.BlockFlow{}: ({==}, Unit{})
    case PointerBackground{} D.ColumnFlow{}: ({==}, ({==}, Unit{}))
    case PointerBackground{} D.RowFlow{}: ({==}, ({==}, Unit{}))
    case PointerBackground{} D.SplitRowFlow{}: ({==}, ({==}, ({==}, Unit{})))
    case PointerBackground{} D.WrapFlow{}: ({==}, ({==}, Unit{}))
    case PointerBackground{} D.InlineControlFlow{alignment}: ({==}, ({==}, ({==}, ({==}, Unit{}))))
    case PointerBackground{} D.ChoiceFlow{}: ({==}, ({==}, ({==}, ({==}, Unit{}))))

def excluded_overflow(+mode: AttributeMode, +overflow: D.Overflow) -> Excluded(mode, R.overflow_style(overflow)):
  match mode overflow:
    case RawBackground{} D.ContentFlow{}: Unit{}
    case RawBackground{} D.ScrollFlow{}: ({==}, Unit{})
    case RawBackground{} D.CodeOverflow{}: ({==}, Unit{})
    case RawBackground{} D.SingleLineOverflow{}: ({==}, ({==}, ({==}, Unit{})))
    case PointerBackground{} D.ContentFlow{}: Unit{}
    case PointerBackground{} D.ScrollFlow{}: ({==}, Unit{})
    case PointerBackground{} D.CodeOverflow{}: ({==}, Unit{})
    case PointerBackground{} D.SingleLineOverflow{}: ({==}, ({==}, ({==}, Unit{})))

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
    case RawBackground{} D.Interactive{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}, opacity, ring, width, offset}: ({==}, ({==}, ({==}, ({==}, ({==}, ({==}, ({==}, ({==}, Unit{}))))))))
    case RawBackground{} D.SurfaceFeedback{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}}: ({==}, ({==}, ({==}, ({==}, Unit{}))))
    case PointerBackground{} D.Passive{}: Unit{}
    case PointerBackground{} D.Interactive{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}, opacity, ring, width, offset}: ({==}, ({==}, ({==}, ({==}, ({==}, ({==}, ({==}, ({==}, Unit{}))))))))
    case PointerBackground{} D.SurfaceFeedback{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}}: ({==}, ({==}, ({==}, ({==}, Unit{}))))

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

def excluded_typography(+mode: AttributeMode, +value: T.Presentation) -> Excluded(mode, R.text_presentation(value)):
  match mode:
    case RawBackground{}: ({==}, ({==}, ({==}, ({==}, Unit{}))))
    case PointerBackground{}: ({==}, ({==}, ({==}, ({==}, Unit{}))))

def typed_style_tail(+value: T.Presentation, flow: D.Flow, overflow: D.Overflow, shadow: Bool, alignment: D.Alignment, states: D.ControlStates) -> +List<Doc.Property>:
  List.append(&2, Doc.Property, style_tail(flow, overflow, shadow, alignment, states), R.text_presentation(value))

def excluded_typed_tail(+mode: AttributeMode, +value: T.Presentation, +flow: D.Flow, +overflow: D.Overflow, +shadow: Bool, +alignment: D.Alignment, +states: D.ControlStates) -> Excluded(mode, typed_style_tail(value, flow, overflow, shadow, alignment, states)):
  excluded_append(mode, style_tail(flow, overflow, shadow, alignment, states), R.text_presentation(value), excluded_style_tail(mode, flow, overflow, shadow, alignment, states), excluded_typography(mode, value))

def excluded_geometry(+mode: AttributeMode, +size: C.Geometry, +visual: D.Style) -> Excluded(mode, R.action_geometry(size, visual)):
  match mode size visual:
    case RawBackground{} C.Geometry{width, height, icon, radius, leading} D.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states}: ({==}, ({==}, ({==}, Unit{})))
    case PointerBackground{} C.Geometry{width, height, icon, radius, leading} D.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states}: ({==}, ({==}, ({==}, Unit{})))

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
    case RawBackground{} C.SingleLineFace{text} C.Geometry{width, height, icon, radius, leading}: ({==}, ({==}, ({==}, Unit{})))
    case RawBackground{} C.IconTextFace{icon, text} C.Geometry{width, height, icon, radius, leading}: ({==}, ({==}, ({==}, Unit{})))
    case RawBackground{} C.PickerFace{leading, text} C.Geometry{width, height, icon, radius, leading}: ({==}, ({==}, ({==}, Unit{})))
    case RawBackground{} C.ChoiceFace{text, checked} C.Geometry{width, height, icon, radius, leading}: ({==}, ({==}, ({==}, Unit{})))
    case RawBackground{} C.DisclosureFace{text, expanded} C.Geometry{width, height, icon, radius, leading}: ({==}, ({==}, ({==}, Unit{})))
    case RawBackground{} C.PermissionFace{filesystem, network, approval} C.Geometry{width, height, icon, radius, leading}: ({==}, ({==}, ({==}, Unit{})))
    case PointerBackground{} C.IconFace{icon} C.Geometry{width, height, icon, radius, leading}: ({==}, ({==}, ({==}, ({==}, Unit{}))))
    case PointerBackground{} C.TextFace{text} C.Geometry{width, height, icon, radius, leading}: ({==}, ({==}, ({==}, Unit{})))
    case PointerBackground{} C.SingleLineFace{text} C.Geometry{width, height, icon, radius, leading}: ({==}, ({==}, ({==}, Unit{})))
    case PointerBackground{} C.IconTextFace{icon, text} C.Geometry{width, height, icon, radius, leading}: ({==}, ({==}, ({==}, Unit{})))
    case PointerBackground{} C.PickerFace{leading, text} C.Geometry{width, height, icon, radius, leading}: ({==}, ({==}, ({==}, Unit{})))
    case PointerBackground{} C.ChoiceFace{text, checked} C.Geometry{width, height, icon, radius, leading}: ({==}, ({==}, ({==}, Unit{})))
    case PointerBackground{} C.DisclosureFace{text, expanded} C.Geometry{width, height, icon, radius, leading}: ({==}, ({==}, ({==}, Unit{})))
    case PointerBackground{} C.PermissionFace{filesystem, network, approval} C.Geometry{width, height, icon, radius, leading}: ({==}, ({==}, ({==}, Unit{})))

def excluded_content_layout(+mode: AttributeMode, +face: C.Face, +size: C.Geometry, layout: C.ContentLayout) ->
  Excluded(mode, R.content_geometry_layout(face, size, layout)):
  C.ContentLayout{alignment, area, gap} = layout
  excluded_extent(mode, face, size)

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
  {R.attr(Doc.element_styles(R.action(key, visual, C.Action{input, availability, name, face, behavior, geometry, placement, help, feedback})), "--native-rest-background") == R.attr(R.style(visual), "background") : String}:
  D.Style{+actual_text, D.Chrome{+foreground, +background, +border, +border_width, +radius, +shadow}, +alignment, +flow, +overflow, +content_frame, +height, +maximum, +states} = visual
  +value: D.Style = D.Style{actual_text, D.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, flow, overflow, content_frame, height, maximum, states}
  +tail: +List<Doc.Property> = typed_style_tail(actual_text, flow, overflow, shadow, alignment, states)
  +extra: +List<Doc.Property> = geometry_tail(value, face, geometry, placement, key)
  Equal.trans(String,
    R.attr(Doc.element_styles(R.action(key, value, C.Action{input, availability, name, face, behavior, geometry, placement, help, feedback})), "--native-rest-background"),
    R.paint(background), R.attr(R.style(value), "background"),
    preserved(PointerBackground{}, List.append(&2, Doc.Property, tail, extra), R.paint(background),
      excluded_append(PointerBackground{}, tail, extra, excluded_typed_tail(PointerBackground{}, actual_text, flow, overflow, shadow, alignment, states), excluded_geometry_tail(PointerBackground{}, value, face, geometry, placement, key))),
    Equal.sym(String, R.attr(R.style(value), "background"), R.paint(background),
      preserved(RawBackground{}, tail, R.paint(background), excluded_typed_tail(RawBackground{}, actual_text, flow, overflow, shadow, alignment, states))))

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
    case D.InlineControlFlow{alignment} Inline{}: {==}
    case D.InlineControlFlow{alignment} Block{}: {==}
    case D.ChoiceFlow{} Inline{}: {==}
    case D.ChoiceFlow{} Block{}: {==}

def preserve_overflow(+value: D.Overflow, +axis: Axis, +previous: String) ->
  {R.attr_last(R.overflow_style(value), axis_name(axis), previous) == previous : String}:
  match value axis:
    case D.ContentFlow{} Inline{}: {==}
    case D.ContentFlow{} Block{}: {==}
    case D.ScrollFlow{} Inline{}: {==}
    case D.ScrollFlow{} Block{}: {==}
    case D.CodeOverflow{} Inline{}: {==}
    case D.SingleLineOverflow{} Inline{}: {==}
    case D.CodeOverflow{} Block{}: {==}
    case D.SingleLineOverflow{} Block{}: {==}

def preserve_details(+shadow: Bool, +alignment: D.Alignment, +states: D.ControlStates, +axis: Axis, +previous: String) ->
  {R.attr_last(R.style_details(shadow, alignment, states), axis_name(axis), previous) == previous : String}:
  match shadow alignment states axis:
    case False{} D.Stretch{} D.Passive{} Inline{}: {==}
    case False{} D.Stretch{} D.Passive{} Block{}: {==}
    case False{} D.Stretch{} D.Interactive{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}, opacity, ring, width, offset} Inline{}: {==}
    case False{} D.Stretch{} D.SurfaceFeedback{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}} Inline{}: {==}
    case False{} D.Stretch{} D.Interactive{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}, opacity, ring, width, offset} Block{}: {==}
    case False{} D.Stretch{} D.SurfaceFeedback{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}} Block{}: {==}
    case False{} D.Leading{} D.Passive{} Inline{}: {==}
    case False{} D.Leading{} D.Passive{} Block{}: {==}
    case False{} D.Leading{} D.Interactive{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}, opacity, ring, width, offset} Inline{}: {==}
    case False{} D.Leading{} D.SurfaceFeedback{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}} Inline{}: {==}
    case False{} D.Leading{} D.Interactive{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}, opacity, ring, width, offset} Block{}: {==}
    case False{} D.Leading{} D.SurfaceFeedback{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}} Block{}: {==}
    case False{} D.Trailing{} D.Passive{} Inline{}: {==}
    case False{} D.Trailing{} D.Passive{} Block{}: {==}
    case False{} D.Trailing{} D.Interactive{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}, opacity, ring, width, offset} Inline{}: {==}
    case False{} D.Trailing{} D.SurfaceFeedback{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}} Inline{}: {==}
    case False{} D.Trailing{} D.Interactive{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}, opacity, ring, width, offset} Block{}: {==}
    case False{} D.Trailing{} D.SurfaceFeedback{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}} Block{}: {==}
    case False{} D.Centered{} D.Passive{} Inline{}: {==}
    case False{} D.Centered{} D.Passive{} Block{}: {==}
    case False{} D.Centered{} D.Interactive{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}, opacity, ring, width, offset} Inline{}: {==}
    case False{} D.Centered{} D.SurfaceFeedback{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}} Inline{}: {==}
    case False{} D.Centered{} D.Interactive{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}, opacity, ring, width, offset} Block{}: {==}
    case False{} D.Centered{} D.SurfaceFeedback{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}} Block{}: {==}
    case True{} D.Stretch{} D.Passive{} Inline{}: {==}
    case True{} D.Stretch{} D.Passive{} Block{}: {==}
    case True{} D.Stretch{} D.Interactive{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}, opacity, ring, width, offset} Inline{}: {==}
    case True{} D.Stretch{} D.SurfaceFeedback{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}} Inline{}: {==}
    case True{} D.Stretch{} D.Interactive{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}, opacity, ring, width, offset} Block{}: {==}
    case True{} D.Stretch{} D.SurfaceFeedback{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}} Block{}: {==}
    case True{} D.Leading{} D.Passive{} Inline{}: {==}
    case True{} D.Leading{} D.Passive{} Block{}: {==}
    case True{} D.Leading{} D.Interactive{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}, opacity, ring, width, offset} Inline{}: {==}
    case True{} D.Leading{} D.SurfaceFeedback{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}} Inline{}: {==}
    case True{} D.Leading{} D.Interactive{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}, opacity, ring, width, offset} Block{}: {==}
    case True{} D.Leading{} D.SurfaceFeedback{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}} Block{}: {==}
    case True{} D.Trailing{} D.Passive{} Inline{}: {==}
    case True{} D.Trailing{} D.Passive{} Block{}: {==}
    case True{} D.Trailing{} D.Interactive{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}, opacity, ring, width, offset} Inline{}: {==}
    case True{} D.Trailing{} D.SurfaceFeedback{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}} Inline{}: {==}
    case True{} D.Trailing{} D.Interactive{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}, opacity, ring, width, offset} Block{}: {==}
    case True{} D.Trailing{} D.SurfaceFeedback{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}} Block{}: {==}
    case True{} D.Centered{} D.Passive{} Inline{}: {==}
    case True{} D.Centered{} D.Passive{} Block{}: {==}
    case True{} D.Centered{} D.Interactive{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}, opacity, ring, width, offset} Inline{}: {==}
    case True{} D.Centered{} D.SurfaceFeedback{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}} Inline{}: {==}
    case True{} D.Centered{} D.Interactive{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}, opacity, ring, width, offset} Block{}: {==}
    case True{} D.Centered{} D.SurfaceFeedback{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}} Block{}: {==}

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

def option_production(+key: String, +label: String, +selected: Bool, description: String, +geometry: C.Geometry, input: Core.Input, +typography: T.Presentation) -> Doc.Node:
  +representation: C.Representation = C.Action{input, View.Available{}, label, C.ChoiceFace{label, selected}, C.ChoiceRadio{selected}, geometry, C.InFlow{}, C.NoHelp{}, C.Quiet{}}
  R.choice_node(key, label, selected, description, A.control_style(A.ordinary_button(typography), representation, typography), representation, Nil{}, typography)

def title_production(+key: String, editor: User.Editor, +name: String, +text: String, choices: +List<Forms.ChoiceValue>, +typography: T.Presentation) -> Doc.Node:
  +meaning: UI.Meaning = UI.Edit{editor, Forms.CardTitle{}, Forms.SingleLine{}, Forms.TextValue{text}, choices}
  R.input(key, meaning, C.Input{meaning, name, C.TextInput{}, C.AccessibleOnly{}, View.Available{}}, A.style(UI.Field{}, meaning, typography))

def description_production(+key: String, editor: User.Editor, +name: String, +text: String, choices: +List<Forms.ChoiceValue>, +typography: T.Presentation) -> Doc.Node:
  +meaning: UI.Meaning = UI.Edit{editor, Forms.CardDescription{}, Forms.Multiline{}, Forms.TextValue{text}, choices}
  R.input(key, meaning, C.Input{meaning, name, C.TextArea{}, C.AccessibleOnly{}, View.Available{}}, A.style(UI.Field{}, meaning, typography))



def preserve_typography(+value: T.Presentation, +axis: Axis, +previous: String) ->
  {R.attr_last(R.text_presentation(value), axis_name(axis), previous) == previous : String}:
  match axis:
    case Inline{}: {==}
    case Block{}: {==}

def preserve_typed_suffix(+value: T.Presentation, +flow: D.Flow, +overflow: D.Overflow, +shadow: Bool, +alignment: D.Alignment, +states: D.ControlStates, +axis: Axis, +previous: String) ->
  {R.attr_last(typed_style_tail(value, flow, overflow, shadow, alignment, states), axis_name(axis), previous) == previous : String}:
  Equal.trans(String, R.attr_last(typed_style_tail(value, flow, overflow, shadow, alignment, states), axis_name(axis), previous),
    R.attr_last(R.text_presentation(value), axis_name(axis), R.attr_last(style_tail(flow, overflow, shadow, alignment, states), axis_name(axis), previous)), previous,
    last_append(style_tail(flow, overflow, shadow, alignment, states), R.text_presentation(value), axis_name(axis), previous),
    Equal.trans(String, R.attr_last(R.text_presentation(value), axis_name(axis), R.attr_last(style_tail(flow, overflow, shadow, alignment, states), axis_name(axis), previous)), R.attr_last(style_tail(flow, overflow, shadow, alignment, states), axis_name(axis), previous), previous,
      preserve_typography(value, axis, R.attr_last(style_tail(flow, overflow, shadow, alignment, states), axis_name(axis), previous)), preserve_suffix(flow, overflow, shadow, alignment, states, axis, previous)))

def style_allocation(+value: D.Style, +axis: Axis) ->
  {R.attr(R.style(value), axis_name(axis)) == R.px(axis_space(axis, Model.area(value))) : String}:
  D.Style{actual_text, D.Chrome{fg, bg, border, border_width, radius, shadow}, alignment, flow, overflow, +content_frame, minimum, maximum, states} = value
  match axis:
    case Inline{}: preserve_typed_suffix(actual_text, flow, overflow, shadow, alignment, states, Inline{}, R.px(E.inline(E.frame_content(content_frame))))
    case Block{}: preserve_typed_suffix(actual_text, flow, overflow, shadow, alignment, states, Block{}, R.px(E.block(E.frame_content(content_frame))))

def duplicate(+name: String, +old: String, +new: String) ->
  {R.attr([R.property(name, old), R.property(name, new)], name) == new : String}:
  Equal.cong(Bool, String, (same => duplicate_value(same, old, new)), String.eq(name, name), True{}, same_string(name))

# These parent properties are emitted by Style; control decoration preserves them.
type ParentProperty is Data:
  FrameGap{}
  MinimumHeight{}
  BorderRadius{}

def parent_name(value: ParentProperty) -> String:
  match value:
    case FrameGap{}: "gap"
    case MinimumHeight{}: "min-height"
    case BorderRadius{}: "border-radius"

def parent_value(value: D.Style, property: ParentProperty) -> String:
  D.Style{text, D.Chrome{fg, bg, border, width, radius, shadow}, alignment, flow, overflow, +frame, minimum, maximum, states} = value
  match property:
    case FrameGap{}: R.px(E.frame_gap(frame))
    case MinimumHeight{}: R.px(minimum)
    case BorderRadius{}: R.px(radius)

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

def parent_append(+pointer: Bool, +property: ParentProperty, +first: +List<Doc.Property>, +second: +List<Doc.Property>, +previous: String, +next: String,
  first_evidence: {R.attr_last(parent_properties(pointer, first), parent_name(property), previous) == next : String},
  second_evidence: {R.attr_last(parent_properties(pointer, second), parent_name(property), next) == next : String}) ->
  {R.attr_last(parent_properties(pointer, List.append(&2, Doc.Property, first, second)), parent_name(property), previous) == next : String}:
  Equal.trans(String,
    R.attr_last(parent_properties(pointer, List.append(&2, Doc.Property, first, second)), parent_name(property), previous),
    R.attr_last(List.append(&2, Doc.Property, parent_properties(pointer, first), parent_properties(pointer, second)), parent_name(property), previous), next,
    Equal.cong(+List<Doc.Property>, String, (values => R.attr_last(values, parent_name(property), previous)),
      parent_properties(pointer, List.append(&2, Doc.Property, first, second)), List.append(&2, Doc.Property, parent_properties(pointer, first), parent_properties(pointer, second)),
      parent_properties_append(pointer, first, second)),
    Equal.trans(String,
      R.attr_last(List.append(&2, Doc.Property, parent_properties(pointer, first), parent_properties(pointer, second)), parent_name(property), previous),
      R.attr_last(parent_properties(pointer, second), parent_name(property), R.attr_last(parent_properties(pointer, first), parent_name(property), previous)), next,
      last_append(parent_properties(pointer, first), parent_properties(pointer, second), parent_name(property), previous),
      Equal.trans(String,
        R.attr_last(parent_properties(pointer, second), parent_name(property), R.attr_last(parent_properties(pointer, first), parent_name(property), previous)),
        R.attr_last(parent_properties(pointer, second), parent_name(property), next), next,
        Equal.cong(String, String, (old => R.attr_last(parent_properties(pointer, second), parent_name(property), old)),
          R.attr_last(parent_properties(pointer, first), parent_name(property), previous), next, first_evidence), second_evidence)))

def parent_flow(+pointer: Bool, +property: ParentProperty, value: D.Flow, +previous: String) ->
  {R.attr_last(parent_properties(pointer, R.flow(value)), parent_name(property), previous) == previous : String}:
  match pointer property value:
    case False{} FrameGap{} D.BlockFlow{}: {==}
    case False{} FrameGap{} D.ColumnFlow{}: {==}
    case False{} FrameGap{} D.RowFlow{}: {==}
    case False{} FrameGap{} D.SplitRowFlow{}: {==}
    case False{} FrameGap{} D.WrapFlow{}: {==}
    case False{} FrameGap{} D.InlineControlFlow{alignment}: {==}
    case False{} FrameGap{} D.ChoiceFlow{}: {==}
    case False{} MinimumHeight{} D.BlockFlow{}: {==}
    case False{} MinimumHeight{} D.ColumnFlow{}: {==}
    case False{} MinimumHeight{} D.RowFlow{}: {==}
    case False{} MinimumHeight{} D.SplitRowFlow{}: {==}
    case False{} MinimumHeight{} D.WrapFlow{}: {==}
    case False{} MinimumHeight{} D.InlineControlFlow{alignment}: {==}
    case False{} MinimumHeight{} D.ChoiceFlow{}: {==}
    case False{} BorderRadius{} D.BlockFlow{}: {==}
    case False{} BorderRadius{} D.ColumnFlow{}: {==}
    case False{} BorderRadius{} D.RowFlow{}: {==}
    case False{} BorderRadius{} D.SplitRowFlow{}: {==}
    case False{} BorderRadius{} D.WrapFlow{}: {==}
    case False{} BorderRadius{} D.InlineControlFlow{alignment}: {==}
    case False{} BorderRadius{} D.ChoiceFlow{}: {==}
    case True{} FrameGap{} D.BlockFlow{}: {==}
    case True{} FrameGap{} D.ColumnFlow{}: {==}
    case True{} FrameGap{} D.RowFlow{}: {==}
    case True{} FrameGap{} D.SplitRowFlow{}: {==}
    case True{} FrameGap{} D.WrapFlow{}: {==}
    case True{} FrameGap{} D.InlineControlFlow{alignment}: {==}
    case True{} FrameGap{} D.ChoiceFlow{}: {==}
    case True{} MinimumHeight{} D.BlockFlow{}: {==}
    case True{} MinimumHeight{} D.ColumnFlow{}: {==}
    case True{} MinimumHeight{} D.RowFlow{}: {==}
    case True{} MinimumHeight{} D.SplitRowFlow{}: {==}
    case True{} MinimumHeight{} D.WrapFlow{}: {==}
    case True{} MinimumHeight{} D.InlineControlFlow{alignment}: {==}
    case True{} MinimumHeight{} D.ChoiceFlow{}: {==}
    case True{} BorderRadius{} D.BlockFlow{}: {==}
    case True{} BorderRadius{} D.ColumnFlow{}: {==}
    case True{} BorderRadius{} D.RowFlow{}: {==}
    case True{} BorderRadius{} D.SplitRowFlow{}: {==}
    case True{} BorderRadius{} D.WrapFlow{}: {==}
    case True{} BorderRadius{} D.InlineControlFlow{alignment}: {==}
    case True{} BorderRadius{} D.ChoiceFlow{}: {==}

def parent_overflow(+pointer: Bool, +property: ParentProperty, value: D.Overflow, +previous: String) ->
  {R.attr_last(parent_properties(pointer, R.overflow_style(value)), parent_name(property), previous) == previous : String}:
  match pointer property value:
    case False{} FrameGap{} D.ContentFlow{}: {==}
    case False{} FrameGap{} D.ScrollFlow{}: {==}
    case False{} FrameGap{} D.CodeOverflow{}: {==}
    case False{} FrameGap{} D.SingleLineOverflow{}: {==}
    case False{} MinimumHeight{} D.ContentFlow{}: {==}
    case False{} MinimumHeight{} D.ScrollFlow{}: {==}
    case False{} MinimumHeight{} D.CodeOverflow{}: {==}
    case False{} MinimumHeight{} D.SingleLineOverflow{}: {==}
    case False{} BorderRadius{} D.ContentFlow{}: {==}
    case False{} BorderRadius{} D.ScrollFlow{}: {==}
    case False{} BorderRadius{} D.CodeOverflow{}: {==}
    case False{} BorderRadius{} D.SingleLineOverflow{}: {==}
    case True{} FrameGap{} D.ContentFlow{}: {==}
    case True{} FrameGap{} D.ScrollFlow{}: {==}
    case True{} FrameGap{} D.CodeOverflow{}: {==}
    case True{} FrameGap{} D.SingleLineOverflow{}: {==}
    case True{} MinimumHeight{} D.ContentFlow{}: {==}
    case True{} MinimumHeight{} D.ScrollFlow{}: {==}
    case True{} MinimumHeight{} D.CodeOverflow{}: {==}
    case True{} MinimumHeight{} D.SingleLineOverflow{}: {==}
    case True{} BorderRadius{} D.ContentFlow{}: {==}
    case True{} BorderRadius{} D.ScrollFlow{}: {==}
    case True{} BorderRadius{} D.CodeOverflow{}: {==}
    case True{} BorderRadius{} D.SingleLineOverflow{}: {==}

def parent_shadow(+pointer: Bool, +property: ParentProperty, value: Bool, +previous: String) ->
  {R.attr_last(parent_properties(pointer, R.shadow_style(value)), parent_name(property), previous) == previous : String}:
  match pointer property value:
    case False{} FrameGap{} False{}: {==}
    case False{} FrameGap{} True{}: {==}
    case False{} MinimumHeight{} False{}: {==}
    case False{} MinimumHeight{} True{}: {==}
    case False{} BorderRadius{} False{}: {==}
    case False{} BorderRadius{} True{}: {==}
    case True{} FrameGap{} False{}: {==}
    case True{} FrameGap{} True{}: {==}
    case True{} MinimumHeight{} False{}: {==}
    case True{} MinimumHeight{} True{}: {==}
    case True{} BorderRadius{} False{}: {==}
    case True{} BorderRadius{} True{}: {==}

def parent_alignment(+pointer: Bool, +property: ParentProperty, value: D.Alignment, +previous: String) ->
  {R.attr_last(parent_properties(pointer, R.alignment_style(value)), parent_name(property), previous) == previous : String}:
  match pointer property value:
    case False{} FrameGap{} D.Stretch{}: {==}
    case False{} FrameGap{} D.Leading{}: {==}
    case False{} FrameGap{} D.Trailing{}: {==}
    case False{} FrameGap{} D.Centered{}: {==}
    case False{} MinimumHeight{} D.Stretch{}: {==}
    case False{} MinimumHeight{} D.Leading{}: {==}
    case False{} MinimumHeight{} D.Trailing{}: {==}
    case False{} MinimumHeight{} D.Centered{}: {==}
    case False{} BorderRadius{} D.Stretch{}: {==}
    case False{} BorderRadius{} D.Leading{}: {==}
    case False{} BorderRadius{} D.Trailing{}: {==}
    case False{} BorderRadius{} D.Centered{}: {==}
    case True{} FrameGap{} D.Stretch{}: {==}
    case True{} FrameGap{} D.Leading{}: {==}
    case True{} FrameGap{} D.Trailing{}: {==}
    case True{} FrameGap{} D.Centered{}: {==}
    case True{} MinimumHeight{} D.Stretch{}: {==}
    case True{} MinimumHeight{} D.Leading{}: {==}
    case True{} MinimumHeight{} D.Trailing{}: {==}
    case True{} MinimumHeight{} D.Centered{}: {==}
    case True{} BorderRadius{} D.Stretch{}: {==}
    case True{} BorderRadius{} D.Leading{}: {==}
    case True{} BorderRadius{} D.Trailing{}: {==}
    case True{} BorderRadius{} D.Centered{}: {==}

def parent_states(+pointer: Bool, +property: ParentProperty, value: D.ControlStates, +previous: String) ->
  {R.attr_last(parent_properties(pointer, R.states_style(value)), parent_name(property), previous) == previous : String}:
  match pointer property value:
    case False{} FrameGap{} D.Passive{}: {==}
    case False{} FrameGap{} D.Interactive{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}, opacity, ring, width, offset}: {==}
    case False{} FrameGap{} D.SurfaceFeedback{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}}: {==}
    case False{} MinimumHeight{} D.Passive{}: {==}
    case False{} MinimumHeight{} D.Interactive{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}, opacity, ring, width, offset}: {==}
    case False{} MinimumHeight{} D.SurfaceFeedback{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}}: {==}
    case False{} BorderRadius{} D.Passive{}: {==}
    case False{} BorderRadius{} D.Interactive{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}, opacity, ring, width, offset}: {==}
    case False{} BorderRadius{} D.SurfaceFeedback{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}}: {==}
    case True{} FrameGap{} D.Passive{}: {==}
    case True{} FrameGap{} D.Interactive{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}, opacity, ring, width, offset}: {==}
    case True{} FrameGap{} D.SurfaceFeedback{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}}: {==}
    case True{} MinimumHeight{} D.Passive{}: {==}
    case True{} MinimumHeight{} D.Interactive{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}, opacity, ring, width, offset}: {==}
    case True{} MinimumHeight{} D.SurfaceFeedback{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}}: {==}
    case True{} BorderRadius{} D.Passive{}: {==}
    case True{} BorderRadius{} D.Interactive{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}, opacity, ring, width, offset}: {==}
    case True{} BorderRadius{} D.SurfaceFeedback{D.PhasePaint{hfg, hbg}, D.PhasePaint{pfg, pbg}}: {==}

def parent_placement(+pointer: Bool, +property: ParentProperty, value: C.Placement, +previous: String) ->
  {R.attr_last(parent_properties(pointer, R.placement_styles(value)), parent_name(property), previous) == previous : String}:
  match pointer property value:
    case False{} FrameGap{} C.InFlow{}: {==}
    case False{} FrameGap{} C.ComposerEnd{}: {==}
    case False{} FrameGap{} C.PanelHeaderEnd{}: {==}
    case False{} FrameGap{} C.CodeToolbar{}: {==}
    case False{} FrameGap{} C.BesideValue{}: {==}
    case False{} FrameGap{} C.GroupHeadingEnd{}: {==}
    case False{} MinimumHeight{} C.InFlow{}: {==}
    case False{} MinimumHeight{} C.ComposerEnd{}: {==}
    case False{} MinimumHeight{} C.PanelHeaderEnd{}: {==}
    case False{} MinimumHeight{} C.CodeToolbar{}: {==}
    case False{} MinimumHeight{} C.BesideValue{}: {==}
    case False{} MinimumHeight{} C.GroupHeadingEnd{}: {==}
    case False{} BorderRadius{} C.InFlow{}: {==}
    case False{} BorderRadius{} C.ComposerEnd{}: {==}
    case False{} BorderRadius{} C.PanelHeaderEnd{}: {==}
    case False{} BorderRadius{} C.CodeToolbar{}: {==}
    case False{} BorderRadius{} C.BesideValue{}: {==}
    case False{} BorderRadius{} C.GroupHeadingEnd{}: {==}
    case True{} FrameGap{} C.InFlow{}: {==}
    case True{} FrameGap{} C.ComposerEnd{}: {==}
    case True{} FrameGap{} C.PanelHeaderEnd{}: {==}
    case True{} FrameGap{} C.CodeToolbar{}: {==}
    case True{} FrameGap{} C.BesideValue{}: {==}
    case True{} FrameGap{} C.GroupHeadingEnd{}: {==}
    case True{} MinimumHeight{} C.InFlow{}: {==}
    case True{} MinimumHeight{} C.ComposerEnd{}: {==}
    case True{} MinimumHeight{} C.PanelHeaderEnd{}: {==}
    case True{} MinimumHeight{} C.CodeToolbar{}: {==}
    case True{} MinimumHeight{} C.BesideValue{}: {==}
    case True{} MinimumHeight{} C.GroupHeadingEnd{}: {==}
    case True{} BorderRadius{} C.InFlow{}: {==}
    case True{} BorderRadius{} C.ComposerEnd{}: {==}
    case True{} BorderRadius{} C.PanelHeaderEnd{}: {==}
    case True{} BorderRadius{} C.CodeToolbar{}: {==}
    case True{} BorderRadius{} C.BesideValue{}: {==}
    case True{} BorderRadius{} C.GroupHeadingEnd{}: {==}

def parent_details(+pointer: Bool, +property: ParentProperty, +shadow: Bool, +alignment: D.Alignment, +states: D.ControlStates, +previous: String) ->
  {R.attr_last(parent_properties(pointer, R.style_details(shadow, alignment, states)), parent_name(property), previous) == previous : String}:
  parent_append(pointer, property, R.shadow_style(shadow), List.append(&2, Doc.Property, R.alignment_style(alignment), R.states_style(states)), previous, previous,
    parent_shadow(pointer, property, shadow, previous),
    parent_append(pointer, property, R.alignment_style(alignment), R.states_style(states), previous, previous,
      parent_alignment(pointer, property, alignment, previous), parent_states(pointer, property, states, previous)))

def parent_suffix(+pointer: Bool, +property: ParentProperty, +flow: D.Flow, +overflow: D.Overflow, +shadow: Bool, +alignment: D.Alignment, +states: D.ControlStates, +previous: String) ->
  {R.attr_last(parent_properties(pointer, style_tail(flow, overflow, shadow, alignment, states)), parent_name(property), previous) == previous : String}:
  parent_append(pointer, property, R.flow(flow), List.append(&2, Doc.Property, R.overflow_style(overflow), R.style_details(shadow, alignment, states)), previous, previous,
    parent_flow(pointer, property, flow, previous),
    parent_append(pointer, property, R.overflow_style(overflow), R.style_details(shadow, alignment, states), previous, previous,
      parent_overflow(pointer, property, overflow, previous), parent_details(pointer, property, shadow, alignment, states, previous)))

def parent_typography(+pointer: Bool, +property: ParentProperty, +value: T.Presentation, +previous: String) ->
  {R.attr_last(parent_properties(pointer, R.text_presentation(value)), parent_name(property), previous) == previous : String}:
  match pointer property:
    case False{} FrameGap{}: {==}
    case False{} MinimumHeight{}: {==}
    case False{} BorderRadius{}: {==}
    case True{} FrameGap{}: {==}
    case True{} MinimumHeight{}: {==}
    case True{} BorderRadius{}: {==}

def parent_typed_suffix(+pointer: Bool, +property: ParentProperty, +value: T.Presentation, +flow: D.Flow, +overflow: D.Overflow, +shadow: Bool, +alignment: D.Alignment, +states: D.ControlStates, +previous: String) ->
  {R.attr_last(parent_properties(pointer, typed_style_tail(value, flow, overflow, shadow, alignment, states)), parent_name(property), previous) == previous : String}:
  parent_append(pointer, property, style_tail(flow, overflow, shadow, alignment, states), R.text_presentation(value), previous, previous,
    parent_suffix(pointer, property, flow, overflow, shadow, alignment, states, previous), parent_typography(pointer, property, value, previous))

def parent_style(+pointer: Bool, +property: ParentProperty, +value: D.Style) ->
  {R.attr(parent_properties(pointer, R.style(value)), parent_name(property)) == parent_value(value, property) : String}:
  match pointer property value:
    case False{} FrameGap{} D.Style{actual_text, D.Chrome{fg, bg, border, border_width, radius, +shadow}, +alignment, +flow, +overflow, +frame, minimum, maximum, +states}:
      parent_typed_suffix(False{}, FrameGap{}, actual_text, flow, overflow, shadow, alignment, states, R.px(E.frame_gap(frame)))
    case False{} MinimumHeight{} D.Style{actual_text, D.Chrome{fg, bg, border, border_width, radius, +shadow}, +alignment, +flow, +overflow, +frame, minimum, maximum, +states}:
      parent_typed_suffix(False{}, MinimumHeight{}, actual_text, flow, overflow, shadow, alignment, states, R.px(minimum))
    case False{} BorderRadius{} D.Style{actual_text, D.Chrome{fg, bg, border, border_width, radius, +shadow}, +alignment, +flow, +overflow, +frame, minimum, maximum, +states}:
      parent_typed_suffix(False{}, BorderRadius{}, actual_text, flow, overflow, shadow, alignment, states, R.px(radius))
    case True{} FrameGap{} D.Style{actual_text, D.Chrome{fg, bg, border, border_width, radius, +shadow}, +alignment, +flow, +overflow, +frame, minimum, maximum, +states}:
      parent_typed_suffix(True{}, FrameGap{}, actual_text, flow, overflow, shadow, alignment, states, R.px(E.frame_gap(frame)))
    case True{} MinimumHeight{} D.Style{actual_text, D.Chrome{fg, bg, border, border_width, radius, +shadow}, +alignment, +flow, +overflow, +frame, minimum, maximum, +states}:
      parent_typed_suffix(True{}, MinimumHeight{}, actual_text, flow, overflow, shadow, alignment, states, R.px(minimum))
    case True{} BorderRadius{} D.Style{actual_text, D.Chrome{fg, bg, border, border_width, radius, +shadow}, +alignment, +flow, +overflow, +frame, minimum, maximum, +states}:
      parent_typed_suffix(True{}, BorderRadius{}, actual_text, flow, overflow, shadow, alignment, states, R.px(radius))

def parent_geometry(+pointer: Bool, +property: ParentProperty, +size: C.Geometry, +visual: D.Style, +previous: String) ->
  {R.attr_last(parent_properties(pointer, R.action_geometry(size, visual)), parent_name(property), previous) == previous : String}:
  match pointer property size visual:
    case False{} FrameGap{} C.Geometry{width, height, icon, radius, leading} D.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states}: {==}
    case False{} MinimumHeight{} C.Geometry{width, height, icon, radius, leading} D.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states}: {==}
    case False{} BorderRadius{} C.Geometry{width, height, icon, radius, leading} D.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states}: {==}
    case True{} FrameGap{} C.Geometry{width, height, icon, radius, leading} D.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states}: {==}
    case True{} MinimumHeight{} C.Geometry{width, height, icon, radius, leading} D.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states}: {==}
    case True{} BorderRadius{} C.Geometry{width, height, icon, radius, leading} D.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states}: {==}

def parent_content(+pointer: Bool, +property: ParentProperty, +face: C.Face, +size: C.Geometry, +previous: String) ->
  {R.attr_last(parent_properties(pointer, R.content_geometry(face, size)), parent_name(property), previous) == previous : String}:
  match pointer property face size:
    case False{} FrameGap{} C.IconFace{icon} C.Geometry{width, height, icon_size, radius, slot}: {==}
    case False{} FrameGap{} C.TextFace{text} C.Geometry{width, height, icon_size, radius, slot}: {==}
    case False{} FrameGap{} C.SingleLineFace{text} C.Geometry{width, height, icon_size, radius, slot}: {==}
    case False{} FrameGap{} C.IconTextFace{icon, text} C.Geometry{width, height, icon_size, radius, slot}: {==}
    case False{} FrameGap{} C.PickerFace{leading, text} C.Geometry{width, height, icon_size, radius, slot}: {==}
    case False{} FrameGap{} C.ChoiceFace{text, checked} C.Geometry{width, height, icon_size, radius, slot}: {==}
    case False{} FrameGap{} C.DisclosureFace{text, expanded} C.Geometry{width, height, icon_size, radius, slot}: {==}
    case False{} FrameGap{} C.PermissionFace{filesystem, network, approval} C.Geometry{width, height, icon_size, radius, slot}: {==}
    case False{} MinimumHeight{} C.IconFace{icon} C.Geometry{width, height, icon_size, radius, slot}: {==}
    case False{} MinimumHeight{} C.TextFace{text} C.Geometry{width, height, icon_size, radius, slot}: {==}
    case False{} MinimumHeight{} C.SingleLineFace{text} C.Geometry{width, height, icon_size, radius, slot}: {==}
    case False{} MinimumHeight{} C.IconTextFace{icon, text} C.Geometry{width, height, icon_size, radius, slot}: {==}
    case False{} MinimumHeight{} C.PickerFace{leading, text} C.Geometry{width, height, icon_size, radius, slot}: {==}
    case False{} MinimumHeight{} C.ChoiceFace{text, checked} C.Geometry{width, height, icon_size, radius, slot}: {==}
    case False{} MinimumHeight{} C.DisclosureFace{text, expanded} C.Geometry{width, height, icon_size, radius, slot}: {==}
    case False{} MinimumHeight{} C.PermissionFace{filesystem, network, approval} C.Geometry{width, height, icon_size, radius, slot}: {==}
    case False{} BorderRadius{} C.IconFace{icon} C.Geometry{width, height, icon_size, radius, slot}: {==}
    case False{} BorderRadius{} C.TextFace{text} C.Geometry{width, height, icon_size, radius, slot}: {==}
    case False{} BorderRadius{} C.SingleLineFace{text} C.Geometry{width, height, icon_size, radius, slot}: {==}
    case False{} BorderRadius{} C.IconTextFace{icon, text} C.Geometry{width, height, icon_size, radius, slot}: {==}
    case False{} BorderRadius{} C.PickerFace{leading, text} C.Geometry{width, height, icon_size, radius, slot}: {==}
    case False{} BorderRadius{} C.ChoiceFace{text, checked} C.Geometry{width, height, icon_size, radius, slot}: {==}
    case False{} BorderRadius{} C.DisclosureFace{text, expanded} C.Geometry{width, height, icon_size, radius, slot}: {==}
    case False{} BorderRadius{} C.PermissionFace{filesystem, network, approval} C.Geometry{width, height, icon_size, radius, slot}: {==}
    case True{} FrameGap{} C.IconFace{icon} C.Geometry{width, height, icon_size, radius, slot}: {==}
    case True{} FrameGap{} C.TextFace{text} C.Geometry{width, height, icon_size, radius, slot}: {==}
    case True{} FrameGap{} C.SingleLineFace{text} C.Geometry{width, height, icon_size, radius, slot}: {==}
    case True{} FrameGap{} C.IconTextFace{icon, text} C.Geometry{width, height, icon_size, radius, slot}: {==}
    case True{} FrameGap{} C.PickerFace{leading, text} C.Geometry{width, height, icon_size, radius, slot}: {==}
    case True{} FrameGap{} C.ChoiceFace{text, checked} C.Geometry{width, height, icon_size, radius, slot}: {==}
    case True{} FrameGap{} C.DisclosureFace{text, expanded} C.Geometry{width, height, icon_size, radius, slot}: {==}
    case True{} FrameGap{} C.PermissionFace{filesystem, network, approval} C.Geometry{width, height, icon_size, radius, slot}: {==}
    case True{} MinimumHeight{} C.IconFace{icon} C.Geometry{width, height, icon_size, radius, slot}: {==}
    case True{} MinimumHeight{} C.TextFace{text} C.Geometry{width, height, icon_size, radius, slot}: {==}
    case True{} MinimumHeight{} C.SingleLineFace{text} C.Geometry{width, height, icon_size, radius, slot}: {==}
    case True{} MinimumHeight{} C.IconTextFace{icon, text} C.Geometry{width, height, icon_size, radius, slot}: {==}
    case True{} MinimumHeight{} C.PickerFace{leading, text} C.Geometry{width, height, icon_size, radius, slot}: {==}
    case True{} MinimumHeight{} C.ChoiceFace{text, checked} C.Geometry{width, height, icon_size, radius, slot}: {==}
    case True{} MinimumHeight{} C.DisclosureFace{text, expanded} C.Geometry{width, height, icon_size, radius, slot}: {==}
    case True{} MinimumHeight{} C.PermissionFace{filesystem, network, approval} C.Geometry{width, height, icon_size, radius, slot}: {==}
    case True{} BorderRadius{} C.IconFace{icon} C.Geometry{width, height, icon_size, radius, slot}: {==}
    case True{} BorderRadius{} C.TextFace{text} C.Geometry{width, height, icon_size, radius, slot}: {==}
    case True{} BorderRadius{} C.SingleLineFace{text} C.Geometry{width, height, icon_size, radius, slot}: {==}
    case True{} BorderRadius{} C.IconTextFace{icon, text} C.Geometry{width, height, icon_size, radius, slot}: {==}
    case True{} BorderRadius{} C.PickerFace{leading, text} C.Geometry{width, height, icon_size, radius, slot}: {==}
    case True{} BorderRadius{} C.ChoiceFace{text, checked} C.Geometry{width, height, icon_size, radius, slot}: {==}
    case True{} BorderRadius{} C.DisclosureFace{text, expanded} C.Geometry{width, height, icon_size, radius, slot}: {==}
    case True{} BorderRadius{} C.PermissionFace{filesystem, network, approval} C.Geometry{width, height, icon_size, radius, slot}: {==}

def parent_anchor(+pointer: Bool, +property: ParentProperty, key: String, +previous: String) ->
  {R.attr_last(parent_properties(pointer, [R.property("anchor-name", R.css_anchor(key))]), parent_name(property), previous) == previous : String}:
  match pointer property:
    case False{} FrameGap{}: {==}
    case False{} MinimumHeight{}: {==}
    case False{} BorderRadius{}: {==}
    case True{} FrameGap{}: {==}
    case True{} MinimumHeight{}: {==}
    case True{} BorderRadius{}: {==}

def parent_action_tail(+pointer: Bool, +property: ParentProperty, +visual: D.Style, +face: C.Face, +size: C.Geometry, +placement: C.Placement, +key: String, +previous: String) ->
  {R.attr_last(parent_properties(pointer, geometry_tail(visual, face, size, placement, key)), parent_name(property), previous) == previous : String}:
  parent_append(pointer, property, R.action_geometry(size, visual), List.append(&2, Doc.Property, R.placement_styles(placement), List.append(&2, Doc.Property, [R.property("anchor-name", R.css_anchor(key))], R.content_geometry(face, size))), previous, previous,
    parent_geometry(pointer, property, size, visual, previous),
    parent_append(pointer, property, R.placement_styles(placement), List.append(&2, Doc.Property, [R.property("anchor-name", R.css_anchor(key))], R.content_geometry(face, size)), previous, previous,
      parent_placement(pointer, property, placement, previous),
      parent_append(pointer, property, [R.property("anchor-name", R.css_anchor(key))], R.content_geometry(face, size), previous, previous,
        parent_anchor(pointer, property, key, previous), parent_content(pointer, property, face, size, previous))))

def parent_action_law(-property: ParentProperty, -key: String, -visual: D.Style, -input: Core.Input, -availability: View.Availability, -name: String,
  -face: C.Face, -behavior: C.Behavior, -size: C.Geometry, -placement: C.Placement, -help: C.Help, -feedback: C.Feedback) -> Type:
  {R.attr(Doc.element_styles(R.action(key, visual, C.Action{input, availability, name, face, behavior, size, placement, help, feedback})), parent_name(property)) == parent_value(visual, property) : String}

def parent_action(+property: ParentProperty, +key: String, +visual: D.Style, +input: Core.Input, +availability: View.Availability, +name: String,
  +face: C.Face, +behavior: C.Behavior, +size: C.Geometry, +placement: C.Placement, +help: C.Help, +feedback: C.Feedback) -> parent_action_law(property, key, visual, input, availability, name, face, behavior, size, placement, help, feedback):
  parent_append(True{}, property, R.style(visual), geometry_tail(visual, face, size, placement, key), "", parent_value(visual, property),
    parent_style(True{}, property, visual), parent_action_tail(True{}, property, visual, face, size, placement, key, parent_value(visual, property)))

def parent_minimum(+value: D.Style) ->
  {parent_value(value, MinimumHeight{}) == R.px(Model.minimum(value)) : String}:
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
  {(R.attr(Doc.element_styles(option_production(key, label, selected, description, geometry, input, typography)), "padding-inline"), R.attr(Doc.element_styles(option_production(key, label, selected, description, geometry, input, typography)), "padding-block")) == ("8px", "8px") : (String & String)}:
  match selected geometry:
    case False{} C.Geometry{width, height, icon, radius, leading}: {==}
    case True{} C.Geometry{width, height, icon, radius, leading}: {==}

def title_production_insets(+key: String, +editor: User.Editor, +name: String, +text: String, choices: +List<Forms.ChoiceValue>, +typography: T.Presentation) ->
  {(R.attr(Doc.element_styles(title_production(key, editor, name, text, choices, typography)), "padding-inline"), R.attr(Doc.element_styles(title_production(key, editor, name, text, choices, typography)), "padding-block")) == ("8px", "6px") : (String & String)}:
  match editor:
    case User.NewTaskEditor{}: {==}
    case User.MessageEditor{task}: {==}
    case User.ProjectEditor{project}: {==}
    case User.CardEditor{card}: {==}
    case User.AgentEditor{agent}: {==}
    case User.ForkEditor{task}: {==}
    case User.CompactEditor{task}: {==}

def description_production_insets(+key: String, +editor: User.Editor, +name: String, +text: String, choices: +List<Forms.ChoiceValue>, +typography: T.Presentation) ->
  {(R.attr(Doc.element_styles(description_production(key, editor, name, text, choices, typography)), "padding-inline"), R.attr(Doc.element_styles(description_production(key, editor, name, text, choices, typography)), "padding-block")) == ("8px", "6px") : (String & String)}:
  match editor:
    case User.NewTaskEditor{}: {==}
    case User.MessageEditor{task}: {==}
    case User.ProjectEditor{project}: {==}
    case User.CardEditor{card}: {==}
    case User.AgentEditor{agent}: {==}
    case User.ForkEditor{task}: {==}
    case User.CompactEditor{task}: {==}



def geometry_complete_law(-width: Nat, -height: Nat, -icon: Nat, -radius: Nat, -leading: Nat, -visual: D.Style) -> Type:
  {R.action_geometry(C.Geometry{width, height, icon, radius, leading}, visual) == [R.property("min-width", R.px(width)), R.property("--native-icon-size", R.px(icon)), R.property("--native-leading-slot", R.px(leading))] : +List<Doc.Property>}

def geometry_complete(+width: Nat, +height: Nat, +icon: Nat, +radius: Nat, +leading: Nat, +visual: D.Style) -> geometry_complete_law(width, height, icon, radius, leading, visual):
  D.Style{text, chrome, alignment, flow, overflow, +content_frame, minimum, maximum, states} = visual
  {==}

type Requirements is Type:
  Requirements{
    parent_properties: @+property:ParentProperty -> @+key:String -> @+visual:D.Style -> @+input:Core.Input -> @+availability:View.Availability -> @+name:String -> @+face:C.Face -> @+behavior:C.Behavior -> @+size:C.Geometry -> @+placement:C.Placement -> @+help:C.Help -> @+feedback:C.Feedback ->
      parent_action_law(property, key, visual, input, availability, name, face, behavior, size, placement, help, feedback),
    area_properties: @+area:E.ContentArea -> {R.content_area_properties(area) == [R.property("padding-inline", R.px(E.inline(area))), R.property("padding-block", R.px(E.block(area))), R.property("box-sizing", "border-box")] : +List<Doc.Property>},
    style_allocation: @+value:D.Style -> @+axis:Axis -> {R.attr(R.style(value), axis_name(axis)) == R.px(axis_space(axis, Model.area(value))) : String},
    duplicate: @+name:String -> @+old:String -> @+new:String -> {R.attr([R.property(name, old), R.property(name, new)], name) == new : String},
    geometry_height: @+size:C.Geometry -> @+visual:D.Style -> {R.attr(List.append(&2, Doc.Property, R.style(visual), R.action_geometry(size, visual)), "min-height") == R.px(Model.minimum(visual)) : String},
    navigation_header: @+typography:T.Presentation -> @+selected:Bool -> {(R.attr(R.style(A.navigation_family_style(selected, 2n, 6n, typography)), "padding-inline"), R.attr(R.style(A.navigation_family_style(selected, 2n, 6n, typography)), "padding-block")) == ("8px", "4px") : (String & String)},
    navigation_task: @+typography:T.Presentation -> @+selected:Bool -> @+key:String -> @+task:Nat -> @+status:String -> @+children:+List<R.Child> -> {(R.attr(Doc.element_styles(R.task_row_node(key, task, status, selected, A.navigation_family_style(selected, 6n, 5n, typography), children, typography)), "padding-inline"), R.attr(Doc.element_styles(R.task_row_node(key, task, status, selected, A.navigation_family_style(selected, 6n, 5n, typography), children, typography)), "padding-block")) == ("8px", "4px") : (String & String)},
    embedded_name: @+typography:T.Presentation -> {(R.attr(R.style(A.project_label_style(A.ordinary_button(typography))), "padding-inline"), R.attr(R.style(A.project_label_style(A.ordinary_button(typography))), "padding-block")) == ("0px", "0px") : (String & String)},
    icon_control: @+typography:T.Presentation -> @+width:String -> {(R.attr(R.style(A.action_style(A.ordinary_button(typography), C.IconFace{C.Plus{}}, C.Geometry{0n, 28n, 16n, 6n, 0n})), "padding-inline"), R.attr(R.style(A.action_style(A.ordinary_button(typography), C.IconFace{C.Plus{}}, C.Geometry{0n, 28n, 16n, 6n, 0n})), "padding-block")) == ("4px", "4px") : (String & String)},
    card_title: @+typography:T.Presentation -> {(R.attr(BoardLaws.title_production_styles(typography), "padding-inline"), R.attr(BoardLaws.title_production_styles(typography), "padding-block")) == ("8px", "4px") : (String & String)},
    search: @+typography:T.Presentation -> @+filter:Board.Filter -> {(R.attr(R.style(A.field_style(UI.BoardSearch{filter}, typography)), "padding-inline"), R.attr(R.style(A.field_style(UI.BoardSearch{filter}, typography)), "padding-block")) == ("8px", "4px") : (String & String)},
    dialog_header: {(R.attr(R.dialog_header_styles(), "padding-inline"), R.attr(R.dialog_header_styles(), "padding-block")) == ("24px", "14px") : (String & String)},
    dialog_body: {(R.attr(R.dialog_body_styles(), "padding-inline"), R.attr(R.dialog_body_styles(), "padding-block")) == ("24px", "20px") : (String & String)},
    dialog_footer: {(R.attr(R.dialog_footer_styles(), "padding-inline"), R.attr(R.dialog_footer_styles(), "padding-block")) == ("24px", "12px") : (String & String)},
    empty_overwrite: @+name:String -> @+old:String -> {R.attr([R.property(name, old), R.property(name, "")], name) == "" : String},
    option_production_insets: @+typography:T.Presentation -> @+key:String -> @+label:String -> @+selected:Bool -> @+description:String -> @+geometry:C.Geometry -> @+input:Core.Input -> {(R.attr(Doc.element_styles(option_production(key, label, selected, description, geometry, input, typography)), "padding-inline"), R.attr(Doc.element_styles(option_production(key, label, selected, description, geometry, input, typography)), "padding-block")) == ("8px", "8px") : (String & String)},
    title_production_insets: @+typography:T.Presentation -> @+key:String -> @+editor:User.Editor -> @+name:String -> @+text:String -> @choices:+List<Forms.ChoiceValue> -> {(R.attr(Doc.element_styles(title_production(key, editor, name, text, choices, typography)), "padding-inline"), R.attr(Doc.element_styles(title_production(key, editor, name, text, choices, typography)), "padding-block")) == ("8px", "6px") : (String & String)},
    description_production_insets: @+typography:T.Presentation -> @+key:String -> @+editor:User.Editor -> @+name:String -> @+text:String -> @choices:+List<Forms.ChoiceValue> -> {(R.attr(Doc.element_styles(description_production(key, editor, name, text, choices, typography)), "padding-inline"), R.attr(Doc.element_styles(description_production(key, editor, name, text, choices, typography)), "padding-block")) == ("8px", "6px") : (String & String)},
    dialog_outer: @+typography:T.Presentation -> {(R.attr(R.style(A.style(UI.Dialog{}, UI.Region{}, typography)), "padding-inline"), R.attr(R.style(A.style(UI.Dialog{}, UI.Region{}, typography)), "padding-block")) == ("0px", "0px") : (String & String)},
    geometry_complete: @+width:Nat -> @+height:Nat -> @+icon:Nat -> @+radius:Nat -> @+leading:Nat -> @+visual:D.Style -> geometry_complete_law(width, height, icon, radius, leading, visual)}

def evidence() -> Requirements:
  Requirements{parent_action, +area => {==}, style_allocation, duplicate, +size => +visual =>
      Equal.trans(String, R.attr(List.append(&2, Doc.Property, R.style(visual), R.action_geometry(size, visual)), "min-height"),
        parent_value(visual, MinimumHeight{}), R.px(Model.minimum(visual)),
        parent_append(False{}, MinimumHeight{}, R.style(visual), R.action_geometry(size, visual), "", parent_value(visual, MinimumHeight{}),
          parent_style(False{}, MinimumHeight{}, visual), parent_geometry(False{}, MinimumHeight{}, size, visual, parent_value(visual, MinimumHeight{}))),
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
    +typography => {==}, geometry_complete}
