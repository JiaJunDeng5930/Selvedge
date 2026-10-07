import Base
import ../BOARD.bend as B
import ../MODEL.bend as M
import ../bendlib/association-map.bend as Finite
import ../bendlib/component.bend as C
import ../bendlib/domain.bend as D
import ../bendlib/json.bend as J
import ./code-block.bend as Content
import ./live-output.bend as Live
import ./user-context.bend as Context
import ./user-experience.bend as E
import ./user-experience-program.bend as ExperienceProgram
import ./user-input.bend as U

type Residence is Data:
  Residence{program: M.World(), drafts: +List<U.Draft>, readers: +List<Finite.Entry(E.Reader)>,
    pending: +List<E.Pending>, previews: +List<Live.Output>, code_blocks: +List<Content.Block>,
    route: U.Route, navigation: E.NavigationState, filter: B.Filter, now: U32, next_ticket: Nat}

type SessionContent is Data:
  SessionContent{drafts: +List<U.Draft>, readers: +List<Finite.Entry(E.Reader)>}

type NativeFrame is Data:
  NativeFrame{program: M.World(), route: U.Route, drafts: +List<U.Draft>, readers: +List<Finite.Entry(E.Reader)>,
    layers: +List<E.Layer>, attention: String, navigation: E.NavigationState, filter: B.Filter, now: U32,
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
  E.Application{program, E.Session{route, +drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}} = application
  drafts

def readers(application: E.Application) -> +List<Finite.Entry(E.Reader)>:
  E.Application{program, E.Session{route, drafts, +readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}} = application
  readers

def attention(application: E.Application) -> String:
  E.Application{program, E.Session{route, drafts, readers, layers, +attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}} = application
  attention

def layers(application: E.Application) -> +List<E.Layer>:
  E.Application{program, E.Session{route, drafts, readers, +layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}} = application
  layers

def previews(application: E.Application) -> +List<Live.Output>:
  E.Application{program, E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, +previews, code_blocks, next_layer}} = application
  previews

def interaction_effects(decision: E.Decision) -> +List<E.Effect>:
  E.Decision{application, reply, runtime, +interaction, durable} = decision
  interaction

def residence(application: E.Application) -> Residence:
  E.Application{program, E.Session{route, +drafts, +readers, layers, attention, navigation, filter, now, next, +pending, +previews, +code_blocks, next_layer}} = application
  Residence{program, drafts, readers, pending, previews, code_blocks, route, navigation, filter, now, next}

def session_content_of(session: E.Session) -> SessionContent:
  E.Session{route, +drafts, +readers, layers, attention_value, navigation, filter, now, next, pending, previews, code_blocks, next_layer} = session
  SessionContent{drafts, readers}

def session_content(application: E.Application) -> SessionContent:
  E.Application{program, session} = application
  session_content_of(session)

def native_frame(application: E.Application) -> NativeFrame:
  E.Application{program, E.Session{+route, +drafts, +readers, +layers, attention, navigation, filter, now, next, +pending, previews, +code_blocks, next_layer}} = application
  NativeFrame{program, route, drafts, readers, layers, attention, navigation, filter, now, next, pending, code_blocks}

def reading_location(reader: E.Reader) -> ReadingLocation:
  E.Reader{generation, position, +disclosures} = reader
  ReadingLocation{position, disclosures}

def reading_owner(application: E.Application, +task: Nat, generation: Nat) -> Bool:
  E.Application{program, E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}} = application
  U.route_owns(route, task) && Nat.is_eq(generation, E.reader_generation(E.reader(readers, task)))

