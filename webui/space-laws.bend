import Base
import ./space.bend as Space
import ./enclosure.bend as Enclosure
import ../bendlib/stdlib.bend as Std

def false_goal(P: Type, value: Bool) -> Type:
  match value:
    case False{}: Unit
    case True{}: P

def impossible(P: Type, evidence: {False{} == True{} : Bool}) -> P:
  Std.transport(Bool, False{}, (value => false_goal(P, value)), Unit{}, True{},
    Equal.sym(Bool, False{}, True{}, evidence))

def zero_le(value: Nat) -> {Nat.is_le(0n, value) == True{} : Bool}:
  match value:
    case 0n: {==}
    case 1n+rest: {==}

def ge_le(+first: Nat, +second: Nat) ->
  {Nat.is_ge(first, second) == Nat.is_le(second, first) : Bool}:
  match first second:
    case 0n 0n: {==}
    case 0n 1n+rest: {==}
    case 1n+rest 0n: {==}
    case 1n+left 1n+right: ge_le(left, right)

def le_refl(+value: Nat) -> {Nat.is_le(value, value) == True{} : Bool}:
  Equal.trans(Bool, Nat.is_le(value, value), Nat.is_ge(value, value), True{},
    Equal.sym(Bool, Nat.is_ge(value, value), Nat.is_le(value, value), ge_le(value, value)), Nat.ge_refl(value))

def add_zero(+value: Nat) -> {Nat.add(value, 0n) == value : Nat}:
  match value:
    case 0n: {==}
    case 1n+rest: Equal.cong(Nat, Nat, (n => 1n+n), Nat.add(rest, 0n), rest, add_zero(rest))

def add_succ(+first: Nat, +second: Nat) ->
  {Nat.add(first, 1n+second) == 1n+Nat.add(first, second) : Nat}:
  match first:
    case 0n: {==}
    case 1n+rest: Equal.cong(Nat, Nat, (n => 1n+n), Nat.add(rest, 1n+second), 1n+Nat.add(rest, second), add_succ(rest, second))

def add_comm(+first: Nat, +second: Nat) ->
  {Nat.add(first, second) == Nat.add(second, first) : Nat}:
  match first:
    case 0n: Equal.sym(Nat, Nat.add(second, 0n), second, add_zero(second))
    case 1n+rest:
      Equal.trans(Nat, 1n+Nat.add(rest, second), 1n+Nat.add(second, rest), Nat.add(second, 1n+rest),
        Equal.cong(Nat, Nat, (n => 1n+n), Nat.add(rest, second), Nat.add(second, rest), add_comm(rest, second)),
        Equal.sym(Nat, Nat.add(second, 1n+rest), 1n+Nat.add(second, rest), add_succ(second, rest)))

def add_assoc(+first: Nat, +second: Nat, +third: Nat) ->
  {Nat.add(Nat.add(first, second), third) == Nat.add(first, Nat.add(second, third)) : Nat}:
  match first:
    case 0n: {==}
    case 1n+rest: Equal.cong(Nat, Nat, (n => 1n+n), Nat.add(Nat.add(rest, second), third), Nat.add(rest, Nat.add(second, third)), add_assoc(rest, second, third))

def le_add(+first: Nat, +extra: Nat) -> {Nat.is_le(first, Nat.add(first, extra)) == True{} : Bool}:
  match first:
    case 0n: zero_le(extra)
    case 1n+rest: le_add(rest, extra)

def le_trans(+first: Nat, +second: Nat, +third: Nat,
  left: {Nat.is_le(first, second) == True{} : Bool},
  right: {Nat.is_le(second, third) == True{} : Bool}) ->
  {Nat.is_le(first, third) == True{} : Bool}:
  match first second third:
    case 0n _ _: zero_le(third)
    case 1n+a 0n _: impossible({Nat.is_le(1n+a, third) == True{} : Bool}, left)
    case 1n+a 1n+b 0n: impossible({Nat.is_le(1n+a, 0n) == True{} : Bool}, right)
    case 1n+a 1n+b 1n+c: le_trans(a, b, c, left, right)

def min_le_first(+first: Nat, +second: Nat) ->
  {Nat.is_le(Nat.min(first, second), first) == True{} : Bool}:
  match first second:
    case 0n _: {==}
    case 1n+rest 0n: {==}
    case 1n+left 1n+right: min_le_first(left, right)

def min_le_second(+first: Nat, +second: Nat) ->
  {Nat.is_le(Nat.min(first, second), second) == True{} : Bool}:
  match first second:
    case 0n _: zero_le(second)
    case 1n+rest 0n: {==}
    case 1n+left 1n+right: min_le_second(left, right)

