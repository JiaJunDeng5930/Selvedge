import Base
import ../../core/SYSTEM.bend as Core
import ../platform-rules.bend as Rule
import ../platform.bend as Model
import ../focus.bend as Focus
import ../../core/interface.bend as InterfaceView

def Rule.editing_retains_selection(revision, body, directory_entry, editor):
  {==}

# Capacity reconciliation uses the committed post-state without replaying its effects.

def Rule.merge_reflow_product(product, effects, refreshed):
  match refreshed:
    case Model.Decision{ignored, platform, reconciliation}: {==}

def Rule.changed_capacity_product(decision, capacity):
  Model.Decision{Core.Decision{+state, reply, runtime, interaction, services, durable}, Model.Platform{readers, editors, focused, ticket, reduced, old_capacity, scope}, effects} = decision
  Rule.merge_reflow_product(Core.Decision{state, reply, runtime, interaction, services, durable}, effects, Model.after_core(Model.unchanged(state),
    Model.Platform{readers, editors, focused, ticket, reduced, capacity, scope}))

def Rule.retained_capacity_product(same, decision, capacity):
  match same:
    case True{}: {==}
    case False{}: Rule.changed_capacity_product(decision, capacity)

def Rule.reflow_preserves_product(decision, capacity):
  Model.Decision{+product, Model.Platform{+readers, +editors, +focused, +ticket, +reduced, +old_capacity, +scope}, +effects} = decision
  Rule.retained_capacity_product(Model.same_capacity(old_capacity, capacity),
    Model.Decision{product, Model.Platform{readers, editors, focused, ticket, reduced, old_capacity, scope}, effects}, capacity)

def Rule.realized_preserves_product(decision):
  Model.Decision{Core.Decision{core, reply, runtime, interaction, services, durable},
    Model.Platform{readers, editors, focused, ticket, reduced, capacity, scope}, effects} = decision
  {==}

def Rule.realized_empty(product, platform):
  Core.Decision{core, reply, runtime, interaction, services, durable} = product
  Model.Platform{readers, editors, focused, ticket, reduced, capacity, scope} = platform
  {==}

def realized_focus(+found: Maybe<&2, String>, +ticket: Nat, +rest: +List<Model.Effect>) ->
  {Model.realized_product_focus(found, ticket, rest) == List.append(&2, Model.Effect, Rule.expected_focus(found, ticket), rest) : +List<Model.Effect>}:
  match found:
    case None{}: {==}
    case Some{key}: {==}

