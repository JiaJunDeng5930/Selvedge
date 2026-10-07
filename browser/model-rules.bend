import Base
import ../bendlib/association-map.bend as Finite
import ../interaction/presentation/MODEL.bend as View
import ./reading/MODEL.bend as Reading
import ./editor/MODEL.bend as Editor
import ./controls/GEOMETRY.bend as Geometry
import ../interaction/presentation/PROGRAM.bend as InterfaceView
import ./document/RENDERED.bend as Rendered
import ./document/SPEC.bend as Spec
import ../interaction/STATE.bend as Core
import ./MODEL.bend as Model
import ./appearance/DESIGN.bend as Design
import ./appearance/FONT.bend as F
import ./runtime/PLATFORM.bend as Platform
import ./focus/MODEL.bend as Focus
law resolved_scope_focus:
  for +ticket: Nat
  for +previous: Focus.Scope
  for +current: Focus.Scope
  for +surface: InterfaceView.Surface
  {Model.resolved_effect(Platform.ScopeFocus{ticket, previous, current}, surface) ==
    Model.resolved_focus(ticket, InterfaceView.focus_target(surface, Focus.scope_target(previous, current, surface))) : +List<Model.Effect>}
law platform_scope_focus:
  for +ticket: Nat
  for +previous: Focus.Scope
  for +current: Focus.Scope
  for +rest: +List<Platform.Effect>
  for +surface: InterfaceView.Surface
  {Model.platform_effects(Platform.ScopeFocus{ticket, previous, current} <> rest, surface) ==
    List.append(&2, Model.Effect,
      Model.resolved_focus(ticket, InterfaceView.focus_target(surface, Focus.scope_target(previous, current, surface))),
      Model.platform_effects(rest, surface)) : +List<Model.Effect>}
law production_commit_preserves_product:
  for +decision: Platform.Decision
  for +generation: Nat
  for +environment: Design.Environment
  for +font: F.State
  {Model.product(Model.production_commit(decision, generation, environment, font)) == Model.platform_product(decision) : Core.Decision}
law contextless_frame_silent:
  for +state: Model.State
  for +received: Nat
  for +frame: Rendered.Frame
  {Model.production_dispatch(state, Model.FrameObserved{received, frame}) ==
    Model.idle_state(state) : Model.Decision}
law observe_frame_exact:
  for +model_state: Model.State
  for +received: Nat
  for +surface: InterfaceView.Surface
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
  for +surface: InterfaceView.Surface
  for +frame: Rendered.Frame
  {Model.frame_focus_recovery(surface, frame, Focus.Document{}) == None{} : Maybe<&2, String>}
law frame_focus_recovery_unfocused:
  for +surface: InterfaceView.Surface
  for +viewport: Geometry.Rect
  for +elements: +List<Rendered.Element>
  for +tab_order: +List<String>
  for +native_focus: +List<Rendered.NativeFocus>
  for +scope: Focus.Scope
  {Model.frame_focus_recovery(surface, Rendered.Frame{viewport, elements, None{}, tab_order, native_focus}, scope) == None{} : Maybe<&2, String>}
law frame_focus_recovery_temporary:
  for +surface: InterfaceView.Surface
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
  for +surface: InterfaceView.Surface
  for +frame: Rendered.Frame
  for owned: {Nat.is_eq(Model.generation(model_state), received) == True{} : Bool}
  for realized: {Model.decision_realization(Model.observe_frame(received, surface, frame,
    model_state)) == Rendered.Realized{Model.generation(model_state), frame} : Rendered.State}
  {Spec.valid(surface, frame) == True{} : Bool}
