import Base
import ../../bendlib/stdlib.bend as Std
import ./SPACE.bend as Space
import ./space-laws.bend as SpaceLaws
import ./PROGRAM.bend as Allocation
import ./physical-packing-rules.bend as Rule
import ./space-proof.bend as SpaceProof

def rigid_chosen(+dimension: Space.Dimension, +room: Nat) -> Rule.rigid_extent(dimension, Space.choose(dimension, room)):
  match dimension:
    case Space.Rigid{extent}: {==}
    case Space.Fit{minimum, extra, maximum}: Unit{}
    case Space.Fill{minimum}: Unit{}

def rigid_prefix(~A: Data, +value: A, +dimension: Space.Dimension, +rest: +List<Space.Slot<A>>, +offset: Nat, +room: Nat,
  +result: Space.Allocation<A>, proof: Rule.allocation_rigid_extents(~A, rest, result)) ->
  Rule.allocation_rigid_extents(~A, Space.Slot{value, dimension} <> rest,
    Space.prepend(~A, Space.Placement{value, offset, Space.choose(dimension, room)}, result)):
  Space.Allocation{placements, unused} = result
  (rigid_chosen(dimension, room), proof)

def rigid_place(~A: Data, +slots: +List<Space.Slot<A>>, +gap: Nat, +offset: Nat, +budget: Nat) ->
  Rule.allocation_rigid_extents(~A, slots, Space.place_from(~A, slots, gap, offset, budget)):
  match slots:
    case Nil{}: Unit{}
    case Con{Space.Slot{+value, +dimension}, +rest}:
      +room = Nat.sub(budget, Space.reservation(~A, rest, gap))
      +size = Space.choose(dimension, room)
      +between = Space.following_gap(~A, rest, gap)
      rigid_prefix(~A, value, dimension, rest, offset, room,
        Space.place_from(~A, rest, gap, Nat.add(offset, Nat.add(size, between)), Nat.sub(Nat.sub(budget, size), between)),
        rigid_place(~A, rest, gap, Nat.add(offset, Nat.add(size, between)), Nat.sub(Nat.sub(budget, size), between)))

def Rule.rigid_placement(A, slots, gap, offset, budget): rigid_place(~A, slots, gap, offset, budget)

# This projection recovers authored slots from the tagged first allocation.
def original_slots(~A: Data, placements: +List<Space.Placement<Allocation.Tagged<A>>>) -> +List<Space.Slot<A>>:
  match placements:
    case Nil{}: Nil{}
    case Con{Space.Placement{Allocation.Tagged{value, original}, offset, extent}, rest}:
      Space.Slot{value, original} <> original_slots(~A, rest)

def allocation_original(~A: Data, result: Space.Allocation<Allocation.Tagged<A>>) -> +List<Space.Slot<A>>:
  Space.Allocation{placements, unused} = result
  original_slots(~A, placements)

def original_prefix(~A: Data, +value: A, +dimension: Space.Dimension, +offset: Nat, +extent: Nat,
  +result: Space.Allocation<Allocation.Tagged<A>>, +rest: +List<Space.Slot<A>>,
  +proof: {allocation_original(~A, result) == rest : +List<Space.Slot<A>>}) ->
  {allocation_original(~A, Space.prepend(~Allocation.Tagged<A>, Space.Placement{Allocation.Tagged{value, dimension}, offset, extent}, result)) ==
    Space.Slot{value, dimension} <> rest : +List<Space.Slot<A>>}:
  Space.Allocation{placements, unused} = result
  Equal.cong(+List<Space.Slot<A>>, +List<Space.Slot<A>>, (tail => Space.Slot{value, dimension} <> tail), original_slots(~A, placements), rest, proof)

