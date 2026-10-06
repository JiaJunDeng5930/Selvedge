import Base
import ../focus-rules.bend as Rule
import ../focus.bend as Model
import ../../core/interface.bend as UI
import ../../core/ui-identity.bend as Identity

def Rule.cycle_evidence():
  Rule.CycleRequirements{order => focused => reverse => {==}, +key => +focused => previous => +first => +last => matching =>
      Equal.cong(Bool, Maybe<&2, String>,
        (hit => Model.cycle_match(hit, False{}, previous, Nil{}, first, last, first)),
        String.eq(key, focused), True{}, matching)
    , +key => +rest => +focused => matching =>
      Equal.cong(Bool, Maybe<&2, String>,
        (hit => Model.cycle_match(hit, True{}, None{}, rest, Some{key},
          List.head(&2, String, List.reverse(&2, String, key <> rest)),
          Model.cycle_scan(rest, focused, Some{key}, Some{key}, List.head(&2, String, List.reverse(&2, String, key <> rest)), True{}))),
        String.eq(key, focused), True{}, matching)
    }

def Rule.realized_restore(content, base, overlays, active, scope, key, found):
  Equal.cong(Maybe<&2, String>, String, Model.resolved_target,
    UI.all_focus_target(UI.Surface{content, base, overlays, Some{active}}, Model.restore(scope)), Some{Identity.encode(key)}, found)

def Rule.settings_restore(content, base, overlays, active, fallback):
  {==}

def Rule.settings_resolved_restore(content, base, overlays, active, fallback, key, found):
  Rule.realized_restore(content, base, overlays, active, Model.settings_scope(True{}, fallback), key, found)


def Rule.document_restores_previous(previous, surface): {==}

def Rule.document_opens_temporary(identity, initial, restore, occurrence, surface): {==}

def Rule.nested_scope_restores_active_trigger(old_identity, old_initial, old_occurrence, trigger, identity, initial, restore, occurrence, surface, key, found):
  Equal.cong(Maybe<&2, String>, String, (candidate => Model.scope_restore_target(candidate, initial)),
    UI.matching_focus(UI.active_nodes(surface), trigger), Some{key}, found)

def Rule.nested_scope_without_active_trigger_uses_initial(old_identity, old_initial, old_occurrence, trigger, identity, initial, restore, occurrence, surface, absent):
  Equal.cong(Maybe<&2, String>, String, (candidate => Model.scope_restore_target(candidate, initial)),
    UI.matching_focus(UI.active_nodes(surface), trigger), None{}, absent)
