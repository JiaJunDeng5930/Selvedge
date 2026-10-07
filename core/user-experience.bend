import ../bendlib/stdlib.bend as Std
import Base
import ./code-block.bend as Content
import ./live-output.bend as Live
import ../MODEL.bend as M
import ../PROJECTS.bend as Projects
import ../WORKSPACE.bend as W
import ../BOARD.bend as B
import ../FEATURES.bend as F
import ../REASONING.bend as Reasoning
import ../bendlib/domain.bend as D
import ../bendlib/component.bend as C
import ../bendlib/association-map.bend as Finite
import ../bendlib/board-state.bend as Board
import ../bendlib/json.bend as J
import ../bendlib/command-codec.bend as CommandCodec
import ./user-context.bend as Context
import ./user-input.bend as U

type Disclosure is Data:
  Disclosure{group: Nat, occurrence: Nat, expanded: Bool}

type Reader is Data:
  Reader{generation: Nat, position: U.ReadingIntent, disclosures: +List<Disclosure>}

type Layer is Data:
  Layer{panel: U.Panel, trigger: String, initial_attention: String, query: String, occurrence: Nat}

type Pending is Data:
  Pending{ticket: Nat, draft: U.Draft, now: U32}

type Session is Data:
  Session{route: U.Route, drafts: +List<U.Draft>, readers: +List<Finite.Entry(Reader)>,
    layers: +List<Layer>, attention: String, navigation: NavigationState, filter: B.Filter,
    now: U32, next_ticket: Nat, pending: +List<Pending>, previews: +List<Live.Output>, code_blocks: +List<Content.Block>, next_layer: Nat}

type NavigationIntent is Data:
  AutomaticNavigation{}
  OpenNavigation{}
  ClosedNavigation{}

type NavigationState is Data:
  NavigationState{intent: NavigationIntent, collapsed_projects: +List<Nat>}

# Execution and human participation form one system. Observations are projections
# of this value, not an independently supplied tree of enabled widgets.
type Application is Data:
  Application{program: M.World(), session: Session}

def program(state: Application) -> M.World():
  Application{program, session} = state
  program

def session(state: Application) -> Session:
  Application{program, session} = state
  session

def route(state: Session) -> U.Route:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer} = state
  route

def drafts(state: Session) -> +List<U.Draft>:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer} = state
  drafts

def readers(state: Session) -> +List<Finite.Entry(Reader)>:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer} = state
  readers

def layers(state: Session) -> +List<Layer>:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer} = state
  layers

def attention(state: Session) -> String:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer} = state
  attention

def navigation(state: Session) -> NavigationState:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer} = state
  navigation

def filter(state: Session) -> B.Filter:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer} = state
  filter

def now(state: Session) -> U32:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer} = state
  now

def next_ticket(state: Session) -> Nat:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer} = state
  next_ticket

def pending(state: Session) -> +List<Pending>:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer} = state
  pending

def previews(state: Session) -> +List<Live.Output>:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer} = state
  previews

def code_blocks(state: Session) -> +List<Content.Block>:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer} = state
  code_blocks

def next_layer(state: Session) -> Nat:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer} = state
  next_layer

def with_program(value: M.World(), state: Application) -> Application:
  Application{program, session} = state
  Application{value, session}

def with_session(value: Session, state: Application) -> Application:
  Application{program, session} = state
  Application{program, value}

def with_now(value: U32, state: Session) -> Session:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer} = state
  Session{route, drafts, readers, layers, attention, navigation, filter, value, next_ticket, pending, previews, code_blocks, next_layer}

def from_program(program: M.World(), session: Session) -> Application:
  Application{program, session}

def with_route(value: U.Route, state: Session) -> Session:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer} = state
  Session{value, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer}

def with_drafts(value: +List<U.Draft>, state: Session) -> Session:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer} = state
  Session{route, value, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer}

def with_layers(value: +List<Layer>, state: Session) -> Session:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer} = state
  Session{route, drafts, readers, value, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer}

def with_attention(value: String, state: Session) -> Session:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer} = state
  Session{route, drafts, readers, layers, value, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer}

def with_navigation(value: NavigationState, state: Session) -> Session:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer} = state
  Session{route, drafts, readers, layers, attention, value, filter, now, next_ticket, pending, previews, code_blocks, next_layer}

def with_next_ticket(value: Nat, state: Session) -> Session:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer} = state
  Session{route, drafts, readers, layers, attention, navigation, filter, now, value, pending, previews, code_blocks, next_layer}

def with_pending(value: +List<Pending>, state: Session) -> Session:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer} = state
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, value, previews, code_blocks, next_layer}

def with_next_layer(value: Nat, state: Session) -> Session:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer} = state
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, value}


type Completion is Data:
  DirectCompletion{}
  DraftCompletion{draft: U.Draft}
  ConfirmationCompletion{command: M.Command, trigger: String, destination: U.Route, occurrence: Nat}

type Effect is Data:
  RequestCommand{command: M.Command, completion: Completion}
  ContentEffect{identity: Content.Identity, effect: Content.Effect}
  ObserveDirectories{ticket: Nat, entered: D.Workspace}
  Attend{target: String}

type Decision is Data:
  Decision{application: Application, reply: J.Json, runtime_effects: +List<M.Effect()>,
    interaction_effects: +List<Effect>, durable: Bool}

type Input is Data:
  ContentInput{identity: Content.Identity, input: Content.Input}
  PreviewObserved{observation: Live.Observation}
  UserInput{input: U.Input}
  RuntimeInput{input: M.Input}
  ProgramObserved{program: M.World()}
  CommandCompleted{program: M.World(), reply: J.Json, completion: Completion}
  DirectoriesObserved{ticket: Nat, result: Result<&2, &2, String, Context.DirectoryObservation>}
  ClockObserved{now: U32}


