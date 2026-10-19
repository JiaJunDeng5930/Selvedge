import Base
import ./string-equality.bend as SafeText
import ./stdlib.bend as Std
import ./categories.bend as Categories

type Json is Data:
  Null{}
  Boolean{value: Bool}
  Number{lexeme: String}
  Text{value: String}
  Array{items: List<&2, Json>}
  Object{fields: List<&2, Field>}

type Field is Data:
  Field{name: String, value: Json}

# Identity compares the canonical encoded structure without a rendering budget.

def same_bool(left: Bool, right: Bool) -> Bool:
  match left right:
    case True{} True{}: True{}
    case False{} False{}: True{}
    case _ _: False{}

def same_text(+left: String, +right: String) -> Bool:
  String.starts_with(left, right) && String.starts_with(right, left)

def same(left: Json, right: Json) -> Bool:
  match left right:
    case Null{} Null{}: True{}
    case Boolean{left} Boolean{right}: same_bool(left, right)
    case Number{left} Number{right}: same_text(left, right)
    case Text{left} Text{right}: same_text(left, right)
    case Array{Nil{}} Array{Nil{}}: True{}
    case Array{Con{left_item, left_rest}} Array{Con{right_item, right_rest}}:
      same(left_item, right_item) && same(Array{left_rest}, Array{right_rest})
    case Object{Nil{}} Object{Nil{}}: True{}
    case Object{Con{Field{left_name, left_value}, left_rest}} Object{Con{Field{right_name, right_value}, right_rest}}:
      same_text(left_name, right_name) && same(left_value, right_value) && same(Object{left_rest}, Object{right_rest})
    case _ _: False{}

# Objects with unique keys compare independently of field order. Array order
# and numeric lexemes retain their structural meaning.
type UnorderedFieldSelection is Data:
  UnorderedFieldSelection{found: Bool, value: Json, rest: +List<Field>}

def same_unordered_select(equal: Bool, value: Json, rest: +List<Field>, field: Field, selected: UnorderedFieldSelection) -> UnorderedFieldSelection:
  match equal:
    case True{}: UnorderedFieldSelection{True{}, value, rest}
    case False{}:
      UnorderedFieldSelection{found, value, tail} = selected
      UnorderedFieldSelection{found, value, Con{field, tail}}

def same_unordered_take(+name: String, fields: +List<Field>) -> UnorderedFieldSelection:
  match fields:
    case Nil{}: UnorderedFieldSelection{False{}, Null{}, Nil{}}
    case Con{Field{+key, +value}, +rest}:
      same_unordered_select(same_text(key, name), value, rest, Field{key, value}, same_unordered_take(name, rest))

def same_unordered_selected_found(selected: UnorderedFieldSelection) -> Bool:
  UnorderedFieldSelection{found, value, rest} = selected
  found

def same_unordered_selected_value(selected: UnorderedFieldSelection) -> Json:
  UnorderedFieldSelection{found, value, rest} = selected
  value

def same_unordered_selected_rest(selected: UnorderedFieldSelection) -> +List<Field>:
  UnorderedFieldSelection{found, value, rest} = selected
  rest

def same_unordered(left: Json, right: Json) -> Bool:
  match left right:
    case Null{} Null{}: True{}
    case Boolean{left} Boolean{right}: same_bool(left, right)
    case Number{left} Number{right}: same_text(left, right)
    case Text{left} Text{right}: same_text(left, right)
    case Array{Nil{}} Array{Nil{}}: True{}
    case Array{Con{left, left_rest}} Array{Con{right, right_rest}}:
      same_unordered(left, right) && same_unordered(Array{left_rest}, Array{right_rest})
    case Object{Nil{}} Object{Nil{}}: True{}
    case Object{Con{Field{name, value}, left_rest}} Object{right_fields}:
      +selection = same_unordered_take(name, right_fields)
      same_unordered_selected_found(selection) && same_unordered(value, same_unordered_selected_value(selection)) && same_unordered(Object{left_rest}, Object{same_unordered_selected_rest(selection)})
    case _ _: False{}

type StackItem is Data:
  Value{value: Json}
  ArrayStart{}
  ObjectStart{}

# DEFENSE: A token packet may close an array without a matching array opener; reject its framing.
def close_array(stack: +List<StackItem>, acc: +List<Json>) -> Result<&2, &2, String, +List<StackItem>>:
  match stack:
    case Con{Value{value}, rest}:
      close_array(rest, value <> acc)
    case Con{ArrayStart{}, rest}:
      Done{Value{Array{acc}} <> rest}
    case _:
      Fail{"invalid array framing"}

