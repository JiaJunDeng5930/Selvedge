From Stdlib Require Import String List Bool Arith NArith Lia.
From Selvedge.Browser Require Import Native.

Theorem composing_never_submits : forall key ime shift alt modified multiline enabled pending,
  submit (normalize_key (KeyObservation key true ime shift alt modified) multiline enabled pending) = false.
Proof. intros; unfold normalize_key; simpl; destruct (String.eqb key "Enter"); reflexivity. Qed.

Theorem ime_never_submits : forall key composing shift alt modified multiline enabled pending,
  submit (normalize_key (KeyObservation key composing true shift alt modified) multiline enabled pending) = false.
Proof. intros; unfold normalize_key; simpl; destruct (String.eqb key "Enter"), composing; reflexivity. Qed.

Theorem pending_never_resubmits : forall key multiline,
  submit (normalize_key key multiline true true) = false.
Proof. intros; unfold normalize_key; simpl; rewrite Bool.andb_false_r; reflexivity. Qed.

Theorem enabled_multiline_enter_submits : forall modified,
  submit (normalize_key (KeyObservation "Enter"%string false false false false modified)
    true true false) = true.
Proof. reflexivity. Qed.

Theorem enabled_modified_enter_submits : forall multiline,
  submit (normalize_key (KeyObservation "Enter"%string false false false false true)
    multiline true false) = true.
Proof. intros []; reflexivity. Qed.

Theorem simultaneous_fits : forall viewport requirements,
  allocate viewport requirements = Simultaneous ->
  navigation_minimum requirements + content_minimum requirements +
    rail_width requirements + gap_width requirements <= viewport.
Proof.
  intros viewport requirements; unfold allocate, simultaneous_minimum.
  destruct (Nat.leb _ _) eqn:fits; [apply Nat.leb_le in fits; auto | discriminate].
Qed.

Theorem stale_publication_does_not_clear_lag : forall generation state,
  generation <> semantic_generation state -> accept_publication generation state = state.
Proof.
  intros generation state different; unfold accept_publication.
  assert (N.eqb generation (semantic_generation state) = false) by (apply N.eqb_neq; assumption).
  rewrite H; reflexivity.
Qed.

Theorem accepted_publication_is_current : forall state,
  document_generation state = semantic_generation state ->
  fresh (accept_publication (semantic_generation state) state) = true.
Proof.
  intros state current; unfold fresh, accept_publication; rewrite current, N.eqb_refl; simpl; apply N.eqb_refl.
Qed.

Theorem semantic_change_requires_publication : forall state,
  fresh state = true -> fresh (advance_semantics state) = false.
Proof.
  intros state ready; unfold fresh in *; apply N.eqb_eq in ready.
  unfold advance_semantics; cbn -[N.eqb]; apply N.eqb_neq; lia.
Qed.

Theorem user_scroll_never_aligns_latest : forall state,
  snd (read_step BeginScroll state) = nil.
Proof. reflexivity. Qed.

Theorem layout_preserves_reading_intent : forall state,
  fst (read_step LayoutChanged state) = state.
Proof. reflexivity. Qed.

Theorem following_latest_requests_alignment : forall state,
  snd (read_step Follow state) = cons AlignLatest nil.
Proof. reflexivity. Qed.

Theorem reading_history_requests_its_saved_anchor : forall value,
  snd (read_step LayoutChanged (ReadingState ReadHistory (Some value))) =
    cons (PreserveAnchor value) nil.
Proof. reflexivity. Qed.

Theorem editing_does_not_change_reading_intent : forall key state,
  fst (read_step (ReadingKey key true) state) = state.
Proof. intros; cbn [read_step]; rewrite Bool.andb_false_r; reflexivity. Qed.

Theorem admitted_event_is_from_current_document : forall generation state,
  admit_generation generation state = true ->
  generation = semantic_generation state /\
    document_generation state = semantic_generation state.
Proof.
  intros generation state admitted; unfold admit_generation, fresh in admitted.
  apply Bool.andb_true_iff in admitted as [published current].
  apply N.eqb_eq in published; apply N.eqb_eq in current; auto.
Qed.

Theorem admitted_same_namespace_snapshot_does_not_roll_back : forall origin expected incoming cursor state,
  incoming = namespace state -> admit_snapshot origin expected incoming cursor state = true ->
  (sequence state <= cursor)%N.
Proof.
  intros origin expected incoming cursor state same admitted.
  unfold admit_snapshot in admitted; rewrite same, String.eqb_refl in admitted.
  apply Bool.andb_true_iff in admitted as [_ ordered]; apply N.leb_le; exact ordered.
Qed.


Theorem resolved_target_matches_request : forall requested view candidates key,
  resolve_target requested view candidates = Some key ->
  exists candidate, In candidate candidates /\ target_key candidate = key /\
    (target_key candidate = requested \/ In requested (target_aliases candidate)).
