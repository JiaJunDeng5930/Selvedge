import Base
import ./MODEL.bend as M
import ./PROGRAM.bend as UX
import ../INPUT.bend as U
import ../submission/FIELDS.bend as Forms
import ../services/CONTEXT.bend as Context
import ../../harness/DOMAIN.bend as D

# Dependencies retain their condition even when the current choice makes them inactive.
type Dependency is Data:
  Dependency{prerequisite: M.Value, decision: M.Decision}

type Relation is Data:
  RootDecision{decision: M.Decision, children: +List<Relation>}
  DependentDecision{parent: M.Decision, prerequisite: M.Value, decision: M.Decision}
  RequiredValue{property: M.Property}
  SupportingValue{property: M.Property}
  CollectionMembers{collection: M.Collection}
  AssessedAction{action: M.ActionUnit, assessment: M.Assessment}
  FieldSpecification{parent: M.Decision, subject: M.Subject, entry: Forms.Entry, profile: D.Profile}

type Activity is Data:
  ComparisonActivity{property: M.Property, relations: +List<Relation>, catalog: +List<D.Profile>}
  ExplanationActivity{property: M.Property, relations: +List<Relation>, catalog: +List<D.Profile>}
  EditingActivity{property: M.Property, edit: M.ProjectEdit, relations: +List<Relation>}

def subject_editor(subject: M.Subject) -> U.Editor:
  M.Subject{editor, field} = subject
  editor

def decision_editor(decision: M.Decision) -> U.Editor:
  subject_editor(UX.decision_subject(decision))

def same_owner(+parent: M.Decision, +child: M.Decision) -> Bool:
  String.eq(UX.object_key(UX.owner(UX.decision_subject(parent))), UX.object_key(UX.owner(UX.decision_subject(child))))

def dependency_applies(+parent: M.Decision, +prerequisite: M.Value, +child: M.Decision) -> Bool:
  UX.selected(parent, prerequisite) && same_owner(parent, child) && U.same_editor(decision_editor(parent), decision_editor(child))

# An inactive condition remains available to information planning. Admission of
# choices and edits continues to use dependency_applies at the consumer boundary.
def retained_dependency(owned: Bool, parent: M.Decision, prerequisite: M.Value, decision: M.Decision) -> +List<Relation>:
  match owned:
    case True{}: [DependentDecision{parent, prerequisite, decision}]
    case False{}: Nil{}

def dependencies(+parent: M.Decision, requests: +List<Dependency>) -> +List<Relation>:
  match requests:
    case Nil{}: Nil{}
    case Con{Dependency{prerequisite, +decision}, rest}:
      List.append(&2, Relation, retained_dependency(same_owner(parent, decision) && U.same_editor(decision_editor(parent), decision_editor(decision)), parent, prerequisite, decision), dependencies(parent, rest))

def root_decision(+decision: M.Decision, children: +List<Dependency>) -> Relation:
  RootDecision{decision, dependencies(decision, children)}

def admitted_required(owned: Bool, property: M.Property) -> +List<Relation>:
  match owned:
    case True{}: [RequiredValue{property}]
    case False{}: Nil{}

def required_values(properties: +List<M.Property>, +editor: U.Editor) -> +List<Relation>:
  match properties:
    case Nil{}: Nil{}
    case Con{+property, rest}:
      List.append(&2, Relation, admitted_required(U.same_editor(UX.property_editor(property), editor), property), required_values(rest, editor))

def field_owner_matches(+parent: M.Decision, +child: M.Subject) -> Bool:
  U.same_editor(decision_editor(parent), subject_editor(child)) &&
    String.eq(UX.object_key(UX.owner(UX.decision_subject(parent))), UX.object_key(UX.owner(child)))

def admitted_effort_field(selected: Bool, parent: M.Decision, subject: M.Subject, entry: Forms.Entry, profile: D.Profile) -> +List<Relation>:
  match selected:
    case True{}: [FieldSpecification{parent, subject, entry, profile}]
    case False{}: Nil{}

def effort_field_for_subject(subject: M.Subject, +parent: M.Decision, +profile: D.Profile, entry: Forms.Entry) -> +List<Relation>:
  match subject entry:
    case M.Subject{+editor, Forms.ModelProfile{}} Forms.SingleLine{}:
      admitted_effort_field(UX.selected(parent, M.Model{profile}) && field_owner_matches(parent, M.Subject{editor, Forms.ReasoningEffort{}}), parent, M.Subject{editor, Forms.ReasoningEffort{}}, Forms.SingleLine{}, profile)
    case M.Subject{+editor, Forms.ModelProfile{}} Forms.DisplayOnly{}:
      admitted_effort_field(UX.selected(parent, M.Model{profile}) && field_owner_matches(parent, M.Subject{editor, Forms.ReasoningEffort{}}), parent, M.Subject{editor, Forms.ReasoningEffort{}}, Forms.DisplayOnly{}, profile)
    case _ _: Nil{}

def effort_field_for_profile(found: Maybe<&2, D.Profile>, +parent: M.Decision) -> +List<Relation>:
  match found:
    case None{}: Nil{}
    case Some{+profile}: effort_field_for_subject(UX.decision_subject(parent), parent, profile, Forms.profile_effort_entry(profile))

def effort_field_for_observation(observation: Forms.Observed, profiles: +List<D.Profile>, parent: M.Decision) -> +List<Relation>:
  match observation:
    case Forms.ModelValue{profile, effort}: effort_field_for_profile(D.find_profile(profiles, profile), parent)
    case _: Nil{}

def effort_field_specification(+parent: M.Decision, profiles: +List<D.Profile>) -> +List<Relation>:
  effort_field_for_observation(UX.decision_observation(parent), profiles, parent)

def root_decision_for_catalog(+decision: M.Decision, children: +List<Dependency>, catalog: +List<D.Profile>) -> Relation:
  RootDecision{decision, List.append(&2, Relation, dependencies(decision, children), effort_field_specification(decision, catalog))}

def decision_relations(owned: Bool, decision: M.Decision, children: +List<Dependency>, catalog: +List<D.Profile>) -> +List<Relation>:
  match owned:
    case True{}: [root_decision_for_catalog(decision, children, catalog)]
    case False{}: Nil{}

