import Base
import ../../MODEL.bend as M
import ../../PROGRAM.bend as P
import ../../LAWS.bend as Laws
import ../tasks.bend as T
import ../stdlib.bend as Std
import ../execution.bend as Execution
import ./protocol.bend as ProtocolProof

# Local proof obligations for the execution boundary. No runtime policy lives here.

def Laws.execution_semantics(action, world):
  match action world:
    case Execution.Rest{} _: {==}
    case Execution.Idle{task} M.World{tasks, next_task, ticket, environment, limits}: {==}
    case Execution.Model{task} M.World{tasks, next_task, ticket, M.Environment{catalog, profiles, max_fork, max_descendants, project}, limits}: {==}
    case Execution.Summary{task, resume} M.World{tasks, next_task, ticket, environment, limits}: {==}
    case Execution.External{tool, call, remaining, task} M.World{tasks, next_task, ticket, environment, limits}: {==}
    case Execution.Internal{operation, call, remaining, task} _:
      Laws.invocation_semantics(operation, call, remaining, task, world)
    case Execution.Failure{code, reason, call, remaining, task} M.World{tasks, next_task, ticket, environment, limits}: {==}

def Laws.work_semantics(work, task, world):
  Laws.execution_semantics(Execution.resolve(work, task, world), world)

def combination_semantics(+before: M.Decision, +after: M.Decision) ->
  {P.combine(before, after) == Execution.combine(before, after) : M.Decision}:
  match before after:
    case M.Decision{old, reply, effects} M.Decision{world, ignored, added}: {==}

def combined_work_semantics(+task: M.Task, +decision: M.Decision) ->
  {P.combine(decision, P.work(M.task_work(task), task, P.decision_world(decision))) ==
    Execution.combine(decision, Execution.work(M.task_work(task), task, Execution.world(decision))) : M.Decision}:
  +work = M.task_work(task)
  +world = P.decision_world(decision)
  +actual = P.work(work, task, world)
  +expected = Execution.work(work, task, world)
  Equal.trans(M.Decision, P.combine(decision, actual), Execution.combine(decision, actual), Execution.combine(decision, expected),
    combination_semantics(decision, actual),
    Equal.cong(M.Decision, M.Decision, (value => Execution.combine(decision, value)), actual, expected, Laws.work_semantics(work, task, world)))

def Scheduling(fuel: Nat) -> Type:
  @+candidate:Maybe<&2, M.Task> -> @+decision:M.Decision ->
    {P.schedule(fuel, candidate, decision) == Execution.schedule(fuel, candidate, decision) : M.Decision}

def scheduling_zero(+candidate: Maybe<&2, M.Task>, +decision: M.Decision) ->
  {P.schedule(0n, candidate, decision) == Execution.schedule(0n, candidate, decision) : M.Decision}:
  match candidate decision:
    case None{} _: {==}
    case Some{task} M.Decision{world, reply, effects}: {==}

def scheduling_successor(+fuel: Nat, induction: Scheduling(fuel), +candidate: Maybe<&2, M.Task>, +decision: M.Decision) ->
  {P.schedule(1n+fuel, candidate, decision) == Execution.schedule(1n+fuel, candidate, decision) : M.Decision}:
  match candidate:
    case None{}: {==}
    case Some{+task}:
      +work = M.task_work(task)
      +world = P.decision_world(decision)
      +actual = P.combine(decision, P.work(work, task, world))
      +expected = Execution.combine(decision, Execution.work(work, task, world))
      +following = T.runnable(P.tasks(P.decision_world(actual)))
      Equal.trans(M.Decision, P.schedule(fuel, following, actual), Execution.schedule(fuel, following, actual),
        Execution.schedule(fuel, T.runnable(P.tasks(P.decision_world(expected))), expected), induction(following, actual),
        Equal.cong(M.Decision, M.Decision,
          (+value => Execution.schedule(fuel, T.runnable(P.tasks(P.decision_world(value))), value)),
          actual, expected, combined_work_semantics(task, decision)))

def Laws.schedule_semantics(fuel, candidate, decision):
  Std.nat_ind(~Scheduling, ~scheduling_zero,
    ~(fuel => induction => +candidate => +decision => scheduling_successor(fuel, induction, candidate, decision)), fuel)(candidate, decision)

def Laws.scheduling_semantics(enabled, decision):
  match enabled:
    case False{}: {==}
    case True{}:
      Laws.schedule_semantics(P.scheduling_budget(P.decision_world(decision)), T.runnable(P.tasks(P.decision_world(decision))), decision)

def Laws.scheduling_disabled(decision):
  {==}

def Laws.scheduling_enabled(decision):
  {==}

def Laws.scheduling_idle(fuel, decision):
  match fuel:
    case 0n: {==}
    case 1n+p: {==}

def Laws.scheduling_exhausted(task, world, reply, effects):
  {==}

def Laws.scheduling_progress(fuel, task, decision):
  {==}

def Laws.scheduling_combines_outputs(old, reply, effects, next, ignored, added):
  {==}

def Laws.model_work(task, world):
  {==}

def Laws.tool_work(task, world):
  {==}

def Laws.idle_work(task, world):
  match world:
    case M.World{tasks, next_task, next_ticket, environment, limits}: {==}

def Laws.no_work(task, world):
  {==}

def Laws.model_dispatch(task, tasks, next_task, ticket, catalog, profiles, max_fork, max_descendants, project, limits):
  {==}

def Laws.tool_dispatch(tool, call, remaining, task, tasks, next_task, ticket, environment, limits):
  {==}

def Laws.small_context_dispatch(task, world):
  {==}

def Laws.large_context_dispatch(task, world):
  {==}
