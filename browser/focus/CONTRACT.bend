import ../../interaction/experience/ACTIVITY.bend as UXActivity
import Base
import ../../interaction/STATE.bend as Core
import ./MODEL.bend as Model
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ../../interaction/presentation/CONTRACT.bend as SemanticRules
import ../../interaction/experience/PROGRAM.bend as UX
import ../../interaction/interactive_markdown/TYPES.bend as IM
import ../../interaction/submission/FIELDS.bend as Forms
import ../../interaction/IDENTITY.bend as Identity
import ../../interaction/INPUT.bend as U
import ../../interaction/session/MODEL.bend as E
import ../../interaction/presentation/MODEL.bend as View
import ../../interaction/services/MODEL.bend as Services
import ../../interaction/TYPES.bend as InteractionTypes
import ../../interaction/presentation/SURFACE.bend as SurfaceTypes
import ../../interaction/presentation/VIEW.bend as View2
import ../runtime/PLATFORM.bend as Platform
import ../../interaction/MODEL.bend as Product
import ../../harness/DOMAIN.bend as D
import ../../bendlib/json.bend as J
import ../runtime/SEMANTICS.bend as Browser
import ../controls/PROGRAM.bend as Controls
import ../reading/MODEL.bend as Reading
import ../../bendlib/association-map.bend as Finite

def expected_same_target(first: Model.Target, second: Model.Target) -> Bool:
  match first second:
    case Model.Product{first} Model.Product{second}: String.eq(first, second)
    case Model.Content{first_owner, first} Model.Content{second_owner, second}:
      String.eq(first_owner, second_owner) && String.eq(first, second)
    case _ _: False{}

law same_target_exact:
  for +first: Model.Target
  for +second: Model.Target
  {Model.same_target(first, second) == expected_same_target(first, second) : Bool}

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
  for +content: InteractionTypes.Scene
  for +base: +List<SurfaceTypes.Node>
  for +overlays: +List<SurfaceTypes.Node>
  for +active: String
  for +scope: Model.Scope
  for +key: Identity.Key
  for found: {InterfaceView.all_focus_target(SurfaceTypes.Surface{content, base, overlays, Some{active}}, Model.restore(scope)) == Some{Identity.encode(key)} : Maybe<&2, String>}
  {Model.restore(Model.realized_scope(SurfaceTypes.Surface{content, base, overlays, Some{active}}, scope)) == Identity.encode(key) : String}

law settings_restore:
  for +content: InteractionTypes.Scene
  for +base: +List<SurfaceTypes.Node>
  for +overlays: +List<SurfaceTypes.Node>
  for +active: String
  for fallback: Model.Scope
  {Model.restore(Model.realized_scope(SurfaceTypes.Surface{content, base, overlays, Some{active}}, Model.settings_scope(True{}, fallback))) == Model.resolved_target(InterfaceView.all_focus_target(SurfaceTypes.Surface{content, base, overlays, Some{active}}, "settings/open")) : String}

law settings_resolved_restore:
  for +content: InteractionTypes.Scene
  for +base: +List<SurfaceTypes.Node>
  for +overlays: +List<SurfaceTypes.Node>
  for +active: String
  for fallback: Model.Scope
  for +key: Identity.Key
  for found: {InterfaceView.all_focus_target(SurfaceTypes.Surface{content, base, overlays, Some{active}}, "settings/open") == Some{Identity.encode(key)} : Maybe<&2, String>}
  {Model.restore(Model.realized_scope(SurfaceTypes.Surface{content, base, overlays, Some{active}}, Model.settings_scope(True{}, fallback))) == Identity.encode(key) : String}

law responsive_settings_restore_targets:
  {Model.settings_restore_target(True{}) == "settings/open" : String} &
  {Model.settings_restore_target(False{}) == "global/menu" : String}

law responsive_settings_restore:
  @+content:InteractionTypes.Scene -> @+base:+List<SurfaceTypes.Node> -> @+overlays:+List<SurfaceTypes.Node> -> @+active:String -> @+navigation_beside:Bool -> @fallback:Model.Scope ->
  {Model.restore(Model.realized_scope(SurfaceTypes.Surface{content, base, overlays, Some{active}}, Model.settings_scope_restore(True{}, navigation_beside, fallback))) ==
    Model.resolved_target(InterfaceView.all_focus_target(SurfaceTypes.Surface{content, base, overlays, Some{active}}, Model.settings_restore_target(navigation_beside))) : String}

law responsive_settings_resolved_restore:
  @+content:InteractionTypes.Scene -> @+base:+List<SurfaceTypes.Node> -> @+overlays:+List<SurfaceTypes.Node> -> @+active:String -> @+navigation_beside:Bool -> @fallback:Model.Scope -> @+key:Identity.Key ->
  @found:{InterfaceView.all_focus_target(SurfaceTypes.Surface{content, base, overlays, Some{active}}, Model.settings_restore_target(navigation_beside)) == Some{Identity.encode(key)} : Maybe<&2, String>} ->
  {Model.restore(Model.realized_scope(SurfaceTypes.Surface{content, base, overlays, Some{active}}, Model.settings_scope_restore(True{}, navigation_beside, fallback))) == Identity.encode(key) : String}

