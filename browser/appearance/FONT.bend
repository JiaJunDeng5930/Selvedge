import Base
import ../../bendlib/categories.bend as Categories
import ./TYPOGRAPHY.bend as T
import ../layout/natural-size.bend as NaturalSize

type Plan is Data:
  Plan{generation: Nat, specifications: +List<T.MeasurementSpec>}

type Observation is Data:
  Observation{generation: Nat, metrics: +List<T.Metric>}

type State is Data:
  Pending{generation: Nat, scale: T.Scale}
  Ready{generation: Nat, scale: T.Scale, body: T.Metric, content: +List<T.Measured>}
  Failed{generation: Nat, scale: T.Scale}

type ActivityMetrics is Data:
  ActivityMetrics{primary: T.Metric, support: T.Metric}

def activity_primary_specification(capacity: Nat, scale: T.Scale) -> T.MeasurementSpec:
  T.spec(T.Probe{"@font/activity-primary", "0", T.resolve_presentation(capacity,
    T.Presentation{T.ActivityPrimary{}, T.Regular{}, scale}), T.WrapWords{}, None{}, "0"})

def activity_support_specification(capacity: Nat, scale: T.Scale) -> T.MeasurementSpec:
  T.spec(T.Probe{"@font/activity-support", "0", T.resolve_presentation(capacity,
    T.Presentation{T.ActivitySupport{}, T.Regular{}, scale}), T.WrapWords{}, None{}, "0"})

def activity_specifications(+capacity: Nat, +scale: T.Scale) -> +List<T.MeasurementSpec>:
  [activity_primary_specification(capacity, scale), activity_support_specification(capacity, scale)]

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

def cached_valid(+expected: T.MeasurementSpec, measured: T.Measured) -> Bool:
  T.Measured{+stored, metric} = measured
  T.same_spec(expected, stored) && T.valid_metric(stored, metric)

def cached_metric(expected: T.MeasurementSpec) -> T.Measured -> Type:
  Categories.holds(T.Measured, cached_valid(expected))

def cached_checked(+specification: T.MeasurementSpec,
  member: Categories.Membership<T.Measured, cached_metric(specification)>) -> Maybe<&2, T.Measured>:
  Categories.Membership{measured, evidence} = member
  Some{measured}

def cached_admitted(+specification: T.MeasurementSpec, rest: Maybe<&2, T.Measured>,
  admitted: Maybe<&1, Categories.Membership<T.Measured, cached_metric(specification)>>) -> Maybe<&2, T.Measured>:
  match admitted:
    case Some{member}: cached_checked(specification, member)
    case None{}: rest

def cached(+specification: T.MeasurementSpec, content: +List<T.Measured>) -> Maybe<&2, T.Measured>:
  match content:
    case Nil{}: None{}
    case Con{measured, rest}:
      cached_admitted(specification, cached(specification, rest), Categories.admit(T.Measured, cached_valid(specification), measured))

def activity_metrics_pair(primary: Maybe<&2, T.Measured>, support: Maybe<&2, T.Measured>) -> Maybe<&2, ActivityMetrics>:
  match primary support:
    case Some{T.Measured{primary_specification, primary}} Some{T.Measured{support_specification, support}}:
      Some{ActivityMetrics{primary, support}}
    case _ _: None{}

def activity_metrics_at(+capacity: Nat, state: State) -> Maybe<&2, ActivityMetrics>:
  match state:
    case Ready{generation, +scale, body, +content}:
      activity_metrics_pair(cached(activity_primary_specification(capacity, scale), content),
        cached(activity_support_specification(capacity, scale), content))
    case _: None{}

def activity_metrics(state: State) -> Maybe<&2, ActivityMetrics>:
  activity_metrics_at(NaturalSize.limit(), state)

def missing_item(found: Maybe<&2, T.Measured>, specification: T.MeasurementSpec, rest: +List<T.MeasurementSpec>) -> +List<T.MeasurementSpec>:
  match found:
    case Some{measured}: rest
    case None{}: Con{specification, rest}

def missing(specifications: +List<T.MeasurementSpec>, +content: +List<T.Measured>) -> +List<T.MeasurementSpec>:
  match specifications:
    case Nil{}: Nil{}
    case Con{+specification, rest}: missing_item(cached(specification, content), specification, missing(rest, content))

