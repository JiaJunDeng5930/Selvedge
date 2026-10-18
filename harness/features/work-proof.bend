import Base
import ../../features/work/MODEL.bend as W
import ../../features/work/SPEC.bend as WorkSpec
import ../../features/work/PROGRAM.bend as WorkProgram
import ../../features/work/PROOF.bend as WorkProof
import ../../bendlib/component.bend as C
import ../../bendlib/json.bend as J
import ../DOMAIN.bend as D
import ../MODEL.bend as M
import ./MODEL.bend as F
import ./work-state.bend as State
import ./SPEC.bend as Spec

def assembled(+change: W.Change, +world: M.World()) ->
  {State.embed(WorkProgram.realize_calculation(change, State.registry(world)), world) ==
   State.embed(WorkSpec.meaning(change, State.registry(world)), world) : M.Decision()}:
  Equal.cong(C.Decision<W.State, Unit>, M.Decision(), value => State.embed(value, world),
    WorkProgram.realize_calculation(change, State.registry(world)), WorkSpec.meaning(change, State.registry(world)),
    WorkProof.refinement(change, State.registry(world)))

def birth(+accepted: Bool, +work: Nat, +task: Nat, +original: M.World(), +decision: M.Decision()) ->
  {State.accepted_birth(accepted, work, task, original, decision) == Spec.work_birth(accepted, work, task, original, decision) : M.Decision()}:
  match accepted decision:
    case False{} C.Decision{world, reply, effects}: {==}
    case True{} C.Decision{world, reply, effects}: {==}

def created(+work: Nat, +task: Nat, +original: M.World(), +decision: M.Decision()) ->
  {State.born(work, task, original, decision) == Spec.work_created(work, task, original, decision) : M.Decision()}:
  C.Decision{world, +reply, effects} = decision
  birth(J.boolean(J.get(reply, "ok")), work, task, original, C.Decision{world, reply, effects})
