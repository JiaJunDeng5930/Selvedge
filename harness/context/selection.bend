import Base
import ../DOMAIN.bend as D
import ../../bendlib/json.bend as J

type Selection is Data:
  Original{}
  Replacement{source_length: Nat, items: +List<J.Json>}

def is_array(value: J.Json) -> Bool:
  match value:
    case J.Array{items}: True{}
    case _: False{}

def nonempty(items: +List<J.Json>) -> Bool:
  match items:
    case Nil{}: False{}
    case Con{item, rest}: True{}

def format_valid(format: String, scope: String) -> Bool:
  match format:
    case "portable": True{}
    case "native": Bool.not(String.eq(scope, ""))
    case _: False{}

def portable_item_kind(kind: String, value: J.Json) -> Bool:
  match kind:
    case "user": J.is_text(J.get(value, "content"))
    case "assistant": J.is_text(J.get(value, "content"))
    case _: False{}

def portable_items(items: +List<J.Json>) -> Bool:
  match items:
    case Nil{}: True{}
    case Con{+item, rest}: portable_item_kind(J.text(J.get(item, "role")), item) && portable_items(rest)

def representation_valid(format: String, items: +List<J.Json>) -> Bool:
  match format:
    case "portable": portable_items(items)
    case "native": True{}
    case _: False{}

def artifact_valid(+value: J.Json) -> Bool:
  J.is_object(value) && format_valid(J.text(J.get(value, "format")), J.text(J.get(value, "scope"))) &&
    is_array(J.get(value, "items")) && nonempty(J.items(J.get(value, "items"))) &&
    representation_valid(J.text(J.get(value, "format")), J.items(J.get(value, "items")))

def consumes(format: String, +producer_scope: String, target_scope: String) -> Bool:
  match format:
    case "portable": True{}
    case "native": Bool.not(String.eq(producer_scope, "")) && String.eq(producer_scope, target_scope)
    case _: False{}

def compatible(+value: J.Json, scope: String) -> Bool:
  artifact_valid(value) && consumes(J.text(J.get(value, "format")), J.text(J.get(value, "scope")), scope)

def source_length(value: J.Json) -> Nat:
  J.natural_or(J.natural(J.get(value, "source_length")), 0n)

def source_checked(source: Maybe<&2, Nat>, current_length: Nat) -> Bool:
  match source:
    case None{}: False{}
    case Some{source}: Nat.is_le(source, current_length)

def source_valid(value: J.Json, current_length: Nat) -> Bool:
  source_checked(J.natural(J.get(value, "source_length")), current_length)

# Returned data cannot choose the source boundary. The pending operation owns it.
def record(+source_length: Nat, +artifact: J.Json) -> D.Message:
  D.ContextReplacement{J.Object{[
    J.Field{"source_length", J.nat(source_length)},
    J.Field{"format", J.get(artifact, "format")},
    J.Field{"scope", J.get(artifact, "scope")},
    J.Field{"items", J.get(artifact, "items")},
    J.Field{"usage", J.get(artifact, "usage")}]}}

def selected(usable: Bool, +value: J.Json, previous: Selection) -> Selection:
  match usable:
    case True{}: Replacement{source_length(value), J.items(J.get(value, "items"))}
    case False{}: previous

def event_kind(kind: String, +message: J.Json, +position: Nat, +scope: String, previous: Selection) -> Selection:
  match kind:
    case "context_replacement": selected(compatible(J.get(message, "content"), scope) &&
      source_valid(J.get(message, "content"), position), J.get(message, "content"), previous)
    case _: previous

def required_event(+message: J.Json, +position: Nat, +scope: String, previous: Selection) -> Selection:
  event_kind(J.text(J.get(message, "role")), message, position, scope, previous)
