import Base
import ../../bendlib/effects.bend as Effects
import ../../bendlib/component.bend as C
import ../DOMAIN.bend as D
import ./MODEL.bend as R
import ./context.bend as Context
import ../../bendlib/json.bend as J
import ../tasks/PROGRAM.bend as T
import ../execution/OPERATIONS.bend as Ops

# This specification does not import the production router or evaluator
# settlement. It fixes the complete successor and ordered effect list. Context
# projection and generation records are shared domain primitives with their own
# frame, privacy and lease properties in the reasoning boundary.
def model_environment(-StateRest: Data, -EffectRest: Data, +task: D.Task, world: C.Frame<D.State, StateRest>, environment_value: D.Environment) -> C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>:
  match world environment_value:
    case C.Frame{+task_state, +rest} D.Environment{+catalog, profiles, forks, descendants, project, plugins, instructions}:
      tasks = D.state_tasks(task_state)
      +ticket = D.state_next_ticket(task_state)
      +tools = T.task_tools(D.task_contract(task))
      +allowed = T.callable(tools, catalog)
      C.Decision{C.Frame{D.with_state_next_ticket(1n+ticket, D.with_state_tasks(T.replace(tasks, D.with_phase(D.ModelPending{ticket, allowed}, task)), task_state)), rest}, J.Null{},
        [Effects.RequestModel{D.task_id(task), ticket, T.task_model(D.task_contract(task)),
          D.context_history(D.task_history(task)), tools, allowed, D.task_context(task)}]}

def model(-StateRest: Data, -EffectRest: Data, +task: D.Task, +world: C.Frame<D.State, StateRest>) -> C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>:
  model_environment(StateRest, EffectRest, task, world, D.state_environment(C.local(D.State, StateRest, world)))

def evaluator(-StateRest: Data, -EffectRest: Data, +task: D.Task, world: C.Frame<D.State, StateRest>) -> C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>:
  C.Frame{+task_state, +rest} = world
  tasks = D.state_tasks(task_state)
  +ticket = D.state_next_ticket(task_state)
  C.Decision{C.Frame{D.with_state_next_ticket(1n+ticket, D.with_state_tasks(T.replace(tasks, D.with_phase(D.ReasoningPending{ticket, D.history_length(D.task_history(task))}, task)), task_state)), rest}, J.Null{},
    [Effects.RequestReasoning{D.task_id(task), ticket, T.task_model(D.task_contract(task)), D.task_history(task)}]}

def required(-StateRest: Data, -EffectRest: Data, plan: R.Plan, task: D.Task, world: C.Frame<D.State, StateRest>) -> C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>:
  match plan:
    case R.FixedPlan{}: model(StateRest, EffectRest, task, world)
    case R.Evaluate{}: evaluator(StateRest, EffectRest, task, world)
    case R.Reuse{effort, remaining}: model(StateRest, EffectRest, Context.generation(effort, remaining, task), world)

def prepared(-StateRest: Data, -EffectRest: Data, +task: D.Task, world: C.Frame<D.State, StateRest>) -> C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>:
  required(StateRest, EffectRest, R.requirement(Context.task_policy(task), Context.lease(D.task_history(task), D.task_id(task))), task, world)

def observe_context(-StateRest: Data, -EffectRest: Data, +task: D.Task, +purpose: D.ContextPurpose, world: C.Frame<D.State, StateRest>) -> C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>:
  C.Frame{+task_state, +rest} = world
  +ticket = D.state_next_ticket(task_state)
  next = D.with_notified(False{}, D.with_phase(D.ContextPending{ticket, D.history_length(D.task_history(task)), purpose}, task))
  C.Decision{C.Frame{D.with_state_next_ticket(1n+ticket, D.with_state_tasks(T.replace(D.state_tasks(task_state), next), task_state)), rest},
    D.success(J.Object{[J.Field{"task_id", J.nat(D.task_id(task))}]}),
    [Effects.ObserveContext{D.task_id(task), ticket, D.task_history(task), D.task_context(task)}]}

