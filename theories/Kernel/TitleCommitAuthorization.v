From Stdlib Require Import String List Bool NArith Lia.
From Selvedge.Foundation Require Import Json.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Kernel Require Import Numbers Domain State Inputs WorldInvariant WorldInvariantProofs
 CommitAdmission AfterHookAuthorizationProofs FeatureFrameProofs FeatureAuthorityProofs TitleCommitProofs TitleCommit DeferredCommitProofs Delivery Notifications TaskScope.
From Selvedge.Features Require Import Domain State TitleRuntime TitleProofs.
Import ListNotations.
Module F := Selvedge.Features.Domain.
Module A := CommitAdmission.

Lemma adding_a_different_title_keeps_existing_generation_authority : forall entries todo owner status,
 (forall entry, In entry todo -> F.title_task entry <> owner) ->
 A.retained_titles todo (F.TitleEntry owner status :: entries) = A.retained_titles todo entries.
Proof.
 intros entries todo; induction todo as [|entry rest IH]; intros owner status Different; [reflexivity|].
 unfold A.retained_titles,KeyedList.retains in IH.
 cbn [A.retained_titles KeyedList.retains forallb]. unfold A.title_entry_at at 1. cbn [F.title_task find].
 assert (NotOwner : N.eqb (F.title_task entry) owner = false).
 { apply N.eqb_neq. apply Different; now left. }
 rewrite NotOwner. rewrite IH; [reflexivity|]. intros; apply Different; now right.
Qed.

Lemma adding_a_fresh_title_keeps_every_feature_authority : forall owner status before,
 features_valid before = true -> TitleRuntime.entry owner before = None ->
 A.features_evolution (world_features before)
   (world_features (TitleRuntime.store owner status before)) = true.
Proof.
 intros owner status before Valid Absent.
 pose proof (well_formed_features_admit_their_unchanged_configuration before Valid) as Self.
 assert (Different : forall entry, In entry (F.feature_titles (world_features before)) -> F.title_task entry <> owner).
 { intros entry Member Same. unfold TitleRuntime.entry in Absent.
   pose proof (find_none _ _ Absent entry Member) as Missing. cbn in Missing.
   rewrite Same, N.eqb_refl in Missing. discriminate. }
 assert (Retained : A.retained_titles (F.feature_titles (world_features before))
   (F.feature_titles (world_features (TitleRuntime.store owner status before))) =
   A.retained_titles (F.feature_titles (world_features before)) (F.feature_titles (world_features before))).
 { unfold TitleRuntime.store. cbn [with_features Selvedge.Features.State.with_titles set].
   rewrite (TitleCommitPreservation.an_absent_title_has_no_previous_registry_entry owner before Absent).
   change (A.retained_titles (F.feature_titles (world_features before))
     (F.TitleEntry owner status :: F.feature_titles (world_features before)) =
     A.retained_titles (F.feature_titles (world_features before)) (F.feature_titles (world_features before))).
   now apply adding_a_different_title_keeps_existing_generation_authority. }
 unfold A.features_evolution, A.titles_evolution in Self |- *.
 rewrite Retained. exact Self.
Qed.

Theorem every_eligible_title_request_has_complete_commit_authority :
 forall source raw owner current selected before,
 well_formed before -> find_task owner before = Some current -> TitleRuntime.entry owner before = None ->
 TitleRuntime.selected_profile current before = Some selected ->
 A.transition_authorized true source raw before (title_decision owner current selected before) = true.
Proof.
 intros source raw owner current selected before Valid Owned Absent Chosen.
 pose proof (well_formed_feature_requirements before Valid) as Features.
 assert (Evolution : A.features_evolution (world_features before)
   (world_features (decision_world (title_decision owner current selected before))) = true).
 { change (A.features_evolution (world_features before)
     (world_features (TitleRuntime.store owner
       (F.TitlePending (world_next_ticket before) selected (title_prompt owner current before)) before)) = true).
   apply adding_a_fresh_title_keeps_every_feature_authority; assumption. }
 unfold A.transition_authorized. apply andb_true_iff; split.
 - apply andb_true_iff; split.
   + unfold A.world_evolution. repeat rewrite andb_true_iff. repeat split.
     * unfold A.retained_tasks. apply unchanged_tasks_keep_authority_across_other_features.
     * change ((world_next_ticket before <=? N.succ (world_next_ticket before))%N = true).
       apply N.leb_le, N.le_succ_diag_r.
     * apply N.leb_refl.
     * exact Evolution.
   + change (A.effect_tickets_fresh (world_next_ticket before) (N.succ (world_next_ticket before))
       [SuggestTitle owner (world_next_ticket before) selected (title_prompt owner current before);ContinueScheduling] = true).
     unfold A.effect_tickets_fresh, A.unique_effect_tickets, A.has_effect_ticket, A.effect_ticket.
     cbn [forallb existsb]. rewrite !N.leb_refl.
     assert (Fresh : (world_next_ticket before <? N.succ (world_next_ticket before))%N = true)
       by (apply N.ltb_lt; apply N.lt_succ_diag_r).
     now rewrite Fresh.
 - change (A.title_effect_valid owner (world_next_ticket before) selected (title_prompt owner current before)
     (TitleRuntime.store owner (F.TitlePending (world_next_ticket before) selected (title_prompt owner current before))
       (with_ticket (N.succ (world_next_ticket before)) before)) && true = true).
   rewrite andb_true_r.
   unfold A.title_effect_valid. rewrite TitleProofs.stored_title_is_observed.
   change (match find_task owner before with
   | Some task => (world_next_ticket before =? world_next_ticket before)%N &&
     A.same_profile selected selected &&
     (match TitleRuntime.selected_profile task before with Some actual => A.same_profile selected actual | None => false end) &&
     String.eqb (title_prompt owner current before) (title_prompt owner current before) &&
     String.eqb (title_prompt owner current before) (title_prompt owner task before)
   | None => false end = true).
   rewrite Owned, Chosen, N.eqb_refl, the_same_profile_has_the_same_configuration, !String.eqb_refl. reflexivity.
Qed.

Theorem every_title_plan_with_its_actual_budget_commits : forall before (request : TitleCommit.plan before) raw,
 world_valid before = true -> Delivery.fits true (TitleCommit.candidate request) = true ->
 TitleCommit.packet request raw =
 (with_sequence (N.succ (world_sequence before)) (decision_world (TitleCommit.candidate request)),
  Notifications.envelope true true (Some Continue) before (TitleCommit.candidate request)).
Proof.
 intros before request raw World Budget.
 destruct (a_title_plan_resolves_the_actual_eligible_task before request)
   as [selected [Absent [Accepts [Nonblank Chosen]]]].
 pose proof (every_title_plan_constructs_its_exact_request before request selected Absent Accepts Nonblank Chosen) as Constructed.
 unfold TitleCommit.packet. apply DeferredCommitProofs.a_constructed_candidate_with_its_actual_budget_is_committed.
 - rewrite Constructed. reflexivity.
 - rewrite Constructed. apply well_formed_worlds_pass_the_checker.
   eapply every_eligible_title_request_preserves_all_world_requirements.
   + now apply the_world_checker_establishes_all_requirements.
   + exact (TaskScope.observed (TitleCommit.reference request)).
   + exact Absent.
   + exact Chosen.
 - rewrite Constructed. eapply every_eligible_title_request_has_complete_commit_authority.
   + now apply the_world_checker_establishes_all_requirements.
   + exact (TaskScope.observed (TitleCommit.reference request)).
   + exact Absent.
   + exact Chosen.
 - exact Budget.
Qed.
