import Base
import ../controls/GEOMETRY.bend as Geometry
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ./SPEC.bend as Spec
import ./RENDERED.bend as Rendered


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
    reflection: @+surface:InterfaceView.Surface -> @+frame:Rendered.Frame ->
      {clear(Rendered.violations(surface, frame)) == Spec.valid(surface, frame) : Bool},
    realized_sound: @+current:Nat -> @+received:Nat -> @+surface:InterfaceView.Surface ->
      @+frame:Rendered.Frame -> @+previous:Rendered.State ->
      @owned:{Nat.is_eq(current, received) == True{} : Bool} ->
      @realized:{Rendered.observe(current, received, surface, frame, previous) == Rendered.Realized{current, frame} : Rendered.State} ->
      {Spec.valid(surface, frame) == True{} : Bool}
  }

law evidence:
  Requirements

law dialog_actions_region_geometry:
  for found: Maybe<&2, Rendered.Element>
  for viewport: Geometry.Rect
  {Spec.region_geometry_valid(InterfaceView.DialogActions{}, found, viewport) == Spec.bounded_region(found, viewport) : Bool}

law dialog_actions_children_visible:
  for inherited: Bool
  for found: Maybe<&2, Rendered.Element>
  for viewport: Geometry.Rect
  {Spec.child_persistent(inherited, InterfaceView.DialogActions{}, found, viewport) == True{} : Bool}
