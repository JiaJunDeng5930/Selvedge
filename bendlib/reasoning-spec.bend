import Base
import ./effects.bend as Effects
import ./component.bend as C
import ./domain.bend as D
import ../REASONING.bend as R
import ./reasoning-context.bend as Context
import ./json.bend as J
import ./tasks.bend as T
import ./operations.bend as Ops

# This specification does not import the production router or evaluator
# settlement. It fixes the complete successor and ordered effect list. Context
# projection and generation records are shared domain primitives with their own
# frame, privacy and lease properties in the reasoning boundary.
def model(-StateRest: Data, -EffectRest: Data, +task: D.Task, world: C.Frame<D.State, StateRest>) -> C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>:
  C.Frame{D.State{tasks, next_task, +ticket, D.Environment{+catalog, profiles, forks, descendants, project, plugins}, limits, projects}, +rest} = world
  +tools = T.task_tools(D.task_contract(task))
  +allowed = T.callable(tools, catalog)
  C.Decision{C.Frame{D.State{T.replace(tasks, D.with_phase(D.ModelPending{ticket, allowed}, task)), next_task, 1n+ticket, D.Environment{catalog, profiles, forks, descendants, project, plugins}, limits, projects}, rest}, J.Null{},
    [Effects.RequestModel{D.task_id(task), ticket, T.task_model(D.task_contract(task)),
      D.context_history(D.task_history(task)), tools, allowed, D.task_context(task)}]}

def evaluator(-StateRest: Data, -EffectRest: Data, +task: D.Task, world: C.Frame<D.State, StateRest>) -> C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>:
  C.Frame{D.State{tasks, next_task, +ticket, environment, limits, projects}, +rest} = world
  C.Decision{C.Frame{D.State{T.replace(tasks, D.with_phase(D.ReasoningPending{ticket, D.history_length(D.task_history(task))}, task)), next_task, 1n+ticket, environment, limits, projects}, rest}, J.Null{},
    [Effects.RequestReasoning{D.task_id(task), ticket, T.task_model(D.task_contract(task)), D.task_history(task)}]}

def required(-StateRest: Data, -EffectRest: Data, plan: R.Plan, task: D.Task, world: C.Frame<D.State, StateRest>) -> C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>:
  match plan:
    case R.FixedPlan{}: model(StateRest, EffectRest, task, world)
    case R.Evaluate{}: evaluator(StateRest, EffectRest, task, world)
    case R.Reuse{effort, remaining}: model(StateRest, EffectRest, Context.generation(effort, remaining, task), world)

def prepared(-StateRest: Data, -EffectRest: Data, +task: D.Task, world: C.Frame<D.State, StateRest>) -> C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>:
  required(StateRest, EffectRest, R.requirement(Context.task_policy(task), Context.lease(D.task_history(task), D.task_id(task))), task, world)

def start(-StateRest: Data, -EffectRest: Data, task: D.Task, world: C.Frame<D.State, StateRest>) -> C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>:
  prepared(StateRest, EffectRest, Ops.publish(task), world)

def failure(reason: String, task: D.Task) -> D.Task:
  T.promote(D.with_phase(D.Idle{}, D.append_message(D.FailureMessage{"Automatic reasoning: " ++ reason}, task)))

def selection(accepted: Bool, effort: String, generations: Nat, +task: D.Task) -> D.Task:
  match accepted:
    case True{}:
      T.promote(D.with_phase(D.Ready{Nil{}}, D.append_message(D.ReasoningRecord{D.task_id(task), effort, generations, False{}}, task)))
    case False{}: failure("the evaluator selected an unsupported effort or lease; no model request was sent", task)

def outcome(value: R.Outcome, +task: D.Task) -> D.Task:
  match value:
    case R.Chosen{+effort, +generations}: selection(R.accepts(Context.task_policy(task), effort, generations), effort, generations, task)
    case R.EvaluationFailed{reason}: failure(reason, task)

def fresh(current: Bool, observation: R.Outcome, task: D.Task) -> D.Task:
  match current:
    case True{}: outcome(observation, task)
    case False{}: T.promote(D.with_phase(D.Ready{Nil{}}, task))

def complete(revision: Nat, observation: R.Outcome, +task: D.Task) -> D.Task:
  fresh(Nat.is_eq(revision, D.history_length(D.task_history(task))), observation, task)
