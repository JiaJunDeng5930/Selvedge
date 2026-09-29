import Base
import ../BOARD.bend as B
import ../MODEL.bend as M
import ../PROGRAM.bend as Program
import ../bendlib/association-map.bend as Finite
import ../bendlib/component.bend as C
import ../bendlib/domain.bend as D
import ../bendlib/json.bend as J
import ./code-block.bend as Content
import ./live-output.bend as Live
import ./user-context.bend as Context
import ./user-experience.bend as E
import ./user-input.bend as U

type Residence is Data:
  Residence{program: M.World(), drafts: +List<U.Draft>, readers: +List<Finite.Entry(E.Reader)>,
    pending: +List<E.Pending>, previews: +List<Live.Output>, code_blocks: +List<Content.Block>,
    route: U.Route, navigation: E.NavigationIntent, filter: B.Filter, now: U32, next_ticket: Nat}

type SessionContent is Data:
  SessionContent{drafts: +List<U.Draft>, readers: +List<Finite.Entry(E.Reader)>}

type NativeFrame is Data:
  NativeFrame{program: M.World(), route: U.Route, drafts: +List<U.Draft>, readers: +List<Finite.Entry(E.Reader)>,
    layers: +List<E.Layer>, attention: String, navigation: E.NavigationIntent, filter: B.Filter, now: U32,
    next_ticket: Nat, pending: +List<E.Pending>, code_blocks: +List<Content.Block>}

type ReadingLocation is Data:
  ReadingLocation{position: U.ReadingIntent, disclosures: +List<E.Disclosure>}

def post(decision: E.Decision) -> E.Application:
  E.Decision{+application, reply, runtime, interaction, durable} = decision
  application

def runtime_program(decision: M.Decision()) -> M.World():
  C.Decision{+program, result, effects} = decision
  program

def drafts(application: E.Application) -> +List<U.Draft>:
  E.Application{program, E.Session{route, +drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks}} = application
  drafts

def readers(application: E.Application) -> +List<Finite.Entry(E.Reader)>:
  E.Application{program, E.Session{route, drafts, +readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks}} = application
  readers

def attention(application: E.Application) -> String:
  E.Application{program, E.Session{route, drafts, readers, layers, +attention, navigation, filter, now, next, pending, previews, code_blocks}} = application
  attention

def layers(application: E.Application) -> +List<E.Layer>:
  E.Application{program, E.Session{route, drafts, readers, +layers, attention, navigation, filter, now, next, pending, previews, code_blocks}} = application
  layers

def previews(application: E.Application) -> +List<Live.Output>:
  E.Application{program, E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, +previews, code_blocks}} = application
  previews

def interaction_effects(decision: E.Decision) -> +List<E.Effect>:
  E.Decision{application, reply, runtime, +interaction, durable} = decision
  interaction

def residence(application: E.Application) -> Residence:
  E.Application{program, E.Session{route, +drafts, +readers, layers, attention, navigation, filter, now, next, +pending, +previews, +code_blocks}} = application
  Residence{program, drafts, readers, pending, previews, code_blocks, route, navigation, filter, now, next}

def session_content_of(session: E.Session) -> SessionContent:
  E.Session{route, +drafts, +readers, layers, attention_value, navigation, filter, now, next, pending, previews, code_blocks} = session
  SessionContent{drafts, readers}

def session_content(application: E.Application) -> SessionContent:
  E.Application{program, session} = application
  session_content_of(session)

def native_frame(application: E.Application) -> NativeFrame:
  E.Application{program, E.Session{+route, +drafts, +readers, +layers, attention, navigation, filter, now, next, +pending, previews, +code_blocks}} = application
  NativeFrame{program, route, drafts, readers, layers, attention, navigation, filter, now, next, pending, code_blocks}

def reading_location(reader: E.Reader) -> ReadingLocation:
  E.Reader{generation, position, +disclosures} = reader
  ReadingLocation{position, disclosures}

def open_residence(application: E.Application, panel: U.Panel, trigger: String) ->
  {residence(post(E.open_panel(panel, trigger, application))) == residence(application) : Residence}:
  E.Application{program, E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks}} = application
  {==}

