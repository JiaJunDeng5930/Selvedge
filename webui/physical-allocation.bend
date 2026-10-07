import Base
import ../bendlib/stdlib.bend as Std
import ./spatial.bend as Spatial
import ./space.bend as Space
import ./enclosure.bend as Enclosure
import ./physical-space.bend as Model

type Axis is Data:
  InlineAxis{}
  BlockAxis{}

type ResolvedDirection is Data:
  Horizontal{}
  Vertical{}
  Layered{}

type FailureReason is Data:
  AuthoredRangeConflict{}
  InsufficientSpace{}
  AllocationBoundExceeded{budget: Nat}

type Failure is Data:
  Failure{key: String, axis: Axis, required: Nat, available: Nat, reason: FailureReason}

type MeasuredTree<-A: Data, -E: Data> is Data:
  MeasuredLeaf{key: String, value: A, interaction: Model.Interaction<E>, rule: Model.Rule,
    demand: Space.Demand, height: Model.Height, outer_width: Nat, inline_offset: Nat, content_height: Nat}
  MeasuredContainer{key: String, value: A, interaction: Model.Interaction<E>, rule: Model.Rule,
    outer_width: Nat, inline_offset: Nat, resolved_direction: ResolvedDirection, children: +List<MeasuredTree<A, E>>}

type WidthOutcome<-A: Data, -E: Data> is Data:
  WidthReady{tree: MeasuredTree<A, E>}
  HeightPending{first: Model.HeightRequest<A>, remaining: +List<Model.HeightRequest<A>>}
  WidthFailure{failure: Failure}

type AllocatedTree<-A: Data, -E: Data> is Data:
  AllocatedLeaf{key: String, value: A, interaction: Model.Interaction<E>, rule: Model.Rule,
    demand: Space.Demand, height: Model.Height, bounds: Spatial.Box, canvas: Enclosure.Extent}
  AllocatedContainer{key: String, value: A, interaction: Model.Interaction<E>, rule: Model.Rule,
    bounds: Spatial.Box, canvas: Enclosure.Extent, resolved_direction: ResolvedDirection, children: +List<AllocatedTree<A, E>>}

type Outcome<-A: Data, -E: Data> is Data:
  Allocated{tree: AllocatedTree<A, E>}
  AwaitingHeights{first: Model.HeightRequest<A>, remaining: +List<Model.HeightRequest<A>>}
  Infeasible{failure: Failure}

type Tagged<-A: Data> is Data:
  Tagged{value: A, original: Space.Dimension}

type SlotsOutcome<-A: Data> is Data:
  SlotsReady{slots: +List<Space.Slot<A>>}
  SlotsFailure{failure: Failure}

type MeasuredChildren<-A: Data, -E: Data> is Data:
  ChildrenMeasured{children: +List<MeasuredTree<A, E>>}
  ChildrenPending{first: Model.HeightRequest<A>, remaining: +List<Model.HeightRequest<A>>}
  ChildrenFailed{failure: Failure}

type PositionedOutcome<-A: Data, -E: Data> is Data:
  Positioned{tree: AllocatedTree<A, E>}
  PositionFailure{failure: Failure}

type AllocatedChildren<-A: Data, -E: Data> is Data:
  ChildrenAllocated{children: +List<AllocatedTree<A, E>>}
  AllocationFailed{failure: Failure}

type ChildPlan<-T: Data> is Data:
  ChildrenPlanned{placements: +List<Space.Placement<T>>, canvas: Nat}
  PlanningFailure{failure: Failure}

type InlinePlan<-A: Data, -E: Data> is Data:
  InlinePlanned{placements: +List<Space.Placement<Model.Tree<A, E>>>, direction: ResolvedDirection, canvas: Nat}
  InlineFailure{failure: Failure}

def source_forest_measured(~A: Data, ~E: Data, trees: +List<MeasuredTree<A, E>>) -> +List<Model.Tree<A, E>>:
  match trees:
    case Nil{}: Nil{}
    case Con{MeasuredLeaf{key, value, interaction, rule, demand, height, outer_width, inline_offset, content_height}, rest}:
      Model.Leaf{key, value, interaction, rule, demand, height} <> source_forest_measured(~A, ~E, rest)
    case Con{MeasuredContainer{key, value, interaction, rule, outer_width, inline_offset, resolved_direction, children}, rest}:
      Model.Container{key, value, interaction, rule, source_forest_measured(~A, ~E, children)} <> source_forest_measured(~A, ~E, rest)

def source_of_measured(~A: Data, ~E: Data, tree: MeasuredTree<A, E>) -> Model.Tree<A, E>:
  match tree:
    case MeasuredLeaf{key, value, interaction, rule, demand, height, outer_width, inline_offset, content_height}:
      Model.Leaf{key, value, interaction, rule, demand, height}
    case MeasuredContainer{key, value, interaction, rule, outer_width, inline_offset, resolved_direction, children}:
      Model.Container{key, value, interaction, rule, source_forest_measured(~A, ~E, children)}

def source_forest_allocated(~A: Data, ~E: Data, trees: +List<AllocatedTree<A, E>>) -> +List<Model.Tree<A, E>>:
  match trees:
    case Nil{}: Nil{}
    case Con{AllocatedLeaf{key, value, interaction, rule, demand, height, bounds, canvas}, rest}:
      Model.Leaf{key, value, interaction, rule, demand, height} <> source_forest_allocated(~A, ~E, rest)
    case Con{AllocatedContainer{key, value, interaction, rule, bounds, canvas, resolved_direction, children}, rest}:
      Model.Container{key, value, interaction, rule, source_forest_allocated(~A, ~E, children)} <> source_forest_allocated(~A, ~E, rest)

def source_of_allocated(~A: Data, ~E: Data, tree: AllocatedTree<A, E>) -> Model.Tree<A, E>:
  match tree:
    case AllocatedLeaf{key, value, interaction, rule, demand, height, bounds, canvas}:
      Model.Leaf{key, value, interaction, rule, demand, height}
    case AllocatedContainer{key, value, interaction, rule, bounds, canvas, resolved_direction, children}:
      Model.Container{key, value, interaction, rule, source_forest_allocated(~A, ~E, children)}

def tree_rule(~A: Data, ~E: Data, tree: Model.Tree<A, E>) -> Model.Rule:
  match tree:
    case Model.Leaf{key, value, interaction, rule, demand, height}: rule
    case Model.Container{key, value, interaction, rule, children}: rule

def tree_key(~A: Data, ~E: Data, tree: Model.Tree<A, E>) -> String:
  match tree:
    case Model.Leaf{key, value, interaction, rule, demand, height}: key
    case Model.Container{key, value, interaction, rule, children}: key

def measured_rule(~A: Data, ~E: Data, tree: MeasuredTree<A, E>) -> Model.Rule:
  tree_rule(~A, ~E, source_of_measured(~A, ~E, tree))

def measured_key(~A: Data, ~E: Data, tree: MeasuredTree<A, E>) -> String:
  tree_key(~A, ~E, source_of_measured(~A, ~E, tree))

def measured_width(~A: Data, ~E: Data, tree: MeasuredTree<A, E>) -> Nat:
  match tree:
    case MeasuredLeaf{key, value, interaction, rule, demand, height, outer_width, inline_offset, content_height}: outer_width
    case MeasuredContainer{key, value, interaction, rule, outer_width, inline_offset, resolved_direction, children}: outer_width

def measured_offset(~A: Data, ~E: Data, tree: MeasuredTree<A, E>) -> Nat:
  match tree:
    case MeasuredLeaf{key, value, interaction, rule, demand, height, outer_width, inline_offset, content_height}: inline_offset
    case MeasuredContainer{key, value, interaction, rule, outer_width, inline_offset, resolved_direction, children}: inline_offset

def inline_size(rule: Model.Rule) -> Model.AxisSize:
  Model.Rule{direction, main_alignment, cross_alignment, frame, border, width, height, minimum, scroll, position} = rule
  width

def block_size(rule: Model.Rule) -> Model.AxisSize:
  Model.Rule{direction, main_alignment, cross_alignment, frame, border, width, height, minimum, scroll, position} = rule
  height

def axis_extent(+axis: Axis, extent: Enclosure.Extent) -> Nat:
  match axis:
    case InlineAxis{}: Enclosure.extent_width(extent)
    case BlockAxis{}: Enclosure.extent_height(extent)

def inline_inset(rule: Model.Rule) -> Nat:
  Model.Rule{direction, main_alignment, cross_alignment, frame, border, width, height, minimum, scroll, position} = rule
  Nat.add(border, Enclosure.inline(Enclosure.frame_content(frame)))

def block_inset(rule: Model.Rule) -> Nat:
  Model.Rule{direction, main_alignment, cross_alignment, frame, border, width, height, minimum, scroll, position} = rule
  Nat.add(border, Enclosure.block(Enclosure.frame_content(frame)))

