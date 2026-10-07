import Base
import ../appearance/TYPOGRAPHY.bend as T
import ../layout/enclosure-laws.bend as EnclosureLaws
import ../layout/enclosure.bend as Enclosure
import ../appearance/DESIGN.bend as Design
import ../appearance/MODEL.bend as Appearance
import ./PROGRAM.bend as Controls
import ../editor/editor-layout.bend as EditorLayout
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ../../interaction/submission/FIELDS.bend as Forms
import ../../interaction/INPUT.bend as User

type Requirements is Type:
  Requirements{
    field_style_widget_binding: @+typography:T.Presentation -> @editor:User.Editor -> @+field:Forms.Field -> @+entry:Forms.Entry -> @+value:Forms.Observed ->
      @choices:+List<Forms.ChoiceValue> ->
      @toggle:{Controls.widget_for(entry, field, value) == Controls.ToggleInput{} : Controls.Widget} ->
      {Appearance.field_style(InterfaceView.Edit{editor, field, entry, value, choices}, typography) == Appearance.toggle_field(typography) : Design.Style},
    dialog_outer_inset: @+typography:T.Presentation -> {EnclosureLaws.frame_coordinates(Design.style_frame(Appearance.style(InterfaceView.Dialog{}, InterfaceView.Region{}, typography))) == (0n, (0n, 0n)) : (Nat & (Nat & Nat))},
    concrete_field_kinds:   {[EditorLayout.card_field(Forms.CardTitle{}), EditorLayout.card_field(Forms.CardDescription{}),
          EditorLayout.card_field(Forms.CardStage{}), EditorLayout.card_field(Forms.CardPriority{}),
          EditorLayout.card_field(Forms.CardProject{}), EditorLayout.card_field(Forms.CardOwner{}),
          EditorLayout.card_field(Forms.CardLabels{}), EditorLayout.card_field(Forms.ContinueCapture{}),
          EditorLayout.card_field(Forms.AssistedCapture{}), EditorLayout.card_field(Forms.AssistanceProfile{})] ==
         [EditorLayout.WorkTitle{}, EditorLayout.WorkDescription{}, EditorLayout.MetadataFlexible{},
          EditorLayout.MetadataFlexible{}, EditorLayout.MetadataFlexible{}, EditorLayout.MetadataWide{},
          EditorLayout.MetadataWide{}, EditorLayout.CaptureOption{}, EditorLayout.CaptureOption{},
          EditorLayout.CaptureOption{}] : +List<EditorLayout.FieldKind>},
    field_layout_binding: @card:Maybe<&2, Nat> -> @field:Forms.Field -> @entry:Forms.Entry -> @value:Forms.Observed ->
      @choices:+List<Forms.ChoiceValue> ->
      {EditorLayout.field_kind(InterfaceView.Edit{User.CardEditor{card}, field, entry, value, choices}) ==
        EditorLayout.card_field(field) : EditorLayout.FieldKind},
    shared_inline_inset: {Enclosure.partition_inline() == 24n : Nat}}

law evidence:
  Requirements
