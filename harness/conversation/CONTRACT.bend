import Base
import ../DOMAIN.bend as D
import ./PROGRAM.bend as Content
import ../../bendlib/json.bend as J
import ../../interaction/conversation/MODEL.bend as Actual

# Task acceptance receipts are operational bookkeeping. All conversational
# content retains its original order independently of disclosure or grouping.
def displayed_message(message: D.Message, rest: +List<D.Message>) -> +List<D.Message>:
  match message:
    case D.SpeechDelegationReceipt{owner, session, identity, mode, text}: rest
    case other: other <> rest

def displayed_messages(messages: +List<D.Message>) -> +List<D.Message>:
  match messages:
    case Nil{}: Nil{}
    case Con{message, rest}: displayed_message(message, displayed_messages(rest))

def audit_sources(entries: +List<Actual.Audit>) -> +List<D.Message>:
  match entries:
    case Nil{}: Nil{}
    case Con{Actual.Audit{occurrence, source}, rest}: source <> audit_sources(rest)

def sources(groups: +List<Actual.Group>) -> +List<D.Message>:
  match groups:
    case Nil{}: Nil{}
    case Con{Actual.Speech{id, speaker, text, source}, rest}: source <> sources(rest)
    case Con{Actual.Activity{id, attention, entries}, rest}:
      List.append(&2, D.Message, audit_sources(entries), sources(rest))

def face_sources(entries: +List<Actual.AuditFace>) -> +List<D.Message>:
  match entries:
    case Nil{}: Nil{}
    case Con{Actual.AuditFace{occurrence, kind, title, source}, rest}: source <> face_sources(rest)

def visible_sources(groups: +List<Actual.VisibleGroup>) -> +List<D.Message>:
  match groups:
    case Nil{}: Nil{}
    case Con{Actual.VisibleSpeech{id, speaker, text, source}, rest}: source <> visible_sources(rest)
    case Con{Actual.VisibleActivity{id, attention, expanded, summary, entries, expand, collapse}, rest}:
      List.append(&2, D.Message, face_sources(entries), visible_sources(rest))

def text(source: D.Message) -> String:
  match source:
    case D.SpeechTranscript{owner, session, item, speaker, completion, value}: value
    case D.UserMessage{value}: D.content_markdown(value)
    case D.AssistantMessage{origin, value}: value
    case D.ModelContext{origin, value}: Content.provider_text(value)
    case _: ""

def text_agreement(groups: +List<Actual.Group>) -> Type:
  match groups:
    case Nil{}: Unit
    case Con{Actual.Speech{id, speaker, value, source}, rest}: {value == text(source) : String} & text_agreement(rest)
    case Con{Actual.Activity{id, attention, entries}, rest}: text_agreement(rest)

def visible_text_agreement(groups: +List<Actual.VisibleGroup>) -> Type:
  match groups:
    case Nil{}: Unit
    case Con{Actual.VisibleSpeech{id, speaker, value, source}, rest}: {value == text(source) : String} & visible_text_agreement(rest)
    case Con{Actual.VisibleActivity{id, attention, expanded, summary, entries, expand, collapse}, rest}: visible_text_agreement(rest)

def timeline_sources(timeline: Actual.Timeline) -> +List<D.Message>:
  Actual.Timeline{task, generation, groups, operations, decisions, reading, latest} = timeline
  visible_sources(groups)
