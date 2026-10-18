import Base
import ./controls/GEOMETRY.bend as Geometry
import ../interaction/presentation/PROGRAM.bend as InterfaceView
import ./document/RENDERED.bend as Rendered
import ./document/SPEC.bend as Spec
import ./MODEL.bend as Model
import ./appearance/DESIGN.bend as Design
import ./appearance/FONT.bend as F
import ./runtime/PLATFORM.bend as Platform
import ./focus/MODEL.bend as Focus
import ../interaction/presentation/SURFACE.bend as SurfaceTypes
import ../interaction/TYPES.bend as InteractionTypes

law resolved_scope_focus:
  for +ticket: Nat
  for +previous: Focus.Scope
  for +current: Focus.Scope
  for +surface: SurfaceTypes.Surface
  {Model.resolved_effect(Platform.ScopeFocus{ticket, previous, current}, surface) ==
    Model.resolved_focus(ticket, InterfaceView.focus_target(surface, Focus.scope_target(previous, current, surface))) : +List<Model.Effect>}

law platform_scope_focus:
  for +ticket: Nat
  for +previous: Focus.Scope
  for +current: Focus.Scope
  for +rest: +List<Platform.Effect>
  for +surface: SurfaceTypes.Surface
  {Model.platform_effects(Platform.ScopeFocus{ticket, previous, current} <> rest, surface) ==
    List.append(&2, Model.Effect,
      Model.resolved_focus(ticket, InterfaceView.focus_target(surface, Focus.scope_target(previous, current, surface))),
      Model.platform_effects(rest, surface)) : +List<Model.Effect>}

law production_commit_preserves_product:
  for +decision: Platform.Decision
  for +generation: Nat
  for +environment: Design.Environment
  for +font: F.State
  {Model.product(Model.production_commit(decision, generation, environment, font)) == Model.platform_product(decision) : InteractionTypes.Decision}

law contextless_frame_silent:
  for +state: Model.State
  for +received: Nat
  for +frame: Rendered.Frame
  {Model.production_dispatch(state, Model.FrameObserved{received, frame}) ==
    Model.idle_state(state) : Model.Decision}

law observe_frame_exact:
  for +model_state: Model.State
  for +received: Nat
  for +surface: SurfaceTypes.Surface
  for +frame: Rendered.Frame
  {Model.observe_frame(received, surface, frame,
    model_state) ==
    Model.Decision{Model.with_realization(Rendered.observe(Model.generation(model_state), received, surface, frame, Model.realization(model_state)), model_state), Platform.unchanged(Platform.core(Model.application(model_state))),
      Model.frame_recovery_effects(Nat.is_eq(Model.generation(model_state), received), Platform.focus_ticket(Platform.platform(Model.application(model_state))), Model.generation(model_state), Model.frame_focus_recovery(surface, frame, Platform.scope(Platform.platform(Model.application(model_state)))))} : Model.Decision}

law visible_focus_recovery_visible:
  for +visible: Bool
  for +eligible: Bool
  for +identity: String
  {Model.visible_focus_recovery(True{}, visible, eligible, identity) == None{} : Maybe<&2, String>}

law visible_focus_recovery_hidden:
  for +focused: Bool
  for +eligible: Bool
  for +identity: String
  {Model.visible_focus_recovery(focused, False{}, eligible, identity) == None{} : Maybe<&2, String>}

law visible_focus_recovery_ineligible:
  for +focused: Bool
  for +visible: Bool
  for +identity: String
  {Model.visible_focus_recovery(focused, visible, False{}, identity) == None{} : Maybe<&2, String>}

law visible_focus_recovery_target:
  for +identity: String
  {Model.visible_focus_recovery(False{}, True{}, True{}, identity) == Some{identity} : Maybe<&2, String>}

law frame_focus_recovery_document:
  for +surface: SurfaceTypes.Surface
  for +frame: Rendered.Frame
  {Model.frame_focus_recovery(surface, frame, Focus.Document{}) == None{} : Maybe<&2, String>}

law frame_focus_recovery_unfocused:
  for +surface: SurfaceTypes.Surface
  for +viewport: Geometry.Rect
  for +elements: +List<Rendered.Element>
  for +tab_order: +List<String>
  for +native_focus: +List<Rendered.NativeFocus>
  for +scope: Focus.Scope
  {Model.frame_focus_recovery(surface, Rendered.Frame{viewport, elements, None{}, tab_order, native_focus}, scope) == None{} : Maybe<&2, String>}

