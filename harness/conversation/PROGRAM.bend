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

def context_kind(kind: String) -> ContextKind:
  match kind:
    case "message": SpeechContext{}
    case "reasoning": ReasoningContext{}
    case "compaction": CompactionContext{}
    case _: OtherContext{}

# Titles are observations of the user's request, never browser-generated names
# or mutable task identities. Whitespace-only messages do not name a thread.
def request_title(text: String, fallback: String) -> String:
  match text:
    case "": fallback
    case title: String.take(title, 96n)

def first_request(messages: +List<D.Message>, fallback: String) -> String:
  match messages:
    case Nil{}: fallback
    case Con{D.UserMessage{text}, rest}: request_title(String.trim(text), first_request(rest, fallback))
    case Con{other, rest}: first_request(rest, fallback)

def title(+task: D.Task) -> String:
  first_request(D.history_messages(D.task_history(task), Nil{}), "Task #" ++ Nat.show(D.task_id(task)))

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
def content_part(kind: String, value: J.Json) -> String:
  match kind:
    case "output_text": J.text(J.get(value, "text"))
    case "summary_text": J.text(J.get(value, "text"))
    case "refusal": J.text(J.get(value, "refusal"))
    case _: ""

def content_parts(parts: +List<J.Json>) -> String:
  match parts:
    case Nil{}: ""
    case Con{+part, rest}: content_part(J.text(J.get(part, "type")), part) ++ content_parts(rest)
