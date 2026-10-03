import Base
import ./font-observation.bend as F
import ./typography.bend as T

def stale(+state: F.State, +received: Nat, +metrics: +List<T.Metric>,
  different: {Nat.is_eq(F.generation(state), received) == False{} : Bool}) ->
  {F.accept(state, Nil{}, F.Observation{received, metrics}) == state : F.State}:
  Equal.cong(Bool, F.State, (owned => F.receive(owned, state, Nil{}, metrics)),
    Nat.is_eq(F.generation(state), received), False{}, different)

def ready_receive(owned: Bool, generation: Nat, scale: T.Scale, body: T.Metric, metrics: +List<T.Metric>) ->
  {F.receive(owned, F.Ready{generation, scale, body, Nil{}}, Nil{}, metrics) ==
    F.Ready{generation, scale, body, Nil{}} : F.State}:
  match owned:
    case True{}: {==}
    case False{}: {==}

def ready_duplicate(+generation: Nat, +scale: T.Scale, +body: T.Metric,
  received: Nat, metrics: +List<T.Metric>) ->
  {F.accept(F.Ready{generation, scale, body, Nil{}}, Nil{}, F.Observation{received, metrics}) ==
    F.Ready{generation, scale, body, Nil{}} : F.State}:
  ready_receive(Nat.is_eq(generation, received), generation, scale, body, metrics)

def failed_receive(owned: Bool, generation: Nat, scale: T.Scale, metrics: +List<T.Metric>) ->
  {F.receive(owned, F.Failed{generation, scale}, Nil{}, metrics) == F.Failed{generation, scale} : F.State}:
  match owned:
    case True{}: {==}
    case False{}: {==}

def failed_duplicate(+generation: Nat, +scale: T.Scale, received: Nat, metrics: +List<T.Metric>) ->
  {F.accept(F.Failed{generation, scale}, Nil{}, F.Observation{received, metrics}) ==
    F.Failed{generation, scale} : F.State}:
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

def current_pending(+generation: Nat, +scale: T.Scale, +received: Nat, +metrics: +List<T.Metric>,
  owned: {Nat.is_eq(generation, received) == True{} : Bool}) ->
  {F.accept(F.Pending{generation, scale}, Nil{}, F.Observation{received, metrics}) ==
    F.admit(generation, scale, metrics) : F.State}:
  Equal.cong(Bool, F.State, (current => F.receive(current, F.Pending{generation, scale}, Nil{}, metrics)),
    Nat.is_eq(generation, received), True{}, owned)

def empty(generation: Nat, scale: T.Scale) ->
  {F.admit(generation, scale, Nil{}) == F.Failed{generation, scale} : F.State}:
  {==}

def multiple(generation: Nat, scale: T.Scale, first: T.Metric, second: T.Metric, rest: +List<T.Metric>) ->
  {F.admit(generation, scale, Con{first, Con{second, rest}}) == F.Failed{generation, scale} : F.State}:
  {==}

def ready_valid(state: F.State) -> Bool:
  match state:
    case F.Ready{generation, scale, body, +content_cache}: T.valid_body(body)
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
    case F.Ready{old, scale, body, +content_cache}: {==}
    case F.Failed{old, scale}: {==}

def retag_body(state: F.State, generation: Nat) ->
  {F.body(F.retag(state, generation)) == F.body(state) : Maybe<&2, T.Metric>}:
  match state:
    case F.Pending{old, scale}: {==}
    case F.Ready{old, scale, body, +content_cache}: {==}
    case F.Failed{old, scale}: {==}

def retag_pending(state: F.State, generation: Nat) ->
  {F.pending(F.retag(state, generation)) == F.pending(state) : Bool}:
  match state:
    case F.Pending{old, scale}: {==}
    case F.Ready{old, scale, body, +content_cache}: {==}
    case F.Failed{old, scale}: {==}

