From Stdlib Require Import String List Bool NArith PeanoNat Lia.
From Selvedge.Foundation Require Import Json Schema BoundedDiagnostic BoundedDiagnosticProofs.
From Selvedge.Kernel Require Import Numbers Domain Inputs ModelDeclarations InputDecoder HookRules ApprovalProtocol ProtocolProofs CallbackDeclarations CallbackProtocolProofs.
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

Local Transparent Common.get.
Definition kernel_failure_input kind id ticket operation message (limit : bool) : option input := match kind with
 | Hook => Some (HookCompleted id ticket (HookFailure message))
 | AfterHook => Some (AfterCompleted id operation ticket (AfterFailure message))
 | Approval => Some (ApprovalCompleted id ticket (ApprovalFailed message))
 | Model => Some (ModelCompleted id ticket (if limit then ModelContextLimit else ModelFailure message))
 | Tool => Some (ToolCompleted id ticket (error_value message) true)
 | Context => Some (ContextCompleted id ticket None message)
 | Reasoning => Some (ReasoningCompleted id ticket (Reasoning.EvaluationFailed message))
 | _ => None end.
Ltac prove_raw_fields :=
 first [apply RawNil | apply RawCons;
   [cbn [decode_field Field OmittableField field_kind field_omittable field_representation
      CallbackDeclarations.operation_identity CallbackDeclarations.failure_kind
      decode_value missing_value as_number as_string as_bool option_map];
    rewrite ?natural_print_parse; reflexivity | prove_raw_fields]].
Ltac failure_wire_roundtrip kind decoder tuple effect message limit Identity Issued Operation :=
 let typed := constr:(Schema.of_tuple (InputDecoder.decoder_fields decoder) tuple) in
 let raw := constr:(CallbackDeclarations.raw_values kind false effect (failure_payload kind (diagnostic kind message) limit)) in
 lazymatch goal with |- _ = ?expected =>
 change (InputDecoder.decode (ModelDeclarations.encode (raw_variant (decoder_declaration decoder)) raw) = expected) end;
 transitivity (ModelDeclarations.decoder_construct decoder typed);
 [apply declared_input_wire; [reflexivity|reflexivity|reflexivity|];
  cbn [CallbackDeclarations.raw_values CallbackDeclarations.append_raw CallbackDeclarations.raw_source CallbackDeclarations.coordinates
    List.app ModelDeclarations.identity CallbackDeclarations.operation_identity Schema.of_tuple Schema.head Schema.tail Schema.Field Schema.field_name];
  unfold Common.get in Identity, Issued; try unfold Common.get in Operation;
  rewrite Identity, Issued; try rewrite Operation;
  prove_raw_fields
 |cbv beta iota zeta delta -[diagnostic InputDecoder.parse_approval_outcome
   InputDecoder.parse_hook InputDecoder.parse_after HookRules.parse_hook HookRules.parse_after
   Nat.leb Utf8.byte_length String.length]].

(** One statement covers all kernel failure callbacks. The coordinates are
    assumptions of this admission theorem, never new restrictions on encoding. *)
Theorem every_kernel_failure_callback_is_decoded kind effect id ticket operation message limit expected :
 kernel_failure_input kind id ticket operation (diagnostic kind message) limit = Some expected ->
 get effect "task_id" = JNumber (show_natural id) -> get effect "ticket" = JNumber (show_natural ticket) ->
 (kind = AfterHook -> get effect "operation_id" = JNumber (show_natural operation)) ->
 InputDecoder.decode (CallbackDeclarations.encode kind false effect (failure_payload kind (diagnostic kind message) limit)) = Some expected.