def axis_inset(+axis: Axis, rule: Model.Rule) -> Nat:
  match axis:
    case InlineAxis{}: inline_inset(rule)
    case BlockAxis{}: block_inset(rule)

def scroll_inline(scroll: Model.Scroll) -> Bool:
  match scroll:
    case Model.ScrollHorizontally{}: True{}
    case Model.ScrollBoth{}: True{}
    case _: False{}

def scroll_block(scroll: Model.Scroll) -> Bool:
  match scroll:
    case Model.ScrollVertically{}: True{}
    case Model.ScrollBoth{}: True{}
    case _: False{}

def scrolls(axis: Axis, scroll: Model.Scroll) -> Bool:
  match axis:
    case InlineAxis{}: scroll_inline(scroll)
    case BlockAxis{}: scroll_block(scroll)

def rule_scroll(rule: Model.Rule) -> Model.Scroll:
  Model.Rule{direction, main_alignment, cross_alignment, frame, border, width, height, minimum, scroll, position} = rule
  scroll

def rule_gap(rule: Model.Rule) -> Nat:
  Model.Rule{direction, main_alignment, cross_alignment, frame, border, width, height, minimum, scroll, position} = rule
  Enclosure.frame_gap(frame)

def alignment_offset(alignment: Spatial.Alignment, +unused: Nat) -> Nat:
  match alignment:
    case Spatial.Stretch{}: 0n
    case Spatial.Leading{}: 0n
    case Spatial.Trailing{}: unused
    case Spatial.Centered{}: Nat.div(unused, 2n)

def main_alignment(rule: Model.Rule) -> Spatial.Alignment:
  Model.Rule{authored, main_alignment, cross_alignment, frame, border, width, height, minimum, scroll, position} = rule
  main_alignment

def cross_alignment(rule: Model.Rule) -> Spatial.Alignment:
  Model.Rule{authored, main_alignment, cross_alignment, frame, border, width, height, minimum, scroll, position} = rule
  cross_alignment

def axis_alignment_direction_2(+direction: ResolvedDirection, +rule: Model.Rule) -> Spatial.Alignment:
  match direction:
    case Layered{}: Spatial.Leading{}
    case Horizontal{}: cross_alignment(rule)
    case _: main_alignment(rule)

def axis_alignment_direction_1(+direction: ResolvedDirection, +rule: Model.Rule) -> Spatial.Alignment:
  match direction:
    case Layered{}: Spatial.Leading{}
    case Horizontal{}: main_alignment(rule)
    case _: cross_alignment(rule)

def axis_alignment(+axis: Axis, +direction: ResolvedDirection, rule: Model.Rule) -> Spatial.Alignment:
  match axis:
    case InlineAxis{}:
      axis_alignment_direction_1(direction, rule)
    case BlockAxis{}:
      axis_alignment_direction_2(direction, rule)

def sequential_direction_2(+direction: ResolvedDirection) -> Bool:
  match direction:
    case Layered{}: False{}
    case Horizontal{}: False{}
    case _: True{}

def sequential_direction_1(+direction: ResolvedDirection) -> Bool:
  match direction:
    case Horizontal{}: True{}
    case _: False{}

def sequential(+axis: Axis, direction: ResolvedDirection) -> Bool:
  match axis:
    case InlineAxis{}:
      sequential_direction_1(direction)
    case BlockAxis{}:
      sequential_direction_2(direction)

def direction_model(direction: ResolvedDirection) -> Model.Direction:
  match direction:
    case Horizontal{}: Model.Horizontal{}
    case Vertical{}: Model.Vertical{}
    case Layered{}: Model.Layered{}

def reduce_demands(demands: +List<Space.Demand>, +direction: ResolvedDirection, +gap: Nat) -> Space.Demand:
  match demands:
    case Nil{}: Space.fixed_demand(0n, 0n)
    case Con{head, Nil{}}: head
    case Con{head, Con{next, tail}}:
      Model.prepend_demand(direction_model(direction), gap, head, reduce_demands(next <> tail, direction, gap))

def resolved_child_demand(+demand: Space.Demand, +actual_width: Nat) -> Space.Demand:
  Space.Demand{Enclosure.Extent{min_width, min_height}, Enclosure.Extent{pref_width, pref_height}} = demand
  Space.Demand{Enclosure.Extent{actual_width, min_height}, Enclosure.Extent{Nat.max(actual_width, pref_width), pref_height}}

def measured_remaining_gap(~A: Data, ~E: Data, trees: +List<MeasuredTree<A, E>>, +gap: Nat) -> Nat:
  match trees:
    case Nil{}: 0n
    case Con{head, rest}: gap

def measured_content_demand(~A: Data, ~E: Data, +trees: +List<MeasuredTree<A, E>>, +direction: ResolvedDirection, +gap: Nat) -> Space.Demand:
  match trees:
    case Nil{}: Space.fixed_demand(0n, 0n)
    case Con{MeasuredLeaf{key, value, interaction, +rule, demand, height, +outer_width, inline_offset, content_height}, +rest}:
      Model.prepend_demand(direction_model(direction), measured_remaining_gap(~A, ~E, rest, gap),
        Model.clearance_demand(direction_model(direction), Model.rule_position(rule), resolved_child_demand(Model.outer_demand(~E, Model.fixed_leaf_content(demand, content_height), rule, interaction), outer_width)),
        measured_content_demand(~A, ~E, rest, direction, gap))
    case Con{MeasuredContainer{key, value, interaction, +rule, +outer_width, inline_offset, child_direction, children}, +rest}:
      Model.prepend_demand(direction_model(direction), measured_remaining_gap(~A, ~E, rest, gap),
        Model.clearance_demand(direction_model(direction), Model.rule_position(rule), resolved_child_demand(Model.outer_demand(~E, measured_content_demand(~A, ~E, children, child_direction, rule_gap(rule)), rule, interaction), outer_width)),
        measured_content_demand(~A, ~E, rest, direction, gap))

def measured_demand(~A: Data, ~E: Data, tree: MeasuredTree<A, E>) -> Space.Demand:
  match tree:
    case MeasuredLeaf{key, value, interaction, rule, demand, height, outer_width, inline_offset, content_height}:
      Model.outer_demand(~E, Model.fixed_leaf_content(demand, content_height), rule, interaction)
    case MeasuredContainer{key, value, interaction, +rule, outer_width, inline_offset, direction, children}:
      Model.outer_demand(~E, measured_content_demand(~A, ~E, children, direction, rule_gap(rule)), rule, interaction)

def measured_content(~A: Data, ~E: Data, trees: +List<MeasuredTree<A, E>>, +direction: ResolvedDirection, +gap: Nat) -> Space.Demand:
  measured_content_demand(~A, ~E, trees, direction, gap)

def count_fill_dimension(dimension: Space.Dimension, +rest: Nat) -> Nat:
  match dimension:
    case Space.Fill{minimum}: Nat.add(1n, rest)
    case _: rest

def fill_count(~A: Data, slots: +List<Space.Slot<A>>) -> Nat:
  match slots:
    case Nil{}: 0n
    case Con{Space.Slot{value, dimension}, rest}: count_fill_dimension(dimension, fill_count(~A, rest))

def frozen_dimension(+dimension: Space.Dimension) -> Space.Dimension:
  match dimension:
    case Space.Fill{minimum}: Space.Rigid{minimum}
    case _: dimension

def freeze_slots(~A: Data, slots: +List<Space.Slot<A>>) -> +List<Space.Slot<Tagged<A>>>:
  match slots:
    case Nil{}: Nil{}
    case Con{Space.Slot{value, +dimension}, rest}:
      Space.Slot{Tagged{value, dimension}, frozen_dimension(dimension)} <> freeze_slots(~A, rest)

def dispatch_surplus_extra_1(selector: Bool) -> Nat:
  match selector:
    case True{}: 0n
    case False{}: 1n

def surplus_extra(+remaining: Nat) -> Nat:
  dispatch_surplus_extra_1(Nat.is_eq(remaining, 0n))

def next_remainder(original: Space.Dimension, +remaining: Nat) -> Nat:
  match original:
    case Space.Fill{minimum}: Nat.sub(remaining, 1n)
    case _: remaining

def shared_extent(original: Space.Dimension, +extent: Nat, +share: Nat, +remaining: Nat) -> Nat:
  match original:
    case Space.Fill{minimum}: Nat.add(extent, Nat.add(share, surplus_extra(remaining)))
    case _: extent

def thaw_slots(~A: Data, placements: +List<Space.Placement<Tagged<A>>>, +share: Nat, +remaining: Nat) -> +List<Space.Slot<A>>:
  match placements:
    case Nil{}: Nil{}
    case Con{Space.Placement{Tagged{value, +original}, offset, extent}, rest}:
      Space.Slot{value, Space.Rigid{shared_extent(original, extent, share, remaining)}} <>
        thaw_slots(~A, rest, share, next_remainder(original, remaining))