def request_at(capacity: Nat, state: State, specifications: +List<T.MeasurementSpec>) -> Plan:
  match state:
    case Pending{generation, scale}: Plan{generation, Con{T.body_spec_at(capacity, scale), specifications}}
    case Ready{generation, scale, body, content}: Plan{generation, missing(specifications, content)}
    case Failed{generation, scale}: Plan{generation, Nil{}}

def request(state: State, specifications: +List<T.MeasurementSpec>) -> Plan:
  request_at(NaturalSize.limit(), state, specifications)

# The request retains evidence for the caller's actual capacity and font cache.
type ActivityRequest<-capacity: Nat, -font: State> is Type:
  ActivityRequest{plan: Plan,
    correspondence: {plan == request_at(capacity, font, activity_specifications(capacity, scale(font))) : Plan}}

def activity_request(+capacity: Nat, +font: State) -> ActivityRequest<capacity, font>:
  ActivityRequest{request_at(capacity, font, activity_specifications(capacity, scale(font))), {==}}

def activity_request_value(-capacity: Nat, -font: State, constructed: ActivityRequest<capacity, font>) -> Plan:
  ActivityRequest{plan, correspondence} = constructed
  plan

def activity_request_plan(+capacity: Nat, +font: State) -> Plan:
  activity_request_value(capacity, font, activity_request(capacity, font))

law activity_request_value_correspondence:
  @+capacity:Nat -> @+font:State -> @constructed:ActivityRequest<capacity, font> ->
  {activity_request_value(capacity, font, constructed) == request_at(capacity, font, activity_specifications(capacity, scale(font))) : Plan}

law activity_request_correspondence:
  @+capacity:Nat -> @+font:State ->
  {activity_request_plan(capacity, font) == request_at(capacity, font, activity_specifications(capacity, scale(font))) : Plan}

def body_metric(metric: T.Metric) -> Type:
  Categories.holds(T.Metric, T.valid_body)(metric)

def admit_checked(generation: Nat, scale: T.Scale,
  member: Categories.Membership<T.Metric, body_metric>) -> State:
  Categories.Membership{metric, evidence} = member
  Ready{generation, scale, metric, Nil{}}

def body_admitted(generation: Nat, scale: T.Scale,
  admitted: Maybe<&1, Categories.Membership<T.Metric, body_metric>>) -> State:
  match admitted:
    case Some{member}: admit_checked(generation, scale, member)
    # DEFENSE: The font measurement contract requires a positive body reference advance and matching body identity before font calibration.
    case None{}: Failed{generation, scale}

def admit_tail(generation: Nat, scale: T.Scale, +metric: T.Metric, rest: +List<T.Metric>) -> State:
  match rest:
    case Nil{}: body_admitted(generation, scale, Categories.admit(T.Metric, T.valid_body, metric))
    case Con{other, tail}: Failed{generation, scale}

def admit(generation: Nat, scale: T.Scale, metrics: +List<T.Metric>) -> State:
  match metrics:
    case Nil{}: Failed{generation, scale}
    case Con{metric, rest}: admit_tail(generation, scale, metric, rest)

def prepend_paired(measured: T.Measured, rest: Maybe<&2, +List<T.Measured>>) -> Maybe<&2, +List<T.Measured>>:
  match rest:
    case Some{rest}: Some{Con{measured, rest}}
    case None{}: None{}

def measured_metric(specification: T.MeasurementSpec) -> T.Metric -> Type:
  Categories.holds(T.Metric, T.valid_metric(specification))

def pair_checked(+specification: T.MeasurementSpec,
  member: Categories.Membership<T.Metric, measured_metric(specification)>,
  rest: Maybe<&2, +List<T.Measured>>) -> Maybe<&2, +List<T.Measured>>:
  Categories.Membership{metric, evidence} = member
  prepend_paired(T.Measured{specification, metric}, rest)

def pair_admitted(+specification: T.MeasurementSpec, rest: Maybe<&2, +List<T.Measured>>,
  admitted: Maybe<&1, Categories.Membership<T.Metric, measured_metric(specification)>>) -> Maybe<&2, +List<T.Measured>>:
  match admitted:
    case Some{member}: pair_checked(specification, member, rest)
    # DEFENSE: Each received metric must match its issued text specification and satisfy the metric relations before entering the font cache.
    case None{}: None{}

