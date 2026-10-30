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

Definition kernel_failure_input (kind : callback_kind) : fields (coordinates kind) -> string -> bool -> option input :=
 match kind as kind return fields (coordinates kind) -> string -> bool -> option input with
 | Hook => fun address message _ => Some (HookCompleted (Schema.head address) (Schema.head (Schema.tail address)) (HookFailure message))
 | AfterHook => fun address message _ => Some (AfterCompleted (Schema.head address)
     (Schema.head (Schema.tail (Schema.tail address))) (Schema.head (Schema.tail address)) (AfterFailure message))
 | Approval => fun address message _ => Some (ApprovalCompleted (Schema.head address) (Schema.head (Schema.tail address)) (ApprovalFailed message))
 | Model => fun address message limit => Some (ModelCompleted (Schema.head address) (Schema.head (Schema.tail address))
     (if limit then ModelContextLimit else ModelFailure message))
 | Tool => fun address message _ => Some (ToolCompleted (Schema.head address) (Schema.head (Schema.tail address)) (error_value message) true)
 | Context => fun address message _ => Some (ContextCompleted (Schema.head address) (Schema.head (Schema.tail address)) None message)
 | Reasoning => fun address message _ => Some (ReasoningCompleted (Schema.head address) (Schema.head (Schema.tail address)) (Reasoning.EvaluationFailed message))
 | _ => fun _ _ _ => None end.

Ltac compute_typed_roundtrip Roundtrip :=
 cbv beta iota zeta delta -[diagnostic show_natural parse_natural] in Roundtrip;
 repeat rewrite natural_print_parse in Roundtrip.
Ltac failure_wire_roundtrip :=
 lazymatch goal with
 | |- InputDecoder.decode (CallbackDeclarations.encode ?kind false ?address ?values) = ?expected =>
   let wire := constr:(CallbackDeclarations.encode kind false address values) in
   let branch := eval cbv in (match CallbackDeclarations.status kind with None => true | Some _ => false end) in
   destruct (constructed_callback_has_declared_fields kind false address values)
     as [canonical [Decoded _]];
   let Computed := fresh "Computed" in pose proof Decoded as Computed;
   compute_typed_roundtrip Computed; inversion Computed; subst canonical;
   change (InputDecoder.decode_callback kind wire = expected);
   unfold InputDecoder.decode_callback,CallbackDeclarations.decode;
   let Status := fresh "Status" in
   assert (Status : CallbackDeclarations.read_status kind wire = Some branch) by reflexivity;
   rewrite Status;
   let Kind := fresh "Kind" in
   assert (Kind : ModelDeclarations.matches (CallbackDeclarations.declaration kind branch) wire = true) by reflexivity;
   rewrite Kind;
   let Parsed := fresh "Parsed" in
   pose proof Decoded as Parsed;
   lazymatch type of Parsed with
   | _ = Some ?result =>
     change (Schema.decode (CallbackDeclarations.full_schema kind branch) wire = Some result) in Parsed
   end;
   rewrite Parsed;
   cbv beta iota zeta delta -[diagnostic InputDecoder.parse_approval_outcome
     InputDecoder.parse_hook InputDecoder.parse_after HookRules.parse_hook HookRules.parse_after
     Nat.leb Utf8.byte_length String.length]
 end.

(** Issued coordinates are typed before callback construction. The schema
    roundtrip is shared; these cases constrain the actual outcome decoders. *)
Theorem every_kernel_failure_callback_is_decoded kind address message limit expected :
 kernel_failure_input kind address (diagnostic kind message) limit = Some expected ->
 InputDecoder.decode (CallbackDeclarations.encode kind false address
   (failure_payload kind (diagnostic kind message) limit)) = Some expected.
Proof.
 destruct kind; cbn [kernel_failure_input]; try discriminate;
 intros Expected; inversion Expected; subst expected.
 - failure_wire_roundtrip.
   now rewrite approval_failure_diagnostic_is_decoded.
 - failure_wire_roundtrip.
   now rewrite hook_failure_diagnostic_is_decoded.
 - failure_wire_roundtrip.
   now rewrite after_failure_diagnostic_is_decoded.
 - failure_wire_roundtrip.
   destruct (diagnostic_text_contract Context message) as [_ [_ Bound]].
   lazymatch goal with |- (if ?within then _ else _) = _ => change (within = true) in Bound end.
   now rewrite Bound.
 - failure_wire_roundtrip.
   destruct (diagnostic_text_contract Reasoning message) as [_ [_ Bound]].
   lazymatch goal with |- (if ?within then _ else _) = _ => change (within = true) in Bound end.
   now rewrite Bound.
 - destruct limit; failure_wire_roundtrip; reflexivity.
 - failure_wire_roundtrip; reflexivity.
Qed.

