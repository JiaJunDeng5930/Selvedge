import Base
import ./LAWS.bend as Laws
import ./bendlib/architecture.bend as Concepts
import ./CONCEPTS.bend as Entry
import ./bendlib/proofs/algebra.bend as AlgebraProof
import ./bendlib/proofs/commit.bend as CommitProof
import ./bendlib/proofs/execution.bend as ExecutionProof
import ./bendlib/proofs/frontend.bend as FrontendProof
import ./bendlib/proofs/observations.bend as ObservationsProof
import ./bendlib/proofs/protocol.bend as ProtocolProof
import ./bendlib/proofs/safety.bend as SafetyProof
import ./bendlib/proofs/tasks.bend as TasksProof
import ./bendlib/proofs/traces.bend as TracesProof
import ./bendlib/proofs/operations.bend as OperationsProof
import ./bendlib/proofs/ui.bend as UIProof
import ./bendlib/proofs/plugins.bend as PluginsProof
import ./bendlib/proofs/results.bend as ResultsProof
import ./bendlib/proofs/reachability.bend as ReachabilityProof
import ./bendlib/workspace-architecture.bend as Workspace
import ./bendlib/proofs/workspaces.bend as WorkspacesProof

# Assemble the conceptual program only after every local obligation is closed.

def Entry.harness():
  Entry.Harness{
    Entry.Meaning{Concepts.commands(), Concepts.interactions(), Concepts.actions(), Concepts.scheduling(), Concepts.native_interface()},
    Entry.Composition{Concepts.protocol_reachability(), Concepts.traces(), Concepts.task_machine(), Concepts.persistence(), Concepts.history(), Concepts.decisions()},
    Entry.Recovery{Concepts.context(), Concepts.interruption(), Concepts.recovery(), Concepts.recovery_batches()},
    Entry.Observation{Concepts.observations(), Concepts.task_views(), Concepts.branch_results(), Concepts.surface()},
    Entry.Concurrency{Concepts.operation_rights(), Concepts.announcement(), Concepts.notifications(), Concepts.coordination()},
    Entry.Extensibility{Concepts.plugin_boundary(), Concepts.result_boundary()}, Workspace.context_boundary()}