def pair(specifications: +List<T.MeasurementSpec>, metrics: +List<T.Metric>) -> Maybe<&2, +List<T.Measured>>:
  match specifications metrics:
    case Nil{} Nil{}: Some{Nil{}}
    case Con{+specification, rest} Con{metric, tail}:
      pair_admitted(specification, pair(rest, tail), Categories.admit(T.Metric, T.valid_metric(specification), metric))
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

def pending_checked(generation: Nat, scale: T.Scale,
  member: Categories.Membership<T.Metric, body_metric>,
  +specifications: +List<T.MeasurementSpec>, metrics: +List<T.Metric>) -> State:
  Categories.Membership{body, evidence} = member
  paired(generation, scale, body, specifications, Nil{}, pair(specifications, metrics))

def pending_admitted(generation: Nat, scale: T.Scale, specifications: +List<T.MeasurementSpec>, metrics: +List<T.Metric>,
  admitted: Maybe<&1, Categories.Membership<T.Metric, body_metric>>) -> State:
  match admitted:
    case Some{member}: pending_checked(generation, scale, member, specifications, metrics)
    # DEFENSE: The pending font batch must include the positive reference metric required by the font measurement protocol.
    case None{}: Failed{generation, scale}

def pending_batch(generation: Nat, scale: T.Scale, +specifications: +List<T.MeasurementSpec>, metrics: +List<T.Metric>) -> State:
  match metrics:
    case Nil{}: Failed{generation, scale}
    case Con{body, rest}:
      pending_admitted(generation, scale, specifications, rest, Categories.admit(T.Metric, T.valid_body, body))

def admit_pending(generation: Nat, scale: T.Scale, specifications: +List<T.MeasurementSpec>, metrics: +List<T.Metric>) -> State:
  match specifications:
    case Nil{}: admit(generation, scale, metrics)
    case Con{first, rest}: pending_batch(generation, scale, Con{first, rest}, metrics)

def ready_batch(generation: Nat, scale: T.Scale, body: T.Metric, +content: +List<T.Measured>,
  specifications: +List<T.MeasurementSpec>, outstanding: +List<T.MeasurementSpec>, metrics: +List<T.Metric>) -> State:
  match outstanding:
    case Nil{}: Ready{generation, scale, body, content}
    case Con{first, rest}: paired(generation, scale, body, specifications, content, pair(Con{first, rest}, metrics))

def current_valid(expected: Nat, observation: Observation) -> Bool:
  Observation{received, metrics} = observation
  Nat.is_eq(expected, received)

def current_observation(expected: Nat) -> Observation -> Type:
  Categories.holds(Observation, current_valid(expected))

def observation_metrics(observation: Observation) -> +List<T.Metric>:
  Observation{received, metrics} = observation
  metrics

def received_metrics(expected: Nat, member: Categories.Membership<Observation, current_observation(expected)>) -> +List<T.Metric>:
  Categories.Membership{observation, evidence} = member
  observation_metrics(observation)

def receive(+state: State, +specifications: +List<T.MeasurementSpec>,
  member: Categories.Membership<Observation, current_observation(generation(state))>) -> State:
  match state:
    case Pending{generation, scale}: admit_pending(generation, scale, specifications, received_metrics(generation, member))
    case Ready{generation, scale, body, +content}:
      ready_batch(generation, scale, body, content, specifications, missing(specifications, content), received_metrics(generation, member))
    case other: other

def observation_admitted(+state: State, specifications: +List<T.MeasurementSpec>,
  admitted: Maybe<&1, Categories.Membership<Observation, current_observation(generation(state))>>) -> State:
  match admitted:
    case Some{member}: receive(state, specifications, member)
    # DEFENSE: An awaited native font measurement can complete after a newer root-font environment starts a new generation.
    case None{}: state

def accept(+state: State, specifications: +List<T.MeasurementSpec>, observation: Observation) -> State:
  observation_admitted(state, specifications, Categories.admit(Observation, current_valid(generation(state)), observation))
