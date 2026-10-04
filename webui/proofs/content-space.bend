import Base
import ../content-space-laws.bend as Rule
import ../content-space.bend as S
import ../design.bend as D
import ../controls.bend as C
import ../enclosure.bend as E
import ../typography.bend as T
import ../space.bend as Space
import ../../core/SYSTEM.bend as Core
import ../../core/ui-world.bend as View
import ../../core/interface.bend as UI
import ../../bendlib/stdlib.bend as Std
import ./space.bend as SpaceLawsProof

def refinement_control(+node: D.Node, +demand: Space.Demand, +children: +List<D.Node>) ->
  {Rule.control_identity(Rule.node_control(S.refine_node(node, demand, children))) == Rule.control_identity(Rule.node_control(node)) : C.Representation}:
  D.Node{key, semantic, label, role, meaning, style, +control, old_children} = node
  match control:
    case C.Action{input, availability, name, face, behavior, geometry, placement, help, feedback}:
      C.Geometry{Space.Demand{E.Extent{width, height}, preferred}, icon, radius, leading} = geometry
      Space.Demand{E.Extent{new_width, new_height}, new_preferred} = demand
      {==}
    case C.NoControl{}: {==}
    case C.Input{binding, name, widget, control_label, availability}: {==}
    case C.Movable{destinations, face, name, handle, geometry, help}: {==}

def refinement_style(+node: D.Node, +demand: Space.Demand, +children: +List<D.Node>) ->
  {Rule.style_identity(Rule.node_style(S.refine_node(node, demand, children))) == Rule.style_identity(Rule.node_style(node)) : D.Style}:
  D.Node{key, semantic, label, role, meaning, +style, +control, old_children} = node
  D.Style{text, chrome, alignment, flow, overflow, frame, height, maximum, states} = style
  match control:
    case C.Action{input, availability, name, face, behavior, geometry, placement, help, feedback}:
      C.Geometry{Space.Demand{E.Extent{width, height}, preferred}, icon, radius, leading} = geometry
      Space.Demand{E.Extent{new_width, new_height}, new_preferred} = demand
      {==}
    case C.NoControl{}: {==}
    case C.Input{binding, name, widget, control_label, availability}: {==}
    case C.Movable{destinations, face, name, handle, geometry, help}: {==}

def refinement_semantics(+node: D.Node, demand: Space.Demand, +children: +List<D.Node>,
  same: {D.semantic_nodes(children) == D.semantic_nodes(Rule.node_children(node)) : +List<UI.Node>}) ->
  {D.semantic_nodes([S.refine_node(node, demand, children)]) == D.semantic_nodes([node]) : +List<UI.Node>}:
  D.Node{+key, +semantic, +label, +role, +meaning, style, +control, +old_children} = node
  match control:
    case C.Action{input, availability, name, face, behavior, geometry, placement, help, feedback}:
      C.Geometry{Space.Demand{E.Extent{width, height}, preferred}, icon, radius, leading} = geometry
      Space.Demand{E.Extent{new_width, new_height}, new_preferred} = demand
      Equal.cong(+List<UI.Node>, +List<UI.Node>, (values => [UI.Node{key, semantic, label, role, meaning, values}]),
        D.semantic_nodes(children), D.semantic_nodes(old_children), same)
    case C.NoControl{}: Equal.cong(+List<UI.Node>, +List<UI.Node>, (values => [UI.Node{key, semantic, label, role, meaning, values}]),
      D.semantic_nodes(children), D.semantic_nodes(old_children), same)
    case C.Input{binding, name, widget, control_label, availability}: Equal.cong(+List<UI.Node>, +List<UI.Node>, (values => [UI.Node{key, semantic, label, role, meaning, values}]),
      D.semantic_nodes(children), D.semantic_nodes(old_children), same)
    case C.Movable{destinations, face, name, handle, geometry, help}: Equal.cong(+List<UI.Node>, +List<UI.Node>, (values => [UI.Node{key, semantic, label, role, meaning, values}]),
      D.semantic_nodes(children), D.semantic_nodes(old_children), same)

def semantic_append_nil(+rest: +List<D.Node>) ->
  {D.semantic_nodes(List.append(&2, D.Node, Nil{}, rest)) == List.append(&2, UI.Node, D.semantic_nodes(Nil{}), D.semantic_nodes(rest)) : +List<UI.Node>}:
  {==}