law document_restores_previous:
  for +previous: Model.Scope
  for surface: SurfaceTypes.Surface
  {Model.scope_target(previous, Model.Document{}, surface) == Model.restore(previous) : String}

law document_opens_temporary:
  for identity: String
  for +initial: String
  for restore: String
  for occurrence: Maybe<&2, Nat>
  for surface: SurfaceTypes.Surface
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
  for +surface: SurfaceTypes.Surface
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
  for +surface: SurfaceTypes.Surface
  for absent: {InterfaceView.matching_focus(InterfaceView.active_nodes(surface), trigger) == None{} : Maybe<&2, String>}
  {Model.scope_target(Model.Temporary{old_identity, old_initial, trigger, old_occurrence}, Model.Temporary{identity, initial, restore, occurrence}, surface) == initial : String}

law panel_policy:
  for +panel: U.Panel
  for initial: String
  for +trigger: String
  for beside: Bool
  {Model.panel_scope(panel, initial, trigger, beside) == Model.dismissal_scope(View2.layer_dismissal(panel, trigger), E.panel_target(panel), initial, trigger, beside) : Model.Scope}

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
    case True{}: {actual == Model.Temporary{"settings", "settings/connect", "settings/open", None{}} : Model.Scope}

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

def responsive_settings_classification(open: Bool, navigation_beside: Bool, fallback: Model.Scope, actual: Model.Scope) -> Type:
  match open navigation_beside:
    case False{} _: {actual == fallback : Model.Scope}
    case True{} True{}: {actual == Model.Temporary{"settings", "settings/connect", "settings/open", None{}} : Model.Scope}
    case True{} False{}: {actual == Model.Temporary{"settings", "settings/connect", "global/menu", None{}} : Model.Scope}

law responsive_settings_policy:
  @+open:Bool -> @+navigation_beside:Bool -> @+fallback:Model.Scope ->
  responsive_settings_classification(open, navigation_beside, fallback, Model.settings_scope_restore(open, navigation_beside, fallback))

law desktop_settings_policy_unchanged:
  @+open:Bool -> @+fallback:Model.Scope ->
  {Model.settings_scope_restore(open, True{}, fallback) == Model.settings_scope(open, fallback) : Model.Scope}

law preview_policy:
  for +preview: Services.Preview
  for +fallback: Model.Scope
  preview_classification(preview, fallback, Model.preview_scope(preview, fallback))

law directory_policy:
  for +picker: Services.DirectoryPicker
  for +fallback: Model.Scope
  directory_classification(picker, fallback, Model.directory_scope(picker, fallback))

law realized_document:
  for content: InteractionTypes.Scene
  for base: +List<SurfaceTypes.Node>
  for overlays: +List<SurfaceTypes.Node>
  for scope: Model.Scope
  {Model.realized_scope(SurfaceTypes.Surface{content, base, overlays, None{}}, scope) == Model.Document{} : Model.Scope}

law realized_active:
  for +content: InteractionTypes.Scene
  for +base: +List<SurfaceTypes.Node>
  for +overlays: +List<SurfaceTypes.Node>
  for +active: String
  for +scope: Model.Scope
  {Model.realized_scope(SurfaceTypes.Surface{content, base, overlays, Some{active}}, scope) ==
    Model.Temporary{active, Model.resolved_target(InterfaceView.focus_target(SurfaceTypes.Surface{content, base, overlays, Some{active}}, Model.initial(scope))),
      Model.resolved_target(InterfaceView.all_focus_target(SurfaceTypes.Surface{content, base, overlays, Some{active}}, Model.restore(scope))), Model.scope_occurrence_of(scope)} : Model.Scope}

law current_scope:
  for +state: InteractionTypes.State
  for +capacity: View.Capacity
  {Model.current(state, capacity) == Model.realized_scope(InterfaceView.observe(capacity, state), Model.logical_scope(state, capacity)) : Model.Scope}

def logical_classification(+state: InteractionTypes.State, capacity: View.Capacity, actual: Model.Scope) -> Type:
  View.Capacity{navigation_beside, details_beside} = capacity
  +observed_application_1 = Core.application(state)
  +observed_session_2 = E.session(observed_application_1)
  +layers = E.layers(observed_session_2)
  +observed_services_3 = Core.services(state)
  +settings = Services.settings_open(observed_services_3)
  +preview = Services.preview(observed_services_3)
  +directory_picker = Services.directory_picker(observed_services_3)
  {actual == Model.preview_scope(preview, Model.directory_scope(directory_picker, Model.settings_scope_restore(settings, navigation_beside, Model.layer_scope(layers, details_beside)))) : Model.Scope}

