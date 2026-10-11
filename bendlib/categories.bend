import Base

# Predicates remain open function values; inclusion supplies the implication.
type Inclusion<-Value: Type, -A: Value -> Type, -B: Value -> Type> is Type:
  Inclusion{evidence: @-value:Value -> A(value) -> B(value)}

type Intersection<-Value: Type, -A: Value -> Type, -B: Value -> Type, -value: Value> is Type:
  Intersection{first: A(value), second: B(value)}

def intersection(-Value: Type, -A: Value -> Type, -B: Value -> Type, -value: Value) -> Type:
  Intersection<Value, A, B, value>

def apply_inclusion(-Value: Type, -A: Value -> Type, -B: Value -> Type, inclusion: Inclusion<Value, A, B>, -value: Value, evidence: A(value)) -> B(value):
  Inclusion{derive} = inclusion
  derive(value, evidence)

def inclusion_identity(-Value: Type, -A: Value -> Type) -> Inclusion<Value, A, A>:
  Inclusion{value => evidence => evidence}

def inclusion_compose(-Value: Type, -A: Value -> Type, -B: Value -> Type, -C: Value -> Type, first: Inclusion<Value, A, B>, second: Inclusion<Value, B, C>) -> Inclusion<Value, A, C>:
  Inclusion{first} = first
  Inclusion{second} = second
  Inclusion{value => evidence => second(value, first(value, evidence))}

def inverse_image(-Source: Type, -Target: Type, projection: Source -> Target, category: Target -> Type, value: Source) -> Type:
  category(projection(value))

def pullback_inclusion(-Source: Type, -Target: Type, -projection: Source -> Target, -first: Target -> Type, -second: Target -> Type, inclusion: Inclusion<Target, first, second>) -> Inclusion<Source, inverse_image(Source, Target, projection, first), inverse_image(Source, Target, projection, second)>:
  Inclusion{evidence} = inclusion
  Inclusion{value => proof => evidence(projection(value), proof)}

def project_intersection_first(-Value: Type, -A: Value -> Type, -B: Value -> Type, -value: Value, evidence: intersection(Value, A, B, value)) -> A(value):
  Intersection{first, second} = evidence
  first

def intersection_first(-Value: Type, -A: Value -> Type, -B: Value -> Type) -> Inclusion<Value, (value => intersection(Value, A, B, value)), A>:
  Inclusion{value => evidence => project_intersection_first(Value, A, B, value, evidence)}

def project_intersection_second(-Value: Type, -A: Value -> Type, -B: Value -> Type, -value: Value, evidence: intersection(Value, A, B, value)) -> B(value):
  Intersection{first, second} = evidence
  second

def intersection_second(-Value: Type, -A: Value -> Type, -B: Value -> Type) -> Inclusion<Value, (value => intersection(Value, A, B, value)), B>:
  Inclusion{value => evidence => project_intersection_second(Value, A, B, value, evidence)}

type Membership<-Value: Type, -category: Value -> Type> is Type:
  Membership{value: Value, evidence: category(value)}

def map_membership(-Source: Type, -Target: Type, projection: Source -> Target, -category: Target -> Type, member: Membership<Source, inverse_image(Source, Target, projection, category)>) -> Membership<Target, category>:
  Membership{value, evidence} = member
  projected = projection(value)
  Membership{projected, evidence}

def reclassify(-Value: Type, -first: Value -> Type, -second: Value -> Type, member: Membership<Value, first>, inclusion: Inclusion<Value, first, second>) -> Membership<Value, second>:
  Membership{value, evidence} = member
  Inclusion{derive} = inclusion
  Membership{value, derive(value, evidence)}

def extend_instance(-Value: Type, -base: Value -> Type, -additional: Value -> Type, value: Value, base_evidence: base(value), additional_evidence: additional(value)) -> Membership<Value, (value => intersection(Value, base, additional, value))>:
  Membership{value, Intersection{base_evidence, additional_evidence}}

type Construction<-Request: Data, -Result: Data> is Data:
  Construction{request: Request, result: Result}

def constructed_by(-Request: Data, -Result: Data, -producer: Request -> Result, construction: Construction<Request, Result>) -> Type:
  Construction{request, result} = construction
  {result == producer(request) : Result}

def construct(-Request: Data, -Result: Data, producer: Request -> Result, +request: Request) -> Membership<Construction<Request, Result>, constructed_by(Request, Result, producer)>:
  +result = producer(request)
  Membership{Construction{request, result}, {==}}

# Provenance alone supplies no domain property; the family law supplies it.
def construct_certified(-Request: Data, -Result: Data, producer: Request -> Result, -premise: Request -> Type, -category: Construction<Request, Result> -> Type, evidence: @-request:Request -> premise(request) -> category(Construction{request, producer(request)}), +request: Request, accepted: premise(request)) -> Membership<Construction<Request, Result>, (value => intersection(Construction<Request, Result>, constructed_by(Request, Result, producer), category, value))>:
  +result = producer(request)
  Membership{Construction{request, result}, Intersection{{==}, evidence(request, accepted)}}

type Implementation<-Operations: Type> is Type:
  Implementation{specification: Operations, operations: Operations}

def holds(-Value: Data, -predicate: Value -> Bool) -> Value -> Type:
  value => {predicate(value) == True{} : Bool}

def admit_checked(-Value: Data, -predicate: Value -> Bool, +value: Value, accepted: Bool, observed: {predicate(value) == accepted : Bool}) -> Maybe<&1, Membership<Value, holds(Value, predicate)>>:
  match accepted:
    case True{}: Some{Membership{value, observed}}
    case False{}: None{}

def admit(-Value: Data, predicate: Value -> Bool, +value: Value) -> Maybe<&1, Membership<Value, holds(Value, predicate)>>:
  admit_checked(Value, predicate, value, predicate(value), {==})

def value(-Value: Type, -category: Value -> Type, member: Membership<Value, category>) -> Value:
  Membership{value, evidence} = member
  value
def admit_intersection_checked(-Value: Data, -first: Value -> Bool, -second: Value -> Bool, +value: Value, a: Bool, b: Bool, ea: {first(value) == a : Bool}, eb: {second(value) == b : Bool}) -> Maybe<&1, Membership<Value, (value => intersection(Value, holds(Value, first), holds(Value, second), value))>>:
  match a b:
    case True{} True{}: Some{Membership{value, Intersection{ea, eb}}}
    case _ _: None{}

def admit_intersection(-Value: Data, first: Value -> Bool, second: Value -> Bool, +value: Value) -> Maybe<&1, Membership<Value, (value => intersection(Value, holds(Value, first), holds(Value, second), value))>>:
  admit_intersection_checked(Value, first, second, value, first(value), second(value), {==}, {==})