def min_floor(+lower: Nat, +extra: Nat, +room: Nat,
  fits: {Nat.is_le(lower, room) == True{} : Bool}) ->
  {Nat.is_le(lower, Nat.min(Nat.add(lower, extra), room)) == True{} : Bool}:
  match lower room:
    case 0n _: zero_le(Nat.min(extra, room))
    case 1n+rest 0n: impossible({Nat.is_le(1n+rest, Nat.min(Nat.add(1n+rest, extra), 0n)) == True{} : Bool}, fits)
    case 1n+rest 1n+remaining: min_floor(rest, extra, remaining, fits)

def first(-P: Type, -Q: Type, pair: P & Q) -> P:
  (left, right) = pair
  left

def second(-P: Type, -Q: Type, pair: P & Q) -> Q:
  (left, right) = pair
  right

def residual_step(+own: Nat, +rest: Nat, +remaining: Nat,
  evidence: {Nat.is_le(rest, Nat.sub(remaining, own)) == True{} : Bool} &
    {Nat.add(own, Nat.sub(remaining, own)) == remaining : Nat}) ->
  {Nat.is_le(rest, Nat.sub(1n+remaining, 1n+own)) == True{} : Bool} &
  {Nat.add(1n+own, Nat.sub(1n+remaining, 1n+own)) == 1n+remaining : Nat}:
  (tail_fits, balance) = evidence
  (tail_fits, Equal.cong(Nat, Nat, (n => 1n+n), Nat.add(own, Nat.sub(remaining, own)), remaining, balance))

# Cancelling a reserved prefix uses the actual saturating subtraction.
def residual(+prefix: Nat, +rest: Nat, +budget: Nat,
  fits: {Nat.is_le(Nat.add(prefix, rest), budget) == True{} : Bool}) ->
  {Nat.is_le(rest, Nat.sub(budget, prefix)) == True{} : Bool} &
  {Nat.add(prefix, Nat.sub(budget, prefix)) == budget : Nat}:
  match prefix budget:
    case 0n 0n: (fits, {==})
    case 0n 1n+remaining: (fits, {==})
    case 1n+own 0n:
      impossible({Nat.is_le(rest, Nat.sub(0n, 1n+own)) == True{} : Bool} &
        {Nat.add(1n+own, Nat.sub(0n, 1n+own)) == 0n : Nat}, fits)
    case 1n+own 1n+remaining:
      residual_step(own, rest, remaining, residual(own, rest, remaining, fits))

def room_fits(+own: Nat, +reserve: Nat, +budget: Nat,
  fits: {Nat.is_le(Nat.add(own, reserve), budget) == True{} : Bool}) ->
  {Nat.is_le(own, Nat.sub(budget, reserve)) == True{} : Bool}:
  swapped = Equal.cong(Nat, Bool, (n => Nat.is_le(n, budget)), Nat.add(own, reserve), Nat.add(reserve, own), add_comm(own, reserve))
  swapped_fits = Equal.trans(Bool, Nat.is_le(Nat.add(reserve, own), budget), Nat.is_le(Nat.add(own, reserve), budget), True{},
    Equal.sym(Bool, Nat.is_le(Nat.add(own, reserve), budget), Nat.is_le(Nat.add(reserve, own), budget), swapped), fits)
  first({Nat.is_le(own, Nat.sub(budget, reserve)) == True{} : Bool},
    {Nat.add(reserve, Nat.sub(budget, reserve)) == budget : Nat}, residual(reserve, own, budget, swapped_fits))

def reserve_fits(+own: Nat, +reserve: Nat, +budget: Nat,
  fits: {Nat.is_le(Nat.add(own, reserve), budget) == True{} : Bool}) ->
  {Nat.is_le(reserve, budget) == True{} : Bool}:
  le_trans(reserve, Nat.add(reserve, own), budget, le_add(reserve, own),
    Equal.trans(Bool, Nat.is_le(Nat.add(reserve, own), budget), Nat.is_le(Nat.add(own, reserve), budget), True{},
      Equal.cong(Nat, Bool, (n => Nat.is_le(n, budget)), Nat.add(reserve, own), Nat.add(own, reserve), add_comm(reserve, own)), fits))

def reserved_use(+own: Nat, +reserve: Nat, +budget: Nat,
  reserve_in_budget: {Nat.is_le(reserve, budget) == True{} : Bool},
  own_in_room: {Nat.is_le(own, Nat.sub(budget, reserve)) == True{} : Bool}) ->
  {Nat.is_le(Nat.add(own, reserve), budget) == True{} : Bool}:
  match reserve budget:
    case 0n 0n:
      %Equal.sym(Nat, Nat.add(own, 0n), own, add_zero(own)) : {Nat.is_le(_, 0n) == True{} : Bool}
      own_in_room
    case 0n 1n+remaining:
      %Equal.sym(Nat, Nat.add(own, 0n), own, add_zero(own)) : {Nat.is_le(_, 1n+remaining) == True{} : Bool}
      own_in_room
    case 1n+rest 0n:
      impossible({Nat.is_le(Nat.add(own, 1n+rest), 0n) == True{} : Bool}, reserve_in_budget)
    case 1n+rest 1n+remaining:
      %Equal.sym(Nat, Nat.add(own, 1n+rest), 1n+Nat.add(own, rest), add_succ(own, rest)) : {Nat.is_le(_, 1n+remaining) == True{} : Bool}
      reserved_use(own, rest, remaining, reserve_in_budget, own_in_room)

