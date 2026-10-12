import ../experience/PROGRAM.bend as UX
import Base
import ../../harness/tasks/PROGRAM.bend as Tasks
import ../../harness/COMMANDS.bend as Commands
import ../../bendlib/categories.bend as Categories
import ../../harness/INVARIANTS.bend as I
import ../../bendlib/stdlib.bend as Std
import ../conversation/CODE.bend as Content
import ../conversation/OUTPUT.bend as Live
import ../../harness/MODEL.bend as M
import ../../harness/workspace/PROJECTS.bend as Projects
import ../../harness/workspace/WORKSPACE.bend as W
import ../../features/board/MODEL.bend as B
import ../../harness/features/MODEL.bend as F
import ../../harness/DOMAIN.bend as D
import ../../bendlib/component.bend as C
import ../../bendlib/association-map.bend as Finite
import ../../features/board/STATE.bend as Board
import ../../bendlib/json.bend as J
import ../../harness/transport/command-codec.bend as CommandCodec
import ../services/CONTEXT.bend as Context
import ../INPUT.bend as U

type Disclosure is Data:
  Disclosure{group: Nat, occurrence: Nat, expanded: Bool}

type Reader is Data:
  Reader{generation: Nat, position: U.ReadingIntent, disclosures: +List<Disclosure>}

type Layer is Data:
  Layer{panel: U.Panel, trigger: String, initial_attention: String, query: String, occurrence: Nat}

type Pending is Data:
  Pending{ticket: Nat, draft: U.Draft, now: U32}

type ModelPreference is Data:
  ModelPreference{profile: String, reasoning: String}

type NavigationIntent is Data:
  AutomaticNavigation{}
  OpenNavigation{}
  ClosedNavigation{}

type NavigationState is Data:
  NavigationState{intent: NavigationIntent, collapsed_projects: +List<Nat>}

# Execution and human participation form one system. Observations are projections
# of this value, not an independently supplied tree of enabled widgets.

type Session is Data:
  Session{route: U.Route, drafts: +List<U.Draft>, readers: +List<Finite.Entry(Reader)>,
    layers: +List<Layer>, attention: String, navigation: NavigationState, filter: B.Filter,
    now: U32, next_ticket: Nat, pending: +List<Pending>, previews: +List<Live.Output>, code_blocks: +List<Content.Block>, next_layer: Nat, model_preference: Maybe<&2, ModelPreference>, draft_model_manual: Bool}

type Application is Data:
  Application{program: M.World(), session: Session}

def program(state: Application) -> M.World():
  Application{program, session} = state
  program

def session(state: Application) -> Session:
  Application{program, session} = state
  session

def route(state: Session) -> U.Route:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual} = state
  route

def drafts(state: Session) -> +List<U.Draft>:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual} = state
  drafts

def readers(state: Session) -> +List<Finite.Entry(Reader)>:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual} = state
  readers

def layers(state: Session) -> +List<Layer>:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual} = state
  layers

def attention(state: Session) -> String:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual} = state
  attention

def navigation(state: Session) -> NavigationState:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual} = state
  navigation

def filter(state: Session) -> B.Filter:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual} = state
  filter

def now(state: Session) -> U32:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual} = state
  now

def next_ticket(state: Session) -> Nat:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual} = state
  next_ticket

def pending(state: Session) -> +List<Pending>:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual} = state
  pending

def previews(state: Session) -> +List<Live.Output>:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual} = state
  previews

def code_blocks(state: Session) -> +List<Content.Block>:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual} = state
  code_blocks

def next_layer(state: Session) -> Nat:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual} = state
  next_layer

def with_program(value: M.World(), state: Application) -> Application:
  Application{program, session} = state
  Application{value, session}

def with_session(value: Session, state: Application) -> Application:
  Application{program, session} = state
  Application{program, value}

def with_now(value: U32, state: Session) -> Session:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual} = state
  Session{route, drafts, readers, layers, attention, navigation, filter, value, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual}

def from_program(program: M.World(), session: Session) -> Application:
  Application{program, session}

def with_route(value: U.Route, state: Session) -> Session:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual} = state
  Session{value, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual}

def with_drafts(value: +List<U.Draft>, state: Session) -> Session:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual} = state
  Session{route, value, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual}

def with_layers(value: +List<Layer>, state: Session) -> Session:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual} = state
  Session{route, drafts, readers, value, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual}

def with_attention(value: String, state: Session) -> Session:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual} = state
  Session{route, drafts, readers, layers, value, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual}

def with_navigation(value: NavigationState, state: Session) -> Session:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual} = state
  Session{route, drafts, readers, layers, attention, value, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual}

def with_next_ticket(value: Nat, state: Session) -> Session:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual} = state
  Session{route, drafts, readers, layers, attention, navigation, filter, now, value, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual}

def with_pending(value: +List<Pending>, state: Session) -> Session:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual} = state
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, value, previews, code_blocks, next_layer, model_preference, draft_model_manual}

def with_next_layer(value: Nat, state: Session) -> Session:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual} = state
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, value, model_preference, draft_model_manual}

type Completion is Data:
  DirectCompletion{}
  DraftCompletion{draft: U.Draft}
  ExecutionCompletion{task: Nat, profile: String, reasoning: String, remember: Bool}
  ConfirmationCompletion{command: M.Command, trigger: String, destination: U.Route, occurrence: Nat}

