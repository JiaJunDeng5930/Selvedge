import Base
import ../../bendlib/stdlib.bend as Std
import ../physical-space.bend as Model
import ./physical-space.bend as ModelProof
import ../physical-space-rules.bend as ModelRules
import ../physical-allocation.bend as Allocation
import ../spatial.bend as Spatial
import ../enclosure.bend as Enclosure
import ../space.bend as Space
import ../space-laws.bend as SpaceLaws
import ./space.bend as SpaceProof
import ../physical-allocation-population-rules.bend as Rule

def SlotsPopulation(~T: Data, +children: +List<T>, result: Allocation.SlotsOutcome<T>) -> Type:
  match result:
    case Allocation.SlotsReady{slots}: {SpaceLaws.slot_values(~T, slots) == children : +List<T>}
    case Allocation.SlotsFailure{failure}: {True{} == True{} : Bool}

def PlanPopulation(~T: Data, +children: +List<T>, result: Allocation.ChildPlan<T>) -> Type:
  match result:
    case Allocation.ChildrenPlanned{placements, canvas}: {SpaceLaws.placement_values(~T, placements) == children : +List<T>}
    case Allocation.PlanningFailure{failure}: {True{} == True{} : Bool}

def PackingPopulation(~T: Data, +children: +List<T>, result: Space.Packing<T>) -> Type:
  match result:
    case Space.Packed{placements, unused}: {SpaceLaws.placement_values(~T, placements) == children : +List<T>}
    case Space.Insufficient{required, available}: {True{} == True{} : Bool}

def prepend_population(~T: Data, +result: Allocation.SlotsOutcome<T>, +head: T, +tail: +List<T>, +dimension: Space.Dimension,
  proof: SlotsPopulation(~T, tail, result)) ->
  SlotsPopulation(~T, head <> tail, Allocation.prepend_slot(~T, Space.Slot{head, dimension}, result)):
  match result:
    case Allocation.SlotsFailure{failure}: {==}
    case Allocation.SlotsReady{slots}:
      Equal.cong(+List<T>, +List<T>, (values => head <> values), SpaceLaws.slot_values(~T, slots), tail, proof)

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
  proof: SpaceLaws.PackedClaim(~T, slots, gap, available, result)) -> PackingPopulation(~T, SpaceLaws.slot_values(~T, slots), result):
  match result:
    case Space.Insufficient{required, received}: Empty.absurd(PackingPopulation(~T, SpaceLaws.slot_values(~T, slots), Space.Insufficient{required, received}), proof)
    case Space.Packed{placements, unused}:
      SpaceLaws.AllocationEvidence{payloads, bounds, order, budget} = proof
      payloads

def pack_fit_population(~T: Data, +fits: Bool, +slots: +List<Space.Slot<T>>, +gap: Nat, +available: Nat,
  +equation: {Nat.is_le(Space.minimum_sequence(~T, slots, gap), available) == fits : Bool}) ->
  PackingPopulation(~T, SpaceLaws.slot_values(~T, slots), Space.pack(~T, slots, gap, available)):
  match fits:
    case True{}:
      packed_claim_population(~T, slots, gap, available, Space.pack(~T, slots, gap, available), SpaceProof.pack_complete(~T, slots, gap, available, equation))
    case False{}:
      Std.transport(Space.Packing<T>, Space.Insufficient{Space.minimum_sequence(~T, slots, gap), available},
        (result => PackingPopulation(~T, SpaceLaws.slot_values(~T, slots), result)), {==}, Space.pack(~T, slots, gap, available),
        SpaceProof.pack_insufficient(~T, slots, gap, available, equation))

def pack_population(~T: Data, +slots: +List<Space.Slot<T>>, +gap: Nat, +available: Nat) ->
  PackingPopulation(~T, SpaceLaws.slot_values(~T, slots), Space.pack(~T, slots, gap, available)):
  pack_fit_population(~T, Nat.is_le(Space.minimum_sequence(~T, slots, gap), available), slots, gap, available, {==})

def tagged_value(~T: Data, tagged: Allocation.Tagged<T>) -> T:
  Allocation.Tagged{value, dimension} = tagged
  value