def opened_application(+application: E.Application, +panel: U.Panel, trigger: String) -> E.Decision:
  E.Application{program, E.Session{route, drafts, readers, layers, attention, navigation, filter,
    now, next, pending, previews, code_blocks, +next_layer}} = application
  +target = E.panel_target(panel)
  E.Decision{E.Application{program, E.Session{route, drafts, readers,
    E.Layer{panel, trigger, target, "", next_layer} <> E.without_panel(layers, E.panel_target(panel)),
    target, navigation, filter, now, next, pending, previews, code_blocks, (next_layer + 1n : Nat)}},
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
    modal_close_nonempty: @+program:M.World() -> @+route:U.Route -> @+drafts:+List<U.Draft> ->
      @+readers:+List<Finite.Entry(E.Reader)> -> @+panel:U.Panel -> @+trigger:String -> @initial:String ->
      @query:String -> @+layer_occurrence:Nat -> @+rest:+List<E.Layer> -> @old_attention:String -> @navigation:E.NavigationState ->
      @filter:B.Filter -> @now:U32 -> @next:Nat -> @+pending:+List<E.Pending> -> @+previews:+List<Live.Output> ->
      @+code_blocks:+List<Content.Block> -> @next_layer:Nat ->
      {E.close_panel(E.Application{program, E.Session{route, drafts, readers,
        E.Layer{panel, trigger, initial, query, layer_occurrence} <> rest, old_attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}}) ==
       E.Decision{E.Application{program, E.Session{route, drafts, readers, rest, trigger, navigation, filter, now, next, pending, previews, code_blocks, next_layer}},
        D.success(J.Null{}), Nil{}, [E.Attend{trigger}], False{}} : E.Decision},
    modal_close_empty: @+program:M.World() -> @+route:U.Route -> @+drafts:+List<U.Draft> ->
      @+readers:+List<Finite.Entry(E.Reader)> -> @attention_value:String -> @navigation:E.NavigationState ->
      @filter:B.Filter -> @now:U32 -> @next:Nat -> @+pending:+List<E.Pending> -> @+previews:+List<Live.Output> ->
      @+code_blocks:+List<Content.Block> -> @next_layer:Nat ->
      {E.close_panel(E.Application{program, E.Session{route, drafts, readers, Nil{}, attention_value, navigation, filter, now, next, pending, previews, code_blocks, next_layer}}) ==
       E.unchanged(E.Application{program, E.Session{route, drafts, readers, Nil{}, attention_value, navigation, filter, now, next, pending, previews, code_blocks, next_layer}}) : E.Decision},
    modal_sequence_attention: @+application:E.Application -> @+panel:U.Panel -> @+trigger:String ->
      {attention(post(E.close_panel(post(E.open_panel(panel, trigger, application))))) == trigger : String},
    modal_sequence_residence: @+application:E.Application -> @+panel:U.Panel -> @+trigger:String ->
      {residence(post(E.close_panel(post(E.open_panel(panel, trigger, application))))) == residence(application) : Residence},
    runtime_keeps_content: @+input:M.Input -> @+application:E.Application ->
      {session_content(post(ExperienceProgram.step(E.RuntimeInput{input}, application))) == session_content(application) : SessionContent},
    native_without_submission_keeps_frame: @+decision:M.Decision() -> @+session:E.Session -> @durable:Bool ->
      {native_frame(post(E.native_result(decision, session, None{}, durable))) ==
        native_frame(E.Application{runtime_program(decision), session}) : NativeFrame},
    native_without_submission_retains_previews: @+decision:M.Decision() -> @+session:E.Session -> @durable:Bool ->
      {previews(post(E.native_result(decision, session, None{}, durable))) ==
        Live.retained(previews(E.Application{runtime_program(decision), session}), runtime_program(decision)) : +List<Live.Output>},
    preview_observation_keeps_content: @+observation:Live.Observation -> @+application:E.Application ->
      {session_content(post(ExperienceProgram.step(E.PreviewObserved{observation}, application))) == session_content(application) : SessionContent},
    navigate_keeps_drafts: @+route:U.Route -> @+application:E.Application ->
      {drafts(post(E.navigate(route, application))) == drafts(application) : +List<U.Draft>},
    new_visit_keeps_location: @+reader:E.Reader ->
      {reading_location(E.new_visit(reader)) == reading_location(reader) : ReadingLocation},
    obsolete_reading: @+task:Nat -> @+generation:Nat -> @+intent:U.ReadingIntent -> @+application:E.Application ->
      @not_owner:{reading_owner(application, task, generation) == False{} : Bool} ->
      {ExperienceProgram.step(E.UserInput{U.ReadTimeline{task, generation, intent}}, application) == E.unchanged(application) : E.Decision},
    model_choice: @+program:M.World() -> @+route:U.Route -> @+drafts:+List<U.Draft> ->
      @+readers:+List<Finite.Entry(E.Reader)> -> @+trigger:String -> @initial:String -> @query:String -> @+layer_occurrence:Nat ->
      @+rest:+List<E.Layer> -> @old_attention:String -> @navigation:E.NavigationState -> @filter:B.Filter ->
      @now:U32 -> @next:Nat -> @+pending:+List<E.Pending> -> @+previews:+List<Live.Output> ->
      @+code_blocks:+List<Content.Block> -> @next_layer:Nat -> @revision:Nat -> @+text:U.Text -> @old_profile:String ->
      @old_reasoning:String -> @context:Context.Configuration -> @feedback:U.Feedback -> @+directory_entry:String ->
      @+new_profile:String -> @+new_reasoning:String ->
      @found:{E.find_draft(drafts, U.NewTaskEditor{}) ==
        Some{U.Draft{revision, U.NewTask{text, old_profile, old_reasoning, context}, feedback, directory_entry}} : Maybe<&2, U.Draft>} ->
      {ExperienceProgram.step(E.UserInput{U.EditDraft{U.NewTaskEditor{}, U.ChooseModel{new_profile, new_reasoning}}},
        E.Application{program, E.Session{route, drafts, readers,
          E.Layer{U.ModelPicker{U.NewTaskEditor{}}, trigger, initial, query, layer_occurrence} <> rest,
          old_attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}}) ==
       E.Decision{E.Application{program, E.Session{route,
         U.Draft{(revision + 1n : Nat), U.NewTask{text, new_profile, new_reasoning, context}, U.Editing{}, directory_entry} <>
           E.without_draft(drafts, U.NewTaskEditor{}),
         readers, rest, trigger, navigation, filter, now, next, pending, previews, code_blocks, next_layer}},
         D.success(J.Null{}), Nil{}, [E.Attend{trigger}], False{}} : E.Decision}
  }

law evidence:
  Requirements
