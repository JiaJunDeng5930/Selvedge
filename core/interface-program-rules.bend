import Base
import ../UI.bend as Model
import ./SYSTEM.bend as Core

law interface_input:
  for +input: Core.Input
  for +state: Core.State
  {Model.step(Model.InterfaceInput{input}, state) == Core.step(input, state) : Core.Decision}


type InterfaceRequirements is Type:
  InterfaceRequirements{
    interface_input: @+input:Core.Input -> @+state:Core.State ->
      {Model.step(Model.InterfaceInput{input}, state) == Core.step(input, state) : Core.Decision}
  }

law interface_evidence:
  InterfaceRequirements
