From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers Schema.
From Selvedge.Interaction Require Import Codec Identity Forms.
Import ListNotations.
Open Scope string_scope.

(** Subjects refer to the actual declaration owned by an editor.  A native field
    name becomes a subject only after admission against that declaration. *)
Record subject (e : editor) := Subject {
  subject_description : form_field;
  subject_declared : In subject_description (form_fields e)
}.
Arguments Subject {e}.
Arguments subject_description {e}.
Arguments subject_declared {e}.
Definition subject_name {e} (s : subject e) :=
  field_name (specification (subject_description s)).
Definition subject_kind {e} (s : subject e) :=
  field_kind (specification (subject_description s)).
Definition admit_subject (e : editor) (name : string) : option (subject e).
Proof.
  destruct (find (fun f => String.eqb name (field_name (specification f)))
    (form_fields e)) as [f|] eqn:Found.
  - refine (Some (Subject f _)). apply find_some in Found. exact (proj1 Found).
  - exact None.
Defined.

Inductive object := TaskDraft | TaskObject (task : N)
| ProjectObject (project : option N) | GraphObject (graph : option N)
| EditorObject (owner : editor) | MessageDraftObject (task : N)
| WorkspaceObject (owner : editor) | ExecutionObject (owner : editor).
Definition object_eq_dec : forall (a b : object), {a = b} + {a <> b}.
Proof. repeat decide equality. Defined.
Definition same_object a b := if object_eq_dec a b then true else false.
Definition root_object e := match e with
| NewTask None => TaskDraft | Message task | Execution task => TaskObject task
| Project id => ProjectObject id | TaskGraph id _ => GraphObject id
| _ => EditorObject e end.
Definition subject_object {e} (s : subject e) :=
  match meaning (subject_description s) with
  | PrimaryDirectory | DirectoryCollection | DirectoryEntry | TaskEnvironmentSelection => WorkspaceObject e
  | ProfileSelection | ReasoningSelection | FilesystemSelection | NetworkSelection
  | ApprovalSelection | ReviewerSelection => ExecutionObject e
  | DeliverySelection => match e with Message task => MessageDraftObject task | _ => root_object e end
  | Scalar => match e with Message task => MessageDraftObject task | _ => root_object e end
  | ProjectSelection | ProjectWorktreePreference => root_object e end.
Definition object_key object := match object with
| TaskDraft => "task-draft" | TaskObject task => "task/" ++ show_natural task
| ProjectObject id => "project/" ++ id_text id | GraphObject id => "task-graph/" ++ id_text id
| EditorObject e => "editor/" ++ editor_key e
| MessageDraftObject task => "message-draft/" ++ show_natural task
| WorkspaceObject e => "workspace/" ++ editor_key e
| ExecutionObject e => "execution-configuration/" ++ editor_key e end.
Definition subject_key {e} (s : subject e) := object_key (subject_object s) ++ "/" ++ subject_name s.
Definition object_parent object := match object with
| WorkspaceObject e | ExecutionObject e => Some (root_object e)
| MessageDraftObject task => Some (TaskObject task) | _ => None end.
Definition group_owner {e} (subjects : list (subject e)) := match subjects with
| [] => root_object e
| first :: rest => if forallb (fun s => same_object (subject_object first) (subject_object s)) rest
    then subject_object first else root_object e end.

Inductive provenance := EnvironmentDefaults | ProjectDefaults (project : N)
| ParentTask (task : N) | DraftChoice | FrozenTask (task : N)
| CatalogEntry (profile : string) | MessageDelivery (task : N).
Inductive information := Present (value : json) | OptionalAbsence
| RequiredAbsence (reason : string) | Unavailable (reason : string)
| NotApplicable (reason : string).
Record observation (e : editor) := Observation {
  observed_subject : subject e;
  observed_information : information;
  observed_provenance : provenance
}.
Arguments Observation {e}.
Arguments observed_subject {e}.
Arguments observed_information {e}.
Arguments observed_provenance {e}.

(** A property's principal and dependent facts cannot silently acquire different
    owners.  Provenance remains per observation, rather than per editor. *)
Record property (e : editor) := Property {
  principal : observation e;
  related : list (observation e);
  related_owned : Forall (fun item => subject_object (observed_subject item) =
    subject_object (observed_subject principal)) related
}.
Arguments Property {e}.
Arguments principal {e}.
Arguments related {e}.
Definition property_owner {e} (p : property e) := subject_object (observed_subject (principal p)).
Definition property_subjects {e} (p : property e) :=
  observed_subject (principal p) :: map (@observed_subject e) (related p).

Record action_identity (e : editor) := ActionIdentity { action_revision : N }.
Arguments ActionIdentity {e}.
Arguments action_revision {e}.
Definition action_key {e} (identity : action_identity e) :=
  editor_key e ++ "/" ++ show_natural (action_revision identity).
