import Base
import ../../features/board/MODEL.bend as B
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
import ./session-laws.bend as Rule

def open_allocation(+application: E.Application, +panel: U.Panel, +trigger: String) ->
  {E.open_panel(panel, trigger, application) == Rule.opened_application(application, panel, trigger) : E.Decision}:
  E.Application{program, E.Session{route, drafts, readers, layers, attention, navigation, filter,
    now, next, pending, previews, code_blocks, next_layer}} = application
  {==}

def open_residence(application: E.Application, panel: U.Panel, trigger: String) ->
  {Rule.residence(Rule.post(E.open_panel(panel, trigger, application))) == Rule.residence(application) : Rule.Residence}:
  E.Application{program, E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}} = application
  {==}

def open_attention(application: E.Application, panel: U.Panel, trigger: String) ->
  {Rule.attention(Rule.post(E.open_panel(panel, trigger, application))) == E.panel_target(panel) : String}:
  E.Application{program, E.Session{route, drafts, readers, layers, attention_value, navigation, filter, now, next, pending, previews, code_blocks, next_layer}} = application
  {==}

def open_effects(application: E.Application, panel: U.Panel, trigger: String) ->
  {Rule.interaction_effects(E.open_panel(panel, trigger, application)) == [E.Attend{E.panel_target(panel)}] : +List<E.Effect>}:
  E.Application{program, E.Session{route, drafts, readers, layers, attention_value, navigation, filter, now, next, pending, previews, code_blocks, next_layer}} = application
  {==}

def close_residence(application: E.Application) ->
  {Rule.residence(Rule.post(E.close_panel(application))) == Rule.residence(application) : Rule.Residence}:
  E.Application{program, E.Session{route, drafts, readers, +layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}} = application
  match layers:
    case Nil{}: {==}
    case Con{E.Layer{panel, trigger, initial, query, layer_occurrence}, rest}: {==}

def sequence_attention(application: E.Application, +panel: U.Panel, +trigger: String) ->
  {Rule.attention(Rule.post(E.close_panel(Rule.post(E.open_panel(panel, trigger, application))))) == trigger : String}:
  E.Application{program, E.Session{route, drafts, readers, layers, attention_value, navigation, filter, now, next, pending, previews, code_blocks, next_layer}} = application
  {==}

def native_without_submission_keeps_content(decision: M.Decision(), session: E.Session, durable: Bool) ->
  {Rule.session_content(Rule.post(E.native_result(decision, session, None{}, durable))) ==
    Rule.session_content(E.Application{Rule.runtime_program(decision), session}) : Rule.SessionContent}:
  C.Decision{program, result, effects} = decision
  E.Session{route, drafts, readers, layers, attention_value, navigation, filter, now, next, pending, previews, code_blocks, next_layer} = session
  {==}

def runtime_keeps_content(+input: M.Input, application: E.Application) ->
  {Rule.session_content(Rule.post(ExperienceProgram.step(E.RuntimeInput{input}, application))) == Rule.session_content(application) : Rule.SessionContent}:
  E.Application{program, session} = application
  native_without_submission_keeps_content(Program.transition(input, program), session, M.durable(input))

def native_without_submission_keeps_frame(decision: M.Decision(), session: E.Session, durable: Bool) ->
  {Rule.native_frame(Rule.post(E.native_result(decision, session, None{}, durable))) ==
    Rule.native_frame(E.Application{Rule.runtime_program(decision), session}) : Rule.NativeFrame}:
  C.Decision{program, result, effects} = decision
  E.Session{route, drafts, readers, layers, attention_value, navigation, filter, now, next, pending, previews, code_blocks, next_layer} = session
  {==}

def native_without_submission_retains_previews(decision: M.Decision(), session: E.Session, durable: Bool) ->
  {Rule.previews(Rule.post(E.native_result(decision, session, None{}, durable))) ==
    Live.retained(Rule.previews(E.Application{Rule.runtime_program(decision), session}), Rule.runtime_program(decision)) : +List<Live.Output>}:
  C.Decision{program, result, effects} = decision
  E.Session{route, drafts, readers, layers, attention_value, navigation, filter, now, next, pending, previews, code_blocks, next_layer} = session
  {==}

def preview_observation_keeps_content(observation: Live.Observation, application: E.Application) ->
  {Rule.session_content(Rule.post(ExperienceProgram.step(E.PreviewObserved{observation}, application))) == Rule.session_content(application) : Rule.SessionContent}:
  E.Application{program, E.Session{route, drafts, readers, layers, attention_value, navigation, filter, now, next, pending, previews, code_blocks, next_layer}} = application
  {==}

