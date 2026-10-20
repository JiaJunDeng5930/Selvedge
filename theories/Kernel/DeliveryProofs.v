From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import State Delivery Notifications.
Import ListNotations.
Theorem oversized_output_cannot_commit_state_or_effects : forall durable result previous,
 Delivery.fits durable result = false ->
 decision_world (Delivery.deliver durable result previous) = previous /\
 decision_effects (Delivery.deliver durable result previous) = [].
Proof. intros; unfold Delivery.deliver; rewrite H; split; reflexivity. Qed.
Theorem fitting_output_preserves_the_complete_decision : forall durable result previous,
 Delivery.fits durable result = true -> Delivery.deliver durable result previous = result.
Proof. intros; unfold Delivery.deliver; rewrite H; reflexivity. Qed.
Theorem notification_observation_never_changes_world : forall durable source previous result,
 decision_world (Notifications.decorate durable source previous result) = decision_world result.
Proof.
 intros; unfold Notifications.decorate; destruct durable; [|reflexivity].
 destruct (_ ++ _ ++ _)%list; [reflexivity|]. destruct (Delivery.fits true _); reflexivity.
Qed.
Theorem notification_observation_never_changes_reply : forall durable source previous result,
 decision_reply (Notifications.decorate durable source previous result) = decision_reply result.
Proof.
 intros; unfold Notifications.decorate; destruct durable; [|reflexivity].
 destruct (_ ++ _ ++ _)%list; [reflexivity|]. destruct (Delivery.fits true _); reflexivity.
Qed.
