import Base
import ../../interaction/STATE.bend as Core
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ../../interaction/presentation/MODEL.bend as View
import ../MODEL.bend as Model
import ../appearance/DESIGN.bend as Design
import ../runtime/PLATFORM.bend as Platform
import ./RENDERED.bend as Rendered
import ../appearance/FONT.bend as F
def decision_state(decision: Model.Decision) -> Model.State:
  Model.Decision{state, product, effects} = decision
  state

def state_capacity(+state: Model.State) -> View.Capacity:
  +observed_application_1 = Model.application(state)
  +platform = Platform.platform(observed_application_1)
  Model.capacity(platform)

def state_environment(+state: Model.State) -> Design.Environment:
  +environment = Model.environment(state)
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
    environment_observed_preserves_core: @+model_state:Model.State ->  @+environment:Design.Environment -> {Model.product(Model.step(Model.EnvironmentObserved{environment}, model_state)) == Platform.unchanged(original_core(Model.application(model_state))) : Core.Decision},
    environment_observed_stores_environment: @+model_state:Model.State ->  @+environment:Design.Environment -> {decision_environment(Model.step(Model.EnvironmentObserved{environment}, model_state)) == environment : Design.Environment},
    frame_preserves_environment: @+model_state:Model.State ->  @received:Nat -> @frame:Rendered.Frame -> {decision_environment(Model.step(Model.FrameObserved{received, frame}, model_state)) == Model.environment(model_state) : Design.Environment},
    element_preserves_environment: @+model_state:Model.State ->  @key:String -> @gesture:InterfaceView.Gesture -> {decision_environment(Model.step(Model.ElementInput{key, gesture}, model_state)) == Model.environment(model_state) : Design.Environment},
    reflow_sets_requested_capacity: @+decision:Platform.Decision -> @+requested:View.Capacity ->
      {platform_decision_capacity(Platform.reflow_capacity(decision, requested)) == requested : View.Capacity},
    environment_observed_preserves_capacity: @+model_state:Model.State ->  @+environment:Design.Environment -> {decision_capacity(Model.step(Model.EnvironmentObserved{environment}, model_state)) == state_capacity(model_state) : View.Capacity}}
law evidence:
  Requirements
