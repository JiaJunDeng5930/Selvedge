import Base
import ../core/interface.bend as UI

type Requirements is Type:
  Requirements{
    source_alert_passive: @+reason:String ->
      {UI.focusable(UI.ReadOnly{reason}) == False{} : Bool}}

law evidence:
  Requirements
