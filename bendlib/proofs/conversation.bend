import Base
import ../../MODEL.bend as M
import ../domain.bend as D
import ../json.bend as J
import ../conversation.bend as Content
import ../conversation-spec.bend as Spec
import ../../core/user-conversation.bend as Actual
import ../../core/user-experience.bend as E

def audit_prepend(+index: Nat, +failed: Bool, +message: D.Message, +tail: +List<Actual.Group>) ->
  {Spec.sources(Actual.prepend_audit(index, failed, message, tail)) == message <> Spec.sources(tail) : +List<D.Message>}:
  match tail:
    case Nil{}: {==}
    case Con{Actual.Speech{id, speaker, text, source}, rest}: {==}
    case Con{Actual.Activity{id, attention, entries}, rest}: {==}

def provider_speech(+assistant: Bool, +index: Nat, +value: J.Json, +tail: +List<Actual.Group>) ->
  {Spec.sources(Actual.provider_speech(assistant, index, value, tail)) == D.ModelContext{value} <> Spec.sources(tail) : +List<D.Message>}:
  match assistant:
    case True{}: {==}
    case False{}: audit_prepend(index, Actual.audit_failed(D.ModelContext{value}), D.ModelContext{value}, tail)

def provider_group(+kind: Content.ContextKind, +index: Nat, +value: J.Json, +tail: +List<Actual.Group>) ->
  {Spec.sources(Actual.provider_group(kind, index, value, tail)) == D.ModelContext{value} <> Spec.sources(tail) : +List<D.Message>}:
  match kind:
    case Content.SpeechContext{}: provider_speech(String.eq(J.text(J.get(value, "role")), "assistant"), index, value, tail)
    case Content.ReasoningContext{}: audit_prepend(index, Actual.audit_failed(D.ModelContext{value}), D.ModelContext{value}, tail)
    case Content.CompactionContext{}: audit_prepend(index, Actual.audit_failed(D.ModelContext{value}), D.ModelContext{value}, tail)
    case Content.OtherContext{}: audit_prepend(index, Actual.audit_failed(D.ModelContext{value}), D.ModelContext{value}, tail)

def prepend(+message: D.Message, +index: Nat, +tail: +List<Actual.Group>) ->
  {Spec.sources(Actual.prepend(message, index, tail)) == message <> Spec.sources(tail) : +List<D.Message>}:
  match message:
    case D.UserMessage{text}: {==}
    case D.AssistantMessage{text}: {==}
    case D.ModelContext{value}: provider_group(Content.context_kind(J.text(J.get(value, "type"))), index, value, tail)
    case D.FunctionCall{call}:
      +audit_message: D.Message = D.FunctionCall{call}
      audit_prepend(index, Actual.audit_failed(audit_message), audit_message, tail)
    case D.FunctionOutput{call_id, value, error}:
      +audit_message: D.Message = D.FunctionOutput{call_id, value, error}
      audit_prepend(index, Actual.audit_failed(audit_message), audit_message, tail)
    case D.OperationResult{ticket, call_id, tool, value, error}:
      +audit_message: D.Message = D.OperationResult{ticket, call_id, tool, value, error}
      audit_prepend(index, Actual.audit_failed(audit_message), audit_message, tail)
    case D.FailureMessage{text}:
      +audit_message: D.Message = D.FailureMessage{text}
      audit_prepend(index, Actual.audit_failed(audit_message), audit_message, tail)
    case D.ContextCheckpoint{summary}:
      +audit_message: D.Message = D.ContextCheckpoint{summary}
      audit_prepend(index, Actual.audit_failed(audit_message), audit_message, tail)
    case D.ReasoningRecord{owner, effort, remaining, sampling}:
      +audit_message: D.Message = D.ReasoningRecord{owner, effort, remaining, sampling}
      audit_prepend(index, Actual.audit_failed(audit_message), audit_message, tail)
    case D.ConfigurationUpdate{effort}:
      +audit_message: D.Message = D.ConfigurationUpdate{effort}
      audit_prepend(index, Actual.audit_failed(audit_message), audit_message, tail)
    case D.HookRecord{task_id, call_id, plugin, outcome}:
      +audit_message: D.Message = D.HookRecord{task_id, call_id, plugin, outcome}
      audit_prepend(index, Actual.audit_failed(audit_message), audit_message, tail)
    case D.ToolReceipt{task_id, operation_id, call, value, error}:
      +audit_message: D.Message = D.ToolReceipt{task_id, operation_id, call, value, error}
      audit_prepend(index, Actual.audit_failed(audit_message), audit_message, tail)
    case D.AfterRecord{task_id, operation_id, plugin, outcome}:
      +audit_message: D.Message = D.AfterRecord{task_id, operation_id, plugin, outcome}
      audit_prepend(index, Actual.audit_failed(audit_message), audit_message, tail)
    case D.ApprovalRecord{task_id, operation_id, call, reviewer, outcome}:
      +audit_message: D.Message = D.ApprovalRecord{task_id, operation_id, call, reviewer, outcome}
      audit_prepend(index, Actual.audit_failed(audit_message), audit_message, tail)
    case D.ForkResult{task_id, call_id, branch}:
      +audit_message: D.Message = D.ForkResult{task_id, call_id, branch}
      audit_prepend(index, Actual.audit_failed(audit_message), audit_message, tail)

