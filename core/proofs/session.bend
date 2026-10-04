import Base
import ../../BOARD.bend as B
import ../../MODEL.bend as M
import ../../PROGRAM.bend as Program
import ../../bendlib/association-map.bend as Finite
import ../../bendlib/component.bend as C
import ../../bendlib/domain.bend as D
import ../../bendlib/json.bend as J
import ../code-block.bend as Content
import ../live-output.bend as Live
import ../user-context.bend as Context
import ../user-experience.bend as E
import ../user-input.bend as U
import ../session-laws.bend as Rule

def open_residence(application: E.Application, panel: U.Panel, trigger: String) ->
  {Rule.residence(Rule.post(E.open_panel(panel, trigger, application))) == Rule.residence(application) : Rule.Residence}:
  E.Application{program, E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks}} = application
  {==}

def open_attention(application: E.Application, panel: U.Panel, trigger: String) ->
  {Rule.attention(Rule.post(E.open_panel(panel, trigger, application))) == E.panel_target(panel) : String}:
  E.Application{program, E.Session{route, drafts, readers, layers, attention_value, navigation, filter, now, next, pending, previews, code_blocks}} = application
  {==}

def open_effects(application: E.Application, panel: U.Panel, trigger: String) ->
  {Rule.interaction_effects(E.open_panel(panel, trigger, application)) == [E.Attend{E.panel_target(panel)}] : +List<E.Effect>}:
  E.Application{program, E.Session{route, drafts, readers, layers, attention_value, navigation, filter, now, next, pending, previews, code_blocks}} = application
  {==}

def close_residence(application: E.Application) ->
  {Rule.residence(Rule.post(E.close_panel(application))) == Rule.residence(application) : Rule.Residence}:
  E.Application{program, E.Session{route, drafts, readers, +layers, attention, navigation, filter, now, next, pending, previews, code_blocks}} = application
  match layers:
    case Nil{}: {==}
    case Con{E.Layer{panel, trigger, initial, query}, rest}: {==}

def sequence_attention(application: E.Application, +panel: U.Panel, +trigger: String) ->
  {Rule.attention(Rule.post(E.close_panel(Rule.post(E.open_panel(panel, trigger, application))))) == trigger : String}:
  E.Application{program, E.Session{route, drafts, readers, layers, attention_value, navigation, filter, now, next, pending, previews, code_blocks}} = application
  {==}

def native_without_submission_keeps_content(decision: M.Decision(), session: E.Session, durable: Bool) ->
  {Rule.session_content(Rule.post(E.native_result(decision, session, None{}, durable))) ==
    Rule.session_content(E.Application{Rule.runtime_program(decision), session}) : Rule.SessionContent}:
  C.Decision{program, result, effects} = decision
  E.Session{route, drafts, readers, layers, attention_value, navigation, filter, now, next, pending, previews, code_blocks} = session
  {==}

def runtime_keeps_content(+input: M.Input, application: E.Application) ->
  {Rule.session_content(Rule.post(E.step(E.RuntimeInput{input}, application))) == Rule.session_content(application) : Rule.SessionContent}:
  E.Application{program, session} = application
  native_without_submission_keeps_content(Program.transition(input, program), session, M.durable(input))

def native_without_submission_keeps_frame(decision: M.Decision(), session: E.Session, durable: Bool) ->
  {Rule.native_frame(Rule.post(E.native_result(decision, session, None{}, durable))) ==
    Rule.native_frame(E.Application{Rule.runtime_program(decision), session}) : Rule.NativeFrame}:
  C.Decision{program, result, effects} = decision
  E.Session{route, drafts, readers, layers, attention_value, navigation, filter, now, next, pending, previews, code_blocks} = session
  {==}

def native_without_submission_retains_previews(decision: M.Decision(), session: E.Session, durable: Bool) ->
  {Rule.previews(Rule.post(E.native_result(decision, session, None{}, durable))) ==
    Live.retained(Rule.previews(E.Application{Rule.runtime_program(decision), session}), Rule.runtime_program(decision)) : +List<Live.Output>}:
  C.Decision{program, result, effects} = decision
  E.Session{route, drafts, readers, layers, attention_value, navigation, filter, now, next, pending, previews, code_blocks} = session
  {==}

def preview_observation_keeps_content(observation: Live.Observation, application: E.Application) ->
  {Rule.session_content(Rule.post(E.step(E.PreviewObserved{observation}, application))) == Rule.session_content(application) : Rule.SessionContent}:
  E.Application{program, E.Session{route, drafts, readers, layers, attention_value, navigation, filter, now, next, pending, previews, code_blocks}} = application
  {==}

def navigate_keeps_drafts(route: U.Route, application: E.Application) ->
  {Rule.drafts(Rule.post(E.navigate(route, application))) == Rule.drafts(application) : +List<U.Draft>}:
  E.Application{program, E.Session{old, +drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks}} = application
  {==}

def visit_preserves_location(reader: E.Reader) ->
  {Rule.reading_location(E.new_visit(reader)) == Rule.reading_location(reader) : Rule.ReadingLocation}:
  E.Reader{generation, position, disclosures} = reader
  {==}

