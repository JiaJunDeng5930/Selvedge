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
import ./typography.bend as T
import ./font-observation.bend as F
import ./viewport-space.bend as ViewportSpace
import ../core/user-experience.bend as E
import ./visibility.bend as Visibility
import ./presentation-order.bend as Order
import ./content-space.bend as CS
import ./renderer.bend as Renderer

type State is Data:
  State{application: Platform.State, generation: Nat, realization: Rendered.State,
    environment: Design.Environment, typography: F.State}

type Input is Data:
  Mount{}
  PlatformInput{input: Platform.Input}
  EnvironmentObserved{environment: Design.Environment}
  ElementInput{key: String, gesture: UI.Gesture}
  FrameObserved{generation: Nat, frame: Rendered.Frame}
  TypographyObserved{observation: F.Observation}

type Effect is Data:
  PlatformEffect{effect: Platform.Effect}
  MeasureFrame{generation: Nat}

type Decision is Data:
  Decision{state: State, product: Core.Decision, effects: +List<Effect>}

type Scene is Data:
  Scene{presentation: Design.PreparedSurface, platform: Platform.Scene, generation: Nat, realization: Rendered.State,
    layout: Design.Layout}

def scene_surface(scene: Scene) -> Design.Surface:
  Scene{Design.PreparedSurface{surface, base, overlays}, platform, generation, realization, layout} = scene
  surface

type SceneOutcome is Data:
  AwaitingTypography{}
  FailedTypography{}
  UnsupportedSpace{required: Nat, available: Nat}
  ReadyScene{scene: Scene}

def initial(program: Program.World()) -> State:
  State{Platform.initial(program), 0n, Rendered.AwaitingFrame{0n},
    Design.Environment{Design.Viewport{0n, 0n}, False{}, 16000n}, F.begin(0n, 16000n)}

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
  Design.Environment{viewport, system_dark, root_font_size_milli} = environment
  viewport

def environment_root(environment: Design.Environment) -> Nat:
  Design.Environment{viewport, system_dark, root_font_size_milli} = environment
  root_font_size_milli

def navigation_intent(application: Platform.State) -> E.NavigationIntent:
  Platform.State{Core.State{E.Application{program, E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, blocks}}, services}, platform} = application
  E.navigation_visibility(navigation)

def font_capacity(font: F.State, environment: Design.Environment, application: Platform.State) -> View.Capacity:
  match font:
    case F.Ready{generation, +scale, metric, +content_cache}:
      Layout.capacity(ViewportSpace.parameters(scale, metric), environment_viewport(environment), navigation_intent(application))
    case _: View.Capacity{False{}, False{}}

def calibrated(+decision: Platform.Decision, environment: Design.Environment, font: F.State) -> Platform.Decision:
  Platform.reflow_capacity(decision, font_capacity(font, environment, Platform.next(decision)))

def realized(decision: Platform.Decision, +generation: Nat, environment: Design.Environment, font: F.State) -> Decision:
  Platform.Decision{+product, +platform, +effects} = decision
  Decision{State{Platform.next(Platform.Decision{product, platform, effects}), generation, Rendered.AwaitingFrame{generation}, environment, font},
    product, List.append(&2, Effect, platform_effects(effects, surface(Platform.next(Platform.Decision{product, platform, effects}))), [MeasureFrame{generation}])}

def invalidate(decision: Platform.Decision, +generation: Nat, +environment: Design.Environment, font: F.State) -> Decision:
  +retagged = F.retag(font, generation)
  realized(calibrated(decision, environment, retagged), generation, environment, retagged)

def idle(+application: Platform.State, generation: Nat, realization: Rendered.State,
  environment: Design.Environment, typography: F.State) -> Decision:
  Platform.State{+core, platform} = application
  Decision{State{application, generation, realization, environment, typography}, Platform.unchanged(core), Nil{}}

# Element identities remain stable while generations correlate physical observations.
def element_input(application: Platform.State, key: String, gesture: UI.Gesture, generation: Nat,
  environment: Design.Environment, typography: F.State) -> Decision:
  Platform.State{core, +platform} = application
  invalidate(Platform.after_core(Product.step(Product.Element{capacity(platform), key, gesture}, core), platform),
    (generation + 1n : Nat), environment, typography)

