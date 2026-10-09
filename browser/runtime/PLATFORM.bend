import Base
import ../../interaction/MODEL.bend as Product
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ../focus/MODEL.bend as Focus
import ../../harness/MODEL.bend as M
import ../../interaction/STATE.bend as Core
import ../../interaction/session/MODEL.bend as E
import ../../interaction/INPUT.bend as U
import ../../interaction/presentation/MODEL.bend as View
import ../../bendlib/association-map.bend as Finite
import ../reading/MODEL.bend as Reading
import ../editor/MODEL.bend as Editor
import ../../interaction/conversation/CODE.bend as Code
import ../controls/GEOMETRY.bend as Physical
import ../../interaction/TYPES.bend as InteractionTypes
import ../../interaction/presentation/SURFACE.bend as SurfaceTypes

type Platform is Data:
  Platform{readers: +List<Finite.Entry(Reading.Bookmark)>, editors: +List<Editor.Editor>,
    focused: Focus.Target, focus_ticket: Nat, reduced_motion: Bool, capacity: View.Capacity, scope: Focus.Scope}

type State is Data:
  State{core: InteractionTypes.State, platform: Platform}

def readers(state: Platform) -> +List<Finite.Entry(Reading.Bookmark)>:
  Platform{value_readers, value_editors, value_focused, value_focus_ticket, value_reduced_motion, value_capacity, value_scope} = state
  value_readers

def editors(state: Platform) -> +List<Editor.Editor>:
  Platform{value_readers, value_editors, value_focused, value_focus_ticket, value_reduced_motion, value_capacity, value_scope} = state
  value_editors

def focused(state: Platform) -> Focus.Target:
  Platform{value_readers, value_editors, value_focused, value_focus_ticket, value_reduced_motion, value_capacity, value_scope} = state
  value_focused

def focus_ticket(state: Platform) -> Nat:
  Platform{value_readers, value_editors, value_focused, value_focus_ticket, value_reduced_motion, value_capacity, value_scope} = state
  value_focus_ticket

def reduced_motion(state: Platform) -> Bool:
  Platform{value_readers, value_editors, value_focused, value_focus_ticket, value_reduced_motion, value_capacity, value_scope} = state
  value_reduced_motion

def capacity(state: Platform) -> View.Capacity:
  Platform{value_readers, value_editors, value_focused, value_focus_ticket, value_reduced_motion, value_capacity, value_scope} = state
  value_capacity

def scope(state: Platform) -> Focus.Scope:
  Platform{value_readers, value_editors, value_focused, value_focus_ticket, value_reduced_motion, value_capacity, value_scope} = state
  value_scope

def with_focus_ticket(value: Nat, state: Platform) -> Platform:
  Platform{value_readers, value_editors, value_focused, value_focus_ticket, value_reduced_motion, value_capacity, value_scope} = state
  Platform{value_readers, value_editors, value_focused, value, value_reduced_motion, value_capacity, value_scope}

def with_scope(value: Focus.Scope, state: Platform) -> Platform:
  Platform{value_readers, value_editors, value_focused, value_focus_ticket, value_reduced_motion, value_capacity, value_scope} = state
  Platform{value_readers, value_editors, value_focused, value_focus_ticket, value_reduced_motion, value_capacity, value}

def core(state: State) -> InteractionTypes.State:
  State{value_core, value_platform} = state
  value_core

def platform(state: State) -> Platform:
  State{value_core, value_platform} = state
  value_platform

def with_core(value: InteractionTypes.State, state: State) -> State:
  State{value_core, value_platform} = state
  State{value, value_platform}

def with_platform(value: Platform, state: State) -> State:
  State{value_core, value_platform} = state
  State{value_core, value}

