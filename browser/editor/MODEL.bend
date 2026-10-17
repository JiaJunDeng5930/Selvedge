import Base
import ../../interaction/INPUT.bend as U
import ../controls/GEOMETRY.bend as Physical
import ../../interaction/submission/FIELDS.bend as Forms
import ../../interaction/presentation/SURFACE.bend as SurfaceTypes

type Editor is Data:
  Editor{owner: U.Editor, selection: Physical.Selection, composing: Bool}

type EditorEvent is Data:
  SelectionChanged{selection: Physical.Selection}
  CompositionChanged{composing: Bool}
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
  Editor{owner, selection, +composing} = editor
  match event:
    case SelectionChanged{range}: Decision{Editor{owner, range, composing}, False{}}
    case CompositionChanged{active}: Decision{Editor{owner, selection, active}, False{}}
    case Enter{shift, alt, modified}:
      Decision{Editor{owner, selection, composing}, Physical.submit_key(composing, True{}, True{}, modified, shift, alt, enabled, pending)}

type FieldKind is Data:
  Ordinary{}
  WorkTitle{}
  WorkDescription{}
  MetadataFlexible{}
  MetadataWide{}
  CaptureOption{}

def card_field(field: Forms.Field) -> FieldKind:
  match field:
    case Forms.CardTitle{}: WorkTitle{}
    case Forms.CardDescription{}: WorkDescription{}
    case Forms.CardStage{}: MetadataFlexible{}
    case Forms.CardPriority{}: MetadataFlexible{}
    case Forms.CardProject{}: MetadataFlexible{}
    case Forms.CardOwner{}: MetadataWide{}
    case Forms.CardLabels{}: MetadataWide{}
    case Forms.ContinueCapture{}: CaptureOption{}
    case Forms.AssistedCapture{}: CaptureOption{}
    case Forms.AssistanceProfile{}: CaptureOption{}
    case _: Ordinary{}

def field_kind(meaning: SurfaceTypes.Meaning) -> FieldKind:
  match meaning:
    case SurfaceTypes.Edit{U.CardEditor{card}, field, entry, value, choices}: card_field(field)
    case _: Ordinary{}
