import Base
import ../core/interface.bend as UI
import ./rendered.bend as Rendered
import ./render-contract.bend as Spec
import ../core/SYSTEM.bend as Core
import ./MODEL.bend as Model
import ./design.bend as Design
import ./font-observation.bend as F
import ./platform.bend as Platform

law production_commit_preserves_product:
  for +decision: Platform.Decision
  for +generation: Nat
  for +environment: Design.Environment
  for +font: F.State
  {Model.product(Model.production_commit(decision, generation, environment, font)) == Model.platform_product(decision) : Core.Decision}

law contextless_frame_silent:
  for +state: Model.State
  for +received: Nat
  for +frame: Rendered.Frame
  {Model.production_dispatch(state, Model.FrameObserved{received, frame}) ==
    Model.idle_state(state) : Model.Decision}

law observe_frame_exact:
  for +application: Platform.State
  for +generation: Nat
  for +previous: Rendered.State
  for +environment: Design.Environment
  for +font: F.State
  for +received: Nat
  for +surface: UI.Surface
  for +frame: Rendered.Frame
  {Model.observe_frame(received, surface, frame, Model.State{application, generation, previous, environment, font}) ==
    Model.idle(application, generation, Rendered.observe(generation, received, surface, frame, previous), environment, font) : Model.Decision}

law observed_realization_sound:
  for +application: Platform.State
  for +generation: Nat
  for +previous: Rendered.State
  for +environment: Design.Environment
  for +font: F.State
  for +received: Nat
  for +surface: UI.Surface
  for +frame: Rendered.Frame
  for owned: {Nat.is_eq(generation, received) == True{} : Bool}
  for realized: {Model.decision_realization(Model.observe_frame(received, surface, frame,
    Model.State{application, generation, previous, environment, font})) == Rendered.Realized{generation, frame} : Rendered.State}
  {Spec.valid(surface, frame) == True{} : Bool}
