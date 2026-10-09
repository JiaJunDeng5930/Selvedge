import Base

# Physical coordinates share the pinned compiler's immediate Nat capacity.
def limit() -> Nat:
  Nat.add(Nat.mul(4294967295n, 65536n), 65535n)

type Calculation is Data:
  Value{value: Nat}
  Sum{left: Calculation, right: Calculation}
  Product{left: Calculation, right: Calculation}
  Maximum{left: Calculation, right: Calculation}
  Quotient{numerator: Calculation, denominator: Calculation}
  Remainder{numerator: Calculation, denominator: Calculation}

def add_if_capacity(accepted: Bool, left: Nat, right: Nat) -> Maybe<&2, Nat>:
  match accepted:
    case True{}: Some{Nat.add(left, right)}
    case False{}: None{}

def checked_add(+capacity: Nat, +left: Nat, +right: Nat) -> Maybe<&2, Nat>:
  add_if_capacity(Nat.is_le(left, Nat.sub(capacity, right)), left, right)

def multiply_if_capacity(accepted: Bool, left: Nat, right: Nat) -> Maybe<&2, Nat>:
  match accepted:
    case True{}: Some{Nat.mul(left, right)}
    case False{}: None{}

def multiply_zero_with_capacity(zero: Bool, capacity: Nat, +left: Nat, +right: Nat) -> Maybe<&2, Nat>:
  match zero:
    case True{}: Some{0n}
    case False{}: multiply_if_capacity(Nat.is_le(left, Nat.div(capacity, right)), left, right)

def checked_mul(+capacity: Nat, left: Nat, +right: Nat) -> Maybe<&2, Nat>:
  multiply_zero_with_capacity(Nat.is_eq(right, 0n), capacity, left, right)

def quotient_if_zero(zero: Bool, numerator: Nat, denominator: Nat) -> Maybe<&2, Nat>:
  match zero:
    case True{}: None{}
    case False{}: Some{Nat.div(numerator, denominator)}

def remainder_if_zero(zero: Bool, numerator: Nat, denominator: Nat) -> Maybe<&2, Nat>:
  match zero:
    case True{}: None{}
    case False{}: Some{Nat.mod(numerator, denominator)}

def sum_pair(capacity: Nat, left: Maybe<&2, Nat>, right: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match left right:
    case Some{left} Some{right}: checked_add(capacity, left, right)
    case _ _: None{}

def product_pair(capacity: Nat, left: Maybe<&2, Nat>, right: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match left right:
    case Some{left} Some{right}: checked_mul(capacity, left, right)
    case _ _: None{}

def maximum_pair(left: Maybe<&2, Nat>, right: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match left right:
    case Some{left} Some{right}: Some{Nat.max(left, right)}
    case _ _: None{}

def quotient_pair(numerator: Maybe<&2, Nat>, denominator: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match numerator denominator:
    case Some{numerator} Some{+denominator}: quotient_if_zero(Nat.is_eq(denominator, 0n), numerator, denominator)
    case _ _: None{}

def remainder_pair(numerator: Maybe<&2, Nat>, denominator: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match numerator denominator:
    case Some{numerator} Some{+denominator}: remainder_if_zero(Nat.is_eq(denominator, 0n), numerator, denominator)
    case _ _: None{}

def evaluate(+capacity: Nat, calculation: Calculation) -> Maybe<&2, Nat>:
  match calculation:
    case Value{value}: Some{value}
    case Sum{left, right}: sum_pair(capacity, evaluate(capacity, left), evaluate(capacity, right))
    case Product{left, right}: product_pair(capacity, evaluate(capacity, left), evaluate(capacity, right))
    case Maximum{left, right}: maximum_pair(evaluate(capacity, left), evaluate(capacity, right))
    case Quotient{numerator, denominator}: quotient_pair(evaluate(capacity, numerator), evaluate(capacity, denominator))
    case Remainder{numerator, denominator}: remainder_pair(evaluate(capacity, numerator), evaluate(capacity, denominator))

def prepend(value: Maybe<&2, Nat>, rest: Maybe<&2, +List<Nat>>) -> Maybe<&2, +List<Nat>>:
  match value rest:
    case Some{value} Some{rest}: Some{Con{value, rest}}
    case _ _: None{}

def evaluate_all(+capacity: Nat, calculations: +List<Calculation>) -> Maybe<&2, +List<Nat>>:
  match calculations:
    case Nil{}: Some{Nil{}}
    case Con{head, tail}: prepend(evaluate(capacity, head), evaluate_all(capacity, tail))

# CSS typography can retain an upper cap; layout admission uses the checked result.

def saturated(capacity: Nat, result: Maybe<&2, Nat>) -> Nat:
  match result:
    case Some{value}: value
    case None{}: capacity