def retag_generation(state: F.State, generation: Nat) ->
  {F.generation(F.retag(state, generation)) == generation : Nat}:
  match state:
    case F.Pending{old, scale}: {==}
    case F.Ready{old, scale, body, +content_cache}: {==}
    case F.Failed{old, scale}: {==}

def pending_request(generation: Nat, scale: T.Scale) ->
  {F.request(F.Pending{generation, scale}, Nil{}) == F.Plan{generation,
    [T.spec(T.Probe{"@font/body", "0", T.resolved(T.Presentation{T.Body{}, T.Regular{}, scale}),
      T.WrapWords{}, None{}, "0"})]} : F.Plan}:
  {==}

def ready_request(generation: Nat, scale: T.Scale, metric: T.Metric) ->
  {F.request(F.Ready{generation, scale, metric, Nil{}}, Nil{}) == F.Plan{generation, Nil{}} : F.Plan}:
  {==}

def failed_request(generation: Nat, scale: T.Scale) ->
  {F.request(F.Failed{generation, scale}, Nil{}) == F.Plan{generation, Nil{}} : F.Plan}:
  {==}

def begin_scale(generation: Nat, root: Nat) ->
  {F.begin(generation, root) == F.Pending{generation,
    T.Scale{Nat.sub(Nat.max(1000n, Nat.div(root, 16n)), 1000n)}} : F.State}:
  {==}

def received_success(+generation: Nat, +scale: T.Scale, +received: Nat, +metric: T.Metric,
  owned: {Nat.is_eq(generation, received) == True{} : Bool},
  valid: {T.valid_body(metric) == True{} : Bool}) ->
  {F.accept(F.Pending{generation, scale}, Nil{}, F.Observation{received, [metric]}) ==
    F.Ready{generation, scale, metric, Nil{}} : F.State}:
  Equal.trans(F.State, F.accept(F.Pending{generation, scale}, Nil{}, F.Observation{received, [metric]}),
    F.admit(generation, scale, [metric]), F.Ready{generation, scale, metric, Nil{}},
    current_pending(generation, scale, received, [metric], owned), success(generation, scale, metric, valid))

def received_invalid(+generation: Nat, +scale: T.Scale, +received: Nat, +metric: T.Metric,
  owned: {Nat.is_eq(generation, received) == True{} : Bool},
  bad: {T.valid_body(metric) == False{} : Bool}) ->
  {F.accept(F.Pending{generation, scale}, Nil{}, F.Observation{received, [metric]}) ==
    F.Failed{generation, scale} : F.State}:
  Equal.trans(F.State, F.accept(F.Pending{generation, scale}, Nil{}, F.Observation{received, [metric]}),
    F.admit(generation, scale, [metric]), F.Failed{generation, scale},
    current_pending(generation, scale, received, [metric], owned), invalid(generation, scale, metric, bad))

def received_empty(+generation: Nat, +scale: T.Scale, +received: Nat,
  owned: {Nat.is_eq(generation, received) == True{} : Bool}) ->
  {F.accept(F.Pending{generation, scale}, Nil{}, F.Observation{received, Nil{}}) ==
    F.Failed{generation, scale} : F.State}:
  current_pending(generation, scale, received, Nil{}, owned)

def received_multiple(+generation: Nat, +scale: T.Scale, +received: Nat,
  +first: T.Metric, +second: T.Metric, +rest: +List<T.Metric>,
  owned: {Nat.is_eq(generation, received) == True{} : Bool}) ->
  {F.accept(F.Pending{generation, scale}, Nil{}, F.Observation{received, Con{first, Con{second, rest}}}) ==
    F.Failed{generation, scale} : F.State}:
  current_pending(generation, scale, received, Con{first, Con{second, rest}}, owned)

