import ../interactive_markdown/DOCUMENTS.bend as Documents
import ../interactive_markdown/TYPES.bend as Interactive
import ../interactive_markdown/MODEL.bend as InteractiveCore
import ../interactive_markdown/CONTRACT.bend as InteractiveRequirement
import ../interactive_markdown/PROOF.bend as InteractiveEvidence
import ../interactive_markdown/documents-proof.bend as DocumentRequirement
import ../interactive_markdown/documents-contract.bend as DocumentDomain
import ../presentation/surface-proof.bend as SurfaceEvidence
import Base

import ../submission/FIELDS.bend as Forms
import ../../bendlib/categories.bend as Categories
import ../../harness/INVARIANTS.bend as I
import ../../features/board/MODEL.bend as B
import ../../features/work/MODEL.bend as Work
import ../../features/board/STATE.bend as Board
import ../../harness/MODEL.bend as M
import ../../harness/features/work-state.bend as WorkState
import ../../harness/PROGRAM.bend as Program
import ../../bendlib/association-map.bend as Finite
import ../../bendlib/component.bend as C
import ../../harness/DOMAIN.bend as D
import ../../harness/COMMANDS.bend as Commands
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

def Rule.global_navigation_panel_identity(): {==}

def Rule.global_navigation_uses_existing_layer_opening(trigger, application): {==}

def Rule.global_navigation_consumption_retains_the_underlying_session(program, session, trigger, initial, query, occurrence, source, field, buffer, rest): {==}

def Rule.global_navigation_settings_origin_is_consumed(program, session, trigger, initial, query, occurrence, source, field, buffer, rest, observed):
  Equal.cong(+List<E.Layer>, E.Application, (layers => E.consume_global_navigation_layers(layers, program, session)), E.layers(session), E.Layer{U.GlobalNavigation{}, trigger, initial, query, occurrence, source, field, buffer} <> rest, observed)

def Rule.global_navigation_consumption_without_a_layer_is_unchanged(program, session): {==}

def Rule.global_navigation_dismissal_keeps_applied_drafts(trigger, initial, query, occurrence, source, field, buffer, rest, application): {==}

def Rule.navigation_clears_transient_layers(route, application):
  E.Application{program, E.Session{old, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code, next_layer, preference, manual, workspace_git, interactive}} = application
  {==}

def Rule.global_navigation_selection_uses_existing_visit(destination, program, session, trigger, initial, query, occurrence, source, field, buffer, rest):
  E.Session{old, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code, next_layer, preference, manual, workspace_git, interactive} = session
  {==}

def Rule.task_visibility_user_transition_preserves_the_complete_frame(expanded, program, session):
  E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code, next_layer, preference, manual, workspace_git, interactive} = session
  {==}

def Rule.task_visibility_selection_epoch_advances_once(expanded, program, session):
  E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code, next_layer, preference, manual, workspace_git, interactive} = session
  E.NavigationState{intent, collapsed, work, visits, generation} = navigation
  {==}

def previous_epoch_differs_from_successor(+generation:Nat) -> {Nat.is_eq(generation, (generation + 1n : Nat)) == False{} : Bool}:
  match generation:
    case 0n: {==}
    case 1n+rest: previous_epoch_differs_from_successor(rest)

def Rule.task_visibility_invalidates_the_previous_work_creation_epoch(expanded, program, session, layer_generation):
  E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code, next_layer, preference, manual, workspace_git, interactive} = session
  E.NavigationState{intent, collapsed, work, visits, generation} = navigation
  Equal.cong(Bool, Bool, (same => same && Nat.is_eq(layer_generation, next_layer)), Nat.is_eq(generation, (generation + 1n : Nat)), False{}, previous_epoch_differs_from_successor(generation))

def open_allocation(+application: E.Application, +panel: U.Panel, +trigger: String) ->
  {E.open_panel(panel, trigger, application) == Rule.opened_application(application, panel, trigger) : E.Decision}:
  E.Application{program, E.Session{route, drafts, readers, layers, attention, navigation, filter,
    now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git, interactive}} = application
  {==}

def open_residence(application: E.Application, panel: U.Panel, trigger: String) ->
  {Rule.residence(Rule.post(E.open_panel(panel, trigger, application))) == Rule.residence(application) : Rule.Residence}:
  E.Application{program, E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git, interactive}} = application
  {==}

def open_attention(application: E.Application, panel: U.Panel, trigger: String) ->
  {Rule.attention(Rule.post(E.open_panel(panel, trigger, application))) == E.panel_target(panel) : String}:
  E.Application{program, E.Session{route, drafts, readers, layers, attention_value, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git, interactive}} = application
  {==}

def open_effects(application: E.Application, panel: U.Panel, trigger: String) ->
  {Rule.interaction_effects(E.open_panel(panel, trigger, application)) == [E.Attend{E.panel_target(panel)}] : +List<E.Effect>}:
  E.Application{program, E.Session{route, drafts, readers, layers, attention_value, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git, interactive}} = application
  {==}

def close_residence(application: E.Application) ->
  {Rule.residence(Rule.post(E.close_panel(application))) == Rule.residence(application) : Rule.Residence}:
  E.Application{program, E.Session{route, drafts, readers, +layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git, interactive}} = application
  match layers:
    case Nil{}: {==}
    case Con{E.Layer{panel, trigger, initial, query, layer_occurrence, source_expanded, decision_field, parameter_buffer}, rest}: {==}

def sequence_attention(application: E.Application, +panel: U.Panel, +trigger: String) ->
  {Rule.attention(Rule.post(E.close_panel(Rule.post(E.open_panel(panel, trigger, application))))) == trigger : String}:
  E.Application{program, E.Session{route, drafts, readers, layers, attention_value, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git, interactive}} = application
  {==}

def native_without_submission_keeps_content(decision: M.Decision(), session: E.Session, durable: Bool) ->
  {Rule.session_content(Rule.post(E.native_result(decision, session, None{}, durable))) ==
    Rule.session_content(E.Application{Rule.runtime_program(decision), session}) : Rule.SessionContent}:
  C.Decision{program, result, effects} = decision
  E.Session{route, drafts, readers, layers, attention_value, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git, interactive} = session
  {==}

def runtime_keeps_content(+input: M.Input, application: E.Application) ->
  {Rule.session_content(Rule.post(ExperienceProgram.step(E.RuntimeInput{input}, application))) == Rule.session_content(application) : Rule.SessionContent}:
  E.Application{program, session} = application
  native_without_submission_keeps_content(Program.transition(input, program), session, M.durable(input))

def native_without_submission_keeps_frame(decision: M.Decision(), session: E.Session, durable: Bool) ->
  {Rule.native_frame(Rule.post(E.native_result(decision, session, None{}, durable))) ==
    Rule.native_frame(E.Application{Rule.runtime_program(decision), session}) : Rule.NativeFrame}:
  C.Decision{program, result, effects} = decision
  E.Session{route, drafts, readers, layers, attention_value, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git, interactive} = session
  {==}

def native_without_submission_retains_previews(decision: M.Decision(), session: E.Session, durable: Bool) ->
  {Rule.previews(Rule.post(E.native_result(decision, session, None{}, durable))) ==
    Live.retained(Rule.previews(E.Application{Rule.runtime_program(decision), session}), Rule.runtime_program(decision)) : +List<Live.Output>}:
  C.Decision{program, result, effects} = decision
  E.Session{route, drafts, readers, layers, attention_value, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git, interactive} = session
  {==}

def code_blocks_keep_content(+blocks: +List<Content.Block>, +session: E.Session) ->
  {Rule.session_content_of(E.with_code_blocks(blocks, session)) == Rule.session_content_of(session) : Rule.SessionContent}:
  E.Session{+route, +drafts, +readers, +layers, +attention_value, +navigation, +filter, +now, +next, +pending, +previews, +code_blocks, +next_layer, +model_preference, +draft_model_manual, +workspace_git, +interactive} = session
  {==}

def forgetting_sources_keeps_content(+effects: +List<Documents.Effect>, +session: E.Session) ->
  {Rule.session_content_of(E.forget_code_sources(effects, session)) == Rule.session_content_of(session) : Rule.SessionContent}:
  match effects:
    case Nil{}: {==}
    case Con{Documents.ForgetMarkdown{+key}, +rest}:
      Equal.trans(Rule.SessionContent,
        Rule.session_content_of(E.forget_code_sources(rest, E.with_code_blocks(E.without_code_source(E.code_blocks(session), key), session))),
        Rule.session_content_of(E.with_code_blocks(E.without_code_source(E.code_blocks(session), key), session)),
        Rule.session_content_of(session),
        forgetting_sources_keeps_content(rest, E.with_code_blocks(E.without_code_source(E.code_blocks(session), key), session)),
        code_blocks_keep_content(E.without_code_source(E.code_blocks(session), key), session))
    case Con{Documents.ObserveMarkdown{document}, +rest}: forgetting_sources_keeps_content(rest, session)
    case Con{Documents.CoreEffect{effect}, +rest}: forgetting_sources_keeps_content(rest, session)