def freeze_population_step(~T: Data, +head: Space.Slot<T>, +tail: +List<Space.Slot<T>>,
  proof: {Std.map(~Allocation.Tagged<T>, ~T, ~(tagged => tagged_value(~T, tagged)), SpaceLaws.slot_values(~Allocation.Tagged<T>, Allocation.freeze_slots(~T, tail))) == SpaceLaws.slot_values(~T, tail) : +List<T>}) ->
  {Std.map(~Allocation.Tagged<T>, ~T, ~(tagged => tagged_value(~T, tagged)), SpaceLaws.slot_values(~Allocation.Tagged<T>, Allocation.freeze_slots(~T, head <> tail))) == SpaceLaws.slot_values(~T, head <> tail) : +List<T>}:
  Space.Slot{+value, dimension} = head
  Equal.cong(+List<T>, +List<T>, (values => value <> values),
    Std.map(~Allocation.Tagged<T>, ~T, ~(tagged => tagged_value(~T, tagged)), SpaceLaws.slot_values(~Allocation.Tagged<T>, Allocation.freeze_slots(~T, tail))), SpaceLaws.slot_values(~T, tail), proof)

def freeze_population(~T: Data, +slots: +List<Space.Slot<T>>) ->
  {Std.map(~Allocation.Tagged<T>, ~T, ~(tagged => tagged_value(~T, tagged)), SpaceLaws.slot_values(~Allocation.Tagged<T>, Allocation.freeze_slots(~T, slots))) == SpaceLaws.slot_values(~T, slots) : +List<T>}:
  Std.list_ind(~Space.Slot<T>, ~(values => {Std.map(~Allocation.Tagged<T>, ~T, ~(tagged => tagged_value(~T, tagged)), SpaceLaws.slot_values(~Allocation.Tagged<T>, Allocation.freeze_slots(~T, values))) == SpaceLaws.slot_values(~T, values) : +List<T>}), ~{==},
    ~(+head => +tail => proof => freeze_population_step(~T, head, tail, proof)), slots)

def thaw_population(~T: Data, +placements: +List<Space.Placement<Allocation.Tagged<T>>>, +share: Nat, +remaining: Nat) ->
  {SpaceLaws.slot_values(~T, Allocation.thaw_slots(~T, placements, share, remaining)) == Std.map(~Allocation.Tagged<T>, ~T, ~(tagged => tagged_value(~T, tagged)), SpaceLaws.placement_values(~Allocation.Tagged<T>, placements)) : +List<T>}:
  match placements:
    case Nil{}: {==}
    case Con{Space.Placement{Allocation.Tagged{+value, +original}, offset, extent}, rest}:
      Equal.cong(+List<T>, +List<T>, (values => value <> values),
        SpaceLaws.slot_values(~T, Allocation.thaw_slots(~T, rest, share, Allocation.next_remainder(original, remaining))),
        Std.map(~Allocation.Tagged<T>, ~T, ~(tagged => tagged_value(~T, tagged)), SpaceLaws.placement_values(~Allocation.Tagged<T>, rest)),
        thaw_population(~T, rest, share, Allocation.next_remainder(original, remaining)))

def packing_retarget(~T: Data, +old: +List<T>, +children: +List<T>, +result: Space.Packing<T>,
  proof: PackingPopulation(~T, old, result), equation: {old == children : +List<T>}) -> PackingPopulation(~T, children, result):
  Std.transport(+List<T>, old, (values => PackingPopulation(~T, values, result)), proof, children,
    Equal.sym(+List<T>, old, children, equation))

def restored_population(~T: Data, +placements: +List<Space.Placement<Allocation.Tagged<T>>>, +share: Nat, +remaining: Nat, +gap: Nat, +available: Nat) ->
  PackingPopulation(~T, Std.map(~Allocation.Tagged<T>, ~T, ~(tagged => tagged_value(~T, tagged)), SpaceLaws.placement_values(~Allocation.Tagged<T>, placements)),
    Space.pack(~T, Allocation.thaw_slots(~T, placements, share, remaining), gap, available)):
  packing_retarget(~T, SpaceLaws.slot_values(~T, Allocation.thaw_slots(~T, placements, share, remaining)),
    Std.map(~Allocation.Tagged<T>, ~T, ~(tagged => tagged_value(~T, tagged)), SpaceLaws.placement_values(~Allocation.Tagged<T>, placements)),
    Space.pack(~T, Allocation.thaw_slots(~T, placements, share, remaining), gap, available),
    pack_population(~T, Allocation.thaw_slots(~T, placements, share, remaining), gap, available), thaw_population(~T, placements, share, remaining))

