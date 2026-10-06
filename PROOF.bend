import Base
import ./bendlib/feature-laws.bend as FeatureLaws
import ./bendlib/proofs/locality.bend as LocalityProof
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
import ./core/proofs/surface.bend as CoreSurfaceProof
import ./core/proofs/session.bend as CoreSessionProof
import ./core/proofs/boundary.bend as CoreBoundaryProof
import ./core/proofs/page-region.bend as CorePageRegionProof
import ./core/proofs/interface.bend as CoreInterfaceProof
import ./core/proofs/composition.bend as CoreCompositionProof
import ./core/proofs/conversation-presentation.bend as CoreConversationPresentationProof
import ./core/proofs/board-presentation.bend as CoreBoardPresentationProof
import ./core/proofs/board-capability.bend as CoreBoardCapabilityProof
import ./core/proofs/execution-context.bend as CoreExecutionContextProof
import ./core/proofs/project-interaction.bend as CoreProjectInteractionProof
import ./core/proofs/directory-entry.bend as CoreDirectoryEntryProof
import ./core/proofs/submission-feedback.bend as CoreSubmissionFeedbackProof
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
import ./core/interface-program-rules.bend as InterfaceProgramRules
import ./core/proofs/interface-program.bend as CoreInterfaceProgramProof
import ./bendlib/json-render-rules.bend as JsonRenderRules
import ./bendlib/proofs/json-render.bend as JsonRenderProof
import ./bendlib/profile-rules.bend as ProfileRules
import ./bendlib/proofs/profiles.bend as ProfilesProof

# Assemble the conceptual program only after every local obligation is closed.

def Entry.harness():
  Entry.Harness{
    Entry.Meaning{Concepts.commands(), Concepts.interactions(), Concepts.actions(), Concepts.scheduling(), Concepts.native_interface()},
    Entry.Composition{Concepts.protocol_reachability(), Concepts.traces(), Concepts.task_machine(), Concepts.persistence(), Concepts.history(), Concepts.decisions()},
    Entry.Recovery{Concepts.context(), Concepts.interruption(), Concepts.recovery(), Concepts.recovery_batches()},
    Entry.Observation{Concepts.observations(), Concepts.task_views(), Concepts.branch_results(), Concepts.surface()},
    Entry.Concurrency{Concepts.operation_rights(), Concepts.announcement(), Concepts.notifications(), Concepts.coordination()},
    Entry.Extensibility{Concepts.plugin_boundary(), Concepts.result_boundary()}, Workspace.context_boundary(), Approval.approval_boundary(),
    Reasoning.reasoning_boundary(), FeatureLaws.features(), LocalityProof.locality()}

# The native product bridge carries all trusted interface decisions unchanged.
def product_interface_evidence() -> InterfaceProgramRules.InterfaceRequirements:
  InterfaceProgramRules.interface_evidence()

# The shared JSON renderer carries its production completeness evidence.
def json_render_evidence() -> JsonRenderRules.Requirements:
  JsonRenderRules.evidence()

# Profile catalogue selections carry the production policy evidence.
def profile_evidence() -> ProfileRules.Requirements:
  ProfileRules.evidence()
