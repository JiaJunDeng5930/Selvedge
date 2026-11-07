From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import State Delivery Notifications.
Import ListNotations.
Theorem oversized_output_cannot_commit_state_or_effects : forall durable result previous,
 Delivery.fits durable result = false ->
 decision_world (snd (Delivery.deliver_with_status durable result previous)) = previous /\
 decision_effects (snd (Delivery.deliver_with_status durable result previous)) = [].
Proof. intros; unfold Delivery.deliver_with_status; rewrite H; split; reflexivity. Qed.
Theorem fitting_output_preserves_the_complete_decision : forall durable result previous,
 Delivery.fits durable result = true -> (snd (Delivery.deliver_with_status durable result previous)) = result.
Proof. intros; unfold Delivery.deliver_with_status; rewrite H; reflexivity. Qed.
