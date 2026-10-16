import Base
import ../../bendlib/stdlib.bend as Std
import ../../harness/features/MODEL.bend as F
import ../../harness/tasks/PROGRAM.bend as Tasks
import ../../harness/MODEL.bend as World
import ../../harness/COMMANDS.bend as Commands
import ../../harness/workspace/PROJECTS.bend as Projects
import ../../features/board/MODEL.bend as Board
import ../../bendlib/json.bend as J
import ./CONTRACT.bend as Rule
import ./MODEL.bend as M
import ./PROGRAM.bend as P
import ./ACTIVITY.bend as Activity
import ../INPUT.bend as U
import ../submission/FIELDS.bend as Forms
import ../services/CONTEXT.bend as Context
import ../../harness/DOMAIN.bend as D
import ../../harness/reasoning/MODEL.bend as Reasoning
import ../../bendlib/equality-proof.bend as Same
import ../../harness/transport/schema.bend as Schema

def duplicate_rejection(compatible: Bool, rest: Bool) ->
  {P.admitted_candidate(compatible, True{}, rest) == False{} : Bool}:
  match compatible:
    case True{}: {==}
    case False{}: {==}

def selected_equation(+decision: M.Decision, +candidate: M.Value) ->
  {P.selected(decision, candidate) == P.observed_selection(Rule.subject_field(P.decision_subject(decision)), P.decision_observation(decision), candidate) : Bool}:
  match decision:
    case M.Decision{M.Subject{editor, field}, observation, question, alternatives, availability}: {==}

def choose_equation(+decision: M.Decision, +candidate: M.Value) ->
  {P.choose(decision, candidate) == P.choose_admitted(P.admitted_value(P.decision_alternatives(decision), candidate), P.decision_subject(decision), P.decision_observation(decision)) : Maybe<&2, U.Input>}:
  match decision:
    case M.Decision{subject, observation, question, alternatives, availability}: {==}

def model_selection(+profile: D.Profile, +effort: String) ->
  {P.model_intent(profile, effort) == P.permitted_model(D.profile_permitted(profile, P.model_effort(D.profile_permitted(profile, effort), effort, profile)), Rule.profile_key(profile), P.model_effort(D.profile_permitted(profile, effort), effort, profile)) : Maybe<&2, U.Edit>}:
  match profile:
    case D.Profile{key, provider, name, policy, options}: {==}

def supporting_subjects(+support: M.Support) ->
  {P.support_subjects(support) == P.subjects(P.support_fields(support), Rule.identity_editor(P.support_identity(support))) : +List<M.Subject>}:
  match support:
    case M.Support{M.ActionIdentity{editor, revision}, fields}: {==}

def head_contains(+key: String, +seen: +List<String>) -> {Schema.contains(key <> seen, key) == True{} : Bool}:
  Equal.cong(Bool, Bool, (same => same || Schema.contains(seen, key)), String.eq(key, key), True{}, Same.same_string(key))

def duplicate_input(label: String, explanation: String, +value: M.Value, +rest: +List<M.Alternative>, +subject: M.Subject, +observation: Forms.Observed, +seen: +List<String>) ->
  {P.admissible(M.Alternative{label, explanation, value} <> rest, subject, observation, P.value_key(value) <> seen) == False{} : Bool}:
  +compatible: Bool = P.has_intent(P.canonical(subject, observation, value))
  +remaining: Bool = P.admissible(rest, subject, observation, P.value_key(value) <> P.value_key(value) <> seen)
  Equal.trans(Bool,
    P.admitted_candidate(compatible, Schema.contains(P.value_key(value) <> seen, P.value_key(value)), remaining),
    P.admitted_candidate(compatible, True{}, remaining), False{},
    Equal.cong(Bool, Bool, (duplicate => P.admitted_candidate(compatible, duplicate, remaining)), Schema.contains(P.value_key(value) <> seen, P.value_key(value)), True{}, head_contains(P.value_key(value), seen)),
    duplicate_rejection(compatible, remaining))
