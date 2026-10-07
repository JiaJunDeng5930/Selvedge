import Base
import ./physical-space.bend as Model
import ./physical-allocation.bend as Allocation
import ./space.bend as Space
import ./space-laws.bend as SpaceLaws
import ./spatial.bend as Spatial
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
