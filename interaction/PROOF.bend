import ./search/PROOF.bend as HistorySearchProof
import ./speech/PROOF.bend as SpeechProof
import ./speech/MODEL.bend as Speech
import ./INPUT.bend as U
import Base
import ../bendlib/categories.bend as Categories
import ../bendlib/string-equality.bend as SafeText
import ../bendlib/equality-proof.bend as TextProof
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
import ./presentation/CONTRACT.bend as SurfaceLaws
import ./submission/CONTRACT.bend as SubmissionLaws
import ./conversation/CONTRACT.bend as ConversationPresentationLaws
import ./services/CONTRACT.bend as ExecutionContextLaws
import ./submission/PROOF.bend as CoreSubmissionProof
import ./TYPES.bend as InteractionTypes

def ExecutionContextLaws.settings_open_changes_only_its_open_flag(state):
  Services.State{access, settings, appearance, next, transfers, preview, directory_picker, +speech} = state
  {==}

def ExecutionContextLaws.settings_close_changes_only_its_open_flag(state):
  Services.State{access, settings, appearance, next, transfers, preview, directory_picker, +speech} = state
  {==}

def Contract.settings_open_consumes_global_navigation_and_preserves_service_fields(application, services):
  Equal.cong(Services.Decision, InteractionTypes.Decision,
    (decision => Core.service_result(decision, E.advance_selection(E.consume_global_navigation(application)))),
    Services.step(Services.OpenSettings{}, services), Services.Decision{Services.with_settings_open(True{}, services), Nil{}},
    ExecutionContextLaws.settings_open_changes_only_its_open_flag(services))

def Contract.settings_close_preserves_service_fields_and_advances_selection(application, services):
  Equal.cong(Services.Decision, InteractionTypes.Decision,
    (decision => Core.service_result(decision, E.advance_selection(application))),
    Services.step(Services.CloseSettings{}, services), Services.Decision{Services.with_settings_open(False{}, services), Nil{}},
    ExecutionContextLaws.settings_close_changes_only_its_open_flag(services))

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
  TextProof.public_refines(path, other_path)

def entity_comparison(owner: Identity.Key, kind: String, identity: String, other_owner: Identity.Key, other_kind: String, other_identity: String) ->
  {Identity.same(Identity.Entity{owner, kind, identity}, Identity.Entity{other_owner, other_kind, other_identity}) == (Identity.same(owner, other_owner) && (String.eq(kind, other_kind) && String.eq(identity, other_identity))) : Bool}:
  Equal.trans(Bool,
    Identity.same(Identity.Entity{owner, kind, identity}, Identity.Entity{other_owner, other_kind, other_identity}),
    (Identity.same(owner, other_owner) && (String.eq(kind, other_kind) && SafeText.string_equal(identity, other_identity))),
    (Identity.same(owner, other_owner) && (String.eq(kind, other_kind) && String.eq(identity, other_identity))),
    Equal.cong(Bool, Bool, (same => Identity.same(owner, other_owner) && (same && SafeText.string_equal(identity, other_identity))),
      SafeText.string_equal(kind, other_kind), String.eq(kind, other_kind), TextProof.public_refines(kind, other_kind)),
    Equal.cong(Bool, Bool, (same => Identity.same(owner, other_owner) && (String.eq(kind, other_kind) && same)),
      SafeText.string_equal(identity, other_identity), String.eq(identity, other_identity), TextProof.public_refines(identity, other_identity)))

