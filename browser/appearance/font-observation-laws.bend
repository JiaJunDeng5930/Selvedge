import Base
import ./FONT.bend as F
import ./TYPOGRAPHY.bend as T

law stale:
  for +state: F.State
  for +received: Nat
  for +metrics: +List<T.Metric>
  for different: {Nat.is_eq(F.generation(state), received) == False{} : Bool}
  {F.accept(state, Nil{}, F.Observation{received, metrics}) == state : F.State}

law ready_duplicate:
  for +generation: Nat
  for +scale: T.Scale
  for +body: T.Metric
  for received: Nat
  for metrics: +List<T.Metric>
  {F.accept(F.Ready{generation, scale, body, Nil{}}, Nil{}, F.Observation{received, metrics}) ==
    F.Ready{generation, scale, body, Nil{}} : F.State}

law failed_duplicate:
  for +generation: Nat
  for +scale: T.Scale
  for received: Nat
  for metrics: +List<T.Metric>
  {F.accept(F.Failed{generation, scale}, Nil{}, F.Observation{received, metrics}) ==
    F.Failed{generation, scale} : F.State}

law current_pending:
  for +generation: Nat
  for +scale: T.Scale
  for +received: Nat
  for +metrics: +List<T.Metric>
  for owned: {Nat.is_eq(generation, received) == True{} : Bool}
  {F.accept(F.Pending{generation, scale}, Nil{}, F.Observation{received, metrics}) ==
    F.admit(generation, scale, metrics) : F.State}

def ready_valid(state: F.State) -> Bool:
  match state:
    case F.Ready{generation, scale, body, +content_cache}: T.valid_body(body)
    case _: True{}

law retag_scale:
  for state: F.State
  for generation: Nat
  {F.scale(F.retag(state, generation)) == F.scale(state) : T.Scale}

law retag_body:
  for state: F.State
  for generation: Nat
  {F.body(F.retag(state, generation)) == F.body(state) : Maybe<&2, T.Metric>}

law retag_pending:
  for state: F.State
  for generation: Nat
  {F.pending(F.retag(state, generation)) == F.pending(state) : Bool}

law retag_generation:
  for state: F.State
  for generation: Nat
  {F.generation(F.retag(state, generation)) == generation : Nat}

law pending_request:
  for capacity: Nat
  for generation: Nat
  for scale: T.Scale
  {F.request_at(capacity, F.Pending{generation, scale}, Nil{}) == F.Plan{generation,
    [T.body_spec_at(capacity, scale)]} : F.Plan}

law ready_request:
  for capacity: Nat
  for generation: Nat
  for scale: T.Scale
  for metric: T.Metric
  {F.request_at(capacity, F.Ready{generation, scale, metric, Nil{}}, Nil{}) == F.Plan{generation, Nil{}} : F.Plan}

law failed_request:
  for capacity: Nat
  for generation: Nat
  for scale: T.Scale
  {F.request_at(capacity, F.Failed{generation, scale}, Nil{}) == F.Plan{generation, Nil{}} : F.Plan}

law begin_scale:
  for generation: Nat
  for root: Nat
  {F.begin(generation, root) == F.Pending{generation,
    T.Scale{Nat.sub(Nat.max(1000n, Nat.div(root, 16n)), 1000n)}} : F.State}

law received_success:
  for +generation: Nat
  for +scale: T.Scale
  for +received: Nat
  for +metric: T.Metric
  for owned: {Nat.is_eq(generation, received) == True{} : Bool}
  for valid: {T.valid_body(metric) == True{} : Bool}
  {F.accept(F.Pending{generation, scale}, Nil{}, F.Observation{received, [metric]}) ==
    F.Ready{generation, scale, metric, Nil{}} : F.State}

law received_invalid:
  for +generation: Nat
  for +scale: T.Scale
  for +received: Nat
  for +metric: T.Metric
  for owned: {Nat.is_eq(generation, received) == True{} : Bool}
  for bad: {T.valid_body(metric) == False{} : Bool}
  {F.accept(F.Pending{generation, scale}, Nil{}, F.Observation{received, [metric]}) ==
    F.Failed{generation, scale} : F.State}

law received_empty:
  for +generation: Nat
  for +scale: T.Scale
  for +received: Nat
  for owned: {Nat.is_eq(generation, received) == True{} : Bool}
  {F.accept(F.Pending{generation, scale}, Nil{}, F.Observation{received, Nil{}}) ==
    F.Failed{generation, scale} : F.State}

law received_multiple:
  for +generation: Nat
  for +scale: T.Scale
  for +received: Nat
  for +first: T.Metric
  for +second: T.Metric
  for +rest: +List<T.Metric>
  for owned: {Nat.is_eq(generation, received) == True{} : Bool}
  {F.accept(F.Pending{generation, scale}, Nil{}, F.Observation{received, Con{first, Con{second, rest}}}) ==
    F.Failed{generation, scale} : F.State}

law received_valid:
  for +generation: Nat
  for +scale: T.Scale
  for +received: Nat
  for +metrics: +List<T.Metric>
  for owned: {Nat.is_eq(generation, received) == True{} : Bool}
  {ready_valid(F.accept(F.Pending{generation, scale}, Nil{}, F.Observation{received, metrics})) == True{} : Bool}

law retag_pending_variant:
  for old: Nat
  for generation: Nat
  for scale: T.Scale
  {F.retag(F.Pending{old, scale}, generation) == F.Pending{generation, scale} : F.State}

law retag_ready_variant:
  for old: Nat
  for generation: Nat
  for scale: T.Scale
  for body: T.Metric
  {F.retag(F.Ready{old, scale, body, Nil{}}, generation) == F.Ready{generation, scale, body, Nil{}} : F.State}

law retag_failed_variant:
  for old: Nat
  for generation: Nat
  for scale: T.Scale
  {F.retag(F.Failed{old, scale}, generation) == F.Failed{generation, scale} : F.State}
