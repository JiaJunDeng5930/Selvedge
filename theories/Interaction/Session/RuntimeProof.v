From Stdlib Require Import String List Bool NArith.
From Selvedge.Interaction Require Input CommandAssessment.
From Selvedge.Interaction.Session Require State Runtime Authoring.
Module SS:=Selvedge.Interaction.Session.State.

Theorem unknown_completion_keeps_duplicate_protection namespace snapshot lagged ticket reason state command:
 SS.pending_command command(Authoring.result_state
   (Runtime.core namespace snapshot lagged(Input.CompletionUnknown ticket reason)state))=
 SS.pending_command command state.
Proof.
 unfold Runtime.core,SS.pending_command. simpl.
 generalize(SS.awaiting(SS.authoring_state state)).
 intro entries. induction entries as [|pending rest IH]; simpl; [reflexivity|].
 rewrite IH. unfold SS.unknown_outcome.
 destruct(N.eqb ticket(SS.ticket pending)); reflexivity.
Qed.
Theorem unknown_completion_keeps_request_tickets namespace snapshot lagged ticket reason state:
 map SS.ticket(SS.awaiting(SS.authoring_state(Authoring.result_state
   (Runtime.core namespace snapshot lagged(Input.CompletionUnknown ticket reason)state))))=
 map SS.ticket(SS.awaiting(SS.authoring_state state)).
Proof.
 unfold Runtime.core. simpl.
 generalize(SS.awaiting(SS.authoring_state state)).
 intro entries. induction entries as [|pending rest IH]; simpl; [reflexivity|].
 rewrite IH. unfold SS.unknown_outcome.
 destruct(N.eqb ticket(SS.ticket pending)); reflexivity.
Qed.
