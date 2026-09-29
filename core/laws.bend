import Base
import ../MODEL.bend as M
import ../PROGRAM.bend as Program
import ../bendlib/component.bend as C
import ./SYSTEM.bend as Core
import ./user-experience.bend as E
import ./user-experience-laws.bend as Existing
import ./client-services.bend as Services

def runtime(decision: Core.Decision) -> M.Decision():
  Core.Decision{Core.State{E.Application{program, session}, services}, reply, effects, interaction, service, durable} = decision
  C.Decision{program, reply, effects}

def lifted(decision: E.Decision, services: Services.State) ->
  {runtime(Core.application_result(decision, services)) == Existing.runtime_observation(decision) : M.Decision()}:
  E.Decision{E.Application{program, session}, reply, effects, interaction, durable} = decision
  {==}

def runtime_input(+input: M.Input, +program: M.World(), +session: E.Session, services: Services.State) ->
  {runtime(Core.step(Core.ApplicationInput{E.RuntimeInput{input}}, Core.State{E.Application{program, session}, services})) ==
    Program.transition(input, program) : M.Decision()}:
  Services.State{access, credential, settings, appearance, next, transfers, preview} = services
  Equal.trans(M.Decision(),
    runtime(Core.application_result(E.step(E.RuntimeInput{input}, E.Application{program, session}), Services.State{access, credential, settings, appearance, next, transfers, preview})),
    Existing.runtime_observation(E.step(E.RuntimeInput{input}, E.Application{program, session})), Program.transition(input, program),
    lifted(E.step(E.RuntimeInput{input}, E.Application{program, session}), Services.State{access, credential, settings, appearance, next, transfers, preview}),
    Existing.runtime_input(input, program, session))
