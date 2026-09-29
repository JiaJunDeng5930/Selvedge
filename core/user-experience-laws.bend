import Base
import ../MODEL.bend as M
import ../PROGRAM.bend as Program
import ../bendlib/component.bend as C
import ./user-experience.bend as E
import ./user-input.bend as U

def runtime_observation(decision: E.Decision) -> M.Decision():
  E.Decision{E.Application{program, session}, reply, effects, interaction, durable} = decision
  C.Decision{program, reply, effects}

# The human-facing system retains the entire existing execution decision:
# post-state, reply and ordered effects. Session behavior cannot replace it.
def native_decision(+decision: M.Decision(), session: E.Session, durable: Bool) ->
  {runtime_observation(E.native_result(decision, session, None{}, durable)) == decision : M.Decision()}:
  C.Decision{program, reply, effects} = decision
  E.Session{route, drafts, readers, layers, focus, navigation, filter, now, next, pending, previews, code_blocks} = session
  {==}

def runtime_input(+input: M.Input, +program: M.World(), session: E.Session) ->
  {runtime_observation(E.step(E.RuntimeInput{input}, E.Application{program, session})) ==
    Program.transition(input, program) : M.Decision()}:
  native_decision(Program.transition(input, program), session, M.durable(input))

def delivery_retains_editor(task: Nat, message: U.Text, previous: U.Delivery, selected: U.Delivery, world: M.World()) ->
  {U.apply_edit(U.ChooseDelivery{selected}, U.Message{task, message, previous}, world) ==
    Done{U.Message{task, message, selected}} : Result<&2, &2, String, U.Body>}:
  {==}
