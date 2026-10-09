import Base
import ../../bendlib/logic-proof.bend as Logic
import ./geometry-proof.bend as ProofGeometryProof
import ../../bendlib/stdlib.bend as Std
import ./SPACE.bend as Space
import ./allocation-contract.bend as RulePhysicalSourceRules
import ./PROGRAM.bend as Allocation
import ./geometry-contract.bend as Rule
import ./physical-space.bend as Model
import ./GEOMETRY.bend as SpatialModel
import ./enclosure.bend as E

def subtract_zero(+value: Nat) -> {Nat.sub(value, 0n) == value : Nat}:
  match value:
    case 0n: {==}
    case 1n+rest: {==}

# These two bridges concern the saturating predecessor at the exact budget boundary.

def rank_at_zero(+value: Nat,
  enough: {Nat.is_le(value, 0n) == True{} : Bool}) -> {value == 0n : Nat}:
  match value:
    case 0n: {==}
    case 1n+rest: Logic.impossible({1n+rest == 0n : Nat}, enough)

def predecessor_in_budget(+value: Nat, +budget: Nat,
  enough: {Nat.is_le(value, 1n+budget) == True{} : Bool}) ->
  {Nat.is_le(Nat.sub(value, 1n), budget) == True{} : Bool}:
  match value:
    case 0n: ProofGeometryProof.zero_le(budget)
    case 1n+rest:
      Std.transport(Nat, rest, (predecessor => {Nat.is_le(predecessor, budget) == True{} : Bool}),
        enough, Nat.sub(rest, 0n), subtract_zero(rest))

# The closed decrease theorem is reusable inside the compile-time induction callbacks.

def iterate_rank_zero(~S: Data, ~step: S -> S, ~rank: S -> Nat,
  ~decreases: @+state:S -> {Nat.is_le(rank(step(state)), Nat.sub(rank(state), 1n)) == True{} : Bool},
  +seed: S, +budget: Nat,
  enough: {Nat.is_le(rank(seed), budget) == True{} : Bool}) ->
  {rank(Std.iter(~S, ~step, budget, seed)) == 0n : Nat}:
  Std.nat_ind(~(count =>
      @+initial:S ->
      @fits:{Nat.is_le(rank(initial), count) == True{} : Bool} ->
      {rank(Std.iter(~S, ~step, count, initial)) == 0n : Nat}),
    ~(initial => fits => rank_at_zero(rank(initial), fits)),
    ~(count => induction => initial => fits =>
      Equal.trans(Nat,
        rank(Std.iter(~S, ~step, 1n+count, initial)),
        rank(Std.iter(~S, ~step, count, step(initial))), 0n,
        Equal.cong(S, Nat, rank,
          Std.iter(~S, ~step, 1n+count, initial),
          Std.iter(~S, ~step, count, step(initial)),
          Equal.trans(S,
            Std.iter(~S, ~step, 1n+count, initial),
            step(Std.iter(~S, ~step, count, initial)),
            Std.iter(~S, ~step, count, step(initial)),
            Std.iter_add(~S, ~step, 1n, count, initial),
            Std.iter_swap_gen(~S, ~S, ~step, ~step, ~step, ~(state => {==}), count, initial))),
        induction(step(initial),
          ProofGeometryProof.le_trans(rank(step(initial)), Nat.sub(rank(initial), 1n), count,
            decreases(initial), predecessor_in_budget(rank(initial), count, fits))))),
    budget)(seed, enough)

def rigid_chosen(+dimension: Space.Dimension, +room: Nat) -> RulePhysicalSourceRules.rigid_extent(dimension, Space.choose(dimension, room)):
  match dimension:
    case Space.Rigid{extent}: {==}
    case Space.Fit{minimum, extra, maximum}: Unit{}
    case Space.Fill{minimum}: Unit{}

def rigid_prefix(~A: Data, +value: A, +dimension: Space.Dimension, +rest: +List<Space.Slot<A>>, +offset: Nat, +room: Nat,
  +result: Space.Allocation<A>, proof: RulePhysicalSourceRules.allocation_rigid_extents(~A, rest, result)) ->
  RulePhysicalSourceRules.allocation_rigid_extents(~A, Space.Slot{value, dimension} <> rest,
    Space.prepend(~A, Space.Placement{value, offset, Space.choose(dimension, room)}, result)):
  Space.Allocation{placements, unused} = result
  (rigid_chosen(dimension, room), proof)

def rigid_place(~A: Data, +slots: +List<Space.Slot<A>>, +gap: Nat, +offset: Nat, +budget: Nat) ->
  RulePhysicalSourceRules.allocation_rigid_extents(~A, slots, Space.place_from(~A, slots, gap, offset, budget)):
  match slots:
    case Nil{}: Unit{}
    case Con{Space.Slot{+value, +dimension}, +rest}:
      +room = Nat.sub(budget, Space.reservation(~A, rest, gap))
      +size = Space.choose(dimension, room)
      +between = Space.following_gap(~A, rest, gap)
      rigid_prefix(~A, value, dimension, rest, offset, room,
        Space.place_from(~A, rest, gap, Nat.add(offset, Nat.add(size, between)), Nat.sub(Nat.sub(budget, size), between)),
        rigid_place(~A, rest, gap, Nat.add(offset, Nat.add(size, between)), Nat.sub(Nat.sub(budget, size), between)))

def RulePhysicalSourceRules.rigid_placement(A, slots, gap, offset, budget): rigid_place(~A, slots, gap, offset, budget)

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
  Nat.is_le(Space.minimum(dimension), extent) && (Rule.maximum_ok(dimension, extent) && Rule.rigid_ok(dimension, extent))

def physical_packing_proof_and_left(+a: Bool, +b: Bool, proof: {Bool.and(a, b) == True{} : Bool}) -> {a == True{} : Bool}:
  ProofGeometryProof.first({a == True{} : Bool}, {b == True{} : Bool}, ProofGeometryProof.and_parts(a, b, proof))

def physical_packing_proof_and_right(+a: Bool, +b: Bool, proof: {Bool.and(a, b) == True{} : Bool}) -> {b == True{} : Bool}:
  ProofGeometryProof.second({a == True{} : Bool}, {b == True{} : Bool}, ProofGeometryProof.and_parts(a, b, proof))

def extended_limit(+dimension: Space.Dimension, +extent: Nat, +share: Nat, +remaining: Nat,
  +proof: {dimension_limit(Allocation.frozen_dimension(dimension), extent) == True{} : Bool}) ->
  {dimension_limit(dimension, Allocation.shared_extent(dimension, extent, share, remaining)) == True{} : Bool}:
  match dimension:
    case Space.Rigid{declared}: proof
    case Space.Fit{minimum, extra, maximum}: proof
    case Space.Fill{minimum}:
      +lower = physical_packing_proof_and_left(Nat.is_le(minimum, extent),
        Rule.maximum_ok(Space.Rigid{minimum}, extent) && Rule.rigid_ok(Space.Rigid{minimum}, extent), proof)
      ProofGeometryProof.and_join(Nat.is_le(minimum, Nat.add(extent, Nat.add(share, Allocation.surplus_extra(remaining)))), True{},
        ProofGeometryProof.le_trans(minimum, extent, Nat.add(extent, Nat.add(share, Allocation.surplus_extra(remaining))), lower,
          ProofGeometryProof.le_add(extent, Nat.add(share, Allocation.surplus_extra(remaining)))), {==})

