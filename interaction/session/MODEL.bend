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
import ../../features/task_graph/MODEL.bend as Graph
import ../../harness/features/MODEL.bend as F
import ../../harness/DOMAIN.bend as D
import ../../bendlib/component.bend as C
import ../../bendlib/association-map.bend as Finite
import ../../features/board/STATE.bend as Board
import ../../bendlib/json.bend as J
import ../../harness/transport/command-codec.bend as CommandCodec
import ../services/CONTEXT.bend as Context
import ../INPUT.bend as U
import ../submission/FIELDS.bend as Forms

type Disclosure is Data:
  Disclosure{group: Nat, occurrence: Nat, expanded: Bool}

type Reader is Data:
  Reader{generation: Nat, position: U.ReadingIntent, disclosures: +List<Disclosure>}

type Layer is Data:
  Layer{panel: U.Panel, trigger: String, initial_attention: String, query: String, occurrence: Nat, source_expanded: Bool, decision_field: Maybe<&2, Forms.Field>, parameter_buffer: Maybe<&2, String>}

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

type WorkspaceGit is Data:
  UnknownWorkspaceGit{}
  LoadingWorkspaceGit{ticket: Nat, primary: String}
  ObservedWorkspaceGit{primary: String, available: Bool}

type Session is Data:
  Session{route: U.Route, drafts: +List<U.Draft>, readers: +List<Finite.Entry(Reader)>,
    layers: +List<Layer>, attention: String, navigation: NavigationState, filter: B.Filter,
    now: U32, next_ticket: Nat, pending: +List<Pending>, previews: +List<Live.Output>, code_blocks: +List<Content.Block>, next_layer: Nat, model_preference: Maybe<&2, ModelPreference>, draft_model_manual: Bool, workspace_git: WorkspaceGit}

type Application is Data:
  Application{program: M.World(), session: Session}

type Completion is Data:
  DirectCompletion{}
  DraftCompletion{draft: U.Draft}
  WorktreePreferenceCompletion{draft: U.Draft, command: M.Command}
  ExecutionCompletion{task: Nat, profile: String, reasoning: String, remember: Bool}
  ExecutionViewCompletion{task: Nat, profile: String, reasoning: String, remember: Bool, occurrence: Nat}
  ConfirmationCompletion{command: M.Command, trigger: String, destination: U.Route, occurrence: Nat}

type Effect is Data:
  RequestCommand{command: M.Command, completion: Completion}
  ContentEffect{identity: Content.Identity, effect: Content.Effect}
  ObserveDirectories{ticket: Nat, entered: D.Workspace}
  Attend{target: String}
  PersistModelPreference{profile: String, reasoning: String}
  ObserveWorkspaceGit{ticket: Nat, primary: String}

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
  WorkspaceGitObserved{ticket: Nat, available: Bool}

type ChoiceCompletion is Data:
  ChoiceCompletion{editor: U.Editor, result: Decision}

type ReadingRequest is Data:
  ReadingRequest{task: Nat, generation: Nat, intent: U.ReadingIntent, application: Application}

type Settlement is Data:
  Settlement{current: U.Draft, revision: Nat, result: J.Json, session: Session}

type SubmissionCompletion is Data:
  SubmissionCompletion{draft: U.Draft, result: J.Json, previous_session: Session, application: Application}

type ConfirmationReceipt is Data:
  ConfirmationReceipt{command: M.Command, trigger: String, occurrence: Nat, result: J.Json, destination: U.Route, application: Application}


def program(state: Application) -> M.World():
  Application{program, session} = state
  program

def session(state: Application) -> Session:
  Application{program, session} = state
  session

def route(state: Session) -> U.Route:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git} = state
  route

def drafts(state: Session) -> +List<U.Draft>:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git} = state
  drafts

def readers(state: Session) -> +List<Finite.Entry(Reader)>:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git} = state
  readers

def layers(state: Session) -> +List<Layer>:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git} = state
  layers

def attention(state: Session) -> String:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git} = state
  attention

def navigation(state: Session) -> NavigationState:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git} = state
  navigation

def filter(state: Session) -> B.Filter:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git} = state
  filter

def now(state: Session) -> U32:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git} = state
  now

def next_ticket(state: Session) -> Nat:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git} = state
  next_ticket

def pending(state: Session) -> +List<Pending>:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git} = state
  pending

def previews(state: Session) -> +List<Live.Output>:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git} = state
  previews

def code_blocks(state: Session) -> +List<Content.Block>:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git} = state
  code_blocks

def next_layer(state: Session) -> Nat:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git} = state
  next_layer

def with_program(value: M.World(), state: Application) -> Application:
  Application{program, session} = state
  Application{value, session}

def with_session(value: Session, state: Application) -> Application:
  Application{program, session} = state
  Application{program, value}

def with_now(value: U32, state: Session) -> Session:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git} = state
  Session{route, drafts, readers, layers, attention, navigation, filter, value, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}

def from_program(program: M.World(), session: Session) -> Application:
  Application{program, session}

def with_route(value: U.Route, state: Session) -> Session:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git} = state
  Session{value, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}

def with_drafts(value: +List<U.Draft>, state: Session) -> Session:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git} = state
  Session{route, value, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}

def with_layers(value: +List<Layer>, state: Session) -> Session:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git} = state
  Session{route, drafts, readers, value, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}

def with_attention(value: String, state: Session) -> Session:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git} = state
  Session{route, drafts, readers, layers, value, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}

def with_navigation(value: NavigationState, state: Session) -> Session:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git} = state
  Session{route, drafts, readers, layers, attention, value, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}

def with_next_ticket(value: Nat, state: Session) -> Session:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git} = state
  Session{route, drafts, readers, layers, attention, navigation, filter, now, value, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}

def with_pending(value: +List<Pending>, state: Session) -> Session:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git} = state
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, value, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}

def with_next_layer(value: Nat, state: Session) -> Session:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git} = state
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, value, model_preference, draft_model_manual, workspace_git}

def first_valid_profile(+valid: Bool, +profile: D.Profile, +fallback: Sigma<&2, &2, String, (_ => String)>) -> Sigma<&2, &2, String, (_ => String)>:
  match valid profile:
    case True{} D.Profile{key, provider, name, policy, options}: (key, D.profile_default(D.Profile{key, provider, name, policy, options}))
    case False{} _: fallback

def first_profile(profiles: +List<D.Profile>) -> Sigma<&2, &2, String, (_ => String)>:
  match profiles:
    case Nil{}: ("", "")
    case Con{+profile, rest}: first_valid_profile(Bool.not(D.is_codex_auto_review(profile)) && D.profile_valid(profile) && D.profile_permitted(profile, D.profile_default(profile)), profile, first_profile(rest))

def chooser_owns(layers: +List<Layer>, editor: U.Editor) -> Bool:
  match layers:
    case Con{Layer{U.ModelPicker{owner}, trigger, initial, query, layer_occurrence, source_expanded, decision_field, parameter_buffer}, rest}: U.same_editor(owner, editor)
    case Con{Layer{U.DeliveryPicker{task}, trigger, initial, query, layer_occurrence, source_expanded, decision_field, parameter_buffer}, rest}: U.same_editor(U.MessageEditor{task}, editor)
    case Con{Layer{U.PermissionsConfiguration{owner}, trigger, initial, query, layer_occurrence, source_expanded, decision_field, parameter_buffer}, rest}: U.same_editor(owner, editor)
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
    case Con{Layer{panel, +trigger, initial, query, layer_occurrence, source_expanded, decision_field, parameter_buffer}, rest}:
      Session{route, drafts, readers, old, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git} = session
      local(program, Session{route, drafts, readers, rest, trigger, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}, [Attend{trigger}])

def close_panel(application: Application) -> Decision:
  Application{program, +session} = application
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git} = session
  close_layers(layers, program, session)

def with_native(local: Decision, result: J.Json, effects: +List<M.Effect()>, durable: Bool) -> Decision:
  Decision{application, ignored_reply, ignored_runtime, interaction, ignored_durable} = local
  Decision{application, result, effects, interaction, durable}

def choice_owned(completion: ChoiceCompletion) -> Bool:
  ChoiceCompletion{editor, result} = completion
  Decision{Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}}, reply, runtime, interaction, durable} = result
  J.boolean(J.get(reply, "ok")) && chooser_owns(layers, editor)

def owned_choice() -> ChoiceCompletion -> Type:
  Categories.holds(ChoiceCompletion, choice_owned)

def same_requested_field(left: Maybe<&2, Forms.Field>, right: Maybe<&2, Forms.Field>) -> Bool:
  match left right:
    case None{} None{}: True{}
    case Some{a} Some{b}: String.eq(Forms.key(a), Forms.key(b))
    case _ _: False{}

