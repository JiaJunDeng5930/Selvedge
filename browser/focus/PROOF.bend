import Base
import ./CONTRACT.bend as Rule
import ./MODEL.bend as Model
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ../../interaction/presentation/CONTRACT.bend as SemanticRules
import ../../interaction/presentation/interaction-proof.bend as SemanticEvidence
import ../../interaction/interactive_markdown/TYPES.bend as IM
import ../../interaction/submission/FIELDS.bend as Forms
import ../../interaction/experience/PROGRAM.bend as UX
import ../../bendlib/association-map.bend as Finite
import ../reading/MODEL.bend as Reading
import ../../interaction/IDENTITY.bend as Identity
import ../../interaction/services/MODEL.bend as Services
import ../../interaction/session/MODEL.bend as E
import ../../interaction/presentation/MODEL.bend as View
import ../../interaction/INPUT.bend as U
import ../runtime/SEMANTICS.bend as Browser
import ../runtime/PLATFORM.bend as Platform
import ../../interaction/presentation/SURFACE.bend as SurfaceTypes
import ../../interaction/TYPES.bend as InteractionTypes
import ../../interaction/STATE.bend as Core
import ../../bendlib/string-equality.bend as SafeText
import ../../bendlib/equality-proof.bend as TextProof

def Rule.same_target_exact(first, second):
  match first second:
    case Model.Product{first} Model.Product{second}: TextProof.public_refines(first, second)
    case Model.Content{+first_owner, +first} Model.Content{+second_owner, +second}:
      Equal.trans(Bool,
        SafeText.string_equal(first_owner, second_owner) && SafeText.string_equal(first, second),
        String.eq(first_owner, second_owner) && SafeText.string_equal(first, second),
        String.eq(first_owner, second_owner) && String.eq(first, second),
        Equal.cong(Bool, Bool, (same => same && SafeText.string_equal(first, second)),
          SafeText.string_equal(first_owner, second_owner), String.eq(first_owner, second_owner),
          TextProof.public_refines(first_owner, second_owner)),
        Equal.cong(Bool, Bool, (same => String.eq(first_owner, second_owner) && same),
          SafeText.string_equal(first, second), String.eq(first, second), TextProof.public_refines(first, second)))
    case Model.Product{first} Model.Content{owner, second}: {==}
    case Model.Content{owner, first} Model.Product{second}: {==}

def Rule.cycle_evidence():
  Rule.CycleRequirements{order => focused => reverse => {==}, +key => +focused => previous => +first => +last => matching =>
      Equal.cong(Bool, Maybe<&2, String>,
        (hit => Model.cycle_match(hit, False{}, previous, Nil{}, first, last, first)),
        SafeText.string_equal(key, focused), True{},
        Equal.trans(Bool, SafeText.string_equal(key, focused), String.eq(key, focused), True{}, TextProof.public_refines(key, focused), matching))
    , +key => +rest => +focused => matching =>
      Equal.cong(Bool, Maybe<&2, String>,
        (hit => Model.cycle_match(hit, True{}, None{}, rest, Some{key},
          List.head(&2, String, List.reverse(&2, String, key <> rest)),
          Model.cycle_scan(rest, focused, Some{key}, Some{key}, List.head(&2, String, List.reverse(&2, String, key <> rest)), True{}))),
        SafeText.string_equal(key, focused), True{},
        Equal.trans(Bool, SafeText.string_equal(key, focused), String.eq(key, focused), True{}, TextProof.public_refines(key, focused), matching))
    }

def Rule.realized_restore(content, base, overlays, active, scope, key, found):
  Equal.cong(Maybe<&2, String>, String, Model.resolved_target,
    InterfaceView.all_focus_target(SurfaceTypes.Surface{content, base, overlays, Some{active}}, Model.restore(scope)), Some{Identity.encode(key)}, found)

def Rule.settings_restore(content, base, overlays, active, fallback):
  {==}

def Rule.settings_resolved_restore(content, base, overlays, active, fallback, key, found):
  Rule.realized_restore(content, base, overlays, active, Model.settings_scope(True{}, fallback), key, found)

def Rule.responsive_settings_restore_targets(): ({==}, {==})

def Rule.responsive_settings_restore(content, base, overlays, active, navigation_beside, fallback): {==}

def Rule.responsive_settings_resolved_restore(content, base, overlays, active, navigation_beside, fallback, key, found):
  Rule.realized_restore(content, base, overlays, active, Model.settings_scope_restore(True{}, navigation_beside, fallback), key, found)

def Rule.responsive_settings_policy(open, navigation_beside, fallback):
  match open navigation_beside:
    case False{} _: {==}
    case True{} True{}: {==}
    case True{} False{}: {==}

def Rule.desktop_settings_policy_unchanged(open, fallback):
  match open:
    case False{}: {==}
    case True{}: {==}

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
    case InteractionTypes.State{E.Application{program, E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git, interactive}}, Services.State{access, settings, appearance, next_service, transfers, preview, directory_picker}} View.Capacity{navigation_beside, details_beside}: {==}

def Rule.current_surface(state, capacity, surface, observed):
  Equal.cong(SurfaceTypes.Surface, Model.Scope, (actual => Model.realized_scope(actual, Model.logical_scope(state, capacity))), InterfaceView.observe(capacity, state), surface, observed)

def toggle_absent(+application: E.Application, +panel: U.Panel, +trigger: String,
  absent: {E.panel_present(Rule.application_layers(application), E.panel_target(panel)) == False{} : Bool}) ->
  {E.toggle_panel(panel, trigger, application) == E.open_panel(panel, trigger, application) : E.Decision}:
  E.Application{program, E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git, interactive}} = application
  +current: E.Application = E.Application{program, E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git, interactive}}
  Equal.cong(Bool, E.Decision, (present => E.toggle_panel_selected(present, panel, trigger, current)),
    E.panel_present(layers, E.panel_target(panel)), False{}, absent)