def redistribution_population(~T: Data, +selector: Bool, +count: Nat, +placements: +List<Space.Placement<Allocation.Tagged<T>>>, +unused: Nat, +gap: Nat, +available: Nat) ->
  PackingPopulation(~T, Std.map(~Allocation.Tagged<T>, ~T, ~(tagged => tagged_value(~T, tagged)), SpaceLaws.placement_values(~Allocation.Tagged<T>, placements)),
    Allocation.dispatch_redistribute_2(~T, selector, count, placements, unused, gap, available)):
  match selector:
    case True{}: restored_population(~T, placements, 0n, 0n, gap, available)
    case False{}: restored_population(~T, placements, Nat.div(unused, count), Nat.sub(unused, Nat.mul(Nat.div(unused, count), count)), gap, available)

def first_pack_population(~T: Data, +first: Space.Packing<Allocation.Tagged<T>>, +slots: +List<Space.Slot<T>>, +count: Nat, +gap: Nat, +available: Nat,
  proof: PackingPopulation(~Allocation.Tagged<T>, SpaceLaws.slot_values(~Allocation.Tagged<T>, Allocation.freeze_slots(~T, slots)), first)) ->
  PackingPopulation(~T, SpaceLaws.slot_values(~T, slots), Allocation.redistribute(~T, count, first, gap, available)):
  match first:
    case Space.Insufficient{required, received}: {==}
    case Space.Packed{placements, unused}:
      packing_retarget(~T,
        Std.map(~Allocation.Tagged<T>, ~T, ~(tagged => tagged_value(~T, tagged)), SpaceLaws.placement_values(~Allocation.Tagged<T>, placements)),
        SpaceLaws.slot_values(~T, slots), Allocation.dispatch_redistribute_2(~T, Nat.is_eq(count, 0n), count, placements, unused, gap, available),
        redistribution_population(~T, Nat.is_eq(count, 0n), count, placements, unused, gap, available),
        Equal.trans(+List<T>,
          Std.map(~Allocation.Tagged<T>, ~T, ~(tagged => tagged_value(~T, tagged)), SpaceLaws.placement_values(~Allocation.Tagged<T>, placements)),
          Std.map(~Allocation.Tagged<T>, ~T, ~(tagged => tagged_value(~T, tagged)), SpaceLaws.slot_values(~Allocation.Tagged<T>, Allocation.freeze_slots(~T, slots))),
          SpaceLaws.slot_values(~T, slots),
          Equal.cong(+List<Allocation.Tagged<T>>, +List<T>,
            (values => Std.map(~Allocation.Tagged<T>, ~T, ~(tagged => tagged_value(~T, tagged)), values)),
            SpaceLaws.placement_values(~Allocation.Tagged<T>, placements), SpaceLaws.slot_values(~Allocation.Tagged<T>, Allocation.freeze_slots(~T, slots)), proof),
          freeze_population(~T, slots)))

def shared_population(~T: Data, +slots: +List<Space.Slot<T>>, +gap: Nat, +available: Nat) ->
  PackingPopulation(~T, SpaceLaws.slot_values(~T, slots), Allocation.shared_pack(~T, slots, gap, available)):
  first_pack_population(~T, Space.pack(~Allocation.Tagged<T>, Allocation.freeze_slots(~T, slots), gap, available), slots, Allocation.fill_count(~T, slots), gap, available,
    pack_population(~Allocation.Tagged<T>, Allocation.freeze_slots(~T, slots), gap, available))

def shift_population_step(~T: Data, +placement: Space.Placement<T>, +tail: +List<Space.Placement<T>>, +shift: Nat,
  proof: {SpaceLaws.placement_values(~T, Allocation.shift_placements(~T, tail, shift)) == SpaceLaws.placement_values(~T, tail) : +List<T>}) ->
  {SpaceLaws.placement_values(~T, Allocation.shift_placements(~T, placement <> tail, shift)) == SpaceLaws.placement_values(~T, placement <> tail) : +List<T>}:
  Space.Placement{+value, offset, extent} = placement
  Equal.cong(+List<T>, +List<T>, (values => value <> values),
    SpaceLaws.placement_values(~T, Allocation.shift_placements(~T, tail, shift)),
    SpaceLaws.placement_values(~T, tail), proof)

