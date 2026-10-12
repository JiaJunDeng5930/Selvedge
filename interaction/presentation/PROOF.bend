import ../experience/PROGRAM.bend as UX
import ../experience/MODEL.bend as Experience
import ../INPUT.bend as U
import Base
import ./CONTRACT.bend as Rule
import ./MODEL.bend as V
import ./SURFACE.bend as SurfaceTypes
import ./PROGRAM.bend as Model
import ../TYPES.bend as InteractionTypes
import ../submission/FIELDS.bend as Forms
import ../../harness/DOMAIN.bend as D
import ../session/MODEL.bend as E
import ../services/CONTEXT.bend as Context
import ../IDENTITY.bend as Identity
import ../STATE.bend as Core
import ./VIEW.bend as View
import ../../harness/tasks/PROGRAM.bend as T
import ../../harness/COMMANDS.bend as Commands

def Rule.composer_tree_present_agreement(identity, revision, message, phase, creation_context, execution_controls, context, assessment, submit, feedback, pending, parent, state):
  match creation_context execution_controls:
    case Nil{} Nil{}: {==}
    case Nil{} Con{first, rest}: {==}
    case Con{first, rest} Nil{}: {==}
    case Con{first, rest} Con{other, tail}: {==}

def Rule.composer_tree_agreement(view, parent, state):
  match view:
    case None{}: {==}
    case Some{V.ComposerScene{+identity, revision, message, phase, creation_context, execution_controls, context, assessment, submit, feedback, pending}}:
      Rule.composer_tree_present_agreement(identity, revision, message, phase, creation_context, execution_controls, context, assessment, submit, feedback, pending, parent, state)

def Rule.composer_enclosure_present_agreement(identity, revision, message, phase, creation_context, execution_controls, context, assessment, submit, feedback, pending, parent, state):
  match creation_context execution_controls:
    case Nil{} Nil{}: {==}
    case Nil{} Con{first, rest}: {==}
    case Con{first, rest} Nil{}: {==}
    case Con{first, rest} Con{other, tail}: {==}

def Rule.composer_enclosure_agreement(view, parent, state):
  match view:
    case None{}: {==}
    case Some{V.ComposerScene{+identity, revision, message, phase, creation_context, execution_controls, context, assessment, submit, feedback, pending}}:
      Rule.composer_enclosure_present_agreement(identity, revision, message, phase, creation_context, execution_controls, context, assessment, submit, feedback, pending, parent, state)

def Rule.relocated_valid_content(valid, node, scene, base, overlays):
  match valid:
    case False{}: {==}
    case True{}:
      SurfaceTypes.Node{key, semantic, label, role, meaning, children} = node
      {==}

def Rule.relocated_found_content(found, target, scene, base, overlays):
  match found:
    case None{}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, +meaning, children}}:
      Rule.relocated_valid_content(Model.persistent_trigger_source(meaning, target),
        SurfaceTypes.Node{key, semantic, label, role, meaning, children}, scene, base, overlays)

def Rule.relocated_key_content(found, target, scene, base, overlays):
  match found:
    case None{}: {==}
    case Some{key}: Rule.relocated_found_content(Model.find_node(base, key), target, scene, base, overlays)

def Rule.relocated_content(trigger, scene, base, overlays):
  match trigger:
    case None{}: {==}
    case Some{SurfaceTypes.PersistentTrigger{target, requested}}: Rule.relocated_key_content(Model.matching_focus(base, requested), target, scene, base, overlays)

def Rule.assembled_content(scene, state):
  InteractionTypes.Scene{V.Scene{nav, main, views, arrangement, attention}, preferences, transfers, attachment, code, folder_picker} = scene
  {==}

def Rule.placement_destination_authority(key, semantic, label, role, destinations, face, children, target, surface):
  {==}

def Rule.placement_filtered_destination_accepted(key, semantic, label, role, destinations, face, children, target, surface, input, hidden, accepted):
  accepted

def Rule.placement_rejected_destination(key, semantic, label, role, destinations, face, children, target, surface, rejected):
  rejected

def Rule.fixed_reasoning_catalogue_entry(key, provider, name, options):
  {==}

def Rule.fixed_reasoning_open_entry(key, provider, name):
  {==}

def Rule.retained_profile_effort(profile, previous, permitted):
  Equal.cong(Bool, String, accepted => Forms.selected_profile_effort(accepted, previous, profile),
    D.profile_permitted(profile, previous), True{}, permitted)

def Rule.reset_profile_effort(profile, previous, denied):
  Equal.cong(Bool, String, accepted => Forms.selected_profile_effort(accepted, previous, profile),
    D.profile_permitted(profile, previous), False{}, denied)

def Rule.rejected_reasoning_edit(profile, reasoning):
  {==}