type Effect is Data:
  RequestCommand{command: M.Command, completion: Completion}
  ContentEffect{identity: Content.Identity, effect: Content.Effect}
  ObserveDirectories{ticket: Nat, entered: D.Workspace}
  Attend{target: String}
  PersistModelPreference{profile: String, reasoning: String}

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
  ModelPreferenceRestored{profile: String, reasoning: String}

def first_valid_profile(+valid: Bool, +profile: D.Profile, +fallback: Sigma<&2, &2, String, (_ => String)>) -> Sigma<&2, &2, String, (_ => String)>:
  match valid profile:
    case True{} D.Profile{key, provider, name, policy, options}: (key, D.profile_default(D.Profile{key, provider, name, policy, options}))
    case False{} _: fallback

def first_profile(profiles: +List<D.Profile>) -> Sigma<&2, &2, String, (_ => String)>:
  match profiles:
    case Nil{}: ("", "")
    case Con{+profile, rest}: first_valid_profile(D.profile_valid(profile) && D.profile_permitted(profile, D.profile_default(profile)), profile, first_profile(rest))

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
      Session{route, drafts, readers, old, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual} = session
      local(program, Session{route, drafts, readers, rest, trigger, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual}, [Attend{trigger}])

def close_panel(application: Application) -> Decision:
  Application{program, +session} = application
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual} = session
  close_layers(layers, program, session)

def with_native(local: Decision, result: J.Json, effects: +List<M.Effect()>, durable: Bool) -> Decision:
  Decision{application, ignored_reply, ignored_runtime, interaction, ignored_durable} = local
  Decision{application, result, effects, interaction, durable}

type ChoiceCompletion is Data:
  ChoiceCompletion{editor: U.Editor, result: Decision}

def choice_owned(completion: ChoiceCompletion) -> Bool:
  ChoiceCompletion{editor, result} = completion
  Decision{Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual}}, reply, runtime, interaction, durable} = result
  J.boolean(J.get(reply, "ok")) && chooser_owns(layers, editor)

def owned_choice() -> ChoiceCompletion -> Type:
  Categories.holds(ChoiceCompletion, choice_owned)

def close_choice_value(result: Decision) -> Decision:
  Decision{application, reply, runtime, interaction, durable} = result
  with_native(close_panel(application), reply, runtime, durable)

def close_choice_owned(member: Categories.Membership<ChoiceCompletion, owned_choice()>) -> Decision:
  Categories.Membership{ChoiceCompletion{editor, result}, evidence} = member
  close_choice_value(result)

def choice_admitted(admitted: Maybe<&1, Categories.Membership<ChoiceCompletion, owned_choice()>>, result: Decision) -> Decision:
  match admitted:
    case None{}: result
    case Some{member}: close_choice_owned(member)

def close_choice(editor: U.Editor, +result: Decision) -> Decision:
  choice_admitted(Categories.admit(ChoiceCompletion, choice_owned, ChoiceCompletion{editor, result}), result)

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
    Nil{}, Nil{}, "composer/new-task", NavigationState{AutomaticNavigation{}, Nil{}}, B.empty_filter(), 0, 0n, Nil{}, Nil{}, Nil{}, 0n, None{}, False{}}}

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
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual} = session
  Session{route, put_draft(draft, drafts), readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual}

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

def edit_local(editor: U.Editor, change: U.Edit, application: Application) -> Decision:
  Application{program, +session} = application
  edit_found(find_draft(drafts(session), editor), change, program, session)

def found_task(program: M.World(), task: Nat) -> Maybe<&2, D.Task>:
  Tasks.find(Commands.entries(program), task)

def permitted_reviewer(found: Maybe<&2, D.Profile>) -> Bool:
  match found:
    case None{}: False{}
    case Some{profile}: D.profile_valid(profile)

def valid_task_change(+change: Maybe<&2, Context.Change>, +profiles: +List<D.Profile>) -> Bool:
  match change:
    case None{}: True{}
    case Some{Context.SetSandbox{sandbox}}: True{}
    case Some{Context.SetApproval{Context.AutomaticReview{key}}}: permitted_reviewer(D.find_profile(profiles, key))
    case Some{Context.SetApproval{choice}}: True{}
    case _: False{}

def reviewer_policy(found: Maybe<&2, D.Profile>, fallback: D.ApprovalPolicy) -> D.ApprovalPolicy:
  match found:
    case None{}: fallback
    case Some{profile}: D.ApprovalForMe{profile}

def chosen_approval(+choice: Context.ApprovalChoice, +profiles: +List<D.Profile>, +fallback: D.ApprovalPolicy) -> D.ApprovalPolicy:
  match choice:
    case Context.Ask{}: D.AskForApproval{}
    case Context.Unrestricted{}: D.FullAccess{}
    case Context.AutomaticReview{key}:
      reviewer_policy(D.find_profile(profiles, key), fallback)

def changed_policy(+change: Maybe<&2, Context.Change>, +sandbox: D.Sandbox, +approval: D.ApprovalPolicy, +profiles: +List<D.Profile>) -> Sigma<&2, &2, D.Sandbox, (_ => D.ApprovalPolicy)>:
  match change:
    case Some{Context.SetSandbox{value}}: (value, approval)
    case Some{Context.SetApproval{choice}}: (sandbox, chosen_approval(choice, profiles, approval))
    case _: (sandbox, approval)

def request_command(command: M.Command, completion: Completion, application: Application) -> Decision:
  Decision{application, D.success(J.Null{}), Nil{}, [RequestCommand{command, completion}], False{}}