def bounds_prefix(~A: Data, +value: A, +dimension: Space.Dimension, +rest: +List<Space.Slot<A>>, +offset: Nat, +extent: Nat,
  +result: Space.Allocation<A>, +head: {dimension_limit(dimension, extent) == True{} : Bool},
  tail: {Rule.allocated_limits(~A, rest, result) == True{} : Bool}) ->
  {Rule.allocated_limits(~A, Space.Slot{value, dimension} <> rest,
    Space.prepend(~A, Space.Placement{value, offset, extent}, result)) == True{} : Bool}:
  Space.Allocation{+placements, unused} = result
  +lower = physical_packing_proof_and_left(Nat.is_le(Space.minimum(dimension), extent),
    Rule.maximum_ok(dimension, extent) && Rule.rigid_ok(dimension, extent), head)
  +rest_head = physical_packing_proof_and_right(Nat.is_le(Space.minimum(dimension), extent),
    Rule.maximum_ok(dimension, extent) && Rule.rigid_ok(dimension, extent), head)
  +upper = physical_packing_proof_and_left(Rule.maximum_ok(dimension, extent), Rule.rigid_ok(dimension, extent), rest_head)
  +rigid = physical_packing_proof_and_right(Rule.maximum_ok(dimension, extent), Rule.rigid_ok(dimension, extent), rest_head)
  ProofGeometryProof.and_join(Nat.is_le(Space.minimum(dimension), extent),
    Rule.maximum_ok(dimension, extent) && (Rule.rigid_ok(dimension, extent) && Rule.limits(~A, rest, placements)), lower,
    ProofGeometryProof.and_join(Rule.maximum_ok(dimension, extent), Rule.rigid_ok(dimension, extent) && Rule.limits(~A, rest, placements), upper,
      ProofGeometryProof.and_join(Rule.rigid_ok(dimension, extent), Rule.limits(~A, rest, placements), rigid, tail)))

def thawed_bounds(~A: Data, +placements: +List<Space.Placement<Allocation.Tagged<A>>>, +gap: Nat, +offset: Nat, +budget: Nat,
  +share: Nat, +remaining: Nat,
  +proof: {Rule.limits(~Allocation.Tagged<A>, Allocation.freeze_slots(~A, original_slots(~A, placements)), placements) == True{} : Bool}) ->
  {Rule.allocated_limits(~A, original_slots(~A, placements),
    Space.place_from(~A, Allocation.thaw_slots(~A, placements, share, remaining), gap, offset, budget)) == True{} : Bool}:
  match placements:
    case Nil{}: {==}
    case Con{Space.Placement{Allocation.Tagged{+value, +dimension}, previous_offset, +extent}, +rest}:
      +frozen = Allocation.frozen_dimension(dimension)
      +frozen_rest = Allocation.freeze_slots(~A, original_slots(~A, rest))
      +tail_limits = Rule.limits(~Allocation.Tagged<A>, frozen_rest, rest)
      +lower = physical_packing_proof_and_left(Nat.is_le(Space.minimum(frozen), extent),
        Rule.maximum_ok(frozen, extent) && (Rule.rigid_ok(frozen, extent) && tail_limits), proof)
      +further = physical_packing_proof_and_right(Nat.is_le(Space.minimum(frozen), extent),
        Rule.maximum_ok(frozen, extent) && (Rule.rigid_ok(frozen, extent) && tail_limits), proof)
      +upper = physical_packing_proof_and_left(Rule.maximum_ok(frozen, extent), Rule.rigid_ok(frozen, extent) && tail_limits, further)
      +rigid_tail = physical_packing_proof_and_right(Rule.maximum_ok(frozen, extent), Rule.rigid_ok(frozen, extent) && tail_limits, further)
      +rigid = physical_packing_proof_and_left(Rule.rigid_ok(frozen, extent), tail_limits, rigid_tail)
      +tail = physical_packing_proof_and_right(Rule.rigid_ok(frozen, extent), tail_limits, rigid_tail)
      +first_bound = ProofGeometryProof.and_join(Nat.is_le(Space.minimum(frozen), extent),
        Rule.maximum_ok(frozen, extent) && Rule.rigid_ok(frozen, extent), lower,
        ProofGeometryProof.and_join(Rule.maximum_ok(frozen, extent), Rule.rigid_ok(frozen, extent), upper, rigid))
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
  {Rule.slot_values(~A, Allocation.thaw_slots(~A, placements, share, remaining)) == Rule.slot_values(~A, original_slots(~A, placements)) : +List<A>}:
  match placements:
    case Nil{}: {==}
    case Con{Space.Placement{Allocation.Tagged{+value, +dimension}, offset, extent}, rest}:
      Equal.cong(+List<A>, +List<A>, (tail => value <> tail),
        Rule.slot_values(~A, Allocation.thaw_slots(~A, rest, share, Allocation.next_remainder(dimension, remaining))),
        Rule.slot_values(~A, original_slots(~A, rest)), thaw_values(~A, rest, share, Allocation.next_remainder(dimension, remaining)))

def restored_allocation(~A: Data, +placements: +List<Space.Placement<Allocation.Tagged<A>>>, +share: Nat, +remaining: Nat,
  +gap: Nat, +available: Nat, +result: Space.Allocation<A>,
  proof: Rule.AllocationEvidence<A, Allocation.thaw_slots(~A, placements, share, remaining), gap, 0n, available, result>,
  bounds: {Rule.allocated_limits(~A, original_slots(~A, placements), result) == True{} : Bool}) ->
  Rule.AllocationEvidence<A, original_slots(~A, placements), gap, 0n, available, result>:
  Rule.AllocationEvidence{payloads, rigid_bounds, order, budget} = proof
  Rule.AllocationEvidence{
    Equal.trans(+List<A>, Rule.allocated_values(~A, result),
      Rule.slot_values(~A, Allocation.thaw_slots(~A, placements, share, remaining)), Rule.slot_values(~A, original_slots(~A, placements)),
      payloads, thaw_values(~A, placements, share, remaining)), bounds, order, budget}

def finish_shared(~A: Data, +slots: +List<Space.Slot<A>>, +gap: Nat, +available: Nat, +result: Space.Allocation<A>,
  proof: Rule.AllocationEvidence<A, slots, gap, 0n, available, result>) ->
  RulePhysicalSourceRules.SharedClaim(~A, slots, gap, available, Space.finish(~A, result)):
  Space.Allocation{placements, unused} = result
  proof


# Recover successful pack evidence through the allocator's complete feasibility law.

def unpack_complete(~A: Data, +slots: +List<Space.Slot<A>>, +gap: Nat, +available: Nat, +result: Space.Allocation<A>,
  proof: Rule.PackedClaim(~A, slots, gap, available, Space.finish(~A, result))) ->
  Rule.AllocationEvidence<A, slots, gap, 0n, available, result>:
  Space.Allocation{placements, unused} = result
  proof

def feasibility(~A: Data, requirements: Rule.SpaceRequirements<A>, +slots: +List<Space.Slot<A>>, +gap: Nat, +available: Nat) ->
  {Rule.packed(~A, Space.pack(~A, slots, gap, available)) == Nat.is_le(Space.minimum_sequence(~A, slots, gap), available) : Bool}:
  Rule.SpaceRequirements{larger, smaller, minimum, maximum, complete, insufficient, construction} = requirements
  complete(slots, gap, available)

