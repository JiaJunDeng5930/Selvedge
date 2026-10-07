import Base
import ./physical-space.bend as Model
import ./physical-space-rules.bend as ModelRules
import ./PROGRAM.bend as Allocation
import ./SPACE.bend as Space
import ./space-laws.bend as SpaceLaws
import ./GEOMETRY.bend as Spatial
import ./enclosure.bend as Enclosure

def InlinePopulation(~A: Data, ~E: Data, +children: +List<Model.Tree<A, E>>, result: Allocation.InlinePlan<A, E>) -> Type:
  match result:
    case Allocation.InlinePlanned{placements, direction, canvas}:
      {SpaceLaws.placement_values(~Model.Tree<A, E>, placements) == children : +List<Model.Tree<A, E>>}
    case Allocation.InlineFailure{failure}: {True{} == True{} : Bool}

def BlockPopulation(~A: Data, ~E: Data, +children: +List<Allocation.MeasuredTree<A, E>>, result: Allocation.ChildPlan<Allocation.MeasuredTree<A, E>>) -> Type:
  match result:
    case Allocation.ChildrenPlanned{placements, canvas}:
      {SpaceLaws.placement_values(~Allocation.MeasuredTree<A, E>, placements) == children : +List<Allocation.MeasuredTree<A, E>>}
    case Allocation.PlanningFailure{failure}: {True{} == True{} : Bool}

type Requirements<-A: Data, -E: Data> is Type:
  Requirements{
    inline_population: @+key:String -> @+rule:Model.Rule -> @+children:+List<Model.Tree<A, E>> -> @+available:Nat ->
      InlinePopulation(~A, ~E, children, Allocation.prepare_inline_children(~A, ~E, key, rule, children, available)),
    block_population: @+key:String -> @+rule:Model.Rule -> @+direction:Allocation.ResolvedDirection ->
      @+children:+List<Allocation.MeasuredTree<A, E>> -> @+available:Nat ->
      BlockPopulation(~A, ~E, children, Allocation.prepare_block_children(~A, ~E, key, rule, direction, children, available))}

law evidence:
  for ~A: Data
  for ~E: Data
  Requirements<A, E>


law aligned_layer_bounds:
  for +outside: Enclosure.Insets
  for +horizontal: Spatial.Alignment
  for +vertical: Spatial.Alignment
  for rule: Model.Rule
  for +left: Nat
  for +top: Nat
  for +available_width: Nat
  for +available_height: Nat
  for +width: Nat
  for +height: Nat
  {Allocation.layered_bounds(Spatial.AlignedLayer{outside, horizontal, vertical}, rule, left, top, available_width, available_height, width, height) ==
    aligned_bounds(outside, horizontal, vertical, left, top, available_width, available_height, width, height) : Spatial.Box}

def aligned_bounds(outside: Enclosure.Insets, horizontal: Spatial.Alignment, vertical: Spatial.Alignment, +left: Nat, +top: Nat, +available_width: Nat, +available_height: Nat, +width: Nat, +height: Nat) -> Spatial.Box:
  Enclosure.Insets{+inline, +block} = outside
  Spatial.Box{Nat.add(Nat.add(left, inline), Allocation.alignment_offset(horizontal, Nat.sub(Nat.sub(available_width, Nat.mul(2n, inline)), width))),
    Nat.add(Nat.add(top, block), Allocation.alignment_offset(vertical, Nat.sub(Nat.sub(available_height, Nat.mul(2n, block)), height))), width, height}

law aligned_layer_clearance:
  for +outside: Enclosure.Insets
  for horizontal: Spatial.Alignment
  for vertical: Spatial.Alignment
  {Model.position_outside(Spatial.AlignedLayer{outside, horizontal, vertical}) == outside : Enclosure.Insets}