law frame_focus_recovery_temporary:
  for +surface: SurfaceTypes.Surface
  for +viewport: Geometry.Rect
  for +elements: +List<Rendered.Element>
  for +key: String
  for +tab_order: +List<String>
  for +native_focus: +List<Rendered.NativeFocus>
  for +identity: String
  for +initial: String
  for +restore: String
  for +occurrence: Maybe<&2, Nat>
  {Model.frame_focus_recovery(surface, Rendered.Frame{viewport, elements, Some{key}, tab_order, native_focus},
    Focus.Temporary{identity, initial, restore, occurrence}) ==
    Model.visible_focus_recovery(Rendered.focus_visible(Rendered.find_element(elements, key), viewport),
      Rendered.focus_visible(Rendered.find_element(elements, identity), viewport),
      Platform.found_focus(InterfaceView.find_node(InterfaceView.active_nodes(surface), identity)), identity) : Maybe<&2, String>}

law frame_recovery_effects_stale:
  for +ticket: Nat
  for +generation: Nat
  for +target: Maybe<&2, String>
  {Model.frame_recovery_effects(False{}, ticket, generation, target) == Nil{} : +List<Model.Effect>}

law frame_recovery_effects_absent:
  for +owned: Bool
  for +ticket: Nat
  for +generation: Nat
  {Model.frame_recovery_effects(owned, ticket, generation, None{}) == Nil{} : +List<Model.Effect>}

law frame_recovery_effects_target:
  for +ticket: Nat
  for +generation: Nat
  for +identity: String
  {Model.frame_recovery_effects(True{}, ticket, generation, Some{identity}) ==
    [Model.PlatformEffect{Platform.Focus{ticket, Focus.Product{identity}}}, Model.MeasureFrame{generation}] : +List<Model.Effect>}

law observed_realization_sound:
  for +model_state: Model.State
  for +received: Nat
  for +surface: SurfaceTypes.Surface
  for +frame: Rendered.Frame
  for owned: {Nat.is_eq(Model.generation(model_state), received) == True{} : Bool}
  for realized: {Model.decision_realization(Model.observe_frame(received, surface, frame,
    model_state)) == Rendered.Realized{Model.generation(model_state), frame} : Rendered.State}
  {Spec.valid(surface, frame) == True{} : Bool}


def focus_delivery(ticket: Nat, selected: Maybe<&2, String>) -> +List<Model.Effect>:
  match selected:
    case None{}: Nil{}
    case Some{identity}: [Model.PlatformEffect{Platform.Focus{ticket, Focus.Product{identity}}}]

def content_focus_delivery(owned: Bool, ticket: Nat, owner: String, identity: String) -> +List<Model.Effect>:
  match owned:
    case False{}: Nil{}
    case True{}: [Model.PlatformEffect{Platform.Focus{ticket, Focus.Content{owner, identity}}}]

# Focus requests resolve in the current interaction scope. Missing product
# targets and content outside that scope deliver no physical focus command.
# Reading and clipboard commands retain their complete payloads and order.
def delivered_effect(effect: Platform.Effect, +surface: SurfaceTypes.Surface) -> +List<Model.Effect>:
  match effect:
    case Platform.Focus{ticket, Focus.Product{requested}}:
      focus_delivery(ticket, InterfaceView.focus_target(surface, requested))
    case Platform.Focus{ticket, Focus.Content{+owner, identity}}:
      content_focus_delivery(Platform.found_content_owner(InterfaceView.find_node(InterfaceView.active_nodes(surface), owner)), ticket, owner, identity)
    case Platform.ScopeFocus{ticket, previous, current}:
      focus_delivery(ticket, InterfaceView.focus_target(surface, Focus.scope_target(previous, current, surface)))
    case Platform.ApplyReading{task, generation, effect}:
      [Model.PlatformEffect{Platform.ApplyReading{task, generation, effect}}]
    case Platform.Clipboard{block, effect}:
      [Model.PlatformEffect{Platform.Clipboard{block, effect}}]

def delivered_effects(effects: +List<Platform.Effect>, +surface: SurfaceTypes.Surface) -> +List<Model.Effect>:
  match effects:
    case Nil{}: Nil{}
    case Con{effect, rest}:
      List.append(&2, Model.Effect, delivered_effect(effect, surface), delivered_effects(rest, surface))

def committed_decision(decision: Platform.Decision, +generation: Nat, +environment: Design.Environment, +font: F.State) -> Model.Decision:
  Platform.Decision{+product, platform, +source} = decision
  InteractionTypes.Decision{core, reply, runtime, interaction, services, durable} = product
  +next: Model.State = Model.State{Platform.State{core, platform}, generation,
    Rendered.AwaitingFrame{generation}, environment, F.retag(font, generation)}
  Model.Decision{next, product, delivered_effects(source, Model.observed_surface(next))}

law production_commit_complete:
  for +decision: Platform.Decision
  for +generation: Nat
  for +environment: Design.Environment
  for +font: F.State
  {Model.production_commit(decision, generation, environment, font) == committed_decision(decision, generation, environment, font) : Model.Decision}
