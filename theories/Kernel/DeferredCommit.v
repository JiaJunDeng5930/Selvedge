From Selvedge.Kernel Require CommitPacket.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Domain State Inputs Dispatch Delivery Notifications.
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

(** The worker starts from [State.initial] and replays admitted inputs. Domain
    constructors own state and request relationships. The commit boundary only
    withdraws cancelled requests and applies the external output budget. *)
Definition admit_with_status (durable : bool) (before : world) (result : decision) :=
 Delivery.deliver_with_status durable (Dispatch.retain_live_effects result) before.

Definition select (durable : bool) (source : option input) (before : world) (candidate : decision) :=
 CommitPacket.choose durable source (admit_with_status durable before candidate).
Definition packet (source : option input) (before : world) (candidate : decision) : world * json :=
 CommitPacket.finalize before (select true source before candidate).
