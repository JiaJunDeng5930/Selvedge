From Stdlib Require Import String List Bool NArith Lia.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Foundation Require Import Json JsonProofs Registry RegistryProofs Utf8.
From Selvedge.Kernel Require Import Domain State Codec Tasks FeatureRequestAdmission ChatgptArgumentsProofs.
From Selvedge.Features Require Import Domain BoardFacts Observation TitleRuntime Chatgpt WorkspaceBinding.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.
Module F := Selvedge.Features.Domain.

Lemma absent_find_has_no_member : forall (A : Type) (test : A -> bool) values,
 find test values = None -> existsb test values = false.
Proof.
 intros A test values; induction values as [|value rest IH]; [reflexivity|].
 cbn; destruct (test value); [discriminate|exact IH].
Qed.
Lemma registered_profile_from_membership : forall selected before,
 In selected (environment_profiles (world_environment before)) ->
 FeatureRequestAdmission.registered_profile selected before = true.
Proof.
 intros selected before Member. unfold FeatureRequestAdmission.registered_profile.
 apply existsb_exists; exists selected; split; [exact Member|apply equal_is_reflexive].
Qed.
Lemma selected_title_profile_is_registered_and_capable : forall task before selected,
 TitleRuntime.selected_profile task before = Some selected ->
 In selected (environment_profiles (world_environment before)) /\ TitleRuntime.capable selected = true.
Proof.
 intros task before selected Chosen. unfold TitleRuntime.selected_profile in Chosen.
 destruct (find _ (environment_profiles (world_environment before))) as [preferred|] eqn:Preferred.
 - inversion Chosen; subst preferred. apply find_some in Preferred as [Member Condition].
   unfold TitleRuntime.ordinary in Condition. repeat rewrite andb_true_iff in Condition. tauto.
 - apply find_some in Chosen as [Member Condition].
   apply andb_true_iff in Condition as [Key Capable]. tauto.
Qed.
Lemma title_scope_from_current_task : forall id task before selected,
 find_task id before = Some task ->
 TitleRuntime.entry id before = None ->
 TitleRuntime.accepts task = true ->
 Utf8.nonblank (TitleRuntime.first_request (task_history task)) = true ->
 TitleRuntime.selected_profile task before = Some selected ->
 FeatureRequestAdmission.title id selected
   (TitleRuntime.prompt (F.title_agent_prompt (F.feature_title_settings (world_features before)))
     (TitleRuntime.first_request (task_history task))) before = true.
Proof.
 intros id task before selected Found Absent Accepts Nonblank Selected.
 pose proof (selected_title_profile_is_registered_and_capable task before selected Selected) as [Member Capable].
 pose proof (registered_profile_from_membership selected before Member) as Registered.
 unfold TitleRuntime.entry in Absent; apply absent_find_has_no_member in Absent.
 assert (Live : negb (task_archived task) = true).
 { unfold task_archived,TitleRuntime.accepts in *; destruct (task_lifecycle task); exact Accepts. }
 unfold TitleRuntime.first_request in Nonblank.
 unfold TitleRuntime.prompt,TitleRuntime.first_request.
 unfold FeatureRequestAdmission.title. rewrite Found,Live,Absent,Registered.
 change (TitleRuntime.capable selected) with (negb (String.eqb (profile_provider selected) "echo")) in Capable.
 rewrite Capable,Nonblank,String.eqb_refl; reflexivity.
Qed.
Lemma retitle_scope_from_current_card : forall id current before selected now,
 registry_at id (F.board_cards (F.feature_board (world_features before))) = Some (Some current) ->
 BoardFacts.mutable current before = true ->
 In selected (environment_profiles (world_environment before)) ->
 TitleRuntime.ordinary selected = true -> (now <=? 4294967295) = true ->
 FeatureRequestAdmission.card id (BoardFacts.revised (F.card_contents current) now current) selected
   (Selvedge.Features.Titles.board_prompt
     (F.title_task_prompt (F.feature_title_settings (world_features before)))
     (F.draft_title (F.card_contents current)) (F.draft_description (F.card_contents current)) true)
   true before = true.
