import Base
import ../submission/FIELDS.bend as Forms
import ../../bendlib/categories.bend as Categories
import ../../harness/INVARIANTS.bend as I
import ../../features/board/MODEL.bend as B
import ../../features/board/STATE.bend as Board
import ../../harness/MODEL.bend as M
import ../../harness/PROGRAM.bend as Program
import ../../bendlib/association-map.bend as Finite
import ../../bendlib/component.bend as C
import ../../harness/DOMAIN.bend as D
import ../../bendlib/json.bend as J
import ../conversation/CODE.bend as Content
import ../conversation/OUTPUT.bend as Live
import ../services/CONTEXT.bend as Context
import ./MODEL.bend as E
import ./PROGRAM.bend as ExperienceProgram
import ../INPUT.bend as U
import ./CONTRACT.bend as Rule
import ../../harness/transport/command-codec.bend as CommandCodec
import ../submission/PROOF.bend as SubmissionProof

def open_allocation(+application: E.Application, +panel: U.Panel, +trigger: String) ->
  {E.open_panel(panel, trigger, application) == Rule.opened_application(application, panel, trigger) : E.Decision}:
  E.Application{program, E.Session{route, drafts, readers, layers, attention, navigation, filter,
    now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}} = application
  {==}

def open_residence(application: E.Application, panel: U.Panel, trigger: String) ->
  {Rule.residence(Rule.post(E.open_panel(panel, trigger, application))) == Rule.residence(application) : Rule.Residence}:
  E.Application{program, E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}} = application
  {==}

def open_attention(application: E.Application, panel: U.Panel, trigger: String) ->
  {Rule.attention(Rule.post(E.open_panel(panel, trigger, application))) == E.panel_target(panel) : String}:
  E.Application{program, E.Session{route, drafts, readers, layers, attention_value, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}} = application
  {==}

def open_effects(application: E.Application, panel: U.Panel, trigger: String) ->
  {Rule.interaction_effects(E.open_panel(panel, trigger, application)) == [E.Attend{E.panel_target(panel)}] : +List<E.Effect>}:
  E.Application{program, E.Session{route, drafts, readers, layers, attention_value, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}} = application
  {==}

def close_residence(application: E.Application) ->
  {Rule.residence(Rule.post(E.close_panel(application))) == Rule.residence(application) : Rule.Residence}:
  E.Application{program, E.Session{route, drafts, readers, +layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}} = application
  match layers:
    case Nil{}: {==}
    case Con{E.Layer{panel, trigger, initial, query, layer_occurrence, source_expanded, decision_field, parameter_buffer}, rest}: {==}

def sequence_attention(application: E.Application, +panel: U.Panel, +trigger: String) ->
  {Rule.attention(Rule.post(E.close_panel(Rule.post(E.open_panel(panel, trigger, application))))) == trigger : String}:
  E.Application{program, E.Session{route, drafts, readers, layers, attention_value, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}} = application
  {==}

def native_without_submission_keeps_content(decision: M.Decision(), session: E.Session, durable: Bool) ->
  {Rule.session_content(Rule.post(E.native_result(decision, session, None{}, durable))) ==
    Rule.session_content(E.Application{Rule.runtime_program(decision), session}) : Rule.SessionContent}:
  C.Decision{program, result, effects} = decision
  E.Session{route, drafts, readers, layers, attention_value, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git} = session
  {==}

def runtime_keeps_content(+input: M.Input, application: E.Application) ->
  {Rule.session_content(Rule.post(ExperienceProgram.step(E.RuntimeInput{input}, application))) == Rule.session_content(application) : Rule.SessionContent}:
  E.Application{program, session} = application
  native_without_submission_keeps_content(Program.transition(input, program), session, M.durable(input))

def native_without_submission_keeps_frame(decision: M.Decision(), session: E.Session, durable: Bool) ->
  {Rule.native_frame(Rule.post(E.native_result(decision, session, None{}, durable))) ==
    Rule.native_frame(E.Application{Rule.runtime_program(decision), session}) : Rule.NativeFrame}:
  C.Decision{program, result, effects} = decision
  E.Session{route, drafts, readers, layers, attention_value, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git} = session
  {==}

def native_without_submission_retains_previews(decision: M.Decision(), session: E.Session, durable: Bool) ->
  {Rule.previews(Rule.post(E.native_result(decision, session, None{}, durable))) ==
    Live.retained(Rule.previews(E.Application{Rule.runtime_program(decision), session}), Rule.runtime_program(decision)) : +List<Live.Output>}:
  C.Decision{program, result, effects} = decision
  E.Session{route, drafts, readers, layers, attention_value, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git} = session
  {==}

def preview_observation_keeps_content(observation: Live.Observation, application: E.Application) ->
  {Rule.session_content(Rule.post(ExperienceProgram.step(E.PreviewObserved{observation}, application))) == Rule.session_content(application) : Rule.SessionContent}:
  E.Application{program, E.Session{route, drafts, readers, layers, attention_value, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}} = application
  {==}

def navigate_keeps_drafts(route: U.Route, application: E.Application) ->
  {Rule.drafts(Rule.post(E.navigate(route, application))) == Rule.drafts(application) : +List<U.Draft>}:
  E.Application{program, E.Session{old, +drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}} = application
  {==}

def visit_preserves_location(reader: E.Reader) ->
  {Rule.reading_location(E.new_visit(reader)) == Rule.reading_location(reader) : Rule.ReadingLocation}:
  E.Reader{generation, position, disclosures} = reader
  {==}

def reading_spec(owned: Bool, task: Nat, intent: U.ReadingIntent, application: E.Application) -> E.Decision:
  match owned:
    case False{}: E.unchanged(application)
    case True{}: E.read(task, intent, application)

def reading_checked_refinement(owned: Bool, +task: Nat, generation: Nat, +intent: U.ReadingIntent, +application: E.Application, observed: {E.reading_owned(E.ReadingRequest{task, generation, intent, application}) == owned : Bool}) ->
  {E.reading_admitted(Categories.admit_checked(E.ReadingRequest, E.reading_owned, E.ReadingRequest{task, generation, intent, application}, owned, observed), application) == reading_spec(owned, task, intent, application) : E.Decision}:
  match owned:
    case False{}: {==}
    case True{}: {==}