def interactive_state_keeps_content(+state: Documents.State, +session: E.Session) ->
  {Rule.session_content_of(E.with_interactive(state, session)) == Rule.session_content_of(session) : Rule.SessionContent}:
  E.Session{+route, +drafts, +readers, +layers, +attention_value, +navigation, +filter, +now, +next, +pending, +previews, +code_blocks, +next_layer, +model_preference, +draft_model_manual, +workspace_git, +interactive} = session
  {==}

def interactive_result_keeps_content(+result: Documents.Decision, +application: E.Application) ->
  {Rule.session_content(Rule.post(E.interactive_result(result, application))) == Rule.session_content(application) : Rule.SessionContent}:
  Documents.Decision{+state, +effects} = result
  E.Application{program, +session} = application
  Equal.trans(Rule.SessionContent,
    Rule.session_content_of(E.with_interactive(state, E.forget_code_sources(effects, session))),
    Rule.session_content_of(E.forget_code_sources(effects, session)), Rule.session_content_of(session),
    interactive_state_keeps_content(state, E.forget_code_sources(effects, session)),
    forgetting_sources_keeps_content(effects, session))

def partial_preview_keeps_content(+output: Live.Output, +application: E.Application) ->
  {Rule.session_content(Rule.post(E.partial_preview(output, application))) == Rule.session_content(application) : Rule.SessionContent}:
  Live.Output{+task, +operation, +parts} = output
  E.Application{+program, +session} = application
  E.Session{+route, +drafts, +readers, +layers, +attention_value, +navigation, +filter, +now, +next, +pending, +previews, +code_blocks, +next_layer, +model_preference, +draft_model_manual, +workspace_git, +interactive} = session
  interactive_result_keeps_content(
    Documents.preview_outputs([output], task, program, E.interactive_data(E.with_previews(Live.observe(Live.PartialOutput{output}, E.previews(session), program), session))),
    E.Application{program, E.with_previews(Live.observe(Live.PartialOutput{output}, E.previews(session), program), session)})

def preview_observation_keeps_content(observation: Live.Observation, +application: E.Application) ->
  {Rule.session_content(Rule.post(ExperienceProgram.step(E.PreviewObserved{observation}, application))) == Rule.session_content(application) : Rule.SessionContent}:
  match observation:
    case Live.ConnectionEnded{}: {==}
    case Live.PartialOutput{+output}: partial_preview_keeps_content(output, application)
    case Live.DiscardOutput{task, operation}:
      E.Application{program, E.Session{+route, +drafts, +readers, +layers, +attention_value, +navigation, +filter, +now, +next, +pending, +previews, +code_blocks, +next_layer, +model_preference, +draft_model_manual, +workspace_git, +interactive}} = application
      {==}

def navigate_keeps_drafts(route: U.Route, application: E.Application) ->
  {Rule.drafts(Rule.post(E.navigate(route, application))) == Rule.drafts(application) : +List<U.Draft>}:
  E.Application{program, E.Session{old, +drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git, interactive}} = application
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
  E.Application{program, E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git, interactive}} = application
  Equal.trans(E.Decision,
    E.read_current(task, generation, intent, application),
    reading_spec(Rule.reading_owner(application, task, generation), task, intent, application), E.unchanged(application),
    reading_checked_refinement(Rule.reading_owner(application, task, generation), task, generation, intent, application, {==}),
    Equal.cong(Bool, E.Decision, (owned => reading_spec(owned, task, intent, application)),
      Rule.reading_owner(application, task, generation), False{}, not_owner))

def model_choice(program: M.World(), route: U.Route, drafts: +List<U.Draft>, readers: +List<Finite.Entry(E.Reader)>,
  +trigger: String, initial: String, query: String, layer_occurrence: Nat, +source_expanded: Bool, +decision_field: Maybe<&2, Forms.Field>, +parameter_buffer: Maybe<&2, String>, rest: +List<E.Layer>, old_attention: String,
  navigation: E.NavigationState, filter: B.Filter, now: U32, next: Nat, pending: +List<E.Pending>,
  previews: +List<Live.Output>, code_blocks: +List<Content.Block>, next_layer: Nat, model_preference: Maybe<&2, E.ModelPreference>, draft_model_manual: Bool, workspace_git: E.WorkspaceGit, interactive: Documents.State, revision: Nat, text: U.Text,
  old_profile: String, old_reasoning: String, context: Context.Configuration, feedback: U.Feedback, +directory_entry: String,
  +new_profile: String, +new_reasoning: String,
  valid: {E.permitted_preference(D.find_profile(Board.profiles(program), new_profile), new_reasoning) == True{} : Bool},
  found: {E.find_draft(drafts, U.NewTaskEditor{None{}}) ==
    Some{U.Draft{revision, U.NewTask{text, old_profile, old_reasoning, context, False{}, None{}}, feedback, directory_entry}} : Maybe<&2, U.Draft>}) ->
  {ExperienceProgram.step(E.UserInput{U.EditDraft{U.NewTaskEditor{None{}}, U.ChooseModel{new_profile, new_reasoning}}},
      E.Application{program, E.Session{route, drafts, readers, E.Layer{U.ModelPicker{U.NewTaskEditor{None{}}}, trigger, initial, query, layer_occurrence, source_expanded, None{}, None{}} <> rest, old_attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git, interactive}}) ==
    E.remember_manual(U.ChooseModel{new_profile, new_reasoning}, E.Decision{E.Application{program, E.Session{route, U.Draft{(revision + 1n : Nat), U.NewTask{text, new_profile, new_reasoning, context, False{}, None{}}, U.Editing{}, directory_entry} <>
        E.without_draft(drafts, U.NewTaskEditor{None{}}), readers, rest, trigger, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git, interactive}},
      D.success(J.Null{}), Nil{}, [E.Attend{trigger}], False{}}) : E.Decision}:
  session: E.Session = E.Session{route, drafts, readers, E.Layer{U.ModelPicker{U.NewTaskEditor{None{}}}, trigger, initial, query, layer_occurrence, source_expanded, None{}, None{}} <> rest, old_attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git, interactive}
  Equal.trans(E.Decision,
    E.manual_creation_edit(E.permitted_preference(D.find_profile(Board.profiles(program), new_profile), new_reasoning), U.ChooseModel{new_profile, new_reasoning}, E.Application{program, session}),
    E.manual_creation_edit(True{}, U.ChooseModel{new_profile, new_reasoning}, E.Application{program, session}),
    E.remember_manual(U.ChooseModel{new_profile, new_reasoning}, E.Decision{E.Application{program, E.Session{route, U.Draft{(revision + 1n : Nat), U.NewTask{text, new_profile, new_reasoning, context, False{}, None{}}, U.Editing{}, directory_entry} <>
        E.without_draft(drafts, U.NewTaskEditor{None{}}), readers, rest, trigger, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git, interactive}},
      D.success(J.Null{}), Nil{}, [E.Attend{trigger}], False{}}),
    Equal.cong(Bool, E.Decision,
      valid => E.manual_creation_edit(valid, U.ChooseModel{new_profile, new_reasoning}, E.Application{program, session}),
      E.permitted_preference(D.find_profile(Board.profiles(program), new_profile), new_reasoning), True{}, valid),
    Equal.cong(Maybe<&2, U.Draft>, E.Decision,
      (found_draft => E.remember_manual(U.ChooseModel{new_profile, new_reasoning}, E.close_selected_choice(U.ChooseModel{new_profile, new_reasoning}, U.NewTaskEditor{None{}},
        E.edit_found(found_draft, U.ChooseModel{new_profile, new_reasoning}, program, session)))),
      E.find_draft(drafts, U.NewTaskEditor{None{}}),
      Some{U.Draft{revision, U.NewTask{text, old_profile, old_reasoning, context, False{}, None{}}, feedback, directory_entry}}, found))

