import Base
import ../core/SYSTEM.bend as Core
import ../core/interface.bend as UI
import ../core/ui-world.bend as View
import ./MODEL.bend as Model
import ./design.bend as Design
import ./layout.bend as Layout
import ./layout-laws.bend as LayoutLaws
import ./appearance-laws.bend as AppearanceLaws
import ./platform.bend as Platform
import ./rendered.bend as Rendered
import ./presentation-order.bend as Order
import ./font-observation.bend as F
import ./typography.bend as T
import ./viewport-space.bend as ViewportSpace
import ./focus.bend as Focus
import ./space-laws.bend as SpaceLaws

def scene_layout(scene: Model.Scene) -> Design.Layout:
  Model.Scene{surface, platform, generation, realization, layout} = scene
  layout

def scene_surface(scene: Model.Scene) -> UI.Surface:
  Model.Scene{surface, platform, generation, realization, layout} = scene
  Design.semantic_surface(surface)

# An unready outcome contains no scene. Ready outcomes must preserve the actual
# semantic surface; Pending/Failed/Unsupported branches have separate equations.
def SemanticClaim(outcome: Model.SceneOutcome, surface: UI.Surface) -> Type:
  match outcome:
    case Model.ReadyScene{scene}: {scene_surface(scene) == surface : UI.Surface}
    case _: Unit

def allocated_semantics(+outcome: Layout.Outcome, application: Platform.State, generation: Nat,
  realization: Rendered.State, +surface: UI.Surface, +dark: Bool, +scale: T.Scale) ->
  SemanticClaim(Model.allocated_scene(outcome, application, generation, realization, surface, dark, scale), surface):
  match outcome:
    case Layout.LayoutReady{layout}: AppearanceLaws.present_preserves_semantics(surface, dark, scale)
    case Layout.LayoutUnsupported{required, available}: Unit{}

def scene_for_surface_preserves_semantics(state: Model.State, +surface: UI.Surface) ->
  SemanticClaim(Model.scene_for_surface(state, surface), surface):
  Model.State{application, generation, realization, Design.Environment{viewport, dark, root}, font} = state
  match font:
    case F.Pending{font_generation, scale}: Unit{}
    case F.Failed{font_generation, scale}: Unit{}
    case F.Ready{font_generation, +scale, metric}:
      allocated_semantics(Layout.present(ViewportSpace.parameters(scale, metric), viewport, surface),
        application, generation, realization, surface, dark, scale)

def observes_semantic_surface(+state: Model.State) ->
  SemanticClaim(Model.observe(state), Model.observed_surface(state)):
  scene_for_surface_preserves_semantics(state, Model.observed_surface(state))

def PreparedReadyClaim(outcome: Model.SceneOutcome, layout: Design.Layout) -> Type:
  match outcome:
    case Model.ReadyScene{scene}: {scene_layout(scene) == layout : Design.Layout}
    case _: Empty

def PreparedClaim(outcome: Model.SceneOutcome, expected: Layout.Outcome) -> Type:
  match expected:
    case Layout.LayoutReady{layout}: PreparedReadyClaim(outcome, layout)
    case Layout.LayoutUnsupported{required, available}:
      {outcome == Model.UnsupportedSpace{required, available} : Model.SceneOutcome}

def allocated_layout(+outcome: Layout.Outcome, application: Platform.State, generation: Nat,
  realization: Rendered.State, surface: UI.Surface, dark: Bool, scale: T.Scale) ->
  PreparedClaim(Model.allocated_scene(outcome, application, generation, realization, surface, dark, scale), outcome):
  match outcome:
    case Layout.LayoutReady{layout}: {==}
    case Layout.LayoutUnsupported{required, available}: {==}