Ltac callback_schema_roundtrip kind address values :=
 destruct (constructed_callback_has_declared_fields kind false address values)
   as [canonical [Decoded _]];
 let Computed := fresh "Computed" in pose proof Decoded as Computed;
 compute_typed_roundtrip Computed; inversion Computed; subst canonical.

Lemma board_failure_wire_is_decoded id ticket message limit :
 Board.decode_completion_payload
   (CallbackDeclarations.encode BoardText false (Schema.of_tuple (coordinates BoardText) [!id;ticket!])
     (failure_payload BoardText (diagnostic BoardText message) limit)) false =
 Some (Board.CompletionPayload id ticket "" "" (diagnostic BoardText message)).
Proof.
 callback_schema_roundtrip BoardText (Schema.of_tuple (coordinates BoardText) [!id;ticket!])
   (failure_payload BoardText (diagnostic BoardText message) limit).
 unfold Board.decode_completion_payload.
 rewrite Decoded; cbv beta iota zeta delta [CallbackDeclarations.full_schema CallbackDeclarations.declaration
   CallbackDeclarations.coordinates CallbackDeclarations.payload CallbackDeclarations.status CallbackDeclarations.wire_payload ModelDeclarations.effect ModelDeclarations.payload_fields
   List.app Schema.of_tuple Schema.head Schema.tail fst snd].
 rewrite board_failure_diagnostic_is_admitted; reflexivity.
Qed.

Theorem title_failure_wire_is_decoded id ticket message limit value :
 TitleRuntime.completion
   (CallbackDeclarations.encode TaskTitle false (Schema.of_tuple (coordinates TaskTitle) [!id;ticket!])
     (failure_payload TaskTitle (diagnostic TaskTitle message) limit)) value =
 Some (true,true,TitleRuntime.complete id ticket false (diagnostic TaskTitle message) value).
Proof.
 callback_schema_roundtrip TaskTitle (Schema.of_tuple (coordinates TaskTitle) [!id;ticket!])
   (failure_payload TaskTitle (diagnostic TaskTitle message) limit).
 destruct (diagnostic_text_contract TaskTitle message) as [unicode [_ bytes]].
 assert (bound : N.leb (N.of_nat (String.length (diagnostic TaskTitle message))) Titles.response_title_bytes = true).
 { apply N.leb_le. apply Nat.leb_le in bytes.
   change (N.of_nat (String.length (diagnostic TaskTitle message)) <= N.of_nat 4096)%N. lia. }
 unfold TitleRuntime.completion.
 change (match Schema.decode (CallbackDeclarations.full_schema TaskTitle false)
   (CallbackDeclarations.encode TaskTitle false (Schema.of_tuple (coordinates TaskTitle) [!id;ticket!])
     (failure_payload TaskTitle (diagnostic TaskTitle message) limit)) with
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
 decode_fields (coordinates Context) (object_fields effect) = Some (Schema.of_tuple (coordinates Context) [!id;ticket!]) ->
 (match failed effect message limit with Some reply => InputDecoder.decode reply | None => None end) =
 Some (ContextCompleted id ticket None (diagnostic Context message)).
Proof.
 intros Callback Address; unfold failed; rewrite Callback, Address; cbn [option_map].
 apply every_kernel_failure_callback_is_decoded; reflexivity.
Qed.

Theorem failed_board_effect_settles_issued_ticket effect id ticket message limit value card retitle :
 callback_kind_of (str effect "kind") = Some BoardText ->
 decode_fields (coordinates BoardText) (object_fields effect) = Some (Schema.of_tuple (coordinates BoardText) [!id;ticket!]) ->
 Board.lookup id value = Some card ->
 Selvedge.Features.Domain.card_enrichment card =
   Selvedge.Features.Domain.Enriching (RequestEnvelope.Envelope ticket ((Selvedge.Features.Domain.card_revision card), retitle)) ->
 Selvedge.Features.Domain.card_archived card = false ->
 (match failed effect message limit with Some reply => Board.completion reply value | None => None end) =
 Some (true,true,Selvedge.Kernel.State.accept (JObject [("accepted",JBool true)])
   (Board.put id (Board.suggestion false retitle "" "" (diagnostic BoardText message) card value) value) []).
Proof.
 intros Callback Address found pending active.
 unfold failed; rewrite Callback, Address; cbn [option_map].
 pose proof (board_failure_wire_is_decoded id ticket message limit) as Parsed.
 set (wire:=CallbackDeclarations.encode BoardText false (Schema.of_tuple (coordinates BoardText) [!id;ticket!])
   (failure_payload BoardText (diagnostic BoardText message) limit)) in *.
 assert (Kind:string_field "kind" wire=Some "board_text") by reflexivity.
 assert (Outcome:bool_field "ok" wire=Some false) by reflexivity.
 unfold Board.completion; rewrite Kind, Outcome, Parsed;
 cbn [Board.completion_card Board.completion_ticket Board.completion_title Board.completion_description Board.completion_message].
 rewrite found, pending, !N.eqb_refl, active; reflexivity.
Qed.