def open_attention(application: E.Application, panel: U.Panel, trigger: String) ->
  {attention(post(E.open_panel(panel, trigger, application))) == E.panel_target(panel) : String}:
  E.Application{program, E.Session{route, drafts, readers, layers, attention_value, navigation, filter, now, next, pending, previews, code_blocks}} = application
  {==}

def open_effects(application: E.Application, panel: U.Panel, trigger: String) ->
  {interaction_effects(E.open_panel(panel, trigger, application)) == [E.Attend{E.panel_target(panel)}] : +List<E.Effect>}:
  E.Application{program, E.Session{route, drafts, readers, layers, attention_value, navigation, filter, now, next, pending, previews, code_blocks}} = application
  {==}

def close_residence(application: E.Application) ->
  {residence(post(E.close_panel(application))) == residence(application) : Residence}:
  E.Application{program, E.Session{route, drafts, readers, +layers, attention, navigation, filter, now, next, pending, previews, code_blocks}} = application
  match layers:
    case Nil{}: {==}
    case Con{E.Layer{panel, trigger, initial, query}, rest}: {==}

def close_nonempty(program: M.World(), route: U.Route, drafts: +List<U.Draft>, readers: +List<Finite.Entry(E.Reader)>,
  panel: U.Panel, +trigger: String, initial: String, query: String, rest: +List<E.Layer>, old_attention: String,
  navigation: E.NavigationIntent, filter: B.Filter, now: U32, next: Nat, pending: +List<E.Pending>,
  previews: +List<Live.Output>, code_blocks: +List<Content.Block>) ->
  {E.close_panel(E.Application{program, E.Session{route, drafts, readers,
      E.Layer{panel, trigger, initial, query} <> rest, old_attention, navigation, filter, now, next, pending, previews, code_blocks}}) ==
    E.Decision{E.Application{program, E.Session{route, drafts, readers, rest, trigger, navigation, filter, now, next, pending, previews, code_blocks}},
      D.success(J.Null{}), Nil{}, [E.Attend{trigger}], False{}} : E.Decision}:
  {==}

def close_empty(program: M.World(), route: U.Route, drafts: +List<U.Draft>, readers: +List<Finite.Entry(E.Reader)>,
  attention_value: String, navigation: E.NavigationIntent, filter: B.Filter, now: U32, next: Nat,
  pending: +List<E.Pending>, previews: +List<Live.Output>, code_blocks: +List<Content.Block>) ->
  {E.close_panel(E.Application{program, E.Session{route, drafts, readers, Nil{}, attention_value, navigation, filter, now, next, pending, previews, code_blocks}}) ==
    E.unchanged(E.Application{program, E.Session{route, drafts, readers, Nil{}, attention_value, navigation, filter, now, next, pending, previews, code_blocks}}) : E.Decision}:
  {==}

def sequence_attention(application: E.Application, +panel: U.Panel, +trigger: String) ->
  {attention(post(E.close_panel(post(E.open_panel(panel, trigger, application))))) == trigger : String}:
  E.Application{program, E.Session{route, drafts, readers, layers, attention_value, navigation, filter, now, next, pending, previews, code_blocks}} = application
  {==}

def sequence_residence(+application: E.Application, +panel: U.Panel, +trigger: String) ->
  {residence(post(E.close_panel(post(E.open_panel(panel, trigger, application))))) == residence(application) : Residence}:
  Equal.trans(Residence,
    residence(post(E.close_panel(post(E.open_panel(panel, trigger, application))))),
    residence(post(E.open_panel(panel, trigger, application))), residence(application),
    close_residence(post(E.open_panel(panel, trigger, application))),
    open_residence(application, panel, trigger))

def native_without_submission_keeps_content(decision: M.Decision(), session: E.Session, durable: Bool) ->
  {session_content(post(E.native_result(decision, session, None{}, durable))) ==
    session_content(E.Application{runtime_program(decision), session}) : SessionContent}:
  C.Decision{program, result, effects} = decision
  E.Session{route, drafts, readers, layers, attention_value, navigation, filter, now, next, pending, previews, code_blocks} = session
  {==}

def runtime_keeps_content(+input: M.Input, application: E.Application) ->
  {session_content(post(E.step(E.RuntimeInput{input}, application))) == session_content(application) : SessionContent}:
  E.Application{program, session} = application
  native_without_submission_keeps_content(Program.transition(input, program), session, M.durable(input))

