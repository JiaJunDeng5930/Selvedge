import Base
import ./json.bend as J
import ./tasks.bend as T

# Shared, strict wire primitives. Protocol-specific schemas remain with owners.
def exact_keys(fields: +List<J.Field>, +allowed: +List<String>, +seen: +List<String>) -> Bool:
  match fields:
    case Nil{}: Nat.is_eq(List.length(&2, String, seen), List.length(&2, String, allowed))
    case Con{J.Field{+key, value}, rest}:
      T.has_name(allowed, key) && Bool.not(T.has_name(seen, key)) && exact_keys(rest, allowed, key <> seen)

def object_keys(value: J.Json, allowed: +List<String>) -> Bool:
  match value:
    case J.Object{fields}: exact_keys(fields, allowed, Nil{})
    case _: False{}

def is_some(value: Maybe<&2, Nat>) -> Bool:
  match value:
    case Some{n}: True{}
    case None{}: False{}

def is_natural(value: J.Json) -> Bool:
  match value:
    case J.Number{lexeme}: is_some(Nat.read(lexeme))
    case _: False{}

def is_bool(value: J.Json) -> Bool:
  match value:
    case J.Boolean{boolean}: True{}
    case _: False{}
