import Base
import ./stdlib.bend as Std

def choose(~S: Data, condition: Bool, yes: S, no: S) -> S:
  match condition:
    case True{}: yes
    case False{}: no

def admit(~S: Data, state_valid: Bool, change_valid: Bool, candidate: S, +previous: S) -> S:
  choose(~S, state_valid, choose(~S, change_valid, candidate, previous), previous)

# The operations are Base operations. Proofs are imported Stdlib certificates;
# the application supplies only type/operation instantiations and equalities.
law append_right_identity:
  for -A: Data
  for +xs: +List<A>
  {List.append(&2, A, xs, Nil{}) == xs : +List<A>}

def append_right_identity(A, xs):
  Std.app_nil_r(A, xs)

law append_associative:
  for -A: Data
  for +xs: +List<A>
  for +ys: +List<A>
  for +zs: +List<A>
  {List.append(&2, A, List.append(&2, A, xs, ys), zs) == List.append(&2, A, xs, List.append(&2, A, ys, zs)) : +List<A>}

def append_associative(A, xs, ys, zs):
  Equal.sym(+List<A>, List.append(&2, A, xs, List.append(&2, A, ys, zs)),
    List.append(&2, A, List.append(&2, A, xs, ys), zs), Std.app_assoc(A, xs, ys, zs))

def replay(~S: Data, ~A: Data, ~step: S -> A -> S, events: +List<A>, state: S) -> S:
  List.foldl(~&2, ~A, ~S, ~step, events, state)

# Instantiate the existing standard fold-left theorem at the actual transition.
def replay_composition(~S: Data, ~A: Data, ~step: S -> A -> S,
  +first: +List<A>, +second: +List<A>, +state: S) ->
  {replay(~S, ~A, ~step, List.append(&2, A, first, second), state) ==
    replay(~S, ~A, ~step, second, replay(~S, ~A, ~step, first, state)) : S}:
  Std.fold_left_app(~S, ~A, ~step, first, second, state)

# A step that is the identity at the reached state may be inserted in a trace.
# The caller proves only the domain fact; trace algebra stays independent of it.
def replay_insert_identity(~S: Data, ~A: Data, ~step: S -> A -> S,
  +first: +List<A>, +second: +List<A>, +event: A, +state: S,
  identity: {step(replay(~S, ~A, ~step, first, state), event) == replay(~S, ~A, ~step, first, state) : S}) ->
  {replay(~S, ~A, ~step, List.append(&2, A, first, event <> second), state) ==
    replay(~S, ~A, ~step, List.append(&2, A, first, second), state) : S}:
  +middle = replay(~S, ~A, ~step, first, state)
  Equal.trans(S, replay(~S, ~A, ~step, List.append(&2, A, first, event <> second), state),
    replay(~S, ~A, ~step, second, step(middle, event)),
    replay(~S, ~A, ~step, List.append(&2, A, first, second), state),
    Std.fold_left_app(~S, ~A, ~step, first, event <> second, state),
    Equal.trans(S, replay(~S, ~A, ~step, second, step(middle, event)),
      replay(~S, ~A, ~step, second, middle), replay(~S, ~A, ~step, List.append(&2, A, first, second), state),
      Equal.cong(S, S, (value => replay(~S, ~A, ~step, second, value)), step(middle, event), middle, identity),
      Equal.sym(S, replay(~S, ~A, ~step, List.append(&2, A, first, second), state),
        replay(~S, ~A, ~step, second, middle), Std.fold_left_app(~S, ~A, ~step, first, second, state))))
