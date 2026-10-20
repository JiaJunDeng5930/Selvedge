import Base
import ./appearance/FONT.bend as F
import ./focus/MODEL.bend as Focus
import ./MODEL.bend as Model
import ./document/RENDERED.bend as Rendered
import ./document/SPEC.bend as Spec
import ./document/CONTRACT.bend as RenderRules
import ./model-rules.bend as Rule
import ./runtime/PLATFORM.bend as Platform
import ../interaction/presentation/PROGRAM.bend as InterfaceView
import ../interaction/presentation/SURFACE.bend as SurfaceTypes
import ../interaction/TYPES.bend as InteractionTypes
import ../interaction/STATE.bend as Core

def Rule.history_message_location(task, message_index, application): {==}

def Rule.resolved_scope_focus(ticket, previous, current, surface): {==}

def Rule.platform_scope_focus(ticket, previous, current, rest, surface): {==}

def Rule.production_commit_preserves_product(decision, generation, environment, font):
  match decision:
    case Platform.Decision{product, platform, effects}: {==}

def Rule.contextless_frame_silent(state, received, frame):
  match state:
    case Model.State{application, generation, realization, environment, font}: {==}

def Rule.observe_frame_exact(model_state, received, surface, frame):
  Model.State{Platform.State{+core, Platform.Platform{+readers, +editors, +focused, +ticket, +reduced, +capacity, +scope}}, +generation, +previous, +environment, +font} = model_state
  {==}

def Rule.visible_focus_recovery_visible(visible, eligible, identity): {==}

def Rule.visible_focus_recovery_hidden(focused, eligible, identity):
  match focused:
    case False{}: {==}
    case True{}: {==}

def Rule.visible_focus_recovery_ineligible(focused, visible, identity):
  match focused visible:
    case False{} False{}: {==}
    case False{} True{}: {==}
    case True{} _: {==}

def Rule.visible_focus_recovery_target(identity): {==}

def Rule.frame_focus_recovery_document(surface, frame):
  match frame:
    case Rendered.Frame{viewport, elements, focused, tab_order, native_focus}: {==}

def Rule.frame_focus_recovery_unfocused(surface, viewport, elements, tab_order, native_focus, scope):
  match scope:
    case Focus.Document{}: {==}
    case Focus.Temporary{identity, initial, restore, occurrence}: {==}

def Rule.frame_focus_recovery_temporary(surface, viewport, elements, key, tab_order, native_focus, identity, initial, restore, occurrence): {==}

def Rule.frame_recovery_effects_stale(ticket, generation, target): {==}

def Rule.frame_recovery_effects_absent(owned, ticket, generation):
  match owned:
    case False{}: {==}
    case True{}: {==}

def Rule.frame_recovery_effects_target(ticket, generation, identity): {==}

def observation_sound(requirements: RenderRules.Requirements, +generation: Nat, +received: Nat,
  +surface: SurfaceTypes.Surface, +frame: Rendered.Frame, +previous: Rendered.State,
  owned: {Nat.is_eq(generation, received) == True{} : Bool},
  realized: {Rendered.observe(generation, received, surface, frame, previous) == Rendered.Realized{generation, frame} : Rendered.State}) ->
  {Spec.valid(surface, frame) == True{} : Bool}:
  match requirements:
    case RenderRules.Requirements{reflection, sound}: sound(generation, received, surface, frame, previous, owned, realized)

def Rule.observed_realization_sound(model_state, received, surface, frame, owned, realized):
  Model.State{+application, +generation, +previous, +environment, +font} = model_state
  match application:
    case Platform.State{core, Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope}}:
      observation_sound(RenderRules.evidence, generation, received, surface, frame, previous, owned, realized)


def focus_delivery_policy(ticket: Nat, selected: Maybe<&2, String>) ->
  {Model.resolved_focus(ticket, selected) == Rule.focus_delivery(ticket, selected) : +List<Model.Effect>}:
  match selected:
    case None{}: {==}
    case Some{identity}: {==}

def content_focus_delivery_policy(owned: Bool, ticket: Nat, owner: String, identity: String) ->
  {Model.resolved_content_focus(owned, ticket, owner, identity) == Rule.content_focus_delivery(owned, ticket, owner, identity) : +List<Model.Effect>}:
  match owned:
    case False{}: {==}
    case True{}: {==}

def resolved_effect_delivery(+effect: Platform.Effect, +surface: SurfaceTypes.Surface) ->
  {Model.resolved_effect(effect, surface) == Rule.delivered_effect(effect, surface) : +List<Model.Effect>}:
  match effect:
    case Platform.Focus{ticket, Focus.Product{requested}}:
      focus_delivery_policy(ticket, InterfaceView.focus_target(surface, requested))
    case Platform.Focus{ticket, Focus.Content{+owner, identity}}:
      content_focus_delivery_policy(Platform.found_content_owner(InterfaceView.find_node(InterfaceView.active_nodes(surface), owner)), ticket, owner, identity)
    case Platform.ScopeFocus{ticket, previous, current}:
      focus_delivery_policy(ticket, InterfaceView.focus_target(surface, Focus.scope_target(previous, current, surface)))
    case Platform.ApplyReading{task, generation, effect}: {==}
    case Platform.Clipboard{block, effect}: {==}
    case Platform.ObserveSkillCatalog{key, ticket, workspace_key, workspace}: {==}
    case Platform.SetEditorSelection{key, selection}: {==}

