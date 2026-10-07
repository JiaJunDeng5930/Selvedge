import Base
import ../../interaction/STATE.bend as Core
import ./MODEL.bend as Model
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ../../interaction/IDENTITY.bend as Identity
import ../../interaction/INPUT.bend as U
import ../../interaction/session/MODEL.bend as E
import ../../interaction/presentation/MODEL.bend as View
import ../../interaction/services/MODEL.bend as Services
type CycleRequirements is Type:
  CycleRequirements{
    document: @order:+List<String> -> @focused:Maybe<&2,String> -> @reverse:Bool ->
      {Model.cycle(Model.Document{}, order, focused, reverse) == None{} : Maybe<&2,String>},
    forward_wrap: @+key:String -> @+focused:String -> @previous:Maybe<&2,String> -> @+first:Maybe<&2,String> -> @+last:Maybe<&2,String> ->
      @matching:{String.eq(key, focused) == True{} : Bool} ->
      {Model.cycle_scan([key], focused, previous, first, last, False{}) == first : Maybe<&2,String>},
    backward_wrap: @+key:String -> @+rest:+List<String> -> @+focused:String ->
      @matching:{String.eq(key, focused) == True{} : Bool} ->
      {Model.cycle_focused(Some{focused}, key <> rest, True{}) == List.head(&2, String, List.reverse(&2, String, key <> rest)) : Maybe<&2,String>}
  }
law cycle_evidence:
  CycleRequirements
law realized_restore:
  for +content: Core.Scene
  for +base: +List<InterfaceView.Node>
  for +overlays: +List<InterfaceView.Node>
  for +active: String
  for +scope: Model.Scope
  for +key: Identity.Key
  for found: {InterfaceView.all_focus_target(InterfaceView.Surface{content, base, overlays, Some{active}}, Model.restore(scope)) == Some{Identity.encode(key)} : Maybe<&2, String>}
  {Model.restore(Model.realized_scope(InterfaceView.Surface{content, base, overlays, Some{active}}, scope)) == Identity.encode(key) : String}
law settings_restore:
  for +content: Core.Scene
  for +base: +List<InterfaceView.Node>
  for +overlays: +List<InterfaceView.Node>
  for +active: String
  for fallback: Model.Scope
  {Model.restore(Model.realized_scope(InterfaceView.Surface{content, base, overlays, Some{active}}, Model.settings_scope(True{}, fallback))) == Model.resolved_target(InterfaceView.all_focus_target(InterfaceView.Surface{content, base, overlays, Some{active}}, "settings/open")) : String}
law settings_resolved_restore:
  for +content: Core.Scene
  for +base: +List<InterfaceView.Node>
  for +overlays: +List<InterfaceView.Node>
  for +active: String
  for fallback: Model.Scope
  for +key: Identity.Key
  for found: {InterfaceView.all_focus_target(InterfaceView.Surface{content, base, overlays, Some{active}}, "settings/open") == Some{Identity.encode(key)} : Maybe<&2, String>}
  {Model.restore(Model.realized_scope(InterfaceView.Surface{content, base, overlays, Some{active}}, Model.settings_scope(True{}, fallback))) == Identity.encode(key) : String}
law document_restores_previous:
  for +previous: Model.Scope
  for surface: InterfaceView.Surface
  {Model.scope_target(previous, Model.Document{}, surface) == Model.restore(previous) : String}
law document_opens_temporary:
  for identity: String
  for +initial: String
  for restore: String
  for occurrence: Maybe<&2, Nat>
  for surface: InterfaceView.Surface
  {Model.scope_target(Model.Document{}, Model.Temporary{identity, initial, restore, occurrence}, surface) == initial : String}
law nested_scope_restores_active_trigger:
  for old_identity: String
  for old_initial: String
  for old_occurrence: Maybe<&2, Nat>
  for +trigger: String
  for identity: String
  for +initial: String
  for restore: String
  for occurrence: Maybe<&2, Nat>
  for +surface: InterfaceView.Surface
  for +key: String
  for found: {InterfaceView.matching_focus(InterfaceView.active_nodes(surface), trigger) == Some{key} : Maybe<&2, String>}
  {Model.scope_target(Model.Temporary{old_identity, old_initial, trigger, old_occurrence}, Model.Temporary{identity, initial, restore, occurrence}, surface) == key : String}
law nested_scope_without_active_trigger_uses_initial:
  for old_identity: String
  for old_initial: String
  for old_occurrence: Maybe<&2, Nat>
  for +trigger: String
  for identity: String
  for +initial: String
  for restore: String
  for occurrence: Maybe<&2, Nat>
  for +surface: InterfaceView.Surface
  for absent: {InterfaceView.matching_focus(InterfaceView.active_nodes(surface), trigger) == None{} : Maybe<&2, String>}
  {Model.scope_target(Model.Temporary{old_identity, old_initial, trigger, old_occurrence}, Model.Temporary{identity, initial, restore, occurrence}, surface) == initial : String}
law panel_policy:
  for +panel: U.Panel
  for initial: String
  for +trigger: String
  for beside: Bool
  {Model.panel_scope(panel, initial, trigger, beside) == Model.dismissal_scope(View.layer_dismissal(panel, trigger), E.panel_target(panel), initial, trigger, beside) : Model.Scope}
def persistent_classification(beside: Bool, identity: String, initial: String, trigger: String, actual: Model.Scope) -> Type:
  match beside:
    case True{}: {actual == Model.Document{} : Model.Scope}
    case False{}: {actual == Model.Temporary{identity, initial, trigger, None{}} : Model.Scope}