def received_valid(+generation: Nat, +scale: T.Scale, +received: Nat, +metrics: +List<T.Metric>,
  owned: {Nat.is_eq(generation, received) == True{} : Bool}) ->
  {ready_valid(F.accept(F.Pending{generation, scale}, Nil{}, F.Observation{received, metrics})) == True{} : Bool}:
  Equal.trans(Bool, ready_valid(F.accept(F.Pending{generation, scale}, Nil{}, F.Observation{received, metrics})),
    ready_valid(F.admit(generation, scale, metrics)), True{},
    Equal.cong(F.State, Bool, ready_valid,
      F.accept(F.Pending{generation, scale}, Nil{}, F.Observation{received, metrics}),
      F.admit(generation, scale, metrics), current_pending(generation, scale, received, metrics, owned)),
    admitted_valid(generation, scale, metrics))

def retag_pending_variant(old: Nat, generation: Nat, scale: T.Scale) ->
  {F.retag(F.Pending{old, scale}, generation) == F.Pending{generation, scale} : F.State}:
  {==}

def retag_ready_variant(old: Nat, generation: Nat, scale: T.Scale, body: T.Metric) ->
  {F.retag(F.Ready{old, scale, body, Nil{}}, generation) == F.Ready{generation, scale, body, Nil{}} : F.State}:
  {==}

def retag_failed_variant(old: Nat, generation: Nat, scale: T.Scale) ->
  {F.retag(F.Failed{old, scale}, generation) == F.Failed{generation, scale} : F.State}:
  {==}

# Content stamps authenticate the requested specification; physical accuracy is external.
def content_stale(+state: F.State, +specifications: +List<T.MeasurementSpec>, +received: Nat, +metrics: +List<T.Metric>,
  different: {Nat.is_eq(F.generation(state), received) == False{} : Bool}) ->
  {F.accept(state, specifications, F.Observation{received, metrics}) == state : F.State}:
  Equal.cong(Bool, F.State, (owned => F.receive(owned, state, specifications, metrics)),
    Nat.is_eq(F.generation(state), received), False{}, different)

def cache_reuse(+specification: T.MeasurementSpec, +stored: T.MeasurementSpec, +metric: T.Metric,
  checked: {T.same_spec(specification, stored) && T.valid_metric(stored, metric) == True{} : Bool}) ->
  {F.cached(specification, [T.Measured{stored, metric}]) == Some{T.Measured{stored, metric}} : Maybe<&2, T.Measured>}:
  Equal.cong(Bool, Maybe<&2, T.Measured>,
    (accepted => F.cached_checked(accepted, T.Measured{stored, metric}, None{})),
    T.same_spec(specification, stored) && T.valid_metric(stored, metric), True{}, checked)

def changed_spec_miss(+specification: T.MeasurementSpec, +stored: T.MeasurementSpec, +metric: T.Metric,
  changed: {T.same_spec(specification, stored) == False{} : Bool}) ->
  {F.cached(specification, [T.Measured{stored, metric}]) == None{} : Maybe<&2, T.Measured>}:
  Equal.cong(Bool, Maybe<&2, T.Measured>,
    (same => F.cached_checked(same && T.valid_metric(stored, metric), T.Measured{stored, metric}, None{})),
    T.same_spec(specification, stored), False{}, changed)

def cached_not_requested(+specification: T.MeasurementSpec, +content: +List<T.Measured>, +measured: T.Measured,
  found: {F.cached(specification, content) == Some{measured} : Maybe<&2, T.Measured>}) ->
  {F.missing([specification], content) == Nil{} : +List<T.MeasurementSpec>}:
  Equal.cong(Maybe<&2, T.Measured>, +List<T.MeasurementSpec>,
    (lookup => F.missing_item(lookup, specification, Nil{})), F.cached(specification, content), Some{measured}, found)

def uncached_requested(+specification: T.MeasurementSpec, +content: +List<T.Measured>,
  absent: {F.cached(specification, content) == None{} : Maybe<&2, T.Measured>}) ->
  {F.missing([specification], content) == [specification] : +List<T.MeasurementSpec>}:
  Equal.cong(Maybe<&2, T.Measured>, +List<T.MeasurementSpec>,
    (lookup => F.missing_item(lookup, specification, Nil{})), F.cached(specification, content), None{}, absent)