def toggle_present(+application: E.Application, +panel: U.Panel, +trigger: String,
  present: {E.panel_present(Rule.application_layers(application), E.panel_target(panel)) == True{} : Bool}) ->
  {E.toggle_panel(panel, trigger, application) == Rule.closed_application(application, panel, trigger) : E.Decision}:
  E.Application{program, E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git, interactive}} = application
  +current: E.Application = E.Application{program, E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git, interactive}}
  Equal.cong(Bool, E.Decision, (owned => E.toggle_panel_selected(owned, panel, trigger, current)),
    E.panel_present(layers, E.panel_target(panel)), True{}, present)

def outside_false(+identity: String, same: Bool, input: InteractionTypes.Input, +state: Browser.State) ->
  {Browser.outside_permitted((same && False{}) && Browser.outside_layer_owned(identity, Browser.current_layer_key(state)), input, state) == Browser.OutsideDecision{False{}, Browser.Decision{state, Nil{}}} : Browser.OutsideDecision}:
  match same:
    case True{}: {==}
    case False{}: {==}

def Rule.dismissal_evidence():
  Rule.DismissalRequirements{
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

def Rule.all_panel_policies(panel, trigger):
  match panel:
    case U.GlobalNavigation{}: {==}
    case U.PropertySource{origin}: {==}
    case U.WorkOverview{}: {==}
    case U.ProjectPicker{}: {==}
    case U.ObjectActions{subject}: {==}
    case U.ArchivedCards{}: {==}
    case U.BoardSettings{}: {==}
    case U.BoardFilters{}: {==}
    case U.CardDetails{card}: {==}
    case U.EditObject{editor}: {==}
    case U.TaskDetails{task}: {==}
    case U.SideConversation{task}: {==}
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

def occurrence_policy(previous: Maybe<&2, Nat>, current: Maybe<&2, Nat>) ->
  {Model.same_occurrence(previous, current) == Rule.required_same_occurrence(previous, current) : Bool}:
  match previous current:
    case None{} None{}: {==}
    case None{} Some{value}: {==}
    case Some{value} None{}: {==}
    case Some{before} Some{after}: {==}

def retained_handoff_policy(retained: Bool, +root: Bool, +changed: Bool) ->
  {Platform.retained_root_handoff(retained, root, changed) == Bool.pick(Bool, retained, root && changed, False{}) : Bool}:
  match retained:
    case False{}: {==}
    case True{}: {==}

def transition_policy(+previous: Model.Scope, +current: Model.Scope, +focused: Model.Target, +eligible: Bool) ->
  {Platform.focus_transition(previous, current, focused, eligible) == Rule.required_transition(previous, current, focused, eligible) : Bool}:
  match previous current focused:
    case Model.Document{} Model.Document{} Model.Product{identity}: {==}
    case Model.Document{} Model.Document{} Model.Content{owner, identity}: {==}
    case Model.Document{} Model.Temporary{identity, initial, restore, occurrence} Model.Product{focused_identity}: {==}
    case Model.Document{} Model.Temporary{identity, initial, restore, occurrence} Model.Content{owner, focused_identity}: {==}
    case Model.Temporary{old_identity, old_initial, old_restore, old_occurrence} Model.Document{} Model.Product{identity}: {==}
    case Model.Temporary{old_identity, old_initial, old_restore, old_occurrence} Model.Document{} Model.Content{owner, identity}: {==}
    case Model.Temporary{+old_identity, +old_initial, old_restore, +old_occurrence} Model.Temporary{+identity, +initial, restore, +occurrence} Model.Product{+focused_identity}:
      Equal.trans(Bool,
        (Bool.not(String.eq(old_identity, identity) && Model.same_occurrence(old_occurrence, occurrence)) || Bool.not(eligible)) ||
          Platform.retained_root_handoff(String.eq(focused_identity, old_initial), String.eq(old_identity, identity) && String.eq(old_initial, old_identity), Bool.not(String.eq(old_initial, initial))),
        (Bool.not(String.eq(old_identity, identity) && Rule.required_same_occurrence(old_occurrence, occurrence)) || Bool.not(eligible)) ||
          Platform.retained_root_handoff(String.eq(focused_identity, old_initial), String.eq(old_identity, identity) && String.eq(old_initial, old_identity), Bool.not(String.eq(old_initial, initial))),
        (Bool.not(String.eq(old_identity, identity) && Rule.required_same_occurrence(old_occurrence, occurrence)) || Bool.not(eligible)) ||
          Bool.pick(Bool, String.eq(focused_identity, old_initial), (String.eq(old_identity, identity) && String.eq(old_initial, old_identity)) && Bool.not(String.eq(old_initial, initial)), False{}),
        Equal.cong(Bool, Bool,
          (same => (Bool.not(String.eq(old_identity, identity) && same) || Bool.not(eligible)) ||
            Platform.retained_root_handoff(String.eq(focused_identity, old_initial), String.eq(old_identity, identity) && String.eq(old_initial, old_identity), Bool.not(String.eq(old_initial, initial)))),
          Model.same_occurrence(old_occurrence, occurrence), Rule.required_same_occurrence(old_occurrence, occurrence), occurrence_policy(old_occurrence, occurrence)),
        Equal.cong(Bool, Bool,
          (handoff => (Bool.not(String.eq(old_identity, identity) && Rule.required_same_occurrence(old_occurrence, occurrence)) || Bool.not(eligible)) || handoff),
          Platform.retained_root_handoff(String.eq(focused_identity, old_initial), String.eq(old_identity, identity) && String.eq(old_initial, old_identity), Bool.not(String.eq(old_initial, initial))),
          Bool.pick(Bool, String.eq(focused_identity, old_initial), (String.eq(old_identity, identity) && String.eq(old_initial, old_identity)) && Bool.not(String.eq(old_initial, initial)), False{}),
          retained_handoff_policy(String.eq(focused_identity, old_initial), String.eq(old_identity, identity) && String.eq(old_initial, old_identity), Bool.not(String.eq(old_initial, initial)))))
    case Model.Temporary{+old_identity, old_initial, old_restore, +old_occurrence} Model.Temporary{+identity, initial, restore, +occurrence} Model.Content{owner, focused_identity}:
      Equal.cong(Bool, Bool, (same => (Bool.not(String.eq(old_identity, identity) && same) || Bool.not(eligible)) || False{}),
        Model.same_occurrence(old_occurrence, occurrence), Rule.required_same_occurrence(old_occurrence, occurrence), occurrence_policy(old_occurrence, occurrence))

def attention_policy(effects: +List<E.Effect>) ->
  {Platform.has_attention(effects) == Rule.required_explicit_focus(effects) : Bool}:
  match effects:
    case Nil{}: {==}
    case Con{E.Attend{target}, rest}: {==}
    case Con{E.RequestCommand{command, completion}, rest}: attention_policy(rest)
    case Con{E.ContentEffect{identity, effect}, rest}: attention_policy(rest)
    case Con{E.ObserveWorkspaceGit{ticket, primary}, rest}: attention_policy(rest)
    case Con{E.ObserveDirectories{ticket, entered}, rest}: attention_policy(rest)
    case Con{E.PersistModelPreference{profile, reasoning}, rest}: attention_policy(rest)
    case Con{E.InteractiveEffect{effect}, rest}: attention_policy(rest)
    case Con{E.ObserveInteractiveMarkdown{document}, rest}: attention_policy(rest)
    case Con{E.ForgetInteractiveMarkdown{key}, rest}: attention_policy(rest)

def explicit_effect_policy(effects: +List<E.Effect>, +ticket: Nat) ->
  {Platform.focus_effects(effects, ticket) == Rule.required_explicit_effects(effects, ticket) : +List<Platform.Effect>}:
  match effects:
    case Nil{}: {==}
    case Con{E.Attend{target}, rest}:
      Equal.cong(+List<Platform.Effect>, +List<Platform.Effect>, (tail => Platform.Focus{ticket, Model.Product{target}} <> tail),
        Platform.focus_effects(rest, ticket), Rule.required_explicit_effects(rest, ticket), explicit_effect_policy(rest, ticket))
    case Con{E.ContentEffect{identity, effect}, rest}:
      Equal.cong(+List<Platform.Effect>, +List<Platform.Effect>, (tail => Platform.Clipboard{identity, effect} <> tail),
        Platform.focus_effects(rest, ticket), Rule.required_explicit_effects(rest, ticket), explicit_effect_policy(rest, ticket))
    case Con{E.RequestCommand{command, completion}, rest}: explicit_effect_policy(rest, ticket)
    case Con{E.ObserveWorkspaceGit{observed_ticket, primary}, rest}: explicit_effect_policy(rest, ticket)
    case Con{E.ObserveDirectories{observed_ticket, entered}, rest}: explicit_effect_policy(rest, ticket)
    case Con{E.PersistModelPreference{profile, reasoning}, rest}: explicit_effect_policy(rest, ticket)
    case Con{E.InteractiveEffect{effect}, rest}: explicit_effect_policy(rest, ticket)
    case Con{E.ObserveInteractiveMarkdown{document}, rest}: explicit_effect_policy(rest, ticket)
    case Con{E.ForgetInteractiveMarkdown{key}, rest}: explicit_effect_policy(rest, ticket)

def content_effect_policy(effects: +List<E.Effect>) ->
  {Platform.content_effects(effects) == Rule.required_content_effects(effects) : +List<Platform.Effect>}:
  match effects:
    case Nil{}: {==}
    case Con{E.ContentEffect{identity, effect}, rest}:
      Equal.cong(+List<Platform.Effect>, +List<Platform.Effect>, (tail => Platform.Clipboard{identity, effect} <> tail),
        Platform.content_effects(rest), Rule.required_content_effects(rest), content_effect_policy(rest))
    case Con{E.RequestCommand{command, completion}, rest}: content_effect_policy(rest)
    case Con{E.ObserveWorkspaceGit{ticket, primary}, rest}: content_effect_policy(rest)
    case Con{E.ObserveDirectories{ticket, entered}, rest}: content_effect_policy(rest)
    case Con{E.Attend{target}, rest}: content_effect_policy(rest)
    case Con{E.PersistModelPreference{profile, reasoning}, rest}: content_effect_policy(rest)
    case Con{E.InteractiveEffect{effect}, rest}: content_effect_policy(rest)
    case Con{E.ObserveInteractiveMarkdown{document}, rest}: content_effect_policy(rest)
    case Con{E.ForgetInteractiveMarkdown{key}, rest}: content_effect_policy(rest)

def scoped_attention_policy(explicit: Bool, +previous: Model.Scope, +current: Model.Scope, +effects: +List<E.Effect>, +ticket: Nat) ->
  {Platform.scope_attention(explicit, previous, current, effects, ticket) ==
    Bool.pick((+List<Platform.Effect>), explicit, Rule.required_explicit_effects(effects, ticket),
      Platform.ScopeFocus{ticket, previous, current} <> Rule.required_content_effects(effects)) : +List<Platform.Effect>}:
  match explicit:
    case True{}: explicit_effect_policy(effects, ticket)
    case False{}:
      Equal.cong(+List<Platform.Effect>, +List<Platform.Effect>, (tail => Platform.ScopeFocus{ticket, previous, current} <> tail),
        Platform.content_effects(effects), Rule.required_content_effects(effects), content_effect_policy(effects))

def scope_effect_policy(transition: Bool, +previous: Model.Scope, +current: Model.Scope, +effects: +List<E.Effect>, +ticket: Nat) ->
  {Platform.scope_effects(transition, previous, current, effects, ticket) == Rule.required_scope_effects(transition, previous, current, effects, ticket) : +List<Platform.Effect>}:
  match transition:
    case False{}: explicit_effect_policy(effects, ticket)
    case True{}:
      Equal.trans(+List<Platform.Effect>, Platform.scope_effects(True{}, previous, current, effects, ticket),
        Bool.pick((+List<Platform.Effect>), Platform.has_attention(effects), Rule.required_explicit_effects(effects, ticket),
          Platform.ScopeFocus{ticket, previous, current} <> Rule.required_content_effects(effects)),
        Rule.required_scope_effects(True{}, previous, current, effects, ticket),
        scoped_attention_policy(Platform.has_attention(effects), previous, current, effects, ticket),
        Equal.cong(Bool, +List<Platform.Effect>,
          (explicit => Bool.pick((+List<Platform.Effect>), explicit, Rule.required_explicit_effects(effects, ticket),
            Platform.ScopeFocus{ticket, previous, current} <> Rule.required_content_effects(effects))),
          Platform.has_attention(effects), Rule.required_explicit_focus(effects), attention_policy(effects)))

def advance_ticket_policy(advance: Bool, +ticket: Nat) ->
  {Platform.advance_ticket(advance, ticket) == Bool.pick(Nat, advance, (ticket + 1n : Nat), ticket) : Nat}:
  match advance:
    case False{}: {==}
    case True{}: {==}

def ticket_policy(+transition: Bool, +effects: +List<E.Effect>, +ticket: Nat) ->
  {Platform.focus_revision(transition, effects, ticket) == Rule.required_focus_ticket(transition, effects, ticket) : Nat}:
  Equal.trans(Nat, Platform.focus_revision(transition, effects, ticket),
    Bool.pick(Nat, transition || Platform.has_attention(effects), (ticket + 1n : Nat), ticket),
    Rule.required_focus_ticket(transition, effects, ticket),
    advance_ticket_policy(transition || Platform.has_attention(effects), ticket),
    Equal.cong(Bool, Nat, (explicit => Bool.pick(Nat, transition || explicit, (ticket + 1n : Nat), ticket)),
      Platform.has_attention(effects), Rule.required_explicit_focus(effects), attention_policy(effects)))

def reading_effect_policy(effects: +List<Reading.Effect>, +task: Nat, +generation: Nat) ->
  {Platform.wrap_scroll(effects, task, generation) == Rule.required_reading_effects(effects, task, generation) : +List<Platform.Effect>}:
  match effects:
    case Nil{}: {==}
    case Con{effect, rest}:
      Equal.cong(+List<Platform.Effect>, +List<Platform.Effect>, (tail => Platform.ApplyReading{task, generation, effect} <> tail),
        Platform.wrap_scroll(rest, task, generation), Rule.required_reading_effects(rest, task, generation), reading_effect_policy(rest, task, generation))

def bookmark_policy(found: Maybe<&2, Reading.Bookmark>) ->
  {Platform.bookmark(found) == Rule.required_bookmark(found) : Reading.Bookmark}:
  match found:
    case None{}: {==}
    case Some{value}: {==}

def route_layout_policy(+route: U.Route, +readers: +List<Finite.Entry(E.Reader)>, +bookmarks: +List<Finite.Entry(Reading.Bookmark)>) ->
  {Platform.layout_route(route, readers, bookmarks) == Rule.required_route_layout(route, readers, bookmarks) : +List<Platform.Effect>}:
  match route:
    case U.Conversation{+task}:
      Equal.trans(+List<Platform.Effect>, Platform.layout_route(U.Conversation{task}, readers, bookmarks),
        Rule.required_reading_effects(Reading.layout(E.reader_position(E.reader(readers, task)),
          Platform.bookmark(Finite.find(~Reading.Bookmark, bookmarks, task))), task, E.reader_generation(E.reader(readers, task))),
        Rule.required_route_layout(U.Conversation{task}, readers, bookmarks),
        reading_effect_policy(Reading.layout(E.reader_position(E.reader(readers, task)),
          Platform.bookmark(Finite.find(~Reading.Bookmark, bookmarks, task))), task, E.reader_generation(E.reader(readers, task))),
        Equal.cong(Reading.Bookmark, +List<Platform.Effect>,
          (bookmark => Rule.required_reading_effects(Reading.layout(E.reader_position(E.reader(readers, task)), bookmark), task, E.reader_generation(E.reader(readers, task)))),
          Platform.bookmark(Finite.find(~Reading.Bookmark, bookmarks, task)), Rule.required_bookmark(Finite.find(~Reading.Bookmark, bookmarks, task)),
          bookmark_policy(Finite.find(~Reading.Bookmark, bookmarks, task))))
    case U.Start{}: {==}
    case U.ProjectHome{project}: {==}
    case U.ProjectCollection{}: {==}
    case U.TaskBoard{}: {==}
    case U.AgentCollection{}: {==}
    case U.TaskGraphs{}: {==}

def tasks_layout_policy(+tasks: +List<Nat>, +readers: +List<Finite.Entry(E.Reader)>, +bookmarks: +List<Finite.Entry(Reading.Bookmark)>) ->
  {Platform.layout_tasks(tasks, readers, bookmarks) == Rule.required_tasks_layout(tasks, readers, bookmarks) : +List<Platform.Effect>}:
  match tasks:
    case Nil{}: {==}
    case Con{+task, +rest}:
      Equal.trans(+List<Platform.Effect>, Platform.layout_tasks(task <> rest, readers, bookmarks),
        List.append(&2, Platform.Effect, Rule.required_route_layout(U.Conversation{task}, readers, bookmarks), Platform.layout_tasks(rest, readers, bookmarks)),
        Rule.required_tasks_layout(task <> rest, readers, bookmarks),
        Equal.cong(+List<Platform.Effect>, +List<Platform.Effect>,
          (head => List.append(&2, Platform.Effect, head, Platform.layout_tasks(rest, readers, bookmarks))),
          Platform.layout_route(U.Conversation{task}, readers, bookmarks), Rule.required_route_layout(U.Conversation{task}, readers, bookmarks),
          route_layout_policy(U.Conversation{task}, readers, bookmarks)),
        Equal.cong(+List<Platform.Effect>, +List<Platform.Effect>,
          (tail => List.append(&2, Platform.Effect, Rule.required_route_layout(U.Conversation{task}, readers, bookmarks), tail)),
          Platform.layout_tasks(rest, readers, bookmarks), Rule.required_tasks_layout(rest, readers, bookmarks), tasks_layout_policy(rest, readers, bookmarks)))

def layout_policy(+application: E.Application, +bookmarks: +List<Finite.Entry(Reading.Bookmark)>) ->
  {Platform.layout_for(application, bookmarks) == Rule.required_layout(application, bookmarks) : +List<Platform.Effect>}:
  +session = E.session(application)
  tasks_layout_policy(E.visible_tasks(session), E.readers(session), bookmarks)

def scope_node_policy(found: Maybe<&2, SurfaceTypes.Node>) ->
  {InterfaceView.scope_node(found) == Rule.required_scope_nodes(found) : +List<SurfaceTypes.Node>}:
  match found:
    case None{}: {==}
    case Some{node}: {==}

def active_nodes_policy(+surface: SurfaceTypes.Surface) ->
  {InterfaceView.active_nodes(surface) == Rule.required_active_nodes(surface) : +List<SurfaceTypes.Node>}:
  SurfaceTypes.Surface{content, base, +overlays, scope} = surface
  match scope:
    case None{}: {==}
    case Some{+key}:
      Equal.trans(+List<SurfaceTypes.Node>, InterfaceView.active_nodes(surface),
        Rule.required_scope_nodes(InterfaceView.find_node(overlays, key)), Rule.required_active_nodes(surface),
        scope_node_policy(InterfaceView.find_node(overlays, key)),
        Equal.cong((Maybe<&2, SurfaceTypes.Node>), +List<SurfaceTypes.Node>, Rule.required_scope_nodes,
          InterfaceView.find_node(overlays, key), SemanticRules.first_named_node(overlays, key), SemanticRules.complete_node_lookup(overlays, key)))

def availability_policy(availability: View.Availability) ->
  {InterfaceView.available(availability) == Rule.required_available(availability) : Bool}:
  match availability:
    case View.Available{}: {==}
    case View.NeedsDirectoryObservation{}: {==}
    case View.Unavailable{reason}: {==}

def focusability_policy(meaning: SurfaceTypes.Meaning) ->
  {InterfaceView.focusable(meaning) == Rule.required_focusable(meaning) : Bool}:
  match meaning:
    case SurfaceTypes.SettingEntry{value_subject, value_value, value_input, value_availability}: availability_policy(value_availability)
    case SurfaceTypes.ActivityRow{value_role}: {==}
    case SurfaceTypes.ActivityGroup{value_activity, value_dismiss, value_outside, value_escape}: {==}
    case SurfaceTypes.DecisionGroup{value_decision}: {==}
    case SurfaceTypes.WorkspaceCollection{value_collection}: {==}
    case SurfaceTypes.WorkspaceMember{value_collection, value_path}: {==}
    case SurfaceTypes.ActionUnit{value_action}: {==}
    case SurfaceTypes.ActionFeedback{value_feedback}: {==}
    case SurfaceTypes.ActionExplanation{value_assessment}: {==}
    case SurfaceTypes.ActionCommit{+value_assessment, value_input, +value_availability}:
      Equal.cong(Bool, Bool, (available => UX.assessment_ready(value_assessment) && available),
        InterfaceView.available(value_availability), Rule.required_available(value_availability), availability_policy(value_availability))
    case SurfaceTypes.ObjectGroup{value_object}: {==}
    case SurfaceTypes.SupportingControl{+value_support, value_property, value_input, +value_availability}:
      Equal.cong(Bool, Bool, (available => UX.support_visible(value_support) && available),
        InterfaceView.available(value_availability), Rule.required_available(value_availability), availability_policy(value_availability))
    case SurfaceTypes.InformationText{value_role}: {==}
    case SurfaceTypes.LayerRegion{value_dismiss, value_outside, value_escape}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{value_value}: {==}
    case SurfaceTypes.PanelToggle{value_expanded, value_input, value_availability}: availability_policy(value_availability)
    case SurfaceTypes.CardContent{value_face}: {==}
    case SurfaceTypes.MovableCard{value_destinations, value_face}: {==}
    case SurfaceTypes.Region{}: {==}
    case SurfaceTypes.PageContext{value_conversation}: {==}
    case SurfaceTypes.ActivityContent{value_expanded, value_audit}: {==}
    case SurfaceTypes.ProjectGroup{value_project, value_selected, value_expanded}: {==}
    case SurfaceTypes.TaskRow{value_task, value_status, value_selected}: {==}
    case SurfaceTypes.TaskChildren{value_task}: {==}
    case SurfaceTypes.ProjectChooser{value_selected}: {==}
    case SurfaceTypes.DirectoryRow{value_path, value_primary}: {==}
    case SurfaceTypes.ContextSummary{value_observation}: {==}
    case SurfaceTypes.ChoiceGroup{}: {==}
    case SurfaceTypes.Choice{value_kind, value_classification, value_selected, value_description, value_input, value_availability}: availability_policy(value_availability)
    case SurfaceTypes.PageRegion{value_region, value_position}: {==}
    case SurfaceTypes.BoardLane{value_stage, value_count}: {==}
    case SurfaceTypes.CardArchive{value_count}: {==}
    case SurfaceTypes.BoardSearch{value_filter}: {==}
    case SurfaceTypes.BoardGroup{value_grouping}: {==}
    case SurfaceTypes.ReadOnly{value_text}: {==}
    case SurfaceTypes.Fact{value_value}: {==}
    case SurfaceTypes.RichText{value_source, value_value}: {==}
    case SurfaceTypes.TaskFacts{value_details}: {==}
    case SurfaceTypes.CodeFacts{value_view}: {==}
    case SurfaceTypes.InteractiveRegion{value_identity, value_source_visible}: {==}
    case SurfaceTypes.InteractiveNode{IM.ExpandedNode{identity, occurrence, tag, attrs, IM.NoBinding{}, children}}: {==}
    case SurfaceTypes.InteractiveNode{IM.ExpandedNode{identity, occurrence, tag, attrs, IM.FieldBinding{state_id, schema, raw, canonical, validation, enabled}, children}}: {==}
    case SurfaceTypes.InteractiveNode{IM.ExpandedNode{identity, occurrence, tag, attrs, IM.ActionBinding{kind, enabled, pending}, children}}: {==}
    case SurfaceTypes.InteractiveView{value_event, value_command, value_label, value_enabled}: {==}
    case SurfaceTypes.Activate{value_input, value_availability}: availability_policy(value_availability)
    case SurfaceTypes.Edit{value_editor, value_field, Forms.DisplayOnly{}, value_value, value_choices}: {==}
    case SurfaceTypes.Edit{value_editor, value_field, Forms.SingleLine{}, value_value, value_choices}: {==}
    case SurfaceTypes.Edit{value_editor, value_field, Forms.Multiline{}, value_value, value_choices}: {==}
    case SurfaceTypes.Edit{value_editor, value_field, Forms.StructuredText{}, value_value, value_choices}: {==}
    case SurfaceTypes.Edit{value_editor, value_field, Forms.Choice{}, value_value, value_choices}: {==}
    case SurfaceTypes.Edit{value_editor, value_field, Forms.MultipleChoices{}, value_value, value_choices}: {==}
    case SurfaceTypes.Edit{value_editor, value_field, Forms.PositiveInteger{}, value_value, value_choices}: {==}
    case SurfaceTypes.Edit{value_editor, value_field, Forms.DirectoryCollection{}, value_value, value_choices}: {==}
    case SurfaceTypes.Edit{value_editor, value_field, Forms.FileCollection{}, value_value, value_choices}: {==}
    case SurfaceTypes.SearchChoices{value_query}: {==}
    case SurfaceTypes.ReceiveFile{value_editor, value_enabled}: {==}
    case SurfaceTypes.EnterDirectory{value_editor, value_text}: {==}
    case SurfaceTypes.BoardProfile{value_automatic, value_selected, value_choices, value_enabled}: {==}

def content_owner_policy(found: Maybe<&2, SurfaceTypes.Node>) ->
  {Platform.found_content_owner(found) == Rule.required_content_owner(found) : Bool}:
  match found:
    case None{}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.SettingEntry{meaning_subject, meaning_value, meaning_input, meaning_availability}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ActivityRow{meaning_role}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ActivityGroup{meaning_activity, meaning_dismiss, meaning_outside, meaning_escape}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.DecisionGroup{meaning_decision}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.WorkspaceCollection{meaning_collection}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.WorkspaceMember{meaning_collection, meaning_path}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ActionUnit{meaning_action}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ActionFeedback{meaning_feedback}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ActionExplanation{meaning_assessment}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ActionCommit{meaning_assessment, meaning_input, meaning_availability}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ObjectGroup{meaning_object}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.SupportingControl{meaning_support, meaning_property, meaning_input, meaning_availability}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.InformationText{meaning_role}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.LayerRegion{meaning_dismiss, meaning_outside, meaning_escape}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.DirectoryBrowserLocation{meaning_value}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.PanelToggle{meaning_expanded, meaning_input, meaning_availability}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.CardContent{meaning_face}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.MovableCard{meaning_destinations, meaning_face}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.Region{}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.PageContext{meaning_conversation}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ActivityContent{meaning_expanded, meaning_audit}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ProjectGroup{meaning_project, meaning_selected, meaning_expanded}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.TaskRow{meaning_task, meaning_status, meaning_selected}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.TaskChildren{meaning_task}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ProjectChooser{meaning_selected}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.DirectoryRow{meaning_path, meaning_primary}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ContextSummary{meaning_observation}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ChoiceGroup{}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.Choice{meaning_kind, meaning_classification, meaning_selected, meaning_description, meaning_input, meaning_availability}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.PageRegion{meaning_region, meaning_position}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.BoardLane{meaning_stage, meaning_count}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.CardArchive{meaning_count}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.BoardSearch{meaning_filter}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.BoardGroup{meaning_grouping}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ReadOnly{meaning_text}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.Fact{meaning_value}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.RichText{meaning_source, meaning_value}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.TaskFacts{meaning_details}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.CodeFacts{meaning_view}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.InteractiveRegion{meaning_identity, meaning_source_visible}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.InteractiveNode{IM.ExpandedNode{identity, occurrence, tag, attrs, binding, original}}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.InteractiveView{meaning_event, meaning_command, meaning_label, meaning_enabled}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.Activate{meaning_input, meaning_availability}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.Edit{meaning_editor, meaning_field, meaning_entry, meaning_value, meaning_choices}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.SearchChoices{meaning_query}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ReceiveFile{meaning_editor, meaning_enabled}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.EnterDirectory{meaning_editor, meaning_text}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.BoardProfile{meaning_automatic, meaning_selected, meaning_choices, meaning_enabled}, children}}: {==}


