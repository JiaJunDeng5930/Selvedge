import Base
import ./MODEL.bend as M
import ./PROGRAM.bend as P
import ./INVARIANTS.bend as I
import ./bendlib/tasks.bend as T
import ./bendlib/commit.bend as Commit
import ./bendlib/structures.bend as S
import ./bendlib/protocol.bend as Protocol
import ./bendlib/execution.bend as Execution
import ./bendlib/json.bend as J
import ./COMMANDS.bend as Commands

# Conceptual entry: begin with Harness below, then follow its named structures.
# Persistent tasks are a command/effect protocol over a deterministic machine.
# COMMANDS owns command meaning; MODEL names the domain; Protocol owns completion
# and accepted-call meaning. No lifecycle or JSON parsing detail lives here.
# The values below identify standard structures on those very program objects.
# PROOF supplies application-specific correspondence, not fresh algebra theory.

def specification(command: M.Command, world: M.World) -> M.Decision:
  Commit.command(~Execution.scheduled, command, world)

def implementation(command: M.Command, world: M.World) -> M.Decision:
  P.transition(M.UserCommand{command}, world)

law commands:
  S.Refinement<M.World, M.Command, M.Decision, specification, implementation>

def interaction_specification(input: M.Input, world: M.World) -> M.Decision:
  Commit.input(~Execution.scheduled, input, world)

def interaction_implementation(input: M.Input, world: M.World) -> M.Decision:
  P.transition(input, world)

def observation(query: M.Query, world: M.World) -> M.Decision:
  P.transition(M.UserCommand{M.Observe{query}}, world)

# Constructing the program object requires all these correspondences for the
# production operations, not merely a prose declaration or a safe transition.
type Harness is Type:
  Harness{
    commands: S.Refinement<M.World, M.Command, M.Decision, specification, implementation>,
    interactions: S.Refinement<M.World, M.Input, M.Decision, interaction_specification, interaction_implementation>,
    machine: S.InvariantSystem<M.World, M.Input, M.initial(), P.next, I.world>,
    journal: S.RightAction<M.World, +List<M.Input>, Nil{}, S.append(M.Input), S.act(~M.World, ~M.Input, ~P.next)>,
    observations: S.ReadOnly<M.World, M.Query, M.Decision, M.Effect, observation, P.decision_world, P.decision_effects>,
    recovery: S.Homomorphism<+List<M.Task>, +List<M.Task>, Nil{}, S.append(M.Task), Nil{}, S.append(M.Task), Protocol.recovery>,
    decisions: S.Semigroup<M.Decision, P.combine>,
    context: S.Projection<M.History, M.context_history>,
    interruption: S.Projection<M.Task, T.interrupt>}

law harness:
  Harness

law interactions:
  S.Refinement<M.World, M.Input, M.Decision, interaction_specification, interaction_implementation>

law task_machine:
  S.InvariantSystem<M.World, M.Input, M.initial(), P.next, I.world>

# Inputs, messages, queued user text, and effect intents use the same free-monoid
# theory. Replay and history extension are its right actions, not special cases.
def inputs() -> S.Monoid<+List<M.Input>, Nil{}, S.append(M.Input)>:
  S.list_monoid(M.Input)

def inbox() -> S.Monoid<+List<String>, Nil{}, S.append(String)>:
  S.list_monoid(String)

def effects() -> S.Monoid<+List<M.Effect>, Nil{}, S.append(M.Effect)>:
  S.list_monoid(M.Effect)

def journal() -> S.RightAction<M.World, +List<M.Input>, Nil{}, S.append(M.Input), S.act(~M.World, ~M.Input, ~P.next)>:
  S.list_action(~M.World, ~M.Input, ~P.next)

def history() -> S.RightAction<M.History, +List<M.Message>, Nil{}, S.append(M.Message), S.act(~M.History, ~M.Message, ~M.history_step)>:
  S.list_action(~M.History, ~M.Message, ~M.history_step)

law journal_interpretation:
  for +world: M.World
  for +inputs: +List<M.Input>
  {P.replay(inputs, world) == S.act(~M.World, ~M.Input, ~P.next, world, inputs) : M.World}

law history_interpretation:
  for +history: M.History
  for +messages: +List<M.Message>
  {M.history_append(messages, history) == S.act(~M.History, ~M.Message, ~M.history_step, history, messages) : M.History}

# Decisions have associative composition, but no global identity: the first
# reply and the last world have different ownership. Only effects form a monoid.
law decisions:
  S.Semigroup<M.Decision, P.combine>

# A context cut, recovery normalization, and interruption are three different
# idempotent projections. Idempotence does not assert summary fidelity or undo.
law context:
  S.Projection<M.History, M.context_history>

law recovery:
  S.Projection<M.Phase, T.recover_phase>

law interruption:
  S.Projection<M.Task, T.interrupt>

law observations:
  S.ReadOnly<M.World, M.Query, M.Decision, M.Effect, observation, P.decision_world, P.decision_effects>

# Batch recovery and public views are monoid homomorphisms. Their partition and
# composition laws are imported map theorems, not special recovery/API proofs.
law recovery_batches:
  S.Homomorphism<+List<M.Task>, +List<M.Task>, Nil{}, S.append(M.Task), Nil{}, S.append(M.Task), Protocol.recovery>

law task_views:
  S.Homomorphism<+List<M.Task>, +List<J.Json>, Nil{}, S.append(M.Task), Nil{}, S.append(J.Json), T.summaries>

law branch_results:
  S.Homomorphism<+List<M.Task>, +List<J.Json>, Nil{}, S.append(M.Task), Nil{}, S.append(J.Json), Commands.identities>