def same_requested_source(left: Bool, right: Bool) -> Bool:
  match left right:
    case True{} True{}: True{}
    case False{} False{}: True{}
    case _ _: False{}

def request_view_changed(layers: +List<Layer>, source: Bool, field: Maybe<&2, Forms.Field>) -> Bool:
  match layers:
    case Con{Layer{panel, trigger, initial, query, occurrence, current_source, current_field, buffer}, rest}:
      Bool.not(same_requested_source(source, current_source) && same_requested_field(field, current_field))
    case _: True{}

# A view request has its own identity. Ordinary parameter text edits retain it.

def update_requested_view(changed: Bool, +panel: U.Panel, +trigger: String, +initial: String, +query: String, occurrence: Nat, +source: Bool, +field: Maybe<&2, Forms.Field>, +buffer: Maybe<&2, String>, +rest: +List<Layer>, +application: Application) -> Decision:
  match changed:
    case False{}: local(program(application), with_layers(Layer{panel, trigger, initial, query, occurrence, source, field, buffer} <> rest, session(application)), Nil{})
    case True{}:
      +current = session(application)
      +fresh = next_layer(current)
      local(program(application), with_next_layer((fresh + 1n : Nat), with_layers(Layer{panel, trigger, initial, query, fresh, source, field, buffer} <> rest, current)), Nil{})

def decision_layer_update(owned: Bool, panel: U.Panel, trigger: String, initial: String, query: String, occurrence: Nat, +source_expanded: Bool, +field: Maybe<&2, Forms.Field>, parameter_buffer: Maybe<&2, String>, rest: +List<Layer>, +application: Application) -> Decision:
  match owned:
    case False{}: unchanged(application)
    case True{}: update_requested_view(request_view_changed(layers(session(application)), source_expanded, field), panel, trigger, initial, query, occurrence, source_expanded, field, parameter_buffer, rest, application)

def decision_editor_matches(found: Maybe<&2, U.Editor>, editor: U.Editor) -> Bool:
  match found:
    case None{}: False{}
    case Some{owner}: U.same_editor(owner, editor)

def decision_panel_editor(panel: U.Panel) -> Maybe<&2, U.Editor>:
  match panel:
    case U.WorkspaceConfiguration{editor}: Some{editor}
    case U.PermissionsConfiguration{editor}: Some{editor}
    case U.ModelPicker{editor}: Some{editor}
    case U.EditObject{editor}: Some{editor}
    case _: None{}

def leave_layer_request(+layers: +List<Layer>, +editor: U.Editor, +application: Application) -> Decision:
  match layers:
    case Con{Layer{+panel, trigger, initial, query, occurrence, source, field, buffer}, rest}:
      match field:
        case Some{field}: decision_layer_update(decision_editor_matches(decision_panel_editor(panel), editor), panel, trigger, initial, query, occurrence, source, None{}, None{}, rest, application)
        case None{}: decision_layer_update(decision_editor_matches(decision_panel_editor(panel), editor), panel, trigger, initial, query, occurrence, False{}, None{}, None{}, rest, application)
    case _: unchanged(application)

def leave_decision(editor: U.Editor, +application: Application) -> Decision:
  leave_layer_request(layers(session(application)), editor, application)

def complete_choice_layers(+layers: +List<Layer>, +editor: U.Editor, +application: Application, +reply: J.Json, +runtime: +List<M.Effect()>, +durable: Bool) -> Decision:
  match layers:
    case Con{Layer{panel, trigger, initial, query, occurrence, source, Some{field}, buffer}, rest}:
      with_native(leave_decision(editor, application), reply, runtime, durable)
    case _: with_native(close_panel(application), reply, runtime, durable)

def complete_choice_value(+editor: U.Editor, +result: Decision) -> Decision:
  Decision{+application, +reply, runtime, interaction, durable} = result
  complete_choice_layers(layers(session(application)), editor, application, reply, runtime, durable)

def close_choice_owned(member: Categories.Membership<ChoiceCompletion, owned_choice()>) -> Decision:
  Categories.Membership{ChoiceCompletion{editor, result}, evidence} = member
  complete_choice_value(editor, result)

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
    case U.ConfigureContext{Context.SetApproval{choice}}: close_choice(editor, result)
    case U.ConfigureContext{Context.SetSandbox{sandbox}}: close_choice(editor, result)
    case _: result

def new_task(profile: Sigma<&2, &2, String, (_ => String)>, origin: Context.Origin) -> U.Body:
  (profile, reasoning) = profile
  U.NewTask{U.initial_text(""), profile, reasoning, Context.defaults(origin), False{}}

def initial(+program: M.World()) -> Application:
  Application{program, Session{U.Start{}, [U.Draft{0n, new_task(first_profile(Board.profiles(program)), Context.EnvironmentDefaults{}), U.Editing{}, ""}],
    Nil{}, Nil{}, "composer/new-task", NavigationState{AutomaticNavigation{}, Nil{}}, B.empty_filter(), 0, 0n, Nil{}, Nil{}, Nil{}, 0n, None{}, False{}, UnknownWorkspaceGit{}}}

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
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git} = session
  Session{route, put_draft(draft, drafts), readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}

def refuse(application: Application, reason: String) -> Decision:
  reply(application, D.failure("interaction_refused", reason))

def edit_result(result: Result<&2, &2, String, U.Draft>, program: M.World(), session: Session) -> Decision:
  match result:
    case Fail{reason}: refuse(Application{program, session}, reason)
    case Done{draft}: local(program, with_draft(session, draft), Nil{})

def workspace_git(session: Session) -> WorkspaceGit:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git} = session
  workspace_git

def with_workspace_git(value: WorkspaceGit, session: Session) -> Session:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, previous} = session
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, value}

def preview_primary(preview: Context.Preview) -> Maybe<&2, String>:
  match preview:
    case Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}: W.primary(Context.selected_workspace(workspace))
    case _: None{}

def new_task_primary(found: Maybe<&2, U.Draft>, world: M.World()) -> Maybe<&2, String>:
  match found:
    case Some{U.Draft{revision, U.NewTask{message, profile, reasoning, context, enabled}, feedback, entry}}: preview_primary(Context.preview(context, world))
    case _: None{}

def current_primary(+application: Application) -> Maybe<&2, String>:
  new_task_primary(find_draft(drafts(session(application)), U.NewTaskEditor{}), program(application))

def workspace_git_matches(git: WorkspaceGit, primary: Maybe<&2, String>) -> Bool:
  match git primary:
    case ObservedWorkspaceGit{root, available} Some{path}: available && String.eq(root, path)
    case _ _: False{}

def worktree_available(+application: Application) -> Bool:
  workspace_git_matches(workspace_git(session(application)), current_primary(application))

def observe_workspace_git_start(+path: String, decision: Decision) -> Decision:
  Decision{Application{world, session}, reply, runtime, effects, durable} = decision
  Session{route, drafts, readers, layers, attention, navigation, filter, now, +next, pending, previews, code_blocks, next_layer, preference, manual, previous} = session
  Decision{Application{world, Session{route, drafts, readers, layers, attention, navigation, filter, now, (next + 1n : Nat), pending, previews, code_blocks, next_layer, preference, manual, LoadingWorkspaceGit{next, path}}}, reply, runtime,
    List.append(&2, Effect, effects, [ObserveWorkspaceGit{next, path}]), durable}

def observe_workspace_git_clear(decision: Decision) -> Decision:
  Decision{Application{world, session}, reply, runtime, effects, durable} = decision
  Decision{Application{world, with_workspace_git(UnknownWorkspaceGit{}, session)}, reply, runtime, effects, durable}

def observe_workspace_git_primary(selected: Maybe<&2, String>, decision: Decision) -> Decision:
  match selected:
    case None{}: observe_workspace_git_clear(decision)
    case Some{path}: observe_workspace_git_start(path, decision)

def observe_workspace_git(decision: Decision) -> Decision:
  Decision{+application, reply, runtime, effects, durable} = decision
  observe_workspace_git_primary(current_primary(application), Decision{application, reply, runtime, effects, durable})

def git_observation_current(current: Nat, ticket: Nat, primary: String, actual: Maybe<&2, String>) -> Bool:
  match actual:
    case None{}: False{}
    case Some{path}: Nat.is_eq(current, ticket) && String.eq(primary, path)

def disable_unavailable_worktree(available: Bool, found: Maybe<&2, U.Draft>, session: Session) -> Session:
  match available found:
    case False{} Some{U.Draft{revision, U.NewTask{message, profile, reasoning, context, enabled}, feedback, entry}}:
      with_draft(session, U.Draft{revision, U.NewTask{message, profile, reasoning, context, False{}}, feedback, entry})
    case _ _: session

