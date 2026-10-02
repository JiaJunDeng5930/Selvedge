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
    case Services.LoadingPreview{ticket, file, trigger}: Temporary{"attachment-preview", "attachment-preview", trigger}
    case Services.ReadyPreview{file, resource, image, trigger}: Temporary{"attachment-preview", "attachment-preview", trigger}
    case Services.FailedPreview{file, reason, trigger}: Temporary{"attachment-preview", "attachment-preview", trigger}

def directory_scope(picker: Services.DirectoryPicker, fallback: Scope) -> Scope:
  match picker:
    case Services.NoDirectoryPicker{}: fallback
    case Services.ReadyDirectory{ticket, editor, catalog, location, trigger}: Temporary{"directory-picker", "directory-picker/location", trigger}
    case Services.LoadingDirectory{ticket, editor, path, trigger}: Temporary{"directory-picker", "directory-picker", trigger}
    case Services.FailedDirectory{ticket, editor, path, reason, trigger}: Temporary{"directory-picker", "directory-picker", trigger}

def logical_scope(state: Core.State, capacity: View.Capacity) -> Scope:
  Core.State{E.Application{program, E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks}},
    Services.State{access, credential, settings, appearance, next_service, transfers, preview, directory_picker}} = state
  View.Capacity{navigation_beside, details_beside} = capacity
  preview_scope(preview, directory_scope(directory_picker, settings_scope(settings, layer_scope(layers, details_beside))))

def changed(previous: Scope, current: Scope) -> Bool:
  Bool.not(String.eq(identity(previous), identity(current)))

def invalid_retained(scope: Scope, eligible: Bool) -> Bool:
  match scope:
    case Document{}: False{}
    case Temporary{identity, initial, restore}: Bool.not(eligible)

def transition(previous: Scope, +current: Scope, eligible: Bool) -> Bool:
  changed(previous, current) || invalid_retained(current, eligible)

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
    case Temporary{identity, initial, restore}: cycle_focused(focused, order, reverse)

def document_cycle(order: +List<String>, focused: Maybe<&2, String>, reverse: Bool) ->
  {cycle(Document{}, order, focused, reverse) == None{} : Maybe<&2, String>}:
  {==}

def forward_wrap(+key: String, +focused: String, previous: Maybe<&2, String>, +first: Maybe<&2, String>, +last: Maybe<&2, String>,
  matching: {String.eq(key, focused) == True{} : Bool}) ->
  {cycle_scan([key], focused, previous, first, last, False{}) == first : Maybe<&2, String>}:
  Equal.cong(Bool, Maybe<&2, String>,
    (hit => cycle_match(hit, False{}, previous, Nil{}, first, last, first)),
    String.eq(key, focused), True{}, matching)

def backward_wrap(+key: String, +rest: +List<String>, +focused: String,
  matching: {String.eq(key, focused) == True{} : Bool}) ->
  {cycle_focused(Some{focused}, key <> rest, True{}) ==
    List.head(&2, String, List.reverse(&2, String, key <> rest)) : Maybe<&2, String>}:
  Equal.cong(Bool, Maybe<&2, String>,
    (hit => cycle_match(hit, True{}, None{}, rest, Some{key},
      List.head(&2, String, List.reverse(&2, String, key <> rest)),
      cycle_scan(rest, focused, Some{key}, Some{key}, List.head(&2, String, List.reverse(&2, String, key <> rest)), True{}))),
    String.eq(key, focused), True{}, matching)

type CycleRequirements is Type:
  CycleRequirements{
    document: @order:+List<String> -> @focused:Maybe<&2,String> -> @reverse:Bool ->
      {cycle(Document{}, order, focused, reverse) == None{} : Maybe<&2,String>},
    forward_wrap: @+key:String -> @+focused:String -> @previous:Maybe<&2,String> -> @+first:Maybe<&2,String> -> @+last:Maybe<&2,String> ->
      @matching:{String.eq(key, focused) == True{} : Bool} ->
      {cycle_scan([key], focused, previous, first, last, False{}) == first : Maybe<&2,String>},
    backward_wrap: @+key:String -> @+rest:+List<String> -> @+focused:String ->
      @matching:{String.eq(key, focused) == True{} : Bool} ->
      {cycle_focused(Some{focused}, key <> rest, True{}) == List.head(&2, String, List.reverse(&2, String, key <> rest)) : Maybe<&2,String>}
  }

def cycle_evidence() -> CycleRequirements:
  CycleRequirements{document_cycle, forward_wrap, backward_wrap}