def semantic_append_cons(node: D.Node, +tail: +List<D.Node>, +rest: +List<D.Node>,
  premise: {D.semantic_nodes(List.append(&2, D.Node, tail, rest)) == List.append(&2, UI.Node, D.semantic_nodes(tail), D.semantic_nodes(rest)) : +List<UI.Node>}) ->
  {D.semantic_nodes(List.append(&2, D.Node, node <> tail, rest)) == List.append(&2, UI.Node, D.semantic_nodes(node <> tail), D.semantic_nodes(rest)) : +List<UI.Node>}:
  D.Node{key, semantic, label, role, meaning, style, control, children} = node
  Equal.cong(+List<UI.Node>, +List<UI.Node>, (values => UI.Node{key, semantic, label, role, meaning, D.semantic_nodes(children)} <> values),
    D.semantic_nodes(List.append(&2, D.Node, tail, rest)), List.append(&2, UI.Node, D.semantic_nodes(tail), D.semantic_nodes(rest)), premise)

def semantic_append(+first: +List<D.Node>, +second: +List<D.Node>) ->
  {D.semantic_nodes(List.append(&2, D.Node, first, second)) == List.append(&2, UI.Node, D.semantic_nodes(first), D.semantic_nodes(second)) : +List<UI.Node>}:
  Std.list_ind(~D.Node,
    ~(values => @+rest:+List<D.Node> -> {D.semantic_nodes(List.append(&2, D.Node, values, rest)) == List.append(&2, UI.Node, D.semantic_nodes(values), D.semantic_nodes(rest)) : +List<UI.Node>}),
    ~(+rest => semantic_append_nil(rest)), ~(node => +tail => premise => +rest => semantic_append_cons(node, tail, rest, premise(rest))), first)(second)

def finish_node_semantics(+node: D.Node, +demand: S.Content, +children: S.Nodes,
  premise: Rule.NodesClaim(Rule.node_children(node), children)) -> Rule.NodesClaim([node], S.finish_node(node, demand, children)):
  match demand children:
    case S.AwaitingInk{first} S.AwaitingNodes{second}: Unit{}
    case S.AwaitingInk{missing} S.PreparedNodes{nodes}: Unit{}
    case S.MeasuredInk{Space.Demand{minimum, preferred}} S.AwaitingNodes{missing}: Unit{}
    case S.MeasuredInk{Space.Demand{minimum, preferred}} S.PreparedNodes{nodes}: refinement_semantics(node, Space.Demand{minimum, preferred}, nodes, premise)

def append_semantics(+first: +List<D.Node>, +second: +List<D.Node>, +left: S.Nodes, +right: S.Nodes,
  left_claim: Rule.NodesClaim(first, left), right_claim: Rule.NodesClaim(second, right)) ->
  Rule.NodesClaim(List.append(&2, D.Node, first, second), S.append_nodes(left, right)):
  match left right:
    case S.AwaitingNodes{a} S.AwaitingNodes{b}: Unit{}
    case S.AwaitingNodes{a} S.PreparedNodes{b}: Unit{}
    case S.PreparedNodes{a} S.AwaitingNodes{b}: Unit{}
    case S.PreparedNodes{+a} S.PreparedNodes{+b}:
      Equal.trans(+List<UI.Node>, D.semantic_nodes(List.append(&2, D.Node, a, b)),
        List.append(&2, UI.Node, D.semantic_nodes(a), D.semantic_nodes(b)), D.semantic_nodes(List.append(&2, D.Node, first, second)), semantic_append(a, b),
        Equal.trans(+List<UI.Node>, List.append(&2, UI.Node, D.semantic_nodes(a), D.semantic_nodes(b)),
          List.append(&2, UI.Node, D.semantic_nodes(first), D.semantic_nodes(second)), D.semantic_nodes(List.append(&2, D.Node, first, second)),
          Equal.trans(+List<UI.Node>, List.append(&2, UI.Node, D.semantic_nodes(a), D.semantic_nodes(b)),
            List.append(&2, UI.Node, D.semantic_nodes(first), D.semantic_nodes(b)), List.append(&2, UI.Node, D.semantic_nodes(first), D.semantic_nodes(second)),
            Equal.cong(+List<UI.Node>, +List<UI.Node>, (values => List.append(&2, UI.Node, values, D.semantic_nodes(b))), D.semantic_nodes(a), D.semantic_nodes(first), left_claim),
            Equal.cong(+List<UI.Node>, +List<UI.Node>, (values => List.append(&2, UI.Node, D.semantic_nodes(first), values)), D.semantic_nodes(b), D.semantic_nodes(second), right_claim)),
          Equal.sym(+List<UI.Node>, D.semantic_nodes(List.append(&2, D.Node, first, second)), List.append(&2, UI.Node, D.semantic_nodes(first), D.semantic_nodes(second)), semantic_append(first, second))))

