import Base
import ../DOMAIN.bend as D
import ../tasks/PROGRAM.bend as Actual
import ./origin-contract.bend as Spec
import ./PROGRAM.bend as Content
import ../../bendlib/json.bend as J
import ../../bendlib/stdlib.bend as Std
import ../../bendlib/categories.bend as Categories
import ../MODEL.bend as M
import ../../bendlib/component.bend as C
import ../protocol/PROGRAM.bend as Protocol
import ../protocol/PROOF.bend as ProtocolProof
import ../COMMANDS.bend as Commands
import ../features/SPEC.bend as FeatureRequirements
import ../tasks/CONTRACT.bend as TaskRequirements

def mode_meaning(+assistant: Bool, +mode: D.OutputMode) ->
  {Actual.context_mode(assistant, mode) == Spec.required_context_mode(assistant, mode) : D.OutputMode}:
  match assistant:
    case True{}: {==}
    case False{}: {==}

def context_prepend(+producer: Nat, +operation: Nat, +mode: D.OutputMode, +part: Nat, +value: J.Json, +tail: +List<D.Message>) ->
  {D.ModelContext{D.OutputOrigin{producer, operation, part, Actual.context_output_mode(value, mode)}, value} <> tail ==
    D.ModelContext{D.OutputOrigin{producer, operation, part, Spec.context_mode(value, mode)}, value} <> tail : +List<D.Message>}:
  Equal.cong(D.OutputMode, +List<D.Message>, next => D.ModelContext{D.OutputOrigin{producer, operation, part, next}, value} <> tail,
    Actual.context_output_mode(value, mode), Spec.context_mode(value, mode),
    mode_meaning(String.eq(J.text(J.get(Content.provider_value(value), "type")), "message") && Content.provider_assistant(value), mode))

def messages(+producer: Nat, +operation: Nat, +mode: D.OutputMode, +items: +List<D.ModelItem>) ->
  {Actual.item_messages(producer, operation, mode, items) == Spec.required_messages(producer, operation, mode, items) : +List<D.Message>}:
  match items:
    case Nil{}: {==}
    case Con{D.Say{+part, +text}, +rest}:
      Equal.cong(+List<D.Message>, +List<D.Message>, tail => D.AssistantMessage{D.OutputOrigin{producer, operation, part, mode}, text} <> tail,
        Actual.item_messages(producer, operation, mode, rest), Spec.required_messages(producer, operation, mode, rest), messages(producer, operation, mode, rest))
    case Con{D.Invoke{+call}, +rest}:
      Equal.cong(+List<D.Message>, +List<D.Message>, tail => D.FunctionCall{call} <> tail,
        Actual.item_messages(producer, operation, mode, rest), Spec.required_messages(producer, operation, mode, rest), messages(producer, operation, mode, rest))
    case Con{D.Context{+part, +value}, +rest}:
      Equal.trans(+List<D.Message>,
        D.ModelContext{D.OutputOrigin{producer, operation, part, Actual.context_output_mode(value, mode)}, value} <> Actual.item_messages(producer, operation, mode, rest),
        D.ModelContext{D.OutputOrigin{producer, operation, part, Actual.context_output_mode(value, mode)}, value} <> Spec.required_messages(producer, operation, mode, rest),
        D.ModelContext{D.OutputOrigin{producer, operation, part, Spec.context_mode(value, mode)}, value} <> Spec.required_messages(producer, operation, mode, rest),
        Equal.cong(+List<D.Message>, +List<D.Message>, tail => D.ModelContext{D.OutputOrigin{producer, operation, part, Actual.context_output_mode(value, mode)}, value} <> tail,
          Actual.item_messages(producer, operation, mode, rest), Spec.required_messages(producer, operation, mode, rest), messages(producer, operation, mode, rest)),
        context_prepend(producer, operation, mode, part, value, Spec.required_messages(producer, operation, mode, rest)))

