import Base
import ./natural-size.bend as Size

type Requirements is Type:
  Requirements{
    addition_capacity: @+capacity:Nat -> @+left:Nat -> @+right:Nat ->
      @conflict:{Nat.is_le(left, Nat.sub(capacity, right)) == False{} : Bool} ->
      {Size.checked_add(capacity, left, right) == None{} : Maybe<&2, Nat>},
    multiplication_capacity: @+capacity:Nat -> @+left:Nat -> @+right:Nat ->
      @nonzero:{Nat.is_eq(right, 0n) == False{} : Bool} ->
      @conflict:{Nat.is_le(left, Nat.div(capacity, right)) == False{} : Bool} ->
      {Size.checked_mul(capacity, left, right) == None{} : Maybe<&2, Nat>},
    multiplication_zero: @+capacity:Nat -> @left:Nat ->
      {Size.checked_mul(capacity, left, 0n) == Some{0n} : Maybe<&2, Nat>}}

law evidence:
  Requirements