def encapsulated_model_choice(+session: E.Session, +program: M.World(), +trigger: String, initial: String, query: String, +layer_occurrence: Nat, +source_expanded: Bool, +decision_field: Maybe<&2, Forms.Field>, +parameter_buffer: Maybe<&2, String>, +rest: +List<E.Layer>, revision: Nat, +text: U.Text, old_profile: String, old_reasoning: String, context: Context.Configuration, feedback: U.Feedback, +directory_entry: String, +new_profile: String, +new_reasoning: String, valid: {E.permitted_preference(D.find_profile(Board.profiles(program), new_profile), new_reasoning) == True{} : Bool}, observed_layers: {E.layers(session) == E.Layer{U.ModelPicker{U.NewTaskEditor{None{}}}, trigger, initial, query, layer_occurrence, source_expanded, None{}, None{}} <> rest : +List<E.Layer>}, found: {E.find_draft(E.drafts(session), U.NewTaskEditor{None{}}) ==
        Some{U.Draft{revision, U.NewTask{text, old_profile, old_reasoning, context, False{}, None{}}, feedback, directory_entry}} : Maybe<&2, U.Draft>}) ->
  {ExperienceProgram.step(E.UserInput{U.EditDraft{U.NewTaskEditor{None{}}, U.ChooseModel{new_profile, new_reasoning}}},
        E.from_program(program, session)) ==
       E.remember_manual(U.ChooseModel{new_profile, new_reasoning}, E.Decision{E.from_program(program, E.with_attention(trigger, E.with_layers(rest, E.with_drafts(U.Draft{(revision + 1n : Nat), U.NewTask{text, new_profile, new_reasoning, context, False{}, None{}}, U.Editing{}, directory_entry} <>
           E.without_draft(E.drafts(session), U.NewTaskEditor{None{}}), session)))),
         D.success(J.Null{}), Nil{}, [E.Attend{trigger}], False{}}) : E.Decision}:
  E.Session{+route, +drafts, +readers, +stored_layers, +old_attention, +navigation, +filter, +now, +next, +pending, +previews, +code_blocks, +next_layer, model_preference, draft_model_manual, workspace_git, interactive} = session
  backwards_layers = Equal.sym(E.Session, session, E.with_layers(E.Layer{U.ModelPicker{U.NewTaskEditor{None{}}}, trigger, initial, query, layer_occurrence, source_expanded, None{}, None{}} <> rest, session),
    Equal.cong(+List<E.Layer>, E.Session, value => E.with_layers(value, session), E.layers(session), E.Layer{U.ModelPicker{U.NewTaskEditor{None{}}}, trigger, initial, query, layer_occurrence, source_expanded, None{}, None{}} <> rest, observed_layers))
  %backwards_layers : {ExperienceProgram.step(E.UserInput{U.EditDraft{U.NewTaskEditor{None{}}, U.ChooseModel{new_profile, new_reasoning}}},
        E.from_program(program, _)) ==
       E.remember_manual(U.ChooseModel{new_profile, new_reasoning}, E.Decision{E.from_program(program, E.with_attention(trigger, E.with_layers(rest, E.with_drafts(U.Draft{(revision + 1n : Nat), U.NewTask{text, new_profile, new_reasoning, context, False{}, None{}}, U.Editing{}, directory_entry} <>
           E.without_draft(E.drafts(_), U.NewTaskEditor{None{}}), _)))),
         D.success(J.Null{}), Nil{}, [E.Attend{trigger}], False{}}) : E.Decision}
  model_choice(program, route, drafts, readers, trigger, initial, query, layer_occurrence, source_expanded, decision_field, parameter_buffer, rest, old_attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git, interactive, revision, text, old_profile, old_reasoning, context, feedback, directory_entry, new_profile, new_reasoning, valid, found)

def model_choice_checked(valid: Bool, +profile: String, +reasoning: String, +application: E.Application) ->
  {E.manual_creation_edit(valid, U.ChooseModel{profile, reasoning}, application) == Rule.model_choice_spec(valid, profile, reasoning, application) : E.Decision}:
  match valid:
    case False{}: {==}
    case True{}: {==}

def model_choice_complete(+profile: String, +reasoning: String, +application: E.Application) ->
  {ExperienceProgram.step(E.UserInput{U.EditDraft{U.NewTaskEditor{None{}}, U.ChooseModel{profile, reasoning}}}, application) ==
    Rule.model_choice_spec(E.permitted_preference(D.find_profile(Board.profiles(E.program(application)), profile), reasoning), profile, reasoning, application) : E.Decision}:
  E.Application{program, session} = application
  model_choice_checked(E.permitted_preference(D.find_profile(Board.profiles(program), profile), reasoning), profile, reasoning, E.Application{program, session})

def invalid_model_choice(+profile: String, +reasoning: String, +application: E.Application,
  invalid: {E.permitted_preference(D.find_profile(Board.profiles(E.program(application)), profile), reasoning) == False{} : Bool}) ->
  {ExperienceProgram.step(E.UserInput{U.EditDraft{U.NewTaskEditor{None{}}, U.ChooseModel{profile, reasoning}}}, application) ==
    E.Decision{application, D.failure("interaction_refused", "Choose an available model and permitted reasoning effort."), Nil{}, Nil{}, False{}} : E.Decision}:
  Equal.trans(E.Decision,
    ExperienceProgram.step(E.UserInput{U.EditDraft{U.NewTaskEditor{None{}}, U.ChooseModel{profile, reasoning}}}, application),
    Rule.model_choice_spec(E.permitted_preference(D.find_profile(Board.profiles(E.program(application)), profile), reasoning), profile, reasoning, application),
    E.Decision{application, D.failure("interaction_refused", "Choose an available model and permitted reasoning effort."), Nil{}, Nil{}, False{}},
    model_choice_complete(profile, reasoning, application),
    Equal.cong(Bool, E.Decision, valid => Rule.model_choice_spec(valid, profile, reasoning, application),
      E.permitted_preference(D.find_profile(Board.profiles(E.program(application)), profile), reasoning), False{}, invalid))

def encapsulated_modal_close_empty(+session: E.Session, +program: M.World(), observed_layers: {E.layers(session) == Nil{} : +List<E.Layer>}) ->
  {E.close_panel(E.from_program(program, session)) ==
       E.unchanged(E.from_program(program, session)) : E.Decision}:
  E.Session{+route, +drafts, +readers, +stored_layers, +attention_value, +navigation, +filter, +now, +next, +pending, +previews, +code_blocks, +next_layer, model_preference, draft_model_manual, workspace_git, interactive} = session
  backwards_layers = Equal.sym(E.Session, session, E.with_layers(Nil{}, session),
    Equal.cong(+List<E.Layer>, E.Session, value => E.with_layers(value, session), E.layers(session), Nil{}, observed_layers))
  %backwards_layers : {E.close_panel(E.from_program(program, _)) ==
       E.unchanged(E.from_program(program, _)) : E.Decision}
  {==}

def encapsulated_modal_close_nonempty(+session: E.Session, +program: M.World(), +panel: U.Panel, +trigger: String, initial: String, query: String, +layer_occurrence: Nat, +source_expanded: Bool, +decision_field: Maybe<&2, Forms.Field>, +parameter_buffer: Maybe<&2, String>, +rest: +List<E.Layer>, observed_layers: {E.layers(session) == E.Layer{panel, trigger, initial, query, layer_occurrence, source_expanded, decision_field, parameter_buffer} <> rest : +List<E.Layer>}) ->
  {E.close_panel(E.from_program(program, session)) ==
       E.Decision{E.from_program(program, E.with_attention(trigger, E.with_layers(rest, session))),
        D.success(J.Null{}), Nil{}, [E.Attend{trigger}], False{}} : E.Decision}:
  E.Session{+route, +drafts, +readers, +stored_layers, +old_attention, +navigation, +filter, +now, +next, +pending, +previews, +code_blocks, +next_layer, model_preference, draft_model_manual, workspace_git, interactive} = session
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

def selected_model_session_refinement(selection: Sigma<&2, &2, String, (_ => String)>, revision: Nat, message: U.Text, context: Context.Configuration, feedback: U.Feedback, directory_entry: String, create_worktree: Bool, session: E.Session, work: Maybe<&2, Nat>) ->
  {E.scoped_model_selection(selection, revision, message, context, feedback, directory_entry, create_worktree, session, work) == Rule.selected_model_session(selection, revision, message, context, feedback, directory_entry, create_worktree, session, work) : E.Session}:
  (selected, effort) = selection
  {==}

def model_resolution_if_refinement(+valid: Bool, +draft: U.Draft, +profiles: +List<D.Profile>, +session: E.Session) ->
  {E.resolve_model_valid(valid, draft, profiles, session) == Rule.model_resolution_if(valid, draft, profiles, session) : E.Session}:
  match valid draft:
    case False{} U.Draft{revision, U.NewTask{message, profile, reasoning, context, +create_worktree, +work}, feedback, directory_entry}:
      Equal.trans(E.Session,
        E.scoped_model_selection(E.preferred_selection(E.preference(session), profiles), revision, message, context, feedback, directory_entry, create_worktree, session, work),
        E.scoped_model_selection(Rule.preference_selection(E.preference(session), profiles), revision, message, context, feedback, directory_entry, create_worktree, session, work),
        Rule.selected_model_session(Rule.preference_selection(E.preference(session), profiles), revision, message, context, feedback, directory_entry, create_worktree, session, work),
        Equal.cong(Sigma<&2, &2, String, (_ => String)>, E.Session,
          selection => E.scoped_model_selection(selection, revision, message, context, feedback, directory_entry, create_worktree, session, work),
          E.preferred_selection(E.preference(session), profiles), Rule.preference_selection(E.preference(session), profiles),
          preference_selection_refinement(E.preference(session), profiles)),
        selected_model_session_refinement(Rule.preference_selection(E.preference(session), profiles), revision, message, context, feedback, directory_entry, create_worktree, session, work))
    case True{} _: {==}
    case False{} U.Draft{revision, U.WorkName{work, name}, feedback, directory_entry}: {==}
    case False{} U.Draft{revision, U.Message{task, message, delivery}, feedback, directory_entry}: {==}
    case False{} U.Draft{revision, U.Project{project, name, workspace, create_worktree}, feedback, directory_entry}: {==}
    case False{} U.Draft{revision, U.Card{card, revision2, value, assist, profile, keep_open}, feedback, directory_entry}: {==}
    case False{} U.Draft{revision, U.Agent{agent, revision2, name, profile, reasoning, instructions, context, concurrency}, feedback, directory_entry}: {==}
    case False{} U.Draft{revision, U.Fork{task, count, messages, context}, feedback, directory_entry}: {==}
    case False{} U.Draft{revision, U.Compact{task, summary}, feedback, directory_entry}: {==}
    case False{} U.Draft{revision, U.TaskGraph{graph, declaration, parsed, work}, feedback, directory_entry}: {==}
    case False{} U.Draft{revision, U.TitlePrompts{settings_revision, prompts}, feedback, directory_entry}: {==}