def settle_workspace_git(current: Bool, +primary: String, +available: Bool, application: Application) -> Decision:
  match current:
    case False{}: unchanged(application)
    case True{}:
      Application{world, +session} = application
      local(world, with_workspace_git(ObservedWorkspaceGit{primary, available}, disable_unavailable_worktree(available, find_draft(drafts(session), U.NewTaskEditor{}), session)), Nil{})

def workspace_git_result(git: WorkspaceGit, ticket: Nat, available: Bool, +application: Application) -> Decision:
  match git:
    case LoadingWorkspaceGit{current, +primary}: settle_workspace_git(git_observation_current(current, ticket, primary, current_primary(application)), primary, available, application)
    case _: unchanged(application)

def workspace_git_observed(ticket: Nat, available: Bool, +application: Application) -> Decision:
  workspace_git_result(workspace_git(session(application)), ticket, available, application)

def refresh_workspace_edit(change: U.Edit) -> Bool:
  match change:
    case U.EditWorkspace{change}: True{}
    case U.ConfirmDirectory{}: True{}
    case U.ConfigureContext{Context.ChooseOrigin{origin}}: True{}
    case U.ConfigureContext{Context.SetWorkspace{workspace}}: True{}
    case U.ConfigureContext{Context.UseDefaultWorkspace{}}: True{}
    case _: False{}

def observe_workspace_edit_enabled(enabled: Bool, decision: Decision) -> Decision:
  match enabled:
    case True{}: observe_workspace_git(decision)
    case False{}: decision

def observe_workspace_edit(editor: U.Editor, change: U.Edit, decision: Decision) -> Decision:
  match editor:
    case U.NewTaskEditor{}: observe_workspace_edit_enabled(refresh_workspace_edit(change), decision)
    case _: decision

def observe_workspace_panel(panel: U.Panel, decision: Decision) -> Decision:
  match panel:
    case U.WorkspaceConfiguration{U.NewTaskEditor{}}: observe_workspace_git(decision)
    case _: decision

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
    case Some{profile}: W.valid_reviewer_profile(profile)

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

def execution_completion_owned(+owned: Bool, +task: Nat, +profile: String, +reasoning: String, +remember: Bool, +occurrence: Nat) -> Completion:
  match owned:
    case True{}: ExecutionViewCompletion{task, profile, reasoning, remember, occurrence}
    case False{}: ExecutionCompletion{task, profile, reasoning, remember}

def execution_completion(+task: Nat, +profile: String, +reasoning: String, +remember: Bool, +layers: +List<Layer>) -> Completion:
  match layers:
    case Con{Layer{panel, trigger, initial, query, occurrence, source, field, buffer}, rest}:
      execution_completion_owned(decision_editor_matches(decision_panel_editor(panel), U.MessageEditor{task}), task, profile, reasoning, remember, occurrence)
    case _: ExecutionCompletion{task, profile, reasoning, remember}

def configure_selected(+remember: Bool, +sandbox: D.Sandbox, +approval: D.ApprovalPolicy, +task: Nat, +profile: String, +reasoning: String, +current_profile: String, +current_reasoning: String, +application: Application) -> Decision:
  match remember:
    case True{}: request_execution(M.ConfigureTaskExecution{task, profile, reasoning, sandbox, approval}, execution_completion(task, profile, reasoning, True{}, layers(session(application))), application)
    case False{}: request_execution(M.ConfigureTaskExecution{task, current_profile, current_reasoning, sandbox, approval}, execution_completion(task, current_profile, current_reasoning, False{}, layers(session(application))), application)

def configure_policy(+policy: Sigma<&2, &2, D.Sandbox, (_ => D.ApprovalPolicy)>, +task: Nat, +profile: String, +reasoning: String, +current_profile: String, +current_reasoning: String, +remember: Bool, +application: Application) -> Decision:
  (sandbox, approval) = policy
  configure_selected(remember, sandbox, approval, task, profile, reasoning, current_profile, current_reasoning, application)

def configure_current(+current: D.ExecutionConfiguration, +task: Nat, +profile: String, +reasoning: String, +change: Maybe<&2, Context.Change>, +remember: Bool, +application: Application) -> Decision:
  D.ExecutionConfiguration{+model, sandbox, approval} = current
  current_profile = D.profile_key(D.model_profile(model))
  current_reasoning = D.model_selection(model)
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

def edit_approval_checked(valid: Bool, +editor: U.Editor, choice: Context.ApprovalChoice, +application: Application) -> Decision:
  match valid editor:
    case False{} _: refuse(application, "The reviewing model is unavailable for automatic review")
    case True{} U.MessageEditor{+task}: configure_task(found_task(program(application), task), task, "", "", Some{Context.SetApproval{choice}}, False{}, application)
    case True{} other: edit_local(other, U.ConfigureContext{Context.SetApproval{choice}}, application)

def edit(+editor: U.Editor, change: U.Edit, +application: Application) -> Decision:
  match editor change:
    case editor U.ConfigureContext{Context.SetApproval{Context.AutomaticReview{+profile}}}:
      edit_approval_checked(valid_task_change(Some{Context.SetApproval{Context.AutomaticReview{profile}}}, Forms.reviewers(program(application))), editor, Context.AutomaticReview{profile}, application)
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
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git} = session
  local(program, Session{route, drafts, (task, Reader{generation, position, disclosures}) <> Finite.remove(~Reader, readers, task),
    layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}, Nil{})

def read(+task: Nat, intent: U.ReadingIntent, application: Application) -> Decision:
  Application{program, +session} = application
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git} = session
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
  Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code, next_layer, model_preference, draft_model_manual, workspace_git}} = application
  local(program, Session{route, drafts, readers, layers, attention, toggle_project_navigation(id, navigation), filter, now, next, pending, previews, code, next_layer, model_preference, draft_model_manual, workspace_git}, Nil{})

def new_visit(reader: Reader) -> Reader:
  Reader{generation, position, disclosures} = reader
  Reader{(generation + 1n : Nat), position, disclosures}

def visit_readers(route: U.Route, +readers: +List<Finite.Entry(Reader)>) -> +List<Finite.Entry(Reader)>:
  match route:
    case U.Conversation{+task}: (task, new_visit(reader(readers, task))) <> Finite.remove(~Reader, readers, task)
    case _: readers

def navigate_with_attention(+route: U.Route, +target: String, application: Application) -> Decision:
  Application{program, Session{old, drafts, +readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}} = application
  +current_readers = visit_readers(route, readers)
  local(program, Session{route, drafts, current_readers, Nil{}, target, navigation_after_visit(navigation), filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git},
    [Attend{target}])

def navigate(route: U.Route, application: Application) -> Decision:
  navigate_with_attention(route, "page-heading", application)

def reader_generation(reader: Reader) -> Nat:
  Reader{generation, position, disclosures} = reader
  generation

def reading_owned(request: ReadingRequest) -> Bool:
  ReadingRequest{+task, generation, intent, Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}}} = request
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
      Session{old, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git} = session
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
    case U.PropertySource{origin}: "property-source/" ++ panel_target(origin)
    case U.DeliveryPicker{task}: "delivery-picker/" ++ Nat.show(task)
    case U.Confirm{command, title, destination}: "confirm/cancel"

def keep_layer(same: Bool, layer: Layer, rest: +List<Layer>) -> +List<Layer>:
  match same:
    case True{}: rest
    case False{}: layer <> rest

def without_panel(layers: +List<Layer>, +identity: String) -> +List<Layer>:
  match layers:
    case Nil{}: Nil{}
    case Con{Layer{+panel, trigger, initial, query, layer_occurrence, source_expanded, decision_field, parameter_buffer}, rest}:
      keep_layer(String.eq(panel_target(panel), identity), Layer{panel, trigger, initial, query, layer_occurrence, source_expanded, decision_field, parameter_buffer}, without_panel(rest, identity))

def open_panel(+panel: U.Panel, trigger: String, application: Application) -> Decision:
  Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, +next_layer, model_preference, draft_model_manual, workspace_git}} = application
  +target = panel_target(panel)
  local(program, Session{route, drafts, readers, Layer{panel, trigger, target, "", next_layer, False{}, None{}, None{}} <> without_panel(layers, panel_target(panel)),
    target, navigation, filter, now, next, pending, previews, code_blocks, (next_layer + 1n : Nat), model_preference, draft_model_manual, workspace_git}, [Attend{target}])

