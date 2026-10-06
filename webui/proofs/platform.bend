import Base
import ../../core/SYSTEM.bend as Core
import ../platform-rules.bend as Rule
import ../platform.bend as Model
import ../focus.bend as Focus
import ../../core/interface.bend as UI

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

def effects_realized(+surface: UI.Surface, source: +List<Model.Effect>) ->
  {Model.realized_effects(surface, source) == Rule.expected_effects(surface, source) : +List<Model.Effect>}:
  match source:
    case Nil{}: {==}
    case Con{Model.Focus{+ticket, Focus.Product{+requested}}, +rest}:
      Equal.trans(+List<Model.Effect>,
        Model.realized_product_focus(UI.focus_target(surface, requested), ticket, Model.realized_effects(surface, rest)),
        List.append(&2, Model.Effect, Rule.expected_focus(UI.focus_target(surface, requested), ticket), Model.realized_effects(surface, rest)),
        List.append(&2, Model.Effect, Rule.expected_focus(UI.focus_target(surface, requested), ticket), Rule.expected_effects(surface, rest)),
        realized_focus(UI.focus_target(surface, requested), ticket, Model.realized_effects(surface, rest)),
        Equal.cong(+List<Model.Effect>, +List<Model.Effect>,
          (remaining => List.append(&2, Model.Effect, Rule.expected_focus(UI.focus_target(surface, requested), ticket), remaining)),
          Model.realized_effects(surface, rest), Rule.expected_effects(surface, rest), effects_realized(surface, rest)))
    case Con{Model.ScopeFocus{+ticket, +previous, +current}, +rest}:
      Equal.trans(+List<Model.Effect>,
        Model.realized_product_focus(UI.focus_target(surface, Focus.scope_target(previous, current, surface)), ticket, Model.realized_effects(surface, rest)),
        List.append(&2, Model.Effect, Rule.expected_focus(UI.focus_target(surface, Focus.scope_target(previous, current, surface)), ticket), Model.realized_effects(surface, rest)),
        List.append(&2, Model.Effect, Rule.expected_focus(UI.focus_target(surface, Focus.scope_target(previous, current, surface)), ticket), Rule.expected_effects(surface, rest)),
        realized_focus(UI.focus_target(surface, Focus.scope_target(previous, current, surface)), ticket, Model.realized_effects(surface, rest)),
        Equal.cong(+List<Model.Effect>, +List<Model.Effect>,
          (remaining => List.append(&2, Model.Effect, Rule.expected_focus(UI.focus_target(surface, Focus.scope_target(previous, current, surface)), ticket), remaining)),
          Model.realized_effects(surface, rest), Rule.expected_effects(surface, rest), effects_realized(surface, rest)))
    case Con{Model.Focus{+ticket, Focus.Content{+owner, +identity}}, +rest}:
      Equal.cong(+List<Model.Effect>, +List<Model.Effect>, (remaining => Model.Focus{ticket, Focus.Content{owner, identity}} <> remaining),
        Model.realized_effects(surface, rest), Rule.expected_effects(surface, rest), effects_realized(surface, rest))
    case Con{Model.Scroll{+task, +generation, +effect}, +rest}:
      Equal.cong(+List<Model.Effect>, +List<Model.Effect>, (remaining => Model.Scroll{task, generation, effect} <> remaining),
        Model.realized_effects(surface, rest), Rule.expected_effects(surface, rest), effects_realized(surface, rest))
    case Con{Model.Clipboard{+block, +effect}, +rest}:
      Equal.cong(+List<Model.Effect>, +List<Model.Effect>, (remaining => Model.Clipboard{block, effect} <> remaining),
        Model.realized_effects(surface, rest), Rule.expected_effects(surface, rest), effects_realized(surface, rest))

def actual_decision_effects(decision: Model.Decision) ->
  {Rule.effects(Model.realized_decision(decision)) == Rule.expected_effects(Rule.decision_surface(decision), Rule.effects(decision)) : +List<Model.Effect>}:
  Model.Decision{Core.Decision{+core, reply, runtime, interaction, services, durable},
    Model.Platform{readers, editors, focused, ticket, reduced, +capacity, scope}, effects} = decision
  effects_realized(UI.observe(capacity, core), effects)

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
      realized_focus_external(UI.focus_target(surface, requested), ticket, Model.realized_effects(surface, rest),
        Rule.realized_effects_are_external(surface, rest))
    case Con{Model.ScopeFocus{ticket, previous, current}, +rest}:
      realized_focus_external(UI.focus_target(surface, Focus.scope_target(previous, current, surface)), ticket, Model.realized_effects(surface, rest),
        Rule.realized_effects_are_external(surface, rest))
    case Con{Model.Focus{ticket, Focus.Content{owner, identity}}, rest}: Rule.realized_effects_are_external(surface, rest)
    case Con{Model.Scroll{task, generation, effect}, rest}: Rule.realized_effects_are_external(surface, rest)
    case Con{Model.Clipboard{block, effect}, rest}: Rule.realized_effects_are_external(surface, rest)

def realized_decision_external(decision: Model.Decision) ->
  {Rule.external_effects(Rule.effects(Model.realized_decision(decision))) == True{} : Bool}:
  Model.Decision{Core.Decision{+core, reply, runtime, interaction, services, durable},
    Model.Platform{readers, editors, focused, ticket, reduced, +capacity, scope}, effects} = decision
  Rule.realized_effects_are_external(UI.observe(capacity, core), effects)

def Rule.actual_step_effects_are_external(input, state):
  realized_decision_external(Model.step_raw(input, state))
