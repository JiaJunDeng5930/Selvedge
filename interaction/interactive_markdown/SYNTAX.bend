import Base
import ../../bendlib/string-equality.bend as SafeText
import ./TYPES.bend as T
import ./EXPRESSION.bend as E
import ./DECIMAL.bend as D
import ../../bendlib/json.bend as J

def same_owner(+left: T.Owner, +right: T.Owner) -> Bool:
  T.Owner{ +key, +epoch} = left
  T.Owner{ +other, +serial} = right
  String.eq(key, other) && Nat.is_eq(epoch, serial)

def owner_key(+owner: T.Owner) -> String:
  T.Owner{ +key, +epoch} = owner
  key ++ "/epoch/" ++ Nat.show(epoch)

def identity_key(+identity: T.Identity) -> String:
  T.Identity{ +owner, +path} = identity
  owner_key(owner) ++ "/" ++ path

def same_identity(+left: T.Identity, +right: T.Identity) -> Bool:
  SafeText.string_equal(identity_key(left), identity_key(right))

def same_event(+left: T.EventIdentity, +right: T.EventIdentity) -> Bool:
  T.EventIdentity{ +identity, +occurrence} = left
  T.EventIdentity{ +other, +serial} = right
  same_identity(identity, other) && Nat.is_eq(occurrence, serial)

def scalar_text(+value: J.Json) -> String:
  match value:
    case J.Null{}: ""
    case J.Text{text}: text
    case J.Number{text}: text
    case J.Boolean{value}: Bool.show(value)
    case _: ""

def source(+attrs: +List<T.Attribute>, +name: String) -> Maybe<&2, String>:
  match attrs:
    case Nil{}: None{}
    case Con{T.Attribute{key, value}, rest}:
      Bool.pick(Maybe<&2, String>, String.eq(key, name), Some{value}, source(rest, name))

def evaluate_parsed(+result: Result<&2, &2, String, E.Expr>, +env: +List<J.Field>) -> Result<&2, &2, String, J.Json>:
  match result:
    case Fail{reason}: Fail{reason}
    case Done{expr}: E.evaluate(expr, env)

def evaluate(+text: String, +env: +List<J.Field>) -> Result<&2, &2, String, J.Json>:
  evaluate_parsed(E.parse(text), env)

def literal_admitted(+expr: E.Expr, +allowed: Bool) -> Result<&2, &2, String, J.Json>:
  match allowed:
    case True{}: E.evaluate(expr, Nil{})
    case False{}: Fail{"This declaration requires a literal value"}

def literal_parsed(+result: Result<&2, &2, String, E.Expr>) -> Result<&2, &2, String, J.Json>:
  match result:
    case Fail{reason}: Fail{reason}
    case Done{+expr}: literal_admitted(expr, E.literal_only(expr))

def literal(+text: String) -> Result<&2, &2, String, J.Json>:
  literal_parsed(E.parse(text))

def value_or(+result: Result<&2, &2, String, J.Json>, +fallback: J.Json) -> J.Json:
  match result:
    case Done{value}: value
    case Fail{reason}: fallback

def attribute_found(+found: Maybe<&2, String>, +env: +List<J.Field>, +fallback: J.Json) -> J.Json:
  match found:
    case None{}: fallback
    case Some{text}: value_or(evaluate(text, env), fallback)

def attribute(+attrs: +List<T.Attribute>, +name: String, +env: +List<J.Field>, +fallback: J.Json) -> J.Json:
  attribute_found(source(attrs, name), env, fallback)

def literal_found(+found: Maybe<&2, String>, +fallback: J.Json) -> J.Json:
  match found:
    case None{}: fallback
    case Some{text}: value_or(literal(text), fallback)

def literal_attribute(+attrs: +List<T.Attribute>, +name: String, +fallback: J.Json) -> J.Json:
  literal_found(source(attrs, name), fallback)

def attributes_join(+name: String, +head: Result<&2, &2, String, J.Json>, +tail: Result<&2, &2, String, +List<J.Field>>) -> Result<&2, &2, String, +List<J.Field>>:
  match head tail:
    case Fail{reason} _: Fail{reason}
    case _ Fail{reason}: Fail{reason}
    case Done{value} Done{rest}: Done{J.Field{name, value} <> rest}

def attributes(+attrs: +List<T.Attribute>, +env: +List<J.Field>) -> Result<&2, &2, String, +List<J.Field>>:
  match attrs:
    case Nil{}: Done{Nil{}}
    case Con{T.Attribute{name, text}, rest}:
      attributes_join(name, evaluate(text, env), attributes(rest, env))

def field_has(+fields: +List<J.Field>, +name: String) -> Bool:
  match fields:
    case Nil{}: False{}
    case Con{J.Field{key, value}, rest}: SafeText.string_equal(key, name) || field_has(rest, name)