def first_profile(profiles: +List<D.Profile>) -> Sigma<&2, &2, String, (_ => String)>:
  match profiles:
    case Nil{}: ("", "")
    case Con{D.Profile{+key, provider, name, policy, options}, rest}: (key, D.profile_default(D.Profile{key, provider, name, policy, options}))

def chooser_owns(layers: +List<Layer>, editor: U.Editor) -> Bool:
  match layers:
    case Con{Layer{U.ModelPicker{owner}, trigger, initial, query, layer_occurrence}, rest}: U.same_editor(owner, editor)
    case Con{Layer{U.DeliveryPicker{task}, trigger, initial, query, layer_occurrence}, rest}: U.same_editor(U.MessageEditor{task}, editor)
    case _: False{}

def reply(application: Application, result: J.Json) -> Decision:
  Decision{application, result, Nil{}, Nil{}, False{}}

def unchanged(application: Application) -> Decision:
  reply(application, D.success(J.Null{}))

def local(program: M.World(), session: Session, effects: +List<Effect>) -> Decision:
  Decision{Application{program, session}, D.success(J.Null{}), Nil{}, effects, False{}}

def close_layers(layers: +List<Layer>, program: M.World(), session: Session) -> Decision:
  match layers:
    case Nil{}: unchanged(Application{program, session})
    case Con{Layer{panel, +trigger, initial, query, layer_occurrence}, rest}:
      Session{route, drafts, readers, old, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer} = session
      local(program, Session{route, drafts, readers, rest, trigger, navigation, filter, now, next, pending, previews, code_blocks, next_layer}, [Attend{trigger}])

def close_panel(application: Application) -> Decision:
  Application{program, +session} = application
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer} = session
  close_layers(layers, program, session)

def with_native(local: Decision, result: J.Json, effects: +List<M.Effect()>, durable: Bool) -> Decision:
  Decision{application, ignored_reply, ignored_runtime, interaction, ignored_durable} = local
  Decision{application, result, effects, interaction, durable}

def close_choice_owned(owned: Bool, result: Decision) -> Decision:
  match owned:
    case False{}: result
    case True{}:
      Decision{application, reply, runtime, interaction, durable} = result
      with_native(close_panel(application), reply, runtime, durable)

def close_choice(editor: U.Editor, +result: Decision) -> Decision:
  Decision{Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}}, reply, runtime, interaction, durable} = result
  close_choice_owned(J.boolean(J.get(reply, "ok")) && chooser_owns(layers, editor), result)

def close_selected_choice(change: U.Edit, editor: U.Editor, result: Decision) -> Decision:
  match change:
    case U.ChooseModel{profile, reasoning}: close_choice(editor, result)
    case U.ChooseDelivery{delivery}: close_choice(editor, result)
    case _: result

def new_task(profile: Sigma<&2, &2, String, (_ => String)>, origin: Context.Origin) -> U.Body:
  (profile, reasoning) = profile
  U.NewTask{U.initial_text(""), profile, reasoning, Context.defaults(origin)}

def initial(+program: M.World()) -> Application:
  Application{program, Session{U.Start{}, [U.Draft{0n, new_task(first_profile(Board.profiles(program)), Context.EnvironmentDefaults{}), U.Editing{}, ""}],
    Nil{}, Nil{}, "composer/new-task", NavigationState{AutomaticNavigation{}, Nil{}}, B.empty_filter(), 0, 0n, Nil{}, Nil{}, Nil{}, 0n}}

def select_draft(hit: Bool, value: U.Draft, rest: Maybe<&2, U.Draft>) -> Maybe<&2, U.Draft>:
  match hit:
    case True{}: Some{value}
    case False{}: rest

def find_draft(drafts: +List<U.Draft>, +editor: U.Editor) -> Maybe<&2, U.Draft>:
  match drafts:
    case Nil{}: None{}
    case Con{U.Draft{revision, +body, feedback, directory_entry}, rest}:
      select_draft(U.same_editor(U.owner(body), editor), U.Draft{revision, body, feedback, directory_entry}, find_draft(rest, editor))

def keep_draft(hit: Bool, draft: U.Draft, rest: +List<U.Draft>) -> +List<U.Draft>:
  match hit:
    case True{}: rest
    case False{}: draft <> rest

def without_draft(drafts: +List<U.Draft>, +editor: U.Editor) -> +List<U.Draft>:
  match drafts:
    case Nil{}: Nil{}
    case Con{U.Draft{revision, +body, feedback, directory_entry}, rest}:
      keep_draft(U.same_editor(U.owner(body), editor), U.Draft{revision, body, feedback, directory_entry}, without_draft(rest, editor))

def put_draft(+draft: U.Draft, drafts: +List<U.Draft>) -> +List<U.Draft>:
  U.Draft{revision, body, feedback, directory_entry} = draft
  draft <> without_draft(drafts, U.owner(body))

def with_draft(session: Session, draft: U.Draft) -> Session:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer} = session
  Session{route, put_draft(draft, drafts), readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}

def refuse(application: Application, reason: String) -> Decision:
  reply(application, D.failure("interaction_refused", reason))

def edit_result(result: Result<&2, &2, String, U.Draft>, program: M.World(), session: Session) -> Decision:
  match result:
    case Fail{reason}: refuse(Application{program, session}, reason)
    case Done{draft}: local(program, with_draft(session, draft), Nil{})

def confirm_found(admitted: Bool, draft: U.Draft, +program: M.World(), session: Session) -> Decision:
  match admitted:
    case False{}: unchanged(Application{program, session})
    case True{}: edit_result(U.edit_draft(U.ConfirmDirectory{}, draft, program), program, session)

def edit_existing(change: U.Edit, +draft: U.Draft, +program: M.World(), session: Session) -> Decision:
  match change:
    case U.ConfirmDirectory{}: confirm_found(U.can_confirm_directory(draft), draft, program, session)
    case other: edit_result(U.edit_draft(other, draft, program), program, session)

