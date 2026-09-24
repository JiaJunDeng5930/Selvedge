import Base

# Lists form a monoid. The task implementation uses Base's append directly.
law append_right_identity:
  for -A: Data
  for +xs: +List<A>
  {List.append(&2, A, xs, Nil{}) == xs : +List<A>}

def append_right_identity(A, xs):
  match xs:
    case Nil{}:
      {==}
    case Con{+head, +tail}:
      %append_right_identity(A, tail) : {head <> List.append(&2, A, tail, Nil{}) == head <> _ : +List<A>}
      {==}

law append_associative:
  for -A: Data
  for +xs: +List<A>
  for +ys: +List<A>
  for +zs: +List<A>
  {List.append(&2, A, List.append(&2, A, xs, ys), zs) == List.append(&2, A, xs, List.append(&2, A, ys, zs)) : +List<A>}

def append_associative(A, xs, ys, zs):
  match xs:
    case Nil{}:
      {==}
    case Con{+head, +tail}:
      %append_associative(A, tail, ys, zs) : {head <> List.append(&2, A, List.append(&2, A, tail, ys), zs) == head <> _ : +List<A>}
      {==}

def replay(~S: Data, ~A: Data, ~step: S -> A -> S, events: +List<A>, state: S) -> S:
  match events:
    case Nil{}:
      state
    case Con{event, rest}:
      replay(~S, ~A, ~step, rest, step(state, event))

# Prove composition with an abstract step, then instantiate it at the program.
# The induction never needs to unfold a server transition or its wire encoder.
def replay_composition(~S: Data, ~A: Data, ~step: S -> A -> S,
  +first: +List<A>, +second: +List<A>, +state: S) ->
  {replay(~S, ~A, ~step, List.append(&2, A, first, second), state) ==
    replay(~S, ~A, ~step, second, replay(~S, ~A, ~step, first, state)) : S}:
  match first:
    case Nil{}: {==}
    case Con{event, rest}:
      replay_composition(~S, ~A, ~step, rest, second, step(state, event))
