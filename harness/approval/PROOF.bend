import Base
import ../../bendlib/component.bend as C
import ../DOMAIN.bend as D
import ../MODEL.bend as M
import ./MODEL.bend as A
import ../PROGRAM.bend as P
import ../LAWS.bend as Laws
import ./CONTRACT.bend as Boundary
import ../protocol/PROOF.bend as ProtocolProof
import ../execution/OPERATIONS.bend as Ops

def human_waits(call:D.Call, remaining:+List<D.Attempt>, task:D.Task, world:M.World()) ->
  {P.decision_effects(P.approval_request(D.HumanReviewer{}, call, remaining, task, world)) == Nil{} : +List<M.Effect()>}:
  C.Frame{core, +board} = world
  {==}

def context_frame(operation:D.Operation(), reviewer:D.ApprovalReviewer, reason:String, +task:D.Task) ->
  {D.task_context(A.permitted(operation, reviewer, reason, task)) == D.task_context(task) : D.TaskContext}:
  D.Task{id, lineage, contract, status, history, queued, phase, operations, notified} = task
  {==}

def Boundary.approval_boundary():
  Boundary.ApprovalBoundary{
    (resolution => world => Laws.review_semantics(resolution, world)),
    (call => remaining => task => world => human_waits(call, remaining, task, world)),
    (profile => call => remaining => task => state => board => {==}),
    (operation => reviewer => reason => task => context_frame(operation, reviewer, reason, task)),
    ((profile => operation => task => outcome => {==}), (operation => task => outcome => {==})),
    (reviewer => origin => operation => task => outcome => {==}),
    (id => call => announced => reviewer => task => value => error => {==}),
    (id => lineage => contract => history => queued => phase => operations => notified => {==})}
