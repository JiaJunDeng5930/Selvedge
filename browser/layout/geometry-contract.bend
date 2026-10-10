import Base
import ./SPACE.bend as Space
import ./GEOMETRY.bend as SpatialModel
import ../appearance/DESIGN.bend as Model
import ../../bendlib/stdlib.bend as Std
import ../../interaction/IDENTITY.bend as Identity
import ../appearance/TYPOGRAPHY.bend as T
import ./enclosure.bend as E
import ../appearance/MODEL.bend as A
import ../controls/PROGRAM.bend as C
import ../../interaction/presentation/MODEL.bend as View
import ../../interaction/TYPES.bend as InteractionTypes
import ../../interaction/presentation/SURFACE.bend as SurfaceTypes
import ./natural-size.bend as Size
import ../../interaction/submission/FIELDS.bend as Forms
import ./physical-space.bend as Model2

def inner_budget(+leading: Nat, trailing: Nat, available: Nat) -> Nat:
  Nat.sub(Nat.sub(available, leading), trailing)

def contains(outer: SpatialModel.Box, inner: SpatialModel.Box) -> Bool:
  SpatialModel.Box{+outer_left, +outer_top, outer_width, outer_height} = outer
  SpatialModel.Box{+inner_left, +inner_top, inner_width, inner_height} = inner
  Bool.and(Nat.is_le(outer_left, inner_left),
    Bool.and(Nat.is_le(outer_top, inner_top),
      Bool.and(Nat.is_le(Nat.add(inner_left, inner_width), Nat.add(outer_left, outer_width)),
        Nat.is_le(Nat.add(inner_top, inner_height), Nat.add(outer_top, outer_height)))))

def all_contained(+target: SpatialModel.Box, placements: +List<Model.NodePlacement>) -> Bool:
  match placements:
    case Nil{}: True{}
    case Con{Model.NodePlacement{key, bounds}, rest}:
      Bool.and(contains(target, bounds), all_contained(target, rest))

def maximum_ok(dimension: Space.Dimension, +size: Nat) -> Bool:
  match dimension:
    case Space.Rigid{value}: Nat.is_le(size, value)
    case Space.Fit{lower, extra, maximum_extra}: Nat.is_le(size, Nat.add(Nat.add(lower, extra), maximum_extra))
    case Space.Fill{lower}: True{}

def rigid_ok(dimension: Space.Dimension, +size: Nat) -> Bool:
  match dimension:
    case Space.Rigid{value}: Nat.is_eq(size, value)
    case _: True{}

def slot_value(~A: Data, slot: Space.Slot<A>) -> A:
  Space.Slot{value, dimension} = slot
  value

def placement_value(~A: Data, placement: Space.Placement<A>) -> A:
  Space.Placement{value, offset, extent} = placement
  value

def slot_values(~A: Data, values: +List<Space.Slot<A>>) -> +List<A>:
  Std.map(~Space.Slot<A>, ~A, ~(value => slot_value(~A, value)), values)

def placement_values(~A: Data, values: +List<Space.Placement<A>>) -> +List<A>:
  Std.map(~Space.Placement<A>, ~A, ~(value => placement_value(~A, value)), values)

def placement_gap(~A: Data, values: +List<Space.Placement<A>>, gap: Nat) -> Nat:
  match values:
    case Nil{}: 0n
    case Con{head, tail}: gap

def used(~A: Data, values: +List<Space.Placement<A>>, +gap: Nat) -> Nat:
  match values:
    case Nil{}: 0n
    case Con{Space.Placement{value, offset, size}, rest}:
      match rest:
        case Nil{}: size
        case Con{next, tail}: Nat.add(size, Nat.add(gap, used(~A, next <> tail, gap)))

def limits(~A: Data, slots: +List<Space.Slot<A>>, placements: +List<Space.Placement<A>>) -> Bool:
  match slots placements:
    case Nil{} Nil{}: True{}
    case Con{Space.Slot{value, +dimension}, rest} Con{Space.Placement{other, offset, +size}, tail}:
      Nat.is_le(Space.minimum(dimension), size) &&
      (maximum_ok(dimension, size) && (rigid_ok(dimension, size) && limits(~A, rest, tail)))
    case _ _: False{}

def positions(~A: Data, values: +List<Space.Placement<A>>, +gap: Nat, offset: Nat) -> Bool:
  match values:
    case Nil{}: True{}
    case Con{Space.Placement{value, +actual, +size}, +rest}:
      Nat.is_eq(actual, offset) && positions(~A, rest, gap,
        Nat.add(actual, Nat.add(size, placement_gap(~A, rest, gap))))

def allocated_values(~A: Data, result: Space.Allocation<A>) -> +List<A>:
  Space.Allocation{placements, unused} = result
  placement_values(~A, placements)

def allocated_limits(~A: Data, slots: +List<Space.Slot<A>>, result: Space.Allocation<A>) -> Bool:
  Space.Allocation{placements, unused} = result
  limits(~A, slots, placements)

def allocated_positions(~A: Data, result: Space.Allocation<A>, gap: Nat, offset: Nat) -> Bool:
  Space.Allocation{placements, unused} = result
  positions(~A, placements, gap, offset)

def allocated_total(~A: Data, result: Space.Allocation<A>, gap: Nat) -> Nat:
  Space.Allocation{placements, unused} = result
  Nat.add(used(~A, placements, gap), unused)