def prepare_node_semantics(+measured: +List<T.Measured>, +node: D.Node, +children: S.Nodes,
  premise: Rule.NodesClaim(Rule.node_children(node), children)) -> Rule.NodesClaim([node], S.prepare_node(measured, node, children)):
  finish_node_semantics(node, S.node_demand(measured, node), children, premise)

def prepare_nodes_semantics(+measured: +List<T.Measured>, +nodes: +List<D.Node>) -> Rule.NodesClaim(nodes, S.prepare_nodes(measured, nodes)):
  match nodes:
    case Nil{}: {==}
    case Con{D.Node{+key, +semantic, +label, +role, +meaning, +style, +control, +children}, +rest}:
      +node: D.Node = D.Node{key, semantic, label, role, meaning, style, control, children}
      append_semantics([node], rest,
        S.prepare_node(measured, node, S.prepare_nodes(measured, children)), S.prepare_nodes(measured, rest),
        prepare_node_semantics(measured, node, S.prepare_nodes(measured, children), prepare_nodes_semantics(measured, children)),
        prepare_nodes_semantics(measured, rest))

def finish_surface_semantics(+surface: D.Surface, +base: S.Nodes, +overlays: S.Nodes,
  base_claim: Rule.NodesClaim(Rule.surface_base(surface), base), overlay_claim: Rule.NodesClaim(Rule.surface_overlays(surface), overlays)) -> Rule.SurfaceClaim(surface, S.finish_surface(surface, base, overlays)):
  D.Surface{+content, theme, +old_base, +old_overlays, +scope} = surface
  match base overlays:
    case S.AwaitingNodes{first} S.AwaitingNodes{second}: Unit{}
    case S.AwaitingNodes{missing} S.PreparedNodes{nodes}: Unit{}
    case S.PreparedNodes{nodes} S.AwaitingNodes{missing}: Unit{}
    case S.PreparedNodes{+base} S.PreparedNodes{+overlays}:
      Equal.trans(UI.Surface, UI.Surface{content, D.semantic_nodes(base), D.semantic_nodes(overlays), scope},
        UI.Surface{content, D.semantic_nodes(old_base), D.semantic_nodes(overlays), scope}, UI.Surface{content, D.semantic_nodes(old_base), D.semantic_nodes(old_overlays), scope},
        Equal.cong(+List<UI.Node>, UI.Surface, (values => UI.Surface{content, values, D.semantic_nodes(overlays), scope}), D.semantic_nodes(base), D.semantic_nodes(old_base), base_claim),
        Equal.cong(+List<UI.Node>, UI.Surface, (values => UI.Surface{content, D.semantic_nodes(old_base), values, scope}), D.semantic_nodes(overlays), D.semantic_nodes(old_overlays), overlay_claim))

def prepare_semantics(+measured: +List<T.Measured>, +surface: D.Surface) -> Rule.SurfaceClaim(surface, S.prepare(measured, surface)):
  D.Surface{content, theme, +base, +overlays, scope} = surface
  finish_surface_semantics(surface, S.prepare_nodes(measured, base), S.prepare_nodes(measured, overlays), prepare_nodes_semantics(measured, base), prepare_nodes_semantics(measured, overlays))

def choice_reservation(+measured: +List<T.Measured>, +key: String, +caption: String,
  +description: Maybe<&2, String>, +text: T.Presentation, +geometry: C.Geometry, +gap: Nat) ->
  {S.ink(measured, key, C.ChoiceFace{caption, description, True{}}, text, geometry, gap) ==
    S.ink(measured, key, C.ChoiceFace{caption, description, False{}}, text, geometry, gap) : S.Content}:
  C.Geometry{Space.Demand{E.Extent{width, height}, preferred}, icon, radius, leading} = geometry
  {==}

def demand_consumed(+key: String, +semantic: String, +label: String, +role: UI.Role, +meaning: UI.Meaning, +style: D.Style, +input: Core.Input, +availability: View.Availability, +name: String, +face: C.Face, +behavior: C.Behavior, +geometry: C.Geometry, +placement: C.Placement, +help: C.Help, +feedback: C.Feedback, +original_children: +List<D.Node>, +minimum: E.Extent, +preferred: E.Extent, +children: +List<D.Node>) ->
  {Rule.prepared_action_demand(S.finish_node(D.Node{key, semantic, label, role, meaning, style, C.Action{input, availability, name, face, behavior, geometry, placement, help, feedback}, original_children}, S.MeasuredInk{Space.Demand{minimum, preferred}}, S.PreparedNodes{children})) == Some{Space.Demand{minimum, preferred}} : Maybe<&2, Space.Demand>}:
  C.Geometry{original_demand, icon, radius, leading} = geometry
  E.Extent{width, height} = minimum
  {==}