def maximum_ok(dimension: Space.Dimension, +size: Nat) -> Bool:
  match dimension:
    case Space.Rigid{value}: Nat.is_le(size, value)
    case Space.Fit{lower, extra, maximum_extra}: Nat.is_le(size, Nat.add(Nat.add(lower, extra), maximum_extra))
    case Space.Fill{lower}: True{}

def rigid_ok(dimension: Space.Dimension, +size: Nat) -> Bool:
  match dimension:
    case Space.Rigid{value}: Nat.is_eq(size, value)
    case _: True{}

def chosen_lower(+dimension: Space.Dimension, +room: Nat,
  fits: {Nat.is_le(Space.minimum(dimension), room) == True{} : Bool}) ->
  {Nat.is_le(Space.minimum(dimension), Space.choose(dimension, room)) == True{} : Bool}:
  match dimension:
    case Space.Rigid{value}: le_refl(value)
    case Space.Fit{lower, extra, maximum_extra}: min_floor(lower, extra, room, fits)
    case Space.Fill{lower}: fits

def chosen_room(+dimension: Space.Dimension, +room: Nat,
  fits: {Nat.is_le(Space.minimum(dimension), room) == True{} : Bool}) ->
  {Nat.is_le(Space.choose(dimension, room), room) == True{} : Bool}:
  match dimension:
    case Space.Rigid{value}: fits
    case Space.Fit{lower, extra, maximum_extra}: min_le_second(Nat.add(lower, extra), room)
    case Space.Fill{lower}: le_refl(room)

def chosen_upper(+dimension: Space.Dimension, +room: Nat) ->
  {maximum_ok(dimension, Space.choose(dimension, room)) == True{} : Bool}:
  match dimension:
    case Space.Rigid{value}: le_refl(value)
    case Space.Fit{lower, extra, maximum_extra}:
      le_trans(Nat.min(Nat.add(lower, extra), room), Nat.add(lower, extra), Nat.add(Nat.add(lower, extra), maximum_extra),
        min_le_first(Nat.add(lower, extra), room), le_add(Nat.add(lower, extra), maximum_extra))
    case Space.Fill{lower}: {==}

def eq_refl(+value: Nat) -> {Nat.is_eq(value, value) == True{} : Bool}:
  match value:
    case 0n: {==}
    case 1n+rest: eq_refl(rest)

def chosen_rigid(+dimension: Space.Dimension, +room: Nat) ->
  {rigid_ok(dimension, Space.choose(dimension, room)) == True{} : Bool}:
  match dimension:
    case Space.Rigid{value}: eq_refl(value)
    case Space.Fit{lower, extra, maximum_extra}: {==}
    case Space.Fill{lower}: {==}

def conjunction(+first: Bool, +second: Bool,
  left: {first == True{} : Bool}, right: {second == True{} : Bool}) ->
  {(first && second) == True{} : Bool}:
  Equal.trans(Bool, first && second, second, True{},
    Equal.cong(Bool, Bool, (value => value && second), first, True{}, left), right)

def sub_zero(+value: Nat) -> {Nat.sub(value, 0n) == value : Nat}:
  match value:
    case 0n: {==}
    case 1n+rest: {==}

def sequence_split(~A: Data, +value: A, +dimension: Space.Dimension, +rest: +List<Space.Slot<A>>, +gap: Nat) ->
  {Space.minimum_sequence(~A, Space.Slot{value, dimension} <> rest, gap) ==
    Nat.add(Space.minimum(dimension), Space.reservation(~A, rest, gap)) : Nat}:
  match rest:
    case Nil{}: Equal.sym(Nat, Nat.add(Space.minimum(dimension), 0n), Space.minimum(dimension), add_zero(Space.minimum(dimension)))
    case Con{next, tail}: {==}

def reserve_split(~A: Data, +rest: +List<Space.Slot<A>>, +gap: Nat) ->
  {Space.reservation(~A, rest, gap) == Nat.add(Space.following_gap(~A, rest, gap), Space.minimum_sequence(~A, rest, gap)) : Nat}:
  match rest:
    case Nil{}: {==}
    case Con{head, tail}: {==}

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

