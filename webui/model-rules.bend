import Base
import ../core/interface.bend as UI
import ./rendered.bend as Rendered
import ./render-contract.bend as Spec
import ../core/SYSTEM.bend as Core
import ./MODEL.bend as Model
import ./design.bend as Design
import ./font-observation.bend as F
import ./platform.bend as Platform
import ./focus.bend as Focus

law resolved_scope_focus:
  for +ticket: Nat
  for +previous: Focus.Scope
  for +current: Focus.Scope
  for +surface: UI.Surface
  {Model.resolved_effect(Platform.ScopeFocus{ticket, previous, current}, surface) ==
    Model.resolved_focus(ticket, UI.focus_target(surface, Focus.scope_target(previous, current, surface))) : +List<Model.Effect>}

law platform_scope_focus:
  for +ticket: Nat
  for +previous: Focus.Scope
  for +current: Focus.Scope
  for +rest: +List<Platform.Effect>
  for +surface: UI.Surface
  {Model.platform_effects(Platform.ScopeFocus{ticket, previous, current} <> rest, surface) ==
    List.append(&2, Model.Effect,
      Model.resolved_focus(ticket, UI.focus_target(surface, Focus.scope_target(previous, current, surface))),
      Model.platform_effects(rest, surface)) : +List<Model.Effect>}

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