def shift_population(~T: Data, +placements: +List<Space.Placement<T>>, +shift: Nat) ->
  {SpaceLaws.placement_values(~T, Allocation.shift_placements(~T, placements, shift)) == SpaceLaws.placement_values(~T, placements) : +List<T>}:
  Std.list_ind(~Space.Placement<T>, ~(values => @+amount:Nat -> {SpaceLaws.placement_values(~T, Allocation.shift_placements(~T, values, amount)) == SpaceLaws.placement_values(~T, values) : +List<T>}), ~(amount => {==}),
    ~(+head => +tail => proof => +amount => shift_population_step(~T, head, tail, amount, proof(amount))), placements)(shift)

def parallel_append_population(~T: Data, +rest: Allocation.ChildPlan<T>, +placements: +List<Space.Placement<T>>, +children: +List<T>, +tree: T, +shift: Nat,
  head_proof: {SpaceLaws.placement_values(~T, placements) == (tree <> Nil{}) : +List<T>},
  tail_proof: PlanPopulation(~T, children, rest)) ->
  PlanPopulation(~T, tree <> children, Allocation.dispatch_prepare_parallel_8(~T, rest, placements, shift)):
  match rest:
    case Allocation.PlanningFailure{failure}: {==}
    case Allocation.ChildrenPlanned{tail, canvas}:
      +shifted = Allocation.shift_placements(~T, placements, shift)
      Equal.trans(+List<T>,
        SpaceLaws.placement_values(~T, List.append(&2, Space.Placement<T>, shifted, tail)),
        List.append(&2, T, SpaceLaws.placement_values(~T, shifted), SpaceLaws.placement_values(~T, tail)), tree <> children,
        Std.map_app(~Space.Placement<T>, ~T, ~(value => SpaceLaws.placement_value(~T, value)), shifted, tail),
        Equal.trans(+List<T>,
          List.append(&2, T, SpaceLaws.placement_values(~T, shifted), SpaceLaws.placement_values(~T, tail)),
          List.append(&2, T, tree <> Nil{}, SpaceLaws.placement_values(~T, tail)), tree <> children,
          Equal.cong(+List<T>, +List<T>, (values => List.append(&2, T, values, SpaceLaws.placement_values(~T, tail))),
            SpaceLaws.placement_values(~T, shifted), tree <> Nil{},
            Equal.trans(+List<T>, SpaceLaws.placement_values(~T, shifted), SpaceLaws.placement_values(~T, placements), tree <> Nil{}, shift_population(~T, placements, shift), head_proof)),
          Equal.cong(+List<T>, +List<T>, (values => tree <> values), SpaceLaws.placement_values(~T, tail), children, tail_proof)))

def packed_parallel_population(~T: Data, ~key_of: T -> String, +first: Space.Packing<T>, +tree: T, +axis: Allocation.Axis, +alignment: Spatial.Alignment, +rest: Allocation.ChildPlan<T>, +children: +List<T>,
  head_proof: PackingPopulation(~T, tree <> Nil{}, first), tail_proof: PlanPopulation(~T, children, rest)) ->
  PlanPopulation(~T, tree <> children, Allocation.packed_parallel(~T, ~key_of, first, tree, axis, alignment, rest)):
  match first:
    case Space.Insufficient{required, available}: {==}
    case Space.Packed{placements, unused}:
      parallel_append_population(~T, rest, placements, children, tree, Allocation.alignment_offset(alignment, unused), head_proof, tail_proof)

def clearance_pack_checked_population(~T: Data, +fits: Bool, +slots: +List<Space.Slot<T>>, +clearance: Nat, +available: Nat) ->
  PackingPopulation(~T, SpaceLaws.slot_values(~T, slots), Allocation.clearance_pack_checked(~T, fits, slots, clearance, available)):
  match fits:
    case False{}: {==}
    case True{}: shared_population(~T, slots, 0n, Nat.sub(available, clearance))

def clearance_pack_population(~T: Data, +slots: +List<Space.Slot<T>>, +clearance: Nat, +available: Nat) ->
  PackingPopulation(~T, SpaceLaws.slot_values(~T, slots), Allocation.clearance_pack(~T, slots, clearance, available)):
  clearance_pack_checked_population(~T, Nat.is_le(clearance, available), slots, clearance, available)

