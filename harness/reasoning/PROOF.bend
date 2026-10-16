import Base
import ../../bendlib/categories.bend as Categories
import ../../bendlib/component.bend as C
import ../DOMAIN.bend as D
import ../../bendlib/effects.bend as Effects
import ./MODEL.bend as R
import ./PROGRAM.bend as Actual
import ./SPEC.bend as Spec
import ./context.bend as Context
import ../execution/OPERATIONS.bend as Ops
import ../features/MODEL.bend as F
import ./CONTRACT.bend as A
import ../LAWS.bend as Laws

def route_meaning(+policy: R.Policy, +lease: R.Lease) ->
  {Actual.route(policy, lease) == R.requirement(policy, lease) : R.Plan}:
  match policy lease:
    case R.Fixed{} _: {==}
    case R.Adaptive{evaluator, efforts, baseline, transport, maximum} R.NoLease{}: {==}
    case R.Adaptive{evaluator, efforts, baseline, transport, maximum} R.Lease{effort, 0n}: {==}
    case R.Adaptive{evaluator, efforts, baseline, transport, maximum} R.Lease{effort, 1n+remaining}: {==}

def request_meaning(-StateRest: Data, -EffectRest: Data, +task: D.Task, +world: C.Frame<D.State, StateRest>) ->
  {Actual.request(StateRest, EffectRest, task, world) == Spec.model(StateRest, EffectRest, task, world) : C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>}:
  match world:
    case C.Frame{D.State{tasks, next_task, ticket, D.Environment{catalog, profiles, forks, descendants, project, plugins, instructions}, limits, projects}, rest}: {==}

def evaluator_meaning(-StateRest: Data, -EffectRest: Data, +task: D.Task, +world: C.Frame<D.State, StateRest>) ->
  {Actual.evaluate(StateRest, EffectRest, task, world) == Spec.evaluator(StateRest, EffectRest, task, world) : C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>}:
  match world:
    case C.Frame{D.State{tasks, next_task, ticket, environment, limits, projects}, rest}: {==}

def execution_meaning(-StateRest: Data, -EffectRest: Data, +plan: R.Plan, +task: D.Task, +world: C.Frame<D.State, StateRest>) ->
  {Actual.execute(StateRest, EffectRest, plan, task, world) == Spec.required(StateRest, EffectRest, plan, task, world) : C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>}:
  match plan:
    case R.FixedPlan{}: request_meaning(StateRest, EffectRest, task, world)
    case R.Evaluate{}: evaluator_meaning(StateRest, EffectRest, task, world)
    case R.Reuse{effort, remaining}: request_meaning(StateRest, EffectRest, Context.generation(effort, remaining, task), world)

def prepared_meaning(-StateRest: Data, -EffectRest: Data, +task: D.Task, +world: C.Frame<D.State, StateRest>) ->
  {Actual.prepared(StateRest, EffectRest, task, world) == Spec.prepared(StateRest, EffectRest, task, world) : C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>}:
  +policy = Context.task_policy(task)
  +lease = Context.lease(D.task_history(task), D.task_id(task))
  +actual = Actual.route(policy, lease)
  +required = R.requirement(policy, lease)
  Equal.trans(C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>,
    Actual.execute(StateRest, EffectRest, actual, task, world), Actual.execute(StateRest, EffectRest, required, task, world), Spec.required(StateRest, EffectRest, required, task, world),
    Equal.cong(R.Plan, C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>,
      plan => Actual.execute(StateRest, EffectRest, plan, task, world), actual, required, route_meaning(policy, lease)),
    execution_meaning(StateRest, EffectRest, required, task, world))

def observe_meaning(-StateRest: Data, -EffectRest: Data, task: D.Task, purpose: D.ContextPurpose, world: C.Frame<D.State, StateRest>) ->
  {Actual.observe_context(StateRest, EffectRest, task, purpose, world) == Spec.observe_context(StateRest, EffectRest, task, purpose, world) : C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>}:
  match world:
    case C.Frame{D.State{tasks, next_task, ticket, environment, limits, projects}, rest}: {==}

def context_active_meaning(-StateRest: Data, -EffectRest: Data, +status: D.Status, +purpose: D.ContextPurpose, +task: D.Task, +world: C.Frame<D.State, StateRest>) ->
  {Actual.context_active(StateRest, EffectRest, status, purpose, task, world) == Spec.context_active(StateRest, EffectRest, status, purpose, task, world) : C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>}:
  match status purpose:
    case D.Active{} D.GenerateContext{}: prepared_meaning(StateRest, EffectRest, task, world)
    case D.Active{} D.SummaryContext{resume}:
      match world:
        case C.Frame{D.State{tasks, next_task, ticket, environment, limits, projects}, rest}: {==}
    case D.Frozen{} D.GenerateContext{}: {==}
    case D.Frozen{} D.SummaryContext{resume}: {==}
    case D.Stopped{} D.GenerateContext{}: {==}
    case D.Stopped{} D.SummaryContext{resume}: {==}
    case D.Archived{} D.GenerateContext{}: {==}
    case D.Archived{} D.SummaryContext{resume}: {==}