def navigate_keeps_drafts(route: U.Route, application: E.Application) ->
  {Rule.drafts(Rule.post(E.navigate(route, application))) == Rule.drafts(application) : +List<U.Draft>}:
  E.Application{program, E.Session{old, +drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}} = application
  {==}

def visit_preserves_location(reader: E.Reader) ->
  {Rule.reading_location(E.new_visit(reader)) == Rule.reading_location(reader) : Rule.ReadingLocation}:
  E.Reader{generation, position, disclosures} = reader
  {==}

def obsolete_reading(+task: Nat, +generation: Nat, +intent: U.ReadingIntent, +application: E.Application,
  not_owner: {Rule.reading_owner(application, task, generation) == False{} : Bool}) ->
  {ExperienceProgram.step(E.UserInput{U.ReadTimeline{task, generation, intent}}, application) == E.unchanged(application) : E.Decision}:
  E.Application{program, E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}} = application
  Equal.cong(Bool, E.Decision, (owned => E.read_owned(owned, task, intent, application)),
    Rule.reading_owner(application, task, generation), False{}, not_owner)

def model_choice(program: M.World(), route: U.Route, drafts: +List<U.Draft>, readers: +List<Finite.Entry(E.Reader)>,
  +trigger: String, initial: String, query: String, layer_occurrence: Nat, rest: +List<E.Layer>, old_attention: String,
  navigation: E.NavigationState, filter: B.Filter, now: U32, next: Nat, pending: +List<E.Pending>,
  previews: +List<Live.Output>, code_blocks: +List<Content.Block>, next_layer: Nat, revision: Nat, text: U.Text,
  old_profile: String, old_reasoning: String, context: Context.Configuration, feedback: U.Feedback, +directory_entry: String,
  +new_profile: String, +new_reasoning: String,
  found: {E.find_draft(drafts, U.NewTaskEditor{}) ==
    Some{U.Draft{revision, U.NewTask{text, old_profile, old_reasoning, context}, feedback, directory_entry}} : Maybe<&2, U.Draft>}) ->
  {ExperienceProgram.step(E.UserInput{U.EditDraft{U.NewTaskEditor{}, U.ChooseModel{new_profile, new_reasoning}}},
      E.Application{program, E.Session{route, drafts, readers,
        E.Layer{U.ModelPicker{U.NewTaskEditor{}}, trigger, initial, query, layer_occurrence} <> rest,
        old_attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}}) ==
    E.Decision{E.Application{program, E.Session{route,
      U.Draft{(revision + 1n : Nat), U.NewTask{text, new_profile, new_reasoning, context}, U.Editing{}, directory_entry} <>
        E.without_draft(drafts, U.NewTaskEditor{}),
      readers, rest, trigger, navigation, filter, now, next, pending, previews, code_blocks, next_layer}},
      D.success(J.Null{}), Nil{}, [E.Attend{trigger}], False{}} : E.Decision}:
  session: E.Session = E.Session{route, drafts, readers,
    E.Layer{U.ModelPicker{U.NewTaskEditor{}}, trigger, initial, query, layer_occurrence} <> rest,
    old_attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}
  Equal.cong(Maybe<&2, U.Draft>, E.Decision,
    (found_draft => E.close_selected_choice(U.ChooseModel{new_profile, new_reasoning}, U.NewTaskEditor{},
      E.edit_found(found_draft, U.ChooseModel{new_profile, new_reasoning}, program, session))),
    E.find_draft(drafts, U.NewTaskEditor{}),
    Some{U.Draft{revision, U.NewTask{text, old_profile, old_reasoning, context}, feedback, directory_entry}}, found)

