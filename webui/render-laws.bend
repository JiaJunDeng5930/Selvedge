import Base
import ../core/interface.bend as UI
import ./render-contract.bend as Spec
import ./rendered.bend as Rendered


def clear(faults: +List<Rendered.Violation>) -> Bool:
  match faults:
    case Nil{}: True{}
    case Con{fault, rest}: False{}

def realized_tag(state: Rendered.State) -> Bool:
  match state:
    case Rendered.Realized{generation, frame}: True{}
    case _: False{}

type Requirements is Type:
  Requirements{
    reflection: @+surface:UI.Surface -> @+frame:Rendered.Frame ->
      {clear(Rendered.violations(surface, frame)) == Spec.valid(surface, frame) : Bool},
    realized_sound: @+current:Nat -> @+received:Nat -> @+surface:UI.Surface ->
      @+frame:Rendered.Frame -> @+previous:Rendered.State ->
      @owned:{Nat.is_eq(current, received) == True{} : Bool} ->
      @realized:{Rendered.observe(current, received, surface, frame, previous) == Rendered.Realized{current, frame} : Rendered.State} ->
      {Spec.valid(surface, frame) == True{} : Bool}
  }

law evidence:
  Requirements