def obsolete_reading(+task: Nat, +generation: Nat, +intent: U.ReadingIntent, +application: E.Application,
  not_owner: {Rule.reading_owner(application, task, generation) == False{} : Bool}) ->
  {ExperienceProgram.step(E.UserInput{U.ReadTimeline{task, generation, intent}}, application) == E.unchanged(application) : E.Decision}:
  E.Application{program, E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}} = application
  Equal.trans(E.Decision,
    E.read_current(task, generation, intent, application),
    reading_spec(Rule.reading_owner(application, task, generation), task, intent, application), E.unchanged(application),
    reading_checked_refinement(Rule.reading_owner(application, task, generation), task, generation, intent, application, {==}),
    Equal.cong(Bool, E.Decision, (owned => reading_spec(owned, task, intent, application)),
      Rule.reading_owner(application, task, generation), False{}, not_owner))

def model_choice(program: M.World(), route: U.Route, drafts: +List<U.Draft>, readers: +List<Finite.Entry(E.Reader)>,
  +trigger: String, initial: String, query: String, layer_occurrence: Nat, +source_expanded: Bool, +decision_field: Maybe<&2, Forms.Field>, +parameter_buffer: Maybe<&2, String>, rest: +List<E.Layer>, old_attention: String,
  navigation: E.NavigationState, filter: B.Filter, now: U32, next: Nat, pending: +List<E.Pending>,
  previews: +List<Live.Output>, code_blocks: +List<Content.Block>, next_layer: Nat, model_preference: Maybe<&2, E.ModelPreference>, draft_model_manual: Bool, workspace_git: E.WorkspaceGit, revision: Nat, text: U.Text,
  old_profile: String, old_reasoning: String, context: Context.Configuration, feedback: U.Feedback, +directory_entry: String,
  +new_profile: String, +new_reasoning: String,
  valid: {E.permitted_preference(D.find_profile(Board.profiles(program), new_profile), new_reasoning) == True{} : Bool},
  found: {E.find_draft(drafts, U.NewTaskEditor{}) ==
    Some{U.Draft{revision, U.NewTask{text, old_profile, old_reasoning, context, False{}}, feedback, directory_entry}} : Maybe<&2, U.Draft>}) ->
  {ExperienceProgram.step(E.UserInput{U.EditDraft{U.NewTaskEditor{}, U.ChooseModel{new_profile, new_reasoning}}},
      E.Application{program, E.Session{route, drafts, readers,
        E.Layer{U.ModelPicker{U.NewTaskEditor{}}, trigger, initial, query, layer_occurrence, source_expanded, None{}, None{}} <> rest,
        old_attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}}) ==
    E.remember_manual(U.ChooseModel{new_profile, new_reasoning}, E.Decision{E.Application{program, E.Session{route,
      U.Draft{(revision + 1n : Nat), U.NewTask{text, new_profile, new_reasoning, context, False{}}, U.Editing{}, directory_entry} <>
        E.without_draft(drafts, U.NewTaskEditor{}),
      readers, rest, trigger, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}},
      D.success(J.Null{}), Nil{}, [E.Attend{trigger}], False{}}) : E.Decision}:
  session: E.Session = E.Session{route, drafts, readers,
    E.Layer{U.ModelPicker{U.NewTaskEditor{}}, trigger, initial, query, layer_occurrence, source_expanded, None{}, None{}} <> rest,
    old_attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}
  Equal.trans(E.Decision,
    E.manual_creation_edit(E.permitted_preference(D.find_profile(Board.profiles(program), new_profile), new_reasoning), U.ChooseModel{new_profile, new_reasoning}, E.Application{program, session}),
    E.manual_creation_edit(True{}, U.ChooseModel{new_profile, new_reasoning}, E.Application{program, session}),
    E.remember_manual(U.ChooseModel{new_profile, new_reasoning}, E.Decision{E.Application{program, E.Session{route,
      U.Draft{(revision + 1n : Nat), U.NewTask{text, new_profile, new_reasoning, context, False{}}, U.Editing{}, directory_entry} <>
        E.without_draft(drafts, U.NewTaskEditor{}),
      readers, rest, trigger, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}},
      D.success(J.Null{}), Nil{}, [E.Attend{trigger}], False{}}),
    Equal.cong(Bool, E.Decision,
      valid => E.manual_creation_edit(valid, U.ChooseModel{new_profile, new_reasoning}, E.Application{program, session}),
      E.permitted_preference(D.find_profile(Board.profiles(program), new_profile), new_reasoning), True{}, valid),
    Equal.cong(Maybe<&2, U.Draft>, E.Decision,
      (found_draft => E.remember_manual(U.ChooseModel{new_profile, new_reasoning}, E.close_selected_choice(U.ChooseModel{new_profile, new_reasoning}, U.NewTaskEditor{},
        E.edit_found(found_draft, U.ChooseModel{new_profile, new_reasoning}, program, session)))),
      E.find_draft(drafts, U.NewTaskEditor{}),
      Some{U.Draft{revision, U.NewTask{text, old_profile, old_reasoning, context, False{}}, feedback, directory_entry}}, found))

