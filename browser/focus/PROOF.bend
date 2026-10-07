import Base
import ./CONTRACT.bend as Rule
import ./MODEL.bend as Model
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ../../interaction/IDENTITY.bend as Identity
import ../../interaction/services/MODEL.bend as Services
import ../../interaction/STATE.bend as Core
import ../../interaction/session/MODEL.bend as E
import ../../interaction/presentation/MODEL.bend as View
import ../../interaction/INPUT.bend as U
import ../runtime/SEMANTICS.bend as Browser
import ./dismissal-laws.bend as RuleDismissalLaws
import ../runtime/PLATFORM.bend as Platform
import ./focus-retention-laws.bend as RuleFocusRetentionLaws

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

def toggle_absent(+application: E.Application, +panel: U.Panel, +trigger: String,
  absent: {E.panel_present(RuleDismissalLaws.application_layers(application), E.panel_target(panel)) == False{} : Bool}) ->
  {E.toggle_panel(panel, trigger, application) == E.open_panel(panel, trigger, application) : E.Decision}:
  E.Application{program, E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}} = application
  +current: E.Application = E.Application{program, E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}}
  Equal.cong(Bool, E.Decision, (present => E.toggle_panel_selected(present, panel, trigger, current)),
    E.panel_present(layers, E.panel_target(panel)), False{}, absent)

def toggle_present(+application: E.Application, +panel: U.Panel, +trigger: String,
  present: {E.panel_present(RuleDismissalLaws.application_layers(application), E.panel_target(panel)) == True{} : Bool}) ->
  {E.toggle_panel(panel, trigger, application) == RuleDismissalLaws.closed_application(application, panel, trigger) : E.Decision}:
  E.Application{program, E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}} = application
  +current: E.Application = E.Application{program, E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}}
  Equal.cong(Bool, E.Decision, (owned => E.toggle_panel_selected(owned, panel, trigger, current)),
    E.panel_present(layers, E.panel_target(panel)), True{}, present)

def outside_false(+identity: String, same: Bool, input: Core.Input, +state: Browser.State) ->
  {Browser.outside_permitted((same && False{}) && Browser.outside_layer_owned(identity, Browser.current_layer_key(state)), input, state) == Browser.OutsideDecision{False{}, Browser.Decision{state, Nil{}}} : Browser.OutsideDecision}:
  match same:
    case True{}: {==}
    case False{}: {==}

def RuleDismissalLaws.evidence():
  RuleDismissalLaws.Requirements{
    toggle_absent,
    toggle_present,
    task => trigger => {==},
    action => {==},
    action => {==},
    +kind => +content => +initial => restore => dismissal => +state => {==},
    +key => semantic => label => role => +input => +outside => +escape => children => rest => {==},
    +identity => +state => {==},
    +identity => +key => input => escape => +state => outside_false(identity, String.eq(identity, key), input, state),
    +identity => +key => +input => +outside => escape => +state => stale => Equal.cong(Bool, Browser.OutsideDecision, (same => Browser.outside_permitted((same && outside) && Browser.outside_layer_owned(identity, Browser.current_layer_key(state)), input, state)), String.eq(identity, key), False{}, stale),
    key => input => outside => +state => {==},
    key => +input => outside => +state => {==},
    +identity => +key => +input => escape => +state => owned => Equal.cong(Bool, Browser.OutsideDecision, (same => Browser.outside_permitted((same && True{}) && Browser.outside_layer_owned(identity, Browser.current_layer_key(state)), input, state)), String.eq(identity, key), True{}, owned),
    +identity => +state => {==},
    +identity => +key => +input => +outside => escape => +state => {==},
    input => +state => {==},
    +identity => initial => restore => occurrence => +input => +state => {==},
    +identity => +candidate => +state => closed => Equal.cong(Bool, Browser.OutsideDecision, (allowed => Browser.outside_completed(allowed, candidate, state)), Browser.outside_closed(identity, candidate), True{}, closed),
    +identity => +candidate => +state => retained => Equal.cong(Bool, Browser.OutsideDecision, (allowed => Browser.outside_completed(allowed, candidate, state)), Browser.outside_closed(identity, candidate), False{}, retained),
    +candidate => state => {==},
    candidate => +state => {==},
    {==},
    {==},
    {==},
    {==}}

def RuleDismissalLaws.all_panel_policies(panel, trigger):
  match panel:
    case U.ProjectPicker{}: {==}
    case U.ObjectActions{subject}: {==}
    case U.ArchivedCards{}: {==}
    case U.BoardSettings{}: {==}
    case U.BoardFilters{}: {==}
    case U.CardDetails{card}: {==}
    case U.EditObject{editor}: {==}
    case U.TaskDetails{task}: {==}
    case U.WorkspaceConfiguration{editor}: {==}
    case U.PermissionsConfiguration{editor}: {==}
    case U.TaskContext{task}: {==}
    case U.ModelPicker{editor}: {==}
    case U.DeliveryPicker{task}: {==}
    case U.Confirm{command, title, destination}: {==}