def appearance_surface(surface: UI.Surface, environment: Design.Environment, font: F.State) -> Design.Surface:
  Design.Environment{viewport, dark, root} = environment
  Appearance.present(surface, dark, F.scale(font))

def required_content(font: F.State, application: Platform.State, environment: Design.Environment) -> +List<T.MeasurementSpec>:
  match font:
    case F.Ready{font_generation, scale, metric, content_cache}:
      CS.specifications(appearance_surface(Order.ordered_surface(surface(application)), environment, F.Ready{font_generation, scale, metric, content_cache}))
    case _: Nil{}

def measurement_plan(state: State) -> F.Plan:
  State{application, generation, realization, environment, +font} = state
  F.request(font, required_content(font, application, environment))

def measurement_budget(state: State) -> Nat:
  State{application, generation, realization, environment, font} = state
  match font:
    case F.Pending{font_generation, scale}: 2n
    case F.Ready{font_generation, scale, metric, content_cache}: 1n
    case F.Failed{font_generation, scale}: 0n

def allocated_scene(outcome: Layout.Outcome, +application: Platform.State, generation: Nat,
  realization: Rendered.State, presentation: Design.PreparedSurface) -> SceneOutcome:
  match outcome:
    case Layout.LayoutUnsupported{required, available}: UnsupportedSpace{required, available}
    case Layout.LayoutReady{layout}:
      ReadyScene{Scene{presentation, Platform.observe(application), generation, realization, layout}}

def presented_scene(+presentation: Design.PreparedSurface, +application: Platform.State, generation: Nat,
  realization: Rendered.State, parameters: Design.LayoutParameters, viewport: Design.Viewport) -> SceneOutcome:
  Design.PreparedSurface{surface, base, overlays} = presentation
  allocated_scene(Layout.present(parameters, viewport, presentation), application, generation, realization, presentation)

def prepared_scene(preparation: CS.Outcome, +application: Platform.State, +generation: Nat, +realization: Rendered.State,
  parameters: Design.LayoutParameters, viewport: Design.Viewport) -> SceneOutcome:
  match preparation:
    case CS.AwaitingContent{missing}: AwaitingTypography{}
    case CS.Prepared{+prepared}:
      presented_scene(Renderer.prepare(prepared), application, generation, realization, parameters, viewport)

def font_scene(font: F.State, +application: Platform.State, +generation: Nat, +realization: Rendered.State,
  +viewport: Design.Viewport, dark: Bool, +surface: UI.Surface) -> SceneOutcome:
  match font:
    case F.Pending{font_generation, scale}: AwaitingTypography{}
    case F.Failed{font_generation, scale}: FailedTypography{}
    case F.Ready{font_generation, +scale, +metric, +content_cache}:
      prepared_scene(CS.prepare(content_cache, appearance_surface(surface, Design.Environment{viewport, dark, 0n}, F.Ready{font_generation, scale, metric, content_cache})), application, generation,
        realization, ViewportSpace.parameters(scale, metric), viewport)

def scene_for_surface(state: State, surface: UI.Surface) -> SceneOutcome:
  State{application, generation, realization, Design.Environment{viewport, dark, root}, font} = state
  font_scene(font, application, generation, realization, viewport, dark, surface)

def projected_frame(outcome: SceneOutcome) -> Maybe<&2, UI.Surface>:
  match outcome:
    case ReadyScene{+scene}:
      Scene{presentation, platform, generation, realization, layout} = scene
      Some{Visibility.project(Design.semantic_surface(scene_surface(scene)), layout)}
    case _: None{}

def frame_surface(state: State, surface: UI.Surface) -> Maybe<&2, UI.Surface>:
  projected_frame(scene_for_surface(state, Order.ordered_surface(surface)))

def observed_frame(owned: Bool, found: Maybe<&2, UI.Surface>, generation: Nat, received: Nat,
  frame: Rendered.Frame, previous: Rendered.State) -> Rendered.State:
  match owned found:
    case False{} _: previous
    case True{} Some{surface}: Rendered.observe(generation, received, surface, frame, previous)
    case True{} None{}: Rendered.AwaitingFrame{generation}