def model_resolution_found_refinement(+found: Maybe<&2, U.Draft>, +profiles: +List<D.Profile>, +session: E.Session) ->
  {E.resolve_model_found(found, profiles, session) == Rule.model_resolution_found(found, profiles, session) : E.Session}:
  match found:
    case Some{U.Draft{revision, U.NewTask{message, +profile, +reasoning, context, create_worktree, +work}, feedback, directory_entry}}:
      model_resolution_if_refinement(E.creation_model_chosen(work, E.manual_model(session)) && E.permitted_preference(D.find_profile(profiles, profile), reasoning), U.Draft{revision, U.NewTask{message, profile, reasoning, context, create_worktree, work}, feedback, directory_entry}, profiles, session)
    case None{}: {==}
    case Some{U.Draft{revision, U.WorkName{work, name}, feedback, directory_entry}}: {==}
    case Some{U.Draft{revision, U.Message{task, message, delivery}, feedback, directory_entry}}: {==}
    case Some{U.Draft{revision, U.Project{project, name, workspace, create_worktree}, feedback, directory_entry}}: {==}
    case Some{U.Draft{revision, U.Card{card, revision2, value, assist, profile, keep_open}, feedback, directory_entry}}: {==}
    case Some{U.Draft{revision, U.Agent{agent, revision2, name, profile, reasoning, instructions, context, concurrency}, feedback, directory_entry}}: {==}
    case Some{U.Draft{revision, U.Fork{task, count, messages, context}, feedback, directory_entry}}: {==}
    case Some{U.Draft{revision, U.Compact{task, summary}, feedback, directory_entry}}: {==}
    case Some{U.Draft{revision, U.TaskGraph{graph, declaration, parsed, work}, feedback, directory_entry}}: {==}
    case Some{U.Draft{revision, U.TitlePrompts{settings_revision, prompts}, feedback, directory_entry}}: {==}

def model_resolution_complete(+session: E.Session, +world: M.World()) ->
  {E.resolve_model_draft(session, world) == Rule.model_resolution(session, world) : E.Session}:
  model_resolution_found_refinement(E.find_draft(E.drafts(session), E.creation_editor(session)), Board.profiles(world), session)

def begin_focus_refinement(+target: String, world: M.World(), session: E.Session) ->
  {E.navigate_with_attention(U.Start{}, target, E.Application{world, session}) == Rule.begin_focus(target, world, session) : E.Decision}:
  E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code, next_layer, preference, manual, workspace_git, interactive} = session
  {==}

def begin_changed_refinement(+result: Result<&2, &2, String, U.Body>, +revision: Nat, +directory_entry: String, +world: M.World(), +session: E.Session) ->
  {E.begin_changed(result, revision, directory_entry, E.Application{world, session}) == Rule.begin_changed_spec(result, revision, directory_entry, world, session) : E.Decision}:
  match result:
    case Fail{reason}: {==}
    case Done{+body}: begin_focus_refinement("composer/" ++ U.editor_key(U.owner(body)), world, E.with_draft(session, U.Draft{(revision + 1n : Nat), body, U.Editing{}, directory_entry}))

def begin_existing_refinement(+found: Maybe<&2, U.Draft>, +origin: Context.Origin, +world: M.World(), +session: E.Session) ->
  {E.begin_existing(found, origin, E.Application{world, session}) == Rule.begin_existing_spec(found, origin, world, session) : E.Decision}:
  match found:
    case None{}: begin_focus_refinement("composer/" ++ U.editor_key(E.creation_editor(session)), world, session)
    case Some{U.Draft{revision, body, feedback, directory_entry}}:
      begin_changed_refinement(U.apply_edit(U.ConfigureContext{Context.ChooseOrigin{origin}}, body, world), revision, directory_entry, world, session)

def begin_resolved_refinement(+origin: Context.Origin, +world: M.World(), +session: E.Session) ->
  {E.begin_resolved(origin, world, session) == Rule.begin_resolved_spec(origin, world, session) : E.Decision}:
  begin_existing_refinement(E.find_draft(E.drafts(session), E.creation_editor(session)), origin, world, session)

def begin_task_complete(+project: Maybe<&2, Nat>, +world: M.World(), +session: E.Session) ->
  {E.begin_task(project, E.Application{world, session}) == Rule.begin_task_spec(project, world, session) : E.Decision}:
  E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code, next_layer, preference, manual, workspace_git, interactive} = session
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
  E.Session{route, drafts, readers, layers, focus, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git, interactive} = session
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
        case U.GlobalNavigation{}: {==}
        case U.WorkOverview{}: {==}
        case U.Confirm{current, title, destination}: {==}
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
        case U.PropertySource{origin}: {==}
        case U.DeliveryPicker{task}: {==}


def confirmation_checked_refinement(owned: Bool, +command: M.Command, +trigger: String, +occurrence: Nat, +result: J.Json, +destination: U.Route, +application: E.Application, observed: {E.receipt_owned(E.ConfirmationReceipt{command, trigger, occurrence, result, destination, application}) == owned : Bool}) ->
  {E.confirmation_admitted(Categories.admit_checked(E.ConfirmationReceipt, E.receipt_owned, E.ConfirmationReceipt{command, trigger, occurrence, result, destination, application}, owned, observed), result, application) == Rule.confirmation_result_spec(owned, result, destination, application) : E.Decision}:
  match owned:
    case False{}: {==}
    case True{}:
      accepted_confirmation_refinement(J.boolean(J.get(result, "ok")), result, destination, application)

def feedback_effect_mapping(+effects: +List<Interactive.Effect>) ->
  {E.interactive_effects(Documents.core_effects(effects)) == Rule.feedback_effects(effects) : +List<E.Effect>}:
  match effects:
    case Nil{}: {==}
    case Con{+effect, +rest}:
      Equal.cong(+List<E.Effect>, +List<E.Effect>, (tail => E.InteractiveEffect{effect} <> tail),
        E.interactive_effects(Documents.core_effects(rest)), Rule.feedback_effects(rest), feedback_effect_mapping(rest))

def feedback_keeps_code_sources(+effects: +List<Interactive.Effect>, +session: E.Session) ->
  {E.forget_code_sources(Documents.core_effects(effects), session) == session : E.Session}:
  match effects:
    case Nil{}: {==}
    case Con{effect, rest}: feedback_keeps_code_sources(rest, session)

def feedback_adapter_complete(+result: Interactive.Decision, +application: E.Application) ->
  {E.interactive_result(Documents.apply_core_result(result, E.interactive_data(E.session(application))), application) ==
    Rule.feedback_decision(result, application) : E.Decision}:
  match result application:
    case Interactive.Decision{+core, +effects} E.Application{+program, E.Session{+route, +drafts, +readers, +layers, +attention, +navigation, +filter, +now, +next_ticket, +pending, +previews, +code_blocks, +next_layer, +preference, +manual, +workspace_git, Documents.State{+namespace, +sequence, +fresh, +allowed, +ready, +documents, old_core, +next_epoch, +retention}}}:
      +previous: E.Session = E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, preference, manual, workspace_git, Documents.State{namespace, sequence, fresh, allowed, ready, documents, old_core, next_epoch, retention}}
      Equal.trans(E.Decision,
        E.interactive_result(Documents.apply_core_result(Interactive.Decision{core, effects}, E.interactive_data(previous)), E.Application{program, previous}),
        E.local(program, E.with_interactive(Documents.State{namespace, sequence, fresh, allowed, ready, documents, core, next_epoch, retention}, previous), E.interactive_effects(Documents.core_effects(effects))),
        Rule.feedback_decision(Interactive.Decision{core, effects}, E.Application{program, previous}),
        Equal.cong(E.Session, E.Decision,
          (retained => E.local(program, E.with_interactive(Documents.State{namespace, sequence, fresh, allowed, ready, documents, core, next_epoch, retention}, retained), E.interactive_effects(Documents.core_effects(effects)))),
          E.forget_code_sources(Documents.core_effects(effects), previous), previous, feedback_keeps_code_sources(effects, previous)),
        Equal.cong(+List<E.Effect>, E.Decision,
          (mapped => E.local(program, E.with_interactive(Documents.State{namespace, sequence, fresh, allowed, ready, documents, core, next_epoch, retention}, previous), mapped)),
          E.interactive_effects(Documents.core_effects(effects)), Rule.feedback_effects(effects), feedback_effect_mapping(effects)))