Inductive repair_target (e : editor) := RepairField (field : subject e) | RepairEditor.
Arguments RepairField {e}.
Arguments RepairEditor {e}.
Record obstruction (e : editor) := Obstruction {
  obstruction_target : repair_target e;
  obstruction_code : string;
  obstruction_message : string;
  obstruction_actionable : bool
}.
Arguments Obstruction {e}.
Arguments obstruction_target {e}.
Arguments obstruction_code {e}.
Arguments obstruction_message {e}.
Arguments obstruction_actionable {e}.
Inductive assessment_result (e : editor) := PreparationReady
| DirectoryObservationRequired (workspace : json)
| PreparationBlocked (first : obstruction e) (rest : list (obstruction e)).
Arguments PreparationReady {e}.
Arguments DirectoryObservationRequired {e}.
Arguments PreparationBlocked {e}.
Record assessment (e : editor) := Assessment {
  assessment_identity : action_identity e;
  assessment_outcome : assessment_result e
}.
Arguments Assessment {e}.
Arguments assessment_identity {e}.
Arguments assessment_outcome {e}.
Definition assessment_obstructions {e} (a : assessment e) := match assessment_outcome a with
| PreparationBlocked first rest => first :: rest | _ => [] end.
Definition attention_obstruction {e} (a : assessment e) :=
  find (@obstruction_actionable e) (assessment_obstructions a).
Definition can_prepare {e} (a : assessment e) := match assessment_outcome a with
| PreparationBlocked _ _ => false | _ => true end.
Definition assess_requirements {e} revision (workspace : option json)
    (requirements : list (obstruction e)) : assessment e :=
  Assessment (ActionIdentity revision) (match requirements with
  | first :: rest => PreparationBlocked first rest
  | [] => match workspace with Some workspace => DirectoryObservationRequired workspace
      | None => PreparationReady end end).
Definition property_obstructions {e} (p : property e) (a : assessment e) :=
  filter (fun obstruction => match obstruction_target obstruction with
  | RepairField subject => existsb (fun own => String.eqb (subject_key subject) (subject_key own))
      (property_subjects p)
  | RepairEditor => false end) (assessment_obstructions a).

Record assignment (e : editor) := Assignment {
  assignment_subject : subject e;
  assignment_value : denote (subject_kind assignment_subject)
}.
Arguments Assignment {e}.
Arguments assignment_subject {e}.
Arguments assignment_value {e}.
Definition assignment_json {e} (a : assignment e) :=
  encode_value (subject_kind (assignment_subject a)) (assignment_value a).
Record alternative {e} (s : subject e) := Alternative {
  alternative_value : denote (subject_kind s);
  alternative_label : string;
  alternative_explanation : string;
  alternative_refusal : option string;
  alternative_supporting_assignments : list (assignment e)
}.
Arguments Alternative {e s}.
Arguments alternative_value {e s}.
Arguments alternative_label {e s}.
Arguments alternative_explanation {e s}.
Arguments alternative_refusal {e s}.
Arguments alternative_supporting_assignments {e s}.
Record decision (e : editor) := Decision {
  decision_subject : subject e;
  decision_selected : option (denote (subject_kind decision_subject));
  decision_alternatives : list (alternative decision_subject)
}.
Arguments Decision {e}.
Arguments decision_subject {e}.
Arguments decision_selected {e}.
Arguments decision_alternatives {e}.
Record dependency {e : editor} (parent : decision e) := Dependency {
  dependency_prerequisite : denote (subject_kind (decision_subject parent));
  dependency_child : decision e;
  dependency_common_owner : subject_object (decision_subject parent) =
    subject_object (decision_subject dependency_child)
}.
Arguments Dependency {e parent}.
Arguments dependency_prerequisite {e parent}.
Arguments dependency_child {e parent}.
Definition dependency_parent {e parent} (_ : dependency (e:=e) parent) := parent.
Definition dependency_applies {e parent} (d : dependency (e:=e) parent) :=
  match decision_selected parent with
  | None => false
  | Some value => Json.equal (encode_value _ value) (encode_value _ (dependency_prerequisite d)) end.
Definition choose {e s} (candidate : alternative (e := e) s) : option (list (assignment e)) :=
  match alternative_refusal candidate with
  | None => Some (Assignment s (alternative_value candidate) :: alternative_supporting_assignments candidate)
  | Some _ => None end.

Theorem admitted_subject_is_declared e name s :
  admit_subject e name = Some s -> In (subject_description s) (form_fields e).
Proof. intros _. exact (subject_declared s). Qed.
Theorem blocked_assessment_has_obstruction e (a : assessment e) :
  can_prepare a = false -> assessment_obstructions a <> [].
Proof. destruct a as [identity [|workspace|first rest]]; simpl; discriminate. Qed.
Theorem every_requirement_is_retained e revision workspace (requirements : list (obstruction e)) :
  assessment_obstructions (assess_requirements revision workspace requirements) = requirements.
Proof. destruct requirements; simpl; auto. destruct workspace; reflexivity. Qed.
Theorem preparation_admission_iff_no_requirement e revision workspace (requirements : list (obstruction e)) :
  can_prepare (assess_requirements revision workspace requirements) = true <-> requirements = [].
Proof.
  destruct requirements as [|first rest].
  - destruct workspace; simpl; tauto.
  - simpl. split; intros Impossible; discriminate.
Qed.
Theorem refused_candidate_cannot_be_applied e s (candidate : alternative (e := e) s) reason :
  alternative_refusal candidate = Some reason -> choose candidate = None.
Proof. intros Refused. unfold choose. now rewrite Refused. Qed.
Theorem dependency_preserves_actual_owner e parent (d : dependency (e:=e) parent) :
  subject_object (decision_subject (dependency_parent d)) =
  subject_object (decision_subject (dependency_child d)).
Proof. exact (dependency_common_owner _ d). Qed.
