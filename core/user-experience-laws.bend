import Base
import ../MODEL.bend as M
import ../PROGRAM.bend as Program
import ../bendlib/component.bend as C
import ../bendlib/domain.bend as D
import ../bendlib/json.bend as J
import ../bendlib/command-codec.bend as CommandCodec
import ./submission-laws.bend as Submission
import ./user-experience.bend as E
import ./user-input.bend as U

def runtime_observation(decision: E.Decision) -> M.Decision():
  E.Decision{E.Application{program, session}, reply, effects, interaction, durable} = decision
  C.Decision{program, reply, effects}

# The human-facing system retains the entire existing execution decision:
# post-state, reply and ordered effects. Session behavior cannot replace it.
def native_decision(+decision: M.Decision(), session: E.Session, durable: Bool) ->
  {runtime_observation(E.native_result(decision, session, None{}, durable)) == decision : M.Decision()}:
  C.Decision{program, reply, effects} = decision
  E.Session{route, drafts, readers, layers, focus, navigation, filter, now, next, pending, previews, code_blocks} = session
  {==}

def runtime_input(+input: M.Input, +program: M.World(), session: E.Session) ->
  {runtime_observation(E.step(E.RuntimeInput{input}, E.Application{program, session})) ==
    Program.transition(input, program) : M.Decision()}:
  native_decision(Program.transition(input, program), session, M.durable(input))

# Requests preserve the entire application until the server supplies a receipt.


















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

def accepted_confirmation_refinement(ok: Bool, +result: J.Json, destination: U.Route, application: E.Application) ->
  {E.with_native(E.confirmation_outcome(ok, destination, application), result, Nil{}, False{}) == accepted_confirmation_spec(ok, result, destination, application) : E.Decision}:
  match ok:
    case True{}: {==}
    case False{}: {==}

def confirmation_result_refinement(owned: Bool, +result: J.Json, destination: U.Route, application: E.Application) ->
  {E.complete_confirmation(owned, result, destination, application) == confirmation_result_spec(owned, result, destination, application) : E.Decision}:
  match owned:
    case False{}: {==}
    case True{}: accepted_confirmation_refinement(J.boolean(J.get(result, "ok")), result, destination, application)

def confirmation_identity_refinement(+layers: +List<E.Layer>, +command: M.Command, +trigger: String) ->
  {E.confirmation_owned(layers, command, trigger) == confirmation_spec(layers, command, trigger) : Bool}:
  match layers:
    case Nil{}: {==}
    case Con{E.Layer{panel, current_trigger, target, query}, rest}:
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
        case U.DeliveryPicker{task}: {==}

def completed_refinement(+completion: E.Completion, +program: M.World(), +result: J.Json, +session: E.Session, previous: M.World()) ->
  {E.step(E.CommandCompleted{program, result, completion}, E.Application{previous, session}) == completion_spec(completion, program, result, session) : E.Decision}:
  match completion:
    case E.DirectCompletion{}: {==}
    case E.DraftCompletion{draft}: {==}
    case E.ConfirmationCompletion{command, trigger, destination}:
      E.Session{route, drafts, readers, +layers, attention, navigation, filter, now, next, pending, previews, code_blocks} = session
      +updated: E.Application = E.Application{program, E.retain_previews(E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks}, program)}
      Equal.trans(E.Decision,
        E.complete_confirmation(E.confirmation_owned(layers, command, trigger), result, destination, updated),
        E.complete_confirmation(confirmation_spec(layers, command, trigger), result, destination, updated),
        confirmation_result_spec(confirmation_spec(layers, command, trigger), result, destination, updated),
        Equal.cong(Bool, E.Decision, (owned => E.complete_confirmation(owned, result, destination, updated)),
          E.confirmation_owned(layers, command, trigger), confirmation_spec(layers, command, trigger),
          confirmation_identity_refinement(layers, command, trigger)),
        confirmation_result_refinement(confirmation_spec(layers, command, trigger), result, destination, updated))

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

def command_evidence() -> CommandRequirements:
  CommandRequirements{
    completion => program => result => session => previous => completed_refinement(completion, program, result, session, previous),
    +command => +application => +submitted => {==},
    +program => +session => previous => {==},
    +program => +result => +session => previous =>
        {==}

      # The submitted snapshot is settled only if its editor still has that revision;
      # the existing submission laws establish acceptance, refusal and stale ownership.
    ,
    +program => +result => +draft => +session => previous => {==},
    +program => +result => +draft => +session => previous => absent => Submission.stale_native(draft, program, result, Nil{}, E.retain_previews(session, program), False{}, absent),
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

      # The receipt contract independently selects the local completion behavior.
    
  }


def confirmation_request(+command: M.Command, title: String, +destination: U.Route, +trigger: String,
  target: String, query: String, rest: +List<E.Layer>, +application: E.Application) ->
  {E.confirm(E.Layer{U.Confirm{command, title, destination}, trigger, target, query} <> rest, application) ==
    E.Decision{application, D.success(J.Null{}), Nil{}, [E.RequestCommand{command, E.ConfirmationCompletion{command, trigger, destination}}], False{}} : E.Decision}:
  {==}

