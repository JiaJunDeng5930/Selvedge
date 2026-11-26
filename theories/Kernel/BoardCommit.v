From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Generated Require Import Commands.
From Selvedge.Kernel Require Import State Inputs.
From Selvedge.Kernel Require Import DeferredCommit.
From Selvedge.Features Require Import Board.
From Selvedge.Programming Require DecisionComposition.

Definition input (decoded : option Inputs.input) : option Commands.create_card_payload :=
 match decoded with
 | Some (UserCommand (Commands.Cmd_create_card request)) => Some request
 | _ => None
 end.
Definition candidate (request : Commands.create_card_payload) (before : world) :=
 match Board.handle_create_card_result request None before with
 | CommandResult.Accepted change =>
   DecisionComposition.run (Board.prepare_creation before)
     (DeferredCommit.continue_result before (CommandResult.Accepted change))
 | CommandResult.Rejected reason => CommandResult.reject before reason
 end.