def observes_layout(environment: Design.Environment, +application: Platform.State,
  generation: Nat, realization: Rendered.State, font_generation: Nat, +scale: T.Scale, +metric: T.Metric,
  valid: {T.valid_body(metric) == True{} : Bool}) ->
  PreparedClaim(Model.observe(Model.State{application, generation, realization, environment, F.Ready{font_generation, scale, metric}}),
    Layout.present(ViewportSpace.parameters(scale, metric), Model.environment_viewport(environment), Order.ordered_surface(Model.surface(application)))):
  Design.Environment{viewport, dark, root} = environment
  allocated_layout(Layout.present(ViewportSpace.parameters(scale, metric), viewport, Order.ordered_surface(Model.surface(application))),
    application, generation, realization, Order.ordered_surface(Model.surface(application)), dark, scale)

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

def decision_state(decision: Model.Decision) -> Model.State:
  Model.Decision{state, product, effects} = decision
  state

def state_capacity(state: Model.State) -> View.Capacity:
  Model.State{Platform.State{core, platform}, generation, realization, environment, font} = state
  Model.capacity(platform)

def state_environment(state: Model.State) -> Design.Environment:
  Model.State{application, generation, realization, environment, font} = state
  environment

def decision_capacity(decision: Model.Decision) -> View.Capacity:
  state_capacity(decision_state(decision))

def decision_environment(decision: Model.Decision) -> Design.Environment:
  state_environment(decision_state(decision))

def realized_environment(decision: Platform.Decision, generation: Nat, +environment: Design.Environment, font: F.State) ->
  {decision_environment(Model.realized(decision, generation, environment, font)) == environment : Design.Environment}:
  Platform.Decision{product, platform, effects} = decision
  {==}

def invalidation_preserves_environment(+decision: Platform.Decision, +generation: Nat,
  +environment: Design.Environment, +font: F.State) ->
  {decision_environment(Model.invalidate(decision, generation, environment, font)) == environment : Design.Environment}:
  realized_environment(Model.calibrated(decision, environment, F.retag(font, generation)), generation, environment, F.retag(font, generation))

def original_core(application: Platform.State) -> Core.State:
  Model.model_core(application)

def original_platform(application: Platform.State) -> Platform.Platform:
  Model.model_platform(application)

def viewport_of(environment: Design.Environment) -> Design.Viewport:
  Design.Environment{viewport, system_dark, root} = environment
  viewport


def environment_observed_stores_environment(+environment: Design.Environment, current_environment: Design.Environment,
  +application: Platform.State, +generation: Nat, realization: Rendered.State, font: F.State) ->
  {decision_environment(Model.step(Model.EnvironmentObserved{environment}, Model.State{application, generation, realization, current_environment, font})) == environment : Design.Environment}:
  invalidation_preserves_environment(Platform.Decision{Platform.unchanged(original_core(application)), original_platform(application), Nil{}},
    (generation + 1n : Nat), environment, F.begin((generation + 1n : Nat), Model.environment_root(environment)))

def frame_preserves_environment(+environment: Design.Environment, received: Nat, frame: Rendered.Frame,
  application: Platform.State, generation: Nat, realization: Rendered.State, font: F.State) ->
  {decision_environment(Model.step(Model.FrameObserved{received, frame}, Model.State{application, generation, realization, environment, font})) == environment : Design.Environment}:
  Platform.State{core, platform} = application
  {==}

def element_preserves_environment(+environment: Design.Environment, key: String, gesture: UI.Gesture,
  application: Platform.State, +generation: Nat, realization: Rendered.State, +font: F.State) ->
  {decision_environment(Model.step(Model.ElementInput{key, gesture}, Model.State{application, generation, realization, environment, font})) == environment : Design.Environment}:
  Platform.State{core, +platform} = application
  invalidation_preserves_environment(Platform.after_core(UI.interact(Model.capacity(platform), key, gesture, core), platform),
    (generation + 1n : Nat), environment, font)

def legacy_capacity_uses_layout(supplied: View.Capacity, +environment: Design.Environment, +application: Platform.State, +font: F.State) ->
  {Model.observed_platform_input(Platform.CapacityObserved{supplied}, environment, font, application) ==
    Platform.CapacityObserved{Model.font_capacity(font, environment, application)} : Platform.Input}:
  {==}

def platform_decision_capacity(decision: Platform.Decision) -> View.Capacity:
  Platform.Decision{product, platform, effects} = decision
  Model.capacity(platform)

