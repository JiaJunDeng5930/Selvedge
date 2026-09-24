import Base

def choose(~S: Data, condition: Bool, yes: S, no: S) -> S:
  match condition:
    case True{}: yes
    case False{}: no

def admit(~S: Data, state_valid: Bool, change_valid: Bool, candidate: S, +previous: S) -> S:
  choose(~S, state_valid, choose(~S, change_valid, candidate, previous), previous)

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

# The usual induction principle for invariant safety in a transition system.
# It states nothing about progress: an identity-only system also preserves safety.
def replay_invariant(~S: Data, ~A: Data, ~step: S -> A -> S, ~valid: S -> Bool,
  ~preserves: @state:S -> @event:A -> {valid(state) == True{} : Bool} -> {valid(step(state, event)) == True{} : Bool},
  events: +List<A>, +state: S, evidence: {valid(state) == True{} : Bool}) ->
  {valid(replay(~S, ~A, ~step, events, state)) == True{} : Bool}:
  match events:
    case Nil{}: evidence
    case Con{+event, rest}:
      replay_invariant(~S, ~A, ~step, ~valid, ~preserves, rest, step(state, event), preserves(state, event, evidence))

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

# A step that is the identity at the reached state may be inserted in a trace.
# The caller proves only the domain fact; trace algebra stays independent of it.
def replay_insert_identity(~S: Data, ~A: Data, ~step: S -> A -> S,
  +first: +List<A>, +second: +List<A>, +event: A, +state: S,
  identity: {step(replay(~S, ~A, ~step, first, state), event) == replay(~S, ~A, ~step, first, state) : S}) ->
  {replay(~S, ~A, ~step, List.append(&2, A, first, event <> second), state) ==
    replay(~S, ~A, ~step, List.append(&2, A, first, second), state) : S}:
  match first:
    case Nil{}:
      %identity : {replay(~S, ~A, ~step, second, step(state, event)) == replay(~S, ~A, ~step, second, _) : S}
      {==}
    case Con{before, rest}:
      replay_insert_identity(~S, ~A, ~step, rest, second, event, step(state, before), identity)