def property_editor_equation(+property: M.Property) ->
  {P.property_editor(property) == Rule.property_editor_meaning(property) : U.Editor}:
  match property:
    case M.ProjectObservation{editor, selected, found}: {==}
    case M.WorkspaceObservation{editor, observation, source}: {==}
    case M.PermissionsObservation{editor, observation}: {==}
    case M.ModelObservation{editor, profile, effort, found}: {==}
    case M.DeliveryObservation{editor, delivery}: {==}

def property_kind_equation(+property: M.Property) ->
  {P.property_kind(property) == Rule.property_kind_meaning(property) : M.PropertyKind}:
  match property:
    case M.ProjectObservation{editor, selected, found}: {==}
    case M.WorkspaceObservation{editor, observation, source}: {==}
    case M.PermissionsObservation{editor, observation}: {==}
    case M.ModelObservation{editor, profile, effort, found}: {==}
    case M.DeliveryObservation{editor, delivery}: {==}

def property_state_equation(+property: M.Property) ->
  {P.property_state(property) == Rule.property_state_meaning(property) : M.PropertyState}:
  match property:
    case M.ProjectObservation{editor, selected, found}: {==}
    case M.WorkspaceObservation{editor, observation, source}: {==}
    case M.PermissionsObservation{editor, observation}: {==}
    case M.ModelObservation{editor, profile, effort, found}: {==}
    case M.DeliveryObservation{editor, delivery}: {==}

def property_value_equation(+property: M.Property) ->
  {P.property_value(property) == Rule.property_value_meaning(property) : String}:
  match property:
    case M.ProjectObservation{editor, selected, found}: {==}
    case M.WorkspaceObservation{editor, observation, source}: {==}
    case M.PermissionsObservation{editor, observation}: {==}
    case M.ModelObservation{editor, profile, effort, found}: {==}
    case M.DeliveryObservation{editor, delivery}: {==}

def property_detail_equation(+property: M.Property) ->
  {P.property_detail(property) == Rule.property_detail_meaning(property) : String}:
  match property:
    case M.ProjectObservation{editor, None{}, found}: {==}
    case M.ProjectObservation{editor, Some{id}, None{}}: {==}
    case M.ProjectObservation{editor, Some{id}, Some{project}}: {==}
    case M.WorkspaceObservation{editor, observation, source}: {==}
    case M.PermissionsObservation{editor, observation}: {==}
    case M.ModelObservation{editor, key, effort, found}: {==}
    case M.DeliveryObservation{editor, U.Send{}}: {==}
    case M.DeliveryObservation{editor, U.Steer{}}: {==}

def property_summary_equation(+property: M.Property) ->
  {P.property_summary(property) == Rule.property_summary_meaning(property) : String}:
  match property:
    case M.ProjectObservation{editor, selected, found}: {==}
    case M.WorkspaceObservation{editor, observation, source}: {==}
    case M.PermissionsObservation{editor, observation}: {==}
    case M.ModelObservation{editor, profile, effort, found}: {==}
    case M.DeliveryObservation{editor, delivery}: {==}

def property_summary_parts_equation(+property: M.Property) ->
  {P.property_summary_parts(property) == Rule.property_summary_parts_meaning(property) : +List<String>}:
  match property:
    case M.ProjectObservation{editor, selected, found}: {==}
    case M.WorkspaceObservation{editor, observation, source}: {==}
    case M.PermissionsObservation{editor, observation}: {==}
    case M.ModelObservation{editor, profile, effort, found}: {==}
    case M.DeliveryObservation{editor, delivery}: {==}

def property_source_key_equation(+property: M.Property) ->
  {P.property_source_key(property) == Rule.property_source_key_meaning(property) : String}:
  match property:
    case M.ProjectObservation{editor, selected, found}: {==}
    case M.WorkspaceObservation{editor, observation, source}: {==}
    case M.PermissionsObservation{editor, observation}: {==}
    case M.ModelObservation{editor, profile, effort, found}: {==}
    case M.DeliveryObservation{editor, delivery}: {==}