law logical_priority:
  for +state: InteractionTypes.State
  for +capacity: View.Capacity
  logical_classification(state, capacity, Model.logical_scope(state, capacity))

law current_surface:
  for +state: InteractionTypes.State
  for +capacity: View.Capacity
  for +surface: SurfaceTypes.Surface
  for observed: {InterfaceView.observe(capacity, state) == surface : SurfaceTypes.Surface}
  {Model.current(state, capacity) == Model.realized_scope(surface, Model.logical_scope(state, capacity)) : Model.Scope}

def effects(value: Platform.Decision) -> +List<Platform.Effect>:
  Platform.Decision{product, platform, effects} = value
  effects

def required_scope_nodes(found: Maybe<&2, SurfaceTypes.Node>) -> +List<SurfaceTypes.Node>:
  match found:
    case None{}: Nil{}
    case Some{node}: [node]

def required_active_nodes(surface: SurfaceTypes.Surface) -> +List<SurfaceTypes.Node>:
  SurfaceTypes.Surface{content, base, overlays, scope} = surface
  match scope:
    case None{}: List.append(&2, SurfaceTypes.Node, base, overlays)
    case Some{key}: required_scope_nodes(SemanticRules.first_named_node(overlays, key))

def required_available(availability: View.Availability) -> Bool:
  match availability:
    case View.Available{}: True{}
    case View.NeedsDirectoryObservation{}: True{}
    case View.Unavailable{reason}: False{}

def required_focusable(meaning: SurfaceTypes.Meaning) -> Bool:
  match meaning:
    case SurfaceTypes.InteractiveNode{IM.ExpandedNode{identity, occurrence, tag, attrs, IM.FieldBinding{state_id, schema, raw, canonical, validation, enabled}, children}}: enabled
    case SurfaceTypes.InteractiveNode{IM.ExpandedNode{identity, occurrence, tag, attrs, IM.ActionBinding{kind, enabled, pending}, children}}: enabled && Bool.not(pending)
    case SurfaceTypes.InteractiveView{event, command, label, enabled}: enabled
    case SurfaceTypes.ActionCommit{assessment, input, availability}: UX.assessment_ready(assessment) && required_available(availability)
    case SurfaceTypes.SupportingControl{support, property, input, availability}: UX.support_visible(support) && required_available(availability)
    case SurfaceTypes.SettingEntry{subject, value, input, availability}: required_available(availability)
    case SurfaceTypes.Activate{input, availability}: required_available(availability)
    case SurfaceTypes.PanelToggle{expanded, input, availability}: required_available(availability)
    case SurfaceTypes.LayerRegion{dismiss, outside, escape}: True{}
    case SurfaceTypes.Choice{kind, classification, selected, description, input, availability}: required_available(availability)
    case SurfaceTypes.Edit{editor, field, Forms.DisplayOnly{}, value, choices}: False{}
    case SurfaceTypes.Edit{editor, field, Forms.FileCollection{}, value, choices}: False{}
    case SurfaceTypes.Edit{editor, field, Forms.DirectoryCollection{}, value, choices}: False{}
    case SurfaceTypes.Edit{editor, field, entry, value, choices}: True{}
    case SurfaceTypes.SearchChoices{query}: True{}
    case SurfaceTypes.BoardSearch{filter}: True{}
    case SurfaceTypes.ReceiveFile{editor, enabled}: enabled
    case SurfaceTypes.EnterDirectory{editor, text}: True{}
    case SurfaceTypes.DirectoryBrowserLocation{value}: True{}
    case SurfaceTypes.BoardProfile{automatic, selected, choices, enabled}: enabled
    case _: False{}

def required_product_target(found: Maybe<&2, SurfaceTypes.Node>) -> Bool:
  match found:
    case None{}: False{}
    case Some{SurfaceTypes.Node{key, semantic, label, role, meaning, children}}: required_focusable(meaning)

def required_content_owner(found: Maybe<&2, SurfaceTypes.Node>) -> Bool:
  match found:
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.InteractiveNode{IM.ExpandedNode{identity, occurrence, tag, attrs, binding, original}}, children}}: String.eq(tag, "markdown")
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ReadOnly{text}, children}}: True{}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.InformationText{information_role}, children}}: True{}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.RichText{source, value}, children}}: True{}
    case _: False{}

def required_target_eligible(+surface: SurfaceTypes.Surface, target: Model.Target) -> Bool:
  match target:
    case Model.Product{identity}: required_product_target(SemanticRules.first_named_node(required_active_nodes(surface), identity))
    case Model.Content{owner, identity}: required_content_owner(SemanticRules.first_named_node(required_active_nodes(surface), owner))

def required_same_occurrence(previous: Maybe<&2, Nat>, current: Maybe<&2, Nat>) -> Bool:
  match previous current:
    case None{} None{}: True{}
    case Some{before} Some{after}: Nat.is_eq(before, after)
    case _ _: False{}