def feedback_no_change(+application: E.Application) ->
  {E.interactive_result(Documents.Decision{E.interactive_data(E.session(application)), Nil{}}, application) == E.Decision{application, D.success(J.Null{}), Nil{}, Nil{}, False{}} : E.Decision}:
  match application:
    case E.Application{program, E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, preference, manual, workspace_git, interactive}}: {==}

def feedback_checked_complete(+owned: Bool, +owner: Interactive.Owner, +path: String, +ticket: Nat, +result: J.Json, +application: E.Application) ->
  {E.interactive_result(Documents.input_checked(owned, Interactive.EffectCompleted{owner, path, ticket, J.boolean(J.get(result, "ok")), J.text(J.get(J.get(result, "error"), "message"))}, E.interactive_data(E.session(application))), application) == Rule.feedback_permitted(owned, owner, path, ticket, result, application) : E.Decision}:
  match owned:
    case False{}: feedback_no_change(application)
    case True{}: feedback_adapter_complete(InteractiveCore.step(Interactive.EffectCompleted{owner, path, ticket,
      J.boolean(J.get(result, "ok")), J.text(J.get(J.get(result, "error"), "message"))}, Documents.core(E.interactive_data(E.session(application)))), application)

def interactive_completion_complete(+owner: Interactive.Owner, +path: String, +ticket: Nat, +result: J.Json, +application: E.Application) ->
  {E.interactive_completed(owner, path, ticket, result, application) == Rule.interactive_completion_spec(owner, path, ticket, result, application) : E.Decision}:
  +input: Interactive.Input = Interactive.EffectCompleted{owner, path, ticket, J.boolean(J.get(result, "ok")), J.text(J.get(J.get(result, "error"), "message"))}
  +documents = E.interactive_data(E.session(application))
  Equal.trans(E.Decision, E.interactive_completed(owner, path, ticket, result, application),
    E.interactive_result(Documents.input_checked(DocumentDomain.owns(Documents.namespace(documents), owner, False{}, Documents.documents(documents)), input, documents), application), Rule.interactive_completion_spec(owner, path, ticket, result, application),
    Equal.cong(Bool, E.Decision, (allowed => E.interactive_result(Documents.input_checked(allowed, input, documents), application)), Documents.input_allowed(input, documents), DocumentDomain.owns(Documents.namespace(documents), owner, False{}, Documents.documents(documents)), DocumentRequirement.permission_meaning(input, documents)),
    feedback_checked_complete(DocumentDomain.owns(Documents.namespace(documents), owner, False{}, Documents.documents(documents)), owner, path, ticket, result, application))

def feedback_interpret_empty(+core: Interactive.State, +application: E.Application) ->
  {E.interpret_interactive_decision(E.interactive_result(Documents.apply_core_result(Interactive.Decision{core, Nil{}}, E.interactive_data(E.session(application))), application)) ==
    E.interactive_result(Documents.apply_core_result(Interactive.Decision{core, Nil{}}, E.interactive_data(E.session(application))), application) : E.Decision}:
  match application:
    case E.Application{program, session}: {==}

def feedback_interpret_complete(+result: Interactive.Decision, +application: E.Application,
  +terminal: {InteractiveRequirement.decision_effects(result) == Nil{} : +List<Interactive.Effect>}) ->
  {E.interpret_interactive_decision(E.interactive_result(Documents.apply_core_result(result, E.interactive_data(E.session(application))), application)) ==
    E.interactive_result(Documents.apply_core_result(result, E.interactive_data(E.session(application))), application) : E.Decision}:
  match result:
    case Interactive.Decision{+core, +effects}:
      Equal.trans(E.Decision,
        E.interpret_interactive_decision(E.interactive_result(Documents.apply_core_result(Interactive.Decision{core, effects}, E.interactive_data(E.session(application))), application)),
        E.interpret_interactive_decision(E.interactive_result(Documents.apply_core_result(Interactive.Decision{core, Nil{}}, E.interactive_data(E.session(application))), application)),
        E.interactive_result(Documents.apply_core_result(Interactive.Decision{core, effects}, E.interactive_data(E.session(application))), application),
        Equal.cong(+List<Interactive.Effect>, E.Decision,
          (items => E.interpret_interactive_decision(E.interactive_result(Documents.apply_core_result(Interactive.Decision{core, items}, E.interactive_data(E.session(application))), application))), effects, Nil{}, terminal),
        Equal.trans(E.Decision,
          E.interpret_interactive_decision(E.interactive_result(Documents.apply_core_result(Interactive.Decision{core, Nil{}}, E.interactive_data(E.session(application))), application)),
          E.interactive_result(Documents.apply_core_result(Interactive.Decision{core, Nil{}}, E.interactive_data(E.session(application))), application),
          E.interactive_result(Documents.apply_core_result(Interactive.Decision{core, effects}, E.interactive_data(E.session(application))), application),
          feedback_interpret_empty(core, application),
          Equal.cong(+List<Interactive.Effect>, E.Decision,
            (items => E.interactive_result(Documents.apply_core_result(Interactive.Decision{core, items}, E.interactive_data(E.session(application))), application)), Nil{}, effects,
            Equal.sym(+List<Interactive.Effect>, effects, Nil{}, terminal))))

def input_completion_checked_complete(+owned: Bool, +owner: Interactive.Owner, +path: String, +ticket: Nat, +result: J.Json, +application: E.Application) ->
  {E.interpret_interactive_decision(E.interactive_result(Documents.input_checked(owned,
    Interactive.EffectCompleted{owner, path, ticket, J.boolean(J.get(result, "ok")), J.text(J.get(J.get(result, "error"), "message"))}, E.interactive_data(E.session(application))), application)) ==
    Rule.feedback_permitted(owned, owner, path, ticket, result, application) : E.Decision}:
  match owned:
    case False{}:
      Equal.trans(E.Decision,
        E.interpret_interactive_decision(E.interactive_result(Documents.Decision{E.interactive_data(E.session(application)), Nil{}}, application)),
        E.interpret_interactive_decision(E.Decision{application, D.success(J.Null{}), Nil{}, Nil{}, False{}}),
        Rule.feedback_permitted(False{}, owner, path, ticket, result, application),
        Equal.cong(E.Decision, E.Decision, (value => E.interpret_interactive_decision(value)),
          E.interactive_result(Documents.Decision{E.interactive_data(E.session(application)), Nil{}}, application),
          E.Decision{application, D.success(J.Null{}), Nil{}, Nil{}, False{}}, feedback_no_change(application)), {==})
    case True{}:
      +core = InteractiveCore.step(Interactive.EffectCompleted{owner, path, ticket,
        J.boolean(J.get(result, "ok")), J.text(J.get(J.get(result, "error"), "message"))}, Documents.core(E.interactive_data(E.session(application))))
      Equal.trans(E.Decision,
        E.interpret_interactive_decision(E.interactive_result(Documents.apply_core_result(core, E.interactive_data(E.session(application))), application)),
        E.interactive_result(Documents.apply_core_result(core, E.interactive_data(E.session(application))), application),
        Rule.feedback_permitted(True{}, owner, path, ticket, result, application),
        feedback_interpret_complete(core, application, InteractiveRequirement.completion_emits_no_effects(owner, path, ticket,
          J.boolean(J.get(result, "ok")), J.text(J.get(J.get(result, "error"), "message")), Documents.core(E.interactive_data(E.session(application))))),
        feedback_adapter_complete(core, application))

def interactive_input_completion_complete(+owner: Interactive.Owner, +path: String, +ticket: Nat, +result: J.Json, +application: E.Application) ->
  {E.interactive_input(Interactive.EffectCompleted{owner, path, ticket, J.boolean(J.get(result, "ok")), J.text(J.get(J.get(result, "error"), "message"))}, application) ==
    Rule.interactive_completion_spec(owner, path, ticket, result, application) : E.Decision}:
  +input: Interactive.Input = Interactive.EffectCompleted{owner, path, ticket, J.boolean(J.get(result, "ok")), J.text(J.get(J.get(result, "error"), "message"))}
  +documents = E.interactive_data(E.session(application))
  Equal.trans(E.Decision, E.interactive_input(input, application),
    E.interpret_interactive_decision(E.interactive_result(Documents.input_checked(DocumentDomain.owns(Documents.namespace(documents), owner, False{}, Documents.documents(documents)), input, documents), application)),
    Rule.interactive_completion_spec(owner, path, ticket, result, application),
    Equal.cong(Bool, E.Decision, (allowed => E.interpret_interactive_decision(E.interactive_result(Documents.input_checked(allowed, input, documents), application))),
      Documents.input_allowed(input, documents), DocumentDomain.owns(Documents.namespace(documents), owner, False{}, Documents.documents(documents)), DocumentRequirement.permission_meaning(input, documents)),
    input_completion_checked_complete(DocumentDomain.owns(Documents.namespace(documents), owner, False{}, Documents.documents(documents)), owner, path, ticket, result, application))

def Rule.interactive_feedback(owner, path, ticket, result, application):
  interactive_input_completion_complete(owner, path, ticket, result, application)