def panel_present(layers: +List<Layer>, +target: String) -> Bool:
  match layers:
    case Nil{}: False{}
    case Con{Layer{panel, trigger, initial, query, layer_occurrence, source_expanded, decision_field, parameter_buffer}, rest}:
      String.eq(panel_target(panel), target) || panel_present(rest, target)

def toggle_panel_selected(present: Bool, +panel: U.Panel, +trigger: String, application: Application) -> Decision:
  match present:
    case False{}: open_panel(panel, trigger, application)
    case True{}:
      Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}} = application
      local(program, Session{route, drafts, readers, without_panel(layers, panel_target(panel)), trigger,
        navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}, [Attend{trigger}])

def toggle_panel(+panel: U.Panel, trigger: String, application: Application) -> Decision:
  Application{program, Session{route, drafts, readers, +layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}} = application
  toggle_panel_selected(panel_present(layers, panel_target(panel)), panel, trigger,
    Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}})

def fresh_project_draft(+body: U.Body, +session: Session) -> Session:
  with_draft(session, U.Draft{next_layer(session), body, U.Editing{}, ""})

def ensure_project(+found: Maybe<&2, U.Draft>, +body: U.Body, +session: Session) -> Session:
  match found:
    case None{}: fresh_project_draft(body, session)
    case _: ensure(found, body, session)

def ensure_editor_draft(+found: Maybe<&2, U.Draft>, +body: U.Body, +session: Session) -> Session:
  match body:
    case U.Project{id, name, workspace, create_worktree}: ensure_project(found, body, session)
    case _: ensure(found, body, session)

def open_editor_found(found: Maybe<&2, U.Draft>, +body: U.Body, program: M.World(), session: Session) -> Decision:
  open_panel(U.EditObject{U.owner(body)}, U.editor_trigger(U.owner(body)), Application{program, ensure_editor_draft(found, body, session)})

def open_editor(+body: U.Body, application: Application) -> Decision:
  Application{program, +session} = application
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git} = session
  open_editor_found(find_draft(drafts, U.owner(body)), body, program, session)

def edit_project(found: Maybe<&2, D.Project>, id: Maybe<&2, Nat>, application: Application) -> Decision:
  match found:
    case None{}: refuse(application, "The project no longer exists")
    case Some{D.Project{name, workspace, guidance, create_worktree}}: open_editor(U.Project{id, name, workspace, create_worktree}, application)

def project_editor(id: Maybe<&2, Nat>, +application: Application) -> Decision:
  match id:
    case None{}: open_editor(U.Project{None{}, "", D.Workspace{Nil{}, None{}}, False{}}, application)
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

def task_graph_editor_text(text: Result<&2, &2, String, String>, graph: Maybe<&2, Nat>, declaration: J.Json, application: Application) -> Decision:
  match text:
    case Fail{reason}: refuse(application, reason)
    case Done{text}: open_editor(U.TaskGraph{graph, text, Some{declaration}}, application)

def task_graph_editor_declaration(graph: Maybe<&2, Nat>, +declaration: J.Json, application: Application) -> Decision:
  task_graph_editor_text(J.show(declaration), graph, declaration, application)

def task_graph_editor_available(available: Bool, result: J.Json, graph: Nat, application: Application) -> Decision:
  match available:
    case False{}: refuse(application, "The task graph no longer exists")
    case True{}:
      +declaration = J.get(result, "result")
      task_graph_editor_declaration(Some{graph}, J.Object{[
        J.Field{"name", J.get(declaration, "name")}, J.Field{"nodes", J.get(declaration, "nodes")},
        J.Field{"rules", J.get(declaration, "rules")}]}, application)

def task_graph_editor_result(+result: J.Json, graph: Nat, application: Application) -> Decision:
  task_graph_editor_available(J.boolean(J.get(result, "ok")), result, graph, application)

def task_graph_editor(graph: Maybe<&2, Nat>, +application: Application) -> Decision:
  match graph:
    case None{}:
      task_graph_editor_declaration(None{}, J.Object{[J.Field{"name", J.Text{"Task graph"}},
        J.Field{"nodes", J.Array{Nil{}}}, J.Field{"rules", J.Array{Nil{}}}]}, application)
    case Some{+graph}:
      Application{program, session} = application
      task_graph_editor_result(Commands.query(M.FeatureQuery{F.TaskGraphQuery{Graph.ReadGraph{graph}}}, program), graph, application)

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
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git} = session
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

def resolved_model_selection(+selection: Sigma<&2, &2, String, (_ => String)>, +revision: Nat, +message: U.Text, +context: Context.Configuration, +feedback: U.Feedback, +directory_entry: String, create_worktree: Bool, +session: Session) -> Session:
  (selected, effort) = selection
  with_draft(session, U.Draft{revision, U.NewTask{message, selected, effort, context, create_worktree}, feedback, directory_entry})

def resolve_model_valid(+valid: Bool, +draft: U.Draft, +profiles: +List<D.Profile>, +session: Session) -> Session:
  match valid draft:
    case False{} U.Draft{revision, U.NewTask{message, profile, reasoning, context, create_worktree}, feedback, directory_entry}:
      resolved_model_selection(preferred_selection(preference(session), profiles), revision, message, context, feedback, directory_entry, create_worktree, session)
    case _ _: session

def manual_model(session: Session) -> Bool:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git} = session
  draft_model_manual

def resolve_model_found(+found: Maybe<&2, U.Draft>, +profiles: +List<D.Profile>, +session: Session) -> Session:
  match found:
    case Some{U.Draft{revision, U.NewTask{message, +profile, +reasoning, context, create_worktree}, feedback, directory_entry}}:
      resolve_model_valid(manual_model(session) && permitted_preference(D.find_profile(profiles, profile), reasoning), U.Draft{revision, U.NewTask{message, profile, reasoning, context, create_worktree}, feedback, directory_entry}, profiles, session)
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

def rejected_feedback(workspace: Bool, revision: Nat, reason: String) -> U.Feedback:
  match workspace:
    case True{}: U.WorkspaceRejected{revision, reason}
    case False{}: U.Rejected{revision, reason}

def command_rejection_feedback(body: U.Body, submitted: Nat, +result: J.Json) -> U.Feedback:
  rejected_feedback(String.eq(J.text(J.get(J.get(result, "error"), "code")), "command_not_submitted") && U.workspace_operation(body),
    submitted, J.text(J.get(J.get(result, "error"), "message")))

def settled_current(current: U.Draft, same: Bool, accepted: Bool, submitted: Nat, +result: J.Json) -> U.Draft:
  U.Draft{revision, +body, feedback, directory_entry} = current
  match same accepted:
    case True{} True{}: U.Draft{(revision + 1n : Nat), U.after_accept(body), U.Accepted{submitted, result}, directory_entry}
    case False{} _: U.Draft{revision, body, feedback, directory_entry}
    case True{} False{}: U.Draft{revision, body, command_rejection_feedback(body, submitted, result), directory_entry}

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
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git} = session
  settle_found(find_draft(drafts, U.owner(body)), revision, result, session)

def same_revision(found: Maybe<&2, U.Draft>, expected: Nat) -> Bool:
  match found:
    case None{}: False{}
    case Some{U.Draft{actual, body, feedback, directory_entry}}: Nat.is_eq(actual, expected)

def owns_submission(draft: U.Draft, session: Session) -> Bool:
  U.Draft{revision, body, feedback, directory_entry} = draft
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git} = session
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
    case editor _ Con{Layer{U.EditObject{current}, trigger, initial, query, layer_occurrence, source_expanded, decision_field, parameter_buffer}, rest}:
      finish_layer(U.same_editor(editor, current), application)
    case _ _ _: unchanged(application)

def capture_open(layers: +List<Layer>) -> Bool:
  match layers:
    case Con{Layer{U.EditObject{U.CardEditor{None{}}}, trigger, initial, query, layer_occurrence, source_expanded, decision_field, parameter_buffer}, rest}: True{}
    case _: False{}

def capture_attention(open: Bool, application: Application) -> Decision:
  match open:
    case True{}:
      Application{program, session} = application
      local(program, session, [Attend{"card-title"}])
    case False{}: unchanged(application)

def continue_capture(+application: Application) -> Decision:
  Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}} = application
  capture_attention(capture_open(layers), application)

def finish_task_graph_layer(same: Bool, application: Application) -> Decision:
  match same:
    case True{}: visit(U.TaskGraphs{}, application)
    case False{}: unchanged(application)

def finish_task_graph(editor: U.Editor, layers: +List<Layer>, application: Application) -> Decision:
  match layers:
    case Con{Layer{U.EditObject{current}, trigger, initial, query, layer_occurrence, source_expanded, decision_field, parameter_buffer}, rest}:
      finish_task_graph_layer(U.same_editor(editor, current), application)
    case _: unchanged(application)

