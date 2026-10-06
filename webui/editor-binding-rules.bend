import Base
import ../core/ui-identity.bend as Identity
import ../core/user-input.bend as U
import ../core/form-fields.bend as Forms
import ../core/interface.bend as UI
import ./source.bend as Source
import ./authored-controls.bend as Controls
import ./document.bend as Doc

type Requirements is Type:
  Requirements{
    message_owner: @+key:Identity.Key -> @+editor:U.Editor -> @+entry:Forms.Entry ->
      @+value:Forms.Observed -> @+choices:+List<Forms.ChoiceValue> ->
      {Controls.field_metadata(key, UI.Edit{editor, Forms.MessageText{}, entry, value, choices}) ==
        [Source.DataAttribute{"field", Forms.key(Forms.MessageText{})}, Source.EditorBindingAttribute{key}] : +List<Source.Attribute>},
    native_owner: @+key:Identity.Key ->
      {Source.attribute_properties(Source.EditorBindingAttribute{key}) ==
        [Doc.Property{"data-native-editor-key", Identity.encode(key)}] : +List<Doc.Property>}}

law evidence:
  Requirements
