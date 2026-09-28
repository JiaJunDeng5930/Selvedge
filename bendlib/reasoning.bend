import Base
import ./effects.bend as Effects
import ./component.bend as C
import ./domain.bend as D
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

def request(-StateRest: Data, -EffectRest: Data, +task: D.Task, world: C.Frame<D.State, StateRest>) -> C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>:
  C.Frame{D.State{tasks, next_task, +ticket, +environment, limits, projects}, +rest} = world
  D.Environment{catalog, profiles, forks, descendants, project, plugins} = environment
  +contract = D.task_contract(task)
  +tools = T.task_tools(contract)
  +allowed = T.callable(tools, catalog)
  next = D.with_phase(D.ModelPending{ticket, allowed}, task)
  C.Decision{C.Frame{D.State{T.replace(tasks, next), next_task, 1n+ticket, environment, limits, projects}, rest}, J.Null{},
    [Effects.RequestModel{D.task_id(task), ticket, T.task_model(contract), D.context_history(D.task_history(task)), tools, allowed, D.task_context(task)}]}

def evaluate(-StateRest: Data, -EffectRest: Data, +task: D.Task, world: C.Frame<D.State, StateRest>) -> C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>:
  C.Frame{D.State{tasks, next_task, +ticket, environment, limits, projects}, +rest} = world
  next = D.with_phase(D.ReasoningPending{ticket, D.history_length(D.task_history(task))}, task)
  C.Decision{C.Frame{D.State{T.replace(tasks, next), next_task, 1n+ticket, environment, limits, projects}, rest}, J.Null{},
    [Effects.RequestReasoning{D.task_id(task), ticket, T.task_model(D.task_contract(task)), D.task_history(task)}]}

def execute(-StateRest: Data, -EffectRest: Data, plan: R.Plan, task: D.Task, world: C.Frame<D.State, StateRest>) -> C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>:
  match plan:
    case R.FixedPlan{}: request(StateRest, EffectRest, task, world)
    case R.Evaluate{}: evaluate(StateRest, EffectRest, task, world)
    case R.Reuse{effort, remaining}: request(StateRest, EffectRest, Context.generation(effort, remaining, task), world)

def prepared(-StateRest: Data, -EffectRest: Data, +task: D.Task, world: C.Frame<D.State, StateRest>) -> C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>:
  execute(StateRest, EffectRest, route(Context.task_policy(task), Context.lease(D.task_history(task), D.task_id(task))), task, world)

def start(-StateRest: Data, -EffectRest: Data, task: D.Task, world: C.Frame<D.State, StateRest>) -> C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>:
  prepared(StateRest, EffectRest, Ops.publish(task), world)

def rejected(reason: String, task: D.Task) -> D.Task:
  T.promote(D.with_phase(D.Idle{}, D.append_message(D.FailureMessage{"Automatic reasoning: " ++ reason}, task)))

def chosen(accepted: Bool, effort: String, generations: Nat, +task: D.Task) -> D.Task:
  match accepted:
    case False{}: rejected("the evaluator selected an unsupported effort or lease; no model request was sent", task)
    case True{}:
      T.promote(D.with_phase(D.Ready{Nil{}},
        D.append_message(D.ReasoningRecord{D.task_id(task), effort, generations, False{}}, task)))

def observed(outcome: R.Outcome, +task: D.Task) -> D.Task:
  match outcome:
    case R.EvaluationFailed{reason}: rejected(reason, task)
    case R.Chosen{+effort, +generations}:
      chosen(R.accepts(Context.task_policy(task), effort, generations), effort, generations, task)

def revision_matches(current: Bool, outcome: R.Outcome, task: D.Task) -> D.Task:
  match current:
    case False{}: T.promote(D.with_phase(D.Ready{Nil{}}, task))
    case True{}: observed(outcome, task)

def complete(revision: Nat, outcome: R.Outcome, +task: D.Task) -> D.Task:
  revision_matches(Nat.is_eq(revision, D.history_length(D.task_history(task))), outcome, task)