def same_capacity_identity(+first: View.Capacity, +second: View.Capacity,
  same: {Platform.same_capacity(first, second) == True{} : Bool}) -> {first == second : View.Capacity}:
  match first second:
    case View.Capacity{False{}, False{}} View.Capacity{False{}, False{}}: {==}
    case View.Capacity{False{}, False{}} View.Capacity{False{}, True{}}: SpaceLaws.impossible({View.Capacity{False{}, False{}} == View.Capacity{False{}, True{}} : View.Capacity}, same)
    case View.Capacity{False{}, False{}} View.Capacity{True{}, False{}}: SpaceLaws.impossible({View.Capacity{False{}, False{}} == View.Capacity{True{}, False{}} : View.Capacity}, same)
    case View.Capacity{False{}, False{}} View.Capacity{True{}, True{}}: SpaceLaws.impossible({View.Capacity{False{}, False{}} == View.Capacity{True{}, True{}} : View.Capacity}, same)
    case View.Capacity{False{}, True{}} View.Capacity{False{}, False{}}: SpaceLaws.impossible({View.Capacity{False{}, True{}} == View.Capacity{False{}, False{}} : View.Capacity}, same)
    case View.Capacity{False{}, True{}} View.Capacity{False{}, True{}}: {==}
    case View.Capacity{False{}, True{}} View.Capacity{True{}, False{}}: SpaceLaws.impossible({View.Capacity{False{}, True{}} == View.Capacity{True{}, False{}} : View.Capacity}, same)
    case View.Capacity{False{}, True{}} View.Capacity{True{}, True{}}: SpaceLaws.impossible({View.Capacity{False{}, True{}} == View.Capacity{True{}, True{}} : View.Capacity}, same)
    case View.Capacity{True{}, False{}} View.Capacity{False{}, False{}}: SpaceLaws.impossible({View.Capacity{True{}, False{}} == View.Capacity{False{}, False{}} : View.Capacity}, same)
    case View.Capacity{True{}, False{}} View.Capacity{False{}, True{}}: SpaceLaws.impossible({View.Capacity{True{}, False{}} == View.Capacity{False{}, True{}} : View.Capacity}, same)
    case View.Capacity{True{}, False{}} View.Capacity{True{}, False{}}: {==}
    case View.Capacity{True{}, False{}} View.Capacity{True{}, True{}}: SpaceLaws.impossible({View.Capacity{True{}, False{}} == View.Capacity{True{}, True{}} : View.Capacity}, same)
    case View.Capacity{True{}, True{}} View.Capacity{False{}, False{}}: SpaceLaws.impossible({View.Capacity{True{}, True{}} == View.Capacity{False{}, False{}} : View.Capacity}, same)
    case View.Capacity{True{}, True{}} View.Capacity{False{}, True{}}: SpaceLaws.impossible({View.Capacity{True{}, True{}} == View.Capacity{False{}, True{}} : View.Capacity}, same)
    case View.Capacity{True{}, True{}} View.Capacity{True{}, False{}}: SpaceLaws.impossible({View.Capacity{True{}, True{}} == View.Capacity{True{}, False{}} : View.Capacity}, same)
    case View.Capacity{True{}, True{}} View.Capacity{True{}, True{}}: {==}

def changed_capacity_actual(decision: Platform.Decision, +requested: View.Capacity) ->
  {platform_decision_capacity(Platform.changed_capacity(decision, requested)) == requested : View.Capacity}:
  Platform.Decision{Core.Decision{Core.State{application, services}, reply, runtime, interaction, service_effects, durable},
    Platform.Platform{readers, editors, focused, ticket, reduced, old_capacity, scope}, effects} = decision
  {==}

def retained_capacity_actual(same: Bool, +decision: Platform.Decision, +requested: View.Capacity,
  binding: {Platform.same_capacity(platform_decision_capacity(decision), requested) == same : Bool}) ->
  {platform_decision_capacity(Platform.retained_capacity(same, decision, requested)) == requested : View.Capacity}:
  match same:
    case True{}: same_capacity_identity(platform_decision_capacity(decision), requested, binding)
    case False{}: changed_capacity_actual(decision, requested)

