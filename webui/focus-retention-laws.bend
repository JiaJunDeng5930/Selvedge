import Base
import ../core/interface.bend as UI
import ../core/SYSTEM.bend as Core
import ../core/ui-world.bend as View
import ../core/user-experience.bend as E
import ./focus.bend as Focus
import ./platform.bend as Platform
import ./laws.bend as Existing

def absent_not_accepted() -> {Platform.found_focus(None{}) == False{} : Bool}:
  {==}

def nonfocusable_not_accepted(key: String, semantic: String, label: String, role: UI.Role,
  +meaning: UI.Meaning, children: +List<UI.Node>, unavailable: {UI.focusable(meaning) == False{} : Bool}) ->
  {Platform.found_focus(Some{UI.Node{key, semantic, label, role, meaning, children}}) == False{} : Bool}:
  unavailable

def retained_transition(+previous: Focus.Scope, +identity: String, +initial: String, +restore: String,
  +eligible: Bool, same: {Focus.changed(previous, Focus.Temporary{identity, initial, restore}) == False{} : Bool}) ->
  {Focus.transition(previous, Focus.Temporary{identity, initial, restore}, eligible) == Bool.not(eligible) : Bool}:
  Equal.cong(Bool, Bool, (changed => changed || Bool.not(eligible)),
    Focus.changed(previous, Focus.Temporary{identity, initial, restore}), False{}, same)

def invalid_focus_requests_initial(+previous: Focus.Scope, +identity: String, +initial: String,
  +restore: String, +ticket: Nat,
  same: {Focus.changed(previous, Focus.Temporary{identity, initial, restore}) == False{} : Bool}) ->
  {Platform.scope_effects(Focus.transition(previous, Focus.Temporary{identity, initial, restore}, False{}), previous,
    Focus.Temporary{identity, initial, restore}, Nil{}, Platform.focus_revision(Focus.transition(previous,
      Focus.Temporary{identity, initial, restore}, False{}), Nil{}, ticket)) ==
    [Platform.Focus{(ticket + 1n : Nat), initial}] : +List<Platform.Effect>}:
  Equal.cong(Bool, +List<Platform.Effect>,
    (trigger => Platform.scope_effects(trigger, previous, Focus.Temporary{identity, initial, restore}, Nil{},
      Platform.focus_revision(trigger, Nil{}, ticket))),
    Focus.transition(previous, Focus.Temporary{identity, initial, restore}, False{}), True{},
    retained_transition(previous, identity, initial, restore, False{}, same))

def valid_focus_no_request(+previous: Focus.Scope, +identity: String, +initial: String,
  +restore: String, +ticket: Nat,
  same: {Focus.changed(previous, Focus.Temporary{identity, initial, restore}) == False{} : Bool}) ->
  {Platform.scope_effects(Focus.transition(previous, Focus.Temporary{identity, initial, restore}, True{}), previous,
    Focus.Temporary{identity, initial, restore}, Nil{}, Platform.focus_revision(Focus.transition(previous,
      Focus.Temporary{identity, initial, restore}, True{}), Nil{}, ticket)) == Nil{} : +List<Platform.Effect>}:
  Equal.cong(Bool, +List<Platform.Effect>,
    (trigger => Platform.scope_effects(trigger, previous, Focus.Temporary{identity, initial, restore}, Nil{},
      Platform.focus_revision(trigger, Nil{}, ticket))),
    Focus.transition(previous, Focus.Temporary{identity, initial, restore}, True{}), False{},
    retained_transition(previous, identity, initial, restore, True{}, same))

def document_transition(+previous: Focus.Scope, eligible: Bool,
  same: {Focus.changed(previous, Focus.Document{}) == False{} : Bool}) ->
  {Focus.transition(previous, Focus.Document{}, eligible) == False{} : Bool}:
  Equal.cong(Bool, Bool, (changed => changed || False{}), Focus.changed(previous, Focus.Document{}), False{}, same)

def document_no_request(+previous: Focus.Scope, +eligible: Bool, +ticket: Nat,
  same: {Focus.changed(previous, Focus.Document{}) == False{} : Bool}) ->
  {Platform.scope_effects(Focus.transition(previous, Focus.Document{}, eligible), previous, Focus.Document{}, Nil{},
    Platform.focus_revision(Focus.transition(previous, Focus.Document{}, eligible), Nil{}, ticket)) == Nil{} : +List<Platform.Effect>}:
  Equal.cong(Bool, +List<Platform.Effect>,
    (trigger => Platform.scope_effects(trigger, previous, Focus.Document{}, Nil{}, Platform.focus_revision(trigger, Nil{}, ticket))),
    Focus.transition(previous, Focus.Document{}, eligible), False{}, document_transition(previous, eligible, same))

def explicit_attention_precedes(+trigger: Bool, previous: Focus.Scope, current: Focus.Scope,
  +target: String, +ticket: Nat) ->
  {Platform.scope_effects(trigger, previous, current, [E.Attend{target}],
    Platform.focus_revision(trigger, [E.Attend{target}], ticket)) == [Platform.Focus{(ticket + 1n : Nat), target}] : +List<Platform.Effect>}:
  match trigger:
    case True{}: {==}
    case False{}: {==}

def effects(value: Platform.Decision) -> +List<Platform.Effect>:
  Platform.Decision{product, platform, effects} = value
  effects

def expected_effects(decision: Core.Decision, platform: Platform.Platform, +current: Focus.Scope) -> +List<Platform.Effect>:
  Core.Decision{Core.State{+application, services}, reply, runtime, +interaction, service, durable} = decision
  Platform.Platform{+readers, editors, focused, +ticket, reduced, capacity, +scope} = platform
  +trigger = Focus.transition(scope, current, Platform.active_focus(Core.State{application, services}, capacity, focused))
  List.append(&2, Platform.Effect, Platform.scope_effects(trigger, scope, current, interaction,
    Platform.focus_revision(trigger, interaction, ticket)), Platform.layout_for(application, readers))

def after_core_effects(+decision: Core.Decision, platform: Platform.Platform, +current: Focus.Scope) ->
  {effects(Platform.after_core_scoped(decision, platform, current)) ==
    expected_effects(decision, platform, current) : +List<Platform.Effect>}:
  match decision platform:
    case Core.Decision{Core.State{application, services}, reply, runtime, interaction, service, durable}
      Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope}: {==}

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
    preservation: Existing.Requirements}

def evidence() -> Requirements:
  Requirements{absent_not_accepted, nonfocusable_not_accepted, invalid_focus_requests_initial, valid_focus_no_request, document_no_request, explicit_attention_precedes, after_core_effects, Existing.evidence()}
