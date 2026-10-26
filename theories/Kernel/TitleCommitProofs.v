From Stdlib Require Import String List Bool NArith Lia.
From Selvedge.Foundation Require Import Json Utf8 ArgumentDeclaration.
From Selvedge.Kernel Require Import Numbers Domain Codec State Tasks Inputs TaskScope TicketedRequest
 TitleCommit FeatureFrameProofs WorldInvariant WorldInvariantProofs DeferredCommit TitleCommitPreservation TicketBoundMonotonicityProofs.
From Selvedge.Features Require Import Domain State Titles TitleRuntime TitleProofs FeatureScopeProofs.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Module F := Selvedge.Features.Domain.
Module S := TicketedRequest.Scoped.

Theorem a_title_plan_resolves_the_actual_eligible_task : forall before (request : TitleCommit.plan before),
 exists selected,
 TitleRuntime.entry (TaskScope.owner (TitleCommit.reference request)) before = None /\
 TitleRuntime.accepts (TaskScope.selected (TitleCommit.reference request)) = true /\
 Utf8.nonblank (TitleRuntime.first_request (task_history (TaskScope.selected (TitleCommit.reference request)))) = true /\
 TitleRuntime.selected_profile (TaskScope.selected (TitleCommit.reference request)) before = Some selected.
Proof.
 intros before [reference Ready]. cbn in *.
 unfold TitleCommit.ready, TitleCommit.proposal, TitleRuntime.start in Ready.
 cbn [decision_world decision_effects accept] in Ready.
 destruct (TitleRuntime.entry (TaskScope.owner reference) before) as [entry|] eqn:Absent; [discriminate|].
 destruct (negb (TitleRuntime.accepts (TaskScope.selected reference) &&
   Utf8.nonblank (TitleRuntime.first_request (task_history (TaskScope.selected reference))))) eqn:Eligible; [discriminate|].
 destruct (TitleRuntime.selected_profile (TaskScope.selected reference) before) as [selected|] eqn:Chosen; [|discriminate].
 apply negb_false_iff in Eligible. apply andb_true_iff in Eligible as [Accepts Nonblank].
 exists selected; repeat split; assumption.
Qed.

Local Lemma string_append_length : forall first second,
 String.length (first ++ second) = (String.length first + String.length second)%nat.
Proof. induction first; cbn; intros; congruence. Qed.

Lemma bounded_title_chunks_obey_the_byte_budget : forall parts bytes,
 (N.of_nat (String.length (Titles.bounded parts bytes)) <= bytes)%N.
Proof.
 induction parts as [|[scalar chunk] rest IH]; intros bytes; cbn [Titles.bounded String.length]; [lia|].
 destruct (N.leb (N.of_nat (String.length chunk)) bytes) eqn:Fits; [|cbn [String.length]; lia].
 rewrite string_append_length, Nat2N.inj_add. specialize (IH (bytes - N.of_nat (String.length chunk))%N).
 apply N.leb_le in Fits; lia.
Qed.

Lemma a_title_prompt_obeys_the_declared_byte_bound : forall instruction request,
 Titles.valid_instructions instruction = true ->
 (N.of_nat (String.length (Titles.prompt_with instruction request)) <=
  Titles.maximum_instruction_bytes + N.of_nat (String.length Titles.title_format) +
  (Titles.prompt_bytes - N.of_nat (String.length (Titles.instructions ++ Titles.title_format))))%N.
Proof.
 intros instruction request Valid.
 unfold Titles.valid_instructions, Titles.instruction_declaration,
  ArgumentDeclaration.bounded_text, ArgumentDeclaration.check in Valid.
 cbn in Valid. unfold ArgumentDeclaration.check_text in Valid.
 destruct (Utf8.scalar_count instruction) as [count|] eqn:Count; [|discriminate].
 cbn in Valid. repeat rewrite andb_true_iff in Valid.
 assert (Bytes : (N.of_nat (String.length instruction) <=? Titles.maximum_instruction_bytes)%N = true) by tauto.
 apply N.leb_le in Bytes.
 unfold Titles.prompt_with. rewrite !string_append_length, !Nat2N.inj_add.
 destruct (Utf8.chunks request) as [chunks|] eqn:Chunks.
 - pose proof (bounded_title_chunks_obey_the_byte_budget
     (Titles.trim_both Utf8.whitespace chunks)
     (Titles.prompt_bytes - N.of_nat (String.length (Titles.instructions ++ Titles.title_format)))) as Bound.
   rewrite string_append_length, Nat2N.inj_add in Bound. lia.
 - cbn [String.length]. lia.