def original_place(~A: Data, +slots: +List<Space.Slot<A>>, +gap: Nat, +offset: Nat, +budget: Nat) ->
  {allocation_original(~A, Space.place_from(~Allocation.Tagged<A>, Allocation.freeze_slots(~A, slots), gap, offset, budget)) == slots : +List<Space.Slot<A>>}:
  match slots:
    case Nil{}: {==}
    case Con{Space.Slot{+value, +dimension}, +rest}:
      +frozen = Allocation.freeze_slots(~A, rest)
      +size = Space.choose(Allocation.frozen_dimension(dimension), Nat.sub(budget, Space.reservation(~Allocation.Tagged<A>, frozen, gap)))
      +between = Space.following_gap(~Allocation.Tagged<A>, frozen, gap)
      original_prefix(~A, value, dimension, offset, size,
        Space.place_from(~Allocation.Tagged<A>, frozen, gap, Nat.add(offset, Nat.add(size, between)), Nat.sub(Nat.sub(budget, size), between)), rest,
        original_place(~A, rest, gap, Nat.add(offset, Nat.add(size, between)), Nat.sub(Nat.sub(budget, size), between)))

def dimension_limit(+dimension: Space.Dimension, +extent: Nat) -> Bool:
  Nat.is_le(Space.minimum(dimension), extent) && (SpaceLaws.maximum_ok(dimension, extent) && SpaceLaws.rigid_ok(dimension, extent))

def and_left(+a: Bool, +b: Bool, proof: {Bool.and(a, b) == True{} : Bool}) -> {a == True{} : Bool}:
  SpaceProof.first({a == True{} : Bool}, {b == True{} : Bool}, SpaceProof.and_parts(a, b, proof))

def and_right(+a: Bool, +b: Bool, proof: {Bool.and(a, b) == True{} : Bool}) -> {b == True{} : Bool}:
  SpaceProof.second({a == True{} : Bool}, {b == True{} : Bool}, SpaceProof.and_parts(a, b, proof))

def extended_limit(+dimension: Space.Dimension, +extent: Nat, +share: Nat, +remaining: Nat,
  +proof: {dimension_limit(Allocation.frozen_dimension(dimension), extent) == True{} : Bool}) ->
  {dimension_limit(dimension, Allocation.shared_extent(dimension, extent, share, remaining)) == True{} : Bool}:
  match dimension:
    case Space.Rigid{declared}: proof
    case Space.Fit{minimum, extra, maximum}: proof
    case Space.Fill{minimum}:
      +lower = and_left(Nat.is_le(minimum, extent),
        SpaceLaws.maximum_ok(Space.Rigid{minimum}, extent) && SpaceLaws.rigid_ok(Space.Rigid{minimum}, extent), proof)
      SpaceProof.and_join(Nat.is_le(minimum, Nat.add(extent, Nat.add(share, Allocation.surplus_extra(remaining)))), True{},
        SpaceProof.le_trans(minimum, extent, Nat.add(extent, Nat.add(share, Allocation.surplus_extra(remaining))), lower,
          SpaceProof.le_add(extent, Nat.add(share, Allocation.surplus_extra(remaining)))), {==})