def parallel_population_step(~T: Data, ~key_of: T -> String, ~clearance_of: T -> Nat, +head: Space.Slot<T>, +tail: +List<Space.Slot<T>>, +axis: Allocation.Axis, +canvas: Nat, +alignment: Spatial.Alignment,
  proof: PlanPopulation(~T, SpaceLaws.slot_values(~T, tail), Allocation.prepare_parallel(~T, ~key_of, ~clearance_of, tail, axis, canvas, alignment))) ->
  PlanPopulation(~T, SpaceLaws.slot_values(~T, head <> tail), Allocation.prepare_parallel(~T, ~key_of, ~clearance_of, head <> tail, axis, canvas, alignment)):
  Space.Slot{+tree, +dimension} = head
  packed_parallel_population(~T, ~key_of, Allocation.clearance_pack(~T, Space.Slot{tree, dimension} <> Nil{}, clearance_of(tree), canvas), tree, axis, alignment,
    Allocation.prepare_parallel(~T, ~key_of, ~clearance_of, tail, axis, canvas, alignment), SpaceLaws.slot_values(~T, tail),
    clearance_pack_population(~T, Space.Slot{tree, dimension} <> Nil{}, clearance_of(tree), canvas), proof)

def parallel_population(~T: Data, ~key_of: T -> String, ~clearance_of: T -> Nat, +slots: +List<Space.Slot<T>>, +axis: Allocation.Axis, +canvas: Nat, +alignment: Spatial.Alignment) ->
  PlanPopulation(~T, SpaceLaws.slot_values(~T, slots), Allocation.prepare_parallel(~T, ~key_of, ~clearance_of, slots, axis, canvas, alignment)):
  Std.list_ind(~Space.Slot<T>, ~(values => @+actual_axis:Allocation.Axis -> @+actual_canvas:Nat -> @+actual_alignment:Spatial.Alignment ->
      PlanPopulation(~T, SpaceLaws.slot_values(~T, values), Allocation.prepare_parallel(~T, ~key_of, ~clearance_of, values, actual_axis, actual_canvas, actual_alignment))),
    ~(+actual_axis => +actual_canvas => +actual_alignment => {==}),
    ~(+head => +tail => proof => +actual_axis => +actual_canvas => +actual_alignment =>
      parallel_population_step(~T, ~key_of, ~clearance_of, head, tail, actual_axis, actual_canvas, actual_alignment, proof(actual_axis)(actual_canvas)(actual_alignment))), slots)(axis)(canvas)(alignment)

def sequential_population(~T: Data, +first: Space.Packing<T>, +slots: +List<Space.Slot<T>>, +key: String, +axis: Allocation.Axis, +alignment: Spatial.Alignment, +canvas: Nat,
  proof: PackingPopulation(~T, SpaceLaws.slot_values(~T, slots), first)) ->
  PlanPopulation(~T, SpaceLaws.slot_values(~T, slots), Allocation.dispatch_prepare_slots_9(~T, first, key, axis, alignment, canvas)):
  match first:
    case Space.Insufficient{required, available}: {==}
    case Space.Packed{placements, unused}:
      Equal.trans(+List<T>,
        SpaceLaws.placement_values(~T, Allocation.shift_placements(~T, placements, Allocation.alignment_offset(alignment, unused))),
        SpaceLaws.placement_values(~T, placements), SpaceLaws.slot_values(~T, slots), shift_population(~T, placements, Allocation.alignment_offset(alignment, unused)), proof)

def sequence_population(~T: Data, ~key_of: T -> String, ~clearance_of: T -> Nat, +is_sequence: Bool, +key: String, +axis: Allocation.Axis,
  +slots: +List<Space.Slot<T>>, +gap: Nat, +canvas: Nat, +alignment: Spatial.Alignment) ->
  PlanPopulation(~T, SpaceLaws.slot_values(~T, slots), Allocation.destructure_prepare_slots_sequence(~T, ~key_of, ~clearance_of, is_sequence, key, axis, slots, gap, canvas, alignment)):
  match is_sequence:
    case False{}: parallel_population(~T, ~key_of, ~clearance_of, slots, axis, canvas, alignment)
    case True{}: sequential_population(~T, Allocation.shared_pack(~T, slots, gap, canvas), slots, key, axis, alignment, canvas, shared_population(~T, slots, gap, canvas))