type AllocationEvidence<-A: Data, -slots: +List<Space.Slot<A>>, -gap: Nat, -offset: Nat, -budget: Nat, -result: Space.Allocation<A>> is Type:
  AllocationEvidence{
    payloads: {allocated_values(~A, result) == slot_values(~A, slots) : +List<A>},
    bounds: {allocated_limits(~A, slots, result) == True{} : Bool},
    order: {allocated_positions(~A, result, gap, offset) == True{} : Bool},
    budget: {allocated_total(~A, result, gap) == budget : Nat}}

def ContainerClaim(~A: Data, +container: Space.Container<A>, +available: Nat, result: Space.Packing<A>) -> Type:
  Space.Container{leading, trailing, gap, slots} = container
  match result:
    case Space.Packed{placements, unused}:
      AllocationEvidence<A, slots, gap, leading, inner_budget(leading, trailing, available), Space.Allocation{placements, unused}> &
      {Nat.add(leading, Nat.add(Nat.add(used(~A, placements, gap), unused), trailing)) == available : Nat}
    case Space.Insufficient{required, received}:
      {required == Space.container_required(~A, container) : Nat} &
      ({received == available : Nat} &
      {Nat.is_le(Space.container_required(~A, container), available) == False{} : Bool})

type Requirement<-A: Data> is Type:
  Requirement{complete: @+container:Space.Container<A> -> @+available:Nat ->
    ContainerClaim(~A, container, available, Space.pack_container(~A, container, available))}

law container_space_evidence:
  for ~A: Data
  Requirement<A>

def packed(~A: Data, value: Space.Packing<A>) -> Bool:
  match value:
    case Space.Packed{placements, unused}: True{}
    case Space.Insufficient{required, available}: False{}

def PackedClaim(~A: Data, +slots: +List<Space.Slot<A>>, +gap: Nat, +available: Nat, result: Space.Packing<A>) -> Type:
  match result:
    case Space.Packed{placements, unused}:
      AllocationEvidence<A, slots, gap, 0n, available, Space.Allocation{placements, unused}>
    case Space.Insufficient{required, received}: Empty

type SpaceRequirements<-A: Data> is Type:
  SpaceRequirements{
    larger_eq_max: @+first:Nat -> @+second:Nat ->
      {Space.larger(first, second) == Nat.max(first, second) : Nat},
    smaller_eq_min: @+first:Nat -> @+second:Nat ->
      {Space.smaller(first, second) == Nat.min(first, second) : Nat},
    minimum_preferred: @+dimension:Space.Dimension ->
      {Nat.is_le(Space.minimum(dimension), Space.preferred(dimension)) == True{} : Bool},
    preferred_maximum: @+dimension:Space.Dimension ->
      {maximum_ok(dimension, Space.preferred(dimension)) == True{} : Bool},
    complete_feasibility: @+slots:+List<Space.Slot<A>> -> @+gap:Nat -> @+available:Nat ->
      {packed(~A, Space.pack(~A, slots, gap, available)) == Nat.is_le(Space.minimum_sequence(~A, slots, gap), available) : Bool},
    insufficient_record: @+slots:+List<Space.Slot<A>> -> @+gap:Nat -> @+available:Nat ->
      @does_not_fit:{Nat.is_le(Space.minimum_sequence(~A, slots, gap), available) == False{} : Bool} ->
      {Space.pack(~A, slots, gap, available) == Space.Insufficient{Space.minimum_sequence(~A, slots, gap), available} : Space.Packing<A>},
    packed_construction: @+slots:+List<Space.Slot<A>> -> @+gap:Nat -> @+available:Nat ->
      @+fits:{Nat.is_le(Space.minimum_sequence(~A, slots, gap), available) == True{} : Bool} ->
      PackedClaim(~A, slots, gap, available, Space.pack(~A, slots, gap, available))}

law space_evidence:
  for ~A: Data
  SpaceRequirements<A>

def actual_geometry(value: C.Representation) -> C.Geometry:
  match value:
    case C.Action{input, availability, name, face, behavior, geometry, placement, help, feedback}: geometry
    case _: C.Geometry{Space.fixed_demand(0n, 0n), 0n, 0n, 0n}

def mark_extent(layout: C.ChoiceContentLayout) -> Nat:
  C.ChoiceContentLayout{text_gap, extent, icon_extent} = layout
  extent

def mark_icon_extent(layout: C.ChoiceContentLayout) -> Nat:
  C.ChoiceContentLayout{text_gap, extent, icon_extent} = layout
  icon_extent

type NaturalSizeRequirements is Type:
  NaturalSizeRequirements{
    addition_capacity: @+capacity:Nat -> @+left:Nat -> @+right:Nat ->
      @conflict:{Nat.is_le(left, Nat.sub(capacity, right)) == False{} : Bool} ->
      {Size.checked_add(capacity, left, right) == None{} : Maybe<&2, Nat>},
    multiplication_capacity: @+capacity:Nat -> @+left:Nat -> @+right:Nat ->
      @nonzero:{Nat.is_eq(right, 0n) == False{} : Bool} ->
      @conflict:{Nat.is_le(left, Nat.div(capacity, right)) == False{} : Bool} ->
      {Size.checked_mul(capacity, left, right) == None{} : Maybe<&2, Nat>},
    multiplication_zero: @+capacity:Nat -> @left:Nat ->
      {Size.checked_mul(capacity, left, 0n) == Some{0n} : Maybe<&2, Nat>}}

law natural_size_evidence:
  NaturalSizeRequirements

