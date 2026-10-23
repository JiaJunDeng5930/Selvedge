From Stdlib Require Import String List Bool NArith.
From Selvedge.Interaction Require Import Codec.
From Selvedge.Interaction Require Resource Services.
From Selvedge.Interaction.Session Require Draft State Authoring Observation.
From Selvedge.Interaction.Submission Require Command.
Module SS:=Selvedge.Interaction.Session.State.

Theorem unavailable_context_rejects_directory_edits snapshot owner change state configuration reason:
 Selvedge.Interaction.Submission.Parameters.editable owner
   Selvedge.Interaction.Submission.Fields.WorkspaceDirectories=true ->
 change<>Selvedge.Interaction.Input.InheritWorkspace ->
 Observation.draft_context(SS.current_draft state owner)=Some configuration ->
 Observation.context_preview snapshot configuration=
   Selvedge.Interaction.Context.ContextUnavailable reason ->
 Authoring.change_workspace snapshot owner change state=Authoring.fail state reason.
Proof.
 intros Editable Edit Configuration Preview.
 unfold Authoring.change_workspace. rewrite Editable.
 destruct change;try contradiction;
 unfold Observation.workspace_for_edit;rewrite Configuration,Preview;reflexivity.
Qed.

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

Theorem current_negative_git_observation_releases_local_worktree_choice
 snapshot ticket owner path state draft message profile reasoning configuration work :
 Services.workspace_git(SS.service_state state)=Resource.Loading ticket(owner,path) ->
 Draft.find_draft owner(SS.drafts(SS.authoring_state state))=Some draft ->
 bind(Observation.workspace_for snapshot draft)
  Selvedge.Kernel.Domain.workspace_primary=Some path ->
 Draft.contents draft=Draft.NewTaskBody message profile reasoning configuration
  (Draft.ManagedWorkspace Selvedge.Kernel.WorkspaceBackend.Local)work ->
 Authoring.service_step snapshot(Services.WorkspaceGitCompleted ticket(inr false))state=
 let settled:=SS.with_services(Services.with_workspace_git
  (Resource.Loaded ticket(owner,path)false)(SS.service_state state))state in
 Authoring.keep(SS.save_draft(Draft.with_body
  (Draft.NewTaskBody message profile reasoning configuration Draft.CurrentWorkspace work)draft)settled).
Proof.
 intros Loading Current Primary Body.
 unfold Authoring.service_step,Authoring.admitted_upload.
 cbn[Services.service_step]. rewrite Loading.
 cbn[Resource.settle]. rewrite N.eqb_refl.
 cbn[Services.keep Services.service_state Services.attached Services.service_effects].
 unfold Authoring.workspace_git_completed. rewrite Loading,N.eqb_refl.
 unfold Authoring.unavailable_local_workspace,SS.with_services.
 cbv [RecordSet.set]. cbn. rewrite Current,Primary,Body,String.eqb_refl. reflexivity.
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
 destruct checked. simpl. rewrite List.app_nil_r, Bool.orb_false_r. reflexivity.
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