def edit_found(found: Maybe<&2, U.Draft>, change: U.Edit, +program: M.World(), session: Session) -> Decision:
  match found:
    case None{}: refuse(Application{program, session}, "The editor is not open")
    case Some{draft}: edit_existing(change, draft, program, session)

def edit(editor: U.Editor, change: U.Edit, application: Application) -> Decision:
  Application{program, +session} = application
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer} = session
  edit_found(find_draft(drafts, editor), change, program, session)

def reader_or_default(found: Maybe<&2, Reader>) -> Reader:
  match found:
    case None{}: Reader{0n, U.FollowLatest{}, Nil{}}
    case Some{reader}: reader

def reader(readers: +List<Finite.Entry(Reader)>, task: Nat) -> Reader:
  reader_or_default(Finite.find(~Reader, readers, task))

def reader_position(reader: Reader) -> U.ReadingIntent:
  Reader{generation, position, disclosures} = reader
  position

def reading_decision(position: U.ReadingIntent, old: Reader, +task: Nat, program: M.World(), session: Session) -> Decision:
  Reader{generation, old_position, disclosures} = old
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer} = session
  local(program, Session{route, drafts, (task, Reader{generation, position, disclosures}) <> Finite.remove(~Reader, readers, task),
    layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}, Nil{})
def read(+task: Nat, intent: U.ReadingIntent, application: Application) -> Decision:
  Application{program, +session} = application
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer} = session
  +old = reader(readers, task)
  reading_decision(intent, old, task, program, session)


def navigation_intent_after_visit(intent: NavigationIntent) -> NavigationIntent:
  match intent:
    case OpenNavigation{}: AutomaticNavigation{}
    case other: other

def navigation_after_visit(state: NavigationState) -> NavigationState:
  NavigationState{intent, collapsed} = state
  NavigationState{navigation_intent_after_visit(intent), collapsed}

def navigation_visibility(state: NavigationState) -> NavigationIntent:
  NavigationState{intent, collapsed} = state
  intent

def navigation_intent(expanded: Bool) -> NavigationIntent:
  match expanded:
    case True{}: OpenNavigation{}
    case False{}: ClosedNavigation{}
def set_navigation(expanded: Bool, state: NavigationState) -> NavigationState:
  NavigationState{intent, collapsed} = state
  NavigationState{navigation_intent(expanded), collapsed}

def project_collapsed(state: NavigationState, +id: Nat) -> Bool:
  NavigationState{intent, collapsed} = state
  List.contains(~Nat, ~Nat.is_eq, collapsed, id)

def project_disclosure_value(entry: Finite.Entry(Nat)) -> Nat:
  (id, value) = entry
  id

def without_collapsed_project(collapsed: +List<Nat>, id: Nat) -> +List<Nat>:
  Std.map(~Finite.Entry(Nat), ~Nat, ~(entry => project_disclosure_value(entry)), Finite.remove(~Nat, Std.map(~Nat, ~Finite.Entry(Nat), ~(current => (current, 0n)), collapsed), id))

def toggle_collapsed(present: Bool, +id: Nat, collapsed: +List<Nat>) -> +List<Nat>:
  match present:
    case True{}: without_collapsed_project(collapsed, id)
    case False{}: id <> collapsed

def toggle_project_navigation(+id: Nat, +state: NavigationState) -> NavigationState:
  NavigationState{intent, collapsed} = state
  NavigationState{intent, toggle_collapsed(project_collapsed(state, id), id, collapsed)}

def toggle_project(id: Nat, application: Application) -> Decision:
  Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code, next_layer}} = application
  local(program, Session{route, drafts, readers, layers, attention, toggle_project_navigation(id, navigation), filter, now, next, pending, previews, code, next_layer}, Nil{})

def new_visit(reader: Reader) -> Reader:
  Reader{generation, position, disclosures} = reader
  Reader{(generation + 1n : Nat), position, disclosures}

def visit_readers(route: U.Route, +readers: +List<Finite.Entry(Reader)>) -> +List<Finite.Entry(Reader)>:
  match route:
    case U.Conversation{+task}: (task, new_visit(reader(readers, task))) <> Finite.remove(~Reader, readers, task)
    case _: readers

def navigate_with_attention(+route: U.Route, +target: String, application: Application) -> Decision:
  Application{program, Session{old, drafts, +readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}} = application
  +current_readers = visit_readers(route, readers)
  local(program, Session{route, drafts, current_readers, Nil{}, target, navigation_after_visit(navigation), filter, now, next, pending, previews, code_blocks, next_layer},
    [Attend{target}])

def navigate(route: U.Route, application: Application) -> Decision:
  navigate_with_attention(route, "page-heading", application)

def reader_generation(reader: Reader) -> Nat:
  Reader{generation, position, disclosures} = reader
  generation

def read_owned(owned: Bool, task: Nat, intent: U.ReadingIntent, application: Application) -> Decision:
  match owned:
    case True{}: read(task, intent, application)
    case False{}: unchanged(application)

def read_current(+task: Nat, generation: Nat, intent: U.ReadingIntent, +application: Application) -> Decision:
  Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}} = application
  read_owned(U.route_owns(route, task) && Nat.is_eq(generation, reader_generation(reader(readers, task))), task, intent, application)

def ensure(found: Maybe<&2, U.Draft>, fallback: U.Body, session: Session) -> Session:
  match found:
    case Some{U.Draft{revision, body, U.Accepted{submitted, result}, directory_entry}}: with_draft(session, U.Draft{(revision + 1n : Nat), fallback, U.Editing{}, ""})
    case Some{draft}: session
    case None{}: with_draft(session, U.Draft{0n, fallback, U.Editing{}, ""})

