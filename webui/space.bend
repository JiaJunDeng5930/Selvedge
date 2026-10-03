import Base

type Dimension is Data:
  Rigid{extent: Nat}
  Fit{minimum: Nat, preferred_extra: Nat, maximum_extra: Nat}
  Fill{minimum: Nat}

def minimum(dimension: Dimension) -> Nat:
  match dimension:
    case Rigid{extent}: extent
    case Fit{value, preferred_extra, maximum_extra}: value
    case Fill{value}: value

def preferred(dimension: Dimension) -> Nat:
  match dimension:
    case Rigid{extent}: extent
    case Fit{value, preferred_extra, maximum_extra}: Nat.add(value, preferred_extra)
    case Fill{value}: value

def maximum(dimension: Dimension) -> Maybe<&2, Nat>:
  match dimension:
    case Rigid{extent}: Some{extent}
    case Fit{value, preferred_extra, maximum_extra}: Some{Nat.add(Nat.add(value, preferred_extra), maximum_extra)}
    case Fill{value}: None{}

type Slot<-A: Data> is Data:
  Slot{value: A, dimension: Dimension}

type Placement<-A: Data> is Data:
  Placement{value: A, offset: Nat, extent: Nat}

type Allocation<-A: Data> is Data:
  Allocation{placements: +List<Placement<A>>, unused: Nat}

type Packing<-A: Data> is Data:
  Packed{placements: +List<Placement<A>>, unused: Nat}
  Insufficient{required: Nat, available: Nat}

def minimum_sequence(~A: Data, slots: +List<Slot<A>>, +gap: Nat) -> Nat:
  match slots:
    case Nil{}: 0n
    case Con{Slot{value, dimension}, rest}:
      match rest:
        case Nil{}: minimum(dimension)
        case Con{next, tail}: Nat.add(minimum(dimension), Nat.add(gap, minimum_sequence(~A, next <> tail, gap)))

def reservation(~A: Data, slots: +List<Slot<A>>, +gap: Nat) -> Nat:
  match slots:
    case Nil{}: 0n
    case Con{head, tail}: Nat.add(gap, minimum_sequence(~A, head <> tail, gap))

def following_gap(~A: Data, slots: +List<Slot<A>>, gap: Nat) -> Nat:
  match slots:
    case Nil{}: 0n
    case Con{head, tail}: gap

def choose(dimension: Dimension, room: Nat) -> Nat:
  match dimension:
    case Rigid{extent}: extent
    case Fit{value, preferred_extra, maximum_extra}: Nat.min(Nat.add(value, preferred_extra), room)
    case Fill{value}: room

def prepend(~A: Data, head: Placement<A>, result: Allocation<A>) -> Allocation<A>:
  Allocation{placements, unused} = result
  Allocation{head <> placements, unused}

# Reserve every remaining minimum before allocating the current child.
def place_from(~A: Data, slots: +List<Slot<A>>, +gap: Nat, +offset: Nat, +budget: Nat) -> Allocation<A>:
  match slots:
    case Nil{}: Allocation{Nil{}, budget}
    case Con{Slot{value, +dimension}, +rest}:
      +size = choose(dimension, Nat.sub(budget, reservation(~A, rest, gap)))
      +between = following_gap(~A, rest, gap)
      prepend(~A, Placement{value, offset, size},
        place_from(~A, rest, gap, Nat.add(offset, Nat.add(size, between)), Nat.sub(Nat.sub(budget, size), between)))

def finish(~A: Data, result: Allocation<A>) -> Packing<A>:
  Allocation{placements, unused} = result
  Packed{placements, unused}

def feasible_pack(~A: Data, feasible: Bool, +slots: +List<Slot<A>>, +gap: Nat, +available: Nat) -> Packing<A>:
  match feasible:
    case False{}: Insufficient{minimum_sequence(~A, slots, gap), available}
    case True{}: finish(~A, place_from(~A, slots, gap, 0n, available))

def pack(~A: Data, +slots: +List<Slot<A>>, +gap: Nat, +available: Nat) -> Packing<A>:
  feasible_pack(~A, Nat.is_le(minimum_sequence(~A, slots, gap), available), slots, gap, available)