def gap_agrees(~A: Data, +slots: +List<Space.Slot<A>>, +placements: +List<Space.Placement<A>>, +gap: Nat,
  valid: {limits(~A, slots, placements) == True{} : Bool}) ->
  {Space.following_gap(~A, slots, gap) == placement_gap(~A, placements, gap) : Nat}:
  match slots placements:
    case Nil{} Nil{}: {==}
    case Con{head, tail} Con{other, rest}: {==}
    case Nil{} Con{head, tail}: impossible({0n == gap : Nat}, valid)
    case Con{Space.Slot{value, dimension}, tail} Nil{}: impossible({gap == 0n : Nat}, valid)

def used_split(~A: Data, +value: A, +offset: Nat, +size: Nat, +rest: +List<Space.Placement<A>>, +gap: Nat) ->
  {used(~A, Space.Placement{value, offset, size} <> rest, gap) ==
    Nat.add(size, Nat.add(placement_gap(~A, rest, gap), used(~A, rest, gap))) : Nat}:
  match rest:
    case Nil{}: Equal.sym(Nat, Nat.add(size, 0n), size, add_zero(size))
    case Con{head, tail}: {==}

def combined_balance(+size: Nat, +between: Nat, +tail_used: Nat, +unused: Nat, +next_budget: Nat, +budget: Nat,
  tail_balance: {Nat.add(tail_used, unused) == next_budget : Nat},
  head_balance: {Nat.add(size, Nat.add(between, next_budget)) == budget : Nat}) ->
  {Nat.add(Nat.add(size, Nat.add(between, tail_used)), unused) == budget : Nat}:
  Equal.trans(Nat, Nat.add(Nat.add(size, Nat.add(between, tail_used)), unused),
    Nat.add(size, Nat.add(Nat.add(between, tail_used), unused)), budget,
    add_assoc(size, Nat.add(between, tail_used), unused),
    Equal.trans(Nat, Nat.add(size, Nat.add(Nat.add(between, tail_used), unused)),
      Nat.add(size, Nat.add(between, Nat.add(tail_used, unused))), budget,
      Equal.cong(Nat, Nat, (n => Nat.add(size, n)), Nat.add(Nat.add(between, tail_used), unused),
        Nat.add(between, Nat.add(tail_used, unused)), add_assoc(between, tail_used, unused)),
      Equal.trans(Nat, Nat.add(size, Nat.add(between, Nat.add(tail_used, unused))),
        Nat.add(size, Nat.add(between, next_budget)), budget,
        Equal.cong(Nat, Nat, (n => Nat.add(size, Nat.add(between, n))), Nat.add(tail_used, unused), next_budget, tail_balance), head_balance)))

def prefix_evidence(~A: Data, +value: A, +dimension: Space.Dimension, +slots: +List<Space.Slot<A>>, +gap: Nat,
  +offset: Nat, +size: Nat, +budget: Nat, +next_budget: Nat, +result: Space.Allocation<A>,
  lower: {Nat.is_le(Space.minimum(dimension), size) == True{} : Bool},
  upper: {maximum_ok(dimension, size) == True{} : Bool},
  rigid: {rigid_ok(dimension, size) == True{} : Bool},
  head_balance: {Nat.add(size, Nat.add(Space.following_gap(~A, slots, gap), next_budget)) == budget : Nat},
  tail: AllocationEvidence<A, slots, gap, Nat.add(offset, Nat.add(size, Space.following_gap(~A, slots, gap))), next_budget, result>) ->
  AllocationEvidence<A, Space.Slot{value, dimension} <> slots, gap, offset, budget,
    Space.prepend(~A, Space.Placement{value, offset, size}, result)>:
  Space.Allocation{+placements, +unused} = result
  AllocationEvidence{payloads, +bounds, order, balance} = tail
  +same_gap = gap_agrees(~A, slots, placements, gap, bounds)
  next_order = Equal.trans(Bool,
    positions(~A, placements, gap, Nat.add(offset, Nat.add(size, placement_gap(~A, placements, gap)))),
    positions(~A, placements, gap, Nat.add(offset, Nat.add(size, Space.following_gap(~A, slots, gap)))), True{},
    Equal.cong(Nat, Bool, (n => positions(~A, placements, gap, Nat.add(offset, Nat.add(size, n)))),
      placement_gap(~A, placements, gap), Space.following_gap(~A, slots, gap),
      Equal.sym(Nat, Space.following_gap(~A, slots, gap), placement_gap(~A, placements, gap), same_gap)), order)
  concrete_head_balance = Equal.trans(Nat,
    Nat.add(size, Nat.add(placement_gap(~A, placements, gap), next_budget)),
    Nat.add(size, Nat.add(Space.following_gap(~A, slots, gap), next_budget)), budget,
    Equal.cong(Nat, Nat, (n => Nat.add(size, Nat.add(n, next_budget))), placement_gap(~A, placements, gap),
      Space.following_gap(~A, slots, gap), Equal.sym(Nat, Space.following_gap(~A, slots, gap), placement_gap(~A, placements, gap), same_gap)), head_balance)
  AllocationEvidence{
    Equal.cong(+List<A>, +List<A>, (items => value <> items), placement_values(~A, placements), slot_values(~A, slots), payloads),
    conjunction(Nat.is_le(Space.minimum(dimension), size), maximum_ok(dimension, size) && (rigid_ok(dimension, size) && limits(~A, slots, placements)), lower,
      conjunction(maximum_ok(dimension, size), rigid_ok(dimension, size) && limits(~A, slots, placements), upper,
        conjunction(rigid_ok(dimension, size), limits(~A, slots, placements), rigid, bounds))),
    conjunction(Nat.is_eq(offset, offset), positions(~A, placements, gap, Nat.add(offset, Nat.add(size, placement_gap(~A, placements, gap)))), eq_refl(offset), next_order),
    Equal.trans(Nat, Nat.add(used(~A, Space.Placement{value, offset, size} <> placements, gap), unused),
      Nat.add(Nat.add(size, Nat.add(placement_gap(~A, placements, gap), used(~A, placements, gap))), unused), budget,
      Equal.cong(Nat, Nat, (n => Nat.add(n, unused)), used(~A, Space.Placement{value, offset, size} <> placements, gap),
        Nat.add(size, Nat.add(placement_gap(~A, placements, gap), used(~A, placements, gap))), used_split(~A, value, offset, size, placements, gap)),
      combined_balance(size, placement_gap(~A, placements, gap), used(~A, placements, gap), unused, next_budget, budget, balance, concrete_head_balance))}