def retained_transition(+previous: Model.Scope, +identity: String, +initial: String, +restore: String, +occurrence: Maybe<&2, Nat>,
  +eligible: Bool, same: {Model.changed(previous, Model.Temporary{identity, initial, restore, occurrence}) == False{} : Bool}) ->
  {Model.transition(previous, Model.Temporary{identity, initial, restore, occurrence}, eligible) == Bool.not(eligible) : Bool}:
  Equal.cong(Bool, Bool, (changed => changed || Bool.not(eligible)),
    Model.changed(previous, Model.Temporary{identity, initial, restore, occurrence}), False{}, same)

def document_transition(+previous: Model.Scope, eligible: Bool,
  same: {Model.changed(previous, Model.Document{}) == False{} : Bool}) ->
  {Model.transition(previous, Model.Document{}, eligible) == False{} : Bool}:
  Equal.cong(Bool, Bool, (changed => changed || False{}), Model.changed(previous, Model.Document{}), False{}, same)

def explicit_attention_precedes(+trigger: Bool, previous: Model.Scope, current: Model.Scope,
  +target: String, +ticket: Nat) ->
  {Platform.scope_effects(trigger, previous, current, [E.Attend{target}],
    Platform.focus_revision(trigger, [E.Attend{target}], ticket)) == [Platform.Focus{(ticket + 1n : Nat), Model.Product{target}}] : +List<Platform.Effect>}:
  match trigger:
    case True{}: {==}
    case False{}: {==}

def scope_handoff_owned(+previous: Model.Scope, +current: Model.Scope, +focused: String,
  +eligible: Bool, +handoff: Bool,
  ordinary: {Model.transition(previous, current, eligible) == False{} : Bool},
  ownership: {Platform.scope_handoff(previous, current, Model.Product{focused}) == handoff : Bool}) ->
  {Platform.focus_transition(previous, current, Model.Product{focused}, eligible) == handoff : Bool}:
  Equal.trans(Bool, Platform.focus_transition(previous, current, Model.Product{focused}, eligible),
    False{} || Platform.scope_handoff(previous, current, Model.Product{focused}), handoff,
    Equal.cong(Bool, Bool, (transition => transition || Platform.scope_handoff(previous, current, Model.Product{focused})),
      Model.transition(previous, current, eligible), False{}, ordinary), ownership)

def retained_root_handoff(+identity: String, +old_initial: String, +initial: String,
  +restore: String, +old_occurrence: Maybe<&2, Nat>, +occurrence: Maybe<&2, Nat>, +focused: String,
  retained: {String.eq(focused, old_initial) == True{} : Bool},
  root: {String.eq(identity, identity) && String.eq(old_initial, identity) == True{} : Bool},
  changed: {Bool.not(String.eq(old_initial, initial)) == True{} : Bool}) ->
  {Platform.scope_handoff(Model.Temporary{identity, old_initial, restore, old_occurrence},
    Model.Temporary{identity, initial, restore, occurrence}, Model.Product{focused}) == True{} : Bool}:
  +resolved_root = Equal.cong(Bool, Bool,
    (at_root => at_root && Bool.not(String.eq(old_initial, initial))),
    String.eq(identity, identity) && String.eq(old_initial, identity), True{}, root)
  +resolved_target = Equal.trans(Bool,
    (String.eq(identity, identity) && String.eq(old_initial, identity)) && Bool.not(String.eq(old_initial, initial)),
    Bool.not(String.eq(old_initial, initial)), True{}, resolved_root, changed)
  Equal.trans(Bool,
    Platform.scope_handoff(Model.Temporary{identity, old_initial, restore, old_occurrence}, Model.Temporary{identity, initial, restore, occurrence}, Model.Product{focused}),
    Platform.retained_root_handoff(True{}, String.eq(identity, identity) && String.eq(old_initial, identity), Bool.not(String.eq(old_initial, initial))),
    True{}, Equal.cong(Bool, Bool,
      (owned => Platform.retained_root_handoff(owned, String.eq(identity, identity) && String.eq(old_initial, identity), Bool.not(String.eq(old_initial, initial)))),
      String.eq(focused, old_initial), True{}, retained), resolved_target)

def after_core_effects(+decision: Core.Decision, platform: Platform.Platform, +current: Model.Scope) ->
  {RuleFocusRetentionLaws.effects(Platform.after_core_scoped(decision, platform, current)) ==
    RuleFocusRetentionLaws.expected_effects(decision, platform, current) : +List<Platform.Effect>}:
  match decision platform:
    case Core.Decision{Core.State{application, services}, reply, runtime, interaction, service, durable}
      Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope}: {==}

