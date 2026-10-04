import Base
import ./content-space.bend as S
import ./design.bend as D
import ./controls.bend as C
import ./enclosure.bend as E
import ./typography.bend as T
import ./space.bend as Space
import ../core/SYSTEM.bend as Core
import ../core/ui-world.bend as View
import ../core/interface.bend as UI

# These claims cover natural action content and semantic identity. The browser's
# measured pixels and height after width allocation remain external premises.

def NodesClaim(original: +List<D.Node>, result: S.Nodes) -> Type:
  match result:
    case S.AwaitingNodes{missing}: Unit
    case S.PreparedNodes{nodes}: {D.semantic_nodes(nodes) == D.semantic_nodes(original) : +List<UI.Node>}

def SurfaceClaim(original: D.Surface, result: S.Outcome) -> Type:
  match result:
    case S.AwaitingContent{missing}: Unit
    case S.Prepared{surface}: {D.semantic_surface(surface) == D.semantic_surface(original) : UI.Surface}

def control_identity(value: C.Representation) -> C.Representation:
  match value:
    case C.Action{input, availability, name, face, behavior, C.Geometry{Space.Demand{E.Extent{width, height}, preferred}, icon, radius, leading}, placement, help, feedback}:
      C.Action{input, availability, name, face, behavior, C.Geometry{Space.fixed_demand(0n, 0n), icon, radius, leading}, placement, help, feedback}
    case _: value

def style_identity(value: D.Style) -> D.Style:
  D.Style{text, chrome, alignment, flow, overflow, frame, height, maximum, states} = value
  D.Style{text, chrome, alignment, flow, overflow, frame, 0n, maximum, states}

def node_control(node: D.Node) -> C.Representation:
  D.Node{key, semantic, label, role, meaning, style, control, children} = node
  control

def node_style(node: D.Node) -> D.Style:
  D.Node{key, semantic, label, role, meaning, style, control, children} = node
  style

def node_children(node: D.Node) -> +List<D.Node>:
  D.Node{key, semantic, label, role, meaning, style, control, children} = node
  children

def surface_base(surface: D.Surface) -> +List<D.Node>:
  D.Surface{content, theme, base, overlays, scope} = surface
  base

def surface_overlays(surface: D.Surface) -> +List<D.Node>:
  D.Surface{content, theme, base, overlays, scope} = surface
  overlays

def control_action_demand(control: C.Representation) -> Maybe<&2, Space.Demand>:
  match control:
    case C.Action{input, availability, name, face, behavior, C.Geometry{demand, icon, radius, leading}, placement, help, feedback}: Some{demand}
    case _: None{}

def node_action_demand(node: D.Node) -> Maybe<&2, Space.Demand>:
  control_action_demand(node_control(node))

# Observe the actual prepared node rather than repeating its construction.
def prepared_action_demand(result: S.Nodes) -> Maybe<&2, Space.Demand>:
  match result:
    case S.AwaitingNodes{missing}: None{}
    case S.PreparedNodes{nodes}:
      match nodes:
        case Nil{}: None{}
        case Con{node, rest}: node_action_demand(node)

def extent_width(value: E.Extent) -> Nat:
  E.Extent{width, height} = value
  width

