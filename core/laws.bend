import Base
import ../MODEL.bend as M
import ../bendlib/component.bend as C
import ./SYSTEM.bend as Core
import ./user-experience.bend as E

def runtime(decision: Core.Decision) -> M.Decision():
  Core.Decision{+observed_state, reply, effects, interaction, service, durable} = decision
  +observed_application = Core.application(observed_state)
  program = E.program(observed_application)
  C.Decision{program, reply, effects}