def encapsulated_model_choice(+session: E.Session, +program: M.World(), +trigger: String, initial: String, query: String, +layer_occurrence: Nat, +source_expanded: Bool, +decision_field: Maybe<&2, Forms.Field>, +parameter_buffer: Maybe<&2, String>, +rest: +List<E.Layer>, revision: Nat, +text: U.Text, old_profile: String, old_reasoning: String, context: Context.Configuration, feedback: U.Feedback, +directory_entry: String, +new_profile: String, +new_reasoning: String, valid: {E.permitted_preference(D.find_profile(Board.profiles(program), new_profile), new_reasoning) == True{} : Bool}, observed_layers: {E.layers(session) == E.Layer{U.ModelPicker{U.NewTaskEditor{}}, trigger, initial, query, layer_occurrence, source_expanded, None{}, None{}} <> rest : +List<E.Layer>}, found: {E.find_draft(E.drafts(session), U.NewTaskEditor{}) ==
        Some{U.Draft{revision, U.NewTask{text, old_profile, old_reasoning, context, False{}}, feedback, directory_entry}} : Maybe<&2, U.Draft>}) ->
  {ExperienceProgram.step(E.UserInput{U.EditDraft{U.NewTaskEditor{}, U.ChooseModel{new_profile, new_reasoning}}},
        E.from_program(program, session)) ==
       E.remember_manual(U.ChooseModel{new_profile, new_reasoning}, E.Decision{E.from_program(program, E.with_attention(trigger, E.with_layers(rest, E.with_drafts(U.Draft{(revision + 1n : Nat), U.NewTask{text, new_profile, new_reasoning, context, False{}}, U.Editing{}, directory_entry} <>
           E.without_draft(E.drafts(session), U.NewTaskEditor{}), session)))),
         D.success(J.Null{}), Nil{}, [E.Attend{trigger}], False{}}) : E.Decision}:
  E.Session{+route, +drafts, +readers, +stored_layers, +old_attention, +navigation, +filter, +now, +next, +pending, +previews, +code_blocks, +next_layer, model_preference, draft_model_manual, workspace_git} = session
  backwards_layers = Equal.sym(E.Session, session, E.with_layers(E.Layer{U.ModelPicker{U.NewTaskEditor{}}, trigger, initial, query, layer_occurrence, source_expanded, None{}, None{}} <> rest, session),
    Equal.cong(+List<E.Layer>, E.Session, value => E.with_layers(value, session), E.layers(session), E.Layer{U.ModelPicker{U.NewTaskEditor{}}, trigger, initial, query, layer_occurrence, source_expanded, None{}, None{}} <> rest, observed_layers))
  %backwards_layers : {ExperienceProgram.step(E.UserInput{U.EditDraft{U.NewTaskEditor{}, U.ChooseModel{new_profile, new_reasoning}}},
        E.from_program(program, _)) ==
       E.remember_manual(U.ChooseModel{new_profile, new_reasoning}, E.Decision{E.from_program(program, E.with_attention(trigger, E.with_layers(rest, E.with_drafts(U.Draft{(revision + 1n : Nat), U.NewTask{text, new_profile, new_reasoning, context, False{}}, U.Editing{}, directory_entry} <>
           E.without_draft(E.drafts(_), U.NewTaskEditor{}), _)))),
         D.success(J.Null{}), Nil{}, [E.Attend{trigger}], False{}}) : E.Decision}
  model_choice(program, route, drafts, readers, trigger, initial, query, layer_occurrence, source_expanded, decision_field, parameter_buffer, rest, old_attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git, revision, text, old_profile, old_reasoning, context, feedback, directory_entry, new_profile, new_reasoning, valid, found)

def model_choice_checked(valid: Bool, +profile: String, +reasoning: String, +application: E.Application) ->
  {E.manual_creation_edit(valid, U.ChooseModel{profile, reasoning}, application) == Rule.model_choice_spec(valid, profile, reasoning, application) : E.Decision}:
  match valid:
    case False{}: {==}
    case True{}: {==}

def model_choice_complete(+profile: String, +reasoning: String, +application: E.Application) ->
  {ExperienceProgram.step(E.UserInput{U.EditDraft{U.NewTaskEditor{}, U.ChooseModel{profile, reasoning}}}, application) ==
    Rule.model_choice_spec(E.permitted_preference(D.find_profile(Board.profiles(E.program(application)), profile), reasoning), profile, reasoning, application) : E.Decision}:
  E.Application{program, session} = application
  model_choice_checked(E.permitted_preference(D.find_profile(Board.profiles(program), profile), reasoning), profile, reasoning, E.Application{program, session})

def invalid_model_choice(+profile: String, +reasoning: String, +application: E.Application,
  invalid: {E.permitted_preference(D.find_profile(Board.profiles(E.program(application)), profile), reasoning) == False{} : Bool}) ->
  {ExperienceProgram.step(E.UserInput{U.EditDraft{U.NewTaskEditor{}, U.ChooseModel{profile, reasoning}}}, application) ==
    E.Decision{application, D.failure("interaction_refused", "Choose an available model and permitted reasoning effort."), Nil{}, Nil{}, False{}} : E.Decision}:
  Equal.trans(E.Decision,
    ExperienceProgram.step(E.UserInput{U.EditDraft{U.NewTaskEditor{}, U.ChooseModel{profile, reasoning}}}, application),
    Rule.model_choice_spec(E.permitted_preference(D.find_profile(Board.profiles(E.program(application)), profile), reasoning), profile, reasoning, application),
    E.Decision{application, D.failure("interaction_refused", "Choose an available model and permitted reasoning effort."), Nil{}, Nil{}, False{}},
    model_choice_complete(profile, reasoning, application),
    Equal.cong(Bool, E.Decision, valid => Rule.model_choice_spec(valid, profile, reasoning, application),
      E.permitted_preference(D.find_profile(Board.profiles(E.program(application)), profile), reasoning), False{}, invalid))

def encapsulated_modal_close_empty(+session: E.Session, +program: M.World(), observed_layers: {E.layers(session) == Nil{} : +List<E.Layer>}) ->
  {E.close_panel(E.from_program(program, session)) ==
       E.unchanged(E.from_program(program, session)) : E.Decision}:
  E.Session{+route, +drafts, +readers, +stored_layers, +attention_value, +navigation, +filter, +now, +next, +pending, +previews, +code_blocks, +next_layer, model_preference, draft_model_manual, workspace_git} = session
  backwards_layers = Equal.sym(E.Session, session, E.with_layers(Nil{}, session),
    Equal.cong(+List<E.Layer>, E.Session, value => E.with_layers(value, session), E.layers(session), Nil{}, observed_layers))
  %backwards_layers : {E.close_panel(E.from_program(program, _)) ==
       E.unchanged(E.from_program(program, _)) : E.Decision}
  {==}

def encapsulated_modal_close_nonempty(+session: E.Session, +program: M.World(), +panel: U.Panel, +trigger: String, initial: String, query: String, +layer_occurrence: Nat, +source_expanded: Bool, +decision_field: Maybe<&2, Forms.Field>, +parameter_buffer: Maybe<&2, String>, +rest: +List<E.Layer>, observed_layers: {E.layers(session) == E.Layer{panel, trigger, initial, query, layer_occurrence, source_expanded, decision_field, parameter_buffer} <> rest : +List<E.Layer>}) ->
  {E.close_panel(E.from_program(program, session)) ==
       E.Decision{E.from_program(program, E.with_attention(trigger, E.with_layers(rest, session))),
        D.success(J.Null{}), Nil{}, [E.Attend{trigger}], False{}} : E.Decision}:
  E.Session{+route, +drafts, +readers, +stored_layers, +old_attention, +navigation, +filter, +now, +next, +pending, +previews, +code_blocks, +next_layer, model_preference, draft_model_manual, workspace_git} = session
  backwards_layers = Equal.sym(E.Session, session, E.with_layers(E.Layer{panel, trigger, initial, query, layer_occurrence, source_expanded, decision_field, parameter_buffer} <> rest, session),
    Equal.cong(+List<E.Layer>, E.Session, value => E.with_layers(value, session), E.layers(session), E.Layer{panel, trigger, initial, query, layer_occurrence, source_expanded, decision_field, parameter_buffer} <> rest, observed_layers))
  %backwards_layers : {E.close_panel(E.from_program(program, _)) ==
       E.Decision{E.from_program(program, E.with_attention(trigger, E.with_layers(rest, _))),
        D.success(J.Null{}), Nil{}, [E.Attend{trigger}], False{}} : E.Decision}
  {==}

