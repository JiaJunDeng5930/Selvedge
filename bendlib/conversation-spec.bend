import Base
import ../MODEL.bend as M
import ./domain.bend as D
import ./conversation.bend as Content
import ./surface.bend as Surface
import ./json.bend as J
import ./tasks.bend as T

# Independent observations of the committed history and of the presentation.
# The observation deliberately excludes layout, headings, animation and timing.
# It includes verbatim speech, result value/error and original audit payloads.
type Speech is Data:
  Speech{speaker: String, text: String}

def assistant(yes: Bool, value: J.Json) -> +List<Speech>:
  match yes:
    case True{}: [Speech{"assistant", Content.content_parts(J.items(J.get(value, "content")))}]
    case False{}: Nil{}

def provider_speech(kind: Content.ContextKind, +value: J.Json) -> +List<Speech>:
  match kind:
    case Content.SpeechContext{}: assistant(String.eq(J.text(J.get(value, "role")), "assistant"), value)
    case Content.ReasoningContext{}: Nil{}
    case Content.CompactionContext{}: Nil{}
    case Content.OtherContext{}: Nil{}

def speech(message: D.Message) -> +List<Speech>:
  match message:
    case D.UserMessage{text}: [Speech{"user", text}]
    case D.AssistantMessage{text}: [Speech{"assistant", text}]
    case D.FailureMessage{text}: [Speech{"error", text}]
    case D.ModelContext{+value}: provider_speech(Content.context_kind(J.text(J.get(value, "type"))), value)
    case _: Nil{}

def transcript(messages: +List<D.Message>) -> +List<Speech>:
  match messages:
    case Nil{}: Nil{}
    case Con{message, rest}: List.append(&2, Speech, speech(message), transcript(rest))

def text_speech(role: String, text: String) -> +List<Speech>:
  match role:
    case "user": [Speech{"user", text}]
    case "assistant": [Speech{"assistant", text}]
    case "error": [Speech{"error", text}]
    case _: Nil{}

def visible_speech(nodes: +List<Surface.Node>) -> +List<Speech>:
  match nodes:
    case Nil{}: Nil{}
    case Con{Surface.Text{key, role, title, text}, rest}:
      List.append(&2, Speech, text_speech(role, text), visible_speech(rest))
    case Con{other, rest}: visible_speech(rest)

def audit_record(message: D.Message) -> +List<J.Json>:
  match message:
    case D.HookRecord{owner, call_id, plugin, outcome}: [T.message_json(D.HookRecord{owner, call_id, plugin, outcome})]
    case D.ToolReceipt{owner, operation, call, value, error}: [T.message_json(D.ToolReceipt{owner, operation, call, value, error})]
    case D.AfterRecord{owner, operation, plugin, outcome}: [T.message_json(D.AfterRecord{owner, operation, plugin, outcome})]
    case D.ApprovalRecord{owner, operation, call, reviewer, outcome}: [T.message_json(D.ApprovalRecord{owner, operation, call, reviewer, outcome})]
    case _: Nil{}

def audit_values(nodes: +List<Surface.Node>) -> +List<J.Json>:
  match nodes:
    case Nil{}: Nil{}
    case Con{Surface.Value{key, title, value}, rest}: value <> audit_values(rest)
    case Con{other, rest}: audit_values(rest)

type Result is Data:
  Result{value: J.Json, error: Bool}

def result(message: D.Message) -> +List<Result>:
  match message:
    case D.FunctionOutput{id, value, error}: [Result{value, error}]
    case D.OperationResult{ticket, id, tool, value, error}: [Result{value, error}]
    case _: Nil{}

def output(children: +List<Surface.Node>, error: Bool) -> +List<Result>:
  match children:
    case Con{Surface.Text{"output", "tool-output", title, text}, rest}: [Result{J.Text{text}, error}]
    case Con{Surface.Value{"output", title, value}, rest}: [Result{value, error}]
    case _: Nil{}

def activity_result(state: Surface.ActivityState, children: +List<Surface.Node>) -> +List<Result>:
  match state:
    case Surface.Complete{}: output(children, False{})
    case Surface.Failed{}: output(children, True{})
    case _: Nil{}

def visible_results(nodes: +List<Surface.Node>) -> +List<Result>:
  match nodes:
    case Nil{}: Nil{}
    case Con{Surface.Activity{key, title, state, children}, rest}:
      List.append(&2, Result, activity_result(state, children), visible_results(rest))
    case Con{other, rest}: visible_results(rest)

type Intent is Data:
  Intent{command: M.Command, enabled: Bool}

type Composer is Data:
  Composer{draft_key: String, intents: +List<Intent>}

def intents(forms: +List<Surface.Node>) -> +List<Intent>:
  match forms:
    case Nil{}: Nil{}
    case Con{Surface.Form{key, title, label, command, fields, enabled}, rest}:
      Intent{command, enabled} <> intents(rest)
    case Con{other, rest}: intents(rest)

def composer(node: Surface.Node) -> Maybe<&2, Composer>:
  match node:
    case Surface.Composer{key, draft_key, title, hint, forms, actions}: Some{Composer{draft_key, intents(forms)}}
    case _: None{}