def property_source_description_equation(+property: M.Property) ->
  {P.property_source_description(property) == Rule.property_source_description_meaning(property) : String}:
  match property:
    case M.ProjectObservation{editor, None{}, found}: {==}
    case M.ProjectObservation{editor, Some{id}, None{}}: {==}
    case M.ProjectObservation{editor, Some{id}, Some{project}}: {==}
    case M.WorkspaceObservation{editor, observation, source}: {==}
    case M.PermissionsObservation{editor, observation}: {==}
    case M.ModelObservation{editor, profile, effort, found}: {==}
    case M.DeliveryObservation{editor, delivery}: {==}

def property_help_equation(+property: M.Property) ->
  {P.property_help(property) == Rule.property_help_meaning(property) : String}:
  match property:
    case M.WorkspaceObservation{editor, +observation, source}: {==}
    case M.ProjectObservation{editor, selected, found}: {==}
    case M.PermissionsObservation{editor, observation}: {==}
    case M.ModelObservation{editor, profile, effort, found}: {==}
    case M.DeliveryObservation{editor, delivery}: {==}


def restricted_obstructions_equation(+assessment: M.Assessment, +reason: String) ->
  {P.assessment_obstructions(P.restricted(assessment, reason)) == P.restriction_obstructions(assessment, reason) : +List<M.Obstruction>}:
  Std.app_nil_r(M.Obstruction, P.restriction_obstructions(assessment, reason))

def restricted_reason_equation(+assessment: M.Assessment, +reason: String) ->
  {P.assessment_reason(P.restricted(assessment, reason)) == P.first_reason(P.restriction_obstructions(assessment, reason)) : String}:
  Equal.cong(+List<M.Obstruction>, String, P.first_reason,
    P.assessment_obstructions(P.restricted(assessment, reason)), P.restriction_obstructions(assessment, reason),
    restricted_obstructions_equation(assessment, reason))

def permission_draft_sources_equation(+editor: U.Editor, +origin: Context.Origin, project: Maybe<&2, Nat>, workspace: Context.WorkspaceValue, +sandbox: Context.SandboxValue, +approval: Context.ApprovalValue, guidance: Context.GuidancePreview) ->
  {P.property_source_key(P.permissions_property(editor, Context.DraftExecution{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}})) == Rule.permission_draft_source_meaning(origin, sandbox, approval) : String}:
  match origin sandbox approval:
    case Context.EnvironmentDefaults{} Context.InheritedSandbox{value} Context.InheritedApproval{policy}: {==}
    case Context.EnvironmentDefaults{} Context.InheritedSandbox{value} Context.ChosenApproval{policy}: {==}
    case Context.EnvironmentDefaults{} Context.ChosenSandbox{value} Context.InheritedApproval{policy}: {==}
    case Context.EnvironmentDefaults{} Context.ChosenSandbox{value} Context.ChosenApproval{policy}: {==}
    case Context.ProjectDefaults{id} Context.InheritedSandbox{value} Context.InheritedApproval{policy}: {==}
    case Context.ProjectDefaults{id} Context.InheritedSandbox{value} Context.ChosenApproval{policy}: {==}
    case Context.ProjectDefaults{id} Context.ChosenSandbox{value} Context.InheritedApproval{policy}: {==}
    case Context.ProjectDefaults{id} Context.ChosenSandbox{value} Context.ChosenApproval{policy}: {==}
    case Context.ParentTask{task} Context.InheritedSandbox{value} Context.InheritedApproval{policy}: {==}
    case Context.ParentTask{task} Context.InheritedSandbox{value} Context.ChosenApproval{policy}: {==}
    case Context.ParentTask{task} Context.ChosenSandbox{value} Context.InheritedApproval{policy}: {==}
    case Context.ParentTask{task} Context.ChosenSandbox{value} Context.ChosenApproval{policy}: {==}
    case Context.ProjectForParent{task, id} Context.InheritedSandbox{value} Context.InheritedApproval{policy}: {==}
    case Context.ProjectForParent{task, id} Context.InheritedSandbox{value} Context.ChosenApproval{policy}: {==}
    case Context.ProjectForParent{task, id} Context.ChosenSandbox{value} Context.InheritedApproval{policy}: {==}
    case Context.ProjectForParent{task, id} Context.ChosenSandbox{value} Context.ChosenApproval{policy}: {==}

