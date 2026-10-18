import Base
import ../DOMAIN.bend as D
import ../tasks/PROGRAM.bend as Actual
import ./PROGRAM.bend as Content
import ../../bendlib/json.bend as J
import ../MODEL.bend as M
import ../../bendlib/component.bend as C
import ../protocol/PROGRAM.bend as Protocol
import ../COMMANDS.bend as Commands
import ../features/SPEC.bend as FeatureRequirements
import ../tasks/CONTRACT.bend as TaskRequirements

def required_context_mode(assistant: Bool, mode: D.OutputMode) -> D.OutputMode:
  match assistant:
    case True{}: mode
    case False{}: D.Plain{}

def context_mode(+value: J.Json, mode: D.OutputMode) -> D.OutputMode:
  required_context_mode(String.eq(J.text(J.get(Content.provider_value(value), "type")), "message") && Content.provider_assistant(value), mode)

def required_messages(+producer: Nat, +operation: Nat, +mode: D.OutputMode, items: +List<D.ModelItem>) -> +List<D.Message>:
  match items:
    case Nil{}: Nil{}
    case Con{D.Say{part, text}, rest}:
      D.AssistantMessage{D.OutputOrigin{producer, operation, part, mode}, text} <> required_messages(producer, operation, mode, rest)
    case Con{D.Invoke{call}, rest}:
      D.FunctionCall{call} <> required_messages(producer, operation, mode, rest)
    case Con{D.Context{part, +value}, rest}:
      D.ModelContext{D.OutputOrigin{producer, operation, part, context_mode(value, mode)}, value} <> required_messages(producer, operation, mode, rest)

# Admission and settlement are the task boundary's existing policies. The new
# requirement fixes every appended message's authority and the complete result.
def required_phase_origin(phase: D.Phase, producer: Nat) -> D.OutputOrigin:
  match phase:
    case D.ModelPending{operation, callable, mode}: D.OutputOrigin{producer, operation, 0n, mode}
    case _: D.OutputOrigin{producer, 0n, 0n, D.Plain{}}

def required_origin(+task: D.Task) -> D.OutputOrigin:
  required_phase_origin(D.task_phase(task), D.task_id(task))

def rejected_reply(+task: D.Task) -> D.Task:
  Actual.settled_model(D.task_notified(task), D.append_message(D.FailureMessage{
    "invalid model reply: duplicate output part, duplicate call identity, unavailable tool, or invalid arguments"}, task))

def required_reply(accepted: Bool, origin: D.OutputOrigin, +items: +List<D.ModelItem>, +task: D.Task) -> D.Task:
  match accepted origin:
    case False{} _: rejected_reply(task)
    case True{} D.OutputOrigin{producer, operation, part, mode}:
      Actual.after_model(Actual.item_calls(items), D.with_history(
        D.history_append(required_messages(producer, operation, mode, items), D.task_history(task)), task))

def required_outcome(outcome: D.Outcome, +allowed: +List<String>, +task: D.Task) -> D.Task:
  match outcome:
    case D.ModelReply{+items}:
      required_reply(Actual.model_reply_permitted(allowed, task, Actual.ModelReplyCandidate{items}), required_origin(task), items, task)
    case D.ModelFailure{message}:
      Actual.settled_model(D.task_notified(task), D.append_message(D.FailureMessage{message}, task))
    case D.ContextLimit{}:
      Actual.promote(D.with_phase(D.Idle{}, D.append_message(D.FailureMessage{
        "Model context limit reached; full task history retained"}, task)))

def required_commit(+task: D.Task, +outcome: D.Outcome, +allowed: +List<String>, world: M.World()) -> M.Decision():
  Protocol.accepted_reaction(FeatureRequirements.react_outputs(~Commands.output_send, D.task_id(task),
    TaskRequirements.accepted_reply_outputs(outcome, allowed, task), Commands.replace(required_outcome(outcome, allowed, task), world)))

def required_completion(status: D.Status, +expected: Nat, +allowed: +List<String>, +task: D.Task, +ticket: Nat, +outcome: D.Outcome) -> Protocol.ResolvedEvent:
  match status:
    case D.Archived{}: Protocol.Ignore{}
    case _: Protocol.matching_calculation(Nat.is_eq(ticket, expected), Protocol.ModelResult{task, outcome, allowed})

def required_model_phase(phase: D.Phase, +task: D.Task, ticket: Nat, outcome: D.Outcome) -> Protocol.ResolvedEvent:
  match phase:
    case D.ModelPending{expected, allowed, mode}:
      required_completion(D.task_status(task), expected, allowed, task, ticket, outcome)
    case _: Protocol.Ignore{}