def effects_realized(+surface: InterfaceView.Surface, source: +List<Model.Effect>) ->
  {Model.realized_effects(surface, source) == Rule.expected_effects(surface, source) : +List<Model.Effect>}:
  match source:
    case Nil{}: {==}
    case Con{Model.Focus{+ticket, Focus.Product{+requested}}, +rest}:
      Equal.trans(+List<Model.Effect>,
        Model.realized_product_focus(InterfaceView.focus_target(surface, requested), ticket, Model.realized_effects(surface, rest)),
        List.append(&2, Model.Effect, Rule.expected_focus(InterfaceView.focus_target(surface, requested), ticket), Model.realized_effects(surface, rest)),
        List.append(&2, Model.Effect, Rule.expected_focus(InterfaceView.focus_target(surface, requested), ticket), Rule.expected_effects(surface, rest)),
        realized_focus(InterfaceView.focus_target(surface, requested), ticket, Model.realized_effects(surface, rest)),
        Equal.cong(+List<Model.Effect>, +List<Model.Effect>,
          (remaining => List.append(&2, Model.Effect, Rule.expected_focus(InterfaceView.focus_target(surface, requested), ticket), remaining)),
          Model.realized_effects(surface, rest), Rule.expected_effects(surface, rest), effects_realized(surface, rest)))
    case Con{Model.ScopeFocus{+ticket, +previous, +current}, +rest}:
      Equal.trans(+List<Model.Effect>,
        Model.realized_product_focus(InterfaceView.focus_target(surface, Focus.scope_target(previous, current, surface)), ticket, Model.realized_effects(surface, rest)),
        List.append(&2, Model.Effect, Rule.expected_focus(InterfaceView.focus_target(surface, Focus.scope_target(previous, current, surface)), ticket), Model.realized_effects(surface, rest)),
        List.append(&2, Model.Effect, Rule.expected_focus(InterfaceView.focus_target(surface, Focus.scope_target(previous, current, surface)), ticket), Rule.expected_effects(surface, rest)),
        realized_focus(InterfaceView.focus_target(surface, Focus.scope_target(previous, current, surface)), ticket, Model.realized_effects(surface, rest)),
        Equal.cong(+List<Model.Effect>, +List<Model.Effect>,
          (remaining => List.append(&2, Model.Effect, Rule.expected_focus(InterfaceView.focus_target(surface, Focus.scope_target(previous, current, surface)), ticket), remaining)),
          Model.realized_effects(surface, rest), Rule.expected_effects(surface, rest), effects_realized(surface, rest)))
    case Con{Model.Focus{+ticket, Focus.Content{+owner, +identity}}, +rest}:
      Equal.cong(+List<Model.Effect>, +List<Model.Effect>, (remaining => Model.Focus{ticket, Focus.Content{owner, identity}} <> remaining),
        Model.realized_effects(surface, rest), Rule.expected_effects(surface, rest), effects_realized(surface, rest))
    case Con{Model.ApplyReading{+task, +generation, +effect}, +rest}:
      Equal.cong(+List<Model.Effect>, +List<Model.Effect>, (remaining => Model.ApplyReading{task, generation, effect} <> remaining),
        Model.realized_effects(surface, rest), Rule.expected_effects(surface, rest), effects_realized(surface, rest))
    case Con{Model.Clipboard{+block, +effect}, +rest}:
      Equal.cong(+List<Model.Effect>, +List<Model.Effect>, (remaining => Model.Clipboard{block, effect} <> remaining),
        Model.realized_effects(surface, rest), Rule.expected_effects(surface, rest), effects_realized(surface, rest))

def actual_decision_effects(decision: Model.Decision) ->
  {Rule.effects(Model.realized_decision(decision)) == Rule.expected_effects(Rule.decision_surface(decision), Rule.effects(decision)) : +List<Model.Effect>}:
  Model.Decision{Core.Decision{+core, reply, runtime, interaction, services, durable},
    Model.Platform{readers, editors, focused, ticket, reduced, +capacity, scope}, effects} = decision
  effects_realized(InterfaceView.observe(capacity, core), effects)

def Rule.step_realizes_effects(input, state):
  actual_decision_effects(Model.step_raw(input, state))

def realized_focus_external(found: Maybe<&2, String>, ticket: Nat, +rest: +List<Model.Effect>,
  external: {Rule.external_effects(rest) == True{} : Bool}) ->
  {Rule.external_effects(Model.realized_product_focus(found, ticket, rest)) == True{} : Bool}:
  match found:
    case None{}: external
    case Some{key}: external

def Rule.realized_effects_are_external(surface, source):
  match source:
    case Nil{}: {==}
    case Con{Model.Focus{ticket, Focus.Product{requested}}, +rest}:
      realized_focus_external(InterfaceView.focus_target(surface, requested), ticket, Model.realized_effects(surface, rest),
        Rule.realized_effects_are_external(surface, rest))
    case Con{Model.ScopeFocus{ticket, previous, current}, +rest}:
      realized_focus_external(InterfaceView.focus_target(surface, Focus.scope_target(previous, current, surface)), ticket, Model.realized_effects(surface, rest),
        Rule.realized_effects_are_external(surface, rest))
    case Con{Model.Focus{ticket, Focus.Content{owner, identity}}, rest}: Rule.realized_effects_are_external(surface, rest)
    case Con{Model.ApplyReading{task, generation, effect}, rest}: Rule.realized_effects_are_external(surface, rest)
    case Con{Model.Clipboard{block, effect}, rest}: Rule.realized_effects_are_external(surface, rest)

def realized_decision_external(decision: Model.Decision) ->
  {Rule.external_effects(Rule.effects(Model.realized_decision(decision))) == True{} : Bool}:
  Model.Decision{Core.Decision{+core, reply, runtime, interaction, services, durable},
    Model.Platform{readers, editors, focused, ticket, reduced, +capacity, scope}, effects} = decision
  Rule.realized_effects_are_external(InterfaceView.observe(capacity, core), effects)

