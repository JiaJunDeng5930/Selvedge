import Base
import ../core/SYSTEM.bend as Core
import ../core/interface.bend as InterfaceView
import ../core/ui-world.bend as View
import ./MODEL.bend as Model
import ./design.bend as Design
import ./platform.bend as Platform
import ./rendered.bend as Rendered
import ./font-observation.bend as F


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


def platform_decision_capacity(decision: Platform.Decision) -> View.Capacity:
  Platform.Decision{product, platform, effects} = decision
  Model.capacity(platform)

type Requirements is Type:
  Requirements{
    environment_observed_preserves_core: @+environment:Design.Environment -> @current_environment:Design.Environment -> @+application:Platform.State -> @+generation:Nat -> @realization:Rendered.State -> @font:F.State ->
      {Model.product(Model.step(Model.EnvironmentObserved{environment}, Model.State{application, generation, realization, current_environment, font})) == Platform.unchanged(original_core(application)) : Core.Decision},
    environment_observed_stores_environment: @+environment:Design.Environment -> @current_environment:Design.Environment -> @+application:Platform.State -> @+generation:Nat -> @realization:Rendered.State -> @font:F.State ->
      {decision_environment(Model.step(Model.EnvironmentObserved{environment}, Model.State{application, generation, realization, current_environment, font})) == environment : Design.Environment},
    frame_preserves_environment: @+environment:Design.Environment -> @received:Nat -> @frame:Rendered.Frame -> @application:Platform.State -> @generation:Nat -> @realization:Rendered.State -> @font:F.State ->
      {decision_environment(Model.step(Model.FrameObserved{received, frame}, Model.State{application, generation, realization, environment, font})) == environment : Design.Environment},
    element_preserves_environment: @+environment:Design.Environment -> @key:String -> @gesture:InterfaceView.Gesture -> @application:Platform.State -> @+generation:Nat -> @realization:Rendered.State -> @+font:F.State ->
      {decision_environment(Model.step(Model.ElementInput{key, gesture}, Model.State{application, generation, realization, environment, font})) == environment : Design.Environment},
    reflow_sets_requested_capacity: @+decision:Platform.Decision -> @+requested:View.Capacity ->
      {platform_decision_capacity(Platform.reflow_capacity(decision, requested)) == requested : View.Capacity},
    environment_observed_preserves_capacity: @+environment:Design.Environment -> @current_environment:Design.Environment -> @+application:Platform.State -> @+generation:Nat -> @realization:Rendered.State -> @font:F.State ->
      {decision_capacity(Model.step(Model.EnvironmentObserved{environment}, Model.State{application, generation, realization, current_environment, font})) == state_capacity(Model.State{application, generation, realization, current_environment, font}) : View.Capacity}}

law evidence:
  Requirements