def catalog_selection_if_refinement(valid: Bool, profile: D.Profile, fallback: Sigma<&2, &2, String, (_ => String)>) ->
  {E.first_valid_profile(valid, profile, fallback) == Rule.catalog_selection_if(valid, profile, fallback) : Sigma<&2, &2, String, (_ => String)>}:
  match valid profile:
    case True{} D.Profile{key, provider, name, policy, options}: {==}
    case False{} _: {==}

def catalog_selection_refinement(+profiles: +List<D.Profile>) ->
  {E.first_profile(profiles) == Rule.catalog_selection(profiles) : Sigma<&2, &2, String, (_ => String)>}:
  match profiles:
    case Nil{}: {==}
    case Con{+profile, +rest}:
      Equal.trans(Sigma<&2, &2, String, (_ => String)>, E.first_profile(profiles),
        E.first_valid_profile(Bool.not(D.is_codex_auto_review(profile)) && D.profile_valid(profile) && D.profile_permitted(profile, D.profile_default(profile)), profile, Rule.catalog_selection(rest)), Rule.catalog_selection(profiles),
        Equal.cong(Sigma<&2, &2, String, (_ => String)>, Sigma<&2, &2, String, (_ => String)>,
          fallback => E.first_valid_profile(Bool.not(D.is_codex_auto_review(profile)) && D.profile_valid(profile) && D.profile_permitted(profile, D.profile_default(profile)), profile, fallback),
          E.first_profile(rest), Rule.catalog_selection(rest), catalog_selection_refinement(rest)),
        catalog_selection_if_refinement(Bool.not(D.is_codex_auto_review(profile)) && D.profile_valid(profile) && D.profile_permitted(profile, D.profile_default(profile)), profile, Rule.catalog_selection(rest)))

def preference_selection_if_refinement(valid: Bool, value: E.ModelPreference, +profiles: +List<D.Profile>) ->
  {E.preferred_if(valid, value, profiles) == Rule.preference_selection_if(valid, value, profiles) : Sigma<&2, &2, String, (_ => String)>}:
  match valid value:
    case True{} E.ModelPreference{profile, reasoning}: {==}
    case False{} _: catalog_selection_refinement(profiles)

def preference_selection_refinement(+value: Maybe<&2, E.ModelPreference>, +profiles: +List<D.Profile>) ->
  {E.preferred_selection(value, profiles) == Rule.preference_selection(value, profiles) : Sigma<&2, &2, String, (_ => String)>}:
  match value:
    case None{}: catalog_selection_refinement(profiles)
    case Some{E.ModelPreference{+profile, +reasoning}}:
      preference_selection_if_refinement(E.permitted_preference(D.find_profile(profiles, profile), reasoning), E.ModelPreference{profile, reasoning}, profiles)

def selected_model_session_refinement(selection: Sigma<&2, &2, String, (_ => String)>, revision: Nat, message: U.Text, context: Context.Configuration, feedback: U.Feedback, directory_entry: String, create_worktree: Bool, session: E.Session) ->
  {E.resolved_model_selection(selection, revision, message, context, feedback, directory_entry, create_worktree, session) == Rule.selected_model_session(selection, revision, message, context, feedback, directory_entry, create_worktree, session) : E.Session}:
  (selected, effort) = selection
  {==}

def model_resolution_if_refinement(+valid: Bool, +draft: U.Draft, +profiles: +List<D.Profile>, +session: E.Session) ->
  {E.resolve_model_valid(valid, draft, profiles, session) == Rule.model_resolution_if(valid, draft, profiles, session) : E.Session}:
  match valid draft:
    case False{} U.Draft{revision, U.NewTask{message, profile, reasoning, context, create_worktree}, feedback, directory_entry}:
      Equal.trans(E.Session,
        E.resolved_model_selection(E.preferred_selection(E.preference(session), profiles), revision, message, context, feedback, directory_entry, create_worktree, session),
        E.resolved_model_selection(Rule.preference_selection(E.preference(session), profiles), revision, message, context, feedback, directory_entry, create_worktree, session),
        Rule.selected_model_session(Rule.preference_selection(E.preference(session), profiles), revision, message, context, feedback, directory_entry, create_worktree, session),
        Equal.cong(Sigma<&2, &2, String, (_ => String)>, E.Session,
          selection => E.resolved_model_selection(selection, revision, message, context, feedback, directory_entry, create_worktree, session),
          E.preferred_selection(E.preference(session), profiles), Rule.preference_selection(E.preference(session), profiles),
          preference_selection_refinement(E.preference(session), profiles)),
        selected_model_session_refinement(Rule.preference_selection(E.preference(session), profiles), revision, message, context, feedback, directory_entry, create_worktree, session))
    case True{} _: {==}
    case False{} U.Draft{revision, U.Message{task, message, delivery}, feedback, directory_entry}: {==}
    case False{} U.Draft{revision, U.Project{project, name, workspace, create_worktree}, feedback, directory_entry}: {==}
    case False{} U.Draft{revision, U.Card{card, revision2, value, assist, profile, keep_open}, feedback, directory_entry}: {==}
    case False{} U.Draft{revision, U.Agent{agent, revision2, name, profile, reasoning, instructions, context, concurrency}, feedback, directory_entry}: {==}
    case False{} U.Draft{revision, U.Fork{task, count, messages, context}, feedback, directory_entry}: {==}
    case False{} U.Draft{revision, U.Compact{task, summary}, feedback, directory_entry}: {==}
    case False{} U.Draft{revision, U.TaskGraph{graph, declaration, parsed}, feedback, directory_entry}: {==}

