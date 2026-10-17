import Base
import ../../bendlib/json.bend as J

def object(properties: +List<J.Field>, required: +List<J.Json>) -> J.Json:
  J.Object{[J.Field{"type", J.Text{"object"}}, J.Field{"properties", J.Object{properties}},
    J.Field{"required", J.Array{required}}, J.Field{"additionalProperties", J.Boolean{False{}}}]}

def retained_field(remove: Bool, field: J.Field, rest: +List<J.Field>) -> +List<J.Field>:
  match remove:
    case True{}: rest
    case False{}: field <> rest

def without_field(fields: +List<J.Field>, +name: String) -> +List<J.Field>:
  match fields:
    case Nil{}: Nil{}
    case Con{J.Field{+key, value}, rest}:
      retained_field(String.eq(key, name), J.Field{key, value}, without_field(rest, name))

def retained_required(remove: Bool, value: J.Json, rest: +List<J.Json>) -> +List<J.Json>:
  match remove:
    case True{}: rest
    case False{}: value <> rest

def without_required(values: +List<J.Json>, +name: String) -> +List<J.Json>:
  match values:
    case Nil{}: Nil{}
    case Con{J.Text{+key}, rest}:
      retained_required(String.eq(key, name), J.Text{key}, without_required(rest, name))
    case Con{value, rest}: value <> without_required(rest, name)

# A frozen feature declaration owns its command name; callers bind only its
# ordinary parameters, and cannot replace that name through their arguments.
def command_arguments_fields(properties: J.Json, required: +List<J.Json>, fallback: J.Json) -> J.Json:
  match properties:
    case J.Object{properties}:
      object(without_field(properties, "op"), without_required(required, "op"))
    case _: fallback

def command_arguments(+schema: J.Json) -> J.Json:
  command_arguments_fields(J.get(schema, "properties"), J.items(J.get(schema, "required")), schema)

def command_body(operation: String, arguments: J.Json) -> J.Json:
  match arguments:
    case J.Object{fields}: J.Object{J.Field{"op", J.Text{operation}} <> without_field(fields, "op")}
    case _: arguments

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

def number(value: J.Json) -> Maybe<&2, U32>:
  match value:
    case J.Number{lexeme}: U32.read(lexeme)
    case _: None{}

def number_or(value: Maybe<&2, U32>, fallback: U32) -> U32:
  match value:
    case None{}: fallback
    case Some{n}: n

def natural_bounds(value: Maybe<&2, U32>, lower: Maybe<&2, U32>, upper: Maybe<&2, U32>) -> Bool:
  match value:
    case None{}: False{}
    case Some{+n}:
      U32.is_le(number_or(lower, 0), n) && U32.is_le(n, number_or(upper, 4294967295))

def allowed_type(+schema: J.Json, expected: String) -> Bool:
  String.eq(J.text(J.get(schema, "type")), expected)

def property_exists(value: J.Json) -> Bool:
  match value:
    case J.Object{fields}: True{}
    case _: False{}

def contains(strings: +List<String>, +value: String) -> Bool:
  match strings:
    case Nil{}: False{}
    case Con{item, rest}: String.eq(item, value) || contains(rest, value)

def string_enum_values(fuel: Nat, values: +List<J.Json>, +seen: +List<String>) -> Bool:
  match fuel values:
    case 0n _: False{}
    case 1n+p Nil{}: True{}
    case 1n+p Con{J.Text{+text}, rest}:
      Bool.not(contains(seen, text)) && string_enum_values(p, rest, text <> seen)
    case 1n+p _: False{}

def string_enum_shape(value: J.Json) -> Bool:
  match value:
    case J.Array{Con{first, rest}}: string_enum_values(256n, first <> rest, Nil{})
    case _: False{}

def string_enum_definition(schema: J.Json) -> Bool:
  match schema:
    case J.Object{+fields}:
      Bool.not(exists(fields, "enum")) || string_enum_shape(J.get(J.Object{fields}, "enum"))
    case _: False{}

def string_enum_member(fuel: Nat, values: +List<J.Json>, +text: String) -> Bool:
  match fuel values:
    case 0n _: False{}
    case 1n+p Nil{}: False{}
    case 1n+p Con{J.Text{item}, rest}:
      String.eq(item, text) || string_enum_member(p, rest, text)
    case 1n+p _: False{}

def string_enum_accepts(+value: J.Json, text: String) -> Bool:
  string_enum_shape(value) && string_enum_member(256n, J.items(value), text)

def string_enum_allowed(schema: J.Json, text: String) -> Bool:
  match schema:
    case J.Object{+fields}:
      Bool.not(exists(fields, "enum")) || string_enum_accepts(J.get(J.Object{fields}, "enum"), text)
    case _: False{}

type Check is Data:
  CheckValue{schema: J.Json, value: J.Json}
  CheckElements{schema: J.Json, values: +List<J.Json>}
  CheckFields{properties: J.Json, values: +List<J.Field>}

def check(fuel: Nat, job: Check) -> Bool:
  match fuel job:
    case 0n _: False{}
    case 1n+p CheckValue{+schema, J.Text{text}}:
      allowed_type(schema, "string") && string_enum_allowed(schema, text)
    case 1n+p CheckValue{+schema, J.Number{lexeme}}:
      allowed_type(schema, "integer") && natural_bounds(U32.read(lexeme),
        number(J.get(schema, "minimum")), number(J.get(schema, "maximum")))
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

