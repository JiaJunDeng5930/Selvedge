import Base
import ../core/SYSTEM.bend as Core
import ../core/interface.bend as UI
import ../core/ui-world.bend as View
import ./MODEL.bend as Model
import ./design.bend as Design
import ./layout.bend as Layout
import ./appearance.bend as Appearance
import ./platform.bend as Platform
import ./rendered.bend as Rendered
import ./presentation-order.bend as Order

def scene_presentation(scene: Model.Scene) -> Design.Presentation:
  Model.Scene{surface, platform, generation, realization, presentation} = scene
  presentation

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

def observes_presentation_law(-environment: Design.Environment, -application: Platform.State, -generation: Nat, -realization: Rendered.State) -> Type:
  {scene_presentation(Model.observe(Model.State{application, generation, realization, environment})) ==
      Design.Presentation{
        Layout.present(viewport_of(environment), Order.ordered_surface(Model.surface(application))),
        Appearance.present(Order.ordered_surface(Model.surface(application)), system_dark_of(environment))
      } : Design.Presentation}

def observes_presentation(environment: Design.Environment, application: Platform.State,
  generation: Nat, realization: Rendered.State) -> observes_presentation_law(environment, application, generation, realization):
  match environment:
    case Design.Environment{viewport, system_dark}: {==}

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

def frame_has_no_effects(environment: Design.Environment, received: Nat, frame: Rendered.Frame,
  application: Platform.State, generation: Nat, realization: Rendered.State) ->
  {Model.effects(Model.step(Model.FrameObserved{received, frame},
    Model.State{application, generation, realization, environment})) == Nil{} : +List<Model.Effect>}:
  Model.frame_emits_no_effects(received, frame, application, generation, realization, environment)

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
    observes_presentation: @environment:Design.Environment -> @application:Platform.State ->
      @generation:Nat -> @realization:Rendered.State ->
      observes_presentation_law(environment, application, generation, realization),
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
      observes_presentation(environment, application, generation, realization),
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
    environment => received => frame => application => generation => realization =>
      frame_has_no_effects(environment, received, frame, application, generation, realization),
    supplied => environment => application => generation => realization =>
      legacy_capacity_uses_layout(supplied, environment, application, generation, realization)
  }
