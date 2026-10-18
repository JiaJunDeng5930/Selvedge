import Base
import ./TYPES.bend as T
import ./SYNTAX.bend as S
import ./DECIMAL.bend as D
import ../../bendlib/json.bend as J

def optional_number(+value: J.Json) -> Maybe<&2, J.Json>:
  match value:
    case J.Number{text}: Some{J.Number{text}}
    case _: None{}

def strings_valid(+values: +List<J.Json>, +seen: +List<String>) -> Bool:
  match values:
    case Nil{}: True{}
    case Con{J.Text{+text}, rest}: Bool.not(String.is_empty(text)) && Bool.not(S.string_seen(seen, text)) && strings_valid(rest, text <> seen)
    case _: False{}

def optional_number_valid(+value: J.Json) -> Bool:
  match value:
    case J.Null{}: True{}
    case J.Number{text}: True{}
    case _: False{}

def numeric_valid(+initial: J.Json, +minimum: J.Json, +maximum: J.Json, +step: J.Json) -> Bool:
  match step:
    case J.Number{step}: optional_number_valid(minimum) && optional_number_valid(maximum) && S.decimal_bool(D.compare(">", step, "0"))
    case _: False{}

def enum_valid(+options: J.Json) -> Bool:
  match options:
    case J.Array{+values}: Bool.not(List.is_empty(&2, J.Json, values)) && Nat.is_le(List.length(&2, J.Json, values), 256n) && strings_valid(values, Nil{})
    case _: False{}

def admit(+schema: T.StateSchema, +valid: Bool) -> Result<&2, &2, String, T.StateSchema>:
  match valid:
    case True{}: Done{schema}
    case False{}: Fail{"Invalid state type, default, range, step or options"}

def valid_options(+kind: T.StateKind, +initial: J.Json, +minimum: J.Json, +maximum: J.Json, +step: J.Json, +options: J.Json, +max_length: Nat) -> Bool:
  match kind:
    case T.IntegerState{}: numeric_valid(initial, minimum, maximum, step) && D.integral(S.scalar_text(step))
    case T.NumberState{}: numeric_valid(initial, minimum, maximum, step)
    case T.BooleanState{}: True{}
    case T.StringState{}: Nat.is_le(max_length, 16384n)
    case T.EnumState{}: enum_valid(options)

def build(+kind: T.StateKind, +initial: J.Json, +minimum: J.Json, +maximum: J.Json, +step: J.Json, +options: J.Json, +max_length: Nat) -> Result<&2, &2, String, T.StateSchema>:
  +schema = {T.StateSchema{kind, initial, optional_number(minimum), optional_number(maximum), step, S.strings(J.items(options)), max_length} : T.StateSchema}
  admit(schema, S.schema_accepts(schema, initial) && valid_options(kind, initial, minimum, maximum, step, options, max_length))

def length_value(+value: J.Json) -> Nat:
  J.natural_or(J.natural(value), 4096n)

def kind_schema(+kind: String, +attrs: +List<T.Attribute>) -> Result<&2, &2, String, T.StateSchema>:
  match kind:
    case "integer": build(T.IntegerState{}, S.literal_attribute(attrs, "initial", J.Null{}), S.literal_attribute(attrs, "min", J.Null{}), S.literal_attribute(attrs, "max", J.Null{}), S.literal_attribute(attrs, "step", J.Number{"1"}), J.Null{}, 4096n)
    case "number": build(T.NumberState{}, S.literal_attribute(attrs, "initial", J.Null{}), S.literal_attribute(attrs, "min", J.Null{}), S.literal_attribute(attrs, "max", J.Null{}), S.literal_attribute(attrs, "step", J.Number{"0.01"}), J.Null{}, 4096n)
    case "boolean": build(T.BooleanState{}, S.literal_attribute(attrs, "initial", J.Null{}), J.Null{}, J.Null{}, J.Null{}, J.Null{}, 4096n)
    case "string": build(T.StringState{}, S.literal_attribute(attrs, "initial", J.Null{}), J.Null{}, J.Null{}, J.Null{}, J.Null{}, length_value(S.literal_attribute(attrs, "max-length", J.nat(4096n))))
    case "enum": build(T.EnumState{}, S.literal_attribute(attrs, "initial", J.Null{}), J.Null{}, J.Null{}, J.Null{}, S.literal_attribute(attrs, "options", J.Null{}), 4096n)
    case _: Fail{"Unknown state type"}

def length_checked(+result: Result<&2, &2, String, T.StateSchema>, +valid: Bool) -> Result<&2, &2, String, T.StateSchema>:
  match valid:
    case True{}: result
    case False{}: Fail{"max-length must be a nonnegative integer at most 16384"}
def length_natural(+value: Maybe<&2, Nat>) -> Bool:
  match value:
    case Some{length}: Nat.is_le(length, 16384n)
    case None{}: False{}

def length_valid(+value: J.Json) -> Bool:
  match value:
    case J.Number{text}: length_natural(Nat.read(text))
    case _: False{}

def from_attributes(+attrs: +List<T.Attribute>) -> Result<&2, &2, String, T.StateSchema>:
  length_checked(kind_schema(J.text(S.literal_attribute(attrs, "type", J.Null{})), attrs), length_valid(S.literal_attribute(attrs, "max-length", J.nat(4096n))))

def raw_result(+result: Result<&2, &2, String, String>) -> Result<&2, &2, String, J.Json>:
  match result:
    case Done{text}: Done{J.Number{text}}
    case Fail{reason}: Fail{reason}

def boolean_raw(+raw: String) -> Result<&2, &2, String, J.Json>:
  match raw:
    case "true": Done{J.Boolean{True{}}}
    case "false": Done{J.Boolean{False{}}}
    case _: Fail{"A checkbox value must be true or false"}

def raw_value(+kind: T.StateKind, +raw: String) -> Result<&2, &2, String, J.Json>:
  match kind:
    case T.IntegerState{}: raw_result(D.parse(raw))
    case T.NumberState{}: raw_result(D.parse(raw))
    case T.BooleanState{}: boolean_raw(raw)
    case T.StringState{}: Done{J.Text{raw}}
    case T.EnumState{}: Done{J.Text{raw}}

def validated_value(+value: J.Json, +valid: Bool) -> Result<&2, &2, String, J.Json>:
  match valid:
    case True{}: Done{value}
    case False{}: Fail{"The input is outside its declared type, range or step grid"}

def validated_raw(+schema: T.StateSchema, +value: Result<&2, &2, String, J.Json>) -> Result<&2, &2, String, J.Json>:
  match value:
    case Fail{reason}: Fail{reason}
    case Done{+value}: validated_value(value, S.schema_accepts(schema, value))

def parse_raw(+schema: T.StateSchema, +raw: String) -> Result<&2, &2, String, J.Json>:
  T.StateSchema{ +kind, +initial, +minimum, +maximum, +step, +options, +max_length} = schema
  validated_raw(T.StateSchema{kind, initial, minimum, maximum, step, options, max_length}, raw_value(kind, raw))
