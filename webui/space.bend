import Base
import ./enclosure.bend as Enclosure

type Axis is Data:
  Horizontal{}
  Vertical{}

type Dimension is Data:
  Rigid{extent: Nat}
  Fit{minimum: Nat, preferred_extra: Nat, maximum_extra: Nat}
  Fill{minimum: Nat}

type Demand is Data:
  Demand{inline: Dimension, block: Dimension}

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

def along(demand: Demand, axis: Axis) -> Dimension:
  Demand{inline, block} = demand
  match axis:
    case Horizontal{}: inline
    case Vertical{}: block

def extent(value: Enclosure.Extent, axis: Axis) -> Nat:
  Enclosure.Extent{width, height} = value
  match axis:
    case Horizontal{}: width
    case Vertical{}: height

def minimum_extent(demand: Demand) -> Enclosure.Extent:
  Demand{inline, block} = demand
  Enclosure.Extent{minimum(inline), minimum(block)}

def preferred_extent(demand: Demand) -> Enclosure.Extent:
  Demand{inline, block} = demand
  Enclosure.Extent{preferred(inline), preferred(block)}

# The extra is measured above the complete minimum, including the target.
def content_dimension(ink_min: Nat, ink_preferred: Nat, inset: Nat, border: Nat, target_min: Nat) -> Dimension:
  +allocation = Nat.mul(2n, Nat.add(border, inset))
  +lower = Nat.max(target_min, Nat.add(ink_min, allocation))
  desired = Nat.max(lower, Nat.add(ink_preferred, allocation))
  Fit{lower, Nat.sub(desired, lower), 0n}

def content_demand(ink_min: Enclosure.Extent, ink_preferred: Enclosure.Extent, +frame: Enclosure.ContentArea,
  +border: Nat, target_min: Enclosure.Extent) -> Demand:
  Enclosure.Extent{min_width, min_height} = ink_min
  Enclosure.Extent{preferred_width, preferred_height} = ink_preferred
  Enclosure.Extent{target_width, target_height} = target_min
  Demand{content_dimension(min_width, preferred_width, Enclosure.inline(frame), border, target_width),
    content_dimension(min_height, preferred_height, Enclosure.block(frame), border, target_height)}

def summed(children: +List<Demand>, +axis: Axis, +gap: Nat, use_preferred: Bool) -> Nat:
  match children:
    case Nil{}: 0n
    case Con{head, rest}:
      match rest:
        case Nil{}:
          match use_preferred:
            case False{}: minimum(along(head, axis))
            case True{}: preferred(along(head, axis))
        case Con{next, tail}:
          match use_preferred:
            case False{}: Nat.add(minimum(along(head, axis)), Nat.add(gap, summed(next <> tail, axis, gap, False{})))
            case True{}: Nat.add(preferred(along(head, axis)), Nat.add(gap, summed(next <> tail, axis, gap, True{})))

def widest(children: +List<Demand>, +axis: Axis, use_preferred: Bool) -> Nat:
  match children:
    case Nil{}: 0n
    case Con{head, rest}:
      match use_preferred:
        case False{}: Nat.max(minimum(along(head, axis)), widest(rest, axis, False{}))
        case True{}: Nat.max(preferred(along(head, axis)), widest(rest, axis, True{}))

def row_demand(+children: +List<Demand>, +gap: Nat, frame: Enclosure.ContentArea, border: Nat) -> Demand:
  content_demand(Enclosure.Extent{summed(children, Horizontal{}, gap, False{}), widest(children, Vertical{}, False{})},
    Enclosure.Extent{summed(children, Horizontal{}, gap, True{}), widest(children, Vertical{}, True{})}, frame, border, Enclosure.Extent{0n, 0n})

def column_demand(+children: +List<Demand>, +gap: Nat, frame: Enclosure.ContentArea, border: Nat) -> Demand:
  content_demand(Enclosure.Extent{widest(children, Horizontal{}, False{}), summed(children, Vertical{}, gap, False{})},
    Enclosure.Extent{widest(children, Horizontal{}, True{}), summed(children, Vertical{}, gap, True{})}, frame, border, Enclosure.Extent{0n, 0n})

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
