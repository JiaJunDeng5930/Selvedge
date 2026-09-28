import Base
import ../../MODEL.bend as M
import ../../REASONING.bend as R
import ../reasoning-architecture.bend as A
import ../reasoning.bend as Actual
import ../reasoning-spec.bend as Spec
import ../reasoning-context.bend as Context
import ../operations.bend as Ops
import ../tasks.bend as T
import ../json.bend as J

def A.route_meaning(policy, lease):
  match policy lease:
    case R.Fixed{} _: {==}
    case R.Adaptive{evaluator, efforts, baseline, transport, maximum} R.NoLease{}: {==}
    case R.Adaptive{evaluator, efforts, baseline, transport, maximum} R.Lease{effort, 0n}: {==}
    case R.Adaptive{evaluator, efforts, baseline, transport, maximum} R.Lease{effort, 1n+remaining}: {==}

def request_meaning(+task: M.Task, +world: M.World) ->
  {Actual.request(task, world) == Spec.model(task, world) : M.Decision}:
  match world:
    case M.World{tasks, next_task, ticket, M.Environment{catalog, profiles, forks, descendants, project, plugins}, limits, projects, board}: {==}

def evaluator_meaning(+task: M.Task, +world: M.World) ->
  {Actual.evaluate(task, world) == Spec.evaluator(task, world) : M.Decision}:
  match world:
    case M.World{tasks, next_task, ticket, environment, limits, projects, board}: {==}

def execution_meaning(+plan: R.Plan, +task: M.Task, +world: M.World) ->
  {Actual.execute(plan, task, world) == Spec.required(plan, task, world) : M.Decision}:
  match plan:
    case R.FixedPlan{}: request_meaning(task, world)
    case R.Evaluate{}: evaluator_meaning(task, world)
    case R.Reuse{effort, remaining}: request_meaning(Context.generation(effort, remaining, task), world)

def prepared_meaning(+task: M.Task, +world: M.World) ->
  {Actual.prepared(task, world) == Spec.prepared(task, world) : M.Decision}:
  +policy = Context.task_policy(task)
  +lease = Context.lease(M.task_history(task), M.task_id(task))
  +actual = Actual.route(policy, lease)
  +required = R.requirement(policy, lease)
  Equal.trans(M.Decision, Actual.execute(actual, task, world), Actual.execute(required, task, world), Spec.required(required, task, world),
    Equal.cong(R.Plan, M.Decision, (plan => Actual.execute(plan, task, world)), actual, required, A.route_meaning(policy, lease)),
    execution_meaning(required, task, world))

def A.start_meaning(task, world):
  prepared_meaning(Ops.publish(task), world)

def selection_meaning(+accepted: Bool, +effort: String, +generations: Nat, +task: M.Task) ->
  {Actual.chosen(accepted, effort, generations, task) == Spec.selection(accepted, effort, generations, task) : M.Task}:
  match accepted:
    case True{}: {==}
    case False{}: {==}

def outcome_meaning(+outcome: R.Outcome, +task: M.Task) ->
  {Actual.observed(outcome, task) == Spec.outcome(outcome, task) : M.Task}:
  match outcome:
    case R.Chosen{+effort, +generations}:
      selection_meaning(R.accepts(Context.task_policy(task), effort, generations), effort, generations, task)
    case R.EvaluationFailed{reason}: {==}

def fresh_meaning(+current: Bool, +outcome: R.Outcome, +task: M.Task) ->
  {Actual.revision_matches(current, outcome, task) == Spec.fresh(current, outcome, task) : M.Task}:
  match current:
    case True{}: outcome_meaning(outcome, task)
    case False{}: {==}

def A.completion_meaning(revision, outcome, task):
  fresh_meaning(Nat.is_eq(revision, M.history_length(M.task_history(task))), outcome, task)

def contract_frame(effort: String, remaining: Nat, +task: M.Task) ->
  {M.task_contract(Context.generation(effort, remaining, task)) == M.task_contract(task) : M.Contract}:
  match task:
    case M.Task{id, lineage, contract, status, history, queued, phase, operations, notified}: {==}

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
    (secret => {==}), (id => value => error => tail => {==})}