def dispatch_redistribute_2(~A: Data, selector: Bool, +count: Nat, +placements: +List<Space.Placement<Tagged<A>>>, +unused: Nat, +gap: Nat, +available: Nat) -> Space.Packing<A>:
  match selector:
    case True{}: Space.pack(~A, thaw_slots(~A, placements, 0n, 0n), gap, available)
    case False{}: Space.pack(~A, thaw_slots(~A, placements, Nat.div(unused, count), Nat.sub(unused, Nat.mul(Nat.div(unused, count), count))), gap, available)

def redistribute_first_first(~A: Data, +first: Space.Packing<Tagged<A>>, +count: Nat, +gap: Nat, +available: Nat) -> Space.Packing<A>:
  match first:
    case Space.Insufficient{required, available}: Space.Insufficient{required, available}
    case Space.Packed{placements, +unused}:
      dispatch_redistribute_2(~A, Nat.is_eq(count, 0n), count, placements, unused, gap, available)

def redistribute(~A: Data, +count: Nat, first: Space.Packing<Tagged<A>>, +gap: Nat, +available: Nat) -> Space.Packing<A>:
  redistribute_first_first(~A, first, count, gap, available)

def shared_pack(~A: Data, +slots: +List<Space.Slot<A>>, +gap: Nat, +available: Nat) -> Space.Packing<A>:
  redistribute(~A, fill_count(~A, slots), Space.pack(~Tagged<A>, freeze_slots(~A, slots), gap, available), gap, available)

def prepend_slot_first_rest(~A: Data, +rest: SlotsOutcome<A>, +slot: Space.Slot<A>) -> SlotsOutcome<A>:
  match rest:
    case SlotsReady{slots}: SlotsReady{slot <> slots}
    case SlotsFailure{failure}: SlotsFailure{failure}

def prepend_slot(~A: Data, slot: Space.Slot<A>, rest: SlotsOutcome<A>) -> SlotsOutcome<A>:
  prepend_slot_first_rest(~A, rest, slot)

def materialized_slot(~T: Data, selector: Maybe<&2, Space.Dimension>, +head: T, +key: String, +axis: Axis, +lower: Nat, +offered: Nat, +rest: SlotsOutcome<T>) -> SlotsOutcome<T>:
  match selector:
    case None{}: SlotsFailure{Failure{key, axis, lower, offered, AuthoredRangeConflict{}}}
    case Some{dimension}: prepend_slot(~T, Space.Slot{head, dimension}, rest)

def outside_inline(outside: Enclosure.Insets) -> Nat:
  Enclosure.Insets{inline, block} = outside
  Nat.mul(2n, inline)

def outside_block(outside: Enclosure.Insets) -> Nat:
  Enclosure.Insets{inline, block} = outside
  Nat.mul(2n, block)

def outside_axis_insets(+axis: Axis, +outside: Enclosure.Insets) -> Nat:
  match axis:
    case InlineAxis{}: outside_inline(outside)
    case BlockAxis{}: outside_block(outside)

def outside_axis(+axis: Axis, rule: Model.Rule) -> Nat:
  outside_axis_insets(axis, Model.position_outside(Model.rule_position(rule)))

def width_slot_demand(~A: Data, ~E: Data, demand: Space.Demand, +head: Model.Tree<A, E>, +offered: Nat, rest: SlotsOutcome<Model.Tree<A, E>>) -> SlotsOutcome<Model.Tree<A, E>>:
  Space.Demand{minimum, preferred} = demand
  +lower = axis_extent(InlineAxis{}, minimum)
  materialized_slot(~Model.Tree<A, E>, Model.materialize(inline_size(tree_rule(~A, ~E, head)), lower, axis_extent(InlineAxis{}, preferred), offered), head, tree_key(~A, ~E, head), InlineAxis{}, lower, offered, rest)

def width_slots(~A: Data, ~E: Data, trees: +List<Model.Tree<A, E>>, +offered: Nat) -> SlotsOutcome<Model.Tree<A, E>>:
  match trees:
    case Nil{}: SlotsReady{Nil{}}
    case Con{+head, rest}: width_slot_demand(~A, ~E, Model.demand(~A, ~E, head), head, Nat.sub(offered, outside_axis(InlineAxis{}, tree_rule(~A, ~E, head))), width_slots(~A, ~E, rest, offered))

def height_slot_demand(~A: Data, ~E: Data, demand: Space.Demand, +head: MeasuredTree<A, E>, +offered: Nat, rest: SlotsOutcome<MeasuredTree<A, E>>) -> SlotsOutcome<MeasuredTree<A, E>>:
  Space.Demand{minimum, preferred} = demand
  +lower = axis_extent(BlockAxis{}, minimum)
  materialized_slot(~MeasuredTree<A, E>, Model.materialize(block_size(measured_rule(~A, ~E, head)), lower, axis_extent(BlockAxis{}, preferred), offered), head, measured_key(~A, ~E, head), BlockAxis{}, lower, offered, rest)

def height_slots(~A: Data, ~E: Data, trees: +List<MeasuredTree<A, E>>, +offered: Nat) -> SlotsOutcome<MeasuredTree<A, E>>:
  match trees:
    case Nil{}: SlotsReady{Nil{}}
    case Con{+head, rest}: height_slot_demand(~A, ~E, measured_demand(~A, ~E, head), head, Nat.sub(offered, outside_axis(BlockAxis{}, measured_rule(~A, ~E, head))), height_slots(~A, ~E, rest, offered))

def maximum_minimum(~A: Data, slots: +List<Space.Slot<A>>) -> Nat:
  match slots:
    case Nil{}: 0n
    case Con{Space.Slot{value, dimension}, rest}: Nat.max(Space.minimum(dimension), maximum_minimum(~A, rest))

def dispatch_prepare_slots_sequence(~A: Data, is_sequence: Bool, slots: +List<Space.Slot<A>>, gap: Nat) -> Nat:
  match is_sequence:
    case True{}: Space.minimum_sequence(~A, slots, gap)
    case False{}: maximum_minimum(~A, slots)

def required_canvas(~A: Data, +is_sequence: Bool, slots: +List<Space.Slot<A>>, gap: Nat) -> Nat:
  dispatch_prepare_slots_sequence(~A, is_sequence, slots, gap)

def canvas_size(+can_scroll: Bool, +available: Nat, required: Nat) -> Nat:
  match can_scroll:
    case True{}: Nat.max(available, required)
    case False{}: available

def dispatch_resolve_direction_5(selector: Bool) -> ResolvedDirection:
  match selector:
    case True{}: Horizontal{}
    case False{}: Vertical{}

def resolve_direction(direction: Model.Direction, +row_minimum: Nat, +inner_width: Nat) -> ResolvedDirection:
  match direction:
    case Model.Horizontal{}: Horizontal{}
    case Model.Vertical{}: Vertical{}
    case Model.Layered{}: Layered{}
    case Model.ResponsiveHorizontal{}:
      dispatch_resolve_direction_5(Nat.is_le(row_minimum, inner_width))

def request_append(~A: Data, requests: +List<Model.HeightRequest<A>>, rest: +List<Model.HeightRequest<A>>) -> +List<Model.HeightRequest<A>>:
  match requests:
    case Nil{}: rest
    case Con{head, tail}: head <> request_append(~A, tail, rest)

def merge_width_ready(~A: Data, ~E: Data, +rest: MeasuredChildren<A, E>, +tree: MeasuredTree<A, E>) -> MeasuredChildren<A, E>:
  match rest:
    case ChildrenFailed{failure}: ChildrenFailed{failure}
    case ChildrenPending{first, remaining}: ChildrenPending{first, remaining}
    case ChildrenMeasured{children}: ChildrenMeasured{tree <> children}

def merge_width_pending(~A: Data, ~E: Data, +rest: MeasuredChildren<A, E>, +first: Model.HeightRequest<A>, +remaining: +List<Model.HeightRequest<A>>) -> MeasuredChildren<A, E>:
  match rest:
    case ChildrenFailed{failure}: ChildrenFailed{failure}
    case ChildrenMeasured{children}: ChildrenPending{first, remaining}
    case ChildrenPending{next, tail}: ChildrenPending{first, request_append(~A, remaining, next <> tail)}

def merge_width(~A: Data, ~E: Data, first: WidthOutcome<A, E>, rest: MeasuredChildren<A, E>) -> MeasuredChildren<A, E>:
  match first:
    case WidthFailure{failure}: ChildrenFailed{failure}
    case HeightPending{+first, remaining}:
      merge_width_pending(~A, ~E, rest, first, remaining)
    case WidthReady{tree}:
      merge_width_ready(~A, ~E, rest, tree)

