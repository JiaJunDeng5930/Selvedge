import Base
import ../../bendlib/json.bend as J
import ../../bendlib/stdlib.bend as Std
import ../../bendlib/logic-proof.bend as Logic
import ./DECIMAL.bend as D
import ./EXPRESSION.bend as E

# The public evaluator must return the language value and skip unused branches.
# Its instruction stack and exact cost of individual expressions are private.
type Requirements is Type:
  Requirements{
    exhausted: @expression:E.Expr -> @env:+List<J.Field> ->
      {E.evaluate_bounded(expression, env, 0n) == E.Evaluation{Fail{"evaluation budget exceeded"}, 0n} : E.Evaluation},
    literal_true: @env:+List<J.Field> ->
      {E.evaluate(E.Literal{J.Boolean{True{}}}, env) == Done{J.Boolean{True{}}} : Result<&2, &2, String, J.Json>},
    literal_false: @env:+List<J.Field> ->
      {E.evaluate(E.Literal{J.Boolean{False{}}}, env) == Done{J.Boolean{False{}}} : Result<&2, &2, String, J.Json>},
    lazy_and: @right:E.Expr -> @env:+List<J.Field> ->
      {E.evaluate(E.Binary{"&&", E.Literal{J.Boolean{False{}}}, right}, env) == Done{J.Boolean{False{}}} : Result<&2, &2, String, J.Json>},
    lazy_or: @right:E.Expr -> @env:+List<J.Field> ->
      {E.evaluate(E.Binary{"||", E.Literal{J.Boolean{True{}}}, right}, env) == Done{J.Boolean{True{}}} : Result<&2, &2, String, J.Json>},
    lazy_conditional_yes: @unused:E.Expr -> @env:+List<J.Field> ->
      {E.evaluate(E.Conditional{E.Literal{J.Boolean{True{}}}, E.Literal{J.Boolean{True{}}}, unused}, env) == Done{J.Boolean{True{}}} : Result<&2, &2, String, J.Json>},
    lazy_conditional_no: @unused:E.Expr -> @env:+List<J.Field> ->
      {E.evaluate(E.Conditional{E.Literal{J.Boolean{False{}}}, unused, E.Literal{J.Boolean{False{}}}}, env) == Done{J.Boolean{False{}}} : Result<&2, &2, String, J.Json>},
    boolean_type_error: @right:E.Expr -> @env:+List<J.Field> ->
      {E.evaluate(E.Binary{"&&", E.Literal{J.Null{}}, right}, env) == Fail{"Boolean operand required"} : Result<&2, &2, String, J.Json>},
    division_zero: @+text:String -> @+value:D.Decimal ->
      @valid:{D.read(text) == Done{value} : Result<&2, &2, String, D.Decimal>} ->
      {D.arithmetic("/", text, "0") == Fail{"division by zero"} : Result<&2, &2, String, String>},
    task_absent_working: {E.builtin("working", [J.Null{}]) == Done{J.Boolean{False{}}} : Result<&2, &2, String, J.Json>},
    task_absent_human: {E.builtin("awaitingHuman", [J.Null{}]) == Done{J.Boolean{False{}}} : Result<&2, &2, String, J.Json>},
    no_object_text: @fields:+List<J.Field> ->
      {E.builtin("text", [J.Object{fields}]) == Fail{"text requires scalar value"} : Result<&2, &2, String, J.Json>},
    no_array_text: @items:+List<J.Json> ->
      {E.builtin("text", [J.Array{items}]) == Fail{"text requires scalar value"} : Result<&2, &2, String, J.Json>},
    budget_never_increases: @+expression:E.Expr -> @+env:+List<J.Field> -> @+budget:Nat ->
      {Nat.is_le(remaining(E.evaluate_bounded(expression, env, budget)), budget) == True{} : Bool}}

def remaining(evaluation: E.Evaluation) -> Nat:
  E.Evaluation{result, budget} = evaluation
  budget

def le_self(+value: Nat) -> {Nat.is_le(value, value) == True{} : Bool}:
  match value:
    case 0n: {==}
    case 1n+rest: le_self(rest)

def le_next(+left: Nat, +right: Nat, bound: {Nat.is_le(left, right) == True{} : Bool}) ->
  {Nat.is_le(left, 1n+right) == True{} : Bool}:
  match left right:
    case 0n _: {==}
    case 1n+rest 0n: Logic.impossible({Nat.is_le(1n+rest, 1n) == True{} : Bool}, bound)
    case 1n+rest 1n+limit: le_next(rest, limit, bound)

