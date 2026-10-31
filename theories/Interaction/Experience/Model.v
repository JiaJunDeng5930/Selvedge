From Stdlib Require Import String Ascii List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Programming Require Import Schema.
From Selvedge.Kernel Require Domain.
From Selvedge.Interaction Require Import Identity.
From Selvedge.Interaction.Submission Require Import Fields Parameters.
Import ListNotations.
Open Scope string_scope.

(** Product subjects name an admitted parameter of their actual owner.  Native
    controls and HTML element kinds are deliberately absent from this model. *)
Record subject (e : editor) := Subject {
  subject_declaration : Fields.field;
  subject_declared : In subject_declaration (Parameters.subject_fields e)
}.
Arguments Subject {e}.
Arguments subject_declaration {e}.
Arguments subject_declared {e}.
Definition admit_subject (e : editor) (name : string) : option (subject e).
Proof.
  destruct (find (fun field => String.eqb name (Parameters.name field))
    (Parameters.subject_fields e)) as [field|] eqn:Found.
  - refine (Some (Subject field _)). apply find_some in Found. exact (proj1 Found).
  - exact None.
Defined.
Definition subject_editor {e} (_ : subject e) := e.
Definition subject_name {e} (s : subject e) := Parameters.name (subject_declaration s).
Definition subject_kind {e} (s : subject e) := Parameters.kind e (subject_declaration s).

Inductive object := TaskDraft | TaskObject (task : N)
| ProjectObject (project : option N) | GraphObject (graph : option N)
| EditorObject (owner : editor) | MessageDraftObject (task : N)
| WorkspaceObject (owner : editor) | ExecutionObject (owner : editor).
Definition root_object e := match e with
| NewTask None => TaskDraft | Message task => TaskObject task
| Project id => ProjectObject id | TaskGraph id _ => GraphObject id
| _ => EditorObject e end.
Definition field_object e field := match field with
| WorkspacePrimary | WorkspaceDirectories | TaskEnvironment => WorkspaceObject e
| ModelProfile | ReasoningEffort | SandboxMode | NetworkAccess | ApprovalPolicy | ApprovalReviewer => ExecutionObject e
| _ => match e,field with
  | Message task,MessageText | Message task,DeliveryIntent => MessageDraftObject task
  | Project id,_ => ProjectObject id | TaskGraph id _,_ => GraphObject id
  | _,_ => EditorObject e end end.
Definition subject_object {e} (s : subject e) := field_object e (subject_declaration s).
Definition object_eq_dec : forall left right:object,{left=right}+{left<>right}.
Proof. decide equality;try apply Identity.editor_eq_dec;try apply N.eq_dec;decide equality;apply N.eq_dec. Defined.
Definition group_owner e fields := match fields with
| [] => root_object e
| first::rest => let owner:=field_object e first in
  if forallb (fun field=>if object_eq_dec (field_object e field) owner then true else false) rest
  then owner else root_object e end.

Inductive property_kind := ProjectProperty | WorkspaceProperty | PermissionsProperty | ModelProperty | DeliveryProperty.
Inductive property_state := Selected | Absent | Invalid | UnavailableObservation.
Inductive readable_value := TextValue (text : string)
| NamedReference (identity : N) (name : string)
| WorkspaceValue (paths : list string) (primary : option string) (inherited : bool)
| NamedChoice (name explanation : string).
Fixpoint directory_basename_from (path : string) (previous segment : string)
  {struct path} : string :=
  match path with
  | EmptyString => if String.eqb segment "" then previous else segment
  | String character rest =>
    if Ascii.eqb character "/"%char then
      directory_basename_from rest
        (if String.eqb segment "" then previous else segment) ""
    else directory_basename_from rest previous (segment ++ String character "")
  end.
(** A workspace caption uses its last nonempty segment; a root path keeps its
    original spelling when it has no named segment. *)
