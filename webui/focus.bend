import Base
import ../core/interface.bend as UI
import ../core/SYSTEM.bend as Core
import ../core/user-experience.bend as E
import ../core/user-input.bend as U
import ../core/ui-world.bend as View
import ../core/client-services.bend as Services

type Scope is Data:
  Document{}
  Temporary{identity: String, initial: String, restore: String}

def identity(scope: Scope) -> String:
  match scope:
    case Document{}: "document"
    case Temporary{id, initial, restore}: id

def initial(scope: Scope) -> String:
  match scope:
    case Document{}: "page-heading"
    case Temporary{id, target, restore}: target

def restore(scope: Scope) -> String:
  match scope:
    case Document{}: "page-heading"
    case Temporary{id, target, trigger}: trigger

def details_scope(beside: Bool, initial: String, trigger: String) -> Scope:
  match beside:
    case True{}: Document{}
    case False{}: Temporary{"task-details", initial, trigger}

def panel_scope(panel: U.Panel, initial: String, trigger: String, beside: Bool) -> Scope:
  match panel:
    case U.TaskDetails{task}: details_scope(beside, initial, trigger)
    case other: Temporary{E.panel_target(other), initial, trigger}

def layer_scope(layers: +List<E.Layer>, beside: Bool) -> Scope:
  match layers:
    case Nil{}: Document{}
    case Con{E.Layer{panel, trigger, initial, query}, rest}: panel_scope(panel, initial, trigger, beside)

def settings_scope(open: Bool, fallback: Scope) -> Scope:
  match open:
    case True{}: Temporary{"settings", "settings/credential", "settings/open"}
    case False{}: fallback

def preview_scope(preview: Services.Preview, fallback: Scope) -> Scope:
  match preview:
    case Services.NoPreview{}: fallback
    case Services.LoadingPreview{ticket, file, trigger}: Temporary{"attachment-preview", "attachment-preview/close", trigger}
    case Services.ReadyPreview{file, resource, image, trigger}: Temporary{"attachment-preview", "attachment-preview/close", trigger}
    case Services.FailedPreview{file, reason, trigger}: Temporary{"attachment-preview", "attachment-preview/close", trigger}

def logical_scope(state: Core.State, capacity: View.Capacity) -> Scope:
  Core.State{E.Application{program, E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks}},
    Services.State{access, credential, settings, appearance, next_service, transfers, preview}} = state
  View.Capacity{navigation_beside, details_beside} = capacity
  preview_scope(preview, settings_scope(settings, layer_scope(layers, details_beside)))

def changed(previous: Scope, current: Scope) -> Bool:
  Bool.not(String.eq(identity(previous), identity(current)))

def change_target(previous: Scope, current: Scope) -> String:
  match current:
    case Document{}: restore(previous)
    case Temporary{id, initial, trigger}: initial

def contains(scope: Scope, observed_owner: String) -> Bool:
  match scope:
    case Document{}: True{}
    case Temporary{id, initial, trigger}: String.eq(id, observed_owner)

def permits_composer(scope: Scope) -> Bool:
  match scope:
    case Document{}: True{}
    case _: False{}

def resolved_target(found: Maybe<&2, String>) -> String:
  match found:
    case Some{key}: key
    case None{}: ""

def choose_scope(active: Maybe<&2, String>, surface: UI.Surface, +scope: Scope) -> Scope:
  match active:
    case None{}: Document{}
    case Some{key}: Temporary{key, resolved_target(UI.focus_target(surface, initial(scope))), restore(scope)}

def realized_scope(+surface: UI.Surface, scope: Scope) -> Scope:
  UI.Surface{content, base, overlays, +active} = surface
  choose_scope(active, surface, scope)

def current(+state: Core.State, +capacity: View.Capacity) -> Scope:
  realized_scope(UI.observe(capacity, state), logical_scope(state, capacity))
