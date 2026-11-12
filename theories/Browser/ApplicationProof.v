From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Programming Require Import Schema.
From Selvedge.Interaction Require Import Codec CommandAssessment.
From Selvedge.Browser Require Import Application.
From Selvedge.Interaction.Submission Require Draft.
From Selvedge.Browser.Session Require State Authoring.
From Selvedge.Interaction.Experience Require Activity Model Observation.
From Selvedge.Interaction.Submission Require Parameters.
From Selvedge.Browser Require Layout.
From Selvedge.Browser.Session Require Import EditorContext.
Import ListNotations.
Open Scope string_scope.
Module EO:=Selvedge.Interaction.Experience.Observation.
Module EM:=Selvedge.Interaction.Experience.Model.
Module SS:=Selvedge.Browser.Session.State.

(** A parser callback without a current document owner cannot drive either
    product preparation or a new publication generation. *)
Theorem irrelevant_document_observation_is_idle request context namespace source raw:
 let state:=Application.prepared_state context in
 Documents.admit_observation
   (Selvedge.Browser.Session.Runtime.context namespace (Application.prepared_world context) state)
   source(SS.document_retention state)=Documents.IrrelevantObservation ->
 Application.input_decision request context namespace (Input.CodeObserved source)raw=
 ((Authoring.keep state,"keep",context),Some false).
Proof. cbn zeta. intros Irrelevant. unfold Application.input_decision. rewrite Irrelevant. reflexivity. Qed.

(** A world refresh can follow ordinary command admission while the stream is
    disconnected. Only the separately correlated authentication receipt owns
    connection recovery. *)
Theorem ordinary_snapshot_preserves_connection namespace snapshot lagged state:
 let result:=Selvedge.Browser.Session.Runtime.core namespace snapshot lagged Input.Snapshot state in
 Services.connection(SS.service_state(Authoring.result_state result))=
 Services.connection(SS.service_state state) /\ Authoring.result_effects result=[].
Proof. split;reflexivity. Qed.

Theorem stale_element_cannot_produce_a_product_input actual generation raw incoming:
 natural_field "generation" raw=Some incoming -> incoming<>generation ->
 Application.element actual generation raw=None.
Proof.
 intros Incoming Different. unfold Application.element, Application.resolve_native_element. rewrite Incoming.
 apply N.eqb_neq in Different. simpl. rewrite Different. reflexivity.
Qed.

Theorem refused_submission_emits_no_command snapshot draft trigger (state:SS.state) command reason:
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
Theorem rejected_interactive_input_is_idle request context namespace language raw :
 let state:=Application.prepared_state context in
 Selvedge.Browser.Session.Runtime.native_language namespace (Application.prepared_world context) state language=false ->
 Application.input_decision request context namespace (Input.Interactive language)raw=
 ((Authoring.keep state,"keep",context),None).
Proof. cbn zeta. intro Rejected; unfold Application.input_decision; rewrite Rejected; reflexivity. Qed.

Theorem repeated_native_selection_keeps_its_publication input current updated :
 Json.equal current updated=true ->
 input<>Input.Snapshot -> input<>Input.EnvironmentObserved ->
 Application.input_publication input current updated="keep".
Proof. intros Equal NoSnapshot NoEnvironment; unfold Application.input_publication; destruct input; try contradiction; now rewrite Equal. Qed.

(** Retaining the admitted state changes neither the new scene nor the
    request's admission of the new world and environment. *)
Theorem rebasing_the_same_admitted_state_keeps_the_prepared_scene request context :
 Application.state request = Some(Application.prepared_state context) ->
 option_map Application.prepared_scene (Application.rebase request context) =
 option_map Application.prepared_scene (Application.prepare request).
Proof.
 intro Same. unfold Application.rebase, Application.prepare.
 destruct (field "world" request); cbn [bind]; [rewrite Same|]; reflexivity.
Qed.

Theorem rebasing_a_canonical_prepared_state_agrees_with_prepare request context :
 Application.state request = Some(Application.prepared_state context) ->
 Application.prepared_encoding context = Application.SC.encode_state(Application.prepared_state context) ->
 Application.rebase request context = Application.prepare request.
Proof.
 intros Same Canonical. unfold Application.rebase, Application.prepare.
 destruct (field "world" request); cbn [bind]; [rewrite Same, Canonical|]; reflexivity.
Qed.
