import Base
import ../../bendlib/component.bend as C
import ../../bendlib/json.bend as J
import ../DOMAIN.bend as D
import ../context/MODEL.bend as Context
import ../context/task-lifecycle.bend as Lifecycle
import ./PROGRAM.bend as T

def control(task: D.Task) -> D.Task:
  D.with_history(D.EmptyHistory{}, task)

def expected_history(change: Maybe<&2, Context.Change>, history: D.History) -> D.History:
  match change:
    case None{}: history
    case Some{change}: D.HistoryNode{history, D.ContextMessage{D.ContextChange{change}}}

def observed_history(+parent: D.Task, +task: D.Task) -> D.History:
  +bindings = D.context_bindings(D.task_history(task))
  +id = D.task_id(parent)
  observation = Lifecycle.observation(id, Nat.show(1n+D.history_length(D.task_history(task))),
    D.status_name(D.task_status(parent)), T.phase_name(D.task_phase(parent)), Context.find(bindings, Lifecycle.key(id)))
  expected_history(Context.resolution_change(Context.observation_resolution(bindings, observation)), D.task_history(task))

type Observation<-parent: D.Task, -before: D.Task, -after: D.Task> is Type:
  Observation{
    history: {D.task_history(after) == observed_history(parent, before) : D.History},
    control: {control(after) == control(before) : D.Task}
  }

def reply(-StateRest: Data, -Effect: Data, decision: C.Decision<C.Frame<D.State, StateRest>, Effect>) -> J.Json:
  C.Decision{world, reply, effects} = decision
  reply

def effects(-StateRest: Data, -Effect: Data, decision: C.Decision<C.Frame<D.State, StateRest>, Effect>) -> +List<Effect>:
  C.Decision{world, reply, effects} = decision
  effects

type FramePreservation<-StateRest: Data, -Effect: Data, -before: C.Decision<C.Frame<D.State, StateRest>, Effect>, -after: C.Decision<C.Frame<D.State, StateRest>, Effect>> is Type:
  FramePreservation{
    remaining: {C.remaining(D.State, StateRest, Effect, after) == C.remaining(D.State, StateRest, Effect, before) : StateRest},
    reply: {reply(StateRest, Effect, after) == reply(StateRest, Effect, before) : J.Json},
    effects: {effects(StateRest, Effect, after) == effects(StateRest, Effect, before) : +List<Effect>}
  }
