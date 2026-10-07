import Base
import ../../harness/MODEL.bend as M
import ../../bendlib/component.bend as C
import ../../harness/DOMAIN.bend as D
import ../../bendlib/json.bend as J
import ../../harness/transport/command-codec.bend as CommandCodec
import ./MODEL.bend as E
import ./PROGRAM.bend as ExperienceProgram
import ../INPUT.bend as U

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