def RuleFocusRetentionLaws.evidence():
  RuleFocusRetentionLaws.Requirements{{==}, key => semantic => label => role => +meaning => children => unavailable => unavailable, +previous => +identity => +initial => +restore => +occurrence => +ticket => same =>
      Equal.cong(Bool, +List<Platform.Effect>,
        (trigger => Platform.scope_effects(trigger, previous, Model.Temporary{identity, initial, restore, occurrence}, Nil{},
          Platform.focus_revision(trigger, Nil{}, ticket))),
        Model.transition(previous, Model.Temporary{identity, initial, restore, occurrence}, False{}), True{},
        retained_transition(previous, identity, initial, restore, occurrence, False{}, same))
    , +previous => +identity => +initial => +restore => +occurrence => +ticket => same =>
      Equal.cong(Bool, +List<Platform.Effect>,
        (trigger => Platform.scope_effects(trigger, previous, Model.Temporary{identity, initial, restore, occurrence}, Nil{},
          Platform.focus_revision(trigger, Nil{}, ticket))),
        Model.transition(previous, Model.Temporary{identity, initial, restore, occurrence}, True{}), False{},
        retained_transition(previous, identity, initial, restore, occurrence, True{}, same))
    , +previous => +eligible => +ticket => same =>
      Equal.cong(Bool, +List<Platform.Effect>,
        (trigger => Platform.scope_effects(trigger, previous, Model.Document{}, Nil{}, Platform.focus_revision(trigger, Nil{}, ticket))),
        Model.transition(previous, Model.Document{}, eligible), False{}, document_transition(previous, eligible, same))
    , explicit_attention_precedes, after_core_effects, +identity => +old_initial => +initial => +restore => +old_occurrence => +occurrence => +focused => +ticket => same => retained => root => changed =>
      Equal.cong(Bool, +List<Platform.Effect>,
        (trigger => Platform.scope_effects(trigger, Model.Temporary{identity, old_initial, restore, old_occurrence}, Model.Temporary{identity, initial, restore, occurrence}, Nil{}, Platform.focus_revision(trigger, Nil{}, ticket))),
        Platform.focus_transition(Model.Temporary{identity, old_initial, restore, old_occurrence}, Model.Temporary{identity, initial, restore, occurrence}, Model.Product{focused}, True{}), True{},
        scope_handoff_owned(Model.Temporary{identity, old_initial, restore, old_occurrence}, Model.Temporary{identity, initial, restore, occurrence}, focused, True{}, True{},
          retained_transition(Model.Temporary{identity, old_initial, restore, old_occurrence}, identity, initial, restore, occurrence, True{}, same),
          retained_root_handoff(identity, old_initial, initial, restore, old_occurrence, occurrence, focused, retained, root, changed)))
    , +identity => +old_initial => +initial => +restore => +old_occurrence => +occurrence => +focused => +ticket => same => moved =>
      Equal.cong(Bool, +List<Platform.Effect>,
        (trigger => Platform.scope_effects(trigger, Model.Temporary{identity, old_initial, restore, old_occurrence}, Model.Temporary{identity, initial, restore, occurrence}, Nil{}, Platform.focus_revision(trigger, Nil{}, ticket))),
        Platform.focus_transition(Model.Temporary{identity, old_initial, restore, old_occurrence}, Model.Temporary{identity, initial, restore, occurrence}, Model.Product{focused}, True{}), False{},
        scope_handoff_owned(Model.Temporary{identity, old_initial, restore, old_occurrence}, Model.Temporary{identity, initial, restore, occurrence}, focused, True{}, False{},
          retained_transition(Model.Temporary{identity, old_initial, restore, old_occurrence}, identity, initial, restore, occurrence, True{}, same),
          Equal.cong(Bool, Bool,
            (owned => Platform.retained_root_handoff(owned, String.eq(identity, identity) && String.eq(old_initial, identity), Bool.not(String.eq(old_initial, initial)))),
            String.eq(focused, old_initial), False{}, moved)))
    }

def RuleFocusRetentionLaws.content_focus_has_no_root_handoff(previous, current, owner, identity): {==}
def RuleFocusRetentionLaws.active_content_uses_owner(core, capacity, owner, identity): {==}
def RuleFocusRetentionLaws.retained_content_no_focus_transition(previous, current, owner, identity, same):
  match current:
    case Model.Document{}:
      Equal.cong(Bool, Bool, (changed => (changed || False{}) || False{}),
        Model.changed(previous, Model.Document{}), False{}, same)
    case Model.Temporary{scope_identity, initial, restore, occurrence}:
      Equal.cong(Bool, Bool, (changed => (changed || False{}) || False{}),
        Model.changed(previous, Model.Temporary{scope_identity, initial, restore, occurrence}), False{}, same)

def RuleFocusRetentionLaws.content_observation_preserves_core(platform, owner, identity, core):
  match platform:
    case Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope}: {==}