Proof.
 intros id current before selected now Found Mutable Member Ordinary Clock.
 assert (Existing : N.eqb id (N.of_nat (List.length (F.board_cards (F.feature_board (world_features before))))) = false).
 { apply N.eqb_neq. pose proof (registry_lookup_implies_position_bound _ _ _ _ Found). lia. }
 pose proof (registered_profile_from_membership selected before Member) as Registered.
 unfold FeatureRequestAdmission.card. rewrite Registered.
 change (FeatureRequestAdmission.ordinary_profile selected = true) in Ordinary.
 rewrite Ordinary.
 replace (F.card_updated (BoardFacts.revised (F.card_contents current) now current)) with now by reflexivity.
 replace (F.card_contents (BoardFacts.revised (F.card_contents current) now current))
   with (F.card_contents current) by reflexivity.
 rewrite Clock,String.eqb_refl,Existing,Found,Mutable,equal_is_reflexive; reflexivity.
Qed.
Lemma connection_scope_from_current_grant : forall connection project request arguments decoded granted target before,
 Chatgpt.bounded_text 128 request = true ->
 ChatgptArguments.admit_args arguments = Some decoded ->
 Chatgpt.authority connection project (Chatgpt.registry before) = Some granted ->
 Chatgpt.project project before = Some target -> workspace_primary (project_workspace target) <> None ->
 Chatgpt.retry connection request (Chatgpt.registry before) = None ->
 WorkspaceBinding.workspace_available (project_workspace target) before = true ->
 WorkspaceBinding.resource_ready (project_workspace target) (project_resource target) before = true ->
 ((N.of_nat (List.length (F.sharing_jobs (Chatgpt.registry before))) <? 128) &&
  (F.sharing_next (Chatgpt.registry before) <? ChatgptArguments.identity_maximum)) = true ->
 FeatureRequestAdmission.connection
   (F.ConnectionJob connection project request decoded (project_workspace target)
     (project_resource target) (F.connection_sandbox granted) F.JobRunning) before = true.
Proof.
 intros connection project request arguments decoded granted target before Bounded Arguments Authority Project Primary Retry Available Resource Capacity.
 pose proof (admitted_arguments_have_a_valid_canonical_wire arguments decoded Arguments) as Canonical.
 unfold Chatgpt.authority,Chatgpt.grant in Authority.
 destruct (find (fun grant=>N.eqb connection (F.connection_id grant)) (F.sharing_grants (Chatgpt.registry before)))
   as [registered|] eqn:Grant; [|discriminate].
 destruct (Chatgpt.member project (F.connection_projects registered)) eqn:Member; [|discriminate].
 inversion Authority; subst registered.
 unfold Chatgpt.project in Project.
 destruct (registry_at project (world_projects before)) as [current|] eqn:ProjectFound; [|discriminate].
 destruct (project_deleted current) eqn:Deleted; [discriminate|].
 inversion Project; subst current.
 unfold Chatgpt.retry in Retry; apply absent_find_has_no_member in Retry.
 assert (SameResource : Workspace.same_resource (project_resource target) (project_resource target)=true).
 { unfold Workspace.same_resource; destruct (project_resource target); [apply N.eqb_refl|reflexivity]. }
 unfold FeatureRequestAdmission.connection.
 cbn [F.job_connection F.job_project F.job_request F.job_workspace F.job_resource F.job_sandbox F.job_arguments_json F.job_arguments].
 fold (Chatgpt.registry before). rewrite Grant,ProjectFound,Deleted.
 change (existsb (N.eqb project) (F.connection_projects granted) = true) in Member.
 unfold F.job_arguments_json; cbn [F.job_arguments].
 rewrite Member,!equal_is_reflexive,SameResource,Available,Resource,Canonical,Retry.
 destruct (workspace_primary (project_workspace target)); [|contradiction].
 unfold Chatgpt.bounded_text in Bounded.
 apply andb_true_iff in Bounded as [Text Length].
 apply andb_true_iff in Text as [Nonempty Encoding].
 apply andb_true_iff in Capacity as [Room Next].
 rewrite Nonempty,Encoding,Length,Room,Next; reflexivity.
Qed.
