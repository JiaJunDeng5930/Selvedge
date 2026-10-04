import Base
import ../../core/SYSTEM.bend as Core
import ../../core/interface.bend as UI
import ../../core/ui-world.bend as View
import ../MODEL.bend as Model
import ../design.bend as Design
import ../layout.bend as Layout
import ../platform.bend as Platform
import ../rendered.bend as Rendered
import ../presentation-order.bend as Order
import ../font-observation.bend as F
import ../typography.bend as T
import ../viewport-space.bend as ViewportSpace
import ../content-space.bend as CS
import ../content-space-laws.bend as CSL
import ../appearance.bend as Appearance
import ../renderer.bend as R

import ../presentation-laws.bend as Rule
import ./appearance.bend as Proof_appearance
import ./content-space.bend as Proof_content_space
import ./space.bend as Proof_space
import ../model-rules.bend as Rules_model_rules

def allocated_semantics(+outcome: Layout.Outcome, application: Platform.State, generation: Nat,
  realization: Rendered.State, +surface: Design.Surface, original: UI.Surface,
  semantic: {Design.semantic_surface(surface) == original : UI.Surface}) ->
  Rule.SemanticClaim(Model.allocated_scene(outcome, application, generation, realization, R.prepare(surface)), original):
  match outcome:
    case Layout.LayoutReady{layout}:
      Design.Surface{content, theme, base, overlays, active_scope} = surface
      semantic
    case Layout.LayoutUnsupported{required, available}: Unit{}

def preparation_semantics(+preparation: CS.Outcome, +application: Platform.State, +generation: Nat,
  +realization: Rendered.State, +parameters: Design.LayoutParameters, +viewport: Design.Viewport,
  +original: UI.Surface, +appearance: Design.Surface,
  preparation_claim: CSL.SurfaceClaim(appearance, preparation),
  appearance_claim: {Design.semantic_surface(appearance) == original : UI.Surface}) ->
  Rule.SemanticClaim(Model.prepared_scene(preparation, application, generation, realization, parameters, viewport), original):
  match preparation:
    case CS.AwaitingContent{missing}: Unit{}
    case CS.Prepared{+prepared}:
      Design.Surface{content, theme, base, overlays, active_scope} = prepared
      allocated_semantics(Layout.present(parameters, viewport, R.prepare(prepared)), application, generation, realization, prepared, original,
        Equal.trans(UI.Surface, Design.semantic_surface(prepared), Design.semantic_surface(appearance), original, preparation_claim, appearance_claim))

def scene_for_surface_preserves_semantics(state: Model.State, +surface: UI.Surface) ->
  Rule.SemanticClaim(Model.scene_for_surface(state, surface), surface):
  Model.State{application, generation, realization, Design.Environment{viewport, +dark, root}, font} = state
  match font:
    case F.Pending{font_generation, scale}: Unit{}
    case F.Failed{font_generation, scale}: Unit{}
    case F.Ready{font_generation, +scale, metric, +content_cache}:
      +appearance = Appearance.present(surface, dark, scale)
      preparation_semantics(CS.prepare(content_cache, appearance), application, generation, realization,
        ViewportSpace.parameters(scale, metric), viewport, surface, appearance,
        Proof_content_space.prepare_semantics(content_cache, appearance), Proof_appearance.present_preserves_semantics(surface, dark, scale))

def observes_semantic_surface(+state: Model.State) ->
  Rule.SemanticClaim(Model.observe(state), Model.observed_surface(state)):
  scene_for_surface_preserves_semantics(state, Model.observed_surface(state))

def allocated_layout(+outcome: Layout.Outcome, application: Platform.State, generation: Nat,
  realization: Rendered.State, surface: Design.Surface) ->
  Rule.PreparedClaim(Model.allocated_scene(outcome, application, generation, realization, R.prepare(surface)), outcome):
  match outcome:
    case Layout.LayoutReady{layout}: {==}
    case Layout.LayoutUnsupported{required, available}: {==}

