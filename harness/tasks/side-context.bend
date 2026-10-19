import Base
import ../../bendlib/component.bend as C
import ../../bendlib/effects.bend as Effects
import ../../bendlib/json.bend as J
import ../DOMAIN.bend as D
import ../context/MODEL.bend as Context
import ../context/task-lifecycle.bend as Lifecycle
import ./PROGRAM.bend as T

def append_change(change: Maybe<&2, Context.Change>, task: D.Task) -> D.Task:
  match change:
    case None{}: task
    case Some{change}: D.append_context(D.ContextChange{change}, task)

def observe(+parent: D.Task, +task: D.Task) -> D.Task:
  +bindings = D.context_bindings(D.task_history(task))
  +id = D.task_id(parent)
  observation = Lifecycle.observation(id, Nat.show(1n+D.history_length(D.task_history(task))),
    D.status_name(D.task_status(parent)), T.phase_name(D.task_phase(parent)), Context.find(bindings, Lifecycle.key(id)))
  append_change(Context.resolution_change(Context.observation_resolution(bindings, observation)), task)

def found(parent: Maybe<&2, D.Task>, task: D.Task) -> D.Task:
  match parent:
    case None{}: task
    case Some{parent}: observe(parent, task)

def selected(parent: Maybe<&2, Nat>, tasks: +List<D.Task>, task: D.Task) -> D.Task:
  match parent:
    case None{}: task
    case Some{id}: found(T.find(tasks, id), task)

def live_task(status: D.Status, +tasks: +List<D.Task>, +value: D.Task) -> D.Task:
  match status:
    case D.Archived{}: value
    case _: selected(D.side_parent(value), tasks, value)

def task(+tasks: +List<D.Task>, +value: D.Task) -> D.Task:
  live_task(D.task_status(value), tasks, value)

def tasks(remaining: +List<D.Task>, +parents: +List<D.Task>) -> +List<D.Task>:
  match remaining:
    case Nil{}: Nil{}
    case Con{value, rest}: task(parents, value) <> tasks(rest, parents)

# Read all parents from one captured world. Appending tracked observations does
# not change lifecycle, queues, notification bits or scheduling eligibility.
def reconcile(-StateRest: Data, -Effect: Data, decision: C.Decision<C.Frame<D.State, StateRest>, Effect>) -> C.Decision<C.Frame<D.State, StateRest>, Effect>:
  C.Decision{C.Frame{+state, rest}, reply, effects} = decision
  +entries = D.state_tasks(state)
  C.Decision{C.Frame{D.with_state_tasks(tasks(entries, entries), state), rest}, reply, effects}

type Dispatch<-Extension: Data> is Data:
  Dispatch{tasks: +List<D.Task>, effects: +List<Effects.Effect<Extension>>}

def unchanged(-Extension: Data, effect: Effects.Effect<Extension>, tasks: +List<D.Task>) -> Dispatch<Extension>:
  Dispatch{tasks, [effect]}

def has_parent(parent: Maybe<&2, Nat>) -> Bool:
  match parent:
    case None{}: False{}
    case Some{id}: True{}

def freeze_context_checked(-Extension: Data, accepted: Bool, id: Nat, +ticket: Nat, history: D.History, context: D.TaskContext, purpose: D.ContextPurpose, +task: D.Task, tasks: +List<D.Task>) -> Dispatch<Extension>:
  match accepted:
    case False{}: unchanged(Extension, Effects.ObserveContext{id, ticket, history, context}, tasks)
    case True{}:
      +current = D.task_history(task)
      Dispatch{T.replace(tasks, D.with_phase(D.ContextPending{ticket, D.history_length(current), purpose}, task)),
        [Effects.ObserveContext{id, ticket, current, context}]}

def freeze_context_phase(-Extension: Data, phase: D.Phase, +id: Nat, +ticket: Nat, history: D.History, +context: D.TaskContext, +task: D.Task, tasks: +List<D.Task>) -> Dispatch<Extension>:
  match phase:
    case D.ContextPending{expected, revision, purpose}:
      freeze_context_checked(Extension, Nat.is_eq(expected, ticket) && has_parent(D.side_parent(task)), id, ticket, history, context, purpose, task, tasks)
    case _: unchanged(Extension, Effects.ObserveContext{id, ticket, history, context}, tasks)

def freeze_context(-Extension: Data, found: Maybe<&2, D.Task>, +id: Nat, +ticket: Nat, history: D.History, +context: D.TaskContext, tasks: +List<D.Task>) -> Dispatch<Extension>:
  match found:
    case Some{+task}:
      freeze_context_phase(Extension, D.task_phase(task), id, ticket, history, context, task, tasks)
    case None{}: unchanged(Extension, Effects.ObserveContext{id, ticket, history, context}, tasks)

def selected_history(accepted: Bool, current: D.History, original: D.History) -> D.History:
  match accepted:
    case True{}: current
    case False{}: original

def model_phase_history(phase: D.Phase, ticket: Nat, +task: D.Task, original: D.History) -> D.History:
  match phase:
    case D.ModelPending{expected, callable, mode}:
      selected_history(Nat.is_eq(expected, ticket) && has_parent(D.side_parent(task)), D.task_history(task), original)
    case _: original