def visit(route: U.Route, application: Application) -> Decision:
  match route:
    case U.Conversation{+task}:
      Application{program, +session} = application
      Session{old, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer} = session
      navigate(U.Conversation{task}, Application{program, ensure(find_draft(drafts, U.MessageEditor{task}),
        U.Message{task, U.initial_text(""), U.Send{}}, session)})
    case other: navigate(other, application)

def panel_target(panel: U.Panel) -> String:
  match panel:
    case U.ProjectPicker{}: "project-picker"
    case U.ObjectActions{subject}: "actions/" ++ U.subject_key(subject)
    case U.ArchivedCards{}: "archived-cards"
    case U.BoardSettings{}: "board-settings"
    case U.BoardFilters{}: "board-filters"
    case U.CardDetails{card}: "card-details/" ++ Nat.show(card)
    case U.EditObject{editor}: "editor/" ++ U.editor_key(editor)
    case U.TaskDetails{task}: "task-details/" ++ Nat.show(task)
    case U.WorkspaceConfiguration{editor}: "workspace-configuration/" ++ U.editor_key(editor)
    case U.PermissionsConfiguration{editor}: "permissions-configuration/" ++ U.editor_key(editor)
    case U.TaskContext{task}: "task-context/" ++ Nat.show(task)
    case U.ModelPicker{editor}: "model-picker/" ++ U.editor_key(editor)
    case U.DeliveryPicker{task}: "delivery-picker/" ++ Nat.show(task)
    case U.Confirm{command, title, destination}: "confirm/cancel"

def keep_layer(same: Bool, layer: Layer, rest: +List<Layer>) -> +List<Layer>:
  match same:
    case True{}: rest
    case False{}: layer <> rest

def without_panel(layers: +List<Layer>, +identity: String) -> +List<Layer>:
  match layers:
    case Nil{}: Nil{}
    case Con{Layer{+panel, trigger, initial, query, layer_occurrence}, rest}:
      keep_layer(String.eq(panel_target(panel), identity), Layer{panel, trigger, initial, query, layer_occurrence}, without_panel(rest, identity))

def open_panel(+panel: U.Panel, trigger: String, application: Application) -> Decision:
  Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, +next_layer}} = application
  +target = panel_target(panel)
  local(program, Session{route, drafts, readers, Layer{panel, trigger, target, "", next_layer} <> without_panel(layers, panel_target(panel)),
    target, navigation, filter, now, next, pending, previews, code_blocks, (next_layer + 1n : Nat)}, [Attend{target}])

def panel_present(layers: +List<Layer>, +target: String) -> Bool:
  match layers:
    case Nil{}: False{}
    case Con{Layer{panel, trigger, initial, query, layer_occurrence}, rest}:
      String.eq(panel_target(panel), target) || panel_present(rest, target)

def toggle_panel_selected(present: Bool, +panel: U.Panel, +trigger: String, application: Application) -> Decision:
  match present:
    case False{}: open_panel(panel, trigger, application)
    case True{}:
      Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}} = application
      local(program, Session{route, drafts, readers, without_panel(layers, panel_target(panel)), trigger,
        navigation, filter, now, next, pending, previews, code_blocks, next_layer}, [Attend{trigger}])

def toggle_panel(+panel: U.Panel, trigger: String, application: Application) -> Decision:
  Application{program, Session{route, drafts, readers, +layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}} = application
  toggle_panel_selected(panel_present(layers, panel_target(panel)), panel, trigger,
    Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}})

def open_editor_found(found: Maybe<&2, U.Draft>, +body: U.Body, program: M.World(), session: Session) -> Decision:
  open_panel(U.EditObject{U.owner(body)}, U.editor_trigger(U.owner(body)), Application{program, ensure(found, body, session)})

def open_editor(+body: U.Body, application: Application) -> Decision:
  Application{program, +session} = application
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer} = session
  open_editor_found(find_draft(drafts, U.owner(body)), body, program, session)

def edit_project(found: Maybe<&2, D.Project>, id: Maybe<&2, Nat>, application: Application) -> Decision:
  match found:
    case None{}: refuse(application, "The project no longer exists")
    case Some{D.Project{name, workspace, guidance}}: open_editor(U.Project{id, name, workspace}, application)

def project_editor(id: Maybe<&2, Nat>, +application: Application) -> Decision:
  match id:
    case None{}: open_editor(U.Project{None{}, "", D.Workspace{Nil{}, None{}}}, application)
    case Some{+id}:
      Application{program, session} = application
      edit_project(Projects.find(Projects.registry(F.State(), program), id), Some{id}, application)

def card_found(found: Maybe<&2, B.Card>, id: Nat, application: Application) -> Decision:
  match found:
    case None{}: refuse(application, "The card no longer exists")
    case Some{+card}:
      open_editor(U.Card{Some{id}, B.revision(card), B.draft(card), False{}, "", False{}}, application)

def board_card(board: B.State, +id: Nat, application: Application) -> Decision:
  cards = B.cards(board)
  card_found(Finite.find(~B.Card, cards, id), id, application)

def new_card_body(+stage: B.Stage) -> U.Body:
  U.Card{None{}, 0n, B.Draft{"", "", stage, B.NoPriority{}, B.Unassigned{}, None{}, Nil{}, Nil{}}, False{}, "", False{}}

def new_card(+stage: B.Stage, +application: Application) -> Decision:
  open_editor(new_card_body(stage), application)

def card_editor(id: Nat, +application: Application) -> Decision:
  Application{program, session} = application
  board_card(Board.registry(program), id, application)

def context_project(project: Maybe<&2, Nat>) -> Context.Origin:
  match project:
    case None{}: Context.EnvironmentDefaults{}
    case Some{id}: Context.ProjectDefaults{id}

def context_origin(value: J.Json) -> Context.Origin:
  match value:
    case J.Number{value}: context_project(Nat.read(value))
    case _: Context.EnvironmentDefaults{}