# The induction reserves the entire remaining sequence before choosing a size.
def place_evidence(~A: Data, +slots: +List<Space.Slot<A>>, +gap: Nat, +offset: Nat, +budget: Nat,
  fits: {Nat.is_le(Space.minimum_sequence(~A, slots, gap), budget) == True{} : Bool}) ->
  AllocationEvidence<A, slots, gap, offset, budget, Space.place_from(~A, slots, gap, offset, budget)>:
  match slots:
    case Nil{}: AllocationEvidence{{==}, {==}, {==}, {==}}
    case Con{Space.Slot{+value, +dimension}, +rest}:
      +reserve = Space.reservation(~A, rest, gap)
      +between = Space.following_gap(~A, rest, gap)
      +room = Nat.sub(budget, reserve)
      +size = Space.choose(dimension, room)
      +next_budget = Nat.sub(Nat.sub(budget, size), between)
      +sequence_fits = Equal.trans(Bool, Nat.is_le(Nat.add(Space.minimum(dimension), reserve), budget),
        Nat.is_le(Space.minimum_sequence(~A, Space.Slot{value, dimension} <> rest, gap), budget), True{},
        Equal.cong(Nat, Bool, (n => Nat.is_le(n, budget)), Nat.add(Space.minimum(dimension), reserve),
          Space.minimum_sequence(~A, Space.Slot{value, dimension} <> rest, gap),
          Equal.sym(Nat, Space.minimum_sequence(~A, Space.Slot{value, dimension} <> rest, gap), Nat.add(Space.minimum(dimension), reserve), sequence_split(~A, value, dimension, rest, gap))), fits)
      +minimum_in_room = room_fits(Space.minimum(dimension), reserve, budget, sequence_fits)
      +allocated_in_budget = reserved_use(size, reserve, budget,
        reserve_fits(Space.minimum(dimension), reserve, budget, sequence_fits), chosen_room(dimension, room, minimum_in_room))
      +allocated_with_split = Equal.trans(Bool, Nat.is_le(Nat.add(size, Nat.add(between, Space.minimum_sequence(~A, rest, gap))), budget),
        Nat.is_le(Nat.add(size, reserve), budget), True{},
        Equal.cong(Nat, Bool, (n => Nat.is_le(Nat.add(size, n), budget)), Nat.add(between, Space.minimum_sequence(~A, rest, gap)), reserve,
          Equal.sym(Nat, reserve, Nat.add(between, Space.minimum_sequence(~A, rest, gap)), reserve_split(~A, rest, gap))), allocated_in_budget)
      +tail_reserve_fits = first({Nat.is_le(Nat.add(between, Space.minimum_sequence(~A, rest, gap)), Nat.sub(budget, size)) == True{} : Bool},
        {Nat.add(size, Nat.sub(budget, size)) == budget : Nat}, residual(size, Nat.add(between, Space.minimum_sequence(~A, rest, gap)), budget, allocated_with_split))
      size_balance = second({Nat.is_le(Nat.add(between, Space.minimum_sequence(~A, rest, gap)), Nat.sub(budget, size)) == True{} : Bool},
        {Nat.add(size, Nat.sub(budget, size)) == budget : Nat}, residual(size, Nat.add(between, Space.minimum_sequence(~A, rest, gap)), budget, allocated_with_split))
      +next_fits = first({Nat.is_le(Space.minimum_sequence(~A, rest, gap), next_budget) == True{} : Bool},
        {Nat.add(between, next_budget) == Nat.sub(budget, size) : Nat}, residual(between, Space.minimum_sequence(~A, rest, gap), Nat.sub(budget, size), tail_reserve_fits))
      gap_balance = second({Nat.is_le(Space.minimum_sequence(~A, rest, gap), next_budget) == True{} : Bool},
        {Nat.add(between, next_budget) == Nat.sub(budget, size) : Nat}, residual(between, Space.minimum_sequence(~A, rest, gap), Nat.sub(budget, size), tail_reserve_fits))
      head_balance = Equal.trans(Nat, Nat.add(size, Nat.add(between, next_budget)), Nat.add(size, Nat.sub(budget, size)), budget,
        Equal.cong(Nat, Nat, (n => Nat.add(size, n)), Nat.add(between, next_budget), Nat.sub(budget, size), gap_balance), size_balance)
      prefix_evidence(~A, value, dimension, rest, gap, offset, size, budget, next_budget,
        Space.place_from(~A, rest, gap, Nat.add(offset, Nat.add(size, between)), next_budget),
        chosen_lower(dimension, room, minimum_in_room), chosen_upper(dimension, room), chosen_rigid(dimension, room), head_balance,
        place_evidence(~A, rest, gap, Nat.add(offset, Nat.add(size, between)), next_budget, next_fits))

