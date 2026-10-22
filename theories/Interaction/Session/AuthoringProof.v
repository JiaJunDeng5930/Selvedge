From Stdlib Require Import String List Bool NArith.
From Selvedge.Interaction Require Import Codec.
From Selvedge.Interaction Require Resource Services.
From Selvedge.Interaction.Session Require Draft State Authoring.
From Selvedge.Interaction.Submission Require Command.
Module SS:=Selvedge.Interaction.Session.State.

Theorem completed_directory_observation_retains_the_captured_request
 snapshot ticket raw state request workspace guidance:
 find(fun resource=>match resource with Resource.Loading actual _=>N.eqb ticket actual|_=>false end)
  (Services.preparations(SS.service_state state))=Some(Resource.Loading ticket request) ->
 Command.admit_directories raw=Some(workspace,guidance) ->
 Authoring.directories_completed snapshot ticket(inr raw)state=
 Authoring.keep(SS.with_services(Services.with_preparations
  (map(Resource.settle ticket(inr(Services.DirectoryObservation workspace guidance)))
   (Services.preparations(SS.service_state state)))(SS.service_state state))state).
Proof.
 intros Pending Admitted. unfold Authoring.directories_completed.
 rewrite Pending,Admitted. reflexivity.
Qed.

Theorem a_captured_submission_waits_for_its_worker_verdict
 snapshot ticket request observation state command:
 Command.observed_command(SS.now state)(Services.preparation_draft request)
  (Services.observed_workspace observation,Services.observed_guidance observation)=Some command ->
 Services.preparation_preference request=None ->
 let checked:=Authoring.ensure_request snapshot(Authoring.preparation_owner ticket command)
  (Draft.revision(Services.preparation_draft request))command state in
 Authoring.assessed_command snapshot(Authoring.preparation_owner ticket command)
  (Draft.revision(Services.preparation_draft request))command(Authoring.result_state checked)=None ->
 Authoring.continue_preparation snapshot ticket request observation state=checked.
Proof.
 intros Constructed NoPreference checked Waiting.
 unfold Authoring.continue_preparation. rewrite Constructed,NoPreference.
 change (Authoring.append checked
  (match Authoring.assessed_command snapshot(Authoring.preparation_owner ticket command)
   (Draft.revision(Services.preparation_draft request))command(Authoring.result_state checked)with
   |None=>Authoring.keep(Authoring.result_state checked)
   |Some(inl reason)=>Authoring.preparation_failed ticket request reason(Authoring.result_state checked)
   |Some(inr _)=>Authoring.issue_prepared ticket request command(Authoring.result_state checked)end)=checked).
 rewrite Waiting. unfold Authoring.append,Authoring.keep.
 destruct checked. simpl. now rewrite List.app_nil_r.
Qed.

Theorem an_admitted_captured_submission_executes_its_captured_command
 snapshot ticket request observation state command:
 Command.observed_command(SS.now state)(Services.preparation_draft request)
  (Services.observed_workspace observation,Services.observed_guidance observation)=Some command ->
 Services.preparation_preference request=None ->
 Authoring.ensure_request snapshot(Authoring.preparation_owner ticket command)
  (Draft.revision(Services.preparation_draft request))command state=Authoring.keep state ->
 Authoring.assessed_command snapshot(Authoring.preparation_owner ticket command)
  (Draft.revision(Services.preparation_draft request))command state=Some(inr tt) ->
 Authoring.continue_preparation snapshot ticket request observation state=
 Authoring.issue command(SS.DraftSubmission(Services.preparation_draft request)
  (Services.preparation_generation request)(Services.preparation_layer request)(Services.preparation_trigger request))
  (Authoring.preparation_finished ticket state).
Proof.
 intros Constructed NoPreference Checked Admitted.
 unfold Authoring.continue_preparation. rewrite Constructed,NoPreference,Checked.
 cbn [Authoring.result_state Authoring.keep]. rewrite Admitted.
 unfold Authoring.issue_prepared. rewrite NoPreference.
 unfold Authoring.append,Authoring.keep. simpl.
 destruct(Authoring.issue command(SS.DraftSubmission(Services.preparation_draft request)
  (Services.preparation_generation request)(Services.preparation_layer request)(Services.preparation_trigger request))
  (Authoring.preparation_finished ticket state)) as [updated effects [error|]];reflexivity.
Qed.

Theorem completion_of_an_older_revision_preserves_the_newer_editor
 snapshot captured navigation layer trigger outcome state:
 Authoring.draft_current captured state=false ->
 Authoring.result_state(Authoring.complete_draft snapshot captured navigation layer trigger outcome state)=state.
Proof.
 intro Older. unfold Authoring.complete_draft. rewrite Older.
 destruct(Authoring.completion_success outcome);[rewrite Bool.andb_false_r|];reflexivity.
Qed.
