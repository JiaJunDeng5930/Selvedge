import Base
import ../interaction/MODEL.bend as Product
import ../harness/MODEL.bend as Program
import ../interaction/STATE.bend as Core
import ../interaction/presentation/PROGRAM.bend as InterfaceView
import ../interaction/presentation/MODEL.bend as View
import ./runtime/PLATFORM.bend as Platform
import ./focus/MODEL.bend as Focus
import ./document/RENDERED.bend as Rendered
import ./appearance/DESIGN.bend as Design
import ./appearance/MODEL.bend as Appearance
import ./appearance/FONT.bend as F
import ./document/presentation-order.bend as Order
import ./document/code-observation.bend as CodeObservation
type State is Data:
  State{application: Platform.State, generation: Nat, realization: Rendered.State,
    environment: Design.Environment, typography: F.State}
def application(state: State) -> Platform.State:
  State{value_application, value_generation, value_realization, value_environment, value_typography} = state
  value_application

def generation(state: State) -> Nat:
  State{value_application, value_generation, value_realization, value_environment, value_typography} = state
  value_generation

def realization(state: State) -> Rendered.State:
  State{value_application, value_generation, value_realization, value_environment, value_typography} = state
  value_realization

def environment(state: State) -> Design.Environment:
  State{value_application, value_generation, value_realization, value_environment, value_typography} = state
  value_environment

def typography(state: State) -> F.State:
  State{value_application, value_generation, value_realization, value_environment, value_typography} = state
  value_typography

def with_application(value: Platform.State, state: State) -> State:
  State{value_application, value_generation, value_realization, value_environment, value_typography} = state
  State{value, value_generation, value_realization, value_environment, value_typography}

type Input is Data:
  Mount{}
  PlatformInput{input: Platform.Input}
  EnvironmentObserved{environment: Design.Environment}
  ElementInput{key: String, gesture: InterfaceView.Gesture}
  FrameObserved{generation: Nat, frame: Rendered.Frame}
  NativeFocusObserved{generation: Nat, owner: String, identity: String}
  CodeSourcesObserved{generation: Nat, observations: +List<CodeObservation.Observation>}
  TypographyObserved{observation: F.Observation}

type Effect is Data:
  PlatformEffect{effect: Platform.Effect}
  MeasureFrame{generation: Nat}

type Decision is Data:
  Decision{state: State, product: Core.Decision, effects: +List<Effect>}

def with_realization(value: Rendered.State, state: State) -> State:
  State{value_application, value_generation, value_realization, value_environment, value_typography} = state
  State{value_application, value_generation, value, value_environment, value_typography}

def with_typography(value: F.State, state: State) -> State:
  State{value_application, value_generation, value_realization, value_environment, value_typography} = state
  State{value_application, value_generation, value_realization, value_environment, value}

def initial(program: Program.World()) -> State:
  State{Platform.initial(program), 0n, Rendered.AwaitingFrame{0n},
    Design.Environment{Design.Viewport{0n, 0n}, False{}, 16000n}, F.begin(0n, 16000n)}

def capacity(+platform: Platform.Platform) -> View.Capacity:
  editors = Platform.editors(platform)
  +capacity = Platform.capacity(platform)
  capacity

def surface(+state: Platform.State) -> InterfaceView.Surface:
  +core = Platform.core(state)
  +platform = Platform.platform(state)
  Product.observe(capacity(platform), core)

def resolved_focus(ticket: Nat, target: Maybe<&2, String>) -> +List<Effect>:
  match target:
    case None{}: Nil{}
    case Some{key}: [PlatformEffect{Platform.Focus{ticket, Focus.Product{key}}}]

def resolved_content_focus(owned: Bool, ticket: Nat, owner: String, identity: String) -> +List<Effect>:
  match owned:
    case True{}: [PlatformEffect{Platform.Focus{ticket, Focus.Content{owner, identity}}}]
    case False{}: Nil{}