Qed.

Definition an_automatic_title_selects_a_capable_configured_profile :=
 FeatureScopeProofs.selected_title_profile_is_registered_and_capable.

Lemma an_automatic_title_uses_an_admitted_profile : forall task before selected,
 well_formed before -> TitleRuntime.selected_profile task before = Some selected -> profile_valid selected = true.
Proof.
 intros task before selected Valid Chosen.
 pose proof (an_automatic_title_selects_a_capable_configured_profile task before selected Chosen) as [Member Capable].
 pose proof (environment_requirement before Valid) as Environment.
 unfold environment_valid in Environment. repeat rewrite andb_true_iff in Environment.
 assert (Profiles : profiles_valid (environment_profiles (world_environment before)) = true) by tauto.
 unfold profiles_valid in Profiles. apply andb_true_iff in Profiles as [Profiles Unique].
 now apply forallb_forall with (x:=selected) in Profiles.
Qed.

Definition title_prompt (owner : N) (current : task) before :=
 TitleRuntime.prompt (F.title_agent_prompt (F.feature_title_settings (world_features before)))
   (TitleRuntime.first_request (task_history current)).
Definition title_decision owner (current : task) selected before :=
 let prompt := title_prompt owner current before in
 Decision (TitleRuntime.store owner (F.TitlePending (world_next_ticket before) selected prompt)
   (with_ticket (N.succ (world_next_ticket before)) before))
   (success JNull) [SuggestTitle owner (world_next_ticket before) selected prompt;ContinueScheduling].

Theorem every_title_plan_constructs_its_exact_request : forall before (request : TitleCommit.plan before) selected,
 TitleRuntime.entry (TaskScope.owner (TitleCommit.reference request)) before = None ->
 TitleRuntime.accepts (TaskScope.selected (TitleCommit.reference request)) = true ->
 Utf8.nonblank (TitleRuntime.first_request (task_history (TaskScope.selected (TitleCommit.reference request)))) = true ->
 TitleRuntime.selected_profile (TaskScope.selected (TitleCommit.reference request)) before = Some selected ->
 TitleCommit.candidate request = title_decision (TaskScope.owner (TitleCommit.reference request))
   (TaskScope.selected (TitleCommit.reference request)) selected before.
Proof.
 intros before request selected Absent Accepts Nonblank Chosen.
 unfold TitleCommit.candidate, TitleCommit.proposal.
 rewrite TitleProofs.title_start_with_observed_owner with (selected:=selected).
 - reflexivity.
 - exact (TaskScope.observed (TitleCommit.reference request)).
 - exact Absent.
 - exact Accepts.
 - exact Nonblank.
 - exact Chosen.
Qed.

Theorem every_eligible_title_request_preserves_all_world_requirements :
 forall owner current selected before,
 well_formed before -> find_task owner before = Some current -> TitleRuntime.entry owner before = None ->
 TitleRuntime.selected_profile current before = Some selected ->
 well_formed (decision_world (title_decision owner current selected before)).
Proof.
 intros owner current selected before Valid Owned Absent Chosen.
 pose proof (well_formed_feature_requirements before Valid) as Features.
 assert (Titles : titles_valid before = true).
 { unfold features_valid in Features; repeat rewrite andb_true_iff in Features; tauto. }
 assert (Supply : tickets_valid before = true) by exact (tickets_requirement before Valid).
 assert (Prompt : Titles.valid_instructions
   (F.title_agent_prompt (F.feature_title_settings (world_features before))) = true).
 { unfold titles_valid in Titles; repeat rewrite andb_true_iff in Titles; tauto. }
 cbn [title_decision decision_world].
 apply storing_a_title_preserves_every_other_world_requirement.
 - apply well_formed_with_ticket; [exact Valid|apply N.le_succ_diag_r].
 - apply storing_one_eligible_title_preserves_title_requirements with (task:=current).
   + apply titles_valid_with_ticket; [apply N.le_succ_diag_r|exact Titles].
   + exact Absent.
   + exact Owned.
   + apply N.lt_succ_diag_r.
   + eapply an_automatic_title_uses_an_admitted_profile; eauto.
   + now apply an_automatic_title_selects_a_capable_configured_profile in Chosen as [_ Chosen].
   + apply a_title_prompt_obeys_the_declared_byte_bound; exact Prompt.
 - apply a_fresh_title_preserves_global_ticket_ownership; assumption.
Qed.