def grouped_history(+messages: +List<D.Message>, +index: Nat) ->
  {Spec.sources(Actual.groups(messages, index)) == messages : +List<D.Message>}:
  match messages:
    case Nil{}: {==}
    case Con{+message, +rest}:
      Equal.trans(+List<D.Message>, Spec.sources(Actual.prepend(message, index, Actual.groups(rest, (index + 1n : Nat)))),
        message <> Spec.sources(Actual.groups(rest, (index + 1n : Nat))), message <> rest,
        prepend(message, index, Actual.groups(rest, (index + 1n : Nat))),
        Equal.cong(+List<D.Message>, +List<D.Message>, (tail => message <> tail), Spec.sources(Actual.groups(rest, (index + 1n : Nat))), rest, grouped_history(rest, (index + 1n : Nat))))

def audit_faces(+entries: +List<Actual.Audit>) ->
  {Spec.face_sources(Actual.audit_faces(entries)) == Spec.audit_sources(entries) : +List<D.Message>}:
  match entries:
    case Nil{}: {==}
    case Con{Actual.Audit{id, +source}, +rest}:
      Equal.cong(+List<D.Message>, +List<D.Message>, (tail => source <> tail), Spec.face_sources(Actual.audit_faces(rest)), Spec.audit_sources(rest), audit_faces(rest))

def visible_history(+groups: +List<Actual.Group>, +task: Nat, +disclosures: +List<E.Disclosure>) ->
  {Spec.visible_sources(Actual.visible(groups, task, disclosures)) == Spec.sources(groups) : +List<D.Message>}:
  match groups:
    case Nil{}: {==}
    case Con{Actual.Speech{id, speaker, text, +source}, +rest}:
      Equal.cong(+List<D.Message>, +List<D.Message>, (tail => source <> tail), Spec.visible_sources(Actual.visible(rest, task, disclosures)), Spec.sources(rest), visible_history(rest, task, disclosures))
    case Con{Actual.Activity{id, attention, +entries}, +rest}:
      Equal.trans(+List<D.Message>,
        List.append(&2, D.Message, Spec.face_sources(Actual.audit_faces(entries)), Spec.visible_sources(Actual.visible(rest, task, disclosures))),
        List.append(&2, D.Message, Spec.audit_sources(entries), Spec.visible_sources(Actual.visible(rest, task, disclosures))),
        List.append(&2, D.Message, Spec.audit_sources(entries), Spec.sources(rest)),
        Equal.cong(+List<D.Message>, +List<D.Message>, (head => List.append(&2, D.Message, head, Spec.visible_sources(Actual.visible(rest, task, disclosures)))), Spec.face_sources(Actual.audit_faces(entries)), Spec.audit_sources(entries), audit_faces(entries)),
        Equal.cong(+List<D.Message>, +List<D.Message>, (tail => List.append(&2, D.Message, Spec.audit_sources(entries), tail)), Spec.visible_sources(Actual.visible(rest, task, disclosures)), Spec.sources(rest), visible_history(rest, task, disclosures)))