def observed_relations(+property: M.Property, +decision: M.Decision, children: +List<Dependency>, facts: +List<M.Property>, catalog: +List<D.Profile>) -> +List<Relation>:
  RequiredValue{property} <>
    List.append(&2, Relation,
      decision_relations(U.same_editor(UX.property_editor(property), decision_editor(decision)), decision, children, catalog),
      List.append(&2, Relation, required_values(facts, UX.property_editor(property)), [SupportingValue{property}]))

def comparison(+property: M.Property, decision: M.Decision, children: +List<Dependency>, facts: +List<M.Property>, +catalog: +List<D.Profile>) -> Activity:
  ComparisonActivity{property, observed_relations(property, decision, children, facts, catalog), catalog}

def explanation(+property: M.Property, decision: M.Decision, children: +List<Dependency>, facts: +List<M.Property>, +catalog: +List<D.Profile>) -> Activity:
  ExplanationActivity{property, observed_relations(property, decision, children, facts, catalog), catalog}

def project_relations_from_draft(+property: M.Property, +edit: M.ProjectEdit, draft: U.Draft) -> +List<Relation>:
  U.Draft{revision, body, feedback, entry} = draft
  match body:
    case U.Project{+id, name, workspace}:
      [RequiredValue{property}, CollectionMembers{UX.collection(U.ProjectEditor{id}, workspace)},
        SupportingValue{property}, AssessedAction{UX.action(U.ProjectEditor{id}, revision, UX.project_edit_pending(edit)), UX.project_edit_assessment(edit)}]
    case _: [RequiredValue{property}, SupportingValue{property}, AssessedAction{UX.action(U.owner(body), revision, UX.project_edit_pending(edit)), UX.project_edit_assessment(edit)}]

def project_relations(+property: M.Property, +edit: M.ProjectEdit) -> +List<Relation>:
  project_relations_from_draft(property, edit, UX.project_edit_draft(edit))

def editing_from_draft(+edit: M.ProjectEdit, draft: U.Draft) -> Activity:
  U.Draft{revision, body, feedback, entry} = draft
  +property: M.Property = UX.project_edit_property(edit)
  EditingActivity{property, edit, project_relations(property, edit)}

def editing(+edit: M.ProjectEdit) -> Activity:
  editing_from_draft(edit, UX.project_edit_draft(edit))

def property(activity: Activity) -> M.Property:
  match activity:
    case ComparisonActivity{property, relations, catalog}: property
    case ExplanationActivity{property, relations, catalog}: property
    case EditingActivity{property, edit, relations}: property

def object(activity: Activity) -> M.Object:
  UX.property_owner(property(activity))

def scope(activity: Activity) -> U.Editor:
  UX.property_editor(property(activity))

def relations(activity: Activity) -> +List<Relation>:
  match activity:
    case ComparisonActivity{property, relations, catalog}: relations
    case ExplanationActivity{property, relations, catalog}: relations
    case EditingActivity{property, edit, relations}: relations

def reading_units(activity: Activity) -> Nat:
  match activity:
    case ComparisonActivity{property, relations, catalog}: 12n
    case ExplanationActivity{property, relations, catalog}: 16n
    case EditingActivity{property, edit, relations}: 24n

def required_relations(values: +List<Relation>) -> +List<Relation>:
  match values:
    case Nil{}: Nil{}
    case Con{+value, rest}:
      match value:
        case SupportingValue{property}: required_relations(rest)
        case _: value <> required_relations(rest)

def support_relations(values: +List<Relation>) -> +List<Relation>:
  match values:
    case Nil{}: Nil{}
    case Con{value, rest}:
      match value:
        case SupportingValue{property}: SupportingValue{property} <> support_relations(rest)
        case _: support_relations(rest)

def required_evidence(activity: Activity) -> +List<Relation>:
  required_relations(relations(activity))

def support_evidence(activity: Activity) -> +List<Relation>:
  support_relations(relations(activity))

def collection_members(collection: M.Collection) -> +List<String>:
  UX.collection_members(collection)

def editing_observation(activity: Activity) -> Maybe<&2, M.ProjectEdit>:
  match activity:
    case EditingActivity{property, edit, relations}: Some{edit}
    case _: None{}

# Query projection reads a decision but never constructs or replaces it.
def candidate_matches(candidate: M.Alternative, query: String) -> Bool:
  M.Alternative{label, explanation, value} = candidate
  String.contains(String.to_lower(label ++ " " ++ UX.value_key(value)), String.to_lower(String.trim(query)))

def projected_candidate(matches: Bool, candidate: M.Alternative, rest: +List<M.Alternative>) -> +List<M.Alternative>:
  match matches:
    case True{}: candidate <> rest
    case False{}: rest

def project_candidates(values: +List<M.Alternative>, +query: String) -> +List<M.Alternative>:
  match values:
    case Nil{}: Nil{}
    case Con{+candidate, rest}: projected_candidate(candidate_matches(candidate, query), candidate, project_candidates(rest, query))

def visible_candidates(decision: M.Decision, query: String) -> +List<M.Alternative>:
  project_candidates(UX.decision_alternatives(decision), query)

def catalog(activity: Activity) -> +List<D.Profile>:
  match activity:
    case ComparisonActivity{property, relations, catalog}: catalog
    case ExplanationActivity{property, relations, catalog}: catalog
    case EditingActivity{property, edit, relations}: Nil{}

# Purpose is the activity's semantic construction, independent of reading measure.
type Purpose is Data:
  Comparison{}
  EffectExplanation{}
  ObjectEditing{}

type DecisionDisclosure is Data:
  Candidates{}
  Summary{}

def purpose(activity: Activity) -> Purpose:
  match activity:
    case ComparisonActivity{property, relations, catalog}: Comparison{}
    case ExplanationActivity{property, relations, catalog}: EffectExplanation{}
    case EditingActivity{property, edit, relations}: ObjectEditing{}

def same_subject(+left: M.Subject, +right: M.Subject) -> Bool:
  UX.same_subject(left, right) && U.same_editor(subject_editor(left), subject_editor(right)) &&
    String.eq(UX.object_key(UX.owner(left)), UX.object_key(UX.owner(right)))

def decision_subject_matches(decision: M.Decision, subject: M.Subject) -> Bool:
  same_subject(UX.decision_subject(decision), subject)

