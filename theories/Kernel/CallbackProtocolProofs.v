From Stdlib Require Import String List Bool.
From Selvedge.Foundation Require Import Json Schema.
From Selvedge.Kernel Require Import ModelDeclarations.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

From Selvedge.Kernel Require Import CallbackDeclarations.

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
