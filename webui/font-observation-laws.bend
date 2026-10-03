import Base
import ./font-observation.bend as F
import ./typography.bend as T

def stale(+state: F.State, +received: Nat, +metrics: +List<T.Metric>,
  different: {Nat.is_eq(F.generation(state), received) == False{} : Bool}) ->
  {F.accept(state, F.Observation{received, metrics}) == state : F.State}:
  Equal.cong(Bool, F.State, (owned => F.receive(owned, state, metrics)),
    Nat.is_eq(F.generation(state), received), False{}, different)

def ready_receive(owned: Bool, generation: Nat, scale: T.Scale, body: T.Metric, metrics: +List<T.Metric>) ->
  {F.receive(owned, F.Ready{generation, scale, body}, metrics) ==
    F.Ready{generation, scale, body} : F.State}:
  match owned:
    case True{}: {==}
    case False{}: {==}

def ready_duplicate(+generation: Nat, +scale: T.Scale, +body: T.Metric,
  received: Nat, metrics: +List<T.Metric>) ->
  {F.accept(F.Ready{generation, scale, body}, F.Observation{received, metrics}) ==
    F.Ready{generation, scale, body} : F.State}:
  ready_receive(Nat.is_eq(generation, received), generation, scale, body, metrics)

def failed_receive(owned: Bool, generation: Nat, scale: T.Scale, metrics: +List<T.Metric>) ->
  {F.receive(owned, F.Failed{generation, scale}, metrics) == F.Failed{generation, scale} : F.State}:
  match owned:
    case True{}: {==}
    case False{}: {==}

def failed_duplicate(+generation: Nat, +scale: T.Scale, received: Nat, metrics: +List<T.Metric>) ->
  {F.accept(F.Failed{generation, scale}, F.Observation{received, metrics}) ==
    F.Failed{generation, scale} : F.State}:
  failed_receive(Nat.is_eq(generation, received), generation, scale, metrics)

def success(+generation: Nat, +scale: T.Scale, +metric: T.Metric,
  valid: {T.valid_body(metric) == True{} : Bool}) ->
  {F.admit(generation, scale, [metric]) == F.Ready{generation, scale, metric} : F.State}:
  Equal.cong(Bool, F.State, (checked => F.admit_checked(checked, generation, scale, metric)),
    T.valid_body(metric), True{}, valid)

def invalid(+generation: Nat, +scale: T.Scale, +metric: T.Metric,
  bad: {T.valid_body(metric) == False{} : Bool}) ->
  {F.admit(generation, scale, [metric]) == F.Failed{generation, scale} : F.State}:
  Equal.cong(Bool, F.State, (checked => F.admit_checked(checked, generation, scale, metric)),
    T.valid_body(metric), False{}, bad)

def current_pending(+generation: Nat, +scale: T.Scale, +received: Nat, +metrics: +List<T.Metric>,
  owned: {Nat.is_eq(generation, received) == True{} : Bool}) ->
  {F.accept(F.Pending{generation, scale}, F.Observation{received, metrics}) ==
    F.admit(generation, scale, metrics) : F.State}:
  Equal.cong(Bool, F.State, (current => F.receive(current, F.Pending{generation, scale}, metrics)),
    Nat.is_eq(generation, received), True{}, owned)

def empty(generation: Nat, scale: T.Scale) ->
  {F.admit(generation, scale, Nil{}) == F.Failed{generation, scale} : F.State}:
  {==}

def multiple(generation: Nat, scale: T.Scale, first: T.Metric, second: T.Metric, rest: +List<T.Metric>) ->
  {F.admit(generation, scale, Con{first, Con{second, rest}}) == F.Failed{generation, scale} : F.State}:
  {==}

def ready_valid(state: F.State) -> Bool:
  match state:
    case F.Ready{generation, scale, body}: T.valid_body(body)
    case _: True{}

def checked_valid(generation: Nat, scale: T.Scale, +metric: T.Metric, +checked: Bool,
  correspondence: {T.valid_body(metric) == checked : Bool}) ->
  {ready_valid(F.admit_checked(checked, generation, scale, metric)) == True{} : Bool}:
  match checked:
    case True{}: correspondence
    case False{}: {==}

def tail_valid(generation: Nat, scale: T.Scale, +metric: T.Metric, rest: +List<T.Metric>) ->
  {ready_valid(F.admit_tail(generation, scale, metric, rest)) == True{} : Bool}:
  match rest:
    case Nil{}: checked_valid(generation, scale, metric, T.valid_body(metric), {==})
    case Con{other, tail}: {==}

def admitted_valid(generation: Nat, scale: T.Scale, metrics: +List<T.Metric>) ->
  {ready_valid(F.admit(generation, scale, metrics)) == True{} : Bool}:
  match metrics:
    case Nil{}: {==}
    case Con{metric, rest}: tail_valid(generation, scale, metric, rest)

def retag_scale(state: F.State, generation: Nat) ->
  {F.scale(F.retag(state, generation)) == F.scale(state) : T.Scale}:
  match state:
    case F.Pending{old, scale}: {==}
    case F.Ready{old, scale, body}: {==}
    case F.Failed{old, scale}: {==}

def retag_body(state: F.State, generation: Nat) ->
  {F.body(F.retag(state, generation)) == F.body(state) : Maybe<&2, T.Metric>}:
  match state:
    case F.Pending{old, scale}: {==}
    case F.Ready{old, scale, body}: {==}
    case F.Failed{old, scale}: {==}