def retained_decisions(values: +List<Relation>, +subject: M.Subject) -> Bool:
  match values:
    case Nil{}: False{}
    case Con{value, rest}:
      match value:
        case RootDecision{decision, children}:
          decision_subject_matches(decision, subject) || retained_decisions(children, subject) || retained_decisions(rest, subject)
        case DependentDecision{+parent, +prerequisite, +decision}:
          (dependency_applies(parent, prerequisite, decision) && decision_subject_matches(decision, subject)) || retained_decisions(rest, subject)
        case _: retained_decisions(rest, subject)

def retains_decision(activity: Activity, decision: M.Decision) -> Bool:
  retained_decisions(relations(activity), UX.decision_subject(decision))

def focused_decision(decision: M.Decision, focused: Maybe<&2, M.Subject>) -> Bool:
  match focused:
    case None{}: False{}
    case Some{subject}: decision_subject_matches(decision, subject)

def focused_disclosure(focused: Bool) -> DecisionDisclosure:
  match focused:
    case True{}: Candidates{}
    case False{}: Summary{}

def purpose_disclosure(purpose: Purpose, focused: Bool) -> DecisionDisclosure:
  match purpose:
    case Comparison{}: Candidates{}
    case _: focused_disclosure(focused)

def retained_disclosure(retained: Bool, purpose: Purpose, focused: Bool) -> DecisionDisclosure:
  match retained:
    case True{}: purpose_disclosure(purpose, focused)
    case False{}: Summary{}

def model_catalog_alternatives(profiles: +List<D.Profile>) -> +List<M.Alternative>:
  match profiles:
    case Nil{}: Nil{}
    case Con{+profile, rest}:
      D.Profile{key, provider, name, policy, options} = profile
      M.Alternative{name, provider, M.Model{profile}} <> model_catalog_alternatives(rest)

def reviewer_catalog_alternatives(profiles: +List<D.Profile>) -> +List<M.Alternative>:
  match profiles:
    case Nil{}: Nil{}
    case Con{D.Profile{key, provider, name, policy, options}, rest}:
      M.Alternative{name, provider, M.Approval{Context.AutomaticReview{key}}} <> reviewer_catalog_alternatives(rest)

def reviewer_alternatives_from_observation(observation: Forms.Observed) -> +List<M.Alternative>:
  match observation:
    case Forms.ContextValue{preview, reviewers}: reviewer_catalog_alternatives(reviewers)
    case _: Nil{}

def execution_strategy_alternatives(observation: Forms.Observed) -> +List<M.Alternative>:
  match observation:
    case Forms.ContextValue{preview, reviewers}:
      [M.Alternative{"Ask", "Bash 请求扩大访问范围时，由你批准一次", M.ExecutionStrategy{M.Ask{}}},
        M.Alternative{"Automatic review", "Review approvals with a configured model", M.ExecutionStrategy{M.AutomaticReview{}}},
        M.Alternative{"Full access", "Unrestricted execution without approval", M.ExecutionStrategy{M.FullAccess{}}}]
    case _: Nil{}

def decision_alternatives_from_subject(subject: M.Subject, catalog: +List<D.Profile>, decision: M.Decision) -> +List<M.Alternative>:
  M.Subject{editor, field} = subject
  match field:
    case Forms.ApprovalPolicy{}: execution_strategy_alternatives(UX.decision_observation(decision))
    case Forms.ModelProfile{}: model_catalog_alternatives(catalog)
    case Forms.ApprovalReviewer{}: reviewer_alternatives_from_observation(UX.decision_observation(decision))
    case _: UX.decision_alternatives(decision)

def retained_candidates(retained: Bool, +activity: Activity, +decision: M.Decision) -> +List<M.CandidateObservation>:
  match retained:
    case True{}: UX.candidate_observations(decision, decision_alternatives_from_subject(UX.decision_subject(decision), catalog(activity), decision))
    case False{}: Nil{}

def decision_candidates(+activity: Activity, +decision: M.Decision) -> +List<M.CandidateObservation>:
  retained_candidates(retains_decision(activity, decision), activity, decision)

def candidate_observation_projection(matches: Bool, observation: M.CandidateObservation, rest: +List<M.CandidateObservation>) -> +List<M.CandidateObservation>:
  match matches:
    case True{}: observation <> rest
    case False{}: rest

def selected_candidate_projection(selected: Bool, matches: Bool, observation: M.CandidateObservation, rest: +List<M.CandidateObservation>) -> +List<M.CandidateObservation>:
  candidate_observation_projection(selected || matches, observation, rest)

def project_candidate_observations(values: +List<M.CandidateObservation>, +query: String) -> +List<M.CandidateObservation>:
  match values:
    case Nil{}: Nil{}
    case Con{+observation, rest}:
      selected_candidate_projection(UX.candidate_selected(observation), candidate_matches(UX.candidate_alternative(observation), query), observation, project_candidate_observations(rest, query))

def visible_candidate_observations(+activity: Activity, +decision: M.Decision, query: String) -> +List<M.CandidateObservation>:
  project_candidate_observations(decision_candidates(activity, decision), query)

# A requested view is admitted against the actual retained relation tree.
type View is Data:
  PrincipalView{}
  DependentView{subject: M.Subject}
  InspectionView{focused: Maybe<&2, M.Subject>}
  CompoundView{}

type Completion is Data:
  ApplyAndDismiss{}
  ApplyAndReturn{}
  ReturnToOwner{}
  CommitOrDiscard{}

type Exposure is Data:
  HiddenRelation{}
  CandidateChoices{}
  DependencySummary{}
  ParameterControl{}
  RequiredExpression{}
  RequestedInformation{}
  CompoundContent{}

type FactReference is Data:
  AppliedReference{}
  DraftReference{}
  OriginalReference{}

type FactIdentity is Data:
  FactIdentity{owner: M.Object, subjects: +List<M.Subject>, observation: M.Property, reference: FactReference}

type DraftFieldIdentity is Data:
  DraftFieldIdentity{owner: M.Object, subject: M.Subject, draft: U.Draft}

def draft_field_identity(+edit: M.ProjectEdit, +subject: M.Subject) -> DraftFieldIdentity:
  DraftFieldIdentity{UX.owner(subject), subject, UX.project_edit_draft(edit)}

type Coverage is Data:
  SelectedPrincipal{fact: FactIdentity, decision: M.Decision, dependencies: +List<Relation>}
  CurrentDependency{fact: FactIdentity, relation: Relation}
  OriginalObject{fact: FactIdentity, edit: M.ProjectEdit}
  RequestedInspection{fact: FactIdentity}
  NecessaryInline{fact: FactIdentity}

