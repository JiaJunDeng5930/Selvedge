import Base
import ../core/SYSTEM.bend as Core
import ../core/interface.bend as UI
import ./MODEL.bend as Model
import ./design.bend as Design
import ./font-observation.bend as F
import ./platform.bend as Platform
import ./rendered.bend as Rendered

law frame_emits_no_effects:
  for received: Nat
  for frame: Rendered.Frame
  for application: Platform.State
  for generation: Nat
  for realization: Rendered.State
  for environment: Design.Environment
  for font: F.State
  {Model.effects(Model.step(Model.FrameObserved{received, frame}, Model.State{application, generation, realization, environment, font})) == Nil{} : +List<Model.Effect>}


law realized_product:
  for decision: Platform.Decision
  for generation: Nat
  for environment: Design.Environment
  for font: F.State
  {Model.product(Model.realized(decision, generation, environment, font)) == Model.platform_product(decision) : Core.Decision}


law invalidated_product:
  for decision: Platform.Decision
  for +generation: Nat
  for +environment: Design.Environment
  for +font: F.State
  {Model.product(Model.invalidate(decision, generation, environment, font)) == Model.platform_product(Model.calibrated(decision, environment, F.retag(font, generation))) : Core.Decision}


law realization_preserves_product:
  for +decision: Platform.Decision
  for +generation: Nat
  for +environment: Design.Environment
  for +font: F.State
  {Model.product(Model.invalidate(decision, generation, environment, font)) == Model.platform_product(decision) : Core.Decision}


law stale_realization:
  for +application: Platform.State
  for +generation: Nat
  for +previous: Rendered.State
  for +environment: Design.Environment
  for +font: F.State
  for +received: Nat
  for +frame: Rendered.Frame
  for +surface: UI.Surface
  for stale: {Nat.is_eq(generation, received) == False{} : Bool}
  {Model.frame_realization(Model.State{application, generation, previous, environment, font}, received, frame, surface) == previous : Rendered.State}
