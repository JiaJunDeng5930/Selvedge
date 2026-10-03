import Base
import ./typography.bend as T

type Plan is Data:
  Plan{generation: Nat, specifications: +List<T.MeasurementSpec>}

type Observation is Data:
  Observation{generation: Nat, metrics: +List<T.Metric>}

type State is Data:
  Pending{generation: Nat, scale: T.Scale}
  Ready{generation: Nat, scale: T.Scale, body: T.Metric, content: +List<T.Measured>}
  Failed{generation: Nat, scale: T.Scale}

def root_scale(root_font_size_milli: Nat) -> T.Scale:
  T.Scale{Nat.sub(Nat.max(1000n, Nat.div(root_font_size_milli, 16n)), 1000n)}

def begin(generation: Nat, root_font_size_milli: Nat) -> State:
  Pending{generation, root_scale(root_font_size_milli)}

def retag(state: State, generation: Nat) -> State:
  match state:
    case Pending{old, scale}: Pending{generation, scale}
    case Ready{old, scale, body, +content}: Ready{generation, scale, body, content}
    case Failed{old, scale}: Failed{generation, scale}

def scale(state: State) -> T.Scale:
  match state:
    case Pending{generation, scale}: scale
    case Ready{generation, scale, body, content}: scale
    case Failed{generation, scale}: scale

def generation(state: State) -> Nat:
  match state:
    case Pending{generation, scale}: generation
    case Ready{generation, scale, body, content}: generation
    case Failed{generation, scale}: generation

def body(state: State) -> Maybe<&2, T.Metric>:
  match state:
    case Ready{generation, scale, body, content}: Some{body}
    case _: None{}

def pending(state: State) -> Bool:
  match state:
    case Pending{generation, scale}: True{}
    case _: False{}

def cached_checked(checked: Bool, measured: T.Measured, rest: Maybe<&2, T.Measured>) -> Maybe<&2, T.Measured>:
  match checked:
    case True{}: Some{measured}
    case False{}: rest

def cached(+specification: T.MeasurementSpec, content: +List<T.Measured>) -> Maybe<&2, T.Measured>:
  match content:
    case Nil{}: None{}
    case Con{T.Measured{+stored, +metric}, rest}:
      cached_checked(T.same_spec(specification, stored) && T.valid_metric(stored, metric),
        T.Measured{stored, metric}, cached(specification, rest))

def missing_item(found: Maybe<&2, T.Measured>, specification: T.MeasurementSpec, rest: +List<T.MeasurementSpec>) -> +List<T.MeasurementSpec>:
  match found:
    case Some{measured}: rest
    case None{}: Con{specification, rest}

def missing(specifications: +List<T.MeasurementSpec>, +content: +List<T.Measured>) -> +List<T.MeasurementSpec>:
  match specifications:
    case Nil{}: Nil{}
    case Con{+specification, rest}: missing_item(cached(specification, content), specification, missing(rest, content))

def request(state: State, specifications: +List<T.MeasurementSpec>) -> Plan:
  match state:
    case Pending{generation, scale}: Plan{generation, Con{T.body_spec(scale), specifications}}
    case Ready{generation, scale, body, content}: Plan{generation, missing(specifications, content)}
    case Failed{generation, scale}: Plan{generation, Nil{}}

def admit_checked(checked: Bool, generation: Nat, scale: T.Scale, metric: T.Metric) -> State:
  match checked:
    case True{}: Ready{generation, scale, metric, Nil{}}
    case False{}: Failed{generation, scale}

def admit_tail(generation: Nat, scale: T.Scale, +metric: T.Metric, rest: +List<T.Metric>) -> State:
  match rest:
    case Nil{}: admit_checked(T.valid_body(metric), generation, scale, metric)
    case Con{other, tail}: Failed{generation, scale}

def admit(generation: Nat, scale: T.Scale, metrics: +List<T.Metric>) -> State:
  match metrics:
    case Nil{}: Failed{generation, scale}
    case Con{metric, rest}: admit_tail(generation, scale, metric, rest)

def prepend_paired(measured: T.Measured, rest: Maybe<&2, +List<T.Measured>>) -> Maybe<&2, +List<T.Measured>>:
  match rest:
    case Some{rest}: Some{Con{measured, rest}}
    case None{}: None{}