def context_retry_meaning(-StateRest: Data, -EffectRest: Data, +status: D.Status, purpose: D.ContextPurpose,
  task: D.Task, world: C.Frame<D.State, StateRest>) ->
  {Actual.context_retry(StateRest, EffectRest, status, purpose, task, world) == Spec.context_retry(StateRest, EffectRest, status, purpose, task, world) : C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>}:
  match status:
    case D.Active{}: observe_meaning(StateRest, EffectRest, task, purpose, world)
    case D.Frozen{}:
      match purpose:
        case D.GenerateContext{}: {==}
        case D.SummaryContext{resume}: {==}
    case D.Stopped{}:
      match purpose:
        case D.GenerateContext{}: {==}
        case D.SummaryContext{resume}: {==}
    case D.Archived{}:
      match purpose:
        case D.GenerateContext{}: {==}
        case D.SummaryContext{resume}: {==}

def context_fresh_meaning(-StateRest: Data, -EffectRest: Data, +current: Bool, +purpose: D.ContextPurpose,
  +outcome: Result<&2, &2, String, +List<D.ContextObservation()>>, +task: D.Task, +world: C.Frame<D.State, StateRest>) ->
  {Actual.context_fresh(StateRest, EffectRest, current, purpose, outcome, task, world) == Spec.context_fresh(StateRest, EffectRest, current, purpose, outcome, task, world) : C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>}:
  match current:
    case False{}: context_retry_meaning(StateRest, EffectRest, D.task_status(task), purpose, task, world)
    case True{}:
      match outcome:
        case Done{observations}:
          +updated = D.apply_context_observations(task, observations)
          context_active_meaning(StateRest, EffectRest, D.task_status(updated), purpose, updated, world)
        case Fail{reason}:
          +updated = D.diagnose_context("Context observation failed; retaining accepted context: " ++ reason, task)
          context_active_meaning(StateRest, EffectRest, D.task_status(updated), purpose, updated, world)

def context_acknowledged_meaning(-StateRest: Data, -EffectRest: Data,
  decision: C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>) ->
  {Actual.context_acknowledged(StateRest, EffectRest, decision) == Spec.context_acknowledged(StateRest, EffectRest, decision) : C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>}:
  match decision:
    case C.Decision{world, reply, effects}: {==}

def context_completed_meaning(-StateRest: Data, -EffectRest: Data, +revision: Nat, +purpose: D.ContextPurpose,
  +outcome: Result<&2, &2, String, +List<D.ContextObservation()>>, +task: D.Task, +world: C.Frame<D.State, StateRest>) ->
  {Actual.context_completed(StateRest, EffectRest, revision, purpose, outcome, task, world) == Spec.context_completed(StateRest, EffectRest, revision, purpose, outcome, task, world) : C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>}:
  +current = Nat.is_eq(revision, D.history_length(D.task_history(task)))
  +actual = Actual.context_fresh(StateRest, EffectRest, current, purpose, outcome, task, world)
  +required = Spec.context_fresh(StateRest, EffectRest, current, purpose, outcome, task, world)
  Equal.trans(C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>,
    Actual.context_acknowledged(StateRest, EffectRest, actual), Actual.context_acknowledged(StateRest, EffectRest, required),
    Spec.context_acknowledged(StateRest, EffectRest, required),
    Equal.cong(C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>, C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>,
      (decision => Actual.context_acknowledged(StateRest, EffectRest, decision)), actual, required,
      context_fresh_meaning(StateRest, EffectRest, current, purpose, outcome, task, world)),
    context_acknowledged_meaning(StateRest, EffectRest, required))

def start_meaning(-StateRest: Data, -EffectRest: Data, +task: D.Task, +world: C.Frame<D.State, StateRest>) ->
  {Actual.start(StateRest, EffectRest, task, world) == Spec.start(StateRest, EffectRest, task, world) : C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>}:
  observe_meaning(StateRest, EffectRest, Ops.publish(task), D.GenerateContext{}, world)

def request_frame(-StateRest: Data, -EffectRest: Data, task: D.Task, world: C.Frame<D.State, StateRest>) ->
  {C.remaining(D.State, StateRest, Effects.Effect<EffectRest>, Actual.request(StateRest, EffectRest, task, world)) == C.rest(D.State, StateRest, world) : StateRest}:
  match world:
    case C.Frame{D.State{tasks, next_task, ticket, D.Environment{catalog, profiles, forks, descendants, project, plugins, instructions}, limits, projects}, rest}: {==}

def evaluator_frame(-StateRest: Data, -EffectRest: Data, task: D.Task, world: C.Frame<D.State, StateRest>) ->
  {C.remaining(D.State, StateRest, Effects.Effect<EffectRest>, Actual.evaluate(StateRest, EffectRest, task, world)) == C.rest(D.State, StateRest, world) : StateRest}:
  match world:
    case C.Frame{D.State{tasks, next_task, ticket, environment, limits, projects}, rest}: {==}