def Rule.actual_step_effects_are_external(input, state):
  realized_decision_external(Model.step_raw(input, state))

def and_right_false(value: Bool) -> {value && False{} == False{} : Bool}:
  match value:
    case False{}: {==}
    case True{}: {==}

def and_left_false(value: Bool) -> {False{} && value == False{} : Bool}:
  match value:
    case False{}: {==}
    case True{}: {==}

def and_left_true(value: Bool) -> {True{} && value == value : Bool}:
  match value:
    case False{}: {==}
    case True{}: {==}

def Rule.failed_focus_receipt(model_state, received, target, observed, failed):
  Model.State{+core, +platform} = model_state
  Core.State{+application, +services} = core
  Model.Platform{+readers, +editors, +focused, +ticket, +reduced, +capacity, +scope} = platform
  +accepted = Nat.is_eq(received, ticket) && Model.active_target(Core.State{application, services}, capacity, target)
  Equal.trans(Model.Decision,
    Model.step(Model.FocusApplied{received, target, observed}, Model.State{core, platform}),
    Model.realized_decision(Model.Decision{Model.unchanged(core), platform, Nil{}}),
    Model.Decision{Model.unchanged(core), platform, Nil{}},
    Equal.cong(Bool, Model.Decision,
      (confirmed => Model.realized_decision(Model.focus_result(confirmed, target, core, platform))),
      accepted && Model.focus_confirmed(target, observed), False{},
      Equal.trans(Bool, accepted && Model.focus_confirmed(target, observed), accepted && False{}, False{},
        Equal.cong(Bool, Bool, (confirmed => accepted && confirmed), Model.focus_confirmed(target, observed), False{}, failed),
        and_right_false(accepted))), Rule.realized_empty(Model.unchanged(core), platform))

def publication_raw_empty(+core: Core.State, +platform: Model.Platform, received: Nat, +target: Focus.Target,
  inactive: {Nat.is_eq(received, Rule.ticket(platform)) && Model.active_target(core, Rule.capacity(platform), target) == False{} : Bool}) ->
  {Model.step(Model.PublicationFocusObserved{received, Some{target}, None{}}, Model.State{core, platform}) == Model.Decision{Model.unchanged(core), platform, Nil{}} : Model.Decision}:
  Core.State{+application, +services} = core
  Model.Platform{+readers, +editors, +focused, +ticket, +reduced, +capacity, +scope} = platform
  Equal.trans(Model.Decision,
    Model.step(Model.PublicationFocusObserved{received, Some{target}, None{}}, Model.State{core, platform}),
    Model.realized_decision(Model.Decision{Model.unchanged(core), platform, Nil{}}),
    Model.Decision{Model.unchanged(core), platform, Nil{}},
    Equal.cong(Bool, Model.Decision,
      (owned => Model.realized_decision(Model.publication_focus_result(owned, ticket, target, core, platform))),
      Nat.is_eq(received, ticket) && Model.active_target(core, capacity, target), False{}, inactive),
    Rule.realized_empty(Model.unchanged(core), platform))

def Rule.publication_focus_after_some(model_state, received, before, after):
  Model.State{+core, +platform} = model_state
  match core:
    case Core.State{application, services}:
      match platform:
        case Model.Platform{readers, editors, focused, ticket, reduced, capacity, scope}:
          match before:
            case None{}: Rule.realized_empty(Model.unchanged(core), platform)
            case Some{target}: Rule.realized_empty(Model.unchanged(core), platform)

def Rule.publication_focus_before_none(model_state, received, after):
  Model.State{+core, +platform} = model_state
  match core:
    case Core.State{application, services}:
      match platform:
        case Model.Platform{readers, editors, focused, ticket, reduced, capacity, scope}:
          match after:
            case None{}: Rule.realized_empty(Model.unchanged(core), platform)
            case Some{target}: Rule.realized_empty(Model.unchanged(core), platform)

