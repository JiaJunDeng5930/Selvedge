import Base
import ../bendlib/json.bend as J
import ./IDENTITY.bend as Identity
import ./identity-laws.bend as Rule
import ../harness/MODEL.bend as M
import ../harness/PROGRAM.bend as Program
import ./STATE.bend as Core
import ./session/MODEL.bend as E
import ./session/PROGRAM.bend as ExperienceProgram
import ./session/CONTRACT.bend as Existing
import ./services/MODEL.bend as Services
import ./session/PROOF.bend as ExistingProof
import ../harness/CONTRACT.bend as Architecture
import ./CONTRACT.bend as Contract
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
import ./submission/PROOF.bend as CoreSubmissionProof
import ./presentation/CONTRACT.bend as InterfaceRules

def place_payload(path: String) ->
  {Identity.place(path) == Identity.Place{path} : Identity.Key}:
  {==}

def entity_payload(owner: Identity.Key, kind: String, identity: String) ->
  {Identity.entity(owner, kind, identity) == Identity.Entity{owner, kind, identity} : Identity.Key}:
  {==}

def part_payload(owner: Identity.Key, name: String) ->
  {Identity.part(owner, name) == Identity.Part{owner, name} : Identity.Key}:
  {==}

def place_comparison(path: String, other_path: String) ->
  {Identity.same(Identity.Place{path}, Identity.Place{other_path}) == String.eq(path, other_path) : Bool}:
  {==}

def entity_comparison(owner: Identity.Key, kind: String, identity: String, other_owner: Identity.Key, other_kind: String, other_identity: String) ->
  {Identity.same(Identity.Entity{owner, kind, identity}, Identity.Entity{other_owner, other_kind, other_identity}) == (Identity.same(owner, other_owner) && (String.eq(kind, other_kind) && String.eq(identity, other_identity))) : Bool}:
  {==}

def part_comparison(owner: Identity.Key, name: String, other_owner: Identity.Key, other_name: String) ->
  {Identity.same(Identity.Part{owner, name}, Identity.Part{other_owner, other_name}) == (Identity.same(owner, other_owner) && String.eq(name, other_name)) : Bool}:
  {==}

def place_entity_distinct(path: String, owner: Identity.Key, kind: String, identity: String) ->
  {Identity.same(Identity.Place{path}, Identity.Entity{owner, kind, identity}) == False{} : Bool}:
  {==}

def place_entity_reverse_distinct(path: String, owner: Identity.Key, kind: String, identity: String) ->
  {Identity.same(Identity.Entity{owner, kind, identity}, Identity.Place{path}) == False{} : Bool}:
  {==}

def place_part_distinct(path: String, owner: Identity.Key, name: String) ->
  {Identity.same(Identity.Place{path}, Identity.Part{owner, name}) == False{} : Bool}:
  {==}

def place_part_reverse_distinct(path: String, owner: Identity.Key, name: String) ->
  {Identity.same(Identity.Part{owner, name}, Identity.Place{path}) == False{} : Bool}:
  {==}

def entity_part_distinct(owner: Identity.Key, kind: String, identity: String, part_owner: Identity.Key, name: String) ->
  {Identity.same(Identity.Entity{owner, kind, identity}, Identity.Part{part_owner, name}) == False{} : Bool}:
  {==}

def entity_part_reverse_distinct(owner: Identity.Key, kind: String, identity: String, part_owner: Identity.Key, name: String) ->
  {Identity.same(Identity.Part{part_owner, name}, Identity.Entity{owner, kind, identity}) == False{} : Bool}:
  {==}

def place_encoding(path: String) ->
  {Identity.encode(Identity.Place{path}) == ("[\"place\",\"" ++ J.escape(path) ++ "\"]") : String}:
  {==}

def entity_encoding(owner: Identity.Key, kind: String, identity: String) ->
  {Identity.encode(Identity.Entity{owner, kind, identity}) == ("[\"entity\"," ++ Identity.encode(owner) ++ ",\"" ++ J.escape(kind) ++ "\",\"" ++ J.escape(identity) ++ "\"]") : String}:
  {==}

def part_encoding(owner: Identity.Key, name: String) ->
  {Identity.encode(Identity.Part{owner, name}) == ("[\"part\"," ++ Identity.encode(owner) ++ ",\"" ++ J.escape(name) ++ "\"]") : String}:
  {==}

def Rule.evidence():
  Rule.Requirements{place_payload, entity_payload, part_payload, place_comparison, entity_comparison, part_comparison, place_entity_distinct, place_entity_reverse_distinct, place_part_distinct, place_part_reverse_distinct, entity_part_distinct, entity_part_reverse_distinct, place_encoding, entity_encoding, part_encoding}

def lifted(decision: E.Decision, services: Services.State) ->
  {Core.runtime(Core.application_result(decision, services)) == Existing.runtime_observation(decision) : M.Decision()}:
  E.Decision{E.Application{program, session}, reply, effects, interaction, durable} = decision
  {==}

def runtime_input(+input: M.Input, +program: M.World(), +session: E.Session, services: Services.State) ->
  {Core.runtime(Core.step(Core.ApplicationInput{E.RuntimeInput{input}}, Core.State{E.Application{program, session}, services})) ==
    Program.transition(input, program) : M.Decision()}:
  Services.State{access, credential, settings, appearance, next, transfers, preview, directory_picker} = services
  Equal.trans(M.Decision(),
    Core.runtime(Core.application_result(ExperienceProgram.step(E.RuntimeInput{input}, E.Application{program, session}), Services.State{access, credential, settings, appearance, next, transfers, preview, directory_picker})),
    Existing.runtime_observation(ExperienceProgram.step(E.RuntimeInput{input}, E.Application{program, session})), Program.transition(input, program),
    lifted(ExperienceProgram.step(E.RuntimeInput{input}, E.Application{program, session}), Services.State{access, credential, settings, appearance, next, transfers, preview, directory_picker}),
    ExistingProof.runtime_input(input, program, session))

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
    input => program => session => services => runtime_input(input, program, session, services),
    capacity => +state => InterfaceRules.assembled_content(Core.observe(capacity, state), state)}
