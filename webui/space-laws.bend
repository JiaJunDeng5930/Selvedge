import Base
import ./space.bend as Space
import ../bendlib/stdlib.bend as Std

def maximum_ok(dimension: Space.Dimension, +size: Nat) -> Bool:
  match dimension:
    case Space.Rigid{value}: Nat.is_le(size, value)
    case Space.Fit{lower, extra, maximum_extra}: Nat.is_le(size, Nat.add(Nat.add(lower, extra), maximum_extra))
    case Space.Fill{lower}: True{}

def rigid_ok(dimension: Space.Dimension, +size: Nat) -> Bool:
  match dimension:
    case Space.Rigid{value}: Nat.is_eq(size, value)
    case _: True{}

def slot_value(~A: Data, slot: Space.Slot<A>) -> A:
  Space.Slot{value, dimension} = slot
  value

def placement_value(~A: Data, placement: Space.Placement<A>) -> A:
  Space.Placement{value, offset, extent} = placement
  value

def slot_values(~A: Data, values: +List<Space.Slot<A>>) -> +List<A>:
  Std.map(~Space.Slot<A>, ~A, ~(value => slot_value(~A, value)), values)

def placement_values(~A: Data, values: +List<Space.Placement<A>>) -> +List<A>:
  Std.map(~Space.Placement<A>, ~A, ~(value => placement_value(~A, value)), values)

def placement_gap(~A: Data, values: +List<Space.Placement<A>>, gap: Nat) -> Nat:
  match values:
    case Nil{}: 0n
    case Con{head, tail}: gap

def used(~A: Data, values: +List<Space.Placement<A>>, +gap: Nat) -> Nat:
  match values:
    case Nil{}: 0n
    case Con{Space.Placement{value, offset, size}, rest}:
      match rest:
        case Nil{}: size
        case Con{next, tail}: Nat.add(size, Nat.add(gap, used(~A, next <> tail, gap)))

def limits(~A: Data, slots: +List<Space.Slot<A>>, placements: +List<Space.Placement<A>>) -> Bool:
  match slots placements:
    case Nil{} Nil{}: True{}
    case Con{Space.Slot{value, +dimension}, rest} Con{Space.Placement{other, offset, +size}, tail}:
      Nat.is_le(Space.minimum(dimension), size) &&
      (maximum_ok(dimension, size) && (rigid_ok(dimension, size) && limits(~A, rest, tail)))
    case _ _: False{}

def positions(~A: Data, values: +List<Space.Placement<A>>, +gap: Nat, offset: Nat) -> Bool:
  match values:
    case Nil{}: True{}
    case Con{Space.Placement{value, +actual, +size}, +rest}:
      Nat.is_eq(actual, offset) && positions(~A, rest, gap,
        Nat.add(actual, Nat.add(size, placement_gap(~A, rest, gap))))

def allocated_values(~A: Data, result: Space.Allocation<A>) -> +List<A>:
  Space.Allocation{placements, unused} = result
  placement_values(~A, placements)

def allocated_limits(~A: Data, slots: +List<Space.Slot<A>>, result: Space.Allocation<A>) -> Bool:
  Space.Allocation{placements, unused} = result
  limits(~A, slots, placements)

def allocated_positions(~A: Data, result: Space.Allocation<A>, gap: Nat, offset: Nat) -> Bool:
  Space.Allocation{placements, unused} = result
  positions(~A, placements, gap, offset)

def allocated_total(~A: Data, result: Space.Allocation<A>, gap: Nat) -> Nat:
  Space.Allocation{placements, unused} = result
  Nat.add(used(~A, placements, gap), unused)

type AllocationEvidence<-A: Data, -slots: +List<Space.Slot<A>>, -gap: Nat, -offset: Nat, -budget: Nat, -result: Space.Allocation<A>> is Type:
  AllocationEvidence{
    payloads: {allocated_values(~A, result) == slot_values(~A, slots) : +List<A>},
    bounds: {allocated_limits(~A, slots, result) == True{} : Bool},
    order: {allocated_positions(~A, result, gap, offset) == True{} : Bool},
    budget: {allocated_total(~A, result, gap) == budget : Nat}}

def packed(~A: Data, value: Space.Packing<A>) -> Bool:
  match value:
    case Space.Packed{placements, unused}: True{}
    case Space.Insufficient{required, available}: False{}

def PackedClaim(~A: Data, +slots: +List<Space.Slot<A>>, +gap: Nat, +available: Nat, result: Space.Packing<A>) -> Type:
  match result:
    case Space.Packed{placements, unused}:
      AllocationEvidence<A, slots, gap, 0n, available, Space.Allocation{placements, unused}>
    case Space.Insufficient{required, received}: Empty

type Requirements<-A: Data> is Type:
  Requirements{
    minimum_preferred: @+dimension:Space.Dimension ->
      {Nat.is_le(Space.minimum(dimension), Space.preferred(dimension)) == True{} : Bool},
    preferred_maximum: @+dimension:Space.Dimension ->
      {maximum_ok(dimension, Space.preferred(dimension)) == True{} : Bool},
    complete_feasibility: @+slots:+List<Space.Slot<A>> -> @+gap:Nat -> @+available:Nat ->
      {packed(~A, Space.pack(~A, slots, gap, available)) == Nat.is_le(Space.minimum_sequence(~A, slots, gap), available) : Bool},
    insufficient_record: @+slots:+List<Space.Slot<A>> -> @+gap:Nat -> @+available:Nat ->
      @does_not_fit:{Nat.is_le(Space.minimum_sequence(~A, slots, gap), available) == False{} : Bool} ->
      {Space.pack(~A, slots, gap, available) == Space.Insufficient{Space.minimum_sequence(~A, slots, gap), available} : Space.Packing<A>},
    packed_construction: @+slots:+List<Space.Slot<A>> -> @+gap:Nat -> @+available:Nat ->
      @+fits:{Nat.is_le(Space.minimum_sequence(~A, slots, gap), available) == True{} : Bool} ->
      PackedClaim(~A, slots, gap, available, Space.pack(~A, slots, gap, available))}

law evidence:
  for ~A: Data
  Requirements<A>
