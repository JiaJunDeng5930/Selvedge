import Base
import ../../UI.bend as UI
import ../../LAWS.bend as Laws
import ../domain.bend as D
import ../surface.bend as Surface
import ../conversation.bend as Content
import ../conversation-spec.bend as Spec
import ../json.bend as J
import ../stdlib.bend as Std

def assistant_prefix(+yes: Bool, +value: J.Json, key: String, +tail: +List<Surface.Node>) ->
  {Spec.visible_speech(List.append(&2, Surface.Node, UI.assistant_context(yes, value, key), tail)) ==
    List.append(&2, Spec.Speech, Spec.assistant(yes, value), Spec.visible_speech(tail)) : +List<Spec.Speech>}:
  match yes:
    case True{}: {==}
    case False{}: {==}

def provider_prefix(+kind: Content.ContextKind, +value: J.Json, key: String, +tail: +List<Surface.Node>) ->
  {Spec.visible_speech(List.append(&2, Surface.Node, UI.provider_context(kind, value, key), tail)) ==
    List.append(&2, Spec.Speech, Spec.provider_speech(kind, value), Spec.visible_speech(tail)) : +List<Spec.Speech>}:
  match kind:
    case Content.SpeechContext{}: assistant_prefix(String.eq(J.text(J.get(value, "role")), "assistant"), value, key, tail)
    case Content.ReasoningContext{}: {==}
    case Content.CompactionContext{}: {==}
    case Content.OtherContext{}: {==}

# One committed message contributes exactly its spoken content before the
# untouched suffix. This is stronger than checking a fixed sample transcript.
def speech_prefix(+message: D.Message, key: String, +tail: +List<Surface.Node>) ->
  {Spec.visible_speech(List.append(&2, Surface.Node, UI.message_nodes(message, key), tail)) ==
    List.append(&2, Spec.Speech, Spec.speech(message), Spec.visible_speech(tail)) : +List<Spec.Speech>}:
  match message:
    case D.UserMessage{text}: {==}
    case D.AssistantMessage{text}: {==}
    case D.FunctionCall{call}: {==}
    case D.FunctionOutput{id, value, error}: {==}
    case D.OperationResult{ticket, id, tool, value, error}: {==}
    case D.FailureMessage{text}: {==}
    case D.ModelContext{+value}: provider_prefix(Content.context_kind(J.text(J.get(value, "type"))), value, key, tail)
    case D.ContextCheckpoint{text}: {==}
    case D.ReasoningRecord{owner, effort, remaining, True{}}: {==}
    case D.ReasoningRecord{owner, effort, remaining, False{}}: {==}
    case D.ConfigurationUpdate{effort}: {==}
    case D.HookRecord{owner, call_id, plugin, outcome}: {==}
    case D.ToolReceipt{owner, operation, call, value, error}: {==}
    case D.AfterRecord{owner, operation, plugin, outcome}: {==}
    case D.ApprovalRecord{owner, operation, call, reviewer, outcome}: {==}
    case D.ForkResult{owner, call_id, branch}: {==}

def TranscriptContent(messages: +List<D.Message>) -> Type:
  @offset:Nat -> {Spec.visible_speech(UI.messages(messages, offset)) == Spec.transcript(messages) : +List<Spec.Speech>}

def empty_transcript(offset: Nat) -> {Spec.visible_speech(UI.messages(Nil{}, offset)) == Spec.transcript(Nil{}) : +List<Spec.Speech>}:
  {==}

def transcript_cons(+message: D.Message, +rest: +List<D.Message>, evidence: TranscriptContent(rest), +offset: Nat) ->
  {Spec.visible_speech(UI.messages(message <> rest, offset)) == Spec.transcript(message <> rest) : +List<Spec.Speech>}:
  first = speech_prefix(message, "message/" ++ Nat.show(offset), UI.messages(rest, 1n+offset))
  second = Equal.cong(+List<Spec.Speech>, +List<Spec.Speech>,
    (tail => List.append(&2, Spec.Speech, Spec.speech(message), tail)),
    Spec.visible_speech(UI.messages(rest, 1n+offset)), Spec.transcript(rest), evidence(1n+offset))
  Equal.trans(+List<Spec.Speech>, Spec.visible_speech(UI.messages(message <> rest, offset)),
    List.append(&2, Spec.Speech, Spec.speech(message), Spec.visible_speech(UI.messages(rest, 1n+offset))),
    Spec.transcript(message <> rest), first, second)

