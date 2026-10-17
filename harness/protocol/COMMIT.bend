import Base
import ../../features/remote/MODEL.bend as Remote
import ../../features/remote/PROGRAM.bend as RemoteProgram
import ../features/remote.bend as RemoteState
import ../transport/command-codec.bend as CommandCodec
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
    case M.UserCommand{M.FeatureCommand{command}}:
      C.Decision{world, reply, effects} = decision
      F.schedules(command) && J.boolean(J.get(reply, "ok"))
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


# A remote request and its command receipt form one native decision. Ordinary
# command resolution, scheduling and configuration checks are reused unchanged.
# The final finish rolls back both the command and receipt if either is invalid.
def remote_recorded(fits: Bool, request: Remote.Request, +decision: M.Decision(), previous: M.World()) -> M.Decision():
  match fits:
    case False{}: reject(previous, "remote_reply_limit", "The command reply exceeds remote receipt retention limits; no command or effect was committed")
    case True{}:
      C.Decision{+world, +reply, effects} = decision
      C.Decision{RemoteState.store(RemoteProgram.remember(request, reply, RemoteState.registry(world)), world), reply, effects}

def remote_record(request: Remote.Request, +decision: M.Decision(), previous: M.World()) -> M.Decision():
  C.Decision{world, +reply, effects} = decision
  remote_recorded(Remote.payload_valid(reply), request, C.Decision{world, reply, effects}, previous)

def remote_environment(environment: Maybe<&2, D.Environment>, world: M.World()) -> M.World():
  match environment:
    case None{}: world
    case Some{value}: state(Protocol.input(M.Configure{value}, world))

def remote_result(accepted: Bool, request: Remote.Request, decision: M.Decision(), +previous: M.World()) -> M.Decision():
  match accepted:
    case True{}: remote_record(request, decision, previous)
    case False{}:
      C.Decision{discarded, reply, effects} = decision
      remote_record(request, C.Decision{previous, reply, Nil{}}, previous)

def remote_executed(request: Remote.Request, +decision: M.Decision(), previous: M.World()) -> M.Decision():
  C.Decision{world, +reply, effects} = decision
  remote_result(J.boolean(J.get(reply, "ok")), request, C.Decision{world, reply, effects}, previous)

def remote_authorized(~schedule: Bool -> @+decision:M.Decision() -> M.Decision(), authorization: Remote.Authorization,
  request: Remote.Request, request_command: M.Command, environment: Maybe<&2, D.Environment>, +world: M.World()) -> M.Decision():
  match authorization:
    case Remote.Denied{code, reason}: reject(world, code, reason)
    case Remote.Replay{reply}: C.Decision{world, reply, Nil{}}
    case Remote.Admitted{}:
      remote_executed(request, command(~schedule, request_command, remote_environment(environment, world)), world)

def remote_prepared_mapped(required: Maybe<&2, Remote.Rights>, original: Remote.Request, +world: M.World()) -> Remote.Authorization:
  match required:
    case None{}: Remote.Denied{"remote_command_forbidden", "Remote access cannot invoke this local management command"}
    case Some{rights}: RemoteProgram.authorize(rights, original, RemoteState.registry(world))

def remote_prepared(same_operation: Bool, +request: Remote.Request, +request_command: M.Command, +world: M.World()) -> Remote.Authorization:
  match same_operation:
    case False{}: Remote.Denied{"remote_intent_mismatch", "The prepared remote command must retain the original operation"}
    case True{}: remote_prepared_mapped(RemoteState.permission(CommandCodec.command_json(request_command)), request, world)

def remote_original(~schedule: Bool -> @+decision:M.Decision() -> M.Decision(), authorization: Remote.Authorization,
  +request: Remote.Request, +request_command: M.Command, environment: Maybe<&2, D.Environment>, +world: M.World()) -> M.Decision():
  match authorization:
    case Remote.Admitted{}:
      Remote.Request{controller, epoch, id, intent} = request
      remote_authorized(~schedule,
        remote_prepared(String.eq(J.text(J.get(intent, "op")), J.text(J.get(CommandCodec.command_json(request_command), "op"))), request, request_command, world),
        request, request_command, environment, world)
    case other: remote_authorized(~schedule, other, request, request_command, environment, world)

def remote_update_candidate(~schedule: Bool -> @+decision:M.Decision() -> M.Decision(), +request: Remote.Request,
  request_command: M.Command, environment: Maybe<&2, D.Environment>, +world: M.World()) -> M.Decision():
  remote_original(~schedule, RemoteState.authorization(request, RemoteState.registry(world)), request, request_command, environment, world)

def remote_query_checked(same_operation: Bool, +request: Remote.Request, +world: M.World()) -> Remote.Authorization:
  match same_operation:
    case False{}: Remote.Denied{"remote_intent_mismatch", "The prepared remote command must retain the original operation"}
    case True{}: RemoteState.query_authorization(request, RemoteState.registry(world))

def remote_query_candidate(authorization: Remote.Authorization, query: M.Query, world: M.World()) -> M.Decision():
  match authorization:
    case Remote.Denied{code, reason}: reject(world, code, reason)
    case Remote.Replay{reply}: C.Decision{world, reply, Nil{}}
    case Remote.Admitted{}: Commands.meaning(Commands.Observe{query}, world)

def remote_candidate(~schedule: Bool -> @+decision:M.Decision() -> M.Decision(), +request: Remote.Request,
  request_command: M.Command, environment: Maybe<&2, D.Environment>, +world: M.World()) -> M.Decision():
  match request_command:
    case M.Observe{+query}:
      remote_query_candidate(remote_query_checked(String.eq(J.text(J.get(Remote.request_intent(request), "op")),
        J.text(J.get(CommandCodec.command_json(M.Observe{query}), "op"))), request, world), query, world)
    case other: remote_update_candidate(~schedule, request, other, environment, world)

def remote_command(~schedule: Bool -> @+decision:M.Decision() -> M.Decision(), +request: Remote.Request,
  +request_command: M.Command, +environment: Maybe<&2, D.Environment>, +world: M.World()) -> M.Decision():
  finish(M.durable(M.RemoteCommand{request, request_command, environment}), remote_candidate(~schedule, request, request_command, environment, world), world)

def input(~schedule: Bool -> @+decision:M.Decision() -> M.Decision(), +event: M.Input, +world: M.World()) -> M.Decision():
  match event:
    case M.UserCommand{request}: command(~schedule, request, world)
    case M.RemoteCommand{request, request_command, environment}: remote_command(~schedule, request, request_command, environment, world)
    case M.RemoteProbe{request, request_command}: deliver(False{}, RemoteState.probe(request_command, request, world), world)
    case M.RemoteCheck{controller, epoch}: deliver(False{}, RemoteState.check(controller, epoch, world), world)
    case other: update(~schedule, other, Protocol.input(other, world), world)
