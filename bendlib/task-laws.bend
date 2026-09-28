import Base
import ./component.bend as C
import ./domain.bend as D
import ./tasks.bend as Tasks

# The shared storage primitive has an independent, complete state equation.
# Frame preservation alone would allow silently discarding the supplied task.
def required_update(task: D.Task, state: D.State) -> D.State:
  D.State{tasks, next_task, next_ticket, environment, limits, projects} = state
  D.State{Tasks.replace(tasks, task), next_task, next_ticket, environment, limits, projects}

def update_meaning(-R: Data, +task: D.Task, +state: D.State, +rest: R) ->
  {Tasks.update_world(R, task, C.Frame{state, rest}) == C.Frame{required_update(task, state), rest} : C.Frame<D.State, R>}:
  match state:
    case D.State{tasks, next_task, next_ticket, environment, limits, projects}: {==}

def update_frame(-StateRest: Data, task: D.Task, world: C.Frame<D.State, StateRest>) ->
  {C.rest(D.State, StateRest, Tasks.update_world(StateRest, task, world)) == C.rest(D.State, StateRest, world) : StateRest}:
  match world:
    case C.Frame{state, rest}: C.map_frame(D.State, StateRest, value => Tasks.update_state(task, value), state, rest)