def extent_contains(outer: E.Extent, inner: E.Extent) -> Bool:
  E.Extent{outer_width, outer_height} = outer
  E.Extent{inner_width, inner_height} = inner
  Nat.is_le(inner_width, outer_width) && Nat.is_le(inner_height, outer_height)

def authored_minimum(size: Model2.AxisSize) -> Nat:
  match size:
    case Model2.NaturalSize{}: 0n
    case Model2.StretchSize{}: 0n
    case Model2.CappedStretchSize{maximum}: 0n
    case Model2.ExactSize{extent}: extent
    case Model2.LimitedSize{minimum, extra, maximum}: minimum
    case Model2.PercentSize{percent}: 0n
    case Model2.CappedNaturalSize{percent}: 0n
    case Model2.AdaptiveNaturalSize{percent}: 0n

def axis_minimum(value: Model2.AxisDemand) -> Nat:
  Model2.AxisDemand{minimum, preferred} = value
  minimum

def axis_preferred(value: Model2.AxisDemand) -> Nat:
  Model2.AxisDemand{minimum, preferred} = value
  preferred

def rule_authored_minimum(rule: Model2.Rule) -> E.Extent:
  Model2.Rule{direction, main, cross, frame, border, width, height, minimum, scroll, position} = rule
  E.Extent{authored_minimum(width), authored_minimum(height)}

def preferred_covers_minimum(value: Space.Demand) -> Bool:
  Space.Demand{minimum, preferred} = value
  extent_contains(preferred, minimum)

def child_minima_participate(~A: Data, ~E: Data, trees: +List<Model2.Tree<A, E>>, +required: E.Extent) -> Bool:
  match trees:
    case Nil{}: True{}
    case Con{tree, rest}:
      extent_contains(required, Model2.minimum_demand(Model2.demand(~A, ~E, tree))) &&
        child_minima_participate(~A, ~E, rest, required)

def percentage_conflict(+extent: Maybe<&2, Nat>, +minimum: Nat) -> Bool:
  match extent:
    case None{}: True{}
    case Some{cap}: Bool.not(Nat.is_le(minimum, cap))

def capped_stretch_dimension(+minimum: Nat, maximum: Nat) -> Space.Dimension:
  Space.Fit{minimum, Nat.sub(maximum, minimum), 0n}

def rejected(result: Maybe<&2, Space.Dimension>) -> Bool:
  match result:
    case None{}: True{}
    case Some{dimension}: False{}

def allocated_width(result: Maybe<&2, Space.Dimension>, room: Nat) -> Maybe<&2, Nat>:
  match result:
    case None{}: None{}
    case Some{dimension}: Some{Space.choose(dimension, room)}

def adaptive_maximum(+minimum: Nat, +offered: Nat, +nominal_cap: Nat) -> Nat:
  Space.smaller(offered, Space.larger(minimum, nominal_cap))

def adaptive_fit(+minimum: Nat, +preferred: Nat, +offered: Nat, +nominal_cap: Nat) -> Space.Dimension:
  +maximum = adaptive_maximum(minimum, offered, nominal_cap)
  +chosen = Space.smaller(maximum, Space.larger(minimum, preferred))
  Space.Fit{minimum, Nat.sub(chosen, minimum), Nat.sub(maximum, chosen)}

def adaptive_ceiling(+minimum: Nat, +preferred: Nat, +offered: Nat, +nominal_cap: Nat) -> Nat:
  +maximum = adaptive_maximum(minimum, offered, nominal_cap)
  +chosen = Space.smaller(maximum, Space.larger(minimum, preferred))
  Nat.add(Nat.add(minimum, Nat.sub(chosen, minimum)), Nat.sub(maximum, chosen))

def nominal_percentage(+offered: Nat, +percent: Nat) -> Nat:
  Nat.add(Nat.mul(Nat.div(offered, 100n), percent), Nat.div(Nat.mul(Nat.mod(offered, 100n), percent), 100n))

def minimum_result(result: Maybe<&2, Space.Dimension>) -> Maybe<&2, Nat>:
  match result:
    case None{}: None{}
    case Some{dimension}: Some{Space.minimum(dimension)}

def maximum_fits(result: Maybe<&2, Space.Dimension>, +offered: Nat) -> Bool:
  match result:
    case None{}: False{}
    case Some{Space.Rigid{extent}}: Nat.is_le(extent, offered)
    case Some{Space.Fit{minimum, preferred_extra, maximum_extra}}: Nat.is_le(Nat.add(Nat.add(minimum, preferred_extra), maximum_extra), offered)
    case Some{Space.Fill{minimum}}: False{}

law aligned_clearance_contains:
  for +outside: E.Insets
  for +horizontal: SpatialModel.Alignment
  for +vertical: SpatialModel.Alignment
  for +extent: E.Extent
  {extent_contains(Model2.clearance_extent(Model2.Layered{}, SpatialModel.AlignedLayer{outside, horizontal, vertical}, extent), extent) == True{} : Bool}

def frame_coordinates(+frame: E.Frame) -> (Nat & (Nat & Nat)):
  (E.inline(E.frame_content(frame)), (E.block(E.frame_content(frame)), E.frame_gap(frame)))

def chrome(value: Model.Style) -> Model.Chrome:
  Model.Style{text, chrome, alignment, flow, overflow, +content_frame, height, maximum, states} = value
  chrome

def style_flow(value: Model.Style) -> SpatialModel.Flow:
  Model.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = value
  flow