def pair_checked(checked: Bool, specification: T.MeasurementSpec, metric: T.Metric,
  rest: Maybe<&2, +List<T.Measured>>) -> Maybe<&2, +List<T.Measured>>:
  match checked:
    case True{}: prepend_paired(T.Measured{specification, metric}, rest)
    case False{}: None{}

def pair(specifications: +List<T.MeasurementSpec>, metrics: +List<T.Metric>) -> Maybe<&2, +List<T.Measured>>:
  match specifications metrics:
    case Nil{} Nil{}: Some{Nil{}}
    case Con{+specification, rest} Con{+metric, tail}:
      pair_checked(T.valid_metric(specification, metric), specification, metric, pair(rest, tail))
    case _ _: None{}

def retain_found(found: Maybe<&2, T.Measured>, rest: Maybe<&2, +List<T.Measured>>) -> Maybe<&2, +List<T.Measured>>:
  match found:
    case Some{measured}: prepend_paired(measured, rest)
    case None{}: None{}

def retain(specifications: +List<T.MeasurementSpec>, +content: +List<T.Measured>) -> Maybe<&2, +List<T.Measured>>:
  match specifications:
    case Nil{}: Some{Nil{}}
    case Con{specification, rest}: retain_found(cached(specification, content), retain(rest, content))

def finish(generation: Nat, scale: T.Scale, body: T.Metric, retained: Maybe<&2, +List<T.Measured>>) -> State:
  match retained:
    case Some{content}: Ready{generation, scale, body, content}
    case None{}: Failed{generation, scale}

def paired(generation: Nat, scale: T.Scale, body: T.Metric, specifications: +List<T.MeasurementSpec>,
  content: +List<T.Measured>, batch: Maybe<&2, +List<T.Measured>>) -> State:
  match batch:
    case Some{observed}: finish(generation, scale, body, retain(specifications, List.append(&2, T.Measured, content, observed)))
    case None{}: Failed{generation, scale}

def pending_checked(checked: Bool, generation: Nat, scale: T.Scale, body: T.Metric,
  +specifications: +List<T.MeasurementSpec>, metrics: +List<T.Metric>) -> State:
  match checked:
    case True{}: paired(generation, scale, body, specifications, Nil{}, pair(specifications, metrics))
    case False{}: Failed{generation, scale}

def pending_batch(generation: Nat, scale: T.Scale, +specifications: +List<T.MeasurementSpec>, metrics: +List<T.Metric>) -> State:
  match metrics:
    case Nil{}: Failed{generation, scale}
    case Con{+body, rest}: pending_checked(T.valid_body(body), generation, scale, body, specifications, rest)

def admit_pending(generation: Nat, scale: T.Scale, specifications: +List<T.MeasurementSpec>, metrics: +List<T.Metric>) -> State:
  match specifications:
    case Nil{}: admit(generation, scale, metrics)
    case Con{first, rest}: pending_batch(generation, scale, Con{first, rest}, metrics)

def ready_batch(generation: Nat, scale: T.Scale, body: T.Metric, +content: +List<T.Measured>,
  specifications: +List<T.MeasurementSpec>, outstanding: +List<T.MeasurementSpec>, metrics: +List<T.Metric>) -> State:
  match outstanding:
    case Nil{}: Ready{generation, scale, body, content}
    case Con{first, rest}: paired(generation, scale, body, specifications, content, pair(Con{first, rest}, metrics))

def receive(owned: Bool, state: State, +specifications: +List<T.MeasurementSpec>, metrics: +List<T.Metric>) -> State:
  match owned state:
    case True{} Pending{generation, scale}: admit_pending(generation, scale, specifications, metrics)
    case True{} Ready{generation, scale, body, +content}:
      ready_batch(generation, scale, body, content, specifications, missing(specifications, content), metrics)
    case _ other: other

def accept(+state: State, specifications: +List<T.MeasurementSpec>, observation: Observation) -> State:
  Observation{received, metrics} = observation
  receive(Nat.is_eq(generation(state), received), state, specifications, metrics)