def Rule.accepted_reasoning_edit(profile, reasoning):
  {==}

def Rule.selected_model_permission(profile, reasoning):
  {==}

def Rule.rejected_profile_choice():
  {==}

def Rule.new_task_model_permission(message, profile, reasoning, context, world):
  {==}

def Rule.agent_model_permission(agent, revision, name, profile, reasoning, instructions, context, concurrency, world):
  {==}

def Rule.modal_navigation_preserved(nav, state): {==}

def Rule.overlay_navigation_scope(key, semantic, label, meaning, children, rest): {==}

def Rule.dialog_actions_region(parent, children):
  {==}

def Rule.editor_submit_region(identity, revision, groups, structure, assessment, submit, feedback, pending, parent, state):
  {==}

def Rule.confirmation_actions_region(title, confirm, cancel, parent, state):
  {==}

def Rule.card_ordered_movement(view, parent, state):
  V.CardScene{id, value, open, actions, linked, destinations, candidates} = view
  InteractionTypes.State{E.Application{world, E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code, next_layer, model_preference, draft_model_manual}}, services} = state
  {==}

def Rule.card_surface_placement(key, semantic, label, face, children, target): {==}

def Rule.card_movement_placement(key, semantic, label, face, destinations, target): {==}

def Rule.project_fact_structure(key, label, value): {==}

def Rule.interface_input(input, state):
  {==}

def Rule.interface_evidence():
  Rule.InterfaceRequirements{Rule.interface_input}

def committed_permission_summary_agreement(+found: Maybe<&2, Context.EffectiveContext>, +parent: Identity.Key, +state: InteractionTypes.State) ->
  {Model.committed_permission_summary(found, parent, state) == Rule.expected_committed_permission_summary(found, parent, state) : +List<SurfaceTypes.Node>}:
  match found:
    case Some{context}: {==}
    case None{}: {==}

def Rule.committed_permission_summary_agreement(task, preview, parent, state):
  committed_permission_summary_agreement(View.committed_context(T.find(Commands.entries(E.program(Core.application(state))), task)), parent, state)

def Rule.task_permission_resets_absent(task, config, parent, state):
  {==}

def Rule.permission_menu_agreement(editor, group, parent, state):
  match group:
    case V.ExecutionInput{config, Context.ContextUnavailable{reason}, controls, projects, reviewers}: {==}
    case V.ExecutionInput{config, Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}, controls, projects, reviewers}: {==}
    case V.MessageInput{value}: {==}
    case V.ModelInput{profile, reasoning, choices}: {==}
    case V.DeliveryInput{selected, send, steer}: {==}
    case V.ProjectNameInput{name}: {==}
    case V.ProjectWorkspaceInput{workspace, controls}: {==}
    case V.CardContentInput{value, projects, stages, priorities, owners}: {==}
    case V.CardAssistanceInput{enabled, profile, choices}: {==}
    case V.AgentIdentityInput{name, instructions, concurrency}: {==}
    case V.ForkInput{count, messages}: {==}
    case V.SummaryInput{summary}: {==}

def supporting_binding_agreement(+support: Experience.Support, +property: Experience.Property, +input: InteractionTypes.Input, +availability: V.Availability, +gesture: SurfaceTypes.Gesture) ->
  {Model.bind(SurfaceTypes.SupportingControl{support, property, input, availability}, gesture) == Rule.expected_supporting_binding(support, input, availability, gesture) : Maybe<&2, InteractionTypes.Input>}:
  match gesture:
    case SurfaceTypes.Place{target}: {==}
    case SurfaceTypes.Press{}: {==}
    case SurfaceTypes.Change{value}: {==}
    case SurfaceTypes.Search{query}: {==}
    case SurfaceTypes.Filter{value}: {==}
    case SurfaceTypes.Attach{file}: {==}
    case SurfaceTypes.Directory{path}: {==}
    case SurfaceTypes.ConfirmDirectory{}: {==}
    case SurfaceTypes.SelectBoardProfile{profile}: {==}

