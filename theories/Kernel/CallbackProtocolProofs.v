From Stdlib Require Import String List Bool.
From Selvedge.Foundation Require Import Json JsonProofs Schema SchemaProofs.
From Selvedge.Kernel Require Import ModelDeclarations ProtocolProofs.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

From Selvedge.Kernel Require Import CallbackDeclarations.

(** Every result branch uses the schema that also admits its wire data. The
    fixed marker is inserted by construction; callers supply only branch data. *)
Theorem constructed_callback_has_declared_fields : forall kind ok address values,
 exists canonical,
 Schema.decode (CallbackDeclarations.full_schema kind ok)
   (CallbackDeclarations.encode kind ok address values) = Some canonical /\
 Schema.encode (CallbackDeclarations.full_schema kind ok) canonical =
   CallbackDeclarations.encode kind ok address values.
Proof.
 intros kind ok address values.
 change (exists canonical,
 Schema.decode (CallbackDeclarations.full_schema kind ok)
   (Schema.encode _ (CallbackDeclarations.full_fields kind ok address values)) = Some canonical /\
 Schema.encode _ canonical = Schema.encode _ (CallbackDeclarations.full_fields kind ok address values)).
 apply schema_wire_roundtrip; destruct kind; destruct ok;
   repeat match goal with flag : bool |- _ => destruct flag end; reflexivity.
Qed.

From Selvedge.Kernel Require Import InputDecoder.
Lemma input_find_is_named : forall name source,
 field "kind" source = Some (JString name) ->
 find (fun entry => ModelDeclarations.matches (decoder_declaration entry) source) InputDecoder.decoders =
 find (fun entry => String.eqb name (InputDecoder.decoder_name entry)) InputDecoder.decoders.
Proof.
 intros name source Tag.
 assert (Named : Forall (fun entry => tag_field (decoder_declaration entry) = "kind" /\
   tag_value (decoder_declaration entry) = JString (InputDecoder.decoder_name entry)) InputDecoder.decoders)
   by repeat constructor.
 revert Named; generalize InputDecoder.decoders as cases.
 induction cases as [|entry rest IH]; intro Named; [reflexivity|].
 inversion Named as [|? ? [Key Value] Tail]; subst.
 cbn [find]; unfold ModelDeclarations.matches at 1.
 rewrite Key, Tag, Value; cbn [equal].
 destruct (String.eqb name (InputDecoder.decoder_name entry)); [reflexivity|].
 now apply IH.
Qed.
