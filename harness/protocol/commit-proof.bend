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

# The output bound consumes and preserves the existing domain certificate.
def sized_projection(+previous: M.World(), admission: Maybe<&1, Categories.Membership<String, Commit.bounded_envelope(previous)>>,
  member: Commit.Committed<previous>) ->
  {Commit.value(previous, Commit.construct_sized(previous, admission, member)) ==
    Commit.sized_admitted(previous, admission, Commit.value(previous, member)) : M.Decision()}:
  match admission:
    case Some{Categories.Membership{text, bounded}}: {==}
    case None{}: {==}

def rendered_projection(result: Result<&2, &2, String, String>, +previous: M.World(), member: Commit.Committed<previous>) ->
  {Commit.value(previous, Commit.construct_rendered(result, previous, member)) ==
    Commit.rendered(result, Commit.value(previous, member), previous) : M.Decision()}:
  match result:
    case Fail{error}: {==}
    case Done{text}: sized_projection(previous, Categories.admit(String, value => Commit.envelope_fits(previous, value), text), member)

def delivery_projection(+durable: Bool, +previous: M.World(), member: Commit.Committed<previous>) ->
  {Commit.value(previous, Commit.construct_delivery(durable, previous, member)) ==
    Commit.deliver(durable, Commit.value(previous, member), previous) : M.Decision()}:
  Commit.Committed{+decision, certificate} = member
  rendered_projection(J.render(D.state_render_budget(C.local(D.State, Features.State(), previous)), J.One{View.envelope(durable, decision)}),
    previous, Commit.Committed{decision, certificate})

def observation_projection(query: M.Query, +world: M.World()) ->
  {P.transition(M.UserCommand{M.Observe{query}}, world) == Commit.deliver(False{}, P.observe(query, world), world) : M.Decision()}:
  delivery_projection(False{}, world, Commit.Committed{P.observe(query, world), Fail{({==}, {==})}})

def after_apply_semantics(+input: M.Input, +decision: M.Decision(), +previous: M.World()) ->
  {P.after_apply(input, decision, previous) == Commit.update(~Execution.scheduled, input, decision, previous) : M.Decision()}:
  Equal.cong(M.Decision(), M.Decision(),
    (value => Commit.finish(M.durable(input), Commit.configuration_checked(input, Notifications.decorate(input, previous, value), previous), previous)),
    P.scheduled(Commit.schedules(input, decision), decision), Execution.scheduled(Commit.schedules(input, decision), decision),
    Laws.scheduling_semantics(Commit.schedules(input, decision), decision))

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
    case M.Observe{query}: observation_projection(query, world)
    case M.ConfigureTaskExecution{id, profile, reasoning, sandbox, approval}: updated_command_semantics(M.ConfigureTaskExecution{id, profile, reasoning, sandbox, approval}, world)
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

def updated_input_semantics(+input: M.Input, +world: M.World()) ->
  {P.update(input, world) == Commit.update(~Execution.scheduled, input, Protocol.input(input, world), world) : M.Decision()}:
  +meaning = Protocol.input(input, world)
  Equal.trans(M.Decision(), P.update(input, world), P.after_apply(input, meaning, world),
    Commit.update(~Execution.scheduled, input, meaning, world),
    Equal.cong(M.Decision(), M.Decision(), (decision => P.after_apply(input, decision, world)),
      P.apply(input, world), meaning, Laws.input_semantics(input, world)), after_apply_semantics(input, meaning, world))

def Laws.interaction_transition(input, world):
  match input:
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
