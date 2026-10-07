import Base
import ../../interaction/STATE.bend as Core
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ../../interaction/presentation/MODEL.bend as View
import ../MODEL.bend as Model
import ../appearance/DESIGN.bend as Design
import ../runtime/PLATFORM.bend as Platform
import ./RENDERED.bend as Rendered
import ../appearance/FONT.bend as F

import ./presentation-laws.bend as Rule
import ../../bendlib/logic-proof.bend as Logic
import ../model-rules.bend as Rules_model_rules

def production_commit_environment(decision: Platform.Decision, generation: Nat, +environment: Design.Environment, font: F.State) ->
  {Rule.decision_environment(Model.production_commit(decision, generation, environment, font)) == environment : Design.Environment}:
  Platform.Decision{product, platform, effects} = decision
  {==}

def environment_observed_stores_environment(+environment: Design.Environment, current_environment: Design.Environment,
  +application: Platform.State, +generation: Nat, realization: Rendered.State, font: F.State) ->
  {Rule.decision_environment(Model.step(Model.EnvironmentObserved{environment}, Model.State{application, generation, realization, current_environment, font})) == environment : Design.Environment}:
  production_commit_environment(Platform.Decision{Platform.unchanged(Rule.original_core(application)), Rule.original_platform(application), Nil{}},
    (generation + 1n : Nat), environment, F.begin((generation + 1n : Nat), Model.environment_root(environment)))

def frame_preserves_environment(+environment: Design.Environment, received: Nat, frame: Rendered.Frame,
  application: Platform.State, generation: Nat, realization: Rendered.State, font: F.State) ->
  {Rule.decision_environment(Model.step(Model.FrameObserved{received, frame}, Model.State{application, generation, realization, environment, font})) == environment : Design.Environment}:
  Platform.State{core, platform} = application
  {==}

def element_preserves_environment(+environment: Design.Environment, key: String, gesture: InterfaceView.Gesture,
  application: Platform.State, +generation: Nat, realization: Rendered.State, +font: F.State) ->
  {Rule.decision_environment(Model.step(Model.ElementInput{key, gesture}, Model.State{application, generation, realization, environment, font})) == environment : Design.Environment}:
  Platform.State{core, +platform} = application
  production_commit_environment(Platform.after_core(InterfaceView.interact(Model.capacity(platform), key, gesture, core), platform),
    (generation + 1n : Nat), environment, font)

def same_capacity_identity(+first: View.Capacity, +second: View.Capacity,
  same: {Platform.same_capacity(first, second) == True{} : Bool}) -> {first == second : View.Capacity}:
  match first second:
    case View.Capacity{False{}, False{}} View.Capacity{False{}, False{}}: {==}
    case View.Capacity{False{}, False{}} View.Capacity{False{}, True{}}: Logic.impossible({View.Capacity{False{}, False{}} == View.Capacity{False{}, True{}} : View.Capacity}, same)
    case View.Capacity{False{}, False{}} View.Capacity{True{}, False{}}: Logic.impossible({View.Capacity{False{}, False{}} == View.Capacity{True{}, False{}} : View.Capacity}, same)
    case View.Capacity{False{}, False{}} View.Capacity{True{}, True{}}: Logic.impossible({View.Capacity{False{}, False{}} == View.Capacity{True{}, True{}} : View.Capacity}, same)
    case View.Capacity{False{}, True{}} View.Capacity{False{}, False{}}: Logic.impossible({View.Capacity{False{}, True{}} == View.Capacity{False{}, False{}} : View.Capacity}, same)
    case View.Capacity{False{}, True{}} View.Capacity{False{}, True{}}: {==}
    case View.Capacity{False{}, True{}} View.Capacity{True{}, False{}}: Logic.impossible({View.Capacity{False{}, True{}} == View.Capacity{True{}, False{}} : View.Capacity}, same)
    case View.Capacity{False{}, True{}} View.Capacity{True{}, True{}}: Logic.impossible({View.Capacity{False{}, True{}} == View.Capacity{True{}, True{}} : View.Capacity}, same)
    case View.Capacity{True{}, False{}} View.Capacity{False{}, False{}}: Logic.impossible({View.Capacity{True{}, False{}} == View.Capacity{False{}, False{}} : View.Capacity}, same)
    case View.Capacity{True{}, False{}} View.Capacity{False{}, True{}}: Logic.impossible({View.Capacity{True{}, False{}} == View.Capacity{False{}, True{}} : View.Capacity}, same)
    case View.Capacity{True{}, False{}} View.Capacity{True{}, False{}}: {==}
    case View.Capacity{True{}, False{}} View.Capacity{True{}, True{}}: Logic.impossible({View.Capacity{True{}, False{}} == View.Capacity{True{}, True{}} : View.Capacity}, same)
    case View.Capacity{True{}, True{}} View.Capacity{False{}, False{}}: Logic.impossible({View.Capacity{True{}, True{}} == View.Capacity{False{}, False{}} : View.Capacity}, same)
    case View.Capacity{True{}, True{}} View.Capacity{False{}, True{}}: Logic.impossible({View.Capacity{True{}, True{}} == View.Capacity{False{}, True{}} : View.Capacity}, same)
    case View.Capacity{True{}, True{}} View.Capacity{True{}, False{}}: Logic.impossible({View.Capacity{True{}, True{}} == View.Capacity{True{}, False{}} : View.Capacity}, same)
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

