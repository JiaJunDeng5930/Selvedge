import Base
import ../harness/CONTRACT.bend as Architecture
import ./CONTRACT.bend as Contract
import ./STATE.bend as Core
import ../harness/conversation/PROOF.bend as Conversation
import ./presentation/surface-laws.bend as SurfaceLaws
import ./session/session-laws.bend as SessionLaws
import ./submission/submission-laws.bend as SubmissionLaws
import ./presentation/boundary-laws.bend as BoundaryLaws
import ./presentation/composition-laws.bend as CompositionLaws
import ./conversation/CONTRACT.bend as ConversationPresentationLaws
import ./presentation/board-presentation-laws.bend as BoardPresentationLaws
import ./presentation/board-capability-laws.bend as BoardCapabilityLaws
import ./services/context-laws.bend as ExecutionContextLaws
import ./presentation/project-interaction-laws.bend as ProjectInteractionLaws
import ./presentation/directory-entry-laws.bend as DirectoryEntryLaws
import ./submission/feedback-laws.bend as SubmissionFeedbackLaws
import ./runtime-proof.bend as CoreLawsProof
import ./submission/submission-proof.bend as CoreSubmissionProof
import ./presentation/CONTRACT.bend as InterfaceRules

def Architecture.surface():
  Contract.Requirements{
    Contract.Interaction{
      SurfaceLaws.evidence(),
      SessionLaws.evidence(),
      BoundaryLaws.evidence(),
      CompositionLaws.evidence()},
    Contract.Drafts{
      SubmissionLaws.evidence(),
      SubmissionFeedbackLaws.evidence(),
      CoreSubmissionProof.reopen_evidence(),
      task => text => previous => selected => world => {==},
      directory_entry => revision => body => feedback => submitted => reply => {==},
      revision => title => description => stage => priority => owner => project => labels => attachments => assist => profile => {==}},
    Contract.Presentation{
      ConversationPresentationLaws.evidence(),
      BoardPresentationLaws.evidence(),
      reader => task => world => Conversation.timeline_history(reader, task, world),
      messages => offset => task => disclosures => Conversation.observed_text(messages, offset, task, disclosures)},
    Contract.Capabilities{
      BoardCapabilityLaws.evidence(),
      ExecutionContextLaws.evidence(),
      ProjectInteractionLaws.evidence(),
      DirectoryEntryLaws.evidence()},
    input => program => session => services => CoreLawsProof.runtime_input(input, program, session, services),
    capacity => +state => InterfaceRules.assembled_content(Core.observe(capacity, state), state)}