def reflow_sets_capacity(+decision: Platform.Decision, +requested: View.Capacity) ->
  {platform_decision_capacity(Platform.reflow_capacity(decision, requested)) == requested : View.Capacity}:
  Platform.Decision{product, Platform.Platform{readers, editors, focused, ticket, reduced, +old_capacity, scope}, effects} = decision
  retained_capacity_actual(Platform.same_capacity(old_capacity, requested),
    Platform.Decision{product, Platform.Platform{readers, editors, focused, ticket, reduced, old_capacity, scope}, effects}, requested, {==})

def realized_capacity(decision: Platform.Decision, generation: Nat, environment: Design.Environment, font: F.State) ->
  {decision_capacity(Model.realized(decision, generation, environment, font)) == platform_decision_capacity(decision) : View.Capacity}:
  Platform.Decision{Core.Decision{core, reply, runtime, interaction, service_effects, durable}, platform, effects} = decision
  {==}

def invalidation_sets_capacity(+decision: Platform.Decision, +generation: Nat, +environment: Design.Environment, +font: F.State) ->
  {decision_capacity(Model.invalidate(decision, generation, environment, font)) ==
    Model.font_capacity(F.retag(font, generation), environment, Platform.next(decision)) : View.Capacity}:
  Equal.trans(View.Capacity, decision_capacity(Model.invalidate(decision, generation, environment, font)),
    platform_decision_capacity(Model.calibrated(decision, environment, F.retag(font, generation))),
    Model.font_capacity(F.retag(font, generation), environment, Platform.next(decision)),
    realized_capacity(Model.calibrated(decision, environment, F.retag(font, generation)), generation, environment, F.retag(font, generation)),
    reflow_sets_capacity(decision, Model.font_capacity(F.retag(font, generation), environment, Platform.next(decision))))

def environment_observed_sets_capacity(+environment: Design.Environment, current_environment: Design.Environment,
  +application: Platform.State, +generation: Nat, realization: Rendered.State, font: F.State) ->
  {decision_capacity(Model.step(Model.EnvironmentObserved{environment}, Model.State{application, generation, realization, current_environment, font})) == View.Capacity{False{}, False{}} : View.Capacity}:
  Design.Environment{viewport, dark, root} = environment
  invalidation_sets_capacity(Platform.Decision{Platform.unchanged(original_core(application)), original_platform(application), Nil{}},
    (generation + 1n : Nat), Design.Environment{viewport, dark, root}, F.begin((generation + 1n : Nat), root))