Definition directory_basename path := directory_basename_from path path "".
Definition readable_text value := match value with
| TextValue text => text | NamedReference _ name => name | NamedChoice name _ => name
| WorkspaceValue _ (Some primary) _ => directory_basename primary
| WorkspaceValue _ None _ => "No directory" end.
Record summary_value (e : editor) := SummaryValue {
  summary_subject : subject e;
  summary_observation : readable_value
}.
Arguments SummaryValue {e}.
Arguments summary_subject {e}.
Arguments summary_observation {e}.
Inductive information (e : editor) := NotApplicable (reason : string)
| PresentInformation (principal : summary_value e) (secondary : option (summary_value e))
| OptionalAbsence | RequiredAbsence (reason : string)
| InvalidInformation (reason : string) | UnavailableInformation (reason : string).
Arguments NotApplicable {e}.
Arguments PresentInformation {e}.
Arguments OptionalAbsence {e}.
Arguments RequiredAbsence {e}.
Arguments InvalidInformation {e}.
Arguments UnavailableInformation {e}.
Record property (e : editor) := Property {
  property_kind_of : property_kind;
  property_subject : subject e;
  property_members : list (subject e);
  property_information : information e;
  property_help : string
}.
Arguments Property {e}.
Arguments property_kind_of {e}.
Arguments property_subject {e}.
Arguments property_members {e}.
Arguments property_information {e}.
Arguments property_help {e}.
Definition property_editor {e} (_ : property e) := e.
Definition property_owner {e} (p : property e) := subject_object (property_subject p).
Definition property_subjects {e} (p : property e) := property_subject p :: property_members p.
Definition property_label {e} (p : property e) := match property_kind_of p with
| ProjectProperty => "Project" | WorkspaceProperty => "Workspace"
| PermissionsProperty => "Permissions" | ModelProperty => "Model" | DeliveryProperty => "Send as" end.
Definition property_status {e} (p : property e) := match property_information p with
| PresentInformation _ _ => Selected | OptionalAbsence | RequiredAbsence _ => Absent
| InvalidInformation _ => Invalid | _ => UnavailableObservation end.
Definition principal_information {e} (p : property e) := match property_information p with
| PresentInformation principal _ => readable_text (summary_observation principal)
| OptionalAbsence => match property_kind_of p with ProjectProperty=>"No project"|WorkspaceProperty=>"No working directory"|_=>"Not set"end
| NotApplicable reason | RequiredAbsence reason | InvalidInformation reason | UnavailableInformation reason => reason end.
Definition secondary_information {e} (p : property e) := match property_information p with
| PresentInformation _ (Some secondary) => Some (readable_text (summary_observation secondary))
| _ => None end.

Inductive availability := Available | Unavailable (reason : string).
Record alternative (e : editor) (s : subject e) := Alternative {
  alternative_label : string;
  alternative_explanation : string;
  alternative_value : denote (subject_kind s);
  alternative_selected : bool;
  alternative_availability : availability;
  alternative_consequences : list (summary_value e)
}.
Arguments Alternative {e s}.
Arguments alternative_label {e s}.
Arguments alternative_explanation {e s}.
Arguments alternative_value {e s}.
Arguments alternative_selected {e s}.
Arguments alternative_availability {e s}.
Arguments alternative_consequences {e s}.
Record decision (e : editor) := Decision {
  decision_subject : subject e;
  decision_observation : information e;
  decision_question : string;
  decision_alternatives : list (alternative e decision_subject);
  decision_availability : availability
}.
Arguments Decision {e}.
Arguments decision_subject {e}.
Arguments decision_observation {e}.
Arguments decision_question {e}.
Arguments decision_alternatives {e}.
Arguments decision_availability {e}.
Record collection (e : editor) := Collection {
  collection_workspace : Domain.workspace;
  collection_inherited : bool
}.
Arguments Collection {e}.
Arguments collection_workspace {e}.
Arguments collection_inherited {e}.
Definition collection_editor {e} (_ : collection e) := e.
Record action_identity (e : editor) := ActionIdentity { action_revision : N }.
Arguments ActionIdentity {e}.
Arguments action_revision {e}.
Inductive action_context := Creation | Continuation (task : N) | ObjectEditing.
Record action_unit (e : editor) := ActionUnit {
  action_identity_of : action_identity e;
  action_context_of : action_context;
  action_pending : bool
}.
Arguments ActionUnit {e}.
Arguments action_identity_of {e}.
Arguments action_context_of {e}.
Arguments action_pending {e}.
Record support (e:editor):=Support{support_identity:action_identity e;support_fields:list(subject e)}.
Arguments Support {e}.
Arguments support_identity {e}.
Arguments support_fields {e}.
Inductive repair_target (e : editor) := RepairEditor | RepairField (field : subject e).
Arguments RepairEditor {e}.
Arguments RepairField {e}.
Record obstruction (e : editor) := Obstruction {
  obstruction_target : repair_target e;
  obstruction_code : string;
  obstruction_message : string
}.
Arguments Obstruction {e}.
Arguments obstruction_target {e}.
Arguments obstruction_code {e}.
Arguments obstruction_message {e}.
Inductive assessment_result (e : editor) := PreparationReady
| DirectoryObservationRequired (workspace : Domain.workspace)
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
