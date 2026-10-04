import Base
import ./design.bend as D
import ./controls.bend as C
import ./enclosure.bend as E
import ./typography.bend as T

# Natural measurements describe unconstrained action content. Wrapped height is
# a separate allocation boundary; these extents do not admit a whole viewport.
type Demand is Data:
  Demand{minimum: E.Extent, preferred: E.Extent}

type Content is Data:
  AwaitingInk{missing: +List<T.MeasurementSpec>}
  MeasuredInk{demand: Demand}

type Nodes is Data:
  AwaitingNodes{missing: +List<T.MeasurementSpec>}
  PreparedNodes{nodes: +List<D.Node>}

type Outcome is Data:
  AwaitingContent{missing: +List<T.MeasurementSpec>}
  Prepared{surface: D.Surface}

def description_presentation(text: T.Presentation) -> T.Presentation:
  T.Presentation{tier, emphasis, scale} = text
  T.Presentation{T.Support{}, T.Regular{}, scale}

def measurement(key: String, text: String, presentation: T.Presentation, wrapping: T.Wrapping) -> T.MeasurementSpec:
  T.spec(T.Probe{key, text, T.resolved(presentation), wrapping, None{}, "0"})

def text_specifications_empty(empty: Bool, key: String, text: String, presentation: T.Presentation, wrapping: T.Wrapping) -> +List<T.MeasurementSpec>:
  match empty:
    case True{}: Nil{}
    case False{}: [measurement(key, text, presentation, wrapping)]

def text_specifications(key: String, +text: String, presentation: T.Presentation, wrapping: T.Wrapping) -> +List<T.MeasurementSpec>:
  text_specifications_empty(String.is_empty(text), key, text, presentation, wrapping)

def description_specifications(key: String, description: Maybe<&2, String>, text: T.Presentation) -> +List<T.MeasurementSpec>:
  match description:
    case None{}: Nil{}
    case Some{description}: text_specifications(key ++ "/description", description, description_presentation(text), C.description_wrapping())

def single_line_specifications_empty(empty: Bool, +key: String, caption: String, +text: T.Presentation, wrapping: T.Wrapping) -> +List<T.MeasurementSpec>:
  match empty:
    case True{}: Nil{}
    case False{}: [measurement(key ++ "/label", caption, text, wrapping), measurement(key ++ "/ellipsis", "…", text, T.SingleLine{})]

def single_line_specifications(key: String, +caption: String, text: T.Presentation, wrapping: T.Wrapping) -> +List<T.MeasurementSpec>:
  single_line_specifications_empty(String.is_empty(caption), key, caption, text, wrapping)

def face_specifications(+key: String, face: C.Face, +text: T.Presentation) -> +List<T.MeasurementSpec>:
  match face:
    case C.IconFace{icon}: Nil{}
    case C.PermissionFace{filesystem, network, approval}: Nil{}
    case C.TextFace{+caption}: text_specifications(key ++ "/label", caption, text, C.caption_wrapping(C.TextFace{caption}))
    case C.SingleLineFace{+caption}: single_line_specifications(key, caption, text, C.caption_wrapping(C.SingleLineFace{caption}))
    case C.IconTextFace{icon, +caption}: text_specifications(key ++ "/label", caption, text, C.caption_wrapping(C.IconTextFace{icon, caption}))
    case C.PickerFace{leading, +caption}: text_specifications(key ++ "/label", caption, text, C.caption_wrapping(C.PickerFace{leading, caption}))
    case C.DisclosureFace{+caption, expanded}: text_specifications(key ++ "/label", caption, text, C.caption_wrapping(C.DisclosureFace{caption, expanded}))
    case C.ChoiceFace{+caption, +description, checked}: List.append(&2, T.MeasurementSpec,
      text_specifications(key ++ "/label", caption, text, C.caption_wrapping(C.ChoiceFace{caption, description, checked})), description_specifications(key, description, text))

