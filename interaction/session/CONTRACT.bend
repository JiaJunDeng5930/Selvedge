import ../experience/PROGRAM.bend as UX
import ../../bendlib/categories.bend as Categories
import Base
import ../submission/FIELDS.bend as Forms
import ../submission/CONTRACT.bend as SubmissionRule
import ../../harness/INVARIANTS.bend as I
import ../../harness/MODEL.bend as M
import ../../bendlib/component.bend as C
import ../../harness/DOMAIN.bend as D
import ../../harness/COMMANDS.bend as Commands
import ../../bendlib/json.bend as J
import ../../harness/transport/command-codec.bend as CommandCodec
import ./MODEL.bend as E
import ./PROGRAM.bend as ExperienceProgram
import ../INPUT.bend as U
import ../../features/board/MODEL.bend as B
import ../../features/board/STATE.bend as Board
import ../../bendlib/association-map.bend as Finite
import ../conversation/CODE.bend as Content
import ../conversation/OUTPUT.bend as Live
import ../services/CONTEXT.bend as Context
import ../interactive_markdown/TYPES.bend as Interactive
import ../interactive_markdown/MODEL.bend as InteractiveCore
import ../interactive_markdown/DOCUMENTS.bend as Documents
import ../interactive_markdown/documents-contract.bend as DocumentRequirement
import ../../features/work/MODEL.bend as Work
import ../../features/worktree/MODEL.bend as Worktree
import ../../harness/conversation/TITLE.bend as Title
import ../../harness/features/MODEL.bend as F

def post(decision: E.Decision) -> E.Application:
  E.Decision{+application, reply, runtime, interaction, durable} = decision
  application

def work_creation_captures_generation(+application: E.Application) -> Type:
  {E.create_work(application) == E.request_command(M.FeatureCommand{F.WorkCommand{Work.Create{""}}}, E.WorkCreationCompletion{(E.selection_generation(E.session(application)) + 1n : Nat), E.next_layer(E.session(application))}, E.advance_selection(application)) : E.Decision}

law global_navigation_panel_identity:
  {E.panel_target(U.GlobalNavigation{}) == "global-navigation" : String}

law global_navigation_uses_existing_layer_opening:
  @+trigger:String -> @+application:E.Application ->
  {E.open_requested_panel(U.GlobalNavigation{}, trigger, application) == E.open_panel(U.GlobalNavigation{}, trigger, application) : E.Decision}

law global_navigation_consumption_retains_the_underlying_session:
  @+program:M.World() -> @+session:E.Session -> @+trigger:String -> @initial:String -> @query:String -> @occurrence:Nat -> @source:Bool -> @field:Maybe<&2, Forms.Field> -> @buffer:Maybe<&2, String> -> @+rest:+List<E.Layer> ->
  {E.consume_global_navigation_layers(E.Layer{U.GlobalNavigation{}, trigger, initial, query, occurrence, source, field, buffer} <> rest, program, session) ==
    E.from_program(program, E.with_next_layer((E.next_layer(session) + 1n : Nat), E.with_attention(trigger, E.with_layers(rest, session)))) : E.Application}

law global_navigation_settings_origin_is_consumed:
  @+program:M.World() -> @+session:E.Session -> @+trigger:String -> @+initial:String -> @+query:String -> @+occurrence:Nat -> @+source:Bool -> @+field:Maybe<&2, Forms.Field> -> @+buffer:Maybe<&2, String> -> @+rest:+List<E.Layer> ->
  @observed:{E.layers(session) == E.Layer{U.GlobalNavigation{}, trigger, initial, query, occurrence, source, field, buffer} <> rest : +List<E.Layer>} ->
  {E.consume_global_navigation(E.from_program(program, session)) ==
    E.from_program(program, E.with_next_layer((E.next_layer(session) + 1n : Nat), E.with_attention(trigger, E.with_layers(rest, session)))) : E.Application}

law global_navigation_consumption_without_a_layer_is_unchanged:
  @+program:M.World() -> @+session:E.Session ->
  {E.consume_global_navigation_layers(Nil{}, program, session) == E.from_program(program, session) : E.Application}

law global_navigation_dismissal_keeps_applied_drafts:
  @trigger:String -> @initial:String -> @query:String -> @occurrence:Nat -> @source:Bool -> @field:Maybe<&2, Forms.Field> -> @buffer:Maybe<&2, String> -> @rest:+List<E.Layer> -> @+application:E.Application ->
  {E.dismiss_layers(E.Layer{U.GlobalNavigation{}, trigger, initial, query, occurrence, source, field, buffer} <> rest, application) == E.close_panel(application) : E.Decision}

law navigation_clears_transient_layers:
  @+route:U.Route -> @+application:E.Application ->
  {E.layers(E.session(post(E.navigate(route, application)))) == Nil{} : +List<E.Layer>}

law global_navigation_selection_uses_existing_visit:
  @+destination:U.Route -> @+program:M.World() -> @+session:E.Session -> @+trigger:String -> @+initial:String -> @+query:String -> @+occurrence:Nat -> @+source:Bool -> @+field:Maybe<&2, Forms.Field> -> @+buffer:Maybe<&2, String> -> @+rest:+List<E.Layer> ->
  {E.activate(U.Navigate{destination}, E.from_program(program, E.with_layers(E.Layer{U.GlobalNavigation{}, trigger, initial, query, occurrence, source, field, buffer} <> rest, session))) ==
    E.visit(destination, E.from_program(program, E.with_layers(E.Layer{U.GlobalNavigation{}, trigger, initial, query, occurrence, source, field, buffer} <> rest, session))) : E.Decision}

def task_visibility_session(expanded:Bool, program:M.World(), session:E.Session) -> E.Session:
  E.session(post(ExperienceProgram.step(E.UserInput{U.SetNavigation{expanded}}, E.from_program(program, session))))

law task_visibility_user_transition_preserves_the_complete_frame:
  @+expanded:Bool -> @+program:M.World() -> @+session:E.Session ->
  {ExperienceProgram.step(E.UserInput{U.SetNavigation{expanded}}, E.from_program(program, session)) ==
    E.local(program, E.with_navigation(E.advance_navigation_selection(E.set_navigation(expanded, E.navigation(session))), E.with_attention(E.navigation_focus(expanded), session)), [E.Attend{E.navigation_focus(expanded)}]) : E.Decision}

law task_visibility_selection_epoch_advances_once:
  @expanded:Bool -> @program:M.World() -> @+session:E.Session ->
  {E.selection_generation(task_visibility_session(expanded, program, session)) == (E.selection_generation(session) + 1n : Nat) : Nat}

law task_visibility_invalidates_the_previous_work_creation_epoch:
  @expanded:Bool -> @program:M.World() -> @+session:E.Session -> @layer_generation:Nat ->
  {E.work_creation_current(E.selection_generation(session), layer_generation, task_visibility_session(expanded, program, session)) == False{} : Bool}

law task_visibility_stale_work_creation_keeps_the_new_interaction:
  @+expanded:Bool -> @+previous:M.World() -> @+session:E.Session -> @+layer_generation:Nat -> @+program:M.World() -> @+result:J.Json ->
  @valid:{I.world(program) == True{} : Bool} ->
  {ExperienceProgram.step(E.CommandCompleted{program, result, E.WorkCreationCompletion{E.selection_generation(session), layer_generation}}, E.from_program(previous, task_visibility_session(expanded, previous, session))) ==
    E.Decision{E.from_program(program, E.retain_previews(task_visibility_session(expanded, previous, session), program)), result, Nil{}, Nil{}, False{}} : E.Decision}

