import Base
import ../architecture.bend as Architecture
import ../../core/contract.bend as Contract
import ../../core/SYSTEM.bend as Core
import ./conversation.bend as Conversation
import ../../core/surface-laws.bend as SurfaceLaws
import ../../core/session-laws.bend as SessionLaws
import ../../core/submission-laws.bend as SubmissionLaws
import ../../core/boundary-laws.bend as BoundaryLaws
import ../../core/composition-laws.bend as CompositionLaws
import ../../core/conversation-presentation-laws.bend as ConversationPresentationLaws
import ../../core/board-presentation-laws.bend as BoardPresentationLaws
import ../../core/board-capability-laws.bend as BoardCapabilityLaws
import ../../core/execution-context-laws.bend as ExecutionContextLaws
import ../../core/project-interaction-laws.bend as ProjectInteractionLaws
import ../../core/directory-entry-laws.bend as DirectoryEntryLaws
import ../../core/submission-feedback-laws.bend as SubmissionFeedbackLaws
import ../../core/proofs/laws.bend as CoreLawsProof
import ../../core/proofs/submission.bend as CoreSubmissionProof
import ../../core/interface-rules.bend as InterfaceRules

def Architecture.surface():
  Contract.Requirements{
    SurfaceLaws.evidence(), SessionLaws.evidence(), SubmissionLaws.evidence(), BoundaryLaws.evidence(), CompositionLaws.evidence(),
    ConversationPresentationLaws.evidence(), BoardPresentationLaws.evidence(), BoardCapabilityLaws.evidence(), ExecutionContextLaws.evidence(), ProjectInteractionLaws.evidence(), DirectoryEntryLaws.evidence(), SubmissionFeedbackLaws.evidence(), CoreSubmissionProof.reopen_evidence(),
    input => program => session => services => CoreLawsProof.runtime_input(input, program, session, services),
    capacity => +state => InterfaceRules.assembled_content(Core.observe(capacity, state), state),
    reader => task => world => Conversation.timeline_history(reader, task, world),
    messages => offset => task => disclosures => Conversation.observed_text(messages, offset, task, disclosures),
    task => text => previous => selected => world => {==},
    directory_entry => revision => body => feedback => submitted => reply => {==},
    revision => title => description => stage => priority => owner => project => labels => attachments => assist => profile => {==}}
