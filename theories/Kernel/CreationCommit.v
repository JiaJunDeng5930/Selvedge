From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Generated Require Import Commands.
From Selvedge.Kernel Require Import Domain Codec State Inputs Delivery Notifications.
From Selvedge.Features Require Import Worktree.
Import ListNotations.

(* Creation commits its birth and resource request before independent scheduling.
   The continuation is durable, just as it is for a public manual fork. *)
Definition input (decoded : option Inputs.input) : option Commands.create_payload :=
 match decoded with
 | Some (UserCommand (Commands.Cmd_create request)) => Some request
 | _ => None
 end.
Definition candidate (request : Commands.create_payload) (before : world) :=
 let result := Worktree.handle_create request None before in
 if bool_default "ok"%string (decision_reply result) false
 then Decision (decision_world result) (decision_reply result)
   (decision_effects result ++ [ContinueScheduling])
 else result.
Definition packet (request : Commands.create_payload) (before : world) : world * json :=
 let '(fits,result) := Delivery.deliver_with_status true (candidate request before) before in
 (with_sequence (N.succ (world_sequence before)) (decision_world result),
  Notifications.envelope true fits (Some (UserCommand (Commands.Cmd_create request))) before result).