def complete_place(~A: Data, +slots: +List<Space.Slot<A>>, +gap: Nat, +available: Nat,
  +fits: {Nat.is_le(Space.minimum_sequence(~A, slots, gap), available) == True{} : Bool}) ->
  Rule.AllocationEvidence<A, slots, gap, 0n, available, Space.place_from(~A, slots, gap, 0n, available)>:
  +complete_equation = feasibility(~A, Rule.space_evidence(~A), slots, gap, available)
  +success = Equal.trans(Bool, Rule.packed(~A, Space.pack(~A, slots, gap, available)),
    Nat.is_le(Space.minimum_sequence(~A, slots, gap), available), True{}, complete_equation, fits)
  +recovered = Equal.trans(Bool, Nat.is_le(Space.minimum_sequence(~A, slots, gap), available),
    Rule.packed(~A, Space.pack(~A, slots, gap, available)), True{},
    Equal.sym(Bool, Rule.packed(~A, Space.pack(~A, slots, gap, available)),
      Nat.is_le(Space.minimum_sequence(~A, slots, gap), available), complete_equation), success)
  +finished = Space.finish(~A, Space.place_from(~A, slots, gap, 0n, available))
  +same = Equal.cong(Bool, Space.Packing<A>, (feasible => Space.feasible_pack(~A, feasible, slots, gap, available)),
    Nat.is_le(Space.minimum_sequence(~A, slots, gap), available), True{}, fits)
  unpack_complete(~A, slots, gap, available, Space.place_from(~A, slots, gap, 0n, available),
    Std.transport(Space.Packing<A>, Space.pack(~A, slots, gap, available),
      (result => Rule.PackedClaim(~A, slots, gap, available, result)),
      ProofGeometryProof.pack_complete(~A, slots, gap, available, recovered), finished,
      Equal.sym(Space.Packing<A>, Space.pack(~A, slots, gap, available), finished, same)))

def restored_feasible(~A: Data, +fits: Bool, +placements: +List<Space.Placement<Allocation.Tagged<A>>>, +share: Nat, +remaining: Nat,
  +gap: Nat, +available: Nat,
  +equation: {Nat.is_le(Space.minimum_sequence(~A, Allocation.thaw_slots(~A, placements, share, remaining), gap), available) == fits : Bool},
  first_bounds: {Rule.limits(~Allocation.Tagged<A>, Allocation.freeze_slots(~A, original_slots(~A, placements)), placements) == True{} : Bool}) ->
  RulePhysicalSourceRules.SharedClaim(~A, original_slots(~A, placements), gap, available,
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
  first_bounds: {Rule.limits(~Allocation.Tagged<A>, Allocation.freeze_slots(~A, original_slots(~A, placements)), placements) == True{} : Bool}) ->
  RulePhysicalSourceRules.SharedClaim(~A, original_slots(~A, placements), gap, available,
    Space.pack(~A, Allocation.thaw_slots(~A, placements, share, remaining), gap, available)):
  restored_feasible(~A, Nat.is_le(Space.minimum_sequence(~A, Allocation.thaw_slots(~A, placements, share, remaining), gap), available),
    placements, share, remaining, gap, available, {==}, first_bounds)

def redistribution_claim(~A: Data, +selector: Bool, +count: Nat, +placements: +List<Space.Placement<Allocation.Tagged<A>>>,
  +unused: Nat, +gap: Nat, +available: Nat,
  first_bounds: {Rule.limits(~Allocation.Tagged<A>, Allocation.freeze_slots(~A, original_slots(~A, placements)), placements) == True{} : Bool}) ->
  RulePhysicalSourceRules.SharedClaim(~A, original_slots(~A, placements), gap, available,
    Allocation.dispatch_redistribute_2(~A, selector, count, placements, unused, gap, available)):
  match selector:
    case True{}: restored_pack(~A, placements, 0n, 0n, gap, available, first_bounds)
    case False{}: restored_pack(~A, placements, Nat.div(unused, count), Nat.sub(unused, Nat.mul(Nat.div(unused, count), count)), gap, available, first_bounds)

def first_allocation_claim(~A: Data, +slots: +List<Space.Slot<A>>, +count: Nat, +gap: Nat, +available: Nat,
  +first: Space.Allocation<Allocation.Tagged<A>>,
  proof: Rule.AllocationEvidence<Allocation.Tagged<A>, Allocation.freeze_slots(~A, slots), gap, 0n, available, first>,
  +original: {allocation_original(~A, first) == slots : +List<Space.Slot<A>>}) ->
  RulePhysicalSourceRules.SharedClaim(~A, slots, gap, available, Allocation.redistribute(~A, count, Space.finish(~Allocation.Tagged<A>, first), gap, available)):
  Space.Allocation{+placements, +unused} = first
  Rule.AllocationEvidence{payloads, bounds, order, budget} = proof
  +source = original_slots(~A, placements)
  +self_bounds = Std.transport(+List<Space.Slot<A>>, slots,
    (sources => {Rule.limits(~Allocation.Tagged<A>, Allocation.freeze_slots(~A, sources), placements) == True{} : Bool}),
    bounds, source, original)
  Std.transport(+List<Space.Slot<A>>, source,
    (sources => RulePhysicalSourceRules.SharedClaim(~A, sources, gap, available,
      Allocation.dispatch_redistribute_2(~A, Nat.is_eq(count, 0n), count, placements, unused, gap, available))),
    redistribution_claim(~A, Nat.is_eq(count, 0n), count, placements, unused, gap, available, self_bounds), slots,
    Equal.sym(+List<Space.Slot<A>>, source, slots, original))

def first_feasible(~A: Data, +fits: Bool, +slots: +List<Space.Slot<A>>, +gap: Nat, +available: Nat,
  +equation: {Nat.is_le(Space.minimum_sequence(~Allocation.Tagged<A>, Allocation.freeze_slots(~A, slots), gap), available) == fits : Bool}) ->
  RulePhysicalSourceRules.SharedClaim(~A, slots, gap, available,
    Allocation.redistribute(~A, Allocation.fill_count(~A, slots),
      Space.feasible_pack(~Allocation.Tagged<A>, fits, Allocation.freeze_slots(~A, slots), gap, available), gap, available)):
  match fits:
    case False{}: Unit{}
    case True{}:
      first_allocation_claim(~A, slots, Allocation.fill_count(~A, slots), gap, available,
        Space.place_from(~Allocation.Tagged<A>, Allocation.freeze_slots(~A, slots), gap, 0n, available),
        complete_place(~Allocation.Tagged<A>, Allocation.freeze_slots(~A, slots), gap, available, equation),
        original_place(~A, slots, gap, 0n, available))

def RulePhysicalSourceRules.shared_packing(A, slots, gap, available):
  first_feasible(~A, Nat.is_le(Space.minimum_sequence(~Allocation.Tagged<A>, Allocation.freeze_slots(~A, slots), gap), available), slots, gap, available, {==})

def SlotsPopulation(~T: Data, +children: +List<T>, result: Allocation.SlotsOutcome<T>) -> Type:
  match result:
    case Allocation.SlotsReady{slots}: {Rule.slot_values(~T, slots) == children : +List<T>}
    case Allocation.SlotsFailure{failure}: {True{} == True{} : Bool}

def PlanPopulation(~T: Data, +children: +List<T>, result: Allocation.ChildPlan<T>) -> Type:
  match result:
    case Allocation.ChildrenPlanned{placements, canvas}: {Rule.placement_values(~T, placements) == children : +List<T>}
    case Allocation.PlanningFailure{failure}: {True{} == True{} : Bool}

