import Base
import ./typography.bend as T

type Plan is Data:
  Plan{generation: Nat, specifications: +List<T.MeasurementSpec>}

type Observation is Data:
  Observation{generation: Nat, metrics: +List<T.Metric>}

type State is Data:
  Pending{generation: Nat, scale: T.Scale}
  Ready{generation: Nat, scale: T.Scale, body: T.Metric}
  Failed{generation: Nat, scale: T.Scale}

def root_scale(root_font_size_milli: Nat) -> T.Scale:
  T.Scale{Nat.sub(Nat.max(1000n, Nat.div(root_font_size_milli, 16n)), 1000n)}

def begin(generation: Nat, root_font_size_milli: Nat) -> State:
  Pending{generation, root_scale(root_font_size_milli)}

def retag(state: State, generation: Nat) -> State:
  match state:
    case Pending{old, scale}: Pending{generation, scale}
    case Ready{old, scale, body}: Ready{generation, scale, body}
    case Failed{old, scale}: Failed{generation, scale}

def scale(state: State) -> T.Scale:
  match state:
    case Pending{generation, scale}: scale
    case Ready{generation, scale, body}: scale
    case Failed{generation, scale}: scale

def generation(state: State) -> Nat:
  match state:
    case Pending{generation, scale}: generation
    case Ready{generation, scale, body}: generation
    case Failed{generation, scale}: generation

def body(state: State) -> Maybe<&2, T.Metric>:
  match state:
    case Ready{generation, scale, body}: Some{body}
    case _: None{}

def pending(state: State) -> Bool:
  match state:
    case Pending{generation, scale}: True{}
    case _: False{}

def request(state: State) -> Plan:
  match state:
    case Pending{generation, scale}: Plan{generation, [T.body_spec(scale)]}
    case Ready{generation, scale, body}: Plan{generation, Nil{}}
    case Failed{generation, scale}: Plan{generation, Nil{}}

def admit_checked(checked: Bool, generation: Nat, scale: T.Scale, metric: T.Metric) -> State:
  match checked:
    case True{}: Ready{generation, scale, metric}
    case False{}: Failed{generation, scale}

def admit_tail(generation: Nat, scale: T.Scale, +metric: T.Metric, rest: +List<T.Metric>) -> State:
  match rest:
    case Nil{}: admit_checked(T.valid_body(metric), generation, scale, metric)
    case Con{other, tail}: Failed{generation, scale}

def admit(generation: Nat, scale: T.Scale, metrics: +List<T.Metric>) -> State:
  match metrics:
    case Nil{}: Failed{generation, scale}
    case Con{metric, rest}: admit_tail(generation, scale, metric, rest)

def receive(owned: Bool, state: State, metrics: +List<T.Metric>) -> State:
  match owned state:
    case True{} Pending{generation, scale}: admit(generation, scale, metrics)
    case _ other: other

def accept(+state: State, observation: Observation) -> State:
  Observation{received, metrics} = observation
  receive(Nat.is_eq(generation(state), received), state, metrics)