def control_specifications(key: String, control: C.Representation, text: T.Presentation) -> +List<T.MeasurementSpec>:
  match control:
    case C.Action{input, availability, name, face, behavior, geometry, placement, help, feedback}: face_specifications(key, face, text)
    case _: Nil{}

def node_own_specifications(key: String, control: C.Representation, style: D.Style) -> +List<T.MeasurementSpec>:
  control_specifications(key, control, D.style_text(style))

def nodes_specifications(nodes: +List<D.Node>) -> +List<T.MeasurementSpec>:
  match nodes:
    case Nil{}: Nil{}
    case Con{D.Node{key, semantic, label, role, meaning, style, control, children}, rest}:
      List.append(&2, T.MeasurementSpec, node_own_specifications(key, control, style),
        List.append(&2, T.MeasurementSpec, nodes_specifications(children), nodes_specifications(rest)))

def specifications(surface: D.Surface) -> +List<T.MeasurementSpec>:
  D.Surface{content, theme, base, overlays, scope} = surface
  List.append(&2, T.MeasurementSpec, nodes_specifications(base), nodes_specifications(overlays))

def admitted(+specification: T.MeasurementSpec, measured: T.Measured) -> Bool:
  T.Measured{actual, metric} = measured
  T.same_spec(specification, actual) && T.valid_metric(specification, metric)

def admit_metric(accepted: Bool, metric: T.Metric) -> Maybe<&2, T.Metric>:
  match accepted:
    case True{}: Some{metric}
    case False{}: None{}

def admit_entry(+entry: T.Measured, +specification: T.MeasurementSpec) -> Maybe<&2, T.Metric>:
  T.Measured{actual, metric} = entry
  admit_metric(admitted(specification, entry), metric)

def lookup_loop(measured: +List<T.Measured>, candidate: Maybe<&2, T.Metric>, +specification: T.MeasurementSpec) -> Maybe<&2, T.Metric>:
  match measured:
    case Nil{}: candidate
    case Con{entry, rest}:
      match candidate:
        case Some{metric}: Some{metric}
        case None{}: lookup_loop(rest, admit_entry(entry, specification), specification)

def lookup(measured: +List<T.Measured>, specification: T.MeasurementSpec) -> Maybe<&2, T.Metric>:
  lookup_loop(measured, None{}, specification)

def fixed(+width: Nat, +height: Nat) -> Content:
  MeasuredInk{Demand{E.Extent{width, height}, E.Extent{width, height}}}

def measured_text(specification: T.MeasurementSpec, value: Maybe<&2, T.Metric>) -> Content:
  match value:
    case None{}: AwaitingInk{[specification]}
    case Some{T.Metric{key, minimum, preferred, +height, reference}}:
      MeasuredInk{Demand{E.Extent{minimum, height}, E.Extent{preferred, height}}}

def text_content_empty(empty: Bool, measured: +List<T.Measured>, key: String, +caption: String, text: T.Presentation, wrapping: T.Wrapping) -> Content:
  match empty:
    case True{}: fixed(0n, 0n)
    case False{}:
      +specification = measurement(key, caption, text, wrapping)
      measured_text(specification, lookup(measured, specification))

def text_content(measured: +List<T.Measured>, key: String, +caption: String, text: T.Presentation, wrapping: T.Wrapping) -> Content:
  text_content_empty(String.is_empty(caption), measured, key, caption, text, wrapping)

def truncated_content(caption: Content, ellipsis: Content) -> Content:
  match caption ellipsis:
    case AwaitingInk{first} AwaitingInk{second}: AwaitingInk{List.append(&2, T.MeasurementSpec, first, second)}
    case AwaitingInk{missing} MeasuredInk{value}: AwaitingInk{missing}
    case MeasuredInk{value} AwaitingInk{missing}: AwaitingInk{missing}
    case MeasuredInk{Demand{E.Extent{minimum, height}, E.Extent{+preferred, natural_height}}} MeasuredInk{Demand{ellipsis_minimum, E.Extent{ellipsis_width, ellipsis_height}}}:
      MeasuredInk{Demand{E.Extent{Nat.min(preferred, ellipsis_width), height}, E.Extent{preferred, natural_height}}}

