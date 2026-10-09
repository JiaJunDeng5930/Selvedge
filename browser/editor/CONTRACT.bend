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
  {Model.step(Model.Editor{owner, selection, True{}}, Model.Enter{shift, alt, modified}, enabled, pending) ==
    Model.Decision{Model.Editor{owner, selection, True{}}, False{}} : Model.Decision}

type BindingRequirements is Type:
  BindingRequirements{
    message_owner: @+key:Identity.Key -> @+editor:U.Editor -> @+entry:Forms.Entry ->
      @+value:Forms.Observed -> @+choices:+List<Forms.ChoiceValue> ->
      {Controls.field_metadata(key, SurfaceTypes.Edit{editor, Forms.MessageText{}, entry, value, choices}) ==
        [Source.DataAttribute{"field", Forms.key(Forms.MessageText{})}, Source.EditorBindingAttribute{key}] : +List<Source.Attribute>},
    native_owner: @+key:Identity.Key ->
      {Source.attribute_properties(Source.EditorBindingAttribute{key}) ==
        [Doc.Property{"data-native-editor-key", Identity.encode(key)}] : +List<Doc.Property>}}

law binding_evidence:
  BindingRequirements
