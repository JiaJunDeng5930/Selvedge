import Base
import ../../bendlib/component.bend as C
import ../DOMAIN.bend as D
import ../../bendlib/effects.bend as Effects
import ./MODEL.bend as R
import ./PROGRAM.bend as Actual
import ./SPEC.bend as Spec
import ./context.bend as Context
import ../execution/OPERATIONS.bend as Ops

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
    case C.Frame{D.State{tasks, next_task, ticket, D.Environment{catalog, profiles, forks, descendants, project, plugins}, limits, projects}, rest}: {==}

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

def start_meaning(-StateRest: Data, -EffectRest: Data, +task: D.Task, +world: C.Frame<D.State, StateRest>) ->
  {Actual.start(StateRest, EffectRest, task, world) == Spec.start(StateRest, EffectRest, task, world) : C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<EffectRest>>}:
  prepared_meaning(StateRest, EffectRest, Ops.publish(task), world)

def request_frame(-StateRest: Data, -EffectRest: Data, task: D.Task, world: C.Frame<D.State, StateRest>) ->
  {C.remaining(D.State, StateRest, Effects.Effect<EffectRest>, Actual.request(StateRest, EffectRest, task, world)) == C.rest(D.State, StateRest, world) : StateRest}:
  match world:
    case C.Frame{D.State{tasks, next_task, ticket, D.Environment{catalog, profiles, forks, descendants, project, plugins}, limits, projects}, rest}: {==}

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
  prepared_frame(StateRest, EffectRest, Ops.publish(task), world)