type Input is Data:
  ProductInput{input: Product.Input}
  ReadingInput{task: Nat, generation: Nat, event: Reading.ReadingEvent}
  EditorInput{editor: U.Editor, event: Editor.EditorEvent}
  CapacityObserved{capacity: View.Capacity}
  FocusObserved{identity: String}
  ContentFocusObserved{owner: String, identity: String}
  FocusApplied{ticket: Nat, target: Focus.Target, observed: Maybe<&2, Focus.Target>}
  PublicationFocusObserved{ticket: Nat, before: Maybe<&2, Focus.Target>, after: Maybe<&2, Focus.Target>}
  MotionPreference{reduced: Bool}

type Effect is Data:
  ApplyReading{task: Nat, generation: Nat, effect: Reading.Effect}
  Focus{ticket: Nat, target: Focus.Target}
  ScopeFocus{ticket: Nat, previous: Focus.Scope, current: Focus.Scope}
  Clipboard{block: Code.Identity, effect: Code.Effect}

type Decision is Data:
  Decision{product: InteractionTypes.Decision, platform: Platform, effects: +List<Effect>}

type Scene is Data:
  Scene{editors: +List<Editor.Editor>, focused: Focus.Target, focus_ticket: Nat, scope: Focus.Scope, reduced_motion: Bool}

def with_editors(value: +List<Editor.Editor>, state: Platform) -> Platform:
  Platform{value_readers, value_editors, value_focused, value_focus_ticket, value_reduced_motion, value_capacity, value_scope} = state
  Platform{value_readers, value, value_focused, value_focus_ticket, value_reduced_motion, value_capacity, value_scope}

def from_core(core: InteractionTypes.State, platform: Platform) -> State:
  State{core, platform}

def decision_platform(decision: Decision) -> Platform:
  Decision{product, platform, effects} = decision
  platform

def initial(program: M.World()) -> State:
  State{Core.initial(program), Platform{Nil{}, Nil{}, Focus.Product{""}, 0n, False{}, View.Capacity{False{}, False{}}, Focus.Document{}}}

def unchanged(+core: InteractionTypes.State) -> InteractionTypes.Decision:
  +application = Core.application(core)
  +services = Core.services(core)
  Core.application_result(E.unchanged(application), services)

def bookmark(found: Maybe<&2, Reading.Bookmark>) -> Reading.Bookmark:
  match found:
    case None{}: Reading.Bookmark{None{}}
    case Some{value}: value

def active_reader(+application: E.Application, +task: Nat, generation: Nat) -> Bool:
  +observed_session_1 = E.session(application)
  +route = E.route(observed_session_1)
  +readers = E.readers(observed_session_1)
  U.route_owns(route, task) && Nat.is_eq(E.reader_generation(E.reader(readers, task)), generation)

def reading_intent(+application: E.Application, task: Nat) -> U.ReadingIntent:
  +observed_session_1 = E.session(application)
  +readers = E.readers(observed_session_1)
  E.reader_position(E.reader(readers, task))

def wrap_scroll(effects: +List<Reading.Effect>, +task: Nat, +generation: Nat) -> +List<Effect>:
  match effects:
    case Nil{}: Nil{}
    case Con{effect, rest}: ApplyReading{task, generation, effect} <> wrap_scroll(rest, task, generation)

def set_intent(intent: Maybe<&2, U.ReadingIntent>, task: Nat, generation: Nat, core: InteractionTypes.State) -> InteractionTypes.Decision:
  match intent:
    case None{}: unchanged(core)
    case Some{intent}: Product.step(Product.Reading{task, generation, intent}, core)

def reading_result(decision: Reading.Decision, +task: Nat, +generation: Nat, core: InteractionTypes.State, platform: Platform) -> Decision:
  Reading.Decision{bookmark, intent, effects} = decision
  Platform{readers, editors, focused, ticket, reduced, capacity, scope} = platform
  Decision{set_intent(intent, task, generation, core),
    Platform{(task, bookmark) <> Finite.remove(~Reading.Bookmark, readers, task), editors, focused, ticket, reduced, capacity, scope}, wrap_scroll(effects, task, generation)}