def product_target_policy(found: Maybe<&2, SurfaceTypes.Node>) ->
  {Platform.found_focus(found) == Rule.required_product_target(found) : Bool}:
  match found:
    case None{}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, meaning, children}}: focusability_policy(meaning)

def current_lookup_policy(+surface: SurfaceTypes.Surface, +key: String) ->
  {InterfaceView.find_node(InterfaceView.active_nodes(surface), key) == SemanticRules.first_named_node(Rule.required_active_nodes(surface), key) : Maybe<&2, SurfaceTypes.Node>}:
  Equal.trans((Maybe<&2, SurfaceTypes.Node>), InterfaceView.find_node(InterfaceView.active_nodes(surface), key),
    SemanticRules.first_named_node(InterfaceView.active_nodes(surface), key), SemanticRules.first_named_node(Rule.required_active_nodes(surface), key),
    SemanticRules.complete_node_lookup(InterfaceView.active_nodes(surface), key),
    Equal.cong(+List<SurfaceTypes.Node>, (Maybe<&2, SurfaceTypes.Node>), (nodes => SemanticRules.first_named_node(nodes, key)),
      InterfaceView.active_nodes(surface), Rule.required_active_nodes(surface), active_nodes_policy(surface)))

def target_eligibility(+surface: SurfaceTypes.Surface, target: Model.Target) ->
  {Platform.active_target_on(surface, target) == Rule.required_target_eligible(surface, target) : Bool}:
  match target:
    case Model.Product{+identity}:
      Equal.trans(Bool, Platform.active_target_on(surface, Model.Product{identity}),
        Rule.required_product_target(InterfaceView.find_node(InterfaceView.active_nodes(surface), identity)), Rule.required_target_eligible(surface, Model.Product{identity}),
        product_target_policy(InterfaceView.find_node(InterfaceView.active_nodes(surface), identity)),
        Equal.cong((Maybe<&2, SurfaceTypes.Node>), Bool, Rule.required_product_target,
          InterfaceView.find_node(InterfaceView.active_nodes(surface), identity), SemanticRules.first_named_node(Rule.required_active_nodes(surface), identity), current_lookup_policy(surface, identity)))
    case Model.Content{+owner, +identity}:
      Equal.trans(Bool, Platform.active_target_on(surface, Model.Content{owner, identity}),
        Rule.required_content_owner(InterfaceView.find_node(InterfaceView.active_nodes(surface), owner)), Rule.required_target_eligible(surface, Model.Content{owner, identity}),
        content_owner_policy(InterfaceView.find_node(InterfaceView.active_nodes(surface), owner)),
        Equal.cong((Maybe<&2, SurfaceTypes.Node>), Bool, Rule.required_content_owner,
          InterfaceView.find_node(InterfaceView.active_nodes(surface), owner), SemanticRules.first_named_node(Rule.required_active_nodes(surface), owner), current_lookup_policy(surface, owner)))