def model_resolution_found_refinement(+found: Maybe<&2, U.Draft>, +profiles: +List<D.Profile>, +session: E.Session) ->
  {E.resolve_model_found(found, profiles, session) == Rule.model_resolution_found(found, profiles, session) : E.Session}:
  match found:
    case Some{U.Draft{revision, U.NewTask{message, +profile, +reasoning, context, create_worktree}, feedback, directory_entry}}:
      model_resolution_if_refinement(E.manual_model(session) && E.permitted_preference(D.find_profile(profiles, profile), reasoning), U.Draft{revision, U.NewTask{message, profile, reasoning, context, create_worktree}, feedback, directory_entry}, profiles, session)
    case None{}: {==}
    case Some{U.Draft{revision, U.Message{task, message, delivery}, feedback, directory_entry}}: {==}
    case Some{U.Draft{revision, U.Project{project, name, workspace, create_worktree}, feedback, directory_entry}}: {==}
    case Some{U.Draft{revision, U.Card{card, revision2, value, assist, profile, keep_open}, feedback, directory_entry}}: {==}
    case Some{U.Draft{revision, U.Agent{agent, revision2, name, profile, reasoning, instructions, context, concurrency}, feedback, directory_entry}}: {==}
    case Some{U.Draft{revision, U.Fork{task, count, messages, context}, feedback, directory_entry}}: {==}
    case Some{U.Draft{revision, U.Compact{task, summary}, feedback, directory_entry}}: {==}
    case Some{U.Draft{revision, U.TaskGraph{graph, declaration, parsed}, feedback, directory_entry}}: {==}

def model_resolution_complete(+session: E.Session, +world: M.World()) ->
  {E.resolve_model_draft(session, world) == Rule.model_resolution(session, world) : E.Session}:
  model_resolution_found_refinement(E.find_draft(E.drafts(session), U.NewTaskEditor{}), Board.profiles(world), session)

def begin_focus_refinement(world: M.World(), session: E.Session) ->
  {E.navigate_with_attention(U.Start{}, "composer/new-task", E.Application{world, session}) == Rule.begin_focus(world, session) : E.Decision}:
  E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code, next_layer, preference, manual, workspace_git} = session
  {==}

def begin_changed_refinement(+result: Result<&2, &2, String, U.Body>, +revision: Nat, +directory_entry: String, +world: M.World(), +session: E.Session) ->
  {E.begin_changed(result, revision, directory_entry, E.Application{world, session}) == Rule.begin_changed_spec(result, revision, directory_entry, world, session) : E.Decision}:
  match result:
    case Fail{reason}: {==}
    case Done{body}: begin_focus_refinement(world, E.with_draft(session, U.Draft{(revision + 1n : Nat), body, U.Editing{}, directory_entry}))

def begin_existing_refinement(+found: Maybe<&2, U.Draft>, +origin: Context.Origin, +world: M.World(), +session: E.Session) ->
  {E.begin_existing(found, origin, E.Application{world, session}) == Rule.begin_existing_spec(found, origin, world, session) : E.Decision}:
  match found:
    case None{}: begin_focus_refinement(world, session)
    case Some{U.Draft{revision, body, feedback, directory_entry}}:
      begin_changed_refinement(U.apply_edit(U.ConfigureContext{Context.ChooseOrigin{origin}}, body, world), revision, directory_entry, world, session)

def begin_resolved_refinement(+origin: Context.Origin, +world: M.World(), +session: E.Session) ->
  {E.begin_resolved(origin, world, session) == Rule.begin_resolved_spec(origin, world, session) : E.Decision}:
  begin_existing_refinement(E.find_draft(E.drafts(session), U.NewTaskEditor{}), origin, world, session)

def begin_task_complete(+project: Maybe<&2, Nat>, +world: M.World(), +session: E.Session) ->
  {E.begin_task(project, E.Application{world, session}) == Rule.begin_task_spec(project, world, session) : E.Decision}:
  E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code, next_layer, preference, manual, workspace_git} = session
  Equal.trans(E.Decision, E.begin_task(project, E.Application{world, session}),
    E.begin_resolved(E.context_project(project), world, Rule.model_resolution(session, world)), Rule.begin_task_spec(project, world, session),
    Equal.cong(E.Session, E.Decision, resolved => E.begin_resolved(E.context_project(project), world, resolved),
      E.resolve_model_draft(session, world), Rule.model_resolution(session, world), model_resolution_complete(session, world)),
    begin_resolved_refinement(E.context_project(project), world, Rule.model_resolution(session, world)))

def Rule.evidence():
  Rule.Requirements{
    application => panel => trigger => open_allocation(application, panel, trigger),
    application => panel => trigger => open_residence(application, panel, trigger),
    application => panel => trigger => open_attention(application, panel, trigger),
    application => panel => trigger => open_effects(application, panel, trigger),
    encapsulated_modal_close_nonempty,
    encapsulated_modal_close_empty,
    application => panel => trigger => sequence_attention(application, panel, trigger),
    +application => +panel => +trigger =>
      Equal.trans(Rule.Residence,
        Rule.residence(Rule.post(E.close_panel(Rule.post(E.open_panel(panel, trigger, application))))),
        Rule.residence(Rule.post(E.open_panel(panel, trigger, application))), Rule.residence(application),
        close_residence(Rule.post(E.open_panel(panel, trigger, application))),
        open_residence(application, panel, trigger)),
    input => application => runtime_keeps_content(input, application),
    decision => session => durable => native_without_submission_keeps_frame(decision, session, durable),
    decision => session => durable => native_without_submission_retains_previews(decision, session, durable),
    observation => application => preview_observation_keeps_content(observation, application),
    route => application => navigate_keeps_drafts(route, application),
    reader => visit_preserves_location(reader),
    task => generation => intent => application => not_owner => obsolete_reading(task, generation, intent, application, not_owner),
    encapsulated_model_choice,
    model_choice_complete,
    invalid_model_choice,
    profile => reasoning => world => session => reply => runtime => interaction => durable => {==},
    begin_task_complete,
    model_resolution_complete,
    draft => profiles => session => {==},
    {==},
    profile => reasoning => world => session => {==},
    message => profile => reasoning => context => result => world => session => {==},
    task => profile => reasoning => remember => world => result => previous => session => {==}
  }

def native_decision(+decision: M.Decision(), session: E.Session, durable: Bool) ->
  {Rule.runtime_observation(E.native_result(decision, session, None{}, durable)) == decision : M.Decision()}:
  C.Decision{program, reply, effects} = decision
  E.Session{route, drafts, readers, layers, focus, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git} = session
  {==}

def runtime_input(+input: M.Input, +program: M.World(), session: E.Session) ->
  {Rule.runtime_observation(ExperienceProgram.step(E.RuntimeInput{input}, E.Application{program, session})) ==
    Program.transition(input, program) : M.Decision()}:
  native_decision(Program.transition(input, program), session, M.durable(input))

