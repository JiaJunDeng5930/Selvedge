import Base
import ../MODEL.bend as M
import ../REASONING.bend as R
import ./reasoning-context.bend as Context
import ./json.bend as J
import ./tasks.bend as T
import ./operations.bend as Ops

def live_lease(policy: R.Policy, lease: R.Lease) -> R.Plan:
  match lease:
    case R.Lease{+effort, 1n+remaining}: R.supported(R.allowed(policy, effort), effort, remaining)
    case _: R.Evaluate{}

def route(policy: R.Policy, lease: R.Lease) -> R.Plan:
  match policy:
    case R.Fixed{}: R.FixedPlan{}
    case R.Adaptive{evaluator, efforts, baseline, transport, maximum}:
      live_lease(R.Adaptive{evaluator, efforts, baseline, transport, maximum}, lease)

def request(+task: M.Task, world: M.World) -> M.Decision:
  M.World{tasks, next_task, +ticket, +environment, limits, projects, board} = world
  M.Environment{catalog, profiles, forks, descendants, project, plugins} = environment
  +contract = M.task_contract(task)
  +tools = T.task_tools(contract)
  +allowed = T.callable(tools, catalog)
  next = M.with_phase(M.ModelPending{ticket, allowed}, task)
  M.Decision{M.World{T.replace(tasks, next), next_task, 1n+ticket, environment, limits, projects, board}, J.Null{},
    [M.RequestModel{M.task_id(task), ticket, T.task_model(contract), M.context_history(M.task_history(task)), tools, allowed, M.task_context(task)}]}

def evaluate(+task: M.Task, world: M.World) -> M.Decision:
  M.World{tasks, next_task, +ticket, environment, limits, projects, board} = world
  next = M.with_phase(M.ReasoningPending{ticket, M.history_length(M.task_history(task))}, task)
  M.Decision{M.World{T.replace(tasks, next), next_task, 1n+ticket, environment, limits, projects, board}, J.Null{},
    [M.RequestReasoning{M.task_id(task), ticket, T.task_model(M.task_contract(task)), M.task_history(task)}]}

def execute(plan: R.Plan, task: M.Task, world: M.World) -> M.Decision:
  match plan:
    case R.FixedPlan{}: request(task, world)
    case R.Evaluate{}: evaluate(task, world)
    case R.Reuse{effort, remaining}: request(Context.generation(effort, remaining, task), world)

def prepared(+task: M.Task, world: M.World) -> M.Decision:
  execute(route(Context.task_policy(task), Context.lease(M.task_history(task), M.task_id(task))), task, world)

def start(task: M.Task, world: M.World) -> M.Decision:
  prepared(Ops.publish(task), world)

def rejected(reason: String, task: M.Task) -> M.Task:
  T.promote(M.with_phase(M.Idle{}, M.append_message(M.FailureMessage{"Automatic reasoning: " ++ reason}, task)))

def chosen(accepted: Bool, effort: String, generations: Nat, +task: M.Task) -> M.Task:
  match accepted:
    case False{}: rejected("the evaluator selected an unsupported effort or lease; no model request was sent", task)
    case True{}:
      T.promote(M.with_phase(M.Ready{Nil{}},
        M.append_message(M.ReasoningRecord{M.task_id(task), effort, generations, False{}}, task)))

def observed(outcome: R.Outcome, +task: M.Task) -> M.Task:
  match outcome:
    case R.EvaluationFailed{reason}: rejected(reason, task)
    case R.Chosen{+effort, +generations}:
      chosen(R.accepts(Context.task_policy(task), effort, generations), effort, generations, task)

def revision_matches(current: Bool, outcome: R.Outcome, task: M.Task) -> M.Task:
  match current:
    case False{}: T.promote(M.with_phase(M.Ready{Nil{}}, task))
    case True{}: observed(outcome, task)

def complete(revision: Nat, outcome: R.Outcome, +task: M.Task) -> M.Task:
  revision_matches(Nat.is_eq(revision, M.history_length(M.task_history(task))), outcome, task)
