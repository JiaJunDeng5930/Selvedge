import Base
import ../UI.bend as Product
import ../MODEL.bend as Program
import ../core/SYSTEM.bend as Core
import ../core/interface.bend as UI
import ../core/ui-world.bend as View
import ./platform.bend as Platform
import ./rendered.bend as Rendered

type State is Data:
  State{application: Platform.State, generation: Nat, realization: Rendered.State}

type Input is Data:
  Mount{}
  PlatformInput{input: Platform.Input}
  ElementInput{key: String, gesture: UI.Gesture}
  FrameObserved{generation: Nat, frame: Rendered.Frame}

type Effect is Data:
  PlatformEffect{effect: Platform.Effect}
  MeasureFrame{generation: Nat}

type Decision is Data:
  Decision{state: State, product: Core.Decision, effects: +List<Effect>}

type Scene is Data:
  Scene{surface: UI.Surface, platform: Platform.Scene, generation: Nat, realization: Rendered.State}

def initial(program: Program.World()) -> State:
  State{Platform.initial(program), 0n, Rendered.AwaitingFrame{0n}}

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

def invalidate(decision: Platform.Decision, +generation: Nat) -> Decision:
  Platform.Decision{+product, +platform, +effects} = decision
  Decision{State{Platform.next(Platform.Decision{product, platform, effects}), generation, Rendered.AwaitingFrame{generation}},
    product, List.append(&2, Effect, platform_effects(effects, surface(Platform.next(Platform.Decision{product, platform, effects}))), [MeasureFrame{generation}])}

def idle(+application: Platform.State, generation: Nat, realization: Rendered.State) -> Decision:
  Platform.State{+core, platform} = application
  Decision{State{application, generation, realization}, Platform.unchanged(core), Nil{}}

# Element keys carry product identity. Rendering generations only correlate
# measurements; streaming must not invalidate an unrelated keystroke.
def element_input(application: Platform.State, key: String, gesture: UI.Gesture, generation: Nat) -> Decision:
  Platform.State{core, +platform} = application
  invalidate(Platform.after_core(Product.step(Product.Element{capacity(platform), key, gesture}, core), platform), (generation + 1n : Nat))

def frame_result(received: Nat, +frame: Rendered.Frame, +application: Platform.State, +generation: Nat, realization: Rendered.State) -> Decision:
  idle(application, generation, Rendered.observe(generation, received, surface(application), frame, realization))

# Measurements acknowledge an existing generation. They never request another
# frame, so observer feedback cannot recursively invalidate the rendering.
def mount(application: Platform.State, generation: Nat) -> Decision:
  Platform.State{core, platform} = application
  invalidate(Platform.after_core(Platform.unchanged(core), platform), generation)
def dispatch(state: State, input: Input) -> Decision:
  State{application, generation, realization} = state
  match input:
    case Mount{}: mount(application, (generation + 1n : Nat))
    case PlatformInput{input}: invalidate(Platform.step(input, application), (generation + 1n : Nat))
    case ElementInput{key, gesture}: element_input(application, key, gesture, generation)
    case FrameObserved{received, frame}: frame_result(received, frame, application, generation, realization)

def observe(state: State) -> Scene:
  State{+application, generation, realization} = state
  Scene{surface(application), Platform.observe(application), generation, realization}

def effects(decision: Decision) -> +List<Effect>:
  Decision{state, product, effects} = decision
  effects

def step(input: Input, state: State) -> Decision:
  dispatch(state, input)
def frame_emits_no_effects(received: Nat, frame: Rendered.Frame, application: Platform.State, generation: Nat, realization: Rendered.State) ->
  {effects(step(FrameObserved{received, frame}, State{application, generation, realization})) == Nil{} : +List<Effect>}:
  Platform.State{core, platform} = application
  {==}




def product(decision: Decision) -> Core.Decision:
  Decision{state, product, effects} = decision
  product

def platform_product(decision: Platform.Decision) -> Core.Decision:
  Platform.Decision{product, platform, effects} = decision
  product
def realization_preserves_product(decision: Platform.Decision, generation: Nat) ->
  {product(invalidate(decision, generation)) == platform_product(decision) : Core.Decision}:
  Platform.Decision{product, platform, effects} = decision
  {==}