def request_execution_resolved(+resolved: Commands.Operation, +command: M.Command, +completion: Completion, +application: Application) -> Decision:
  match resolved:
    case Commands.Refuse{code, message}: refuse(application, message)
    case _: request_command(command, completion, application)

def request_execution(+command: M.Command, +completion: Completion, +application: Application) -> Decision:
  request_execution_resolved(Commands.resolve(command, program(application)), command, completion, application)

def configure_selected(+remember: Bool, +sandbox: D.Sandbox, +approval: D.ApprovalPolicy, +task: Nat, +profile: String, +reasoning: String, +current_profile: String, +current_reasoning: String, +application: Application) -> Decision:
  match remember:
    case True{}: request_execution(M.ConfigureTaskExecution{task, profile, reasoning, sandbox, approval}, ExecutionCompletion{task, profile, reasoning, True{}}, application)
    case False{}: request_execution(M.ConfigureTaskExecution{task, current_profile, current_reasoning, sandbox, approval}, ExecutionCompletion{task, current_profile, current_reasoning, False{}}, application)

def configure_policy(+policy: Sigma<&2, &2, D.Sandbox, (_ => D.ApprovalPolicy)>, +task: Nat, +profile: String, +reasoning: String, +current_profile: String, +current_reasoning: String, +remember: Bool, +application: Application) -> Decision:
  (sandbox, approval) = policy
  configure_selected(remember, sandbox, approval, task, profile, reasoning, current_profile, current_reasoning, application)

def configure_current(+current: D.ExecutionConfiguration, +task: Nat, +profile: String, +reasoning: String, +change: Maybe<&2, Context.Change>, +remember: Bool, +application: Application) -> Decision:
  D.ExecutionConfiguration{current_profile, current_reasoning, model, sandbox, approval} = current
  +world = program(application)
  configure_policy(changed_policy(change, sandbox, approval, Board.profiles(world)), task, profile, reasoning, current_profile, current_reasoning, remember, application)

def configure_checked(+valid: Bool, +current: D.ExecutionConfiguration, +task: Nat, +profile: String, +reasoning: String, +change: Maybe<&2, Context.Change>, +remember: Bool, +application: Application) -> Decision:
  match valid:
    case False{}: refuse(application, "Task configuration changes require valid execution settings and cannot change workspace or project")
    case True{}: configure_current(current, task, profile, reasoning, change, remember, application)
def configure_task(+found: Maybe<&2, D.Task>, +task: Nat, +profile: String, +reasoning: String, +change: Maybe<&2, Context.Change>, +remember: Bool, +application: Application) -> Decision:
  match found:
    case None{}: refuse(application, "The task no longer exists")
    case Some{value}: configure_checked(valid_task_change(change, Board.profiles(program(application))), D.task_execution(value), task, profile, reasoning, change, remember, application)

def edit(+editor: U.Editor, change: U.Edit, +application: Application) -> Decision:
  match editor change:
    case U.MessageEditor{+task} U.ChooseModel{profile, reasoning}: configure_task(found_task(program(application), task), task, profile, reasoning, None{}, True{}, application)
    case U.MessageEditor{+task} U.ConfigureContext{change}: configure_task(found_task(program(application), task), task, "", "", Some{change}, False{}, application)
    case _ other: edit_local(editor, other, application)

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
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual} = session
  local(program, Session{route, drafts, (task, Reader{generation, position, disclosures}) <> Finite.remove(~Reader, readers, task),
    layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual}, Nil{})

def read(+task: Nat, intent: U.ReadingIntent, application: Application) -> Decision:
  Application{program, +session} = application
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual} = session
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
  Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code, next_layer, model_preference, draft_model_manual}} = application
  local(program, Session{route, drafts, readers, layers, attention, toggle_project_navigation(id, navigation), filter, now, next, pending, previews, code, next_layer, model_preference, draft_model_manual}, Nil{})

def new_visit(reader: Reader) -> Reader:
  Reader{generation, position, disclosures} = reader
  Reader{(generation + 1n : Nat), position, disclosures}

def visit_readers(route: U.Route, +readers: +List<Finite.Entry(Reader)>) -> +List<Finite.Entry(Reader)>:
  match route:
    case U.Conversation{+task}: (task, new_visit(reader(readers, task))) <> Finite.remove(~Reader, readers, task)
    case _: readers

def navigate_with_attention(+route: U.Route, +target: String, application: Application) -> Decision:
  Application{program, Session{old, drafts, +readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual}} = application
  +current_readers = visit_readers(route, readers)
  local(program, Session{route, drafts, current_readers, Nil{}, target, navigation_after_visit(navigation), filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual},
    [Attend{target}])

def navigate(route: U.Route, application: Application) -> Decision:
  navigate_with_attention(route, "page-heading", application)

def reader_generation(reader: Reader) -> Nat:
  Reader{generation, position, disclosures} = reader
  generation

type ReadingRequest is Data:
  ReadingRequest{task: Nat, generation: Nat, intent: U.ReadingIntent, application: Application}

def reading_owned(request: ReadingRequest) -> Bool:
  ReadingRequest{+task, generation, intent, Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual}}} = request
  U.route_owns(route, task) && Nat.is_eq(generation, reader_generation(reader(readers, task)))

def owned_reading() -> ReadingRequest -> Type:
  Categories.holds(ReadingRequest, reading_owned)