def obsolete_reading(+task: Nat, +generation: Nat, +intent: U.ReadingIntent, +application: E.Application,
  not_owner: {Rule.reading_owner(application, task, generation) == False{} : Bool}) ->
  {E.step(E.UserInput{U.ReadTimeline{task, generation, intent}}, application) == E.unchanged(application) : E.Decision}:
  E.Application{program, E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks}} = application
  Equal.cong(Bool, E.Decision, (owned => E.read_owned(owned, task, intent, application)),
    Rule.reading_owner(application, task, generation), False{}, not_owner)

def model_choice(program: M.World(), route: U.Route, drafts: +List<U.Draft>, readers: +List<Finite.Entry(E.Reader)>,
  +trigger: String, initial: String, query: String, rest: +List<E.Layer>, old_attention: String,
  navigation: E.NavigationState, filter: B.Filter, now: U32, next: Nat, pending: +List<E.Pending>,
  previews: +List<Live.Output>, code_blocks: +List<Content.Block>, revision: Nat, text: U.Text,
  old_profile: String, old_reasoning: String, context: Context.Configuration, feedback: U.Feedback, +directory_entry: String,
  +new_profile: String, +new_reasoning: String,
  found: {E.find_draft(drafts, U.NewTaskEditor{}) ==
    Some{U.Draft{revision, U.NewTask{text, old_profile, old_reasoning, context}, feedback, directory_entry}} : Maybe<&2, U.Draft>}) ->
  {E.step(E.UserInput{U.EditDraft{U.NewTaskEditor{}, U.ChooseModel{new_profile, new_reasoning}}},
      E.Application{program, E.Session{route, drafts, readers,
        E.Layer{U.ModelPicker{U.NewTaskEditor{}}, trigger, initial, query} <> rest,
        old_attention, navigation, filter, now, next, pending, previews, code_blocks}}) ==
    E.Decision{E.Application{program, E.Session{route,
      U.Draft{(revision + 1n : Nat), U.NewTask{text, new_profile, new_reasoning, context}, U.Editing{}, directory_entry} <>
        E.without_draft(drafts, U.NewTaskEditor{}),
      readers, rest, trigger, navigation, filter, now, next, pending, previews, code_blocks}},
      D.success(J.Null{}), Nil{}, [E.Attend{trigger}], False{}} : E.Decision}:
  session: E.Session = E.Session{route, drafts, readers,
    E.Layer{U.ModelPicker{U.NewTaskEditor{}}, trigger, initial, query} <> rest,
    old_attention, navigation, filter, now, next, pending, previews, code_blocks}
  Equal.cong(Maybe<&2, U.Draft>, E.Decision,
    (found_draft => E.close_selected_choice(U.ChooseModel{new_profile, new_reasoning}, U.NewTaskEditor{},
      E.edit_found(found_draft, U.ChooseModel{new_profile, new_reasoning}, program, session))),
    E.find_draft(drafts, U.NewTaskEditor{}),
    Some{U.Draft{revision, U.NewTask{text, old_profile, old_reasoning, context}, feedback, directory_entry}}, found)

def Rule.evidence():
  Rule.Requirements{
    application => panel => trigger => open_residence(application, panel, trigger),
    application => panel => trigger => open_attention(application, panel, trigger),
    application => panel => trigger => open_effects(application, panel, trigger),
    application => close_residence(application),
    program => route => drafts => readers => panel => +trigger => initial => query => rest => old_attention => navigation => filter => now => next => pending => previews => code_blocks => {==},
    program => route => drafts => readers => attention_value => navigation => filter => now => next => pending => previews => code_blocks => {==},
    application => panel => trigger => sequence_attention(application, panel, trigger),
    +application => +panel => +trigger =>
      Equal.trans(Rule.Residence,
        Rule.residence(Rule.post(E.close_panel(Rule.post(E.open_panel(panel, trigger, application))))),
        Rule.residence(Rule.post(E.open_panel(panel, trigger, application))), Rule.residence(application),
        close_residence(Rule.post(E.open_panel(panel, trigger, application))),
        open_residence(application, panel, trigger))
    ,
    input => application => runtime_keeps_content(input, application),
    decision => session => durable => native_without_submission_keeps_frame(decision, session, durable),
    decision => session => durable => native_without_submission_retains_previews(decision, session, durable),
    observation => application => preview_observation_keeps_content(observation, application),
    route => application => navigate_keeps_drafts(route, application),
    reader => visit_preserves_location(reader),
    task => generation => intent => application => not_owner => obsolete_reading(task, generation, intent, application, not_owner),
    program => route => drafts => readers => trigger => initial => query => rest => old_attention => navigation => filter => now => next => pending => previews => code_blocks => revision => text => old_profile => old_reasoning => context => feedback => directory_entry => new_profile => new_reasoning => found =>
      model_choice(program, route, drafts, readers, trigger, initial, query, rest, old_attention, navigation, filter, now, next, pending, previews, code_blocks, revision, text, old_profile, old_reasoning, context, feedback, directory_entry, new_profile, new_reasoning, found)
  }
