import Base
import ./harness/LAWS.bend as Laws
import ./interaction/presentation/CONTRACT.bend as InterfaceProgramRules
import ./harness/CONTRACT.bend as Concepts
import ./harness/approval/CONTRACT.bend as Approval
import ./features/board/CONTRACT.bend as Board
import ./harness/reasoning/CONTRACT.bend as Reasoning
import ./harness/workspace/CONTRACT.bend as Workspace
import ./CONCEPTS.bend as Entry
import ./harness/reasoning/PROOF.bend as ReasoningProof
import ./harness/tasks/PROOF.bend as TasksProof
import ./harness/PROOF.bend as LocalityProof
import ./features/board/PROOF.bend as BoardProof
import ./harness/features/laws.bend as FeatureLaws
import ./harness/protocol/PROOF.bend as ProtocolProof
import ./harness/execution/PROOF.bend as ExecutionProof
import ./harness/protocol/commit-proof.bend as CommitProof
import ./harness/history/PROOF.bend as TracesProof
import ./harness/transport/CONTRACT.bend as JsonRenderRules
import ./harness/transport/PROOF.bend as FrontendProof
import ./bendlib/algebra-proof.bend as AlgebraProof
import ./browser/layout/geometry-proof.bend as SplitBrowserLayoutGeometryProof
import ./browser/appearance/PROOF.bend as RegisteredBrowserAppearanceProof
import ./browser/document/PROOF.bend as SplitBrowserDocumentProof
import ./browser/document/content-proof.bend as SplitBrowserDocumentContentProof
import ./browser/model-proof.bend as RegisteredBrowserModelProof
import ./browser/document/presentation-proof.bend as RegisteredBrowserDocumentPresentationProof
import ./browser/document/render-proof.bend as SplitBrowserDocumentRenderProof
import ./browser/document/source-proof.bend as SplitBrowserDocumentSourceProof
import ./browser/layout/allocation-proof.bend as SplitBrowserLayoutAllocationProof
import ./browser/layout/sizing-proof.bend as SplitBrowserLayoutSizingProof
import ./browser/layout/PROOF.bend as SplitBrowserLayoutProof
import ./browser/layout/render-proof.bend as SplitBrowserLayoutRenderProof
import ./harness/approval/PROOF.bend as PluginsProof
import ./harness/workspace/PROOF.bend as WorkspacesProof
import ./interaction/conversation/PROOF.bend as CoreConversationPresentationProof
import ./interaction/presentation/PROOF.bend as CoreSurfaceProof
import ./interaction/presentation/interaction-proof.bend as SplitInteractionPresentationInteractionProof
import ./interaction/submission/PROOF.bend as CoreSubmissionFeedbackProof
import ./interaction/presentation/scene-proof.bend as SplitInteractionPresentationSceneProof
import ./interaction/services/PROOF.bend as CoreExecutionContextProof
import ./interaction/session/PROOF.bend as CoreSessionProof
import ./interaction/PROOF.bend as UIProof

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

def json_render_evidence() -> JsonRenderRules.JsonRenderRequirements:
  JsonRenderRules.json_render_evidence()

# Profile catalogue selections carry the production policy evidence.

def profile_evidence() -> JsonRenderRules.ProfileRequirements:
  JsonRenderRules.profile_evidence()