def read(owned: Bool, +task: Nat, generation: Nat, event: Reading.ReadingEvent, +core: InteractionTypes.State, platform: Platform) -> Decision:
  match owned:
    case False{}: Decision{unchanged(core), platform, Nil{}}
    case True{}:
      Platform{+readers, editors, focused, ticket, +reduced, capacity, scope} = platform
      +application = Core.application(core)
      reading_result(Reading.step(event, reading_intent(application, task), bookmark(Finite.find(~Reading.Bookmark, readers, task)), reduced),
        task, generation, core, Platform{readers, editors, focused, ticket, reduced, capacity, scope})

def choose_editor(same: Bool, editor: Editor.Editor, fallback: Editor.Editor) -> Editor.Editor:
  match same:
    case True{}: editor
    case False{}: fallback

def find_editor(editors: +List<Editor.Editor>, +owner: U.Editor) -> Editor.Editor:
  match editors:
    case Nil{}: Editor.Editor{owner, Physical.Selection{0n, 0n, "none"}, False{}}
    case Con{Editor.Editor{+current, selection, composing}, rest}:
      choose_editor(U.same_editor(current, owner), Editor.Editor{current, selection, composing}, find_editor(rest, owner))

def replace_editor(same: Bool, old: Editor.Editor, rest: +List<Editor.Editor>, current: Editor.Editor, fallback: +List<Editor.Editor>) -> +List<Editor.Editor>:
  match same:
    case True{}: current <> rest
    case False{}: old <> fallback

def save_editor(editors: +List<Editor.Editor>, +owner: U.Editor, +current: Editor.Editor) -> +List<Editor.Editor>:
  match editors:
    case Nil{}: [current]
    case Con{Editor.Editor{+key, selection, composing}, +rest}:
      replace_editor(U.same_editor(key, owner), Editor.Editor{key, selection, composing}, rest, current, save_editor(rest, owner, current))

def editor_enabled(core: InteractionTypes.State, owner: U.Editor, capacity: View.Capacity) -> Bool:
  InterfaceView.composer_enabled(capacity, owner, core)

def layout_route(route: U.Route, +readers: +List<Finite.Entry(E.Reader)>, bookmarks: +List<Finite.Entry(Reading.Bookmark)>) -> +List<Effect>:
  match route:
    case U.Conversation{+task}: wrap_scroll(Reading.layout(E.reader_position(E.reader(readers, task)), bookmark(Finite.find(~Reading.Bookmark, bookmarks, task))), task, E.reader_generation(E.reader(readers, task)))
    case _: Nil{}

def layout_for(+application: E.Application, bookmarks: +List<Finite.Entry(Reading.Bookmark)>) -> +List<Effect>:
  +session = E.session(application)
  layout_route(E.route(session), E.readers(session), bookmarks)

def focus_effects(effects: +List<E.Effect>, +ticket: Nat) -> +List<Effect>:
  match effects:
    case Nil{}: Nil{}
    case Con{E.Attend{target}, rest}: Focus{ticket, Focus.Product{target}} <> focus_effects(rest, ticket)
    case Con{E.ContentEffect{identity, effect}, rest}: Clipboard{identity, effect} <> focus_effects(rest, ticket)
    case Con{other, rest}: focus_effects(rest, ticket)

def content_effects(effects: +List<E.Effect>) -> +List<Effect>:
  match effects:
    case Nil{}: Nil{}
    case Con{E.ContentEffect{identity, effect}, rest}: Clipboard{identity, effect} <> content_effects(rest)
    case Con{other, rest}: content_effects(rest)

def has_attention(effects: +List<E.Effect>) -> Bool:
  match effects:
    case Nil{}: False{}
    case Con{E.Attend{target}, rest}: True{}
    case Con{other, rest}: has_attention(rest)