law persistent_scope:
  for +action: U.Action
  for +identity: String
  for +initial: String
  for +trigger: String
  for +beside: Bool
  persistent_classification(beside, identity, initial, trigger, Model.dismissal_scope(View.ByTrigger{action}, identity, initial, trigger, beside))
law temporary_scope:
  for action: U.Action
  for +identity: String
  for initial: String
  for trigger: String
  for beside: Bool
  {Model.dismissal_scope(View.OutsideOrEscape{action}, identity, initial, trigger, beside) == Model.Temporary{identity, initial, trigger, None{}} : Model.Scope}
def settings_classification(open: Bool, fallback: Model.Scope, actual: Model.Scope) -> Type:
  match open:
    case False{}: {actual == fallback : Model.Scope}
    case True{}: {actual == Model.Temporary{"settings", "settings/credential", "settings/open", None{}} : Model.Scope}

def preview_classification(preview: Services.Preview, fallback: Model.Scope, actual: Model.Scope) -> Type:
  match preview:
    case Services.NoPreview{}: {actual == fallback : Model.Scope}
    case Services.LoadingPreview{ticket, file, trigger}: {actual == Model.Temporary{"attachment-preview", "attachment-preview", trigger, None{}} : Model.Scope}
    case Services.ReadyPreview{file, resource, image, trigger}: {actual == Model.Temporary{"attachment-preview", "attachment-preview", trigger, None{}} : Model.Scope}
    case Services.FailedPreview{file, reason, trigger}: {actual == Model.Temporary{"attachment-preview", "attachment-preview", trigger, None{}} : Model.Scope}

def directory_classification(picker: Services.DirectoryPicker, fallback: Model.Scope, actual: Model.Scope) -> Type:
  match picker:
    case Services.NoDirectoryPicker{}: {actual == fallback : Model.Scope}
    case Services.ReadyDirectory{ticket, editor, catalog, location, trigger}: {actual == Model.Temporary{"directory-picker", "directory-picker/location", trigger, None{}} : Model.Scope}
    case Services.LoadingDirectory{ticket, editor, path, trigger}: {actual == Model.Temporary{"directory-picker", "directory-picker", trigger, None{}} : Model.Scope}
    case Services.FailedDirectory{ticket, editor, path, reason, trigger}: {actual == Model.Temporary{"directory-picker", "directory-picker", trigger, None{}} : Model.Scope}

law settings_policy:
  for +open: Bool
  for +fallback: Model.Scope
  settings_classification(open, fallback, Model.settings_scope(open, fallback))
law preview_policy:
  for +preview: Services.Preview
  for +fallback: Model.Scope
  preview_classification(preview, fallback, Model.preview_scope(preview, fallback))
law directory_policy:
  for +picker: Services.DirectoryPicker
  for +fallback: Model.Scope
  directory_classification(picker, fallback, Model.directory_scope(picker, fallback))
law realized_document:
  for content: Core.Scene
  for base: +List<InterfaceView.Node>
  for overlays: +List<InterfaceView.Node>
  for scope: Model.Scope
  {Model.realized_scope(InterfaceView.Surface{content, base, overlays, None{}}, scope) == Model.Document{} : Model.Scope}
law realized_active:
  for +content: Core.Scene
  for +base: +List<InterfaceView.Node>
  for +overlays: +List<InterfaceView.Node>
  for +active: String
  for +scope: Model.Scope
  {Model.realized_scope(InterfaceView.Surface{content, base, overlays, Some{active}}, scope) ==
    Model.Temporary{active, Model.resolved_target(InterfaceView.focus_target(InterfaceView.Surface{content, base, overlays, Some{active}}, Model.initial(scope))),
      Model.resolved_target(InterfaceView.all_focus_target(InterfaceView.Surface{content, base, overlays, Some{active}}, Model.restore(scope))), Model.scope_occurrence_of(scope)} : Model.Scope}
law current_scope:
  for +state: Core.State
  for +capacity: View.Capacity
  {Model.current(state, capacity) == Model.realized_scope(InterfaceView.observe(capacity, state), Model.logical_scope(state, capacity)) : Model.Scope}
def logical_classification(+state: Core.State, capacity: View.Capacity, actual: Model.Scope) -> Type:
  View.Capacity{navigation_beside, details_beside} = capacity
  +observed_application_1 = Core.application(state)
  +observed_session_2 = E.session(observed_application_1)
  +layers = E.layers(observed_session_2)
  +observed_services_3 = Core.services(state)
  +settings = Services.settings_open(observed_services_3)
  +preview = Services.preview(observed_services_3)
  +directory_picker = Services.directory_picker(observed_services_3)
  {actual == Model.preview_scope(preview, Model.directory_scope(directory_picker, Model.settings_scope(settings, Model.layer_scope(layers, details_beside)))) : Model.Scope}

law logical_priority:
  for +state: Core.State
  for +capacity: View.Capacity
  logical_classification(state, capacity, Model.logical_scope(state, capacity))
law current_surface:
  for +state: Core.State
  for +capacity: View.Capacity
  for +surface: InterfaceView.Surface
  for observed: {InterfaceView.observe(capacity, state) == surface : InterfaceView.Surface}
  {Model.current(state, capacity) == Model.realized_scope(surface, Model.logical_scope(state, capacity)) : Model.Scope}
