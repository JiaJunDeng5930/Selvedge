import Base
import ../core/interface.bend as InterfaceView

type Requirements is Type:
  Requirements{
    source_alert_passive: @+reason:String ->
      {InterfaceView.focusable(InterfaceView.ReadOnly{reason}) == False{} : Bool}}

law evidence:
  Requirements
