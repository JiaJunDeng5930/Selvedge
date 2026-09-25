import Base
import ./bendlib/architecture.bend as A

# Selvedge is a persistent command/effect protocol. Start with Harness below.
# COMMANDS defines requested behavior; MODEL names the domain. The bindings in
# A attach every structure here to the actual operations, not a second model.

# Meaning fixes the entire decision: refusal or exact new world, reply and
# effects. External completions, internal invocations, finite scheduling and
# malformed native input all participate in this same refinement chain.
type Meaning is Type:
  Meaning{commands: A.CommandMeaning(),
    interactions: A.InputMeaning(),
    execution: A.ActionMeaning(),
    scheduling: A.SchedulingMeaning(),
    native_input: A.NativeInterface()}

# A finite protocol is a discrete dynamical system. Its simulation preserves
# complete decision receipts. Inputs/history act by free-monoid actions; a
# journal carries both its interpretation and its safety obligation. Decision
# combination is only a semigroup: the first reply and final world have owners.
type Composition is Type:
  Composition{traces: A.TraceSimulation(),
    state_machine: A.StateMachine(),
    journal: A.Journal,
    history: A.HistoryAction(),
    decisions: A.DecisionComposition()}

# Context cuts and interruption are idempotent projections, not inverse actions.
# Recovery distributes over independent task collections as a homomorphism.
# These facts do not permit replaying an external mutation of unknown outcome.
type Recovery is Type:
  Recovery{context: A.ContextProjection(),
    interruption: A.InterruptionProjection(),
    phase_normalization: A.RecoveryProjection(),
    batches: A.RecoveryBatches()}

# Queries are read-only, including their effects. Task views and branch results
# preserve collection composition rather than inventing a second task model.
type Observation is Type:
  Observation{queries: A.Observations(),
    tasks: A.TaskViews(),
    branches: A.BranchResults()}

type Harness is Type:
  Harness{meaning: Meaning, composition: Composition, recovery: Recovery, observation: Observation}

# Construction is mandatory in PROOF. No field is an unproved assertion.
# The OS/network/SQLite effect interpreter is an explicit external boundary;
# its ordering and cancellation contracts are exercised by integration tests.
law harness:
  Harness