def frame_realization(+state: State, +received: Nat, frame: Rendered.Frame, surface: UI.Surface) -> Rendered.State:
  State{application, +generation, +previous, environment, font} = state
  observed_frame(Nat.is_eq(generation, received), frame_surface(State{application, generation, previous, environment, font}, surface), generation, received, frame, previous)

def frame_result(received: Nat, frame: Rendered.Frame, +application: Platform.State, +generation: Nat,
  +realization: Rendered.State, +environment: Design.Environment, +font: F.State) -> Decision:
  idle(application, generation,
    frame_realization(State{application, generation, realization, environment, font}, received, frame, surface(application)), environment, font)

def mount(application: Platform.State, generation: Nat, environment: Design.Environment, typography: F.State) -> Decision:
  Platform.State{core, platform} = application
  invalidate(Platform.after_core(Platform.unchanged(core), platform), generation, environment, typography)

def observed_platform_input(input: Platform.Input, environment: Design.Environment, font: F.State, application: Platform.State) -> Platform.Input:
  match input:
    case Platform.CapacityObserved{capacity}: Platform.CapacityObserved{font_capacity(font, environment, application)}
    case other: other

def font_admitted(font: F.State, +application: Platform.State, +generation: Nat, realization: Rendered.State,
  +environment: Design.Environment) -> Decision:
  match font:
    case F.Ready{+font_generation, +scale, +metric, +content_cache}:
      Platform.State{core, platform} = application
      realized(calibrated(Platform.Decision{Platform.unchanged(core), platform, Nil{}}, environment, F.Ready{font_generation, scale, metric, content_cache}),
        generation, environment, F.Ready{font_generation, scale, metric, content_cache})
    case other: idle(application, generation, Rendered.AwaitingFrame{generation}, environment, other)

def content_admitted(font: F.State, +application: Platform.State, +generation: Nat,
  realization: Rendered.State, +environment: Design.Environment) -> Decision:
  match font:
    case F.Ready{font_generation, scale, metric, content_cache}:
      Platform.State{core, platform} = application
      realized(Platform.Decision{Platform.unchanged(core), platform, Nil{}}, generation, environment,
        F.Ready{font_generation, scale, metric, content_cache})
    case other: idle(application, generation, Rendered.AwaitingFrame{generation}, environment, other)

def content_receipt(missing: +List<T.MeasurementSpec>, +font: F.State, +required: +List<T.MeasurementSpec>,
  +application: Platform.State, +generation: Nat, +realization: Rendered.State, +environment: Design.Environment,
  observation: F.Observation) -> Decision:
  match missing:
    case Nil{}: idle(application, generation, realization, environment, font)
    case Con{specification, rest}: content_admitted(F.accept(font, required, observation), application, generation, realization, environment)

def pending_receipt(font: F.State, +application: Platform.State, +generation: Nat, +realization: Rendered.State,
  +environment: Design.Environment, observation: F.Observation) -> Decision:
  match font:
    case F.Pending{font_generation, scale}:
      font_admitted(F.accept(F.Pending{font_generation, scale}, Nil{}, observation), application, generation, realization, environment)
    case F.Ready{+font_generation, +scale, +metric, +content_cache}:
      +font: F.State = F.Ready{font_generation, scale, metric, content_cache}
      +required = required_content(font, application, environment)
      content_receipt(F.missing(required, content_cache), font, required, application, generation, realization, environment, observation)
    case F.Failed{font_generation, scale}: idle(application, generation, realization, environment, F.Failed{font_generation, scale})

def receipt_owned_state(owned: Bool, +application: Platform.State, +generation: Nat, +realization: Rendered.State,
  +environment: Design.Environment, font: F.State, observation: F.Observation) -> Decision:
  match owned:
    case True{}: pending_receipt(font, application, generation, realization, environment, observation)
    case False{}: idle(application, generation, realization, environment, font)

def receipt_owned(owned: Bool, state: State, observation: F.Observation) -> Decision:
  State{application, generation, realization, environment, font} = state
  receipt_owned_state(owned, application, generation, realization, environment, font, observation)

