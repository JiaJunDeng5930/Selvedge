import ./skill-mention.bend as Mention
import ../../bendlib/json.bend as J
import Base
import ../../interaction/INPUT.bend as U
import ../controls/GEOMETRY.bend as Physical
import ../../interaction/submission/FIELDS.bend as Forms
import ../../interaction/presentation/SURFACE.bend as SurfaceTypes

type Editor is Data:
  Editor{owner: U.Editor, selection: Physical.Selection, composing: Bool, mentions: Mention.State}

type EditorEvent is Data:
  SelectionChanged{selection: Physical.Selection}
  CompositionChanged{composing: Bool}
  SelectionObserved{key: String, selection: Physical.Selection}
  FocusObserved{key: String, selection: Physical.Selection}
  CatalogObserved{ticket: Nat, workspace: String, body: J.Json}
  MoveMention{backward: Bool}
  AcceptMention{index: Maybe<&2, Nat>}
  DismissMention{}
  Enter{shift: Bool, alt: Bool, modified: Bool}

type Decision is Data:
  Decision{editor: Editor, submit: Bool}

type KeyObservation is Data:
  KeyObservation{keyboard: String, composing: Bool, key_code: U32,
    shift: Bool, alt: Bool, modified: Bool}

type NativeKey is Data:
  NativeKey{event: Maybe<&2, EditorEvent>, prevent_default: Bool}

def native_key_ready(ready: Bool, +shift: Bool, +alt: Bool, modified: Bool) -> NativeKey:
  match ready:
    case False{}: NativeKey{None{}, False{}}
    case True{}: NativeKey{Some{Enter{shift, alt, modified}}, Bool.not(shift) && Bool.not(alt)}

def native_key(observation: KeyObservation) -> NativeKey:
  KeyObservation{keyboard, composing, key_code, shift, alt, modified} = observation
  native_key_ready(String.eq(keyboard, "Enter") && Bool.not(composing) && Bool.not(U32.is_eq(key_code, 229)), shift, alt, modified)

def step(editor: Editor, event: EditorEvent, enabled: Bool, pending: Bool) -> Decision:
  Editor{owner, selection, +composing, mentions} = editor
  match event:
    case SelectionChanged{range}: Decision{Editor{owner, range, composing, mentions}, False{}}
    case CompositionChanged{active}: Decision{Editor{owner, selection, active, mentions}, False{}}
    case SelectionObserved{key, range}: Decision{Editor{owner, range, composing, Mention.with_field(key, mentions)}, False{}}
    case FocusObserved{key, range}: Decision{Editor{owner, range, composing, Mention.with_field(key, Mention.refocus(mentions))}, False{}}
    case Enter{shift, alt, modified}:
      Decision{Editor{owner, selection, composing, mentions}, Physical.submit_key(composing, True{}, True{}, modified, shift, alt, enabled, pending)}

    case _: Decision{Editor{owner, selection, composing, mentions}, False{}}

def mentions(editor: Editor) -> Mention.State:
  Editor{owner, selection, composing, value} = editor
  value

def with_mentions(mentions: Mention.State, editor: Editor) -> Editor:
  Editor{owner, selection, composing, previous} = editor
  Editor{owner, selection, composing, mentions}

type FieldKind is Data:
  Ordinary{}
  WorkTitle{}
  WorkDescription{}

def card_field(field: Forms.Field) -> FieldKind:
  match field:
    case Forms.CardTitle{}: WorkTitle{}
    case Forms.CardDescription{}: WorkDescription{}
    case _: Ordinary{}

def field_kind(meaning: SurfaceTypes.Meaning) -> FieldKind:
  match meaning:
    case SurfaceTypes.Edit{U.CardEditor{card}, field, entry, value, choices}: card_field(field)
    case _: Ordinary{}

def mention_keyboard(keyboard: String, +state: Mention.State, active: Maybe<&2, Mention.Skill>) -> NativeKey:
  match keyboard active:
    case "Escape" _: NativeKey{Some{DismissMention{}}, True{}}
    case "ArrowUp" Some{skill}: NativeKey{Some{MoveMention{True{}}}, True{}}
    case "ArrowDown" Some{skill}: NativeKey{Some{MoveMention{False{}}}, True{}}
    case "Enter" Some{skill}: NativeKey{Some{AcceptMention{None{}}}, True{}}
    case "Tab" Some{skill}: NativeKey{Some{AcceptMention{None{}}}, True{}}
    case _ _: NativeKey{None{}, False{}}

def native_mentions_ready(ready: Bool, keyboard: String, +state: Mention.State) -> NativeKey:
  match ready:
    case False{}: NativeKey{None{}, False{}}
    case True{}:
      mention_keyboard(keyboard, state, Mention.active(state))

def native_mentions(observation: KeyObservation, editor: Editor) -> NativeKey:
  KeyObservation{keyboard, composing, key_code, shift, alt, modified} = observation
  Editor{owner, selection, editor_composing, +mentions} = editor
  native_mentions_ready(Mention.open(mentions) && Bool.not(composing || editor_composing || U32.is_eq(key_code, 229) || shift || alt || modified), keyboard, mentions)
