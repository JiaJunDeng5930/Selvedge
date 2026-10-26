From Selvedge.Kernel Require CommitPacket.
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

Definition continue_result (before : world) (result : CommandResult.result CommandResult.change) :=
 CommandResult.commit before (CommandResult.append_effects [ContinueScheduling]) result.

Definition admit_with_status (durable : bool) (source : option input) (raw : json)
 (before : world) (result : decision) :=
 let result := Dispatch.retain_live_effects result in
 let '(valid,result) := WorldInvariant.validate_with_status before result in
 let '(authorized,result) := CommitAdmission.validate_with_status durable source raw before result in
 let '(fits,result) := Delivery.deliver_with_status durable result before in
 (valid && authorized && fits,result).

Definition select (durable : bool) (source : option input) (raw : json) (before : world) (candidate : decision) :=
 CommitPacket.choose durable source (admit_with_status durable source raw before candidate).
Definition packet (source : option input) (raw : json) (before : world) (candidate : decision) : world * json :=
 CommitPacket.finalize before (select true source raw before candidate).