def PackingPopulation(~T: Data, +children: +List<T>, result: Space.Packing<T>) -> Type:
  match result:
    case Space.Packed{placements, unused}: {Rule.placement_values(~T, placements) == children : +List<T>}
    case Space.Insufficient{required, available}: {True{} == True{} : Bool}

def prepend_population(~T: Data, +result: Allocation.SlotsOutcome<T>, +head: T, +tail: +List<T>, +dimension: Space.Dimension,
  proof: SlotsPopulation(~T, tail, result)) ->
  SlotsPopulation(~T, head <> tail, Allocation.prepend_slot(~T, Space.Slot{head, dimension}, result)):
  match result:
    case Allocation.SlotsFailure{failure}: {==}
    case Allocation.SlotsReady{slots}:
      Equal.cong(+List<T>, +List<T>, (values => head <> values), Rule.slot_values(~T, slots), tail, proof)

def materialized_population(~T: Data, +selector: Maybe<&2, Space.Dimension>, +head: T, +tail: +List<T>,
  +key: String, +axis: Allocation.Axis, +lower: Nat, +offered: Nat, +rest: Allocation.SlotsOutcome<T>,
  proof: SlotsPopulation(~T, tail, rest)) ->
  SlotsPopulation(~T, head <> tail, Allocation.materialized_slot(~T, selector, head, key, axis, lower, offered, rest)):
  match selector:
    case None{}: {==}
    case Some{dimension}: prepend_population(~T, rest, head, tail, dimension, proof)

def width_demand_population(~A: Data, ~E: Data, +demand: Space.Demand, +head: Model.Tree<A, E>,
  +tail: +List<Model.Tree<A, E>>, +offered: Nat, +rest: Allocation.SlotsOutcome<Model.Tree<A, E>>,
  proof: SlotsPopulation(~Model.Tree<A, E>, tail, rest)) ->
  SlotsPopulation(~Model.Tree<A, E>, head <> tail, Allocation.width_slot_demand(~A, ~E, demand, head, offered, rest)):
  Space.Demand{minimum, preferred} = demand
  materialized_population(~Model.Tree<A, E>,
    Model.materialize(Allocation.inline_size(Allocation.tree_rule(~A, ~E, head)), Allocation.axis_extent(Allocation.InlineAxis{}, minimum), Allocation.axis_extent(Allocation.InlineAxis{}, preferred), offered),
    head, tail, Allocation.tree_key(~A, ~E, head), Allocation.InlineAxis{}, Allocation.axis_extent(Allocation.InlineAxis{}, minimum), offered, rest, proof)

def width_population(~A: Data, ~E: Data, +children: +List<Model.Tree<A, E>>, +offered: Nat) ->
  SlotsPopulation(~Model.Tree<A, E>, children, Allocation.width_slots(~A, ~E, children, offered)):
  Std.list_ind(~Model.Tree<A, E>, ~(trees => @+available:Nat -> SlotsPopulation(~Model.Tree<A, E>, trees, Allocation.width_slots(~A, ~E, trees, available))),
    ~(+available => {==}), ~(+head => +tail => proof => +available => width_demand_population(~A, ~E, Model.demand(~A, ~E, head), head, tail, Nat.sub(available, Allocation.outside_axis(Allocation.InlineAxis{}, Allocation.tree_rule(~A, ~E, head))), Allocation.width_slots(~A, ~E, tail, available), proof(available))), children)(offered)

def height_demand_population(~A: Data, ~E: Data, +demand: Space.Demand, +head: Allocation.MeasuredTree<A, E>,
  +tail: +List<Allocation.MeasuredTree<A, E>>, +offered: Nat, +rest: Allocation.SlotsOutcome<Allocation.MeasuredTree<A, E>>,
  proof: SlotsPopulation(~Allocation.MeasuredTree<A, E>, tail, rest)) ->
  SlotsPopulation(~Allocation.MeasuredTree<A, E>, head <> tail, Allocation.height_slot_demand(~A, ~E, demand, head, offered, rest)):
  Space.Demand{minimum, preferred} = demand
  materialized_population(~Allocation.MeasuredTree<A, E>,
    Model.materialize(Allocation.block_size(Allocation.measured_rule(~A, ~E, head)), Allocation.axis_extent(Allocation.BlockAxis{}, minimum), Allocation.axis_extent(Allocation.BlockAxis{}, preferred), offered),
    head, tail, Allocation.measured_key(~A, ~E, head), Allocation.BlockAxis{}, Allocation.axis_extent(Allocation.BlockAxis{}, minimum), offered, rest, proof)

def height_population(~A: Data, ~E: Data, +children: +List<Allocation.MeasuredTree<A, E>>, +offered: Nat) ->
  SlotsPopulation(~Allocation.MeasuredTree<A, E>, children, Allocation.height_slots(~A, ~E, children, offered)):
  Std.list_ind(~Allocation.MeasuredTree<A, E>, ~(trees => @+available:Nat -> SlotsPopulation(~Allocation.MeasuredTree<A, E>, trees, Allocation.height_slots(~A, ~E, trees, available))),
    ~(+available => {==}), ~(+head => +tail => proof => +available => height_demand_population(~A, ~E, Allocation.measured_demand(~A, ~E, head), head, tail, Nat.sub(available, Allocation.outside_axis(Allocation.BlockAxis{}, Allocation.measured_rule(~A, ~E, head))), Allocation.height_slots(~A, ~E, tail, available), proof(available))), children)(offered)

# Successful packing carries the imported complete payload equation; failure imposes no feasibility claim.

def packed_claim_population(~T: Data, +slots: +List<Space.Slot<T>>, +gap: Nat, +available: Nat, +result: Space.Packing<T>,
  proof: Rule.PackedClaim(~T, slots, gap, available, result)) -> PackingPopulation(~T, Rule.slot_values(~T, slots), result):
  match result:
    case Space.Insufficient{required, received}: Empty.absurd(PackingPopulation(~T, Rule.slot_values(~T, slots), Space.Insufficient{required, received}), proof)
    case Space.Packed{placements, unused}:
      Rule.AllocationEvidence{payloads, bounds, order, budget} = proof
      payloads

def pack_fit_population(~T: Data, +fits: Bool, +slots: +List<Space.Slot<T>>, +gap: Nat, +available: Nat,
  +equation: {Nat.is_le(Space.minimum_sequence(~T, slots, gap), available) == fits : Bool}) ->
  PackingPopulation(~T, Rule.slot_values(~T, slots), Space.pack(~T, slots, gap, available)):
  match fits:
    case True{}:
      packed_claim_population(~T, slots, gap, available, Space.pack(~T, slots, gap, available), ProofGeometryProof.pack_complete(~T, slots, gap, available, equation))
    case False{}:
      Std.transport(Space.Packing<T>, Space.Insufficient{Space.minimum_sequence(~T, slots, gap), available},
        (result => PackingPopulation(~T, Rule.slot_values(~T, slots), result)), {==}, Space.pack(~T, slots, gap, available),
        ProofGeometryProof.pack_insufficient(~T, slots, gap, available, equation))

def pack_population(~T: Data, +slots: +List<Space.Slot<T>>, +gap: Nat, +available: Nat) ->
  PackingPopulation(~T, Rule.slot_values(~T, slots), Space.pack(~T, slots, gap, available)):
  pack_fit_population(~T, Nat.is_le(Space.minimum_sequence(~T, slots, gap), available), slots, gap, available, {==})