def context_workspace(value: J.Json) -> Maybe<&2, D.Workspace>:
  match value:
    case J.Null{}: None{}
    case other: Some{W.read_workspace(other, D.Workspace{Nil{}, None{}})}

def sandbox_result(result: Result<&2, &2, String, D.Sandbox>) -> Maybe<&2, D.Sandbox>:
  match result:
    case Fail{reason}: None{}
    case Done{value}: Some{value}

def context_sandbox(value: J.Json) -> Maybe<&2, D.Sandbox>:
  match value:
    case J.Null{}: None{}
    case other: sandbox_result(W.read_sandbox(other, D.Sandbox{D.WorkspaceWrite{}, False{}}))

def approval_mode(mode: String, value: J.Json) -> Maybe<&2, Context.ApprovalChoice>:
  match mode:
    case "full-access": Some{Context.Unrestricted{}}
    case "approval-for-me": Some{Context.AutomaticReview{J.text(J.get(value, "reviewer_profile"))}}
    case _: Some{Context.Ask{}}

def context_approval(+value: J.Json) -> Maybe<&2, Context.ApprovalChoice>:
  match value:
    case J.Null{}: None{}
    case +other: approval_mode(J.text(J.get(other, "mode")), other)

def context_from_settings(+settings: J.Json) -> Context.Configuration:
  Context.Configuration{context_origin(J.get(settings, "project_id")), context_workspace(J.get(settings, "workspace")),
    context_sandbox(J.get(settings, "sandbox")), context_approval(J.get(settings, "approval"))}

def agent_found(found: Maybe<&2, B.AgentProfile>, id: Nat, application: Application) -> Decision:
  match found:
    case None{}: refuse(application, "The agent profile no longer exists")
    case Some{+agent}:
      open_editor(U.Agent{Some{id}, B.agent_revision(agent), B.agent_name(agent), B.agent_profile(agent), B.agent_reasoning(agent), B.agent_instructions(agent), context_from_settings(B.agent_settings(agent)), B.agent_concurrency(agent)}, application)

def board_agent(board: B.State, +id: Nat, application: Application) -> Decision:
  agents = B.agents(board)
  agent_found(Finite.find(~B.AgentProfile, agents, id), id, application)

def new_agent(profile: Sigma<&2, &2, String, (_ => String)>, application: Application) -> Decision:
  (profile, reasoning) = profile
  open_editor(U.Agent{None{}, 0n, "", profile, reasoning, "", Context.defaults(Context.EnvironmentDefaults{}), 1n}, application)

def agent_editor(+application: Application, id: Maybe<&2, Nat>) -> Decision:
  Application{program, session} = application
  match id:
    case None{}: new_agent(first_profile(Board.profiles(program)), application)
    case Some{id}: board_agent(Board.registry(program), id, application)

def begin_changed(body: Result<&2, &2, String, U.Body>, revision: Nat, directory_entry: String, application: Application) -> Decision:
  match body:
    case Fail{reason}: refuse(application, reason)
    case Done{body}:
      Application{program, session} = application
      navigate_with_attention(U.Start{}, "composer/" ++ U.editor_key(U.NewTaskEditor{}), Application{program, with_draft(session, U.Draft{(revision + 1n : Nat), body, U.Editing{}, directory_entry})})

def begin_context_change(origin: Context.Origin, body: U.Body, revision: Nat, directory_entry: String, +application: Application) -> Decision:
  Application{program, session} = application
  begin_changed(U.apply_edit(U.ConfigureContext{Context.ChooseOrigin{origin}}, body, program), revision, directory_entry, application)

def begin_existing(found: Maybe<&2, U.Draft>, origin: Context.Origin, application: Application) -> Decision:
  match found:
    case None{}: navigate_with_attention(U.Start{}, "composer/" ++ U.editor_key(U.NewTaskEditor{}), application)
    case Some{U.Draft{revision, body, feedback, directory_entry}}:
      begin_context_change(origin, body, revision, directory_entry, application)

def begin_task(project: Maybe<&2, Nat>, application: Application) -> Decision:
  Application{program, +session} = application
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer} = session
  begin_existing(find_draft(drafts, U.NewTaskEditor{}), context_project(project), Application{program, session})

def busy(pending: +List<Pending>, +editor: U.Editor) -> Bool:
  match pending:
    case Nil{}: False{}
    case Con{Pending{ticket, U.Draft{revision, body, feedback, directory_entry}, now}, rest}:
      U.same_editor(U.owner(body), editor) || busy(rest, editor)

def settled_current(current: U.Draft, same: Bool, accepted: Bool, submitted: Nat, +result: J.Json) -> U.Draft:
  U.Draft{revision, body, feedback, directory_entry} = current
  match same accepted:
    case True{} True{}: U.Draft{(revision + 1n : Nat), U.after_accept(body), U.Accepted{submitted, result}, directory_entry}
    case False{} _: U.Draft{revision, body, feedback, directory_entry}
    case True{} False{}: U.Draft{revision, body, U.Rejected{submitted, J.text(J.get(J.get(result, "error"), "message"))}, directory_entry}

def settle_owned(owned: Bool, current: U.Draft, revision: Nat, +result: J.Json, session: Session) -> Session:
  match owned:
    case False{}: session
    case True{}: with_draft(session, settled_current(current, True{}, J.boolean(J.get(result, "ok")), revision, result))

def settle_found(found: Maybe<&2, U.Draft>, +revision: Nat, +result: J.Json, session: Session) -> Session:
  match found:
    case None{}: session
    case Some{U.Draft{+current, body, feedback, directory_entry}}:
      settle_owned(Nat.is_eq(current, revision), U.Draft{current, body, feedback, directory_entry}, revision, result, session)

