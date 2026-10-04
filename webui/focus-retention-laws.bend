import Base
import ../core/interface.bend as UI
import ../core/SYSTEM.bend as Core
import ../core/user-experience.bend as E
import ./focus.bend as Focus
import ./platform.bend as Platform

def effects(value: Platform.Decision) -> +List<Platform.Effect>:
  Platform.Decision{product, platform, effects} = value
  effects

def expected_effects(decision: Core.Decision, platform: Platform.Platform, +current: Focus.Scope) -> +List<Platform.Effect>:
  Core.Decision{Core.State{+application, services}, reply, runtime, +interaction, service, durable} = decision
  Platform.Platform{+readers, editors, +focused, +ticket, reduced, capacity, +scope} = platform
  +trigger = Platform.focus_transition(scope, current, focused, Platform.active_focus(Core.State{application, services}, capacity, focused))
  List.append(&2, Platform.Effect, Platform.scope_effects(trigger, scope, current, interaction,
    Platform.focus_revision(trigger, interaction, ticket)), Platform.layout_for(application, readers))

type Requirements is Type:
  Requirements{
    absent_not_accepted: {Platform.found_focus(None{}) == False{} : Bool},
    nonfocusable_not_accepted: @key: String -> @semantic: String -> @label: String -> @role: UI.Role -> @+meaning: UI.Meaning -> @children: +List<UI.Node> -> @unavailable: {UI.focusable(meaning) == False{} : Bool} -> {Platform.found_focus(Some{UI.Node{key, semantic, label, role, meaning, children}}) == False{} : Bool},
    invalid_focus_requests_initial: @+previous: Focus.Scope -> @+identity: String -> @+initial: String -> @+restore: String -> @+ticket: Nat -> @same: {Focus.changed(previous, Focus.Temporary{identity, initial, restore}) == False{} : Bool} -> {Platform.scope_effects(Focus.transition(previous, Focus.Temporary{identity, initial, restore}, False{}), previous,
          Focus.Temporary{identity, initial, restore}, Nil{}, Platform.focus_revision(Focus.transition(previous,
            Focus.Temporary{identity, initial, restore}, False{}), Nil{}, ticket)) ==
          [Platform.Focus{(ticket + 1n : Nat), initial}] : +List<Platform.Effect>},
    valid_focus_no_request: @+previous: Focus.Scope -> @+identity: String -> @+initial: String -> @+restore: String -> @+ticket: Nat -> @same: {Focus.changed(previous, Focus.Temporary{identity, initial, restore}) == False{} : Bool} -> {Platform.scope_effects(Focus.transition(previous, Focus.Temporary{identity, initial, restore}, True{}), previous,
          Focus.Temporary{identity, initial, restore}, Nil{}, Platform.focus_revision(Focus.transition(previous,
            Focus.Temporary{identity, initial, restore}, True{}), Nil{}, ticket)) == Nil{} : +List<Platform.Effect>},
    document_no_request: @+previous: Focus.Scope -> @+eligible: Bool -> @+ticket: Nat -> @same: {Focus.changed(previous, Focus.Document{}) == False{} : Bool} -> {Platform.scope_effects(Focus.transition(previous, Focus.Document{}, eligible), previous, Focus.Document{}, Nil{},
    Platform.focus_revision(Focus.transition(previous, Focus.Document{}, eligible), Nil{}, ticket)) == Nil{} : +List<Platform.Effect>},
    explicit_attention_precedes: @+trigger: Bool -> @previous: Focus.Scope -> @current: Focus.Scope -> @+target: String -> @+ticket: Nat -> {Platform.scope_effects(trigger, previous, current, [E.Attend{target}],
    Platform.focus_revision(trigger, [E.Attend{target}], ticket)) == [Platform.Focus{(ticket + 1n : Nat), target}] : +List<Platform.Effect>},
    after_core_effects: @+decision: Core.Decision -> @platform: Platform.Platform -> @+current: Focus.Scope -> {effects(Platform.after_core_scoped(decision, platform, current)) ==
    expected_effects(decision, platform, current) : +List<Platform.Effect>},
    root_handoff_requests_initial: @+identity: String -> @+old_initial: String -> @+initial: String -> @+restore: String -> @+focused: String -> @+ticket: Nat -> @same: {Focus.changed(Focus.Temporary{identity, old_initial, restore}, Focus.Temporary{identity, initial, restore}) == False{} : Bool} -> @retained: {String.eq(focused, old_initial) == True{} : Bool} -> @root: {String.eq(identity, identity) && String.eq(old_initial, identity) == True{} : Bool} -> @changed: {Bool.not(String.eq(old_initial, initial)) == True{} : Bool} ->   {Platform.scope_effects(Platform.focus_transition(Focus.Temporary{identity, old_initial, restore}, Focus.Temporary{identity, initial, restore}, focused, True{}),
          Focus.Temporary{identity, old_initial, restore}, Focus.Temporary{identity, initial, restore}, Nil{},
          Platform.focus_revision(Platform.focus_transition(Focus.Temporary{identity, old_initial, restore}, Focus.Temporary{identity, initial, restore}, focused, True{}), Nil{}, ticket)) ==
          [Platform.Focus{(ticket + 1n : Nat), initial}] : +List<Platform.Effect>},
    moved_focus_no_handoff: @+identity: String -> @+old_initial: String -> @+initial: String -> @+restore: String -> @+focused: String -> @+ticket: Nat -> @same: {Focus.changed(Focus.Temporary{identity, old_initial, restore}, Focus.Temporary{identity, initial, restore}) == False{} : Bool} -> @moved: {String.eq(focused, old_initial) == False{} : Bool} ->   {Platform.scope_effects(Platform.focus_transition(Focus.Temporary{identity, old_initial, restore}, Focus.Temporary{identity, initial, restore}, focused, True{}),
          Focus.Temporary{identity, old_initial, restore}, Focus.Temporary{identity, initial, restore}, Nil{},
          Platform.focus_revision(Platform.focus_transition(Focus.Temporary{identity, old_initial, restore}, Focus.Temporary{identity, initial, restore}, focused, True{}), Nil{}, ticket)) == Nil{} : +List<Platform.Effect>}}

law evidence:
  Requirements