def field_specification_applies(+parent: M.Decision, +subject: M.Subject, +profile: D.Profile) -> Bool:
  field_owner_matches(parent, subject) && UX.selected(parent, M.Model{profile})

def retained_subject(values: +List<Relation>, +subject: M.Subject) -> Bool:
  match values:
    case Nil{}: False{}
    case Con{relation, rest}:
      match relation:
        case RootDecision{decision, children}: decision_subject_matches(decision, subject) || retained_subject(children, subject) || retained_subject(rest, subject)
        case DependentDecision{+parent, +prerequisite, +decision}: (dependency_applies(parent, prerequisite, decision) && decision_subject_matches(decision, subject)) || retained_subject(rest, subject)
        case FieldSpecification{parent, +child, entry, profile}: (field_specification_applies(parent, child, profile) && same_subject(child, subject)) || retained_subject(rest, subject)
        case _: retained_subject(rest, subject)

def admitted_focus(retained: Bool, subject: M.Subject) -> Maybe<&2, M.Subject>:
  match retained:
    case True{}: Some{subject}
    case False{}: None{}

def requested_focus(+activity: Activity, focus: Maybe<&2, M.Subject>) -> Maybe<&2, M.Subject>:
  match focus:
    case None{}: None{}
    case Some{+subject}: admitted_focus(retained_subject(relations(activity), subject), subject)

def requested_view(inspection: Bool, focus: Maybe<&2, M.Subject>) -> View:
  match inspection focus:
    case True{} focus: InspectionView{focus}
    case False{} Some{subject}: DependentView{subject}
    case False{} None{}: PrincipalView{}

def root_subject(values: +List<Relation>, +subject: M.Subject) -> Bool:
  match values:
    case Nil{}: False{}
    case Con{relation, rest}:
      match relation:
        case RootDecision{decision, children}: decision_subject_matches(decision, subject) || root_subject(rest, subject)
        case _: root_subject(rest, subject)

def focus_is_root(+activity: Activity, focus: Maybe<&2,M.Subject>) -> Bool:
  match focus:
    case Some{subject}: root_subject(relations(activity), subject)
    case None{}: False{}

def requested_view_for_root(root: Bool, inspection: Bool, focus: Maybe<&2,M.Subject>) -> View:
  match root inspection:
    case True{} False{}: PrincipalView{}
    case _ _: requested_view(inspection, focus)

def view_for_purpose(goal: Purpose, root: Bool, focus: Maybe<&2, M.Subject>, inspection: Bool) -> View:
  match goal:
    case ObjectEditing{}: CompoundView{}
    case _: requested_view_for_root(root, inspection, focus)

def view(+activity: Activity, +focus: Maybe<&2, M.Subject>, inspection: Bool) -> View:
  view_for_purpose(purpose(activity), focus_is_root(activity, focus), requested_focus(activity, focus), inspection)

def inspection_completion(focus: Maybe<&2,M.Subject>) -> Completion:
  match focus:
    case Some{subject}: ApplyAndReturn{}
    case None{}: ReturnToOwner{}

def completion_for_purpose(goal: Purpose, current: View) -> Completion:
  match goal current:
    case ObjectEditing{} _: CommitOrDiscard{}
    case _ PrincipalView{}: ApplyAndDismiss{}
    case _ DependentView{subject}: ApplyAndReturn{}
    case _ InspectionView{focused}: inspection_completion(focused)
    case _ CompoundView{}: CommitOrDiscard{}

def completion(activity: Activity, current: View) -> Completion:
  completion_for_purpose(purpose(activity), current)

def view_focus(current: View) -> Maybe<&2, M.Subject>:
  match current:
    case DependentView{subject}: Some{subject}
    case InspectionView{focused}: focused
    case _: None{}

def focus_matches(focus: Maybe<&2,M.Subject>, subject: M.Subject) -> Bool:
  match focus:
    case None{}: False{}
    case Some{focused}: same_subject(focused, subject)

def requested_subject(current: View, subject: M.Subject) -> Bool:
  focus_matches(view_focus(current), subject)

def candidate_exposure(requested: Bool) -> Exposure:
  match requested:
    case True{}: CandidateChoices{}
    case False{}: HiddenRelation{}

def parameter_exposure(requested: Bool) -> Exposure:
  match requested:
    case True{}: ParameterControl{}
    case False{}: HiddenRelation{}

def admitted_exposure(admitted: Bool, exposed: Exposure) -> Exposure:
  match admitted:
    case True{}: exposed
    case False{}: HiddenRelation{}

def dependent_exposure(current: View, subject: M.Subject) -> Exposure:
  match current:
    case PrincipalView{}: DependencySummary{}
    case InspectionView{None{}}: DependencySummary{}
    case _: candidate_exposure(requested_subject(current, subject))

def field_exposure(current: View, subject: M.Subject) -> Exposure:
  match current:
    case PrincipalView{}: DependencySummary{}
    case InspectionView{None{}}: DependencySummary{}
    case _: parameter_exposure(requested_subject(current, subject))

def initial_dependency_exposure(goal: Purpose) -> Exposure:
  match goal:
    case Comparison{}: DependencySummary{}
    case _: HiddenRelation{}

def dependency_view_exposure(activity: Activity, current: View, subject: M.Subject) -> Exposure:
  match current:
    case PrincipalView{}: initial_dependency_exposure(purpose(activity))
    case _: dependent_exposure(current,subject)

def parameter_view_exposure(activity: Activity, current: View, subject: M.Subject) -> Exposure:
  match current:
    case PrincipalView{}: initial_dependency_exposure(purpose(activity))
    case _: field_exposure(current,subject)

def root_exposure(current: View) -> Exposure:
  match current:
    case PrincipalView{}: CandidateChoices{}
    case InspectionView{None{}}: DependencySummary{}
    case _: HiddenRelation{}

def root_decision_exposure(+activity: Activity, +current: View, +decision: M.Decision) -> Exposure:
  match current:
    case InspectionView{Some{subject}}:
      candidate_exposure(retains_decision(activity,decision) && same_subject(UX.decision_subject(decision),subject))
    case _: root_exposure(current)