# Requests preserve the entire application until the server supplies a receipt.

def accepted_confirmation_refinement(ok: Bool, +result: J.Json, destination: U.Route, application: E.Application) ->
  {E.with_native(E.confirmation_outcome(ok, destination, application), result, Nil{}, False{}) == Rule.accepted_confirmation_spec(ok, result, destination, application) : E.Decision}:
  match ok:
    case True{}: {==}
    case False{}: {==}


def confirmation_identity_refinement(+layers: +List<E.Layer>, +command: M.Command, +trigger: String, +occurrence: Nat) ->
  {E.confirmation_owned(layers, command, trigger, occurrence) == Rule.confirmation_spec(layers, command, trigger, occurrence) : Bool}:
  match layers:
    case Nil{}: {==}
    case Con{E.Layer{panel, current_trigger, target, query, layer_occurrence, source_expanded, decision_field, parameter_buffer}, rest}:
      match panel:
        case U.Confirm{current, title, destination}: {==}
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
        case U.PropertySource{origin}: {==}
        case U.DeliveryPicker{task}: {==}


def confirmation_checked_refinement(owned: Bool, +command: M.Command, +trigger: String, +occurrence: Nat, +result: J.Json, +destination: U.Route, +application: E.Application, observed: {E.receipt_owned(E.ConfirmationReceipt{command, trigger, occurrence, result, destination, application}) == owned : Bool}) ->
  {E.confirmation_admitted(Categories.admit_checked(E.ConfirmationReceipt, E.receipt_owned, E.ConfirmationReceipt{command, trigger, occurrence, result, destination, application}, owned, observed), result, application) == Rule.confirmation_result_spec(owned, result, destination, application) : E.Decision}:
  match owned:
    case False{}: {==}
    case True{}:
      accepted_confirmation_refinement(J.boolean(J.get(result, "ok")), result, destination, application)

def completed_checked_refinement(valid: Bool, +completion: E.Completion, +program: M.World(), +result: J.Json, +session: E.Session, previous: M.World(), observed: {I.world(program) == valid : Bool}) ->
  {E.complete_command_admitted(Categories.admit_checked(M.World(), (world => I.world(world)), program, valid, observed), result, completion, E.Application{previous, session}) == Rule.completion_checked_spec(valid, completion, program, result, session, previous) : E.Decision}:
  match valid:
    case False{}: {==}
    case True{}:
      match completion:
        case E.ExecutionViewCompletion{task, profile, reasoning, remember, occurrence}: {==}
        case E.ExecutionCompletion{task, profile, reasoning, remember}: {==}
        case E.DirectCompletion{}: {==}
        case E.WorktreePreferenceCompletion{draft, command}: {==}
        case E.DraftCompletion{draft}: SubmissionProof.native_session_refinement(Some{draft}, program, result, Nil{}, E.retain_previews(session, program), False{})
        case E.ConfirmationCompletion{command, trigger, destination, occurrence}:
          E.Session{route, drafts, readers, +layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git} = session
          +updated: E.Application = E.Application{program, E.retain_previews(E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git}, program)}
          Equal.trans(E.Decision,
            E.complete_confirmation_current(command, trigger, occurrence, result, destination, updated),
            Rule.confirmation_result_spec(E.confirmation_owned(layers, command, trigger, occurrence), result, destination, updated),
            Rule.confirmation_result_spec(Rule.confirmation_spec(layers, command, trigger, occurrence), result, destination, updated),
            confirmation_checked_refinement(E.confirmation_owned(layers, command, trigger, occurrence), command, trigger, occurrence, result, destination, updated, {==}),
            Equal.cong(Bool, E.Decision, (owned => Rule.confirmation_result_spec(owned, result, destination, updated)),
              E.confirmation_owned(layers, command, trigger, occurrence), Rule.confirmation_spec(layers, command, trigger, occurrence),
              confirmation_identity_refinement(layers, command, trigger, occurrence)))

def completed_refinement(+completion: E.Completion, +program: M.World(), +result: J.Json, +session: E.Session, previous: M.World()) ->
  {ExperienceProgram.step(E.CommandCompleted{program, result, completion}, E.Application{previous, session}) == Rule.completion_spec(completion, program, result, session, previous) : E.Decision}:
  completed_checked_refinement(I.world(program), completion, program, result, session, previous, {==})

def observed_checked_refinement(valid: Bool, +program: M.World(), +session: E.Session, previous: M.World(), observed: {I.world(program) == valid : Bool}) ->
  {E.observe_program_admitted(Categories.admit_checked(M.World(), (world => I.world(world)), program, valid, observed), E.Application{previous, session}) == Rule.observed_checked_spec(valid, program, session, previous) : E.Decision}:
  match valid:
    case False{}: {==}
    case True{}: {==}

def stale_checked_refinement(valid: Bool, +program: M.World(), +result: J.Json, +draft: U.Draft, +session: E.Session, previous: M.World(), observed: {I.world(program) == valid : Bool}, absent: {E.owns_submission(draft, E.retain_previews(session, program)) == False{} : Bool}) ->
  {E.complete_command_admitted(Categories.admit_checked(M.World(), (world => I.world(world)), program, valid, observed), result, E.DraftCompletion{draft}, E.Application{previous, session}) == Rule.stale_completion_spec(valid, previous, program, result, session) : E.Decision}:
  match valid:
    case False{}: {==}
    case True{}: SubmissionProof.stale_native(draft, program, result, Nil{}, E.retain_previews(session, program), False{}, absent)

def preference_request_refinement(preference: Maybe<&2, M.Command>, command: M.Command, draft: U.Draft, application: E.Application) ->
  {E.execute_preference(preference, command, draft, application) == Rule.preference_request_spec(preference, command, draft, application) : E.Decision}:
  match preference:
    case None{}: {==}
    case Some{update}: {==}

def submission_checked_refinement(allowed: Bool, preference: Maybe<&2, M.Command>, command: M.Command, draft: U.Draft, application: E.Application) ->
  {E.execute_submitted(allowed, preference, command, draft, application) == Rule.submission_checked_spec(allowed, preference, command, draft, application) : E.Decision}:
  match allowed:
    case False{}: {==}
    case True{}: preference_request_refinement(preference, command, draft, application)

def submission_request_refinement(+command: M.Command, +application: E.Application, +submitted: Maybe<&2, U.Draft>) ->
  {E.execute(command, application, submitted) == Rule.submission_request_spec(command, application, submitted) : E.Decision}:
  match submitted:
    case None{}: {==}
    case Some{+draft}: submission_checked_refinement(E.worktree_submission_allowed(U.contents(draft), application), E.worktree_preference_available(E.worktree_available(application), U.contents(draft), E.program(application)), command, draft, application)