def scope_attention(explicit: Bool, previous: Focus.Scope, current: Focus.Scope, effects: +List<E.Effect>, ticket: Nat) -> +List<Effect>:
  match explicit:
    case True{}: focus_effects(effects, ticket)
    case False{}: ScopeFocus{ticket, previous, current} <> content_effects(effects)

def retained_root_handoff(retained: Bool, previous_root: Bool, next_input: Bool) -> Bool:
  match retained:
    case False{}: False{}
    case True{}: previous_root && next_input

# NOTE: A loading layer keeps its root eligible after content arrives; transfer only
# while that root still owns focus, so an intervening user choice is preserved.

def product_scope_handoff(previous: Focus.Scope, current: Focus.Scope, +focused: String) -> Bool:
  match previous current:
    case Focus.Temporary{+old_identity, +old_initial, old_restore, old_occurrence} Focus.Temporary{new_identity, new_initial, new_restore, new_occurrence}:
      retained_root_handoff(String.eq(focused, old_initial),
        String.eq(old_identity, new_identity) && String.eq(old_initial, old_identity),
        Bool.not(String.eq(old_initial, new_initial)))
    case _ _: False{}

def scope_handoff(previous: Focus.Scope, current: Focus.Scope, focused: Focus.Target) -> Bool:
  match focused:
    case Focus.Content{owner, identity}: False{}
    case Focus.Product{focused}: product_scope_handoff(previous, current, focused)

def focus_transition(+previous: Focus.Scope, +current: Focus.Scope, focused: Focus.Target, eligible: Bool) -> Bool:
  Focus.transition(previous, current, eligible) || scope_handoff(previous, current, focused)

def scope_effects(changed: Bool, previous: Focus.Scope, current: Focus.Scope, +effects: +List<E.Effect>, +ticket: Nat) -> +List<Effect>:
  match changed:
    case True{}: scope_attention(has_attention(effects), previous, current, effects, ticket)
    case False{}: focus_effects(effects, ticket)

def advance_ticket(advance: Bool, ticket: Nat) -> Nat:
  match advance:
    case True{}: (ticket + 1n : Nat)
    case False{}: ticket

def focus_revision(scope_changed: Bool, effects: +List<E.Effect>, ticket: Nat) -> Nat:
  advance_ticket(scope_changed || has_attention(effects), ticket)

def empty_message(body: U.Body) -> Bool:
  match body:
    case U.NewTask{U.Text{text}, profile, reasoning, context}: String.eq(text, "")
    case U.Message{task, U.Text{text}, delivery}: String.eq(text, "")
    case _: False{}

def clear_selection(clear: Bool, editor: Editor.Editor) -> Editor.Editor:
  match clear:
    case False{}: editor
    case True{}:
      Editor.Editor{owner, selection, composing} = editor
      Editor.Editor{owner, Physical.Selection{0n, 0n, "none"}, False{}}

def synchronize_editor(found: Maybe<&2, U.Draft>, editor: Editor.Editor) -> Editor.Editor:
  match found:
    case Some{U.Draft{revision, body, U.Accepted{submitted, result}, directory_entry}}: clear_selection(empty_message(body), editor)
    case _: editor

def synchronize_drafts(+drafts: +List<U.Draft>, editors: +List<Editor.Editor>) -> +List<Editor.Editor>:
  match editors:
    case Nil{}: Nil{}
    case Con{Editor.Editor{+owner, selection, composing}, rest}:
      synchronize_editor(E.find_draft(drafts, owner), Editor.Editor{owner, selection, composing}) <> synchronize_drafts(drafts, rest)

def synchronize_editors(editors: +List<Editor.Editor>, +application: E.Application) -> +List<Editor.Editor>:
  +observed_session_1 = E.session(application)
  +drafts = E.drafts(observed_session_1)
  synchronize_drafts(drafts, editors)