# DEFENSE: Object tokens may omit a string key or matching opener; reject the packet instead of inventing fields.
def close_object(stack: +List<StackItem>, acc: +List<Field>) -> Result<&2, &2, String, +List<StackItem>>:
  match stack:
    case Con{Value{value}, Con{Value{Text{key}}, rest}}:
      close_object(rest, Field{key, value} <> acc)
    case Con{ObjectStart{}, rest}:
      Done{Value{Object{acc}} <> rest}
    case _:
      Fail{"invalid object framing"}

# DEFENSE: The native token ABI admits only the listed tags; reject an unknown tag before constructing JSON.
def push(token: String, stack: +List<StackItem>) -> Result<&2, &2, String, +List<StackItem>>:
  match token:
    case SCon{'s', text}:
      Done{Value{Text{text}} <> stack}
    case SCon{'n', text}:
      Done{Value{Number{text}} <> stack}
    case SCon{'t', SNil{}}:
      Done{Value{Boolean{True{}}} <> stack}
    case SCon{'f', SNil{}}:
      Done{Value{Boolean{False{}}} <> stack}
    case SCon{'z', SNil{}}:
      Done{Value{Null{}} <> stack}
    case SCon{'[', SNil{}}:
      Done{ArrayStart{} <> stack}
    case SCon{']', SNil{}}:
      close_array(stack, Nil{})
    case SCon{'{', SNil{}}:
      Done{ObjectStart{} <> stack}
    case SCon{'}', SNil{}}:
      close_object(stack, Nil{})
    case _:
      Fail{"unknown JSON token"}

# DEFENSE: A packet may end with unmatched containers, no value, or multiple values; require exactly one completed value.
def decode_go(tokens: +List<String>, stack: Result<&2, &2, String, +List<StackItem>>) -> Result<&2, &2, String, Json>:
  match tokens stack:
    case Nil{} Done{Con{Value{value}, Nil{}}}:
      Done{value}
    case Nil{} _:
      Fail{"incomplete JSON value"}
    case Con{token, rest} Done{items}:
      decode_go(rest, push(token, items))
    case Con{token, rest} Fail{error}:
      Fail{error}

def decode(tokens: +List<String>) -> Result<&2, &2, String, Json>:
  decode_go(tokens, Done{Nil{}})

def choose_field(same: Bool, value: Json, rest: Json) -> Json:
  match same:
    case True{}:
      value
    case False{}:
      rest

def find(fields: +List<Field>, +name: String) -> Json:
  match fields:
    case Nil{}:
      Null{}
    case Con{Field{key, value}, rest}:
      choose_field(SafeText.string_equal(key, name), value, find(rest, name))

def get(value: Json, name: String) -> Json:
  match value:
    case Object{fields}:
      find(fields, name)
    case _:
      Null{}

def text(value: Json) -> String:
  match value:
    case Text{value}:
      value
    case _:
      ""

def text_items(values: +List<String>) -> +List<Json>:
  Std.map(~String, ~Json, ~(text => Text{text}), values)

def text_values(values: +List<Json>) -> +List<String>:
  Std.map(~Json, ~String, ~text, values)

def optional_text(value: Json) -> Maybe<&2, String>:
  match value:
    case Text{text}: Some{text}
    case _: None{}

def text_or(value: Json, fallback: String) -> String:
  match value:
    case Text{text}: text
    case _: fallback

def is_text(value: Json) -> Bool:
  match value:
    case Text{value}:
      True{}
    case _:
      False{}

def is_object(value: Json) -> Bool:
  match value:
    case Object{fields}:
      True{}
    case _:
      False{}

def items(value: Json) -> +List<Json>:
  match value:
    case Array{items}:
      items
    case _:
      Nil{}

def boolean(value: Json) -> Bool:
  match value:
    case Boolean{value}:
      value
    case _:
      False{}

def natural(value: Json) -> Maybe<&2, Nat>:
  match value:
    case Number{lexeme}:
      Nat.read(lexeme)
    case _:
      None{}

def natural_or(value: Maybe<&2, Nat>, fallback: Nat) -> Nat:
  match value:
    case Some{n}:
      n
    case None{}:
      fallback

def nat(n: Nat) -> Json:
  Number{Nat.show(n)}