def summary(-StateRest: Data, -EffectRest: Data, task: D.Task, resume: Bool, world: C.Frame<D.State, StateRest>) -> C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>:
  C.Frame{+task_state, +rest} = world
  +task = D.append_message(D.UserMessage{D.summary_instructions()}, task)
  +ticket = D.state_next_ticket(task_state)
  next = D.with_notified(False{}, D.with_phase(D.SummaryPending{ticket, resume}, task))
  C.Decision{C.Frame{D.with_state_next_ticket(1n+ticket, D.with_state_tasks(T.replace(D.state_tasks(task_state), next), task_state)), rest},
    D.success(J.Object{[J.Field{"task_id", J.nat(D.task_id(task))}]}),
    [Effects.RequestSummary{D.task_id(task), ticket, T.task_model(D.task_contract(task)), D.context_history(D.task_history(task)), D.task_context(task)}]}

def observed_context(outcome: Result<&2, &2, String, +List<D.ContextObservation()>>, task: D.Task) -> D.Task:
  match outcome:
    case Done{observations}: D.apply_context_observations(task, observations)
    case Fail{reason}: D.diagnose_context("Context observation failed; retaining accepted context: " ++ reason, task)

def context_suspended(purpose: D.ContextPurpose, task: D.Task) -> D.Task:
  match purpose:
    case D.GenerateContext{}: T.promote(D.with_phase(D.Ready{Nil{}}, task))
    case D.SummaryContext{resume}:
      T.promote(D.with_phase(D.Idle{}, D.append_message(D.FailureMessage{"Context summary was not sent because the task is frozen or stopped; original history retained"}, task)))

def context_active(-StateRest: Data, -EffectRest: Data, status: D.Status, +purpose: D.ContextPurpose, task: D.Task, world: C.Frame<D.State, StateRest>) -> C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>:
  match status:
    case D.Active{}:
      match purpose:
        case D.GenerateContext{}: prepared(StateRest, EffectRest, task, world)
        case D.SummaryContext{resume}: summary(StateRest, EffectRest, task, resume, world)
    case _: C.Decision{T.update_world(StateRest, context_suspended(purpose, task), world), J.Null{}, Nil{}}

def context_continue(-StateRest: Data, -EffectRest: Data, purpose: D.ContextPurpose, +task: D.Task, world: C.Frame<D.State, StateRest>) -> C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>:
  context_active(StateRest, EffectRest, D.task_status(task), purpose, task, world)

def context_retry(-StateRest: Data, -EffectRest: Data, status: D.Status, purpose: D.ContextPurpose,
  task: D.Task, world: C.Frame<D.State, StateRest>) -> C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>:
  match status:
    case D.Active{}: observe_context(StateRest, EffectRest, task, purpose, world)
    case _: C.Decision{T.update_world(StateRest, context_suspended(purpose, task), world), J.Null{}, Nil{}}

def context_fresh(-StateRest: Data, -EffectRest: Data, current: Bool, purpose: D.ContextPurpose,
  outcome: Result<&2, &2, String, +List<D.ContextObservation()>>, +task: D.Task, world: C.Frame<D.State, StateRest>) -> C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>:
  match current:
    case False{}: context_retry(StateRest, EffectRest, D.task_status(task), purpose, task, world)
    case True{}: context_continue(StateRest, EffectRest, purpose, observed_context(outcome, task), world)

def context_acknowledged(-StateRest: Data, -EffectRest: Data,
  decision: C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>) -> C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>:
  C.Decision{world, reply, effects} = decision
  C.Decision{world, D.success(J.Object{[J.Field{"accepted", J.Boolean{True{}}}]}), effects}

def context_completed(-StateRest: Data, -EffectRest: Data, revision: Nat, purpose: D.ContextPurpose,
  outcome: Result<&2, &2, String, +List<D.ContextObservation()>>, +task: D.Task, world: C.Frame<D.State, StateRest>) -> C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>:
  context_acknowledged(StateRest, EffectRest, context_fresh(StateRest, EffectRest, Nat.is_eq(revision, D.history_length(D.task_history(task))), purpose, outcome, task, world))

def start(-StateRest: Data, -EffectRest: Data, task: D.Task, world: C.Frame<D.State, StateRest>) -> C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>:
  observe_context(StateRest, EffectRest, Ops.publish(task), D.GenerateContext{}, world)

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