def Rule.command_evidence():
  Rule.CommandRequirements{
    completion => program => result => session => previous => completed_refinement(completion, program, result, session, previous),
    submission_request_refinement,
    +program => +session => previous => observed_checked_refinement(I.world(program), program, session, previous, {==}),

      # The submitted snapshot is settled only if its editor still has that revision;
      # the existing submission laws establish acceptance, refusal and stale ownership.
    +program => +result => +draft => +session => previous => absent => stale_checked_refinement(I.world(program), program, result, draft, session, previous, {==}, absent),
    +result => destination => application => accepted =>
      Equal.cong(Bool, E.Decision,
        (ok => E.with_native(E.confirmation_outcome(ok, destination, application), result, Nil{}, False{})),
        J.boolean(J.get(result, "ok")), True{}, accepted)
    ,
    +result => destination => +application => rejected =>
      Equal.cong(Bool, E.Decision,
        (ok => E.with_native(E.confirmation_outcome(ok, destination, application), result, Nil{}, False{})),
        J.boolean(J.get(result, "ok")), False{}, rejected)
    ,
    result => destination => application =>
        {==}

    , +current => title => destination => +current_trigger => target => query => +current_occurrence => rest => +command => +trigger => +occurrence => stale =>
      Equal.cong(Bool, Bool,
        (same => same && (String.eq(current_trigger, trigger) && J.same(CommandCodec.command_json(current), CommandCodec.command_json(command)))),
        Nat.is_eq(current_occurrence, occurrence), False{}, stale)

      # The receipt contract independently selects the local completion behavior.

  }

def Rule.invalid_observed_decision():
  +program => +session => +previous => observed =>
  Equal.trans(E.Decision, ExperienceProgram.step(E.ProgramObserved{program}, E.from_program(previous, session)), Rule.observed_spec(program, session, previous), E.refuse(E.from_program(previous, session), "The observed program violates a world invariant"),
    observed_checked_refinement(I.world(program), program, session, previous, {==}),
    Equal.cong(Bool, E.Decision, (value => Rule.observed_checked_spec(value, program, session, previous)), I.world(program), False{}, observed))

def Rule.valid_observed_decision():
  +program => +session => +previous => observed =>
  Equal.trans(E.Decision, ExperienceProgram.step(E.ProgramObserved{program}, E.from_program(previous, session)), Rule.observed_spec(program, session, previous), E.Decision{E.from_program(program, E.resolve_model_draft(E.retain_previews(session, program), program)), D.success(J.Null{}), Nil{}, Nil{}, False{}},
    observed_checked_refinement(I.world(program), program, session, previous, {==}),
    Equal.cong(Bool, E.Decision, (value => Rule.observed_checked_spec(value, program, session, previous)), I.world(program), True{}, observed))

def Rule.invalid_completion_decision():
  +completion => +program => +result => +session => +previous => observed =>
  Equal.trans(E.Decision, ExperienceProgram.step(E.CommandCompleted{program, result, completion}, E.from_program(previous, session)), Rule.completion_spec(completion, program, result, session, previous), E.refuse(E.from_program(previous, session), "The observed program violates a world invariant"),
    completed_refinement(completion, program, result, session, previous),
    Equal.cong(Bool, E.Decision, (value => Rule.completion_checked_spec(value, completion, program, result, session, previous)), I.world(program), False{}, observed))

def Rule.valid_completion_decision():
  +completion => +program => +result => +session => +previous => observed =>
  Equal.trans(E.Decision, ExperienceProgram.step(E.CommandCompleted{program, result, completion}, E.from_program(previous, session)), Rule.completion_spec(completion, program, result, session, previous), Rule.valid_completion_spec(completion, program, result, session),
    completed_refinement(completion, program, result, session, previous),
    Equal.cong(Bool, E.Decision, (value => Rule.completion_checked_spec(value, completion, program, result, session, previous)), I.world(program), True{}, observed))

def Rule.valid_stale_completion_decision():
  +program => +result => +draft => +session => +previous => observed => absent =>
  Equal.trans(E.Decision,
    ExperienceProgram.step(E.CommandCompleted{program, result, E.DraftCompletion{draft}}, E.from_program(previous, session)),
    Rule.stale_completion_spec(I.world(program), previous, program, result, session),
    E.Decision{E.from_program(program, E.retain_previews(session, program)), result, Nil{}, Nil{}, False{}},
    stale_checked_refinement(I.world(program), program, result, draft, session, previous, {==}, absent),
    Equal.cong(Bool, E.Decision, (value => Rule.stale_completion_spec(value, previous, program, result, session)), I.world(program), True{}, observed))

def Rule.submission_requirements_gate(pending, world, revision, body, feedback, entry): {==}

def Rule.invalid_preparation_complete_refusal(pending, world, revision, body, feedback, entry, application): {==}

def Rule.workspace_settlement_preserves_stale_draft(draft, revision, reason, session): {==}
def Rule.workspace_settlement_retains_body(revision, body, feedback, entry, submitted, reason, session): {==}
def Rule.rejected_command_uses_actual_code_and_workspace(body, revision, result): {==}
def Rule.property_source_toggle_preserves_application(panel, trigger, initial, query, occurrence, expanded, field, parameter_buffer, rest, application):
  E.Application{program, session} = application
  {==}
def Rule.property_source_toggle_refuses_wrong_owner(panel, trigger, initial, query, occurrence, expanded, field, parameter_buffer, rest, application): {==}
def Rule.invalid_workspace_retry_preserves_application(draft, application): {==}

def Rule.workspace_preparation_failure_complete(draft, reason, application):
  E.Application{program, session} = application
  {==}
def Rule.blocked_workspace_retry_retains_failure(draft, application): {==}
def Rule.accepted_workspace_retry_uses_normal_admission(revision, body, feedback, entry, application): {==}

def Rule.workspace_command_not_submitted_feedback(body, revision, reason): {==}

def Rule.unknown_decision_focus_preserves_application(editor, application):
  {==}

def Rule.unrelated_decision_focus_preserves_application(panel, trigger, initial, query, occurrence, source, field, parameter_buffer, rest, application):
  {==}

def Rule.decision_focus_preserves_query_and_source(panel, trigger, initial, query, occurrence, source, field, parameter_buffer, rest, application):
  {==}

