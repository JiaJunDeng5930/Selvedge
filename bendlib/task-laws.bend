import Base
import ./component.bend as C
import ./domain.bend as D
import ./tasks.bend as Tasks

# The shared storage primitive has an independent, complete state equation.
# Frame preservation alone would allow silently discarding the supplied task.
def required_update(task: D.Task, state: D.State) -> D.State:
  D.State{tasks, next_task, next_ticket, environment, limits, projects} = state
  D.State{Tasks.replace(tasks, task), next_task, next_ticket, environment, limits, projects}