def found_focus(found: Maybe<&2, SurfaceTypes.Node>) -> Bool:
  match found:
    case None{}: False{}
    case Some{SurfaceTypes.Node{key, semantic, label, role, meaning, children}}: InterfaceView.focusable(meaning)

def active_focus(core: InteractionTypes.State, capacity: View.Capacity, identity: String) -> Bool:
  found_focus(InterfaceView.find_node(InterfaceView.active_nodes(InterfaceView.observe(capacity, core)), identity))

def found_content_owner(found: Maybe<&2, SurfaceTypes.Node>) -> Bool:
  match found:
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ReadOnly{text}, children}}: True{}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.RichText{source, value}, children}}: True{}
    case _: False{}

def active_content_owner(core: InteractionTypes.State, capacity: View.Capacity, owner: String) -> Bool:
  found_content_owner(InterfaceView.find_node(InterfaceView.active_nodes(InterfaceView.observe(capacity, core)), owner))

def active_target(+core: InteractionTypes.State, +capacity: View.Capacity, target: Focus.Target) -> Bool:
  match target:
    case Focus.Product{identity}: active_focus(core, capacity, identity)
    case Focus.Content{owner, identity}: active_content_owner(core, capacity, owner)

def after_core_scoped(decision: InteractionTypes.Decision, platform: Platform, +current_scope: Focus.Scope) -> Decision:
  InteractionTypes.Decision{+observed_state_1, reply, runtime, +interaction, service, durable} = decision
  Platform{+readers, editors, +focused, +ticket, reduced, +capacity, +scope} = platform
  +application = Core.application(observed_state_1)
  +transition = focus_transition(scope, current_scope, focused, active_target(observed_state_1, capacity, focused))
  Decision{InteractionTypes.Decision{observed_state_1, reply, runtime, interaction, service, durable},
    Platform{readers, synchronize_editors(editors, application), focused, focus_revision(transition, interaction, ticket), reduced, capacity, current_scope},
    List.append(&2, Effect, scope_effects(transition, scope, current_scope, interaction, focus_revision(transition, interaction, ticket)), layout_for(application, readers))}

def after_core(decision: InteractionTypes.Decision, platform: Platform) -> Decision:
  InteractionTypes.Decision{+state, reply, runtime, interaction, services, durable} = decision
  Platform{readers, editors, focused, ticket, reduced, +capacity, scope} = platform
  after_core_scoped(InteractionTypes.Decision{state, reply, runtime, interaction, services, durable},
    Platform{readers, editors, focused, ticket, reduced, capacity, scope}, Focus.current(state, capacity))

def submit_from_platform(core: InteractionTypes.State, owner: U.Editor, +platform: Platform) -> Decision:
  Platform{readers, editors, focused, ticket, reduced, +capacity, scope} = platform
  after_core(Product.step(Product.SubmitComposer{capacity, owner}, core), platform)

def editor_result(requested: Bool, owner: U.Editor, core: InteractionTypes.State, platform: Platform) -> Decision:
  match requested:
    case True{}: submit_from_platform(core, owner, platform)
    case False{}: Decision{unchanged(core), platform, Nil{}}

def edit_result(result: Editor.Decision, +owner: U.Editor, core: InteractionTypes.State, platform: Platform) -> Decision:
  Editor.Decision{editor, requested} = result
  Platform{readers, editors, focused, ticket, reduced, capacity, scope} = platform
  editor_result(requested, owner, core, Platform{readers, save_editor(editors, owner, editor), focused, ticket, reduced, capacity, scope})

def focus_confirmed(expected: Focus.Target, observed: Maybe<&2, Focus.Target>) -> Bool:
  match observed:
    case None{}: False{}
    case Some{actual}: Focus.same_target(expected, actual)

def publication_focus_result(owned: Bool, ticket: Nat, before: Focus.Target, core: InteractionTypes.State, platform: Platform) -> Decision:
  match owned:
    case False{}: Decision{unchanged(core), platform, Nil{}}
    case True{}: Decision{unchanged(core), platform, [Focus{ticket, before}]}

