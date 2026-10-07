import Base
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ../../interaction/submission/FIELDS.bend as Forms
import ../../interaction/INPUT.bend as User

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

def field_kind(meaning: InterfaceView.Meaning) -> FieldKind:
  match meaning:
    case InterfaceView.Edit{User.CardEditor{card}, field, entry, value, choices}: card_field(field)
    case _: Ordinary{}