def required_model(found: Maybe<&2, D.Task>, +ticket: Nat, +outcome: D.Outcome) -> Protocol.ResolvedEvent:
  match found:
    case None{}: Protocol.Ignore{}
    case Some{+task}: required_model_phase(D.task_phase(task), task, ticket, outcome)

type OriginBoundary is Type:
  OriginBoundary{
    complete_messages: @+producer:Nat -> @+operation:Nat -> @+mode:D.OutputMode -> @+items:+List<D.ModelItem> ->
      {Actual.item_messages(producer, operation, mode, items) == required_messages(producer, operation, mode, items) : +List<D.Message>},
    frozen_request: @+producer:Nat -> @+operation:Nat -> @callable:+List<String> -> @+mode:D.OutputMode -> @+part:Nat ->
      {Actual.phase_output_origin(D.ModelPending{operation, callable, mode}, producer, part) == D.OutputOrigin{producer, operation, part, mode} : D.OutputOrigin},
    opaque_context: @+producer:Nat -> @+operation:Nat -> @+mode:D.OutputMode -> @+part:Nat -> @+value:J.Json ->
      {Actual.item_messages(producer, operation, mode, [D.Context{part, value}]) ==
        [D.ModelContext{D.OutputOrigin{producer, operation, part, context_mode(value, mode)}, value}] : +List<D.Message>},
    received_outcome: @+outcome:D.Outcome -> @+allowed:+List<String> -> @+task:D.Task ->
      {Actual.model_outcome(outcome, allowed, task) == required_outcome(outcome, allowed, task) : D.Task},
    committed_outcome: @+task:D.Task -> @+outcome:D.Outcome -> @+allowed:+List<String> -> @+world:M.World() ->
      {Protocol.model_result(task, outcome, allowed, world) == required_commit(task, outcome, allowed, world) : M.Decision()},
    correlated_completion: @+status:D.Status -> @+expected:Nat -> @+allowed:+List<String> -> @mode:D.OutputMode -> @+task:D.Task -> @+ticket:Nat -> @+outcome:D.Outcome ->
      {Protocol.model_phase(status, D.ModelPending{expected, allowed, mode}, task, ticket, outcome) ==
        required_completion(status, expected, allowed, task, ticket, outcome) : Protocol.ResolvedEvent},
    resolved_model: @+found:Maybe<&2, D.Task> -> @+ticket:Nat -> @+outcome:D.Outcome ->
      {Protocol.model(found, ticket, outcome) == required_model(found, ticket, outcome) : Protocol.ResolvedEvent},
    duplicate_text_rejected: @+part:Nat -> @+text:String -> @+rest:+List<D.ModelItem> -> @+allowed:+List<String> -> @+task:D.Task ->
      @duplicate:{Actual.contains_part(rest, part) == True{} : Bool} ->
      {Actual.model_outcome(D.ModelReply{D.Say{part, text} <> rest}, allowed, task) == rejected_reply(task) : D.Task},
    duplicate_context_rejected: @+part:Nat -> @+value:J.Json -> @+rest:+List<D.ModelItem> -> @+allowed:+List<String> -> @+task:D.Task ->
      @duplicate:{Actual.contains_part(rest, part) == True{} : Bool} ->
      {Actual.model_outcome(D.ModelReply{D.Context{part, value} <> rest}, allowed, task) == rejected_reply(task) : D.Task},
    rejected_outputs: @+items:+List<D.ModelItem> -> @+allowed:+List<String> -> @+task:D.Task ->
      @rejected:{Actual.model_reply_permitted(allowed, task, Actual.ModelReplyCandidate{items}) == False{} : Bool} ->
      {Actual.accepted_reply_outputs(D.ModelReply{items}, allowed, task) == Nil{} : +List<String>},
    rejected_commit: @+items:+List<D.ModelItem> -> @+allowed:+List<String> -> @+task:D.Task -> @+world:M.World() ->
      @rejected:{Actual.model_reply_permitted(allowed, task, Actual.ModelReplyCandidate{items}) == False{} : Bool} ->
      {Protocol.model_result(task, D.ModelReply{items}, allowed, world) ==
        C.Decision{Commands.replace(rejected_reply(task), world), Protocol.acknowledgement(True{}), Nil{}} : M.Decision()}}

law origin_boundary:
  OriginBoundary
