import Base
import ../core/user-input.bend as U
import ./editor.bend as Model
import ./interaction.bend as Physical

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