def environment_observed_preserves_capacity(+environment: Design.Environment, current_environment: Design.Environment,
  +application: Platform.State, +generation: Nat, realization: Rendered.State, font: F.State) ->
  {Rule.decision_capacity(Model.step(Model.EnvironmentObserved{environment}, Model.State{application, generation, realization, current_environment, font})) ==
    Rule.state_capacity(Model.State{application, generation, realization, current_environment, font}) : View.Capacity}:
  Platform.State{Core.State{application, services}, Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope}} = application
  {==}

def state_environment_observed_preserves_core_evidence(+model_state: Model.State, +environment: Design.Environment) ->
  {Model.product(Model.step(Model.EnvironmentObserved{environment}, model_state)) == Platform.unchanged(Rule.original_core(Model.application(model_state))) : Core.Decision}:
  Model.State{+application, +generation, +realization, +current_environment, +font} = model_state
  Rules_model_rules.production_commit_preserves_product(Platform.Decision{Platform.unchanged(Rule.original_core(application)), Rule.original_platform(application), Nil{}},
    (generation + 1n : Nat), environment, F.begin((generation + 1n : Nat), Model.environment_root(environment)))

def state_environment_observed_stores_environment_evidence(+model_state: Model.State, +environment: Design.Environment) ->
  {Rule.decision_environment(Model.step(Model.EnvironmentObserved{environment}, model_state)) == environment : Design.Environment}:
  Model.State{+application, +generation, +realization, +current_environment, +font} = model_state
  environment_observed_stores_environment(environment, current_environment, application, generation, realization, font)

def state_frame_preserves_environment_evidence(+model_state: Model.State, received: Nat, frame: Rendered.Frame) ->
  {Rule.decision_environment(Model.step(Model.FrameObserved{received, frame}, model_state)) == Model.environment(model_state) : Design.Environment}:
  Model.State{+application, +generation, +realization, +environment, +font} = model_state
  frame_preserves_environment(environment, received, frame, application, generation, realization, font)

def state_element_preserves_environment_evidence(+model_state: Model.State, key: String, gesture: InterfaceView.Gesture) ->
  {Rule.decision_environment(Model.step(Model.ElementInput{key, gesture}, model_state)) == Model.environment(model_state) : Design.Environment}:
  Model.State{+application, +generation, +realization, +environment, +font} = model_state
  element_preserves_environment(environment, key, gesture, application, generation, realization, font)

def state_environment_observed_preserves_capacity_evidence(+model_state: Model.State, +environment: Design.Environment) ->
  {Rule.decision_capacity(Model.step(Model.EnvironmentObserved{environment}, model_state)) == Rule.state_capacity(model_state) : View.Capacity}:
  Model.State{+application, +generation, +realization, +current_environment, +font} = model_state
  environment_observed_preserves_capacity(environment, current_environment, application, generation, realization, font)

def Rule.evidence():
  Rule.Requirements{
    state_environment_observed_preserves_core_evidence,
    state_environment_observed_stores_environment_evidence,
    state_frame_preserves_environment_evidence,
    state_element_preserves_environment_evidence,
    reflow_sets_capacity,
    state_environment_observed_preserves_capacity_evidence}