type WorkRequirements is Type:
  WorkRequirements{
    draft_owner: @+work:Maybe<&2, Nat> -> @message:U.Text -> @profile:String -> @reasoning:String -> @context:Context.Configuration -> @enabled:Bool ->
      {U.owner(U.NewTask{message, profile, reasoning, context, enabled, work}) == U.NewTaskEditor{work} : U.Editor},
    member_creation: @+work:Nat -> @+message:U.Text -> @+profile:String -> @+reasoning:String -> @+context:Context.Configuration -> @+enabled:Bool -> @now:U32 ->
      {U.command(U.NewTask{message, profile, reasoning, context, enabled, Some{work}}, now) == M.FeatureCommand{F.WorkCommand{Work.CreateTask{work, profile, reasoning, U.text(message), Context.settings(context), enabled}}} : M.Command},
    independent_creation: @+message:U.Text -> @+profile:String -> @+reasoning:String -> @+context:Context.Configuration -> @+enabled:Bool -> @now:U32 ->
      {U.command(U.NewTask{message, profile, reasoning, context, enabled, None{}}, now) == U.task_creation(enabled, profile, reasoning, U.text(message), Context.settings(context)) : M.Command},
    rename_owner: @+work:Nat -> @+name:String -> @now:U32 ->
      {U.command(U.WorkName{work, name}, now) == M.FeatureCommand{F.WorkCommand{Work.Rename{work, name}}} : M.Command},
    selection_keeps_previous_location: @+work:Maybe<&2, Nat> -> @+route:U.Route -> @intent:E.NavigationIntent -> @collapsed:+List<Nat> -> @+previous:Maybe<&2, Nat> -> @+visits:+List<E.WorkVisit> -> @+generation:Nat ->
      {E.select_work_navigation(work, route, E.NavigationState{intent, collapsed, previous, visits, generation}) == E.NavigationState{intent, collapsed, work, E.WorkVisit{previous, route} <> E.without_work_visit(visits, previous), generation} : E.NavigationState},
    other_scope_completion_keeps_location: @work:Maybe<&2, Nat> -> @route:U.Route -> @layers:+List<E.Layer> -> @result:J.Json -> @+application:E.Application ->
      {E.finish_scoped_task(False{}, work, route, layers, result, application) == E.unchanged(application) : E.Decision},
    member_model_is_retained: @work:Nat -> @manual:Bool -> {E.creation_model_chosen(Some{work}, manual) == True{} : Bool},
    member_completion_keeps_other_draft_preference: @work:Nat -> @+session:E.Session ->
      {E.completed_creation_model(Some{work}, session) == session : E.Session},
    member_model_choice_keeps_independent_manual_state: @work:Nat -> @+change:U.Edit -> @+result:E.Decision ->
      {E.remember_creation_choice(Some{work}, change, result) == E.remember_choice(change, result) : E.Decision},
    navigation_advances_generation: @+navigation:E.NavigationState ->
      {E.navigation_generation(E.navigation_after_visit(navigation)) == (E.navigation_generation(navigation) + 1n : Nat) : Nat},
    repeated_work_selection_advances_generation: @work:Maybe<&2, Nat> -> @+application:E.Application ->
      {E.select_work_changed(True{}, work, application) == E.unchanged(E.advance_selection(E.dismiss_work_overview(application))) : E.Decision},
    current_overview_selection_dismisses: @+trigger:String -> @initial:String -> @query:String -> @occurrence:Nat -> @source:Bool -> @field:Maybe<&2, Forms.Field> -> @buffer:Maybe<&2, String> -> @+rest:+List<E.Layer> -> @+program:M.World() -> @+session:E.Session ->
      {E.dismiss_work_overview_layers(E.Layer{U.WorkOverview{}, trigger, initial, query, occurrence, source, field, buffer} <> rest, E.from_program(program, session)) == E.from_program(program, E.with_attention(trigger, E.with_layers(rest, session))) : E.Application},
    overview_selection_exposes_scope: @+work:Maybe<&2, Nat> -> @+program:M.World() -> @+session:E.Session -> @+result:J.Json -> @+runtime:+List<M.Effect()> -> @interaction:+List<E.Effect> -> @+durable:Bool ->
      {E.focus_work_selection(True{}, work, E.Decision{E.from_program(program, session), result, runtime, interaction, durable}) == E.Decision{E.from_program(program, E.with_attention(E.work_selection_target(E.route(session), work), session)), result, runtime, [E.Attend{E.work_target(work)}, E.Attend{E.work_selection_target(E.route(session), work)}], durable} : E.Decision},
    refused_overview_selection_keeps_interaction: @work:Maybe<&2, Nat> -> @+decision:E.Decision ->
      {E.focus_work_selection(False{}, work, decision) == decision : E.Decision},
    overview_opens_at_selected_card: @+program:M.World() -> @+session:E.Session -> @+result:J.Json -> @+runtime:+List<M.Effect()> -> @interaction:+List<E.Effect> -> @+durable:Bool ->
      {E.attend_work_overview(E.Decision{E.from_program(program, session), result, runtime, interaction, durable}) == E.Decision{E.from_program(program, E.with_attention("overview/" ++ E.work_target(E.active_work(session)), session)), result, runtime, [E.Attend{"overview/" ++ E.work_target(E.active_work(session))}], durable} : E.Decision},
    overview_activation_uses_selected_card: @+trigger:String -> @+application:E.Application ->
      {E.open_requested_panel(U.WorkOverview{}, trigger, application) == E.open_work_overview(trigger, application) : E.Decision},
    creation_captures_new_selection_generation: @+application:E.Application ->
      work_creation_captures_generation(application),
    creation_exposes_selected_tab: @+work:Nat -> @+application:E.Application ->
      {E.created_work_id(Some{work}, application) == E.expose_created_work(work, E.select_work(Some{work}, application)) : E.Decision},
    tab_exposure_focuses_member_composer: @+work:Nat -> @+program:M.World() -> @+session:E.Session -> @+result:J.Json -> @+runtime:+List<M.Effect()> -> @+interaction:+List<E.Effect> -> @+durable:Bool ->
      @accepted:{J.boolean(J.get(result, "ok")) == True{} : Bool} ->
      {E.expose_created_work(work, E.Decision{E.from_program(program, session), result, runtime, interaction, durable}) == E.Decision{E.from_program(program, E.with_attention("message-text", session)), result, runtime, [E.Attend{"work/" ++ Nat.show(work)}, E.Attend{"message-text"}], durable} : E.Decision},
    refused_selection_keeps_attention: @work:Nat -> @+application:E.Application -> @+result:J.Json -> @+runtime:+List<M.Effect()> -> @+interaction:+List<E.Effect> -> @+durable:Bool ->
      @refused:{J.boolean(J.get(result, "ok")) == False{} : Bool} ->
      {E.expose_created_work(work, E.Decision{application, result, runtime, interaction, durable}) == E.Decision{application, result, runtime, interaction, durable} : E.Decision},
    rejected_creation_keeps_interaction: @result:J.Json -> @+application:E.Application ->
      {E.created_work_checked(False{}, result, application) == E.unchanged(application) : E.Decision},
    stale_creation_keeps_current_interaction: @+result:J.Json -> @+application:E.Application ->
      {E.complete_work_creation(False{}, result, application) == E.Decision{application, result, Nil{}, Nil{}, False{}} : E.Decision},
    workspace_observation_uses_active_scope: @+application:E.Application ->
      {E.current_primary(application) == E.new_task_primary(E.find_draft(E.drafts(E.session(application)), E.creation_editor(E.session(application))), E.program(application)) : Maybe<&2, String>},
    selection_observes_scoped_workspace: @+work:Maybe<&2, Nat> -> @+application:E.Application ->
      {E.activate_selected(U.SelectWork{work}, application) == E.observe_scope_workspace(E.select_work(work, application)) : E.Decision},
    refused_scope_observation_is_unchanged: @+decision:E.Decision ->
      {E.observe_scope_workspace_checked(False{}, decision) == decision : E.Decision},
    accepted_scope_observes_after_focus: @+decision:E.Decision ->
      {E.observe_scope_workspace_checked(True{}, decision) == E.observe_workspace_git(decision) : E.Decision}
  }

law work_evidence:
  WorkRequirements

def model_choice_spec(valid: Bool, +profile: String, +reasoning: String, +application: E.Application) -> E.Decision:
  match valid:
    case True{}: E.remember_manual(U.ChooseModel{profile, reasoning}, E.close_selected_choice(U.ChooseModel{profile, reasoning}, U.NewTaskEditor{None{}}, E.edit(U.NewTaskEditor{None{}}, U.ChooseModel{profile, reasoning}, application)))
    case False{}: E.Decision{application, D.failure("interaction_refused", "Choose an available model and permitted reasoning effort."), Nil{}, Nil{}, False{}}

def catalog_selection_if(valid: Bool, +profile: D.Profile, fallback: Sigma<&2, &2, String, (_ => String)>) -> Sigma<&2, &2, String, (_ => String)>:
  match valid:
    case True{}: (D.profile_key(profile), D.profile_default(profile))
    case False{}: fallback

def catalog_selection(profiles: +List<D.Profile>) -> Sigma<&2, &2, String, (_ => String)>:
  match profiles:
    case Nil{}: ("", "")
    case Con{+profile, rest}: catalog_selection_if(Bool.not(D.is_codex_auto_review(profile)) && D.profile_valid(profile) && D.profile_permitted(profile, D.profile_default(profile)), profile, catalog_selection(rest))

def preference_selection_if(valid: Bool, value: E.ModelPreference, profiles: +List<D.Profile>) -> Sigma<&2, &2, String, (_ => String)>:
  match valid value:
    case True{} E.ModelPreference{profile, reasoning}: (profile, reasoning)
    case False{} _: catalog_selection(profiles)

def preference_selection(value: Maybe<&2, E.ModelPreference>, +profiles: +List<D.Profile>) -> Sigma<&2, &2, String, (_ => String)>:
  match value:
    case None{}: catalog_selection(profiles)
    case Some{+selection}:
      E.ModelPreference{profile, reasoning} = selection
      preference_selection_if(E.permitted_preference(D.find_profile(profiles, profile), reasoning), selection, profiles)

def selected_model_session(selection: Sigma<&2, &2, String, (_ => String)>, revision: Nat, message: U.Text, context: Context.Configuration, feedback: U.Feedback, directory_entry: String, create_worktree: Bool, session: E.Session, work: Maybe<&2, Nat>) -> E.Session:
  (selected, effort) = selection
  E.with_draft(session, U.Draft{revision, U.NewTask{message, selected, effort, context, create_worktree, work}, feedback, directory_entry})

def model_resolution_if(valid: Bool, draft: U.Draft, +profiles: +List<D.Profile>, +session: E.Session) -> E.Session:
  match valid draft:
    case False{} U.Draft{revision, U.NewTask{message, profile, reasoning, context, create_worktree, work}, feedback, directory_entry}:
      selected_model_session(preference_selection(E.preference(session), profiles), revision, message, context, feedback, directory_entry, create_worktree, session, work)
    case _ _: session

def model_resolution_found(found: Maybe<&2, U.Draft>, +profiles: +List<D.Profile>, +session: E.Session) -> E.Session:
  match found:
    case Some{U.Draft{revision, U.NewTask{message, +profile, +reasoning, context, create_worktree, +work}, feedback, directory_entry}}:
      model_resolution_if(E.creation_model_chosen(work, E.manual_model(session)) && E.permitted_preference(D.find_profile(profiles, profile), reasoning), U.Draft{revision, U.NewTask{message, profile, reasoning, context, create_worktree, work}, feedback, directory_entry}, profiles, session)
    case _: session

def model_resolution(+session: E.Session, +world: M.World()) -> E.Session:
  model_resolution_found(E.find_draft(E.drafts(session), E.creation_editor(session)), Board.profiles(world), session)

def begin_focus(+target: String, +world: M.World(), +session: E.Session) -> E.Decision:
  E.local(world, E.with_navigation(E.navigation_after_visit(E.navigation(session)), E.with_attention(target, E.with_layers(Nil{}, E.with_route(U.Start{}, session)))), [E.Attend{target}])

def begin_changed_spec(result: Result<&2, &2, String, U.Body>, revision: Nat, directory_entry: String, +world: M.World(), +session: E.Session) -> E.Decision:
  match result:
    case Fail{reason}: E.reply(E.from_program(world, session), D.failure("interaction_refused", reason))
    case Done{+body}: begin_focus("composer/" ++ U.editor_key(U.owner(body)), world, E.with_draft(session, U.Draft{(revision + 1n : Nat), body, U.Editing{}, directory_entry}))