def part_comparison(owner: Identity.Key, name: String, other_owner: Identity.Key, other_name: String) ->
  {Identity.same(Identity.Part{owner, name}, Identity.Part{other_owner, other_name}) == (Identity.same(owner, other_owner) && String.eq(name, other_name)) : Bool}:
  Equal.cong(Bool, Bool, (same => Identity.same(owner, other_owner) && same),
    SafeText.string_equal(name, other_name), String.eq(name, other_name), TextProof.public_refines(name, other_name))

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
  {Core.runtime(Core.step(InteractionTypes.ApplicationInput{E.RuntimeInput{input}}, InteractionTypes.State{E.Application{program, session}, services})) ==
    Program.transition(input, program) : M.Decision()}:
  Services.State{access, settings, appearance, next, transfers, preview, directory_picker, +speech} = services
  Equal.trans(M.Decision(),
    Core.runtime(Core.application_result(ExperienceProgram.step(E.RuntimeInput{input}, E.Application{program, session}), Services.State{access, settings, appearance, next, transfers, preview, directory_picker, speech})),
    Existing.runtime_observation(ExperienceProgram.step(E.RuntimeInput{input}, E.Application{program, session})), Program.transition(input, program),
    lifted(ExperienceProgram.step(E.RuntimeInput{input}, E.Application{program, session}), Services.State{access, settings, appearance, next, transfers, preview, directory_picker, speech}),
    ExistingProof.runtime_input(input, program, session))

def Architecture.surface():
  Contract.Requirements{
    Contract.Interaction{
      SurfaceLaws.surface_evidence(),
      Existing.evidence(),
      SurfaceLaws.boundary_evidence(),
      SurfaceLaws.composition_evidence()},
    Contract.Drafts{
      SubmissionLaws.submission_evidence(),
      SubmissionLaws.feedback_evidence(),
      CoreSubmissionProof.reopen_evidence(),
      task => text => previous => selected => world => {==},
      graph => source => previous_source => previous => world => {==},
      graph => source => {==},
      directory_entry => revision => body => feedback => submitted => reply => {==},
      revision => title => description => stage => priority => owner => project => labels => attachments => assist => profile => {==}},
    Contract.Presentation{
      ConversationPresentationLaws.evidence(),
      SurfaceLaws.board_presentation_evidence(),
      reader => task => world => Conversation.timeline_history(reader, task, world),
      messages => offset => task => disclosures => Conversation.observed_text(messages, offset, task, disclosures)},
    Contract.Capabilities{
      SpeechProof.production(),
      SurfaceLaws.board_capability_evidence(),
      ExecutionContextLaws.context_evidence(),
      SurfaceLaws.project_interaction_evidence(),
      SurfaceLaws.directory_entry_evidence()},
    input => program => session => services => runtime_input(input, program, session, services),
    SurfaceLaws.observed_content}

def Contract.actual_control_observation(state, identity, label, prominence, input, availability):
  InteractionTypes.State{application, services} = state
  {==}

def Contract.service_submit_obstruction(connected, blocked):
  match connected blocked:
    case False{} False{}: {==}
    case False{} True{}: {==}
    case True{} False{}: {==}
    case True{} True{}: {==}

def Contract.service_action_obstruction(blocked):
  match blocked:
    case False{}: {==}
    case True{}: {==}

def Contract.submission_service_requirements(access, transfers, editor):
  Contract.service_submit_obstruction(Services.connected(access), Services.blocks(editor, transfers))

def Contract.workspace_retry_service_requirements(access, transfers, editor):
  Contract.service_submit_obstruction(Services.connected(access), Services.blocks(editor, transfers))

def Contract.confirmation_service_requirement(access, transfers):
  Contract.service_action_obstruction(Bool.not(Services.connected(access)))

def Contract.command_service_requirement(access, command): {==}

def Contract.local_action_requires_no_connection(access): {==}

def application_admission_checked(+input: E.Input, +application: E.Application, +services: Services.State,
  available: Bool, observed: {Core.application_available(Core.ApplicationRequest{input, application, services}) == available : Bool}) ->
  {Core.application_admitted(Categories.admit_checked(Core.ApplicationRequest, Core.application_available,
      Core.ApplicationRequest{input, application, services}, available, observed), application, services) ==
    Contract.application_admission_result(available, input, application, services) : InteractionTypes.Decision}:
  match available:
    case True{}: {==}
    case False{}: {==}

def Contract.actual_application_admission(input, application, services):
  application_admission_checked(input, application, services,
    Core.application_available(Core.ApplicationRequest{input, application, services}), {==})