def dimension_minimum(+dimension: Space.Dimension) ->
  {Nat.is_le(Space.minimum(dimension), Space.preferred(dimension)) == True{} : Bool}:
  match dimension:
    case Space.Rigid{size}: le_refl(size)
    case Space.Fit{lower, extra, maximum_extra}: le_add(lower, extra)
    case Space.Fill{lower}: le_refl(lower)

def dimension_maximum(+dimension: Space.Dimension) ->
  {maximum_ok(dimension, Space.preferred(dimension)) == True{} : Bool}:
  match dimension:
    case Space.Rigid{size}: le_refl(size)
    case Space.Fit{lower, extra, maximum_extra}: le_add(Nat.add(lower, extra), maximum_extra)
    case Space.Fill{lower}: {==}

def restore_preferred(+lower: Nat, +desired: Nat,
  fits: {Nat.is_le(lower, desired) == True{} : Bool}) ->
  {Nat.add(lower, Nat.sub(desired, lower)) == desired : Nat}:
  appended_fits = Equal.trans(Bool, Nat.is_le(Nat.add(lower, 0n), desired), Nat.is_le(lower, desired), True{},
    Equal.cong(Nat, Bool, (n => Nat.is_le(n, desired)), Nat.add(lower, 0n), lower, add_zero(lower)), fits)
  second({Nat.is_le(0n, Nat.sub(desired, lower)) == True{} : Bool},
    {Nat.add(lower, Nat.sub(desired, lower)) == desired : Nat}, residual(lower, 0n, desired, appended_fits))

def padded(ink: Nat, inset: Nat, border: Nat) -> Nat:
  Nat.add(ink, Nat.mul(2n, Nat.add(border, inset)))

def content_lower(+ink: Nat, +natural: Nat, +inset: Nat, +border: Nat, +target: Nat) ->
  {Space.minimum(Space.content_dimension(ink, natural, inset, border, target)) == Nat.max(target, padded(ink, inset, border)) : Nat}:
  {==}

def content_preferred(+ink: Nat, +natural: Nat, +inset: Nat, +border: Nat, +target: Nat) ->
  {Space.preferred(Space.content_dimension(ink, natural, inset, border, target)) ==
    Nat.max(Nat.max(target, padded(ink, inset, border)), padded(natural, inset, border)) : Nat}:
  +lower = Nat.max(target, padded(ink, inset, border))
  +desired = Nat.max(lower, padded(natural, inset, border))
  lower_fits = Equal.trans(Bool, Nat.is_le(lower, desired), Nat.is_ge(desired, lower), True{},
    Equal.sym(Bool, Nat.is_ge(desired, lower), Nat.is_le(lower, desired), ge_le(desired, lower)), Nat.max_ge_l(lower, padded(natural, inset, border)))
  restore_preferred(lower, desired, lower_fits)