def temporary_transition_policy(+previous: Model.Scope, +identity: String, +initial: String, +restore: String,
  +occurrence: Maybe<&2, Nat>, +focused: Model.Target, +surface: SurfaceTypes.Surface) ->
  {Platform.focus_transition_on(previous, Model.Temporary{identity, initial, restore, occurrence}, focused, surface) ==
    Rule.required_transition(previous, Model.Temporary{identity, initial, restore, occurrence}, focused, Rule.required_target_eligible(surface, focused)) : Bool}:
  +current: Model.Scope = Model.Temporary{identity, initial, restore, occurrence}
  Equal.trans(Bool, Platform.focus_transition_on(previous, current, focused, surface),
    Rule.required_transition(previous, current, focused, Platform.active_target_on(surface, focused)),
    Rule.required_transition(previous, current, focused, Rule.required_target_eligible(surface, focused)),
    transition_policy(previous, current, focused, Platform.active_target_on(surface, focused)),
    Equal.cong(Bool, Bool, (eligible => Rule.required_transition(previous, current, focused, eligible)),
      Platform.active_target_on(surface, focused), Rule.required_target_eligible(surface, focused), target_eligibility(surface, focused)))

def transition_on_policy(+previous: Model.Scope, +current: Model.Scope, +focused: Model.Target, +surface: SurfaceTypes.Surface) ->
  {Platform.focus_transition_on(previous, current, focused, surface) ==
    Rule.required_transition(previous, current, focused, Rule.required_target_eligible(surface, focused)) : Bool}:
  match previous current focused:
    case Model.Document{} Model.Document{} Model.Product{identity}: {==}
    case Model.Document{} Model.Document{} Model.Content{owner, identity}: {==}
    case Model.Temporary{identity, initial, restore, occurrence} Model.Document{} Model.Product{focused_identity}: {==}
    case Model.Temporary{identity, initial, restore, occurrence} Model.Document{} Model.Content{owner, focused_identity}: {==}
    case Model.Document{} Model.Temporary{identity, initial, restore, occurrence} Model.Product{focused_identity}:
      temporary_transition_policy(Model.Document{}, identity, initial, restore, occurrence, Model.Product{focused_identity}, surface)
    case Model.Document{} Model.Temporary{identity, initial, restore, occurrence} Model.Content{owner, focused_identity}:
      temporary_transition_policy(Model.Document{}, identity, initial, restore, occurrence, Model.Content{owner, focused_identity}, surface)
    case Model.Temporary{old_identity, old_initial, old_restore, old_occurrence} Model.Temporary{identity, initial, restore, occurrence} Model.Product{focused_identity}:
      temporary_transition_policy(Model.Temporary{old_identity, old_initial, old_restore, old_occurrence}, identity, initial, restore, occurrence, Model.Product{focused_identity}, surface)
    case Model.Temporary{old_identity, old_initial, old_restore, old_occurrence} Model.Temporary{identity, initial, restore, occurrence} Model.Content{owner, focused_identity}:
      temporary_transition_policy(Model.Temporary{old_identity, old_initial, old_restore, old_occurrence}, identity, initial, restore, occurrence, Model.Content{owner, focused_identity}, surface)

