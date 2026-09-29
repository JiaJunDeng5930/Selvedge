import Base
import ../architecture.bend as Architecture
import ../../core/contract.bend as Contract
import ../../core/SYSTEM.bend as Core
import ../../core/laws.bend as CoreLaws
import ../../core/interface.bend as Interface
import ./conversation.bend as Conversation
import ../../core/surface-laws.bend as SurfaceLaws
import ../../core/session-laws.bend as SessionLaws
import ../../core/submission-laws.bend as SubmissionLaws
import ../../core/boundary-laws.bend as BoundaryLaws

def Architecture.surface():
  Contract.Requirements{
    SurfaceLaws.evidence(), SessionLaws.evidence(), SubmissionLaws.evidence(), BoundaryLaws.evidence(),
    input => program => session => services => CoreLaws.runtime_input(input, program, session, services),
    capacity => +state => Interface.assembled_content(Core.observe(capacity, state), state),
    reader => task => world => Conversation.timeline_history(reader, task, world),
    messages => offset => Conversation.grouped_history(messages, offset),
    groups => task => disclosures => Conversation.visible_history(groups, task, disclosures),
    messages => offset => task => disclosures => Conversation.observed_text(messages, offset, task, disclosures),
    task => text => previous => selected => world => {==},
    revision => body => feedback => submitted => reply => {==},
    revision => title => description => stage => priority => owner => project => labels => attachments => assist => profile => {==}}