def resolved_effect(effect: Platform.Effect, +surface: InterfaceView.Surface) -> +List<Effect>:
  match effect:
    case Platform.Focus{ticket, Focus.Product{target}}: resolved_focus(ticket, InterfaceView.focus_target(surface, target))
    case Platform.Focus{ticket, Focus.Content{+owner, identity}}:
      resolved_content_focus(Platform.found_content_owner(InterfaceView.find_node(InterfaceView.active_nodes(surface), owner)), ticket, owner, identity)
    case Platform.ScopeFocus{ticket, previous, current}:
      resolved_focus(ticket, InterfaceView.focus_target(surface, Focus.scope_target(previous, current, surface)))
    case other: [PlatformEffect{other}]

def platform_effects(effects: +List<Platform.Effect>, +surface: InterfaceView.Surface) -> +List<Effect>:
  match effects:
    case Nil{}: Nil{}
    case Con{effect, rest}: List.append(&2, Effect, resolved_effect(effect, surface), platform_effects(rest, surface))

def environment_root(environment: Design.Environment) -> Nat:
  Design.Environment{viewport, system_dark, root_font_size_milli} = environment
  root_font_size_milli

def idle(+application: Platform.State, generation: Nat, realization: Rendered.State,
  environment: Design.Environment, typography: F.State) -> Decision:
  +core = Platform.core(application)
  Decision{State{application, generation, realization, environment, typography}, Platform.unchanged(core), Nil{}}

# Element identities remain stable while generations correlate physical observations.

def appearance_surface(surface: InterfaceView.Surface, environment: Design.Environment, font: F.State) -> Design.Surface:
  Design.Environment{viewport, dark, root} = environment
  Appearance.present(surface, dark, F.scale(font))

def model_core(+state: Platform.State) -> Core.State:
  +core = Platform.core(state)
  core

def model_platform(+state: Platform.State) -> Platform.Platform:
  +platform = Platform.platform(state)
  platform

def observed_surface(state: State) -> InterfaceView.Surface:
  State{application, generation, realization, environment, font} = state
  Order.ordered_surface(surface(application))

def effects(decision: Decision) -> +List<Effect>:
  Decision{state, product, effects} = decision
  effects

# Physical allocation owns capacity admission and frame measurement requests.

def production_commit(decision: Platform.Decision, +generation: Nat, environment: Design.Environment,
  font: F.State) -> Decision:
  Platform.Decision{+product, +platform, +effects} = decision
  +application = Platform.next(Platform.Decision{product, platform, effects})
  Decision{State{application, generation, Rendered.AwaitingFrame{generation}, environment, F.retag(font, generation)},
    product, platform_effects(effects, Order.ordered_surface(surface(application)))}

def production_platform_input(input: Platform.Input, application: Platform.State) -> Platform.Input:
  match input:
    case Platform.CapacityObserved{observed}: Platform.CapacityObserved{capacity(model_platform(application))}
    case other: other

def production_typography_owned(owned: Bool, +application: Platform.State, generation: Nat,
  realization: Rendered.State, environment: Design.Environment, font: F.State, observation: F.Observation) -> Decision:
  match owned:
    case True{}: idle(application, generation, realization, environment, F.accept(font, Nil{}, observation))
    case False{}: idle(application, generation, realization, environment, font)

def production_typography(+state: State, +observation: F.Observation) -> Decision:
  State{application, generation, realization, environment, +font} = state
  F.Observation{+received, metrics} = observation
  production_typography_owned(Nat.is_eq(F.generation(font), received), application, generation, realization,
    environment, font, F.Observation{received, metrics})

def idle_state(state: State) -> Decision:
  State{application, generation, realization, environment, font} = state
  idle(application, generation, realization, environment, font)

def visible_focus_recovery(focused_visible: Bool, container_visible: Bool, eligible: Bool, identity: String) -> Maybe<&2, String>:
  match focused_visible container_visible eligible:
    case False{} True{} True{}: Some{identity}
    case _ _ _: None{}