def support_exposure(current: View) -> Exposure:
  match current:
    case InspectionView{focused}: RequestedInformation{}
    case CompoundView{}: RequestedInformation{}
    case _: HiddenRelation{}

def compound_exposure(current: View) -> Exposure:
  match current:
    case CompoundView{}: CompoundContent{}
    case _: HiddenRelation{}

def relation_exposure(+activity: Activity, +current: View, relation: Relation) -> Exposure:
  match relation:
    case RootDecision{decision, children}: root_decision_exposure(activity,current,decision)
    case DependentDecision{+parent, +prerequisite, +decision}:
      admitted_exposure(dependency_applies(parent, prerequisite, decision) && retains_decision(activity, decision), dependency_view_exposure(activity, current, UX.decision_subject(decision)))
    case FieldSpecification{+parent, +subject, entry, +profile}:
      admitted_exposure(field_specification_applies(parent, subject, profile) && retained_subject(relations(activity), subject), parameter_view_exposure(activity, current, subject))
    case RequiredValue{property}: RequiredExpression{}
    case SupportingValue{property}: support_exposure(current)
    case CollectionMembers{collection}: compound_exposure(current)
    case AssessedAction{action, assessment}: compound_exposure(current)


def reference_for_editor(editor: U.Editor) -> FactReference:
  match editor:
    case U.MessageEditor{task}: AppliedReference{}
    case U.ProjectEditor{id}: OriginalReference{}
    case _: DraftReference{}

def property_reference(property: M.Property) -> FactReference:
  reference_for_editor(UX.property_editor(property))

def fact_identity(+property: M.Property) -> FactIdentity:
  FactIdentity{UX.property_owner(property), UX.property_subjects(property), property, property_reference(property)}

def same_boolean(left: Bool, right: Bool) -> Bool:
  match left right:
    case True{} True{}: True{}
    case False{} False{}: True{}
    case _ _: False{}

def same_sandbox(left: D.Sandbox, right: D.Sandbox) -> Bool:
  D.Sandbox{left_mode, left_network} = left
  D.Sandbox{right_mode, right_network} = right
  UX.value_same(M.Filesystem{left_mode}, M.Filesystem{right_mode}) && same_boolean(left_network, right_network)

def preview_matches_context(preview: Context.Preview, sandbox: D.Sandbox, choice: Context.ApprovalChoice) -> Bool:
  match preview:
    case Context.ProspectiveContext{origin, project, workspace, current_sandbox, approval, guidance}:
      same_sandbox(Context.unwrap_sandbox(current_sandbox), sandbox) && UX.value_same(M.Approval{Context.observed_approval(approval)}, M.Approval{choice})
    case _: False{}

def context_observation_matches(observation: Context.Observation, preview: Context.Preview) -> Bool:
  match observation:
    case Context.DraftExecution{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}}:
      preview_matches_context(preview, Context.unwrap_sandbox(sandbox), Context.observed_approval(approval))
    case Context.CommittedExecution{Context.EffectiveContext{task, D.TaskContext{workspace, sandbox, approval, project}, guidance, access}}:
      preview_matches_context(preview, sandbox, Context.approval_choice(approval))
    case _: False{}

def model_context_matches(found: Maybe<&2,Forms.Observed>, observed: Forms.Observed) -> Bool:
  match found observed:
    case Some{Forms.ModelValue{profile,effort}} Forms.ModelValue{current_profile,current_effort}:
      String.eq(profile,current_profile) && String.eq(effort,current_effort)
    case _ _: False{}

def permission_context_matches(found: Maybe<&2,Context.Observation>, observed: Forms.Observed) -> Bool:
  match found observed:
    case Some{observation} Forms.ContextValue{preview,reviewers}: context_observation_matches(observation,preview)
    case _ _: False{}

def observation_matches(+property: M.Property, +observed: Forms.Observed, editor: U.Editor) -> Bool:
  U.same_editor(UX.property_editor(property),editor) &&
    (model_context_matches(UX.property_model_context(property),observed) || permission_context_matches(UX.property_permission_context(property),observed))


def property_observation_matches(+property: M.Property, +decision: M.Decision) -> Bool:
  String.eq(UX.object_key(UX.property_owner(property)), UX.object_key(UX.owner(UX.decision_subject(decision)))) && observation_matches(property, UX.decision_observation(decision), decision_editor(decision))

def selected_candidate_present(candidates: +List<M.CandidateObservation>) -> Bool:
  match candidates:
    case Nil{}: False{}
    case Con{candidate, rest}: UX.candidate_selected(candidate) || selected_candidate_present(rest)

def selected_expression(found: Bool, fact: FactIdentity, decision: M.Decision, children: +List<Relation>) -> Maybe<&2, Coverage>:
  match found:
    case True{}: Some{SelectedPrincipal{fact, decision, children}}
    case False{}: None{}

def dependent_expression(admitted: Bool, property: M.Property, relation: Relation) -> Maybe<&2,Coverage>:
  match admitted:
    case True{}: Some{CurrentDependency{fact_identity(property), relation}}
    case False{}: None{}

def root_expression(current: View, matched: Bool, fact: FactIdentity, decision: M.Decision, children: +List<Relation>) -> Maybe<&2,Coverage>:
  match current:
    case PrincipalView{}: selected_expression(matched, fact, decision, children)
    case _: None{}

def relation_expression(+activity: Activity, +property: M.Property, +current: View, +relation: Relation) -> Maybe<&2, Coverage>:
  match relation:
    case RootDecision{+decision, children}:
      root_expression(current, property_observation_matches(property, decision) && selected_candidate_present(decision_candidates(activity, decision)), fact_identity(property), decision, children)
    case DependentDecision{parent, prerequisite, +decision}:
      dependent_expression(requested_subject(current, UX.decision_subject(decision)) && dependency_applies(parent, prerequisite, decision) && property_observation_matches(property, decision), property, relation)
    case FieldSpecification{+parent, +subject, entry, +profile}:
      dependent_expression(requested_subject(current, subject) && field_specification_applies(parent, subject, profile) && property_observation_matches(property, parent), property, relation)
    case _: None{}

def expression_or_rest(found: Maybe<&2, Coverage>, rest: Maybe<&2, Coverage>) -> Maybe<&2, Coverage>:
  match found:
    case Some{value}: Some{value}
    case None{}: rest

