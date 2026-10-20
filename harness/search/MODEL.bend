import Base
import ../DOMAIN.bend as D
import ../conversation/PROGRAM.bend as Content
import ../../bendlib/json.bend as J

# Search sources retain the existing task summary and its immutable history.
type Source is Data:
  Source{task: D.Task, summary: J.Json, work: Maybe<&2, Nat>}

type Text is Data:
  Text{role: String, text: String}

def provider_speech(assistant: Bool, value: J.Json) -> Maybe<&2, Text>:
  match assistant:
    case False{}: None{}
    case True{}: Some{Text{"assistant", Content.provider_text(value)}}

def provider_readable(kind: Content.ContextKind, +value: J.Json) -> Maybe<&2, Text>:
  match kind:
    case Content.SpeechContext{}: provider_speech(Content.provider_assistant(value), value)
    case _: None{}

def readable(message: D.Message) -> Maybe<&2, Text>:
  match message:
    case D.UserMessage{text}: Some{Text{"user", text}}
    case D.AssistantMessage{origin, text}: Some{Text{"assistant", text}}
    case D.ModelContext{origin, +value}: provider_readable(Content.provider_kind(value), value)
    case D.SpeechTranscript{owner, session, item, speaker, completion, text}:
      Some{Text{D.speech_speaker_name(speaker), text}}
    case _: None{}

def identity_matches(filter: Maybe<&2, Nat>, identity: Maybe<&2, Nat>) -> Bool:
  match filter identity:
    case None{} _: True{}
    case Some{expected} Some{actual}: Nat.is_eq(expected, actual)
    case Some{expected} None{}: False{}

def page_size_valid(+limit: Nat) -> Bool:
  Nat.is_le(1n, limit) && Nat.is_le(limit, 50n)

def context_characters() -> Nat:
  180n

def snippet_characters() -> Nat:
  320n

def query_valid(+query: String) -> Bool:
  Bool.not(String.is_empty(query)) && Nat.is_le(String.length(query), 240n)