# A loading dialog hands its root focus to the new initial input only if the
# user has not moved elsewhere. Content focus never requests this handoff.
def required_root_transfer(previous: Model.Scope, current: Model.Scope, target: Model.Target) -> Bool:
  match previous current target:
    case Model.Temporary{+old_owner, +old_initial, old_restore, old_occurrence}
      Model.Temporary{new_owner, initial, restore, occurrence} Model.Product{focused}:
      Bool.pick(Bool, String.eq(focused, old_initial),
        (String.eq(old_owner, new_owner) && String.eq(old_initial, old_owner)) && Bool.not(String.eq(old_initial, initial)), False{})
    case _ _ _: False{}

def required_transition(previous: Model.Scope, +current: Model.Scope, +target: Model.Target, eligible: Bool) -> Bool:
  match previous current:
    case Model.Document{} Model.Document{}: False{}
    case Model.Document{} Model.Temporary{identity, initial, restore, occurrence}: True{}
    case Model.Temporary{identity, initial, restore, occurrence} Model.Document{}: True{}
    case Model.Temporary{+old_owner, +old_initial, +old_restore, +old_occurrence} Model.Temporary{+owner, +initial, +restore, +occurrence}:
      (Bool.not(String.eq(old_owner, owner) && required_same_occurrence(old_occurrence, occurrence)) || Bool.not(eligible)) ||
        required_root_transfer(Model.Temporary{old_owner, old_initial, old_restore, old_occurrence}, Model.Temporary{owner, initial, restore, occurrence}, target)

def required_explicit_focus(effects: +List<E.Effect>) -> Bool:
  match effects:
    case Nil{}: False{}
    case Con{E.Attend{target}, rest}: True{}
    case Con{other, rest}: required_explicit_focus(rest)

def required_focus_ticket(transition: Bool, effects: +List<E.Effect>, +ticket: Nat) -> Nat:
  Bool.pick(Nat, transition || required_explicit_focus(effects), (ticket + 1n : Nat), ticket)

def required_explicit_effects(effects: +List<E.Effect>, +ticket: Nat) -> +List<Platform.Effect>:
  match effects:
    case Nil{}: Nil{}
    case Con{E.Attend{target}, rest}: Platform.Focus{ticket, Model.Product{target}} <> required_explicit_effects(rest, ticket)
    case Con{E.ContentEffect{identity, effect}, rest}: Platform.Clipboard{identity, effect} <> required_explicit_effects(rest, ticket)
    case Con{other, rest}: required_explicit_effects(rest, ticket)

def required_content_effects(effects: +List<E.Effect>) -> +List<Platform.Effect>:
  match effects:
    case Nil{}: Nil{}
    case Con{E.ContentEffect{identity, effect}, rest}: Platform.Clipboard{identity, effect} <> required_content_effects(rest)
    case Con{other, rest}: required_content_effects(rest)

def required_scope_effects(transition: Bool, previous: Model.Scope, current: Model.Scope,
  +effects: +List<E.Effect>, +ticket: Nat) -> +List<Platform.Effect>:
  match transition:
    case False{}: required_explicit_effects(effects, ticket)
    case True{}:
      Bool.pick((+List<Platform.Effect>), required_explicit_focus(effects), required_explicit_effects(effects, ticket),
        Platform.ScopeFocus{ticket, previous, current} <> required_content_effects(effects))

def required_bookmark(found: Maybe<&2, Reading.Bookmark>) -> Reading.Bookmark:
  match found:
    case None{}: Reading.Bookmark{None{}}
    case Some{bookmark}: bookmark

def required_reading_effects(effects: +List<Reading.Effect>, +task: Nat, +generation: Nat) -> +List<Platform.Effect>:
  match effects:
    case Nil{}: Nil{}
    case Con{effect, rest}: Platform.ApplyReading{task, generation, effect} <> required_reading_effects(rest, task, generation)

def required_route_layout(route: U.Route, +readers: +List<Finite.Entry(E.Reader)>, bookmarks: +List<Finite.Entry(Reading.Bookmark)>) -> +List<Platform.Effect>:
  match route:
    case U.Conversation{+task}:
      required_reading_effects(Reading.layout(E.reader_position(E.reader(readers, task)),
        required_bookmark(Finite.find(~Reading.Bookmark, bookmarks, task))), task, E.reader_generation(E.reader(readers, task)))
    case _: Nil{}

def required_layout(application: E.Application, bookmarks: +List<Finite.Entry(Reading.Bookmark)>) -> +List<Platform.Effect>:
  +session = E.session(application)
  required_route_layout(E.route(session), E.readers(session), bookmarks)

def required_commit_effects(decision: InteractionTypes.Decision, +platform: Platform.Platform, +current: Model.Scope, +transition: Bool) -> +List<Platform.Effect>:
  InteractionTypes.Decision{+core, reply, runtime, +interaction, service, durable} = decision
  Platform.Platform{+readers, editors, focused, +ticket, reduced, capacity, +previous} = platform
  List.append(&2, Platform.Effect, required_scope_effects(transition, previous, current, interaction,
    required_focus_ticket(transition, interaction, ticket)), required_layout(Core.application(core), readers))