def preparation_layout(+preparation: CS.Outcome, +parameters: Design.LayoutParameters, +viewport: Design.Viewport,
  application: Platform.State, generation: Nat, realization: Rendered.State) ->
  Rule.PreparationClaim(preparation, parameters, viewport, Model.prepared_scene(preparation, application, generation, realization, parameters, viewport)):
  match preparation:
    case CS.AwaitingContent{missing}: {==}
    case CS.Prepared{+surface}:
      Design.Surface{content, theme, base, overlays, active_scope} = surface
      allocated_layout(Layout.present(parameters, viewport, R.prepare(surface)), application, generation, realization, surface)

def observes_layout(+environment: Design.Environment, +application: Platform.State,
  +generation: Nat, +realization: Rendered.State, +font_generation: Nat, +scale: T.Scale, +metric: T.Metric,
  +content_cache: +List<T.Measured>, valid: {T.valid_body(metric) == True{} : Bool}) ->
  Rule.PreparationClaim(CS.prepare(content_cache, Model.appearance_surface(Model.observed_surface(Model.State{application, generation, realization, environment, F.Ready{font_generation, scale, metric, content_cache}}), environment, F.Ready{font_generation, scale, metric, content_cache})),
    ViewportSpace.parameters(scale, metric), Model.environment_viewport(environment),
    Model.observe(Model.State{application, generation, realization, environment, F.Ready{font_generation, scale, metric, content_cache}})):
  Design.Environment{viewport, dark, root} = environment
  preparation_layout(CS.prepare(content_cache, Appearance.present(Order.ordered_surface(Model.surface(application)), dark, scale)),
    ViewportSpace.parameters(scale, metric), viewport, application, generation, realization)

def awaiting_scene(application: Platform.State, generation: Nat, realization: Rendered.State,
  environment: Design.Environment, font_generation: Nat, scale: T.Scale, surface: UI.Surface) ->
  {Model.scene_for_surface(Model.State{application, generation, realization, environment, F.Pending{font_generation, scale}}, surface) == Model.AwaitingTypography{} : Model.SceneOutcome}:
  Design.Environment{viewport, dark, root} = environment
  {==}

def failed_scene(application: Platform.State, generation: Nat, realization: Rendered.State,
  environment: Design.Environment, font_generation: Nat, scale: T.Scale, surface: UI.Surface) ->
  {Model.scene_for_surface(Model.State{application, generation, realization, environment, F.Failed{font_generation, scale}}, surface) == Model.FailedTypography{} : Model.SceneOutcome}:
  Design.Environment{viewport, dark, root} = environment
  {==}

def realized_environment(decision: Platform.Decision, generation: Nat, +environment: Design.Environment, font: F.State) ->
  {Rule.decision_environment(Model.realized(decision, generation, environment, font)) == environment : Design.Environment}:
  Platform.Decision{product, platform, effects} = decision
  {==}

def invalidation_preserves_environment(+decision: Platform.Decision, +generation: Nat,
  +environment: Design.Environment, +font: F.State) ->
  {Rule.decision_environment(Model.invalidate(decision, generation, environment, font)) == environment : Design.Environment}:
  realized_environment(Model.calibrated(decision, environment, F.retag(font, generation)), generation, environment, F.retag(font, generation))

def environment_observed_stores_environment(+environment: Design.Environment, current_environment: Design.Environment,
  +application: Platform.State, +generation: Nat, realization: Rendered.State, font: F.State) ->
  {Rule.decision_environment(Model.step(Model.EnvironmentObserved{environment}, Model.State{application, generation, realization, current_environment, font})) == environment : Design.Environment}:
  invalidation_preserves_environment(Platform.Decision{Platform.unchanged(Rule.original_core(application)), Rule.original_platform(application), Nil{}},
    (generation + 1n : Nat), environment, F.begin((generation + 1n : Nat), Model.environment_root(environment)))

def frame_preserves_environment(+environment: Design.Environment, received: Nat, frame: Rendered.Frame,
  application: Platform.State, generation: Nat, realization: Rendered.State, font: F.State) ->
  {Rule.decision_environment(Model.step(Model.FrameObserved{received, frame}, Model.State{application, generation, realization, environment, font})) == environment : Design.Environment}:
  Platform.State{core, platform} = application
  {==}

