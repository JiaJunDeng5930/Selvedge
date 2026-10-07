import Base
import ../features/MODEL.bend as F
import ../DOMAIN.bend as D
import ../MODEL.bend as M
import ./MODEL.bend as R
import ../../bendlib/json.bend as J
import ../tasks/PROGRAM.bend as T
import ./context.bend as Context
import ./PROGRAM.bend as Actual
import ./SPEC.bend as Spec
import ../protocol/PROGRAM.bend as Protocol

law route_meaning:
  for +policy: R.Policy
  for +lease: R.Lease
  {Actual.route(policy, lease) == R.requirement(policy, lease) : R.Plan}

law start_meaning:
  for +task: D.Task
  for +world: M.World()
  {Actual.start(F.State(), F.Effect, task, world) == Spec.start(F.State(), F.Effect, task, world) : M.Decision()}

law completion_meaning:
  for +revision: Nat
  for +outcome: R.Outcome
  for +task: D.Task
  {Actual.complete(revision, outcome, task) == Spec.complete(revision, outcome, task) : D.Task}

# The callback is merely a proposed bounded lease. The production start and
# settlement are fixed above; this structure cannot be instantiated with a
# different scheduler or an always-refusing substitute. Quality of the model's
# choice and the Jev/HTTP/tokenizer boundaries are not propositions here.
type ReasoningBoundary is Type:
  ReasoningBoundary{
    routing: @+policy:R.Policy -> @+lease:R.Lease ->
      {Actual.route(policy, lease) == R.requirement(policy, lease) : R.Plan},
    sampling: @+task:D.Task -> @+world:M.World() ->
      {Actual.start(F.State(), F.Effect, task, world) == Spec.start(F.State(), F.Effect, task, world) : M.Decision()},
    settlement: @+revision:Nat -> @+outcome:R.Outcome -> @+task:D.Task ->
      {Actual.complete(revision, outcome, task) == Spec.complete(revision, outcome, task) : D.Task},
    fixed_bypass: @lease:R.Lease -> {Actual.route(R.Fixed{}, lease) == R.FixedPlan{} : R.Plan},
    supported_lease: @+effort:String -> @+remaining:Nat ->
      {R.supported(True{}, effort, remaining) == R.Reuse{effort, remaining} : R.Plan},
    unsupported_lease: @effort:String -> @remaining:Nat ->
      {R.supported(False{}, effort, remaining) == R.Evaluate{} : R.Plan},
    admissible_choice: @evaluator:String -> @+efforts:+List<String> -> @baseline:String -> @transport:R.Transport ->
      @+maximum:Nat -> @+effort:String -> @+generations:Nat ->
      {R.accepts(R.Adaptive{evaluator, efforts, baseline, transport, maximum}, effort, generations) ==
        (R.member(efforts, effort) && ((Nat.is_eq(generations, 1n) || Nat.is_eq(generations, 2n) ||
          Nat.is_eq(generations, 5n) || Nat.is_eq(generations, 10n)) && Nat.is_le(generations, maximum))) : Bool},
    record_identity: @history:D.History -> @+owner:Nat -> @+record_owner:Nat -> @+effort:String -> @+remaining:Nat -> @sampling:Bool ->
      {Context.lease(D.HistoryNode{history, D.ReasoningRecord{record_owner, effort, remaining, sampling}}, owner) ==
        Context.recorded(Nat.is_eq(owner, record_owner), effort, remaining) : R.Lease},
    foreign_record: @effort:String -> @remaining:Nat -> {Context.recorded(False{}, effort, remaining) == R.NoLease{} : R.Lease},
    stale_result: @outcome:R.Outcome -> @+task:D.Task ->
      {Actual.revision_matches(False{}, outcome, task) == T.promote(D.with_phase(D.Ready{Nil{}}, task)) : D.Task},
    completion_ticket: @+expected:Nat -> @+revision:Nat -> @+task:D.Task -> @+ticket:Nat -> @+outcome:R.Outcome ->
      {Protocol.reasoning_phase(D.Active{}, D.ReasoningPending{expected, revision}, task, ticket, outcome) ==
        Protocol.matching(Nat.is_eq(ticket, expected), Protocol.ReasoningResult{task, revision, outcome}) : Protocol.ResolvedEvent},
    archived_completion: @phase:D.Phase -> @task:D.Task -> @ticket:Nat -> @outcome:R.Outcome ->
      {Protocol.reasoning_phase(D.Archived{}, phase, task, ticket, outcome) == Protocol.Ignore{} : Protocol.ResolvedEvent},
    new_input: @history:D.History -> @text:String -> @owner:Nat ->
      {Context.lease(D.HistoryNode{history, D.UserMessage{text}}, owner) == R.NoLease{} : R.Lease},
    tool_failure: @history:D.History -> @call:String -> @value:J.Json -> @owner:Nat ->
      {Context.lease(D.HistoryNode{history, D.FunctionOutput{call, value, True{}}}, owner) == R.NoLease{} : R.Lease},
    failure: @history:D.History -> @text:String -> @owner:Nat ->
      {Context.lease(D.HistoryNode{history, D.FailureMessage{text}}, owner) == R.NoLease{} : R.Lease},
    checkpoint: @history:D.History -> @summary:String -> @owner:Nat ->
      {Context.lease(D.HistoryNode{history, D.ContextCheckpoint{summary}}, owner) == R.NoLease{} : R.Lease},
    checkpoint_update: @history:D.History -> @summary:String ->
      {Context.last_update(D.HistoryNode{history, D.ContextCheckpoint{summary}}) == None{} : Maybe<&2, String>},
    baseline: @evaluator:String -> @efforts:+List<String> -> @+baseline:String -> @maximum:Nat -> @effective:String ->
      {R.request_effort(R.Adaptive{evaluator, efforts, baseline, R.ConfigurationUpdates{}, maximum}, effective) == baseline : String},
    sample_frame: @+effort:String -> @+remaining:Nat -> @+owner:Nat -> @+history:D.History ->
      {Context.sampling_history(False{}, effort, remaining, owner, history) ==
        D.HistoryNode{history, D.ReasoningRecord{owner, effort, remaining, True{}}} : D.History},
    update_frame: @+effort:String -> @+remaining:Nat -> @+owner:Nat -> @+history:D.History ->
      {Context.sampling_history(True{}, effort, remaining, owner, history) ==
        D.HistoryNode{D.HistoryNode{Context.separate(Context.trailing_update(history), history),
          D.ReasoningRecord{owner, effort, remaining, True{}}}, D.ConfigurationUpdate{effort}} : D.History},
    separator_frame: @+history:D.History ->
      {Context.separate(True{}, history) == D.HistoryNode{history, D.FailureMessage{
        "The previous generation has no retained output after its configuration update; continuing from the committed request prefix."}} : D.History},
    frozen_contract: @effort:String -> @remaining:Nat -> @+task:D.Task ->
      {D.task_contract(Context.generation(effort, remaining, task)) == D.task_contract(task) : D.Contract},
    private_continuation: @secret:J.Json -> @+summary:+List<J.Json> -> @+tail:+List<J.Json> ->
      {Context.public_context_named("reasoning", J.Object{[J.Field{"encrypted_content", secret}, J.Field{"summary", J.Array{summary}}]}, tail) ==
        (J.Object{[J.Field{"role", J.Text{"reasoning_summary"}}, J.Field{"content", J.Array{Context.public_parts(summary)}}]} <> tail) : +List<J.Json>},
    private_field: @secret:J.Json ->
      {Context.public_field("encrypted_content", secret) == J.Field{"encrypted_content", J.Text{"[Private provider continuation omitted]"}} : J.Field},
    public_tool_result: @+id:String -> @+value:J.Json -> @+error:Bool -> @+tail:+List<J.Json> ->
      {Context.public_message(D.FunctionOutput{id, value, error}, tail) ==
        (J.Object{[J.Field{"role", J.Text{"function_output"}}, J.Field{"call_id", J.Text{id}},
          J.Field{"content", Context.public_value(512n, value)}, J.Field{"is_error", J.Boolean{error}}]} <> tail) : +List<J.Json>}
  }

law reasoning_boundary:
  ReasoningBoundary