def select_height(matches: Bool, +height: Nat, +rest: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match matches:
    case True{}: Some{height}
    case False{}: rest

def find_height_samples(samples: +List<Model.HeightSample>, +key: String, +width: Nat) -> Maybe<&2, Nat>:
  match samples:
    case Nil{}: None{}
    case Con{Model.HeightSample{sample_key, sample_width, height}, rest}:
      select_height(String.eq(key, sample_key) && Nat.is_eq(width, sample_width), height, find_height_samples(rest, key, width))

def find_height(+key: String, +width: Nat, samples: +List<Model.HeightSample>) -> Maybe<&2, Nat>:
  find_height_samples(samples, key, width)

def leaf_height(height: Model.Height, width: Nat, samples: +List<Model.HeightSample>) -> Maybe<&2, Nat>:
  match height:
    case Model.FixedHeight{height}: Some{height}
    case Model.HeightAtWidth{key}: find_height(key, width, samples)

def height_key(height: Model.Height) -> String:
  match height:
    case Model.FixedHeight{height}: ""
    case Model.HeightAtWidth{key}: key

def finish_measurement_first_result(~A: Data, ~E: Data, +result: MeasuredChildren<A, E>, +key: String, +value: A, +interaction: Model.Interaction<E>, +rule: Model.Rule, +width: Nat, +offset: Nat, +direction: ResolvedDirection) -> WidthOutcome<A, E>:
  match result:
    case ChildrenFailed{failure}: WidthFailure{failure}
    case ChildrenPending{first, remaining}: HeightPending{first, remaining}
    case ChildrenMeasured{children}: WidthReady{MeasuredContainer{key, value, interaction, rule, width, offset, direction, children}}

def finish_measurement(~A: Data, ~E: Data, key: String, value: A, interaction: Model.Interaction<E>, rule: Model.Rule, width: Nat, offset: Nat, direction: ResolvedDirection, result: MeasuredChildren<A, E>) -> WidthOutcome<A, E>:
  finish_measurement_first_result(~A, ~E, result, key, value, interaction, rule, width, offset, direction)

def shift_placement(~T: Data, placement: Space.Placement<T>, shift: Nat) -> Space.Placement<T>:
  Space.Placement{value, offset, extent} = placement
  Space.Placement{value, Nat.add(shift, offset), extent}

def shift_placements(~T: Data, +placements: +List<Space.Placement<T>>, +shift: Nat) -> +List<Space.Placement<T>>:
  match placements:
    case Nil{}: Nil{}
    case Con{placement, rest}: shift_placement(~T, placement, shift) <> shift_placements(~T, rest, shift)

def dispatch_prepare_parallel_8(~T: Data, selector: ChildPlan<T>, +placements: +List<Space.Placement<T>>, +shift: Nat) -> ChildPlan<T>:
  match selector:
    case PlanningFailure{failure}: PlanningFailure{failure}
    case ChildrenPlanned{tail, canvas}: ChildrenPlanned{List.append(&2, Space.Placement<T>, shift_placements(~T, placements, shift), tail), canvas}

def packed_parallel(~T: Data, ~key_of: T -> String, selector: Space.Packing<T>, +tree: T, +axis: Axis, +alignment: Spatial.Alignment, +rest: ChildPlan<T>) -> ChildPlan<T>:
  match selector:
    case Space.Insufficient{required, available}: PlanningFailure{Failure{key_of(tree), axis, required, available, InsufficientSpace{}}}
    case Space.Packed{placements, unused}:
      dispatch_prepare_parallel_8(~T, rest, placements, alignment_offset(alignment, unused))

def clearance_pack_checked(~T: Data, +fits: Bool, +slots: +List<Space.Slot<T>>, +clearance: Nat, +available: Nat) -> Space.Packing<T>:
  match fits:
    case False{}: Space.Insufficient{clearance, available}
    case True{}: shared_pack(~T, slots, 0n, Nat.sub(available, clearance))

def clearance_pack(~T: Data, slots: +List<Space.Slot<T>>, +clearance: Nat, +available: Nat) -> Space.Packing<T>:
  clearance_pack_checked(~T, Nat.is_le(clearance, available), slots, clearance, available)

def prepare_parallel(~T: Data, ~key_of: T -> String, ~clearance_of: T -> Nat, slots: +List<Space.Slot<T>>, +axis: Axis, +canvas: Nat, +alignment: Spatial.Alignment) -> ChildPlan<T>:
  match slots:
    case Nil{}: ChildrenPlanned{Nil{}, canvas}
    case Con{Space.Slot{+tree, dimension}, rest}:
      packed_parallel(~T, ~key_of, clearance_pack(~T, Space.Slot{tree, dimension} <> Nil{}, clearance_of(tree), canvas), tree, axis, alignment, prepare_parallel(~T, ~key_of, ~clearance_of, rest, axis, canvas, alignment))

def dispatch_prepare_slots_9(~T: Data, selector: Space.Packing<T>, +key: String, +axis: Axis, +alignment: Spatial.Alignment, +canvas: Nat) -> ChildPlan<T>:
  match selector:
    case Space.Insufficient{required, available}: PlanningFailure{Failure{key, axis, required, available, InsufficientSpace{}}}
    case Space.Packed{placements, unused}:
      +shift = alignment_offset(alignment, unused)
      ChildrenPlanned{shift_placements(~T, placements, shift), canvas}

def destructure_prepare_slots_sequence(~T: Data, ~key_of: T -> String, ~clearance_of: T -> Nat, is_sequence: Bool, +key: String, +axis: Axis, +slots: +List<Space.Slot<T>>, +gap: Nat, +canvas: Nat, +alignment: Spatial.Alignment) -> ChildPlan<T>:
  match is_sequence:
    case False{}: prepare_parallel(~T, ~key_of, ~clearance_of, slots, axis, canvas, alignment)
    case True{}:
      dispatch_prepare_slots_9(~T, shared_pack(~T, slots, gap, canvas), key, axis, alignment, canvas)

def resolved_canvas(+direction: ResolvedDirection, +available: Nat, +scroll_canvas: Nat) -> Nat:
  match direction:
    case Layered{}: available
    case _: scroll_canvas

def prepare_slots(~T: Data, ~key_of: T -> String, ~clearance_of: T -> Nat, +key: String, +axis: Axis, +rule: Model.Rule, +direction: ResolvedDirection, +slots: +List<Space.Slot<T>>, +available: Nat) -> ChildPlan<T>:
  +is_sequence = sequential(axis, direction)
  +gap = rule_gap(rule)
  +canvas = resolved_canvas(direction, available, canvas_size(scrolls(axis, rule_scroll(rule)), available, required_canvas(~T, is_sequence, slots, gap)))
  +alignment = axis_alignment(axis, direction, rule)
  destructure_prepare_slots_sequence(~T, ~key_of, ~clearance_of, is_sequence, key, axis, slots, gap, canvas, alignment)

def dispatch_prepare_inline_children_11(~A: Data, ~E: Data, selector: ChildPlan<Model.Tree<A, E>>, +direction: ResolvedDirection) -> InlinePlan<A, E>:
  match selector:
    case PlanningFailure{failure}: InlineFailure{failure}
    case ChildrenPlanned{placements, canvas}: InlinePlanned{placements, direction, canvas}

def prepare_inline_rule_unchecked(~A: Data, ~E: Data, +rule: Model.Rule, +key: String, +available: Nat, +slots: +List<Space.Slot<Model.Tree<A, E>>>) -> InlinePlan<A, E>:
  Model.Rule{authored, main_alignment, cross_alignment, frame, border, width, height, minimum, scroll, position} = rule
  +direction = resolve_direction(authored, Space.minimum_sequence(~Model.Tree<A, E>, slots, rule_gap(rule)), available)
  dispatch_prepare_inline_children_11(~A, ~E, prepare_slots(~Model.Tree<A, E>, ~(tree => tree_key(~A, ~E, tree)), ~(tree => outside_axis(InlineAxis{}, tree_rule(~A, ~E, tree))), key, InlineAxis{}, rule, direction, slots, available), direction)

def layered_gap_valid(rule: Model.Rule) -> Bool:
  Model.Rule{direction, main, cross, frame, border, width, height, minimum, scroll, position} = rule
  match direction:
    case Model.Layered{}: Nat.is_eq(Enclosure.frame_gap(frame), 0n)
    case _: True{}

def prepare_inline_gap(~A: Data, ~E: Data, +valid: Bool, +rule: Model.Rule, +key: String, +available: Nat, +slots: +List<Space.Slot<Model.Tree<A, E>>>) -> InlinePlan<A, E>:
  match valid:
    case False{}: InlineFailure{Failure{key, InlineAxis{}, rule_gap(rule), 0n, AuthoredRangeConflict{}}}
    case True{}: prepare_inline_rule_unchecked(~A, ~E, rule, key, available, slots)

def prepare_inline_rule(~A: Data, ~E: Data, +rule: Model.Rule, key: String, available: Nat, slots: +List<Space.Slot<Model.Tree<A, E>>>) -> InlinePlan<A, E>:
  prepare_inline_gap(~A, ~E, layered_gap_valid(rule), rule, key, available, slots)

def dispatch_prepare_inline_children_10(~A: Data, ~E: Data, selector: SlotsOutcome<Model.Tree<A, E>>, +key: String, +rule: Model.Rule, +available: Nat) -> InlinePlan<A, E>:
  match selector:
    case SlotsFailure{failure}: InlineFailure{failure}
    case SlotsReady{+slots}:
      prepare_inline_rule(~A, ~E, rule, key, available, slots)

def prepare_inline_children(~A: Data, ~E: Data, +key: String, +rule: Model.Rule, children: +List<Model.Tree<A, E>>, +available: Nat) -> InlinePlan<A, E>:
  dispatch_prepare_inline_children_10(~A, ~E, width_slots(~A, ~E, children, available), key, rule, available)

def collect_width_outcomes(~A: Data, ~E: Data, outcomes: +List<WidthOutcome<A, E>>) -> MeasuredChildren<A, E>:
  List.foldr(~&2, ~WidthOutcome<A, E>, ~MeasuredChildren<A, E>, ~(first => rest => merge_width(~A, ~E, first, rest)), outcomes, ChildrenMeasured{Nil{}})

# Continuations retain parent work as data; the quoted iterator owns repetition.
type WidthReturn<-A: Data, -E: Data> is Data:
  WidthRootReturn{}
  WidthContainerReturn{key: String, value: A, interaction: Model.Interaction<E>, rule: Model.Rule,
    outer_width: Nat, offset: Nat, direction: ResolvedDirection,
    remaining: +List<Space.Placement<Model.Tree<A, E>>>, previous: +List<WidthOutcome<A, E>>, parent: WidthReturn<A, E>}

type WidthState<-A: Data, -E: Data> is Data:
  WidthVisit{tree: Model.Tree<A, E>, width: Nat, offset: Nat, return_to: WidthReturn<A, E>}
  WidthMinimumChecked{fits: Bool, tree: Model.Tree<A, E>, width: Nat, offset: Nat, rule: Model.Rule, lower: Nat, return_to: WidthReturn<A, E>}
  WidthLeafHeight{sample: Maybe<&2, Nat>, key: String, value: A, interaction: Model.Interaction<E>, rule: Model.Rule,
    demand: Space.Demand, height: Model.Height, inner_width: Nat, outer_width: Nat, offset: Nat, return_to: WidthReturn<A, E>}
  WidthContainerPlan{plan: InlinePlan<A, E>, key: String, value: A, interaction: Model.Interaction<E>, rule: Model.Rule,
    outer_width: Nat, offset: Nat, return_to: WidthReturn<A, E>}
  WidthChildren{remaining: +List<Space.Placement<Model.Tree<A, E>>>, key: String, value: A, interaction: Model.Interaction<E>, rule: Model.Rule,
    outer_width: Nat, offset: Nat, direction: ResolvedDirection, previous: +List<WidthOutcome<A, E>>, return_to: WidthReturn<A, E>}
  WidthComplete{result: WidthOutcome<A, E>, return_to: WidthReturn<A, E>}
  WidthDone{result: WidthOutcome<A, E>}

def in_flow(position: Spatial.Position) -> Bool:
  match position:
    case Spatial.InFlow{}: True{}
    case _: False{}

def width_position_valid(~A: Data, ~E: Data, position: Spatial.Position, parent: WidthReturn<A, E>) -> Bool:
  match parent:
    case WidthRootReturn{}: in_flow(position)
    case WidthContainerReturn{key, value, interaction, rule, width, offset, Layered{}, remaining, previous, parent}: True{}
    case _: in_flow(position)

def width_visit_valid(~A: Data, ~E: Data, +rule: Model.Rule, parent: WidthReturn<A, E>) -> Bool:
  width_position_valid(~A, ~E, Model.rule_position(rule), parent) && layered_gap_valid(rule)

def width_visit_checked(~A: Data, ~E: Data, +valid: Bool, +tree: Model.Tree<A, E>, +width: Nat, +offset: Nat, +rule: Model.Rule, +lower: Nat, +return_to: WidthReturn<A, E>) -> WidthState<A, E>:
  match valid:
    case False{}: WidthComplete{WidthFailure{Failure{tree_key(~A, ~E, tree), InlineAxis{}, 0n, width, AuthoredRangeConflict{}}}, return_to}
    case True{}: WidthMinimumChecked{Nat.is_le(lower, width), tree, width, offset, rule, lower, return_to}

def width_step(~A: Data, ~E: Data, state: WidthState<A, E>, +samples: +List<Model.HeightSample>) -> WidthState<A, E>:
  match state:
    case WidthVisit{+tree, +width, +offset, +return_to}:
      +rule = tree_rule(~A, ~E, tree)
      +lower = axis_extent(InlineAxis{}, Model.minimum_demand(Model.demand(~A, ~E, tree)))
      width_visit_checked(~A, ~E, width_visit_valid(~A, ~E, rule, return_to), tree, width, offset, rule, lower, return_to)
    case WidthMinimumChecked{False{}, tree, width, offset, rule, lower, return_to}:
      WidthComplete{WidthFailure{Failure{tree_key(~A, ~E, tree), InlineAxis{}, lower, width, InsufficientSpace{}}}, return_to}
    case WidthMinimumChecked{True{}, Model.Leaf{key, value, interaction, +rule, demand, +height}, +width, offset, checked_rule, lower, return_to}:
      +inner_width = Nat.sub(width, Nat.mul(2n, inline_inset(rule)))
      WidthLeafHeight{leaf_height(height, inner_width, samples), key, value, interaction, rule, demand, height, inner_width, width, offset, return_to}
    case WidthMinimumChecked{True{}, Model.Container{+key, value, interaction, +rule, children}, +width, offset, checked_rule, lower, return_to}:
      +inner_width = Nat.sub(width, Nat.mul(2n, inline_inset(rule)))
      WidthContainerPlan{prepare_inline_children(~A, ~E, key, rule, children, inner_width), key, value, interaction, rule, width, offset, return_to}
    case WidthLeafHeight{None{}, key, value, interaction, rule, demand, height, inner_width, outer_width, offset, return_to}:
      WidthComplete{HeightPending{Model.HeightRequest{height_key(height), value, inner_width}, Nil{}}, return_to}
    case WidthLeafHeight{Some{content_height}, key, value, interaction, rule, demand, height, inner_width, outer_width, offset, return_to}:
      WidthComplete{WidthReady{MeasuredLeaf{key, value, interaction, rule, demand, height, outer_width, offset, content_height}}, return_to}
    case WidthContainerPlan{InlineFailure{failure}, key, value, interaction, rule, outer_width, offset, return_to}:
      WidthComplete{WidthFailure{failure}, return_to}
    case WidthContainerPlan{InlinePlanned{placements, direction, canvas}, key, value, interaction, rule, outer_width, offset, return_to}:
      WidthChildren{placements, key, value, interaction, rule, outer_width, offset, direction, Nil{}, return_to}
    case WidthChildren{Nil{}, key, value, interaction, rule, outer_width, offset, direction, previous, return_to}:
      WidthComplete{finish_measurement(~A, ~E, key, value, interaction, rule, outer_width, offset, direction, collect_width_outcomes(~A, ~E, previous)), return_to}
    case WidthChildren{Con{Space.Placement{child, child_offset, extent}, rest}, key, value, interaction, rule, outer_width, offset, direction, previous, return_to}:
      WidthVisit{child, extent, child_offset, WidthContainerReturn{key, value, interaction, rule, outer_width, offset, direction, rest, previous, return_to}}
    case WidthComplete{result, WidthRootReturn{}}: WidthDone{result}
    case WidthComplete{result, WidthContainerReturn{key, value, interaction, rule, outer_width, offset, direction, remaining, previous, parent}}:
      WidthChildren{remaining, key, value, interaction, rule, outer_width, offset, direction,
        List.append(&2, WidthOutcome<A, E>, previous, result <> Nil{}), parent}
    case WidthDone{result}: WidthDone{result}

# Leaf work is four steps; each forest root also reserves its parent's visit edge.
def width_forest_work(~A: Data, ~E: Data, trees: +List<Model.Tree<A, E>>) -> Nat:
  match trees:
    case Nil{}: 0n
    case Con{Model.Leaf{key, value, interaction, rule, demand, height}, rest}:
      Nat.add(5n, width_forest_work(~A, ~E, rest))
    case Con{Model.Container{key, value, interaction, rule, children}, rest}:
      Nat.add(6n, Nat.add(width_forest_work(~A, ~E, children), width_forest_work(~A, ~E, rest)))

def finish_width_iteration(~A: Data, ~E: Data, state: WidthState<A, E>, +key: String, +width: Nat, +budget: Nat) -> WidthOutcome<A, E>:
  match state:
    case WidthDone{result}: result
    case _: WidthFailure{Failure{key, InlineAxis{}, budget, width, AllocationBoundExceeded{budget}}}

# Samples stay in the runtime seed; the quoted iterator callback is closed.
type WidthExecution<-A: Data, -E: Data> is Data:
  WidthExecution{state: WidthState<A, E>, samples: +List<Model.HeightSample>}

def width_execution_step(~A: Data, ~E: Data, execution: WidthExecution<A, E>) -> WidthExecution<A, E>:
  WidthExecution{state, +samples} = execution
  WidthExecution{width_step(~A, ~E, state, samples), samples}

def width_execution_state(~A: Data, ~E: Data, execution: WidthExecution<A, E>) -> WidthState<A, E>:
  WidthExecution{state, samples} = execution
  state

def iterate_width(~A: Data, ~E: Data, +tree: Model.Tree<A, E>, +outer_width: Nat, +offset: Nat, +samples: +List<Model.HeightSample>) -> WidthState<A, E>:
  +budget = width_forest_work(~A, ~E, tree <> Nil{})
  width_execution_state(~A, ~E, Std.iter(~WidthExecution<A, E>, ~(execution => width_execution_step(~A, ~E, execution)), budget, WidthExecution{WidthVisit{tree, outer_width, offset, WidthRootReturn{}}, samples}))

def measure_at(~A: Data, ~E: Data, +tree: Model.Tree<A, E>, +outer_width: Nat, +offset: Nat, +samples: +List<Model.HeightSample>) -> WidthOutcome<A, E>:
  +budget = width_forest_work(~A, ~E, tree <> Nil{})
  finish_width_iteration(~A, ~E,
    iterate_width(~A, ~E, tree, outer_width, offset, samples),
    tree_key(~A, ~E, tree), outer_width, budget)

def root_measurement_first_placements(~A: Data, ~E: Data, +placements: +List<Space.Placement<Model.Tree<A, E>>>, +tree: Model.Tree<A, E>, +samples: +List<Model.HeightSample>) -> WidthOutcome<A, E>:
  match placements:
    case Nil{}: WidthFailure{Failure{tree_key(~A, ~E, tree), InlineAxis{}, 1n, 0n, InsufficientSpace{}}}
    case Con{Space.Placement{value, offset, extent}, rest}: measure_at(~A, ~E, value, extent, offset, samples)

def root_measurement(~A: Data, ~E: Data, +tree: Model.Tree<A, E>, placements: +List<Space.Placement<Model.Tree<A, E>>>, samples: +List<Model.HeightSample>) -> WidthOutcome<A, E>:
  root_measurement_first_placements(~A, ~E, placements, tree, samples)

def dispatch_fit_width_16(~A: Data, ~E: Data, selector: Space.Packing<Model.Tree<A, E>>, +tree: Model.Tree<A, E>, +samples: +List<Model.HeightSample>) -> WidthOutcome<A, E>:
  match selector:
    case Space.Insufficient{required, available}: WidthFailure{Failure{tree_key(~A, ~E, tree), InlineAxis{}, required, available, InsufficientSpace{}}}
    case Space.Packed{placements, unused}: root_measurement(~A, ~E, tree, placements, samples)

def dispatch_fit_width_15(~A: Data, ~E: Data, selector: SlotsOutcome<Model.Tree<A, E>>, +tree: Model.Tree<A, E>, +offered_width: Nat, +samples: +List<Model.HeightSample>) -> WidthOutcome<A, E>:
  match selector:
    case SlotsFailure{failure}: WidthFailure{failure}
    case SlotsReady{slots}:
      dispatch_fit_width_16(~A, ~E, shared_pack(~Model.Tree<A, E>, slots, 0n, offered_width), tree, samples)

def fit_width(~A: Data, ~E: Data, +tree: Model.Tree<A, E>, +offered_width: Nat, samples: +List<Model.HeightSample>) -> WidthOutcome<A, E>:
  dispatch_fit_width_15(~A, ~E, width_slots(~A, ~E, tree <> Nil{}, offered_width), tree, offered_width, samples)

def merge_positioned_tree(~A: Data, ~E: Data, +rest: AllocatedChildren<A, E>, +tree: AllocatedTree<A, E>) -> AllocatedChildren<A, E>:
  match rest:
    case AllocationFailed{failure}: AllocationFailed{failure}
    case ChildrenAllocated{children}: ChildrenAllocated{tree <> children}

def merge_allocation(~A: Data, ~E: Data, first: PositionedOutcome<A, E>, rest: AllocatedChildren<A, E>) -> AllocatedChildren<A, E>:
  match first:
    case PositionFailure{failure}: AllocationFailed{failure}
    case Positioned{tree}:
      merge_positioned_tree(~A, ~E, rest, tree)

def allocated_container_first_result(~A: Data, ~E: Data, +result: AllocatedChildren<A, E>, +key: String, +value: A, +interaction: Model.Interaction<E>, +rule: Model.Rule, +bounds: Spatial.Box, +canvas: Enclosure.Extent, +direction: ResolvedDirection) -> PositionedOutcome<A, E>:
  match result:
    case AllocationFailed{failure}: PositionFailure{failure}
    case ChildrenAllocated{children}: Positioned{AllocatedContainer{key, value, interaction, rule, bounds, canvas, direction, children}}

def allocated_container(~A: Data, ~E: Data, key: String, value: A, interaction: Model.Interaction<E>, rule: Model.Rule, bounds: Spatial.Box, canvas: Enclosure.Extent, direction: ResolvedDirection, result: AllocatedChildren<A, E>) -> PositionedOutcome<A, E>:
  allocated_container_first_result(~A, ~E, result, key, value, interaction, rule, bounds, canvas, direction)

def allocate_leaf_demand(~A: Data, ~E: Data, +demand: Space.Demand, +key: String, +value: A, +interaction: Model.Interaction<E>, +rule: Model.Rule, +height: Model.Height, +bounds: Spatial.Box, +content_height: Nat, +inner_width: Nat, +inner_height: Nat) -> PositionedOutcome<A, E>:
  Space.Demand{Enclosure.Extent{min_width, min_height}, preferred} = demand
  +canvas_width = canvas_size(scrolls(InlineAxis{}, rule_scroll(rule)), inner_width, min_width)
  +canvas_height = canvas_size(scrolls(BlockAxis{}, rule_scroll(rule)), inner_height, Nat.max(min_height, content_height))
  Positioned{AllocatedLeaf{key, value, interaction, rule, demand, height, bounds, Enclosure.Extent{canvas_width, canvas_height}}}

def allocated_leaf_first_bounds(~A: Data, ~E: Data, +bounds: Spatial.Box, +key: String, +value: A, +interaction: Model.Interaction<E>, +rule: Model.Rule, +demand: Space.Demand, +height: Model.Height, +content_height: Nat) -> PositionedOutcome<A, E>:
  Spatial.Box{left, top, width, block_height} = bounds
  +inner_width = Nat.sub(width, Nat.mul(2n, axis_inset(InlineAxis{}, rule)))
  +inner_height = Nat.sub(block_height, Nat.mul(2n, axis_inset(BlockAxis{}, rule)))
  allocate_leaf_demand(~A, ~E, demand, key, value, interaction, rule, height, bounds, content_height, inner_width, inner_height)

def allocated_leaf(~A: Data, ~E: Data, key: String, value: A, interaction: Model.Interaction<E>, +rule: Model.Rule, +demand: Space.Demand, height: Model.Height, +bounds: Spatial.Box, +content_height: Nat) -> PositionedOutcome<A, E>:
  allocated_leaf_first_bounds(~A, ~E, bounds, key, value, interaction, rule, demand, height, content_height)

def box_height(bounds: Spatial.Box) -> Nat:
  Spatial.Box{left, top, width, height} = bounds
  height

def dispatch_prepare_block_children_17(~A: Data, ~E: Data, selector: SlotsOutcome<MeasuredTree<A, E>>, +key: String, +rule: Model.Rule, +direction: ResolvedDirection, +available: Nat) -> ChildPlan<MeasuredTree<A, E>>:
  match selector:
    case SlotsFailure{failure}: PlanningFailure{failure}
    case SlotsReady{slots}: prepare_slots(~MeasuredTree<A, E>, ~(tree => measured_key(~A, ~E, tree)), ~(tree => outside_axis(BlockAxis{}, measured_rule(~A, ~E, tree))), key, BlockAxis{}, rule, direction, slots, available)

def prepare_block_children(~A: Data, ~E: Data, key: String, rule: Model.Rule, direction: ResolvedDirection, children: +List<MeasuredTree<A, E>>, +available: Nat) -> ChildPlan<MeasuredTree<A, E>>:
  dispatch_prepare_block_children_17(~A, ~E, height_slots(~A, ~E, children, available), key, rule, direction, available)

def measured_canvas_width(~A: Data, ~E: Data, trees: +List<MeasuredTree<A, E>>, direction: ResolvedDirection, gap: Nat, +viewport: Nat) -> Nat:
  Nat.max(viewport, axis_extent(InlineAxis{}, Model.minimum_demand(measured_content(~A, ~E, trees, direction, gap))))

def collect_positioned_outcomes(~A: Data, ~E: Data, outcomes: +List<PositionedOutcome<A, E>>) -> AllocatedChildren<A, E>:
  List.foldr(~&2, ~PositionedOutcome<A, E>, ~AllocatedChildren<A, E>, ~(first => rest => merge_allocation(~A, ~E, first, rest)), outcomes, ChildrenAllocated{Nil{}})

type HeightReturn<-A: Data, -E: Data> is Data:
  HeightRootReturn{}
  HeightContainerReturn{key: String, value: A, interaction: Model.Interaction<E>, rule: Model.Rule,
    bounds: Spatial.Box, canvas: Enclosure.Extent, direction: ResolvedDirection, content_left: Nat, content_top: Nat,
    remaining: +List<Space.Placement<MeasuredTree<A, E>>>, previous: +List<PositionedOutcome<A, E>>, parent: HeightReturn<A, E>}

type HeightState<-A: Data, -E: Data> is Data:
  HeightVisit{tree: MeasuredTree<A, E>, bounds: Spatial.Box, return_to: HeightReturn<A, E>}
  HeightMinimumChecked{fits: Bool, tree: MeasuredTree<A, E>, bounds: Spatial.Box, lower: Nat, return_to: HeightReturn<A, E>}
  HeightContainerPlan{plan: ChildPlan<MeasuredTree<A, E>>, key: String, value: A, interaction: Model.Interaction<E>, rule: Model.Rule,
    bounds: Spatial.Box, children: +List<MeasuredTree<A, E>>, direction: ResolvedDirection, inner_width: Nat, left: Nat, top: Nat, return_to: HeightReturn<A, E>}
  HeightChildren{remaining: +List<Space.Placement<MeasuredTree<A, E>>>, key: String, value: A, interaction: Model.Interaction<E>, rule: Model.Rule,
    bounds: Spatial.Box, canvas: Enclosure.Extent, direction: ResolvedDirection, content_left: Nat, content_top: Nat,
    previous: +List<PositionedOutcome<A, E>>, return_to: HeightReturn<A, E>}
  HeightComplete{result: PositionedOutcome<A, E>, return_to: HeightReturn<A, E>}
  HeightDone{result: PositionedOutcome<A, E>}

def clamp_coordinate(+candidate: Nat, +start: Nat, +available: Nat, extent: Nat) -> Nat:
  Nat.max(start, Nat.min(candidate, Nat.add(start, Nat.sub(available, extent))))

def anchor_inline_offset(alignment: Spatial.Alignment, +left: Nat, +anchor_width: Nat, +width: Nat) -> Nat:
  match alignment:
    case Spatial.Centered{}: Nat.add(left, Nat.div(Nat.sub(anchor_width, width), 2n))
    case Spatial.Trailing{}: Nat.sub(Nat.add(left, anchor_width), width)
    case _: left

def anchor_inline(alignment: Spatial.Alignment, anchor: Spatial.Box, width: Nat) -> Nat:
  Spatial.Box{left, top, anchor_width, height} = anchor
  anchor_inline_offset(alignment, left, anchor_width, width)

def anchor_block_choose(+below_fits: Bool, +above_fits: Bool, +below: Nat, +above: Nat, +top: Nat, +height: Nat, +extent: Nat) -> Nat:
  match below_fits above_fits:
    case True{} _: below
    case False{} True{}: above
    case False{} False{}: clamp_coordinate(below, top, height, extent)

def anchor_block(anchor: Spatial.Box, +gap: Nat, +top: Nat, +height: Nat, +extent: Nat) -> Nat:
  Spatial.Box{left, +anchor_top, width, anchor_height} = anchor
  +below = Nat.add(Nat.add(anchor_top, anchor_height), gap)
  +above = Nat.sub(Nat.sub(anchor_top, gap), extent)
  anchor_block_choose(Nat.is_le(top, below) && Nat.is_le(Nat.add(below, extent), Nat.add(top, height)),
    Nat.is_le(Nat.add(gap, extent), anchor_top) && Nat.is_le(top, above) && Nat.is_le(Nat.add(above, extent), Nat.add(top, height)),
    below, above, top, height, extent)

def centered_bounds(+left: Nat, +top: Nat, +available_width: Nat, +available_height: Nat, +width: Nat, +height: Nat) -> Spatial.Box:
  Spatial.Box{Nat.add(left, Nat.div(Nat.sub(available_width, width), 2n)), Nat.add(top, Nat.div(Nat.sub(available_height, height), 2n)), width, height}

def anchored_bounds(+anchor: Maybe<&2, Spatial.Box>, +gap: Nat, +alignment: Spatial.Alignment,
  +left: Nat, +top: Nat, +available_width: Nat, +available_height: Nat, +width: Nat, +height: Nat) -> Spatial.Box:
  match anchor:
    case None{}: centered_bounds(left, top, available_width, available_height, width, height)
    case Some{+bounds}:
      Spatial.Box{clamp_coordinate(anchor_inline(alignment, bounds, width), left, available_width, width),
        clamp_coordinate(anchor_block(bounds, gap, top, available_height, height), top, available_height, height), width, height}

def layered_bounds_position(+position: Spatial.Position, +rule: Model.Rule, +left: Nat, +top: Nat,
  +available_width: Nat, +available_height: Nat, +width: Nat, +height: Nat, +clear_left: Nat, +clear_top: Nat, +clear_width: Nat, +clear_height: Nat) -> Spatial.Box:
  match position:
    case Spatial.InFlow{}:
      Spatial.Box{Nat.add(left, alignment_offset(cross_alignment(rule), Nat.sub(available_width, width))),
        Nat.add(top, alignment_offset(main_alignment(rule), Nat.sub(available_height, height))), width, height}
    case Spatial.CenteredLayer{outside}: centered_bounds(clear_left, clear_top, clear_width, clear_height, width, height)
    case Spatial.AlignedLayer{outside, horizontal, vertical}:
      Spatial.Box{Nat.add(clear_left, alignment_offset(horizontal, Nat.sub(clear_width, width))),
        Nat.add(clear_top, alignment_offset(vertical, Nat.sub(clear_height, height))), width, height}
    case Spatial.AnchoredLayer{anchor_key, anchor, outside, gap, alignment}:
      anchored_bounds(anchor, gap, alignment, clear_left, clear_top, clear_width, clear_height, width, height)

def layered_bounds_insets(outside: Enclosure.Insets, +position: Spatial.Position, +rule: Model.Rule, +left: Nat, +top: Nat,
  +available_width: Nat, +available_height: Nat, +width: Nat, +height: Nat) -> Spatial.Box:
  Enclosure.Insets{+inline, +block} = outside
  +clear_left = Nat.add(left, inline)
  +clear_top = Nat.add(top, block)
  +clear_width = Nat.sub(available_width, Nat.mul(2n, inline))
  +clear_height = Nat.sub(available_height, Nat.mul(2n, block))
  layered_bounds_position(position, rule, left, top, available_width, available_height, width, height, clear_left, clear_top, clear_width, clear_height)

def layered_bounds(+position: Spatial.Position, rule: Model.Rule, left: Nat, top: Nat, available_width: Nat, available_height: Nat, width: Nat, height: Nat) -> Spatial.Box:
  layered_bounds_insets(Model.position_outside(position), position, rule, left, top, available_width, available_height, width, height)

def height_child_bounds(~A: Data, ~E: Data, +direction: ResolvedDirection, +rule: Model.Rule, +canvas: Enclosure.Extent,
  +child: MeasuredTree<A, E>, +offset: Nat, +extent: Nat, +left: Nat, +top: Nat) -> Spatial.Box:
  match direction:
    case Layered{}:
      Enclosure.Extent{width, height} = canvas
      layered_bounds(Model.rule_position(measured_rule(~A, ~E, child)), rule, left, top, width, height, measured_width(~A, ~E, child), extent)
    case _: Spatial.Box{Nat.add(left, measured_offset(~A, ~E, child)), Nat.add(top, offset), measured_width(~A, ~E, child), extent}

def height_step(~A: Data, ~E: Data, state: HeightState<A, E>) -> HeightState<A, E>:
  match state:
    case HeightVisit{+tree, +bounds, return_to}:
      +lower = axis_extent(BlockAxis{}, Model.minimum_demand(measured_demand(~A, ~E, tree)))
      HeightMinimumChecked{Nat.is_le(lower, box_height(bounds)), tree, bounds, lower, return_to}
    case HeightMinimumChecked{False{}, tree, bounds, lower, return_to}:
      HeightComplete{PositionFailure{Failure{measured_key(~A, ~E, tree), BlockAxis{}, lower, box_height(bounds), InsufficientSpace{}}}, return_to}
    case HeightMinimumChecked{True{}, MeasuredLeaf{key, value, interaction, rule, demand, height, outer_width, inline_offset, content_height}, bounds, lower, return_to}:
      HeightComplete{allocated_leaf(~A, ~E, key, value, interaction, rule, demand, height, bounds, content_height), return_to}
    case HeightMinimumChecked{True{}, MeasuredContainer{+key, value, interaction, +rule, outer_width, inline_offset, +direction, +children}, +bounds, lower, return_to}:
      Spatial.Box{left, top, width, height} = bounds
      +inner_width = Nat.sub(width, Nat.mul(2n, inline_inset(rule)))
      +inner_height = Nat.sub(height, Nat.mul(2n, block_inset(rule)))
      HeightContainerPlan{prepare_block_children(~A, ~E, key, rule, direction, children, inner_height), key, value, interaction, rule,
        bounds, children, direction, inner_width, left, top, return_to}
    case HeightContainerPlan{PlanningFailure{failure}, key, value, interaction, rule, bounds, children, direction, inner_width, left, top, return_to}:
      HeightComplete{PositionFailure{failure}, return_to}
    case HeightContainerPlan{ChildrenPlanned{placements, canvas_height}, key, value, interaction, +rule, bounds, children, +direction, inner_width, left, top, return_to}:
      +canvas_width = measured_canvas_width(~A, ~E, children, direction, rule_gap(rule), inner_width)
      HeightChildren{placements, key, value, interaction, rule, bounds, Enclosure.Extent{canvas_width, canvas_height}, direction,
        Nat.add(left, inline_inset(rule)), Nat.add(top, block_inset(rule)), Nil{}, return_to}
    case HeightChildren{Nil{}, key, value, interaction, rule, bounds, canvas, direction, content_left, content_top, previous, return_to}:
      HeightComplete{allocated_container(~A, ~E, key, value, interaction, rule, bounds, canvas, direction, collect_positioned_outcomes(~A, ~E, previous)), return_to}
    case HeightChildren{Con{Space.Placement{+child, child_offset, extent}, rest}, key, value, interaction, +rule, bounds, +canvas, +direction, +content_left, +content_top, previous, return_to}:
      HeightVisit{child, height_child_bounds(~A, ~E, direction, rule, canvas, child, child_offset, extent, content_left, content_top),
        HeightContainerReturn{key, value, interaction, rule, bounds, canvas, direction, content_left, content_top, rest, previous, return_to}}
    case HeightComplete{result, HeightRootReturn{}}: HeightDone{result}
    case HeightComplete{result, HeightContainerReturn{key, value, interaction, rule, bounds, canvas, direction, content_left, content_top, remaining, previous, parent}}:
      HeightChildren{remaining, key, value, interaction, rule, bounds, canvas, direction, content_left, content_top,
        List.append(&2, PositionedOutcome<A, E>, previous, result <> Nil{}), parent}
    case HeightDone{result}: HeightDone{result}

# Leaf work is three steps; the root's unused parent edge leaves one slack step.
def height_forest_work(~A: Data, ~E: Data, trees: +List<MeasuredTree<A, E>>) -> Nat:
  match trees:
    case Nil{}: 0n
    case Con{MeasuredLeaf{key, value, interaction, rule, demand, height, outer_width, inline_offset, content_height}, rest}:
      Nat.add(4n, height_forest_work(~A, ~E, rest))
    case Con{MeasuredContainer{key, value, interaction, rule, outer_width, inline_offset, direction, children}, rest}:
      Nat.add(6n, Nat.add(height_forest_work(~A, ~E, children), height_forest_work(~A, ~E, rest)))

def finish_height_iteration(~A: Data, ~E: Data, state: HeightState<A, E>, +key: String, +height: Nat, +budget: Nat) -> PositionedOutcome<A, E>:
  match state:
    case HeightDone{result}: result
    case _: PositionFailure{Failure{key, BlockAxis{}, budget, height, AllocationBoundExceeded{budget}}}

def iterate_height(~A: Data, ~E: Data, +tree: MeasuredTree<A, E>, +bounds: Spatial.Box) -> HeightState<A, E>:
  +budget = height_forest_work(~A, ~E, tree <> Nil{})
  Std.iter(~HeightState<A, E>, ~(state => height_step(~A, ~E, state)), budget, HeightVisit{tree, bounds, HeightRootReturn{}})

def allocate_measured(~A: Data, ~E: Data, +tree: MeasuredTree<A, E>, +bounds: Spatial.Box) -> PositionedOutcome<A, E>:
  +budget = height_forest_work(~A, ~E, tree <> Nil{})
  finish_height_iteration(~A, ~E,
    iterate_height(~A, ~E, tree, bounds),
    measured_key(~A, ~E, tree), box_height(bounds), budget)

def positioned_outcome(~A: Data, ~E: Data, result: PositionedOutcome<A, E>) -> Outcome<A, E>:
  match result:
    case Positioned{tree}: Allocated{tree}
    case PositionFailure{failure}: Infeasible{failure}

def positioned_root_first_placements(~A: Data, ~E: Data, +placements: +List<Space.Placement<MeasuredTree<A, E>>>, +tree: MeasuredTree<A, E>, +left: Nat, +top: Nat) -> Outcome<A, E>:
  match placements:
    case Nil{}: Infeasible{Failure{measured_key(~A, ~E, tree), BlockAxis{}, 1n, 0n, InsufficientSpace{}}}
    case Con{Space.Placement{+value, offset, extent}, rest}:
      positioned_outcome(~A, ~E, allocate_measured(~A, ~E, value, Spatial.Box{Nat.add(left, measured_offset(~A, ~E, value)), Nat.add(top, offset), measured_width(~A, ~E, value), extent}))

def positioned_root(~A: Data, ~E: Data, +tree: MeasuredTree<A, E>, placements: +List<Space.Placement<MeasuredTree<A, E>>>, left: Nat, top: Nat) -> Outcome<A, E>:
  positioned_root_first_placements(~A, ~E, placements, tree, left, top)

def dispatch_allocate_root_height_21(~A: Data, ~E: Data, selector: Space.Packing<MeasuredTree<A, E>>, +tree: MeasuredTree<A, E>, +left: Nat, +top: Nat) -> Outcome<A, E>:
  match selector:
    case Space.Insufficient{required, available}: Infeasible{Failure{measured_key(~A, ~E, tree), BlockAxis{}, required, available, InsufficientSpace{}}}
    case Space.Packed{placements, unused}: positioned_root(~A, ~E, tree, placements, left, top)

def dispatch_allocate_root_height_20(~A: Data, ~E: Data, selector: SlotsOutcome<MeasuredTree<A, E>>, +tree: MeasuredTree<A, E>, +height: Nat, +left: Nat, +top: Nat) -> Outcome<A, E>:
  match selector:
    case SlotsFailure{failure}: Infeasible{failure}
    case SlotsReady{slots}:
      dispatch_allocate_root_height_21(~A, ~E, shared_pack(~MeasuredTree<A, E>, slots, 0n, height), tree, left, top)

def allocate_root_height_first_offered(~A: Data, ~E: Data, +offered: Spatial.Box, +tree: MeasuredTree<A, E>) -> Outcome<A, E>:
  Spatial.Box{+left, +top, width, +height} = offered
  dispatch_allocate_root_height_20(~A, ~E, height_slots(~A, ~E, tree <> Nil{}, height), tree, height, left, top)

def allocate_root_height(~A: Data, ~E: Data, +tree: MeasuredTree<A, E>, offered: Spatial.Box) -> Outcome<A, E>:
  allocate_root_height_first_offered(~A, ~E, offered, tree)

def dispatch_allocate_22(~A: Data, ~E: Data, selector: WidthOutcome<A, E>, +offered_box: Spatial.Box) -> Outcome<A, E>:
  match selector:
    case WidthFailure{failure}: Infeasible{failure}
    case HeightPending{first, remaining}: AwaitingHeights{first, remaining}
    case WidthReady{tree}: allocate_root_height(~A, ~E, tree, offered_box)

def allocate_first_offered_box(~A: Data, ~E: Data, +offered_box: Spatial.Box, +tree: Model.Tree<A, E>, +samples: +List<Model.HeightSample>) -> Outcome<A, E>:
  Spatial.Box{left, top, width, height} = offered_box
  dispatch_allocate_22(~A, ~E, fit_width(~A, ~E, tree, width, samples), offered_box)

def allocate(~A: Data, ~E: Data, tree: Model.Tree<A, E>, +offered_box: Spatial.Box, samples: +List<Model.HeightSample>) -> Outcome<A, E>:
  allocate_first_offered_box(~A, ~E, offered_box, tree, samples)

