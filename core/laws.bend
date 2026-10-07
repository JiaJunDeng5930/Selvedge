import Base
import ../MODEL.bend as M
import ../bendlib/component.bend as C
import ./SYSTEM.bend as Core
import ./user-experience.bend as E

def runtime(decision: Core.Decision) -> M.Decision():
  Core.Decision{Core.State{E.Application{program, session}, services}, reply, effects, interaction, service, durable} = decision
  C.Decision{program, reply, effects}