def typography_result(+state: State, +observation: F.Observation) -> Decision:
  State{application, generation, realization, environment, +font} = state
  F.Observation{+received, metrics} = observation
  receipt_owned(Nat.is_eq(F.generation(font), received), State{application, generation, realization, environment, font}, F.Observation{received, metrics})

def model_core(state: Platform.State) -> Core.State:
  Platform.State{core, platform} = state
  core

def model_platform(state: Platform.State) -> Platform.Platform:
  Platform.State{core, platform} = state
  platform

def dispatch(state: State, input: Input) -> Decision:
  State{+application, +generation, +realization, +environment, +font} = state
  match input:
    case Mount{}: mount(application, (generation + 1n : Nat), environment, font)
    case PlatformInput{input}:
      invalidate(Platform.step(observed_platform_input(input, environment, font, application), application),
        (generation + 1n : Nat), environment, font)
    case EnvironmentObserved{+environment}:
      invalidate(Platform.Decision{Platform.unchanged(model_core(application)), model_platform(application), Nil{}},
        (generation + 1n : Nat), environment, F.begin((generation + 1n : Nat), environment_root(environment)))
    case ElementInput{key, gesture}: element_input(application, key, gesture, generation, environment, font)
    case FrameObserved{received, frame}: frame_result(received, frame, application, generation, realization, environment, font)
    case TypographyObserved{observation}: typography_result(State{application, generation, realization, environment, font}, observation)

def observed_surface(state: State) -> UI.Surface:
  State{application, generation, realization, environment, font} = state
  Order.ordered_surface(surface(application))

def observe(+state: State) -> SceneOutcome:
  scene_for_surface(state, observed_surface(state))

def effects(decision: Decision) -> +List<Effect>:
  Decision{state, product, effects} = decision
  effects

def step(input: Input, state: State) -> Decision:
  dispatch(state, input)
def frame_emits_no_effects(received: Nat, frame: Rendered.Frame, application: Platform.State,
  generation: Nat, realization: Rendered.State, environment: Design.Environment, font: F.State) ->
  {effects(step(FrameObserved{received, frame}, State{application, generation, realization, environment, font})) == Nil{} : +List<Effect>}:
  Platform.State{core, platform} = application
  {==}




def product(decision: Decision) -> Core.Decision:
  Decision{state, product, effects} = decision
  product

def platform_product(decision: Platform.Decision) -> Core.Decision:
  Platform.decision_product(decision)
def realized_product(decision: Platform.Decision, generation: Nat, environment: Design.Environment, font: F.State) ->
  {product(realized(decision, generation, environment, font)) == platform_product(decision) : Core.Decision}:
  match decision:
    case Platform.Decision{product, platform, effects}: {==}

def invalidated_product(decision: Platform.Decision, +generation: Nat, +environment: Design.Environment, +font: F.State) ->
  {product(invalidate(decision, generation, environment, font)) == platform_product(calibrated(decision, environment, F.retag(font, generation))) : Core.Decision}:
  realized_product(calibrated(decision, environment, F.retag(font, generation)), generation, environment, F.retag(font, generation))

def realization_preserves_product(+decision: Platform.Decision, +generation: Nat,
  +environment: Design.Environment, +font: F.State) ->
  {product(invalidate(decision, generation, environment, font)) == platform_product(decision) : Core.Decision}:
  Equal.trans(Core.Decision, product(invalidate(decision, generation, environment, font)),
    platform_product(calibrated(decision, environment, F.retag(font, generation))), platform_product(decision),
    invalidated_product(decision, generation, environment, font),
    Platform.reflow_preserves_product(decision,
      font_capacity(F.retag(font, generation), environment, Platform.next(decision))))

def stale_realization(+application: Platform.State, +generation: Nat, +previous: Rendered.State,
  +environment: Design.Environment, +font: F.State, +received: Nat, +frame: Rendered.Frame, +surface: UI.Surface,
  stale: {Nat.is_eq(generation, received) == False{} : Bool}) ->
  {frame_realization(State{application, generation, previous, environment, font}, received, frame, surface) == previous : Rendered.State}:
  Equal.cong(Bool, Rendered.State,
    (owned => observed_frame(owned, frame_surface(State{application, generation, previous, environment, font}, surface), generation, received, frame, previous)),
    Nat.is_eq(generation, received), False{}, stale)