def tagged_value(~T: Data, tagged: Allocation.Tagged<T>) -> T:
  Allocation.Tagged{value, dimension} = tagged
  value

def freeze_population_step(~T: Data, +head: Space.Slot<T>, +tail: +List<Space.Slot<T>>,
  proof: {Std.map(~Allocation.Tagged<T>, ~T, ~(tagged => tagged_value(~T, tagged)), Rule.slot_values(~Allocation.Tagged<T>, Allocation.freeze_slots(~T, tail))) == Rule.slot_values(~T, tail) : +List<T>}) ->
  {Std.map(~Allocation.Tagged<T>, ~T, ~(tagged => tagged_value(~T, tagged)), Rule.slot_values(~Allocation.Tagged<T>, Allocation.freeze_slots(~T, head <> tail))) == Rule.slot_values(~T, head <> tail) : +List<T>}:
  Space.Slot{+value, dimension} = head
  Equal.cong(+List<T>, +List<T>, (values => value <> values),
    Std.map(~Allocation.Tagged<T>, ~T, ~(tagged => tagged_value(~T, tagged)), Rule.slot_values(~Allocation.Tagged<T>, Allocation.freeze_slots(~T, tail))), Rule.slot_values(~T, tail), proof)

def freeze_population(~T: Data, +slots: +List<Space.Slot<T>>) ->
  {Std.map(~Allocation.Tagged<T>, ~T, ~(tagged => tagged_value(~T, tagged)), Rule.slot_values(~Allocation.Tagged<T>, Allocation.freeze_slots(~T, slots))) == Rule.slot_values(~T, slots) : +List<T>}:
  Std.list_ind(~Space.Slot<T>, ~(values => {Std.map(~Allocation.Tagged<T>, ~T, ~(tagged => tagged_value(~T, tagged)), Rule.slot_values(~Allocation.Tagged<T>, Allocation.freeze_slots(~T, values))) == Rule.slot_values(~T, values) : +List<T>}), ~{==},
    ~(+head => +tail => proof => freeze_population_step(~T, head, tail, proof)), slots)

def thaw_population(~T: Data, +placements: +List<Space.Placement<Allocation.Tagged<T>>>, +share: Nat, +remaining: Nat) ->
  {Rule.slot_values(~T, Allocation.thaw_slots(~T, placements, share, remaining)) == Std.map(~Allocation.Tagged<T>, ~T, ~(tagged => tagged_value(~T, tagged)), Rule.placement_values(~Allocation.Tagged<T>, placements)) : +List<T>}:
  match placements:
    case Nil{}: {==}
    case Con{Space.Placement{Allocation.Tagged{+value, +original}, offset, extent}, rest}:
      Equal.cong(+List<T>, +List<T>, (values => value <> values),
        Rule.slot_values(~T, Allocation.thaw_slots(~T, rest, share, Allocation.next_remainder(original, remaining))),
        Std.map(~Allocation.Tagged<T>, ~T, ~(tagged => tagged_value(~T, tagged)), Rule.placement_values(~Allocation.Tagged<T>, rest)),
        thaw_population(~T, rest, share, Allocation.next_remainder(original, remaining)))

def packing_retarget(~T: Data, +old: +List<T>, +children: +List<T>, +result: Space.Packing<T>,
  proof: PackingPopulation(~T, old, result), equation: {old == children : +List<T>}) -> PackingPopulation(~T, children, result):
  Std.transport(+List<T>, old, (values => PackingPopulation(~T, values, result)), proof, children,
    Equal.sym(+List<T>, old, children, equation))

def restored_population(~T: Data, +placements: +List<Space.Placement<Allocation.Tagged<T>>>, +share: Nat, +remaining: Nat, +gap: Nat, +available: Nat) ->
  PackingPopulation(~T, Std.map(~Allocation.Tagged<T>, ~T, ~(tagged => tagged_value(~T, tagged)), Rule.placement_values(~Allocation.Tagged<T>, placements)),
    Space.pack(~T, Allocation.thaw_slots(~T, placements, share, remaining), gap, available)):
  packing_retarget(~T, Rule.slot_values(~T, Allocation.thaw_slots(~T, placements, share, remaining)),
    Std.map(~Allocation.Tagged<T>, ~T, ~(tagged => tagged_value(~T, tagged)), Rule.placement_values(~Allocation.Tagged<T>, placements)),
    Space.pack(~T, Allocation.thaw_slots(~T, placements, share, remaining), gap, available),
    pack_population(~T, Allocation.thaw_slots(~T, placements, share, remaining), gap, available), thaw_population(~T, placements, share, remaining))

def redistribution_population(~T: Data, +selector: Bool, +count: Nat, +placements: +List<Space.Placement<Allocation.Tagged<T>>>, +unused: Nat, +gap: Nat, +available: Nat) ->
  PackingPopulation(~T, Std.map(~Allocation.Tagged<T>, ~T, ~(tagged => tagged_value(~T, tagged)), Rule.placement_values(~Allocation.Tagged<T>, placements)),
    Allocation.dispatch_redistribute_2(~T, selector, count, placements, unused, gap, available)):
  match selector:
    case True{}: restored_population(~T, placements, 0n, 0n, gap, available)
    case False{}: restored_population(~T, placements, Nat.div(unused, count), Nat.sub(unused, Nat.mul(Nat.div(unused, count), count)), gap, available)

def first_pack_population(~T: Data, +first: Space.Packing<Allocation.Tagged<T>>, +slots: +List<Space.Slot<T>>, +count: Nat, +gap: Nat, +available: Nat,
  proof: PackingPopulation(~Allocation.Tagged<T>, Rule.slot_values(~Allocation.Tagged<T>, Allocation.freeze_slots(~T, slots)), first)) ->
  PackingPopulation(~T, Rule.slot_values(~T, slots), Allocation.redistribute(~T, count, first, gap, available)):
  match first:
    case Space.Insufficient{required, received}: {==}
    case Space.Packed{placements, unused}:
      packing_retarget(~T,
        Std.map(~Allocation.Tagged<T>, ~T, ~(tagged => tagged_value(~T, tagged)), Rule.placement_values(~Allocation.Tagged<T>, placements)),
        Rule.slot_values(~T, slots), Allocation.dispatch_redistribute_2(~T, Nat.is_eq(count, 0n), count, placements, unused, gap, available),
        redistribution_population(~T, Nat.is_eq(count, 0n), count, placements, unused, gap, available),
        Equal.trans(+List<T>,
          Std.map(~Allocation.Tagged<T>, ~T, ~(tagged => tagged_value(~T, tagged)), Rule.placement_values(~Allocation.Tagged<T>, placements)),
          Std.map(~Allocation.Tagged<T>, ~T, ~(tagged => tagged_value(~T, tagged)), Rule.slot_values(~Allocation.Tagged<T>, Allocation.freeze_slots(~T, slots))),
          Rule.slot_values(~T, slots),
          Equal.cong(+List<Allocation.Tagged<T>>, +List<T>,
            (values => Std.map(~Allocation.Tagged<T>, ~T, ~(tagged => tagged_value(~T, tagged)), values)),
            Rule.placement_values(~Allocation.Tagged<T>, placements), Rule.slot_values(~Allocation.Tagged<T>, Allocation.freeze_slots(~T, slots)), proof),
          freeze_population(~T, slots)))

