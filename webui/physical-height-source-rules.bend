import Base
import ./physical-space.bend as Model
import ./physical-allocation.bend as Allocation
import ./spatial.bend as Spatial

def source_claim(~A: Data, ~E: Data, +source: Model.Tree<A, E>, result: Allocation.PositionedOutcome<A, E>) -> Type:
  match result:
    case Allocation.Positioned{tree}: {Allocation.source_of_allocated(~A, ~E, tree) == source : Model.Tree<A, E>}
    case _: {True{} == True{} : Bool}

type Requirements<-A: Data, -E: Data> is Type:
  Requirements{preserved: @+tree:Allocation.MeasuredTree<A, E> -> @+bounds:Spatial.Box ->
    source_claim(~A, ~E, Allocation.source_of_measured(~A, ~E, tree), Allocation.allocate_measured(~A, ~E, tree, bounds))}

law evidence:
  for ~A: Data
  for ~E: Data
  Requirements<A, E>
