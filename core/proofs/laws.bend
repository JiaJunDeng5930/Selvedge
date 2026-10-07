import Base
import ../../MODEL.bend as M
import ../../PROGRAM.bend as Program
import ../SYSTEM.bend as Core
import ../user-experience.bend as E
import ../user-experience-program.bend as ExperienceProgram
import ../user-experience-laws.bend as Existing
import ../client-services.bend as Services
import ../laws.bend as Rule
import ./user-experience.bend as ExistingProof

def lifted(decision: E.Decision, services: Services.State) ->
  {Rule.runtime(Core.application_result(decision, services)) == Existing.runtime_observation(decision) : M.Decision()}:
  E.Decision{E.Application{program, session}, reply, effects, interaction, durable} = decision
  {==}

def runtime_input(+input: M.Input, +program: M.World(), +session: E.Session, services: Services.State) ->
  {Rule.runtime(Core.step(Core.ApplicationInput{E.RuntimeInput{input}}, Core.State{E.Application{program, session}, services})) ==
    Program.transition(input, program) : M.Decision()}:
  Services.State{access, credential, settings, appearance, next, transfers, preview, directory_picker} = services
  Equal.trans(M.Decision(),
    Rule.runtime(Core.application_result(ExperienceProgram.step(E.RuntimeInput{input}, E.Application{program, session}), Services.State{access, credential, settings, appearance, next, transfers, preview, directory_picker})),
    Existing.runtime_observation(ExperienceProgram.step(E.RuntimeInput{input}, E.Application{program, session})), Program.transition(input, program),
    lifted(ExperienceProgram.step(E.RuntimeInput{input}, E.Application{program, session}), Services.State{access, credential, settings, appearance, next, transfers, preview, directory_picker}),
    ExistingProof.runtime_input(input, program, session))