def content_target(+ink: Nat, +natural: Nat, +inset: Nat, +border: Nat, +target: Nat) ->
  {Nat.is_le(target, Space.minimum(Space.content_dimension(ink, natural, inset, border, target))) == True{} : Bool}:
  +complete = Nat.max(target, padded(ink, inset, border))
  Equal.trans(Bool, Nat.is_le(target, complete), Nat.is_ge(complete, target), True{},
    Equal.sym(Bool, Nat.is_ge(complete, target), Nat.is_le(target, complete), ge_le(complete, target)), Nat.max_ge_l(target, padded(ink, inset, border)))

def content_ink(+ink: Nat, +natural: Nat, +inset: Nat, +border: Nat, +target: Nat) ->
  {Nat.is_le(padded(ink, inset, border), Space.minimum(Space.content_dimension(ink, natural, inset, border, target))) == True{} : Bool}:
  +complete = Nat.max(target, padded(ink, inset, border))
  Equal.trans(Bool, Nat.is_le(padded(ink, inset, border), complete), Nat.is_ge(complete, padded(ink, inset, border)), True{},
    Equal.sym(Bool, Nat.is_ge(complete, padded(ink, inset, border)), Nat.is_le(padded(ink, inset, border), complete), ge_le(complete, padded(ink, inset, border))),
    Nat.max_ge_r(target, padded(ink, inset, border)))

def content_natural(+ink: Nat, +natural: Nat, +inset: Nat, +border: Nat, +target: Nat) ->
  {Nat.is_le(padded(natural, inset, border), Space.preferred(Space.content_dimension(ink, natural, inset, border, target))) == True{} : Bool}:
  +lower = Nat.max(target, padded(ink, inset, border))
  +desired = Nat.max(lower, padded(natural, inset, border))
  bound = Equal.trans(Bool, Nat.is_le(padded(natural, inset, border), desired), Nat.is_ge(desired, padded(natural, inset, border)), True{},
    Equal.sym(Bool, Nat.is_ge(desired, padded(natural, inset, border)), Nat.is_le(padded(natural, inset, border), desired), ge_le(desired, padded(natural, inset, border))),
    Nat.max_ge_r(lower, padded(natural, inset, border)))
  Equal.trans(Bool, Nat.is_le(padded(natural, inset, border), Space.preferred(Space.content_dimension(ink, natural, inset, border, target))),
    Nat.is_le(padded(natural, inset, border), desired), True{},
    Equal.cong(Nat, Bool, (n => Nat.is_le(padded(natural, inset, border), n)),
      Space.preferred(Space.content_dimension(ink, natural, inset, border, target)), desired, content_preferred(ink, natural, inset, border, target)), bound)

def row_minimum(+children: +List<Space.Demand>, +gap: Nat, +area: Enclosure.ContentArea, +border: Nat) ->
  {Space.minimum_extent(Space.row_demand(children, gap, area, border)) ==
    Enclosure.Extent{padded(Space.summed(children, Space.Horizontal{}, gap, False{}), Enclosure.inline(area), border),
      padded(Space.widest(children, Space.Vertical{}, False{}), Enclosure.block(area), border)} : Enclosure.Extent}:
  {==}

def column_minimum(+children: +List<Space.Demand>, +gap: Nat, +area: Enclosure.ContentArea, +border: Nat) ->
  {Space.minimum_extent(Space.column_demand(children, gap, area, border)) ==
    Enclosure.Extent{padded(Space.widest(children, Space.Horizontal{}, False{}), Enclosure.inline(area), border),
      padded(Space.summed(children, Space.Vertical{}, gap, False{}), Enclosure.block(area), border)} : Enclosure.Extent}:
  {==}

def packed(~A: Data, value: Space.Packing<A>) -> Bool:
  match value:
    case Space.Packed{placements, unused}: True{}
    case Space.Insufficient{required, available}: False{}

def PackedClaim(~A: Data, +slots: +List<Space.Slot<A>>, +gap: Nat, +available: Nat, result: Space.Packing<A>) -> Type:
  match result:
    case Space.Packed{placements, unused}:
      AllocationEvidence<A, slots, gap, 0n, available, Space.Allocation{placements, unused}>
    case Space.Insufficient{required, received}: Empty

def finish_claim(~A: Data, +slots: +List<Space.Slot<A>>, +gap: Nat, +available: Nat, +result: Space.Allocation<A>,
  evidence: AllocationEvidence<A, slots, gap, 0n, available, result>) ->
  PackedClaim(~A, slots, gap, available, Space.finish(~A, result)):
  Space.Allocation{placements, unused} = result
  evidence

def pack_complete(~A: Data, +slots: +List<Space.Slot<A>>, +gap: Nat, +available: Nat,
  +fits: {Nat.is_le(Space.minimum_sequence(~A, slots, gap), available) == True{} : Bool}) ->
  PackedClaim(~A, slots, gap, available, Space.pack(~A, slots, gap, available)):
  Std.transport(Bool, True{}, (feasible => PackedClaim(~A, slots, gap, available, Space.feasible_pack(~A, feasible, slots, gap, available))),
    finish_claim(~A, slots, gap, available, Space.place_from(~A, slots, gap, 0n, available), place_evidence(~A, slots, gap, 0n, available, fits)),
    Nat.is_le(Space.minimum_sequence(~A, slots, gap), available), fits)

