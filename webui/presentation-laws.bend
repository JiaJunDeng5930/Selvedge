import Base
import ../core/SYSTEM.bend as Core
import ../core/interface.bend as UI
import ../core/ui-world.bend as View
import ./MODEL.bend as Model
import ./design.bend as Design
import ./layout.bend as Layout
import ./appearance.bend as Appearance
import ./appearance-laws.bend as AppearanceLaws
import ./platform.bend as Platform
import ./rendered.bend as Rendered
import ./presentation-order.bend as Order

def scene_layout(scene: Model.Scene) -> Design.Layout:
  Model.Scene{surface, platform, generation, realization, layout} = scene
  layout

def scene_surface(scene: Model.Scene) -> UI.Surface:
  Model.Scene{surface, platform, generation, realization, layout} = scene
  Design.semantic_surface(surface)

def decision_state(decision: Model.Decision) -> Model.State:
  Model.Decision{state, product, effects} = decision
  state

def state_capacity(state: Model.State) -> View.Capacity:
  Model.State{Platform.State{+core, platform}, +generation, +realization, +environment} = state
  Model.capacity(platform)

def state_environment(state: Model.State) -> Design.Environment:
  Model.State{+application, +generation, +realization, environment} = state
  environment

def decision_capacity(decision: Model.Decision) -> View.Capacity:
  state_capacity(decision_state(decision))

def decision_environment(decision: Model.Decision) -> Design.Environment:
  state_environment(decision_state(decision))

def invalidation_preserves_environment(+decision: Platform.Decision, generation: Nat,
  +environment: Design.Environment) ->
  {decision_environment(Model.invalidate(decision, generation, environment)) == environment : Design.Environment}:
  match decision:
    case Platform.Decision{+product, +platform, +effects}: {==}

def original_core(application: Platform.State) -> Core.State:
  Platform.State{core, platform} = application
  core

def viewport_of(environment: Design.Environment) -> Design.Viewport:
  Design.Environment{viewport, system_dark} = environment
  viewport

def system_dark_of(environment: Design.Environment) -> Bool:
  Design.Environment{viewport, system_dark} = environment
  system_dark

def observes_layout_law(-environment: Design.Environment, -application: Platform.State, -generation: Nat, -realization: Rendered.State) -> Type:
  {scene_layout(Model.observe(Model.State{application, generation, realization, environment})) ==
    Layout.present(viewport_of(environment), Order.ordered_surface(Model.surface(application))) : Design.Layout}

def observes_layout(environment: Design.Environment, application: Platform.State,
  generation: Nat, realization: Rendered.State) -> observes_layout_law(environment, application, generation, realization):
  match environment:
    case Design.Environment{viewport, system_dark}: {==}

def observes_prepared_scene(environment: Design.Environment, application: Platform.State,
  generation: Nat, realization: Rendered.State) ->
  {Model.observe(Model.State{application, generation, realization, environment}) ==
    Model.Scene{Appearance.present(Order.ordered_surface(Model.surface(application)), system_dark_of(environment)),
      Platform.observe(application), generation, realization,
      Layout.present(viewport_of(environment), Order.ordered_surface(Model.surface(application)))} : Model.Scene}:
  match environment:
    case Design.Environment{viewport, system_dark}: {==}

def scene_for_surface_preserves_semantics(state: Model.State, surface: UI.Surface) ->
  {scene_surface(Model.scene_for_surface(state, surface)) == surface : UI.Surface}:
  match state:
    case Model.State{application, generation, realization, Design.Environment{viewport, system_dark}}:
      AppearanceLaws.present_preserves_semantics(surface, system_dark)

def observes_semantic_surface(+state: Model.State) ->
  {scene_surface(Model.observe(state)) == Model.observed_surface(state) : UI.Surface}:
  scene_for_surface_preserves_semantics(state, Model.observed_surface(state))

def environment_observed_preserves_core_law(-environment: Design.Environment, -current_environment: Design.Environment, -application: Platform.State, -generation: Nat, -realization: Rendered.State) -> Type:
  {Model.product(Model.step(Model.EnvironmentObserved{environment},
      Model.State{application, generation, realization, current_environment})) ==
      Platform.unchanged(original_core(application)) : Core.Decision}

