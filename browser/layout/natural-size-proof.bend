import Base
import ./natural-size.bend as Size
import ./natural-size-rules.bend as Rule

def addition_capacity(+capacity: Nat, +left: Nat, +right: Nat,
  conflict: {Nat.is_le(left, Nat.sub(capacity, right)) == False{} : Bool}) ->
  {Size.checked_add(capacity, left, right) == None{} : Maybe<&2, Nat>}:
  Equal.cong(Bool, Maybe<&2, Nat>, (accepted => Size.add_if_capacity(accepted, left, right)),
    Nat.is_le(left, Nat.sub(capacity, right)), False{}, conflict)

def multiplication_capacity(+capacity: Nat, +left: Nat, +right: Nat,
  nonzero: {Nat.is_eq(right, 0n) == False{} : Bool},
  conflict: {Nat.is_le(left, Nat.div(capacity, right)) == False{} : Bool}) ->
  {Size.checked_mul(capacity, left, right) == None{} : Maybe<&2, Nat>}:
  Equal.trans(Maybe<&2, Nat>, Size.checked_mul(capacity, left, right), Size.multiply_zero_with_capacity(False{}, capacity, left, right), None{},
    Equal.cong(Bool, Maybe<&2, Nat>, (zero => Size.multiply_zero_with_capacity(zero, capacity, left, right)),
      Nat.is_eq(right, 0n), False{}, nonzero),
    Equal.cong(Bool, Maybe<&2, Nat>, (accepted => Size.multiply_if_capacity(accepted, left, right)),
      Nat.is_le(left, Nat.div(capacity, right)), False{}, conflict))

def multiplication_zero(+capacity: Nat, left: Nat) ->
  {Size.checked_mul(capacity, left, 0n) == Some{0n} : Maybe<&2, Nat>}:
  {==}

def Rule.evidence():
  Rule.Requirements{
    (capacity => left => right => conflict => addition_capacity(capacity, left, right, conflict)),
    (capacity => left => right => nonzero => conflict => multiplication_capacity(capacity, left, right, nonzero, conflict)),
    (capacity => left => multiplication_zero(capacity, left))}