def element_preserves_environment(+environment: Design.Environment, key: String, gesture: UI.Gesture,
  application: Platform.State, +generation: Nat, realization: Rendered.State, +font: F.State) ->
  {Rule.decision_environment(Model.step(Model.ElementInput{key, gesture}, Model.State{application, generation, realization, environment, font})) == environment : Design.Environment}:
  Platform.State{core, +platform} = application
  invalidation_preserves_environment(Platform.after_core(UI.interact(Model.capacity(platform), key, gesture, core), platform),
    (generation + 1n : Nat), environment, font)

def legacy_capacity_uses_layout(supplied: View.Capacity, +environment: Design.Environment, +application: Platform.State, +font: F.State) ->
  {Model.observed_platform_input(Platform.CapacityObserved{supplied}, environment, font, application) ==
    Platform.CapacityObserved{Model.font_capacity(font, environment, application)} : Platform.Input}:
  {==}

def same_capacity_identity(+first: View.Capacity, +second: View.Capacity,
  same: {Platform.same_capacity(first, second) == True{} : Bool}) -> {first == second : View.Capacity}:
  match first second:
    case View.Capacity{False{}, False{}} View.Capacity{False{}, False{}}: {==}
    case View.Capacity{False{}, False{}} View.Capacity{False{}, True{}}: Proof_space.impossible({View.Capacity{False{}, False{}} == View.Capacity{False{}, True{}} : View.Capacity}, same)
    case View.Capacity{False{}, False{}} View.Capacity{True{}, False{}}: Proof_space.impossible({View.Capacity{False{}, False{}} == View.Capacity{True{}, False{}} : View.Capacity}, same)
    case View.Capacity{False{}, False{}} View.Capacity{True{}, True{}}: Proof_space.impossible({View.Capacity{False{}, False{}} == View.Capacity{True{}, True{}} : View.Capacity}, same)
    case View.Capacity{False{}, True{}} View.Capacity{False{}, False{}}: Proof_space.impossible({View.Capacity{False{}, True{}} == View.Capacity{False{}, False{}} : View.Capacity}, same)
    case View.Capacity{False{}, True{}} View.Capacity{False{}, True{}}: {==}
    case View.Capacity{False{}, True{}} View.Capacity{True{}, False{}}: Proof_space.impossible({View.Capacity{False{}, True{}} == View.Capacity{True{}, False{}} : View.Capacity}, same)
    case View.Capacity{False{}, True{}} View.Capacity{True{}, True{}}: Proof_space.impossible({View.Capacity{False{}, True{}} == View.Capacity{True{}, True{}} : View.Capacity}, same)
    case View.Capacity{True{}, False{}} View.Capacity{False{}, False{}}: Proof_space.impossible({View.Capacity{True{}, False{}} == View.Capacity{False{}, False{}} : View.Capacity}, same)
    case View.Capacity{True{}, False{}} View.Capacity{False{}, True{}}: Proof_space.impossible({View.Capacity{True{}, False{}} == View.Capacity{False{}, True{}} : View.Capacity}, same)
    case View.Capacity{True{}, False{}} View.Capacity{True{}, False{}}: {==}
    case View.Capacity{True{}, False{}} View.Capacity{True{}, True{}}: Proof_space.impossible({View.Capacity{True{}, False{}} == View.Capacity{True{}, True{}} : View.Capacity}, same)
    case View.Capacity{True{}, True{}} View.Capacity{False{}, False{}}: Proof_space.impossible({View.Capacity{True{}, True{}} == View.Capacity{False{}, False{}} : View.Capacity}, same)
    case View.Capacity{True{}, True{}} View.Capacity{False{}, True{}}: Proof_space.impossible({View.Capacity{True{}, True{}} == View.Capacity{False{}, True{}} : View.Capacity}, same)
    case View.Capacity{True{}, True{}} View.Capacity{True{}, False{}}: Proof_space.impossible({View.Capacity{True{}, True{}} == View.Capacity{True{}, False{}} : View.Capacity}, same)
    case View.Capacity{True{}, True{}} View.Capacity{True{}, True{}}: {==}