def committed_unrestricted_parts_agreement(sandbox: D.Sandbox, choice: Context.ApprovalChoice) ->
  {P.committed_summary_parts(D.Unrestricted{}, sandbox, choice) == ["Full access", "Network available", "No approval"] : +List<String>}:
  match sandbox:
    case D.Sandbox{mode, network}: {==}

def shared_evidence() -> Rule.SharedRequirements:
  Rule.SharedRequirements{
    editor => +selected => world => {==},
    editor => +observation => world => {==},
    editor => observation => {==},
    editor => +profile => effort => world => {==},
    editor => delivery => {==},
    +property => property_editor_equation(property),
    +property => property_kind_equation(property),
    +property => property_state_equation(property),
    +property => property_value_equation(property),
    +property => property_summary_equation(property),
    mode => network => choice => {==},
    sandbox => choice => committed_unrestricted_parts_agreement(sandbox, choice),
    sandbox => choice => {==},
    reason => {==},
    origin => project => workspace => +sandbox => +approval => guidance => {==},
    task => workspace => +sandbox => +approval => project => guidance => +access => {==},
    +property => property_summary_parts_equation(property),
    {==},
    {==},
    {==},
    {==},
    profile => {==},
    +property => property_detail_equation(property),
    +editor => +origin => project => workspace => +sandbox => +approval => guidance => permission_draft_sources_equation(editor, origin, project, workspace, sandbox, approval, guidance),
    editor => +task => context => guidance => access => {==},
    +property => property_source_description_equation(property),
    +property => property_source_key_equation(property),
    +property => property_help_equation(property),
    +property => {==},
    +property => {==},
    +property => {==},
    +property => {==},
    editor => world => {==},
    editor => id => {==},
    editor => world => {==},
    editor => origin => project => workspace => +sandbox => approval => guidance => {==},
    editor => +origin => project => workspace => sandbox => approval => guidance => source => {==},
    +action => +property => {==},
    action => +property => {==},
    action => property => {==},
    +body => pending => +world => {==},
    body => pending => world => {==},
    +body => revision => pending => now => +world => {==},
    +first => +rest => body => revision => now => world => {==},
    workspace => body => revision => now => world => {==},
    +body => +revision => now => world => {==},
    +code => +reason => +identity => editor => {==},
    +identity => +requirements => +state => +refusal => {==},
    +identity => +requirements => +state => +refusal => {==},
    +identity => +requirements => +state => +refusal => {==},
    +assessment => {==},
    +assessment => {==},
    +assessment => {==},
    {==},
    {==},
    message => +profile => +reasoning => context => +world => {==},
    +task => message => delivery => world => {==},
    +id => name => workspace => world => {==},
    revision => +name => +profile => +reasoning => +instructions => settings => +concurrency => {==},
    +count => +messages => +parent => +world => {==},
    +id => world => {==},
    +name => {==},
    +name => {==},
    +profile => {==},
    +reasoning => {==},
    +instructions => {==},
    +count => {==},
    +count => +parent => {==},
    +count => +messages => {==},
    +count => +parent => world => {==},
    +editor => +reason => {==},
    effort => +editor => {==},
    +profile => +effort => +editor => {==},
    +id => name => workspace => world => {==},
    +editor => {==},
    +obstruction => {==},
    obstruction => {==},
    +target => +field => +code => +message => {==},
    +target => +field => +code => +message => {==},
    +target => +field => +code => +message => {==},
    +target => +field => +code => +message => {==},
    +assessment => reason => {==},
    +assessment => +reason => restricted_obstructions_equation(assessment, reason),
    assessment => reason => {==},
    +assessment => +reason => restricted_reason_equation(assessment, reason),
    +assessment => +reason => {==}}

