import Base
import ./typography.bend as T
import ./enclosure-laws.bend as EnclosureLaws
import ./enclosure.bend as Enclosure
import ./design.bend as Design
import ./appearance.bend as Appearance
import ./controls.bend as Controls
import ./editor-layout.bend as EditorLayout
import ../core/interface.bend as UI
import ../core/form-fields.bend as Forms
import ../core/user-input.bend as User

type Requirements is Type:
  Requirements{
    field_style_widget_binding: @+typography:T.Presentation -> @editor:User.Editor -> @+field:Forms.Field -> @+entry:Forms.Entry -> @+value:Forms.Observed ->
      @choices:+List<Forms.ChoiceValue> ->
      @toggle:{Controls.widget_for(entry, field, value) == Controls.ToggleInput{} : Controls.Widget} ->
      {Appearance.field_style(UI.Edit{editor, field, entry, value, choices}, typography) == Appearance.toggle_field(typography) : Design.Style},
    dialog_outer_inset: @+typography:T.Presentation -> {EnclosureLaws.frame_coordinates(Design.style_frame(Appearance.style(UI.Dialog{}, UI.Region{}, typography))) == (0n, (0n, 0n)) : (Nat & (Nat & Nat))},
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
      {EditorLayout.field_kind(UI.Edit{User.CardEditor{card}, field, entry, value, choices}) ==
        EditorLayout.card_field(field) : EditorLayout.FieldKind},
    shared_inline_inset: {Enclosure.partition_inline() == 24n : Nat}}

law evidence:
  Requirements
