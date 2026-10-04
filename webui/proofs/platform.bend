import Base
import ../../core/SYSTEM.bend as Core
import ../platform-rules.bend as Rule
import ../platform.bend as Model

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
