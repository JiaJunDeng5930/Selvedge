import Base

# Predicates remain open function values; inclusion supplies the implication.
type Inclusion<-Value: Type, -A: Value -> Type, -B: Value -> Type> is Type:
  Inclusion{evidence: @-value:Value -> A(value) -> B(value)}

type Intersection<-Value: Type, -A: Value -> Type, -B: Value -> Type, -value: Value> is Type:
  Intersection{first: A(value), second: B(value)}

def intersection(-Value: Type, -A: Value -> Type, -B: Value -> Type, -value: Value) -> Type:
  Intersection<Value, A, B, value>

def inclusion_identity(-Value: Type, -A: Value -> Type) -> Inclusion<Value, A, A>:
  Inclusion{value => evidence => evidence}

def inclusion_compose(-Value: Type, -A: Value -> Type, -B: Value -> Type, -C: Value -> Type, first: Inclusion<Value, A, B>, second: Inclusion<Value, B, C>) -> Inclusion<Value, A, C>:
  Inclusion{first} = first
  Inclusion{second} = second
  Inclusion{value => evidence => second(value, first(value, evidence))}

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
