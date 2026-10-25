From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Domain State Inputs Dispatch WorldInvariant CommitAdmission Delivery Notifications.
Import ListNotations.

(* An independent request is durable before the scheduler may change its owner.
   The existing continuation performs ordinary scheduling in the next turn. *)
Definition continue (result : decision) :=
 if Codec.bool_default "ok"%string (decision_reply result) false then
   Decision (decision_world result) (decision_reply result)
     (decision_effects result ++ [ContinueScheduling])
 else result.

Definition admit_with_status (durable : bool) (source : option input) (raw : json)
 (before : world) (result : decision) :=
 let result := Dispatch.retain_live_effects result in
 let '(valid,result) := WorldInvariant.validate_with_status before result in
 let '(authorized,result) := CommitAdmission.validate_with_status durable source raw before result in
 let '(fits,result) := Delivery.deliver_with_status durable result before in
 (valid && authorized && fits,result).

Definition packet (source : option input) (raw : json) (before : world) (candidate : decision) : world * json :=
 let '(admitted,result) := admit_with_status true source raw before candidate in
 (with_sequence (N.succ (world_sequence before)) (decision_world result),
  Notifications.envelope true admitted source before result).
