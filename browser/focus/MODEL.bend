import Base
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ../../interaction/STATE.bend as Core
import ../../interaction/session/MODEL.bend as E
import ../../interaction/INPUT.bend as U
import ../../interaction/presentation/MODEL.bend as View
import ../../interaction/services/MODEL.bend as Services
type Target is Data:
  Product{identity: String}
  Content{owner: String, identity: String}
def same_target(first: Target, second: Target) -> Bool:
  match first second:
    case Product{first} Product{second}: String.eq(first, second)
    case Content{first_owner, first} Content{second_owner, second}: String.eq(first_owner, second_owner) && String.eq(first, second)
    case _ _: False{}

def target_key(target: Target) -> String:
  match target:
    case Product{identity}: identity
    case Content{owner, identity}: identity

type Scope is Data:
  Document{}
  Temporary{identity: String, initial: String, restore: String, occurrence: Maybe<&2, Nat>}
def identity(scope: Scope) -> String:
  match scope:
    case Document{}: "document"
    case Temporary{id, initial, restore, occurrence}: id

def initial(scope: Scope) -> String:
  match scope:
    case Document{}: "page-heading"
    case Temporary{id, target, restore, occurrence}: target

def restore(scope: Scope) -> String:
  match scope:
    case Document{}: "page-heading"
    case Temporary{id, target, trigger, occurrence}: trigger

def dismissal_scope(dismissal: View.Dismissal, identity: String, initial: String, trigger: String, beside: Bool) -> Scope:
  match dismissal:
    case View.ByTrigger{action}:
      match beside:
        case True{}: Document{}
        case False{}: Temporary{identity, initial, trigger, None{}}
    case View.OutsideOrEscape{action}: Temporary{identity, initial, trigger, None{}}

def panel_scope(+panel: U.Panel, initial: String, +trigger: String, beside: Bool) -> Scope:
  dismissal_scope(View.layer_dismissal(panel, trigger), E.panel_target(panel), initial, trigger, beside)

def scope_occurrence(scope: Scope, occurrence: Nat) -> Scope:
  match scope:
    case Document{}: Document{}
    case Temporary{identity, initial, restore, old_occurrence}: Temporary{identity, initial, restore, Some{occurrence}}

def layer_scope(layers: +List<E.Layer>, beside: Bool) -> Scope:
  match layers:
    case Nil{}: Document{}
    case Con{E.Layer{panel, trigger, initial, query, layer_occurrence}, rest}: scope_occurrence(panel_scope(panel, initial, trigger, beside), layer_occurrence)

def settings_scope(open: Bool, fallback: Scope) -> Scope:
  match open:
    case True{}: Temporary{"settings", "settings/credential", "settings/open", None{}}
    case False{}: fallback

def preview_scope(preview: Services.Preview, fallback: Scope) -> Scope:
  match preview:
    case Services.NoPreview{}: fallback
    case Services.LoadingPreview{ticket, file, trigger}: Temporary{"attachment-preview", "attachment-preview", trigger, None{}}
    case Services.ReadyPreview{file, resource, image, trigger}: Temporary{"attachment-preview", "attachment-preview", trigger, None{}}
    case Services.FailedPreview{file, reason, trigger}: Temporary{"attachment-preview", "attachment-preview", trigger, None{}}

def directory_scope(picker: Services.DirectoryPicker, fallback: Scope) -> Scope:
  match picker:
    case Services.NoDirectoryPicker{}: fallback
    case Services.ReadyDirectory{ticket, editor, catalog, location, trigger}: Temporary{"directory-picker", "directory-picker/location", trigger, None{}}
    case Services.LoadingDirectory{ticket, editor, path, trigger}: Temporary{"directory-picker", "directory-picker", trigger, None{}}
    case Services.FailedDirectory{ticket, editor, path, reason, trigger}: Temporary{"directory-picker", "directory-picker", trigger, None{}}

def logical_scope(+state: Core.State, capacity: View.Capacity) -> Scope:
  View.Capacity{navigation_beside, details_beside} = capacity
  +observed_application_1 = Core.application(state)
  +observed_session_2 = E.session(observed_application_1)
  +layers = E.layers(observed_session_2)
  +observed_services_3 = Core.services(state)
  +settings = Services.settings_open(observed_services_3)
  +preview = Services.preview(observed_services_3)
  +directory_picker = Services.directory_picker(observed_services_3)
  preview_scope(preview, directory_scope(directory_picker, settings_scope(settings, layer_scope(layers, details_beside))))

def scope_occurrence_of(scope: Scope) -> Maybe<&2, Nat>:
  match scope:
    case Document{}: None{}
    case Temporary{identity, initial, restore, occurrence}: occurrence

def same_occurrence(previous: Maybe<&2, Nat>, current: Maybe<&2, Nat>) -> Bool:
  match previous current:
    case None{} None{}: True{}
    case Some{previous} Some{current}: Nat.is_eq(previous, current)
    case _ _: False{}