def expressions_from_relations(+activity: Activity, +property: M.Property, +current: View, values: +List<Relation>) -> Maybe<&2, Coverage>:
  match values:
    case Nil{}: None{}
    case Con{+relation, rest}:
      match relation:
        case RootDecision{decision, children}:
          expression_or_rest(relation_expression(activity, property, current, relation), expression_or_rest(expressions_from_relations(activity, property, current, children), expressions_from_relations(activity, property, current, rest)))
        case _:
          expression_or_rest(relation_expression(activity, property, current, relation), expressions_from_relations(activity, property, current, rest))

def expression_or_inline(found: Maybe<&2, Coverage>, property: M.Property) -> Coverage:
  match found:
    case Some{value}: value
    case None{}: NecessaryInline{fact_identity(property)}

def original_found(found: Maybe<&2,M.ProjectEdit>, property: M.Property) -> Coverage:
  match found:
    case Some{edit}: OriginalObject{fact_identity(property), edit}
    case None{}: NecessaryInline{fact_identity(property)}

def original_expression(activity: Activity, property: M.Property) -> Coverage:
  original_found(editing_observation(activity), property)

def coverage(+activity: Activity, current: View, +property: M.Property) -> Coverage:
  match current:
    case InspectionView{focused}: RequestedInspection{fact_identity(property)}
    case CompoundView{}: original_expression(activity, property)
    case _: expression_or_inline(expressions_from_relations(activity, property, current, relations(activity)), property)

def search_for_purpose(goal: Purpose, current: View, profiles: +List<D.Profile>) -> Bool:
  match goal current:
    case Comparison{} PrincipalView{}: Nat.is_lt(8n, List.length(&2, D.Profile, profiles))
    case _ _: False{}

def search_for_kind(kind: M.PropertyKind, goal: Purpose, current: View, profiles: +List<D.Profile>) -> Bool:
  match kind:
    case M.ModelProperty{}: search_for_purpose(goal, current, profiles)
    case _: False{}

def search_for_view(current: View, kind: M.PropertyKind, goal: Purpose, profiles: +List<D.Profile>) -> Bool:
  match current:
    case PrincipalView{}: search_for_kind(kind,goal,PrincipalView{},profiles)
    case _: False{}

def search_required(+activity: Activity, current: View) -> Bool:
  search_for_view(current,UX.property_kind(property(activity)),purpose(activity),catalog(activity))

def root_decision_matches(values: +List<Relation>, +decision: M.Decision) -> Bool:
  match values:
    case Nil{}: False{}
    case Con{relation, rest}:
      match relation:
        case RootDecision{root, children}: same_subject(UX.decision_subject(root), UX.decision_subject(decision)) || root_decision_matches(rest, decision)
        case _: root_decision_matches(rest, decision)

def view_disclosure(+activity: Activity, +decision: M.Decision, +current: View) -> DecisionDisclosure:
  match current:
    case PrincipalView{}:
      focused_disclosure(root_decision_matches(relations(activity), decision))
    case _:
      focused_disclosure(requested_subject(current, UX.decision_subject(decision)) && retains_decision(activity, decision))

def decision_disclosure(+activity: Activity, +decision: M.Decision, focused: Maybe<&2, M.Subject>) -> DecisionDisclosure:
  view_disclosure(activity, decision, view(activity, focused, False{}))

# Views expose retained payloads for interpretation, not activity construction.
type RelationView is Data:
  RootDecisionView{decision: M.Decision, children: +List<Relation>}
  DependentDecisionView{parent: M.Decision, prerequisite: M.Value, decision: M.Decision}
  RequiredValueView{property: M.Property}
  SupportingValueView{property: M.Property}
  CollectionMembersView{collection: M.Collection}
  AssessedActionView{action: M.ActionUnit, assessment: M.Assessment}
  FieldSpecificationView{parent: M.Decision, subject: M.Subject, entry: Forms.Entry, profile: D.Profile}

def relation_view(relation: Relation) -> RelationView:
  match relation:
    case RootDecision{decision, children}: RootDecisionView{decision, children}
    case DependentDecision{+parent, +prerequisite, +decision}: DependentDecisionView{parent, prerequisite, decision}
    case RequiredValue{property}: RequiredValueView{property}
    case SupportingValue{property}: SupportingValueView{property}
    case CollectionMembers{collection}: CollectionMembersView{collection}
    case AssessedAction{action, assessment}: AssessedActionView{action, assessment}
    case FieldSpecification{+parent, +subject, entry, +profile}: FieldSpecificationView{parent, subject, entry, profile}

# Structural traversal remains with the owner of the recursive relation carrier.
def fold_relations(~Context: Data, ~Result: Data, ~handler: Context -> RelationView -> +List<Result> -> Result, +context: Context, values: +List<Relation>) -> +List<Result>:
  match values:
    case Nil{}: Nil{}
    case Con{+relation, rest}:
      match relation:
        case RootDecision{decision, children}:
          handler(context, relation_view(relation), fold_relations(~Context, ~Result, ~handler, context, children)) <> fold_relations(~Context, ~Result, ~handler, context, rest)
        case _:
          handler(context, relation_view(relation), Nil{}) <> fold_relations(~Context, ~Result, ~handler, context, rest)

# Each required subject receives an expression; partial coverage retains inline facts.
type SubjectExpression is Data:
  SelectedSubject{subject: M.Subject, decision: M.Decision}
  OwnedParameter{subject: M.Subject, relation: Relation}
  PermissionConsequence{subject: M.Subject, observation: Context.Observation, decision: M.Decision}
  OwnerContext{subject: M.Subject, property: M.Property}
  OriginalIdentity{subject: M.Subject, edit: M.ProjectEdit}
  InspectionFact{subject: M.Subject, property: M.Property}
  InlineSubject{subject: M.Subject, property: M.Property}

def expression_subject(expression: SubjectExpression) -> M.Subject:
  match expression:
    case SelectedSubject{subject, decision}: subject
    case OwnedParameter{subject, relation}: subject
    case PermissionConsequence{subject, observation, decision}: subject
    case OwnerContext{subject, property}: subject
    case OriginalIdentity{subject, edit}: subject
    case InspectionFact{subject, property}: subject
    case InlineSubject{subject, property}: subject