def expected_effects(+decision: InteractionTypes.Decision, +platform: Platform.Platform, +current: Model.Scope) -> +List<Platform.Effect>:
  InteractionTypes.Decision{+core, reply, runtime, interaction, service, durable} = decision
  Platform.Platform{readers, editors, +focused, ticket, reduced, +capacity, +previous} = platform
  required_commit_effects(decision, platform, current,
    required_transition(previous, current, focused, required_target_eligible(InterfaceView.observe(capacity, core), focused)))

type FocusRetentionRequirements is Type:
  FocusRetentionRequirements{
    absent_not_accepted: {Platform.found_focus(None{}) == False{} : Bool},
    nonfocusable_not_accepted: @key: Identity.Key -> @semantic: String -> @label: String -> @role: SurfaceTypes.Role -> @+meaning: SurfaceTypes.Meaning -> @children: +List<SurfaceTypes.Node> -> @unavailable: {InterfaceView.focusable(meaning) == False{} : Bool} -> {Platform.found_focus(Some{SurfaceTypes.Node{key, semantic, label, role, meaning, children}}) == False{} : Bool},
    invalid_focus_requests_initial: @+previous: Model.Scope -> @+identity: String -> @+initial: String -> @+restore: String -> @+occurrence:Maybe<&2, Nat> -> @+ticket: Nat -> @same: {Model.changed(previous, Model.Temporary{identity, initial, restore, occurrence}) == False{} : Bool} -> {Platform.scope_effects(Model.transition(previous, Model.Temporary{identity, initial, restore, occurrence}, False{}), previous,
          Model.Temporary{identity, initial, restore, occurrence}, Nil{}, Platform.focus_revision(Model.transition(previous,
            Model.Temporary{identity, initial, restore, occurrence}, False{}), Nil{}, ticket)) ==
          [Platform.ScopeFocus{(ticket + 1n : Nat), previous, Model.Temporary{identity, initial, restore, occurrence}}] : +List<Platform.Effect>},
    valid_focus_no_request: @+previous: Model.Scope -> @+identity: String -> @+initial: String -> @+restore: String -> @+occurrence:Maybe<&2, Nat> -> @+ticket: Nat -> @same: {Model.changed(previous, Model.Temporary{identity, initial, restore, occurrence}) == False{} : Bool} -> {Platform.scope_effects(Model.transition(previous, Model.Temporary{identity, initial, restore, occurrence}, True{}), previous,
          Model.Temporary{identity, initial, restore, occurrence}, Nil{}, Platform.focus_revision(Model.transition(previous,
            Model.Temporary{identity, initial, restore, occurrence}, True{}), Nil{}, ticket)) == Nil{} : +List<Platform.Effect>},
    document_no_request: @+previous: Model.Scope -> @+eligible: Bool -> @+ticket: Nat -> @same: {Model.changed(previous, Model.Document{}) == False{} : Bool} -> {Platform.scope_effects(Model.transition(previous, Model.Document{}, eligible), previous, Model.Document{}, Nil{},
    Platform.focus_revision(Model.transition(previous, Model.Document{}, eligible), Nil{}, ticket)) == Nil{} : +List<Platform.Effect>},
    explicit_attention_precedes: @+trigger: Bool -> @previous: Model.Scope -> @current: Model.Scope -> @+target: String -> @+ticket: Nat -> {Platform.scope_effects(trigger, previous, current, [E.Attend{target}],
    Platform.focus_revision(trigger, [E.Attend{target}], ticket)) == [Platform.Focus{(ticket + 1n : Nat), Model.Product{target}}] : +List<Platform.Effect>},
    after_core_effects: @+decision: InteractionTypes.Decision -> @platform: Platform.Platform -> @+current: Model.Scope -> {effects(Platform.after_core_scoped(decision, platform, current)) ==
    expected_effects(decision, platform, current) : +List<Platform.Effect>},
    root_handoff_requests_initial: @+identity: String -> @+old_initial: String -> @+initial: String -> @+restore: String -> @+old_occurrence:Maybe<&2, Nat> -> @+occurrence:Maybe<&2, Nat> -> @+focused: String -> @+ticket: Nat -> @same: {Model.changed(Model.Temporary{identity, old_initial, restore, old_occurrence}, Model.Temporary{identity, initial, restore, occurrence}) == False{} : Bool} -> @retained: {String.eq(focused, old_initial) == True{} : Bool} -> @root: {String.eq(identity, identity) && String.eq(old_initial, identity) == True{} : Bool} -> @changed: {Bool.not(String.eq(old_initial, initial)) == True{} : Bool} ->   {Platform.scope_effects(Platform.focus_transition(Model.Temporary{identity, old_initial, restore, old_occurrence}, Model.Temporary{identity, initial, restore, occurrence}, Model.Product{focused}, True{}),
          Model.Temporary{identity, old_initial, restore, old_occurrence}, Model.Temporary{identity, initial, restore, occurrence}, Nil{},
          Platform.focus_revision(Platform.focus_transition(Model.Temporary{identity, old_initial, restore, old_occurrence}, Model.Temporary{identity, initial, restore, occurrence}, Model.Product{focused}, True{}), Nil{}, ticket)) ==
          [Platform.ScopeFocus{(ticket + 1n : Nat), Model.Temporary{identity, old_initial, restore, old_occurrence}, Model.Temporary{identity, initial, restore, occurrence}}] : +List<Platform.Effect>},
    moved_focus_no_handoff: @+identity: String -> @+old_initial: String -> @+initial: String -> @+restore: String -> @+old_occurrence:Maybe<&2, Nat> -> @+occurrence:Maybe<&2, Nat> -> @+focused: String -> @+ticket: Nat -> @same: {Model.changed(Model.Temporary{identity, old_initial, restore, old_occurrence}, Model.Temporary{identity, initial, restore, occurrence}) == False{} : Bool} -> @moved: {String.eq(focused, old_initial) == False{} : Bool} ->   {Platform.scope_effects(Platform.focus_transition(Model.Temporary{identity, old_initial, restore, old_occurrence}, Model.Temporary{identity, initial, restore, occurrence}, Model.Product{focused}, True{}),
          Model.Temporary{identity, old_initial, restore, old_occurrence}, Model.Temporary{identity, initial, restore, occurrence}, Nil{},
          Platform.focus_revision(Platform.focus_transition(Model.Temporary{identity, old_initial, restore, old_occurrence}, Model.Temporary{identity, initial, restore, occurrence}, Model.Product{focused}, True{}), Nil{}, ticket)) == Nil{} : +List<Platform.Effect>}}