def environment_observed_preserves_core(environment: Design.Environment, current_environment: Design.Environment,
  application: Platform.State, generation: Nat, realization: Rendered.State) -> environment_observed_preserves_core_law(environment, current_environment, application, generation, realization):
  match environment:
    case Design.Environment{viewport, system_dark}:
      match application:
        case Platform.State{Core.State{+core_application, +services},
          Platform.Platform{+readers, +editors, +focused, +ticket, +reduced, +capacity, +scope}}:
          {==}

def environment_observed_sets_capacity_law(-environment: Design.Environment, -current_environment: Design.Environment, -application: Platform.State, -generation: Nat, -realization: Rendered.State) -> Type:
  {decision_capacity(Model.step(Model.EnvironmentObserved{environment},
      Model.State{application, generation, realization, current_environment})) ==
      Layout.capacity(viewport_of(environment)) : View.Capacity}

def environment_observed_sets_capacity(environment: Design.Environment, current_environment: Design.Environment,
  application: Platform.State, generation: Nat, realization: Rendered.State) -> environment_observed_sets_capacity_law(environment, current_environment, application, generation, realization):
  match environment:
    case Design.Environment{viewport, system_dark}:
      match application:
        case Platform.State{Core.State{+core_application, +services},
          Platform.Platform{+readers, +editors, +focused, +ticket, +reduced, +capacity, +scope}}:
          {==}

def environment_observed_stores_environment(environment: Design.Environment, current_environment: Design.Environment,
  application: Platform.State, generation: Nat, realization: Rendered.State) ->
  {decision_environment(Model.step(Model.EnvironmentObserved{environment},
    Model.State{application, generation, realization, current_environment})) == environment : Design.Environment}:
  match environment:
    case Design.Environment{viewport, system_dark}:
      match application:
        case Platform.State{Core.State{+core_application, +services},
          Platform.Platform{+readers, +editors, +focused, +ticket, +reduced, +capacity, +scope}}:
          {==}

def frame_preserves_environment(environment: Design.Environment, received: Nat, frame: Rendered.Frame,
  application: Platform.State, generation: Nat, realization: Rendered.State) ->
  {decision_environment(Model.step(Model.FrameObserved{received, frame},
    Model.State{application, generation, realization, environment})) == environment : Design.Environment}:
  match environment:
    case Design.Environment{viewport, system_dark}:
      match application:
        case Platform.State{Core.State{+core_application, +services},
          Platform.Platform{+readers, +editors, +focused, +ticket, +reduced, +capacity, +scope}}:
          {==}

def element_preserves_environment(environment: Design.Environment, key: String, gesture: UI.Gesture,
  application: Platform.State, generation: Nat, realization: Rendered.State) ->
  {decision_environment(Model.step(Model.ElementInput{key, gesture},
    Model.State{application, generation, realization, environment})) == environment : Design.Environment}:
  match environment:
    case Design.Environment{viewport, system_dark}:
      match application:
        case Platform.State{Core.State{+core_application, +services},
          Platform.Platform{+readers, +editors, +focused, +ticket, +reduced, +capacity, +scope}}:
          invalidation_preserves_environment(
            Platform.after_core(UI.interact(capacity, key, gesture, Core.State{core_application, services}),
              Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope}),
            (generation + 1n : Nat), environment)



def legacy_capacity_uses_layout_law(-supplied: View.Capacity, -environment: Design.Environment, -application: Platform.State, -generation: Nat, -realization: Rendered.State) -> Type:
  {decision_capacity(Model.step(Model.PlatformInput{Platform.CapacityObserved{supplied}},
      Model.State{application, generation, realization, environment})) ==
      Layout.capacity(viewport_of(environment)) : View.Capacity}

def legacy_capacity_uses_layout(supplied: View.Capacity, environment: Design.Environment,
  application: Platform.State, generation: Nat, realization: Rendered.State) -> legacy_capacity_uses_layout_law(supplied, environment, application, generation, realization):
  match environment:
    case Design.Environment{viewport, system_dark}:
      match application:
        case Platform.State{Core.State{+core_application, +services},
          Platform.Platform{+readers, +editors, +focused, +ticket, +reduced, +capacity, +scope}}:
          {==}