def padded_ink(ink: E.Extent, style: D.Style) -> E.Extent:
  E.Extent{width, height} = ink
  D.Style{text, D.Chrome{foreground, background, paint, border, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = style
  E.required_extent(width, height, border, E.frame_content(frame))

def geometry_width(value: C.Geometry) -> Nat:
  C.Geometry{Space.Demand{E.Extent{width, height}, preferred}, icon, radius, leading} = value
  width

def UnshapedDemand(face: C.Face, original: Space.Demand, shaped: Space.Demand) -> Type:
  match face:
    case C.IconFace{icon}: Unit
    case _: {shaped == original : Space.Demand}

def SquareContent(content: S.Content) -> Type:
  match content:
    case S.AwaitingInk{missing}: Unit
    case S.MeasuredInk{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}}:
      {width == height : Nat} & {preferred_width == preferred_height : Nat}

def UnshapedContent(face: C.Face, original: S.Content, shaped: S.Content) -> Type:
  match face:
    case C.IconFace{icon}: Unit
    case _: {shaped == original : S.Content}

def unshaped_demand(measured: +List<T.Measured>, key: String, face: C.Face, +geometry: C.Geometry, +style: D.Style) -> S.Content:
  D.Style{text, chrome, alignment, flow, overflow, frame, height, maximum, states} = style
  S.outer_content(S.ink(measured, key, face, text, geometry, E.frame_gap(frame)), geometry, style)

type Requirements is Type:
  Requirements{
    face_other_demand: @+face:C.Face -> @+demand:Space.Demand -> UnshapedDemand(face, demand, C.face_demand(face, demand)),
    shape_awaiting: @face:C.Face -> @+missing:+List<T.MeasurementSpec> -> {S.shape_content(face, S.AwaitingInk{missing}) == S.AwaitingInk{missing} : S.Content},
    natural_icon_axes: @measured:+List<T.Measured> -> @key:String -> @+icon:C.Icon -> @+geometry:C.Geometry -> @+style:D.Style -> SquareContent(S.natural_demand(measured, key, C.IconFace{icon}, geometry, style)),
    natural_other_faces: @+measured:+List<T.Measured> -> @+key:String -> @+face:C.Face -> @+geometry:C.Geometry -> @+style:D.Style -> UnshapedContent(face, unshaped_demand(measured, key, face, geometry, style), S.natural_demand(measured, key, face, geometry, style)),
    semantics: @+measured:+List<T.Measured> -> @+surface:D.Surface -> SurfaceClaim(surface, S.prepare(measured, surface)),
    control: @+node:D.Node -> @+demand:Space.Demand -> @+children:+List<D.Node> -> {control_identity(node_control(S.refine_node(node, demand, children))) == control_identity(node_control(node)) : C.Representation},
    style: @+node:D.Node -> @+demand:Space.Demand -> @+children:+List<D.Node> -> {style_identity(node_style(S.refine_node(node, demand, children))) == style_identity(node_style(node)) : D.Style},
    consumed: @+key:String -> @+semantic:String -> @+label:String -> @+role:UI.Role -> @+meaning:UI.Meaning -> @+style:D.Style -> @+input:Core.Input -> @+availability:View.Availability -> @+name:String -> @+face:C.Face -> @+behavior:C.Behavior -> @+geometry:C.Geometry -> @+placement:C.Placement -> @+help:C.Help -> @+feedback:C.Feedback -> @+original_children:+List<D.Node> -> @+minimum:E.Extent -> @+preferred:E.Extent -> @+children:+List<D.Node> -> {prepared_action_demand(S.finish_node(D.Node{key, semantic, label, role, meaning, style, C.Action{input, availability, name, face, behavior, geometry, placement, help, feedback}, original_children}, S.MeasuredInk{Space.Demand{minimum, preferred}}, S.PreparedNodes{children})) == Some{Space.Demand{minimum, preferred}} : Maybe<&2, Space.Demand>},
    choice: @+measured:+List<T.Measured> -> @+key:String -> @+caption:String -> @+description:Maybe<&2, String> -> @+text:T.Presentation -> @+geometry:C.Geometry -> @+gap:Nat -> {S.ink(measured, key, C.ChoiceFace{caption, description, True{}}, text, geometry, gap) == S.ink(measured, key, C.ChoiceFace{caption, description, False{}}, text, geometry, gap) : S.Content},
    outer_width_geometry: @+ink:E.Extent -> @+geometry:C.Geometry -> @+style:D.Style -> {Nat.is_ge(extent_width(S.outer_extent(ink, geometry, style)), geometry_width(geometry)) == True{} : Bool},
    outer_width_ink: @+ink:E.Extent -> @+geometry:C.Geometry -> @+style:D.Style -> {Nat.is_ge(extent_width(S.outer_extent(ink, geometry, style)), extent_width(padded_ink(ink, style))) == True{} : Bool},
    outer_height_style: @+ink:E.Extent -> @+geometry:C.Geometry -> @+style:D.Style -> {Nat.is_ge(E.extent_height(S.outer_extent(ink, geometry, style)), D.style_minimum_height(style)) == True{} : Bool},
    outer_height_geometry: @+ink:E.Extent -> @+geometry:C.Geometry -> @+style:D.Style -> {Nat.is_le(C.geometry_minimum_height(geometry), E.extent_height(S.outer_extent(ink, geometry, style))) == True{} : Bool},
    outer_height_ink: @+ink:E.Extent -> @+geometry:C.Geometry -> @+style:D.Style -> {Nat.is_le(E.extent_height(padded_ink(ink, style)), E.extent_height(S.outer_extent(ink, geometry, style))) == True{} : Bool}}

law evidence:
  Requirements