def with_manual_model(value: Bool, session: Session) -> Session:
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, previous, workspace_git} = session
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, value, workspace_git}

def finish_fresh_task(+route: U.Route, +layers: +List<Layer>, +result: J.Json, +application: Application) -> Decision:
  Application{program, session} = application
  finish_at_location(U.NewTaskEditor{}, route, layers, result, Application{program, with_manual_model(False{}, session)})

def finish_body(body: U.Body, route: U.Route, layers: +List<Layer>, result: J.Json, application: Application) -> Decision:
  match body:
    case U.NewTask{message, profile, reasoning, context, create_worktree}: finish_fresh_task(route, layers, result, application)
    case U.Card{None{}, revision, value, assist, profile, True{}}:
      continue_capture(application)
    case U.TaskGraph{graph, declaration, parsed}: finish_task_graph(U.TaskGraphEditor{graph}, layers, application)
    case other: finish_at_location(U.owner(other), route, layers, result, application)

def submission_accepted(completion: SubmissionCompletion) -> Bool:
  SubmissionCompletion{draft, +result, previous_session, application} = completion
  J.boolean(J.get(result, "ok")) && owns_submission(draft, previous_session)

def accepted_submission() -> SubmissionCompletion -> Type:
  Categories.holds(SubmissionCompletion, submission_accepted)

def finish_submission_value(draft: U.Draft, result: J.Json, +application: Application) -> Decision:
  U.Draft{revision, body, feedback, directory_entry} = draft
  Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}} = application
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
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git} = session
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, Live.retained(previews, world), code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}

def native_result(decision: M.Decision(), session: Session, submitted: Maybe<&2, U.Draft>, durable: Bool) -> Decision:
  C.Decision{+program, +result, effects} = decision
  native_session(submitted, program, result, effects, retain_previews(session, program), durable)

def submission_completion(submitted: Maybe<&2, U.Draft>) -> Completion:
  match submitted:
    case None{}: DirectCompletion{}
    case Some{draft}: DraftCompletion{draft}

def worktree_preference_changed(same: Bool, id: Nat, enabled: Bool) -> Maybe<&2, M.Command>:
  match same:
    case True{}: None{}
    case False{}: Some{M.UpdateProject{id, None{}, J.Null{}, J.Null{}, J.Boolean{enabled}}}

def worktree_project_preference(found: Maybe<&2, D.Project>, id: Nat, +enabled: Bool) -> Maybe<&2, M.Command>:
  match found:
    case Some{D.Project{name, roots, guidance, previous}}: worktree_preference_changed(UX.same_worktree_choice(enabled, previous), id, enabled)
    case None{}: None{}

def worktree_preference_command(body: U.Body, world: M.World()) -> Maybe<&2, M.Command>:
  match body:
    case U.NewTask{message, profile, reasoning, Context.Configuration{Context.ProjectDefaults{+id}, workspace, sandbox, approval}, enabled}:
      worktree_project_preference(Projects.find(Projects.registry(F.State(), world), id), id, enabled)
    case _: None{}

def worktree_preference_available(available: Bool, body: U.Body, world: M.World()) -> Maybe<&2, M.Command>:
  match available:
    case True{}: worktree_preference_command(body, world)
    case False{}: None{}

def worktree_submission_allowed(body: U.Body, +application: Application) -> Bool:
  match body:
    case U.NewTask{message, profile, reasoning, context, True{}}:
      worktree_available(application) && workspace_git_matches(workspace_git(session(application)), preview_primary(Context.preview(context, program(application))))
    case _: True{}

def unverified_worktree_submission(application: Application) -> Decision:
  refuse(application, "Wait for Git verification of the primary workspace before creating a worktree.")

def request_submitted(allowed: Bool, command: M.Command, draft: U.Draft, application: Application) -> Decision:
  match allowed:
    case False{}: unverified_worktree_submission(application)
    case True{}: request_command(command, DraftCompletion{draft}, application)

def execute_preference(preference: Maybe<&2, M.Command>, command: M.Command, draft: U.Draft, application: Application) -> Decision:
  match preference:
    case None{}: request_command(command, DraftCompletion{draft}, application)
    case Some{update}: request_command(update, WorktreePreferenceCompletion{draft, command}, application)

def execute_submitted(allowed: Bool, preference: Maybe<&2, M.Command>, command: M.Command, draft: U.Draft, application: Application) -> Decision:
  match allowed:
    case False{}: unverified_worktree_submission(application)
    case True{}: execute_preference(preference, command, draft, application)

def execute(command: M.Command, +application: Application, submitted: Maybe<&2, U.Draft>) -> Decision:
  match submitted:
    case None{}: request_command(command, DirectCompletion{}, application)
    case Some{+draft}: execute_submitted(worktree_submission_allowed(U.contents(draft), application), worktree_preference_available(worktree_available(application), U.contents(draft), program(application)), command, draft, application)

def execute_direct(command: Maybe<&2, M.Command>, application: Application) -> Decision:
  match command:
    case None{}: refuse(application, "This action requires an editor or a navigation transition")
    case Some{command}: execute(command, application, None{})

def prepare_directories(application: Application, workspace: Maybe<&2, D.Workspace>, +draft: U.Draft) -> Decision:
  Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, +now, +next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}} = application
  match workspace:
    case None{}:
      U.Draft{revision, body, feedback, directory_entry} = draft
      execute(U.command(body, now), Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}}, Some{draft})
    case Some{workspace}:
      local(program, Session{route, drafts, readers, layers, attention, navigation, filter, now, (next + 1n : Nat),
        Pending{next, draft, now} <> pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}, [ObserveDirectories{next, workspace}])

def prepare_checked(allowed: Bool, application: Application, workspace: Maybe<&2, D.Workspace>, draft: U.Draft) -> Decision:
  match allowed:
    case False{}: unverified_worktree_submission(application)
    case True{}: prepare_directories(application, workspace, draft)

def prepare(+application: Application, workspace: Maybe<&2, D.Workspace>, +draft: U.Draft) -> Decision:
  prepare_checked(worktree_submission_allowed(U.contents(draft), application), application, workspace, draft)

def submission_ready(+pending: +List<Pending>, +program: M.World(), draft: U.Draft) -> Bool:
  U.Draft{revision, +body, feedback, directory_entry} = draft
  UX.draft_can_prepare(U.Draft{revision, body, feedback, directory_entry}, busy(pending, U.owner(body)), program)

def ready_submission(+pending: +List<Pending>, +program: M.World()) -> U.Draft -> Type:
  Categories.holds(U.Draft, (draft => submission_ready(pending, program, draft)))

def submit_ready(+pending: +List<Pending>, +program: M.World(), member: Categories.Membership<U.Draft, ready_submission(pending, program)>, application: Application) -> Decision:
  Categories.Membership{+draft, evidence} = member
  U.Draft{revision, body, feedback, directory_entry} = draft
  prepare(application, U.required_workspace(body), draft)

def submission_refusal(+pending: +List<Pending>, +program: M.World(), candidate: U.Draft, +application: Application) -> Decision:
  U.Draft{+revision, +body, feedback, directory_entry} = candidate
  +now = now(session(application))
  refuse(application, UX.assessment_reason(UX.assessed_requirements(UX.draft_requirements(U.Draft{revision, body, feedback, directory_entry}, busy(pending, U.owner(body)), program), body, revision, now, program)))

def submit_admitted(+pending: +List<Pending>, +program: M.World(), candidate: U.Draft, admitted: Maybe<&1, Categories.Membership<U.Draft, ready_submission(pending, program)>>, application: Application) -> Decision:
  match admitted:
    case None{}: submission_refusal(pending, program, candidate, application)
    case Some{member}: submit_ready(pending, program, member, application)

def submit_found(found: Maybe<&2, U.Draft>, +application: Application) -> Decision:
  match found:
    case None{}: refuse(application, "The editor is not open")
    case Some{+draft}:
      Application{+program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, +pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}} = application
      submit_admitted(pending, program, draft, Categories.admit(U.Draft, (draft => submission_ready(pending, program, draft)), draft), application)

def submit(editor: U.Editor, +application: Application) -> Decision:
  Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}} = application
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
  Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}} = application
  Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, without_pending(pending, ticket), previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}}

def workspace_settlement(current: Bool, draft: U.Draft, revision: Nat, reason: String, session: Session) -> Session:
  match current:
    case False{}: session
    case True{}:
      U.Draft{current, body, feedback, entry} = draft
      with_draft(session, U.Draft{current, body, U.WorkspaceRejected{revision, reason}, entry})

