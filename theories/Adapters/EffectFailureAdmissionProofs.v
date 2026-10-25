From Stdlib Require Import String List Bool NArith PeanoNat Lia.
From Selvedge.Foundation Require Import Json Schema BoundedDiagnostic BoundedDiagnosticProofs.
From Selvedge.Kernel Require Import Numbers Domain Inputs ModelDeclarations InputDecoder HookRules ApprovalProtocol ProtocolProofs.
From Selvedge.Features Require Import Board BoardParameters Titles TitleRuntime.
From Selvedge.Adapters Require Import Common EffectCallbacks EffectCallbacksProofs.
Import ListNotations.
Open Scope string_scope.

Lemma diagnostic_text_contract kind message :
 Utf8.well_formed (diagnostic kind message) = true /\
 Utf8.no_nul (diagnostic kind message) = true /\
 Nat.leb (String.length (diagnostic kind message)) 4096 = true.
Proof.
 pose proof (every_callback_diagnostic_is_admitted kind message) as valid.
 unfold BoundedDiagnostic.accepts in valid.
 repeat rewrite andb_true_iff in valid.
 destruct valid as [[[unicode nul] bytes] blank].
 repeat split; try assumption.
 apply Nat.leb_le. apply Nat.leb_le in bytes.
 eapply Nat.le_trans; [exact bytes|].
 apply Nat.leb_le. destruct kind; reflexivity.
Qed.

Lemma approval_diagnostic_contract message :
 ApprovalProtocol.valid_justification (diagnostic Approval message) = true.
Proof.
 pose proof (every_callback_diagnostic_is_admitted Approval message) as valid.
 unfold BoundedDiagnostic.accepts in valid.
 cbn [diagnostic_contract BoundedDiagnostic.byte_budget BoundedDiagnostic.require_nonblank] in valid.
 repeat rewrite andb_true_iff in valid.
 destruct valid as [[[unicode nul] bytes] blank].
 unfold ApprovalProtocol.valid_justification, ApprovalProtocol.valid_reason.
 rewrite unicode, nul, blank. cbn.
 apply N.leb_le. apply Nat.leb_le in bytes.
 change (N.of_nat (String.length (diagnostic Approval message)) <= N.of_nat 2048)%N. lia.
Qed.

Lemma hook_failure_text_admitted text :
 Utf8.well_formed text = true -> Nat.leb (String.length text) 4096 = true ->
 HookRules.parse_hook (JObject [("decision",JString "failed");("reason",JString text)]) =
 Some (HookFailure text).
Proof.
 intros unicode bytes. unfold HookRules.parse_hook, HookRules.parse_reason_decision.
 change (option_map HookFailure (if Utf8.well_formed text && Nat.leb (String.length text) 4096
   then Some text else None) = Some (HookFailure text)).
 now rewrite unicode, bytes.
Qed.

Lemma after_failure_text_admitted text :
 Utf8.well_formed text = true -> Nat.leb (String.length text) 4096 = true ->
 HookRules.parse_after (JObject [("decision",JString "failed");("reason",JString text)]) =
 Some (AfterFailure text).
Proof.
 intros unicode bytes. unfold HookRules.parse_after, HookRules.parse_reason_decision.
 change (option_map AfterFailure (if Utf8.well_formed text && Nat.leb (String.length text) 4096
   then Some text else None) = Some (AfterFailure text)).
 now rewrite unicode, bytes.
Qed.

Lemma approval_failure_text_admitted text :
 ApprovalProtocol.valid_justification text = true ->
 InputDecoder.parse_approval_outcome (JObject [("decision",JString "failed");("reason",JString text)]) =
 Some (ApprovalFailed text).
Proof.
 intro reason. unfold InputDecoder.parse_approval_outcome. cbn.
 rewrite reason. unfold ApprovalProtocol.normalize_outcome.
 unfold ApprovalProtocol.valid_justification in reason.
 apply andb_true_iff in reason. cbn [ApprovalProtocol.outcome_reason].
 now rewrite (proj2 reason).
Qed.

(** These are the production outcome decoders, rather than a separate predicate
    describing an assumed callback contract. The external observation cannot
    make a failure callback itself fail admission. *)
Theorem hook_failure_diagnostic_is_decoded message :
 HookRules.parse_hook (JObject [("decision",JString "failed");
   ("reason",JString (diagnostic Hook message))]) =
 Some (HookFailure (diagnostic Hook message)).
Proof.
 destruct (diagnostic_text_contract Hook message) as [unicode [_ bytes]].
 now apply hook_failure_text_admitted.