def field_remove(+fields: +List<J.Field>, +name: String) -> +List<J.Field>:
  match fields:
    case Nil{}: Nil{}
    case Con{J.Field{+key, value}, rest}:
      +filtered = field_remove(rest, name)
      Bool.pick(+List<J.Field>, SafeText.string_equal(key, name), filtered, J.Field{key, value} <> filtered)

def field_set(+fields: +List<J.Field>, +name: String, +value: J.Json) -> +List<J.Field>:
  J.Field{name, value} <> field_remove(fields, name)

def strings(+values: +List<J.Json>) -> +List<String>:
  match values:
    case Nil{}: Nil{}
    case Con{J.Text{text}, rest}: text <> strings(rest)
    case Con{other, rest}: strings(rest)

def string_seen(+values: +List<String>, +value: String) -> Bool:
  match values:
    case Nil{}: False{}
    case Con{first, rest}: SafeText.string_equal(first, value) || string_seen(rest, value)

def id_tail(+text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{Chr{+code}, rest}:
      ((U32.is_le(65, code) && U32.is_le(code, 90)) || (U32.is_le(97, code) && U32.is_le(code, 122)) ||
      (U32.is_le(48, code) && U32.is_le(code, 57)) || U32.is_eq(code, 45) || U32.is_eq(code, 95)) && id_tail(rest)

def id_first(+text: String) -> Bool:
  match text:
    case SNil{}: False{}
    case SCon{Chr{+code}, rest}:
      ((U32.is_le(65, code) && U32.is_le(code, 90)) || (U32.is_le(97, code) && U32.is_le(code, 122))) && id_tail(rest)

def valid_id(+text: String) -> Bool:
  Nat.is_le(String.length(text), 64n) && id_first(text)

def kind_name(+kind: T.StateKind) -> String:
  match kind:
    case T.IntegerState{}: "integer"
    case T.NumberState{}: "number"
    case T.BooleanState{}: "boolean"
    case T.StringState{}: "string"
    case T.EnumState{}: "enum"

def optional_json(+value: Maybe<&2, J.Json>) -> J.Json:
  match value:
    case None{}: J.Null{}
    case Some{value}: value

def schema_json(+schema: T.StateSchema) -> J.Json:
  T.StateSchema{ +kind, +initial, +minimum, +maximum, +step, +options, +max_length} = schema
  J.Object{[J.Field{"type", J.Text{kind_name(kind)}}, J.Field{"initial", initial},
    J.Field{"min", optional_json(minimum)}, J.Field{"max", optional_json(maximum)},
    J.Field{"step", step}, J.Field{"options", J.Array{J.text_items(options)}}, J.Field{"maxLength", J.nat(max_length)}]}

def same_schema(+left: T.StateSchema, +right: T.StateSchema) -> Bool:
  J.same(schema_json(left), schema_json(right))

def decimal_bool(+result: Result<&2, &2, String, Bool>) -> Bool:
  match result:
    case Done{value}: value
    case Fail{reason}: False{}

def number_bound(+value: J.Json, +bound: Maybe<&2, J.Json>, +op: String) -> Bool:
  match value bound:
    case J.Number{number} Some{J.Number{bound}}: decimal_bool(D.compare(op, number, bound))
    case J.Number{number} None{}: True{}
    case _ _: False{}

def valid_number(+parsed: Result<&2, &2, String, String>) -> Bool:
  match parsed:
    case Done{number}: True{}
    case Fail{reason}: False{}

def step_anchor(+minimum: Maybe<&2, J.Json>) -> String:
  match minimum:
    case Some{J.Number{number}}: number
    case None{}: "0"
    case _: ""

def number_step(+number: String, +minimum: Maybe<&2, J.Json>, +step: J.Json) -> Bool:
  match step:
    case J.Number{stride}: D.step_matches(number, step_anchor(minimum), stride)
    case _: False{}

def schema_accepts(+schema: T.StateSchema, +value: J.Json) -> Bool:
  T.StateSchema{ +kind, +initial, +minimum, +maximum, +step, +options, +max_length} = schema
  match kind value:
    case T.IntegerState{} J.Number{+number}: number_step(number, minimum, step) && valid_number(D.parse(number)) && D.integral(number) && number_bound(J.Number{number}, minimum, ">=") && number_bound(J.Number{number}, maximum, "<=")
    case T.NumberState{} J.Number{+number}: number_step(number, minimum, step) && valid_number(D.parse(number)) && number_bound(J.Number{number}, minimum, ">=") && number_bound(J.Number{number}, maximum, "<=")
    case T.BooleanState{} J.Boolean{value}: True{}
    case T.StringState{} J.Text{text}: Nat.is_le(String.length(text), max_length)
    case T.EnumState{} J.Text{text}: string_seen(options, text)
    case _ _: False{}

def binding_tail(+text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{'-', rest}: False{}
    case SCon{c, rest}: binding_tail(rest)

def valid_binding_id(+text: String) -> Bool:
  valid_id(text) && binding_tail(text) && Bool.not(String.eq(text, "true") || String.eq(text, "false") || String.eq(text, "null"))
