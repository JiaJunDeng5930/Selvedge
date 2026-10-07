import Base
import ../../interaction/INPUT.bend as U
import ./MODEL.bend as Model
import ../controls/GEOMETRY.bend as Physical

law composing_enter:
  for owner: U.Editor
  for selection: Physical.Selection
  for shift: Bool
  for alt: Bool
  for modified: Bool
  for enabled: Bool
  for pending: Bool
  {Model.step(Model.Editor{owner, selection, True{}}, Model.Enter{shift, alt, modified}, enabled, pending) ==
    Model.Decision{Model.Editor{owner, selection, True{}}, False{}} : Model.Decision}