def feedback_business_empty(+result: Interactive.Decision, +application: E.Application,
  terminal: {InteractiveRequirement.decision_effects(result) == Nil{} : +List<Interactive.Effect>}) ->
  {Rule.business_effects(Rule.feedback_decision(result, application)) == (Nil{}, Nil{}) : +List<M.Effect()> & +List<E.Effect>}:
  match result application:
    case Interactive.Decision{core, +effects} E.Application{program, E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next_ticket, pending, previews, code_blocks, next_layer, preference, manual, workspace_git, Documents.State{namespace, sequence, fresh, allowed, ready, documents, old_core, next_epoch, retention}}}:
      Equal.cong(+List<Interactive.Effect>, +List<M.Effect()> & +List<E.Effect>,
        (items => (Nil{}, Rule.feedback_effects(items))), effects, Nil{}, terminal)

def feedback_permitted_business_empty(+owned: Bool, +owner: Interactive.Owner, +path: String, +ticket: Nat, +result: J.Json, +application: E.Application) ->
  {Rule.business_effects(Rule.feedback_permitted(owned, owner, path, ticket, result, application)) ==
    (Nil{}, Nil{}) : +List<M.Effect()> & +List<E.Effect>}:
  match owned:
    case False{}: {==}
    case True{}:
      feedback_business_empty(InteractiveCore.step(Interactive.EffectCompleted{owner, path, ticket,
        J.boolean(J.get(result, "ok")), J.text(J.get(J.get(result, "error"), "message"))}, Documents.core(E.interactive_data(E.session(application)))), application,
        InteractiveRequirement.completion_emits_no_effects(owner, path, ticket, J.boolean(J.get(result, "ok")), J.text(J.get(J.get(result, "error"), "message")), Documents.core(E.interactive_data(E.session(application)))))

def Rule.interactive_feedback_is_terminal(owner, path, ticket, result, application):
  +documents = E.interactive_data(E.session(application))
  +input: Interactive.Input = Interactive.EffectCompleted{owner, path, ticket, J.boolean(J.get(result, "ok")), J.text(J.get(J.get(result, "error"), "message"))}
  Equal.trans(+List<M.Effect()> & +List<E.Effect>, Rule.business_effects(E.interactive_input(input, application)),
    Rule.business_effects(Rule.interactive_completion_spec(owner, path, ticket, result, application)), (Nil{}, Nil{}),
    Equal.cong(E.Decision, +List<M.Effect()> & +List<E.Effect>, (decision => Rule.business_effects(decision)),
      E.interactive_input(input, application), Rule.interactive_completion_spec(owner, path, ticket, result, application),
      interactive_input_completion_complete(owner, path, ticket, result, application)),
    feedback_permitted_business_empty(DocumentDomain.owns(Documents.namespace(documents), owner, False{}, Documents.documents(documents)), owner, path, ticket, result, application))

def captured_request_complete(+operation: Commands.Operation, +command: M.Command, +owner: Interactive.Owner, +path: String, +ticket: Nat, +application: E.Application) ->
  {E.interactive_send_resolved(operation, command, owner, path, ticket, application) == Rule.captured_request(operation, command, owner, path, ticket, application) : E.Decision}:
  match operation:
    case Commands.Refuse{code, message}: interactive_completion_complete(owner, path, ticket, D.failure(code, message), application)
    case Commands.ConfigureExecution{task, configuration}: {==}
    case Commands.Start{profile, reasoning, message, selection}: {==}
    case Commands.StartIdle{profile, reasoning, selection, work, create_worktree}: {==}
    case Commands.RecordSpeech{task, session, item, speaker, completion, text}: {==}
    case Commands.DelegateSpeech{task, session, identity, mode, message}: {==}
    case Commands.ReplaySpeech{result}: {==}
    case Commands.Deliver{task, message}: {==}
    case Commands.Steer{task, message}: {==}
    case Commands.Cancel{task, operation}: {==}
    case Commands.Control{task, request, next}: {==}
    case Commands.Branch{parent, count, messages, selection}: {==}
    case Commands.OpenSideConversation{parent, message}: {==}
    case Commands.ReturnSideConversation{side, parent, after, through, transcript}: {==}
    case Commands.Summarize{task}: {==}
    case Commands.Checkpoint{task, summary}: {==}
    case Commands.Observe{query}: {==}
    case Commands.StoreProject{project_id, project, next_id}: {==}
    case Commands.RemoveProject{project_id}: {==}
    case Commands.Review{resolution}: {==}
    case Commands.FeatureOperation{operation}: {==}

def captured_ready_complete(+ready: Bool, +task: Nat, +owner: Interactive.Owner, +path: String, +ticket: Nat, +message: String, +application: E.Application) ->
  {E.interactive_send_checked(ready, owner, path, ticket, U.Draft{0n, U.Message{task, U.initial_text(message), U.Send{}}, U.Editing{}, ""}, application) == Rule.captured_send_ready(ready, task, owner, path, ticket, message, application) : E.Decision}:
  match ready:
    case False{}: interactive_completion_complete(owner, path, ticket, D.failure("interaction_refused", "This task cannot accept this message now"), application)
    case True{}:
      +command: M.Command = U.message_command(U.Send{}, task, message)
      captured_request_complete(Commands.resolve(command, E.program(application)), command, owner, path, ticket, application)

def shared_document_owner_complete(+found: Maybe<&2, Documents.Document>, +owner: Interactive.Owner) ->
  {Documents.shared_owner_found(found, owner) == Rule.shared_document_owner(found, owner) : Bool}:
  match found:
    case None{}: {==}
    case Some{Documents.Document{+source, text, +epoch, revision, ending, observed, +fences, +active}}:
      Equal.cong(Bool, Bool, accepted => active && accepted,
        Documents.owner_matches(fences, source, epoch, owner), DocumentDomain.fence_owned(source, epoch, owner, fences),
        DocumentRequirement.fence_owner_meaning(fences, source, epoch, owner))

def shared_owner_complete(+owner: Interactive.Owner, +work: Nat, +state: Documents.State) ->
  {Documents.shared_owner(owner, E.shared_ui_owner(work), state) == Rule.shared_owns(owner, work, state) : Bool}:
  +source: Content.Source = Content.SharedDocument{Documents.namespace(state), "work/" ++ Nat.show(work)}
  +key: String = Content.source_key(source)
  +documents: +List<Documents.Document> = Documents.documents(state)
  Equal.trans(Bool, Documents.shared_owner(owner, E.shared_ui_owner(work), state),
    Rule.shared_document_owner(Documents.find(documents, key), owner), Rule.shared_owns(owner, work, state),
    shared_document_owner_complete(Documents.find(documents, key), owner),
    Equal.cong(Maybe<&2, Documents.Document>, Bool, found => Rule.shared_document_owner(found, owner),
      Documents.find(documents, key), DocumentDomain.document_lookup(key, documents),
      DocumentRequirement.lookup_meaning(documents, key)))

def task_in_work_complete(+current: Maybe<&2, Nat>, +work: Nat) ->
  {E.same_work(Some{work}, current) == Rule.task_in_work(current, work) : Bool}:
  match current:
    case None{}: {==}
    case Some{value}: {==}

def selected_work_task_complete(+selected: Maybe<&2, Nat>, +work: Nat, +world: M.World()) ->
  {E.shared_action_task(selected, work, world) == Rule.selected_work_task(selected, work, world) : Maybe<&2, Nat>}:
  match selected:
    case None{}: {==}
    case Some{+task}:
      Equal.cong(Bool, Maybe<&2, Nat>, owned => Bool.pick(Maybe<&2, Nat>, owned, Some{task}, None{}),
        E.same_work(Some{work}, WorkState.task_owner(task, world)), Rule.task_in_work(WorkState.task_owner(task, world), work),
        task_in_work_complete(WorkState.task_owner(task, world), work))

def shared_action_choice_complete(+owned: Bool, +owner: Interactive.Owner, +work: Nat, +selected: Maybe<&2, Nat>, +application: E.Application) ->
  {E.shared_action_owner(owned, owner, work, selected, application) == Rule.shared_action_choice(owned, work, selected, Rule.document_action_task(owner, application), E.program(application)) : Maybe<&2, Nat>}:
  match owned:
    case True{}: selected_work_task_complete(selected, work, E.program(application))
    case False{}: DocumentRequirement.current_task_owner_meaning(owner, E.interactive_data(E.session(application)))

def shared_action_route_complete(+work: Nat, +selected: Maybe<&2, Nat>, +owner: Interactive.Owner, +application: E.Application) ->
  {E.interactive_action_route(U.SharedUI{work, selected}, owner, application) == Rule.action_task_at(U.SharedUI{work, selected}, owner, application) : Maybe<&2, Nat>}:
  +documents: Documents.State = E.interactive_data(E.session(application))
  +owned: Bool = Documents.shared_owner(owner, E.shared_ui_owner(work), documents)
  Equal.trans(Maybe<&2, Nat>, E.interactive_action_route(U.SharedUI{work, selected}, owner, application),
    Rule.shared_action_choice(owned, work, selected, Rule.document_action_task(owner, application), E.program(application)),
    Rule.action_task_at(U.SharedUI{work, selected}, owner, application),
    shared_action_choice_complete(owned, owner, work, selected, application),
    Equal.cong(Bool, Maybe<&2, Nat>, accepted => Rule.shared_action_choice(accepted, work, selected, Rule.document_action_task(owner, application), E.program(application)),
      owned, Rule.shared_owns(owner, work, documents), shared_owner_complete(owner, work, documents)))