def read_owned(member: Categories.Membership<ReadingRequest, owned_reading()>) -> Decision:
  Categories.Membership{ReadingRequest{task, generation, intent, application}, evidence} = member
  read(task, intent, application)

def reading_admitted(admitted: Maybe<&1, Categories.Membership<ReadingRequest, owned_reading()>>, application: Application) -> Decision:
  match admitted:
    case None{}: unchanged(application)
    case Some{member}: read_owned(member)

def read_current(task: Nat, generation: Nat, intent: U.ReadingIntent, +application: Application) -> Decision:
  reading_admitted(Categories.admit(ReadingRequest, reading_owned, ReadingRequest{task, generation, intent, application}), application)

def ensure(found: Maybe<&2, U.Draft>, fallback: U.Body, session: Session) -> Session:
  match found:
    case Some{U.Draft{revision, body, U.Accepted{submitted, result}, directory_entry}}: with_draft(session, U.Draft{(revision + 1n : Nat), fallback, U.Editing{}, ""})
    case Some{draft}: session
    case None{}: with_draft(session, U.Draft{0n, fallback, U.Editing{}, ""})

def visit(route: U.Route, application: Application) -> Decision:
  match route:
    case U.Conversation{+task}:
      Application{program, +session} = application
      Session{old, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual} = session
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
  Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, +next_layer, model_preference, draft_model_manual}} = application
  +target = panel_target(panel)
  local(program, Session{route, drafts, readers, Layer{panel, trigger, target, "", next_layer} <> without_panel(layers, panel_target(panel)),
    target, navigation, filter, now, next, pending, previews, code_blocks, (next_layer + 1n : Nat), model_preference, draft_model_manual}, [Attend{target}])

def panel_present(layers: +List<Layer>, +target: String) -> Bool:
  match layers:
    case Nil{}: False{}
    case Con{Layer{panel, trigger, initial, query, layer_occurrence}, rest}:
      String.eq(panel_target(panel), target) || panel_present(rest, target)

def toggle_panel_selected(present: Bool, +panel: U.Panel, +trigger: String, application: Application) -> Decision:
  match present:
    case False{}: open_panel(panel, trigger, application)
    case True{}:
      Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual}} = application
      local(program, Session{route, drafts, readers, without_panel(layers, panel_target(panel)), trigger,
        navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual}, [Attend{trigger}])

def toggle_panel(+panel: U.Panel, trigger: String, application: Application) -> Decision:
  Application{program, Session{route, drafts, readers, +layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual}} = application
  toggle_panel_selected(panel_present(layers, panel_target(panel)), panel, trigger,
    Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual}})

def open_editor_found(found: Maybe<&2, U.Draft>, +body: U.Body, program: M.World(), session: Session) -> Decision:
  open_panel(U.EditObject{U.owner(body)}, U.editor_trigger(U.owner(body)), Application{program, ensure(found, body, session)})

def open_editor(+body: U.Body, application: Application) -> Decision:
  Application{program, +session} = application
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual} = session
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

def permitted_preference(found: Maybe<&2, D.Profile>, reasoning: String) -> Bool:
  match found:
    case None{}: False{}
    case Some{profile}: D.profile_permitted(profile, reasoning)

def preference(session: Session) -> Maybe<&2, ModelPreference>:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual} = session
  model_preference

def valid_preference(value: ModelPreference, profiles: +List<D.Profile>) -> Bool:
  ModelPreference{profile, reasoning} = value
  permitted_preference(D.find_profile(profiles, profile), reasoning)

def preferred_if(+valid: Bool, +value: ModelPreference, +profiles: +List<D.Profile>) -> Sigma<&2, &2, String, (_ => String)>:
  match valid value:
    case True{} ModelPreference{profile, reasoning}: (profile, reasoning)
    case False{} _: first_profile(profiles)

def preferred_selection(+value: Maybe<&2, ModelPreference>, +profiles: +List<D.Profile>) -> Sigma<&2, &2, String, (_ => String)>:
  match value:
    case None{}: first_profile(profiles)
    case Some{+selection}: preferred_if(valid_preference(selection, profiles), selection, profiles)

def resolved_model_selection(+selection: Sigma<&2, &2, String, (_ => String)>, +revision: Nat, +message: U.Text, +context: Context.Configuration, +feedback: U.Feedback, +directory_entry: String, +session: Session) -> Session:
  (selected, effort) = selection
  with_draft(session, U.Draft{revision, U.NewTask{message, selected, effort, context}, feedback, directory_entry})

def resolve_model_valid(+valid: Bool, +draft: U.Draft, +profiles: +List<D.Profile>, +session: Session) -> Session:
  match valid draft:
    case False{} U.Draft{revision, U.NewTask{message, profile, reasoning, context}, feedback, directory_entry}:
      resolved_model_selection(preferred_selection(preference(session), profiles), revision, message, context, feedback, directory_entry, session)
    case _ _: session

def manual_model(session: Session) -> Bool:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual} = session
  draft_model_manual

def resolve_model_found(+found: Maybe<&2, U.Draft>, +profiles: +List<D.Profile>, +session: Session) -> Session:
  match found:
    case Some{U.Draft{revision, U.NewTask{message, +profile, +reasoning, context}, feedback, directory_entry}}:
      resolve_model_valid(manual_model(session) && permitted_preference(D.find_profile(profiles, profile), reasoning), U.Draft{revision, U.NewTask{message, profile, reasoning, context}, feedback, directory_entry}, profiles, session)
    case _: session