def optional_nat(value: Maybe<&2, Nat>) -> Json:
  match value:
    case Some{n}:
      nat(n)
    case None{}:
      Null{}

def hex_digit(n: U32) -> String:
  match n:
    case 0: "0"
    case 1: "1"
    case 2: "2"
    case 3: "3"
    case 4: "4"
    case 5: "5"
    case 6: "6"
    case 7: "7"
    case 8: "8"
    case 9: "9"
    case 10: "a"
    case 11: "b"
    case 12: "c"
    case 13: "d"
    case 14: "e"
    case _: "f"

def escaped_other(control: Bool, +code: U32) -> String:
  match control:
    case True{}:
      "\\u00" ++ hex_digit(U32.div(code, 16)) ++ hex_digit(U32.mod(code, 16))
    case False{}:
      SCon{Chr{code}, SNil{}}

def escaped_decision(quote: Bool, backslash: Bool, +code: U32) -> String:
  match quote backslash:
    case True{} _: "\\\""
    case False{} True{}: "\\\\"
    case False{} False{}: escaped_other(U32.is_lt(code, 32), code)

def escaped_char(+code: U32) -> String:
  escaped_decision(U32.is_eq(code, 34), U32.is_eq(code, 92), code)

# Each escaped character contributes at most six characters, bounding append depth.

def escape_collect(text: String, parts: +List<String>) -> +List<String>:
  match text:
    case SNil{}: parts
    case SCon{Chr{code}, rest}:
      escape_collect(rest, Con{escaped_char(code), parts})

def escape_join(parts: +List<String>, suffix: String) -> String:
  match parts:
    case Nil{}: suffix
    case Con{part, rest}: escape_join(rest, part ++ suffix)

def escape(text: String) -> String:
  escape_join(escape_collect(text, Nil{}), "")

def quote(text: String) -> String:
  "\"" ++ escape(text) ++ "\""

def show_bool(value: Bool) -> String:
  match value:
    case True{}: "true"
    case False{}: "false"

def comma(first: Bool) -> String:
  match first:
    case True{}: ""
    case False{}: ","

type Render is Data:
  One{value: Json}
  Elements{values: +List<Json>, first: Bool}
  Fields{values: +List<Field>, first: Bool}

# A recursive edge consumes one unit; sibling jobs receive the same remainder.

def payload_required(+value: Json) -> Nat:
  match value:
    case Null{}: 0n
    case Boolean{value}: 0n
    case Number{lexeme}: 0n
    case Text{value}: 0n
    case Array{Nil{}}: 1n
    case Array{Con{head, tail}}:
      1n+Nat.max(1n+payload_required(head), payload_required(Array{tail}))
    case Object{Nil{}}: 1n
    case Object{Con{Field{key, value}, tail}}:
      1n+Nat.max(1n+payload_required(value), payload_required(Object{tail}))

def required(+job: Render) -> Nat:
  match job:
    case One{value}: 1n+payload_required(value)
    case Elements{values, first}: payload_required(Array{values})
    case Fields{values, first}: payload_required(Object{values})

def join(left: Result<&2, &2, String, String>, right: Result<&2, &2, String, String>) -> Result<&2, &2, String, String>:
  match left right:
    case Done{a} Done{b}: Done{a ++ b}
    case Fail{error} _: Fail{error}
    case _ Fail{error}: Fail{error}

def surround(left: String, middle: Result<&2, &2, String, String>, right: String) -> Result<&2, &2, String, String>:
  join(Done{left}, join(middle, Done{right}))

# DEFENSE: Explicit render budgets can be exhausted by deeply nested or long
# user/model values; return an error instead of emitting a partial JSON reply.

def render(fuel: Nat, job: Render) -> Result<&2, &2, String, String>:
  match fuel job:
    case 0n _:
      Fail{"JSON rendering limit exceeded"}
    case 1n+p One{Null{}}:
      Done{"null"}
    case 1n+p One{Boolean{value}}:
      Done{show_bool(value)}
    case 1n+p One{Number{lexeme}}:
      Done{lexeme}
    case 1n+p One{Text{value}}:
      Done{quote(value)}
    case 1n+p One{Array{items}}:
      surround("[", render(p, Elements{items, True{}}), "]")
    case 1n+p One{Object{fields}}:
      surround("{", render(p, Fields{fields, True{}}), "}")
    case 1n+p Elements{Nil{}, first}:
      Done{""}
    case 1n+ +p Elements{Con{head, tail}, first}:
      surround(comma(first), join(render(p, One{head}), render(p, Elements{tail, False{}})), "")
    case 1n+p Fields{Nil{}, first}:
      Done{""}
    case 1n+ +p Fields{Con{Field{key, value}, tail}, first}:
      surround(comma(first) ++ quote(key) ++ ":", join(render(p, One{value}), render(p, Fields{tail, False{}})), "")