def workspace_settlement_found(found: Maybe<&2, U.Draft>, +revision: Nat, reason: String, session: Session) -> Session:
  match found:
    case None{}: session
    case Some{+draft}:
      U.Draft{current, body, feedback, entry} = draft
      workspace_settlement(Nat.is_eq(current, revision), draft, revision, reason, session)

def settle_workspace(submitted: U.Draft, reason: String, +session: Session) -> Session:
  U.Draft{revision, body, feedback, entry} = submitted
  workspace_settlement_found(find_draft(drafts(session), U.owner(body)), revision, reason, session)

def preparation_failure(draft: U.Draft, +reason: String, application: Application) -> Decision:
  Application{program, session} = application
  +result = D.failure("workspace_observation_failed", reason)
  Decision{Application{program, settle_workspace(draft, reason, session)}, result, Nil{}, Nil{}, False{}}

def retry_workspace_allowed(allowed: Bool, +draft: U.Draft, +application: Application) -> Decision:
  match allowed:
    case False{}: submission_refusal(pending(session(application)), program(application), draft, application)
    case True{}:
      U.Draft{revision, +body, feedback, entry} = draft
      +retry: U.Draft = U.Draft{revision, body, U.Editing{}, entry}
      +updated = with_session(with_draft(session(application), retry), application)
      submit_found(Some{retry}, updated)

def retry_workspace_current(current: Bool, +draft: U.Draft, +application: Application) -> Decision:
  match current:
    case False{}: refuse(application, "There is no current workspace failure to retry")
    case True{}:
      U.Draft{+revision, +body, feedback, +entry} = draft
      +candidate: U.Draft = U.Draft{revision, body, U.Editing{}, entry}
      retry_workspace_allowed(UX.draft_can_prepare(candidate, busy(pending(session(application)), U.owner(body)), program(application)), draft, application)

def retry_workspace_found(found: Maybe<&2, U.Draft>, application: Application) -> Decision:
  match found:
    case None{}: refuse(application, "The editor is not open")
    case Some{+draft}:
      U.Draft{revision, body, feedback, entry} = draft
      retry_workspace_current(UX.workspace_rejection_current(feedback, revision), draft, application)

def retry_workspace(editor: U.Editor, +application: Application) -> Decision:
  retry_workspace_found(find_draft(drafts(session(application)), editor), application)

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
  Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}} = application
  observed_pending(find_pending(pending, ticket), result, application)

def confirmation_outcome(ok: Bool, destination: U.Route, application: Application) -> Decision:
  match ok:
    case True{}: navigate(destination, application)
    case False{}: unchanged(application)

def confirmation_owned(layers: +List<Layer>, +command: M.Command, +trigger: String, occurrence: Nat) -> Bool:
  match layers:
    case Con{Layer{U.Confirm{current, title, destination}, current_trigger, target, query, layer_occurrence, source_expanded, decision_field, parameter_buffer}, rest}:
      Nat.is_eq(layer_occurrence, occurrence) && (String.eq(current_trigger, trigger) && J.same(CommandCodec.command_json(current), CommandCodec.command_json(command)))
    case _: False{}

def receipt_owned(receipt: ConfirmationReceipt) -> Bool:
  ConfirmationReceipt{command, trigger, occurrence, result, destination, Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}}} = receipt
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
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, previous, draft_model_manual, workspace_git} = session
  Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, value, draft_model_manual, workspace_git}

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

def finish_execution_view_checked(+owned: Bool, +task: Nat, +result: Decision) -> Decision:
  match owned:
    case True{}: complete_choice_value(U.MessageEditor{task}, result)
    case False{}: result

def execution_view_owned(+layers: +List<Layer>, +task: Nat, +occurrence: Nat) -> Bool:
  match layers:
    case Con{Layer{panel, trigger, initial, query, current, source, field, buffer}, rest}:
      Nat.is_eq(current, occurrence) && decision_editor_matches(decision_panel_editor(panel), U.MessageEditor{task})
    case _: False{}

def finish_execution_view(+ok: Bool, +task: Nat, +profile: String, +reasoning: String, +remember: Bool, +occurrence: Nat, +world: M.World(), +result: J.Json, +application: Application) -> Decision:
  Application{previous, +session} = application
  +decision = reply(Application{world, session}, result)
  +completed = finish_execution_view_checked(ok && execution_view_owned(layers(session), task, occurrence), task, decision)
  remember_valid(ok && remember, profile, reasoning, completed)

def finish_worktree_preference(ok: Bool, draft: U.Draft, command: M.Command, result: J.Json, application: Application) -> Decision:
  match ok:
    case True{}:
      +draft_value = draft
      +application_value = application
      request_submitted(worktree_submission_allowed(U.contents(draft_value), application_value), command, draft_value, application_value)
    case False{}:
      Application{world, session} = application
      native_session(Some{draft}, world, result, Nil{}, session, False{})

def complete_command_member(member: Categories.Membership<M.World(), program_world()>, +result: J.Json, completion: Completion, application: Application) -> Decision:
  Categories.Membership{+program, evidence} = member
  match completion:
    case ExecutionViewCompletion{task, profile, reasoning, remember, occurrence}: finish_execution_view(J.boolean(J.get(result, "ok")), task, profile, reasoning, remember, occurrence, program, result, application)
    case ExecutionCompletion{task, profile, reasoning, remember}: finish_execution(J.boolean(J.get(result, "ok")), task, profile, reasoning, remember, program, result, application)
    case DirectCompletion{}:
      Application{previous, session} = application
      native_session(None{}, program, result, Nil{}, retain_previews(session, program), False{})
    case WorktreePreferenceCompletion{draft, command}:
      Application{previous, session} = application
      finish_worktree_preference(J.boolean(J.get(result, "ok")), draft, command, result, Application{program, retain_previews(session, program)})
    case DraftCompletion{draft}:
      Application{previous, session} = application
      native_session(Some{draft}, program, result, Nil{}, retain_previews(session, program), False{})
    case ConfirmationCompletion{command, trigger, destination, occurrence}:
      Application{previous, session} = application
      Session{route, drafts, readers, +layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git} = session
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
    case Con{Layer{U.Confirm{+command, title, destination}, trigger, target, query, layer_occurrence, source_expanded, decision_field, parameter_buffer}, rest}: request_command(command, ConfirmationCompletion{command, trigger, destination, layer_occurrence}, application)
    case _: refuse(application, "No confirmation is open")

# Cancelling an editor drops its complete draft and pending observations. The
# monotone occurrence also seeds a fresh revision, so late accepted results cannot
# settle a reopened project draft with the same editor identity.

def reserve_draft_occurrence(+found: Maybe<&2, U.Draft>, +current: Nat) -> Nat:
  match found:
    case None{}: (current + 1n : Nat)
    case Some{U.Draft{revision, body, feedback, entry}}: Nat.max((revision + 1n : Nat), (current + 1n : Nat))

def without_editor_pending(+pending: +List<Pending>, +editor: U.Editor) -> +List<Pending>:
  match pending:
    case Nil{}: Nil{}
    case Con{Pending{ticket, U.Draft{revision, +body, feedback, entry}, now}, rest}:
      keep_pending(U.same_editor(U.owner(body), editor), Pending{ticket, U.Draft{revision, body, feedback, entry}, now}, without_editor_pending(rest, editor))

def discard_project_session(+editor: U.Editor, +session: Session) -> Session:
  +fresh = reserve_draft_occurrence(find_draft(drafts(session), editor), next_layer(session))
  with_next_layer(fresh, with_pending(without_editor_pending(pending(session), editor), with_drafts(without_draft(drafts(session), editor), session)))

def dismiss_layer_draft(+panel: U.Panel, +application: Application) -> Application:
  match panel:
    case U.EditObject{U.ProjectEditor{id}}:
      Application{program, session} = application
      Application{program, discard_project_session(U.ProjectEditor{id}, session)}
    case _: application

def dismiss_layers(+layers: +List<Layer>, +application: Application) -> Decision:
  match layers:
    case Con{Layer{panel, trigger, initial, query, occurrence, source, field, buffer}, rest}: close_panel(dismiss_layer_draft(panel, application))
    case _: unchanged(application)

def dismiss_panel(+application: Application) -> Decision:
  dismiss_layers(layers(session(application)), application)

def source_origin_inspected(panel: U.Panel, expanded: Bool, field: Maybe<&2, Forms.Field>) -> Bool:
  match panel field:
    case U.ModelPicker{editor} None{}: expanded
    case U.PermissionsConfiguration{editor} None{}: expanded
    case U.WorkspaceConfiguration{editor} None{}: True{}
    case U.EditObject{editor} None{}: True{}
    case _ _: False{}