def resolve_model_draft(+session: Session, +program: M.World()) -> Session:
  resolve_model_found(find_draft(drafts(session), U.NewTaskEditor{}), Board.profiles(program), session)

def begin_resolved(+origin: Context.Origin, +program: M.World(), +session: Session) -> Decision:
  begin_existing(find_draft(drafts(session), U.NewTaskEditor{}), origin, Application{program, session})


def begin_task(project: Maybe<&2, Nat>, application: Application) -> Decision:
  Application{+program, +session} = application
  begin_resolved(context_project(project), program, resolve_model_draft(session, program))

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

type Settlement is Data:
  Settlement{current: U.Draft, revision: Nat, result: J.Json, session: Session}

def settlement_owned(settlement: Settlement) -> Bool:
  Settlement{U.Draft{current, body, feedback, directory_entry}, revision, result, session} = settlement
  Nat.is_eq(current, revision)

def owned_settlement() -> Settlement -> Type:
  Categories.holds(Settlement, settlement_owned)

def settle_value(current: U.Draft, revision: Nat, +result: J.Json, session: Session) -> Session:
  with_draft(session, settled_current(current, True{}, J.boolean(J.get(result, "ok")), revision, result))

def settle_owned(member: Categories.Membership<Settlement, owned_settlement()>) -> Session:
  Categories.Membership{Settlement{current, revision, result, session}, evidence} = member
  settle_value(current, revision, result, session)

def settlement_admitted(admitted: Maybe<&1, Categories.Membership<Settlement, owned_settlement()>>, session: Session) -> Session:
  match admitted:
    case None{}: session
    case Some{member}: settle_owned(member)

def settle_found(found: Maybe<&2, U.Draft>, revision: Nat, result: J.Json, +session: Session) -> Session:
  match found:
    case None{}: session
    case Some{current}: settlement_admitted(Categories.admit(Settlement, settlement_owned, Settlement{current, revision, result, session}), session)

def settle(submitted: U.Draft, +result: J.Json, +session: Session) -> Session:
  U.Draft{revision, body, feedback, directory_entry} = submitted
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual} = session
  settle_found(find_draft(drafts, U.owner(body)), revision, result, session)

def same_revision(found: Maybe<&2, U.Draft>, expected: Nat) -> Bool:
  match found:
    case None{}: False{}
    case Some{U.Draft{actual, body, feedback, directory_entry}}: Nat.is_eq(actual, expected)

def owns_submission(draft: U.Draft, session: Session) -> Bool:
  U.Draft{revision, body, feedback, directory_entry} = draft
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual} = session
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
  Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual}} = application
  capture_attention(capture_open(layers), application)

def with_manual_model(value: Bool, session: Session) -> Session:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, previous} = session
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, value}

def finish_fresh_task(+route: U.Route, +layers: +List<Layer>, +result: J.Json, +application: Application) -> Decision:
  Application{program, session} = application
  finish_at_location(U.NewTaskEditor{}, route, layers, result, Application{program, with_manual_model(False{}, session)})


def finish_body(body: U.Body, route: U.Route, layers: +List<Layer>, result: J.Json, application: Application) -> Decision:
  match body:
    case U.NewTask{message, profile, reasoning, context}: finish_fresh_task(route, layers, result, application)
    case U.Card{None{}, revision, value, assist, profile, True{}}:
      continue_capture(application)
    case other: finish_at_location(U.owner(other), route, layers, result, application)

type SubmissionCompletion is Data:
  SubmissionCompletion{draft: U.Draft, result: J.Json, previous_session: Session, application: Application}

def submission_accepted(completion: SubmissionCompletion) -> Bool:
  SubmissionCompletion{draft, +result, previous_session, application} = completion
  J.boolean(J.get(result, "ok")) && owns_submission(draft, previous_session)

def accepted_submission() -> SubmissionCompletion -> Type:
  Categories.holds(SubmissionCompletion, submission_accepted)

def finish_submission_value(draft: U.Draft, result: J.Json, +application: Application) -> Decision:
  U.Draft{revision, body, feedback, directory_entry} = draft
  Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual}} = application
  finish_body(body, route, layers, result, application)

def finish_submission(member: Categories.Membership<SubmissionCompletion, accepted_submission()>) -> Decision:
  Categories.Membership{SubmissionCompletion{draft, result, previous_session, application}, evidence} = member
  finish_submission_value(draft, result, application)

def submission_admitted(admitted: Maybe<&1, Categories.Membership<SubmissionCompletion, accepted_submission()>>, application: Application) -> Decision:
  match admitted:
    case None{}: unchanged(application)
    case Some{member}: finish_submission(member)

def finish_submission_current(+draft: U.Draft, +result: J.Json, previous_session: Session, +application: Application) -> Decision:
  submission_admitted(Categories.admit(SubmissionCompletion, submission_accepted, SubmissionCompletion{draft, result, previous_session, application}), application)

def native_session(submitted: Maybe<&2, U.Draft>, program: M.World(), +result: J.Json,
  effects: +List<M.Effect()>, +session: Session, durable: Bool) -> Decision:
  match submitted:
    case None{}: with_native(unchanged(Application{program, session}), result, effects, durable)
    case Some{+draft}:
      with_native(finish_submission_current(draft, result, session,
        Application{program, settle(draft, result, session)}), result, effects, durable)

def retain_previews(session: Session, world: M.World()) -> Session:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual} = session
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, Live.retained(previews, world), code_blocks, next_layer, model_preference, draft_model_manual}