def begin_existing_spec(found: Maybe<&2, U.Draft>, origin: Context.Origin, +world: M.World(), +session: E.Session) -> E.Decision:
  match found:
    case None{}: begin_focus("composer/" ++ U.editor_key(E.creation_editor(session)), world, session)
    case Some{U.Draft{revision, body, feedback, directory_entry}}:
      begin_changed_spec(U.apply_edit(U.ConfigureContext{Context.ChooseOrigin{origin}}, body, world), revision, directory_entry, world, session)

def begin_resolved_spec(+origin: Context.Origin, +world: M.World(), +session: E.Session) -> E.Decision:
  begin_existing_spec(E.find_draft(E.drafts(session), E.creation_editor(session)), origin, world, session)

def begin_task_spec(project: Maybe<&2, Nat>, +world: M.World(), session: E.Session) -> E.Decision:
  begin_resolved_spec(E.context_project(project), world, model_resolution(session, world))

type ReadingLocation is Data:
  ReadingLocation{position: U.ReadingIntent, disclosures: +List<E.Disclosure>}

def runtime_program(decision: M.Decision()) -> M.World():
  C.Decision{+program, result, effects} = decision
  program

def drafts(application: E.Application) -> +List<U.Draft>:
  E.drafts(E.session(application))

def readers(application: E.Application) -> +List<Finite.Entry(E.Reader)>:
  E.readers(E.session(application))

type SessionContent is Data:
  SessionContent{drafts: +List<U.Draft>, readers: +List<Finite.Entry(E.Reader)>}

def attention(application: E.Application) -> String:
  E.attention(E.session(application))

def layers(application: E.Application) -> +List<E.Layer>:
  E.layers(E.session(application))

type NativeFrame is Data:
  NativeFrame{program: M.World(), route: U.Route, drafts: +List<U.Draft>, readers: +List<Finite.Entry(E.Reader)>,
    layers: +List<E.Layer>, attention: String, navigation: E.NavigationState, filter: B.Filter, now: U32,
    next_ticket: Nat, pending: +List<E.Pending>, code_blocks: +List<Content.Block>}

def previews(application: E.Application) -> +List<Live.Output>:
  E.previews(E.session(application))

type Residence is Data:
  Residence{program: M.World(), drafts: +List<U.Draft>, readers: +List<Finite.Entry(E.Reader)>,
    pending: +List<E.Pending>, previews: +List<Live.Output>, code_blocks: +List<Content.Block>,
    route: U.Route, navigation: E.NavigationState, filter: B.Filter, now: U32, next_ticket: Nat}

def interaction_effects(decision: E.Decision) -> +List<E.Effect>:
  E.Decision{application, reply, runtime, +interaction, durable} = decision
  interaction

def residence(+application: E.Application) -> Residence:
  program = E.program(application)
  +observed_session = E.session(application)
  route = E.route(observed_session)
  +drafts = E.drafts(observed_session)
  +readers = E.readers(observed_session)
  navigation = E.navigation(observed_session)
  filter = E.filter(observed_session)
  now = E.now(observed_session)
  next = E.next_ticket(observed_session)
  +pending = E.pending(observed_session)
  +previews = E.previews(observed_session)
  +code_blocks = E.code_blocks(observed_session)
  Residence{program, drafts, readers, pending, previews, code_blocks, route, navigation, filter, now, next}

def session_content_of(+session: E.Session) -> SessionContent:
  +drafts = E.drafts(session)
  +readers = E.readers(session)
  SessionContent{drafts, readers}

def session_content(application: E.Application) -> SessionContent:
  session = E.session(application)
  session_content_of(session)

def native_frame(+application: E.Application) -> NativeFrame:
  program = E.program(application)
  +observed_session = E.session(application)
  +route = E.route(observed_session)
  +drafts = E.drafts(observed_session)
  +readers = E.readers(observed_session)
  +layers = E.layers(observed_session)
  attention = E.attention(observed_session)
  navigation = E.navigation(observed_session)
  filter = E.filter(observed_session)
  now = E.now(observed_session)
  next = E.next_ticket(observed_session)
  +pending = E.pending(observed_session)
  +code_blocks = E.code_blocks(observed_session)
  NativeFrame{program, route, drafts, readers, layers, attention, navigation, filter, now, next, pending, code_blocks}

def reading_location(reader: E.Reader) -> ReadingLocation:
  E.Reader{generation, position, +disclosures} = reader
  ReadingLocation{position, disclosures}

def reading_owner(application: E.Application, +task: Nat, generation: Nat) -> Bool:
  +observed_session = E.session(application)
  route = E.route(observed_session)
  readers = E.readers(observed_session)
  E.task_visible(observed_session, task) && Nat.is_eq(generation, E.reader_generation(E.reader(readers, task)))

def opened_application(+application: E.Application, +panel: U.Panel, trigger: String) -> E.Decision:
  +program = E.program(application)
  +observed_session = E.session(application)
  layers = E.layers(observed_session)
  +next_layer = E.next_layer(observed_session)
  +target = E.panel_target(panel)
  E.Decision{E.from_program(program, E.with_next_layer((next_layer + 1n : Nat), E.with_attention(target, E.with_layers(E.Layer{panel, trigger, target, "", next_layer, False{}, None{}, None{}} <> E.without_panel(layers, E.panel_target(panel)), observed_session)))),
    D.success(J.Null{}), Nil{}, [E.Attend{target}], False{}}

type Requirements is Type:
  Requirements{
    modal_open_allocation: @+application:E.Application -> @+panel:U.Panel -> @+trigger:String ->
      {E.open_panel(panel, trigger, application) == opened_application(application, panel, trigger) : E.Decision},
    modal_open_residence: @+application:E.Application -> @+panel:U.Panel -> @trigger:String ->
      {residence(post(E.open_panel(panel, trigger, application))) == residence(application) : Residence},
    modal_open_attention: @+application:E.Application -> @+panel:U.Panel -> @trigger:String ->
      {attention(post(E.open_panel(panel, trigger, application))) == E.panel_target(panel) : String},
    modal_open_effects: @+application:E.Application -> @+panel:U.Panel -> @trigger:String ->
      {interaction_effects(E.open_panel(panel, trigger, application)) == [E.Attend{E.panel_target(panel)}] : +List<E.Effect>},
    modal_close_nonempty: @+session:E.Session -> @+program:M.World() -> @+panel:U.Panel -> @+trigger:String -> @initial:String ->
      @query:String -> @+layer_occurrence:Nat -> @+source_expanded:Bool -> @+decision_field:Maybe<&2, Forms.Field> -> @+parameter_buffer:Maybe<&2, String> -> @+rest:+List<E.Layer> ->
      @observed_layers:{E.layers(session) == E.Layer{panel, trigger, initial, query, layer_occurrence, source_expanded, decision_field, parameter_buffer} <> rest : +List<E.Layer>} ->
       {E.close_panel(E.from_program(program, session)) ==
       E.Decision{E.from_program(program, E.with_attention(trigger, E.with_layers(rest, session))),
        D.success(J.Null{}), Nil{}, [E.Attend{trigger}], False{}} : E.Decision},
    modal_close_empty: @+session:E.Session -> @+program:M.World() ->
      @observed_layers:{E.layers(session) == Nil{} : +List<E.Layer>} ->
       {E.close_panel(E.from_program(program, session)) ==
       E.unchanged(E.from_program(program, session)) : E.Decision},
    modal_sequence_attention: @+application:E.Application -> @+panel:U.Panel -> @+trigger:String ->
      {attention(post(E.close_panel(post(E.open_panel(panel, trigger, application))))) == trigger : String},
    modal_sequence_residence: @+application:E.Application -> @+panel:U.Panel -> @+trigger:String ->
      {residence(post(E.close_panel(post(E.open_panel(panel, trigger, application))))) == residence(application) : Residence},
    runtime_keeps_content: @+input:M.Input -> @+application:E.Application ->
      {session_content(post(ExperienceProgram.step(E.RuntimeInput{input}, application))) == session_content(application) : SessionContent},
    native_without_submission_keeps_frame: @+decision:M.Decision() -> @+session:E.Session -> @durable:Bool ->
      {native_frame(post(E.native_result(decision, session, None{}, durable))) ==
        native_frame(E.from_program(runtime_program(decision), session)) : NativeFrame},
    native_without_submission_retains_previews: @+decision:M.Decision() -> @+session:E.Session -> @durable:Bool ->
      {previews(post(E.native_result(decision, session, None{}, durable))) ==
        Live.retained(previews(E.from_program(runtime_program(decision), session)), runtime_program(decision)) : +List<Live.Output>},
    preview_observation_keeps_content: @+observation:Live.Observation -> @+application:E.Application ->
      {session_content(post(ExperienceProgram.step(E.PreviewObserved{observation}, application))) == session_content(application) : SessionContent},
    navigate_keeps_drafts: @+route:U.Route -> @+application:E.Application ->
      {drafts(post(E.navigate(route, application))) == drafts(application) : +List<U.Draft>},
    new_visit_keeps_location: @+reader:E.Reader ->
      {reading_location(E.new_visit(reader)) == reading_location(reader) : ReadingLocation},
    obsolete_reading: @+task:Nat -> @+generation:Nat -> @+intent:U.ReadingIntent -> @+application:E.Application ->
      @not_owner:{reading_owner(application, task, generation) == False{} : Bool} ->
      {ExperienceProgram.step(E.UserInput{U.ReadTimeline{task, generation, intent}}, application) == E.unchanged(application) : E.Decision},
    model_choice: @+session:E.Session -> @+program:M.World() -> @+trigger:String -> @initial:String -> @query:String -> @+layer_occurrence:Nat -> @+source_expanded:Bool -> @+decision_field:Maybe<&2, Forms.Field> -> @+parameter_buffer:Maybe<&2, String> ->
      @+rest:+List<E.Layer> -> @revision:Nat -> @+text:U.Text -> @old_profile:String ->
      @old_reasoning:String -> @context:Context.Configuration -> @feedback:U.Feedback -> @+directory_entry:String ->
      @+new_profile:String -> @+new_reasoning:String ->
      @valid:{E.permitted_preference(D.find_profile(Board.profiles(program), new_profile), new_reasoning) == True{} : Bool} ->
      @observed_layers:{E.layers(session) == E.Layer{U.ModelPicker{U.NewTaskEditor{None{}}}, trigger, initial, query, layer_occurrence, source_expanded, None{}, None{}} <> rest : +List<E.Layer>} ->
      @found:{E.find_draft(E.drafts(session), U.NewTaskEditor{None{}}) ==
        Some{U.Draft{revision, U.NewTask{text, old_profile, old_reasoning, context, False{}, None{}}, feedback, directory_entry}} : Maybe<&2, U.Draft>} ->
      {ExperienceProgram.step(E.UserInput{U.EditDraft{U.NewTaskEditor{None{}}, U.ChooseModel{new_profile, new_reasoning}}},
        E.from_program(program, session)) ==
       E.remember_manual(U.ChooseModel{new_profile, new_reasoning}, E.Decision{E.from_program(program, E.with_attention(trigger, E.with_layers(rest, E.with_drafts(U.Draft{(revision + 1n : Nat), U.NewTask{text, new_profile, new_reasoning, context, False{}, None{}}, U.Editing{}, directory_entry} <>
           E.without_draft(E.drafts(session), U.NewTaskEditor{None{}}), session)))),
         D.success(J.Null{}), Nil{}, [E.Attend{trigger}], False{}}) : E.Decision},
    model_choice_complete: @+profile:String -> @+reasoning:String -> @+application:E.Application ->
      {ExperienceProgram.step(E.UserInput{U.EditDraft{U.NewTaskEditor{None{}}, U.ChooseModel{profile, reasoning}}}, application) ==
        model_choice_spec(E.permitted_preference(D.find_profile(Board.profiles(E.program(application)), profile), reasoning), profile, reasoning, application) : E.Decision},
    invalid_model_choice: @+profile:String -> @+reasoning:String -> @+application:E.Application ->
      @invalid:{E.permitted_preference(D.find_profile(Board.profiles(E.program(application)), profile), reasoning) == False{} : Bool} ->
      {ExperienceProgram.step(E.UserInput{U.EditDraft{U.NewTaskEditor{None{}}, U.ChooseModel{profile, reasoning}}}, application) ==
        E.Decision{application, D.failure("interaction_refused", "Choose an available model and permitted reasoning effort."), Nil{}, Nil{}, False{}} : E.Decision},
    manual_preference_persistence: @+profile:String -> @+reasoning:String -> @+world:M.World() -> @+session:E.Session -> @+reply:J.Json -> @+runtime:+List<M.Effect()> -> @+interaction:+List<E.Effect> -> @durable:Bool ->
      {E.remember_valid(True{}, profile, reasoning, E.Decision{E.from_program(world, session), reply, runtime, interaction, durable}) ==
        E.Decision{E.from_program(world, E.with_preference(Some{E.ModelPreference{profile, reasoning}}, session)), reply, runtime, E.PersistModelPreference{profile, reasoning} <> interaction, durable} : E.Decision},
    begin_task_complete: @+project:Maybe<&2, Nat> -> @+world:M.World() -> @+session:E.Session ->
      {E.begin_task(project, E.from_program(world, session)) == begin_task_spec(project, world, session) : E.Decision},
    model_resolution_complete: @+session:E.Session -> @+world:M.World() ->
      {E.resolve_model_draft(session, world) == model_resolution(session, world) : E.Session},
    manual_draft_priority: @draft:U.Draft -> @profiles:+List<D.Profile> -> @+session:E.Session ->
      {E.resolve_model_valid(True{}, draft, profiles, session) == session : E.Session},
    unavailable_catalog: {E.first_profile(Nil{}) == ("", "") : Sigma<&2, &2, String, (_ => String)>},
    preference_keeps_tasks: @profile:String -> @reasoning:String -> @+world:M.World() -> @session:E.Session ->
      {E.program(post(E.restore_preference(profile, reasoning, E.from_program(world, session)))) == world : M.World()},
    completed_creation_resets_manual: @message:U.Text -> @profile:String -> @reasoning:String -> @context:Context.Configuration -> @+result:J.Json -> @+world:M.World() -> @+session:E.Session ->
      {E.finish_body(U.NewTask{message, profile, reasoning, context, False{}, None{}}, U.Start{}, Nil{}, result, E.from_program(world, session)) ==
        E.finish_scoped_task(E.same_work(None{}, E.active_work(session)), None{}, U.Start{}, Nil{}, result, E.from_program(world, session)) : E.Decision},
    rejected_execution_keeps_preference: @task:Nat -> @profile:String -> @reasoning:String -> @remember:Bool -> @+world:M.World() -> @+result:J.Json -> @previous:M.World() -> @+session:E.Session ->
      {E.finish_execution(False{}, task, profile, reasoning, remember, world, result, E.from_program(previous, session)) ==
        E.reply(E.from_program(world, session), result) : E.Decision}

  }

