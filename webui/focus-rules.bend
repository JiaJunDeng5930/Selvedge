import Base
import ../core/SYSTEM.bend as Core
import ./focus.bend as Model
import ../core/interface.bend as UI
import ../core/ui-identity.bend as Identity

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
  for +base: +List<UI.Node>
  for +overlays: +List<UI.Node>
  for +active: String
  for +scope: Model.Scope
  for +key: Identity.Key
  for found: {UI.all_focus_target(UI.Surface{content, base, overlays, Some{active}}, Model.restore(scope)) == Some{Identity.encode(key)} : Maybe<&2, String>}
  {Model.restore(Model.realized_scope(UI.Surface{content, base, overlays, Some{active}}, scope)) == Identity.encode(key) : String}

law settings_restore:
  for +content: Core.Scene
  for +base: +List<UI.Node>
  for +overlays: +List<UI.Node>
  for +active: String
  for fallback: Model.Scope
  {Model.restore(Model.realized_scope(UI.Surface{content, base, overlays, Some{active}}, Model.settings_scope(True{}, fallback))) == Model.resolved_target(UI.all_focus_target(UI.Surface{content, base, overlays, Some{active}}, "settings/open")) : String}

law settings_resolved_restore:
  for +content: Core.Scene
  for +base: +List<UI.Node>
  for +overlays: +List<UI.Node>
  for +active: String
  for fallback: Model.Scope
  for +key: Identity.Key
  for found: {UI.all_focus_target(UI.Surface{content, base, overlays, Some{active}}, "settings/open") == Some{Identity.encode(key)} : Maybe<&2, String>}
  {Model.restore(Model.realized_scope(UI.Surface{content, base, overlays, Some{active}}, Model.settings_scope(True{}, fallback))) == Identity.encode(key) : String}


law document_restores_previous:
  for +previous: Model.Scope
  for surface: UI.Surface
  {Model.scope_target(previous, Model.Document{}, surface) == Model.restore(previous) : String}

law document_opens_temporary:
  for identity: String
  for +initial: String
  for restore: String
  for occurrence: Maybe<&2, Nat>
  for surface: UI.Surface
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
  for +surface: UI.Surface
  for +key: String
  for found: {UI.matching_focus(UI.active_nodes(surface), trigger) == Some{key} : Maybe<&2, String>}
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
  for +surface: UI.Surface
  for absent: {UI.matching_focus(UI.active_nodes(surface), trigger) == None{} : Maybe<&2, String>}
  {Model.scope_target(Model.Temporary{old_identity, old_initial, trigger, old_occurrence}, Model.Temporary{identity, initial, restore, occurrence}, surface) == initial : String}
