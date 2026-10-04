import Base
import ../../core/SYSTEM.bend as Core
import ../MODEL.bend as Model
import ../font-observation.bend as F
import ../model-rules.bend as Rule
import ../platform-rules.bend as PlatformRule
import ../platform.bend as Platform
import ../rendered.bend as Rendered

def Rule.frame_emits_no_effects(received, frame, application, generation, realization, environment, font):
  Platform.State{core, platform} = application
  {==}

def Rule.realized_product(decision, generation, environment, font):
  match decision:
    case Platform.Decision{product, platform, effects}: {==}

def Rule.invalidated_product(decision, generation, environment, font):
  Rule.realized_product(Model.calibrated(decision, environment, F.retag(font, generation)), generation, environment, F.retag(font, generation))

def Rule.realization_preserves_product(decision, generation, environment, font):
  Equal.trans(Core.Decision, Model.product(Model.invalidate(decision, generation, environment, font)),
    Model.platform_product(Model.calibrated(decision, environment, F.retag(font, generation))), Model.platform_product(decision),
    Rule.invalidated_product(decision, generation, environment, font),
    PlatformRule.reflow_preserves_product(decision,
      Model.font_capacity(F.retag(font, generation), environment, Platform.next(decision))))

def Rule.stale_realization(application, generation, previous, environment, font, received, frame, surface, stale):
  Equal.cong(Bool, Rendered.State,
    (owned => Model.observed_frame(owned, Model.frame_surface(Model.State{application, generation, previous, environment, font}, surface), generation, received, frame, previous)),
    Nat.is_eq(generation, received), False{}, stale)
