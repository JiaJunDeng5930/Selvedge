import Base
import ./CONTRACT.bend as Rule
import ../../harness/MODEL.bend as M
import ../../harness/PROGRAM.bend as Program
import ../../bendlib/component.bend as C
import ../../bendlib/json.bend as J
import ../../harness/transport/command-codec.bend as CommandCodec
import ./MODEL.bend as E
import ./PROGRAM.bend as ExperienceProgram
import ../INPUT.bend as U
import ../submission/submission-proof.bend as SubmissionProof

def native_decision(+decision: M.Decision(), session: E.Session, durable: Bool) ->
  {Rule.runtime_observation(E.native_result(decision, session, None{}, durable)) == decision : M.Decision()}:
  C.Decision{program, reply, effects} = decision
  E.Session{route, drafts, readers, layers, focus, navigation, filter, now, next, pending, previews, code_blocks, next_layer} = session
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

def confirmation_result_refinement(owned: Bool, +result: J.Json, destination: U.Route, application: E.Application) ->
  {E.complete_confirmation(owned, result, destination, application) == Rule.confirmation_result_spec(owned, result, destination, application) : E.Decision}:
  match owned:
    case False{}: {==}
    case True{}: accepted_confirmation_refinement(J.boolean(J.get(result, "ok")), result, destination, application)

def confirmation_identity_refinement(+layers: +List<E.Layer>, +command: M.Command, +trigger: String, +occurrence: Nat) ->
  {E.confirmation_owned(layers, command, trigger, occurrence) == Rule.confirmation_spec(layers, command, trigger, occurrence) : Bool}:
  match layers:
    case Nil{}: {==}
    case Con{E.Layer{panel, current_trigger, target, query, layer_occurrence}, rest}:
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
  {ExperienceProgram.step(E.CommandCompleted{program, result, completion}, E.Application{previous, session}) == Rule.completion_spec(completion, program, result, session) : E.Decision}:
  match completion:
    case E.DirectCompletion{}: {==}
    case E.DraftCompletion{draft}: {==}
    case E.ConfirmationCompletion{command, trigger, destination, occurrence}:
      E.Session{route, drafts, readers, +layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer} = session
      +updated: E.Application = E.Application{program, E.retain_previews(E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}, program)}
      Equal.trans(E.Decision,
        E.complete_confirmation(E.confirmation_owned(layers, command, trigger, occurrence), result, destination, updated),
        E.complete_confirmation(Rule.confirmation_spec(layers, command, trigger, occurrence), result, destination, updated),
        Rule.confirmation_result_spec(Rule.confirmation_spec(layers, command, trigger, occurrence), result, destination, updated),
        Equal.cong(Bool, E.Decision, (owned => E.complete_confirmation(owned, result, destination, updated)),
          E.confirmation_owned(layers, command, trigger, occurrence), Rule.confirmation_spec(layers, command, trigger, occurrence),
          confirmation_identity_refinement(layers, command, trigger, occurrence)),
        confirmation_result_refinement(Rule.confirmation_spec(layers, command, trigger, occurrence), result, destination, updated))

def Rule.command_evidence():
  Rule.CommandRequirements{
    completion => program => result => session => previous => completed_refinement(completion, program, result, session, previous),
    +command => +application => +submitted => {==},
    +program => +session => previous => {==},

      # The submitted snapshot is settled only if its editor still has that revision;
      # the existing submission laws establish acceptance, refusal and stale ownership.
    +program => +result => +draft => +session => previous => absent => SubmissionProof.stale_native(draft, program, result, Nil{}, E.retain_previews(session, program), False{}, absent),
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