def bounds_prefix(~A: Data, +value: A, +dimension: Space.Dimension, +rest: +List<Space.Slot<A>>, +offset: Nat, +extent: Nat,
  +result: Space.Allocation<A>, +head: {dimension_limit(dimension, extent) == True{} : Bool},
  tail: {SpaceLaws.allocated_limits(~A, rest, result) == True{} : Bool}) ->
  {SpaceLaws.allocated_limits(~A, Space.Slot{value, dimension} <> rest,
    Space.prepend(~A, Space.Placement{value, offset, extent}, result)) == True{} : Bool}:
  Space.Allocation{+placements, unused} = result
  +lower = and_left(Nat.is_le(Space.minimum(dimension), extent),
    SpaceLaws.maximum_ok(dimension, extent) && SpaceLaws.rigid_ok(dimension, extent), head)
  +rest_head = and_right(Nat.is_le(Space.minimum(dimension), extent),
    SpaceLaws.maximum_ok(dimension, extent) && SpaceLaws.rigid_ok(dimension, extent), head)
  +upper = and_left(SpaceLaws.maximum_ok(dimension, extent), SpaceLaws.rigid_ok(dimension, extent), rest_head)
  +rigid = and_right(SpaceLaws.maximum_ok(dimension, extent), SpaceLaws.rigid_ok(dimension, extent), rest_head)
  SpaceProof.and_join(Nat.is_le(Space.minimum(dimension), extent),
    SpaceLaws.maximum_ok(dimension, extent) && (SpaceLaws.rigid_ok(dimension, extent) && SpaceLaws.limits(~A, rest, placements)), lower,
    SpaceProof.and_join(SpaceLaws.maximum_ok(dimension, extent), SpaceLaws.rigid_ok(dimension, extent) && SpaceLaws.limits(~A, rest, placements), upper,
      SpaceProof.and_join(SpaceLaws.rigid_ok(dimension, extent), SpaceLaws.limits(~A, rest, placements), rigid, tail)))

def thawed_bounds(~A: Data, +placements: +List<Space.Placement<Allocation.Tagged<A>>>, +gap: Nat, +offset: Nat, +budget: Nat,
  +share: Nat, +remaining: Nat,
  +proof: {SpaceLaws.limits(~Allocation.Tagged<A>, Allocation.freeze_slots(~A, original_slots(~A, placements)), placements) == True{} : Bool}) ->
  {SpaceLaws.allocated_limits(~A, original_slots(~A, placements),
    Space.place_from(~A, Allocation.thaw_slots(~A, placements, share, remaining), gap, offset, budget)) == True{} : Bool}:
  match placements:
    case Nil{}: {==}
    case Con{Space.Placement{Allocation.Tagged{+value, +dimension}, previous_offset, +extent}, +rest}:
      +frozen = Allocation.frozen_dimension(dimension)
      +frozen_rest = Allocation.freeze_slots(~A, original_slots(~A, rest))
      +tail_limits = SpaceLaws.limits(~Allocation.Tagged<A>, frozen_rest, rest)
      +lower = and_left(Nat.is_le(Space.minimum(frozen), extent),
        SpaceLaws.maximum_ok(frozen, extent) && (SpaceLaws.rigid_ok(frozen, extent) && tail_limits), proof)
      +further = and_right(Nat.is_le(Space.minimum(frozen), extent),
        SpaceLaws.maximum_ok(frozen, extent) && (SpaceLaws.rigid_ok(frozen, extent) && tail_limits), proof)
      +upper = and_left(SpaceLaws.maximum_ok(frozen, extent), SpaceLaws.rigid_ok(frozen, extent) && tail_limits, further)
      +rigid_tail = and_right(SpaceLaws.maximum_ok(frozen, extent), SpaceLaws.rigid_ok(frozen, extent) && tail_limits, further)
      +rigid = and_left(SpaceLaws.rigid_ok(frozen, extent), tail_limits, rigid_tail)
      +tail = and_right(SpaceLaws.rigid_ok(frozen, extent), tail_limits, rigid_tail)
      +first_bound = SpaceProof.and_join(Nat.is_le(Space.minimum(frozen), extent),
        SpaceLaws.maximum_ok(frozen, extent) && SpaceLaws.rigid_ok(frozen, extent), lower,
        SpaceProof.and_join(SpaceLaws.maximum_ok(frozen, extent), SpaceLaws.rigid_ok(frozen, extent), upper, rigid))
      +size = Allocation.shared_extent(dimension, extent, share, remaining)
      +next_remaining = Allocation.next_remainder(dimension, remaining)
      +thawed_rest = Allocation.thaw_slots(~A, rest, share, next_remaining)
      +between = Space.following_gap(~A, thawed_rest, gap)
      +next_offset = Nat.add(offset, Nat.add(size, between))
      +next_budget = Nat.sub(Nat.sub(budget, size), between)
      bounds_prefix(~A, value, dimension, original_slots(~A, rest), offset, size,
        Space.place_from(~A, thawed_rest, gap, next_offset, next_budget), extended_limit(dimension, extent, share, remaining, first_bound),
        thawed_bounds(~A, rest, gap, next_offset, next_budget, share, next_remaining, tail))

