import Base
import ../../bendlib/proofs/logic.bend as Logic
import ../../bendlib/proofs/algebra.bend as Alg
import ../space.bend as Space
import ../../bendlib/stdlib.bend as Std
import ../space-laws.bend as Rule

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

def and_join(+a: Bool, +b: Bool, first: {a == True{} : Bool}, second: {b == True{} : Bool}) ->
  {Bool.and(a, b) == True{} : Bool}:
  match a:
    case False{}: Logic.impossible({Bool.and(False{}, b) == True{} : Bool}, first)
    case True{}: second

def and_parts(+a: Bool, +b: Bool, proof: {Bool.and(a, b) == True{} : Bool}) ->
  {a == True{} : Bool} & {b == True{} : Bool}:
  match a:
    case False{}: Logic.impossible({False{} == True{} : Bool} & {b == True{} : Bool}, proof)
    case True{}: ({==}, proof)

def max_left(+a: Nat, +b: Nat) -> {Nat.is_le(a, Nat.max(a, b)) == True{} : Bool}:
  Equal.trans(Bool, Nat.is_le(a, Nat.max(a, b)), Nat.is_ge(Nat.max(a, b), a), True{},
    Equal.sym(Bool, Nat.is_ge(Nat.max(a, b), a), Nat.is_le(a, Nat.max(a, b)), ge_le(Nat.max(a, b), a)), Nat.max_ge_l(a, b))

def max_right(+a: Nat, +b: Nat) -> {Nat.is_le(b, Nat.max(a, b)) == True{} : Bool}:
  Equal.trans(Bool, Nat.is_le(b, Nat.max(a, b)), Nat.is_ge(Nat.max(a, b), b), True{},
    Equal.sym(Bool, Nat.is_ge(Nat.max(a, b), b), Nat.is_le(b, Nat.max(a, b)), ge_le(Nat.max(a, b), b)), Nat.max_ge_r(a, b))

def le_refl(+value: Nat) -> {Nat.is_le(value, value) == True{} : Bool}:
  Equal.trans(Bool, Nat.is_le(value, value), Nat.is_ge(value, value), True{},
    Equal.sym(Bool, Nat.is_ge(value, value), Nat.is_le(value, value), ge_le(value, value)), Nat.ge_refl(value))

