import Base
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
    realization: @+resolution:A.Resolution -> @+world:M.World ->
      {P.review_result(resolution, world) == A.meaning(resolution, world) : M.Decision},
    human_waits: @call:M.Call -> @remaining:+List<M.Attempt> -> @task:M.Task -> @world:M.World ->
      {P.decision_effects(P.approval_request(M.HumanReviewer{}, call, remaining, task, world)) == Nil{} : +List<M.Effect>},
    model_waits: @+profile:M.Profile -> @+call:M.Call -> @+remaining:+List<M.Attempt> -> @+task:M.Task ->
      @tasks:+List<M.Task> -> @next_task:Nat -> @+ticket:Nat -> @environment:M.Environment -> @limits:M.ExecutionLimits -> @projects:M.Projects ->
      {P.decision_effects(P.approval_request(M.ModelReviewer{profile}, call, remaining, task,
        M.World{tasks, next_task, ticket, environment, limits, projects})) ==
        [M.RequestApproval{M.task_id(T.promote(Ops.awaiting(ticket, M.ModelReviewer{profile}, call, remaining, task))), ticket, profile, call,
          M.task_context(T.promote(Ops.awaiting(ticket, M.ModelReviewer{profile}, call, remaining, task))),
          M.task_history(T.promote(Ops.awaiting(ticket, M.ModelReviewer{profile}, call, remaining, task)))}] : +List<M.Effect>},
    grant_preserves_context: @operation:M.Operation() -> @reviewer:M.ApprovalReviewer -> @reason:String -> @+task:M.Task ->
      {M.task_context(A.permitted(operation, reviewer, reason, task)) == M.task_context(task) : M.TaskContext},
    origin_separation: ((@profile:M.Profile -> @operation:M.Operation() -> @task:M.Task -> @outcome:M.ApprovalOutcome ->
        {A.pending(M.ApprovalPending{M.ModelReviewer{profile}}, A.HumanDecision{}, operation, task, outcome) == A.stale(A.HumanDecision{}) : A.Resolution}) &
      (@operation:M.Operation() -> @task:M.Task -> @outcome:M.ApprovalOutcome ->
        {A.pending(M.ApprovalPending{M.HumanReviewer{}}, A.ModelDecision{}, operation, task, outcome) == A.Ignore{} : A.Resolution})),
    consumed_grant: @reviewer:M.ApprovalReviewer -> @+origin:A.Origin -> @operation:M.Operation() -> @task:M.Task -> @outcome:M.ApprovalOutcome ->
      {A.pending(M.ApprovalGranted{reviewer}, origin, operation, task, outcome) == A.stale(origin) : A.Resolution},
    no_premature_callback: @id:Nat -> @call:M.Call -> @announced:Bool -> @reviewer:M.ApprovalReviewer ->
      @task:M.Task -> @value:J.Json -> @error:Bool ->
      {Protocol.tool_operation(Some{(id, M.OperationBody{call, announced, M.ApprovalPending{reviewer}})}, task, value, error) == Protocol.Ignore{} : Protocol.Event},
    frozen_owner: @id:Nat -> @lineage:+List<Nat> -> @contract:M.Contract -> @history:M.History -> @queued:+List<String> ->
      @phase:M.Phase -> @operations:+List<M.Operation()> -> @notified:Bool ->
      {M.task_work(M.Task{id, lineage, contract, M.Frozen{}, history, queued, phase, operations, notified}) == M.NoWork{} : M.Work}
  }

law approval_boundary:
  ApprovalBoundary