def Rule.publication_focus_stale(model_state, received, before, after, stale):
  Model.State{+core, +platform} = model_state
  match before after:
    case Some{+target} None{}:
      publication_raw_empty(core, platform, received, target,
        Equal.trans(Bool,
          Nat.is_eq(received, Rule.ticket(platform)) && Model.active_target(core, Rule.capacity(platform), target),
          False{} && Model.active_target(core, Rule.capacity(platform), target), False{},
          Equal.cong(Bool, Bool, (current => current && Model.active_target(core, Rule.capacity(platform), target)),
            Nat.is_eq(received, Rule.ticket(platform)), False{}, stale),
          and_left_false(Model.active_target(core, Rule.capacity(platform), target))))
    case None{} after: Rule.publication_focus_before_none(Model.State{core, platform}, received, after)
    case Some{target} Some{after}: Rule.publication_focus_after_some(Model.State{core, platform}, received, Some{target}, after)

def Rule.publication_focus_inactive(model_state, received, target, inactive):
  Model.State{+core, +platform} = model_state
  publication_raw_empty(core, platform, received, target,
    Equal.trans(Bool,
      Nat.is_eq(received, Rule.ticket(platform)) && Model.active_target(core, Rule.capacity(platform), target),
      Nat.is_eq(received, Rule.ticket(platform)) && False{}, False{},
      Equal.cong(Bool, Bool, (active => Nat.is_eq(received, Rule.ticket(platform)) && active),
        Model.active_target(core, Rule.capacity(platform), target), False{}, inactive),
      and_right_false(Nat.is_eq(received, Rule.ticket(platform)))))

def realized_loss_focus(found: Maybe<&2, String>, ticket: Nat) ->
  {Model.realized_product_focus(found, ticket, Nil{}) == Rule.expected_focus(found, ticket) : +List<Model.Effect>}:
  match found:
    case None{}: {==}
    case Some{key}: {==}

def realized_loss(+core: Core.State, +platform: Model.Platform, target: Focus.Target) ->
  {Model.realized_decision(Model.Decision{Model.unchanged(core), platform, [Model.Focus{Rule.ticket(platform), target}]}) == Model.Decision{Model.unchanged(core), platform, Rule.loss_effects(core, platform, target)} : Model.Decision}:
  Core.State{+application, +services} = core
  Model.Platform{readers, editors, focused, +ticket, reduced, +capacity, scope} = platform
  match target:
    case Focus.Product{identity}:
      Equal.cong(+List<Model.Effect>, Model.Decision,
        (effects => Model.Decision{Model.unchanged(core), platform, effects}),
        Model.realized_product_focus(InterfaceView.focus_target(InterfaceView.observe(capacity, core), identity), ticket, Nil{}),
        Rule.expected_focus(InterfaceView.focus_target(InterfaceView.observe(capacity, core), identity), ticket),
        realized_loss_focus(InterfaceView.focus_target(InterfaceView.observe(capacity, core), identity), ticket))
    case Focus.Content{owner, identity}: {==}

def Rule.publication_focus_loss(model_state, received, target, current, active):
  Model.State{+core, +platform} = model_state
  Core.State{+application, +services} = core
  Model.Platform{+readers, +editors, +focused, +ticket, +reduced, +capacity, +scope} = platform
  Equal.trans(Model.Decision,
    Model.step(Model.PublicationFocusObserved{received, Some{target}, None{}}, Model.State{core, platform}),
    Model.realized_decision(Model.Decision{Model.unchanged(core), platform, [Model.Focus{ticket, target}]}),
    Model.Decision{Model.unchanged(core), platform, Rule.loss_effects(core, platform, target)},
    Equal.cong(Bool, Model.Decision,
      (owned => Model.realized_decision(Model.publication_focus_result(owned, ticket, target, core, platform))),
      Nat.is_eq(received, ticket) && Model.active_target(core, capacity, target), True{},
      Equal.trans(Bool,
        Nat.is_eq(received, ticket) && Model.active_target(core, capacity, target),
        True{} && Model.active_target(core, capacity, target), True{},
        Equal.cong(Bool, Bool, (valid => valid && Model.active_target(core, capacity, target)), Nat.is_eq(received, ticket), True{}, current),
        Equal.trans(Bool, True{} && Model.active_target(core, capacity, target), Model.active_target(core, capacity, target), True{},
          and_left_true(Model.active_target(core, capacity, target)), active))),
    realized_loss(core, platform, target))