def settle(submitted: U.Draft, +result: J.Json, +session: Session) -> Session:
  U.Draft{revision, body, feedback, directory_entry} = submitted
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer} = session
  settle_found(find_draft(drafts, U.owner(body)), revision, result, session)

def same_revision(found: Maybe<&2, U.Draft>, expected: Nat) -> Bool:
  match found:
    case None{}: False{}
    case Some{U.Draft{actual, body, feedback, directory_entry}}: Nat.is_eq(actual, expected)

def owns_submission(draft: U.Draft, session: Session) -> Bool:
  U.Draft{revision, body, feedback, directory_entry} = draft
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer} = session
  same_revision(find_draft(drafts, U.owner(body)), revision)

def follow_created(id: Maybe<&2, Nat>, application: Application) -> Decision:
  match id:
    case None{}: unchanged(application)
    case Some{id}: visit(U.Conversation{id}, application)

def finish_layer(same: Bool, application: Application) -> Decision:
  match same:
    case True{}: close_panel(application)
    case False{}: unchanged(application)

def finish_at_location(editor: U.Editor, route: U.Route, layers: +List<Layer>, result: J.Json, application: Application) -> Decision:
  match editor route layers:
    case U.NewTaskEditor{} U.Start{} _:
      follow_created(J.natural(J.get(J.get(result, "result"), "task_id")), application)
    case editor _ Con{Layer{U.EditObject{current}, trigger, initial, query, layer_occurrence}, rest}:
      finish_layer(U.same_editor(editor, current), application)
    case _ _ _: unchanged(application)

def capture_open(layers: +List<Layer>) -> Bool:
  match layers:
    case Con{Layer{U.EditObject{U.CardEditor{None{}}}, trigger, initial, query, layer_occurrence}, rest}: True{}
    case _: False{}

def capture_attention(open: Bool, application: Application) -> Decision:
  match open:
    case True{}:
      Application{program, session} = application
      local(program, session, [Attend{"card-title"}])
    case False{}: unchanged(application)

def continue_capture(+application: Application) -> Decision:
  Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}} = application
  capture_attention(capture_open(layers), application)

def finish_body(body: U.Body, route: U.Route, layers: +List<Layer>, result: J.Json, application: Application) -> Decision:
  match body:
    case U.Card{None{}, revision, value, assist, profile, True{}}:
      continue_capture(application)
    case other: finish_at_location(U.owner(other), route, layers, result, application)

def finish_submission(accepted_current: Bool, draft: U.Draft, result: J.Json, +application: Application) -> Decision:
  match accepted_current:
    case False{}: unchanged(application)
    case True{}:
      U.Draft{revision, body, feedback, directory_entry} = draft
      Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}} = application
      finish_body(body, route, layers, result, application)

def native_session(submitted: Maybe<&2, U.Draft>, program: M.World(), +result: J.Json,
  effects: +List<M.Effect()>, +session: Session, durable: Bool) -> Decision:
  match submitted:
    case None{}: with_native(unchanged(Application{program, session}), result, effects, durable)
    case Some{+draft}:
      with_native(finish_submission(J.boolean(J.get(result, "ok")) && owns_submission(draft, session), draft, result,
        Application{program, settle(draft, result, session)}), result, effects, durable)

def retain_previews(session: Session, world: M.World()) -> Session:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer} = session
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, Live.retained(previews, world), code_blocks, next_layer}
def native_result(decision: M.Decision(), session: Session, submitted: Maybe<&2, U.Draft>, durable: Bool) -> Decision:
  C.Decision{+program, +result, effects} = decision
  native_session(submitted, program, result, effects, retain_previews(session, program), durable)

def submission_completion(submitted: Maybe<&2, U.Draft>) -> Completion:
  match submitted:
    case None{}: DirectCompletion{}
    case Some{draft}: DraftCompletion{draft}

def request_command(command: M.Command, completion: Completion, application: Application) -> Decision:
  Decision{application, D.success(J.Null{}), Nil{}, [RequestCommand{command, completion}], False{}}

def execute(command: M.Command, application: Application, submitted: Maybe<&2, U.Draft>) -> Decision:
  request_command(command, submission_completion(submitted), application)

def execute_direct(command: Maybe<&2, M.Command>, application: Application) -> Decision:
  match command:
    case None{}: refuse(application, "This action requires an editor or a navigation transition")
    case Some{command}: execute(command, application, None{})

def prepare(application: Application, workspace: Maybe<&2, D.Workspace>, +draft: U.Draft) -> Decision:
  Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, +now, +next, pending, previews, code_blocks, next_layer}} = application
  match workspace:
    case None{}:
      U.Draft{revision, body, feedback, directory_entry} = draft
      execute(U.command(body, now), Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}}, Some{draft})
    case Some{workspace}:
      local(program, Session{route, drafts, readers, layers, attention, navigation, filter, now, (next + 1n : Nat),
        Pending{next, draft, now} <> pending, previews, code_blocks, next_layer}, [ObserveDirectories{next, workspace}])

def submit_ready(ready: Bool, +draft: U.Draft, application: Application) -> Decision:
  match ready:
    case False{}: refuse(application, "Submission is pending, composition is active, or the context origin or model selection is invalid")
    case True{}:
      U.Draft{revision, body, feedback, directory_entry} = draft
      prepare(application, U.required_workspace(body), draft)

def submit_found(found: Maybe<&2, U.Draft>, +application: Application) -> Decision:
  match found:
    case None{}: refuse(application, "The editor is not open")
    case Some{U.Draft{revision, +body, feedback, directory_entry}}:
      Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}} = application
      submit_ready(Bool.not(busy(pending, U.owner(body))) && U.valid_origin(body) && U.model_permitted(body, program),
        U.Draft{revision, body, feedback, directory_entry}, application)

def submit(editor: U.Editor, +application: Application) -> Decision:
  Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}} = application
  submit_found(find_draft(drafts, editor), application)