def thaw_values(~A: Data, +placements: +List<Space.Placement<Allocation.Tagged<A>>>, +share: Nat, +remaining: Nat) ->
  {SpaceLaws.slot_values(~A, Allocation.thaw_slots(~A, placements, share, remaining)) == SpaceLaws.slot_values(~A, original_slots(~A, placements)) : +List<A>}:
  match placements:
    case Nil{}: {==}
    case Con{Space.Placement{Allocation.Tagged{+value, +dimension}, offset, extent}, rest}:
      Equal.cong(+List<A>, +List<A>, (tail => value <> tail),
        SpaceLaws.slot_values(~A, Allocation.thaw_slots(~A, rest, share, Allocation.next_remainder(dimension, remaining))),
        SpaceLaws.slot_values(~A, original_slots(~A, rest)), thaw_values(~A, rest, share, Allocation.next_remainder(dimension, remaining)))

def restored_allocation(~A: Data, +placements: +List<Space.Placement<Allocation.Tagged<A>>>, +share: Nat, +remaining: Nat,
  +gap: Nat, +available: Nat, +result: Space.Allocation<A>,
  proof: SpaceLaws.AllocationEvidence<A, Allocation.thaw_slots(~A, placements, share, remaining), gap, 0n, available, result>,
  bounds: {SpaceLaws.allocated_limits(~A, original_slots(~A, placements), result) == True{} : Bool}) ->
  SpaceLaws.AllocationEvidence<A, original_slots(~A, placements), gap, 0n, available, result>:
  SpaceLaws.AllocationEvidence{payloads, rigid_bounds, order, budget} = proof
  SpaceLaws.AllocationEvidence{
    Equal.trans(+List<A>, SpaceLaws.allocated_values(~A, result),
      SpaceLaws.slot_values(~A, Allocation.thaw_slots(~A, placements, share, remaining)), SpaceLaws.slot_values(~A, original_slots(~A, placements)),
      payloads, thaw_values(~A, placements, share, remaining)), bounds, order, budget}

def finish_shared(~A: Data, +slots: +List<Space.Slot<A>>, +gap: Nat, +available: Nat, +result: Space.Allocation<A>,
  proof: SpaceLaws.AllocationEvidence<A, slots, gap, 0n, available, result>) ->
  Rule.SharedClaim(~A, slots, gap, available, Space.finish(~A, result)):
  Space.Allocation{placements, unused} = result
  proof


# Recover successful pack evidence through the allocator's complete feasibility law.
def unpack_complete(~A: Data, +slots: +List<Space.Slot<A>>, +gap: Nat, +available: Nat, +result: Space.Allocation<A>,
  proof: SpaceLaws.PackedClaim(~A, slots, gap, available, Space.finish(~A, result))) ->
  SpaceLaws.AllocationEvidence<A, slots, gap, 0n, available, result>:
  Space.Allocation{placements, unused} = result
  proof

def feasibility(~A: Data, requirements: SpaceLaws.Requirements<A>, +slots: +List<Space.Slot<A>>, +gap: Nat, +available: Nat) ->
  {SpaceLaws.packed(~A, Space.pack(~A, slots, gap, available)) == Nat.is_le(Space.minimum_sequence(~A, slots, gap), available) : Bool}:
  SpaceLaws.Requirements{larger, smaller, minimum, maximum, complete, insufficient, construction} = requirements
  complete(slots, gap, available)

