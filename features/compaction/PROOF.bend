import Base
import ../../harness/context/selection-proof.bend as ContextProof
import ../../harness/compaction/PROOF.bend as BoundedProof
import ./MODEL.bend as A
import ./STATE.bend as State
import ./SPEC.bend as Spec
import ./PROGRAM.bend as Actual
import ./CONTRACT.bend as Contract
import ../../harness/MODEL.bend as M
import ../../harness/DOMAIN.bend as D
import ../../harness/compaction/MODEL.bend as Bounded
import ../../bendlib/categories.bend as Categories
import ../../bendlib/json.bend as J

def meaning(+change: Spec.Change, +world: M.World()) ->
  {Actual.realize_calculation(change, world) == Spec.meaning(change, world) : M.Decision()}:
  match change:
    case Spec.Unchanged{}: {==}
    case Spec.Change{state, None{}, False{}, effects}: {==}
    case Spec.Change{state, None{}, True{}, effects}: {==}
    case Spec.Change{state, Some{task}, False{}, effects}: {==}
    case Spec.Change{state, Some{task}, True{}, effects}: {==}

def completion(+completion: A.Completion, +world: M.World()) ->
  {Actual.complete(completion, world) == Spec.meaning(Spec.resolve(completion, world), world) : M.Decision()}:
  meaning(Spec.resolve(completion, world), world)

def supplied(+summary: String, +task: D.Task, +world: M.World()) ->
  ({Actual.supplied(summary, task, world) == Spec.meaning(Spec.supplied(summary, task, world), world) : M.Decision()} &
   Contract.local_summary(summary, task, Spec.supplied(summary, task, world)) & Contract.accepted(Actual.supplied(summary, task, world))):
  match task:
    case D.Task{+id, +lineage, +contract, +current, +status, +history, +queued, +phase, +operations, +notified}:
      +original: D.Task = D.Task{id, lineage, contract, current, status, history, queued, phase, operations, notified}
      (meaning(Spec.supplied(summary, original, world), world), ({==}, {==}), {==})

def captured_watermark(+snapshot: D.History, +entry: A.Entry, +measurement: A.Measurement) ->
  ({A.current_revision(Spec.mark_finished(snapshot, entry, measurement)) == A.current_revision(entry) : Nat} &
   {A.maintained_revision(Spec.mark_finished(snapshot, entry, measurement)) == Nat.max(A.useful(snapshot), A.maintained_revision(entry)) : Nat}):
  match entry:
    case A.Entry{previous, job, useful, maintained, attempted, activity, deadline, cache, scope}: ({==}, {==})

def late_reply(+ticket: Nat, +expected: Nat, +snapshot: D.History, +model: D.Model, +reason: A.Reason,
  +progress: Bounded.State, +job_scope: String, +measurement: A.Measurement, +useful: Nat, +maintained: Nat, +attempted: Nat,
  +activity: Nat, +deadline: Nat, +cache: D.History, +scope: String, +task: D.Task, +value: J.Json, +error: Bool, +world: M.World(),
  stale: {Nat.is_eq(ticket, expected) == False{} : Bool}) ->
  {Spec.compact_result(ticket, value, error, task,
    A.Entry{measurement, A.Compacting{expected, snapshot, model, reason, progress, job_scope}, useful, maintained, attempted, activity, deadline, cache, scope}, world) == Spec.Unchanged{} : Spec.Change}:
  Equal.cong(Bool, Spec.Change,
    same => Spec.compact_matched(same, job_scope, snapshot, model, reason, progress, value, error, task,
      A.Entry{measurement, A.Compacting{expected, snapshot, model, reason, progress, job_scope}, useful, maintained, attempted, activity, deadline, cache, scope}, world),
    Nat.is_eq(ticket, expected), False{}, stale)

def synchronize(+tasks: +List<D.Task>, +decision: M.Decision()) ->
  {Actual.synchronize(tasks, decision) == Spec.synchronize_all(tasks, decision) : M.Decision()}:
  match tasks:
    case Nil{}: {==}
    case Con{+task, +rest}:
      +current = Spec.decision_world(decision)
      +change = Spec.synchronize(task, current)
      +actual = Spec.combine(decision, Actual.realize_calculation(change, current))
      +required = Spec.combine(decision, Spec.meaning(change, current))
      Equal.trans(M.Decision(), Actual.synchronize(rest, actual), Spec.synchronize_all(rest, actual), Spec.synchronize_all(rest, required),
        synchronize(rest, actual),
        Equal.cong(M.Decision(), M.Decision(), next => Spec.synchronize_all(rest, next), actual, required,
          Equal.cong(M.Decision(), M.Decision(), value => Spec.combine(decision, value),
            Actual.realize_calculation(change, current), Spec.meaning(change, current), meaning(change, current))))

def preparation(+decision: M.Decision()) ->
  {Actual.prepare(decision) == Spec.required_prepare(decision) : M.Decision()}:
  +tasks = State.tasks(Spec.decision_world(decision))
  +actual = Actual.synchronize(tasks, decision)
  +required = Spec.synchronize_all(tasks, decision)
  Equal.trans(M.Decision(),
    Spec.combine(actual, Actual.realize_calculation(Spec.arm(State.registry(Spec.decision_world(actual))), Spec.decision_world(actual))),
    Spec.combine(actual, Spec.meaning(Spec.arm(State.registry(Spec.decision_world(actual))), Spec.decision_world(actual))),
    Spec.combine(required, Spec.meaning(Spec.arm(State.registry(Spec.decision_world(required))), Spec.decision_world(required))),
    Equal.cong(M.Decision(), M.Decision(), value => Spec.combine(actual, value),
      Actual.realize_calculation(Spec.arm(State.registry(Spec.decision_world(actual))), Spec.decision_world(actual)),
      Spec.meaning(Spec.arm(State.registry(Spec.decision_world(actual))), Spec.decision_world(actual)),
      meaning(Spec.arm(State.registry(Spec.decision_world(actual))), Spec.decision_world(actual))),
    Equal.cong(M.Decision(), M.Decision(), +value => Spec.combine(value, Spec.meaning(Spec.arm(State.registry(Spec.decision_world(value))), Spec.decision_world(value))),
      actual, required, synchronize(tasks, decision)))

def boundary() -> Contract.Boundary:
  Contract.Boundary{meaning, completion, preparation, supplied, captured_watermark, late_reply}