law evidence:
  Requirements

def runtime_observation(decision: E.Decision) -> M.Decision():
  E.Decision{+observed_application, reply, effects, interaction, durable} = decision
  program = E.program(observed_application)
  C.Decision{program, reply, effects}

# The human-facing system retains the entire existing execution decision:
# post-state, reply and ordered effects. Session behavior cannot replace it.

def confirmation_spec(layers: +List<E.Layer>, +command: M.Command, +trigger: String, occurrence: Nat) -> Bool:
  match layers:
    case Con{E.Layer{U.Confirm{current, title, destination}, current_trigger, target, query, layer_occurrence, source_expanded, decision_field, parameter_buffer}, rest}:
      Nat.is_eq(layer_occurrence, occurrence) && (String.eq(current_trigger, trigger) && J.same(CommandCodec.command_json(current), CommandCodec.command_json(command)))
    case _: False{}

def accepted_confirmation_spec(ok: Bool, +result: J.Json, destination: U.Route, +application: E.Application) -> E.Decision:
  match ok:
    case True{}: E.with_native(E.visit(destination, application), result, Nil{}, False{})
    case False{}: E.Decision{application, result, Nil{}, Nil{}, False{}}

def confirmation_result_spec(owned: Bool, +result: J.Json, destination: U.Route, +application: E.Application) -> E.Decision:
  match owned:
    case False{}: E.Decision{application, result, Nil{}, Nil{}, False{}}
    case True{}: accepted_confirmation_spec(J.boolean(J.get(result, "ok")), result, destination, application)

# A completed interactive command is feedback to its captured owner, path and
# ticket. It is not another submission, and it never edits the composer. This
# adapter specification writes every Session/Decision field; the core operation
# is the separately specified public interactive-language boundary.
def feedback_effects(+effects: +List<Interactive.Effect>) -> +List<E.Effect>:
  match effects:
    case Nil{}: Nil{}
    case Con{effect, rest}: E.InteractiveEffect{effect} <> feedback_effects(rest)

def feedback_decision(+result: Interactive.Decision, +application: E.Application) -> E.Decision:
  match result application:
    case Interactive.Decision{core, effects} E.Application{program, E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, preference, manual, workspace_git, Documents.State{namespace, sequence, fresh, allowed, ready, documents, old_core, next_epoch, retention}}}:
      E.Decision{E.Application{program, E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, preference, manual, workspace_git, Documents.State{namespace, sequence, fresh, allowed, ready, documents, core, next_epoch, retention}}}, D.success(J.Null{}), Nil{}, feedback_effects(effects), False{}}

def feedback_permitted(+owned: Bool, +owner: Interactive.Owner, +path: String, +ticket: Nat, +result: J.Json, +application: E.Application) -> E.Decision:
  match owned:
    case False{}: E.Decision{application, D.success(J.Null{}), Nil{}, Nil{}, False{}}
    case True{}:
      feedback_decision(InteractiveCore.step(Interactive.EffectCompleted{owner, path, ticket,
        J.boolean(J.get(result, "ok")), J.text(J.get(J.get(result, "error"), "message"))},
        Documents.core(E.interactive_data(E.session(application)))), application)

def interactive_completion_spec(+owner: Interactive.Owner, +path: String, +ticket: Nat, +result: J.Json, +application: E.Application) -> E.Decision:
  +documents = E.interactive_data(E.session(application))
  feedback_permitted(DocumentRequirement.owns(Documents.namespace(documents), owner, False{}, Documents.documents(documents)), owner, path, ticket, result, application)

law interactive_feedback:
  for +owner: Interactive.Owner
  for +path: String
  for +ticket: Nat
  for +result: J.Json
  for +application: E.Application
  {E.interactive_input(Interactive.EffectCompleted{owner, path, ticket,
    J.boolean(J.get(result, "ok")), J.text(J.get(J.get(result, "error"), "message"))}, application) ==
    interactive_completion_spec(owner, path, ticket, result, application) : E.Decision}

def business_effects(+decision: E.Decision) -> +List<M.Effect()> & +List<E.Effect>:
  E.Decision{application, reply, runtime, interaction, durable} = decision
  (runtime, interaction)

law interactive_feedback_is_terminal:
  for +owner: Interactive.Owner
  for +path: String
  for +ticket: Nat
  for +result: J.Json
  for +application: E.Application
  {business_effects(E.interactive_input(Interactive.EffectCompleted{owner, path, ticket,
    J.boolean(J.get(result, "ok")), J.text(J.get(J.get(result, "error"), "message"))}, application)) ==
    (Nil{}, Nil{}) : +List<M.Effect()> & +List<E.Effect>}

# Sending from a view captures its declared message, never the mutable composer.
# The existing submission rules and authoritative Commands resolver decide
# whether that captured request may run. Failure settles the same correlation;
# success emits exactly one request and keeps the entire application unchanged.
def captured_request(+operation: Commands.Operation, +command: M.Command, +owner: Interactive.Owner, +path: String, +ticket: Nat, +application: E.Application) -> E.Decision:
  match operation:
    case Commands.Refuse{code, message}: interactive_completion_spec(owner, path, ticket, D.failure(code, message), application)
    case _: E.Decision{application, D.success(J.Null{}), Nil{}, [E.RequestCommand{command, E.InteractiveCompletion{owner, path, ticket}}], False{}}

