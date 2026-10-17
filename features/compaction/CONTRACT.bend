import Base
import ../../harness/compaction/MODEL.bend as Bounded
import ./MODEL.bend as A
import ./SPEC.bend as Spec
import ./PROGRAM.bend as Actual
import ../../harness/MODEL.bend as M
import ../../harness/DOMAIN.bend as D
import ../../bendlib/json.bend as J
import ../../harness/context/PROGRAM.bend as Context
import ../../bendlib/component.bend as C

def local_summary(+summary: String, +original: D.Task, change: Spec.Change) -> Type:
  match change:
    case Spec.Change{state, Some{written}, reserve, effects}:
      ({D.task_history(written) == Context.adopt(D.task_history(original), Context.portable(summary), D.task_history(original)) : D.History} &
       {reserve == False{} : Bool})
    case _: Empty

def accepted(decision: M.Decision()) -> Type:
  C.Decision{world, reply, effects} = decision
  {reply == D.success(J.Object{[J.Field{"accepted", J.Boolean{True{}}}]}) : J.Json}

type Boundary is Type:
  Boundary{
    meaning: @+change:Spec.Change -> @+world:M.World() ->
      {Actual.realize_calculation(change, world) == Spec.meaning(change, world) : M.Decision()},
    completion: @+completion:A.Completion -> @+world:M.World() ->
      {Actual.complete(completion, world) == Spec.meaning(Spec.resolve(completion, world), world) : M.Decision()},
    preparation: @+decision:M.Decision() -> {Actual.prepare(decision) == Spec.required_prepare(decision) : M.Decision()},
    supplied: @+summary:String -> @+task:D.Task -> @+world:M.World() ->
      ({Actual.supplied(summary, task, world) == Spec.meaning(Spec.supplied(summary, task, world), world) : M.Decision()} &
       local_summary(summary, task, Spec.supplied(summary, task, world)) & accepted(Actual.supplied(summary, task, world))),
    captured_watermark: @+snapshot:D.History -> @+entry:A.Entry -> @+measurement:A.Measurement ->
      ({A.current_revision(Spec.mark_finished(snapshot, entry, measurement)) == A.current_revision(entry) : Nat} &
       {A.maintained_revision(Spec.mark_finished(snapshot, entry, measurement)) == Nat.max(A.useful(snapshot), A.maintained_revision(entry)) : Nat}),
    late_reply: @+ticket:Nat -> @+expected:Nat -> @+snapshot:D.History -> @+model:D.Model -> @+reason:A.Reason ->
      @+progress:Bounded.State -> @+job_scope:String -> @+measurement:A.Measurement -> @+useful:Nat -> @+maintained:Nat -> @+attempted:Nat ->
      @+activity:Nat -> @+deadline:Nat -> @+cache:D.History -> @+scope:String -> @+task:D.Task -> @+value:J.Json -> @+error:Bool -> @+world:M.World() ->
      {Nat.is_eq(ticket, expected) == False{} : Bool} ->
      {Spec.compact_result(ticket, value, error, task,
        A.Entry{measurement, A.Compacting{expected, snapshot, model, reason, progress, job_scope}, useful, maintained, attempted, activity, deadline, cache, scope}, world) == Spec.Unchanged{} : Spec.Change}}