def encapsulated_model_choice(+session: E.Session, +program: M.World(), +trigger: String, initial: String, query: String, +layer_occurrence: Nat, +rest: +List<E.Layer>, revision: Nat, +text: U.Text, old_profile: String, old_reasoning: String, context: Context.Configuration, feedback: U.Feedback, +directory_entry: String, +new_profile: String, +new_reasoning: String, observed_layers: {E.layers(session) == E.Layer{U.ModelPicker{U.NewTaskEditor{}}, trigger, initial, query, layer_occurrence} <> rest : +List<E.Layer>}, found: {E.find_draft(E.drafts(session), U.NewTaskEditor{}) ==
        Some{U.Draft{revision, U.NewTask{text, old_profile, old_reasoning, context}, feedback, directory_entry}} : Maybe<&2, U.Draft>}) ->
  {ExperienceProgram.step(E.UserInput{U.EditDraft{U.NewTaskEditor{}, U.ChooseModel{new_profile, new_reasoning}}},
        E.from_program(program, session)) ==
       E.Decision{E.from_program(program, E.with_attention(trigger, E.with_layers(rest, E.with_drafts(U.Draft{(revision + 1n : Nat), U.NewTask{text, new_profile, new_reasoning, context}, U.Editing{}, directory_entry} <>
           E.without_draft(E.drafts(session), U.NewTaskEditor{}), session)))),
         D.success(J.Null{}), Nil{}, [E.Attend{trigger}], False{}} : E.Decision}:
  E.Session{+route, +drafts, +readers, +stored_layers, +old_attention, +navigation, +filter, +now, +next, +pending, +previews, +code_blocks, +next_layer} = session
  backwards_layers = Equal.sym(E.Session, session, E.with_layers(E.Layer{U.ModelPicker{U.NewTaskEditor{}}, trigger, initial, query, layer_occurrence} <> rest, session),
    Equal.cong(+List<E.Layer>, E.Session, value => E.with_layers(value, session), E.layers(session), E.Layer{U.ModelPicker{U.NewTaskEditor{}}, trigger, initial, query, layer_occurrence} <> rest, observed_layers))
  %backwards_layers : {ExperienceProgram.step(E.UserInput{U.EditDraft{U.NewTaskEditor{}, U.ChooseModel{new_profile, new_reasoning}}},
        E.from_program(program, _)) ==
       E.Decision{E.from_program(program, E.with_attention(trigger, E.with_layers(rest, E.with_drafts(U.Draft{(revision + 1n : Nat), U.NewTask{text, new_profile, new_reasoning, context}, U.Editing{}, directory_entry} <>
           E.without_draft(E.drafts(_), U.NewTaskEditor{}), _)))),
         D.success(J.Null{}), Nil{}, [E.Attend{trigger}], False{}} : E.Decision}
  model_choice(program, route, drafts, readers, trigger, initial, query, layer_occurrence, rest, old_attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer, revision, text, old_profile, old_reasoning, context, feedback, directory_entry, new_profile, new_reasoning, found)

def encapsulated_modal_close_empty(+session: E.Session, +program: M.World(), observed_layers: {E.layers(session) == Nil{} : +List<E.Layer>}) ->
  {E.close_panel(E.from_program(program, session)) ==
       E.unchanged(E.from_program(program, session)) : E.Decision}:
  E.Session{+route, +drafts, +readers, +stored_layers, +attention_value, +navigation, +filter, +now, +next, +pending, +previews, +code_blocks, +next_layer} = session
  backwards_layers = Equal.sym(E.Session, session, E.with_layers(Nil{}, session),
    Equal.cong(+List<E.Layer>, E.Session, value => E.with_layers(value, session), E.layers(session), Nil{}, observed_layers))
  %backwards_layers : {E.close_panel(E.from_program(program, _)) ==
       E.unchanged(E.from_program(program, _)) : E.Decision}
  {==}

def encapsulated_modal_close_nonempty(+session: E.Session, +program: M.World(), +panel: U.Panel, +trigger: String, initial: String, query: String, +layer_occurrence: Nat, +rest: +List<E.Layer>, observed_layers: {E.layers(session) == E.Layer{panel, trigger, initial, query, layer_occurrence} <> rest : +List<E.Layer>}) ->
  {E.close_panel(E.from_program(program, session)) ==
       E.Decision{E.from_program(program, E.with_attention(trigger, E.with_layers(rest, session))),
        D.success(J.Null{}), Nil{}, [E.Attend{trigger}], False{}} : E.Decision}:
  E.Session{+route, +drafts, +readers, +stored_layers, +old_attention, +navigation, +filter, +now, +next, +pending, +previews, +code_blocks, +next_layer} = session
  backwards_layers = Equal.sym(E.Session, session, E.with_layers(E.Layer{panel, trigger, initial, query, layer_occurrence} <> rest, session),
    Equal.cong(+List<E.Layer>, E.Session, value => E.with_layers(value, session), E.layers(session), E.Layer{panel, trigger, initial, query, layer_occurrence} <> rest, observed_layers))
  %backwards_layers : {E.close_panel(E.from_program(program, _)) ==
       E.Decision{E.from_program(program, E.with_attention(trigger, E.with_layers(rest, _))),
        D.success(J.Null{}), Nil{}, [E.Attend{trigger}], False{}} : E.Decision}
  {==}

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
    encapsulated_model_choice
  }
