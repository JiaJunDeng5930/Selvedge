import Base
import ../../bendlib/categories.bend as Categories
import ../../bendlib/effects.bend as Effects
import ../../bendlib/component.bend as C
import ../DOMAIN.bend as D
import ./MODEL.bend as R
import ./context.bend as Context
import ../../bendlib/json.bend as J
import ../tasks/PROGRAM.bend as T
import ../execution/OPERATIONS.bend as Ops

def live_lease(policy: R.Policy, lease: R.Lease) -> R.Plan:
  match lease:
    case R.Lease{+effort, 1n+remaining}: R.supported(R.allowed(policy, effort), effort, remaining)
    case _: R.Evaluate{}

def route(policy: R.Policy, lease: R.Lease) -> R.Plan:
  match policy:
    case R.Fixed{}: R.FixedPlan{}
    case R.Adaptive{evaluator, efforts, baseline, transport, maximum}:
      live_lease(R.Adaptive{evaluator, efforts, baseline, transport, maximum}, lease)

def request_environment(-StateRest: Data, -EffectRest: Data, +task: D.Task, world: C.Frame<D.State, StateRest>, environment_value: D.Environment) -> C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>:
  match world environment_value:
    case C.Frame{+task_state, +rest} D.Environment{catalog, profiles, forks, descendants, project, plugins, instructions}:
      tasks = D.state_tasks(task_state)
      +ticket = D.state_next_ticket(task_state)
      +contract = D.task_contract(task)
      +tools = T.task_tools(contract)
      +allowed = T.callable(tools, catalog)
      next = D.with_phase(D.ModelPending{ticket, allowed, D.history_output_mode(D.task_history(task))}, task)
      C.Decision{C.Frame{D.with_state_next_ticket(1n+ticket, D.with_state_tasks(T.replace(tasks, next), task_state)), rest}, J.Null{},
        [Effects.RequestModel{D.task_id(task), ticket, D.task_model(task), D.task_history(task), tools, allowed, D.task_context(task), "", 0n}]}

def request(-StateRest: Data, -EffectRest: Data, +task: D.Task, +world: C.Frame<D.State, StateRest>) -> C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>:
  request_environment(StateRest, EffectRest, task, world, D.state_environment(C.local(D.State, StateRest, world)))

def evaluate(-StateRest: Data, -EffectRest: Data, +task: D.Task, world: C.Frame<D.State, StateRest>) -> C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>:
  C.Frame{+task_state, +rest} = world
  tasks = D.state_tasks(task_state)
  +ticket = D.state_next_ticket(task_state)
  next = D.with_phase(D.ReasoningPending{ticket, D.history_length(D.task_history(task))}, task)
  C.Decision{C.Frame{D.with_state_next_ticket(1n+ticket, D.with_state_tasks(T.replace(tasks, next), task_state)), rest}, J.Null{},
    [Effects.RequestReasoning{D.task_id(task), ticket, D.task_model(task), D.task_history(task)}]}

def execute(-StateRest: Data, -EffectRest: Data, plan: R.Plan, task: D.Task, world: C.Frame<D.State, StateRest>) -> C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>:
  match plan:
    case R.FixedPlan{}: request(StateRest, EffectRest, task, world)
    case R.Evaluate{}: evaluate(StateRest, EffectRest, task, world)
    case R.Reuse{effort, remaining}: request(StateRest, EffectRest, Context.generation(effort, remaining, task), world)

def prepared(-StateRest: Data, -EffectRest: Data, +task: D.Task, world: C.Frame<D.State, StateRest>) -> C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>:
  execute(StateRest, EffectRest, route(Context.task_policy(task), Context.lease(D.task_history(task), D.task_id(task))), task, world)

# Source reads are committed effects. Their accepted callback records changes
# before allocating the model request that carries the resulting history.
def observe_context(-StateRest: Data, -EffectRest: Data, +task: D.Task, +purpose: D.ContextPurpose, world: C.Frame<D.State, StateRest>) -> C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>:
  C.Frame{+task_state, +rest} = world
  +ticket = D.state_next_ticket(task_state)
  next = D.with_notified(False{}, D.with_phase(D.ContextPending{ticket, D.history_length(D.task_history(task)), purpose}, task))
  C.Decision{C.Frame{D.with_state_next_ticket(1n+ticket, D.with_state_tasks(T.replace(D.state_tasks(task_state), next), task_state)), rest},
    D.success(J.Object{[J.Field{"task_id", J.nat(D.task_id(task))}]}),
    [Effects.ObserveContext{D.task_id(task), ticket, D.task_history(task), D.task_context(task)}]}

def summary(-StateRest: Data, -EffectRest: Data, task: D.Task, world: C.Frame<D.State, StateRest>) -> C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>:
  C.Decision{T.update_world(StateRest, D.with_phase(D.Idle{}, task), world), J.Null{}, Nil{}}

