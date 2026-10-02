import Base
import ./UI.bend as Product
import ./bendlib/feature-laws.bend as FeatureLaws
import ./bendlib/locality.bend as Locality
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
import ./bendlib/approval-architecture.bend as Approval
import ./bendlib/proofs/approvals.bend as ApprovalsProof
import ./bendlib/reasoning-architecture.bend as Reasoning
import ./bendlib/proofs/reasoning.bend as ReasoningProof
import ./bendlib/board-architecture.bend as Board
import ./bendlib/proofs/board.bend as BoardProof

# Assemble the conceptual program only after every local obligation is closed.

def Entry.harness():
  Entry.Harness{
    Entry.Meaning{Concepts.commands(), Concepts.interactions(), Concepts.actions(), Concepts.scheduling(), Concepts.native_interface()},
    Entry.Composition{Concepts.protocol_reachability(), Concepts.traces(), Concepts.task_machine(), Concepts.persistence(), Concepts.history(), Concepts.decisions()},
    Entry.Recovery{Concepts.context(), Concepts.interruption(), Concepts.recovery(), Concepts.recovery_batches()},
    Entry.Observation{Concepts.observations(), Concepts.task_views(), Concepts.branch_results(), Concepts.surface()},
    Entry.Concurrency{Concepts.operation_rights(), Concepts.announcement(), Concepts.notifications(), Concepts.coordination()},
    Entry.Extensibility{Concepts.plugin_boundary(), Concepts.result_boundary()}, Workspace.context_boundary(), Approval.approval_boundary(),
    Reasoning.reasoning_boundary(), FeatureLaws.features(), Locality.locality()}

# The native product bridge carries all trusted interface decisions unchanged.
def product_interface_evidence() -> Product.InterfaceRequirements:
  Product.interface_evidence()
