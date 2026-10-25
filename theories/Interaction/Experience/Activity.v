From Stdlib Require Import String List Bool NArith.
From Selvedge.Kernel Require Domain.
From Selvedge.Interaction Require Import Identity.
From Selvedge.Interaction.Experience Require Import Model.
Import ListNotations.

Inductive view(e:editor):=PrincipalView|DependentView(subject:Model.subject e)
|InspectionView(subject:option(Model.subject e))|CompoundView.
Arguments PrincipalView {e}.
Arguments DependentView {e}.
Arguments InspectionView {e}.
Arguments CompoundView {e}.
Inductive activity_request := PropertyActivity (kind : property_kind)
| SubjectActivity (field : string) | WorkspaceActivity.

Record assignment (e : editor) := Assignment {
  assignment_subject : subject e;
  assignment_value : Selvedge.Foundation.Schema.denote (subject_kind assignment_subject)
}.
Arguments Assignment {e}.
Arguments assignment_subject {e}.
Arguments assignment_value {e}.

Inductive relation (e : editor) :=
| RootDecision (root : decision e) (children : list (relation e))
| DependentDecision (parent : decision e)
    (prerequisite : alternative e (decision_subject parent)) (child : decision e)
| RequiredValue (required : property e)
| SupportingValue (supporting : property e)
| CollectionMembers (members : collection e)
| AssessedAction (action : action_unit e) (outcome : assessment_result e)
| FieldSpecification (parent : decision e) (field : subject e) (profile : Domain.profile).
Arguments RootDecision {e}.
Arguments DependentDecision {e}.
Arguments RequiredValue {e}.
Arguments SupportingValue {e}.
Arguments CollectionMembers {e}.
Arguments AssessedAction {e}.
Arguments FieldSpecification {e}.

Inductive activity (e : editor) :=
| ComparisonActivity (compared : property e) (relations : list (relation e))
    (catalog : list Domain.profile)
| ExplanationActivity (explained : property e) (relations : list (relation e))
    (catalog : list Domain.profile)
| EditingActivity (edited : property e) (edits : list (assignment e))
    (relations : list (relation e)).
Arguments ComparisonActivity {e}.
Arguments ExplanationActivity {e}.
Arguments EditingActivity {e}.
Definition activity_property {e} (value : activity e) := match value with
| ComparisonActivity property _ _ | ExplanationActivity property _ _
| EditingActivity property _ _ => property end.
Definition activity_relations {e} (value : activity e) := match value with
| ComparisonActivity _ relations _ | ExplanationActivity _ relations _
| EditingActivity _ _ relations => relations end.