def supporting_submission_agreement(+support: Experience.Support, +property: Experience.Property, +input: InteractionTypes.Input, +availability: V.Availability, +editor: U.Editor) ->
  {Model.submits(SurfaceTypes.SupportingControl{support, property, input, availability}, editor) == Rule.expected_supporting_submission(support, input, availability, editor) : Bool}:
  match input:
    case InteractionTypes.ApplicationInput{E.ContentInput{p0, p1}}: {==}
    case InteractionTypes.ApplicationInput{E.PreviewObserved{p0}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.Navigate{p0}}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.SelectProject{p0}}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.ToggleProjectGroup{p0}}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.BeginTask{p0}}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.EditProject{p0}}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.NewCard{p0}}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.EditCard{p0}}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.EditAgent{p0}}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.ForkTask{p0}}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.CompactTask{p0}}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.Submit{p0}}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.ControlTask{p0, p1}}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.CancelOperation{p0, p1}}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.ReviewApproval{p0, p1, p2, p3}}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.DeleteProject{p0}}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.BoardCommand{p0}}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.OpenPanel{p0, p1}}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.TogglePanel{p0, p1}}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.ClosePanel{}}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.ConfirmAction{}}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.EditDraft{p0, p1}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.ReadTimeline{p0, p1, p2}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.SetDisclosure{p0, p1, p2, p3}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.SetNavigation{p0}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.SearchChoices{p0}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.FilterBoard{p0}}}: {==}
    case InteractionTypes.ApplicationInput{E.RuntimeInput{p0}}: {==}
    case InteractionTypes.ApplicationInput{E.ProgramObserved{p0}}: {==}
    case InteractionTypes.ApplicationInput{E.CommandCompleted{p0, p1, p2}}: {==}
    case InteractionTypes.ApplicationInput{E.DirectoriesObserved{p0, p1}}: {==}
    case InteractionTypes.ApplicationInput{E.ClockObserved{p0}}: {==}
    case InteractionTypes.ApplicationInput{E.ModelPreferenceRestored{p0, p1}}: {==}
    case InteractionTypes.ServiceInput{p0}: {==}
    case InteractionTypes.EditField{p0, p1, p2}: {==}
    case InteractionTypes.RemoveAttachment{p0, p1}: {==}

def effort_entry_surface_agreement(+entry: Forms.Entry, +observation: Forms.Observed, +editor: U.Editor, +parent: Identity.Key, +state: InteractionTypes.State, +groups: +List<V.InputGroup>) ->
  {Model.model_effort_surface(entry, observation, editor, parent, state, groups) == Rule.expected_model_effort_surface(entry, observation, editor, parent, state, groups) : SurfaceTypes.Node}:
  match entry:
    case Forms.Choice{}: {==}
    case Forms.SingleLine{}: {==}
    case Forms.DisplayOnly{}: {==}
    case Forms.Multiline{}: {==}
    case Forms.MultipleChoices{}: {==}
    case Forms.PositiveInteger{}: {==}
    case Forms.DirectoryCollection{}: {==}
    case Forms.FileCollection{}: {==}

def canonical_commit_agreement(+action: Experience.ActionUnit, +assessment: Experience.Assessment, +identity: String, +label: String, +prominence: V.Prominence, input: U.Input, +availability: V.Availability, +parent: Identity.Key, +state: InteractionTypes.State) ->
  {Model.canonical_commit(action, assessment, V.ControlDeclaration{identity, label, prominence, input, availability}, parent, state) == Rule.expected_action_commit(assessment, parent, Core.control(state, V.ControlDeclaration{identity, label, prominence, UX.commit(action), availability})) : SurfaceTypes.Node}:
  InteractionTypes.State{application, services} = state
  {==}

def Rule.experience_evidence():
  Rule.ExperienceRequirements{
    entry => observation => editor => parent => state => groups => effort_entry_surface_agreement(entry, observation, editor, parent, state, groups),
    profile => reasoning => choices => editor => parent => state => groups => {==},
    controls => action => assessment => submit => parent => state => {==},
    support => property => input => availability => gesture => supporting_binding_agreement(support, property, input, availability, gesture),
    support => property => input => availability => {==},
    support => property => input => availability => editor => supporting_submission_agreement(support, property, input, availability, editor),
    subject => observed => {==},
    profile => reasoning => choices => rest => editor => parent => state => {==},
    title => entries => rest => editor => parent => ordinal => state => groups => {==},
    property => declaration => rest => action => parent => state => {==},
    subject => observed => profile => rest => {==},
    decision => parent => state => {==},
    decision => label => explanation => value => input => parent => state => {==},
    collection => path => parent => state => {==},
    action => assessment => identity => label => prominence => input => availability => parent => state => canonical_commit_agreement(action, assessment, identity, label, prominence, input, availability, parent, state),
    editor => revision => reason => parent => {==},
    support => property => parent => identity => label => prominence => input => availability => {==}}

def Rule.assessed_editor_scene(revision, body, feedback, entry, pending, now, world): {==}

def Rule.available_assessment_preserved(assessment): {==}
def Rule.directory_assessment_preserved(assessment): {==}
def Rule.unavailable_assessment_uses_actual_reason(assessment, reason): {==}
def Rule.duplicate_assessment_reason_preserved(assessment, reason): {==}
def Rule.distinct_assessment_reason_retained(assessment, reason): {==}
def Rule.commit_explanation_observes_same_assessment(assessment, parent, identity, label, prominence, input, availability): {==}


def Rule.context_permission_facts(observation): {==}
def Rule.context_summary_labels(observation, parent, state): {==}