def show(+value: Json) -> Result<&2, &2, String, String>:
  render(required(One{value}), One{value})

# The witness retains the text produced by the bounded renderer itself.
def Completed(-result: Result<&2, &2, String, String>) -> Type:
  Sigma<&2, &1, String, (text => {result == Done{text} : Result<&2, &2, String, String>})>

# Equality elimination closes the impossible exhausted-budget branches.

def exhausted(+job: Render,
  enough: {Nat.is_ge(0n, required(job)) == True{} : Bool}) ->
  Completed(render(0n, job)):
  match job:
    case One{Null{}}: Categories.impossible(Completed(render(0n, One{Null{}})), enough)
    case One{Boolean{value}}: Categories.impossible(Completed(render(0n, One{Boolean{value}})), enough)
    case One{Number{lexeme}}: Categories.impossible(Completed(render(0n, One{Number{lexeme}})), enough)
    case One{Text{value}}: Categories.impossible(Completed(render(0n, One{Text{value}})), enough)
    case One{Array{items}}: Categories.impossible(Completed(render(0n, One{Array{items}})), enough)
    case One{Object{fields}}: Categories.impossible(Completed(render(0n, One{Object{fields}})), enough)
    case Elements{Nil{}, first}: Categories.impossible(Completed(render(0n, Elements{Nil{}, first})), enough)
    case Elements{Con{head, tail}, first}:
      Categories.impossible(Completed(render(0n, Elements{Con{head, tail}, first})), enough)
    case Fields{Nil{}, first}: Categories.impossible(Completed(render(0n, Fields{Nil{}, first})), enough)
    case Fields{Con{Field{key, value}, tail}, first}:
      Categories.impossible(Completed(render(0n, Fields{Con{Field{key, value}, tail}, first})), enough)

# Base supplies both maximum bounds. This local bridge passes an enclosing
# render budget through such a bound without re-proving the maximum theorems.

def budget_lower_bound(+budget: Nat, +ceiling: Nat, +lower: Nat,
  fits: {Nat.is_ge(budget, ceiling) == True{} : Bool},
  bound: {Nat.is_ge(ceiling, lower) == True{} : Bool}) ->
  {Nat.is_ge(budget, lower) == True{} : Bool}:
  match budget ceiling lower:
    case 0n _ 0n: {==}
    case 1n+rest _ 0n: {==}
    case _ 0n 1n+rest:
      Categories.impossible({Nat.is_ge(budget, 1n+rest) == True{} : Bool}, bound)
    case 0n 1n+rest 1n+lower_rest:
      Categories.impossible({Nat.is_ge(0n, 1n+lower_rest) == True{} : Bool}, fits)
    case 1n+budget_rest 1n+ceiling_rest 1n+lower_rest:
      budget_lower_bound(budget_rest, ceiling_rest, lower_rest, fits, bound)

def joined(+left: Result<&2, &2, String, String>, +right: Result<&2, &2, String, String>,
  left_done: Completed(left), right_done: Completed(right)) ->
  Completed(join(left, right)):
  (+a, left_equal) = left_done
  (+b, right_equal) = right_done
  (a ++ b, Equal.trans(Result<&2, &2, String, String>,
    join(left, right), join(Done{a}, right), Done{a ++ b},
    Equal.cong(Result<&2, &2, String, String>, Result<&2, &2, String, String>,
      (result => join(result, right)), left, Done{a}, left_equal),
    Equal.cong(Result<&2, &2, String, String>, Result<&2, &2, String, String>,
      (result => join(Done{a}, result)), right, Done{b}, right_equal)))

def surrounded(+left: String, +middle: Result<&2, &2, String, String>, +right: String,
  middle_done: Completed(middle)) -> Completed(surround(left, middle, right)):
  joined(Done{left}, join(middle, Done{right}), (left, {==}),
    joined(middle, Done{right}, middle_done, (right, {==})))