def Laws.ui_transcript_content(messages, offset):
  Std.list_ind(~D.Message, ~TranscriptContent, ~empty_transcript,
    ~(message => rest => evidence => offset => transcript_cons(message, rest, evidence, offset)), messages)(offset)

def Laws.ui_audit_content(message, key):
  match message:
    case D.UserMessage{text}: {==}
    case D.AssistantMessage{text}: {==}
    case D.FunctionCall{call}: {==}
    case D.FunctionOutput{id, value, error}: {==}
    case D.OperationResult{ticket, id, tool, value, error}: {==}
    case D.FailureMessage{text}: {==}
    case D.ModelContext{value}: {==}
    case D.ContextCheckpoint{text}: {==}
    case D.ReasoningRecord{owner, effort, remaining, sampling}: {==}
    case D.ConfigurationUpdate{effort}: {==}
    case D.HookRecord{owner, call_id, plugin, outcome}: {==}
    case D.ToolReceipt{owner, operation, call, value, error}: {==}
    case D.AfterRecord{owner, operation, plugin, outcome}: {==}
    case D.ApprovalRecord{owner, operation, call, reviewer, outcome}: {==}
    case D.ForkResult{owner, call_id, branch}: {==}

def output_value(+value: J.Json, +error: Bool) ->
  {Spec.output([UI.output_node(value)], error) == [Spec.Result{value, error}] : +List<Spec.Result>}:
  match value:
    case J.Null{}: {==}
    case J.Boolean{value}: {==}
    case J.Number{value}: {==}
    case J.Text{value}: {==}
    case J.Array{items}: {==}
    case J.Object{fields}: {==}

def result_value(key: String, title: String, +value: J.Json, +error: Bool) ->
  {Spec.visible_results([UI.result_node(key, title, value, error)]) == [Spec.Result{value, error}] : +List<Spec.Result>}:
  match error:
    case True{}:
      first = Std.app_nil_r(Spec.Result, Spec.output([UI.output_node(value)], True{}))
      Equal.trans(+List<Spec.Result>, Spec.visible_results([UI.result_node(key, title, value, True{})]),
        Spec.output([UI.output_node(value)], True{}), [Spec.Result{value, True{}}], first, output_value(value, True{}))
    case False{}:
      first = Std.app_nil_r(Spec.Result, Spec.output([UI.output_node(value)], False{}))
      Equal.trans(+List<Spec.Result>, Spec.visible_results([UI.result_node(key, title, value, False{})]),
        Spec.output([UI.output_node(value)], False{}), [Spec.Result{value, False{}}], first, output_value(value, False{}))

def assistant_results(+yes: Bool, value: J.Json, key: String) ->
  {Spec.visible_results(UI.assistant_context(yes, value, key)) == Nil{} : +List<Spec.Result>}:
  match yes:
    case True{}: {==}
    case False{}: {==}

def provider_results(+kind: Content.ContextKind, +value: J.Json, key: String) ->
  {Spec.visible_results(UI.provider_context(kind, value, key)) == Nil{} : +List<Spec.Result>}:
  match kind:
    case Content.SpeechContext{}: assistant_results(String.eq(J.text(J.get(value, "role")), "assistant"), value, key)
    case Content.ReasoningContext{}: {==}
    case Content.CompactionContext{}: {==}
    case Content.OtherContext{}: {==}

def Laws.ui_result_content(message, key):
  match message:
    case D.UserMessage{text}: {==}
    case D.AssistantMessage{text}: {==}
    case D.FunctionCall{call}: {==}
    case D.FunctionOutput{id, value, error}: result_value(key, "Tool result · " ++ id, value, error)
    case D.OperationResult{ticket, id, tool, value, error}: result_value(key, tool ++ " · " ++ Nat.show(ticket), value, error)
    case D.FailureMessage{text}: {==}
    case D.ModelContext{+value}: provider_results(Content.context_kind(J.text(J.get(value, "type"))), value, key)
    case D.ContextCheckpoint{text}: {==}
    case D.ReasoningRecord{owner, effort, remaining, True{}}: {==}
    case D.ReasoningRecord{owner, effort, remaining, False{}}: {==}
    case D.ConfigurationUpdate{effort}: {==}
    case D.HookRecord{owner, call_id, plugin, outcome}: {==}
    case D.ToolReceipt{owner, operation, call, value, error}: {==}
    case D.AfterRecord{owner, operation, plugin, outcome}: {==}
    case D.ApprovalRecord{owner, operation, call, reviewer, outcome}: {==}
    case D.ForkResult{owner, call_id, branch}: {==}

def Laws.ui_composer_intents(id, world):
  {==}
