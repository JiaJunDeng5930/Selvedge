From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema.
From Selvedge.Interaction Require Import Codec CommandAssessment Application.
From Selvedge.Interaction.Session Require Draft State Authoring.
From Selvedge.Interaction.Experience Require Activity Model Observation.
From Selvedge.Interaction.Submission Require Parameters.
From Selvedge.Browser Require Layout.
Import ListNotations.
Open Scope string_scope.
Module EO:=Selvedge.Interaction.Experience.Observation.
Module EM:=Selvedge.Interaction.Experience.Model.
Module SS:=Selvedge.Interaction.Session.State.

(** A parser callback without a current document owner cannot drive either
    product preparation or a new publication generation. *)
Theorem irrelevant_document_observation_is_idle request snapshot namespace source raw state:
 Documents.admit_observation
   (Selvedge.Interaction.Session.Runtime.context namespace snapshot state)
   source(SS.document_retention state)=Documents.IrrelevantObservation ->
 Application.input_decision request snapshot namespace (Input.CodeObserved source)raw state=
 (Authoring.keep state,"keep").
Proof. intros Irrelevant. unfold Application.input_decision. rewrite Irrelevant. reflexivity. Qed.

(** A world refresh can follow ordinary command admission while the stream is
    disconnected. Only the separately correlated authentication receipt owns
    connection recovery. *)
Theorem ordinary_snapshot_preserves_connection namespace snapshot lagged state:
 let result:=Selvedge.Interaction.Session.Runtime.core namespace snapshot lagged Input.Snapshot state in
 Services.connection(SS.service_state(Authoring.result_state result))=
 Services.connection(SS.service_state state) /\ Authoring.result_effects result=[].
Proof. split;reflexivity. Qed.

Theorem stale_element_cannot_produce_a_product_input snapshot current environment generation raw incoming:
 natural_field "generation" raw=Some incoming -> incoming<>generation ->
 Application.element snapshot current environment generation raw=None.
Proof.
 intros Incoming Different. unfold Application.element. rewrite Incoming.
 apply N.eqb_neq in Different. simpl. rewrite Different. reflexivity.
Qed.

Theorem refused_submission_emits_no_command snapshot draft trigger state command reason:
 Authoring.current_command state draft=Some command ->
 EO.admission snapshot state(DraftOwner(Draft.owner draft))(Draft.revision draft)command=EM.Unavailable reason ->
 Authoring.result_effects(Authoring.issue_draft snapshot draft trigger state)=nil.
Proof.
 intros Command Refused. unfold Authoring.issue_draft.
 destruct(Authoring.submission_obstruction snapshot draft state)as [obstruction|];[reflexivity|].
 rewrite Command. unfold Authoring.canonical_ready. rewrite Refused. reflexivity.
Qed.

Theorem live_setting_selection_preserves_the_message_draft snapshot owner assignment state draft:
 Draft.find_draft owner(SS.drafts(SS.authoring_state state))=Some draft ->
 EO.assignment_available snapshot state assignment=EM.Available ->
 Parameters.live_configuration owner(EM.subject_declaration(Activity.assignment_subject assignment))=true ->
 SS.drafts(SS.authoring_state(Authoring.result_state(Authoring.apply_field snapshot owner assignment state)))=
 SS.drafts(SS.authoring_state state).
Proof.
 intros Existing Available Live. unfold Authoring.apply_field.
 rewrite Live. cbn [andb].
 destruct(SS.pending_editor owner state);[reflexivity|].
 unfold Authoring.ensure_draft. rewrite Existing,Available.
 repeat rewrite Live.
 destruct(Values.candidate_command snapshot(SS.now state)(SS.current_draft state owner)assignment)as [command|];simpl;auto.
 destruct(Authoring.canonical_ready snapshot state
  (EO.candidate_owner(Activity.assignment_subject assignment)
   (Schema.encode_value(EM.subject_kind(Activity.assignment_subject assignment))(Activity.assignment_value assignment)))
  (Draft.revision(SS.current_draft state owner))command);unfold Authoring.issue;destruct(SS.pending_command command state);reflexivity.
Qed.

Theorem a_pending_command_is_not_executed_twice command purpose state:
 SS.pending_command command state=true ->
 Authoring.result_effects(Authoring.issue command purpose state)=nil.
Proof. intro Pending. unfold Authoring.issue. rewrite Pending. reflexivity. Qed.

(** A rejected raw component event cannot trigger synchronization, IO or a new
    publication generation before its identity has been admitted. *)
Theorem rejected_interactive_input_is_idle request snapshot namespace language raw state :
 Selvedge.Interaction.Session.Runtime.native_language namespace snapshot state language=false ->
 Application.input_decision request snapshot namespace (Input.Interactive language)raw state=
 (Authoring.keep state,"keep").
Proof. intro Rejected; unfold Application.input_decision; rewrite Rejected; reflexivity. Qed.

Theorem repeated_native_selection_keeps_its_publication input current updated :
 Json.equal(Selvedge.Interaction.Session.Codec.encode_state current)(Selvedge.Interaction.Session.Codec.encode_state updated)=true ->
 input<>Input.Snapshot -> input<>Input.EnvironmentObserved ->
 Application.input_publication input current updated="keep".
Proof. intros Equal NoSnapshot NoEnvironment; unfold Application.input_publication; destruct input; try contradiction; now rewrite Equal. Qed.