def sufficient(+fuel: Nat, +job: Render,
  enough: {Nat.is_ge(fuel, required(job)) == True{} : Bool}) ->
  Completed(render(fuel, job)):
  match fuel:
    case 0n: exhausted(job, enough)
    case 1n+remaining:
      match job:
        case One{Null{}}: ("null", {==})
        case One{Boolean{value}}: (show_bool(value), {==})
        case One{Number{lexeme}}: (lexeme, {==})
        case One{Text{value}}: (quote(value), {==})
        case One{Array{items}}:
          surrounded("[", render(remaining, Elements{items, True{}}), "]",
            sufficient(remaining, Elements{items, True{}}, enough))
        case One{Object{fields}}:
          surrounded("{", render(remaining, Fields{fields, True{}}), "}",
            sufficient(remaining, Fields{fields, True{}}, enough))
        case Elements{Nil{}, first}: ("", {==})
        case Elements{Con{head, tail}, first}:
          +fits = enough
          +head_job: Render = One{head}
          +tail_job: Render = Elements{tail, False{}}
          +head_budget = required(head_job)
          +tail_budget = required(tail_job)
          surrounded(comma(first), join(render(remaining, head_job), render(remaining, tail_job)), "",
            joined(render(remaining, head_job), render(remaining, tail_job),
              sufficient(remaining, head_job, budget_lower_bound(remaining, Nat.max(head_budget, tail_budget), head_budget,
                fits, Nat.max_ge_l(head_budget, tail_budget))),
              sufficient(remaining, tail_job, budget_lower_bound(remaining, Nat.max(head_budget, tail_budget), tail_budget,
                fits, Nat.max_ge_r(head_budget, tail_budget)))))
        case Fields{Nil{}, first}: ("", {==})
        case Fields{Con{Field{key, value}, tail}, first}:
          +fits = enough
          +head_job: Render = One{value}
          +tail_job: Render = Fields{tail, False{}}
          +head_budget = required(head_job)
          +tail_budget = required(tail_job)
          surrounded(comma(first) ++ quote(key) ++ ":",
            join(render(remaining, head_job), render(remaining, tail_job)), "",
            joined(render(remaining, head_job), render(remaining, tail_job),
              sufficient(remaining, head_job, budget_lower_bound(remaining, Nat.max(head_budget, tail_budget), head_budget,
                fits, Nat.max_ge_l(head_budget, tail_budget))),
              sufficient(remaining, tail_job, budget_lower_bound(remaining, Nat.max(head_budget, tail_budget), tail_budget,
                fits, Nat.max_ge_r(head_budget, tail_budget)))))

def render_complete(+job: Render) -> Completed(render(required(job), job)):
  sufficient(required(job), job, Nat.ge_refl(required(job)))

def show_complete(+value: Json) -> Completed(show(value)):
  render_complete(One{value})

# Total JSON serialization projects the existing renderer's completion witness.
# Callers that do not impose a budget cannot encounter rendering exhaustion.
def completed_text(-result: Result<&2, &2, String, String>, completion: Completed(result)) -> String:
  (text, evidence) = completion
  text

def completed_text_correct(-result: Result<&2, &2, String, String>, completion: Completed(result)) ->
  {result == Done{completed_text(result, completion)} : Result<&2, &2, String, String>}:
  (text, evidence) = completion
  evidence

def stringify(+value: Json) -> String:
  completed_text(show(value), show_complete(value))

def stringify_complete(+value: Json) ->
  {show(value) == Done{stringify(value)} : Result<&2, &2, String, String>}:
  completed_text_correct(show(value), show_complete(value))

def char_width(ascii: Bool, two: Bool, three: Bool) -> Nat:
  match ascii two three:
    case True{} _ _: 1n
    case False{} True{} _: 2n
    case False{} False{} True{}: 3n
    case _ _ _: 4n

def utf8_length_spec(text: String) -> Nat:
  match text:
    case SNil{}: 0n
    case SCon{Chr{+code}, rest}:
      Nat.add(char_width(U32.is_lt(code, 128), U32.is_lt(code, 2048), U32.is_lt(code, 65536)), utf8_length_spec(rest))

def utf8_length_acc(text: String, total: Nat) -> Nat:
  match text:
    case SNil{}: total
    case SCon{Chr{+code}, rest}:
      utf8_length_acc(rest, Nat.add(total, char_width(U32.is_lt(code, 128), U32.is_lt(code, 2048), U32.is_lt(code, 65536))))

def utf8_length(text: String) -> Nat:
  utf8_length_acc(text, 0n)