def active_bound(+budget: Nat, +state: E.EvalState, +env: +List<J.Field>, +active: Bool,
  recursive: {Nat.is_le(remaining(E.eval_loop(budget, E.eval_step(state, env), env)), budget) == True{} : Bool}) ->
  {Nat.is_le(remaining(E.choose(E.Evaluation, active,
    (_ => E.eval_loop(budget, E.eval_step(state, env), env)),
    (_ => E.Evaluation{Fail{E.eval_error(state)}, budget}))), 1n+budget) == True{} : Bool}:
  match active:
    case True{}: le_next(remaining(E.eval_loop(budget, E.eval_step(state, env), env)), budget, recursive)
    case False{}: le_next(budget, budget, le_self(budget))

def loop_branch(+budget: Nat, +state: E.EvalState, +env: +List<J.Field>, +active: Bool,
  observed: {String.eq(E.eval_error(state), "") == active : Bool},
  recursive: {Nat.is_le(remaining(E.eval_loop(budget, E.eval_step(state, env), env)), budget) == True{} : Bool}) ->
  {Nat.is_le(remaining(E.choose(E.Evaluation, String.eq(E.eval_error(state), ""),
    (_ => E.eval_loop(budget, E.eval_step(state, env), env)),
    (_ => E.Evaluation{Fail{E.eval_error(state)}, budget}))), 1n+budget) == True{} : Bool}:
  Std.transport(Bool, active,
    (condition => {Nat.is_le(remaining(E.choose(E.Evaluation, condition,
      (_ => E.eval_loop(budget, E.eval_step(state, env), env)),
      (_ => E.Evaluation{Fail{E.eval_error(state)}, budget}))), 1n+budget) == True{} : Bool}),
    active_bound(budget, state, env, active, recursive),
    String.eq(E.eval_error(state), ""), observed)

def loop_bound(+budget: Nat, +state: E.EvalState, +env: +List<J.Field>) ->
  {Nat.is_le(remaining(E.eval_loop(budget, state, env)), budget) == True{} : Bool}:
  match budget state:
    case +budget E.EvalState{Nil{}, Con{value, Nil{}}, SNil{}}: le_self(budget)
    case 0n E.EvalState{Nil{}, Con{value, Nil{}}, SCon{character, error}}: {==}
    case 1n+rest E.EvalState{Nil{}, Con{+value, Nil{}}, SCon{+character, +error}}:
      +state: E.EvalState = E.EvalState{Nil{}, Con{value, Nil{}}, SCon{character, error}}
      loop_branch(rest, state, env, String.eq(E.eval_error(state), ""), {==},
        loop_bound(rest, E.eval_step(state, env), env))
    case 0n E.EvalState{Nil{}, Nil{}, error}: {==}
    case 1n+rest E.EvalState{Nil{}, Nil{}, +error}:
      +state: E.EvalState = E.EvalState{Nil{}, Nil{}, error}
      loop_branch(rest, state, env, String.eq(E.eval_error(state), ""), {==},
        loop_bound(rest, E.eval_step(state, env), env))
    case 0n E.EvalState{Nil{}, Con{first, Con{second, values}}, error}: {==}
    case 1n+rest E.EvalState{Nil{}, Con{+first, Con{+second, +values}}, +error}:
      +state: E.EvalState = E.EvalState{Nil{}, Con{first, Con{second, values}}, error}
      loop_branch(rest, state, env, String.eq(E.eval_error(state), ""), {==},
        loop_bound(rest, E.eval_step(state, env), env))
    case 0n E.EvalState{Con{task, tasks}, values, error}: {==}
    case 1n+rest E.EvalState{Con{+task, +tasks}, +values, +error}:
      +state: E.EvalState = E.EvalState{Con{task, tasks}, values, error}
      loop_branch(rest, state, env, String.eq(E.eval_error(state), ""), {==},
        loop_bound(rest, E.eval_step(state, env), env))

def division_zero(+text: String, +value: D.Decimal,
  valid: {D.read(text) == Done{value} : Result<&2, &2, String, D.Decimal>}) ->
  {D.arithmetic("/", text, "0") == Fail{"division by zero"} : Result<&2, &2, String, String>}:
  match value:
    case D.Decimal{negative, magnitude}:
      Std.transport(Result<&2, &2, String, D.Decimal>, Done{D.Decimal{negative, magnitude}},
        (parsed => {D.arithmetic_results("/", parsed, D.read("0")) == Fail{"division by zero"} : Result<&2, &2, String, String>}),
        {==}, D.read(text), valid)

def evidence() -> Requirements:
  Requirements{
    expression => env => {==},
    env => {==}, env => {==},
    right => env => {==}, right => env => {==},
    unused => env => {==}, unused => env => {==},
    right => env => {==}, division_zero,
    {==}, {==}, fields => {==}, items => {==},
    expression => env => budget => loop_bound(budget, E.EvalState{[E.Visit{expression, 33n}], Nil{}, ""}, env)}
