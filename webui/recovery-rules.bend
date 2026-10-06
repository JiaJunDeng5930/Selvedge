import Base
import ./physical-browser.bend as Browser
import ./browser.bend as Legacy
import ./MODEL.bend as Web
import ./document.bend as Doc
import ./paint.bend as Paint
import ./typography.bend as T

type Requirements is Type:
  Requirements{
    blocked_presentation: @+capacity:Nat -> @+reason:String -> @+font:T.Presentation ->
      {Browser.observed_lifecycle_at(capacity, Browser.Blocked{reason}, None{}, font) == Browser.recovery_document_at(capacity, reason, font) : Doc.Document},
    recovery_document: @capacity:Nat -> @message:String -> @font:T.Presentation ->
      {Browser.recovery_document_at(capacity, message, font) ==
        Doc.Document{Doc.Element{"@browser/status", "section",
          [Doc.Property{"role", "status"}, Doc.Property{"data-frame-observation", "off"}],
          Paint.text_presentation_at(capacity, font), Nil{}, [Doc.Text{message}, Browser.recovery_button()]}, "Selvedge"} : Doc.Document},
    retry_button:
      {Browser.recovery_button() == Doc.Element{"@browser/retry", "button",
        [Doc.Property{"type", "button"}, Doc.Property{"aria-label", "Retry rendering"}],
        Nil{}, [Doc.Activate{"@browser/retry"}], [Doc.Text{"Retry"}]} : Doc.Node},
    retry_dispatch: @+state:Browser.State ->
      {Browser.activate("@browser/retry", state) == Browser.accept(True{}, Legacy.activate("@browser/retry", Browser.legacy(state)), state) : Browser.Decision},
    retry_mount: @+state:Legacy.State ->
      {Legacy.activate("@browser/retry", state) == Legacy.native(Web.Mount{}, state) : Legacy.Decision}}

law evidence:
  Requirements
