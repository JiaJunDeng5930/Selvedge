import Base
import ./PROGRAM.bend as Allocation
import ./GEOMETRY.bend as Spatial

def completed(~A: Data, ~E: Data, state: Allocation.HeightState<A, E>) -> Bool:
  match state:
    case Allocation.HeightDone{result}: True{}
    case _: False{}

def complete_claim(~A: Data, ~E: Data, tree: Allocation.MeasuredTree<A, E>, bounds: Spatial.Box) -> Type:
  {completed(~A, ~E, Allocation.iterate_height(~A, ~E, tree, bounds)) == True{} : Bool}

type Requirements<-A: Data, -E: Data> is Type:
  Requirements{
    completion: @+tree:Allocation.MeasuredTree<A, E> -> @+bounds:Spatial.Box -> complete_claim(~A, ~E, tree, bounds)}

law evidence:
  for ~A: Data
  for ~E: Data
  Requirements<A, E>