def model_history(found: Maybe<&2, D.Task>, +ticket: Nat, original: D.History) -> D.History:
  match found:
    case Some{+task}:
      model_phase_history(D.task_phase(task), ticket, task, original)
    case None{}: original

def freeze_reasoning_checked(-Extension: Data, accepted: Bool, id: Nat, +ticket: Nat, model: D.Model, history: D.History, +task: D.Task, tasks: +List<D.Task>) -> Dispatch<Extension>:
  match accepted:
    case False{}: unchanged(Extension, Effects.RequestReasoning{id, ticket, model, history}, tasks)
    case True{}:
      +current = D.task_history(task)
      Dispatch{T.replace(tasks, D.with_phase(D.ReasoningPending{ticket, D.history_length(current)}, task)),
        [Effects.RequestReasoning{id, ticket, model, current}]}

def freeze_reasoning_phase(-Extension: Data, phase: D.Phase, +id: Nat, +ticket: Nat, +model: D.Model, history: D.History, +task: D.Task, tasks: +List<D.Task>) -> Dispatch<Extension>:
  match phase:
    case D.ReasoningPending{expected, revision}:
      freeze_reasoning_checked(Extension, Nat.is_eq(expected, ticket) && has_parent(D.side_parent(task)), id, ticket, model, history, task, tasks)
    case _: unchanged(Extension, Effects.RequestReasoning{id, ticket, model, history}, tasks)

def freeze_reasoning(-Extension: Data, found: Maybe<&2, D.Task>, +id: Nat, +ticket: Nat, +model: D.Model, history: D.History, tasks: +List<D.Task>) -> Dispatch<Extension>:
  match found:
    case Some{+task}:
      freeze_reasoning_phase(Extension, D.task_phase(task), id, ticket, model, history, task, tasks)
    case None{}: unchanged(Extension, Effects.RequestReasoning{id, ticket, model, history}, tasks)

def freeze_effect(-Extension: Data, effect: Effects.Effect<Extension>, +tasks: +List<D.Task>) -> Dispatch<Extension>:
  match effect:
    case Effects.ObserveContext{+id, ticket, history, context}:
      freeze_context(Extension, T.find(tasks, id), id, ticket, history, context, tasks)
    case Effects.RequestModel{+id, +ticket, model, history, tools, callable, context, scope, reserve}:
      Dispatch{tasks, [Effects.RequestModel{id, ticket, model, model_history(T.find(tasks, id), ticket, history), tools, callable, context, scope, reserve}]}
    case Effects.RequestReasoning{+id, ticket, model, history}:
      freeze_reasoning(Extension, T.find(tasks, id), id, ticket, model, history, tasks)
    case other: unchanged(Extension, other, tasks)

def joined_dispatch(-Extension: Data, earlier: +List<Effects.Effect<Extension>>, next: Dispatch<Extension>) -> Dispatch<Extension>:
  Dispatch{tasks, effects} = next
  Dispatch{tasks, List.append(&2, Effects.Effect<Extension>, earlier, effects)}

def continue_frozen(-Extension: Data, first: Dispatch<Extension>, next: +List<D.Task> -> Dispatch<Extension>) -> Dispatch<Extension>:
  Dispatch{tasks, effects} = first
  joined_dispatch(Extension, effects, next(tasks))

def freeze_effects(-Extension: Data, remaining: +List<Effects.Effect<Extension>>, +tasks: +List<D.Task>) -> Dispatch<Extension>:
  match remaining:
    case Nil{}: Dispatch{tasks, Nil{}}
    case Con{effect, rest}:
      continue_frozen(Extension, freeze_effect(Extension, effect, tasks), (next => freeze_effects(Extension, rest, next)))

# Only effects belonging to this uncommitted decision are frozen again. A
# previously dispatched request retains its captured revision and callback.
def frozen(-StateRest: Data, -Extension: Data, dispatch: Dispatch<Extension>, state: D.State, rest: StateRest, reply: J.Json) -> C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<Extension>>:
  Dispatch{tasks, effects} = dispatch
  C.Decision{C.Frame{D.with_state_tasks(tasks, state), rest}, reply, effects}

def freeze(-StateRest: Data, -Extension: Data, decision: C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<Extension>>) -> C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<Extension>>:
  C.Decision{C.Frame{+state, rest}, reply, effects} = decision
  frozen(StateRest, Extension, freeze_effects(Extension, effects, D.state_tasks(state)), state, rest, reply)

def reconcile_dispatch(-StateRest: Data, -Extension: Data, decision: C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<Extension>>) -> C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<Extension>>:
  freeze(StateRest, Extension, reconcile(StateRest, Effects.Effect<Extension>, decision))

def prepare_dispatch(-StateRest: Data, -Extension: Data, enabled: Bool, decision: C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<Extension>>) -> C.Decision<C.Frame<D.State, StateRest>, Effects.Effect<Extension>>:
  match enabled:
    case False{}: decision
    case True{}: reconcile_dispatch(StateRest, Extension, decision)