def platform_effect_delivery(+source: +List<Platform.Effect>, +surface: SurfaceTypes.Surface) ->
  {Model.platform_effects(source, surface) == Rule.delivered_effects(source, surface) : +List<Model.Effect>}:
  match source:
    case Nil{}: {==}
    case Con{+first, +rest}:
      Equal.trans((+List<Model.Effect>),
        List.append(&2, Model.Effect, Model.resolved_effect(first, surface), Model.platform_effects(rest, surface)),
        List.append(&2, Model.Effect, Rule.delivered_effect(first, surface), Model.platform_effects(rest, surface)),
        Rule.delivered_effects(first <> rest, surface),
        Equal.cong((+List<Model.Effect>), (+List<Model.Effect>),
          (head => List.append(&2, Model.Effect, head, Model.platform_effects(rest, surface))),
          Model.resolved_effect(first, surface), Rule.delivered_effect(first, surface), resolved_effect_delivery(first, surface)),
        Equal.cong((+List<Model.Effect>), (+List<Model.Effect>),
          (tail => List.append(&2, Model.Effect, Rule.delivered_effect(first, surface), tail)),
          Model.platform_effects(rest, surface), Rule.delivered_effects(rest, surface), platform_effect_delivery(rest, surface)))

def deferred_effect_delivery(+source: +List<Platform.Effect>, +surface: SurfaceTypes.Surface) ->
  {Model.deferred_platform_effects(source, (_ => surface)) == Rule.delivered_effects(source, surface) : +List<Model.Effect>}:
  match source:
    case Nil{}: {==}
    case Con{Platform.Focus{+ticket, +target}, +rest}:
      platform_effect_delivery(Platform.Focus{ticket, target} <> rest, surface)
    case Con{Platform.ScopeFocus{+ticket, +previous, +current}, +rest}:
      platform_effect_delivery(Platform.ScopeFocus{ticket, previous, current} <> rest, surface)
    case Con{Platform.ApplyReading{+task, +generation, +effect}, +rest}:
      Equal.cong(+List<Model.Effect>, +List<Model.Effect>, (tail => Model.PlatformEffect{Platform.ApplyReading{task, generation, effect}} <> tail),
        Model.deferred_platform_effects(rest, (_ => surface)), Rule.delivered_effects(rest, surface), deferred_effect_delivery(rest, surface))
    case Con{Platform.Clipboard{+block, +effect}, +rest}:
      Equal.cong(+List<Model.Effect>, +List<Model.Effect>, (tail => Model.PlatformEffect{Platform.Clipboard{block, effect}} <> tail),
        Model.deferred_platform_effects(rest, (_ => surface)), Rule.delivered_effects(rest, surface), deferred_effect_delivery(rest, surface))
    case Con{Platform.ObserveSkillCatalog{+key, +ticket, +workspace_key, +workspace}, +rest}:
      Equal.cong(+List<Model.Effect>, +List<Model.Effect>, (tail => Model.PlatformEffect{Platform.ObserveSkillCatalog{key, ticket, workspace_key, workspace}} <> tail),
        Model.deferred_platform_effects(rest, (_ => surface)), Rule.delivered_effects(rest, surface), deferred_effect_delivery(rest, surface))
    case Con{Platform.SetEditorSelection{+key, +selection}, +rest}:
      Equal.cong(+List<Model.Effect>, +List<Model.Effect>, (tail => Model.PlatformEffect{Platform.SetEditorSelection{key, selection}} <> tail),
        Model.deferred_platform_effects(rest, (_ => surface)), Rule.delivered_effects(rest, surface), deferred_effect_delivery(rest, surface))

def Rule.production_commit_complete(decision, generation, environment, font):
  Platform.Decision{+product, +platform, +source} = decision
  InteractionTypes.Decision{+core, reply, runtime, +interaction, services, durable} = product
  +application: Platform.State = Platform.next(Platform.Decision{product, platform, source})
  Equal.cong(+List<Model.Effect>, Model.Decision,
    (result => Model.Decision{Model.State{application, generation, Rendered.AwaitingFrame{generation}, environment, F.retag(font, generation)}, product,
      List.append(&2, Model.Effect, result, Model.history_location_effects(interaction, Core.application(core)))}),
    Model.deferred_platform_effects(source, (_ => Model.observed_surface(Model.State{application, generation, Rendered.AwaitingFrame{generation}, environment, font}))),
    Rule.delivered_effects(source, Model.observed_surface(Model.State{application, generation, Rendered.AwaitingFrame{generation}, environment, font})),
    deferred_effect_delivery(source, Model.observed_surface(Model.State{application, generation, Rendered.AwaitingFrame{generation}, environment, font})))
