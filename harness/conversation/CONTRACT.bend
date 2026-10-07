import Base
import ../DOMAIN.bend as D
import ./PROGRAM.bend as Content
import ../../bendlib/json.bend as J
import ../../interaction/conversation/MODEL.bend as Actual

# The observable record is the original ordered history, independently of
# speech/activity classification and whether an activity is expanded.
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
    case D.UserMessage{value}: value
    case D.AssistantMessage{value}: value
    case D.ModelContext{value}: Content.content_parts(J.items(J.get(value, "content")))
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
