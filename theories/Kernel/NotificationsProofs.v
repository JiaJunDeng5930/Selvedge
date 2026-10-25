From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import State Observation Notifications Delivery.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Local Opaque Notifications.batch Observation.effect_json Delivery.fits_json.

Theorem a_noncommitting_observation_has_no_notification_batch : forall durable source before result,
 Notifications.envelope durable false source before result = Observation.envelope durable result.
Proof. intros; unfold Notifications.envelope; destruct durable; reflexivity. Qed.
Theorem a_query_has_no_notification_batch : forall admitted source before result,
 Notifications.envelope false admitted source before result = Observation.envelope false result.
Proof. reflexivity. Qed.
Theorem notification_envelopes_preserve_the_committed_reply : forall durable admitted source before result,
 field "reply" (Notifications.envelope durable admitted source before result) = Some (decision_reply result).
Proof.
 intros; unfold Notifications.envelope; destruct (durable && admitted); [|reflexivity].
 destruct (Notifications.batch source before result); [reflexivity|].
 destruct (Delivery.fits_json _); reflexivity.
Qed.
Theorem notification_envelopes_preserve_the_durability_flag : forall durable admitted source before result,
 field "durable" (Notifications.envelope durable admitted source before result) = Some (JBool durable).
Proof.
 intros; unfold Notifications.envelope; destruct (durable && admitted); [|reflexivity].
 destruct (Notifications.batch source before result); [reflexivity|].
 destruct (Delivery.fits_json _); reflexivity.
Qed.
Theorem notification_envelopes_preserve_all_business_effects : forall durable admitted source before result,
 let effects := map (Observation.effect_json (decision_world result)) (decision_effects result) in
 field "effects" (Notifications.envelope durable admitted source before result) = Some (JArray effects) \/
 field "effects" (Notifications.envelope durable admitted source before result) =
   Some (JArray (effects ++ [JObject [("kind",JString "plugin_events");
     ("events",JArray (Notifications.batch source before result))]])).
Proof.
 intros. unfold Notifications.envelope; destruct (durable && admitted); [|left; reflexivity].
 destruct (Notifications.batch source before result) eqn:Batch; [left; reflexivity|].
 destruct (Delivery.fits_json _); [right|left]; reflexivity.
Qed.
Theorem oversized_notification_batch_leaves_the_complete_base_envelope : forall source before result,
 Delivery.fits_json (Notifications.enriched_envelope true result (Notifications.batch source before result)) = false ->
 Notifications.envelope true true source before result = Observation.envelope true result.
Proof.
 intros source before result Overflow. unfold Notifications.envelope; cbn [andb].
 destruct (Notifications.batch source before result) eqn:Batch; [reflexivity|].
 rewrite Overflow. reflexivity.
Qed.
Theorem a_fitting_base_envelope_remains_within_the_output_budget : forall durable admitted source before result,
 Delivery.fits durable result = true ->
 Delivery.fits_json (Notifications.envelope durable admitted source before result) = true.
Proof.
 intros durable admitted source before result Base. unfold Notifications.envelope.
 destruct (durable && admitted); [|exact Base].
 destruct (Notifications.batch source before result) as [|notice rest]; [exact Base|].
 destruct (Delivery.fits_json (Notifications.enriched_envelope durable result (notice :: rest))) eqn:Enriched;
   [exact Enriched|exact Base].
Qed.