def retag_pending(state: F.State, generation: Nat) ->
  {F.pending(F.retag(state, generation)) == F.pending(state) : Bool}:
  match state:
    case F.Pending{old, scale}: {==}
    case F.Ready{old, scale, body}: {==}
    case F.Failed{old, scale}: {==}

def retag_generation(state: F.State, generation: Nat) ->
  {F.generation(F.retag(state, generation)) == generation : Nat}:
  match state:
    case F.Pending{old, scale}: {==}
    case F.Ready{old, scale, body}: {==}
    case F.Failed{old, scale}: {==}

def pending_request(generation: Nat, scale: T.Scale) ->
  {F.request(F.Pending{generation, scale}) == F.Plan{generation,
    [T.spec(T.Probe{"@font/body", "0", T.resolved(T.Presentation{T.Body{}, T.Regular{}, scale}),
      T.WrapWords{}, None{}, "0"})]} : F.Plan}:
  {==}

def ready_request(generation: Nat, scale: T.Scale, metric: T.Metric) ->
  {F.request(F.Ready{generation, scale, metric}) == F.Plan{generation, Nil{}} : F.Plan}:
  {==}

def failed_request(generation: Nat, scale: T.Scale) ->
  {F.request(F.Failed{generation, scale}) == F.Plan{generation, Nil{}} : F.Plan}:
  {==}

def begin_scale(generation: Nat, root: Nat) ->
  {F.begin(generation, root) == F.Pending{generation,
    T.Scale{Nat.sub(Nat.max(1000n, Nat.div(root, 16n)), 1000n)}} : F.State}:
  {==}

def received_success(+generation: Nat, +scale: T.Scale, +received: Nat, +metric: T.Metric,
  owned: {Nat.is_eq(generation, received) == True{} : Bool},
  valid: {T.valid_body(metric) == True{} : Bool}) ->
  {F.accept(F.Pending{generation, scale}, F.Observation{received, [metric]}) ==
    F.Ready{generation, scale, metric} : F.State}:
  Equal.trans(F.State, F.accept(F.Pending{generation, scale}, F.Observation{received, [metric]}),
    F.admit(generation, scale, [metric]), F.Ready{generation, scale, metric},
    current_pending(generation, scale, received, [metric], owned), success(generation, scale, metric, valid))

def received_invalid(+generation: Nat, +scale: T.Scale, +received: Nat, +metric: T.Metric,
  owned: {Nat.is_eq(generation, received) == True{} : Bool},
  bad: {T.valid_body(metric) == False{} : Bool}) ->
  {F.accept(F.Pending{generation, scale}, F.Observation{received, [metric]}) ==
    F.Failed{generation, scale} : F.State}:
  Equal.trans(F.State, F.accept(F.Pending{generation, scale}, F.Observation{received, [metric]}),
    F.admit(generation, scale, [metric]), F.Failed{generation, scale},
    current_pending(generation, scale, received, [metric], owned), invalid(generation, scale, metric, bad))

def received_empty(+generation: Nat, +scale: T.Scale, +received: Nat,
  owned: {Nat.is_eq(generation, received) == True{} : Bool}) ->
  {F.accept(F.Pending{generation, scale}, F.Observation{received, Nil{}}) ==
    F.Failed{generation, scale} : F.State}:
  current_pending(generation, scale, received, Nil{}, owned)

def received_multiple(+generation: Nat, +scale: T.Scale, +received: Nat,
  +first: T.Metric, +second: T.Metric, +rest: +List<T.Metric>,
  owned: {Nat.is_eq(generation, received) == True{} : Bool}) ->
  {F.accept(F.Pending{generation, scale}, F.Observation{received, Con{first, Con{second, rest}}}) ==
    F.Failed{generation, scale} : F.State}:
  current_pending(generation, scale, received, Con{first, Con{second, rest}}, owned)

def received_valid(+generation: Nat, +scale: T.Scale, +received: Nat, +metrics: +List<T.Metric>,
  owned: {Nat.is_eq(generation, received) == True{} : Bool}) ->
  {ready_valid(F.accept(F.Pending{generation, scale}, F.Observation{received, metrics})) == True{} : Bool}:
  Equal.trans(Bool, ready_valid(F.accept(F.Pending{generation, scale}, F.Observation{received, metrics})),
    ready_valid(F.admit(generation, scale, metrics)), True{},
    Equal.cong(F.State, Bool, ready_valid,
      F.accept(F.Pending{generation, scale}, F.Observation{received, metrics}),
      F.admit(generation, scale, metrics), current_pending(generation, scale, received, metrics, owned)),
    admitted_valid(generation, scale, metrics))

def retag_pending_variant(old: Nat, generation: Nat, scale: T.Scale) ->
  {F.retag(F.Pending{old, scale}, generation) == F.Pending{generation, scale} : F.State}:
  {==}

def retag_ready_variant(old: Nat, generation: Nat, scale: T.Scale, body: T.Metric) ->
  {F.retag(F.Ready{old, scale, body}, generation) == F.Ready{generation, scale, body} : F.State}:
  {==}

def retag_failed_variant(old: Nat, generation: Nat, scale: T.Scale) ->
  {F.retag(F.Failed{old, scale}, generation) == F.Failed{generation, scale} : F.State}:
  {==}