def select_pending(hit: Bool, pending: Pending, rest: Maybe<&2, Pending>) -> Maybe<&2, Pending>:
  match hit:
    case True{}: Some{pending}
    case False{}: rest

def find_pending(pending: +List<Pending>, +ticket: Nat) -> Maybe<&2, Pending>:
  match pending:
    case Nil{}: None{}
    case Con{Pending{+id, draft, now}, rest}: select_pending(Nat.is_eq(id, ticket), Pending{id, draft, now}, find_pending(rest, ticket))

def keep_pending(hit: Bool, pending: Pending, rest: +List<Pending>) -> +List<Pending>:
  match hit:
    case True{}: rest
    case False{}: pending <> rest

def without_pending(pending: +List<Pending>, +ticket: Nat) -> +List<Pending>:
  match pending:
    case Nil{}: Nil{}
    case Con{Pending{+id, draft, now}, rest}: keep_pending(Nat.is_eq(id, ticket), Pending{id, draft, now}, without_pending(rest, ticket))

def finish_preparation(ticket: Nat, application: Application) -> Application:
  Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}} = application
  Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, without_pending(pending, ticket), previews, code_blocks, next_layer}}

def preparation_failure(draft: U.Draft, reason: String, application: Application) -> Decision:
  Application{program, session} = application
  +result = D.failure("workspace_observation_failed", reason)
  Decision{Application{program, settle(draft, result, session)}, result, Nil{}, Nil{}, False{}}

def observed_valid(valid: Bool, observation: Context.DirectoryObservation, +draft: U.Draft, now: U32, application: Application) -> Decision:
  match valid:
    case False{}: preparation_failure(draft, "The directory observation does not satisfy the workspace contract", application)
    case True{}:
      U.Draft{revision, body, feedback, directory_entry} = draft
      execute(U.prepared_command(body, observation, now), application, Some{draft})

def observation_result(result: Result<&2, &2, String, Context.DirectoryObservation>, pending: Pending, application: Application) -> Decision:
  match result:
    case Fail{reason}:
      Pending{ticket, draft, now} = pending
      preparation_failure(draft, reason, finish_preparation(ticket, application))
    case Done{+observation}:
      Pending{ticket, draft, now} = pending
      observed_valid(Context.observation_valid(observation), observation, draft, now, finish_preparation(ticket, application))

def observed_pending(found: Maybe<&2, Pending>, result: Result<&2, &2, String, Context.DirectoryObservation>, application: Application) -> Decision:
  match found:
    case None{}: refuse(application, "The directory observation has no pending request")
    case Some{pending}: observation_result(result, pending, application)

def observed(ticket: Nat, result: Result<&2, &2, String, Context.DirectoryObservation>, +application: Application) -> Decision:
  Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}} = application
  observed_pending(find_pending(pending, ticket), result, application)


def confirmation_outcome(ok: Bool, destination: U.Route, application: Application) -> Decision:
  match ok:
    case True{}: navigate(destination, application)
    case False{}: unchanged(application)

def confirmation_owned(layers: +List<Layer>, +command: M.Command, +trigger: String, occurrence: Nat) -> Bool:
  match layers:
    case Con{Layer{U.Confirm{current, title, destination}, current_trigger, target, query, layer_occurrence}, rest}:
      Nat.is_eq(layer_occurrence, occurrence) && (String.eq(current_trigger, trigger) && J.same(CommandCodec.command_json(current), CommandCodec.command_json(command)))
    case _: False{}

def complete_confirmation(owned: Bool, +result: J.Json, destination: U.Route, application: Application) -> Decision:
  match owned:
    case False{}: reply(application, result)
    case True{}: with_native(confirmation_outcome(J.boolean(J.get(result, "ok")), destination, application), result, Nil{}, False{})

def observe_program(+program: M.World(), application: Application) -> Decision:
  Application{previous, session} = application
  unchanged(Application{program, retain_previews(session, program)})

def complete_command(+program: M.World(), result: J.Json, completion: Completion, application: Application) -> Decision:
  match completion:
    case DirectCompletion{}:
      Application{previous, session} = application
      native_session(None{}, program, result, Nil{}, retain_previews(session, program), False{})
    case DraftCompletion{draft}:
      Application{previous, session} = application
      native_session(Some{draft}, program, result, Nil{}, retain_previews(session, program), False{})
    case ConfirmationCompletion{command, trigger, destination, occurrence}:
      Application{previous, session} = application
      Session{route, drafts, readers, +layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer} = session
      complete_confirmation(confirmation_owned(layers, command, trigger, occurrence), result, destination,
        Application{program, retain_previews(session, program)})

def confirm(layers: +List<Layer>, application: Application) -> Decision:
  match layers:
    case Con{Layer{U.Confirm{+command, title, destination}, trigger, target, query, layer_occurrence}, rest}: request_command(command, ConfirmationCompletion{command, trigger, destination, layer_occurrence}, application)
    case _: refuse(application, "No confirmation is open")

