From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain State Notifications Delivery.
Import ListNotations.
Open Scope list_scope.

Theorem decoration_preserves_effects_or_appends_one_notification_batch :
 forall durable source before result,
 decision_effects (Notifications.decorate durable source before result) = decision_effects result \/
 exists notices, notices <> [] /\
   decision_effects (Notifications.decorate durable source before result) =
     decision_effects result ++ [NotifyPlugins notices].
Proof.
 intros durable source before result.
 unfold Notifications.decorate.
 destruct durable; [|left; reflexivity].
 destruct (Notifications.input_events source before (decision_world result) ++
   List.concat (Numbers.indexed (fun id task => Notifications.task_events before id task
     (decision_world result)) 0 (world_tasks (decision_world result))) ++
   List.flat_map (Notifications.effect_events (decision_world result)) (decision_effects result))%list
   as [|notice rest]; [left; reflexivity|].
 destruct (Delivery.fits true (Decision (decision_world result) (decision_reply result)
   (decision_effects result ++ [NotifyPlugins (notice :: rest)]))) eqn:Fits.
 - right; exists (notice :: rest); split; [discriminate|reflexivity].
 - left; reflexivity.
Qed.

Theorem oversized_notification_batch_leaves_the_candidate_effects :
 forall source before result,
 let notices :=
   Notifications.input_events source before (decision_world result) ++
   List.concat (Numbers.indexed (fun id task => Notifications.task_events before id task
     (decision_world result)) 0 (world_tasks (decision_world result))) ++
   List.flat_map (Notifications.effect_events (decision_world result)) (decision_effects result) in
 notices <> [] ->
 Delivery.fits true (Decision (decision_world result) (decision_reply result)
   (decision_effects result ++ [NotifyPlugins notices])) = false ->
 Notifications.decorate true source before result = result.
Proof.
 intros source before result Nonempty DoesNotFit Overflow.
 cbn zeta in *.
 remember (Notifications.input_events source before (decision_world result) ++
   List.concat (Numbers.indexed (fun id task => Notifications.task_events before id task
     (decision_world result)) 0 (world_tasks (decision_world result))) ++
   List.flat_map (Notifications.effect_events (decision_world result)) (decision_effects result))%list
   as notices eqn:Batch.
 destruct notices as [|notice rest].
 - contradiction.
 - unfold Notifications.decorate.
   unfold Nonempty in Overflow.
   rewrite <- Batch; cbn; rewrite Overflow; reflexivity.
Qed.
