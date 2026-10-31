From Stdlib Require Import String Bool NArith.
From Selvedge.Foundation Require Import Registry.
From Selvedge.Kernel Require Import State.
From Selvedge.Features Require Domain.
From Selvedge.Programming Require CommandResult OptionObservation.
Open Scope string_scope.
Module F := Selvedge.Features.Domain.

Definition lookup id before :=
 match registry_at id (F.board_cards (F.feature_board (world_features before))) with
 | Some card => card | None => None end.
Record card_reference (before : world) (id : N) := CardReference {
 selected_card : F.card;
 selected_card_found : lookup id before = Some selected_card
}.
Arguments CardReference {before id}.
Arguments selected_card {before id}.
Arguments selected_card_found {before id}.

Definition select_card_reference (id revision:N) (value:world) : CommandResult.result (card_reference value id) :=
 OptionObservation.observe (lookup id value) (fun card Found =>
   if N.eqb revision (Selvedge.Features.Domain.card_revision card)
   then CommandResult.Accepted (CardReference card Found)
   else CommandResult.refuse "card_conflict" "The card changed in another view or during execution. Refresh its current values before applying this edit.")
 (fun _ => CommandResult.refuse "card_not_found" "The board card does not exist").
Definition select_card (id revision:N) (value:world) :=
 CommandResult.map selected_card (select_card_reference id revision value).
Definition with_card (id revision:N) (value:world) (run:Selvedge.Features.Domain.card->decision) :=
 CommandResult.resolve value run (select_card id revision value).