def captured_send_ready(+ready: Bool, +task: Nat, +owner: Interactive.Owner, +path: String, +ticket: Nat, +message: String, +application: E.Application) -> E.Decision:
  match ready:
    case False{}: interactive_completion_spec(owner, path, ticket, D.failure("interaction_refused", "This task cannot accept this message now"), application)
    case True{}:
      +command: M.Command = U.message_command(U.Send{}, task, message)
      captured_request(Commands.resolve(command, E.program(application)), command, owner, path, ticket, application)

def captured_send_owner(+task: Maybe<&2, Nat>, +owner: Interactive.Owner, +path: String, +ticket: Nat, +message: String, +application: E.Application) -> E.Decision:
  match task:
    case None{}: interactive_completion_spec(owner, path, ticket, D.failure("interaction_refused", "This view no longer owns a task"), application)
    case Some{+id}:
      captured_send_ready(UX.draft_can_prepare(U.Draft{0n, U.Message{id, U.initial_text(message), U.Send{}}, U.Editing{}, ""},
        E.busy(E.pending(E.session(application)), U.MessageEditor{id}), E.program(application)), id, owner, path, ticket, message, application)

def captured_send(+owner: Interactive.Owner, +path: String, +ticket: Nat, +message: String, +application: E.Application) -> E.Decision:
  captured_send_owner(Documents.current_owning_task(owner, E.interactive_data(E.session(application))), owner, path, ticket, message, application)

law interactive_send:
  for +owner: Interactive.Owner
  for +path: String
  for +ticket: Nat
  for +message: String
  for +application: E.Application
  {E.interpret_interactive_effect(Interactive.SendMessage{owner, path, ticket, message}, application) == captured_send(owner, path, ticket, message, application) : E.Decision}

def work_creation_spec(current: Bool, +result: J.Json, application: E.Application) -> E.Decision:
  match current:
    case False{}: E.Decision{application, result, Nil{}, Nil{}, False{}}
    case True{}: E.with_native(E.created_work(result, application), result, Nil{}, False{})

def side_response_spec(accepted: Bool, +result: J.Json, +application: E.Application) -> E.Decision:
  match accepted:
    case False{}: E.Decision{application, result, Nil{}, Nil{}, False{}}
    case True{}: E.with_native(E.show_created_side(J.natural(J.get(J.get(result, "result"), "task_id")), application), result, Nil{}, False{})

def side_creation_spec(current: Bool, draft: Maybe<&2, U.Draft>, +result: J.Json, +application: E.Application) -> E.Decision:
  match current:
    case False{}: E.Decision{E.from_program(E.program(application), E.settle_side_draft(draft, result, E.session(application))), result, Nil{}, Nil{}, False{}}
    case True{}: side_response_spec(J.boolean(J.get(result, "ok")), result, E.from_program(E.program(application), E.settle_side_draft(draft, result, E.session(application))))

def valid_completion_spec(completion: E.Completion, +program: M.World(), +result: J.Json, +session: E.Session) -> E.Decision:
  match completion:
    case E.WorkCreationCompletion{generation, layer_generation}: work_creation_spec(E.work_creation_current(generation, layer_generation, session), result, E.from_program(program, E.retain_previews(session, program)))
    case E.SideCreationCompletion{parent, +draft, generation, layer_generation}: side_creation_spec(E.side_creation_current(parent, draft, generation, layer_generation, E.retain_previews(session, program)), draft, result, E.from_program(program, E.retain_previews(session, program)))
    case E.InteractiveCompletion{owner, path, ticket}: interactive_completion_spec(owner, path, ticket, result, E.from_program(program, E.retain_previews(session, program)))
    case E.ExecutionViewCompletion{task, profile, reasoning, remember, occurrence}: E.finish_execution_view(J.boolean(J.get(result, "ok")), task, profile, reasoning, remember, occurrence, program, result, E.from_program(program, session))
    case E.ExecutionCompletion{task, profile, reasoning, remember}: E.finish_execution(J.boolean(J.get(result, "ok")), task, profile, reasoning, remember, program, result, E.from_program(program, session))
    case E.DirectCompletion{}: E.Decision{E.from_program(program, E.retain_previews(session, program)), result, Nil{}, Nil{}, False{}}
    case E.WorktreePreferenceCompletion{draft, command}:
      E.finish_worktree_preference(J.boolean(J.get(result, "ok")), draft, command, result,
        E.from_program(program, E.retain_previews(session, program)))
    case E.DraftCompletion{+draft}:
      E.with_native(SubmissionRule.finish_submission_spec(J.boolean(J.get(result, "ok")) && E.owns_submission(draft, E.retain_previews(session, program)), draft, result,
        E.from_program(program, E.settle(draft, result, E.retain_previews(session, program)))), result, Nil{}, False{})
    case E.ConfirmationCompletion{command, trigger, destination, occurrence}:
      +layers = E.layers(session)
      confirmation_result_spec(confirmation_spec(layers, command, trigger, occurrence), result, destination, E.from_program(program, E.retain_previews(session, program)))

def completion_checked_spec(valid: Bool, completion: E.Completion, program: M.World(), result: J.Json, session: E.Session, previous: M.World()) -> E.Decision:
  match valid:
    case True{}: valid_completion_spec(completion, program, result, session)
    case False{}: E.refuse(E.from_program(previous, session), "The observed program violates a world invariant")

def completion_spec(completion: E.Completion, +program: M.World(), result: J.Json, session: E.Session, previous: M.World()) -> E.Decision:
  completion_checked_spec(I.world(program), completion, program, result, session, previous)

def observed_checked_spec(valid: Bool, +program: M.World(), session: E.Session, previous: M.World()) -> E.Decision:
  match valid:
    case True{}: E.Decision{E.from_program(program, E.resolve_model_draft(E.retain_previews(session, program), program)), D.success(J.Null{}), Nil{}, Nil{}, False{}}
    case False{}: E.refuse(E.from_program(previous, session), "The observed program violates a world invariant")

def observed_spec(+program: M.World(), session: E.Session, previous: M.World()) -> E.Decision:
  observed_checked_spec(I.world(program), program, session, previous)

def stale_completion_spec(valid: Bool, previous: M.World(), +program: M.World(), result: J.Json, session: E.Session) -> E.Decision:
  match valid:
    case True{}: E.Decision{E.from_program(program, E.retain_previews(session, program)), result, Nil{}, Nil{}, False{}}
    case False{}: E.refuse(E.from_program(previous, session), "The observed program violates a world invariant")

def preference_request_spec(preference: Maybe<&2, M.Command>, +command: M.Command, draft: U.Draft, +application: E.Application) -> E.Decision:
  match preference:
    case None{}: E.Decision{application, D.success(J.Null{}), Nil{}, [E.RequestCommand{command, E.composer_completion(command, draft, application)}], False{}}
    case Some{update}: E.Decision{application, D.success(J.Null{}), Nil{}, [E.RequestCommand{update, E.WorktreePreferenceCompletion{draft, command}}], False{}}

def submission_checked_spec(allowed: Bool, preference: Maybe<&2, M.Command>, command: M.Command, draft: U.Draft, application: E.Application) -> E.Decision:
  match allowed:
    case False{}: E.refuse(application, "Wait for Git verification of the primary workspace before creating a worktree.")
    case True{}: preference_request_spec(preference, command, draft, application)

def submission_request_spec(command: M.Command, +application: E.Application, submitted: Maybe<&2, U.Draft>) -> E.Decision:
  match submitted:
    case None{}: E.Decision{application, D.success(J.Null{}), Nil{}, [E.RequestCommand{command, E.DirectCompletion{}}], False{}}
    case Some{+draft}: submission_checked_spec(E.worktree_submission_allowed(U.contents(draft), application), E.worktree_preference_available(E.worktree_available(application), U.contents(draft), E.program(application)), command, draft, application)

type CommandRequirements is Type:
  CommandRequirements{
    receipt: @+completion:E.Completion -> @+program:M.World() -> @+result:J.Json -> @+session:E.Session -> @previous:M.World() ->
      {ExperienceProgram.step(E.CommandCompleted{program, result, completion}, E.from_program(previous, session)) == completion_spec(completion, program, result, session, previous) : E.Decision},
    request: @+command:M.Command -> @+application:E.Application -> @+submitted:Maybe<&2, U.Draft> ->
      {E.execute(command, application, submitted) == submission_request_spec(command, application, submitted) : E.Decision},
    observation: @+program:M.World() -> @+session:E.Session -> @previous:M.World() ->
      {ExperienceProgram.step(E.ProgramObserved{program}, E.from_program(previous, session)) == observed_spec(program, session, previous) : E.Decision},
    stale: @+program:M.World() -> @+result:J.Json -> @+draft:U.Draft -> @+session:E.Session -> @previous:M.World() ->
      @absent:{E.owns_submission(draft, E.retain_previews(session, program)) == False{} : Bool} ->
      {ExperienceProgram.step(E.CommandCompleted{program, result, E.DraftCompletion{draft}}, E.from_program(previous, session)) == stale_completion_spec(I.world(program), previous, program, result, session) : E.Decision},
    accepted: @+result:J.Json -> @destination:U.Route -> @application:E.Application ->
      @ok:{J.boolean(J.get(result, "ok")) == True{} : Bool} ->
      {E.complete_confirmation_value(result, destination, application) == E.with_native(E.visit(destination, application), result, Nil{}, False{}) : E.Decision},
    refused: @+result:J.Json -> @destination:U.Route -> @+application:E.Application ->
      @ok:{J.boolean(J.get(result, "ok")) == False{} : Bool} ->
      {E.complete_confirmation_value(result, destination, application) == E.Decision{application, result, Nil{}, Nil{}, False{}} : E.Decision},
    replaced: @result:J.Json -> @destination:U.Route -> @application:E.Application ->
      {confirmation_result_spec(False{}, result, destination, application) == E.Decision{application, result, Nil{}, Nil{}, False{}} : E.Decision},
    stale_occurrence: @+current:M.Command -> @title:String -> @destination:U.Route -> @+current_trigger:String -> @target:String -> @query:String -> @+current_occurrence:Nat -> @rest:+List<E.Layer> -> @+command:M.Command -> @+trigger:String -> @+occurrence:Nat ->
      @stale:{Nat.is_eq(current_occurrence, occurrence) == False{} : Bool} ->
      {E.confirmation_owned(E.Layer{U.Confirm{current, title, destination}, current_trigger, target, query, current_occurrence, False{}, None{}, None{}} <> rest, command, trigger, occurrence) == False{} : Bool}
  }