Proof.
 destruct kind; cbn [kernel_failure_input]; try discriminate;
 intros Expected Identity Issued Operation; inversion Expected; subst expected.
 - failure_wire_roundtrip Approval InputDecoder.approval_decoder [!id;ticket;failure_outcome (diagnostic Approval message)!] effect message limit Identity Issued Operation.
   now rewrite approval_failure_diagnostic_is_decoded.
 - failure_wire_roundtrip Hook InputDecoder.hook_decoder [!id;ticket;failure_outcome (diagnostic Hook message)!] effect message limit Identity Issued Operation.
   now rewrite hook_failure_diagnostic_is_decoded.
 - specialize (Operation eq_refl).
   failure_wire_roundtrip AfterHook InputDecoder.after_decoder [!id;ticket;operation;failure_outcome (diagnostic AfterHook message)!] effect message limit Identity Issued Operation.
   now rewrite after_failure_diagnostic_is_decoded.
 - failure_wire_roundtrip Context InputDecoder.context_decoder [!id;ticket;false;(@None (list json));Some (diagnostic Context message)!] effect message limit Identity Issued Operation.
   destruct (diagnostic_text_contract Context message) as [_ [_ Bound]].
   change ((if Nat.leb (String.length (diagnostic Context message)) 4096 then Some (ContextCompleted id ticket None (diagnostic Context message)) else None) = Some (ContextCompleted id ticket None (diagnostic Context message))).
   now rewrite Bound.
 - failure_wire_roundtrip Reasoning InputDecoder.reasoning_decoder [!id;ticket;false;(@None string);(@None N);Some (diagnostic Reasoning message)!] effect message limit Identity Issued Operation.
   destruct (diagnostic_text_contract Reasoning message) as [_ [_ Bound]].
   change ((if Nat.leb (String.length (diagnostic Reasoning message)) 4096 then Some (ReasoningCompleted id ticket (Reasoning.EvaluationFailed (diagnostic Reasoning message))) else None) = Some (ReasoningCompleted id ticket (Reasoning.EvaluationFailed (diagnostic Reasoning message)))).
   now rewrite Bound.
 - destruct limit.
   + failure_wire_roundtrip Model InputDecoder.model_decoder [!id;ticket;false;(@None (list json));Some (diagnostic Model message);
       Schema.decode_value (KEnum "context_limit" []) (JString "context_limit")!] effect message true Identity Issued Operation. reflexivity.
   + failure_wire_roundtrip Model InputDecoder.model_decoder [!id;ticket;false;(@None (list json));Some (diagnostic Model message);(@None (denote (KEnum "context_limit" [])))!] effect message false Identity Issued Operation. reflexivity.
 - failure_wire_roundtrip Tool InputDecoder.tool_decoder [!id;ticket;true;Some (error_value (diagnostic Tool message))!] effect message limit Identity Issued Operation. reflexivity.
Qed.

Ltac callback_body_is_decoded Identity Issued :=
 cbn [CallbackDeclarations.raw_values CallbackDeclarations.append_raw CallbackDeclarations.raw_source
   CallbackDeclarations.coordinates ModelDeclarations.identity Schema.of_tuple Schema.head Schema.tail Schema.Field Schema.field_name];
 unfold Common.get in Identity, Issued; rewrite Identity, Issued; prove_raw_fields.

Theorem board_failure_wire_is_admitted effect id ticket message limit :
 get effect "card_id" = JNumber (show_natural id) ->
 get effect "ticket" = JNumber (show_natural ticket) ->
 Board.valid_completion_payload
   (CallbackDeclarations.encode BoardText false effect (failure_payload BoardText (diagnostic BoardText message) limit)) false = true.
Proof.
 intros Identity Issued.
 assert (Decoded : Schema.decode (CallbackDeclarations.full_schema BoardText false)
   (CallbackDeclarations.encode BoardText false effect (failure_payload BoardText (diagnostic BoardText message) limit)) =
   Some (Schema.of_tuple (CallbackDeclarations.full_schema BoardText false)
     [!callback_text BoardText;id;ticket;false;diagnostic BoardText message!])).
 { apply full_callback_roundtrip; [reflexivity|callback_body_is_decoded Identity Issued]. }
 unfold Board.valid_completion_payload, Selvedge.Features.Worktree.shape.
 rewrite Decoded; cbn; apply board_failure_diagnostic_is_admitted.
