From Stdlib Require Import String List Bool NArith.
From Selvedge.Browser.Session Require Input.
From Selvedge.Interaction Require CommandAssessment.
From Selvedge.Browser.Session Require State Runtime Authoring.
Module SS:=Selvedge.Browser.Session.State.

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

Theorem unknown_document_callback_is_idle namespace snapshot lagged input state owner:
 Runtime.callback_owner input=Some owner->
 Selvedge.Browser.Documents.known_owner(Runtime.context namespace snapshot state)owner(SS.document_retention state)=false->
 Runtime.language_step namespace snapshot lagged input state=
 Selvedge.Interaction.Interactive.State.Decision(SS.interactive_state state)nil.
Proof.
 intros callback unknown. unfold Runtime.language_step. rewrite callback,unknown. reflexivity.
Qed.

Theorem synchronizing_language_reuses_document_visibility namespace snapshot lagged state:
 Runtime.synchronize_language namespace snapshot lagged state=
 Runtime.apply_language namespace snapshot lagged
   Selvedge.Interaction.Interactive.Types.EnvironmentChanged state.
Proof.
 unfold Runtime.synchronize_language,Runtime.apply_language,Runtime.language_step,Runtime.callback_owner.
 destruct (Selvedge.Interaction.Interactive.State.blocks (SS.interactive_state state)) eqn:Blocks.
 - unfold Selvedge.Interaction.Interactive.Language.step_visible,
     Selvedge.Interaction.Interactive.Runtime.step_visible. now rewrite Blocks.
 - reflexivity.
Qed.
