import Base
import ./component.bend as Component
import ../harness/DOMAIN.bend as D
import ../harness/MODEL.bend as M
import ../harness/PROGRAM.bend as P
import ../harness/LAWS.bend as Laws
import ../harness/tasks/PROGRAM.bend as T
import ./stdlib.bend as Std
import ./json.bend as J
import ../harness/COMMANDS.bend as Commands
import ./theory.bend as Theory
import ../harness/CONTRACT.bend as Concepts
import ../harness/history/PROGRAM.bend as Traces
import ../harness/conversation/MODEL.bend as Transcript
import ../harness/protocol/PROGRAM.bend as Protocol
import ../harness/protocol/commit-proof.bend as CommitProof
import ../harness/execution/PROOF.bend as ExecutionProof
import ../harness/transport/PROOF.bend as FrontendProof
import ../harness/PROOF.bend as ObservationsProof
import ../harness/tasks/PROOF.bend as TasksProof
import ../harness/history/PROOF.bend as TracesProof

# Local proof obligations for the algebra boundary. No runtime policy lives here.
def nat_add_zero(+value: Nat) -> {Nat.add(value, 0n) == value : Nat}:
  match value:
    case 0n: {==}
    case 1n+rest: Equal.cong(Nat, Nat, (n => 1n+n), Nat.add(rest, 0n), rest, nat_add_zero(rest))

def nat_add_assoc(+first: Nat, +second: Nat, +third: Nat) ->
  {Nat.add(Nat.add(first, second), third) == Nat.add(first, Nat.add(second, third)) : Nat}:
  match first:
    case 0n: {==}
    case 1n+rest: Equal.cong(Nat, Nat, (n => 1n+n), Nat.add(Nat.add(rest, second), third), Nat.add(rest, Nat.add(second, third)), nat_add_assoc(rest, second, third))

def nat_add_succ(+first: Nat, +second: Nat) ->
  {Nat.add(first, 1n+second) == 1n+Nat.add(first, second) : Nat}:
  match first:
    case 0n: {==}
    case 1n+rest: Equal.cong(Nat, Nat, (n => 1n+n), Nat.add(rest, 1n+second), 1n+Nat.add(rest, second), nat_add_succ(rest, second))

def Concepts.recovery_batches():
  (tasks => {==})

def Concepts.task_views():
  (tasks => {==})

def Concepts.branch_results():
  (tasks => {==})

def Laws.recovery_partition(first, second):
  Std.map_app(~D.Task, ~D.Task, ~Protocol.recover, first, second)

def Laws.task_view_partition(first, second):
  Std.map_app(~D.Task, ~J.Json, ~T.summary, first, second)

def Laws.branch_result_partition(first, second):
  Std.map_app(~D.Task, ~J.Json, ~Commands.identity, first, second)

def Laws.recovery_view_composition(tasks):
  Std.map_map(~D.Task, ~D.Task, ~J.Json, ~Protocol.recover, ~T.summary, tasks)

def decision_associativity(+first: M.Decision(), +second: M.Decision(), +third: M.Decision()) ->
  {P.combine(P.combine(first, second), third) == P.combine(first, P.combine(second, third)) : M.Decision()}:
  match first second third:
    case Component.Decision{old, +reply, +a} Component.Decision{middle, ignored, +b} Component.Decision{+last, also_ignored, +c}:
      Equal.cong(+List<M.Effect()>, M.Decision(), (effects => Component.Decision{last, reply, effects}),
        List.append(&2, M.Effect(), List.append(&2, M.Effect(), a, b), c),
        List.append(&2, M.Effect(), a, List.append(&2, M.Effect(), b, c)),
        Theory.append_associative(M.Effect(), a, b, c))

def Concepts.commands():
  (command => world => Laws.command_transition(command, world))

def Concepts.interactions():
  (input => world => Laws.interaction_transition(input, world))

def Concepts.task_machine():
  (Laws.initial_world_valid(),
    (state => input => evidence => Laws.transition_preserves_world(state, input, evidence)))

def Concepts.journal_interpretation(world, inputs):
  {==}

def Concepts.decisions():
  (first => second => third => decision_associativity(first, second, third))

def Concepts.context():
  (history => Laws.context_projection_idempotent(history))

def Concepts.recovery():
  (phase => Laws.recover_phase_idempotent(phase))

def Concepts.interruption():
  (task => Laws.interrupt_idempotent(task))

def Concepts.observations():
  (+query => +world => (Laws.observation_preserves_world(query, world), Laws.observation_has_no_effects(query, world)))

def Concepts.actions():
  (action => world => Laws.execution_semantics(action, world))

def Concepts.scheduling():
  (enabled => decision => Laws.scheduling_semantics(enabled, decision))

# Only the one-step correspondence is local. Nat.iter_swap_gen supplies every
# finite run, including its complete decision receipts; there is no local
# Dynamics/Simulation hierarchy or copied induction theorem.

def Concepts.traces():
  (count => tape => Std.iter_swap_gen(~Transcript.Tape, ~Transcript.Tape, ~Transcript.identity,
    ~Traces.implementation, ~Transcript.step, ~(tape => Laws.trace_step(tape)), count, tape))

def Concepts.native_interface():
  (tokens => world => Laws.frontend_packet(tokens, world))

def Concepts.persistence():
  Concepts.Journal{
    (world => inputs => Concepts.journal_interpretation(world, inputs)),
    (inputs => world => evidence => Laws.replay_preserves_world(inputs, world, evidence))}