def choice_style_metrics(+value: Model.Style) -> (Nat & SpatialModel.Flow):
  (E.frame_gap(Model.style_frame(value)), style_flow(value))

def actual_choice_normalization_law(-key: Identity.Key, -selected: Bool, -description: String, -input: InteractionTypes.Input, -availability: View.Availability, -label: String,
  -role: SurfaceTypes.Role, -context: C.Context, -fallback: Model.Style, +typography: T.Presentation) -> Type:
  {choice_style_metrics(A.control_style(fallback, C.make_choice(key, SurfaceTypes.SingleChoice{}, None{}, selected, description, input, availability, label, role, context), typography)) == (8n, SpatialModel.ChoiceFlow{}) : (Nat & SpatialModel.Flow)}

type FrameRelationRequirements is Type:
  FrameRelationRequirements{
    actual_action_flow: @+value:Model.Style -> @+face:C.Face -> @+size:C.Geometry ->
      {style_flow(A.action_style(value, face, size)) == A.action_flow(face, C.content_layout(face)) : SpatialModel.Flow},
    actual_choice_normalization: @+typography:T.Presentation -> @+key:Identity.Key -> @+selected:Bool -> @+description:String -> @+input:InteractionTypes.Input -> @+availability:View.Availability -> @+label:String -> @+role:SurfaceTypes.Role -> @+context:C.Context -> @+fallback:Model.Style ->
      actual_choice_normalization_law(key, selected, description, input, availability, label, role, context, fallback, typography),
    embedded_gap: @+content:E.ContentArea -> @+gap:Nat -> {E.frame_gap(E.frame(content, E.EmbeddedContent{gap})) == gap : Nat},
    separate_gap: @+content:E.ContentArea -> @+spacing:E.Separation -> {E.frame_gap(E.frame(content, E.SeparateFrames{spacing})) == E.separation(spacing) : Nat},
    joined_gap: @content:E.ContentArea -> {E.frame_gap(E.frame(content, E.JoinedPartitions{})) == 0n : Nat},
    content_preserves_arrangement: @+value:Model.Style -> @content:E.ContentArea -> {E.frame_gap(Model.style_frame(A.with_content_area(value, content))) == E.frame_gap(Model.style_frame(value)) : Nat},
    role_navigation: @+typography:T.Presentation -> @+meaning:SurfaceTypes.Meaning -> {Model.style_frame(A.style(SurfaceTypes.Navigation{}, meaning, typography)) == E.Frame{E.area(E.Navigation{}), E.SeparateFrames{E.NavigationRows{}}} : E.Frame},
    role_menu: @+typography:T.Presentation -> @+meaning:SurfaceTypes.Meaning -> {Model.style_frame(A.style(SurfaceTypes.Menu{}, meaning, typography)) == E.Frame{E.area(E.Menu{}), E.SeparateFrames{E.MenuItems{}}} : E.Frame},
    role_card: @+typography:T.Presentation -> @+meaning:SurfaceTypes.Meaning -> {Model.style_frame(A.style(SurfaceTypes.Card{}, meaning, typography)) == E.Frame{E.area(E.Card{}), E.SeparateFrames{E.CardSections{}}} : E.Frame},
    role_details: @+typography:T.Presentation -> @+meaning:SurfaceTypes.Meaning -> {Model.style_frame(A.style(SurfaceTypes.Details{}, meaning, typography)) == E.Frame{E.area(E.Details{}), E.SeparateFrames{E.Sections{}}} : E.Frame},
    role_dialog: @+typography:T.Presentation -> @+meaning:SurfaceTypes.Meaning -> {Model.style_frame(A.style(SurfaceTypes.Dialog{}, meaning, typography)) == E.Frame{E.DialogPartitions{}, E.JoinedPartitions{}} : E.Frame},
    actual_choice_geometry: @+key:Identity.Key -> @+selected:Bool -> @+description:String -> @+input:InteractionTypes.Input -> @+availability:View.Availability -> @+label:String -> @+role:SurfaceTypes.Role -> @+context:C.Context -> {actual_geometry(C.make_choice(key, SurfaceTypes.SingleChoice{}, None{}, selected, description, input, availability, label, role, context)) == C.Geometry{Space.fixed_demand(0n, 28n), 16n, 6n, 20n} : C.Geometry},
    actual_choice_layout: @+key:Identity.Key -> @+selected:Bool -> @+description:String -> @+input:InteractionTypes.Input -> @+availability:View.Availability -> @+label:String -> @+role:SurfaceTypes.Role -> @+context:C.Context -> {C.choice_layout(C.make_choice(key, SurfaceTypes.SingleChoice{}, None{}, selected, description, input, availability, label, role, context)) == C.ChoiceContentLayout{2n, 20n, 16n} : C.ChoiceContentLayout},
    actual_choice_mark_contains_icon: @+key:Identity.Key -> @+selected:Bool -> @+description:String -> @+input:InteractionTypes.Input -> @+availability:View.Availability -> @+label:String -> @+role:SurfaceTypes.Role -> @+context:C.Context -> {Nat.is_le(mark_icon_extent(C.choice_layout(C.make_choice(key, SurfaceTypes.SingleChoice{}, None{}, selected, description, input, availability, label, role, context))), mark_extent(C.choice_layout(C.make_choice(key, SurfaceTypes.SingleChoice{}, None{}, selected, description, input, availability, label, role, context)))) == True{} : Bool},
    selection_keeps_allocation: @+key:Identity.Key -> @+description:String -> @+input:InteractionTypes.Input -> @+availability:View.Availability -> @+label:String -> @+role:SurfaceTypes.Role -> @+context:C.Context -> {C.choice_layout(C.make_choice(key, SurfaceTypes.SingleChoice{}, None{}, True{}, description, input, availability, label, role, context)) == C.choice_layout(C.make_choice(key, SurfaceTypes.SingleChoice{}, None{}, False{}, description, input, availability, label, role, context)) : C.ChoiceContentLayout},
    timeline_gap: @+typography:T.Presentation -> @+meaning:SurfaceTypes.Meaning -> {E.frame_gap(Model.style_frame(A.style(SurfaceTypes.Timeline{}, meaning, typography))) == E.separation(E.Messages{}) : Nat},
    section_gap: @+typography:T.Presentation -> @+meaning:SurfaceTypes.Meaning -> {E.frame_gap(Model.style_frame(A.style(SurfaceTypes.Section{}, meaning, typography))) == E.separation(E.Sections{}) : Nat}}

