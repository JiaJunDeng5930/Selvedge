From Stdlib Require Import String List Bool NArith.
From Selvedge.Adapters Require Import Common Observation EffectCallbacks.
From Selvedge.Kernel Require Import ModelDeclarations CallbackDeclarations ProtocolProofs.
From Selvedge.Foundation Require Import Schema SchemaProofs BoundedDiagnostic BoundedDiagnosticProofs.
Import ListNotations.
Open Scope string_scope.

(** Provider results cannot choose the pending operation they complete. The
    numeric coordinates come only from the issued effect's decoded fields. *)
Definition committed_coordinates (effect reply : json) : Prop := forall kind address,
 callback_kind_of (str effect "kind") = Some kind ->
 decode_fields (coordinates kind) (object_fields effect) = Some address ->
 decode_fields (coordinates kind) (object_fields reply) = Some address.
Lemma encoded_callback_preserves_coordinates kind ok address values :
 decode_fields (coordinates kind) (object_fields (CallbackDeclarations.encode kind ok address values)) = Some address.
Proof.
 destruct kind; cbn [CallbackDeclarations.encode append_fields coordinates declaration
   ModelDeclarations.effect ModelDeclarations.payload_fields ModelDeclarations.identity
   ModelDeclarations.task_only List.app ModelDeclarations.encode ModelDeclarations.tag_field
   ModelDeclarations.tag_value operation_identity String.eqb Ascii.eqb Bool.eqb
   object_fields encode_fields encode_field encode_value Field field_kind
   field_representation field_omittable field_name decode_fields decode_field
   decode_value lookup as_number Schema.head Schema.tail].
 all: repeat rewrite natural_print_parse.
 all: lazymatch type of address with fields ?description =>
   change (Some (rebuild_fields description address) = Some address) end.
 all: now rewrite rebuild_fields_identity.
Qed.

Theorem completed_callback_preserves_committed_coordinates effect result reply :
 completed effect result = Some reply -> committed_coordinates effect reply.
Proof.
 unfold completed.
 destruct (callback_kind_of (str effect "kind")) as [kind|] eqn:Kind; [|discriminate].
 destruct (decode_fields (coordinates kind) (object_fields effect)) as [address|] eqn:Address; [|discriminate].
 destruct (observed_result kind result) as [[ok values]|]; [|discriminate].
 intro Accepted; inversion Accepted; subst reply.
 intros named chosen Named Chosen; rewrite Kind in Named; inversion Named; subst named.
 rewrite Address in Chosen; inversion Chosen; subst chosen; apply encoded_callback_preserves_coordinates.
Qed.
Theorem failed_callback_preserves_committed_coordinates effect message limit reply :
 failed effect message limit = Some reply -> committed_coordinates effect reply.
Proof.
 unfold failed.
 destruct (callback_kind_of (str effect "kind")) as [kind|] eqn:Kind; [|discriminate].
 destruct (decode_fields (coordinates kind) (object_fields effect)) as [address|] eqn:Address; [|discriminate].
 intro Accepted; inversion Accepted; subst reply.
 intros named chosen Named Chosen; rewrite Kind in Named; inversion Named; subst named.
 rewrite Address in Chosen; inversion Chosen; subst chosen; apply encoded_callback_preserves_coordinates.
Qed.
Theorem every_callback_diagnostic_is_admitted kind message :
 BoundedDiagnostic.accepts (diagnostic_contract kind) (diagnostic kind message) = true.
Proof.
 unfold diagnostic. apply constructed_diagnostic_is_admitted.
 destruct kind; reflexivity.
Qed.
Theorem failure_construction_is_total source kind address message :
 callback_kind_of (str (get source "effect") "kind") = Some kind ->
 decode_fields (coordinates kind) (object_fields (get source "effect")) = Some address ->
 as_string (get source "message") = Some message ->
 exists reply, failure source = success reply /\ committed_coordinates (get source "effect") reply.
Proof.
 intros Kind Address Message. unfold failure; rewrite Message.
 assert (Issued : failed (get source "effect") message (boolean_field source "context_limit") =
   Some (CallbackDeclarations.encode kind false address
     (failure_payload kind (diagnostic kind message) (boolean_field source "context_limit")))).
 { unfold failed; now rewrite Kind, Address. }
 rewrite Issued; eexists; split; [reflexivity|].
 now apply (failed_callback_preserves_committed_coordinates _ _ _ _ Issued).
Qed.