def activate_selected(action: U.Action, +application: Application) -> Decision:
  match action:
    case U.SelectProject{project}: begin_task(project, application)
    case U.ToggleProjectGroup{project}: toggle_project(project, application)
    case U.Navigate{route}: visit(route, application)
    case U.BeginTask{+project}: begin_task(project, application)
    case U.EditProject{+project}: project_editor(project, application)
    case U.NewCard{stage}: new_card(stage, application)
    case U.EditCard{card}: card_editor(card, application)
    case U.EditAgent{agent}: agent_editor(application, agent)
    case U.ForkTask{+task}: open_editor(U.Fork{task, 1n, Nil{}, Context.defaults(Context.ParentTask{task})}, application)
    case U.CompactTask{task}: open_editor(U.Compact{task, None{}}, application)
    case U.Submit{editor}: submit(editor, application)
    case U.ControlTask{task, control}: execute_direct(U.direct_command(U.ControlTask{task, control}), application)
    case U.CancelOperation{task, operation}: execute_direct(U.direct_command(U.CancelOperation{task, operation}), application)
    case U.ReviewApproval{task, operation, allow, reason}: execute_direct(U.direct_command(U.ReviewApproval{task, operation, allow, reason}), application)
    case U.DeleteProject{+project}: open_panel(U.Confirm{M.DeleteProject{project}, "Delete project", U.ProjectCollection{}}, "project/delete/" ++ Nat.show(project), application)
    case U.BoardCommand{B.Delete{+id, revision}}:
      open_panel(U.Confirm{M.FeatureCommand{F.BoardCommand{B.Delete{id, revision}}}, "Delete card", U.TaskBoard{}}, "card/delete/" ++ Nat.show(id), application)
    case U.BoardCommand{command}: execute_direct(U.direct_command(U.BoardCommand{command}), application)
    case U.OpenPanel{panel, trigger}: open_panel(panel, trigger, application)
    case U.TogglePanel{panel, trigger}: toggle_panel(panel, trigger, application)
    case U.ClosePanel{}: close_panel(application)
    case U.ConfirmAction{}:
      Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}} = application
      confirm(layers, application)

def keep_disclosure(same: Bool, value: Disclosure, rest: +List<Disclosure>) -> +List<Disclosure>:
  match same:
    case True{}: rest
    case False{}: value <> rest
def without_disclosure(disclosures: +List<Disclosure>, +group: Nat) -> +List<Disclosure>:
  match disclosures:
    case Nil{}: Nil{}
    case Con{Disclosure{+current, occurrence, expanded}, rest}:
      keep_disclosure(Nat.is_eq(current, group), Disclosure{current, occurrence, expanded}, without_disclosure(rest, group))

def disclosed_reader(old: Reader, +group: Nat, occurrence: Nat, expanded: Bool) -> Reader:
  Reader{generation, position, disclosures} = old
  Reader{generation, position, Disclosure{group, occurrence, expanded} <> without_disclosure(disclosures, group)}

def disclose(+task: Nat, group: Nat, occurrence: Nat, expanded: Bool, application: Application) -> Decision:
  Application{program, Session{route, drafts, +readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}} = application
  local(program, Session{route, drafts, (task, disclosed_reader(reader(readers, task), group, occurrence, expanded)) <> Finite.remove(~Reader, readers, task),
    layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}, Nil{})


def navigation_focus(expanded: Bool) -> String:
  match expanded:
    case True{}: "new-task"
    case False{}: "navigation/toggle"
def search_choices(query: String, application: Application) -> Decision:
  Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}} = application
  match layers:
    case Nil{}: local(program, Session{route, drafts, readers, Nil{}, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}, Nil{})
    case Con{Layer{panel, trigger, initial, previous, layer_occurrence}, rest}:
      local(program, Session{route, drafts, readers, Layer{panel, trigger, initial, query, layer_occurrence} <> rest, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}, Nil{})

def action_leaves_menu(action: U.Action) -> Bool:
  match action:
    case U.OpenPanel{panel, trigger}: False{}
    case U.TogglePanel{panel, trigger}: False{}
    case U.ClosePanel{}: False{}
    case _: True{}

def remove_action_menu(layers: +List<Layer>) -> +List<Layer>:
  match layers:
    case Con{Layer{U.ObjectActions{subject}, trigger, initial, query, layer_occurrence}, rest}: rest
    case other: other

def dismiss_action_menu(leaves: Bool, application: Application) -> Application:
  match leaves:
    case False{}: application
    case True{}:
      Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}} = application
      Application{program, Session{route, drafts, readers, remove_action_menu(layers), attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}}

def activate(+action: U.Action, application: Application) -> Decision:
  activate_selected(action, dismiss_action_menu(action_leaves_menu(action), application))
def user(input: U.Input, application: Application) -> Decision:
  match input:
    case U.Activate{action}: activate(action, application)
    case U.EditDraft{+editor, +change}: close_selected_choice(change, editor, edit(editor, change, application))
    case U.ReadTimeline{task, generation, intent}: read_current(task, generation, intent, application)
    case U.SetDisclosure{task, group, occurrence, expanded}: disclose(task, group, occurrence, expanded, application)
    case U.SetNavigation{+expanded}:
      Application{program, Session{route, drafts, readers, layers, attention, previous, filter, now, next, pending, previews, code_blocks, next_layer}} = application
      +target = navigation_focus(expanded)
      local(program, Session{route, drafts, readers, layers, target, set_navigation(expanded, previous), filter, now, next, pending, previews, code_blocks, next_layer}, [Attend{target}])
    case U.SearchChoices{query}: search_choices(query, application)
    case U.FilterBoard{filter}:
      Application{program, Session{route, drafts, readers, layers, attention, navigation, previous, now, next, pending, previews, code_blocks, next_layer}} = application
      local(program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}, Nil{})


def observe_preview(observation: Live.Observation, application: Application) -> Decision:
  Application{+program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}} = application
  local(program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, Live.observe(observation, previews, program), code_blocks, next_layer}, Nil{})
def content_effects(effects: +List<Content.Effect>, +identity: Content.Identity) -> +List<Effect>:
  match effects:
    case Nil{}: Nil{}
    case Con{effect, rest}: ContentEffect{identity, effect} <> content_effects(rest, identity)

def content_result(result: Content.Decision, +identity: Content.Identity, application: Application) -> Decision:
  Content.Decision{block, effects} = result
  Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}} = application
  local(program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, Content.save_block(code_blocks, identity, block), next_layer}, content_effects(effects, identity))

def content_input(+identity: Content.Identity, input: Content.Input, application: Application) -> Decision:
  Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, +code_blocks, next_layer}} = application
  content_result(Content.step(Content.find_block(code_blocks, identity), input), identity,
    Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}})