def shared_population(~T: Data, +slots: +List<Space.Slot<T>>, +gap: Nat, +available: Nat) ->
  PackingPopulation(~T, Rule.slot_values(~T, slots), Allocation.shared_pack(~T, slots, gap, available)):
  first_pack_population(~T, Space.pack(~Allocation.Tagged<T>, Allocation.freeze_slots(~T, slots), gap, available), slots, Allocation.fill_count(~T, slots), gap, available,
    pack_population(~Allocation.Tagged<T>, Allocation.freeze_slots(~T, slots), gap, available))

def shift_population_step(~T: Data, +placement: Space.Placement<T>, +tail: +List<Space.Placement<T>>, +shift: Nat,
  proof: {Rule.placement_values(~T, Allocation.shift_placements(~T, tail, shift)) == Rule.placement_values(~T, tail) : +List<T>}) ->
  {Rule.placement_values(~T, Allocation.shift_placements(~T, placement <> tail, shift)) == Rule.placement_values(~T, placement <> tail) : +List<T>}:
  Space.Placement{+value, offset, extent} = placement
  Equal.cong(+List<T>, +List<T>, (values => value <> values),
    Rule.placement_values(~T, Allocation.shift_placements(~T, tail, shift)),
    Rule.placement_values(~T, tail), proof)

def shift_population(~T: Data, +placements: +List<Space.Placement<T>>, +shift: Nat) ->
  {Rule.placement_values(~T, Allocation.shift_placements(~T, placements, shift)) == Rule.placement_values(~T, placements) : +List<T>}:
  Std.list_ind(~Space.Placement<T>, ~(values => @+amount:Nat -> {Rule.placement_values(~T, Allocation.shift_placements(~T, values, amount)) == Rule.placement_values(~T, values) : +List<T>}), ~(amount => {==}),
    ~(+head => +tail => proof => +amount => shift_population_step(~T, head, tail, amount, proof(amount))), placements)(shift)

def parallel_append_population(~T: Data, +rest: Allocation.ChildPlan<T>, +placements: +List<Space.Placement<T>>, +children: +List<T>, +tree: T, +shift: Nat,
  head_proof: {Rule.placement_values(~T, placements) == (tree <> Nil{}) : +List<T>},
  tail_proof: PlanPopulation(~T, children, rest)) ->
  PlanPopulation(~T, tree <> children, Allocation.dispatch_prepare_parallel_8(~T, rest, placements, shift)):
  match rest:
    case Allocation.PlanningFailure{failure}: {==}
    case Allocation.ChildrenPlanned{tail, canvas}:
      +shifted = Allocation.shift_placements(~T, placements, shift)
      Equal.trans(+List<T>,
        Rule.placement_values(~T, List.append(&2, Space.Placement<T>, shifted, tail)),
        List.append(&2, T, Rule.placement_values(~T, shifted), Rule.placement_values(~T, tail)), tree <> children,
        Std.map_app(~Space.Placement<T>, ~T, ~(value => Rule.placement_value(~T, value)), shifted, tail),
        Equal.trans(+List<T>,
          List.append(&2, T, Rule.placement_values(~T, shifted), Rule.placement_values(~T, tail)),
          List.append(&2, T, tree <> Nil{}, Rule.placement_values(~T, tail)), tree <> children,
          Equal.cong(+List<T>, +List<T>, (values => List.append(&2, T, values, Rule.placement_values(~T, tail))),
            Rule.placement_values(~T, shifted), tree <> Nil{},
            Equal.trans(+List<T>, Rule.placement_values(~T, shifted), Rule.placement_values(~T, placements), tree <> Nil{}, shift_population(~T, placements, shift), head_proof)),
          Equal.cong(+List<T>, +List<T>, (values => tree <> values), Rule.placement_values(~T, tail), children, tail_proof)))

def packed_parallel_population(~T: Data, ~key_of: T -> String, +first: Space.Packing<T>, +tree: T, +axis: Allocation.Axis, +alignment: SpatialModel.Alignment, +rest: Allocation.ChildPlan<T>, +children: +List<T>,
  head_proof: PackingPopulation(~T, tree <> Nil{}, first), tail_proof: PlanPopulation(~T, children, rest)) ->
  PlanPopulation(~T, tree <> children, Allocation.packed_parallel(~T, ~key_of, first, tree, axis, alignment, rest)):
  match first:
    case Space.Insufficient{required, available}: {==}
    case Space.Packed{placements, unused}:
      parallel_append_population(~T, rest, placements, children, tree, Allocation.alignment_offset(alignment, unused), head_proof, tail_proof)

def clearance_pack_checked_population(~T: Data, +fits: Bool, +slots: +List<Space.Slot<T>>, +clearance: Nat, +available: Nat) ->
  PackingPopulation(~T, Rule.slot_values(~T, slots), Allocation.clearance_pack_checked(~T, fits, slots, clearance, available)):
  match fits:
    case False{}: {==}
    case True{}: shared_population(~T, slots, 0n, Nat.sub(available, clearance))

def clearance_pack_population(~T: Data, +slots: +List<Space.Slot<T>>, +clearance: Nat, +available: Nat) ->
  PackingPopulation(~T, Rule.slot_values(~T, slots), Allocation.clearance_pack(~T, slots, clearance, available)):
  clearance_pack_checked_population(~T, Nat.is_le(clearance, available), slots, clearance, available)

def parallel_population_step(~T: Data, ~key_of: T -> String, ~clearance_of: T -> Nat, +head: Space.Slot<T>, +tail: +List<Space.Slot<T>>, +axis: Allocation.Axis, +canvas: Nat, +alignment: SpatialModel.Alignment,
  proof: PlanPopulation(~T, Rule.slot_values(~T, tail), Allocation.prepare_parallel(~T, ~key_of, ~clearance_of, tail, axis, canvas, alignment))) ->
  PlanPopulation(~T, Rule.slot_values(~T, head <> tail), Allocation.prepare_parallel(~T, ~key_of, ~clearance_of, head <> tail, axis, canvas, alignment)):
  Space.Slot{+tree, +dimension} = head
  packed_parallel_population(~T, ~key_of, Allocation.clearance_pack(~T, Space.Slot{tree, dimension} <> Nil{}, clearance_of(tree), canvas), tree, axis, alignment,
    Allocation.prepare_parallel(~T, ~key_of, ~clearance_of, tail, axis, canvas, alignment), Rule.slot_values(~T, tail),
    clearance_pack_population(~T, Space.Slot{tree, dimension} <> Nil{}, clearance_of(tree), canvas), proof)

def parallel_population(~T: Data, ~key_of: T -> String, ~clearance_of: T -> Nat, +slots: +List<Space.Slot<T>>, +axis: Allocation.Axis, +canvas: Nat, +alignment: SpatialModel.Alignment) ->
  PlanPopulation(~T, Rule.slot_values(~T, slots), Allocation.prepare_parallel(~T, ~key_of, ~clearance_of, slots, axis, canvas, alignment)):
  Std.list_ind(~Space.Slot<T>, ~(values => @+actual_axis:Allocation.Axis -> @+actual_canvas:Nat -> @+actual_alignment:SpatialModel.Alignment ->
      PlanPopulation(~T, Rule.slot_values(~T, values), Allocation.prepare_parallel(~T, ~key_of, ~clearance_of, values, actual_axis, actual_canvas, actual_alignment))),
    ~(+actual_axis => +actual_canvas => +actual_alignment => {==}),
    ~(+head => +tail => proof => +actual_axis => +actual_canvas => +actual_alignment =>
      parallel_population_step(~T, ~key_of, ~clearance_of, head, tail, actual_axis, actual_canvas, actual_alignment, proof(actual_axis)(actual_canvas)(actual_alignment))), slots)(axis)(canvas)(alignment)