def action_route_complete(+route: U.Route, +owner: Interactive.Owner, +application: E.Application) ->
  {E.interactive_action_route(route, owner, application) == Rule.action_task_at(route, owner, application) : Maybe<&2, Nat>}:
  match route:
    case U.SharedUI{work, selected}: shared_action_route_complete(work, selected, owner, application)
    case U.Start{}: DocumentRequirement.current_task_owner_meaning(owner, E.interactive_data(E.session(application)))
    case U.Conversation{task}: DocumentRequirement.current_task_owner_meaning(owner, E.interactive_data(E.session(application)))
    case U.ProjectHome{project}: DocumentRequirement.current_task_owner_meaning(owner, E.interactive_data(E.session(application)))
    case U.ProjectCollection{}: DocumentRequirement.current_task_owner_meaning(owner, E.interactive_data(E.session(application)))
    case U.TaskBoard{}: DocumentRequirement.current_task_owner_meaning(owner, E.interactive_data(E.session(application)))
    case U.AgentCollection{}: DocumentRequirement.current_task_owner_meaning(owner, E.interactive_data(E.session(application)))
    case U.TaskGraphs{}: DocumentRequirement.current_task_owner_meaning(owner, E.interactive_data(E.session(application)))
    case U.HistorySearch{search}: DocumentRequirement.current_task_owner_meaning(owner, E.interactive_data(E.session(application)))

def Rule.interactive_action_owner(owner, application):
  action_route_complete(E.route(E.session(application)), owner, application)

def fill_composer_empty_complete(+found: Maybe<&2, U.Draft>) ->
  {E.interactive_draft_empty(found) == Rule.fill_composer_empty(found) : Bool}:
  match found:
    case None{}: {==}
    case Some{U.Draft{revision, U.WorkName{work, name}, feedback, entry}}: {==}
    case Some{U.Draft{revision, U.NewTask{message, profile, reasoning, context, create_worktree, work}, feedback, entry}}: {==}
    case Some{U.Draft{revision, U.Message{task, U.Text{text, images}, delivery}, feedback, entry}}: {==}
    case Some{U.Draft{revision, U.Project{project, name, workspace, create_worktree}, feedback, entry}}: {==}
    case Some{U.Draft{revision, U.Card{card, version, value, assist, profile, keep_open}, feedback, entry}}: {==}
    case Some{U.Draft{revision, U.Agent{agent, version, name, profile, reasoning, instructions, context, concurrency}, feedback, entry}}: {==}
    case Some{U.Draft{revision, U.Fork{task, count, messages, context}, feedback, entry}}: {==}
    case Some{U.Draft{revision, U.Compact{task, summary}, feedback, entry}}: {==}
    case Some{U.Draft{revision, U.TaskGraph{graph, declaration, parsed, work}, feedback, entry}}: {==}
    case Some{U.Draft{revision, U.TitlePrompts{version, prompts}, feedback, entry}}: {==}

def captured_fill_empty_complete(+empty: Bool, +task: Nat, +message: String, +application: E.Application) ->
  {E.interactive_fill_empty(empty, task, message, application) == Rule.captured_fill_empty(empty, task, message, application) : E.Decision}:
  match empty:
    case False{}: {==}
    case True{}: {==}

def captured_fill_owner_complete(+task: Maybe<&2, Nat>, +message: String, +application: E.Application) ->
  {E.interactive_fill_owned(task, message, application) == Rule.captured_fill_owner(task, message, application) : E.Decision}:
  match task:
    case None{}: {==}
    case Some{+id}:
      +found: Maybe<&2, U.Draft> = E.find_draft(E.drafts(E.session(application)), U.MessageEditor{id})
      Equal.trans(E.Decision, E.interactive_fill_owned(Some{id}, message, application),
        Rule.captured_fill_empty(E.interactive_draft_empty(found), id, message, application),
        Rule.captured_fill_owner(Some{id}, message, application),
        captured_fill_empty_complete(E.interactive_draft_empty(found), id, message, application),
        Equal.cong(Bool, E.Decision, empty => Rule.captured_fill_empty(empty, id, message, application),
          E.interactive_draft_empty(found), Rule.fill_composer_empty(found), fill_composer_empty_complete(found)))

def Rule.interactive_fill(owner, path, message, application):
  Equal.trans(E.Decision, E.interpret_interactive_effect(Interactive.FillDraft{owner, path, message}, application),
    E.interactive_fill_owned(Rule.action_task(owner, application), message, application), Rule.captured_fill(owner, message, application),
    Equal.cong(Maybe<&2, Nat>, E.Decision, task => E.interactive_fill_owned(task, message, application),
      E.interactive_action_task(owner, application), Rule.action_task(owner, application), Rule.interactive_action_owner(owner, application)),
    captured_fill_owner_complete(Rule.action_task(owner, application), message, application))

def captured_owner_complete(+task: Maybe<&2, Nat>, +owner: Interactive.Owner, +path: String, +ticket: Nat, +message: String, +application: E.Application) ->
  {E.interactive_send_owned(task, owner, path, ticket, message, application) == Rule.captured_send_owner(task, owner, path, ticket, message, application) : E.Decision}:
  match task:
    case None{}: interactive_completion_complete(owner, path, ticket, D.failure("interaction_refused", "This view no longer owns a task"), application)
    case Some{+id}:
      captured_ready_complete(E.submission_ready(E.pending(E.session(application)), E.program(application), U.Draft{0n, U.Message{id, U.initial_text(message), U.Send{}}, U.Editing{}, ""}), id, owner, path, ticket, message, application)

def Rule.interactive_send(owner, path, ticket, message, application):
  Equal.trans(E.Decision, E.interpret_interactive_effect(Interactive.SendMessage{owner, path, ticket, message}, application),
    E.interactive_send_owned(Rule.action_task(owner, application), owner, path, ticket, message, application), Rule.captured_send(owner, path, ticket, message, application),
    Equal.cong(Maybe<&2, Nat>, E.Decision, task => E.interactive_send_owned(task, owner, path, ticket, message, application),
      E.interactive_action_task(owner, application), Rule.action_task(owner, application), Rule.interactive_action_owner(owner, application)),
    captured_owner_complete(Rule.action_task(owner, application), owner, path, ticket, message, application))

def work_creation_refinement(current: Bool, +result: J.Json, +application: E.Application) ->
  {E.complete_work_creation(current, result, application) == Rule.work_creation_spec(current, result, application) : E.Decision}:
  match current:
    case False{}: {==}
    case True{}: {==}

def side_response_refinement(accepted: Bool, +result: J.Json, +application: E.Application) ->
  {E.complete_side_response(accepted, result, application) == Rule.side_response_spec(accepted, result, application) : E.Decision}:
  match accepted:
    case False{}: {==}
    case True{}: {==}

def side_creation_refinement(current: Bool, +draft: Maybe<&2, U.Draft>, +result: J.Json, +application: E.Application) ->
  {E.complete_side_creation_checked(current, draft, result, application) == Rule.side_creation_spec(current, draft, result, application) : E.Decision}:
  match current:
    case False{}: {==}
    case True{}: side_response_refinement(J.boolean(J.get(result, "ok")), result, E.from_program(E.program(application), E.settle_side_draft(draft, result, E.session(application))))

def completed_checked_refinement(valid: Bool, +completion: E.Completion, +program: M.World(), +result: J.Json, +session: E.Session, previous: M.World(), observed: {I.world(program) == valid : Bool}) ->
  {E.complete_command_admitted(Categories.admit_checked(M.World(), (world => I.world(world)), program, valid, observed), result, completion, E.Application{previous, session}) == Rule.completion_checked_spec(valid, completion, program, result, session, previous) : E.Decision}:
  match valid:
    case False{}: {==}
    case True{}:
      match completion:
        case E.InteractiveCompletion{owner, path, ticket}: interactive_completion_complete(owner, path, ticket, result, E.from_program(program, E.retain_previews(session, program)))
        case E.WorkCreationCompletion{generation, layer_generation}: work_creation_refinement(E.work_creation_current(generation, layer_generation, session), result, E.from_program(program, E.retain_previews(session, program)))
        case E.SideCreationCompletion{parent, +draft, generation, layer_generation}:
          side_creation_refinement(E.side_creation_current(parent, draft, generation, layer_generation, E.retain_previews(session, program)), draft, result, E.from_program(program, E.retain_previews(session, program)))
        case E.ExecutionViewCompletion{task, profile, reasoning, remember, occurrence}: {==}
        case E.ExecutionCompletion{task, profile, reasoning, remember}: {==}
        case E.DirectCompletion{}: {==}
        case E.WorktreePreferenceCompletion{draft, command}: {==}
        case E.DraftCompletion{draft}: SubmissionProof.native_session_refinement(Some{draft}, program, result, Nil{}, E.retain_previews(session, program), False{})
        case E.ConfirmationCompletion{command, trigger, destination, occurrence}:
          E.Session{route, drafts, readers, +layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git, interactive} = session
          +updated: E.Application = E.Application{program, E.retain_previews(E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, model_preference, draft_model_manual, workspace_git, interactive}, program)}
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

