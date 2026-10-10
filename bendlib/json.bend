import Base
import ./stdlib.bend as Std

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

def same(left: Json, right: Json) -> Bool:
  match left right:
    case Null{} Null{}: True{}
    case Boolean{left} Boolean{right}: same_bool(left, right)
    case Number{left} Number{right}: String.eq(left, right)
    case Text{left} Text{right}: String.eq(left, right)
    case Array{Nil{}} Array{Nil{}}: True{}
    case Array{Con{left_item, left_rest}} Array{Con{right_item, right_rest}}:
      same(left_item, right_item) && same(Array{left_rest}, Array{right_rest})
    case Object{Nil{}} Object{Nil{}}: True{}
    case Object{Con{Field{left_name, left_value}, left_rest}} Object{Con{Field{right_name, right_value}, right_rest}}:
      String.eq(left_name, right_name) && same(left_value, right_value) && same(Object{left_rest}, Object{right_rest})
    case _ _: False{}
    case _ _: False{}

type StackItem is Data:
  Value{value: Json}
  ArrayStart{}
  ObjectStart{}

def close_array(stack: +List<StackItem>, acc: +List<Json>) -> Result<&2, &2, String, +List<StackItem>>:
  match stack:
    case Con{Value{value}, rest}:
      close_array(rest, value <> acc)
    case Con{ArrayStart{}, rest}:
      Done{Value{Array{acc}} <> rest}
    case _:
      Fail{"invalid array framing"}

def close_object(stack: +List<StackItem>, acc: +List<Field>) -> Result<&2, &2, String, +List<StackItem>>:
  match stack:
    case Con{Value{value}, Con{Value{Text{key}}, rest}}:
      close_object(rest, Field{key, value} <> acc)
    case Con{ObjectStart{}, rest}:
      Done{Value{Object{acc}} <> rest}
    case _:
      Fail{"invalid object framing"}

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
      choose_field(String.eq(key, name), value, find(rest, name))

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

def escaped_char(code: U32) -> String:
  match code:
    case 34: "\\\""
    case 92: "\\\\"
    case +other:
      escaped_other(U32.is_lt(other, 32), other)

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

# Fuel bounds container depth and list traversal, not string length. Exhaustion
# is an error: the transport must never emit a partial value as a valid reply.

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