def publication_focus_observed(received: Nat, before: Maybe<&2, Focus.Target>, after: Maybe<&2, Focus.Target>, +core: InteractionTypes.State, platform: Platform) -> Decision:
  match before after:
    case Some{+target} None{}:
      Platform{readers, editors, focused, +ticket, reduced, +capacity, scope} = platform
      publication_focus_result(Nat.is_eq(received, ticket) && active_target(core, capacity, target), ticket, target, core,
        Platform{readers, editors, focused, ticket, reduced, capacity, scope})
    case _ _: Decision{unchanged(core), platform, Nil{}}

def focus_result(owned: Bool, identity: Focus.Target, core: InteractionTypes.State, platform: Platform) -> Decision:
  match owned:
    case False{}: Decision{unchanged(core), platform, Nil{}}
    case True{}:
      Platform{readers, editors, focused, ticket, reduced, capacity, scope} = platform
      Decision{unchanged(core), Platform{readers, editors, identity, ticket, reduced, capacity, scope}, Nil{}}

def observed_focus(platform: Platform, inside: Bool, identity: Focus.Target, core: InteractionTypes.State) -> Decision:
  Platform{readers, editors, focused, +ticket, reduced, capacity, +scope} = platform
  match inside:
    case True{}: Decision{unchanged(core), Platform{readers, editors, identity, (ticket + 1n : Nat), reduced, capacity, scope}, Nil{}}
    case False{}: Decision{unchanged(core), Platform{readers, editors, focused, (ticket + 1n : Nat), reduced, capacity, scope}, [Focus{(ticket + 1n : Nat), Focus.Product{Focus.initial(scope)}}]}

def dispatch(+state: State, +input: Input) -> Decision:
  State{+observed_state_1, platform} = state
  Platform{readers, +editors, +focused, +ticket, reduced, +capacity, +scope} = platform
  match input:
    case ProductInput{input}: after_core(Product.step(input, observed_state_1), Platform{readers, editors, focused, ticket, reduced, capacity, scope})
    case ReadingInput{+task, +generation, event}:
      read(active_reader(Core.application(observed_state_1), task, generation), task, generation, event, observed_state_1, Platform{readers, editors, focused, ticket, reduced, capacity, scope})
    case EditorInput{+owner, event}:
      edit_result(Editor.step(find_editor(editors, owner), event, editor_enabled(observed_state_1, owner, capacity) && Focus.permits_composer(scope), False{}), owner, observed_state_1, Platform{readers, editors, focused, ticket, reduced, capacity, scope})
    case CapacityObserved{value}: after_core(unchanged(observed_state_1), Platform{readers, editors, focused, ticket, reduced, value, scope})
    case FocusObserved{+identity}: observed_focus(Platform{readers, editors, focused, ticket, reduced, capacity, scope}, active_focus(observed_state_1, capacity, identity), Focus.Product{identity}, observed_state_1)
    case ContentFocusObserved{+owner, identity}: observed_focus(Platform{readers, editors, focused, ticket, reduced, capacity, scope}, active_content_owner(observed_state_1, capacity, owner), Focus.Content{owner, identity}, observed_state_1)
    case FocusApplied{expected, +identity, observed}: focus_result((Nat.is_eq(expected, ticket) && active_target(observed_state_1, capacity, identity)) && focus_confirmed(identity, observed), identity, observed_state_1, Platform{readers, editors, focused, ticket, reduced, capacity, scope})
    case PublicationFocusObserved{received, before, after}: publication_focus_observed(received, before, after, observed_state_1, Platform{readers, editors, focused, ticket, reduced, capacity, scope})
    case MotionPreference{value}: Decision{unchanged(observed_state_1), Platform{readers, editors, focused, ticket, value, capacity, scope}, Nil{}}