def native_without_submission_keeps_frame(decision: M.Decision(), session: E.Session, durable: Bool) ->
  {native_frame(post(E.native_result(decision, session, None{}, durable))) ==
    native_frame(E.Application{runtime_program(decision), session}) : NativeFrame}:
  C.Decision{program, result, effects} = decision
  E.Session{route, drafts, readers, layers, attention_value, navigation, filter, now, next, pending, previews, code_blocks} = session
  {==}

def native_without_submission_retains_previews(decision: M.Decision(), session: E.Session, durable: Bool) ->
  {previews(post(E.native_result(decision, session, None{}, durable))) ==
    Live.retained(previews(E.Application{runtime_program(decision), session}), runtime_program(decision)) : +List<Live.Output>}:
  C.Decision{program, result, effects} = decision
  E.Session{route, drafts, readers, layers, attention_value, navigation, filter, now, next, pending, previews, code_blocks} = session
  {==}

def preview_observation_keeps_content(observation: Live.Observation, application: E.Application) ->
  {session_content(post(E.step(E.PreviewObserved{observation}, application))) == session_content(application) : SessionContent}:
  E.Application{program, E.Session{route, drafts, readers, layers, attention_value, navigation, filter, now, next, pending, previews, code_blocks}} = application
  {==}

def navigate_keeps_drafts(route: U.Route, application: E.Application) ->
  {drafts(post(E.navigate(route, application))) == drafts(application) : +List<U.Draft>}:
  E.Application{program, E.Session{old, +drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks}} = application
  {==}

def visit_preserves_location(reader: E.Reader) ->
  {reading_location(E.new_visit(reader)) == reading_location(reader) : ReadingLocation}:
  E.Reader{generation, position, disclosures} = reader
  {==}

def reading_owner(application: E.Application, +task: Nat, generation: Nat) -> Bool:
  E.Application{program, E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks}} = application
  E.route_owns(route, task) && Nat.is_eq(generation, E.reader_generation(E.reader(readers, task)))

def obsolete_reading(+task: Nat, +generation: Nat, +intent: U.ReadingIntent, +application: E.Application,
  not_owner: {reading_owner(application, task, generation) == False{} : Bool}) ->
  {E.step(E.UserInput{U.ReadTimeline{task, generation, intent}}, application) == E.unchanged(application) : E.Decision}:
  E.Application{program, E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks}} = application
  Equal.cong(Bool, E.Decision, (owned => E.read_owned(owned, task, intent, application)),
    reading_owner(application, task, generation), False{}, not_owner)