def effect_block_policy(+transition: Bool, +previous: Model.Scope, +current: Model.Scope, +interaction: +List<E.Effect>, +ticket: Nat,
  +application: E.Application, +readers: +List<Finite.Entry(Reading.Bookmark)>) ->
  {List.append(&2, Platform.Effect, Platform.scope_effects(transition, previous, current, interaction, Platform.focus_revision(transition, interaction, ticket)),
      Platform.layout_for(application, readers)) ==
    List.append(&2, Platform.Effect, Rule.required_scope_effects(transition, previous, current, interaction, Rule.required_focus_ticket(transition, interaction, ticket)),
      Rule.required_layout(application, readers)) : +List<Platform.Effect>}:
  +old_ticket: Nat = Platform.focus_revision(transition, interaction, ticket)
  +new_ticket: Nat = Rule.required_focus_ticket(transition, interaction, ticket)
  Equal.trans(+List<Platform.Effect>,
    List.append(&2, Platform.Effect, Platform.scope_effects(transition, previous, current, interaction, old_ticket), Platform.layout_for(application, readers)),
    List.append(&2, Platform.Effect, Rule.required_scope_effects(transition, previous, current, interaction, old_ticket), Platform.layout_for(application, readers)),
    List.append(&2, Platform.Effect, Rule.required_scope_effects(transition, previous, current, interaction, new_ticket), Rule.required_layout(application, readers)),
    Equal.cong(+List<Platform.Effect>, +List<Platform.Effect>, (effects => List.append(&2, Platform.Effect, effects, Platform.layout_for(application, readers))),
      Platform.scope_effects(transition, previous, current, interaction, old_ticket), Rule.required_scope_effects(transition, previous, current, interaction, old_ticket),
      scope_effect_policy(transition, previous, current, interaction, old_ticket)),
    Equal.trans(+List<Platform.Effect>,
      List.append(&2, Platform.Effect, Rule.required_scope_effects(transition, previous, current, interaction, old_ticket), Platform.layout_for(application, readers)),
      List.append(&2, Platform.Effect, Rule.required_scope_effects(transition, previous, current, interaction, new_ticket), Platform.layout_for(application, readers)),
      List.append(&2, Platform.Effect, Rule.required_scope_effects(transition, previous, current, interaction, new_ticket), Rule.required_layout(application, readers)),
      Equal.cong(Nat, +List<Platform.Effect>, (revision => List.append(&2, Platform.Effect, Rule.required_scope_effects(transition, previous, current, interaction, revision), Platform.layout_for(application, readers))),
        old_ticket, new_ticket, ticket_policy(transition, interaction, ticket)),
      Equal.cong(+List<Platform.Effect>, +List<Platform.Effect>, (effects => List.append(&2, Platform.Effect, Rule.required_scope_effects(transition, previous, current, interaction, new_ticket), effects)),
        Platform.layout_for(application, readers), Rule.required_layout(application, readers), layout_policy(application, readers))))

