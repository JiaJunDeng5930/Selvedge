import Base
import ./effects.bend as Effects
import ../FEATURES.bend as F
import ./component.bend as C
import ./domain.bend as D
import ../BOARD.bend as Board
import ../MODEL.bend as M
import ../APPROVALS.bend as A
import ../PROGRAM.bend as P
import ./tasks.bend as T
import ./operations.bend as Ops
import ./protocol.bend as Protocol
import ./json.bend as J

# These properties name the executing dispatcher, resolver and scheduler. The
# effect type distinguishes a tool-free review from a task's model/tool effects.
type ApprovalBoundary is Type:
  ApprovalBoundary{
    realization: @+resolution:A.Resolution -> @+world:M.World() ->
      {P.review_result(resolution, world) == A.meaning(F.State(), F.Effect, resolution, world) : M.Decision()},
    human_waits: @call:D.Call -> @remaining:+List<D.Attempt> -> @task:D.Task -> @world:M.World() ->
      {P.decision_effects(P.approval_request(D.HumanReviewer{}, call, remaining, task, world)) == Nil{} : +List<M.Effect()>},
    model_waits: @+profile:D.Profile -> @+call:D.Call -> @+remaining:+List<D.Attempt> -> @+task:D.Task ->
      @tasks:+List<D.Task> -> @next_task:Nat -> @+ticket:Nat -> @environment:D.Environment -> @limits:D.ExecutionLimits -> @projects:D.Projects -> @board:F.State() ->
      {P.decision_effects(P.approval_request(D.ModelReviewer{profile}, call, remaining, task,
        C.Frame{D.State{tasks, next_task, ticket, environment, limits, projects}, board})) ==
        [Effects.RequestApproval{D.task_id(T.promote(Ops.awaiting(ticket, D.ModelReviewer{profile}, call, remaining, task))), ticket, profile, call,
          D.task_context(T.promote(Ops.awaiting(ticket, D.ModelReviewer{profile}, call, remaining, task))),
          D.task_history(T.promote(Ops.awaiting(ticket, D.ModelReviewer{profile}, call, remaining, task)))}] : +List<M.Effect()>},
    grant_preserves_context: @operation:D.Operation() -> @reviewer:D.ApprovalReviewer -> @reason:String -> @+task:D.Task ->
      {D.task_context(A.permitted(operation, reviewer, reason, task)) == D.task_context(task) : D.TaskContext},
    origin_separation: ((@profile:D.Profile -> @operation:D.Operation() -> @task:D.Task -> @outcome:D.ApprovalOutcome ->
        {A.pending(D.ApprovalPending{D.ModelReviewer{profile}}, A.HumanDecision{}, operation, task, outcome) == A.stale(A.HumanDecision{}) : A.Resolution}) &
      (@operation:D.Operation() -> @task:D.Task -> @outcome:D.ApprovalOutcome ->
        {A.pending(D.ApprovalPending{D.HumanReviewer{}}, A.ModelDecision{}, operation, task, outcome) == A.Ignore{} : A.Resolution})),
    consumed_grant: @reviewer:D.ApprovalReviewer -> @+origin:A.Origin -> @operation:D.Operation() -> @task:D.Task -> @outcome:D.ApprovalOutcome ->
      {A.pending(D.ApprovalGranted{reviewer}, origin, operation, task, outcome) == A.stale(origin) : A.Resolution},
    no_premature_callback: @id:Nat -> @call:D.Call -> @announced:Bool -> @reviewer:D.ApprovalReviewer ->
      @task:D.Task -> @value:J.Json -> @error:Bool ->
      {Protocol.tool_operation(Some{(id, D.OperationBody{call, announced, D.ApprovalPending{reviewer}})}, task, value, error) == Protocol.Ignore{} : Protocol.Event},
    frozen_owner: @id:Nat -> @lineage:+List<Nat> -> @contract:D.Contract -> @history:D.History -> @queued:+List<String> ->
      @phase:D.Phase -> @operations:+List<D.Operation()> -> @notified:Bool ->
      {D.task_work(D.Task{id, lineage, contract, D.Frozen{}, history, queued, phase, operations, notified}) == D.NoWork{} : D.Work}
  }

law approval_boundary:
  ApprovalBoundary