def native_result(decision: M.Decision(), session: Session, submitted: Maybe<&2, U.Draft>, durable: Bool) -> Decision:
  C.Decision{+program, +result, effects} = decision
  native_session(submitted, program, result, effects, retain_previews(session, program), durable)

def submission_completion(submitted: Maybe<&2, U.Draft>) -> Completion:
  match submitted:
    case None{}: DirectCompletion{}
    case Some{draft}: DraftCompletion{draft}

def execute(command: M.Command, application: Application, submitted: Maybe<&2, U.Draft>) -> Decision:
  request_command(command, submission_completion(submitted), application)

def execute_direct(command: Maybe<&2, M.Command>, application: Application) -> Decision:
  match command:
    case None{}: refuse(application, "This action requires an editor or a navigation transition")
    case Some{command}: execute(command, application, None{})

def prepare(application: Application, workspace: Maybe<&2, D.Workspace>, +draft: U.Draft) -> Decision:
  Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, +now, +next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual}} = application
  match workspace:
    case None{}:
      U.Draft{revision, body, feedback, directory_entry} = draft
      execute(U.command(body, now), Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual}}, Some{draft})
    case Some{workspace}:
      local(program, Session{route, drafts, readers, layers, attention, navigation, filter, now, (next + 1n : Nat),
        Pending{next, draft, now} <> pending, previews, code_blocks, next_layer, model_preference, draft_model_manual}, [ObserveDirectories{next, workspace}])

def submission_ready(+pending: +List<Pending>, +program: M.World(), draft: U.Draft) -> Bool:
  U.Draft{revision, +body, feedback, directory_entry} = draft
  UX.can_prepare(body, busy(pending, U.owner(body)), program)

def ready_submission(+pending: +List<Pending>, +program: M.World()) -> U.Draft -> Type:
  Categories.holds(U.Draft, (draft => submission_ready(pending, program, draft)))

def submit_ready(+pending: +List<Pending>, +program: M.World(), member: Categories.Membership<U.Draft, ready_submission(pending, program)>, application: Application) -> Decision:
  Categories.Membership{+draft, evidence} = member
  U.Draft{revision, body, feedback, directory_entry} = draft
  prepare(application, U.required_workspace(body), draft)

def submission_refusal(+pending: +List<Pending>, +program: M.World(), candidate: U.Draft, +application: Application) -> Decision:
  U.Draft{revision, +body, feedback, directory_entry} = candidate
  +now = now(session(application))
  refuse(application, UX.assessment_reason(UX.assessed_requirements(UX.requirements(body, busy(pending, U.owner(body)), program), body, revision, now, program)))

def submit_admitted(+pending: +List<Pending>, +program: M.World(), candidate: U.Draft, admitted: Maybe<&1, Categories.Membership<U.Draft, ready_submission(pending, program)>>, application: Application) -> Decision:
  match admitted:
    case None{}: submission_refusal(pending, program, candidate, application)
    case Some{member}: submit_ready(pending, program, member, application)

def submit_found(found: Maybe<&2, U.Draft>, +application: Application) -> Decision:
  match found:
    case None{}: refuse(application, "The editor is not open")
    case Some{+draft}:
      Application{+program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, +pending, previews, code_blocks, next_layer, model_preference, draft_model_manual}} = application
      submit_admitted(pending, program, draft, Categories.admit(U.Draft, (draft => submission_ready(pending, program, draft)), draft), application)

def submit(editor: U.Editor, +application: Application) -> Decision:
  Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual}} = application
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
  Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual}} = application
  Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, without_pending(pending, ticket), previews, code_blocks, next_layer, model_preference, draft_model_manual}}

def preparation_failure(draft: U.Draft, reason: String, application: Application) -> Decision:
  Application{program, session} = application
  +result = D.failure("workspace_observation_failed", reason)
  Decision{Application{program, settle(draft, result, session)}, result, Nil{}, Nil{}, False{}}

def directory_observation() -> Context.DirectoryObservation -> Type:
  Categories.holds(Context.DirectoryObservation, Context.observation_valid)

def observed_valid(member: Categories.Membership<Context.DirectoryObservation, directory_observation()>, +draft: U.Draft, now: U32, application: Application) -> Decision:
  Categories.Membership{observation, evidence} = member
  U.Draft{revision, body, feedback, directory_entry} = draft
  execute(U.prepared_command(body, observation, now), application, Some{draft})

def observation_admitted(admitted: Maybe<&1, Categories.Membership<Context.DirectoryObservation, directory_observation()>>, draft: U.Draft, now: U32, application: Application) -> Decision:
  match admitted:
    case None{}: preparation_failure(draft, "The directory observation does not satisfy the workspace contract", application)
    case Some{member}: observed_valid(member, draft, now, application)

def observation_result(result: Result<&2, &2, String, Context.DirectoryObservation>, pending: Pending, application: Application) -> Decision:
  match result:
    case Fail{reason}:
      Pending{ticket, draft, now} = pending
      preparation_failure(draft, reason, finish_preparation(ticket, application))
    case Done{+observation}:
      Pending{ticket, draft, now} = pending
      observation_admitted(Categories.admit(Context.DirectoryObservation, Context.observation_valid, observation), draft, now, finish_preparation(ticket, application))

def observed_pending(found: Maybe<&2, Pending>, result: Result<&2, &2, String, Context.DirectoryObservation>, application: Application) -> Decision:
  match found:
    case None{}: refuse(application, "The directory observation has no pending request")
    case Some{pending}: observation_result(result, pending, application)

