import Base
import ./physical-space.bend as Model
import ./physical-allocation.bend as Allocation
import ./space.bend as Space
import ./space-laws.bend as SpaceLaws

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
