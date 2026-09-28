import Base
import ../MODEL.bend as M
import ../REASONING.bend as R
import ./reasoning-context.bend as Context
import ./json.bend as J
import ./tasks.bend as T
import ./operations.bend as Ops

# This specification does not import the production router or evaluator
# settlement. It fixes the complete successor and ordered effect list. Context
# projection and generation records are shared domain primitives with their own
# frame, privacy and lease properties in the reasoning boundary.
def model(+task: M.Task, world: M.World) -> M.Decision:
  M.World{tasks, next_task, +ticket, M.Environment{+catalog, profiles, forks, descendants, project, plugins}, limits, projects} = world
  +tools = T.task_tools(M.task_contract(task))
  +allowed = T.callable(tools, catalog)
  M.Decision{M.World{T.replace(tasks, M.with_phase(M.ModelPending{ticket, allowed}, task)), next_task, 1n+ticket,
    M.Environment{catalog, profiles, forks, descendants, project, plugins}, limits, projects}, J.Null{},
    [M.RequestModel{M.task_id(task), ticket, T.task_model(M.task_contract(task)),
      M.context_history(M.task_history(task)), tools, allowed, M.task_context(task)}]}

def evaluator(+task: M.Task, world: M.World) -> M.Decision:
  M.World{tasks, next_task, +ticket, environment, limits, projects} = world
  M.Decision{M.World{T.replace(tasks, M.with_phase(M.ReasoningPending{ticket, M.history_length(M.task_history(task))}, task)),
    next_task, 1n+ticket, environment, limits, projects}, J.Null{},
    [M.RequestReasoning{M.task_id(task), ticket, T.task_model(M.task_contract(task)), M.task_history(task)}]}

def required(plan: R.Plan, task: M.Task, world: M.World) -> M.Decision:
  match plan:
    case R.FixedPlan{}: model(task, world)
    case R.Evaluate{}: evaluator(task, world)
    case R.Reuse{effort, remaining}: model(Context.generation(effort, remaining, task), world)

def prepared(+task: M.Task, world: M.World) -> M.Decision:
  required(R.requirement(Context.task_policy(task), Context.lease(M.task_history(task), M.task_id(task))), task, world)

def start(task: M.Task, world: M.World) -> M.Decision:
  prepared(Ops.publish(task), world)

def failure(reason: String, task: M.Task) -> M.Task:
  T.promote(M.with_phase(M.Idle{}, M.append_message(M.FailureMessage{"Automatic reasoning: " ++ reason}, task)))

def selection(accepted: Bool, effort: String, generations: Nat, +task: M.Task) -> M.Task:
  match accepted:
    case True{}:
      T.promote(M.with_phase(M.Ready{Nil{}}, M.append_message(M.ReasoningRecord{M.task_id(task), effort, generations, False{}}, task)))
    case False{}: failure("the evaluator selected an unsupported effort or lease; no model request was sent", task)

def outcome(value: R.Outcome, +task: M.Task) -> M.Task:
  match value:
    case R.Chosen{+effort, +generations}: selection(R.accepts(Context.task_policy(task), effort, generations), effort, generations, task)
    case R.EvaluationFailed{reason}: failure(reason, task)

def fresh(current: Bool, observation: R.Outcome, task: M.Task) -> M.Task:
  match current:
    case True{}: outcome(observation, task)
    case False{}: T.promote(M.with_phase(M.Ready{Nil{}}, task))

def complete(revision: Nat, observation: R.Outcome, +task: M.Task) -> M.Task:
  fresh(Nat.is_eq(revision, M.history_length(M.task_history(task))), observation, task)