def source_origin_owned(layers: +List<Layer>, origin: U.Panel) -> Bool:
  match layers:
    case Con{Layer{+panel, trigger, initial, query, occurrence, expanded, field, buffer}, rest}:
      String.eq(panel_target(panel), panel_target(origin)) && source_origin_inspected(panel, expanded, field)
    case _: False{}

def open_source_checked(owned: Bool, origin: U.Panel, trigger: String, application: Application) -> Decision:
  match owned:
    case False{}: refuse(application, "The setting source does not belong to the current inspection")
    case True{}: open_panel(U.PropertySource{origin}, trigger, application)

def open_requested_panel(panel: U.Panel, trigger: String, +application: Application) -> Decision:
  match panel:
    case U.PropertySource{+origin}: open_source_checked(source_origin_owned(layers(session(application)), origin), origin, trigger, application)
    case other: open_panel(other, trigger, application)

def activate_selected(action: U.Action, +application: Application) -> Decision:
  match action:
    case U.SelectProject{project}: observe_workspace_git(begin_task(project, application))
    case U.ToggleProjectGroup{project}: toggle_project(project, application)
    case U.Navigate{route}: visit(route, application)
    case U.BeginTask{+project}: observe_workspace_git(begin_task(project, application))
    case U.EditProject{+project}: project_editor(project, application)
    case U.NewCard{stage}: new_card(stage, application)
    case U.EditCard{card}: card_editor(card, application)
    case U.EditAgent{agent}: agent_editor(application, agent)
    case U.EditTaskGraph{graph}: task_graph_editor(graph, application)
    case U.ForkTask{+task}: open_editor(U.Fork{task, 1n, Nil{}, Context.defaults(Context.ParentTask{task})}, application)
    case U.CompactTask{task}: open_editor(U.Compact{task, None{}}, application)
    case U.Submit{editor}: submit(editor, application)
    case U.RetryWorkspace{editor}: retry_workspace(editor, application)
    case U.ControlTask{task, control}: execute_direct(U.direct_command(U.ControlTask{task, control}), application)
    case U.CancelOperation{task, operation}: execute_direct(U.direct_command(U.CancelOperation{task, operation}), application)
    case U.ReviewApproval{task, operation, allow, reason}: execute_direct(U.direct_command(U.ReviewApproval{task, operation, allow, reason}), application)
    case U.RetryWorktreeArchive{task}: execute_direct(U.direct_command(U.RetryWorktreeArchive{task}), application)
    case U.DeleteProject{+project}: open_panel(U.Confirm{M.DeleteProject{project}, "Delete project", U.ProjectCollection{}}, "project/delete/" ++ Nat.show(project), application)
    case U.DeleteTaskGraph{+graph}: open_panel(U.Confirm{M.FeatureCommand{F.TaskGraphCommand{Graph.Delete{graph}}}, "Delete task graph", U.TaskGraphs{}}, "task-graph/delete/" ++ Nat.show(graph), application)
    case U.BoardCommand{B.Delete{+id, revision}}:
      open_panel(U.Confirm{M.FeatureCommand{F.BoardCommand{B.Delete{id, revision}}}, "Delete card", U.TaskBoard{}}, "card/delete/" ++ Nat.show(id), application)
    case U.BoardCommand{command}: execute_direct(U.direct_command(U.BoardCommand{command}), application)
    case U.OpenPanel{+panel, trigger}: observe_workspace_panel(panel, open_requested_panel(panel, trigger, application))
    case U.TogglePanel{+panel, trigger}: observe_workspace_panel(panel, toggle_panel(panel, trigger, application))
    case U.ClosePanel{}: dismiss_panel(application)
    case U.ConfirmAction{}:
      Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}} = application
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
  Application{program, Session{route, drafts, +readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}} = application
  local(program, Session{route, drafts, (task, disclosed_reader(reader(readers, task), group, occurrence, expanded)) <> Finite.remove(~Reader, readers, task),
    layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}, Nil{})

def navigation_focus(expanded: Bool) -> String:
  match expanded:
    case True{}: "new-task"
    case False{}: "navigation/toggle"

def property_source_panel(panel: U.Panel, editor: U.Editor) -> Bool:
  match panel:
    case U.WorkspaceConfiguration{owner}: U.same_editor(owner, editor)
    case U.PermissionsConfiguration{owner}: U.same_editor(owner, editor)
    case U.ModelPicker{owner}: U.same_editor(owner, editor)
    case U.EditObject{owner}: U.same_editor(owner, editor)
    case _: False{}

def toggle_source_layers(allowed: Bool, panel: U.Panel, trigger: String, initial: String, query: String, occurrence: Nat, source_expanded: Bool, decision_field: Maybe<&2, Forms.Field>, +parameter_buffer: Maybe<&2, String>, rest: +List<Layer>, +application: Application) -> Decision:
  match allowed:
    case False{}: refuse(application, "The property source is not open for this editor")
    case True{}:
      update_requested_view(True{}, panel, trigger, initial, query, occurrence, Bool.not(source_expanded), None{}, None{}, rest, application)

def toggle_property_source_layers(layers: +List<Layer>, +editor: U.Editor, +application: Application) -> Decision:
  match layers:
    case Nil{}: refuse(application, "The property source is not open")
    case Con{Layer{+panel, trigger, initial, query, occurrence, source_expanded, decision_field, parameter_buffer}, rest}:
      toggle_source_layers(property_source_panel(panel, editor), panel, trigger, initial, query, occurrence, source_expanded, decision_field, parameter_buffer, rest, application)

def toggle_property_source(+editor: U.Editor, +application: Application) -> Decision:
  toggle_property_source_layers(layers(session(application)), editor, application)

def property_source_expanded(layers: +List<Layer>, editor: U.Editor) -> Bool:
  match layers:
    case Con{Layer{panel, trigger, initial, query, occurrence, source_expanded, decision_field, parameter_buffer}, rest}: property_source_panel(panel, editor) && source_expanded
    case _: False{}

def initial_parameter_buffer(+field: Maybe<&2, Forms.Field>, +observed: Forms.Observed) -> Maybe<&2, String>:
  match field observed:
    case Some{Forms.ReasoningEffort{}} Forms.ModelValue{profile, reasoning}: Some{reasoning}
    case _ _: None{}

def parameter_observation(+found: Maybe<&2, U.Draft>, +world: M.World()) -> Forms.Observed:
  match found:
    case None{}: Forms.NotApplicable{}
    case Some{U.Draft{revision, body, feedback, entry}}: Forms.observed(body, Forms.ReasoningEffort{}, world)

def editor_parameter(+editor: U.Editor, +application: Application) -> Forms.Observed:
  parameter_observation(find_draft(drafts(session(application)), editor), program(application))

def decision_focus_layers(layers: +List<Layer>, +editor: U.Editor, +field: Maybe<&2, Forms.Field>, +application: Application) -> Decision:
  match layers:
    case Nil{}: unchanged(application)
    case Con{Layer{+panel, trigger, initial, query, occurrence, source_expanded, previous, parameter_buffer}, rest}:
      decision_layer_update(decision_editor_matches(decision_panel_editor(panel), editor), panel, trigger, initial, query, occurrence, source_expanded, field, initial_parameter_buffer(field, editor_parameter(editor, application)), rest, application)

def enter_retained_decision(+retained: Bool, +editor: U.Editor, +field: Forms.Field, +application: Application) -> Decision:
  match retained:
    case True{}: decision_focus_layers(layers(session(application)), editor, Some{field}, application)
    case False{}: unchanged(application)

def retained_parameter_model(+observed: Forms.Observed, +world: M.World()) -> Bool:
  match observed:
    case Forms.ModelValue{profile, reasoning}: permitted_preference(D.find_profile(Board.profiles(world), profile), reasoning)
    case _: False{}

def retained_context_policy(+field: Forms.Field, +approval: Context.ApprovalChoice) -> Bool:
  match field approval:
    case Forms.ApprovalReviewer{} Context.AutomaticReview{profile}: True{}
    case Forms.ApprovalPolicy{} _: True{}
    case Forms.SandboxMode{} Context.Unrestricted{}: False{}
    case Forms.NetworkAccess{} Context.Unrestricted{}: False{}
    case Forms.SandboxMode{} _: True{}
    case Forms.NetworkAccess{} _: True{}
    case _ _: False{}

def retained_context_dependency(+field: Forms.Field, +observed: Forms.Observed) -> Bool:
  match observed:
    case Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}, reviewers}:
      retained_context_policy(field, Context.observed_approval(approval))
    case _: False{}

