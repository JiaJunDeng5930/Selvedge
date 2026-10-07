import Base
import ./physical-space.bend as Model
import ./PROGRAM.bend as Allocation

def completed(~A: Data, ~E: Data, state: Allocation.WidthState<A, E>) -> Bool:
  match state:
    case Allocation.WidthDone{result}: True{}
    case _: False{}

def complete_claim(~A: Data, ~E: Data, +tree: Model.Tree<A, E>, +width: Nat, +offset: Nat, +samples: +List<Model.HeightSample>) -> Type:
  {completed(~A, ~E, Allocation.iterate_width(~A, ~E, tree, width, offset, samples)) == True{} : Bool}

type Requirements<-A: Data, -E: Data> is Type:
  Requirements{
    complete: @+tree:Model.Tree<A, E> -> @+width:Nat -> @+offset:Nat -> @+samples:+List<Model.HeightSample> ->
      complete_claim(~A, ~E, tree, width, offset, samples)}

law evidence:
  for ~A: Data
  for ~E: Data
  Requirements<A, E>