def origin_meaning(+task: D.Task) ->
  {Actual.request_output_origin(task, 0n) == Spec.required_origin(task) : D.OutputOrigin}:
  match task:
    case D.Task{id, lineage, contract, current, status, history, queued, +phase, operations, notified}:
      match phase:
        case D.ModelPending{operation, callable, mode}: {==}
        case D.ContextPending{ticket, revision, purpose}: {==}
        case D.Idle{}: {==}
        case D.Ready{calls}: {==}
        case D.ReasoningPending{ticket, revision}: {==}
        case D.HookPending{ticket, plugin, call, pending, remaining}: {==}

def reply_at_meaning(+origin: D.OutputOrigin, +items: +List<D.ModelItem>, +task: D.Task) ->
  {Actual.model_reply_at(origin, items, Actual.item_calls(items), task) == Spec.required_reply(True{}, origin, items, task) : D.Task}:
  match origin:
    case D.OutputOrigin{+producer, +operation, part, +mode}:
      Equal.cong(+List<D.Message>, D.Task,
        values => Actual.after_model(Actual.item_calls(items), D.with_history(D.history_append(values, D.task_history(task)), task)),
        Actual.item_messages(producer, operation, mode, items), Spec.required_messages(producer, operation, mode, items),
        messages(producer, operation, mode, items))

def reply_calculation_meaning(+items: +List<D.ModelItem>, +task: D.Task) ->
  {Actual.model_reply_calculation(items, Actual.item_calls(items), task) ==
    Spec.required_reply(True{}, Spec.required_origin(task), items, task) : D.Task}:
  Equal.trans(D.Task,
    Actual.model_reply_calculation(items, Actual.item_calls(items), task),
    Spec.required_reply(True{}, Actual.request_output_origin(task, 0n), items, task),
    Spec.required_reply(True{}, Spec.required_origin(task), items, task),
    reply_at_meaning(Actual.request_output_origin(task, 0n), items, task),
    Equal.cong(D.OutputOrigin, D.Task, origin => Spec.required_reply(True{}, origin, items, task),
      Actual.request_output_origin(task, 0n), Spec.required_origin(task), origin_meaning(task)))

def reply_admission_meaning(+allowed: +List<String>, +task: D.Task, +items: +List<D.ModelItem>, accepted: Bool,
  observed: {Actual.model_reply_permitted(allowed, task, Actual.ModelReplyCandidate{items}) == accepted : Bool}) ->
  {Actual.model_reply_admission(allowed, task, Categories.admit_checked(Actual.ModelReplyCandidate,
      candidate => Actual.model_reply_permitted(allowed, task, candidate), Actual.ModelReplyCandidate{items}, accepted, observed)) ==
    Spec.required_reply(accepted, Spec.required_origin(task), items, task) : D.Task}:
  match accepted:
    case False{}: {==}
    case True{}: reply_calculation_meaning(items, task)

def outcome_meaning(+outcome: D.Outcome, +allowed: +List<String>, +task: D.Task) ->
  {Actual.model_outcome(outcome, allowed, task) == Spec.required_outcome(outcome, allowed, task) : D.Task}:
  match outcome:
    case D.ModelReply{+items}:
      reply_admission_meaning(allowed, task, items,
        Actual.model_reply_permitted(allowed, task, Actual.ModelReplyCandidate{items}), {==})
    case D.ModelFailure{message}: {==}
    case D.ContextLimit{}: {==}

def commit_meaning(+task: D.Task, +outcome: D.Outcome, +allowed: +List<String>, +world: M.World()) ->
  {Protocol.model_result(task, outcome, allowed, world) == Spec.required_commit(task, outcome, allowed, world) : M.Decision()}:
  Equal.cong(D.Task, M.Decision(), next => Protocol.accepted_reaction(
      FeatureRequirements.react_outputs(~Commands.output_send, D.task_id(task),
        TaskRequirements.accepted_reply_outputs(outcome, allowed, task), Commands.replace(next, world))),
    Actual.model_outcome(outcome, allowed, task), Spec.required_outcome(outcome, allowed, task), outcome_meaning(outcome, allowed, task))