law command_evidence:
  CommandRequirements

law invalid_observed_decision:
  @+program:M.World() -> @+session:E.Session -> @previous:M.World() ->
  @observed:{I.world(program) == False{} : Bool} ->
  {ExperienceProgram.step(E.ProgramObserved{program}, E.from_program(previous, session)) == E.refuse(E.from_program(previous, session), "The observed program violates a world invariant") : E.Decision}

law valid_observed_decision:
  @+program:M.World() -> @+session:E.Session -> @previous:M.World() ->
  @observed:{I.world(program) == True{} : Bool} ->
  {ExperienceProgram.step(E.ProgramObserved{program}, E.from_program(previous, session)) == E.Decision{E.from_program(program, E.resolve_model_draft(E.retain_previews(session, program), program)), D.success(J.Null{}), Nil{}, Nil{}, False{}} : E.Decision}

law invalid_completion_decision:
  @+completion:E.Completion -> @+program:M.World() -> @+result:J.Json -> @+session:E.Session -> @previous:M.World() ->
  @observed:{I.world(program) == False{} : Bool} ->
  {ExperienceProgram.step(E.CommandCompleted{program, result, completion}, E.from_program(previous, session)) == E.refuse(E.from_program(previous, session), "The observed program violates a world invariant") : E.Decision}

law valid_completion_decision:
  @+completion:E.Completion -> @+program:M.World() -> @+result:J.Json -> @+session:E.Session -> @previous:M.World() ->
  @observed:{I.world(program) == True{} : Bool} ->
  {ExperienceProgram.step(E.CommandCompleted{program, result, completion}, E.from_program(previous, session)) == valid_completion_spec(completion, program, result, session) : E.Decision}

law valid_stale_completion_decision:
  @+program:M.World() -> @+result:J.Json -> @+draft:U.Draft -> @+session:E.Session -> @+previous:M.World() ->
  @observed:{I.world(program) == True{} : Bool} ->
  @absent:{E.owns_submission(draft, E.retain_previews(session, program)) == False{} : Bool} ->
  {ExperienceProgram.step(E.CommandCompleted{program, result, E.DraftCompletion{draft}}, E.from_program(previous, session)) == E.Decision{E.from_program(program, E.retain_previews(session, program)), result, Nil{}, Nil{}, False{}} : E.Decision}

law submission_requirements_gate:
  @+pending:+List<E.Pending> -> @+world:M.World() -> @revision:Nat -> @+body:U.Body -> @feedback:U.Feedback -> @entry:String ->
  {E.submission_ready(pending, world, U.Draft{revision, body, feedback, entry}) == UX.draft_can_prepare(U.Draft{revision, body, feedback, entry}, E.busy(pending, U.owner(body)), world) : Bool}

law invalid_preparation_complete_refusal:
  @+pending:+List<E.Pending> -> @+world:M.World() -> @revision:Nat -> @+body:U.Body -> @feedback:U.Feedback -> @entry:String -> @+application:E.Application ->
  {E.submit_admitted(pending, world, U.Draft{revision, body, feedback, entry}, None{}, application) ==
    E.Decision{application, D.failure("interaction_refused", UX.assessment_reason(UX.assessed_requirements(UX.draft_requirements(U.Draft{revision, body, feedback, entry}, E.busy(pending, U.owner(body)), world), body, revision, E.now(E.session(application)), world))), Nil{}, Nil{}, False{}} : E.Decision}

law workspace_settlement_preserves_stale_draft:
  @draft:U.Draft -> @revision:Nat -> @reason:String -> @+session:E.Session ->
  {E.workspace_settlement(False{}, draft, revision, reason, session) == session : E.Session}

law workspace_settlement_retains_body:
  @+revision:Nat -> @+body:U.Body -> @feedback:U.Feedback -> @+entry:String -> @+submitted:Nat -> @+reason:String -> @+session:E.Session ->
  {E.workspace_settlement(True{}, U.Draft{revision, body, feedback, entry}, submitted, reason, session) ==
    E.with_draft(session, U.Draft{revision, body, U.WorkspaceRejected{submitted, reason}, entry}) : E.Session}

law rejected_command_uses_actual_code_and_workspace:
  @+body:U.Body -> @+revision:Nat -> @+result:J.Json ->
  {E.command_rejection_feedback(body, revision, result) ==
    E.rejected_feedback(String.eq(J.text(J.get(J.get(result, "error"), "code")), "command_not_submitted") && U.workspace_operation(body), revision, J.text(J.get(J.get(result, "error"), "message"))) : U.Feedback}

law property_source_toggle_preserves_application:
  @+panel:U.Panel -> @+trigger:String -> @+initial:String -> @+query:String -> @+occurrence:Nat -> @+expanded:Bool -> @+field:Maybe<&2, Forms.Field> -> @+parameter_buffer:Maybe<&2, String> -> @+rest:+List<E.Layer> -> @+application:E.Application ->
  {E.toggle_source_layers(True{}, panel, trigger, initial, query, occurrence, expanded, field, parameter_buffer, rest, application) ==
    E.update_requested_view(True{}, panel, trigger, initial, query, occurrence, Bool.not(expanded), None{}, None{}, rest, application) : E.Decision}

law property_source_toggle_refuses_wrong_owner:
  @panel:U.Panel -> @trigger:String -> @initial:String -> @query:String -> @occurrence:Nat -> @expanded:Bool -> @field:Maybe<&2, Forms.Field> -> @+parameter_buffer:Maybe<&2, String> -> @rest:+List<E.Layer> -> @+application:E.Application ->
  {E.toggle_source_layers(False{}, panel, trigger, initial, query, occurrence, expanded, field, parameter_buffer, rest, application) == E.refuse(application, "The property source is not open for this editor") : E.Decision}

law invalid_workspace_retry_preserves_application:
  @draft:U.Draft -> @+application:E.Application ->
  {E.retry_workspace_current(False{}, draft, application) == E.refuse(application, "There is no current workspace failure to retry") : E.Decision}

law workspace_preparation_failure_complete:
  @+draft:U.Draft -> @+reason:String -> @+application:E.Application ->
  {E.preparation_failure(draft, reason, application) ==
    E.Decision{E.with_session(E.settle_workspace(draft, reason, E.session(application)), application), D.failure("workspace_observation_failed", reason), Nil{}, Nil{}, False{}} : E.Decision}

law blocked_workspace_retry_retains_failure:
  @+draft:U.Draft -> @+application:E.Application ->
  {E.retry_workspace_allowed(False{}, draft, application) == E.submission_refusal(E.pending(E.session(application)), E.program(application), draft, application) : E.Decision}

law accepted_workspace_retry_uses_normal_admission:
  @+revision:Nat -> @+body:U.Body -> @feedback:U.Feedback -> @+entry:String -> @+application:E.Application ->
  {E.retry_workspace_allowed(True{}, U.Draft{revision, body, feedback, entry}, application) ==
    E.submit_found(Some{U.Draft{revision, body, U.Editing{}, entry}}, E.with_session(E.with_draft(E.session(application), U.Draft{revision, body, U.Editing{}, entry}), application)) : E.Decision}

law workspace_command_not_submitted_feedback:
  @+body:U.Body -> @+revision:Nat -> @+reason:String ->
  {E.command_rejection_feedback(body, revision, D.failure("command_not_submitted", reason)) == E.rejected_feedback(U.workspace_operation(body), revision, reason) : U.Feedback}

law unknown_decision_focus_preserves_application:
  @editor:U.Editor -> @+application:E.Application ->
  {E.enter_known_decision(None{}, editor, application) == E.unchanged(application) : E.Decision}

law unrelated_decision_focus_preserves_application:
  @panel:U.Panel -> @trigger:String -> @initial:String -> @query:String -> @occurrence:Nat -> @source:Bool ->
  @field:Maybe<&2, Forms.Field> -> @+parameter_buffer:Maybe<&2, String> -> @rest:+List<E.Layer> -> @+application:E.Application ->
  {E.decision_layer_update(False{}, panel, trigger, initial, query, occurrence, source, field, parameter_buffer, rest, application) == E.unchanged(application) : E.Decision}

law decision_focus_preserves_query_and_source:
  @+panel:U.Panel -> @+trigger:String -> @+initial:String -> @+query:String -> @+occurrence:Nat -> @+source:Bool ->
  @+field:Maybe<&2, Forms.Field> -> @+parameter_buffer:Maybe<&2, String> -> @+rest:+List<E.Layer> -> @+application:E.Application ->
  {E.decision_layer_update(True{}, panel, trigger, initial, query, occurrence, source, field, parameter_buffer, rest, application) ==
    E.update_requested_view(E.request_view_changed(E.layers(E.session(application)), source, field), panel, trigger, initial, query, occurrence, source, field, parameter_buffer, rest, application) : E.Decision}

law workspace_retry_assesses_complete_candidate:
  @+revision:Nat -> @+body:U.Body -> @+feedback:U.Feedback -> @+entry:String -> @+application:E.Application ->
  {E.retry_workspace_current(True{}, U.Draft{revision, body, feedback, entry}, application) ==
    E.retry_workspace_allowed(UX.draft_can_prepare(U.Draft{revision, body, U.Editing{}, entry}, E.busy(E.pending(E.session(application)), U.owner(body)), E.program(application)),
      U.Draft{revision, body, feedback, entry}, application) : E.Decision}

law requested_parameter_preserves_applied_draft:
  @+panel:U.Panel -> @+trigger:String -> @+initial:String -> @+query:String -> @+occurrence:Nat -> @+source:Bool ->
  @+field:Maybe<&2, Forms.Field> -> @+buffer:Maybe<&2, String> -> @+rest:+List<E.Layer> -> @+value:String -> @+application:E.Application ->
  {E.write_parameter_checked(True{}, E.Layer{panel, trigger, initial, query, occurrence, source, field, buffer} <> rest, value, application) ==
    E.local(E.program(application), E.with_layers(E.Layer{panel, trigger, initial, query, occurrence, source, field, Some{value}} <> rest, E.session(application)), Nil{}) : E.Decision}