law frame_relation_evidence:
  FrameRelationRequirements

def area(value: Model.Style) -> E.ContentArea:
  Model.Style{text, chrome, alignment, flow, overflow, +content_frame, height, maximum, states} = value
  E.frame_content(content_frame)

def interaction(value: Model.Style) -> Model.ControlStates:
  Model.Style{text, chrome, alignment, flow, overflow, +content_frame, height, maximum, states} = value
  states

type PhysicalSpaceRequirements<-A: Data, -E: Data> is Type:
  PhysicalSpaceRequirements{
    axis_authored_floor: @+size:Model2.AxisSize -> @+minimum:Nat -> @+preferred:Nat ->
      {Nat.is_le(authored_minimum(size), axis_minimum(Model2.axis_demand(size, minimum, preferred))) == True{} : Bool},
    outer_authored_floor: @+content:Space.Demand -> @+rule:Model2.Rule -> @+interaction:Model2.Interaction<E> ->
      {extent_contains(Model2.minimum_demand(Model2.outer_demand(~E, content, rule, interaction)), rule_authored_minimum(rule)) == True{} : Bool},
    axis_intrinsic_floor: @+size:Model2.AxisSize -> @+minimum:Nat -> @+preferred:Nat ->
      {Nat.is_le(minimum, axis_minimum(Model2.axis_demand(size, minimum, preferred))) == True{} : Bool},
    axis_preferred_floor: @+size:Model2.AxisSize -> @+minimum:Nat -> @+preferred:Nat ->
      {Nat.is_le(axis_minimum(Model2.axis_demand(size, minimum, preferred)), axis_preferred(Model2.axis_demand(size, minimum, preferred))) == True{} : Bool},
    authored_preferred: @+width:Model2.AxisSize -> @+height:Model2.AxisSize -> @+content:Space.Demand ->
      {preferred_covers_minimum(Model2.authored_demand(width, height, content)) == True{} : Bool},
    authored_floor: @+width:Model2.AxisSize -> @+height:Model2.AxisSize -> @+content:Space.Demand ->
      {extent_contains(Model2.minimum_demand(Model2.authored_demand(width, height, content)), Model2.minimum_demand(content)) == True{} : Bool},
    outer_preferred: @+content:Space.Demand -> @+rule:Model2.Rule -> @+interaction:Model2.Interaction<E> ->
      {preferred_covers_minimum(Model2.outer_demand(~E, content, rule, interaction)) == True{} : Bool},
    outer_intrinsic_floor: @+content:Space.Demand -> @+rule:Model2.Rule -> @+interaction:Model2.Interaction<E> ->
      {extent_contains(Model2.minimum_demand(Model2.outer_demand(~E, content, rule, interaction)), Model2.minimum_demand(Model2.intrinsic_outer_demand(~E, content, rule, interaction))) == True{} : Bool},
    authored_exact: @+minimum:Nat -> @+preferred:Nat -> @+extent:Nat ->
      {Model2.axis_demand(Model2.ExactSize{extent}, minimum, preferred) == Model2.AxisDemand{Nat.max(minimum, extent), Nat.max(minimum, extent)} : Model2.AxisDemand},
    authored_limited_floor: @+minimum:Nat -> @+preferred:Nat -> @+authored:Nat -> @+extra:Nat -> @+maximum:Nat ->
      {Nat.is_le(authored, axis_minimum(Model2.axis_demand(Model2.LimitedSize{authored, extra, maximum}, minimum, preferred))) == True{} : Bool},

    adaptive_exact: @+minimum:Nat -> @+preferred:Nat -> @+offered:Nat -> @+nominal_cap:Nat ->
      @fits:{Nat.is_le(minimum, offered) == True{} : Bool} ->
      {Model2.adaptive_dimension(Some{nominal_cap}, minimum, preferred, offered) == Some{adaptive_fit(minimum, preferred, offered, nominal_cap)} : Maybe<&2, Space.Dimension>},
    adaptive_total: @+minimum:Nat -> @+preferred:Nat -> @+offered:Nat -> @+percent:Nat ->
      @valid:{Nat.is_le(percent, 100n) == True{} : Bool} -> @fits:{Nat.is_le(minimum, offered) == True{} : Bool} ->
      {Model2.materialize(Model2.AdaptiveNaturalSize{percent}, minimum, preferred, offered) == Some{adaptive_fit(minimum, preferred, offered, nominal_percentage(offered, percent))} : Maybe<&2, Space.Dimension>},
    adaptive_minimum: @+minimum:Nat -> @+preferred:Nat -> @+offered:Nat -> @+percent:Nat ->
      @valid:{Nat.is_le(percent, 100n) == True{} : Bool} -> @fits:{Nat.is_le(minimum, offered) == True{} : Bool} ->
      {minimum_result(Model2.materialize(Model2.AdaptiveNaturalSize{percent}, minimum, preferred, offered)) == Some{minimum} : Maybe<&2, Nat>},
    adaptive_maximum: @+minimum:Nat -> @+preferred:Nat -> @+offered:Nat -> @+percent:Nat ->
      @valid:{Nat.is_le(percent, 100n) == True{} : Bool} -> @fits:{Nat.is_le(minimum, offered) == True{} : Bool} ->
      {maximum_fits(Model2.materialize(Model2.AdaptiveNaturalSize{percent}, minimum, preferred, offered), offered) == True{} : Bool},
    adaptive_normal: @+minimum:Nat -> @+preferred:Nat -> @+offered:Nat -> @+nominal_cap:Nat ->
      @content_fits:{Nat.is_le(minimum, nominal_cap) == True{} : Bool} -> @cap_fits:{Nat.is_le(nominal_cap, offered) == True{} : Bool} ->
      {Model2.adaptive_dimension(Some{nominal_cap}, minimum, preferred, offered) == Model2.capped_dimension(Some{nominal_cap}, minimum, preferred) : Maybe<&2, Space.Dimension>},
    adaptive_invalid: @+minimum:Nat -> @+preferred:Nat -> @+offered:Nat -> @+percent:Nat ->
      @invalid:{Nat.is_le(percent, 100n) == False{} : Bool} ->
      {Model2.materialize(Model2.AdaptiveNaturalSize{percent}, minimum, preferred, offered) == None{} : Maybe<&2, Space.Dimension>},
    adaptive_conflict: @+minimum:Nat -> @+preferred:Nat -> @+offered:Nat -> @+percent:Nat ->
      @conflict:{Nat.is_le(minimum, offered) == False{} : Bool} ->
      {Model2.materialize(Model2.AdaptiveNaturalSize{percent}, minimum, preferred, offered) == None{} : Maybe<&2, Space.Dimension>},
    capped_stretch_accepted: @+minimum:Nat -> @preferred:Nat -> @offered:Nat -> @+maximum:Nat ->
      @fits:{Nat.is_le(minimum, maximum) == True{} : Bool} ->
      {Model2.materialize(Model2.CappedStretchSize{maximum}, minimum, preferred, offered) == Some{capped_stretch_dimension(minimum, maximum)} : Maybe<&2, Space.Dimension>},
    capped_stretch_rejected: @+minimum:Nat -> @preferred:Nat -> @offered:Nat -> @+maximum:Nat ->
      {rejected(Model2.materialize(Model2.CappedStretchSize{maximum}, minimum, preferred, offered)) == Bool.not(Nat.is_le(minimum, maximum)) : Bool},
    capped_stretch_width: @+minimum:Nat -> @preferred:Nat -> @offered:Nat -> @+maximum:Nat -> @+room:Nat ->
      @+fits:{Nat.is_le(minimum, maximum) == True{} : Bool} -> @room_fits:{Nat.is_le(minimum, room) == True{} : Bool} ->
      {allocated_width(Model2.materialize(Model2.CappedStretchSize{maximum}, minimum, preferred, offered), room) == Some{Nat.min(room, maximum)} : Maybe<&2, Nat>},
    capped_stretch_attained: @+minimum:Nat -> @preferred:Nat -> @offered:Nat -> @+maximum:Nat -> @+room:Nat ->
      @+fits:{Nat.is_le(minimum, maximum) == True{} : Bool} -> @+room_fits:{Nat.is_le(maximum, room) == True{} : Bool} ->
      {allocated_width(Model2.materialize(Model2.CappedStretchSize{maximum}, minimum, preferred, offered), room) == Some{maximum} : Maybe<&2, Nat>},
    preferred_floor: @+tree:Model2.Tree<A, E> ->
      {preferred_covers_minimum(Model2.demand(~A, ~E, tree)) == True{} : Bool},
    children_participate: @+trees:+List<Model2.Tree<A, E>> -> @+direction:Model2.Direction -> @+gap:Nat ->
      {child_minima_participate(~A, ~E, trees, Model2.minimum_demand(Model2.content_demand(~A, ~E, trees, direction, gap))) == True{} : Bool},
    operable_floor: @+content:Space.Demand -> @+rule:Model2.Rule -> @first:E -> @remaining:+List<E> -> @enabled:Bool ->
      {extent_contains(Model2.minimum_demand(Model2.outer_demand(~E, content, rule, Model2.Operable{first, remaining, enabled})), E.Extent{32n, 32n}) == True{} : Bool},
    limited_conflict: @+minimum:Nat -> @preferred:Nat -> @offered:Nat -> @+authored_minimum:Nat -> @+preferred_extra:Nat -> @+maximum_extra:Nat ->
      @conflict:{Nat.is_le(minimum, Nat.add(Nat.add(authored_minimum, preferred_extra), maximum_extra)) == False{} : Bool} ->
      {Model2.materialize(Model2.LimitedSize{authored_minimum, preferred_extra, maximum_extra}, minimum, preferred, offered) == None{} : Maybe<&2, Space.Dimension>},
    exact_conflict: @+minimum:Nat -> @preferred:Nat -> @offered:Nat -> @+extent:Nat ->
      @conflict:{Nat.is_le(minimum, extent) == False{} : Bool} ->
      {Model2.materialize(Model2.ExactSize{extent}, minimum, preferred, offered) == None{} : Maybe<&2, Space.Dimension>},
    invalid_percent: @+minimum:Nat -> @preferred:Nat -> @+offered:Nat -> @+percent:Nat ->
      @invalid:{Nat.is_le(percent, 100n) == False{} : Bool} ->
      {Model2.materialize(Model2.PercentSize{percent}, minimum, preferred, offered) == None{} : Maybe<&2, Space.Dimension>},
    invalid_cap: @+minimum:Nat -> @+preferred:Nat -> @+offered:Nat -> @+percent:Nat ->
      @invalid:{Nat.is_le(percent, 100n) == False{} : Bool} ->
      {Model2.materialize(Model2.CappedNaturalSize{percent}, minimum, preferred, offered) == None{} : Maybe<&2, Space.Dimension>},
    capped_conflict: @+minimum:Nat -> @+preferred:Nat -> @+offered:Nat -> @+maximum_percent:Nat ->
      @conflict:{percentage_conflict(Model2.percentage_extent(offered, maximum_percent), minimum) == True{} : Bool} ->
      {Model2.materialize(Model2.CappedNaturalSize{maximum_percent}, minimum, preferred, offered) == None{} : Maybe<&2, Space.Dimension>}}