def Rule.experience_evidence():
  Rule.Requirements{
    +subject => observation => question => alternatives => {==},
    subject => +observation => question => alternatives => {==},
    subject => observation => +question => alternatives => {==},
    +subject => +observation => question => +alternatives => {==},
    +subject => +observation => question => +alternatives => {==},
    subject => observation => question => {==},
    subject => observation => question => candidate => {==},
    compatible => rest => duplicate_rejection(compatible, rest),
    duplicate => rest => {==},
    label => explanation => +value => rest => subject => observation => +seen => duplicate_input(label, explanation, value, rest, subject, observation, seen),
    label => explanation => +value => rest => +candidate => {==},
    values => {==},
    {==},
    label => explanation => +value => rest => +subject => +observation => +seen => {==},
    +decision => +candidate => selected_equation(decision, candidate),
    +decision => +candidate => choose_equation(decision, candidate),
    subject => observation => {==},
    +subject => +observation => +value => {==},
    +editor => +field => +observation => +value => {==},
    intent => {==},
    +editor => +field => +observation => +value => {==},
    {==},
    +task => {==},
    +project => {==},
    +task => {==},
    +editor => {==},
    +editor => {==},
    +editor => {==},
    +editor => +field => {==},
    +editor => +revision => {==},
    +editor => {==},
    +editor => +first => +rest => {==},
    editor => object => {==},
    +editor => field => +rest => +object => {==},
    +object => editor => {==},
    object => +editor => {==},
    {==},
    +task => {==},
    +project => {==},
    +task => {==},
    +editor => {==},
    +editor => {==},
    +editor => {==},
    origin => project => workspace => +sandbox => approval => guidance => +mode => reviewers => {==},
    origin => project => workspace => +sandbox => approval => guidance => +enabled => reviewers => {==},
    origin => project => workspace => sandbox => approval => guidance => +choice => reviewers => {==},
    origin => project => workspace => +sandbox => approval => guidance => +mode => reviewers => {==},
    origin => project => workspace => +sandbox => approval => guidance => +network => reviewers => {==},
    origin => project => workspace => sandbox => +approval => guidance => +choice => reviewers => {==},
    +current => effort => +key => provider => name => policy => options => {==},
    profile => +current => +effort => {==},
    roots => +primary => +path => {==},
    observation => value => {==},
    observation => value => {==},
    old => +network => +mode => {==},
    +mode => old => +network => {==},
    +profile => +effort => model_selection(profile, effort),
    +profile => old => +effort => {==},
    +roots => primary => +path => {==},
    task => observation => value => {==},
    task => observation => value => {==},
    editor => +workspace => {==},
    +editor => workspace => {==},
    editor => +workspace => {==},
    editor => +workspace => +path => {==},
    +editor => +workspace => {==},
    +collection => +path => {==},
    +editor => +workspace => +path => {==},
    +editor => revision => pending => {==},
    editor => revision => +pending => {==},
    +editor => +revision => pending => {==},
    +editor => revision => pending => {==},
    +editor => revision => pending => {==},
    +editor => revision => pending => {==},
    +editor => +revision => pending => fields => {==},
    +editor => revision => pending => +fields => {==},
    +support => supporting_subjects(support),
    +field => {==},
    task => +field => {==},
    field => {==},
    task => {==},
    {==},
    shared_evidence(),
    +editor => +revision => +reason => {==},
    +graph => {==},
    +graph => {==},
    +graph => {==},
    graph => {==},
    +graph => source => world => {==},
    +graph => old => previous => +source => world => {==}}

def Rule.draft_workspace_requirement(revision, submitted, body, reason, entry, pending, world): {==}
def Rule.editing_draft_requirements(revision, body, entry, pending, world): {==}
def Rule.draft_preparation_requirements(draft, pending, world): {==}
def Rule.property_repair_observation(property, assessment): {==}

def Rule.empty_message_obstruction_is_passive(target, field, reason): {==}