def completion_meaning(+status: D.Status, +expected: Nat, +allowed: +List<String>, mode: D.OutputMode,
  +task: D.Task, +ticket: Nat, +outcome: D.Outcome) ->
  {Protocol.model_phase(status, D.ModelPending{expected, allowed, mode}, task, ticket, outcome) ==
    Spec.required_completion(status, expected, allowed, task, ticket, outcome) : Protocol.ResolvedEvent}:
  match status:
    case D.Archived{}: {==}
    case D.Active{}: ProtocolProof.matching_calculation_semantics(ticket, expected, Protocol.ModelResult{task, outcome, allowed})
    case D.Frozen{}: ProtocolProof.matching_calculation_semantics(ticket, expected, Protocol.ModelResult{task, outcome, allowed})
    case D.Stopped{}: ProtocolProof.matching_calculation_semantics(ticket, expected, Protocol.ModelResult{task, outcome, allowed})

def model_resolution_meaning(+found: Maybe<&2, D.Task>, +ticket: Nat, +outcome: D.Outcome) ->
  {Protocol.model(found, ticket, outcome) == Spec.required_model(found, ticket, outcome) : Protocol.ResolvedEvent}:
  match found:
    case None{}: {==}
    case Some{D.Task{+id, +lineage, +contract, +current, +status, +history, +queued, +phase, +operations, +notified}}:
      match status phase:
        case +status D.ModelPending{+expected, +allowed, +mode}:
          completion_meaning(status, expected, allowed, mode,
            D.Task{id, lineage, contract, current, status, history, queued, D.ModelPending{expected, allowed, mode}, operations, notified}, ticket, outcome)
        case D.Active{} D.ContextPending{ticket, revision, purpose}: {==}
        case D.Active{} D.Idle{}: {==}
        case D.Active{} D.Ready{calls}: {==}
        case D.Active{} D.ReasoningPending{ticket, revision}: {==}
        case D.Active{} D.HookPending{ticket, plugin, call, pending, remaining}: {==}
        case D.Frozen{} D.ContextPending{ticket, revision, purpose}: {==}
        case D.Frozen{} D.Idle{}: {==}
        case D.Frozen{} D.Ready{calls}: {==}
        case D.Frozen{} D.ReasoningPending{ticket, revision}: {==}
        case D.Frozen{} D.HookPending{ticket, plugin, call, pending, remaining}: {==}
        case D.Stopped{} D.ContextPending{ticket, revision, purpose}: {==}
        case D.Stopped{} D.Idle{}: {==}
        case D.Stopped{} D.Ready{calls}: {==}
        case D.Stopped{} D.ReasoningPending{ticket, revision}: {==}
        case D.Stopped{} D.HookPending{ticket, plugin, call, pending, remaining}: {==}
        case D.Archived{} D.ContextPending{ticket, revision, purpose}: {==}
        case D.Archived{} D.Idle{}: {==}
        case D.Archived{} D.Ready{calls}: {==}
        case D.Archived{} D.ReasoningPending{ticket, revision}: {==}
        case D.Archived{} D.HookPending{ticket, plugin, call, pending, remaining}: {==}

def rejected_outcome(+items: +List<D.ModelItem>, +allowed: +List<String>, +task: D.Task,
  rejected: {Actual.model_reply_permitted(allowed, task, Actual.ModelReplyCandidate{items}) == False{} : Bool}) ->
  {Actual.model_outcome(D.ModelReply{items}, allowed, task) == Spec.rejected_reply(task) : D.Task}:
  Equal.trans(D.Task, Actual.model_outcome(D.ModelReply{items}, allowed, task),
    Spec.required_outcome(D.ModelReply{items}, allowed, task), Spec.rejected_reply(task),
    outcome_meaning(D.ModelReply{items}, allowed, task),
    Equal.cong(Bool, D.Task, accepted => Spec.required_reply(accepted, Spec.required_origin(task), items, task),
      Actual.model_reply_permitted(allowed, task, Actual.ModelReplyCandidate{items}), False{}, rejected))

