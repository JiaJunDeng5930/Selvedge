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

type FormatValidName is Data:
  FormatValidNamePortable{}
  FormatValidNameNative{}
  FormatValidNameOther{}

def format_valid_discriminant(+value: String) -> FormatValidName:
  Bool.pick(FormatValidName, String.eq(value, "portable"), FormatValidNamePortable{},
    Bool.pick(FormatValidName, String.eq(value, "native"), FormatValidNameNative{},
    FormatValidNameOther{}))

def format_valid_classified(format: FormatValidName, scope: String) -> Bool:
  match format:
    case FormatValidNamePortable{}: True{}
    case FormatValidNameNative{}: Bool.not(String.eq(scope, ""))
    case FormatValidNameOther{}: False{}

def format_valid(format: String, scope: String) -> Bool:
  format_valid_classified(format_valid_discriminant(format), scope)

type PortableItemKindName is Data:
  PortableItemKindNameUser{}
  PortableItemKindNameOther{}

def portable_item_kind_discriminant(+value: String) -> PortableItemKindName:
  Bool.pick(PortableItemKindName, String.eq(value, "user"), PortableItemKindNameUser{},
    Bool.pick(PortableItemKindName, String.eq(value, "assistant"), PortableItemKindNameUser{},
    PortableItemKindNameOther{}))

def portable_item_kind_classified(kind: PortableItemKindName, value: J.Json) -> Bool:
  match kind:
    case PortableItemKindNameUser{}: J.is_text(J.get(value, "content"))
    case PortableItemKindNameOther{}: False{}

def portable_item_kind(kind: String, value: J.Json) -> Bool:
  portable_item_kind_classified(portable_item_kind_discriminant(kind), value)

def portable_items(items: +List<J.Json>) -> Bool:
  match items:
    case Nil{}: True{}
    case Con{+item, rest}: portable_item_kind(J.text(J.get(item, "role")), item) && portable_items(rest)

type RepresentationValidName is Data:
  RepresentationValidNamePortable{}
  RepresentationValidNameNative{}
  RepresentationValidNameOther{}

def representation_valid_discriminant(+value: String) -> RepresentationValidName:
  Bool.pick(RepresentationValidName, String.eq(value, "portable"), RepresentationValidNamePortable{},
    Bool.pick(RepresentationValidName, String.eq(value, "native"), RepresentationValidNameNative{},
    RepresentationValidNameOther{}))

def representation_valid_classified(format: RepresentationValidName, items: +List<J.Json>) -> Bool:
  match format:
    case RepresentationValidNamePortable{}: portable_items(items)
    case RepresentationValidNameNative{}: True{}
    case RepresentationValidNameOther{}: False{}

def representation_valid(format: String, items: +List<J.Json>) -> Bool:
  representation_valid_classified(representation_valid_discriminant(format), items)

def artifact_valid(+value: J.Json) -> Bool:
  J.is_object(value) && format_valid(J.text(J.get(value, "format")), J.text(J.get(value, "scope"))) &&
    is_array(J.get(value, "items")) && nonempty(J.items(J.get(value, "items"))) &&
    representation_valid(J.text(J.get(value, "format")), J.items(J.get(value, "items")))

type ConsumesName is Data:
  ConsumesNamePortable{}
  ConsumesNameNative{}
  ConsumesNameOther{}

def consumes_discriminant(+value: String) -> ConsumesName:
  Bool.pick(ConsumesName, String.eq(value, "portable"), ConsumesNamePortable{},
    Bool.pick(ConsumesName, String.eq(value, "native"), ConsumesNameNative{},
    ConsumesNameOther{}))

def consumes_classified(format: ConsumesName, +producer_scope: String, target_scope: String) -> Bool:
  match format:
    case ConsumesNamePortable{}: True{}
    case ConsumesNameNative{}: Bool.not(String.eq(producer_scope, "")) && String.eq(producer_scope, target_scope)
    case ConsumesNameOther{}: False{}

def consumes(format: String, +producer_scope: String, target_scope: String) -> Bool:
  consumes_classified(consumes_discriminant(format), producer_scope, target_scope)

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

type EventKindName is Data:
  EventKindNameContextReplacement{}
  EventKindNameOther{}

def event_kind_discriminant(+value: String) -> EventKindName:
  Bool.pick(EventKindName, String.eq(value, "context_replacement"), EventKindNameContextReplacement{},
    EventKindNameOther{})

def event_kind_classified(kind: EventKindName, +message: J.Json, +position: Nat, +scope: String, previous: Selection) -> Selection:
  match kind:
    case EventKindNameContextReplacement{}: selected(compatible(J.get(message, "content"), scope) &&
      source_valid(J.get(message, "content"), position), J.get(message, "content"), previous)
    case EventKindNameOther{}: previous

def event_kind(kind: String, +message: J.Json, +position: Nat, +scope: String, previous: Selection) -> Selection:
  event_kind_classified(event_kind_discriminant(kind), message, position, scope, previous)

def required_event(+message: J.Json, +position: Nat, +scope: String, previous: Selection) -> Selection:
  event_kind(J.text(J.get(message, "role")), message, position, scope, previous)

# Compression may summarize text; image references remain actual model inputs.
def image_part(part: J.Json) -> Bool:
  String.eq(J.text(J.get(part, "type")), "image")

def image_parts(parts: +List<J.Json>) -> +List<J.Json>:
  List.filter(~J.Json, image_part, parts)

def message_image_parts(content: J.Json) -> +List<J.Json>:
  match content:
    case J.Array{parts}: image_parts(parts)
    case other: image_parts(J.items(J.get(other, "content")))

def retained_images(parts: +List<J.Json>, rest: +List<J.Json>) -> +List<J.Json>:
  match parts:
    case Nil{}: rest
    case Con{first, parts}: J.Object{[J.Field{"role", J.Text{"user"}}, J.Field{"content", J.Array{first <> parts}}]} <> rest
