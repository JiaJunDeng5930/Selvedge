import Base
import ./focus/MODEL.bend as Focus
import ./MODEL.bend as Model
import ../interaction/presentation/PROGRAM.bend as InterfaceView
import ./document/RENDERED.bend as Rendered
import ./document/SPEC.bend as Spec
import ./document/CONTRACT.bend as RenderRules
import ./document/PROOF.bend as RenderProof
import ./model-rules.bend as Rule
import ./runtime/PLATFORM.bend as Platform

def Rule.resolved_scope_focus(ticket, previous, current, surface): {==}

def Rule.platform_scope_focus(ticket, previous, current, rest, surface): {==}

def Rule.production_commit_preserves_product(decision, generation, environment, font):
  match decision:
    case Platform.Decision{product, platform, effects}: {==}

def Rule.contextless_frame_silent(state, received, frame):
  match state:
    case Model.State{application, generation, realization, environment, font}: {==}

def Rule.observe_frame_exact(model_state, received, surface, frame):
  Model.State{Platform.State{+core, Platform.Platform{+readers, +editors, +focused, +ticket, +reduced, +capacity, +scope}}, +generation, +previous, +environment, +font} = model_state
  {==}

def Rule.visible_focus_recovery_visible(visible, eligible, identity): {==}

def Rule.visible_focus_recovery_hidden(focused, eligible, identity):
  match focused:
    case False{}: {==}
    case True{}: {==}

def Rule.visible_focus_recovery_ineligible(focused, visible, identity):
  match focused visible:
    case False{} False{}: {==}
    case False{} True{}: {==}
    case True{} _: {==}

def Rule.visible_focus_recovery_target(identity): {==}

def Rule.frame_focus_recovery_document(surface, frame):
  match frame:
    case Rendered.Frame{viewport, elements, focused, tab_order, native_focus}: {==}

def Rule.frame_focus_recovery_unfocused(surface, viewport, elements, tab_order, native_focus, scope):
  match scope:
    case Focus.Document{}: {==}
    case Focus.Temporary{identity, initial, restore, occurrence}: {==}

def Rule.frame_focus_recovery_temporary(surface, viewport, elements, key, tab_order, native_focus, identity, initial, restore, occurrence): {==}

def Rule.frame_recovery_effects_stale(ticket, generation, target): {==}

def Rule.frame_recovery_effects_absent(owned, ticket, generation):
  match owned:
    case False{}: {==}
    case True{}: {==}

def Rule.frame_recovery_effects_target(ticket, generation, identity): {==}

def observation_sound(requirements: RenderRules.Requirements, +generation: Nat, +received: Nat,
  +surface: InterfaceView.Surface, +frame: Rendered.Frame, +previous: Rendered.State,
  owned: {Nat.is_eq(generation, received) == True{} : Bool},
  realized: {Rendered.observe(generation, received, surface, frame, previous) == Rendered.Realized{generation, frame} : Rendered.State}) ->
  {Spec.valid(surface, frame) == True{} : Bool}:
  match requirements:
    case RenderRules.Requirements{reflection, sound}: sound(generation, received, surface, frame, previous, owned, realized)

def Rule.observed_realization_sound(model_state, received, surface, frame, owned, realized):
  Model.State{+application, +generation, +previous, +environment, +font} = model_state
  match application:
    case Platform.State{core, Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope}}:
      observation_sound(RenderRules.evidence, generation, received, surface, frame, previous, owned, realized)
