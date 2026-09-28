import Base
import ../component.bend as C
import ../domain.bend as D
import ../../MODEL.bend as M
import ../../APPROVALS.bend as A
import ../../PROGRAM.bend as P
import ../../LAWS.bend as Laws
import ../approval-architecture.bend as Boundary
import ./protocol.bend as ProtocolProof
import ../operations.bend as Ops

def human_waits(call:D.Call, remaining:+List<D.Attempt>, task:D.Task, world:M.World()) ->
  {P.decision_effects(P.approval_request(D.HumanReviewer{}, call, remaining, task, world)) == Nil{} : +List<M.Effect()>}:
  C.Frame{D.State{tasks, next_task, ticket, environment, limits, projects}, +board} = world
  {==}

def context_frame(operation:D.Operation(), reviewer:D.ApprovalReviewer, reason:String, +task:D.Task) ->
  {D.task_context(A.permitted(operation, reviewer, reason, task)) == D.task_context(task) : D.TaskContext}:
  D.Task{id, lineage, contract, status, history, queued, phase, operations, notified} = task
  {==}

def Boundary.approval_boundary():
  Boundary.ApprovalBoundary{
    (resolution => world => Laws.review_semantics(resolution, world)),
    (call => remaining => task => world => human_waits(call, remaining, task, world)),
    (profile => call => remaining => task => tasks => next_task => ticket => environment => limits => projects => board => {==}),
    (operation => reviewer => reason => task => context_frame(operation, reviewer, reason, task)),
    ((profile => operation => task => outcome => {==}), (operation => task => outcome => {==})),
    (reviewer => origin => operation => task => outcome => {==}),
    (id => call => announced => reviewer => task => value => error => {==}),
    (id => lineage => contract => history => queued => phase => operations => notified => {==})}