def execution_frame(-StateRest: Data, -EffectRest: Data, plan: R.Plan, task: D.Task, world: C.Frame<D.State, StateRest>) ->
  {C.remaining(D.State, StateRest, Effects.Effect<EffectRest>, Actual.execute(StateRest, EffectRest, plan, task, world)) == C.rest(D.State, StateRest, world) : StateRest}:
  match plan:
    case R.FixedPlan{}: request_frame(StateRest, EffectRest, task, world)
    case R.Evaluate{}: evaluator_frame(StateRest, EffectRest, task, world)
    case R.Reuse{effort, remaining}: request_frame(StateRest, EffectRest, Context.generation(effort, remaining, task), world)

def prepared_frame(-StateRest: Data, -EffectRest: Data, +task: D.Task, world: C.Frame<D.State, StateRest>) ->
  {C.remaining(D.State, StateRest, Effects.Effect<EffectRest>, Actual.prepared(StateRest, EffectRest, task, world)) == C.rest(D.State, StateRest, world) : StateRest}:
  execution_frame(StateRest, EffectRest, Actual.route(Context.task_policy(task), Context.lease(D.task_history(task), D.task_id(task))), task, world)

def start_frame(-StateRest: Data, -EffectRest: Data, task: D.Task, world: C.Frame<D.State, StateRest>) ->
  {C.remaining(D.State, StateRest, Effects.Effect<EffectRest>, Actual.start(StateRest, EffectRest, task, world)) == C.rest(D.State, StateRest, world) : StateRest}:
  match world:
    case C.Frame{D.State{tasks, next_task, ticket, environment, limits, projects}, rest}: {==}

def A.route_meaning(policy, lease):
  route_meaning(policy, lease)

def A.start_meaning(task, world):
  start_meaning(F.State(), F.Effect, task, world)

def selection_meaning(+accepted: Bool, +effort: String, +generations: Nat, +task: D.Task,
  checked: {Actual.chosen_permitted(task, R.Chosen{effort, generations}) == accepted : Bool}) ->
  {Actual.chosen_admission(task, Categories.admit_checked(R.Outcome, outcome => Actual.chosen_permitted(task, outcome),
    R.Chosen{effort, generations}, accepted, checked)) == Spec.selection(accepted, effort, generations, task) : D.Task}:
  match accepted:
    case True{}: {==}
    case False{}: {==}

def outcome_meaning(+outcome: R.Outcome, +task: D.Task) ->
  {Actual.observed(outcome, task) == Spec.outcome(outcome, task) : D.Task}:
  match outcome:
    case R.Chosen{+effort, +generations}:
      selection_meaning(R.accepts(Context.task_policy(task), effort, generations), effort, generations, task, {==})
    case R.EvaluationFailed{reason}: {==}

def fresh_meaning(+revision: Nat, +current: Bool, +outcome: R.Outcome, +task: D.Task,
  checked: {Actual.revision_current(revision, task) == current : Bool}) ->
  {Actual.revision_admission(revision, outcome, task,
    Categories.admit_checked(D.Task, task => Actual.revision_current(revision, task), task, current, checked)) == Spec.fresh(current, outcome, task) : D.Task}:
  match current:
    case True{}: outcome_meaning(outcome, task)
    case False{}: {==}

def A.completion_meaning(revision, outcome, task):
  fresh_meaning(revision, Nat.is_eq(revision, D.history_length(D.task_history(task))), outcome, task, {==})

def contract_frame(effort: String, remaining: Nat, +task: D.Task) ->
  {D.task_contract(Context.generation(effort, remaining, task)) == D.task_contract(task) : D.Contract}:
  match task:
    case D.Task{id, lineage, contract, status, history, queued, phase, operations, notified}: {==}

def A.reasoning_boundary():
  A.ReasoningBoundary{
    A.route_meaning, A.start_meaning, A.completion_meaning,
    (lease => {==}),
    (effort => remaining => {==}),
    (effort => remaining => {==}),
    (evaluator => efforts => baseline => transport => maximum => effort => generations => {==}),
    (history => owner => record_owner => effort => remaining => sampling => {==}),
    (effort => remaining => {==}),
    (outcome => task => {==}),
    (expected => revision => task => ticket => outcome => {==}),
    (phase => task => ticket => outcome => {==}),
    (history => text => owner => {==}),
    (history => call => value => owner => {==}),
    (history => text => owner => {==}),
    (history => summary => owner => {==}),
    (history => summary => {==}),
    (evaluator => efforts => baseline => maximum => effective => {==}),
    (effort => remaining => owner => history => {==}),
    (effort => remaining => owner => history => {==}),
    (history => {==}), contract_frame,
    (secret => summary => tail => {==}),
    (secret => {==}), (id => value => error => tail => {==}),
    (history => change => owner => {==})}


def Laws.model_request_full_history(task, state, board, catalog, profiles, forks, descendants, project, plugins, instructions):
  match state:
    case D.State{tasks, next_task, next_ticket, environment, limits, registry}: {==}
