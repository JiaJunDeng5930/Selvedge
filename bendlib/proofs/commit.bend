import Base
import ../../MODEL.bend as M
import ../../PROGRAM.bend as P
import ../../LAWS.bend as Laws
import ../json.bend as J
import ../presentation.bend as View
import ../../INVARIANTS.bend as I
import ../../COMMANDS.bend as Commands
import ../commit.bend as Commit
import ../execution.bend as Execution
import ../protocol.bend as Protocol
import ./execution.bend as ExecutionProof
import ./protocol.bend as ProtocolProof
import ../../UI.bend as UI
import ../notifications.bend as Notifications

# Local proof obligations for the commit boundary. No runtime policy lives here.

def guard_semantics(+state_valid: Bool, +change_valid: Bool, +decision: M.Decision, +previous: M.World) ->
  {P.admitted(state_valid, change_valid, decision, previous) == Commit.guard(state_valid, change_valid, decision, previous) : M.Decision}:
  match state_valid change_valid:
    case True{} True{}: {==}
    case True{} False{}: {==}
    case False{} True{}: {==}
    case False{} False{}: {==}

def validate_semantics(+decision: M.Decision, +previous: M.World) ->
  {P.check_live(decision, previous) == Commit.validate(decision, previous) : M.Decision}:
  match decision:
    case M.Decision{+world, +reply, +effects}:
      +decision : M.Decision = M.Decision{world, reply, effects}
      guard_semantics(I.world(world), I.decision(previous, decision), decision, previous)

def live_semantics(+decision: M.Decision) -> {P.live_decision(decision) == Commit.live(decision) : M.Decision}:
  match decision:
    case M.Decision{M.World{tasks, next_task, next_ticket, environment, limits, projects, board}, reply, effects}: {==}

def Laws.commit_semantics(decision, previous):
  +live = P.live_decision(decision)
  Equal.trans(M.Decision, P.checked(decision, previous), Commit.validate(live, previous), Commit.checked(decision, previous),
    validate_semantics(live, previous),
    Equal.cong(M.Decision, M.Decision, (value => Commit.validate(value, previous)),
      live, Commit.live(decision), live_semantics(decision)))

def sized_semantics(+fits: Bool, +decision: M.Decision, +previous: M.World) ->
  {P.output_admitted(fits, decision, previous) == Commit.sized(fits, decision, previous) : M.Decision}:
  match fits:
    case True{}: {==}
    case False{}: {==}

def rendered_semantics(+rendered: Result<&2, &2, String, String>, +decision: M.Decision, +previous: M.World) ->
  {P.admission(rendered, decision, previous) == Commit.rendered(rendered, decision, previous) : M.Decision}:
  match rendered:
    case Fail{error}: {==}
    case Done{text}:
      sized_semantics(Nat.is_le(J.utf8_length(text), U32.to_nat(Commit.frame_bytes(previous))), decision, previous)

def Laws.output_semantics(durable, decision, previous):
  rendered_semantics(J.render(Commit.render_budget(previous), J.One{View.envelope(durable, decision)}), decision, previous)

def after_apply_semantics(+input: M.Input, +decision: M.Decision, +previous: M.World) ->
  {P.after_apply(input, decision, previous) == Commit.update(~Execution.scheduled, input, decision, previous) : M.Decision}:
  +durable = M.durable(input)
  +candidate = Notifications.decorate(input, previous, UI.decorate(input, P.scheduled(Commit.schedules(input, decision), decision)))
  first = Equal.trans(M.Decision, P.after_apply(input, decision, previous), Commit.deliver(durable, P.checked(candidate, previous), previous),
    Commit.update(~P.scheduled, input, decision, previous), Laws.output_semantics(durable, P.checked(candidate, previous), previous),
    Equal.cong(M.Decision, M.Decision, (value => Commit.deliver(durable, value, previous)),
      P.checked(candidate, previous), Commit.checked(candidate, previous), Laws.commit_semantics(candidate, previous)))
  Equal.trans(M.Decision, P.after_apply(input, decision, previous), Commit.update(~P.scheduled, input, decision, previous),
    Commit.update(~Execution.scheduled, input, decision, previous), first,
    Equal.cong(M.Decision, M.Decision, (value => Commit.finish(durable, Notifications.decorate(input, previous, UI.decorate(input, value)), previous)),
      P.scheduled(Commit.schedules(input, decision), decision), Execution.scheduled(Commit.schedules(input, decision), decision), Laws.scheduling_semantics(Commit.schedules(input, decision), decision)))