def slots_population(~T: Data, ~key_of: T -> String, ~clearance_of: T -> Nat, +key: String, +axis: Allocation.Axis, +rule: Model.Rule,
  +direction: Allocation.ResolvedDirection, +slots: +List<Space.Slot<T>>, +available: Nat) ->
  PlanPopulation(~T, SpaceLaws.slot_values(~T, slots), Allocation.prepare_slots(~T, ~key_of, ~clearance_of, key, axis, rule, direction, slots, available)):
  sequence_population(~T, ~key_of, ~clearance_of, Allocation.sequential(axis, direction), key, axis, slots, Allocation.rule_gap(rule),
    Allocation.resolved_canvas(direction, available, Allocation.canvas_size(Allocation.scrolls(axis, Allocation.rule_scroll(rule)), available, Allocation.required_canvas(~T, Allocation.sequential(axis, direction), slots, Allocation.rule_gap(rule)))),
    Allocation.axis_alignment(axis, direction, rule))

def inline_wrapper_population(~A: Data, ~E: Data, +result: Allocation.ChildPlan<Model.Tree<A, E>>, +children: +List<Model.Tree<A, E>>, +direction: Allocation.ResolvedDirection,
  proof: PlanPopulation(~Model.Tree<A, E>, children, result)) ->
  Rule.InlinePopulation(~A, ~E, children, Allocation.dispatch_prepare_inline_children_11(~A, ~E, result, direction)):
  match result:
    case Allocation.PlanningFailure{failure}: {==}
    case Allocation.ChildrenPlanned{placements, canvas}: proof

def inline_rule_unchecked_population(~A: Data, ~E: Data, +rule: Model.Rule, +key: String, +available: Nat, +slots: +List<Space.Slot<Model.Tree<A, E>>>) ->
  Rule.InlinePopulation(~A, ~E, SpaceLaws.slot_values(~Model.Tree<A, E>, slots), Allocation.prepare_inline_rule_unchecked(~A, ~E, rule, key, available, slots)):
  Model.Rule{+authored, main_alignment, cross_alignment, frame, border, width, height, minimum, scroll, position} = rule
  +direction = Allocation.resolve_direction(authored, Space.minimum_sequence(~Model.Tree<A, E>, slots, Allocation.rule_gap(rule)), available)
  inline_wrapper_population(~A, ~E,
    Allocation.prepare_slots(~Model.Tree<A, E>, ~(tree => Allocation.tree_key(~A, ~E, tree)), ~(tree => Allocation.outside_axis(Allocation.InlineAxis{}, Allocation.tree_rule(~A, ~E, tree))), key, Allocation.InlineAxis{}, rule, direction, slots, available),
    SpaceLaws.slot_values(~Model.Tree<A, E>, slots), direction,
    slots_population(~Model.Tree<A, E>, ~(tree => Allocation.tree_key(~A, ~E, tree)), ~(tree => Allocation.outside_axis(Allocation.InlineAxis{}, Allocation.tree_rule(~A, ~E, tree))), key, Allocation.InlineAxis{}, rule, direction, slots, available))

def inline_gap_population(~A: Data, ~E: Data, +valid: Bool, +rule: Model.Rule, +key: String, +available: Nat, +slots: +List<Space.Slot<Model.Tree<A, E>>>) ->
  Rule.InlinePopulation(~A, ~E, SpaceLaws.slot_values(~Model.Tree<A, E>, slots), Allocation.prepare_inline_gap(~A, ~E, valid, rule, key, available, slots)):
  match valid:
    case False{}: {==}
    case True{}: inline_rule_unchecked_population(~A, ~E, rule, key, available, slots)

def inline_rule_population(~A: Data, ~E: Data, +rule: Model.Rule, +key: String, +available: Nat, +slots: +List<Space.Slot<Model.Tree<A, E>>>) ->
  Rule.InlinePopulation(~A, ~E, SpaceLaws.slot_values(~Model.Tree<A, E>, slots), Allocation.prepare_inline_rule(~A, ~E, rule, key, available, slots)):
  inline_gap_population(~A, ~E, Allocation.layered_gap_valid(rule), rule, key, available, slots)

