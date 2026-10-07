import Base
import ../FEATURES.bend as F
import ./component.bend as C
import ./domain.bend as D
import ../MODEL.bend as M
import ../COMMANDS.bend as Commands
import ../INVARIANTS.bend as I
import ./json.bend as J
import ./presentation.bend as View
import ./protocol.bend as Protocol
import ./notifications.bend as Notifications

# Complete command meaning includes the finite scheduling and commit boundary.
# A refusal cannot advance unrelated tasks. Accepted commands may advance any
# runnable task, bounded by the world's scheduling fuel. A rejected commit or
# oversized complete envelope rolls back the whole decision, including effects.
def schedules(input: M.Input, decision: M.Decision()) -> Bool:
  match input:
    case M.UserCommand{M.Observe{query}}: False{}
    case M.UserCommand{other}:
      C.Decision{world, reply, effects} = decision
      J.boolean(J.get(reply, "ok"))
    case other: M.schedules(other)

def frame_bytes(world: M.World()) -> U32:
  C.Frame{D.State{tasks, next_task, next_ticket, environment, D.ExecutionLimits{steps, render, bytes}, projects}, +board} = world
  bytes

def reject(previous: M.World(), code: String, reason: String) -> M.Decision():
  C.Decision{previous, D.failure(code, reason), Nil{}}

def guard(state_valid: Bool, change_valid: Bool, decision: M.Decision(), previous: M.World()) -> M.Decision():
  match state_valid change_valid:
    case True{} True{}: decision
    case _ _: reject(previous, "invariant_violation", "The candidate violates a world invariant, task retention, or effect authority")

def live(decision: M.Decision()) -> M.Decision():
  C.Decision{+world, reply, effects} = decision
  C.Frame{D.State{tasks, next_task, next_ticket, environment, limits, projects}, +board} = world
  C.Decision{world, reply, I.live_effects(effects, tasks)}

def state(decision: M.Decision()) -> M.World():
  C.Decision{world, reply, effects} = decision
  world

def validate(+decision: M.Decision(), +previous: M.World()) -> M.Decision():
  guard(I.world(state(decision)), I.decision(previous, decision), decision, previous)

def checked(decision: M.Decision(), previous: M.World()) -> M.Decision():
  validate(live(decision), previous)

def sized(fits: Bool, decision: M.Decision(), previous: M.World()) -> M.Decision():
  match fits:
    case True{}: decision
    case False{}: reject(previous, "output_limit", "The complete decision exceeds the native output bound; no state change or effect was committed")

def rendered(result: Result<&2, &2, String, String>, decision: M.Decision(), +previous: M.World()) -> M.Decision():
  match result:
    case Fail{error}: reject(previous, "output_limit", error)
    case Done{text}: sized(Nat.is_le(J.utf8_length(text), U32.to_nat(frame_bytes(previous))), decision, previous)

def deliver(+durable: Bool, +decision: M.Decision(), +previous: M.World()) -> M.Decision():
  rendered(J.render(D.state_render_budget(C.local(D.State, F.State(), previous)), J.One{View.envelope(durable, decision)}), decision, previous)

def finish(durable: Bool, decision: M.Decision(), +previous: M.World()) -> M.Decision():
  deliver(durable, checked(decision, previous), previous)

def update(~schedule: Bool -> @+decision:M.Decision() -> M.Decision(), +input: M.Input, +decision: M.Decision(), +previous: M.World()) -> M.Decision():
  finish(M.durable(input), Notifications.decorate(input, previous, schedule(schedules(input, decision), decision)), previous)

# Scheduling is a supplied deterministic transducer, constrained by the exact
# zero/idle/successor equations in LAWS, not a fairness or termination assumption.
def command(~schedule: Bool -> @+decision:M.Decision() -> M.Decision(), +request: M.Command, +world: M.World()) -> M.Decision():
  match request:
    case M.Observe{query}: deliver(False{}, Commands.meaning(Commands.Observe{query}, world), world)
    case other: update(~schedule, M.UserCommand{other}, Commands.command(other, world), world)

def input(~schedule: Bool -> @+decision:M.Decision() -> M.Decision(), +event: M.Input, +world: M.World()) -> M.Decision():
  match event:
    case M.UserCommand{request}: command(~schedule, request, world)
    case other: update(~schedule, other, Protocol.input(other, world), world)
