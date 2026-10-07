import Base
import ./space.bend as Space
import ./space-laws.bend as Allocation

def inner_budget(+leading: Nat, trailing: Nat, available: Nat) -> Nat:
  Nat.sub(Nat.sub(available, leading), trailing)
def ContainerClaim(~A: Data, +container: Space.Container<A>, +available: Nat, result: Space.Packing<A>) -> Type:
  Space.Container{leading, trailing, gap, slots} = container
  match result:
    case Space.Packed{placements, unused}:
      Allocation.AllocationEvidence<A, slots, gap, leading, inner_budget(leading, trailing, available), Space.Allocation{placements, unused}> &
      {Nat.add(leading, Nat.add(Nat.add(Allocation.used(~A, placements, gap), unused), trailing)) == available : Nat}
    case Space.Insufficient{required, received}:
      {required == Space.container_required(~A, container) : Nat} &
      ({received == available : Nat} &
      {Nat.is_le(Space.container_required(~A, container), available) == False{} : Bool})

type Requirement<-A: Data> is Type:
  Requirement{complete: @+container:Space.Container<A> -> @+available:Nat ->
    ContainerClaim(~A, container, available, Space.pack_container(~A, container, available))}

law evidence:
  for ~A: Data
  Requirement<A>