def parameter_subject(relation: Relation) -> Maybe<&2,M.Subject>:
  match relation:
    case DependentDecision{parent, prerequisite, decision}: Some{UX.decision_subject(decision)}
    case FieldSpecification{parent, subject, entry, profile}: Some{subject}
    case _: None{}

def admitted_parameter_relation(relation: Relation) -> Bool:
  match relation:
    case DependentDecision{parent, prerequisite, decision}: dependency_applies(parent, prerequisite, decision)
    case FieldSpecification{parent, subject, entry, profile}: field_specification_applies(parent, subject, profile)
    case _: False{}

def subject_parameter_match(found: Maybe<&2,M.Subject>, subject: M.Subject) -> Bool:
  match found:
    case Some{parameter}: same_subject(parameter, subject)
    case None{}: False{}

def admitted_parameter_expression(admitted: Bool, subject: M.Subject, relation: Relation) -> Maybe<&2,SubjectExpression>:
  match admitted:
    case True{}: Some{OwnedParameter{subject, relation}}
    case False{}: None{}

def parameter_expression(+subject: M.Subject, +relation: Relation) -> Maybe<&2,SubjectExpression>:
  admitted_parameter_expression(admitted_parameter_relation(relation) && subject_parameter_match(parameter_subject(relation), subject), subject, relation)

def parameter_or_rest(found: Maybe<&2,SubjectExpression>, rest: Maybe<&2,SubjectExpression>) -> Maybe<&2,SubjectExpression>:
  match found:
    case Some{expression}: Some{expression}
    case None{}: rest

def parameter_from_relations(+subject: M.Subject, values: +List<Relation>) -> Maybe<&2,SubjectExpression>:
  match values:
    case Nil{}: None{}
    case Con{+relation, rest}:
      match relation:
        case RootDecision{decision, children}: parameter_or_rest(parameter_from_relations(subject, children), parameter_from_relations(subject, rest))
        case _: parameter_or_rest(parameter_expression(subject, relation), parameter_from_relations(subject, rest))

def permission_subject(field: Forms.Field) -> Bool:
  match field:
    case Forms.SandboxMode{}: True{}
    case Forms.NetworkAccess{}: True{}
    case Forms.ApprovalReviewer{}: True{}
    case _: False{}

def permission_expression(admitted: Bool, subject: M.Subject, observation: Context.Observation, decision: M.Decision, property: M.Property) -> SubjectExpression:
  match admitted:
    case True{}: PermissionConsequence{subject, observation, decision}
    case False{}: InlineSubject{subject, property}

def permission_subject_value(subject: M.Subject) -> Bool:
  M.Subject{editor,field} = subject
  permission_subject(field)

def consequence_from_context(+found: Maybe<&2,Context.Observation>, +subject: M.Subject, +property: M.Property, +decision: M.Decision) -> SubjectExpression:
  match found:
    case Some{observation}: permission_expression(permission_subject_value(subject) && property_observation_matches(property,decision),subject,observation,decision,property)
    case None{}: InlineSubject{subject,property}

def consequence_expression(+subject: M.Subject, +property: M.Property, decision: M.Decision) -> SubjectExpression:
  consequence_from_context(UX.property_permission_context(property),subject,property,decision)


def parameter_or_consequence(found: Maybe<&2,SubjectExpression>, subject: M.Subject, property: M.Property, decision: M.Decision) -> SubjectExpression:
  match found:
    case Some{expression}: expression
    case None{}: consequence_expression(subject, property, decision)

def remaining_principal_expression(kind: M.PropertyKind, +subject: M.Subject, property: M.Property, decision: M.Decision, dependencies: +List<Relation>) -> SubjectExpression:
  match kind:
    case M.PermissionsProperty{}: consequence_expression(subject,property,decision)
    case _: parameter_or_consequence(parameter_from_relations(subject,dependencies),subject,property,decision)

def principal_subject_expression(selected: Bool, +subject: M.Subject, +property: M.Property, decision: M.Decision, dependencies: +List<Relation>) -> SubjectExpression:
  match selected:
    case True{}: SelectedSubject{subject, decision}
    case False{}: remaining_principal_expression(UX.property_kind(property),subject,property,decision,dependencies)

def principal_expressions(subjects: +List<M.Subject>, +property: M.Property, +decision: M.Decision, +dependencies: +List<Relation>) -> +List<SubjectExpression>:
  match subjects:
    case Nil{}: Nil{}
    case Con{+subject, rest}:
      principal_subject_expression(same_subject(subject, UX.decision_subject(decision)), subject, property, decision, dependencies) <> principal_expressions(rest, property, decision, dependencies)

def owner_context_expression(field: Forms.Field, subject: M.Subject, property: M.Property) -> SubjectExpression:
  match field:
    case Forms.ModelProfile{}: OwnerContext{subject, property}
    case Forms.ApprovalPolicy{}: OwnerContext{subject, property}
    case _: InlineSubject{subject, property}

def context_expression(+subject: M.Subject, property: M.Property) -> SubjectExpression:
  M.Subject{editor, field} = subject
  owner_context_expression(field, subject, property)

def dependent_subject_expression(found: Maybe<&2,SubjectExpression>, subject: M.Subject, property: M.Property) -> SubjectExpression:
  match found:
    case Some{expression}: expression
    case None{}: context_expression(subject, property)

def dependent_expressions(subjects: +List<M.Subject>, +property: M.Property, +relation: Relation) -> +List<SubjectExpression>:
  match subjects:
    case Nil{}: Nil{}
    case Con{+subject, rest}: dependent_subject_expression(parameter_expression(subject, relation), subject, property) <> dependent_expressions(rest, property, relation)

def fact_subjects(fact: FactIdentity) -> +List<M.Subject>:
  FactIdentity{owner, subjects, observation, reference} = fact
  subjects

def fact_property(fact: FactIdentity) -> M.Property:
  FactIdentity{owner, subjects, observation, reference} = fact
  observation

def inspected_expressions(subjects: +List<M.Subject>, +property: M.Property) -> +List<SubjectExpression>:
  match subjects:
    case Nil{}: Nil{}
    case Con{subject, rest}: InspectionFact{subject, property} <> inspected_expressions(rest, property)

def inline_expressions(subjects: +List<M.Subject>, +property: M.Property) -> +List<SubjectExpression>:
  match subjects:
    case Nil{}: Nil{}
    case Con{subject, rest}: InlineSubject{subject, property} <> inline_expressions(rest, property)