def Rule.task_visibility_stale_work_creation_keeps_the_new_interaction(expanded, previous, session, layer_generation, program, result, valid):
  +updated = Rule.task_visibility_session(expanded, previous, session)
  +completion: E.Completion = E.WorkCreationCompletion{E.selection_generation(session), layer_generation}
  Equal.trans(E.Decision,
    ExperienceProgram.step(E.CommandCompleted{program, result, completion}, E.from_program(previous, updated)),
    Rule.completion_spec(completion, program, result, updated, previous),
    E.Decision{E.from_program(program, E.retain_previews(updated, program)), result, Nil{}, Nil{}, False{}},
    completed_refinement(completion, program, result, updated, previous),
    Equal.trans(E.Decision,
      Rule.completion_spec(completion, program, result, updated, previous),
      Rule.valid_completion_spec(completion, program, result, updated),
      E.Decision{E.from_program(program, E.retain_previews(updated, program)), result, Nil{}, Nil{}, False{}},
      Equal.cong(Bool, E.Decision, (accepted => Rule.completion_checked_spec(accepted, completion, program, result, updated, previous)), I.world(program), True{}, valid),
      Equal.cong(Bool, E.Decision,
        (current => Rule.work_creation_spec(current, result, E.from_program(program, E.retain_previews(updated, program)))),
        E.work_creation_current(E.selection_generation(session), layer_generation, updated), False{},
        Rule.task_visibility_invalidates_the_previous_work_creation_epoch(expanded, previous, session, layer_generation))))

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
def Rule.title_prompts_dismiss_discards_complete_draft(world, session): {==}
def Rule.fresh_title_prompts_use_reserved_occurrence(revision, prompts, session): {==}
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

def navigation_generation_progress(+navigation: E.NavigationState) ->
  {E.navigation_generation(E.navigation_after_visit(navigation)) == (E.navigation_generation(navigation) + 1n : Nat) : Nat}:
  E.NavigationState{intent, collapsed, work, visits, generation} = navigation
  {==}

def creation_capture_generation(+application: E.Application) -> Rule.work_creation_captures_generation(application):
  E.Application{program, E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code, next_layer, preference, manual, workspace_git, interactive}} = application
  E.NavigationState{intent, collapsed, work, visits, generation} = navigation
  {==}

def created_work_focus_accepted(+work: Nat, +program: M.World(), +session: E.Session, +result: J.Json, +runtime: +List<M.Effect()>, +interaction: +List<E.Effect>, +durable: Bool,
  accepted: {J.boolean(J.get(result, "ok")) == True{} : Bool}) ->
  {E.expose_created_work(work, E.Decision{E.Application{program, session}, result, runtime, interaction, durable}) == E.Decision{E.Application{program, E.with_attention("message-text", session)}, result, runtime, [E.Attend{"work/" ++ Nat.show(work)}, E.Attend{"message-text"}], durable} : E.Decision}:
  Equal.cong(Bool, E.Decision,
    (value => E.expose_created_work_checked(value, work, E.Decision{E.Application{program, session}, result, runtime, interaction, durable})),
    J.boolean(J.get(result, "ok")), True{}, accepted)

def created_work_focus_refused(work: Nat, +application: E.Application, +result: J.Json, +runtime: +List<M.Effect()>, +interaction: +List<E.Effect>, +durable: Bool,
  refused: {J.boolean(J.get(result, "ok")) == False{} : Bool}) ->
  {E.expose_created_work(work, E.Decision{application, result, runtime, interaction, durable}) == E.Decision{application, result, runtime, interaction, durable} : E.Decision}:
  Equal.cong(Bool, E.Decision,
    (value => E.expose_created_work_checked(value, work, E.Decision{application, result, runtime, interaction, durable})),
    J.boolean(J.get(result, "ok")), False{}, refused)

def Rule.work_evidence():
  Rule.WorkRequirements{
    work => message => profile => reasoning => context => enabled => {==},
    work => message => profile => reasoning => context => enabled => now => {==},
    message => profile => reasoning => context => enabled => now => {==},
    work => name => now => {==},
    work => route => intent => collapsed => previous => visits => generation => {==},
    work => route => layers => result => application => {==},
    work => manual => {==},
    work => session => {==},
    work => change => result => {==},
    navigation_generation_progress,
    work => application => {==},
    trigger => initial => query => occurrence => source => field => buffer => rest => program => session => {==},
    work => program => session => result => runtime => interaction => durable => {==},
    work => decision => {==},
    program => session => result => runtime => interaction => durable => {==},
    trigger => application => {==},
    creation_capture_generation,
    work => application => {==},
    created_work_focus_accepted,
    created_work_focus_refused,
    result => application => {==},
    result => application => {==},
    application => {==},
    work => application => {==},
    decision => {==},
    decision => {==}}

def Rule.worktree_unknown_is_unavailable(primary): {==}
def Rule.worktree_observation_dispatch(ticket, available, application): {==}
def Rule.current_worktree_observation_settles(current, ticket, primary, available, application, observed):
  E.Application{+world, +session} = application
  Equal.cong(Bool, E.Decision, (accepted => E.settle_workspace_git(accepted, primary, available, E.from_program(world, session))),
    E.git_observation_current(current, ticket, primary, E.current_primary(E.from_program(world, session))), True{}, observed)
def Rule.prepared_task_retains_worktree_choice(message, profile, reasoning, context, enabled, work, observation, now): {==}
def Rule.prepared_project_creation_retains_worktree_choice(name, previous, workspace, guidance, enabled, now): {==}
def Rule.prepared_project_update_retains_worktree_choice(id, name, previous, workspace, guidance, enabled, now): {==}
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
def Rule.model_selection_preserves_worktree_choice(message, profile, reasoning, context, enabled, work, selected, effort, world): {==}
def Rule.saved_worktree_preference_continues_captured_submission(draft, command, result, application, verified):
  Equal.cong(Bool, E.Decision, (allowed => E.request_submitted(allowed, command, draft, application)),
    E.worktree_submission_allowed(U.contents(draft), application), True{}, verified)
def Rule.ordinary_task_submission_needs_no_git_observation(message, profile, reasoning, context, work, application): {==}
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

def Rule.composer_side_command(task, message, question, delivery, now, recognized):
  Equal.cong(Maybe<&2, String>, M.Command, (found => U.composer_message_command(found, delivery, task, message)), U.side_conversation_question(message), Some{question}, recognized)

def Rule.composer_plain_message(task, message, delivery, now, ordinary):
  Equal.cong(Maybe<&2, String>, M.Command, (found => U.composer_message_command(found, delivery, task, message)), U.side_conversation_question(message), None{}, ordinary)

def Rule.side_creation_captures_composer_and_attention(parent, message, draft, application): {==}
def Rule.side_creation_requires_current_owner_and_attention(parent, draft, generation, layer_generation, session): {==}
def Rule.stale_side_creation_settles_only_its_captured_draft(draft, result, application): {==}
def Rule.side_window_dismissal_does_not_return_content(task, trigger, initial, query, occurrence, source, field, buffer, rest, application): {==}
def Rule.side_return_is_explicit(task): {==}
def Rule.visible_tasks_include_side_windows_and_the_original_route(route, layers, session):
  E.Session{old, drafts, readers, previous, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, preference, manual, git, interactive} = session
  {==}
def shared_work_document_complete(+found: Maybe<&2, Work.Work>, +work: Nat, +previous: E.Decision) ->
  {E.shared_ui_found(found, work, previous) == Rule.required_work_document(found, work, previous) : E.Decision}:
  match found:
    case None{}: {==}
    case Some{value}: {==}

def shared_documents_route_complete(+route: U.Route, +previous: E.Decision) ->
  {E.shared_ui_route(route, previous) == Rule.required_shared_documents(route, previous) : E.Decision}:
  match route:
    case U.SharedUI{work, task}:
      shared_work_document_complete(Work.find(WorkState.registry(E.program(E.decision_application(previous))), work), work, previous)
    case U.Start{}: {==}
    case U.Conversation{task}: {==}
    case U.ProjectHome{project}: {==}
    case U.ProjectCollection{}: {==}
    case U.TaskBoard{}: {==}
    case U.AgentCollection{}: {==}
    case U.TaskGraphs{}: {==}
    case U.HistorySearch{search}: {==}

def Rule.interactive_documents_follow_visible_tasks(application):
  +tasks: E.Decision = E.interactive_result(Documents.reconcile_visible(E.visible_tasks(E.session(application)), E.previews(E.session(application)), E.program(application), E.interactive_data(E.session(application))), application)
  shared_documents_route_complete(E.route(E.session(E.decision_application(tasks))), tasks)
def Rule.captured_interactive_send_remains_literal(task, message, now): {==}