def Rule.workspace_retry_assesses_complete_candidate(revision, body, feedback, entry, application):
  {==}

def Rule.requested_parameter_preserves_applied_draft(panel, trigger, initial, query, occurrence, source, field, buffer, rest, value, application): {==}
def Rule.unavailable_parameter_does_not_apply(layers, value, application): {==}
def Rule.invalid_complete_parameter_preserves_application(editor, profile, value, application): {==}
def Rule.complete_parameter_uses_canonical_configuration(editor, profile, value, application): {==}
def Rule.full_access_has_no_filesystem_dependency(): {==}
def Rule.full_access_has_no_network_dependency(): {==}
def Rule.reviewer_dependency_requires_automatic_strategy(profile): {==}
def Rule.back_from_dependency_retains_inspection_parent(editor, trigger, initial, query, occurrence, source, field, buffer, rest, application): {==}
def Rule.mismatched_execution_view_does_not_dismiss(task, result): {==}
def Rule.explicit_dismiss_preserves_nonproject_state(editor, application): {==}
def Rule.project_dismiss_discards_complete_draft(id, world, session): {==}
def Rule.fresh_project_uses_reserved_occurrence(body, session): {==}
def Rule.cancelled_project_advances_shared_fresh_occurrence(revision, body, feedback, entry, current): {==}


def Rule.requested_view_change_uses_fresh_identity(panel, trigger, initial, query, occurrence, source, field, buffer, rest, application): {==}
def Rule.same_requested_view_preserves_identity(panel, trigger, initial, query, occurrence, source, field, buffer, rest, application): {==}

def Rule.source_navigation_uses_current_inspection(origin, trigger, application): {==}
def Rule.source_navigation_rejects_unowned_origin(origin, trigger, application): {==}
def Rule.source_navigation_pushes_distinct_activity(origin, trigger, application):
  open_allocation(application, U.PropertySource{origin}, trigger)
def Rule.source_navigation_has_own_identity(origin): {==}
def Rule.source_navigation_is_read_only(origin): {==}
def Rule.source_dismiss_preserves_underlying_draft(origin, application): {==}
def Rule.source_back_uses_actual_stack(origin, trigger, initial, query, occurrence, expanded, field, buffer, rest, application): {==}

def Rule.worktree_unknown_is_unavailable(primary): {==}
def Rule.worktree_loading_is_unavailable(ticket, root, primary): {==}
def Rule.worktree_observed_requires_matching_primary(root, available, primary): {==}
def Rule.worktree_without_primary_is_unavailable(root, available): {==}
def Rule.worktree_observation_requires_current_ticket_and_primary(current, ticket, root, primary): {==}
def Rule.worktree_stale_observation_preserves_application(current, ticket, root, available, application, stale):
  Equal.cong(Bool, E.Decision, (accepted => E.settle_workspace_git(accepted, root, available, application)),
    E.git_observation_current(current, ticket, root, E.current_primary(application)), False{}, stale)

def stale_git_ticket(+current: Nat, +ticket: Nat, +root: String, actual: Maybe<&2, String>, stale: {Nat.is_eq(current, ticket) == False{} : Bool}) ->
  {E.git_observation_current(current, ticket, root, actual) == False{} : Bool}:
  match actual:
    case None{}: {==}
    case Some{primary}:
      Equal.cong(Bool, Bool, (same => same && String.eq(root, primary)), Nat.is_eq(current, ticket), False{}, stale)

def changed_git_primary(same_ticket: Bool, +root: String, +primary: String, changed: {String.eq(root, primary) == False{} : Bool}) ->
  {(same_ticket && String.eq(root, primary)) == False{} : Bool}:
  match same_ticket:
    case False{}: {==}
    case True{}: changed

def Rule.worktree_stale_ticket_preserves_application(current, ticket, root, available, application, stale):
  Rule.worktree_stale_observation_preserves_application(current, ticket, root, available, application,
    stale_git_ticket(current, ticket, root, E.current_primary(application), stale))

def Rule.worktree_changed_primary_preserves_application(current, ticket, root, primary, available, application, observed, changed):
  Rule.worktree_stale_observation_preserves_application(current, ticket, root, available, application,
    Equal.trans(Bool, E.git_observation_current(current, ticket, root, E.current_primary(application)),
      E.git_observation_current(current, ticket, root, Some{primary}), False{},
      Equal.cong(Maybe<&2, String>, Bool, (actual => E.git_observation_current(current, ticket, root, actual)),
        E.current_primary(application), Some{primary}, observed),
      changed_git_primary(Nat.is_eq(current, ticket), root, primary, changed)))
def Rule.task_without_worktree_uses_normal_creation(profile, reasoning, message, settings): {==}
def Rule.task_with_worktree_uses_owned_creation(profile, reasoning, message, settings): {==}
def Rule.model_selection_preserves_worktree_choice(message, profile, reasoning, context, enabled, selected, effort, world): {==}
def Rule.saved_worktree_preference_continues_captured_submission(draft, command, result, application, verified):
  Equal.cong(Bool, E.Decision, (allowed => E.request_submitted(allowed, command, draft, application)),
    E.worktree_submission_allowed(U.contents(draft), application), True{}, verified)
def Rule.ordinary_task_submission_needs_no_git_observation(message, profile, reasoning, context, application): {==}
def Rule.unverified_worktree_preparation_preserves_application(draft, workspace, application, blocked):
  Equal.cong(Bool, E.Decision, (allowed => E.prepare_checked(allowed, application, workspace, draft)),
    E.worktree_submission_allowed(U.contents(draft), application), False{}, blocked)
def Rule.unverified_worktree_command_preserves_application(draft, command, application, blocked):
  Equal.cong(Bool, E.Decision, (allowed => E.execute_submitted(allowed, E.worktree_preference_available(E.worktree_available(application), U.contents(draft), E.program(application)), command, draft, application)),
    E.worktree_submission_allowed(U.contents(draft), application), False{}, blocked)
def Rule.unverified_saved_worktree_preference_stops_submission(draft, command, result, application, blocked):
  Equal.cong(Bool, E.Decision, (allowed => E.request_submitted(allowed, command, draft, application)),
    E.worktree_submission_allowed(U.contents(draft), application), False{}, blocked)
def Rule.unavailable_worktree_does_not_change_project_preference(body, world): {==}
def Rule.refused_worktree_preference_stops_submission(draft, command, result, world, session, failed):
  SubmissionProof.failed_native(draft, world, result, Nil{}, session, False{}, failed)