# Extension schemas use exactly the native decidable fragment. Unsupported
# JSON Schema keywords are rejected at registration, never silently ignored.

def keywords(fields: +List<J.Field>, +allowed: +List<String>, +seen: +List<String>) -> Bool:
  match fields:
    case Nil{}: True{}
    case Con{J.Field{+name, value}, rest}:
      contains(allowed, name) && Bool.not(contains(seen, name)) && keywords(rest, allowed, name <> seen)

def keys(value: J.Json, allowed: +List<String>) -> Bool:
  match value:
    case J.Object{fields}: keywords(fields, allowed, Nil{})
    case _: False{}

def optional_text(value: J.Json) -> Bool:
  match value:
    case J.Null{}: True{}
    case J.Text{text}: True{}
    case _: False{}

def closed(value: J.Json) -> Bool:
  match value:
    case J.Null{}: True{}
    case J.Boolean{False{}}: True{}
    case _: False{}

def bounded_natural(value: Maybe<&2, U32>) -> Bool:
  match value:
    case None{}: False{}
    case Some{n}: True{}

def bound(value: J.Json) -> Bool:
  match value:
    case J.Null{}: True{}
    case J.Number{lexeme}: bounded_natural(number(J.Number{lexeme}))
    case _: False{}

def required_names(names: +List<J.Json>, +properties: +List<J.Field>, +seen: +List<String>) -> Bool:
  match names:
    case Nil{}: True{}
    case Con{J.Text{+name}, rest}:
      exists(properties, name) && Bool.not(contains(seen, name)) && required_names(rest, properties, name <> seen)
    case _: False{}

def required_shape(value: J.Json, fields: +List<J.Field>) -> Bool:
  match value:
    case J.Null{}: True{}
    case J.Array{names}: required_names(names, fields, Nil{})
    case _: False{}

def property_requirements(properties: J.Json, required: J.Json) -> Bool:
  match properties:
    case J.Object{fields}: required_shape(required, fields)
    case _: False{}

type Definition is Data:
  SchemaDefinition{value: J.Json}
  PropertiesDefinition{value: J.Json, seen: +List<String>}

def definition_jobs(kind: String, +value: J.Json, rest: +List<Definition>) -> Maybe<&2, +List<Definition>>:
  match kind:
    case "object": Some{PropertiesDefinition{J.get(value, "properties"), Nil{}} <> rest}
    case "array": Some{SchemaDefinition{J.get(value, "items")} <> rest}
    case "string": Some{rest}
    case "integer": Some{rest}
    case "boolean": Some{rest}
    case "null": Some{rest}
    case _: None{}

def definition_shape(kind: String, +value: J.Json) -> Bool:
  match kind:
    case "object": keys(value, ["type", "description", "title", "properties", "required", "additionalProperties"]) &&
      closed(J.get(value, "additionalProperties")) && property_requirements(J.get(value, "properties"), J.get(value, "required"))
    case "array": keys(value, ["type", "description", "title", "items"]) && J.is_object(J.get(value, "items"))
    case "string": keys(value, ["type", "description", "title", "enum"]) && string_enum_definition(value)
    case "integer": keys(value, ["type", "description", "title", "minimum", "maximum"]) &&
      bound(J.get(value, "minimum")) && bound(J.get(value, "maximum")) &&
      U32.is_le(number_or(number(J.get(value, "minimum")), 0), number_or(number(J.get(value, "maximum")), 4294967295))
    case _: keys(value, ["type", "description", "title"])

def definition(fuel: Nat, jobs: Maybe<&2, +List<Definition>>) -> Bool:
  match fuel jobs:
    case 0n _: False{}
    case 1n+p None{}: False{}
    case 1n+p Some{Nil{}}: True{}
    case 1n+p Some{Con{SchemaDefinition{+value}, rest}}:
      optional_text(J.get(value, "title")) && optional_text(J.get(value, "description")) &&
        definition_shape(J.text(J.get(value, "type")), value) &&
        definition(p, definition_jobs(J.text(J.get(value, "type")), value, rest))
    case 1n+p Some{Con{PropertiesDefinition{J.Object{Nil{}}, seen}, rest}}: definition(p, Some{rest})
    case 1n+p Some{Con{PropertiesDefinition{J.Object{Con{J.Field{+name, value}, fields}}, +seen}, rest}}:
      Bool.not(contains(seen, name)) && definition(p,
        Some{SchemaDefinition{value} <> PropertiesDefinition{J.Object{fields}, name <> seen} <> rest})
    case 1n+p Some{Con{PropertiesDefinition{value, seen}, rest}}: False{}

def supported(schema: J.Json) -> Bool:
  definition(256n, Some{[SchemaDefinition{schema}]})

def command_supported(+schema: J.Json) -> Bool:
  supported(schema) && allowed_type(schema, "object") &&
    allowed_type(J.get(J.get(schema, "properties"), "op"), "string") &&
    contains(J.text_values(J.items(J.get(schema, "required"))), "op")
