import Base
import ../../harness/MODEL.bend as M
import ../../bendlib/component.bend as C
import ../../harness/DOMAIN.bend as D
import ../../bendlib/json.bend as J
import ../../harness/transport/command-codec.bend as CommandCodec
import ./MODEL.bend as E
import ./PROGRAM.bend as ExperienceProgram
import ../INPUT.bend as U
import ../../features/board/MODEL.bend as B
import ../../bendlib/association-map.bend as Finite
import ../conversation/CODE.bend as Content
import ../conversation/OUTPUT.bend as Live
import ../services/CONTEXT.bend as Context

type ReadingLocation is Data:
  ReadingLocation{position: U.ReadingIntent, disclosures: +List<E.Disclosure>}

def post(decision: E.Decision) -> E.Application:
  E.Decision{+application, reply, runtime, interaction, durable} = decision
  application

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
  U.route_owns(route, task) && Nat.is_eq(generation, E.reader_generation(E.reader(readers, task)))

def opened_application(+application: E.Application, +panel: U.Panel, trigger: String) -> E.Decision:
  +program = E.program(application)
  +observed_session = E.session(application)
  layers = E.layers(observed_session)
  +next_layer = E.next_layer(observed_session)
  +target = E.panel_target(panel)
  E.Decision{E.from_program(program, E.with_next_layer((next_layer + 1n : Nat), E.with_attention(target, E.with_layers(E.Layer{panel, trigger, target, "", next_layer} <> E.without_panel(layers, E.panel_target(panel)), observed_session)))),
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
      @query:String -> @+layer_occurrence:Nat -> @+rest:+List<E.Layer> ->
      @observed_layers:{E.layers(session) == E.Layer{panel, trigger, initial, query, layer_occurrence} <> rest : +List<E.Layer>} ->
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
    model_choice: @+session:E.Session -> @+program:M.World() -> @+trigger:String -> @initial:String -> @query:String -> @+layer_occurrence:Nat ->
      @+rest:+List<E.Layer> -> @revision:Nat -> @+text:U.Text -> @old_profile:String ->
      @old_reasoning:String -> @context:Context.Configuration -> @feedback:U.Feedback -> @+directory_entry:String ->
      @+new_profile:String -> @+new_reasoning:String ->
      @observed_layers:{E.layers(session) == E.Layer{U.ModelPicker{U.NewTaskEditor{}}, trigger, initial, query, layer_occurrence} <> rest : +List<E.Layer>} ->
      @found:{E.find_draft(E.drafts(session), U.NewTaskEditor{}) ==
        Some{U.Draft{revision, U.NewTask{text, old_profile, old_reasoning, context}, feedback, directory_entry}} : Maybe<&2, U.Draft>} ->
      {ExperienceProgram.step(E.UserInput{U.EditDraft{U.NewTaskEditor{}, U.ChooseModel{new_profile, new_reasoning}}},
        E.from_program(program, session)) ==
       E.Decision{E.from_program(program, E.with_attention(trigger, E.with_layers(rest, E.with_drafts(U.Draft{(revision + 1n : Nat), U.NewTask{text, new_profile, new_reasoning, context}, U.Editing{}, directory_entry} <>
           E.without_draft(E.drafts(session), U.NewTaskEditor{}), session)))),
         D.success(J.Null{}), Nil{}, [E.Attend{trigger}], False{}} : E.Decision}
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
    case Con{E.Layer{U.Confirm{current, title, destination}, current_trigger, target, query, layer_occurrence}, rest}:
      Nat.is_eq(layer_occurrence, occurrence) && (String.eq(current_trigger, trigger) && J.same(CommandCodec.command_json(current), CommandCodec.command_json(command)))
    case _: False{}

def accepted_confirmation_spec(ok: Bool, +result: J.Json, destination: U.Route, +application: E.Application) -> E.Decision:
  match ok:
    case True{}: E.with_native(E.navigate(destination, application), result, Nil{}, False{})
    case False{}: E.Decision{application, result, Nil{}, Nil{}, False{}}

def confirmation_result_spec(owned: Bool, +result: J.Json, destination: U.Route, +application: E.Application) -> E.Decision:
  match owned:
    case False{}: E.Decision{application, result, Nil{}, Nil{}, False{}}
    case True{}: accepted_confirmation_spec(J.boolean(J.get(result, "ok")), result, destination, application)

def completion_spec(completion: E.Completion, +program: M.World(), +result: J.Json, +session: E.Session) -> E.Decision:
  match completion:
    case E.DirectCompletion{}: E.Decision{E.from_program(program, E.retain_previews(session, program)), result, Nil{}, Nil{}, False{}}
    case E.DraftCompletion{+draft}:
      E.with_native(E.finish_submission(J.boolean(J.get(result, "ok")) && E.owns_submission(draft, E.retain_previews(session, program)), draft, result,
        E.from_program(program, E.settle(draft, result, E.retain_previews(session, program)))), result, Nil{}, False{})
    case E.ConfirmationCompletion{command, trigger, destination, occurrence}:
      +layers = E.layers(session)
      confirmation_result_spec(confirmation_spec(layers, command, trigger, occurrence), result, destination, E.from_program(program, E.retain_previews(session, program)))

type CommandRequirements is Type:
  CommandRequirements{
    receipt: @+completion:E.Completion -> @+program:M.World() -> @+result:J.Json -> @+session:E.Session -> @previous:M.World() ->
      {ExperienceProgram.step(E.CommandCompleted{program, result, completion}, E.from_program(previous, session)) == completion_spec(completion, program, result, session) : E.Decision},
    request: @+command:M.Command -> @+application:E.Application -> @+submitted:Maybe<&2, U.Draft> ->
      {E.execute(command, application, submitted) ==
        E.Decision{application, D.success(J.Null{}), Nil{},
          [E.RequestCommand{command, E.submission_completion(submitted)}], False{}} : E.Decision},
    observation: @+program:M.World() -> @+session:E.Session -> @previous:M.World() ->
      {ExperienceProgram.step(E.ProgramObserved{program}, E.from_program(previous, session)) == E.Decision{E.from_program(program, E.retain_previews(session, program)), D.success(J.Null{}), Nil{}, Nil{}, False{}} : E.Decision},
    stale: @+program:M.World() -> @+result:J.Json -> @+draft:U.Draft -> @+session:E.Session -> @previous:M.World() ->
      @absent:{E.owns_submission(draft, E.retain_previews(session, program)) == False{} : Bool} ->
      {ExperienceProgram.step(E.CommandCompleted{program, result, E.DraftCompletion{draft}}, E.from_program(previous, session)) == E.Decision{E.from_program(program, E.retain_previews(session, program)), result, Nil{}, Nil{}, False{}} : E.Decision},
    accepted: @+result:J.Json -> @destination:U.Route -> @application:E.Application ->
      @ok:{J.boolean(J.get(result, "ok")) == True{} : Bool} ->
      {E.complete_confirmation(True{}, result, destination, application) == E.with_native(E.navigate(destination, application), result, Nil{}, False{}) : E.Decision},
    refused: @+result:J.Json -> @destination:U.Route -> @+application:E.Application ->
      @ok:{J.boolean(J.get(result, "ok")) == False{} : Bool} ->
      {E.complete_confirmation(True{}, result, destination, application) == E.Decision{application, result, Nil{}, Nil{}, False{}} : E.Decision},
    replaced: @result:J.Json -> @destination:U.Route -> @application:E.Application ->
      {E.complete_confirmation(False{}, result, destination, application) == E.Decision{application, result, Nil{}, Nil{}, False{}} : E.Decision},
    stale_occurrence: @+current:M.Command -> @title:String -> @destination:U.Route -> @+current_trigger:String -> @target:String -> @query:String -> @+current_occurrence:Nat -> @rest:+List<E.Layer> -> @+command:M.Command -> @+trigger:String -> @+occurrence:Nat ->
      @stale:{Nat.is_eq(current_occurrence, occurrence) == False{} : Bool} ->
      {E.confirmation_owned(E.Layer{U.Confirm{current, title, destination}, current_trigger, target, query, current_occurrence} <> rest, command, trigger, occurrence) == False{} : Bool}
  }

law command_evidence:
  CommandRequirements
