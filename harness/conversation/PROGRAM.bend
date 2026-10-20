import Base
import ../DOMAIN.bend as D
import ../../bendlib/json.bend as J

# Provider wire strings are decoded once. The view and its independent
# observation consume the same vocabulary, not separate string decision trees.
type ContextKind is Data:
  SpeechContext{}
  ReasoningContext{}
  CompactionContext{}
  OtherContext{}

type ContextKindName is Data:
  ContextKindNameMessage{}
  ContextKindNameReasoning{}
  ContextKindNameCompaction{}
  ContextKindNameOther{}

def context_kind_discriminant(+value: String) -> ContextKindName:
  Bool.pick(ContextKindName, String.eq(value, "message"), ContextKindNameMessage{},
    Bool.pick(ContextKindName, String.eq(value, "reasoning"), ContextKindNameReasoning{},
    Bool.pick(ContextKindName, String.eq(value, "compaction"), ContextKindNameCompaction{},
    ContextKindNameOther{})))

def context_kind_classified(kind: ContextKindName) -> ContextKind:
  match kind:
    case ContextKindNameMessage{}: SpeechContext{}
    case ContextKindNameReasoning{}: ReasoningContext{}
    case ContextKindNameCompaction{}: CompactionContext{}
    case ContextKindNameOther{}: OtherContext{}

def context_kind(kind: String) -> ContextKind:
  context_kind_classified(context_kind_discriminant(kind))

type ProviderValueKindName is Data:
  ProviderValueKindNameProviderReceipt{}
  ProviderValueKindNameOther{}

def provider_value_kind_discriminant(+value: String) -> ProviderValueKindName:
  Bool.pick(ProviderValueKindName, String.eq(value, "provider_receipt"), ProviderValueKindNameProviderReceipt{},
    ProviderValueKindNameOther{})

def provider_value_kind_classified(kind: ProviderValueKindName, +value: J.Json) -> J.Json:
  match kind:
    case ProviderValueKindNameProviderReceipt{}: J.get(value, "item")
    case ProviderValueKindNameOther{}: value

def provider_value_kind(kind: String, +value: J.Json) -> J.Json:
  provider_value_kind_classified(provider_value_kind_discriminant(kind), value)

def provider_value(+value: J.Json) -> J.Json:
  provider_value_kind(J.text(J.get(value, "type")), value)

def provider_kind(value: J.Json) -> ContextKind:
  context_kind(J.text(J.get(provider_value(value), "type")))

def provider_assistant(value: J.Json) -> Bool:
  String.eq(J.text(J.get(provider_value(value), "role")), "assistant")

# Request-derived fallback titles are shared by every title observer.

def request_title(text: String, fallback: Unit -> String) -> String:
  match text:
    case "": fallback(Unit{})
    case title: title

def first_request(messages: +List<D.Message>, fallback: String) -> String:
  match messages:
    case Nil{}: fallback
    case Con{D.UserMessage{text}, rest}: request_title(String.trim(D.content_text(text)), unused => first_request(rest, fallback))
    case Con{other, rest}: first_request(rest, fallback)

def title(+task: D.Task) -> String:
  String.take(first_request(D.history_messages(D.task_history(task), Nil{}), "Task #" ++ Nat.show(D.task_id(task))), 96n)

def working(phase: D.Phase, operations: +List<D.Operation()>) -> Bool:
  match phase:
    case D.Idle{}: Nat.is_lt(0n, List.length(&2, D.Operation(), operations))
    case _: True{}

def active_label(busy: Bool) -> String:
  match busy:
    case True{}: "Working"
    case False{}: "Ready"

def status_label(status: D.Status, busy: Bool) -> String:
  match status:
    case D.Active{}: active_label(busy)
    case D.Frozen{}: "Paused"
    case D.Stopped{}: "Stopped"
    case D.Archived{}: "Archived"

def status(+task: D.Task) -> String:
  status_label(D.task_status(task), working(D.task_phase(task), D.task_operations(task)))

# The provider's textual content is a shared decoding primitive. It does not
# decide placement, visibility of diagnostics, authorization, or execution.

type ContentPartName is Data:
  ContentPartNameOutputText{}
  ContentPartNameRefusal{}
  ContentPartNameOther{}

def content_part_discriminant(+value: String) -> ContentPartName:
  Bool.pick(ContentPartName, String.eq(value, "output_text"), ContentPartNameOutputText{},
    Bool.pick(ContentPartName, String.eq(value, "summary_text"), ContentPartNameOutputText{},
    Bool.pick(ContentPartName, String.eq(value, "refusal"), ContentPartNameRefusal{},
    ContentPartNameOther{})))

def content_part_classified(kind: ContentPartName, value: J.Json) -> String:
  match kind:
    case ContentPartNameOutputText{}: J.text(J.get(value, "text"))
    case ContentPartNameRefusal{}: J.text(J.get(value, "refusal"))
    case ContentPartNameOther{}: ""

def content_part(kind: String, value: J.Json) -> String:
  content_part_classified(content_part_discriminant(kind), value)

def content_parts(parts: +List<J.Json>) -> String:
  match parts:
    case Nil{}: ""
    case Con{+part, rest}: content_part(J.text(J.get(part, "type")), part) ++ content_parts(rest)

def provider_text(value: J.Json) -> String:
  content_parts(J.items(J.get(provider_value(value), "content")))

def public_parts_text(parts: +List<J.Json>) -> String:
  match parts:
    case Nil{}: ""
    case Con{part, Nil{}}: J.text(J.get(part, "text"))
    case Con{part, rest}: J.text(J.get(part, "text")) ++ "\n" ++ public_parts_text(rest)

def public_text(value: J.Json) -> String:
  match value:
    case J.Text{text}: text
    case J.Array{parts}: public_parts_text(parts)
    case _: ""
