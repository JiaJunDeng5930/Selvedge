import Base
import ../../bendlib/stdlib.bend as Std
import ./space.bend as SpaceProof
import ../../bendlib/proofs/logic.bend as Logic

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
    case 0n: SpaceProof.zero_le(budget)
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
          SpaceProof.le_trans(rank(step(initial)), Nat.sub(rank(initial), 1n), count,
            decreases(initial), predecessor_in_budget(rank(initial), count, fits))))),
    budget)(seed, enough)
