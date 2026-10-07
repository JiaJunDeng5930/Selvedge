import Base
import ../../interaction/IDENTITY.bend as Identity
import ../../interaction/INPUT.bend as U
import ../../interaction/submission/FIELDS.bend as Forms
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ../document/SOURCE.bend as Source
import ../controls/CONTROLS.bend as Controls
import ../document/MODEL.bend as Doc

type Requirements is Type:
  Requirements{
    message_owner: @+key:Identity.Key -> @+editor:U.Editor -> @+entry:Forms.Entry ->
      @+value:Forms.Observed -> @+choices:+List<Forms.ChoiceValue> ->
      {Controls.field_metadata(key, InterfaceView.Edit{editor, Forms.MessageText{}, entry, value, choices}) ==
        [Source.DataAttribute{"field", Forms.key(Forms.MessageText{})}, Source.EditorBindingAttribute{key}] : +List<Source.Attribute>},
    native_owner: @+key:Identity.Key ->
      {Source.attribute_properties(Source.EditorBindingAttribute{key}) ==
        [Doc.Property{"data-native-editor-key", Identity.encode(key)}] : +List<Doc.Property>}}

law evidence:
  Requirements