def sequential_population(~T: Data, +first: Space.Packing<T>, +slots: +List<Space.Slot<T>>, +key: String, +axis: Allocation.Axis, +alignment: SpatialModel.Alignment, +canvas: Nat,
  proof: PackingPopulation(~T, Rule.slot_values(~T, slots), first)) ->
  PlanPopulation(~T, Rule.slot_values(~T, slots), Allocation.dispatch_prepare_slots_9(~T, first, key, axis, alignment, canvas)):
  match first:
    case Space.Insufficient{required, available}: {==}
    case Space.Packed{placements, unused}:
      Equal.trans(+List<T>,
        Rule.placement_values(~T, Allocation.shift_placements(~T, placements, Allocation.alignment_offset(alignment, unused))),
        Rule.placement_values(~T, placements), Rule.slot_values(~T, slots), shift_population(~T, placements, Allocation.alignment_offset(alignment, unused)), proof)

def sequence_population(~T: Data, ~key_of: T -> String, ~clearance_of: T -> Nat, +is_sequence: Bool, +key: String, +axis: Allocation.Axis,
  +slots: +List<Space.Slot<T>>, +gap: Nat, +canvas: Nat, +alignment: SpatialModel.Alignment) ->
  PlanPopulation(~T, Rule.slot_values(~T, slots), Allocation.destructure_prepare_slots_sequence(~T, ~key_of, ~clearance_of, is_sequence, key, axis, slots, gap, canvas, alignment)):
  match is_sequence:
    case False{}: parallel_population(~T, ~key_of, ~clearance_of, slots, axis, canvas, alignment)
    case True{}: sequential_population(~T, Allocation.shared_pack(~T, slots, gap, canvas), slots, key, axis, alignment, canvas, shared_population(~T, slots, gap, canvas))

def slots_population(~T: Data, ~key_of: T -> String, ~clearance_of: T -> Nat, +key: String, +axis: Allocation.Axis, +rule: Model.Rule,
  +direction: Allocation.ResolvedDirection, +slots: +List<Space.Slot<T>>, +available: Nat) ->
  PlanPopulation(~T, Rule.slot_values(~T, slots), Allocation.prepare_slots(~T, ~key_of, ~clearance_of, key, axis, rule, direction, slots, available)):
  sequence_population(~T, ~key_of, ~clearance_of, Allocation.sequential(axis, direction), key, axis, slots, Allocation.rule_gap(rule),
    Allocation.resolved_canvas(direction, available, Allocation.canvas_size(Allocation.scrolls(axis, Allocation.rule_scroll(rule)), available, Allocation.required_canvas(~T, Allocation.sequential(axis, direction), slots, Allocation.rule_gap(rule)))),
    Allocation.axis_alignment(axis, direction, rule))

def inline_wrapper_population(~A: Data, ~E: Data, +result: Allocation.ChildPlan<Model.Tree<A, E>>, +children: +List<Model.Tree<A, E>>, +direction: Allocation.ResolvedDirection,
  proof: PlanPopulation(~Model.Tree<A, E>, children, result)) ->
  RulePhysicalSourceRules.InlinePopulation(~A, ~E, children, Allocation.dispatch_prepare_inline_children_11(~A, ~E, result, direction)):
  match result:
    case Allocation.PlanningFailure{failure}: {==}
    case Allocation.ChildrenPlanned{placements, canvas}: proof

def inline_rule_unchecked_population(~A: Data, ~E: Data, +rule: Model.Rule, +key: String, +available: Nat, +slots: +List<Space.Slot<Model.Tree<A, E>>>) ->
  RulePhysicalSourceRules.InlinePopulation(~A, ~E, Rule.slot_values(~Model.Tree<A, E>, slots), Allocation.prepare_inline_rule_unchecked(~A, ~E, rule, key, available, slots)):
  Model.Rule{+authored, main_alignment, cross_alignment, frame, border, width, height, minimum, scroll, position} = rule
  +direction = Allocation.resolve_direction(authored, Space.minimum_sequence(~Model.Tree<A, E>, slots, Allocation.rule_gap(rule)), available)
  inline_wrapper_population(~A, ~E,
    Allocation.prepare_slots(~Model.Tree<A, E>, ~(tree => Allocation.tree_key(~A, ~E, tree)), ~(tree => Allocation.outside_axis(Allocation.InlineAxis{}, Allocation.tree_rule(~A, ~E, tree))), key, Allocation.InlineAxis{}, rule, direction, slots, available),
    Rule.slot_values(~Model.Tree<A, E>, slots), direction,
    slots_population(~Model.Tree<A, E>, ~(tree => Allocation.tree_key(~A, ~E, tree)), ~(tree => Allocation.outside_axis(Allocation.InlineAxis{}, Allocation.tree_rule(~A, ~E, tree))), key, Allocation.InlineAxis{}, rule, direction, slots, available))

def inline_gap_population(~A: Data, ~E: Data, +valid: Bool, +rule: Model.Rule, +key: String, +available: Nat, +slots: +List<Space.Slot<Model.Tree<A, E>>>) ->
  RulePhysicalSourceRules.InlinePopulation(~A, ~E, Rule.slot_values(~Model.Tree<A, E>, slots), Allocation.prepare_inline_gap(~A, ~E, valid, rule, key, available, slots)):
  match valid:
    case False{}: {==}
    case True{}: inline_rule_unchecked_population(~A, ~E, rule, key, available, slots)

def inline_rule_population(~A: Data, ~E: Data, +rule: Model.Rule, +key: String, +available: Nat, +slots: +List<Space.Slot<Model.Tree<A, E>>>) ->
  RulePhysicalSourceRules.InlinePopulation(~A, ~E, Rule.slot_values(~Model.Tree<A, E>, slots), Allocation.prepare_inline_rule(~A, ~E, rule, key, available, slots)):
  inline_gap_population(~A, ~E, Allocation.layered_gap_valid(rule), rule, key, available, slots)

def inline_dispatch_population(~A: Data, ~E: Data, +result: Allocation.SlotsOutcome<Model.Tree<A, E>>, +children: +List<Model.Tree<A, E>>, +key: String, +rule: Model.Rule, +available: Nat,
  proof: SlotsPopulation(~Model.Tree<A, E>, children, result)) ->
  RulePhysicalSourceRules.InlinePopulation(~A, ~E, children, Allocation.dispatch_prepare_inline_children_10(~A, ~E, result, key, rule, available)):
  match result:
    case Allocation.SlotsFailure{failure}: {==}
    case Allocation.SlotsReady{slots}:
      Std.transport(+List<Model.Tree<A, E>>, Rule.slot_values(~Model.Tree<A, E>, slots),
        (values => RulePhysicalSourceRules.InlinePopulation(~A, ~E, values, Allocation.prepare_inline_rule(~A, ~E, rule, key, available, slots))),
        inline_rule_population(~A, ~E, rule, key, available, slots), children,
        Equal.sym(+List<Model.Tree<A, E>>, Rule.slot_values(~Model.Tree<A, E>, slots), children, proof))

def inline_population(~A: Data, ~E: Data, +key: String, +rule: Model.Rule, +children: +List<Model.Tree<A, E>>, +available: Nat) ->
  RulePhysicalSourceRules.InlinePopulation(~A, ~E, children, Allocation.prepare_inline_children(~A, ~E, key, rule, children, available)):
  inline_dispatch_population(~A, ~E, Allocation.width_slots(~A, ~E, children, available), children, key, rule, available,
    width_population(~A, ~E, children, available))