def single_line_content_empty(empty: Bool, +measured: +List<T.Measured>, +key: String, +caption: String, +text: T.Presentation, wrapping: T.Wrapping) -> Content:
  match empty:
    case True{}: fixed(0n, 0n)
    case False{}: truncated_content(text_content(measured, key ++ "/label", caption, text, wrapping),
      text_content(measured, key ++ "/ellipsis", "…", text, T.SingleLine{}))

def single_line_content(+measured: +List<T.Measured>, +key: String, +caption: String, +text: T.Presentation, wrapping: T.Wrapping) -> Content:
  single_line_content_empty(String.is_empty(caption), measured, key, caption, text, wrapping)

def row_extent(first: E.Extent, second: E.Extent, gap: Nat) -> E.Extent:
  E.Extent{first_width, first_height} = first
  E.Extent{second_width, second_height} = second
  E.Extent{Nat.add(first_width, Nat.add(gap, second_width)), Nat.max(first_height, second_height)}

def column_extent(first: E.Extent, second: E.Extent, gap: Nat) -> E.Extent:
  E.Extent{first_width, first_height} = first
  E.Extent{second_width, second_height} = second
  E.Extent{Nat.max(first_width, second_width), Nat.add(first_height, Nat.add(gap, second_height))}

def combine(first: Content, second: Content, +gap: Nat, row: Bool) -> Content:
  match first second:
    case AwaitingInk{left} AwaitingInk{right}: AwaitingInk{List.append(&2, T.MeasurementSpec, left, right)}
    case AwaitingInk{missing} MeasuredInk{value}: AwaitingInk{missing}
    case MeasuredInk{value} AwaitingInk{missing}: AwaitingInk{missing}
    case MeasuredInk{Demand{first_minimum, first_preferred}} MeasuredInk{Demand{second_minimum, second_preferred}}:
      match row:
        case True{}: MeasuredInk{Demand{row_extent(first_minimum, second_minimum, gap), row_extent(first_preferred, second_preferred, gap)}}
        case False{}: MeasuredInk{Demand{column_extent(first_minimum, second_minimum, gap), column_extent(first_preferred, second_preferred, gap)}}

def choice_text_description(description: Maybe<&2, String>, label: Content, measured: +List<T.Measured>, key: String, text: T.Presentation, gap: Nat) -> Content:
  match description:
    case None{}: label
    case Some{description}: combine(label, text_content(measured, key ++ "/description", description, description_presentation(text), C.description_wrapping()), gap, False{})

def choice_text(+measured: +List<T.Measured>, +key: String, caption: String, description: Maybe<&2, String>, +text: T.Presentation, gap: Nat, wrapping: T.Wrapping) -> Content:
  choice_text_description(description, text_content(measured, key ++ "/label", caption, text, wrapping), measured, key, text, gap)

def choice_ink_layout(layout: C.ChoiceContentLayout, measured: +List<T.Measured>, key: String, caption: String, description: Maybe<&2, String>, text: T.Presentation, gap: Nat, wrapping: T.Wrapping) -> Content:
  C.ChoiceContentLayout{text_gap, mark_extent, mark_icon_extent} = layout
  combine(choice_text(measured, key, caption, description, text, text_gap, wrapping), fixed(mark_extent, mark_icon_extent), gap, True{})

def choice_ink(measured: +List<T.Measured>, key: String, caption: String, description: Maybe<&2, String>, text: T.Presentation, geometry: C.Geometry, gap: Nat, wrapping: T.Wrapping) -> Content:
  choice_ink_layout(C.choice_content_layout(geometry), measured, key, caption, description, text, gap, wrapping)