def observed(ticket: Nat, result: Result<&2, &2, String, Context.DirectoryObservation>, +application: Application) -> Decision:
  Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual}} = application
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

type ConfirmationReceipt is Data:
  ConfirmationReceipt{command: M.Command, trigger: String, occurrence: Nat, result: J.Json, destination: U.Route, application: Application}

def receipt_owned(receipt: ConfirmationReceipt) -> Bool:
  ConfirmationReceipt{command, trigger, occurrence, result, destination, Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual}}} = receipt
  confirmation_owned(layers, command, trigger, occurrence)

def owned_confirmation() -> ConfirmationReceipt -> Type:
  Categories.holds(ConfirmationReceipt, receipt_owned)

def complete_confirmation_value(+result: J.Json, destination: U.Route, application: Application) -> Decision:
  with_native(confirmation_outcome(J.boolean(J.get(result, "ok")), destination, application), result, Nil{}, False{})

def complete_confirmation(member: Categories.Membership<ConfirmationReceipt, owned_confirmation()>) -> Decision:
  Categories.Membership{ConfirmationReceipt{command, trigger, occurrence, result, destination, application}, evidence} = member
  complete_confirmation_value(result, destination, application)

def confirmation_admitted(admitted: Maybe<&1, Categories.Membership<ConfirmationReceipt, owned_confirmation()>>, result: J.Json, application: Application) -> Decision:
  match admitted:
    case None{}: reply(application, result)
    case Some{member}: complete_confirmation(member)

def complete_confirmation_current(command: M.Command, trigger: String, occurrence: Nat, +result: J.Json, destination: U.Route, +application: Application) -> Decision:
  confirmation_admitted(Categories.admit(ConfirmationReceipt, receipt_owned, ConfirmationReceipt{command, trigger, occurrence, result, destination, application}), result, application)

def program_world() -> M.World() -> Type:
  Categories.holds(M.World(), (world => I.world(world)))

def observe_program_member(member: Categories.Membership<M.World(), program_world()>, application: Application) -> Decision:
  Categories.Membership{+program, evidence} = member
  Application{previous, session} = application
  unchanged(Application{program, resolve_model_draft(retain_previews(session, program), program)})

def observe_program_admitted(admitted: Maybe<&1, Categories.Membership<M.World(), program_world()>>, application: Application) -> Decision:
  match admitted:
    case None{}: refuse(application, "The observed program violates a world invariant")
    case Some{member}: observe_program_member(member, application)

def observe_program(program: M.World(), application: Application) -> Decision:
  observe_program_admitted(Categories.admit(M.World(), (world => I.world(world)), program), application)

def with_preference(value: Maybe<&2, ModelPreference>, session: Session) -> Session:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, previous, draft_model_manual} = session
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, value, draft_model_manual}

def remember_valid(+valid: Bool, +profile: String, +reasoning: String, +result: Decision) -> Decision:
  match valid result:
    case False{} other: other
    case True{} Decision{Application{program, session}, reply, runtime, interaction, durable}: Decision{Application{program, with_preference(Some{ModelPreference{profile, reasoning}}, session)}, reply, runtime, PersistModelPreference{profile, reasoning} <> interaction, durable}

def remember_choice(+change: U.Edit, +result: Decision) -> Decision:
  match change:
    case U.ChooseModel{+profile, +reasoning}:
      Decision{Application{+program, session}, +reply, runtime, interaction, durable} = result
      remember_valid(J.boolean(J.get(reply, "ok")) && permitted_preference(D.find_profile(Board.profiles(program), profile), reasoning), profile, reasoning, Decision{Application{program, session}, reply, runtime, interaction, durable})
    case _: result

def finish_execution_session(+ok: Bool, +task: Nat, +profile: String, +reasoning: String, +remember: Bool, +program: M.World(), +result: J.Json, +session: Session) -> Decision:
  match ok remember:
    case True{} True{}: remember_choice(U.ChooseModel{profile, reasoning}, with_native(close_panel(Application{program, session}), result, Nil{}, False{}))
    case True{} False{}: with_native(close_panel(Application{program, session}), result, Nil{}, False{})
    case False{} _: reply(Application{program, session}, result)

def finish_execution(ok: Bool, task: Nat, profile: String, reasoning: String, remember: Bool, program: M.World(), result: J.Json, application: Application) -> Decision:
  Application{previous, session} = application
  finish_execution_session(ok, task, profile, reasoning, remember, program, result, session)

def complete_command_member(member: Categories.Membership<M.World(), program_world()>, +result: J.Json, completion: Completion, application: Application) -> Decision:
  Categories.Membership{+program, evidence} = member
  match completion:
    case ExecutionCompletion{task, profile, reasoning, remember}: finish_execution(J.boolean(J.get(result, "ok")), task, profile, reasoning, remember, program, result, application)
    case DirectCompletion{}:
      Application{previous, session} = application
      native_session(None{}, program, result, Nil{}, retain_previews(session, program), False{})
    case DraftCompletion{draft}:
      Application{previous, session} = application
      native_session(Some{draft}, program, result, Nil{}, retain_previews(session, program), False{})
    case ConfirmationCompletion{command, trigger, destination, occurrence}:
      Application{previous, session} = application
      Session{route, drafts, readers, +layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual} = session
      complete_confirmation_current(command, trigger, occurrence, result, destination,
        Application{program, retain_previews(session, program)})

