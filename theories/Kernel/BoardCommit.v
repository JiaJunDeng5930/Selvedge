From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Generated Require Import Commands.
From Selvedge.Kernel Require Import State Inputs.
From Selvedge.Kernel Require Import DeferredCommit.
From Selvedge.Features Require Import Board.

Definition input (decoded : option Inputs.input) : option Commands.create_card_payload :=
 match decoded with
 | Some (UserCommand (Commands.Cmd_create_card request)) => Some request
 | _ => None
 end.
Definition candidate (request : Commands.create_card_payload) (before : world) :=
 DeferredCommit.continue_result before (Board.handle_create_card_result request None before).
Definition packet (request : Commands.create_card_payload) (raw : json) (before : world) :=
 DeferredCommit.packet (Some (UserCommand (Commands.Cmd_create_card request))) before
   (candidate request before).