def Rule.workspace_operation_classification(body):
  match body:
    case U.NewTask{message, profile, reasoning, context}: {==}
    case U.Project{id, name, workspace}: {==}
    case U.Agent{id, revision, name, profile, reasoning, instructions, context, concurrency}: {==}
    case U.Fork{task, count, messages, context}: {==}
    case U.Message{task, message, delivery}: {==}
    case U.Card{id, revision, value, assist, profile, keep_open}: {==}
    case U.Compact{task, summary}: {==}
    case U.TaskGraph{graph, declaration, parsed}: {==}

def Rule.assessment_attention_uses_all_obstructions(assessment): {==}
def Rule.attention_keeps_first_repair(obstruction, rest, repair):
  Equal.cong(Bool, Maybe<&2, M.Obstruction>, passive => P.attention_obstruction_select(passive, obstruction, P.attention_obstruction_list(rest)), P.passive_obstruction(obstruction), False{}, repair)
def Rule.attention_skips_passive_obstruction(obstruction, rest, passive):
  Equal.cong(Bool, Maybe<&2, M.Obstruction>, hidden => P.attention_obstruction_select(hidden, obstruction, P.attention_obstruction_list(rest)), P.passive_obstruction(obstruction), True{}, passive)

def editing_reading_from_draft(+edit: M.ProjectEdit, draft: U.Draft) ->
  {Activity.reading_units(Activity.editing_from_draft(edit, draft)) == 24n : Nat}:
  U.Draft{revision, body, feedback, entry} = draft
  {==}

def editing_reading_agreement(+edit: M.ProjectEdit) ->
  {Activity.reading_units(Activity.editing(edit)) == 24n : Nat}:
  editing_reading_from_draft(edit, P.project_edit_draft(edit))

def project_edit_agreement(+draft: U.Draft, +pending: Bool, +now: U32, +world: World.World()) ->
  {P.project_edit(draft, pending, now, world) == Rule.project_edit_meaning(draft, pending, now, world) : M.ProjectEdit}:
  match draft:
    case U.Draft{revision, body, feedback, entry}: {==}

def Rule.activity_evidence():
  Rule.ActivityRequirements{
    decision => children => {==},
    property => decision => children => facts => catalog => {==},
    property => decision => children => facts => catalog => {==},
    property => rest => {==},
    action => assessment => rest => {==},
    property => rest => {==},
    collection => {==},
    property => decision => children => facts => catalog => {==},
    property => decision => children => facts => catalog => {==},
    property => decision => children => facts => catalog => {==},
    property => decision => children => facts => catalog => {==},
    edit => editing_reading_agreement(edit),
    draft => pending => now => world => project_edit_agreement(draft, pending, now, world),
    revision => body => feedback => entry => pending => world => {==},
    id => name => workspace => entry => world => {==},
    origin => project => workspace => sandbox => approval => guidance => choice => reviewers => {==}}


def Rule.project_relations_order(property, edit, revision, body, feedback, entry):
  match body:
    case U.NewTask{message, profile, reasoning, context}: {==}
    case U.Message{task, message, delivery}: {==}
    case U.Project{id, name, workspace}: {==}
    case U.Card{card, draft_revision, value, assist, profile, keep_open}: {==}
    case U.Agent{agent, draft_revision, name, profile, reasoning, instructions, context, concurrency}: {==}
    case U.Fork{task, count, messages, context}: {==}
    case U.Compact{task, summary}: {==}
    case U.TaskGraph{graph, declaration, parsed}: {==}

def editing_relations_from_draft_agreement(+edit: M.ProjectEdit, +draft: U.Draft) ->
  {Activity.relations(Activity.editing_from_draft(edit, draft)) == Activity.project_relations_from_draft(P.project_edit_property(edit), edit, P.project_edit_draft(edit)) : +List<Activity.Relation>}:
  U.Draft{revision, body, feedback, entry} = draft
  {==}

def Rule.editing_relations_order(edit):
  editing_relations_from_draft_agreement(edit, P.project_edit_draft(edit))

