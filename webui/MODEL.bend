import Base
import ../UI.bend as Product
import ../MODEL.bend as Program
import ../core/SYSTEM.bend as Core
import ../core/interface.bend as UI
import ../core/ui-world.bend as View
import ./platform.bend as Platform
import ./rendered.bend as Rendered
import ./design.bend as Design
import ./layout.bend as Layout
import ./appearance.bend as Appearance
import ./visibility.bend as Visibility
import ./presentation-order.bend as Order

type State is Data:
  State{application: Platform.State, generation: Nat, realization: Rendered.State,
    environment: Design.Environment}

type Input is Data:
  Mount{}
  PlatformInput{input: Platform.Input}
  EnvironmentObserved{environment: Design.Environment}
  ElementInput{key: String, gesture: UI.Gesture}
  FrameObserved{generation: Nat, frame: Rendered.Frame}

type Effect is Data:
  PlatformEffect{effect: Platform.Effect}
  MeasureFrame{generation: Nat}

type Decision is Data:
  Decision{state: State, product: Core.Decision, effects: +List<Effect>}

type Scene is Data:
  Scene{surface: Design.Surface, platform: Platform.Scene, generation: Nat, realization: Rendered.State,
    layout: Design.Layout}

def initial(program: Program.World()) -> State:
  State{Platform.initial(program), 0n, Rendered.AwaitingFrame{0n},
    Design.Environment{Design.Viewport{0n, 0n}, False{}}}

def capacity(platform: Platform.Platform) -> View.Capacity:
  Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope} = platform
  capacity

def surface(state: Platform.State) -> UI.Surface:
  Platform.State{core, platform} = state
  Product.observe(capacity(platform), core)

def resolved_focus(ticket: Nat, target: Maybe<&2, String>) -> +List<Effect>:
  match target:
    case None{}: Nil{}
    case Some{key}: [PlatformEffect{Platform.Focus{ticket, key}}]

def resolved_effect(effect: Platform.Effect, surface: UI.Surface) -> +List<Effect>:
  match effect:
    case Platform.Focus{ticket, target}: resolved_focus(ticket, UI.focus_target(surface, target))
    case other: [PlatformEffect{other}]
def platform_effects(effects: +List<Platform.Effect>, +surface: UI.Surface) -> +List<Effect>:
  match effects:
    case Nil{}: Nil{}
    case Con{effect, rest}: List.append(&2, Effect, resolved_effect(effect, surface), platform_effects(rest, surface))

def environment_viewport(environment: Design.Environment) -> Design.Viewport:
  Design.Environment{viewport, system_dark} = environment
  viewport

def invalidate(decision: Platform.Decision, +generation: Nat, environment: Design.Environment) -> Decision:
  Platform.Decision{+product, +platform, +effects} = decision
  Decision{State{Platform.next(Platform.Decision{product, platform, effects}), generation, Rendered.AwaitingFrame{generation}, environment},
    product, List.append(&2, Effect, platform_effects(effects, surface(Platform.next(Platform.Decision{product, platform, effects}))), [MeasureFrame{generation}])}

def idle(+application: Platform.State, generation: Nat, realization: Rendered.State,
  environment: Design.Environment) -> Decision:
  Platform.State{+core, platform} = application
  Decision{State{application, generation, realization, environment}, Platform.unchanged(core), Nil{}}

# Element keys carry product identity. Rendering generations only correlate
# measurements; streaming must not invalidate an unrelated keystroke.
def element_input(application: Platform.State, key: String, gesture: UI.Gesture, generation: Nat,
  environment: Design.Environment) -> Decision:
  Platform.State{core, +platform} = application
  invalidate(Platform.after_core(Product.step(Product.Element{capacity(platform), key, gesture}, core), platform),
    (generation + 1n : Nat), environment)

def frame_surface(environment: Design.Environment, +surface: UI.Surface) -> UI.Surface:
  +ordered = Order.ordered_surface(surface)
  Visibility.project(ordered, Layout.present(environment_viewport(environment), ordered))

def frame_result(received: Nat, +frame: Rendered.Frame, +application: Platform.State, +generation: Nat,
  realization: Rendered.State, +environment: Design.Environment) -> Decision:
  idle(application, generation, Rendered.observe(generation, received, frame_surface(environment, surface(application)), frame, realization), environment)

# Measurements acknowledge an existing generation. They never request another
# frame, so observer feedback cannot recursively invalidate the rendering.
def mount(application: Platform.State, generation: Nat, environment: Design.Environment) -> Decision:
  Platform.State{core, platform} = application
  invalidate(Platform.after_core(Platform.unchanged(core), platform), generation, environment)

def observed_platform_input(input: Platform.Input, environment: Design.Environment) -> Platform.Input:
  match input:
    case Platform.CapacityObserved{capacity}:
      Platform.CapacityObserved{Layout.capacity(environment_viewport(environment))}
    case other: other

def dispatch(state: State, input: Input) -> Decision:
  State{application, generation, realization, +environment} = state
  match input:
    case Mount{}: mount(application, (generation + 1n : Nat), environment)
    case PlatformInput{input}:
      invalidate(Platform.step(observed_platform_input(input, environment), application),
        (generation + 1n : Nat), environment)
    case EnvironmentObserved{+environment}:
      invalidate(Platform.step(Platform.CapacityObserved{Layout.capacity(environment_viewport(environment))}, application),
        (generation + 1n : Nat), environment)
    case ElementInput{key, gesture}: element_input(application, key, gesture, generation, environment)
    # The observed generation tags the prescribed plan; physical renderer fidelity remains external.
    case FrameObserved{received, frame}:
      frame_result(received, frame, application, generation, realization, environment)

def observed_surface(state: State) -> UI.Surface:
  State{application, generation, realization, environment} = state
  Order.ordered_surface(surface(application))

def scene_for_surface(state: State, +surface: UI.Surface) -> Scene:
  State{application, generation, realization, Design.Environment{viewport, system_dark}} = state
  Scene{Appearance.present(surface, system_dark), Platform.observe(application), generation, realization,
    Layout.present(viewport, surface)}

def observe(+state: State) -> Scene:
  scene_for_surface(state, observed_surface(state))

def effects(decision: Decision) -> +List<Effect>:
  Decision{state, product, effects} = decision
  effects

def step(input: Input, state: State) -> Decision:
  dispatch(state, input)
def frame_emits_no_effects(received: Nat, frame: Rendered.Frame, application: Platform.State,
  generation: Nat, realization: Rendered.State, environment: Design.Environment) ->
  {effects(step(FrameObserved{received, frame}, State{application, generation, realization, environment})) == Nil{} : +List<Effect>}:
  Platform.State{core, platform} = application
  {==}




def product(decision: Decision) -> Core.Decision:
  Decision{state, product, effects} = decision
  product

def platform_product(decision: Platform.Decision) -> Core.Decision:
  Platform.Decision{product, platform, effects} = decision
  product
def realization_preserves_product(decision: Platform.Decision, generation: Nat,
  environment: Design.Environment) ->
  {product(invalidate(decision, generation, environment)) == platform_product(decision) : Core.Decision}:
  Platform.Decision{product, platform, effects} = decision
  {==}