def add_comm(+first: Nat, +second: Nat) ->
  {Nat.add(first, second) == Nat.add(second, first) : Nat}:
  match first:
    case 0n: Equal.sym(Nat, Nat.add(second, 0n), second, Alg.nat_add_zero(second))
    case 1n+rest:
      Equal.trans(Nat, 1n+Nat.add(rest, second), 1n+Nat.add(second, rest), Nat.add(second, 1n+rest),
        Equal.cong(Nat, Nat, (n => 1n+n), Nat.add(rest, second), Nat.add(second, rest), add_comm(rest, second)),
        Equal.sym(Nat, Nat.add(second, 1n+rest), 1n+Nat.add(second, rest), Alg.nat_add_succ(second, rest)))

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
    case 1n+a 0n _: Logic.impossible({Nat.is_le(1n+a, third) == True{} : Bool}, left)
    case 1n+a 1n+b 0n: Logic.impossible({Nat.is_le(1n+a, 0n) == True{} : Bool}, right)
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
    case 1n+rest 0n: Logic.impossible({Nat.is_le(1n+rest, Nat.min(Nat.add(1n+rest, extra), 0n)) == True{} : Bool}, fits)
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
      Logic.impossible({Nat.is_le(rest, Nat.sub(0n, 1n+own)) == True{} : Bool} &
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
      %Equal.sym(Nat, Nat.add(own, 0n), own, Alg.nat_add_zero(own)) : {Nat.is_le(_, 0n) == True{} : Bool}
      own_in_room
    case 0n 1n+remaining:
      %Equal.sym(Nat, Nat.add(own, 0n), own, Alg.nat_add_zero(own)) : {Nat.is_le(_, 1n+remaining) == True{} : Bool}
      own_in_room
    case 1n+rest 0n:
      Logic.impossible({Nat.is_le(Nat.add(own, 1n+rest), 0n) == True{} : Bool}, reserve_in_budget)
    case 1n+rest 1n+remaining:
      %Equal.sym(Nat, Nat.add(own, 1n+rest), 1n+Nat.add(own, rest), Alg.nat_add_succ(own, rest)) : {Nat.is_le(_, 1n+remaining) == True{} : Bool}
      reserved_use(own, rest, remaining, reserve_in_budget, own_in_room)

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
  {Rule.maximum_ok(dimension, Space.choose(dimension, room)) == True{} : Bool}:
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
  {Rule.rigid_ok(dimension, Space.choose(dimension, room)) == True{} : Bool}:
  match dimension:
    case Space.Rigid{value}: eq_refl(value)
    case Space.Fit{lower, extra, maximum_extra}: {==}
    case Space.Fill{lower}: {==}

def conjunction(+first: Bool, +second: Bool,
  left: {first == True{} : Bool}, right: {second == True{} : Bool}) ->
  {(first && second) == True{} : Bool}:
  Equal.trans(Bool, first && second, second, True{},
    Equal.cong(Bool, Bool, (value => value && second), first, True{}, left), right)

def sequence_split(~A: Data, +value: A, +dimension: Space.Dimension, +rest: +List<Space.Slot<A>>, +gap: Nat) ->
  {Space.minimum_sequence(~A, Space.Slot{value, dimension} <> rest, gap) ==
    Nat.add(Space.minimum(dimension), Space.reservation(~A, rest, gap)) : Nat}:
  match rest:
    case Nil{}: Equal.sym(Nat, Nat.add(Space.minimum(dimension), 0n), Space.minimum(dimension), Alg.nat_add_zero(Space.minimum(dimension)))
    case Con{next, tail}: {==}

def reserve_split(~A: Data, +rest: +List<Space.Slot<A>>, +gap: Nat) ->
  {Space.reservation(~A, rest, gap) == Nat.add(Space.following_gap(~A, rest, gap), Space.minimum_sequence(~A, rest, gap)) : Nat}:
  match rest:
    case Nil{}: {==}
    case Con{head, tail}: {==}

def gap_agrees(~A: Data, +slots: +List<Space.Slot<A>>, +placements: +List<Space.Placement<A>>, +gap: Nat,
  valid: {Rule.limits(~A, slots, placements) == True{} : Bool}) ->
  {Space.following_gap(~A, slots, gap) == Rule.placement_gap(~A, placements, gap) : Nat}:
  match slots placements:
    case Nil{} Nil{}: {==}
    case Con{head, tail} Con{other, rest}: {==}
    case Nil{} Con{head, tail}: Logic.impossible({0n == gap : Nat}, valid)
    case Con{Space.Slot{value, dimension}, tail} Nil{}: Logic.impossible({gap == 0n : Nat}, valid)

def used_split(~A: Data, +value: A, +offset: Nat, +size: Nat, +rest: +List<Space.Placement<A>>, +gap: Nat) ->
  {Rule.used(~A, Space.Placement{value, offset, size} <> rest, gap) ==
    Nat.add(size, Nat.add(Rule.placement_gap(~A, rest, gap), Rule.used(~A, rest, gap))) : Nat}:
  match rest:
    case Nil{}: Equal.sym(Nat, Nat.add(size, 0n), size, Alg.nat_add_zero(size))
    case Con{head, tail}: {==}

def combined_balance(+size: Nat, +between: Nat, +tail_used: Nat, +unused: Nat, +next_budget: Nat, +budget: Nat,
  tail_balance: {Nat.add(tail_used, unused) == next_budget : Nat},
  head_balance: {Nat.add(size, Nat.add(between, next_budget)) == budget : Nat}) ->
  {Nat.add(Nat.add(size, Nat.add(between, tail_used)), unused) == budget : Nat}:
  Equal.trans(Nat, Nat.add(Nat.add(size, Nat.add(between, tail_used)), unused),
    Nat.add(size, Nat.add(Nat.add(between, tail_used), unused)), budget,
    Alg.nat_add_assoc(size, Nat.add(between, tail_used), unused),
    Equal.trans(Nat, Nat.add(size, Nat.add(Nat.add(between, tail_used), unused)),
      Nat.add(size, Nat.add(between, Nat.add(tail_used, unused))), budget,
      Equal.cong(Nat, Nat, (n => Nat.add(size, n)), Nat.add(Nat.add(between, tail_used), unused),
        Nat.add(between, Nat.add(tail_used, unused)), Alg.nat_add_assoc(between, tail_used, unused)),
      Equal.trans(Nat, Nat.add(size, Nat.add(between, Nat.add(tail_used, unused))),
        Nat.add(size, Nat.add(between, next_budget)), budget,
        Equal.cong(Nat, Nat, (n => Nat.add(size, Nat.add(between, n))), Nat.add(tail_used, unused), next_budget, tail_balance), head_balance)))

def prefix_evidence(~A: Data, +value: A, +dimension: Space.Dimension, +slots: +List<Space.Slot<A>>, +gap: Nat,
  +offset: Nat, +size: Nat, +budget: Nat, +next_budget: Nat, +result: Space.Allocation<A>,
  lower: {Nat.is_le(Space.minimum(dimension), size) == True{} : Bool},
  upper: {Rule.maximum_ok(dimension, size) == True{} : Bool},
  rigid: {Rule.rigid_ok(dimension, size) == True{} : Bool},
  head_balance: {Nat.add(size, Nat.add(Space.following_gap(~A, slots, gap), next_budget)) == budget : Nat},
  tail: Rule.AllocationEvidence<A, slots, gap, Nat.add(offset, Nat.add(size, Space.following_gap(~A, slots, gap))), next_budget, result>) ->
  Rule.AllocationEvidence<A, Space.Slot{value, dimension} <> slots, gap, offset, budget,
    Space.prepend(~A, Space.Placement{value, offset, size}, result)>:
  Space.Allocation{+placements, +unused} = result
  Rule.AllocationEvidence{payloads, +bounds, order, balance} = tail
  +same_gap = gap_agrees(~A, slots, placements, gap, bounds)
  next_order = Equal.trans(Bool,
    Rule.positions(~A, placements, gap, Nat.add(offset, Nat.add(size, Rule.placement_gap(~A, placements, gap)))),
    Rule.positions(~A, placements, gap, Nat.add(offset, Nat.add(size, Space.following_gap(~A, slots, gap)))), True{},
    Equal.cong(Nat, Bool, (n => Rule.positions(~A, placements, gap, Nat.add(offset, Nat.add(size, n)))),
      Rule.placement_gap(~A, placements, gap), Space.following_gap(~A, slots, gap),
      Equal.sym(Nat, Space.following_gap(~A, slots, gap), Rule.placement_gap(~A, placements, gap), same_gap)), order)
  concrete_head_balance = Equal.trans(Nat,
    Nat.add(size, Nat.add(Rule.placement_gap(~A, placements, gap), next_budget)),
    Nat.add(size, Nat.add(Space.following_gap(~A, slots, gap), next_budget)), budget,
    Equal.cong(Nat, Nat, (n => Nat.add(size, Nat.add(n, next_budget))), Rule.placement_gap(~A, placements, gap),
      Space.following_gap(~A, slots, gap), Equal.sym(Nat, Space.following_gap(~A, slots, gap), Rule.placement_gap(~A, placements, gap), same_gap)), head_balance)
  Rule.AllocationEvidence{
    Equal.cong(+List<A>, +List<A>, (items => value <> items), Rule.placement_values(~A, placements), Rule.slot_values(~A, slots), payloads),
    conjunction(Nat.is_le(Space.minimum(dimension), size), Rule.maximum_ok(dimension, size) && (Rule.rigid_ok(dimension, size) && Rule.limits(~A, slots, placements)), lower,
      conjunction(Rule.maximum_ok(dimension, size), Rule.rigid_ok(dimension, size) && Rule.limits(~A, slots, placements), upper,
        conjunction(Rule.rigid_ok(dimension, size), Rule.limits(~A, slots, placements), rigid, bounds))),
    conjunction(Nat.is_eq(offset, offset), Rule.positions(~A, placements, gap, Nat.add(offset, Nat.add(size, Rule.placement_gap(~A, placements, gap)))), eq_refl(offset), next_order),
    Equal.trans(Nat, Nat.add(Rule.used(~A, Space.Placement{value, offset, size} <> placements, gap), unused),
      Nat.add(Nat.add(size, Nat.add(Rule.placement_gap(~A, placements, gap), Rule.used(~A, placements, gap))), unused), budget,
      Equal.cong(Nat, Nat, (n => Nat.add(n, unused)), Rule.used(~A, Space.Placement{value, offset, size} <> placements, gap),
        Nat.add(size, Nat.add(Rule.placement_gap(~A, placements, gap), Rule.used(~A, placements, gap))), used_split(~A, value, offset, size, placements, gap)),
      combined_balance(size, Rule.placement_gap(~A, placements, gap), Rule.used(~A, placements, gap), unused, next_budget, budget, balance, concrete_head_balance))}

# The induction reserves the entire remaining sequence before choosing a size.
def place_evidence(~A: Data, +slots: +List<Space.Slot<A>>, +gap: Nat, +offset: Nat, +budget: Nat,
  fits: {Nat.is_le(Space.minimum_sequence(~A, slots, gap), budget) == True{} : Bool}) ->
  Rule.AllocationEvidence<A, slots, gap, offset, budget, Space.place_from(~A, slots, gap, offset, budget)>:
  match slots:
    case Nil{}: Rule.AllocationEvidence{{==}, {==}, {==}, {==}}
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
  {Rule.maximum_ok(dimension, Space.preferred(dimension)) == True{} : Bool}:
  match dimension:
    case Space.Rigid{size}: le_refl(size)
    case Space.Fit{lower, extra, maximum_extra}: le_add(Nat.add(lower, extra), maximum_extra)
    case Space.Fill{lower}: {==}

def finish_claim(~A: Data, +slots: +List<Space.Slot<A>>, +gap: Nat, +available: Nat, +result: Space.Allocation<A>,
  evidence: Rule.AllocationEvidence<A, slots, gap, 0n, available, result>) ->
  Rule.PackedClaim(~A, slots, gap, available, Space.finish(~A, result)):
  Space.Allocation{placements, unused} = result
  evidence

def pack_complete(~A: Data, +slots: +List<Space.Slot<A>>, +gap: Nat, +available: Nat,
  +fits: {Nat.is_le(Space.minimum_sequence(~A, slots, gap), available) == True{} : Bool}) ->
  Rule.PackedClaim(~A, slots, gap, available, Space.pack(~A, slots, gap, available)):
  Std.transport(Bool, True{}, (feasible => Rule.PackedClaim(~A, slots, gap, available, Space.feasible_pack(~A, feasible, slots, gap, available))),
    finish_claim(~A, slots, gap, available, Space.place_from(~A, slots, gap, 0n, available), place_evidence(~A, slots, gap, 0n, available, fits)),
    Nat.is_le(Space.minimum_sequence(~A, slots, gap), available), fits)

def pack_insufficient(~A: Data, +slots: +List<Space.Slot<A>>, +gap: Nat, +available: Nat,
  does_not_fit: {Nat.is_le(Space.minimum_sequence(~A, slots, gap), available) == False{} : Bool}) ->
  {Space.pack(~A, slots, gap, available) == Space.Insufficient{Space.minimum_sequence(~A, slots, gap), available} : Space.Packing<A>}:
  Equal.cong(Bool, Space.Packing<A>, (feasible => Space.feasible_pack(~A, feasible, slots, gap, available)),
    Nat.is_le(Space.minimum_sequence(~A, slots, gap), available), False{}, does_not_fit)

def finish_packed(~A: Data, result: Space.Allocation<A>) -> {Rule.packed(~A, Space.finish(~A, result)) == True{} : Bool}:
  Space.Allocation{placements, unused} = result
  {==}

def feasible_tag(~A: Data, +feasible: Bool, +slots: +List<Space.Slot<A>>, +gap: Nat, +available: Nat) ->
  {Rule.packed(~A, Space.feasible_pack(~A, feasible, slots, gap, available)) == feasible : Bool}:
  match feasible:
    case False{}: {==}
    case True{}: finish_packed(~A, Space.place_from(~A, slots, gap, 0n, available))

def Rule.evidence(A):
  Rule.Requirements{dimension_minimum, dimension_maximum,
    +slots => +gap => +available => feasible_tag(~A, Nat.is_le(Space.minimum_sequence(~A, slots, gap), available), slots, gap, available),
    +slots => +gap => +available => does_not_fit => pack_insufficient(~A, slots, gap, available, does_not_fit),
    +slots => +gap => +available => +fits => pack_complete(~A, slots, gap, available, fits)}
