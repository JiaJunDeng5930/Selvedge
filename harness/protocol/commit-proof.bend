import Base
import ../../bendlib/categories.bend as Categories
import ../features/MODEL.bend as Features
import ../DOMAIN.bend as D
import ../../bendlib/component.bend as C
import ../MODEL.bend as M
import ../PROGRAM.bend as P
import ../LAWS.bend as Laws
import ../../bendlib/json.bend as J
import ../transport/presentation.bend as View
import ../INVARIANTS.bend as I
import ../COMMANDS.bend as Commands
import ./COMMIT.bend as Commit
import ../execution/PROGRAM.bend as Execution
import ./PROGRAM.bend as Protocol
import ../execution/PROOF.bend as ExecutionProof
import ./PROOF.bend as ProtocolProof
import ../execution/notifications.bend as Notifications

# Local proof obligations for the commit boundary. No runtime policy lives here.
def validate_observed(+first: Bool, +second: Bool, +decision: M.Decision(), +previous: M.World(), state_observed: {Commit.state_safe(decision) == first : Bool}, change_observed: {Commit.effect_authorized(previous, decision) == second : Bool}) ->
  {P.admitted(first, second, decision, previous) == Commit.validate_admitted(previous, Categories.admit_intersection_checked(M.Decision(), Commit.state_safe, candidate => Commit.effect_authorized(previous, candidate), decision, first, second, state_observed, change_observed)) : M.Decision()}:
  match first second:
    case True{} True{}: {==}
    case True{} False{}: {==}
    case False{} True{}: {==}
    case False{} False{}: {==}

def validate_semantics(+decision: M.Decision(), +previous: M.World()) ->
  {P.check_live(decision, previous) == Commit.validate(decision, previous) : M.Decision()}:
  match decision:
    case C.Decision{+world, +reply, +effects}:
      +decision : M.Decision() = C.Decision{world, reply, effects}
      validate_observed(I.world(world), I.decision(previous, decision), decision, previous, {==}, {==})

def live_semantics(+decision: M.Decision()) -> {P.live_decision(decision) == Commit.live(decision) : M.Decision()}:
  match decision:
    case C.Decision{C.Frame{D.State{tasks, next_task, next_ticket, environment, limits, projects}, +board}, reply, effects}: {==}

def Laws.commit_semantics(decision, previous):
  {==}

def sized_semantics(+fits: Bool, +text: String, +decision: M.Decision(), +previous: M.World(), observed: {Commit.envelope_fits(previous, text) == fits : Bool}) ->
  {P.output_admitted(fits, decision, previous) == Commit.sized_admitted(previous, Categories.admit_checked(String, value => Commit.envelope_fits(previous, value), text, fits, observed), decision) : M.Decision()}:
  match fits:
    case True{}: {==}
    case False{}: {==}

def rendered_semantics(+rendered: Result<&2, &2, String, String>, +decision: M.Decision(), +previous: M.World()) ->
  {P.admission(rendered, decision, previous) == Commit.rendered(rendered, decision, previous) : M.Decision()}:
  match rendered:
    case Fail{error}: {==}
    case Done{+text}:
      sized_semantics(Commit.envelope_fits(previous, text), text, decision, previous, {==})

def Laws.output_semantics(durable, decision, previous):
  {==}

def after_apply_semantics(+input: M.Input, +decision: M.Decision(), +previous: M.World()) ->
  {P.after_apply(input, decision, previous) == Commit.update(~Execution.scheduled, input, decision, previous) : M.Decision()}:
  +durable = M.durable(input)
  +candidate = Commit.configuration_checked(input, Notifications.decorate(input, previous, P.scheduled(Commit.schedules(input, decision), decision)), previous)
  first = Equal.trans(M.Decision(), P.after_apply(input, decision, previous), Commit.deliver(durable, P.checked(candidate, previous), previous),
    Commit.update(~P.scheduled, input, decision, previous), Laws.output_semantics(durable, P.checked(candidate, previous), previous),
    Equal.cong(M.Decision(), M.Decision(), (value => Commit.deliver(durable, value, previous)),
      P.checked(candidate, previous), Commit.checked(candidate, previous), Laws.commit_semantics(candidate, previous)))
  Equal.trans(M.Decision(), P.after_apply(input, decision, previous), Commit.update(~P.scheduled, input, decision, previous),
    Commit.update(~Execution.scheduled, input, decision, previous), first,
    Equal.cong(M.Decision(), M.Decision(), (value => Commit.finish(durable, Commit.configuration_checked(input, Notifications.decorate(input, previous, value), previous), previous)),
      P.scheduled(Commit.schedules(input, decision), decision), Execution.scheduled(Commit.schedules(input, decision), decision), Laws.scheduling_semantics(Commit.schedules(input, decision), decision)))