law unavailable_parameter_does_not_apply:
  @layers:+List<E.Layer> -> @value:String -> @+application:E.Application ->
  {E.write_parameter_checked(False{}, layers, value, application) == E.refuse(application, "The open parameter is not available in this view") : E.Decision}

law invalid_complete_parameter_preserves_application:
  @editor:U.Editor -> @profile:String -> @value:String -> @+application:E.Application ->
  {E.complete_parameter_value(False{}, editor, profile, value, application) == E.refuse(application, "Choose an available model and permitted reasoning effort.") : E.Decision}

law complete_parameter_uses_canonical_configuration:
  @+editor:U.Editor -> @+profile:String -> @+value:String -> @+application:E.Application ->
  {E.complete_parameter_value(True{}, editor, profile, value, application) == E.manual_edit(editor, U.ChooseModel{profile, value}, application) : E.Decision}

law full_access_has_no_filesystem_dependency:
  {E.retained_context_policy(Forms.SandboxMode{}, Context.Unrestricted{}) == False{} : Bool}

law full_access_has_no_network_dependency:
  {E.retained_context_policy(Forms.NetworkAccess{}, Context.Unrestricted{}) == False{} : Bool}

law reviewer_dependency_requires_automatic_strategy:
  @+profile:String ->
  {E.retained_context_policy(Forms.ApprovalReviewer{}, Context.AutomaticReview{profile}) == True{} : Bool}

law back_from_dependency_retains_inspection_parent:
  @+editor:U.Editor -> @+trigger:String -> @+initial:String -> @+query:String -> @+occurrence:Nat -> @+source:Bool ->
  @+field:Forms.Field -> @+buffer:Maybe<&2, String> -> @+rest:+List<E.Layer> -> @+application:E.Application ->
  {E.leave_layer_request(E.Layer{U.ModelPicker{editor}, trigger, initial, query, occurrence, source, Some{field}, buffer} <> rest, editor, application) ==
    E.decision_layer_update(U.same_editor(editor, editor), U.ModelPicker{editor}, trigger, initial, query, occurrence, source, None{}, None{}, rest, application) : E.Decision}

law mismatched_execution_view_does_not_dismiss:
  @task:Nat -> @+result:E.Decision ->
  {E.finish_execution_view_checked(False{}, task, result) == result : E.Decision}

law explicit_dismiss_preserves_nonproject_state:
  @+editor:U.Editor -> @+application:E.Application ->
  {E.dismiss_layer_draft(U.ModelPicker{editor}, application) == application : E.Application}

law project_dismiss_discards_complete_draft:
  @+id:Maybe<&2, Nat> -> @+world:M.World() -> @+session:E.Session ->
  {E.dismiss_layer_draft(U.EditObject{U.ProjectEditor{id}}, E.from_program(world, session)) ==
    E.from_program(world, E.discard_editor_session(U.ProjectEditor{id}, session)) : E.Application}

law title_prompts_dismiss_discards_complete_draft:
  @+world:M.World() -> @+session:E.Session ->
  {E.dismiss_layer_draft(U.EditObject{U.TitlePromptEditor{}}, E.from_program(world, session)) ==
    E.from_program(world, E.discard_editor_session(U.TitlePromptEditor{}, session)) : E.Application}

law fresh_title_prompts_use_reserved_occurrence:
  @+revision:Nat -> @+prompts:Title.Prompts -> @+session:E.Session ->
  {E.ensure_editor_draft(None{}, U.TitlePrompts{revision, prompts}, session) ==
    E.fresh_editor_draft(U.TitlePrompts{revision, prompts}, session) : E.Session}

law fresh_project_uses_reserved_occurrence:
  @+body:U.Body -> @+session:E.Session ->
  {E.fresh_editor_draft(body, session) == E.with_draft(session, U.Draft{E.next_layer(session), body, U.Editing{}, ""}) : E.Session}

law cancelled_project_advances_shared_fresh_occurrence:
  @+revision:Nat -> @body:U.Body -> @feedback:U.Feedback -> @entry:String -> @+current:Nat ->
  {E.reserve_draft_occurrence(Some{U.Draft{revision, body, feedback, entry}}, current) == Nat.max((revision + 1n : Nat), (current + 1n : Nat)) : Nat}


law requested_view_change_uses_fresh_identity:
  @+panel:U.Panel -> @+trigger:String -> @+initial:String -> @+query:String -> @occurrence:Nat -> @+source:Bool ->
  @+field:Maybe<&2, Forms.Field> -> @+buffer:Maybe<&2, String> -> @+rest:+List<E.Layer> -> @+application:E.Application ->
  {E.update_requested_view(True{}, panel, trigger, initial, query, occurrence, source, field, buffer, rest, application) ==
    E.local(E.program(application), E.with_next_layer((E.next_layer(E.session(application)) + 1n : Nat),
      E.with_layers(E.Layer{panel, trigger, initial, query, E.next_layer(E.session(application)), source, field, buffer} <> rest, E.session(application))), Nil{}) : E.Decision}

law same_requested_view_preserves_identity:
  @+panel:U.Panel -> @+trigger:String -> @+initial:String -> @+query:String -> @+occurrence:Nat -> @+source:Bool ->
  @+field:Maybe<&2, Forms.Field> -> @+buffer:Maybe<&2, String> -> @+rest:+List<E.Layer> -> @+application:E.Application ->
  {E.update_requested_view(False{}, panel, trigger, initial, query, occurrence, source, field, buffer, rest, application) ==
    E.local(E.program(application), E.with_layers(E.Layer{panel, trigger, initial, query, occurrence, source, field, buffer} <> rest, E.session(application)), Nil{}) : E.Decision}

law source_navigation_uses_current_inspection:
  @+origin:U.Panel -> @+trigger:String -> @+application:E.Application ->
  {E.activate_selected(U.OpenPanel{U.PropertySource{origin}, trigger}, application) ==
    E.open_source_checked(E.source_origin_owned(E.layers(E.session(application)), origin), origin, trigger, application) : E.Decision}

law source_navigation_rejects_unowned_origin:
  @origin:U.Panel -> @trigger:String -> @+application:E.Application ->
  {E.open_source_checked(False{}, origin, trigger, application) ==
    E.refuse(application, "The setting source does not belong to the current inspection") : E.Decision}

law source_navigation_pushes_distinct_activity:
  @+origin:U.Panel -> @+trigger:String -> @+application:E.Application ->
  {E.open_source_checked(True{}, origin, trigger, application) ==
    opened_application(application, U.PropertySource{origin}, trigger) : E.Decision}

law source_navigation_has_own_identity:
  @+origin:U.Panel ->
  {E.panel_target(U.PropertySource{origin}) == "property-source/" ++ E.panel_target(origin) : String}

law source_navigation_is_read_only:
  @origin:U.Panel ->
  {E.decision_panel_editor(U.PropertySource{origin}) == None{} : Maybe<&2, U.Editor>}

law source_dismiss_preserves_underlying_draft:
  @origin:U.Panel -> @+application:E.Application ->
  {E.dismiss_layer_draft(U.PropertySource{origin}, application) == application : E.Application}

law source_back_uses_actual_stack:
  @+origin:U.Panel -> @+trigger:String -> @+initial:String -> @+query:String -> @+occurrence:Nat -> @+expanded:Bool ->
  @+field:Maybe<&2, Forms.Field> -> @+buffer:Maybe<&2, String> -> @+rest:+List<E.Layer> -> @+application:E.Application ->
  {E.dismiss_layers(E.Layer{U.PropertySource{origin}, trigger, initial, query, occurrence, expanded, field, buffer} <> rest, application) ==
    E.close_panel(application) : E.Decision}

law worktree_unknown_is_unavailable:
  @primary:Maybe<&2, String> ->
  {E.workspace_git_matches(E.UnknownWorkspaceGit{}, primary) == False{} : Bool}

law worktree_observation_dispatch:
  @+ticket:Nat -> @+available:Bool -> @+application:E.Application ->
  {ExperienceProgram.step(E.WorkspaceGitObserved{ticket, available}, application) ==
    E.workspace_git_result(E.workspace_git(E.session(application)), ticket, available, application) : E.Decision}

law current_worktree_observation_settles:
  @+current:Nat -> @+ticket:Nat -> @+primary:String -> @+available:Bool -> @+application:E.Application ->
  @observed:{E.git_observation_current(current, ticket, primary, E.current_primary(application)) == True{} : Bool} ->
  {E.workspace_git_result(E.LoadingWorkspaceGit{current, primary}, ticket, available, application) ==
    E.local(E.program(application), E.with_workspace_git(E.ObservedWorkspaceGit{primary, available},
      E.disable_unavailable_worktree(available, E.find_draft(E.drafts(E.session(application)), E.creation_editor(E.session(application))), E.session(application))), Nil{}) : E.Decision}

law prepared_task_retains_worktree_choice:
  @+message:U.Text -> @+profile:String -> @+reasoning:String -> @+context:Context.Configuration ->
  @+enabled:Bool -> @+work:Maybe<&2, Nat> -> @+observation:Context.DirectoryObservation -> @+now:U32 ->
  {U.prepared_command(U.NewTask{message, profile, reasoning, context, enabled, work}, observation, now) ==
    U.create_task(work, enabled, profile, reasoning, U.text(message), Context.observed_settings(context, observation)) : M.Command}

law prepared_project_creation_retains_worktree_choice:
  @+name:String -> @previous:D.Workspace -> @+workspace:D.Workspace -> @+guidance:D.ProjectContext -> @+enabled:Bool -> @now:U32 ->
  {U.prepared_command(U.Project{None{}, name, previous, enabled}, Context.DirectoryObservation{workspace, guidance}, now) ==
    M.CreateProject{name, D.workspace_json(workspace), D.project_json(guidance), J.Boolean{enabled}} : M.Command}

law prepared_project_update_retains_worktree_choice:
  @+id:Nat -> @+name:String -> @previous:D.Workspace -> @+workspace:D.Workspace -> @+guidance:D.ProjectContext -> @+enabled:Bool -> @now:U32 ->
  {U.prepared_command(U.Project{Some{id}, name, previous, enabled}, Context.DirectoryObservation{workspace, guidance}, now) ==
    M.UpdateProject{id, Some{name}, D.workspace_json(workspace), D.project_json(guidance), J.Boolean{enabled}} : M.Command}