def audit_text(+index: Nat, +failed: Bool, +message: D.Message, +tail: +List<Actual.Group>, evidence: Spec.text_agreement(tail)) ->
  Spec.text_agreement(Actual.prepend_audit(index, failed, message, tail)):
  match tail:
    case Nil{}: evidence
    case Con{Actual.Speech{id, speaker, text, source}, rest}: evidence
    case Con{Actual.Activity{id, attention, entries}, rest}: evidence

def provider_speech_text(+assistant: Bool, +index: Nat, +value: J.Json, +tail: +List<Actual.Group>, evidence: Spec.text_agreement(tail)) ->
  Spec.text_agreement(Actual.provider_speech(assistant, index, value, tail)):
  match assistant:
    case True{}: ({==}, evidence)
    case False{}: audit_text(index, Actual.audit_failed(D.ModelContext{value}), D.ModelContext{value}, tail, evidence)

def provider_group_text(+kind: Content.ContextKind, +index: Nat, +value: J.Json, +tail: +List<Actual.Group>, evidence: Spec.text_agreement(tail)) ->
  Spec.text_agreement(Actual.provider_group(kind, index, value, tail)):
  match kind:
    case Content.SpeechContext{}: provider_speech_text(String.eq(J.text(J.get(value, "role")), "assistant"), index, value, tail, evidence)
    case Content.ReasoningContext{}: audit_text(index, Actual.audit_failed(D.ModelContext{value}), D.ModelContext{value}, tail, evidence)
    case Content.CompactionContext{}: audit_text(index, Actual.audit_failed(D.ModelContext{value}), D.ModelContext{value}, tail, evidence)
    case Content.OtherContext{}: audit_text(index, Actual.audit_failed(D.ModelContext{value}), D.ModelContext{value}, tail, evidence)