def after_core_effects(+decision: InteractionTypes.Decision, +platform: Platform.Platform, +current: Model.Scope) ->
  {Rule.effects(Platform.after_core_scoped(decision, platform, current)) == Rule.expected_effects(decision, platform, current) : +List<Platform.Effect>}:
  InteractionTypes.Decision{+core, reply, runtime, +interaction, service, durable} = decision
  Platform.Platform{+readers, editors, +focused, +ticket, reduced, +capacity, +previous} = platform
  +surface: SurfaceTypes.Surface = InterfaceView.observe(capacity, core)
  +transition: Bool = Platform.focus_transition_on(previous, current, focused, surface)
  Equal.trans(+List<Platform.Effect>, Rule.effects(Platform.after_core_scoped(decision, platform, current)),
    Rule.required_commit_effects(decision, platform, current, transition), Rule.expected_effects(decision, platform, current),
    effect_block_policy(transition, previous, current, interaction, ticket, Core.application(core), readers),
    Equal.cong(Bool, +List<Platform.Effect>, (required => Rule.required_commit_effects(decision, platform, current, required)),
      transition, Rule.required_transition(previous, current, focused, Rule.required_target_eligible(surface, focused)),
      transition_on_policy(previous, current, focused, surface)))

def Rule.focus_retention_evidence():
  Rule.FocusRetentionRequirements{{==}, key => semantic => label => role => +meaning => children => unavailable => unavailable, +previous => +identity => +initial => +restore => +occurrence => +ticket => same =>
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
    , explicit_attention_precedes, +decision => platform => +current => after_core_effects(decision, platform, current), +identity => +old_initial => +initial => +restore => +old_occurrence => +occurrence => +focused => +ticket => same => retained => root => changed =>
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

def Rule.content_focus_has_no_root_handoff(previous, current, owner, identity): {==}

def Rule.active_content_uses_owner(core, capacity, owner, identity): {==}

def Rule.retained_content_no_focus_transition(previous, current, owner, identity, same):
  match current:
    case Model.Document{}:
      Equal.cong(Bool, Bool, (changed => (changed || False{}) || False{}),
        Model.changed(previous, Model.Document{}), False{}, same)
    case Model.Temporary{scope_identity, initial, restore, occurrence}:
      Equal.cong(Bool, Bool, (changed => (changed || False{}) || False{}),
        Model.changed(previous, Model.Temporary{scope_identity, initial, restore, occurrence}), False{}, same)

def Rule.content_observation_preserves_core(platform, owner, identity, core):
  match platform:
    case Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope}: {==}

