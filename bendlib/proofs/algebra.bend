import Base
import ../../MODEL.bend as M
import ../../PROGRAM.bend as P
import ../../LAWS.bend as Laws
import ../tasks.bend as T
import ../stdlib.bend as Std
import ../json.bend as J
import ../../COMMANDS.bend as Commands
import ../structures.bend as S
import ../architecture.bend as Concepts
import ../traces.bend as Traces
import ../transcript.bend as Transcript
import ../protocol.bend as Protocol
import ./commit.bend as CommitProof
import ./execution.bend as ExecutionProof
import ./frontend.bend as FrontendProof
import ./observations.bend as ObservationsProof
import ./safety.bend as SafetyProof
import ./tasks.bend as TasksProof
import ./traces.bend as TracesProof

# Local proof obligations for the algebra boundary. No runtime policy lives here.

def Concepts.recovery_batches():
  S.Homomorphism{S.list_monoid(M.Task), S.list_monoid(M.Task), {==},
    (first => second => Std.map_app(~M.Task, ~M.Task, ~Protocol.recover, first, second))}

def Concepts.task_views():
  S.Homomorphism{S.list_monoid(M.Task), S.list_monoid(J.Json), {==},
    (first => second => Std.map_app(~M.Task, ~J.Json, ~T.summary, first, second))}

def Concepts.branch_results():
  S.Homomorphism{S.list_monoid(M.Task), S.list_monoid(J.Json), {==},
    (first => second => Std.map_app(~M.Task, ~J.Json, ~Commands.identity, first, second))}

def Laws.recovery_partition(first, second):
  S.homomorphism_join(+List<M.Task>, +List<M.Task>, Nil{}, S.append(M.Task), Nil{}, S.append(M.Task),
    Protocol.recovery, Concepts.recovery_batches(), first, second)

def Laws.task_view_partition(first, second):
  S.homomorphism_join(+List<M.Task>, +List<J.Json>, Nil{}, S.append(M.Task), Nil{}, S.append(J.Json),
    T.summaries, Concepts.task_views(), first, second)

def Laws.branch_result_partition(first, second):
  S.homomorphism_join(+List<M.Task>, +List<J.Json>, Nil{}, S.append(M.Task), Nil{}, S.append(J.Json),
    Commands.identities, Concepts.branch_results(), first, second)

def Laws.recovery_view_composition(tasks):
  S.map_composition(~M.Task, ~M.Task, ~J.Json, ~Protocol.recover, ~T.summary, tasks)

def decision_associativity(+first: M.Decision, +second: M.Decision, +third: M.Decision) ->
  {P.combine(P.combine(first, second), third) == P.combine(first, P.combine(second, third)) : M.Decision}:
  match first second third:
    case M.Decision{old, +reply, +a} M.Decision{middle, ignored, +b} M.Decision{+last, also_ignored, +c}:
      Equal.cong(+List<M.Effect>, M.Decision, (effects => M.Decision{last, reply, effects}),
        List.append(&2, M.Effect, List.append(&2, M.Effect, a, b), c),
        List.append(&2, M.Effect, a, List.append(&2, M.Effect, b, c)),
        S.monoid_associative(+List<M.Effect>, Nil{}, S.append(M.Effect), Concepts.effects(), a, b, c))

def Concepts.commands():
  S.Refinement{(command => world => Laws.command_transition(command, world))}

def Concepts.interactions():
  S.Refinement{(input => world => Laws.interaction_transition(input, world))}

def Concepts.task_machine():
  S.InvariantSystem{Laws.initial_world_valid(),
    (state => input => evidence => Laws.transition_preserves_world(state, input, evidence))}

def Concepts.journal_interpretation(world, inputs):
  {==}

def Concepts.history_interpretation(history, messages):
  {==}

def Concepts.decisions():
  S.Associative{(first => second => third => decision_associativity(first, second, third))}

def Concepts.context():
  S.Projection{(history => Laws.context_projection_idempotent(history))}

def Concepts.recovery():
  S.Projection{(phase => Laws.recover_phase_idempotent(phase))}

def Concepts.interruption():
  S.Projection{(task => Laws.interrupt_idempotent(task))}

def Concepts.observations():
  S.ReadOnly{(query => world => Laws.observation_preserves_world(query, world)),
    (query => world => Laws.observation_has_no_effects(query, world))}

def Concepts.actions():
  S.Refinement{(action => world => Laws.execution_semantics(action, world))}

def Concepts.scheduling():
  S.Refinement{(enabled => decision => Laws.scheduling_semantics(enabled, decision))}

def bind_trace_simulation(standard:
  S.Simulation<Transcript.Tape, Transcript.Tape, Traces.implementation, Transcript.step,
    Transcript.identity, Std.iter(~Transcript.Tape, ~Traces.implementation), Std.iter(~Transcript.Tape, ~Transcript.step)>) ->
  Concepts.TraceSimulation():
  S.Simulation{S.Dynamics{source_zero, source_successor, source_partition},
    S.Dynamics{target_zero, target_successor, target_partition}, commutes, finite_runs} = standard
  S.Simulation{
    S.Dynamics{(state => source_zero(state)), (count => state => source_successor(count, state)),
      (first => second => state => source_partition(first, second, state))},
    S.Dynamics{(state => target_zero(state)), (count => state => target_successor(count, state)),
      (first => second => state => target_partition(first, second, state))},
    (state => commutes(state)), (count => state => finite_runs(count, state))}

def Concepts.traces():
  bind_trace_simulation(S.simulation(~Transcript.Tape, ~Transcript.Tape, ~Traces.implementation, ~Transcript.step,
    ~Transcript.identity, ~(tape => Laws.trace_step(tape))))

def Concepts.native_interface():
  S.Refinement{(tokens => world => Laws.frontend_packet(tokens, world))}

def Concepts.persistence():
  Concepts.Journal{Concepts.journal(),
    (world => inputs => Concepts.journal_interpretation(world, inputs)),
    (inputs => world => evidence => Laws.replay_preserves_world(inputs, world, evidence))}