def changed_capacity_actual(decision: Platform.Decision, +requested: View.Capacity) ->
  {Rule.platform_decision_capacity(Platform.changed_capacity(decision, requested)) == requested : View.Capacity}:
  Platform.Decision{Core.Decision{Core.State{application, services}, reply, runtime, interaction, service_effects, durable},
    Platform.Platform{readers, editors, focused, ticket, reduced, old_capacity, scope}, effects} = decision
  {==}

def retained_capacity_actual(same: Bool, +decision: Platform.Decision, +requested: View.Capacity,
  binding: {Platform.same_capacity(Rule.platform_decision_capacity(decision), requested) == same : Bool}) ->
  {Rule.platform_decision_capacity(Platform.retained_capacity(same, decision, requested)) == requested : View.Capacity}:
  match same:
    case True{}: same_capacity_identity(Rule.platform_decision_capacity(decision), requested, binding)
    case False{}: changed_capacity_actual(decision, requested)

def reflow_sets_capacity(+decision: Platform.Decision, +requested: View.Capacity) ->
  {Rule.platform_decision_capacity(Platform.reflow_capacity(decision, requested)) == requested : View.Capacity}:
  Platform.Decision{product, Platform.Platform{readers, editors, focused, ticket, reduced, +old_capacity, scope}, effects} = decision
  retained_capacity_actual(Platform.same_capacity(old_capacity, requested),
    Platform.Decision{product, Platform.Platform{readers, editors, focused, ticket, reduced, old_capacity, scope}, effects}, requested, {==})

def realized_capacity(decision: Platform.Decision, generation: Nat, environment: Design.Environment, font: F.State) ->
  {Rule.decision_capacity(Model.realized(decision, generation, environment, font)) == Rule.platform_decision_capacity(decision) : View.Capacity}:
  Platform.Decision{Core.Decision{core, reply, runtime, interaction, service_effects, durable}, platform, effects} = decision
  {==}

def invalidation_sets_capacity(+decision: Platform.Decision, +generation: Nat, +environment: Design.Environment, +font: F.State) ->
  {Rule.decision_capacity(Model.invalidate(decision, generation, environment, font)) ==
    Model.font_capacity(F.retag(font, generation), environment, Platform.next(decision)) : View.Capacity}:
  Equal.trans(View.Capacity, Rule.decision_capacity(Model.invalidate(decision, generation, environment, font)),
    Rule.platform_decision_capacity(Model.calibrated(decision, environment, F.retag(font, generation))),
    Model.font_capacity(F.retag(font, generation), environment, Platform.next(decision)),
    realized_capacity(Model.calibrated(decision, environment, F.retag(font, generation)), generation, environment, F.retag(font, generation)),
    reflow_sets_capacity(decision, Model.font_capacity(F.retag(font, generation), environment, Platform.next(decision))))

def environment_observed_sets_capacity(+environment: Design.Environment, current_environment: Design.Environment,
  +application: Platform.State, +generation: Nat, realization: Rendered.State, font: F.State) ->
  {Rule.decision_capacity(Model.step(Model.EnvironmentObserved{environment}, Model.State{application, generation, realization, current_environment, font})) == View.Capacity{False{}, False{}} : View.Capacity}:
  Design.Environment{viewport, dark, root} = environment
  invalidation_sets_capacity(Platform.Decision{Platform.unchanged(Rule.original_core(application)), Rule.original_platform(application), Nil{}},
    (generation + 1n : Nat), Design.Environment{viewport, dark, root}, F.begin((generation + 1n : Nat), root))

def Rule.evidence():
  Rule.Requirements{observes_semantic_surface, observes_layout, awaiting_scene, failed_scene,
    +environment => current_environment => +application => +generation => realization => font =>
      Rules_model_rules.realization_preserves_product(Platform.Decision{Platform.unchanged(Rule.original_core(application)), Rule.original_platform(application), Nil{}},
        (generation + 1n : Nat), environment, F.begin((generation + 1n : Nat), Model.environment_root(environment)))
    , environment_observed_stores_environment,
    frame_preserves_environment, element_preserves_environment, Rules_model_rules.frame_emits_no_effects,
    reflow_sets_capacity, invalidation_sets_capacity, environment_observed_sets_capacity, legacy_capacity_uses_layout}