def updated_command_semantics(+command: M.Command, +world: M.World()) ->
  {P.update(M.UserCommand{command}, world) == Commit.update(~Execution.scheduled, M.UserCommand{command}, Commands.command(command, world), world) : M.Decision()}:
  +input : M.Input = M.UserCommand{command}
  +meaning = Commands.command(command, world)
  Equal.trans(M.Decision(), P.update(input, world), P.after_apply(input, meaning, world),
    Commit.update(~Execution.scheduled, input, meaning, world),
    Equal.cong(M.Decision(), M.Decision(), (decision => P.after_apply(input, decision, world)),
      P.apply_command(command, world), meaning, Laws.command_semantics(command, world)), after_apply_semantics(input, meaning, world))

def Laws.command_transition(command, world):
  match command:
    case M.FeatureCommand{command}: updated_command_semantics(M.FeatureCommand{command}, world)
    case M.Observe{query}: Laws.output_semantics(False{}, P.observe(query, world), world)
    case M.ConfigureTaskExecution{id, profile, reasoning, sandbox, approval}: updated_command_semantics(M.ConfigureTaskExecution{id, profile, reasoning, sandbox, approval}, world)
    case M.Create{profile, reasoning, message, options}: updated_command_semantics(M.Create{profile, reasoning, message, options}, world)
    case M.Send{id, message}: updated_command_semantics(M.Send{id, message}, world)
    case M.Steer{id, message}: updated_command_semantics(M.Steer{id, message}, world)
    case M.Cancel{id, ticket}: updated_command_semantics(M.Cancel{id, ticket}, world)
    case M.ChangeStatus{id, control}: updated_command_semantics(M.ChangeStatus{id, control}, world)
    case M.Fork{id, count, messages, options}: updated_command_semantics(M.Fork{id, count, messages, options}, world)
    case M.Compact{id, summary}: updated_command_semantics(M.Compact{id, summary}, world)
    case M.CreateProject{name, workspace, guidance, create_worktree}: updated_command_semantics(M.CreateProject{name, workspace, guidance, create_worktree}, world)
    case M.UpdateProject{id, name, workspace, guidance, create_worktree}: updated_command_semantics(M.UpdateProject{id, name, workspace, guidance, create_worktree}, world)
    case M.DeleteProject{id}: updated_command_semantics(M.DeleteProject{id}, world)
    case M.ReviewApproval{id, operation, outcome}: updated_command_semantics(M.ReviewApproval{id, operation, outcome}, world)

def updated_input_semantics(+input: M.Input, +world: M.World()) ->
  {P.update(input, world) == Commit.update(~Execution.scheduled, input, Protocol.input(input, world), world) : M.Decision()}:
  +meaning = Protocol.input(input, world)
  Equal.trans(M.Decision(), P.update(input, world), P.after_apply(input, meaning, world),
    Commit.update(~Execution.scheduled, input, meaning, world),
    Equal.cong(M.Decision(), M.Decision(), (decision => P.after_apply(input, decision, world)),
      P.apply(input, world), meaning, Laws.input_semantics(input, world)), after_apply_semantics(input, meaning, world))

def Laws.interaction_transition(input, world):
  match input:
    case M.RemoteCommand{request, command, environment}: {==}
    case M.RemoteProbe{request, command}: {==}
    case M.RemoteCheck{controller, epoch}: {==}
    case M.UserCommand{command}: Laws.command_transition(command, world)
    case M.ContextObserved{id, ticket, outcome}: updated_input_semantics(M.ContextObserved{id, ticket, outcome}, world)
    case M.ModelCompleted{id, ticket, outcome}: updated_input_semantics(M.ModelCompleted{id, ticket, outcome}, world)
    case M.ReasoningCompleted{id, ticket, outcome}: updated_input_semantics(M.ReasoningCompleted{id, ticket, outcome}, world)
    case M.FeatureCompleted{completion}: updated_input_semantics(M.FeatureCompleted{completion}, world)
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