def changed(previous: Scope, current: Scope) -> Bool:
  match previous current:
    case Document{} Document{}: False{}
    case Temporary{previous, old_initial, old_restore, old_occurrence} Temporary{current, initial, restore, occurrence}:
      Bool.not(String.eq(previous, current) && same_occurrence(old_occurrence, occurrence))
    case _ _: True{}

def invalid_retained(scope: Scope, eligible: Bool) -> Bool:
  match scope:
    case Document{}: False{}
    case Temporary{identity, initial, restore, occurrence}: Bool.not(eligible)

def transition(previous: Scope, +current: Scope, eligible: Bool) -> Bool:
  changed(previous, current) || invalid_retained(current, eligible)

def scope_restore_target(found: Maybe<&2, String>, initial: String) -> String:
  match found:
    case Some{key}: key
    case None{}: initial

def temporary_scope_target(previous: Scope, initial: String, surface: InterfaceView.Surface) -> String:
  match previous:
    case Document{}: initial
    case Temporary{old_id, old_initial, restore, occurrence}:
      scope_restore_target(InterfaceView.matching_focus(InterfaceView.active_nodes(surface), restore), initial)

def scope_target(previous: Scope, current: Scope, surface: InterfaceView.Surface) -> String:
  match current:
    case Document{}: restore(previous)
    case Temporary{id, initial, trigger, occurrence}: temporary_scope_target(previous, initial, surface)

def permits_composer(scope: Scope) -> Bool:
  match scope:
    case Document{}: True{}
    case _: False{}

def resolved_target(found: Maybe<&2, String>) -> String:
  match found:
    case Some{key}: key
    case None{}: ""

def choose_scope_occurrence(occurrence: Maybe<&2, Nat>, active: Maybe<&2, String>, +surface: InterfaceView.Surface, +scope: Scope) -> Scope:
  match active:
    case None{}: Document{}
    case Some{key}: Temporary{key, resolved_target(InterfaceView.focus_target(surface, initial(scope))), resolved_target(InterfaceView.all_focus_target(surface, restore(scope))), occurrence}

def choose_scope(active: Maybe<&2, String>, surface: InterfaceView.Surface, +scope: Scope) -> Scope:
  choose_scope_occurrence(scope_occurrence_of(scope), active, surface, scope)

def realized_scope(+surface: InterfaceView.Surface, scope: Scope) -> Scope:
  InterfaceView.Surface{content, base, overlays, +active} = surface
  choose_scope(active, surface, scope)

def current(+state: Core.State, +capacity: View.Capacity) -> Scope:
  realized_scope(InterfaceView.observe(capacity, state), logical_scope(state, capacity))

def next_tab(remaining: +List<String>, fallback: Maybe<&2, String>) -> Maybe<&2, String>:
  match remaining:
    case Nil{}: fallback
    case Con{key, rest}: Some{key}

def cycle_pick(reverse: Bool, previous: Maybe<&2, String>, remaining: +List<String>,
  first: Maybe<&2, String>, last: Maybe<&2, String>) -> Maybe<&2, String>:
  match reverse:
    case True{}:
      match previous:
        case None{}: last
        case Some{key}: Some{key}
    case False{}: next_tab(remaining, first)

def cycle_match(hit: Bool, reverse: Bool, previous: Maybe<&2, String>, remaining: +List<String>,
  first: Maybe<&2, String>, last: Maybe<&2, String>, fallback: Maybe<&2, String>) -> Maybe<&2, String>:
  match hit:
    case True{}: cycle_pick(reverse, previous, remaining, first, last)
    case False{}: fallback

def cycle_scan(order: +List<String>, +focused: String, previous: Maybe<&2, String>,
  +first: Maybe<&2, String>, +last: Maybe<&2, String>, +reverse: Bool) -> Maybe<&2, String>:
  match order:
    case Nil{}:
      match reverse:
        case True{}: last
        case False{}: first
    case Con{+key, +rest}:
      cycle_match(String.eq(key, focused), reverse, previous, rest, first, last,
        cycle_scan(rest, focused, Some{key}, first, last, reverse))

def cycle_start(focused: Maybe<&2, String>, order: +List<String>, first: Maybe<&2, String>, last: Maybe<&2, String>, reverse: Bool) -> Maybe<&2, String>:
  match focused:
    case None{}:
      match reverse:
        case True{}: last
        case False{}: first
    case Some{key}: cycle_scan(order, key, None{}, first, last, reverse)

def cycle_focused(focused: Maybe<&2, String>, +order: +List<String>, reverse: Bool) -> Maybe<&2, String>:
  cycle_start(focused, order, List.head(&2, String, order), List.head(&2, String, List.reverse(&2, String, order)), reverse)

def cycle(scope: Scope, order: +List<String>, focused: Maybe<&2, String>, reverse: Bool) -> Maybe<&2, String>:
  match scope:
    case Document{}: None{}
    case Temporary{identity, initial, restore, occurrence}: cycle_focused(focused, order, reverse)