def prepend_text(+message: D.Message, +index: Nat, +tail: +List<Actual.Group>, evidence: Spec.text_agreement(tail)) ->
  Spec.text_agreement(Actual.prepend(message, index, tail)):
  match message:
    case D.UserMessage{text}: ({==}, evidence)
    case D.AssistantMessage{text}: ({==}, evidence)
    case D.ModelContext{value}: provider_group_text(Content.context_kind(J.text(J.get(value, "type"))), index, value, tail, evidence)
    case D.FunctionCall{call}:
      +audit_message: D.Message = D.FunctionCall{call}
      audit_text(index, Actual.audit_failed(audit_message), audit_message, tail, evidence)
    case D.FunctionOutput{call_id, value, error}:
      +audit_message: D.Message = D.FunctionOutput{call_id, value, error}
      audit_text(index, Actual.audit_failed(audit_message), audit_message, tail, evidence)
    case D.OperationResult{ticket, call_id, tool, value, error}:
      +audit_message: D.Message = D.OperationResult{ticket, call_id, tool, value, error}
      audit_text(index, Actual.audit_failed(audit_message), audit_message, tail, evidence)
    case D.FailureMessage{text}:
      +audit_message: D.Message = D.FailureMessage{text}
      audit_text(index, Actual.audit_failed(audit_message), audit_message, tail, evidence)
    case D.ContextCheckpoint{summary}:
      +audit_message: D.Message = D.ContextCheckpoint{summary}
      audit_text(index, Actual.audit_failed(audit_message), audit_message, tail, evidence)
    case D.ReasoningRecord{owner, effort, remaining, sampling}:
      +audit_message: D.Message = D.ReasoningRecord{owner, effort, remaining, sampling}
      audit_text(index, Actual.audit_failed(audit_message), audit_message, tail, evidence)
    case D.ConfigurationUpdate{effort}:
      +audit_message: D.Message = D.ConfigurationUpdate{effort}
      audit_text(index, Actual.audit_failed(audit_message), audit_message, tail, evidence)
    case D.HookRecord{task_id, call_id, plugin, outcome}:
      +audit_message: D.Message = D.HookRecord{task_id, call_id, plugin, outcome}
      audit_text(index, Actual.audit_failed(audit_message), audit_message, tail, evidence)
    case D.ToolReceipt{task_id, operation_id, call, value, error}:
      +audit_message: D.Message = D.ToolReceipt{task_id, operation_id, call, value, error}
      audit_text(index, Actual.audit_failed(audit_message), audit_message, tail, evidence)
    case D.AfterRecord{task_id, operation_id, plugin, outcome}:
      +audit_message: D.Message = D.AfterRecord{task_id, operation_id, plugin, outcome}
      audit_text(index, Actual.audit_failed(audit_message), audit_message, tail, evidence)
    case D.ApprovalRecord{task_id, operation_id, call, reviewer, outcome}:
      +audit_message: D.Message = D.ApprovalRecord{task_id, operation_id, call, reviewer, outcome}
      audit_text(index, Actual.audit_failed(audit_message), audit_message, tail, evidence)
    case D.ForkResult{task_id, call_id, branch}:
      +audit_message: D.Message = D.ForkResult{task_id, call_id, branch}
      audit_text(index, Actual.audit_failed(audit_message), audit_message, tail, evidence)

def displayed_text(+messages: +List<D.Message>, +index: Nat) -> Spec.text_agreement(Actual.groups(messages, index)):
  match messages:
    case Nil{}: Unit{}
    case Con{message, +rest}: prepend_text(message, index, Actual.groups(rest, (index + 1n : Nat)), displayed_text(rest, (index + 1n : Nat)))

def visible_text(+groups: +List<Actual.Group>, +task: Nat, +disclosures: +List<E.Disclosure>, evidence: Spec.text_agreement(groups)) ->
  Spec.visible_text_agreement(Actual.visible(groups, task, disclosures)):
  match groups:
    case Nil{}: Unit{}
    case Con{Actual.Speech{id, speaker, text, source}, rest}:
      (head, tail) = evidence
      (head, visible_text(rest, task, disclosures, tail))
    case Con{Actual.Activity{id, attention, entries}, rest}: visible_text(rest, task, disclosures, evidence)

def observed_text(+messages: +List<D.Message>, +offset: Nat, task: Nat, disclosures: +List<E.Disclosure>) ->
  Spec.visible_text_agreement(Actual.visible(Actual.groups(messages, offset), task, disclosures)):
  visible_text(Actual.groups(messages, offset), task, disclosures, displayed_text(messages, offset))

def timeline_history(+reader: E.Reader, +task: D.Task, +world: M.World()) ->
  {Spec.timeline_sources(Actual.timeline(reader, task, world)) == D.history_messages(D.task_history(task), Nil{}) : +List<D.Message>}:
  E.Reader{generation, position, disclosures} = reader
  Equal.trans(+List<D.Message>,
    Spec.visible_sources(Actual.visible(Actual.groups(D.history_messages(D.task_history(task), Nil{}), 0n), D.task_id(task), disclosures)),
    Spec.sources(Actual.groups(D.history_messages(D.task_history(task), Nil{}), 0n)), D.history_messages(D.task_history(task), Nil{}),
    visible_history(Actual.groups(D.history_messages(D.task_history(task), Nil{}), 0n), D.task_id(task), disclosures), grouped_history(D.history_messages(D.task_history(task), Nil{}), 0n))
