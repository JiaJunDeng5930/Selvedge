import ../../interaction/experience/PROGRAM.bend as UX
import ../../interaction/experience/MODEL.bend as UXTypes
import ./skill-mention.bend as Mention
import Base
import ../../interaction/INPUT.bend as U
import ./MODEL.bend as Model
import ../controls/GEOMETRY.bend as Physical
import ../../interaction/IDENTITY.bend as Identity
import ../../interaction/submission/FIELDS.bend as Forms
import ../document/SOURCE.bend as Source
import ../controls/CONTROLS.bend as Controls
import ../document/MODEL.bend as Doc
import ../../interaction/presentation/SURFACE.bend as SurfaceTypes

law composing_enter:
  for owner: U.Editor
  for selection: Physical.Selection
  for shift: Bool
  for alt: Bool
  for modified: Bool
  for enabled: Bool
  for pending: Bool
  for mentions: Mention.State
  {Model.step(Model.Editor{owner, selection, True{}, mentions}, Model.Enter{shift, alt, modified}, enabled, pending) ==
    Model.Decision{Model.Editor{owner, selection, True{}, mentions}, False{}} : Model.Decision}

law native_composition_retains_default:
  @keyboard:String -> @key_code:U32 -> @shift:Bool -> @alt:Bool -> @modified:Bool ->
  {Model.native_key(Model.KeyObservation{keyboard, True{}, key_code, shift, alt, modified}) ==
    Model.NativeKey{None{}, False{}} : Model.NativeKey}

law native_ime_retains_default:
  @keyboard:String -> @composing:Bool -> @shift:Bool -> @alt:Bool -> @modified:Bool ->
  {Model.native_key(Model.KeyObservation{keyboard, composing, 229, shift, alt, modified}) ==
    Model.NativeKey{None{}, False{}} : Model.NativeKey}

law native_enter_preserves_modifiers:
  @+key_code:U32 -> @+shift:Bool -> @+alt:Bool -> @modified:Bool ->
  @ordinary:{U32.is_eq(key_code, 229) == False{} : Bool} ->
  {Model.native_key(Model.KeyObservation{"Enter", False{}, key_code, shift, alt, modified}) ==
    Model.NativeKey{Some{Model.Enter{shift, alt, modified}}, Bool.not(shift) && Bool.not(alt)} : Model.NativeKey}

law native_other_key_retains_default:
  @+keyboard:String -> @composing:Bool -> @key_code:U32 -> @shift:Bool -> @alt:Bool -> @modified:Bool ->
  @other:{String.eq(keyboard, "Enter") == False{} : Bool} ->
  {Model.native_key(Model.KeyObservation{keyboard, composing, key_code, shift, alt, modified}) ==
    Model.NativeKey{None{}, False{}} : Model.NativeKey}

type BindingRequirements is Type:
  BindingRequirements{
    message_owner: @+key:Identity.Key -> @+editor:U.Editor -> @+entry:Forms.Entry ->
      @+value:Forms.Observed -> @+choices:+List<Forms.ChoiceValue> ->
      {Controls.field_metadata(key, SurfaceTypes.Edit{editor, Forms.MessageText{}, entry, value, choices}) ==
        [Source.DataAttribute{"field", Forms.key(Forms.MessageText{})}, Source.DataAttribute{"property", UX.subject_key(UXTypes.Subject{editor, Forms.MessageText{}})}, Source.DataAttribute{"object-owner", UX.object_key(UX.owner(UXTypes.Subject{editor, Forms.MessageText{}}))}, Source.EditorBindingAttribute{key}] : +List<Source.Attribute>},
    native_owner: @+key:Identity.Key ->
      {Source.attribute_properties(Source.EditorBindingAttribute{key}) ==
        [Doc.Property{"data-native-editor-key", Identity.encode(key)}] : +List<Doc.Property>}}

law binding_evidence:
  BindingRequirements

law mention_composition_retains_default:
  @keyboard:String -> @key_code:U32 -> @shift:Bool -> @alt:Bool -> @modified:Bool -> @editor:Model.Editor ->
  {Model.native_mentions(Model.KeyObservation{keyboard, True{}, key_code, shift, alt, modified}, editor) ==
    Model.NativeKey{None{}, False{}} : Model.NativeKey}

law mention_ime_retains_default:
  @keyboard:String -> @composing:Bool -> @shift:Bool -> @alt:Bool -> @modified:Bool -> @editor:Model.Editor ->
  {Model.native_mentions(Model.KeyObservation{keyboard, composing, 229, shift, alt, modified}, editor) ==
    Model.NativeKey{None{}, False{}} : Model.NativeKey}

law selected_reference_preserves_surrounding_text:
  @+text:String -> @+start:Nat -> @+end:Nat -> @query:String -> @+skill:Mention.Skill ->
  {Mention.insert(text, Mention.Trigger{start, end, query}, skill) ==
    Mention.Insertion{String.take(text, start) ++ (Mention.reference(skill) ++ Mention.separator(String.drop(text, end))) ++ String.drop(text, end),
      (start + String.length(Mention.reference(skill) ++ Mention.separator(String.drop(text, end))) : Nat)} : Mention.Insertion}