def inline_dispatch_population(~A: Data, ~E: Data, +result: Allocation.SlotsOutcome<Model.Tree<A, E>>, +children: +List<Model.Tree<A, E>>, +key: String, +rule: Model.Rule, +available: Nat,
  proof: SlotsPopulation(~Model.Tree<A, E>, children, result)) ->
  Rule.InlinePopulation(~A, ~E, children, Allocation.dispatch_prepare_inline_children_10(~A, ~E, result, key, rule, available)):
  match result:
    case Allocation.SlotsFailure{failure}: {==}
    case Allocation.SlotsReady{slots}:
      Std.transport(+List<Model.Tree<A, E>>, SpaceLaws.slot_values(~Model.Tree<A, E>, slots),
        (values => Rule.InlinePopulation(~A, ~E, values, Allocation.prepare_inline_rule(~A, ~E, rule, key, available, slots))),
        inline_rule_population(~A, ~E, rule, key, available, slots), children,
        Equal.sym(+List<Model.Tree<A, E>>, SpaceLaws.slot_values(~Model.Tree<A, E>, slots), children, proof))

def inline_population(~A: Data, ~E: Data, +key: String, +rule: Model.Rule, +children: +List<Model.Tree<A, E>>, +available: Nat) ->
  Rule.InlinePopulation(~A, ~E, children, Allocation.prepare_inline_children(~A, ~E, key, rule, children, available)):
  inline_dispatch_population(~A, ~E, Allocation.width_slots(~A, ~E, children, available), children, key, rule, available,
    width_population(~A, ~E, children, available))

def block_wrapper_population(~A: Data, ~E: Data, +result: Allocation.ChildPlan<Allocation.MeasuredTree<A, E>>, +children: +List<Allocation.MeasuredTree<A, E>>,
  proof: PlanPopulation(~Allocation.MeasuredTree<A, E>, children, result)) -> Rule.BlockPopulation(~A, ~E, children, result):
  match result:
    case Allocation.PlanningFailure{failure}: {==}
    case Allocation.ChildrenPlanned{placements, canvas}: proof

def block_dispatch_population(~A: Data, ~E: Data, +result: Allocation.SlotsOutcome<Allocation.MeasuredTree<A, E>>, +children: +List<Allocation.MeasuredTree<A, E>>,
  +key: String, +rule: Model.Rule, +direction: Allocation.ResolvedDirection, +available: Nat,
  proof: SlotsPopulation(~Allocation.MeasuredTree<A, E>, children, result)) ->
  Rule.BlockPopulation(~A, ~E, children, Allocation.dispatch_prepare_block_children_17(~A, ~E, result, key, rule, direction, available)):
  match result:
    case Allocation.SlotsFailure{failure}: {==}
    case Allocation.SlotsReady{slots}:
      Std.transport(+List<Allocation.MeasuredTree<A, E>>, SpaceLaws.slot_values(~Allocation.MeasuredTree<A, E>, slots),
        (values => Rule.BlockPopulation(~A, ~E, values,
          Allocation.prepare_slots(~Allocation.MeasuredTree<A, E>, ~(tree => Allocation.measured_key(~A, ~E, tree)), ~(tree => Allocation.outside_axis(Allocation.BlockAxis{}, Allocation.measured_rule(~A, ~E, tree))), key, Allocation.BlockAxis{}, rule, direction, slots, available))),
        block_wrapper_population(~A, ~E,
          Allocation.prepare_slots(~Allocation.MeasuredTree<A, E>, ~(tree => Allocation.measured_key(~A, ~E, tree)), ~(tree => Allocation.outside_axis(Allocation.BlockAxis{}, Allocation.measured_rule(~A, ~E, tree))), key, Allocation.BlockAxis{}, rule, direction, slots, available),
          SpaceLaws.slot_values(~Allocation.MeasuredTree<A, E>, slots),
          slots_population(~Allocation.MeasuredTree<A, E>, ~(tree => Allocation.measured_key(~A, ~E, tree)), ~(tree => Allocation.outside_axis(Allocation.BlockAxis{}, Allocation.measured_rule(~A, ~E, tree))), key, Allocation.BlockAxis{}, rule, direction, slots, available)),
        children, Equal.sym(+List<Allocation.MeasuredTree<A, E>>, SpaceLaws.slot_values(~Allocation.MeasuredTree<A, E>, slots), children, proof))