def block_wrapper_population(~A: Data, ~E: Data, +result: Allocation.ChildPlan<Allocation.MeasuredTree<A, E>>, +children: +List<Allocation.MeasuredTree<A, E>>,
  proof: PlanPopulation(~Allocation.MeasuredTree<A, E>, children, result)) -> RulePhysicalSourceRules.BlockPopulation(~A, ~E, children, result):
  match result:
    case Allocation.PlanningFailure{failure}: {==}
    case Allocation.ChildrenPlanned{placements, canvas}: proof

def block_dispatch_population(~A: Data, ~E: Data, +result: Allocation.SlotsOutcome<Allocation.MeasuredTree<A, E>>, +children: +List<Allocation.MeasuredTree<A, E>>,
  +key: String, +rule: Model.Rule, +direction: Allocation.ResolvedDirection, +available: Nat,
  proof: SlotsPopulation(~Allocation.MeasuredTree<A, E>, children, result)) ->
  RulePhysicalSourceRules.BlockPopulation(~A, ~E, children, Allocation.dispatch_prepare_block_children_17(~A, ~E, result, key, rule, direction, available)):
  match result:
    case Allocation.SlotsFailure{failure}: {==}
    case Allocation.SlotsReady{slots}:
      Std.transport(+List<Allocation.MeasuredTree<A, E>>, Rule.slot_values(~Allocation.MeasuredTree<A, E>, slots),
        (values => RulePhysicalSourceRules.BlockPopulation(~A, ~E, values,
          Allocation.prepare_slots(~Allocation.MeasuredTree<A, E>, ~(tree => Allocation.measured_key(~A, ~E, tree)), ~(tree => Allocation.outside_axis(Allocation.BlockAxis{}, Allocation.measured_rule(~A, ~E, tree))), key, Allocation.BlockAxis{}, rule, direction, slots, available))),
        block_wrapper_population(~A, ~E,
          Allocation.prepare_slots(~Allocation.MeasuredTree<A, E>, ~(tree => Allocation.measured_key(~A, ~E, tree)), ~(tree => Allocation.outside_axis(Allocation.BlockAxis{}, Allocation.measured_rule(~A, ~E, tree))), key, Allocation.BlockAxis{}, rule, direction, slots, available),
          Rule.slot_values(~Allocation.MeasuredTree<A, E>, slots),
          slots_population(~Allocation.MeasuredTree<A, E>, ~(tree => Allocation.measured_key(~A, ~E, tree)), ~(tree => Allocation.outside_axis(Allocation.BlockAxis{}, Allocation.measured_rule(~A, ~E, tree))), key, Allocation.BlockAxis{}, rule, direction, slots, available)),
        children, Equal.sym(+List<Allocation.MeasuredTree<A, E>>, Rule.slot_values(~Allocation.MeasuredTree<A, E>, slots), children, proof))

def block_population(~A: Data, ~E: Data, +key: String, +rule: Model.Rule, +direction: Allocation.ResolvedDirection,
  +children: +List<Allocation.MeasuredTree<A, E>>, +available: Nat) ->
  RulePhysicalSourceRules.BlockPopulation(~A, ~E, children, Allocation.prepare_block_children(~A, ~E, key, rule, direction, children, available)):
  block_dispatch_population(~A, ~E, Allocation.height_slots(~A, ~E, children, available), children, key, rule, direction, available,
    height_population(~A, ~E, children, available))

def RulePhysicalSourceRules.allocation_population_evidence(A, E):
  RulePhysicalSourceRules.AllocationPopulationRequirements{
    +key => +rule => +children => +available => inline_population(~A, ~E, key, rule, children, available),
    +key => +rule => +direction => +children => +available => block_population(~A, ~E, key, rule, direction, children, available)}

def RulePhysicalSourceRules.aligned_layer_bounds(outside, horizontal, vertical, rule, left, top, available_width, available_height, width, height):
  E.Insets{inline, block} = outside
  {==}

def RulePhysicalSourceRules.aligned_layer_clearance(outside, horizontal, vertical): {==}

def root_position_policy(~A: Data, ~E: Data, +position: SpatialModel.Position, +tree: Allocation.MeasuredTree<A, E>, +offered: SpatialModel.Box, +offset: Nat, +height: Nat) ->
  RulePhysicalSourceRules.RootBoundsPolicy(~A, ~E, position, tree, offered, offset, height, Allocation.root_bounds_position(~A, ~E, position, tree, offered, offset, height)):
  match position:
    case SpatialModel.InFlow{}: {==}
    case SpatialModel.CenteredLayer{outside}: {==}
    case SpatialModel.AlignedLayer{outside, horizontal, vertical}: {==}
    case SpatialModel.AnchoredLayer{key, anchor, outside, gap, alignment}: {==}

def RulePhysicalSourceRules.root_position(A, E, tree, offered, offset, height):
  root_position_policy(~A, ~E, Model.rule_position(Allocation.measured_rule(~A, ~E, tree)), tree, offered, offset, height)

def RulePhysicalSourceRules.root_width_clearance(A, E, slots, tree, width, samples):
  {==}

def RulePhysicalSourceRules.root_height_clearance(A, E, slots, tree, offered):
  {==}

def RulePhysicalSourceRules.root_allocation_bounds(A, E, tree, value, rest, offset, height, offered):
  {==}

def measured_preferred(~A: Data, ~E: Data, +tree: Allocation.MeasuredTree<A, E>) ->
  {Rule.preferred_covers_minimum(Allocation.measured_demand(~A, ~E, tree)) == True{} : Bool}:
  match tree:
    case Allocation.MeasuredLeaf{key, value, interaction, rule, demand, height, outer_width, inline_offset, content_height}:
      ProofGeometryProof.outer_preferred(~E, Model.fixed_leaf_content(demand, content_height), rule, interaction)
    case Allocation.MeasuredContainer{key, value, interaction, +rule, outer_width, inline_offset, direction, children}:
      ProofGeometryProof.outer_preferred(~E, Allocation.measured_content_demand(~A, ~E, children, direction, Allocation.rule_gap(rule)), rule, interaction)

def RulePhysicalSourceRules.measured_preferred(A, E, tree):
  measured_preferred(~A, ~E, tree)

def measured_authored_floor(~A: Data, ~E: Data, +tree: Allocation.MeasuredTree<A, E>) ->
  {Rule.extent_contains(Model.minimum_demand(Allocation.measured_demand(~A, ~E, tree)), Rule.rule_authored_minimum(Allocation.measured_rule(~A, ~E, tree))) == True{} : Bool}:
  match tree:
    case Allocation.MeasuredLeaf{key, value, interaction, rule, demand, height, outer_width, inline_offset, content_height}:
      ProofGeometryProof.outer_authored_floor(~E, Model.fixed_leaf_content(demand, content_height), rule, interaction)
    case Allocation.MeasuredContainer{key, value, interaction, +rule, outer_width, inline_offset, direction, children}:
      ProofGeometryProof.outer_authored_floor(~E, Allocation.measured_content_demand(~A, ~E, children, direction, Allocation.rule_gap(rule)), rule, interaction)

def RulePhysicalSourceRules.measured_authored_floor(A, E, tree):
  measured_authored_floor(~A, ~E, tree)