law worktree_loading_is_unavailable:
  @ticket:Nat -> @root:String -> @primary:Maybe<&2, String> ->
  {E.workspace_git_matches(E.LoadingWorkspaceGit{ticket, root}, primary) == False{} : Bool}

law worktree_observed_requires_matching_primary:
  @root:String -> @+available:Bool -> @primary:String ->
  {E.workspace_git_matches(E.ObservedWorkspaceGit{root, available}, Some{primary}) ==
    available && String.eq(root, primary) : Bool}

law worktree_without_primary_is_unavailable:
  @root:String -> @available:Bool ->
  {E.workspace_git_matches(E.ObservedWorkspaceGit{root, available}, None{}) == False{} : Bool}

law worktree_observation_requires_current_ticket_and_primary:
  @+current:Nat -> @+ticket:Nat -> @+root:String -> @+primary:String ->
  {E.git_observation_current(current, ticket, root, Some{primary}) ==
    Nat.is_eq(current, ticket) && String.eq(root, primary) : Bool}

law worktree_stale_observation_preserves_application:
  @+current:Nat -> @+ticket:Nat -> @+root:String -> @+available:Bool -> @+application:E.Application ->
  @stale:{E.git_observation_current(current, ticket, root, E.current_primary(application)) == False{} : Bool} ->
  {E.workspace_git_result(E.LoadingWorkspaceGit{current, root}, ticket, available, application) == E.unchanged(application) : E.Decision}

law worktree_stale_ticket_preserves_application:
  @+current:Nat -> @+ticket:Nat -> @+root:String -> @+available:Bool -> @+application:E.Application ->
  @stale:{Nat.is_eq(current, ticket) == False{} : Bool} ->
  {E.workspace_git_result(E.LoadingWorkspaceGit{current, root}, ticket, available, application) == E.unchanged(application) : E.Decision}

law worktree_changed_primary_preserves_application:
  @+current:Nat -> @+ticket:Nat -> @+root:String -> @+primary:String -> @+available:Bool -> @+application:E.Application ->
  @observed:{E.current_primary(application) == Some{primary} : Maybe<&2, String>} ->
  @changed:{String.eq(root, primary) == False{} : Bool} ->
  {E.workspace_git_result(E.LoadingWorkspaceGit{current, root}, ticket, available, application) == E.unchanged(application) : E.Decision}

law task_without_worktree_uses_normal_creation:
  @profile:String -> @reasoning:String -> @message:String -> @settings:J.Json ->
  {U.task_creation(False{}, profile, reasoning, message, settings) == M.Create{profile, reasoning, message, settings} : M.Command}

law task_with_worktree_uses_owned_creation:
  @profile:String -> @reasoning:String -> @message:String -> @settings:J.Json ->
  {U.task_creation(True{}, profile, reasoning, message, settings) ==
    M.FeatureCommand{F.WorktreeCommand{Worktree.Create{profile, reasoning, message, settings}}} : M.Command}

law model_selection_preserves_worktree_choice:
  @+message:U.Text -> @profile:String -> @reasoning:String -> @+context:Context.Configuration ->
  @+enabled:Bool -> @+work:Maybe<&2, Nat> -> @+selected:String -> @+effort:String -> @world:M.World() ->
  {U.apply_edit(U.ChooseModel{selected, effort}, U.NewTask{message, profile, reasoning, context, enabled, work}, world) ==
    Done{U.NewTask{message, selected, effort, context, enabled, work}} : Result<&2, &2, String, U.Body>}

law saved_worktree_preference_continues_captured_submission:
  @+draft:U.Draft -> @+command:M.Command -> @result:J.Json -> @+application:E.Application ->
  @verified:{E.worktree_submission_allowed(U.contents(draft), application) == True{} : Bool} ->
  {E.finish_worktree_preference(True{}, draft, command, result, application) ==
    E.Decision{application, D.success(J.Null{}), Nil{}, [E.RequestCommand{command, E.DraftCompletion{draft}}], False{}} : E.Decision}

law ordinary_task_submission_needs_no_git_observation:
  @message:U.Text -> @profile:String -> @reasoning:String -> @context:Context.Configuration -> @work:Maybe<&2, Nat> -> @application:E.Application ->
  {E.worktree_submission_allowed(U.NewTask{message, profile, reasoning, context, False{}, work}, application) == True{} : Bool}

law unverified_worktree_preparation_preserves_application:
  @+draft:U.Draft -> @workspace:Maybe<&2, D.Workspace> -> @+application:E.Application ->
  @blocked:{E.worktree_submission_allowed(U.contents(draft), application) == False{} : Bool} ->
  {E.prepare(application, workspace, draft) ==
    E.Decision{application, D.failure("interaction_refused", "Wait for Git verification of the primary workspace before creating a worktree."), Nil{}, Nil{}, False{}} : E.Decision}

law unverified_worktree_command_preserves_application:
  @+draft:U.Draft -> @+command:M.Command -> @+application:E.Application ->
  @blocked:{E.worktree_submission_allowed(U.contents(draft), application) == False{} : Bool} ->
  {E.execute(command, application, Some{draft}) ==
    E.Decision{application, D.failure("interaction_refused", "Wait for Git verification of the primary workspace before creating a worktree."), Nil{}, Nil{}, False{}} : E.Decision}

law unverified_saved_worktree_preference_stops_submission:
  @+draft:U.Draft -> @+command:M.Command -> @result:J.Json -> @+application:E.Application ->
  @blocked:{E.worktree_submission_allowed(U.contents(draft), application) == False{} : Bool} ->
  {E.finish_worktree_preference(True{}, draft, command, result, application) ==
    E.Decision{application, D.failure("interaction_refused", "Wait for Git verification of the primary workspace before creating a worktree."), Nil{}, Nil{}, False{}} : E.Decision}

law unavailable_worktree_does_not_change_project_preference:
  @body:U.Body -> @world:M.World() ->
  {E.worktree_preference_available(False{}, body, world) == None{} : Maybe<&2, M.Command>}

law refused_worktree_preference_stops_submission:
  @+draft:U.Draft -> @command:M.Command -> @+result:J.Json -> @+world:M.World() -> @+session:E.Session ->
  @failed:{J.boolean(J.get(result, "ok")) == False{} : Bool} ->
  {E.finish_worktree_preference(False{}, draft, command, result, E.from_program(world, session)) ==
    E.Decision{E.from_program(world, E.settle(draft, result, session)), result, Nil{}, Nil{}, False{}} : E.Decision}

law composer_side_command:
  @+task:Nat -> @+message:String -> @+question:String -> @delivery:U.Delivery -> @now:U32 ->
  @recognized:{U.side_conversation_question(message) == Some{question} : Maybe<&2, String>} ->
  {U.command(U.Message{task, U.initial_text(message), delivery}, now) == M.OpenSideConversation{task, question} : M.Command}

law composer_plain_message:
  @+task:Nat -> @+message:String -> @+delivery:U.Delivery -> @now:U32 ->
  @ordinary:{U.side_conversation_question(message) == None{} : Maybe<&2, String>} ->
  {U.command(U.Message{task, U.initial_text(message), delivery}, now) == U.message_command(delivery, task, message) : M.Command}

law side_creation_captures_composer_and_attention:
  @+parent:Nat -> @message:String -> @+draft:U.Draft -> @+application:E.Application ->
  {E.composer_completion(M.OpenSideConversation{parent, message}, draft, application) ==
    E.SideCreationCompletion{parent, Some{draft}, E.selection_generation(E.session(application)), E.next_layer(E.session(application))} : E.Completion}

law side_creation_requires_current_owner_and_attention:
  @+parent:Nat -> @+draft:Maybe<&2, U.Draft> -> @+generation:Nat -> @+layer_generation:Nat -> @+session:E.Session ->
  {E.side_creation_current(parent, draft, generation, layer_generation, session) ==
    E.task_visible(session, parent) && E.side_draft_owned(draft, session) && E.work_creation_current(generation, layer_generation, session) : Bool}

law stale_side_creation_settles_only_its_captured_draft:
  @+draft:Maybe<&2, U.Draft> -> @+result:J.Json -> @+application:E.Application ->
  {E.complete_side_creation_checked(False{}, draft, result, application) ==
    E.Decision{E.from_program(E.program(application), E.settle_side_draft(draft, result, E.session(application))), result, Nil{}, Nil{}, False{}} : E.Decision}

law side_window_dismissal_does_not_return_content:
  @task:Nat -> @trigger:String -> @initial:String -> @query:String -> @occurrence:Nat -> @source:Bool -> @field:Maybe<&2, Forms.Field> -> @buffer:Maybe<&2, String> -> @rest:+List<E.Layer> -> @+application:E.Application ->
  {E.dismiss_layers(E.Layer{U.SideConversation{task}, trigger, initial, query, occurrence, source, field, buffer} <> rest, application) == E.close_panel(application) : E.Decision}

law side_return_is_explicit:
  @+task:Nat ->
  {U.direct_command(U.ReturnSideConversation{task}) == Some{M.ReturnSideConversation{task}} : Maybe<&2, M.Command>}

law visible_tasks_include_side_windows_and_the_original_route:
  @+route:U.Route -> @+layers:+List<E.Layer> -> @+session:E.Session ->
  {E.visible_tasks(E.with_layers(layers, E.with_route(route, session))) == E.visible_route_tasks(route, layers) : +List<Nat>}

law interactive_documents_follow_visible_tasks:
  @+application:E.Application ->
  {E.interactive_synchronize(application) == E.interactive_result(Documents.reconcile_visible(E.visible_tasks(E.session(application)), E.previews(E.session(application)), E.program(application), E.interactive_data(E.session(application))), application) : E.Decision}

law captured_interactive_send_remains_literal:
  @+task:Nat -> @+message:String -> @now:U32 ->
  {E.interactive_message_command(U.Message{task, U.initial_text(message), U.Send{}}, now) == M.Send{task, message} : M.Command}