law physical_space_evidence:
  for ~A: Data
  for ~E: Data
  PhysicalSpaceRequirements<A, E>

def page_content() -> Type:
  {E.spacing(E.PageContent{}) == E.Insets{24n, 24n} : E.Insets}

type EnclosureRequirements is Type:
  EnclosureRequirements{
    page_content: page_content(),positive: @+profile:E.Profile -> {(Nat.min(1n, E.inline(E.area(profile))), Nat.min(1n, E.block(E.area(profile)))) == (1n, 1n) : (Nat & Nat)},
    extent: @+width:Nat -> @+height:Nat -> @+border:Nat -> @+space:E.ContentArea -> {E.required_extent(width, height, border, space) == E.Extent{Nat.add(width, Nat.mul(2n, Nat.add(border, E.inline(space)))), Nat.add(height, Nat.mul(2n, Nat.add(border, E.block(space))))} : E.Extent},
    borderless: @+width:Nat -> @+height:Nat -> @+profile:E.Profile -> {E.required_extent(width, height, 0n, E.area(profile)) == E.Extent{Nat.add(width, Nat.mul(2n, E.inline(E.area(profile)))), Nat.add(height, Nat.mul(2n, E.block(E.area(profile))))} : E.Extent},
    action_insets: @+value:Model.Style -> @+geometry:C.Geometry -> @+space:E.ContentArea -> @+gap:Nat -> @content_height:Nat -> {area(A.action_style_insets(value, geometry, space, gap, content_height)) == space : E.ContentArea},
    layout_copied: @+value:Model.Style -> @+layout:C.ContentLayout -> @+geometry:C.Geometry -> @content_height:Nat -> {area(A.action_content_style(value, layout, geometry, content_height)) == C.layout_content_area(layout) : E.ContentArea},
    action_copied: @+value:Model.Style -> @+face:C.Face -> @+geometry:C.Geometry -> {area(A.action_style(value, face, geometry)) == C.layout_content_area(C.content_layout(face)) : E.ContentArea},
    minimum_extent: @+typography:T.Presentation -> @+value:Model.Style -> @+geometry:C.Geometry -> @+space:E.ContentArea -> @+gap:Nat -> @+content_height:Nat -> {Model.style_minimum_height(A.action_style_insets(value, geometry, space, gap, content_height)) == Nat.max(C.geometry_minimum_height(geometry), E.extent_height(E.required_extent(0n, content_height, A.chrome_border_width(chrome(value)), space))) : Nat},
    choice_area: @+typography:T.Presentation -> {area(A.choice_button(True{}, typography)) == area(A.choice_button(False{}, typography)) : E.ContentArea},
    choice_text: @+typography:T.Presentation -> {Model.style_text(A.choice_button(True{}, typography)) == Model.style_text(A.choice_button(False{}, typography)) : T.Presentation},
    role_navigation: @+typography:T.Presentation -> @+meaning:SurfaceTypes.Meaning -> {area(A.style(SurfaceTypes.Navigation{}, meaning, typography)) == E.area(E.Navigation{}) : E.ContentArea},
    role_composer: @+typography:T.Presentation -> @+meaning:SurfaceTypes.Meaning -> {area(A.style(SurfaceTypes.Composer{}, meaning, typography)) == E.area(E.Composer{}) : E.ContentArea},
    role_approval: @+typography:T.Presentation -> @+meaning:SurfaceTypes.Meaning -> {area(A.style(SurfaceTypes.Approval{}, meaning, typography)) == E.area(E.Approval{}) : E.ContentArea},
    role_codeblock: @+typography:T.Presentation -> @+meaning:SurfaceTypes.Meaning -> {area(A.style(SurfaceTypes.CodeBlock{}, meaning, typography)) == E.area(E.CodeBlock{}) : E.ContentArea},
    role_menu: @+typography:T.Presentation -> @+meaning:SurfaceTypes.Meaning -> {area(A.style(SurfaceTypes.Menu{}, meaning, typography)) == E.area(E.Menu{}) : E.ContentArea},
    role_details: @+typography:T.Presentation -> @+meaning:SurfaceTypes.Meaning -> {area(A.style(SurfaceTypes.Details{}, meaning, typography)) == E.area(E.Details{}) : E.ContentArea},
    role_card: @+typography:T.Presentation -> @+meaning:SurfaceTypes.Meaning -> {area(A.style(SurfaceTypes.Card{}, meaning, typography)) == E.area(E.Card{}) : E.ContentArea},
    role_dialog: @+typography:T.Presentation -> @+meaning:SurfaceTypes.Meaning -> {area(A.style(SurfaceTypes.Dialog{}, meaning, typography)) == E.DialogPartitions{} : E.ContentArea},
    canvas: @+typography:T.Presentation -> @+meaning:SurfaceTypes.Meaning -> {area(A.style(SurfaceTypes.Main{}, meaning, typography)) == E.ambient(0n, 0n) : E.ContentArea},
    field: @+typography:T.Presentation -> {area(A.editable_field(typography)) == E.area(E.Field{}) : E.ContentArea},
    part_header: {E.partition(E.Header{}) == E.ambient(E.partition_inline(), 14n) : E.ContentArea},
    part_body: {E.partition(E.Body{}) == E.ambient(E.partition_inline(), 20n) : E.ContentArea},
    part_footer: {E.partition(E.Footer{}) == E.ambient(E.partition_inline(), 12n) : E.ContentArea},
    state_allocation: @+value:Model.Style -> @+space:E.ContentArea -> {interaction(A.with_content_area(value, space)) == interaction(value) : Model.ControlStates},
    text_layout: @+text:String -> {C.layout_content_area(C.content_layout(C.TextFace{text})) == E.area(E.TextControl{}) : E.ContentArea},
    option_layout: @+text:String -> @+selected:Bool -> {C.layout_content_area(C.content_layout(C.ChoiceFace{text, None{}, None{}, selected})) == E.area(E.OptionControl{}) : E.ContentArea},
    embedded_input: @+typography:T.Presentation -> {area(A.widget_field_style(C.MessageInput{}, Forms.Multiline{}, typography)) == E.area(E.Field{}) : E.ContentArea}}