def duplicate_text_rejected(+part: Nat, +text: String, +rest: +List<D.ModelItem>, +allowed: +List<String>, +task: D.Task,
  duplicate: {Actual.contains_part(rest, part) == True{} : Bool}) ->
  {Actual.model_outcome(D.ModelReply{D.Say{part, text} <> rest}, allowed, task) == Spec.rejected_reply(task) : D.Task}:
  rejected_outcome(D.Say{part, text} <> rest, allowed, task,
    Equal.cong(Bool, Bool, present => (Bool.not(present) && Actual.valid_parts(rest)) &&
      Actual.valid_calls(Actual.item_calls(D.Say{part, text} <> rest), allowed, D.task_history(task)),
      Actual.contains_part(rest, part), True{}, duplicate))

def duplicate_context_rejected(+part: Nat, +value: J.Json, +rest: +List<D.ModelItem>, +allowed: +List<String>, +task: D.Task,
  duplicate: {Actual.contains_part(rest, part) == True{} : Bool}) ->
  {Actual.model_outcome(D.ModelReply{D.Context{part, value} <> rest}, allowed, task) == Spec.rejected_reply(task) : D.Task}:
  rejected_outcome(D.Context{part, value} <> rest, allowed, task,
    Equal.cong(Bool, Bool, present => (Bool.not(present) && Actual.valid_parts(rest)) &&
      Actual.valid_calls(Actual.item_calls(D.Context{part, value} <> rest), allowed, D.task_history(task)),
      Actual.contains_part(rest, part), True{}, duplicate))

def rejected_outputs(+items: +List<D.ModelItem>, +allowed: +List<String>, +task: D.Task,
  rejected: {Actual.model_reply_permitted(allowed, task, Actual.ModelReplyCandidate{items}) == False{} : Bool}) ->
  {Actual.accepted_reply_outputs(D.ModelReply{items}, allowed, task) == Nil{} : +List<String>}:
  Equal.cong(Bool, +List<String>, accepted => Actual.permitted_reply_outputs(accepted, D.ModelReply{items}),
    Actual.model_reply_permitted(allowed, task, Actual.ModelReplyCandidate{items}), False{}, rejected)

def rejected_commit(+items: +List<D.ModelItem>, +allowed: +List<String>, +task: D.Task, +world: M.World(),
  rejected: {Actual.model_reply_permitted(allowed, task, Actual.ModelReplyCandidate{items}) == False{} : Bool}) ->
  {Protocol.model_result(task, D.ModelReply{items}, allowed, world) ==
    C.Decision{Commands.replace(Spec.rejected_reply(task), world), Protocol.acknowledgement(True{}), Nil{}} : M.Decision()}:
  Equal.trans(M.Decision(), Protocol.model_result(task, D.ModelReply{items}, allowed, world),
    Spec.required_commit(task, D.ModelReply{items}, allowed, world),
    C.Decision{Commands.replace(Spec.rejected_reply(task), world), Protocol.acknowledgement(True{}), Nil{}},
    commit_meaning(task, D.ModelReply{items}, allowed, world),
    Std.transport(Bool, False{},
      (accepted => {Protocol.accepted_reaction(FeatureRequirements.react_outputs(~Commands.output_send, D.task_id(task),
          TaskRequirements.permitted_outputs(accepted, D.ModelReply{items}),
          Commands.replace(Spec.required_reply(accepted, Spec.required_origin(task), items, task), world))) ==
        C.Decision{Commands.replace(Spec.rejected_reply(task), world), Protocol.acknowledgement(True{}), Nil{}} : M.Decision()}),
      {==}, Actual.model_reply_permitted(allowed, task, Actual.ModelReplyCandidate{items}), rejected))

def Spec.origin_boundary():
  Spec.OriginBoundary{producer => operation => mode => items => messages(producer, operation, mode, items),
    producer => operation => callable => mode => part => {==},
    producer => operation => mode => part => value => context_prepend(producer, operation, mode, part, value, Nil{}),
    outcome_meaning, commit_meaning, completion_meaning, model_resolution_meaning,
    duplicate_text_rejected, duplicate_context_rejected, rejected_outputs, rejected_commit}