Qed.
Theorem after_failure_diagnostic_is_decoded message :
 HookRules.parse_after (JObject [("decision",JString "failed");
   ("reason",JString (diagnostic AfterHook message))]) =
 Some (AfterFailure (diagnostic AfterHook message)).
Proof.
 destruct (diagnostic_text_contract AfterHook message) as [unicode [_ bytes]].
 now apply after_failure_text_admitted.
Qed.
Theorem approval_failure_diagnostic_is_decoded message :
 InputDecoder.parse_approval_outcome (JObject [("decision",JString "failed");
   ("reason",JString (diagnostic Approval message))]) =
 Some (ApprovalFailed (diagnostic Approval message)).
Proof. apply approval_failure_text_admitted, approval_diagnostic_contract. Qed.

Theorem board_failure_diagnostic_is_admitted message :
 BoardParameters.limited (diagnostic BoardText message) 4096 = true.
Proof.
 destruct (diagnostic_text_contract BoardText message) as [unicode [nul bytes]].
 unfold BoardParameters.limited. rewrite unicode, nul. cbn.
 apply N.leb_le. apply Nat.leb_le in bytes.
 change (N.of_nat (String.length (diagnostic BoardText message)) <= N.of_nat 4096)%N. lia.
Qed.

Local Opaque show_natural parse_natural diagnostic Common.get BoardParameters.limited
 Utf8.well_formed Utf8.no_nul Utf8.nonblank TitleRuntime.complete
 Board.lookup Board.put Board.suggestion HookRules.parse_hook HookRules.parse_after
 InputDecoder.parse_approval_outcome.

Theorem hook_failure_wire_is_decoded id ticket message :
 InputDecoder.decode (JObject [("kind",JString "hook");
   ("task_id",JNumber (show_natural id));("ticket",JNumber (show_natural ticket));
   ("outcome",JObject [("decision",JString "failed");("reason",JString (diagnostic Hook message))])]) =
 Some (HookCompleted id ticket (HookFailure (diagnostic Hook message))).
Proof. cbn. rewrite !natural_print_parse. cbn. now rewrite hook_failure_diagnostic_is_decoded. Qed.

Theorem after_failure_wire_is_decoded id ticket operation message :
 InputDecoder.decode (JObject [("kind",JString "after_hook");
   ("task_id",JNumber (show_natural id));("ticket",JNumber (show_natural ticket));
   ("operation_id",JNumber (show_natural operation));
   ("outcome",JObject [("decision",JString "failed");("reason",JString (diagnostic AfterHook message))])]) =
 Some (AfterCompleted id operation ticket (AfterFailure (diagnostic AfterHook message))).
Proof. cbn. rewrite !natural_print_parse. cbn. now rewrite after_failure_diagnostic_is_decoded. Qed.

Theorem approval_failure_wire_is_decoded id ticket message :
 InputDecoder.decode (JObject [("kind",JString "approval");
   ("task_id",JNumber (show_natural id));("ticket",JNumber (show_natural ticket));
   ("outcome",JObject [("decision",JString "failed");("reason",JString (diagnostic Approval message))])]) =
 Some (ApprovalCompleted id ticket (ApprovalFailed (diagnostic Approval message))).
Proof. cbn. rewrite !natural_print_parse. cbn. now rewrite approval_failure_diagnostic_is_decoded. Qed.

Theorem model_failure_wire_is_decoded id ticket message :
 InputDecoder.decode (JObject [("kind",JString "model");
   ("task_id",JNumber (show_natural id));("ticket",JNumber (show_natural ticket));
   ("ok",JBool false);("message",JString (diagnostic Model message))]) =
 Some (ModelCompleted id ticket (ModelFailure (diagnostic Model message))).
Proof. cbn. rewrite !natural_print_parse. reflexivity. Qed.

Theorem tool_failure_wire_is_decoded id ticket message :
 InputDecoder.decode (JObject [("kind",JString "tool");
   ("task_id",JNumber (show_natural id));("ticket",JNumber (show_natural ticket));
   ("error",JBool true);("value",error_value (diagnostic Tool message))]) =
 Some (ToolCompleted id ticket (error_value (diagnostic Tool message)) true).
Proof. cbn. rewrite !natural_print_parse. reflexivity. Qed.

Theorem context_failure_wire_is_decoded id ticket message :
 InputDecoder.decode (JObject [("kind",JString "context_observed");
   ("task_id",JNumber (show_natural id));("ticket",JNumber (show_natural ticket));
   ("ok",JBool false);("message",JString (diagnostic Context message))]) =
 Some (ContextCompleted id ticket None (diagnostic Context message)).
