import Base
import ../font-observation-laws.bend as Rule
import ../font-observation.bend as F
import ../typography.bend as T

def Rule.stale(state, received, metrics, different):
  Equal.cong(Bool, F.State, (owned => F.receive(owned, state, Nil{}, metrics)),
    Nat.is_eq(F.generation(state), received), False{}, different)

def ready_receive(owned: Bool, generation: Nat, scale: T.Scale, body: T.Metric, metrics: +List<T.Metric>) ->
  {F.receive(owned, F.Ready{generation, scale, body, Nil{}}, Nil{}, metrics) ==
    F.Ready{generation, scale, body, Nil{}} : F.State}:
  match owned:
    case True{}: {==}
    case False{}: {==}

def Rule.ready_duplicate(generation, scale, body, received, metrics):
  ready_receive(Nat.is_eq(generation, received), generation, scale, body, metrics)

def failed_receive(owned: Bool, generation: Nat, scale: T.Scale, metrics: +List<T.Metric>) ->
  {F.receive(owned, F.Failed{generation, scale}, Nil{}, metrics) == F.Failed{generation, scale} : F.State}:
  match owned:
    case True{}: {==}
    case False{}: {==}

def Rule.failed_duplicate(generation, scale, received, metrics):
  failed_receive(Nat.is_eq(generation, received), generation, scale, metrics)

def success(+generation: Nat, +scale: T.Scale, +metric: T.Metric,
  valid: {T.valid_body(metric) == True{} : Bool}) ->
  {F.admit(generation, scale, [metric]) == F.Ready{generation, scale, metric, Nil{}} : F.State}:
  Equal.cong(Bool, F.State, (checked => F.admit_checked(checked, generation, scale, metric)),
    T.valid_body(metric), True{}, valid)

def invalid(+generation: Nat, +scale: T.Scale, +metric: T.Metric,
  bad: {T.valid_body(metric) == False{} : Bool}) ->
  {F.admit(generation, scale, [metric]) == F.Failed{generation, scale} : F.State}:
  Equal.cong(Bool, F.State, (checked => F.admit_checked(checked, generation, scale, metric)),
    T.valid_body(metric), False{}, bad)

def Rule.current_pending(generation, scale, received, metrics, owned):
  Equal.cong(Bool, F.State, (current => F.receive(current, F.Pending{generation, scale}, Nil{}, metrics)),
    Nat.is_eq(generation, received), True{}, owned)

def checked_valid(generation: Nat, scale: T.Scale, +metric: T.Metric, +checked: Bool,
  correspondence: {T.valid_body(metric) == checked : Bool}) ->
  {Rule.ready_valid(F.admit_checked(checked, generation, scale, metric)) == True{} : Bool}:
  match checked:
    case True{}: correspondence
    case False{}: {==}

def tail_valid(generation: Nat, scale: T.Scale, +metric: T.Metric, rest: +List<T.Metric>) ->
  {Rule.ready_valid(F.admit_tail(generation, scale, metric, rest)) == True{} : Bool}:
  match rest:
    case Nil{}: checked_valid(generation, scale, metric, T.valid_body(metric), {==})
    case Con{other, tail}: {==}

def admitted_valid(generation: Nat, scale: T.Scale, metrics: +List<T.Metric>) ->
  {Rule.ready_valid(F.admit(generation, scale, metrics)) == True{} : Bool}:
  match metrics:
    case Nil{}: {==}
    case Con{metric, rest}: tail_valid(generation, scale, metric, rest)

def Rule.retag_scale(state, generation):
  match state:
    case F.Pending{old, scale}: {==}
    case F.Ready{old, scale, body, +content_cache}: {==}
    case F.Failed{old, scale}: {==}

def Rule.retag_body(state, generation):
  match state:
    case F.Pending{old, scale}: {==}
    case F.Ready{old, scale, body, +content_cache}: {==}
    case F.Failed{old, scale}: {==}

def Rule.retag_pending(state, generation):
  match state:
    case F.Pending{old, scale}: {==}
    case F.Ready{old, scale, body, +content_cache}: {==}
    case F.Failed{old, scale}: {==}

def Rule.retag_generation(state, generation):
  match state:
    case F.Pending{old, scale}: {==}
    case F.Ready{old, scale, body, +content_cache}: {==}
    case F.Failed{old, scale}: {==}

def Rule.pending_request(capacity, generation, scale):
  {==}

def Rule.ready_request(capacity, generation, scale, metric):
  {==}

def Rule.failed_request(capacity, generation, scale):
  {==}

def Rule.begin_scale(generation, root):
  {==}

def Rule.received_success(generation, scale, received, metric, owned, valid):
  Equal.trans(F.State, F.accept(F.Pending{generation, scale}, Nil{}, F.Observation{received, [metric]}),
    F.admit(generation, scale, [metric]), F.Ready{generation, scale, metric, Nil{}},
    Rule.current_pending(generation, scale, received, [metric], owned), success(generation, scale, metric, valid))

def Rule.received_invalid(generation, scale, received, metric, owned, bad):
  Equal.trans(F.State, F.accept(F.Pending{generation, scale}, Nil{}, F.Observation{received, [metric]}),
    F.admit(generation, scale, [metric]), F.Failed{generation, scale},
    Rule.current_pending(generation, scale, received, [metric], owned), invalid(generation, scale, metric, bad))

def Rule.received_empty(generation, scale, received, owned):
  Rule.current_pending(generation, scale, received, Nil{}, owned)

def Rule.received_multiple(generation, scale, received, first, second, rest, owned):
  Rule.current_pending(generation, scale, received, Con{first, Con{second, rest}}, owned)

def Rule.received_valid(generation, scale, received, metrics, owned):
  Equal.trans(Bool, Rule.ready_valid(F.accept(F.Pending{generation, scale}, Nil{}, F.Observation{received, metrics})),
    Rule.ready_valid(F.admit(generation, scale, metrics)), True{},
    Equal.cong(F.State, Bool, Rule.ready_valid,
      F.accept(F.Pending{generation, scale}, Nil{}, F.Observation{received, metrics}),
      F.admit(generation, scale, metrics), Rule.current_pending(generation, scale, received, metrics, owned)),
    admitted_valid(generation, scale, metrics))

def Rule.retag_pending_variant(old, generation, scale):
  {==}

def Rule.retag_ready_variant(old, generation, scale, body):
  {==}

def Rule.retag_failed_variant(old, generation, scale):
  {==}

# Content stamps authenticate the requested specification; physical accuracy is external.

def ready_no_outstanding(+generation: Nat, +scale: T.Scale, +body: T.Metric, +content: +List<T.Measured>,
  +specifications: +List<T.MeasurementSpec>, +metrics: +List<T.Metric>,
  complete: {F.missing(specifications, content) == Nil{} : +List<T.MeasurementSpec>}) ->
  {F.receive(True{}, F.Ready{generation, scale, body, content}, specifications, metrics) == F.Ready{generation, scale, body, content} : F.State}:
  Equal.cong(+List<T.MeasurementSpec>, F.State,
    (outstanding => F.ready_batch(generation, scale, body, content, specifications, outstanding, metrics)),
    F.missing(specifications, content), Nil{}, complete)