law focus_retention_evidence:
  FocusRetentionRequirements

law content_focus_has_no_root_handoff:
  for previous: Model.Scope
  for current: Model.Scope
  for owner: String
  for identity: String
  {Platform.scope_handoff(previous, current, Model.Content{owner, identity}) == False{} : Bool}

law active_content_uses_owner:
  for core: InteractionTypes.State
  for capacity: View.Capacity
  for owner: String
  for identity: String
  {Platform.active_target(core, capacity, Model.Content{owner, identity}) == Platform.active_content_owner(core, capacity, owner) : Bool}

law retained_content_no_focus_transition:
  for +previous: Model.Scope
  for +current: Model.Scope
  for owner: String
  for identity: String
  for same: {Model.changed(previous, current) == False{} : Bool}
  {Platform.focus_transition(previous, current, Model.Content{owner, identity}, True{}) == False{} : Bool}

law content_observation_preserves_core:
  for +platform: Platform.Platform
  for owner: String
  for identity: String
  for +core: InteractionTypes.State
  {Platform.decision_product(Platform.observed_focus(platform, True{}, Model.Content{owner, identity}, core)) == Platform.unchanged(core) : InteractionTypes.Decision}

def expected_product_focus_observation(+core: InteractionTypes.State, platform: Platform.Platform, identity: String) -> Platform.Decision:
  Platform.Platform{readers, editors, focused, ticket, reduced, capacity, scope} = platform
  Platform.Decision{Platform.unchanged(core),
    Platform.Platform{readers, editors, Model.Product{identity}, (ticket + 1n : Nat), reduced, capacity, scope}, Nil{}}

law active_product_focus_observation:
  for +core: InteractionTypes.State
  for +platform: Platform.Platform
  for +identity: String
  for active: {Platform.active_focus(core, Platform.capacity(platform), identity) == True{} : Bool}
  {Platform.step(Platform.FocusObserved{identity}, Platform.State{core, platform}) ==
    expected_product_focus_observation(core, platform, identity) : Platform.Decision}

law available_surface_focus_observation:
  for +core: InteractionTypes.State
  for +platform: Platform.Platform
  for +identity: String
  for +key: Identity.Key
  for +semantic: String
  for +label: String
  for +role: SurfaceTypes.Role
  for +meaning: SurfaceTypes.Meaning
  for +children: +List<SurfaceTypes.Node>
  for found: {InterfaceView.find_node(InterfaceView.active_nodes(InterfaceView.observe(Platform.capacity(platform), core)), identity) ==
    Some{SurfaceTypes.Node{key, semantic, label, role, meaning, children}} : Maybe<&2, SurfaceTypes.Node>}
  for available: {InterfaceView.focusable(meaning) == True{} : Bool}
  {Platform.step(Platform.FocusObserved{identity}, Platform.State{core, platform}) ==
    expected_product_focus_observation(core, platform, identity) : Platform.Decision}

def application_layers(+application: E.Application) -> +List<E.Layer>:
  +observed_session_1 = E.session(application)
  +layers = E.layers(observed_session_1)
  +attention = E.attention(observed_session_1)
  layers

# The complete result fixes all unaffected state and the ordered attention effect.

