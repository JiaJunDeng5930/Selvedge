import Base
import ./MODEL.bend as M
import ./PROGRAM.bend as UX
import ../INPUT.bend as U
import ../submission/FIELDS.bend as Forms
import ../services/CONTEXT.bend as Context
import ../../harness/DOMAIN.bend as D

# Dependencies are requests; only the root decision can admit them.
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

def admitted_dependency(applies: Bool, parent: M.Decision, prerequisite: M.Value, decision: M.Decision) -> +List<Relation>:
  match applies:
    case True{}: [DependentDecision{parent, prerequisite, decision}]
    case False{}: Nil{}

def dependent_decision(+parent: M.Decision, +prerequisite: M.Value, +decision: M.Decision) -> +List<Relation>:
  admitted_dependency(dependency_applies(parent, prerequisite, decision), parent, prerequisite, decision)

def dependencies(+parent: M.Decision, requests: +List<Dependency>) -> +List<Relation>:
  match requests:
    case Nil{}: Nil{}
    case Con{Dependency{prerequisite, decision}, rest}:
      List.append(&2, Relation, dependent_decision(parent, prerequisite, decision), dependencies(parent, rest))

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
        AssessedAction{UX.action(U.ProjectEditor{id}, revision, UX.project_edit_pending(edit)), UX.project_edit_assessment(edit)}, SupportingValue{property}]
    case _: [RequiredValue{property}, AssessedAction{UX.action(U.owner(body), revision, UX.project_edit_pending(edit)), UX.project_edit_assessment(edit)}, SupportingValue{property}]

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

def decision_disclosure(+activity: Activity, +decision: M.Decision, focused: Maybe<&2, M.Subject>) -> DecisionDisclosure:
  retained_disclosure(retains_decision(activity, decision), purpose(activity), focused_decision(decision, focused))

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
      [M.Alternative{"Ask", "Ask before a tool needs approval", M.ExecutionStrategy{M.Ask{}}},
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

def project_candidate_observations(values: +List<M.CandidateObservation>, +query: String) -> +List<M.CandidateObservation>:
  match values:
    case Nil{}: Nil{}
    case Con{+observation, rest}:
      candidate_observation_projection(candidate_matches(UX.candidate_alternative(observation), query), observation, project_candidate_observations(rest, query))

def visible_candidate_observations(+activity: Activity, +decision: M.Decision, query: String) -> +List<M.CandidateObservation>:
  project_candidate_observations(decision_candidates(activity, decision), query)

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
    case DependentDecision{parent, prerequisite, decision}: DependentDecisionView{parent, prerequisite, decision}
    case RequiredValue{property}: RequiredValueView{property}
    case SupportingValue{property}: SupportingValueView{property}
    case CollectionMembers{collection}: CollectionMembersView{collection}
    case AssessedAction{action, assessment}: AssessedActionView{action, assessment}
    case FieldSpecification{parent, subject, entry, profile}: FieldSpecificationView{parent, subject, entry, profile}

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