def picker_ink_leading(leading: Maybe<&2, C.Icon>, trailing: Content, +icon: Nat, gap: Nat) -> Content:
  match leading:
    case None{}: trailing
    case Some{value}: combine(fixed(icon, icon), trailing, gap, True{})

def picker_ink(leading: Maybe<&2, C.Icon>, caption: Content, +icon: Nat, +gap: Nat) -> Content:
  picker_ink_leading(leading, combine(caption, fixed(icon, icon), gap, True{}), icon, gap)

def ink_geometry(+geometry: C.Geometry, +measured: +List<T.Measured>, +key: String, face: C.Face, +text: T.Presentation, +gap: Nat) -> Content:
  C.Geometry{width, height, +icon, radius, leading} = geometry
  match face:
    case C.IconFace{value}: fixed(icon, icon)
    case C.PermissionFace{filesystem, network, approval}: fixed(Nat.add(Nat.mul(3n, icon), Nat.mul(2n, gap)), icon)
    case C.TextFace{+caption}: text_content(measured, key ++ "/label", caption, text, C.caption_wrapping(C.TextFace{caption}))
    case C.SingleLineFace{+caption}: single_line_content(measured, key, caption, text, C.caption_wrapping(C.SingleLineFace{caption}))
    case C.IconTextFace{value, +caption}: combine(fixed(icon, icon), text_content(measured, key ++ "/label", caption, text, C.caption_wrapping(C.IconTextFace{value, caption})), gap, True{})
    case C.DisclosureFace{+caption, expanded}: combine(fixed(icon, icon), text_content(measured, key ++ "/label", caption, text, C.caption_wrapping(C.DisclosureFace{caption, expanded})), gap, True{})
    case C.PickerFace{+leading, +caption}: picker_ink(leading, text_content(measured, key ++ "/label", caption, text, C.caption_wrapping(C.PickerFace{leading, caption})), icon, gap)
    case C.ChoiceFace{+caption, +description, checked}: choice_ink(measured, key, caption, description, text, geometry, gap, C.caption_wrapping(C.ChoiceFace{caption, description, checked}))

def ink(+measured: +List<T.Measured>, +key: String, face: C.Face, +text: T.Presentation, +geometry: C.Geometry, +gap: Nat) -> Content:
  ink_geometry(geometry, measured, key, face, text, gap)

def outer_required(required: E.Extent, minimum_width: Nat, minimum_height: Nat, style_height: Nat) -> E.Extent:
  E.Extent{required_width, required_height} = required
  E.Extent{Nat.max(minimum_width, required_width), Nat.max(style_height, Nat.max(minimum_height, required_height))}

def outer_extent(ink: E.Extent, geometry: C.Geometry, style: D.Style) -> E.Extent:
  E.Extent{width, height} = ink
  C.Geometry{minimum_width, minimum_height, icon, radius, leading} = geometry
  D.Style{text, D.Chrome{foreground, background, paint, border, chrome_radius, shadow}, alignment, flow, overflow, frame, style_height, maximum, states} = style
  outer_required(E.required_extent(width, height, border, E.frame_content(frame)), minimum_width, minimum_height, style_height)

def outer_content(content: Content, +geometry: C.Geometry, +style: D.Style) -> Content:
  match content:
    case AwaitingInk{missing}: AwaitingInk{missing}
    case MeasuredInk{Demand{minimum, preferred}}:
      MeasuredInk{Demand{outer_extent(minimum, geometry, style), outer_extent(preferred, geometry, style)}}

def natural_demand(measured: +List<T.Measured>, key: String, face: C.Face, +geometry: C.Geometry, +style: D.Style) -> Content:
  D.Style{text, chrome, alignment, flow, overflow, frame, height, maximum, states} = style
  outer_content(ink(measured, key, face, text, geometry, E.frame_gap(frame)), geometry, style)

