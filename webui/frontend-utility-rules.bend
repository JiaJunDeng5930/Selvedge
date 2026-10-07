import Base
import ./frontend-utility.bend as Utility
import ./source.bend as Source
import ./document.bend as Doc
import ./authored-controls.bend as AuthoredControls
import ./controls.bend as Controls
import ./appearance.bend as Appearance
import ./typography.bend as T
import ../core/ui-identity.bend as Identity

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
