import Base
import ../../bendlib/component.bend as C
import ../../bendlib/effects.bend as Effects
import ../DOMAIN.bend as D
import ../context/MODEL.bend as Context
import ../context/task-lifecycle.bend as Lifecycle
import ./PROGRAM.bend as T
import ./side-context.bend as Actual
import ./side-context-contract.bend as Spec
import ../reasoning/MODEL.bend as Reasoning
import ../reasoning/context.bend as ReasoningContext

def appended_history(+change: Maybe<&2, Context.Change>, +task: D.Task) ->
  {D.task_history(Actual.append_change(change, task)) == Spec.expected_history(change, D.task_history(task)) : D.History}:
  match change task:
    case None{} _: {==}
    case Some{change} D.Task{id, lineage, contract, current, status, history, queued, phase, operations, notified}: {==}

def appended_control(+change: Maybe<&2, Context.Change>, +task: D.Task) ->
  {Spec.control(Actual.append_change(change, task)) == Spec.control(task) : D.Task}:
  match change task:
    case None{} _: {==}
    case Some{change} D.Task{id, lineage, contract, current, status, history, queued, phase, operations, notified}: {==}

def observation(+parent: D.Task, +task: D.Task) -> Spec.Observation<parent, task, Actual.observe(parent, task)>:
  +bindings = D.context_bindings(D.task_history(task))
  +id = D.task_id(parent)
  +observed = Lifecycle.observation(id, Nat.show(1n+D.history_length(D.task_history(task))),
    D.status_name(D.task_status(parent)), T.phase_name(D.task_phase(parent)), Context.find(bindings, Lifecycle.key(id)))
  +change = Context.resolution_change(Context.observation_resolution(bindings, observed))
  Spec.Observation{appended_history(change, task), appended_control(change, task)}

def frame(-StateRest: Data, -Effect: Data, +decision: C.Decision<C.Frame<D.State, StateRest>, Effect>) ->
  Spec.FramePreservation<StateRest, Effect, decision, Actual.reconcile(StateRest, Effect, decision)>:
  C.Decision{C.Frame{state, rest}, reply, effects} = decision
  Spec.FramePreservation{{==}, {==}, {==}}

def native_state_roundtrip() -> {Context.observer(Context.observer_json(Context.NativeState{})) == Some{Context.NativeState{}} : Maybe<&2, Context.Observer>}:
  {==}

def observed_control(-parent: D.Task, -task: D.Task, evidence: Spec.Observation<parent, task, Actual.observe(parent, task)>) ->
  {Spec.control(Actual.observe(parent, task)) == Spec.control(task) : D.Task}:
  Spec.Observation{history, control} = evidence
  control

def found_control(+parent: Maybe<&2, D.Task>, +task: D.Task) ->
  {Spec.control(Actual.found(parent, task)) == Spec.control(task) : D.Task}:
  match parent:
    case None{}: {==}
    case Some{+parent}: observed_control(parent, task, observation(parent, task))

def selected_control(+parent: Maybe<&2, Nat>, +tasks: +List<D.Task>, +task: D.Task) ->
  {Spec.control(Actual.selected(parent, tasks, task)) == Spec.control(task) : D.Task}:
  match parent:
    case None{}: {==}
    case Some{id}: found_control(T.find(tasks, id), task)

def live_control(+status: D.Status, +tasks: +List<D.Task>, +task: D.Task) ->
  {Spec.control(Actual.live_task(status, tasks, task)) == Spec.control(task) : D.Task}:
  match status:
    case D.Archived{}: {==}
    case D.Active{}: selected_control(D.side_parent(task), tasks, task)
    case D.Stopped{}: selected_control(D.side_parent(task), tasks, task)
    case D.Frozen{}: selected_control(D.side_parent(task), tasks, task)

def task_control(+tasks: +List<D.Task>, +task: D.Task) ->
  {Spec.control(Actual.task(tasks, task)) == Spec.control(task) : D.Task}:
  live_control(D.task_status(task), tasks, task)

def archived(tasks: +List<D.Task>, +task: D.Task) ->
  {Actual.live_task(D.Archived{}, tasks, task) == task : D.Task}:
  {==}

def context_dispatch(-Extension: Data, id: Nat, +ticket: Nat, history: D.History, context: D.TaskContext, purpose: D.ContextPurpose, +task: D.Task, tasks: +List<D.Task>) ->
  {Actual.freeze_context_checked(Extension, True{}, id, ticket, history, context, purpose, task, tasks) ==
    Actual.Dispatch{T.replace(tasks, D.with_phase(D.ContextPending{ticket, D.history_length(D.task_history(task)), purpose}, task)),
      [Effects.ObserveContext{id, ticket, D.task_history(task), context}]} : Actual.Dispatch<Extension>}:
  {==}

def reasoning_dispatch(-Extension: Data, id: Nat, +ticket: Nat, model: D.Model, history: D.History, +task: D.Task, tasks: +List<D.Task>) ->
  {Actual.freeze_reasoning_checked(Extension, True{}, id, ticket, model, history, task, tasks) ==
    Actual.Dispatch{T.replace(tasks, D.with_phase(D.ReasoningPending{ticket, D.history_length(D.task_history(task))}, task)),
      [Effects.RequestReasoning{id, ticket, model, D.task_history(task)}]} : Actual.Dispatch<Extension>}:
  {==}

def model_dispatch(+expected: Nat, callable: +List<String>, mode: D.OutputMode, +ticket: Nat, +task: D.Task, +original: D.History,
  matching: {Nat.is_eq(expected, ticket) && Actual.has_parent(D.side_parent(task)) == True{} : Bool}) ->
  {Actual.model_phase_history(D.ModelPending{expected, callable, mode}, ticket, task, original) == D.task_history(task) : D.History}:
  Equal.cong(Bool, D.History, (accepted => Actual.selected_history(accepted, D.task_history(task), original)),
    Nat.is_eq(expected, ticket) && Actual.has_parent(D.side_parent(task)), True{}, matching)

# A tracked lifecycle change does not create or renew a reasoning sample. The
# existing selected effort and remaining lease have exactly their prior meaning.
def reasoning_sample_preserved(+policy: Reasoning.Policy, +owner: Nat, +history: D.History, +change: Context.Change) ->
  {ReasoningContext.valid_sample(policy, owner, D.HistoryNode{history, D.ContextMessage{D.ContextChange{change}}}) ==
    ReasoningContext.valid_sample(policy, owner, history) : Bool}:
  match policy:
    case Reasoning.Fixed{}: {==}
    case Reasoning.Adaptive{evaluator, efforts, baseline, Reasoning.ConfigurationUpdates{}, maximum}: {==}
    case Reasoning.Adaptive{evaluator, efforts, baseline, Reasoning.RequestEffort{}, maximum}: {==}