Proof.
  intros requested view candidates key resolved.
  assert (safe_alias : forall candidate,
    In candidate (filter (fun candidate => existsb (String.eqb requested) (target_aliases candidate)) candidates) ->
    In candidate candidates /\ In requested (target_aliases candidate)).
  { intros candidate inside; apply filter_In in inside as [present matched].
    apply existsb_exists in matched as [alias [member equal]].
    apply String.eqb_eq in equal; subst alias; auto. }
  unfold resolve_target in resolved.
  destruct (find _ candidates) as [candidate|] eqn:direct.
  - inversion resolved; subst; apply find_some in direct as [present correct].
    apply String.eqb_eq in correct; exists candidate; repeat split; auto.
  - destruct (find _ (filter _ candidates)) as [candidate|] eqn:preferred.
    + inversion resolved; subst; apply find_some in preferred as [inside _].
      apply safe_alias in inside as [present alias]; exists candidate; auto.
    + destruct (filter _ candidates) as [|candidate rest] eqn:aliases; [discriminate|].
      inversion resolved; subst.
      destruct (safe_alias candidate (or_introl eq_refl)) as [present alias].
      exists candidate; auto.
Qed.

Theorem exact_physical_targets_take_precedence : forall requested view candidates candidate,
  In candidate candidates -> target_key candidate = requested ->
  resolve_target requested view candidates = Some requested.
Proof.
  intros requested view candidates candidate present same; unfold resolve_target.
  destruct (find _ candidates) as [selected|] eqn:direct.
  - apply find_some in direct as [_ correct]; apply String.eqb_eq in correct; now rewrite <- correct.
  - apply find_none with (x := candidate) in direct; [|exact present].
    rewrite same, String.eqb_refl in direct; discriminate.
Qed.

Theorem a_visible_logical_target_is_reachable : forall requested view candidates candidate,
  In candidate candidates -> In requested (target_aliases candidate) ->
  exists key, resolve_target requested view candidates = Some key.
Proof.
  intros requested view candidates candidate present same; unfold resolve_target.
  destruct (find _ candidates); [eauto|].
  destruct (find _ (filter _ candidates)); [eauto|].
  assert (alias : In candidate (filter (fun candidate => existsb (String.eqb requested) (target_aliases candidate)) candidates)).
  { apply filter_In; split; [exact present|apply existsb_exists; exists requested; split; [exact same|apply String.eqb_refl]]. }
  destruct (filter (fun candidate => existsb (String.eqb requested) (target_aliases candidate)) candidates)
    as [|selected rest]; [contradiction|].
  exists (target_key selected); reflexivity.
Qed.


Theorem preferred_view_targets_stay_in_their_view : forall requested view candidates candidate,
  find (fun observed => String.eqb requested (target_key observed)) candidates = None ->
  In candidate candidates -> In requested (target_aliases candidate) -> target_view candidate = view ->
  exists selected, In selected candidates /\ target_view selected = view /\
    resolve_target requested view candidates = Some (target_key selected).
Proof.
  intros requested view candidates candidate absent present alias same.
  unfold resolve_target; rewrite absent.
  assert (admitted : In candidate (filter (fun observed => existsb (String.eqb requested) (target_aliases observed)) candidates)).
  { apply filter_In; split; [exact present|].
    apply existsb_exists; exists requested; split; [exact alias|apply String.eqb_refl]. }
  destruct (find _ (filter _ candidates)) as [selected|] eqn:preferred.
  - apply find_some in preferred as [inside matched].
    apply filter_In in inside as [inside _]; apply String.eqb_eq in matched.
    exists selected; repeat split; auto.
  - apply find_none with (x := candidate) in preferred; [|exact admitted].
    rewrite same, String.eqb_refl in preferred; discriminate.
Qed.

Theorem restored_focus_uses_an_observed_target : forall requested fallback view candidates key,
  resolve_focus_target requested fallback view candidates = Some key ->
  exists candidate, In candidate candidates /\ target_key candidate = key /\
    ((target_key candidate = requested \/ In requested (target_aliases candidate)) \/
     (target_key candidate = fallback \/ In fallback (target_aliases candidate))).
Proof.
  intros requested fallback view candidates key resolved.
  unfold resolve_focus_target in resolved.
  destruct (resolve_target requested view candidates) as [original|] eqn:primary.
  - inversion resolved; subst original.
    apply resolved_target_matches_request in primary as [candidate [present [same matched]]].
    exists candidate; split; [exact present|]; split; [exact same|]; left; exact matched.
  - apply resolved_target_matches_request in resolved as [candidate [present [same matched]]].
    exists candidate; split; [exact present|]; split; [exact same|]; right; exact matched.
Qed.

Theorem restored_focus_keeps_a_present_target : forall requested fallback view candidates candidate,
  In candidate candidates -> target_key candidate = requested ->
  resolve_focus_target requested fallback view candidates = Some requested.
Proof.
  intros requested fallback view candidates candidate present same.
  unfold resolve_focus_target.
  rewrite (exact_physical_targets_take_precedence requested view candidates candidate present same).
  reflexivity.
Qed.

Theorem restored_focus_reaches_a_present_fallback : forall requested fallback view candidates candidate,
  resolve_target requested view candidates = None ->
  In candidate candidates -> target_key candidate = fallback ->
  resolve_focus_target requested fallback view candidates = Some fallback.
Proof.
  intros requested fallback view candidates candidate missing present same.
  unfold resolve_focus_target; rewrite missing.
  exact (exact_physical_targets_take_precedence fallback view candidates candidate present same).
Qed.