def with_minimum(style: D.Style, height: Nat) -> D.Style:
  D.Style{text, chrome, alignment, flow, overflow, frame, old_height, maximum, states} = style
  D.Style{text, chrome, alignment, flow, overflow, frame, height, maximum, states}

def refine_node(node: D.Node, minimum: E.Extent, children: +List<D.Node>) -> D.Node:
  D.Node{key, semantic, label, role, meaning, style, control, old_children} = node
  match control:
    case C.Action{input, availability, name, face, behavior, C.Geometry{old_width, old_height, icon, radius, leading}, placement, help, feedback}:
      E.Extent{width, +height} = minimum
      D.Node{key, semantic, label, role, meaning, with_minimum(style, height),
        C.Action{input, availability, name, face, behavior, C.Geometry{width, height, icon, radius, leading}, placement, help, feedback}, children}
    case _: D.Node{key, semantic, label, role, meaning, style, control, children}

def finish_node(node: D.Node, demand: Content, children: Nodes) -> Nodes:
  match demand children:
    case AwaitingInk{first} AwaitingNodes{second}: AwaitingNodes{List.append(&2, T.MeasurementSpec, first, second)}
    case AwaitingInk{missing} PreparedNodes{nodes}: AwaitingNodes{missing}
    case MeasuredInk{value} AwaitingNodes{missing}: AwaitingNodes{missing}
    case MeasuredInk{Demand{minimum, preferred}} PreparedNodes{nodes}: PreparedNodes{[refine_node(node, minimum, nodes)]}

def node_demand(measured: +List<T.Measured>, node: D.Node) -> Content:
  D.Node{key, semantic, label, role, meaning, style, control, children} = node
  match control:
    case C.Action{input, availability, name, face, behavior, geometry, placement, help, feedback}: natural_demand(measured, key, face, geometry, style)
    case _: fixed(0n, 0n)

def prepare_node(+measured: +List<T.Measured>, +node: D.Node, children: Nodes) -> Nodes:
  finish_node(node, node_demand(measured, node), children)

def append_nodes(first: Nodes, second: Nodes) -> Nodes:
  match first second:
    case AwaitingNodes{left} AwaitingNodes{right}: AwaitingNodes{List.append(&2, T.MeasurementSpec, left, right)}
    case AwaitingNodes{missing} PreparedNodes{nodes}: AwaitingNodes{missing}
    case PreparedNodes{nodes} AwaitingNodes{missing}: AwaitingNodes{missing}
    case PreparedNodes{first} PreparedNodes{second}: PreparedNodes{List.append(&2, D.Node, first, second)}

def prepare_nodes(+measured: +List<T.Measured>, nodes: +List<D.Node>) -> Nodes:
  match nodes:
    case Nil{}: PreparedNodes{Nil{}}
    case Con{D.Node{key, semantic, label, role, meaning, style, control, +children}, rest}:
      node: D.Node = D.Node{key, semantic, label, role, meaning, style, control, children}
      append_nodes(prepare_node(measured, node, prepare_nodes(measured, children)), prepare_nodes(measured, rest))

def finish_surface(surface: D.Surface, base: Nodes, overlays: Nodes) -> Outcome:
  D.Surface{content, theme, old_base, old_overlays, scope} = surface
  match base overlays:
    case AwaitingNodes{first} AwaitingNodes{second}: AwaitingContent{List.append(&2, T.MeasurementSpec, first, second)}
    case AwaitingNodes{missing} PreparedNodes{nodes}: AwaitingContent{missing}
    case PreparedNodes{nodes} AwaitingNodes{missing}: AwaitingContent{missing}
    case PreparedNodes{base} PreparedNodes{overlays}: Prepared{D.Surface{content, theme, base, overlays, scope}}

def prepare(+measured: +List<T.Measured>, +surface: D.Surface) -> Outcome:
  D.Surface{content, theme, +base, +overlays, scope} = surface
  finish_surface(surface, prepare_nodes(measured, base), prepare_nodes(measured, overlays))
