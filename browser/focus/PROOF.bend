import Base
import ./CONTRACT.bend as Rule
import ./MODEL.bend as Model
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ../../interaction/IDENTITY.bend as Identity
import ../../interaction/services/MODEL.bend as Services
import ../../interaction/STATE.bend as Core
import ../../interaction/session/MODEL.bend as E
import ../../interaction/presentation/MODEL.bend as View

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
    InterfaceView.all_focus_target(InterfaceView.Surface{content, base, overlays, Some{active}}, Model.restore(scope)), Some{Identity.encode(key)}, found)

def Rule.settings_restore(content, base, overlays, active, fallback):
  {==}

def Rule.settings_resolved_restore(content, base, overlays, active, fallback, key, found):
  Rule.realized_restore(content, base, overlays, active, Model.settings_scope(True{}, fallback), key, found)


def Rule.document_restores_previous(previous, surface): {==}

def Rule.document_opens_temporary(identity, initial, restore, occurrence, surface): {==}

def Rule.nested_scope_restores_active_trigger(old_identity, old_initial, old_occurrence, trigger, identity, initial, restore, occurrence, surface, key, found):
  Equal.cong(Maybe<&2, String>, String, (candidate => Model.scope_restore_target(candidate, initial)),
    InterfaceView.matching_focus(InterfaceView.active_nodes(surface), trigger), Some{key}, found)

def Rule.nested_scope_without_active_trigger_uses_initial(old_identity, old_initial, old_occurrence, trigger, identity, initial, restore, occurrence, surface, absent):
  Equal.cong(Maybe<&2, String>, String, (candidate => Model.scope_restore_target(candidate, initial)),
    InterfaceView.matching_focus(InterfaceView.active_nodes(surface), trigger), None{}, absent)


def Rule.panel_policy(panel, initial, trigger, beside): {==}
def Rule.persistent_scope(action, identity, initial, trigger, beside):
  match beside:
    case True{}: {==}
    case False{}: {==}
def Rule.temporary_scope(action, identity, initial, trigger, beside): {==}
def Rule.settings_policy(open, fallback):
  match open:
    case True{}: {==}
    case False{}: {==}
def Rule.preview_policy(preview, fallback):
  match preview:
    case Services.NoPreview{}: {==}
    case Services.LoadingPreview{ticket, file, trigger}: {==}
    case Services.ReadyPreview{file, resource, image, trigger}: {==}
    case Services.FailedPreview{file, reason, trigger}: {==}
def Rule.directory_policy(picker, fallback):
  match picker:
    case Services.NoDirectoryPicker{}: {==}
    case Services.ReadyDirectory{ticket, editor, catalog, location, trigger}: {==}
    case Services.LoadingDirectory{ticket, editor, path, trigger}: {==}
    case Services.FailedDirectory{ticket, editor, path, reason, trigger}: {==}
def Rule.realized_document(content, base, overlays, scope): {==}
def Rule.realized_active(content, base, overlays, active, scope): {==}
def Rule.current_scope(state, capacity): {==}


def Rule.logical_priority(state, capacity):
  match state capacity:
    case Core.State{E.Application{program, E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}}, Services.State{access, credential, settings, appearance, next_service, transfers, preview, directory_picker}} View.Capacity{navigation_beside, details_beside}: {==}

def Rule.current_surface(state, capacity, surface, observed):
  Equal.cong(InterfaceView.Surface, Model.Scope, (actual => Model.realized_scope(actual, Model.logical_scope(state, capacity))), InterfaceView.observe(capacity, state), surface, observed)