def editing_purpose_from_draft(+edit: M.ProjectEdit, draft: U.Draft) ->
  {Activity.purpose(Activity.editing_from_draft(edit, draft)) == Activity.ObjectEditing{} : Activity.Purpose}:
  U.Draft{revision, body, feedback, entry} = draft
  {==}

def editing_purpose_agreement(+edit: M.ProjectEdit) ->
  {Activity.purpose(Activity.editing(edit)) == Activity.ObjectEditing{} : Activity.Purpose}:
  editing_purpose_from_draft(edit, P.project_edit_draft(edit))

def Rule.decision_disclosure_evidence():
  Rule.DecisionDisclosureRequirements{
    property => decision => children => facts => catalog => {==},
    property => decision => children => facts => catalog => {==},
    edit => editing_purpose_agreement(edit),
    activity => decision => focused => {==},
    purpose => focused => {==},
    focused => {==},
    {==}, {==}, {==}, {==},
    decision => {==},
    decision => subject => {==},
    parent => prerequisite => child => rest => subject => {==}}

def Rule.candidate_evidence():
  Rule.CandidateRequirements{
    parent => alternative => {==},
    parent => alternative => {==},
    parent => label => explanation => value => {==},
    admission => label => explanation => value => {==},
    observation => {==},
    observation => {==},
    parent => first => rest => {==},
    activity => parent => {==},
    activity => parent => query => {==}}

def Rule.relation_view_evidence():
  Rule.RelationViewRequirements{
    decision => children => {==},
    parent => prerequisite => decision => {==},
    property => {==}, property => {==}, collection => {==},
    action => assessment => {==},
    parent => subject => entry => profile => {==}}

def Rule.field_specification_evidence():
  Rule.FieldSpecificationRequirements{
    parent => profiles => {==},
    parent => profile => {==},
    editor => parent => profile => {==},
    parent => children => catalog => {==},
    parent => subject => entry => profile => {==},
    parent => {==}}

def Rule.reviewer_catalogue_evidence():
  Rule.ReviewerCatalogueRequirements{
    profile => reviewers => {==}, profile => {==}, key => {==},
    {==}, profile => {==}, parent => alternative => {==}}

def Rule.strategy_evidence():
  Rule.StrategyRequirements{
    {==}, {==}, profile => {==},
    profile => reviewers => {==}, reviewers => {==},
    strategy => current => reviewers => {==},
    origin => project => workspace => sandbox => approval => guidance => strategy => reviewers => {==},
    origin => project => workspace => sandbox => approval => guidance => strategy => reviewers => {==},
    {==}}

def Rule.relation_fold_evidence(Context, Result, handler, context):
  Rule.RelationFoldRequirements{
    {==},
    decision => children => rest => {==},
    parent => prerequisite => decision => rest => {==},
    property => rest => {==}, property => rest => {==},
    collection => rest => {==}, action => assessment => rest => {==},
    parent => subject => entry => profile => rest => {==}}

def compound_completion_agreement(property:M.Property, edit:M.ProjectEdit, relations:+List<Activity.Relation>, current:Activity.View) ->
  {Activity.completion(Activity.EditingActivity{property,edit,relations},current) == Activity.CommitOrDiscard{} : Activity.Completion}:
  match current:
    case Activity.PrincipalView{}: {==}
    case Activity.DependentView{subject}: {==}
    case Activity.InspectionView{focused}: {==}
    case Activity.CompoundView{}: {==}

