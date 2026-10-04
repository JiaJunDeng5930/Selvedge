import Base
import ../MODEL.bend as M
import ../bendlib/component.bend as C
import ../bendlib/domain.bend as D
import ../bendlib/json.bend as J
import ../bendlib/command-codec.bend as CommandCodec
import ./user-experience.bend as E
import ./user-input.bend as U

def runtime_observation(decision: E.Decision) -> M.Decision():
  E.Decision{E.Application{program, session}, reply, effects, interaction, durable} = decision
  C.Decision{program, reply, effects}

# The human-facing system retains the entire existing execution decision:
# post-state, reply and ordered effects. Session behavior cannot replace it.

def confirmation_spec(layers: +List<E.Layer>, +command: M.Command, +trigger: String) -> Bool:
  match layers:
    case Con{E.Layer{U.Confirm{current, title, destination}, current_trigger, target, query}, rest}:
      String.eq(current_trigger, trigger) && J.same(CommandCodec.command_json(current), CommandCodec.command_json(command))
    case _: False{}

def accepted_confirmation_spec(ok: Bool, +result: J.Json, destination: U.Route, application: E.Application) -> E.Decision:
  match ok:
    case True{}: E.with_native(E.navigate(destination, application), result, Nil{}, False{})
    case False{}: E.Decision{application, result, Nil{}, Nil{}, False{}}

def confirmation_result_spec(owned: Bool, +result: J.Json, destination: U.Route, application: E.Application) -> E.Decision:
  match owned:
    case False{}: E.Decision{application, result, Nil{}, Nil{}, False{}}
    case True{}: accepted_confirmation_spec(J.boolean(J.get(result, "ok")), result, destination, application)

def completion_spec(completion: E.Completion, +program: M.World(), +result: J.Json, +session: E.Session) -> E.Decision:
  match completion:
    case E.DirectCompletion{}: E.Decision{E.Application{program, E.retain_previews(session, program)}, result, Nil{}, Nil{}, False{}}
    case E.DraftCompletion{+draft}:
      E.with_native(E.finish_submission(J.boolean(J.get(result, "ok")) && E.owns_submission(draft, E.retain_previews(session, program)), draft, result,
        E.Application{program, E.settle(draft, result, E.retain_previews(session, program))}), result, Nil{}, False{})
    case E.ConfirmationCompletion{command, trigger, destination}:
      E.Session{route, drafts, readers, +layers, attention, navigation, filter, now, next, pending, previews, code_blocks} = session
      confirmation_result_spec(confirmation_spec(layers, command, trigger), result, destination, E.Application{program, E.retain_previews(session, program)})

type CommandRequirements is Type:
  CommandRequirements{
    receipt: @+completion:E.Completion -> @+program:M.World() -> @+result:J.Json -> @+session:E.Session -> @previous:M.World() ->
      {E.step(E.CommandCompleted{program, result, completion}, E.Application{previous, session}) == completion_spec(completion, program, result, session) : E.Decision},
    request: @+command:M.Command -> @+application:E.Application -> @+submitted:Maybe<&2, U.Draft> ->
      {E.execute(command, application, submitted) ==
        E.Decision{application, D.success(J.Null{}), Nil{},
          [E.RequestCommand{command, E.submission_completion(submitted)}], False{}} : E.Decision},
    observation: @+program:M.World() -> @+session:E.Session -> @previous:M.World() ->
      {E.step(E.ProgramObserved{program}, E.Application{previous, session}) == E.Decision{E.Application{program, E.retain_previews(session, program)}, D.success(J.Null{}), Nil{}, Nil{}, False{}} : E.Decision},
    direct: @+program:M.World() -> @+result:J.Json -> @+session:E.Session -> @previous:M.World() ->
      {E.step(E.CommandCompleted{program, result, E.DirectCompletion{}}, E.Application{previous, session}) == E.Decision{E.Application{program, E.retain_previews(session, program)}, result, Nil{}, Nil{}, False{}} : E.Decision},
    draft: @+program:M.World() -> @+result:J.Json -> @+draft:U.Draft -> @+session:E.Session -> @previous:M.World() ->
      {E.step(E.CommandCompleted{program, result, E.DraftCompletion{draft}}, E.Application{previous, session}) ==
        E.with_native(E.finish_submission(J.boolean(J.get(result, "ok")) && E.owns_submission(draft, E.retain_previews(session, program)), draft, result,
          E.Application{program, E.settle(draft, result, E.retain_previews(session, program))}), result, Nil{}, False{}) : E.Decision},
    stale: @+program:M.World() -> @+result:J.Json -> @+draft:U.Draft -> @+session:E.Session -> @previous:M.World() ->
      @absent:{E.owns_submission(draft, E.retain_previews(session, program)) == False{} : Bool} ->
      {E.step(E.CommandCompleted{program, result, E.DraftCompletion{draft}}, E.Application{previous, session}) == E.Decision{E.Application{program, E.retain_previews(session, program)}, result, Nil{}, Nil{}, False{}} : E.Decision},
    accepted: @+result:J.Json -> @destination:U.Route -> @application:E.Application ->
      @ok:{J.boolean(J.get(result, "ok")) == True{} : Bool} ->
      {E.complete_confirmation(True{}, result, destination, application) == E.with_native(E.navigate(destination, application), result, Nil{}, False{}) : E.Decision},
    refused: @+result:J.Json -> @destination:U.Route -> @+application:E.Application ->
      @ok:{J.boolean(J.get(result, "ok")) == False{} : Bool} ->
      {E.complete_confirmation(True{}, result, destination, application) == E.Decision{application, result, Nil{}, Nil{}, False{}} : E.Decision},
    replaced: @result:J.Json -> @destination:U.Route -> @application:E.Application ->
      {E.complete_confirmation(False{}, result, destination, application) == E.Decision{application, result, Nil{}, Nil{}, False{}} : E.Decision}
  }

law command_evidence:
  CommandRequirements