def complete_command_admitted(admitted: Maybe<&1, Categories.Membership<M.World(), program_world()>>, result: J.Json, completion: Completion, application: Application) -> Decision:
  match admitted:
    case None{}: refuse(application, "The observed program violates a world invariant")
    case Some{member}: complete_command_member(member, result, completion, application)

def complete_command(program: M.World(), result: J.Json, completion: Completion, application: Application) -> Decision:
  complete_command_admitted(Categories.admit(M.World(), (world => I.world(world)), program), result, completion, application)

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
      Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual}} = application
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
  Application{program, Session{route, drafts, +readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual}} = application
  local(program, Session{route, drafts, (task, disclosed_reader(reader(readers, task), group, occurrence, expanded)) <> Finite.remove(~Reader, readers, task),
    layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual}, Nil{})

def navigation_focus(expanded: Bool) -> String:
  match expanded:
    case True{}: "new-task"
    case False{}: "navigation/toggle"

def search_choices(query: String, application: Application) -> Decision:
  Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual}} = application
  match layers:
    case Nil{}: local(program, Session{route, drafts, readers, Nil{}, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual}, Nil{})
    case Con{Layer{panel, trigger, initial, previous, layer_occurrence}, rest}:
      local(program, Session{route, drafts, readers, Layer{panel, trigger, initial, query, layer_occurrence} <> rest, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual}, Nil{})

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
      Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual}} = application
      Application{program, Session{route, drafts, readers, remove_action_menu(layers), attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual}}

def activate(+action: U.Action, application: Application) -> Decision:
  activate_selected(action, dismiss_action_menu(action_leaves_menu(action), application))

def mark_manual_choice(valid: Bool, result: Decision) -> Decision:
  match valid result:
    case True{} Decision{Application{program, session}, reply, runtime, interaction, durable}: Decision{Application{program, with_manual_model(True{}, session)}, reply, runtime, interaction, durable}
    case False{} other: other

def remember_manual(+change: U.Edit, +result: Decision) -> Decision:
  match change:
    case U.ChooseModel{profile, reasoning}:
      Decision{application, +reply, runtime, interaction, durable} = result
      mark_manual_choice(J.boolean(J.get(reply, "ok")) && permitted_preference(D.find_profile(Board.profiles(program(application)), profile), reasoning), remember_choice(U.ChooseModel{profile, reasoning}, Decision{application, reply, runtime, interaction, durable}))
    case _: result


def permitted_creation_edit(change: U.Edit, world: M.World()) -> Bool:
  match change:
    case U.ChooseModel{profile, reasoning}: permitted_preference(D.find_profile(Board.profiles(world), profile), reasoning)
    case _: True{}

def manual_creation_edit(valid: Bool, +change: U.Edit, application: Application) -> Decision:
  match valid:
    case True{}: remember_manual(change, close_selected_choice(change, U.NewTaskEditor{}, edit(U.NewTaskEditor{}, change, application)))
    case False{}: reply(application, D.failure("interaction_refused", "Choose an available model and permitted reasoning effort."))

def manual_edit(+editor: U.Editor, +change: U.Edit, +application: Application) -> Decision:
  match editor:
    case U.MessageEditor{task}: edit(editor, change, application)
    case U.NewTaskEditor{}: manual_creation_edit(permitted_creation_edit(change, program(application)), change, application)
    case _: close_selected_choice(change, editor, edit(editor, change, application))


def user(input: U.Input, application: Application) -> Decision:
  match input:
    case U.Activate{action}: activate(action, application)
    case U.EditDraft{+editor, +change}: manual_edit(editor, change, application)
    case U.ReadTimeline{task, generation, intent}: read_current(task, generation, intent, application)
    case U.SetDisclosure{task, group, occurrence, expanded}: disclose(task, group, occurrence, expanded, application)
    case U.SetNavigation{+expanded}:
      Application{program, Session{route, drafts, readers, layers, attention, previous, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual}} = application
      +target = navigation_focus(expanded)
      local(program, Session{route, drafts, readers, layers, target, set_navigation(expanded, previous), filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual}, [Attend{target}])
    case U.SearchChoices{query}: search_choices(query, application)
    case U.FilterBoard{filter}:
      Application{program, Session{route, drafts, readers, layers, attention, navigation, previous, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual}} = application
      local(program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual}, Nil{})

def observe_preview(observation: Live.Observation, application: Application) -> Decision:
  Application{+program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual}} = application
  local(program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, Live.observe(observation, previews, program), code_blocks, next_layer, model_preference, draft_model_manual}, Nil{})

def content_effects(effects: +List<Content.Effect>, +identity: Content.Identity) -> +List<Effect>:
  match effects:
    case Nil{}: Nil{}
    case Con{effect, rest}: ContentEffect{identity, effect} <> content_effects(rest, identity)

def content_result(result: Content.Decision, +identity: Content.Identity, application: Application) -> Decision:
  Content.Decision{block, effects} = result
  Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual}} = application
  local(program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, Content.save_block(code_blocks, identity, block), next_layer, model_preference, draft_model_manual}, content_effects(effects, identity))

def content_input(+identity: Content.Identity, input: Content.Input, application: Application) -> Decision:
  Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, +code_blocks, next_layer, model_preference, draft_model_manual}} = application
  content_result(Content.step(Content.find_block(code_blocks, identity), input), identity,
    Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual}})


def restore_preference(+profile: String, +reasoning: String, +application: Application) -> Decision:
  Application{+program, +session} = application
  local(program, resolve_model_draft(with_preference(Some{ModelPreference{profile, reasoning}}, session), program), Nil{})