type Requirements is Type:
  Requirements{
    observes_semantic_surface: @+state:Model.State -> SemanticClaim(Model.observe(state), Model.observed_surface(state)),
    observes_layout: @environment:Design.Environment -> @+application:Platform.State -> @generation:Nat -> @realization:Rendered.State ->
      @font_generation:Nat -> @+scale:T.Scale -> @+metric:T.Metric -> @valid:{T.valid_body(metric) == True{} : Bool} ->
      PreparedClaim(Model.observe(Model.State{application, generation, realization, environment, F.Ready{font_generation, scale, metric}}),
        Layout.present(ViewportSpace.parameters(scale, metric), Model.environment_viewport(environment), Order.ordered_surface(Model.surface(application)))),
    pending_is_awaiting: @application:Platform.State -> @generation:Nat -> @realization:Rendered.State -> @environment:Design.Environment -> @font_generation:Nat -> @scale:T.Scale -> @surface:UI.Surface ->
      {Model.scene_for_surface(Model.State{application, generation, realization, environment, F.Pending{font_generation, scale}}, surface) == Model.AwaitingTypography{} : Model.SceneOutcome},
    failed_is_failed: @application:Platform.State -> @generation:Nat -> @realization:Rendered.State -> @environment:Design.Environment -> @font_generation:Nat -> @scale:T.Scale -> @surface:UI.Surface ->
      {Model.scene_for_surface(Model.State{application, generation, realization, environment, F.Failed{font_generation, scale}}, surface) == Model.FailedTypography{} : Model.SceneOutcome},
    environment_observed_preserves_core: @+environment:Design.Environment -> @current_environment:Design.Environment -> @+application:Platform.State -> @+generation:Nat -> @realization:Rendered.State -> @font:F.State ->
      {Model.product(Model.step(Model.EnvironmentObserved{environment}, Model.State{application, generation, realization, current_environment, font})) == Platform.unchanged(original_core(application)) : Core.Decision},
    environment_observed_stores_environment: @+environment:Design.Environment -> @current_environment:Design.Environment -> @+application:Platform.State -> @+generation:Nat -> @realization:Rendered.State -> @font:F.State ->
      {decision_environment(Model.step(Model.EnvironmentObserved{environment}, Model.State{application, generation, realization, current_environment, font})) == environment : Design.Environment},
    frame_preserves_environment: @+environment:Design.Environment -> @received:Nat -> @frame:Rendered.Frame -> @application:Platform.State -> @generation:Nat -> @realization:Rendered.State -> @font:F.State ->
      {decision_environment(Model.step(Model.FrameObserved{received, frame}, Model.State{application, generation, realization, environment, font})) == environment : Design.Environment},
    element_preserves_environment: @+environment:Design.Environment -> @key:String -> @gesture:UI.Gesture -> @application:Platform.State -> @+generation:Nat -> @realization:Rendered.State -> @+font:F.State ->
      {decision_environment(Model.step(Model.ElementInput{key, gesture}, Model.State{application, generation, realization, environment, font})) == environment : Design.Environment},
    frame_has_no_effects: @received:Nat -> @frame:Rendered.Frame -> @application:Platform.State -> @generation:Nat -> @realization:Rendered.State -> @environment:Design.Environment -> @font:F.State ->
      {Model.effects(Model.step(Model.FrameObserved{received, frame}, Model.State{application, generation, realization, environment, font})) == Nil{} : +List<Model.Effect>},
    reflow_sets_requested_capacity: @+decision:Platform.Decision -> @+requested:View.Capacity ->
      {platform_decision_capacity(Platform.reflow_capacity(decision, requested)) == requested : View.Capacity},
    invalidation_sets_admitted_capacity: @+decision:Platform.Decision -> @+generation:Nat -> @+environment:Design.Environment -> @+font:F.State ->
      {decision_capacity(Model.invalidate(decision, generation, environment, font)) == Model.font_capacity(F.retag(font, generation), environment, Platform.next(decision)) : View.Capacity},
    environment_observed_sets_capacity: @+environment:Design.Environment -> @current_environment:Design.Environment -> @+application:Platform.State -> @+generation:Nat -> @realization:Rendered.State -> @font:F.State ->
      {decision_capacity(Model.step(Model.EnvironmentObserved{environment}, Model.State{application, generation, realization, current_environment, font})) == View.Capacity{False{}, False{}} : View.Capacity},
    supplied_capacity_is_not_trusted: @supplied:View.Capacity -> @+environment:Design.Environment -> @+application:Platform.State -> @+font:F.State ->
      {Model.observed_platform_input(Platform.CapacityObserved{supplied}, environment, font, application) == Platform.CapacityObserved{Model.font_capacity(font, environment, application)} : Platform.Input}}

def evidence() -> Requirements:
  Requirements{observes_semantic_surface, observes_layout, awaiting_scene, failed_scene,
    +environment => current_environment => +application => +generation => realization => font =>
      Model.realization_preserves_product(Platform.Decision{Platform.unchanged(original_core(application)), original_platform(application), Nil{}},
        (generation + 1n : Nat), environment, F.begin((generation + 1n : Nat), Model.environment_root(environment)))
    , environment_observed_stores_environment,
    frame_preserves_environment, element_preserves_environment, Model.frame_emits_no_effects,
    reflow_sets_capacity, invalidation_sets_capacity, environment_observed_sets_capacity, legacy_capacity_uses_layout}