def Rule.view_construction_evidence():
  Rule.ViewConstructionRequirements{
    activity => subject => {==},
    subject => {==},
    activity => decision => children => {==},
    activity => decision => children => {==},
    property => relations => catalog => {==},
    property => relations => catalog => {==},
    property => relations => catalog => subject => {==},
    property => relations => catalog => {==},
    property => relations => catalog => subject => {==},
    activity => decision => subject => children => {==},
    property => edit => relations => current => compound_completion_agreement(property,edit,relations,current),
    matches => observation => rest => {==},
    first => rest => query => {==},
    activity => current => property => {==},
    property => {==},
    fact => decision => children => {==},
    fact => decision => children => {==},
    property => {==},
    edit => subject => {==},
    activity => focused => property => {==},
    activity => property => {==},
    property => edit => relations => {==},
    property => relations => catalog => {==},
    property => relations => catalog => focused => {==},
    property => decision => {==},
    {==}, {==},
    activity => subject => {==},
    subject => property => decision => dependencies => {==},
    activity => current => value => {==},
    property => decision => dependencies => {==},
    subject => property => decision => dependencies => {==},
    subject => relation => {==},
    subject => property => {==},
    subject => rest => property => decision => dependencies => {==},
    activity => current => parent => prerequisite => decision => {==},
    subject => {==},
    activity => parent => subject => entry => profile => {==}}


def Rule.property_context_evidence():
  Rule.PropertyContextRequirements{
    editor => profile => effort => world => {==},
    editor => observation => {==},
    editor => profile => effort => world => {==},
    editor => observation => {==}}

def recognition_observation(+property: M.Property) ->
  {P.summary_property(P.property_recognition_summary(property)) == property : M.Property}:
  match property:
    case M.ProjectObservation{editor,selected,found}: {==}
    case M.WorkspaceObservation{editor,observation,source}: {==}
    case M.PermissionsObservation{editor,observation}: {==}
    case M.ModelObservation{editor,profile,effort,found}: {==}
    case M.DeliveryObservation{editor,delivery}: {==}

def recognition_projection_owner(+full: Bool, +property: M.Property, principal: M.SummaryValue, secondary: Maybe<&2,M.SummaryValue>) ->
  {P.summary_property(P.summary_projection(full,M.RecognitionSummary{property,principal,secondary})) == property : M.Property}:
  match full:
    case True{}: {==}
    case False{}: {==}

def recognition_projection_identity(+full: Bool, property: M.Property, +principal: M.SummaryValue, secondary: Maybe<&2,M.SummaryValue>) ->
  {P.summary_principal(P.summary_projection(full,M.RecognitionSummary{property,principal,secondary})) == principal : M.SummaryValue}:
  match full:
    case True{}: {==}
    case False{}: {==}

def recognition_compact_detail(+summary: M.RecognitionSummary) ->
  {P.summary_secondary(P.summary_projection(False{},summary)) == None{} : Maybe<&2,M.SummaryValue>}:
  M.RecognitionSummary{property,principal,secondary} = summary
  {==}

def Rule.recognition_summary_evidence():
  Rule.RecognitionSummaryRequirements{
    +property => recognition_observation(property),
    +editor => +selected => +found => {==},
    +editor => +observation => +source => {==},
    +editor => +delivery => {==},
    +editor => +profile => +effort => +found => {==},
    +editor => +observation => {==},
    {==}, {==}, {==},
    choice => observation => {==},
    reason => {==},
    origin => project => workspace => sandbox => approval => guidance => {==},
    task => workspace => sandbox => approval => project => guidance => {==},
    +editor => +task => +workspace => +sandbox => +approval => +project => +guidance => {==},
    editor => task => workspace => sandbox => approval => project => guidance => {==},
    +editor => +mode => network => {==},
    {==}, {==},
    +full => +property => principal => secondary => recognition_projection_owner(full,property,principal,secondary),
    +full => property => +principal => secondary => recognition_projection_identity(full,property,principal,secondary),
    summary => recognition_compact_detail(summary),
    +summary => {==}}

def Rule.information_evidence():
  Rule.InformationRequirements{
    parent => prerequisite => child => {==},
    parent => prerequisite => child => rest => {==},
    parent => prerequisite => child => subject => {==},
    observed => {==}, observed => {==},
    found => {==}, id => {==}, {==}, {==},
    activity => current => property => subject => {==},
    current => subject => reason => {==},
    current => subject => reason => {==},
    current => subject => reason => {==},
    expression => rest => {==}, expression => rest => {==},
    activity => current => property => expression => rest => {==},
    activity => current => coverage => {==}}
