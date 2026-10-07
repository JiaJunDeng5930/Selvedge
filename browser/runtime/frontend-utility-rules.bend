import Base
import ./frontend-utility.bend as Utility
import ../document/SOURCE.bend as Source
import ../document/MODEL.bend as Doc
import ../controls/CONTROLS.bend as AuthoredControls
import ../controls/PROGRAM.bend as Controls
import ../appearance/MODEL.bend as Appearance
import ../appearance/TYPOGRAPHY.bend as T
import ../../interaction/IDENTITY.bend as Identity

type Requirements is Type:
  Requirements{
    supported: @+purpose:Utility.Purpose -> @+font:T.Presentation -> @+glyph_only:Bool ->
      {Utility.supported(Utility.source(purpose, font, glyph_only)) == True{} : Bool},
    retry_identity_and_event: @+font:T.Presentation -> @+reason:String ->
      {Utility.retry(font, reason) == Source.Control{Utility.retry_key(), Source.Button{}, Utility.retry_style(font),
        [Source.DataAttribute{"native-key", Identity.encode(Utility.retry_key())}, Source.TitleAttribute{"Retry rendering: " ++ reason}], "Retry rendering: " ++ reason,
        True{}, Doc.Activate{"@browser/retry"}, Nil{},
        [AuthoredControls.glyph(Identity.part(Utility.retry_key(), "icon"), Controls.Refresh{}, Appearance.ordinary_button(font), 16n)]} : Source.Node},
    source_owned: @+purpose:Utility.Purpose -> @+font:T.Presentation -> @+glyph_only:Bool ->
      {Utility.owned(Utility.source(purpose, font, glyph_only)) == True{} : Bool}}

law evidence:
  Requirements