type Requirements is Type:
  Requirements{
    observes_prepared_scene: @environment:Design.Environment -> @application:Platform.State ->
      @generation:Nat -> @realization:Rendered.State ->
      {Model.observe(Model.State{application, generation, realization, environment}) ==
        Model.Scene{Appearance.present(Order.ordered_surface(Model.surface(application)), system_dark_of(environment)),
          Platform.observe(application), generation, realization,
          Layout.present(viewport_of(environment), Order.ordered_surface(Model.surface(application)))} : Model.Scene},
    observes_semantic_surface: @state:Model.State ->
      {scene_surface(Model.observe(state)) == Model.observed_surface(state) : UI.Surface},
    observes_layout: @environment:Design.Environment -> @application:Platform.State ->
      @generation:Nat -> @realization:Rendered.State ->
      observes_layout_law(environment, application, generation, realization),
    environment_observed_preserves_core: @environment:Design.Environment -> @current_environment:Design.Environment ->
      @application:Platform.State -> @generation:Nat -> @realization:Rendered.State ->
      environment_observed_preserves_core_law(environment, current_environment, application, generation, realization),
    environment_observed_sets_capacity: @environment:Design.Environment -> @current_environment:Design.Environment ->
      @application:Platform.State -> @generation:Nat -> @realization:Rendered.State ->
      environment_observed_sets_capacity_law(environment, current_environment, application, generation, realization),
    environment_observed_stores_environment: @environment:Design.Environment -> @current_environment:Design.Environment ->
      @application:Platform.State -> @generation:Nat -> @realization:Rendered.State ->
      {decision_environment(Model.step(Model.EnvironmentObserved{environment},
        Model.State{application, generation, realization, current_environment})) == environment : Design.Environment},
    frame_preserves_environment: @environment:Design.Environment -> @received:Nat -> @frame:Rendered.Frame ->
      @application:Platform.State -> @generation:Nat -> @realization:Rendered.State ->
      {decision_environment(Model.step(Model.FrameObserved{received, frame},
        Model.State{application, generation, realization, environment})) == environment : Design.Environment},
    element_preserves_environment: @environment:Design.Environment -> @key:String -> @gesture:UI.Gesture ->
      @application:Platform.State -> @generation:Nat -> @realization:Rendered.State ->
      {decision_environment(Model.step(Model.ElementInput{key, gesture},
        Model.State{application, generation, realization, environment})) == environment : Design.Environment},
    frame_has_no_effects: @environment:Design.Environment -> @received:Nat -> @frame:Rendered.Frame ->
      @application:Platform.State -> @generation:Nat -> @realization:Rendered.State ->
      {Model.effects(Model.step(Model.FrameObserved{received, frame},
        Model.State{application, generation, realization, environment})) == Nil{} : +List<Model.Effect>},
    legacy_capacity_uses_layout: @supplied:View.Capacity -> @environment:Design.Environment ->
      @application:Platform.State -> @generation:Nat -> @realization:Rendered.State ->
      legacy_capacity_uses_layout_law(supplied, environment, application, generation, realization)
  }

def evidence() -> Requirements:
  Requirements{
    environment => application => generation => realization =>
      observes_prepared_scene(environment, application, generation, realization),
    state => observes_semantic_surface(state),
    environment => application => generation => realization =>
      observes_layout(environment, application, generation, realization),
    environment => current_environment => application => generation => realization =>
      environment_observed_preserves_core(environment, current_environment, application, generation, realization),
    environment => current_environment => application => generation => realization =>
      environment_observed_sets_capacity(environment, current_environment, application, generation, realization),
    environment => current_environment => application => generation => realization =>
      environment_observed_stores_environment(environment, current_environment, application, generation, realization),
    environment => received => frame => application => generation => realization =>
      frame_preserves_environment(environment, received, frame, application, generation, realization),
    environment => key => gesture => application => generation => realization =>
      element_preserves_environment(environment, key, gesture, application, generation, realization),
    environment => received => frame => application => generation => realization => Model.frame_emits_no_effects(received, frame, application, generation, realization, environment),
    supplied => environment => application => generation => realization =>
      legacy_capacity_uses_layout(supplied, environment, application, generation, realization)
  }
