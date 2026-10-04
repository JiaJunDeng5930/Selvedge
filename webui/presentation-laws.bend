import Base
import ../core/SYSTEM.bend as Core
import ../core/interface.bend as UI
import ../core/ui-world.bend as View
import ./MODEL.bend as Model
import ./design.bend as Design
import ./layout.bend as Layout
import ./platform.bend as Platform
import ./rendered.bend as Rendered
import ./font-observation.bend as F
import ./typography.bend as T
import ./viewport-space.bend as ViewportSpace
import ./content-space.bend as CS
import ./renderer.bend as R


def scene_layout(scene: Model.Scene) -> Design.Layout:
  Model.Scene{surface, platform, generation, realization, layout} = scene
  layout

def scene_surface(scene: Model.Scene) -> UI.Surface:
  Design.semantic_surface(Model.scene_surface(scene))

# An unready outcome contains no scene. Ready outcomes must preserve the actual
# semantic surface; Pending/Failed/Unsupported branches have separate equations.
def SemanticClaim(outcome: Model.SceneOutcome, surface: UI.Surface) -> Type:
  match outcome:
    case Model.ReadyScene{scene}: {scene_surface(scene) == surface : UI.Surface}
    case _: Unit

def PreparedReadyClaim(outcome: Model.SceneOutcome, layout: Design.Layout) -> Type:
  match outcome:
    case Model.ReadyScene{scene}: {scene_layout(scene) == layout : Design.Layout}
    case _: Empty

def PreparedClaim(outcome: Model.SceneOutcome, expected: Layout.Outcome) -> Type:
  match expected:
    case Layout.LayoutReady{layout}: PreparedReadyClaim(outcome, layout)
    case Layout.LayoutUnsupported{required, available}:
      {outcome == Model.UnsupportedSpace{required, available} : Model.SceneOutcome}

def PreparationClaim(preparation: CS.Outcome, parameters: Design.LayoutParameters, viewport: Design.Viewport, actual: Model.SceneOutcome) -> Type:
  match preparation:
    case CS.AwaitingContent{missing}: {actual == Model.AwaitingTypography{} : Model.SceneOutcome}
    case CS.Prepared{surface}: PreparedClaim(actual, Layout.present(parameters, viewport, R.prepare(surface)))

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

def original_core(application: Platform.State) -> Core.State:
  Model.model_core(application)

def original_platform(application: Platform.State) -> Platform.Platform:
  Model.model_platform(application)

def viewport_of(environment: Design.Environment) -> Design.Viewport:
  Design.Environment{viewport, system_dark, root} = environment
  viewport


def platform_decision_capacity(decision: Platform.Decision) -> View.Capacity:
  Platform.Decision{product, platform, effects} = decision
  Model.capacity(platform)

type Requirements is Type:
  Requirements{
    observes_semantic_surface: @+state:Model.State -> SemanticClaim(Model.observe(state), Model.observed_surface(state)),
    observes_layout: @+environment:Design.Environment -> @+application:Platform.State -> @+generation:Nat -> @+realization:Rendered.State ->
      @+font_generation:Nat -> @+scale:T.Scale -> @+metric:T.Metric -> @+content_cache:+List<T.Measured> -> @valid:{T.valid_body(metric) == True{} : Bool} ->
      PreparationClaim(CS.prepare(content_cache, Model.appearance_surface(Model.observed_surface(Model.State{application, generation, realization, environment, F.Ready{font_generation, scale, metric, content_cache}}), environment, F.Ready{font_generation, scale, metric, content_cache})),
        ViewportSpace.parameters(scale, metric), Model.environment_viewport(environment), Model.observe(Model.State{application, generation, realization, environment, F.Ready{font_generation, scale, metric, content_cache}})),
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

law evidence:
  Requirements
