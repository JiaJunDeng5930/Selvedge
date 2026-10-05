import Base
import ../MODEL.bend as Model
import ../../core/interface.bend as UI
import ../rendered.bend as Rendered
import ../render-contract.bend as Spec
import ../render-laws.bend as RenderRules
import ./render.bend as RenderProof
import ../model-rules.bend as Rule
import ../platform.bend as Platform

def Rule.production_commit_preserves_product(decision, generation, environment, font):
  match decision:
    case Platform.Decision{product, platform, effects}: {==}


def Rule.contextless_frame_silent(state, received, frame):
  match state:
    case Model.State{application, generation, realization, environment, font}: {==}

def Rule.observe_frame_exact(application, generation, previous, environment, font, received, surface, frame): {==}

def observation_sound(requirements: RenderRules.Requirements, +generation: Nat, +received: Nat,
  +surface: UI.Surface, +frame: Rendered.Frame, +previous: Rendered.State,
  owned: {Nat.is_eq(generation, received) == True{} : Bool},
  realized: {Rendered.observe(generation, received, surface, frame, previous) == Rendered.Realized{generation, frame} : Rendered.State}) ->
  {Spec.valid(surface, frame) == True{} : Bool}:
  match requirements:
    case RenderRules.Requirements{reflection, sound}: sound(generation, received, surface, frame, previous, owned, realized)

def Rule.observed_realization_sound(application, generation, previous, environment, font, received, surface, frame, owned, realized):
  match application:
    case Platform.State{core, platform}:
      observation_sound(RenderRules.evidence, generation, received, surface, frame, previous, owned, realized)
