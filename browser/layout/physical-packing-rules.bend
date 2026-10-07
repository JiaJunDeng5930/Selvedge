import Base
import ./SPACE.bend as Space
import ./space-laws.bend as SpaceLaws
import ./PROGRAM.bend as Allocation

# Successful shared packing retains the original authored dimension contract.
def SharedClaim(~A: Data, +slots: +List<Space.Slot<A>>, +gap: Nat, +available: Nat, result: Space.Packing<A>) -> Type:
  match result:
    case Space.Insufficient{required, received}: Unit
    case Space.Packed{placements, unused}:
      SpaceLaws.AllocationEvidence<A, slots, gap, 0n, available, Space.Allocation{placements, unused}>

# Rigid extents are selected directly, without reflecting boolean equality.
def rigid_extent(dimension: Space.Dimension, extent: Nat) -> Type:
  match dimension:
    case Space.Rigid{declared}: {extent == declared : Nat}
    case _: Unit

def rigid_extents(~A: Data, slots: +List<Space.Slot<A>>, placements: +List<Space.Placement<A>>) -> Type:
  match slots placements:
    case Nil{} Nil{}: Unit
    case Con{Space.Slot{value, +dimension}, rest} Con{Space.Placement{other, offset, extent}, tail}:
      rigid_extent(dimension, extent) & rigid_extents(~A, rest, tail)
    case _ _: Empty

def allocation_rigid_extents(~A: Data, slots: +List<Space.Slot<A>>, allocation: Space.Allocation<A>) -> Type:
  Space.Allocation{placements, unused} = allocation
  rigid_extents(~A, slots, placements)

law rigid_placement:
  for ~A: Data
  for +slots: +List<Space.Slot<A>>
  for +gap: Nat
  for +offset: Nat
  for +budget: Nat
  allocation_rigid_extents(~A, slots, Space.place_from(~A, slots, gap, offset, budget))

law shared_packing:
  for ~A: Data
  for +slots: +List<Space.Slot<A>>
  for +gap: Nat
  for +available: Nat
  SharedClaim(~A, slots, gap, available, Allocation.shared_pack(~A, slots, gap, available))
