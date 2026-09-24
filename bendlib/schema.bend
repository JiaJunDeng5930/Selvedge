import Base
import ./json.bend as J

# The schema fragment used by built-in commands and tools. MCP schemas are
# preserved verbatim and validated by their server, not misrepresented here.
def exists(fields: +List<J.Field>, +name: String) -> Bool:
  match fields:
    case Nil{}: False{}
    case Con{J.Field{key, value}, rest}: String.eq(key, name) || exists(rest, name)

def required(names: +List<J.Json>, +fields: +List<J.Field>) -> Bool:
  match names:
    case Nil{}: True{}
    case Con{J.Text{name}, rest}: exists(fields, name) && required(rest, fields)
    case Con{other, rest}: False{}

def natural_bounds(value: Maybe<&2, Nat>, lower: Maybe<&2, Nat>, upper: Maybe<&2, Nat>) -> Bool:
  match value:
    case None{}: False{}
    case Some{+n}:
      Nat.is_le(J.natural_or(lower, 0n), n) && Nat.is_le(n, J.natural_or(upper, U32.to_nat(4294967295)))

def allowed_type(+schema: J.Json, expected: String) -> Bool:
  String.eq(J.text(J.get(schema, "type")), expected)

def property_exists(value: J.Json) -> Bool:
  match value:
    case J.Object{fields}: True{}
    case _: False{}

type Check is Data:
  CheckValue{schema: J.Json, value: J.Json}
  CheckElements{schema: J.Json, values: +List<J.Json>}
  CheckFields{properties: J.Json, values: +List<J.Field>}

def check(fuel: Nat, job: Check) -> Bool:
  match fuel job:
    case 0n _: False{}
    case 1n+p CheckValue{schema, J.Text{text}}:
      allowed_type(schema, "string")
    case 1n+p CheckValue{+schema, J.Number{lexeme}}:
      allowed_type(schema, "integer") && natural_bounds(Nat.read(lexeme),
        J.natural(J.get(schema, "minimum")), J.natural(J.get(schema, "maximum")))
    case 1n+p CheckValue{schema, J.Boolean{value}}:
      allowed_type(schema, "boolean")
    case 1n+p CheckValue{schema, J.Null{}}:
      allowed_type(schema, "null")
    case 1n+p CheckValue{+schema, J.Array{values}}:
      allowed_type(schema, "array") && check(p, CheckElements{J.get(schema, "items"), values})
    case 1n+p CheckValue{+schema, J.Object{+fields}}:
      allowed_type(schema, "object") && required(J.items(J.get(schema, "required")), fields) &&
        check(p, CheckFields{J.get(schema, "properties"), fields})
    case 1n+p CheckElements{schema, Nil{}}:
      True{}
    case 1n+ +p CheckElements{+schema, Con{value, rest}}:
      check(p, CheckValue{schema, value}) && check(p, CheckElements{schema, rest})
    case 1n+p CheckFields{properties, Nil{}}:
      True{}
    case 1n+ +p CheckFields{+properties, Con{J.Field{+name, value}, rest}}:
      property_exists(J.get(properties, name)) && check(p, CheckValue{J.get(properties, name), value}) &&
        check(p, CheckFields{properties, rest})

def valid(schema: J.Json, value: J.Json) -> Bool:
  check(256n, CheckValue{schema, value})