def complete_place(~A: Data, +slots: +List<Space.Slot<A>>, +gap: Nat, +available: Nat,
  +fits: {Nat.is_le(Space.minimum_sequence(~A, slots, gap), available) == True{} : Bool}) ->
  SpaceLaws.AllocationEvidence<A, slots, gap, 0n, available, Space.place_from(~A, slots, gap, 0n, available)>:
  +complete_equation = feasibility(~A, SpaceLaws.evidence(~A), slots, gap, available)
  +success = Equal.trans(Bool, SpaceLaws.packed(~A, Space.pack(~A, slots, gap, available)),
    Nat.is_le(Space.minimum_sequence(~A, slots, gap), available), True{}, complete_equation, fits)
  +recovered = Equal.trans(Bool, Nat.is_le(Space.minimum_sequence(~A, slots, gap), available),
    SpaceLaws.packed(~A, Space.pack(~A, slots, gap, available)), True{},
    Equal.sym(Bool, SpaceLaws.packed(~A, Space.pack(~A, slots, gap, available)),
      Nat.is_le(Space.minimum_sequence(~A, slots, gap), available), complete_equation), success)
  +finished = Space.finish(~A, Space.place_from(~A, slots, gap, 0n, available))
  +same = Equal.cong(Bool, Space.Packing<A>, (feasible => Space.feasible_pack(~A, feasible, slots, gap, available)),
    Nat.is_le(Space.minimum_sequence(~A, slots, gap), available), True{}, fits)
  unpack_complete(~A, slots, gap, available, Space.place_from(~A, slots, gap, 0n, available),
    Std.transport(Space.Packing<A>, Space.pack(~A, slots, gap, available),
      (result => SpaceLaws.PackedClaim(~A, slots, gap, available, result)),
      SpaceProof.pack_complete(~A, slots, gap, available, recovered), finished,
      Equal.sym(Space.Packing<A>, Space.pack(~A, slots, gap, available), finished, same)))

def restored_feasible(~A: Data, +fits: Bool, +placements: +List<Space.Placement<Allocation.Tagged<A>>>, +share: Nat, +remaining: Nat,
  +gap: Nat, +available: Nat,
  +equation: {Nat.is_le(Space.minimum_sequence(~A, Allocation.thaw_slots(~A, placements, share, remaining), gap), available) == fits : Bool},
  first_bounds: {SpaceLaws.limits(~Allocation.Tagged<A>, Allocation.freeze_slots(~A, original_slots(~A, placements)), placements) == True{} : Bool}) ->
  Rule.SharedClaim(~A, original_slots(~A, placements), gap, available,
    Space.feasible_pack(~A, fits, Allocation.thaw_slots(~A, placements, share, remaining), gap, available)):
  match fits:
    case False{}: Unit{}
    case True{}:
      finish_shared(~A, original_slots(~A, placements), gap, available,
        Space.place_from(~A, Allocation.thaw_slots(~A, placements, share, remaining), gap, 0n, available),
        restored_allocation(~A, placements, share, remaining, gap, available,
          Space.place_from(~A, Allocation.thaw_slots(~A, placements, share, remaining), gap, 0n, available),
          complete_place(~A, Allocation.thaw_slots(~A, placements, share, remaining), gap, available, equation),
          thawed_bounds(~A, placements, gap, 0n, available, share, remaining, first_bounds)))

def restored_pack(~A: Data, +placements: +List<Space.Placement<Allocation.Tagged<A>>>, +share: Nat, +remaining: Nat,
  +gap: Nat, +available: Nat,
  first_bounds: {SpaceLaws.limits(~Allocation.Tagged<A>, Allocation.freeze_slots(~A, original_slots(~A, placements)), placements) == True{} : Bool}) ->
  Rule.SharedClaim(~A, original_slots(~A, placements), gap, available,
    Space.pack(~A, Allocation.thaw_slots(~A, placements, share, remaining), gap, available)):
  restored_feasible(~A, Nat.is_le(Space.minimum_sequence(~A, Allocation.thaw_slots(~A, placements, share, remaining), gap), available),
    placements, share, remaining, gap, available, {==}, first_bounds)