def step_raw(input: Input, state: State) -> Decision:
  dispatch(state, input)

def realized_product_focus(found: Maybe<&2, String>, ticket: Nat, rest: +List<Effect>) -> +List<Effect>:
  match found:
    case None{}: rest
    case Some{key}: Focus{ticket, Focus.Product{key}} <> rest

def realized_effects(+surface: SurfaceTypes.Surface, effects: +List<Effect>) -> +List<Effect>:
  match effects:
    case Nil{}: Nil{}
    case Con{Focus{ticket, Focus.Product{requested}}, rest}:
      realized_product_focus(InterfaceView.focus_target(surface, requested), ticket, realized_effects(surface, rest))
    case Con{ScopeFocus{ticket, previous, current}, rest}:
      realized_product_focus(InterfaceView.focus_target(surface, Focus.scope_target(previous, current, surface)), ticket, realized_effects(surface, rest))
    case Con{effect, rest}: effect <> realized_effects(surface, rest)

def realized_decision(decision: Decision) -> Decision:
  Decision{InteractionTypes.Decision{+core, reply, runtime, interaction, services, durable},
    Platform{readers, editors, focused, ticket, reduced, +capacity, scope}, effects} = decision
  # NOTE: Resolve product focus once against the committed UI before host delivery.
  +surface = InterfaceView.observe(capacity, core)
  Decision{InteractionTypes.Decision{core, reply, runtime, interaction, services, durable},
    Platform{readers, editors, focused, ticket, reduced, capacity, scope}, realized_effects(surface, effects)}

def step(input: Input, state: State) -> Decision:
  realized_decision(step_raw(input, state))

def next(decision: Decision) -> State:
  Decision{InteractionTypes.Decision{core, reply, runtime, interaction, services, durable}, platform, effects} = decision
  State{core, platform}

def observe(state: State) -> Scene:
  State{core, Platform{readers, editors, focused, ticket, reduced, capacity, scope}} = state
  Scene{editors, focused, ticket, scope, reduced}

def same_capacity(first: View.Capacity, second: View.Capacity) -> Bool:
  View.Capacity{+first_navigation, +first_details} = first
  View.Capacity{+second_navigation, +second_details} = second
  ((first_navigation && second_navigation) || (Bool.not(first_navigation) && Bool.not(second_navigation))) &&
    ((first_details && second_details) || (Bool.not(first_details) && Bool.not(second_details)))

def merge_reflow(product: InteractionTypes.Decision, effects: +List<Effect>, refreshed: Decision) -> Decision:
  Decision{ignored_product, platform, reconciliation} = refreshed
  Decision{product, platform, List.append(&2, Effect, effects, reconciliation)}

def changed_capacity(decision: Decision, capacity: View.Capacity) -> Decision:
  Decision{InteractionTypes.Decision{+state, reply, runtime, interaction, services, durable}, Platform{readers, editors, focused, ticket, reduced, old_capacity, scope}, effects} = decision
  merge_reflow(InteractionTypes.Decision{state, reply, runtime, interaction, services, durable}, effects, after_core(unchanged(state),
    Platform{readers, editors, focused, ticket, reduced, capacity, scope}))

def retained_capacity(same: Bool, decision: Decision, capacity: View.Capacity) -> Decision:
  match same:
    case True{}: decision
    case False{}: changed_capacity(decision, capacity)

def reflow_capacity(+decision: Decision, +capacity: View.Capacity) -> Decision:
  Decision{product, Platform{readers, editors, focused, ticket, reduced, +old_capacity, scope}, effects} = decision
  retained_capacity(same_capacity(old_capacity, capacity),
    Decision{product, Platform{readers, editors, focused, ticket, reduced, old_capacity, scope}, effects}, capacity)

def decision_product(decision: Decision) -> InteractionTypes.Decision:
  Decision{product, platform, effects} = decision
  product