def pack_insufficient(~A: Data, +slots: +List<Space.Slot<A>>, +gap: Nat, +available: Nat,
  does_not_fit: {Nat.is_le(Space.minimum_sequence(~A, slots, gap), available) == False{} : Bool}) ->
  {Space.pack(~A, slots, gap, available) == Space.Insufficient{Space.minimum_sequence(~A, slots, gap), available} : Space.Packing<A>}:
  Equal.cong(Bool, Space.Packing<A>, (feasible => Space.feasible_pack(~A, feasible, slots, gap, available)),
    Nat.is_le(Space.minimum_sequence(~A, slots, gap), available), False{}, does_not_fit)

def finish_packed(~A: Data, result: Space.Allocation<A>) -> {packed(~A, Space.finish(~A, result)) == True{} : Bool}:
  Space.Allocation{placements, unused} = result
  {==}

def feasible_tag(~A: Data, +feasible: Bool, +slots: +List<Space.Slot<A>>, +gap: Nat, +available: Nat) ->
  {packed(~A, Space.feasible_pack(~A, feasible, slots, gap, available)) == feasible : Bool}:
  match feasible:
    case False{}: {==}
    case True{}: finish_packed(~A, Space.place_from(~A, slots, gap, 0n, available))

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
      PackedClaim(~A, slots, gap, available, Space.pack(~A, slots, gap, available)),
    content_minimum: @+ink:Nat -> @+natural:Nat -> @+inset:Nat -> @+border:Nat -> @+target:Nat ->
      {Space.minimum(Space.content_dimension(ink, natural, inset, border, target)) == Nat.max(target, padded(ink, inset, border)) : Nat},
    content_preferred: @+ink:Nat -> @+natural:Nat -> @+inset:Nat -> @+border:Nat -> @+target:Nat ->
      {Space.preferred(Space.content_dimension(ink, natural, inset, border, target)) == Nat.max(Nat.max(target, padded(ink, inset, border)), padded(natural, inset, border)) : Nat},
    content_target: @+ink:Nat -> @+natural:Nat -> @+inset:Nat -> @+border:Nat -> @+target:Nat ->
      {Nat.is_le(target, Space.minimum(Space.content_dimension(ink, natural, inset, border, target))) == True{} : Bool},
    content_ink: @+ink:Nat -> @+natural:Nat -> @+inset:Nat -> @+border:Nat -> @+target:Nat ->
      {Nat.is_le(padded(ink, inset, border), Space.minimum(Space.content_dimension(ink, natural, inset, border, target))) == True{} : Bool},
    content_natural: @+ink:Nat -> @+natural:Nat -> @+inset:Nat -> @+border:Nat -> @+target:Nat ->
      {Nat.is_le(padded(natural, inset, border), Space.preferred(Space.content_dimension(ink, natural, inset, border, target))) == True{} : Bool},
    row_minimum: @+children:+List<Space.Demand> -> @+gap:Nat -> @+area:Enclosure.ContentArea -> @+border:Nat ->
      {Space.minimum_extent(Space.row_demand(children, gap, area, border)) == Enclosure.Extent{
        padded(Space.summed(children, Space.Horizontal{}, gap, False{}), Enclosure.inline(area), border),
        padded(Space.widest(children, Space.Vertical{}, False{}), Enclosure.block(area), border)} : Enclosure.Extent},
    column_minimum: @+children:+List<Space.Demand> -> @+gap:Nat -> @+area:Enclosure.ContentArea -> @+border:Nat ->
      {Space.minimum_extent(Space.column_demand(children, gap, area, border)) == Enclosure.Extent{
        padded(Space.widest(children, Space.Horizontal{}, False{}), Enclosure.inline(area), border),
        padded(Space.summed(children, Space.Vertical{}, gap, False{}), Enclosure.block(area), border)} : Enclosure.Extent}}

def evidence(~A: Data) -> Requirements<A>:
  Requirements{dimension_minimum, dimension_maximum,
    +slots => +gap => +available => feasible_tag(~A, Nat.is_le(Space.minimum_sequence(~A, slots, gap), available), slots, gap, available),
    +slots => +gap => +available => does_not_fit => pack_insufficient(~A, slots, gap, available, does_not_fit),
    +slots => +gap => +available => +fits => pack_complete(~A, slots, gap, available, fits), content_lower, content_preferred, content_target, content_ink, content_natural, row_minimum, column_minimum}
