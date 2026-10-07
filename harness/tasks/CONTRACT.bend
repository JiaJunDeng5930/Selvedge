import Base
import ../../bendlib/component.bend as C
import ../DOMAIN.bend as D
import ./PROGRAM.bend as Tasks

# The shared storage primitive has an independent, complete state equation.
# Frame preservation alone would allow silently discarding the supplied task.
def required_update(+task: D.Task, +state: D.State) -> D.State:
  D.with_state_tasks(Tasks.replace(D.state_tasks(state), task), state)
