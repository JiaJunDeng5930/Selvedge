import Base
import ../../bendlib/categories.bend as Categories
import ../features/MODEL.bend as F
import ../../bendlib/component.bend as C
import ../DOMAIN.bend as D
import ../MODEL.bend as M
import ../COMMANDS.bend as Commands
import ../INVARIANTS.bend as I
import ../../bendlib/json.bend as J
import ../transport/presentation.bend as View
import ./PROGRAM.bend as Protocol
import ../execution/notifications.bend as Notifications

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

def frame_bytes_limits(world: M.World(), limits_value: D.ExecutionLimits) -> U32:
  match world limits_value:
    case C.Frame{+task_state, +board} D.ExecutionLimits{steps, render, bytes}:
      bytes

def frame_bytes(+world: M.World()) -> U32:
  frame_bytes_limits(world, D.state_limits(C.local(D.State, F.State(), world)))

def reject(previous: M.World(), code: String, reason: String) -> M.Decision():
  C.Decision{previous, D.failure(code, reason), Nil{}}

def state(decision: M.Decision()) -> M.World():
  C.Decision{world, reply, effects} = decision
  world

def state_safe(decision: M.Decision()) -> Bool:
  I.world(state(decision))

def effect_authorized(previous: M.World(), decision: M.Decision()) -> Bool:
  I.decision(previous, decision)

def valid_candidate(+previous: M.World(), +decision: M.Decision()) -> Bool:
  Bool.and(state_safe(decision), effect_authorized(previous, decision))

def state_safety() -> M.Decision() -> Type:
  Categories.holds(M.Decision(), state_safe)

def effect_authority(+previous: M.World()) -> M.Decision() -> Type:
  Categories.holds(M.Decision(), decision => effect_authorized(previous, decision))

def committable(+previous: M.World()) -> M.Decision() -> Type:
  decision => Categories.intersection(M.Decision(), state_safety(), effect_authority(previous), decision)

def state_and_authority(+previous: M.World()) -> M.Decision() -> Type:
  committable(previous)

def committable_state(+previous: M.World()) -> Categories.Inclusion<M.Decision(), committable(previous), state_safety()>:
  Categories.intersection_first(M.Decision(), state_safety(), effect_authority(previous))

def committable_authority(+previous: M.World()) -> Categories.Inclusion<M.Decision(), committable(previous), effect_authority(previous)>:
  Categories.intersection_second(M.Decision(), state_safety(), effect_authority(previous))

def commit_candidate(-previous: M.World(), member: Categories.Membership<M.Decision(), committable(previous)>) -> M.Decision():
  Categories.Membership{decision, evidence} = member
  decision

def validate_admitted(previous: M.World(), admitted: Maybe<&1, Categories.Membership<M.Decision(), committable(previous)>>) -> M.Decision():
  match admitted:
    case Some{member}: commit_candidate(previous, member)
    case None{}: reject(previous, "invariant_violation", "The candidate violates a world invariant, task retention, or effect authority")

def live(decision: M.Decision()) -> M.Decision():
  C.Decision{+world, reply, effects} = decision
  C.Frame{+task_state, +board} = world
  tasks = D.state_tasks(task_state)
  C.Decision{world, reply, I.live_effects(effects, tasks)}

def validate(+decision: M.Decision(), +previous: M.World()) -> M.Decision():
  validate_admitted(previous, Categories.admit_intersection(M.Decision(), state_safe, candidate => effect_authorized(previous, candidate), decision))

def checked(decision: M.Decision(), previous: M.World()) -> M.Decision():
  validate(live(decision), previous)

def envelope_fits(+previous: M.World(), text: String) -> Bool:
  Nat.is_le(J.utf8_length(text), U32.to_nat(frame_bytes(previous)))

def bounded_envelope(+previous: M.World()) -> String -> Type:
  Categories.holds(String, text => envelope_fits(previous, text))

def sized_success(-previous: M.World(), member: Categories.Membership<String, bounded_envelope(previous)>, decision: M.Decision()) -> M.Decision():
  Categories.Membership{text, evidence} = member
  decision

def sized_admitted(previous: M.World(), admitted: Maybe<&1, Categories.Membership<String, bounded_envelope(previous)>>, decision: M.Decision()) -> M.Decision():
  match admitted:
    case Some{member}: sized_success(previous, member, decision)
    case None{}: reject(previous, "output_limit", "The complete decision exceeds the native output bound; no state change or effect was committed")

def rendered(result: Result<&2, &2, String, String>, decision: M.Decision(), +previous: M.World()) -> M.Decision():
  match result:
    case Fail{error}: reject(previous, "output_limit", error)
    case Done{text}: sized_admitted(previous, Categories.admit(String, value => envelope_fits(previous, value), text), decision)

def deliver(+durable: Bool, +decision: M.Decision(), +previous: M.World()) -> M.Decision():
  rendered(J.render(D.state_render_budget(C.local(D.State, F.State(), previous)), J.One{View.envelope(durable, decision)}), decision, previous)

def finish(durable: Bool, decision: M.Decision(), +previous: M.World()) -> M.Decision():
  deliver(durable, checked(decision, previous), previous)

def configuration_admitted(allowed: Bool, decision: M.Decision(), previous: M.World()) -> M.Decision():
  match allowed:
    case True{}: decision
    case False{}: reject(previous, "configuration_violation", "The candidate changes execution settings outside the resolved configuration command")

def configuration_checked(input: M.Input, +decision: M.Decision(), +previous: M.World()) -> M.Decision():
  configuration_admitted(Commands.configuration_allowed(input, previous, decision), decision, previous)

def update(~schedule: Bool -> @+decision:M.Decision() -> M.Decision(), +input: M.Input, +decision: M.Decision(), +previous: M.World()) -> M.Decision():
  finish(M.durable(input), configuration_checked(input, Notifications.decorate(input, previous, schedule(schedules(input, decision), decision)), previous), previous)

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
