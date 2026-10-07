import Base
import ../space.bend as Space
import ../space-laws.bend as Allocation
import ../container-space-laws.bend as Rule
import ./space.bend as AllocationProof

# Both subtractions are justified by the full minimum, including both insets.
def inset_budget_from(+leading: Nat, +trailing: Nat, +minimum: Nat, +available: Nat,
  evidence: {Nat.is_le(Nat.add(minimum, trailing), Nat.sub(available, leading)) == True{} : Bool} &
    {Nat.add(leading, Nat.sub(available, leading)) == available : Nat}) ->
  {Nat.is_le(minimum, Rule.inner_budget(leading, trailing, available)) == True{} : Bool} &
  {Nat.add(leading, Nat.add(Rule.inner_budget(leading, trailing, available), trailing)) == available : Nat}:
  (+remaining_fits, leading_balance) = evidence
  +remaining = Nat.sub(available, leading)
  +inner = Rule.inner_budget(leading, trailing, available)
  inner_fits = AllocationProof.room_fits(minimum, trailing, remaining, remaining_fits)
  swapped_fits = Equal.trans(Bool, Nat.is_le(Nat.add(trailing, minimum), remaining),
    Nat.is_le(Nat.add(minimum, trailing), remaining), True{},
    Equal.cong(Nat, Bool, (n => Nat.is_le(n, remaining)), Nat.add(trailing, minimum),
      Nat.add(minimum, trailing), AllocationProof.add_comm(trailing, minimum)), remaining_fits)
  trailing_balance = AllocationProof.second({Nat.is_le(minimum, Nat.sub(remaining, trailing)) == True{} : Bool},
    {Nat.add(trailing, Nat.sub(remaining, trailing)) == remaining : Nat},
    AllocationProof.residual(trailing, minimum, remaining, swapped_fits))
  inner_balance = Equal.trans(Nat, Nat.add(inner, trailing), Nat.add(trailing, inner), remaining,
    AllocationProof.add_comm(inner, trailing), trailing_balance)
  (inner_fits, Equal.trans(Nat, Nat.add(leading, Nat.add(inner, trailing)), Nat.add(leading, remaining), available,
    Equal.cong(Nat, Nat, (n => Nat.add(leading, n)), Nat.add(inner, trailing), remaining, inner_balance), leading_balance))

def inset_budget(+leading: Nat, +trailing: Nat, +minimum: Nat, +available: Nat,
  fits: {Nat.is_le(Nat.add(leading, Nat.add(minimum, trailing)), available) == True{} : Bool}) ->
  {Nat.is_le(minimum, Rule.inner_budget(leading, trailing, available)) == True{} : Bool} &
  {Nat.add(leading, Nat.add(Rule.inner_budget(leading, trailing, available), trailing)) == available : Nat}:
  inset_budget_from(leading, trailing, minimum, available,
    AllocationProof.residual(leading, Nat.add(minimum, trailing), available, fits))

def finish_claim(~A: Data, +leading: Nat, +trailing: Nat, +gap: Nat, +slots: +List<Space.Slot<A>>, +available: Nat,
  +result: Space.Allocation<A>,
  evidence: Allocation.AllocationEvidence<A, slots, gap, leading, Rule.inner_budget(leading, trailing, available), result>,
  balance: {Nat.add(leading, Nat.add(Rule.inner_budget(leading, trailing, available), trailing)) == available : Nat}) ->
  Rule.ContainerClaim(~A, Space.Container{leading, trailing, gap, slots}, available, Space.finish(~A, result)):
  Space.Allocation{+placements, +unused} = result
  Allocation.AllocationEvidence{payloads, bounds, positions, +total} = evidence
  (Allocation.AllocationEvidence{payloads, bounds, positions, total},
    Equal.trans(Nat, Nat.add(leading, Nat.add(Nat.add(Allocation.used(~A, placements, gap), unused), trailing)),
      Nat.add(leading, Nat.add(Rule.inner_budget(leading, trailing, available), trailing)), available,
      Equal.cong(Nat, Nat, (n => Nat.add(leading, Nat.add(n, trailing))),
        Nat.add(Allocation.used(~A, placements, gap), unused), Rule.inner_budget(leading, trailing, available), total), balance))

def accepted_claim(~A: Data, +leading: Nat, +trailing: Nat, +gap: Nat, +slots: +List<Space.Slot<A>>, +available: Nat,
  evidence: {Nat.is_le(Space.minimum_sequence(~A, slots, gap), Rule.inner_budget(leading, trailing, available)) == True{} : Bool} &
    {Nat.add(leading, Nat.add(Rule.inner_budget(leading, trailing, available), trailing)) == available : Nat}) ->
  Rule.ContainerClaim(~A, Space.Container{leading, trailing, gap, slots}, available,
    Space.finish(~A, Space.place_from(~A, slots, gap, leading, Rule.inner_budget(leading, trailing, available)))):
  (inner_fits, balance) = evidence
  finish_claim(~A, leading, trailing, gap, slots, available,
    Space.place_from(~A, slots, gap, leading, Rule.inner_budget(leading, trailing, available)),
    AllocationProof.place_evidence(~A, slots, gap, leading, Rule.inner_budget(leading, trailing, available), inner_fits), balance)

def feasible_claim(~A: Data, +feasible: Bool, +container: Space.Container<A>, +available: Nat,
  decision: {Nat.is_le(Space.container_required(~A, container), available) == feasible : Bool}) ->
  Rule.ContainerClaim(~A, container, available, Space.feasible_container(~A, feasible, container, available)):
  match feasible:
    case False{}:
      Space.Container{leading, trailing, gap, slots} = container
      ({==}, ({==}, decision))
    case True{}:
      Space.Container{+leading, +trailing, +gap, +slots} = container
      accepted_claim(~A, leading, trailing, gap, slots, available,
        inset_budget(leading, trailing, Space.minimum_sequence(~A, slots, gap), available, decision))

def complete(~A: Data, +container: Space.Container<A>, +available: Nat) ->
  Rule.ContainerClaim(~A, container, available, Space.pack_container(~A, container, available)):
  feasible_claim(~A, Nat.is_le(Space.container_required(~A, container), available), container, available, {==})

def Rule.evidence(A):
  Rule.Requirement{+container => +available => complete(~A, container, available)}
