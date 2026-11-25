From Stdlib Require Import NArith List Bool.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import State Inputs Notifications Delivery.
Import ListNotations.

(** A complete domain outcome is selected before journal finalization. The
    transport budget applies once; advancing the cursor and rendering a receipt
    cannot schedule another operation. *)
Record selected := Selected {
 selected_durable : bool;
 selected_admitted : bool;
 selected_source : option input;
 selected_decision : decision
}.
Definition choose (durable : bool) (source : option input) (outcome : bool * decision) :=
 Selected durable (fst outcome) source (snd outcome).
Definition finalize_world (before : world) (chosen : selected) : world :=
 let next := decision_world (selected_decision chosen) in
 if selected_durable chosen then with_sequence (N.succ (world_sequence before)) next else next.
Definition finalize (before : world) (chosen : selected) : world * json :=
 (finalize_world before chosen,
  Notifications.envelope (selected_durable chosen) (selected_admitted chosen)
    (selected_source chosen) before (selected_decision chosen)).

(** The recovery image is observed by the checkpoint codec at the runtime
    boundary. Only an issued obligation or a different recovery image needs
    a row. A scheduler wakeup can be delivered without advancing the cursor. *)
Definition needs_commit_effect (request : effect) :=
 match request with
 | ContinueScheduling => false
 | ObserveContext _ _ _ | RequestModel _ | RequestReasoning _ _ _
 | ExecuteTool _ _ _ _ _ _ _ | RequestApproval _ _ _ _ _
 | CheckTool _ _ _ _ _ | CheckResult _ _ _ _ _ _ _
 | ResetModelSession _ | CancelTask _ | CancelTicket _ _
 | CreateWorktree _ _ _ _ | ArchiveWorktree _ _ _ _ _
 | RequestFeature _ | CancelConnectionJob _ | MaintainContext _ => true
 end.
Definition needs_commit (same_image : world -> world -> bool) (before : world) (result : decision) :=
 existsb needs_commit_effect (decision_effects result) ||
 negb (same_image before (decision_world result)).
Definition select_journal (same_image : world -> world -> bool) (before : world) (chosen : selected) :=
 let result := selected_decision chosen in
 if needs_commit same_image before result
 then Selected true (selected_admitted chosen) (selected_source chosen) result
 else
   (* The frame budget includes the durability flag. The JSON spelling of
      false is wider than true, so only a formerly durable reply needs a
      second size decision when its flag changes. *)
   let transient := Decision before (decision_reply result) (decision_effects result) in
   if selected_durable chosen then choose false (selected_source chosen)
     (Delivery.deliver_with_status false transient before)
   else Selected false (selected_admitted chosen) (selected_source chosen) transient.
Definition journal_finalize same_image before chosen :=
 finalize before (select_journal same_image before chosen).

(** Consumers lift a property of the selected outcome once, rather than
    reopening each transaction's delivery and journal branches. *)
Theorem finalize_preserves : forall (P : world -> Prop) before chosen,
 (forall value sequence, P value -> P (with_sequence sequence value)) ->
 P (decision_world (selected_decision chosen)) -> P (fst (finalize before chosen)).
Proof.
 intros P before [durable admitted source result] Cursor Holds.
 destruct durable; cbn [finalize finalize_world selected_durable selected_decision fst]; auto.
Qed.
Theorem finalize_has_its_selected_receipt : forall before chosen,
 snd (finalize before chosen) =
 Notifications.envelope (selected_durable chosen) (selected_admitted chosen)
   (selected_source chosen) before (selected_decision chosen).
Proof. intros before []; reflexivity. Qed.
Theorem a_durable_packet_advances_the_cursor : forall before chosen,
 selected_durable chosen = true ->
 world_sequence (fst (finalize before chosen)) = N.succ (world_sequence before).
Proof. intros before [durable admitted source result] Durable; cbn in Durable; subst durable; reflexivity. Qed.

Theorem journal_selection_retains_exactly_the_recovery_obligations :
 forall same_image before chosen,
 let result := selected_decision chosen in
 selected_durable (select_journal same_image before chosen) = true <->
 (exists request, In request (decision_effects result) /\ needs_commit_effect request = true) \/
 same_image before (decision_world result) = false.
Proof.
 intros same_image before chosen. cbn zeta.
 assert (Durable : selected_durable (select_journal same_image before chosen) =
      needs_commit same_image before (selected_decision chosen)).
 { unfold select_journal. destruct (needs_commit same_image before (selected_decision chosen)); [reflexivity|].
   destruct (selected_durable chosen); reflexivity. }
 rewrite Durable. unfold needs_commit.
 rewrite Bool.orb_true_iff, existsb_exists, Bool.negb_true_iff. reflexivity.
Qed.

Theorem journal_transients_preserve_the_world_and_only_wake_the_scheduler :
 forall same_image before chosen,
 let selected := select_journal same_image before chosen in
 selected_durable selected = false ->
 finalize_world before selected = before /\
 forall request, In request (decision_effects (selected_decision selected)) ->
 request = ContinueScheduling.
Proof.
 intros same_image before chosen. cbn zeta.
 unfold select_journal, needs_commit.
 destruct (existsb needs_commit_effect (decision_effects (selected_decision chosen))) eqn:Effects;
   cbn [orb]; [discriminate|].
 destruct (same_image before (decision_world (selected_decision chosen))); [|discriminate].
 assert (Wakeups : forall request, In request (decision_effects (selected_decision chosen)) ->
   request = ContinueScheduling).
 { intros request Present.
   destruct request; try reflexivity; exfalso;
   assert (HasEffect : existsb needs_commit_effect (decision_effects (selected_decision chosen)) = true)
     by (apply existsb_exists; eexists; split; [exact Present|reflexivity]);
   congruence. }
 destruct (selected_durable chosen); cbn [negb].
 - unfold Delivery.deliver_with_status.
   destruct (Delivery.fits false _); cbn [choose selected_durable selected_decision fst snd finalize_world
     decision_world decision_effects reject]; intros _; split; try reflexivity; auto; contradiction.
 - intros _. split; [reflexivity|exact Wakeups].
Qed.

Theorem journal_material_changes_keep_the_original_decision :
 forall same_image before chosen,
 selected_durable (select_journal same_image before chosen) = true ->
 selected_decision (select_journal same_image before chosen) = selected_decision chosen.
Proof.
 intros same_image before chosen. unfold select_journal.
 destruct (needs_commit same_image before (selected_decision chosen)); [reflexivity|].
 destruct (selected_durable chosen); discriminate.
Qed.