def block_population(~A: Data, ~E: Data, +key: String, +rule: Model.Rule, +direction: Allocation.ResolvedDirection,
  +children: +List<Allocation.MeasuredTree<A, E>>, +available: Nat) ->
  Rule.BlockPopulation(~A, ~E, children, Allocation.prepare_block_children(~A, ~E, key, rule, direction, children, available)):
  block_dispatch_population(~A, ~E, Allocation.height_slots(~A, ~E, children, available), children, key, rule, direction, available,
    height_population(~A, ~E, children, available))

def Rule.evidence(A, E):
  Rule.Requirements{
    +key => +rule => +children => +available => inline_population(~A, ~E, key, rule, children, available),
    +key => +rule => +direction => +children => +available => block_population(~A, ~E, key, rule, direction, children, available)}


def Rule.aligned_layer_bounds(outside, horizontal, vertical, rule, left, top, available_width, available_height, width, height):
  Enclosure.Insets{inline, block} = outside
  {==}

def Rule.aligned_layer_clearance(outside, horizontal, vertical): {==}

def root_position_policy(~A: Data, ~E: Data, +position: Spatial.Position, +tree: Allocation.MeasuredTree<A, E>, +offered: Spatial.Box, +offset: Nat, +height: Nat) ->
  Rule.RootBoundsPolicy(~A, ~E, position, tree, offered, offset, height, Allocation.root_bounds_position(~A, ~E, position, tree, offered, offset, height)):
  match position:
    case Spatial.InFlow{}: {==}
    case Spatial.CenteredLayer{outside}: {==}
    case Spatial.AlignedLayer{outside, horizontal, vertical}: {==}
    case Spatial.AnchoredLayer{key, anchor, outside, gap, alignment}: {==}

def Rule.root_position(A, E, tree, offered, offset, height):
  root_position_policy(~A, ~E, Model.rule_position(Allocation.measured_rule(~A, ~E, tree)), tree, offered, offset, height)

def Rule.root_width_clearance(A, E, slots, tree, width, samples):
  {==}

def Rule.root_height_clearance(A, E, slots, tree, offered):
  {==}

def Rule.root_allocation_bounds(A, E, tree, value, rest, offset, height, offered):
  {==}

def measured_preferred(~A: Data, ~E: Data, +tree: Allocation.MeasuredTree<A, E>) ->
  {ModelRules.preferred_covers_minimum(Allocation.measured_demand(~A, ~E, tree)) == True{} : Bool}:
  match tree:
    case Allocation.MeasuredLeaf{key, value, interaction, rule, demand, height, outer_width, inline_offset, content_height}:
      ModelProof.outer_preferred(~E, Model.fixed_leaf_content(demand, content_height), rule, interaction)
    case Allocation.MeasuredContainer{key, value, interaction, +rule, outer_width, inline_offset, direction, children}:
      ModelProof.outer_preferred(~E, Allocation.measured_content_demand(~A, ~E, children, direction, Allocation.rule_gap(rule)), rule, interaction)

def Rule.measured_preferred(A, E, tree):
  measured_preferred(~A, ~E, tree)

def measured_authored_floor(~A: Data, ~E: Data, +tree: Allocation.MeasuredTree<A, E>) ->
  {ModelRules.extent_contains(Model.minimum_demand(Allocation.measured_demand(~A, ~E, tree)), ModelRules.rule_authored_minimum(Allocation.measured_rule(~A, ~E, tree))) == True{} : Bool}:
  match tree:
    case Allocation.MeasuredLeaf{key, value, interaction, rule, demand, height, outer_width, inline_offset, content_height}:
      ModelProof.outer_authored_floor(~E, Model.fixed_leaf_content(demand, content_height), rule, interaction)
    case Allocation.MeasuredContainer{key, value, interaction, +rule, outer_width, inline_offset, direction, children}:
      ModelProof.outer_authored_floor(~E, Allocation.measured_content_demand(~A, ~E, children, direction, Allocation.rule_gap(rule)), rule, interaction)

def Rule.measured_authored_floor(A, E, tree):
  measured_authored_floor(~A, ~E, tree)