def pairing_retains_specification(+specification: T.MeasurementSpec, +metric: T.Metric,
  valid: {T.valid_metric(specification, metric) == True{} : Bool}) ->
  {F.pair([specification], [metric]) == Some{[T.Measured{specification, metric}]} : Maybe<&2, +List<T.Measured>>}:
  Equal.cong(Bool, Maybe<&2, +List<T.Measured>>,
    (checked => F.pair_checked(checked, specification, metric, Some{Nil{}})),
    T.valid_metric(specification, metric), True{}, valid)

def invalid_pairing(+specification: T.MeasurementSpec, +metric: T.Metric,
  specifications: +List<T.MeasurementSpec>, metrics: +List<T.Metric>,
  bad: {T.valid_metric(specification, metric) == False{} : Bool}) ->
  {F.pair(Con{specification, specifications}, Con{metric, metrics}) == None{} : Maybe<&2, +List<T.Measured>>}:
  Equal.cong(Bool, Maybe<&2, +List<T.Measured>>,
    (checked => F.pair_checked(checked, specification, metric, F.pair(specifications, metrics))),
    T.valid_metric(specification, metric), False{}, bad)

def missing_batch_metric(specification: T.MeasurementSpec, specifications: +List<T.MeasurementSpec>) ->
  {F.pair(Con{specification, specifications}, Nil{}) == None{} : Maybe<&2, +List<T.Measured>>}:
  {==}

def extra_batch_metric(metric: T.Metric, metrics: +List<T.Metric>) ->
  {F.pair(Nil{}, Con{metric, metrics}) == None{} : Maybe<&2, +List<T.Measured>>}:
  {==}

def paired_invalid(generation: Nat, scale: T.Scale, body: T.Metric,
  specifications: +List<T.MeasurementSpec>, content: +List<T.Measured>) ->
  {F.paired(generation, scale, body, specifications, content, None{}) == F.Failed{generation, scale} : F.State}:
  {==}

def paired_complete(+generation: Nat, +scale: T.Scale, +body: T.Metric,
  +specifications: +List<T.MeasurementSpec>, +content: +List<T.Measured>, +observed: +List<T.Measured>, +retained: +List<T.Measured>,
  complete: {F.retain(specifications, List.append(&2, T.Measured, content, observed)) == Some{retained} : Maybe<&2, +List<T.Measured>>}) ->
  {F.paired(generation, scale, body, specifications, content, Some{observed}) == F.Ready{generation, scale, body, retained} : F.State}:
  Equal.cong(Maybe<&2, +List<T.Measured>>, F.State,
    (result => F.finish(generation, scale, body, result)),
    F.retain(specifications, List.append(&2, T.Measured, content, observed)), Some{retained}, complete)

def ready_no_outstanding(+generation: Nat, +scale: T.Scale, +body: T.Metric, +content: +List<T.Measured>,
  +specifications: +List<T.MeasurementSpec>, +metrics: +List<T.Metric>,
  complete: {F.missing(specifications, content) == Nil{} : +List<T.MeasurementSpec>}) ->
  {F.receive(True{}, F.Ready{generation, scale, body, content}, specifications, metrics) == F.Ready{generation, scale, body, content} : F.State}:
  Equal.cong(+List<T.MeasurementSpec>, F.State,
    (outstanding => F.ready_batch(generation, scale, body, content, specifications, outstanding, metrics)),
    F.missing(specifications, content), Nil{}, complete)

def ready_owned_batch(+generation: Nat, +scale: T.Scale, +body: T.Metric, +content: +List<T.Measured>,
  +specifications: +List<T.MeasurementSpec>, +received: Nat, +metrics: +List<T.Metric>,
  owned: {Nat.is_eq(generation, received) == True{} : Bool}) ->
  {F.accept(F.Ready{generation, scale, body, content}, specifications, F.Observation{received, metrics}) ==
    F.ready_batch(generation, scale, body, content, specifications, F.missing(specifications, content), metrics) : F.State}:
  Equal.cong(Bool, F.State,
    (current => F.receive(current, F.Ready{generation, scale, body, content}, specifications, metrics)),
    Nat.is_eq(generation, received), True{}, owned)