def model_choice(program: M.World(), route: U.Route, drafts: +List<U.Draft>, readers: +List<Finite.Entry(E.Reader)>,
  +trigger: String, initial: String, query: String, rest: +List<E.Layer>, old_attention: String,
  navigation: E.NavigationIntent, filter: B.Filter, now: U32, next: Nat, pending: +List<E.Pending>,
  previews: +List<Live.Output>, code_blocks: +List<Content.Block>, revision: Nat, text: U.Text,
  old_profile: String, old_reasoning: String, context: Context.Configuration, feedback: U.Feedback,
  +new_profile: String, +new_reasoning: String,
  found: {E.find_draft(drafts, U.NewTaskEditor{}) ==
    Some{U.Draft{revision, U.NewTask{text, old_profile, old_reasoning, context}, feedback}} : Maybe<&2, U.Draft>}) ->
  {E.step(E.UserInput{U.EditDraft{U.NewTaskEditor{}, U.ChooseModel{new_profile, new_reasoning}}},
      E.Application{program, E.Session{route, drafts, readers,
        E.Layer{U.ModelPicker{U.NewTaskEditor{}}, trigger, initial, query} <> rest,
        old_attention, navigation, filter, now, next, pending, previews, code_blocks}}) ==
    E.Decision{E.Application{program, E.Session{route,
      U.Draft{(revision + 1n : Nat), U.NewTask{text, new_profile, new_reasoning, context}, U.Editing{}} <>
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
    Some{U.Draft{revision, U.NewTask{text, old_profile, old_reasoning, context}, feedback}}, found)

type Requirements is Type:
  Requirements{
    modal_open_residence: @+application:E.Application -> @+panel:U.Panel -> @trigger:String ->
      {residence(post(E.open_panel(panel, trigger, application))) == residence(application) : Residence},
    modal_open_attention: @+application:E.Application -> @+panel:U.Panel -> @trigger:String ->
      {attention(post(E.open_panel(panel, trigger, application))) == E.panel_target(panel) : String},
    modal_open_effects: @+application:E.Application -> @+panel:U.Panel -> @trigger:String ->
      {interaction_effects(E.open_panel(panel, trigger, application)) == [E.Attend{E.panel_target(panel)}] : +List<E.Effect>},
    modal_close_residence: @+application:E.Application ->
      {residence(post(E.close_panel(application))) == residence(application) : Residence},
    modal_close_nonempty: @+program:M.World() -> @+route:U.Route -> @+drafts:+List<U.Draft> ->
      @+readers:+List<Finite.Entry(E.Reader)> -> @+panel:U.Panel -> @+trigger:String -> @initial:String ->
      @query:String -> @+rest:+List<E.Layer> -> @old_attention:String -> @navigation:E.NavigationIntent ->
      @filter:B.Filter -> @now:U32 -> @next:Nat -> @+pending:+List<E.Pending> -> @+previews:+List<Live.Output> ->
      @+code_blocks:+List<Content.Block> ->
      {E.close_panel(E.Application{program, E.Session{route, drafts, readers,
        E.Layer{panel, trigger, initial, query} <> rest, old_attention, navigation, filter, now, next, pending, previews, code_blocks}}) ==
       E.Decision{E.Application{program, E.Session{route, drafts, readers, rest, trigger, navigation, filter, now, next, pending, previews, code_blocks}},
        D.success(J.Null{}), Nil{}, [E.Attend{trigger}], False{}} : E.Decision},
    modal_close_empty: @+program:M.World() -> @+route:U.Route -> @+drafts:+List<U.Draft> ->
      @+readers:+List<Finite.Entry(E.Reader)> -> @attention_value:String -> @navigation:E.NavigationIntent ->
      @filter:B.Filter -> @now:U32 -> @next:Nat -> @+pending:+List<E.Pending> -> @+previews:+List<Live.Output> ->
      @+code_blocks:+List<Content.Block> ->
      {E.close_panel(E.Application{program, E.Session{route, drafts, readers, Nil{}, attention_value, navigation, filter, now, next, pending, previews, code_blocks}}) ==
       E.unchanged(E.Application{program, E.Session{route, drafts, readers, Nil{}, attention_value, navigation, filter, now, next, pending, previews, code_blocks}}) : E.Decision},
    modal_sequence_attention: @+application:E.Application -> @+panel:U.Panel -> @+trigger:String ->
      {attention(post(E.close_panel(post(E.open_panel(panel, trigger, application))))) == trigger : String},
    modal_sequence_residence: @+application:E.Application -> @+panel:U.Panel -> @+trigger:String ->
      {residence(post(E.close_panel(post(E.open_panel(panel, trigger, application))))) == residence(application) : Residence},
    runtime_keeps_content: @+input:M.Input -> @+application:E.Application ->
      {session_content(post(E.step(E.RuntimeInput{input}, application))) == session_content(application) : SessionContent},
    native_without_submission_keeps_frame: @+decision:M.Decision() -> @+session:E.Session -> @durable:Bool ->
      {native_frame(post(E.native_result(decision, session, None{}, durable))) ==
        native_frame(E.Application{runtime_program(decision), session}) : NativeFrame},
    native_without_submission_retains_previews: @+decision:M.Decision() -> @+session:E.Session -> @durable:Bool ->
      {previews(post(E.native_result(decision, session, None{}, durable))) ==
        Live.retained(previews(E.Application{runtime_program(decision), session}), runtime_program(decision)) : +List<Live.Output>},
    preview_observation_keeps_content: @+observation:Live.Observation -> @+application:E.Application ->
      {session_content(post(E.step(E.PreviewObserved{observation}, application))) == session_content(application) : SessionContent},
    navigate_keeps_drafts: @+route:U.Route -> @+application:E.Application ->
      {drafts(post(E.navigate(route, application))) == drafts(application) : +List<U.Draft>},
    new_visit_keeps_location: @+reader:E.Reader ->
      {reading_location(E.new_visit(reader)) == reading_location(reader) : ReadingLocation},
    obsolete_reading: @+task:Nat -> @+generation:Nat -> @+intent:U.ReadingIntent -> @+application:E.Application ->
      @not_owner:{reading_owner(application, task, generation) == False{} : Bool} ->
      {E.step(E.UserInput{U.ReadTimeline{task, generation, intent}}, application) == E.unchanged(application) : E.Decision},
    model_choice: @+program:M.World() -> @+route:U.Route -> @+drafts:+List<U.Draft> ->
      @+readers:+List<Finite.Entry(E.Reader)> -> @+trigger:String -> @initial:String -> @query:String ->
      @+rest:+List<E.Layer> -> @old_attention:String -> @navigation:E.NavigationIntent -> @filter:B.Filter ->
      @now:U32 -> @next:Nat -> @+pending:+List<E.Pending> -> @+previews:+List<Live.Output> ->
      @+code_blocks:+List<Content.Block> -> @revision:Nat -> @+text:U.Text -> @old_profile:String ->
      @old_reasoning:String -> @context:Context.Configuration -> @feedback:U.Feedback ->
      @+new_profile:String -> @+new_reasoning:String ->
      @found:{E.find_draft(drafts, U.NewTaskEditor{}) ==
        Some{U.Draft{revision, U.NewTask{text, old_profile, old_reasoning, context}, feedback}} : Maybe<&2, U.Draft>} ->
      {E.step(E.UserInput{U.EditDraft{U.NewTaskEditor{}, U.ChooseModel{new_profile, new_reasoning}}},
        E.Application{program, E.Session{route, drafts, readers,
          E.Layer{U.ModelPicker{U.NewTaskEditor{}}, trigger, initial, query} <> rest,
          old_attention, navigation, filter, now, next, pending, previews, code_blocks}}) ==
       E.Decision{E.Application{program, E.Session{route,
         U.Draft{(revision + 1n : Nat), U.NewTask{text, new_profile, new_reasoning, context}, U.Editing{}} <>
           E.without_draft(drafts, U.NewTaskEditor{}),
         readers, rest, trigger, navigation, filter, now, next, pending, previews, code_blocks}},
         D.success(J.Null{}), Nil{}, [E.Attend{trigger}], False{}} : E.Decision}
  }

def evidence() -> Requirements:
  Requirements{
    application => panel => trigger => open_residence(application, panel, trigger),
    application => panel => trigger => open_attention(application, panel, trigger),
    application => panel => trigger => open_effects(application, panel, trigger),
    application => close_residence(application),
    program => route => drafts => readers => panel => trigger => initial => query => rest => old_attention => navigation => filter => now => next => pending => previews => code_blocks =>
      close_nonempty(program, route, drafts, readers, panel, trigger, initial, query, rest, old_attention, navigation, filter, now, next, pending, previews, code_blocks),
    program => route => drafts => readers => attention_value => navigation => filter => now => next => pending => previews => code_blocks =>
      close_empty(program, route, drafts, readers, attention_value, navigation, filter, now, next, pending, previews, code_blocks),
    application => panel => trigger => sequence_attention(application, panel, trigger),
    application => panel => trigger => sequence_residence(application, panel, trigger),
    input => application => runtime_keeps_content(input, application),
    decision => session => durable => native_without_submission_keeps_frame(decision, session, durable),
    decision => session => durable => native_without_submission_retains_previews(decision, session, durable),
    observation => application => preview_observation_keeps_content(observation, application),
    route => application => navigate_keeps_drafts(route, application),
    reader => visit_preserves_location(reader),
    task => generation => intent => application => not_owner => obsolete_reading(task, generation, intent, application, not_owner),
    program => route => drafts => readers => trigger => initial => query => rest => old_attention => navigation => filter => now => next => pending => previews => code_blocks => revision => text => old_profile => old_reasoning => context => feedback => new_profile => new_reasoning => found =>
      model_choice(program, route, drafts, readers, trigger, initial, query, rest, old_attention, navigation, filter, now, next, pending, previews, code_blocks, revision, text, old_profile, old_reasoning, context, feedback, new_profile, new_reasoning, found)
  }