def retained_dependency_body(+field: Forms.Field, +body: U.Body, +world: M.World()) -> Bool:
  match field:
    case Forms.ReasoningEffort{}: retained_parameter_model(Forms.observed(body, field, world), world)
    case Forms.WorkspacePrimary{}: True{}
    case other: retained_context_dependency(other, Forms.observed(body, other, world))

def retained_dependency_found(+found: Maybe<&2, U.Draft>, +field: Forms.Field, +world: M.World()) -> Bool:
  match found:
    case None{}: False{}
    case Some{U.Draft{revision, body, feedback, entry}}: retained_dependency_body(field, body, world)

def enter_known_decision(field: Maybe<&2, Forms.Field>, +editor: U.Editor, +application: Application) -> Decision:
  match field:
    case None{}: unchanged(application)
    case Some{+field}: enter_retained_decision(retained_dependency_found(find_draft(drafts(session(application)), editor), field, program(application)), editor, field, application)

def enter_decision(editor: U.Editor, field_key: String, application: Application) -> Decision:
  enter_known_decision(Forms.choice_field_by_key(field_key), editor, application)

def search_choices(query: String, application: Application) -> Decision:
  Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}} = application
  match layers:
    case Nil{}: local(program, Session{route, drafts, readers, Nil{}, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}, Nil{})
    case Con{Layer{panel, trigger, initial, previous, layer_occurrence, source_expanded, decision_field, parameter_buffer}, rest}:
      local(program, Session{route, drafts, readers, Layer{panel, trigger, initial, query, layer_occurrence, source_expanded, decision_field, parameter_buffer} <> rest, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}, Nil{})

def action_leaves_menu(action: U.Action) -> Bool:
  match action:
    case U.OpenPanel{panel, trigger}: False{}
    case U.TogglePanel{panel, trigger}: False{}
    case U.ClosePanel{}: False{}
    case _: True{}

def remove_action_menu(layers: +List<Layer>) -> +List<Layer>:
  match layers:
    case Con{Layer{U.ObjectActions{subject}, trigger, initial, query, layer_occurrence, source_expanded, decision_field, parameter_buffer}, rest}: rest
    case other: other

def dismiss_action_menu(leaves: Bool, application: Application) -> Application:
  match leaves:
    case False{}: application
    case True{}:
      Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}} = application
      Application{program, Session{route, drafts, readers, remove_action_menu(layers), attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}}

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

# The layer occurrence correlates completion with the view that requested it.

def owned_decision_field(+owned: Bool, +field: Maybe<&2, Forms.Field>) -> Maybe<&2, Forms.Field>:
  match owned:
    case True{}: field
    case False{}: None{}

def requested_decision(+layers: +List<Layer>, +editor: U.Editor) -> Maybe<&2, Forms.Field>:
  match layers:
    case Con{Layer{panel, trigger, initial, query, occurrence, source, field, buffer}, rest}:
      owned_decision_field(decision_editor_matches(decision_panel_editor(panel), editor), field)
    case _: None{}

def owned_parameter_buffer(+owned: Bool, +buffer: Maybe<&2, String>) -> Maybe<&2, String>:
  match owned:
    case True{}: buffer
    case False{}: None{}

def requested_parameter(+layers: +List<Layer>, +editor: U.Editor) -> Maybe<&2, String>:
  match layers:
    case Con{Layer{panel, trigger, initial, query, occurrence, source, Some{Forms.ReasoningEffort{}}, buffer}, rest}:
      owned_parameter_buffer(decision_editor_matches(decision_panel_editor(panel), editor), buffer)
    case _: None{}

def open_parameter_entry(+entry: Forms.Entry) -> Bool:
  match entry:
    case Forms.SingleLine{}: True{}
    case _: False{}

def open_parameter_profile(+found: Maybe<&2, D.Profile>) -> Bool:
  match found:
    case None{}: False{}
    case Some{profile}: open_parameter_entry(Forms.profile_effort_entry(profile))

def open_parameter_observation(+observed: Forms.Observed, +world: M.World()) -> Bool:
  match observed:
    case Forms.ModelValue{profile, reasoning}: open_parameter_profile(D.find_profile(Board.profiles(world), profile))
    case _: False{}

def write_parameter_checked(+allowed: Bool, +layers: +List<Layer>, +value: String, +application: Application) -> Decision:
  match allowed layers:
    case True{} Con{Layer{panel, trigger, initial, query, occurrence, source, field, buffer}, rest}:
      local(program(application), with_layers(Layer{panel, trigger, initial, query, occurrence, source, field, Some{value}} <> rest, session(application)), Nil{})
    case _ _: refuse(application, "The open parameter is not available in this view")

def write_decision_focused(+focus: Maybe<&2, Forms.Field>, +editor: U.Editor, +value: String, +application: Application) -> Decision:
  match focus:
    case Some{Forms.ReasoningEffort{}}:
      write_parameter_checked(open_parameter_observation(editor_parameter(editor, application), program(application)), layers(session(application)), value, application)
    case _: refuse(application, "The open parameter is not available in this view")

def write_decision_parameter(+editor: U.Editor, +value: String, +application: Application) -> Decision:
  write_decision_focused(requested_decision(layers(session(application)), editor), editor, value, application)

def complete_parameter_value(+permitted: Bool, +editor: U.Editor, +profile: String, +value: String, +application: Application) -> Decision:
  match permitted:
    case True{}: manual_edit(editor, U.ChooseModel{profile, value}, application)
    case False{}: refuse(application, "Choose an available model and permitted reasoning effort.")

def complete_parameter_observed(+observed: Forms.Observed, +buffer: Maybe<&2, String>, +editor: U.Editor, +application: Application) -> Decision:
  match observed buffer:
    case Forms.ModelValue{+profile, previous} Some{+value}:
      +found = D.find_profile(Board.profiles(program(application)), profile)
      complete_parameter_value(open_parameter_profile(found) && permitted_preference(found, value), editor, profile, value, application)
    case _ _: refuse(application, "The open parameter is not available in this view")

def complete_decision_parameter(+editor: U.Editor, +application: Application) -> Decision:
  complete_parameter_observed(editor_parameter(editor, application), requested_parameter(layers(session(application)), editor), editor, application)

# Requested inspection remains the parent while one of its fields is open.

def user(input: U.Input, application: Application) -> Decision:
  match input:
    case U.WriteDecisionParameter{editor, value}: write_decision_parameter(editor, value, application)
    case U.CompleteDecisionParameter{editor}: complete_decision_parameter(editor, application)
    case U.EnterDecision{editor, field_key}: enter_decision(editor, field_key, application)
    case U.LeaveDecision{editor}: leave_decision(editor, application)
    case U.TogglePropertySource{editor}: toggle_property_source(editor, application)
    case U.Activate{action}: activate(action, application)
    case U.EditDraft{+editor, +change}: observe_workspace_edit(editor, change, manual_edit(editor, change, application))
    case U.ReadTimeline{task, generation, intent}: read_current(task, generation, intent, application)
    case U.SetDisclosure{task, group, occurrence, expanded}: disclose(task, group, occurrence, expanded, application)
    case U.SetNavigation{+expanded}:
      Application{program, Session{route, drafts, readers, layers, attention, previous, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}} = application
      +target = navigation_focus(expanded)
      local(program, Session{route, drafts, readers, layers, target, set_navigation(expanded, previous), filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}, [Attend{target}])
    case U.SearchChoices{query}: search_choices(query, application)
    case U.FilterBoard{filter}:
      Application{program, Session{route, drafts, readers, layers, attention, navigation, previous, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}} = application
      local(program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}, Nil{})

def observe_preview(observation: Live.Observation, application: Application) -> Decision:
  Application{+program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}} = application
  local(program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, Live.observe(observation, previews, program), code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}, Nil{})

def content_effects(effects: +List<Content.Effect>, +identity: Content.Identity) -> +List<Effect>:
  match effects:
    case Nil{}: Nil{}
    case Con{effect, rest}: ContentEffect{identity, effect} <> content_effects(rest, identity)

def content_result(result: Content.Decision, +identity: Content.Identity, application: Application) -> Decision:
  Content.Decision{block, effects} = result
  Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}} = application
  local(program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, Content.save_block(code_blocks, identity, block), next_layer, model_preference, draft_model_manual, workspace_git}, content_effects(effects, identity))

def content_input(+identity: Content.Identity, input: Content.Input, application: Application) -> Decision:
  Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, +code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}} = application
  content_result(Content.step(Content.find_block(code_blocks, identity), input), identity,
    Application{program, Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}})

def restore_preference(+profile: String, +reasoning: String, +application: Application) -> Decision:
  Application{+program, +session} = application
  local(program, resolve_model_draft(with_preference(Some{ModelPreference{profile, reasoning}}, session), program), Nil{})
