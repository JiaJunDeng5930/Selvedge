import Base
import ../core/ui-identity.bend as UIIdentity
import ../core/interface.bend as InterfaceView
import ../core/SYSTEM.bend as Core
import ../core/user-experience.bend as E
import ../core/ui-world.bend as View
import ./focus.bend as Focus
import ./platform.bend as Platform

def effects(value: Platform.Decision) -> +List<Platform.Effect>:
  Platform.Decision{product, platform, effects} = value
  effects

def expected_effects(decision: Core.Decision, platform: Platform.Platform, +current: Focus.Scope) -> +List<Platform.Effect>:
  Core.Decision{Core.State{+application, services}, reply, runtime, +interaction, service, durable} = decision
  Platform.Platform{+readers, editors, +focused, +ticket, reduced, capacity, +scope} = platform
  +trigger = Platform.focus_transition(scope, current, focused, Platform.active_target(Core.State{application, services}, capacity, focused))
  List.append(&2, Platform.Effect, Platform.scope_effects(trigger, scope, current, interaction,
    Platform.focus_revision(trigger, interaction, ticket)), Platform.layout_for(application, readers))

type Requirements is Type:
  Requirements{
    absent_not_accepted: {Platform.found_focus(None{}) == False{} : Bool},
    nonfocusable_not_accepted: @key: UIIdentity.Key -> @semantic: String -> @label: String -> @role: InterfaceView.Role -> @+meaning: InterfaceView.Meaning -> @children: +List<InterfaceView.Node> -> @unavailable: {InterfaceView.focusable(meaning) == False{} : Bool} -> {Platform.found_focus(Some{InterfaceView.Node{key, semantic, label, role, meaning, children}}) == False{} : Bool},
    invalid_focus_requests_initial: @+previous: Focus.Scope -> @+identity: String -> @+initial: String -> @+restore: String -> @+occurrence:Maybe<&2, Nat> -> @+ticket: Nat -> @same: {Focus.changed(previous, Focus.Temporary{identity, initial, restore, occurrence}) == False{} : Bool} -> {Platform.scope_effects(Focus.transition(previous, Focus.Temporary{identity, initial, restore, occurrence}, False{}), previous,
          Focus.Temporary{identity, initial, restore, occurrence}, Nil{}, Platform.focus_revision(Focus.transition(previous,
            Focus.Temporary{identity, initial, restore, occurrence}, False{}), Nil{}, ticket)) ==
          [Platform.ScopeFocus{(ticket + 1n : Nat), previous, Focus.Temporary{identity, initial, restore, occurrence}}] : +List<Platform.Effect>},
    valid_focus_no_request: @+previous: Focus.Scope -> @+identity: String -> @+initial: String -> @+restore: String -> @+occurrence:Maybe<&2, Nat> -> @+ticket: Nat -> @same: {Focus.changed(previous, Focus.Temporary{identity, initial, restore, occurrence}) == False{} : Bool} -> {Platform.scope_effects(Focus.transition(previous, Focus.Temporary{identity, initial, restore, occurrence}, True{}), previous,
          Focus.Temporary{identity, initial, restore, occurrence}, Nil{}, Platform.focus_revision(Focus.transition(previous,
            Focus.Temporary{identity, initial, restore, occurrence}, True{}), Nil{}, ticket)) == Nil{} : +List<Platform.Effect>},
    document_no_request: @+previous: Focus.Scope -> @+eligible: Bool -> @+ticket: Nat -> @same: {Focus.changed(previous, Focus.Document{}) == False{} : Bool} -> {Platform.scope_effects(Focus.transition(previous, Focus.Document{}, eligible), previous, Focus.Document{}, Nil{},
    Platform.focus_revision(Focus.transition(previous, Focus.Document{}, eligible), Nil{}, ticket)) == Nil{} : +List<Platform.Effect>},
    explicit_attention_precedes: @+trigger: Bool -> @previous: Focus.Scope -> @current: Focus.Scope -> @+target: String -> @+ticket: Nat -> {Platform.scope_effects(trigger, previous, current, [E.Attend{target}],
    Platform.focus_revision(trigger, [E.Attend{target}], ticket)) == [Platform.Focus{(ticket + 1n : Nat), Focus.Product{target}}] : +List<Platform.Effect>},
    after_core_effects: @+decision: Core.Decision -> @platform: Platform.Platform -> @+current: Focus.Scope -> {effects(Platform.after_core_scoped(decision, platform, current)) ==
    expected_effects(decision, platform, current) : +List<Platform.Effect>},
    root_handoff_requests_initial: @+identity: String -> @+old_initial: String -> @+initial: String -> @+restore: String -> @+old_occurrence:Maybe<&2, Nat> -> @+occurrence:Maybe<&2, Nat> -> @+focused: String -> @+ticket: Nat -> @same: {Focus.changed(Focus.Temporary{identity, old_initial, restore, old_occurrence}, Focus.Temporary{identity, initial, restore, occurrence}) == False{} : Bool} -> @retained: {String.eq(focused, old_initial) == True{} : Bool} -> @root: {String.eq(identity, identity) && String.eq(old_initial, identity) == True{} : Bool} -> @changed: {Bool.not(String.eq(old_initial, initial)) == True{} : Bool} ->   {Platform.scope_effects(Platform.focus_transition(Focus.Temporary{identity, old_initial, restore, old_occurrence}, Focus.Temporary{identity, initial, restore, occurrence}, Focus.Product{focused}, True{}),
          Focus.Temporary{identity, old_initial, restore, old_occurrence}, Focus.Temporary{identity, initial, restore, occurrence}, Nil{},
          Platform.focus_revision(Platform.focus_transition(Focus.Temporary{identity, old_initial, restore, old_occurrence}, Focus.Temporary{identity, initial, restore, occurrence}, Focus.Product{focused}, True{}), Nil{}, ticket)) ==
          [Platform.ScopeFocus{(ticket + 1n : Nat), Focus.Temporary{identity, old_initial, restore, old_occurrence}, Focus.Temporary{identity, initial, restore, occurrence}}] : +List<Platform.Effect>},
    moved_focus_no_handoff: @+identity: String -> @+old_initial: String -> @+initial: String -> @+restore: String -> @+old_occurrence:Maybe<&2, Nat> -> @+occurrence:Maybe<&2, Nat> -> @+focused: String -> @+ticket: Nat -> @same: {Focus.changed(Focus.Temporary{identity, old_initial, restore, old_occurrence}, Focus.Temporary{identity, initial, restore, occurrence}) == False{} : Bool} -> @moved: {String.eq(focused, old_initial) == False{} : Bool} ->   {Platform.scope_effects(Platform.focus_transition(Focus.Temporary{identity, old_initial, restore, old_occurrence}, Focus.Temporary{identity, initial, restore, occurrence}, Focus.Product{focused}, True{}),
          Focus.Temporary{identity, old_initial, restore, old_occurrence}, Focus.Temporary{identity, initial, restore, occurrence}, Nil{},
          Platform.focus_revision(Platform.focus_transition(Focus.Temporary{identity, old_initial, restore, old_occurrence}, Focus.Temporary{identity, initial, restore, occurrence}, Focus.Product{focused}, True{}), Nil{}, ticket)) == Nil{} : +List<Platform.Effect>}}

law evidence:
  Requirements


law content_focus_has_no_root_handoff:
  for previous: Focus.Scope
  for current: Focus.Scope
  for owner: String
  for identity: String
  {Platform.scope_handoff(previous, current, Focus.Content{owner, identity}) == False{} : Bool}

law active_content_uses_owner:
  for core: Core.State
  for capacity: View.Capacity
  for owner: String
  for identity: String
  {Platform.active_target(core, capacity, Focus.Content{owner, identity}) == Platform.active_content_owner(core, capacity, owner) : Bool}

law retained_content_no_focus_transition:
  for +previous: Focus.Scope
  for +current: Focus.Scope
  for owner: String
  for identity: String
  for same: {Focus.changed(previous, current) == False{} : Bool}
  {Platform.focus_transition(previous, current, Focus.Content{owner, identity}, True{}) == False{} : Bool}


law content_observation_preserves_core:
  for +platform: Platform.Platform
  for owner: String
  for identity: String
  for +core: Core.State
  {Platform.decision_product(Platform.observed_focus(platform, True{}, Focus.Content{owner, identity}, core)) == Platform.unchanged(core) : Core.Decision}