def updated_command_semantics(+command: M.Command, +world: M.World) ->
  {P.update(M.UserCommand{command}, world) == Commit.update(~Execution.scheduled, M.UserCommand{command}, Commands.command(command, world), world) : M.Decision}:
  +input : M.Input = M.UserCommand{command}
  +meaning = Commands.command(command, world)
  Equal.trans(M.Decision, P.update(input, world), P.after_apply(input, meaning, world),
    Commit.update(~Execution.scheduled, input, meaning, world),
    Equal.cong(M.Decision, M.Decision, (decision => P.after_apply(input, decision, world)),
      P.apply_command(command, world), meaning, Laws.command_semantics(command, world)), after_apply_semantics(input, meaning, world))

def Laws.command_transition(command, world):
  match command:
    case M.BoardCommand{command}: updated_command_semantics(M.BoardCommand{command}, world)
    case M.Observe{query}: Laws.output_semantics(False{}, P.observe(query, world), world)
    case M.Create{profile, reasoning, message, options}: updated_command_semantics(M.Create{profile, reasoning, message, options}, world)
    case M.Send{id, message}: updated_command_semantics(M.Send{id, message}, world)
    case M.Steer{id, message}: updated_command_semantics(M.Steer{id, message}, world)
    case M.Cancel{id, ticket}: updated_command_semantics(M.Cancel{id, ticket}, world)
    case M.ChangeStatus{id, control}: updated_command_semantics(M.ChangeStatus{id, control}, world)
    case M.Fork{id, count, messages, options}: updated_command_semantics(M.Fork{id, count, messages, options}, world)
    case M.Compact{id, summary}: updated_command_semantics(M.Compact{id, summary}, world)
    case M.CreateProject{name, workspace, guidance}: updated_command_semantics(M.CreateProject{name, workspace, guidance}, world)
    case M.UpdateProject{id, name, workspace, guidance}: updated_command_semantics(M.UpdateProject{id, name, workspace, guidance}, world)
    case M.DeleteProject{id}: updated_command_semantics(M.DeleteProject{id}, world)
    case M.ReviewApproval{id, operation, outcome}: updated_command_semantics(M.ReviewApproval{id, operation, outcome}, world)

def updated_input_semantics(+input: M.Input, +world: M.World) ->
  {P.update(input, world) == Commit.update(~Execution.scheduled, input, Protocol.input(input, world), world) : M.Decision}:
  +meaning = Protocol.input(input, world)
  Equal.trans(M.Decision, P.update(input, world), P.after_apply(input, meaning, world),
    Commit.update(~Execution.scheduled, input, meaning, world),
    Equal.cong(M.Decision, M.Decision, (decision => P.after_apply(input, decision, world)),
      P.apply(input, world), meaning, Laws.input_semantics(input, world)), after_apply_semantics(input, meaning, world))

def Laws.interaction_transition(input, world):
  match input:
    case M.UserCommand{command}: Laws.command_transition(command, world)
    case M.UserInterface{state, event}: updated_input_semantics(M.UserInterface{state, event}, world)
    case M.ModelCompleted{id, ticket, outcome}: updated_input_semantics(M.ModelCompleted{id, ticket, outcome}, world)
    case M.ReasoningCompleted{id, ticket, outcome}: updated_input_semantics(M.ReasoningCompleted{id, ticket, outcome}, world)
    case M.BoardTextCompleted{id, ticket, outcome}: updated_input_semantics(M.BoardTextCompleted{id, ticket, outcome}, world)
    case M.ToolCompleted{id, ticket, value, error}: updated_input_semantics(M.ToolCompleted{id, ticket, value, error}, world)
    case M.HookCompleted{id, ticket, outcome}: updated_input_semantics(M.HookCompleted{id, ticket, outcome}, world)
    case M.AfterCompleted{id, operation, ticket, outcome}: updated_input_semantics(M.AfterCompleted{id, operation, ticket, outcome}, world)
    case M.ApprovalCompleted{id, ticket, outcome}: updated_input_semantics(M.ApprovalCompleted{id, ticket, outcome}, world)
    case M.Configure{environment}: updated_input_semantics(M.Configure{environment}, world)
    case M.Recover{}: updated_input_semantics(M.Recover{}, world)
    case M.Continue{}: updated_input_semantics(M.Continue{}, world)

def Laws.rejected_delivery_unchanged(decision, world):
  {==}

def Laws.rejected_delivery_no_effects(decision, world):
  {==}
