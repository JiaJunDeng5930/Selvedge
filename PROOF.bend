import Base
import ./harness/features/laws.bend as FeatureLaws
import ./harness/PROOF.bend as LocalityProof
import ./harness/LAWS.bend as Laws
import ./harness/CONTRACT.bend as Concepts
import ./CONCEPTS.bend as Entry
import ./bendlib/algebra-proof.bend as AlgebraProof
import ./harness/protocol/commit-proof.bend as CommitProof
import ./harness/execution/PROOF.bend as ExecutionProof
import ./harness/transport/PROOF.bend as FrontendProof
import ./harness/protocol/PROOF.bend as ProtocolProof
import ./harness/tasks/PROOF.bend as TasksProof
import ./harness/history/PROOF.bend as TracesProof
import ./interaction/presentation/PROOF.bend as CoreSurfaceProof
import ./interaction/session/PROOF.bend as CoreSessionProof
import ./interaction/conversation/PROOF.bend as CoreConversationPresentationProof
import ./interaction/services/PROOF.bend as CoreExecutionContextProof
import ./interaction/submission/PROOF.bend as CoreSubmissionFeedbackProof
import ./interaction/PROOF.bend as UIProof
import ./harness/approval/PROOF.bend as PluginsProof
import ./harness/workspace/CONTRACT.bend as Workspace
import ./harness/workspace/PROOF.bend as WorkspacesProof
import ./harness/approval/CONTRACT.bend as Approval
import ./harness/reasoning/CONTRACT.bend as Reasoning
import ./harness/reasoning/PROOF.bend as ReasoningProof
import ./features/board/CONTRACT.bend as Board
import ./features/board/PROOF.bend as BoardProof
import ./interaction/presentation/CONTRACT.bend as InterfaceProgramRules
import ./harness/transport/json-render-rules.bend as JsonRenderRules
import ./harness/transport/profile-rules.bend as ProfileRules

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