def pending_owned_batch(+generation: Nat, +scale: T.Scale, +specifications: +List<T.MeasurementSpec>,
  +received: Nat, +metrics: +List<T.Metric>, owned: {Nat.is_eq(generation, received) == True{} : Bool}) ->
  {F.accept(F.Pending{generation, scale}, specifications, F.Observation{received, metrics}) ==
    F.admit_pending(generation, scale, specifications, metrics) : F.State}:
  Equal.cong(Bool, F.State,
    (current => F.receive(current, F.Pending{generation, scale}, specifications, metrics)),
    Nat.is_eq(generation, received), True{}, owned)

def retag_content(old: Nat, generation: Nat, scale: T.Scale, body: T.Metric, content: +List<T.Measured>) ->
  {F.retag(F.Ready{old, scale, body, content}, generation) == F.Ready{generation, scale, body, content} : F.State}:
  {==}

def failed_content(owned: Bool, generation: Nat, scale: T.Scale,
  specifications: +List<T.MeasurementSpec>, metrics: +List<T.Metric>) ->
  {F.receive(owned, F.Failed{generation, scale}, specifications, metrics) == F.Failed{generation, scale} : F.State}:
  match owned:
    case True{}: {==}
    case False{}: {==}

def finish_body_valid(generation: Nat, scale: T.Scale, +body: T.Metric,
  retained: Maybe<&2, +List<T.Measured>>, valid: {T.valid_body(body) == True{} : Bool}) ->
  {ready_valid(F.finish(generation, scale, body, retained)) == True{} : Bool}:
  match retained:
    case Some{content}: valid
    case None{}: {==}

def paired_body_valid(generation: Nat, scale: T.Scale, +body: T.Metric,
  specifications: +List<T.MeasurementSpec>, content: +List<T.Measured>, batch: Maybe<&2, +List<T.Measured>>,
  valid: {T.valid_body(body) == True{} : Bool}) ->
  {ready_valid(F.paired(generation, scale, body, specifications, content, batch)) == True{} : Bool}:
  match batch:
    case Some{observed}: finish_body_valid(generation, scale, body,
      F.retain(specifications, List.append(&2, T.Measured, content, observed)), valid)
    case None{}: {==}

def pending_checked_valid(+checked: Bool, generation: Nat, scale: T.Scale, +body: T.Metric,
  +specifications: +List<T.MeasurementSpec>, metrics: +List<T.Metric>,
  correspondence: {T.valid_body(body) == checked : Bool}) ->
  {ready_valid(F.pending_checked(checked, generation, scale, body, specifications, metrics)) == True{} : Bool}:
  match checked:
    case True{}: paired_body_valid(generation, scale, body, specifications, Nil{}, F.pair(specifications, metrics), correspondence)
    case False{}: {==}

def pending_batch_valid(generation: Nat, scale: T.Scale, +specifications: +List<T.MeasurementSpec>, metrics: +List<T.Metric>) ->
  {ready_valid(F.pending_batch(generation, scale, specifications, metrics)) == True{} : Bool}:
  match metrics:
    case Nil{}: {==}
    case Con{+body, rest}: pending_checked_valid(T.valid_body(body), generation, scale, body, specifications, rest, {==})

def admitted_content_body_valid(generation: Nat, scale: T.Scale, specifications: +List<T.MeasurementSpec>, metrics: +List<T.Metric>) ->
  {ready_valid(F.admit_pending(generation, scale, specifications, metrics)) == True{} : Bool}:
  match specifications:
    case Nil{}: admitted_valid(generation, scale, metrics)
    case Con{first, rest}: pending_batch_valid(generation, scale, Con{first, rest}, metrics)