Qed.

Theorem title_failure_wire_is_decoded effect id ticket message limit value :
 get effect "task_id" = JNumber (show_natural id) ->
 get effect "ticket" = JNumber (show_natural ticket) ->
 TitleRuntime.completion
   (CallbackDeclarations.encode TaskTitle false effect (failure_payload TaskTitle (diagnostic TaskTitle message) limit)) value =
 Some (true,true,TitleRuntime.complete id ticket false (diagnostic TaskTitle message) value).
Proof.
 intros Identity Issued.
 assert (Decoded : Schema.decode (CallbackDeclarations.full_schema TaskTitle false)
   (CallbackDeclarations.encode TaskTitle false effect (failure_payload TaskTitle (diagnostic TaskTitle message) limit)) =
   Some (Schema.of_tuple (CallbackDeclarations.full_schema TaskTitle false)
     [!callback_text TaskTitle;id;ticket;false;diagnostic TaskTitle message!])).
 { apply full_callback_roundtrip; [reflexivity|callback_body_is_decoded Identity Issued]. }
 destruct (diagnostic_text_contract TaskTitle message) as [unicode [_ bytes]].
 assert (bound : N.leb (N.of_nat (String.length (diagnostic TaskTitle message))) Titles.response_title_bytes = true).
 { apply N.leb_le. apply Nat.leb_le in bytes.
   change (N.of_nat (String.length (diagnostic TaskTitle message)) <= N.of_nat 4096)%N. lia. }
 unfold TitleRuntime.completion.
 change (match Schema.decode (CallbackDeclarations.full_schema TaskTitle false)
   (CallbackDeclarations.encode TaskTitle false effect (failure_payload TaskTitle (diagnostic TaskTitle message) limit)) with
   | Some fields => let fields := tail fields in let id := head fields in let fields := tail fields in
     let ticket := head fields in let text := head (tail (tail fields)) in
     if negb (N.leb (N.of_nat (String.length text)) Titles.response_title_bytes && Utf8.well_formed text)
     then None else Some (true,true,TitleRuntime.complete id ticket false text value)
   | None => None end = Some (true,true,TitleRuntime.complete id ticket false (diagnostic TaskTitle message) value)).
 rewrite Decoded.
 change ((if negb (N.leb (N.of_nat (String.length (diagnostic TaskTitle message))) Titles.response_title_bytes &&
   Utf8.well_formed (diagnostic TaskTitle message)) then None else
   Some (true,true,TitleRuntime.complete id ticket false (diagnostic TaskTitle message) value)) =
   Some (true,true,TitleRuntime.complete id ticket false (diagnostic TaskTitle message) value)).
 now rewrite bound, unicode.
Qed.

Theorem failed_context_effect_is_decoded effect id ticket message limit :
 callback_kind_of (str effect "kind") = Some Context ->
 get effect "task_id" = JNumber (show_natural id) ->
 get effect "ticket" = JNumber (show_natural ticket) ->
 InputDecoder.decode (failed effect message limit) =
 Some (ContextCompleted id ticket None (diagnostic Context message)).
Proof.
 intros callback identity issued; unfold failed; rewrite callback.
 eapply every_kernel_failure_callback_is_decoded with (operation:=0%N);
   [reflexivity|exact identity|exact issued|discriminate].
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
 unfold failed. rewrite callback.
 pose proof (board_failure_wire_is_admitted effect id ticket message limit identity issued) as admitted.
 unfold Board.completion.
 unfold Common.get in identity, issued.
 cbn in admitted |- *.
 rewrite identity, issued in admitted |- *. cbn. rewrite !natural_print_parse. cbn.
 rewrite admitted. cbn.
 rewrite found, pending, !N.eqb_refl, active. reflexivity.
Qed.