Proof.
 destruct (diagnostic_text_contract Context message) as [_ [_ bytes]].
 cbn. rewrite !natural_print_parse. cbn.
 change ((if Nat.leb (String.length (diagnostic Context message)) 4096
   then Some (ContextCompleted id ticket None (diagnostic Context message)) else None) =
   Some (ContextCompleted id ticket None (diagnostic Context message))).
 now rewrite bytes.
Qed.

Theorem reasoning_failure_wire_is_decoded id ticket message :
 InputDecoder.decode (JObject [("kind",JString "reasoning");
   ("task_id",JNumber (show_natural id));("ticket",JNumber (show_natural ticket));
   ("ok",JBool false);("message",JString (diagnostic Reasoning message))]) =
 Some (ReasoningCompleted id ticket (Reasoning.EvaluationFailed (diagnostic Reasoning message))).
Proof.
 destruct (diagnostic_text_contract Reasoning message) as [_ [_ bytes]].
 cbn. rewrite !natural_print_parse. cbn.
 change ((if Nat.leb (String.length (diagnostic Reasoning message)) 4096
   then Some (ReasoningCompleted id ticket (Reasoning.EvaluationFailed (diagnostic Reasoning message))) else None) =
   Some (ReasoningCompleted id ticket (Reasoning.EvaluationFailed (diagnostic Reasoning message)))).
 now rewrite bytes.
Qed.

Theorem board_failure_wire_is_admitted id ticket message :
 Board.valid_completion_payload (JObject [("kind",JString "board_text");
   ("card_id",JNumber (show_natural id));("ticket",JNumber (show_natural ticket));
   ("ok",JBool false);("message",JString (diagnostic BoardText message))]) false = true.
Proof.
 pose proof (board_failure_diagnostic_is_admitted message) as text.
 unfold Board.valid_completion_payload, Selvedge.Features.Worktree.shape.
 cbn. rewrite !natural_print_parse. cbn. exact text.
Qed.

Theorem title_failure_wire_is_decoded id ticket message value :
 TitleRuntime.completion (JObject [("kind",JString "task_title");
   ("task_id",JNumber (show_natural id));("ticket",JNumber (show_natural ticket));
   ("ok",JBool false);("message",JString (diagnostic TaskTitle message))]) value =
 Some (true,true,TitleRuntime.complete id ticket false (diagnostic TaskTitle message) value).
Proof.
 destruct (diagnostic_text_contract TaskTitle message) as [unicode [_ bytes]].
 assert (bound : N.leb (N.of_nat (String.length (diagnostic TaskTitle message))) Titles.response_title_bytes = true).
 { apply N.leb_le. apply Nat.leb_le in bytes.
   change (N.of_nat (String.length (diagnostic TaskTitle message)) <= N.of_nat 4096)%N. lia. }
 unfold TitleRuntime.completion.
 cbn.
 rewrite !natural_print_parse. cbn. now rewrite bound, unicode.
Qed.

Theorem failed_context_effect_is_decoded effect id ticket message limit :
 callback_kind_of (str effect "kind") = Some Context ->
 get effect "task_id" = JNumber (show_natural id) ->
 get effect "ticket" = JNumber (show_natural ticket) ->
 InputDecoder.decode (failed effect message limit) =
 Some (ContextCompleted id ticket None (diagnostic Context message)).
Proof.
 intros callback identity issued. unfold failed. rewrite callback.
 unfold EffectCallbacks.base. rewrite identity, issued. apply context_failure_wire_is_decoded.
Qed.

Local Opaque Board.valid_completion_payload.

Theorem failed_board_effect_settles_issued_ticket effect id ticket message limit value card retitle :
 callback_kind_of (str effect "kind") = Some BoardText ->
 get effect "card_id" = JNumber (show_natural id) ->
 get effect "ticket" = JNumber (show_natural ticket) ->
 Board.lookup id value = Some card ->
 Selvedge.Features.Domain.card_enrichment card =
   Selvedge.Features.Domain.Enriching ticket (Selvedge.Features.Domain.card_revision card) retitle ->
 Selvedge.Features.Domain.card_archived card = false ->
 Board.completion (failed effect message limit) value =
 Some (true,true,Selvedge.Kernel.State.accept (JObject [("accepted",JBool true)])
   (Board.put id (Board.suggestion false retitle "" "" (diagnostic BoardText message) card value) value) []).
Proof.
 intros callback identity issued found pending active.
 unfold failed. rewrite callback, identity, issued.
 pose proof (board_failure_wire_is_admitted id ticket message) as admitted.
 unfold Board.completion.
 cbn.
 rewrite !natural_print_parse, admitted. cbn.
 rewrite found, pending, !N.eqb_refl, active. reflexivity.
Qed.