def observed_context(outcome: Result<&2, &2, String, +List<D.ContextObservation()>>, task: D.Task) -> D.Task:
  match outcome:
    case Done{observations}: D.apply_context_observations(task, observations)
    case Fail{reason}: D.diagnose_context("Context observation failed; retaining accepted context: " ++ reason, task)

def context_suspended(purpose: D.ContextPurpose, task: D.Task) -> D.Task:
  match purpose:
    case D.GenerateContext{}: T.promote(D.with_phase(D.Ready{Nil{}}, task))
    case D.SummaryContext{}:
      T.promote(D.with_phase(D.Idle{}, D.append_message(D.FailureMessage{"Context summary was not sent because the task is frozen or stopped; original history retained"}, task)))

def context_active(-StateRest: Data, -EffectRest: Data, status: D.Status, +purpose: D.ContextPurpose, task: D.Task, world: C.Frame<D.State, StateRest>) -> C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>:
  match status:
    case D.Active{}:
      match purpose:
        case D.GenerateContext{}: prepared(StateRest, EffectRest, task, world)
        case D.SummaryContext{}: summary(StateRest, EffectRest, task, world)
    case _: C.Decision{T.update_world(StateRest, context_suspended(purpose, task), world), J.Null{}, Nil{}}

def context_continue(-StateRest: Data, -EffectRest: Data, purpose: D.ContextPurpose, +task: D.Task, world: C.Frame<D.State, StateRest>) -> C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>:
  context_active(StateRest, EffectRest, D.task_status(task), purpose, task, world)

def context_retry(-StateRest: Data, -EffectRest: Data, status: D.Status, purpose: D.ContextPurpose,
  task: D.Task, world: C.Frame<D.State, StateRest>) -> C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>:
  match status:
    case D.Active{}: observe_context(StateRest, EffectRest, task, purpose, world)
    case _: C.Decision{T.update_world(StateRest, context_suspended(purpose, task), world), J.Null{}, Nil{}}

# Other completions may append history while sources are being read. Retry from
# the new prefix rather than applying a patch proposed for the older baseline.
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

def rejected(reason: String, task: D.Task) -> D.Task:
  T.promote(D.with_phase(D.Idle{}, D.append_message(D.FailureMessage{"Automatic reasoning: " ++ reason}, task)))

def chosen_permitted(+task: D.Task, outcome: R.Outcome) -> Bool:
  match outcome:
    case R.Chosen{effort, generations}: R.accepts(Context.task_policy(task), effort, generations)
    case _: False{}

def chosen_calculation(effort: String, generations: Nat, +task: D.Task) -> D.Task:
  T.promote(D.with_phase(D.Ready{Nil{}},
    D.append_message(D.ReasoningRecord{D.task_id(task), effort, generations, False{}}, task)))

def chosen(+task: D.Task, member: Categories.Membership<R.Outcome, Categories.holds(R.Outcome, outcome => chosen_permitted(task, outcome))>) -> D.Task:
  Categories.Membership{outcome, evidence} = member
  match outcome:
    case R.Chosen{effort, generations}: chosen_calculation(effort, generations, task)
    case _: rejected("the evaluator selected an unsupported effort or lease; no model request was sent", task)

def chosen_admission(+task: D.Task, result: Maybe<&1, Categories.Membership<R.Outcome, Categories.holds(R.Outcome, outcome => chosen_permitted(task, outcome))>>) -> D.Task:
  match result:
    case Some{member}: chosen(task, member)
    case None{}: rejected("the evaluator selected an unsupported effort or lease; no model request was sent", task)

def observed(outcome: R.Outcome, +task: D.Task) -> D.Task:
  match outcome:
    case R.EvaluationFailed{reason}: rejected(reason, task)
    case R.Chosen{effort, generations}:
      chosen_admission(task, Categories.admit(R.Outcome, outcome => chosen_permitted(task, outcome), R.Chosen{effort, generations}))

def revision_current(+revision: Nat, task: D.Task) -> Bool:
  Nat.is_eq(revision, D.history_length(D.task_history(task)))

def stale_result(outcome: R.Outcome, task: D.Task) -> D.Task:
  T.promote(D.with_phase(D.Ready{Nil{}}, task))

def revision_matches(+revision: Nat, outcome: R.Outcome, member: Categories.Membership<D.Task, Categories.holds(D.Task, task => revision_current(revision, task))>) -> D.Task:
  Categories.Membership{task, evidence} = member
  observed(outcome, task)

def revision_admission(+revision: Nat, outcome: R.Outcome, task: D.Task, result: Maybe<&1, Categories.Membership<D.Task, Categories.holds(D.Task, task => revision_current(revision, task))>>) -> D.Task:
  match result:
    case Some{member}: revision_matches(revision, outcome, member)
    case None{}: stale_result(outcome, task)

def complete(+revision: Nat, outcome: R.Outcome, +task: D.Task) -> D.Task:
  revision_admission(revision, outcome, task, Categories.admit(D.Task, task => revision_current(revision, task), task))