def closed_application(+application: E.Application, panel: U.Panel, +trigger: String) -> E.Decision:
  +session = E.session(application)
  +layers = E.layers(session)
  E.Decision{E.with_session(E.with_attention(trigger,
    E.with_layers(E.without_panel(layers, E.panel_target(panel)), session)), application),
    D.success(J.Null{}), Nil{}, [E.Attend{trigger}], False{}}

type DismissalRequirements is Type:
  DismissalRequirements{
    toggle_absent: @+application:E.Application -> @+panel:U.Panel -> @+trigger:String ->
      @absent:{E.panel_present(application_layers(application), E.panel_target(panel)) == False{} : Bool} ->
      {E.toggle_panel(panel, trigger, application) == E.open_panel(panel, trigger, application) : E.Decision},
    toggle_present: @+application:E.Application -> @+panel:U.Panel -> @+trigger:String ->
      @present:{E.panel_present(application_layers(application), E.panel_target(panel)) == True{} : Bool} ->
      {E.toggle_panel(panel, trigger, application) == closed_application(application, panel, trigger) : E.Decision},
    details_policy: @task:Nat -> @trigger:String -> {View2.layer_dismissal(U.TaskDetails{task}, trigger) == View.ByTrigger{U.TogglePanel{U.TaskDetails{task}, trigger}} : View.Dismissal},
    persistent_policy: @action:U.Action -> {InterfaceView.dismissal_meaning(View.ByTrigger{action}) == SurfaceTypes.LayerRegion{InteractionTypes.ApplicationInput{E.UserInput{U.Activate{action}}}, False{}, False{}} : SurfaceTypes.Meaning},
    transient_policy: @action:U.Action -> {InterfaceView.dismissal_meaning(View.OutsideOrEscape{action}) == SurfaceTypes.LayerRegion{InteractionTypes.ApplicationInput{E.UserInput{U.Activate{action}}}, True{}, True{}} : SurfaceTypes.Meaning},
    layer_children: @+kind:View.LayerKind -> @+content:View.LayerContent -> @+initial:String -> @restore:String -> @dismissal:View.Dismissal -> @+state:InteractionTypes.State ->
      {InterfaceView.layers([View.Layer{kind, content, initial, restore, dismissal}], state) ==
          [SurfaceTypes.Node{InterfaceView.layer_key(initial), initial, InterfaceView.activity_layer_label(InterfaceView.layer_activity(content, state), View2.layer_title(content), state), InterfaceView.layer_role(kind), InterfaceView.layer_meaning(InterfaceView.layer_activity(content, state), dismissal),
            InterfaceView.layer_content(content, InterfaceView.layer_key(initial), state)}] : +List<SurfaceTypes.Node>},
    observed_policy: @+key:Identity.Key -> @semantic:String -> @label:String -> @role:SurfaceTypes.Role -> @+input:InteractionTypes.Input -> @+outside:Bool -> @+escape:Bool -> @children:+List<SurfaceTypes.Node> -> @rest:+List<SurfaceTypes.Node> ->
      {Browser.dismiss_target(SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.LayerRegion{input, outside, escape}, children} <> rest) == Some{Browser.DismissTarget{Identity.encode(key), input, outside, escape}} : Maybe<&2, Browser.DismissTarget>},
    outside_absent: @+identity:String -> @+state:Browser.State -> {Browser.outside_target(identity, None{}, Browser.current_layer_key(state), state) == Browser.OutsideDecision{False{}, Browser.Decision{state, Nil{}}} : Browser.OutsideDecision},
    outside_persistent: @+identity:String -> @+key:String -> @input:InteractionTypes.Input -> @escape:Bool -> @+state:Browser.State -> {Browser.outside_target(identity, Some{Browser.DismissTarget{key, input, False{}, escape}}, Browser.current_layer_key(state), state) == Browser.OutsideDecision{False{}, Browser.Decision{state, Nil{}}} : Browser.OutsideDecision},
    outside_stale: @+identity:String -> @+key:String -> @+input:InteractionTypes.Input -> @+outside:Bool -> @escape:Bool -> @+state:Browser.State -> @stale:{String.eq(identity, key) == False{} : Bool} ->
      {Browser.outside_target(identity, Some{Browser.DismissTarget{key, input, outside, escape}}, Browser.current_layer_key(state), state) == Browser.OutsideDecision{False{}, Browser.Decision{state, Nil{}}} : Browser.OutsideDecision},
    escape_persistent: @key:String -> @input:InteractionTypes.Input -> @outside:Bool -> @+state:Browser.State -> {Browser.escape_target(Some{Browser.DismissTarget{key, input, outside, False{}}}, state) == Browser.Decision{state, Nil{}} : Browser.Decision},
    escape_dispatch: @key:String -> @+input:InteractionTypes.Input -> @outside:Bool -> @+state:Browser.State -> {Browser.escape_target(Some{Browser.DismissTarget{key, input, outside, True{}}}, state) == Browser.product_input(Product.InterfaceInput{input}, state) : Browser.Decision},
    outside_dispatch: @+identity:String -> @+key:String -> @+input:InteractionTypes.Input -> @escape:Bool -> @+state:Browser.State -> @owned:{String.eq(identity, key) == True{} : Bool} ->
      {Browser.outside_target(identity, Some{Browser.DismissTarget{key, input, True{}, escape}}, Browser.current_layer_key(state), state) == Browser.outside_permitted(Browser.outside_layer_owned(identity, Browser.current_layer_key(state)), input, state) : Browser.OutsideDecision},
    outside_production: @+identity:String -> @+state:Browser.State -> {Browser.outside_event(identity, state) == Browser.outside_target(identity, Browser.dismiss_target(Browser.nodes(state)), Browser.current_layer_key(state), state) : Browser.OutsideDecision},
    outside_policy: @+identity:String -> @+key:String -> @+input:InteractionTypes.Input -> @+outside:Bool -> @escape:Bool -> @+state:Browser.State -> {Browser.outside_target(identity, Some{Browser.DismissTarget{key, input, outside, escape}}, Browser.current_layer_key(state), state) == Browser.outside_permitted((String.eq(identity, key) && outside) && Browser.outside_layer_owned(identity, Browser.current_layer_key(state)), input, state) : Browser.OutsideDecision},
    outside_document: @input:InteractionTypes.Input -> @+state:Browser.State -> {Browser.outside_scoped(Model.Document{}, input, state) == Browser.OutsideDecision{False{}, Browser.Decision{state, Nil{}}} : Browser.OutsideDecision},
    outside_temporary: @+identity:String -> @initial:String -> @restore:String -> @occurrence:Maybe<&2, Nat> -> @+input:InteractionTypes.Input -> @+state:Browser.State -> {Browser.outside_scoped(Model.Temporary{identity, initial, restore, occurrence}, input, state) == Browser.outside_transition(identity, Browser.product_input(Product.InterfaceInput{input}, state), state) : Browser.OutsideDecision},
    outside_transition_dispatch: @+identity:String -> @+candidate:Browser.Decision -> @+state:Browser.State -> @closed:{Browser.outside_closed(identity, candidate) == True{} : Bool} -> {Browser.outside_transition(identity, candidate, state) == Browser.OutsideDecision{True{}, candidate} : Browser.OutsideDecision},
    outside_transition_refusal: @+identity:String -> @+candidate:Browser.Decision -> @+state:Browser.State -> @retained:{Browser.outside_closed(identity, candidate) == False{} : Bool} -> {Browser.outside_transition(identity, candidate, state) == Browser.OutsideDecision{False{}, Browser.Decision{state, Nil{}}} : Browser.OutsideDecision},
    outside_completed_dispatch: @+candidate:Browser.Decision -> @state:Browser.State -> {Browser.outside_completed(True{}, candidate, state) == Browser.OutsideDecision{True{}, candidate} : Browser.OutsideDecision},
    outside_completed_refusal: @candidate:Browser.Decision -> @+state:Browser.State -> {Browser.outside_completed(False{}, candidate, state) == Browser.OutsideDecision{False{}, Browser.Decision{state, Nil{}}} : Browser.OutsideDecision},
    collapsed_navigation: {Controls.navigation_icon(False{}) == Controls.Sidebar{} : Controls.Icon},
    expanded_navigation: {Controls.navigation_icon(True{}) == Controls.SidebarClose{} : Controls.Icon},
    collapsed_details: {Controls.inspector_icon(False{}) == Controls.Inspector{} : Controls.Icon},
    expanded_details: {Controls.inspector_icon(True{}) == Controls.InspectorClose{} : Controls.Icon}}

law dismissal_evidence:
  DismissalRequirements

def dismissal_panel_policy(panel: U.Panel, trigger: String, dismissal: View.Dismissal) -> Type:
  match panel:
    case U.TaskDetails{task}: {dismissal == View.ByTrigger{U.TogglePanel{U.TaskDetails{task}, trigger}} : View.Dismissal}
    case _: {dismissal == View.OutsideOrEscape{U.ClosePanel{}} : View.Dismissal}

law all_panel_policies:
  for +panel: U.Panel
  for +trigger: String
  dismissal_panel_policy(panel, trigger, View2.layer_dismissal(panel, trigger))

law activity_dismiss_target:
  @activity:UXActivity.Activity -> @+key:Identity.Key -> @semantic:String -> @label:String -> @role:SurfaceTypes.Role -> @+input:InteractionTypes.Input -> @+outside:Bool -> @+escape:Bool -> @children:+List<SurfaceTypes.Node> -> @rest:+List<SurfaceTypes.Node> ->
    {Browser.dismiss_target(SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ActivityGroup{activity, input, outside, escape}, children} <> rest) ==
      Some{Browser.DismissTarget{Identity.encode(key), input, outside, escape}} : Maybe<&2, Browser.DismissTarget>}