def Rule.active_product_focus_observation(core, platform, identity, active):
  match core platform:
    case InteractionTypes.State{+application, +services} Platform.Platform{readers, editors, focused, ticket, reduced, +capacity, scope}:
      Equal.cong(Bool, Platform.Decision,
        (inside => Platform.realized_decision(Platform.observed_focus(
          Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope}, inside,
          Model.Product{identity}, InteractionTypes.State{application, services}))),
        Platform.active_focus(InteractionTypes.State{application, services}, capacity, identity), True{}, active)

def Rule.available_surface_focus_observation(core, platform, identity, key, semantic, label, role, meaning, children, found, available):
  Rule.active_product_focus_observation(core, platform, identity,
    Equal.trans(Bool,
      Platform.active_focus(core, Platform.capacity(platform), identity),
      Platform.found_focus(Some{SurfaceTypes.Node{key, semantic, label, role, meaning, children}}), True{},
      Equal.cong(Maybe<&2, SurfaceTypes.Node>, Bool, Platform.found_focus,
        InterfaceView.find_node(InterfaceView.active_nodes(InterfaceView.observe(Platform.capacity(platform), core)), identity),
        Some{SurfaceTypes.Node{key, semantic, label, role, meaning, children}}, found), available))

def Rule.activity_dismiss_target(activity, key, semantic, label, role, input, outside, escape, children, rest): {==}