def original_expressions(subjects: +List<M.Subject>, +edit: M.ProjectEdit) -> +List<SubjectExpression>:
  match subjects:
    case Nil{}: Nil{}
    case Con{subject, rest}: OriginalIdentity{subject, edit} <> original_expressions(rest, edit)

def coverage_expressions(value: Coverage) -> +List<SubjectExpression>:
  match value:
    case SelectedPrincipal{+fact, decision, dependencies}: principal_expressions(fact_subjects(fact), fact_property(fact), decision, dependencies)
    case CurrentDependency{+fact, relation}: dependent_expressions(fact_subjects(fact), fact_property(fact), relation)
    case OriginalObject{fact, edit}: original_expressions(fact_subjects(fact), edit)
    case RequestedInspection{+fact}: inspected_expressions(fact_subjects(fact), fact_property(fact))
    case NecessaryInline{+fact}: inline_expressions(fact_subjects(fact), fact_property(fact))

# The fold's public view keeps the exact payload used by common projection policy.
def relation_for_view(value: RelationView) -> Relation:
  match value:
    case RootDecisionView{decision, children}: RootDecision{decision, children}
    case DependentDecisionView{parent, prerequisite, decision}: DependentDecision{parent, prerequisite, decision}
    case RequiredValueView{property}: RequiredValue{property}
    case SupportingValueView{property}: SupportingValue{property}
    case CollectionMembersView{collection}: CollectionMembers{collection}
    case AssessedActionView{action, assessment}: AssessedAction{action, assessment}
    case FieldSpecificationView{parent, subject, entry, profile}: FieldSpecification{parent, subject, entry, profile}

def relation_view_exposure(activity: Activity, current: View, value: RelationView) -> Exposure:
  relation_exposure(activity,current,relation_for_view(value))


# Applicability and absence are observations of the activity's real dependencies
# and domain observations, never classifications of already formatted captions.
type DependencyState is Data:
  IndependentInformation{}
  InactiveInformation{}
  ActiveInformation{}

def merge_dependency(left: DependencyState, right: DependencyState) -> DependencyState:
  match left right:
    case ActiveInformation{} _: ActiveInformation{}
    case _ ActiveInformation{}: ActiveInformation{}
    case InactiveInformation{} _: InactiveInformation{}
    case _ InactiveInformation{}: InactiveInformation{}
    case _ _: IndependentInformation{}

def dependency_condition(matched: Bool, active: Bool) -> DependencyState:
  match matched active:
    case False{} _: IndependentInformation{}
    case True{} True{}: ActiveInformation{}
    case True{} False{}: InactiveInformation{}

def relation_dependency(relation: Relation, +subject: M.Subject) -> DependencyState:
  match relation:
    case DependentDecision{+parent, +prerequisite, +decision}:
      dependency_condition(same_subject(UX.decision_subject(decision), subject), dependency_applies(parent, prerequisite, decision))
    case FieldSpecification{+parent, +child, entry, +profile}:
      dependency_condition(same_subject(child, subject), field_specification_applies(parent, child, profile))
    case _: IndependentInformation{}

def subject_dependency(values: +List<Relation>, +subject: M.Subject) -> DependencyState:
  match values:
    case Nil{}: IndependentInformation{}
    case Con{relation, rest}:
      match relation:
        case RootDecision{decision, children}: merge_dependency(subject_dependency(children,subject),subject_dependency(rest,subject))
        case _: merge_dependency(relation_dependency(relation,subject),subject_dependency(rest,subject))

def obstruction_subject_information(matched: Bool, obstruction: M.Obstruction, fallback: M.InformationStatus) -> M.InformationStatus:
  match matched:
    case True{}: M.RequiredAbsence{UX.obstruction_message(obstruction)}
    case False{}: fallback

def obstruction_information(values: +List<M.Obstruction>, +subject: M.Subject, fallback: M.InformationStatus) -> M.InformationStatus:
  match values:
    case Nil{}: fallback
    case Con{+obstruction, rest}:
      obstruction_subject_information(UX.subject_obstruction_matches(subject, UX.obstruction_field(obstruction)), obstruction, obstruction_information(rest, subject, fallback))


def editing_information(found: Maybe<&2,M.ProjectEdit>, subject: M.Subject, fallback: M.InformationStatus) -> M.InformationStatus:
  match found:
    case None{}: fallback
    case Some{edit}: obstruction_information(UX.assessment_obstructions(UX.project_edit_assessment(edit)), subject, fallback)

def conditional_information(condition: DependencyState, observed: M.InformationStatus) -> M.InformationStatus:
  match condition:
    case InactiveInformation{}: M.NotApplicable{"This setting does not apply to the current selection"}
    case _: observed

def information_status(+activity: Activity, current: View, +property: M.Property, +subject: M.Subject) -> M.InformationStatus:
  conditional_information(subject_dependency(relations(activity), subject),
    editing_information(editing_observation(activity), subject, UX.property_information(property, subject, catalog(activity))))

def information_visible(current: View, subject: M.Subject, status: M.InformationStatus) -> Bool:
  match status:
    case M.NotApplicable{reason}: requested_subject(current, subject)
    case _: True{}

def coverage_property(value: Coverage) -> M.Property:
  match value:
    case SelectedPrincipal{fact, decision, dependencies}: fact_property(fact)
    case CurrentDependency{fact, relation}: fact_property(fact)
    case OriginalObject{fact, edit}: fact_property(fact)
    case RequestedInspection{fact}: fact_property(fact)
    case NecessaryInline{fact}: fact_property(fact)

def admitted_information(visible: Bool, expression: SubjectExpression, rest: +List<SubjectExpression>) -> +List<SubjectExpression>:
  match visible:
    case True{}: expression <> rest
    case False{}: rest

def required_information_expressions(+activity: Activity, +current: View, +property: M.Property, values: +List<SubjectExpression>) -> +List<SubjectExpression>:
  match values:
    case Nil{}: Nil{}
    case Con{+expression, rest}:
      admitted_information(information_visible(current, expression_subject(expression), information_status(activity, current, property, expression_subject(expression))), expression,
        required_information_expressions(activity, current, property, rest))

def information_expressions(+activity: Activity, +current: View, +value: Coverage) -> +List<SubjectExpression>:
  required_information_expressions(activity, current, coverage_property(value), coverage_expressions(value))