def frame_focus_visible(frame: Rendered.Frame, key: String) -> Bool:
  Rendered.Frame{viewport, elements, focused, tab_order, native_focus} = frame
  Rendered.focus_visible(Rendered.find_element(elements, key), viewport)

def scoped_frame_focus_recovery(scope: Focus.Scope, focused: Maybe<&2, String>, +surface: InterfaceView.Surface,
  +frame: Rendered.Frame) -> Maybe<&2, String>:
  match scope focused:
    case Focus.Temporary{+identity, initial, restore, occurrence} Some{key}:
      visible_focus_recovery(frame_focus_visible(frame, key), frame_focus_visible(frame, identity),
        Platform.found_focus(InterfaceView.find_node(InterfaceView.active_nodes(surface), identity)), identity)
    case _ _: None{}

def frame_focus_recovery(surface: InterfaceView.Surface, +frame: Rendered.Frame, scope: Focus.Scope) -> Maybe<&2, String>:
  Rendered.Frame{viewport, elements, focused, tab_order, native_focus} = frame
  scoped_frame_focus_recovery(scope, focused, surface, frame)

def frame_recovery_effects(owned: Bool, ticket: Nat, generation: Nat, target: Maybe<&2, String>) -> +List<Effect>:
  match owned target:
    case True{} Some{key}: [PlatformEffect{Platform.Focus{ticket, Focus.Product{key}}}, MeasureFrame{generation}]
    case _ _: Nil{}

def observe_frame(+received: Nat, +surface: InterfaceView.Surface, +frame: Rendered.Frame, +state: State) -> Decision:
  State{+application, +generation, realization, environment, font} = state
  +core = Platform.core(application)
  +observed_platform_1 = Platform.platform(application)
  editors = Platform.editors(observed_platform_1)
  +ticket = Platform.focus_ticket(observed_platform_1)
  +scope = Platform.scope(observed_platform_1)
  Decision{State{application, generation, Rendered.observe(generation, received, surface, frame, realization), environment, font},
    Platform.unchanged(core), frame_recovery_effects(Nat.is_eq(generation, received), ticket, generation,
      frame_focus_recovery(surface, frame, scope))}

def decision_realization(decision: Decision) -> Rendered.State:
  Decision{State{application, generation, realization, environment, font}, product, effects} = decision
  realization

def production_dispatch(state: State, input: Input) -> Decision:
  State{+application, +generation, +realization, +environment, +font} = state
  match input:
    case Mount{}:
      production_commit(Platform.after_core(Platform.unchanged(model_core(application)), model_platform(application)),
        (generation + 1n : Nat), environment, font)
    case PlatformInput{input}:
      production_commit(Platform.step(production_platform_input(input, application), application),
        (generation + 1n : Nat), environment, font)
    case EnvironmentObserved{+observed}:
      production_commit(Platform.Decision{Platform.unchanged(model_core(application)), model_platform(application), Nil{}},
        (generation + 1n : Nat), observed,
        F.begin((generation + 1n : Nat), environment_root(observed)))
    case ElementInput{key, gesture}:
      production_commit(Platform.after_core(Product.step(Product.Element{capacity(model_platform(application)), key, gesture},
        model_core(application)), model_platform(application)), (generation + 1n : Nat), environment, font)
    case NativeFocusObserved{received, owner, identity}: idle(application, generation, realization, environment, font)
    case CodeSourcesObserved{received, observations}: idle(application, generation, realization, environment, font)
    case FrameObserved{+received, frame}:
      idle(application, generation, realization, environment, font)
    case TypographyObserved{observation}:
      production_typography(State{application, generation, realization, environment, font}, observation)

def step(input: Input, state: State) -> Decision:
  production_dispatch(state, input)

def product(decision: Decision) -> Core.Decision:
  Decision{state, product, effects} = decision
  product

def platform_product(decision: Platform.Decision) -> Core.Decision:
  Platform.decision_product(decision)