def RootBoundsPolicy(~A: Data, ~E: Data, +position: Spatial.Position, +tree: Allocation.MeasuredTree<A, E>, +offered: Spatial.Box,
  +offset: Nat, +height: Nat, bounds: Spatial.Box) -> Type:
  match position:
    case Spatial.InFlow{}: {bounds == Allocation.inflow_root_bounds(~A, ~E, tree, offered, offset, height) : Spatial.Box}
    case Spatial.CenteredLayer{outside}: {bounds == Allocation.layered_root_bounds(~A, ~E, tree, Spatial.CenteredLayer{outside}, offered, height) : Spatial.Box}
    case Spatial.AlignedLayer{outside, horizontal, vertical}: {bounds == Allocation.layered_root_bounds(~A, ~E, tree, Spatial.AlignedLayer{outside, horizontal, vertical}, offered, height) : Spatial.Box}
    case Spatial.AnchoredLayer{key, anchor, outside, gap, alignment}: {bounds == Allocation.layered_root_bounds(~A, ~E, tree, Spatial.AnchoredLayer{key, anchor, outside, gap, alignment}, offered, height) : Spatial.Box}

law root_position:
  for ~A: Data
  for ~E: Data
  for +tree: Allocation.MeasuredTree<A, E>
  for +offered: Spatial.Box
  for +offset: Nat
  for +height: Nat
  RootBoundsPolicy(~A, ~E, Model.rule_position(Allocation.measured_rule(~A, ~E, tree)), tree, offered, offset, height, Allocation.root_bounds(~A, ~E, tree, offered, offset, height))

law root_width_clearance:
  for ~A: Data
  for ~E: Data
  for +slots: +List<Space.Slot<Model.Tree<A, E>>>
  for +tree: Model.Tree<A, E>
  for +width: Nat
  for +samples: +List<Model.HeightSample>
  {Allocation.dispatch_fit_width_15(~A, ~E, Allocation.SlotsReady{slots}, tree, width, samples) ==
    Allocation.dispatch_fit_width_16(~A, ~E, Allocation.shared_pack(~Model.Tree<A, E>, slots, 0n, Nat.sub(width, Allocation.outside_axis(Allocation.InlineAxis{}, Allocation.tree_rule(~A, ~E, tree)))), tree, samples) : Allocation.WidthOutcome<A, E>}

law root_height_clearance:
  for ~A: Data
  for ~E: Data
  for +slots: +List<Space.Slot<Allocation.MeasuredTree<A, E>>>
  for +tree: Allocation.MeasuredTree<A, E>
  for +offered: Spatial.Box
  {Allocation.dispatch_allocate_root_height_20(~A, ~E, Allocation.SlotsReady{slots}, tree, offered) ==
    Allocation.dispatch_allocate_root_height_21(~A, ~E, Allocation.shared_pack(~Allocation.MeasuredTree<A, E>, slots, 0n, Nat.sub(Allocation.box_height(offered), Allocation.outside_axis(Allocation.BlockAxis{}, Allocation.measured_rule(~A, ~E, tree)))), tree, offered) : Allocation.Outcome<A, E>}

law root_allocation_bounds:
  for ~A: Data
  for ~E: Data
  for +tree: Allocation.MeasuredTree<A, E>
  for +value: Allocation.MeasuredTree<A, E>
  for +rest: +List<Space.Placement<Allocation.MeasuredTree<A, E>>>
  for +offset: Nat
  for +height: Nat
  for +offered: Spatial.Box
  {Allocation.positioned_root_first_placements(~A, ~E, Space.Placement{value, offset, height} <> rest, tree, offered) ==
    Allocation.positioned_outcome(~A, ~E, Allocation.allocate_measured(~A, ~E, value, Allocation.root_bounds(~A, ~E, value, offered, offset, height))) : Allocation.Outcome<A, E>}

law measured_preferred:
  for ~A: Data
  for ~E: Data
  for +tree: Allocation.MeasuredTree<A, E>
  {ModelRules.preferred_covers_minimum(Allocation.measured_demand(~A, ~E, tree)) == True{} : Bool}

law measured_authored_floor:
  for ~A: Data
  for ~E: Data
  for +tree: Allocation.MeasuredTree<A, E>
  {ModelRules.extent_contains(Model.minimum_demand(Allocation.measured_demand(~A, ~E, tree)), ModelRules.rule_authored_minimum(Allocation.measured_rule(~A, ~E, tree))) == True{} : Bool}
