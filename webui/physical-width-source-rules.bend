import Base
import ./physical-space.bend as Model
import ./physical-allocation.bend as Allocation

def source_claim(~A: Data, ~E: Data, +source: Model.Tree<A, E>, result: Allocation.WidthOutcome<A, E>) -> Type:
  match result:
    case Allocation.WidthReady{tree}: {Allocation.source_of_measured(~A, ~E, tree) == source : Model.Tree<A, E>}
    case _: {True{} == True{} : Bool}

type Requirements<-A: Data, -E: Data> is Type:
  Requirements{preserved: @+tree:Model.Tree<A, E> -> @+width:Nat -> @+samples:+List<Model.HeightSample> ->
    source_claim(~A, ~E, tree, Allocation.fit_width(~A, ~E, tree, width, samples))}

law evidence:
  for ~A: Data
  for ~E: Data
  Requirements<A, E>