def outer_width_geometry(+ink: E.Extent, +geometry: C.Geometry, +style: D.Style) ->
  {Nat.is_ge(Rule.extent_width(S.outer_extent(ink, geometry, style)), Rule.geometry_width(geometry)) == True{} : Bool}:
  E.Extent{width, height} = ink
  C.Geometry{Space.Demand{E.Extent{+minimum_width, minimum_height}, preferred}, icon, radius, leading} = geometry
  D.Style{text, D.Chrome{foreground, background, paint, border, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = style
  required_width = Rule.extent_width(E.required_extent(width, height, border, E.frame_content(frame)))
  Nat.max_ge_l(minimum_width, required_width)

def outer_width_ink(+ink: E.Extent, +geometry: C.Geometry, +style: D.Style) ->
  {Nat.is_ge(Rule.extent_width(S.outer_extent(ink, geometry, style)), Rule.extent_width(Rule.padded_ink(ink, style))) == True{} : Bool}:
  E.Extent{width, height} = ink
  C.Geometry{Space.Demand{E.Extent{minimum_width, minimum_height}, preferred}, icon, radius, leading} = geometry
  D.Style{text, D.Chrome{foreground, background, paint, border, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = style
  required_width = Rule.extent_width(E.required_extent(width, height, border, E.frame_content(frame)))
  Nat.max_ge_r(minimum_width, required_width)

def outer_height_style(+ink: E.Extent, +geometry: C.Geometry, +style: D.Style) ->
  {Nat.is_ge(E.extent_height(S.outer_extent(ink, geometry, style)), D.style_minimum_height(style)) == True{} : Bool}:
  E.Extent{width, height} = ink
  C.Geometry{Space.Demand{E.Extent{minimum_width, +minimum_height}, preferred}, icon, radius, leading} = geometry
  D.Style{text, D.Chrome{foreground, background, paint, border, radius, shadow}, alignment, flow, overflow, frame, +minimum, maximum, states} = style
  required_height = E.extent_height(E.required_extent(width, height, border, E.frame_content(frame)))
  Nat.max_ge_l(minimum, Nat.max(minimum_height, required_height))

def outer_height_geometry(+ink: E.Extent, +geometry: C.Geometry, +style: D.Style) ->
  {Nat.is_le(C.geometry_minimum_height(geometry), E.extent_height(S.outer_extent(ink, geometry, style))) == True{} : Bool}:
  E.Extent{width, height} = ink
  C.Geometry{Space.Demand{E.Extent{minimum_width, +minimum_height}, preferred}, icon, radius, leading} = geometry
  D.Style{text, D.Chrome{foreground, background, paint, border, radius, shadow}, alignment, flow, overflow, frame, +minimum, maximum, states} = style
  +required_height = E.extent_height(E.required_extent(width, height, border, E.frame_content(frame)))
  +inner = Nat.max(minimum_height, required_height)
  +outer = Nat.max(minimum, inner)
  SpaceLawsProof.le_trans(minimum_height, inner, outer,
    Equal.trans(Bool, Nat.is_le(minimum_height, inner), Nat.is_ge(inner, minimum_height), True{}, Equal.sym(Bool, Nat.is_ge(inner, minimum_height), Nat.is_le(minimum_height, inner), SpaceLawsProof.ge_le(inner, minimum_height)), Nat.max_ge_l(minimum_height, required_height)),
    Equal.trans(Bool, Nat.is_le(inner, outer), Nat.is_ge(outer, inner), True{}, Equal.sym(Bool, Nat.is_ge(outer, inner), Nat.is_le(inner, outer), SpaceLawsProof.ge_le(outer, inner)), Nat.max_ge_r(minimum, inner)))

def outer_height_ink(+ink: E.Extent, +geometry: C.Geometry, +style: D.Style) ->
  {Nat.is_le(E.extent_height(Rule.padded_ink(ink, style)), E.extent_height(S.outer_extent(ink, geometry, style))) == True{} : Bool}:
  E.Extent{width, height} = ink
  C.Geometry{Space.Demand{E.Extent{minimum_width, +minimum_height}, preferred}, icon, radius, leading} = geometry
  D.Style{text, D.Chrome{foreground, background, paint, border, radius, shadow}, alignment, flow, overflow, frame, +minimum, maximum, states} = style
  +required_height = E.extent_height(E.required_extent(width, height, border, E.frame_content(frame)))
  +inner = Nat.max(minimum_height, required_height)
  +outer = Nat.max(minimum, inner)
  SpaceLawsProof.le_trans(required_height, inner, outer,
    Equal.trans(Bool, Nat.is_le(required_height, inner), Nat.is_ge(inner, required_height), True{}, Equal.sym(Bool, Nat.is_ge(inner, required_height), Nat.is_le(required_height, inner), SpaceLawsProof.ge_le(inner, required_height)), Nat.max_ge_r(minimum_height, required_height)),
    Equal.trans(Bool, Nat.is_le(inner, outer), Nat.is_ge(outer, inner), True{}, Equal.sym(Bool, Nat.is_ge(outer, inner), Nat.is_le(inner, outer), SpaceLawsProof.ge_le(outer, inner)), Nat.max_ge_r(minimum, inner)))

def face_other_demand(+face: C.Face, +demand: Space.Demand) -> Rule.UnshapedDemand(face, demand, C.face_demand(face, demand)):
  match face:
    case C.IconFace{icon}: Unit{}
    case C.TextFace{text}: {==}
    case C.SingleLineFace{text}: {==}
    case C.IconTextFace{icon, text}: {==}
    case C.PickerFace{leading, text}: {==}
    case C.ChoiceFace{text, description, checked}: {==}
    case C.DisclosureFace{text, expanded}: {==}
    case C.PermissionFace{filesystem, network, approval}: {==}

def shape_awaiting(face: C.Face, +missing: +List<T.MeasurementSpec>) ->
  {S.shape_content(face, S.AwaitingInk{missing}) == S.AwaitingInk{missing} : S.Content}:
  {==}

def shape_icon_axes(icon: C.Icon, content: S.Content) -> Rule.SquareContent(S.shape_content(C.IconFace{icon}, content)):
  match content:
    case S.AwaitingInk{missing}: Unit{}
    case S.MeasuredInk{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}}: ({==}, {==})

def shape_other_faces(+face: C.Face, +content: S.Content) -> Rule.UnshapedContent(face, content, S.shape_content(face, content)):
  match face:
    case C.IconFace{icon}: Unit{}
    case C.TextFace{text}: match content:
      case S.AwaitingInk{missing}: {==}
      case S.MeasuredInk{demand}: {==}
    case C.SingleLineFace{text}: match content:
      case S.AwaitingInk{missing}: {==}
      case S.MeasuredInk{demand}: {==}
    case C.IconTextFace{icon, text}: match content:
      case S.AwaitingInk{missing}: {==}
      case S.MeasuredInk{demand}: {==}
    case C.PickerFace{leading, text}: match content:
      case S.AwaitingInk{missing}: {==}
      case S.MeasuredInk{demand}: {==}
    case C.ChoiceFace{text, description, checked}: match content:
      case S.AwaitingInk{missing}: {==}
      case S.MeasuredInk{demand}: {==}
    case C.DisclosureFace{text, expanded}: match content:
      case S.AwaitingInk{missing}: {==}
      case S.MeasuredInk{demand}: {==}
    case C.PermissionFace{filesystem, network, approval}: match content:
      case S.AwaitingInk{missing}: {==}
      case S.MeasuredInk{demand}: {==}

def natural_icon_axes(measured: +List<T.Measured>, key: String, +icon: C.Icon, +geometry: C.Geometry, +style: D.Style) ->
  Rule.SquareContent(S.natural_demand(measured, key, C.IconFace{icon}, geometry, style)):
  D.Style{text, chrome, alignment, flow, overflow, frame, height, maximum, states} = style
  shape_icon_axes(icon, Rule.unshaped_demand(measured, key, C.IconFace{icon}, geometry, style))

def natural_other_faces(+measured: +List<T.Measured>, +key: String, +face: C.Face, +geometry: C.Geometry, +style: D.Style) ->
  Rule.UnshapedContent(face, Rule.unshaped_demand(measured, key, face, geometry, style), S.natural_demand(measured, key, face, geometry, style)):
  D.Style{text, chrome, alignment, flow, overflow, frame, height, maximum, states} = style
  shape_other_faces(face, Rule.unshaped_demand(measured, key, face, geometry, style))

def Rule.evidence():
  Rule.Requirements{face_other_demand, shape_awaiting, natural_icon_axes, natural_other_faces, prepare_semantics, refinement_control, refinement_style, demand_consumed, choice_reservation,
    outer_width_geometry, outer_width_ink, outer_height_style, outer_height_geometry, outer_height_ink}