law enclosure_evidence:
  EnclosureRequirements

law forward_clip:
  for +distance: Nat
  for extent: Nat
  for +limit: Nat
  {SpatialModel.clip_axis(SpatialModel.Forward{distance}, extent, limit) ==
    SpatialModel.Axis{Nat.min(distance, limit), Nat.min(extent, Nat.sub(limit, Nat.min(distance, limit)))} : SpatialModel.Axis}

law backward_clip:
  for distance: Nat
  for extent: Nat
  for limit: Nat
  {SpatialModel.clip_axis(SpatialModel.Backward{distance}, extent, limit) ==
    SpatialModel.Axis{0n, Nat.min(Nat.sub(extent, distance), limit)} : SpatialModel.Axis}

law forward_forward:
  for +left: Nat
  for +top: Nat
  for width: Nat
  for height: Nat
  for +viewport_width: Nat
  for +viewport_height: Nat
  {SpatialModel.visible(SpatialModel.Forward{left}, SpatialModel.Forward{top}, width, height, viewport_width, viewport_height) ==
    SpatialModel.Box{Nat.min(left, viewport_width), Nat.min(top, viewport_height), Nat.min(width, Nat.sub(viewport_width, Nat.min(left, viewport_width))), Nat.min(height, Nat.sub(viewport_height, Nat.min(top, viewport_height)))} : SpatialModel.Box}