def redistribution_claim(~A: Data, +selector: Bool, +count: Nat, +placements: +List<Space.Placement<Allocation.Tagged<A>>>,
  +unused: Nat, +gap: Nat, +available: Nat,
  first_bounds: {SpaceLaws.limits(~Allocation.Tagged<A>, Allocation.freeze_slots(~A, original_slots(~A, placements)), placements) == True{} : Bool}) ->
  Rule.SharedClaim(~A, original_slots(~A, placements), gap, available,
    Allocation.dispatch_redistribute_2(~A, selector, count, placements, unused, gap, available)):
  match selector:
    case True{}: restored_pack(~A, placements, 0n, 0n, gap, available, first_bounds)
    case False{}: restored_pack(~A, placements, Nat.div(unused, count), Nat.sub(unused, Nat.mul(Nat.div(unused, count), count)), gap, available, first_bounds)

def first_allocation_claim(~A: Data, +slots: +List<Space.Slot<A>>, +count: Nat, +gap: Nat, +available: Nat,
  +first: Space.Allocation<Allocation.Tagged<A>>,
  proof: SpaceLaws.AllocationEvidence<Allocation.Tagged<A>, Allocation.freeze_slots(~A, slots), gap, 0n, available, first>,
  +original: {allocation_original(~A, first) == slots : +List<Space.Slot<A>>}) ->
  Rule.SharedClaim(~A, slots, gap, available, Allocation.redistribute(~A, count, Space.finish(~Allocation.Tagged<A>, first), gap, available)):
  Space.Allocation{+placements, +unused} = first
  SpaceLaws.AllocationEvidence{payloads, bounds, order, budget} = proof
  +source = original_slots(~A, placements)
  +self_bounds = Std.transport(+List<Space.Slot<A>>, slots,
    (sources => {SpaceLaws.limits(~Allocation.Tagged<A>, Allocation.freeze_slots(~A, sources), placements) == True{} : Bool}),
    bounds, source, original)
  Std.transport(+List<Space.Slot<A>>, source,
    (sources => Rule.SharedClaim(~A, sources, gap, available,
      Allocation.dispatch_redistribute_2(~A, Nat.is_eq(count, 0n), count, placements, unused, gap, available))),
    redistribution_claim(~A, Nat.is_eq(count, 0n), count, placements, unused, gap, available, self_bounds), slots,
    Equal.sym(+List<Space.Slot<A>>, source, slots, original))

def first_feasible(~A: Data, +fits: Bool, +slots: +List<Space.Slot<A>>, +gap: Nat, +available: Nat,
  +equation: {Nat.is_le(Space.minimum_sequence(~Allocation.Tagged<A>, Allocation.freeze_slots(~A, slots), gap), available) == fits : Bool}) ->
  Rule.SharedClaim(~A, slots, gap, available,
    Allocation.redistribute(~A, Allocation.fill_count(~A, slots),
      Space.feasible_pack(~Allocation.Tagged<A>, fits, Allocation.freeze_slots(~A, slots), gap, available), gap, available)):
  match fits:
    case False{}: Unit{}
    case True{}:
      first_allocation_claim(~A, slots, Allocation.fill_count(~A, slots), gap, available,
        Space.place_from(~Allocation.Tagged<A>, Allocation.freeze_slots(~A, slots), gap, 0n, available),
        complete_place(~Allocation.Tagged<A>, Allocation.freeze_slots(~A, slots), gap, available, equation),
        original_place(~A, slots, gap, 0n, available))

def Rule.shared_packing(A, slots, gap, available):
  first_feasible(~A, Nat.is_le(Space.minimum_sequence(~Allocation.Tagged<A>, Allocation.freeze_slots(~A, slots), gap), available), slots, gap, available, {==})