law forward_backward:
  for +left: Nat
  for +top: Nat
  for width: Nat
  for height: Nat
  for +viewport_width: Nat
  for +viewport_height: Nat
  {SpatialModel.visible(SpatialModel.Forward{left}, SpatialModel.Backward{top}, width, height, viewport_width, viewport_height) ==
    SpatialModel.Box{Nat.min(left, viewport_width), 0n, Nat.min(width, Nat.sub(viewport_width, Nat.min(left, viewport_width))), Nat.min(Nat.sub(height, top), viewport_height)} : SpatialModel.Box}

law backward_forward:
  for +left: Nat
  for +top: Nat
  for width: Nat
  for height: Nat
  for +viewport_width: Nat
  for +viewport_height: Nat
  {SpatialModel.visible(SpatialModel.Backward{left}, SpatialModel.Forward{top}, width, height, viewport_width, viewport_height) ==
    SpatialModel.Box{0n, Nat.min(top, viewport_height), Nat.min(Nat.sub(width, left), viewport_width), Nat.min(height, Nat.sub(viewport_height, Nat.min(top, viewport_height)))} : SpatialModel.Box}

law backward_backward:
  for +left: Nat
  for +top: Nat
  for width: Nat
  for height: Nat
  for +viewport_width: Nat
  for +viewport_height: Nat
  {SpatialModel.visible(SpatialModel.Backward{left}, SpatialModel.Backward{top}, width, height, viewport_width, viewport_height) ==
    SpatialModel.Box{0n, 0n, Nat.min(Nat.sub(width, left), viewport_width), Nat.min(Nat.sub(height, top), viewport_height)} : SpatialModel.Box}

law negative_top_regression:
  {SpatialModel.visible(SpatialModel.Forward{100n}, SpatialModel.Backward{8n}, 40n, 40n, 1000n, 800n) ==
    SpatialModel.Box{100n, 0n, 40n, 32n} : SpatialModel.Box}
