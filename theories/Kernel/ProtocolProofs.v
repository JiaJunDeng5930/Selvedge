From Stdlib Require Import String List Bool NArith Numbers.DecimalString Numbers.DecimalN.
From Selvedge.Foundation Require Import Json Numbers Schema SchemaProofs.
Import ListNotations.

Lemma natural_print_parse : forall value,
 Selvedge.Foundation.Numbers.parse_natural (show_natural value) = Some value.
Proof.
 intros value.
 assert (Nonempty : N.to_uint value <> Decimal.Nil).
 { intro H. pose proof (DecimalN.Unsigned.of_to value) as Roundtrip.
   rewrite H in Roundtrip; cbn in Roundtrip. subst value. discriminate. }
 pose proof (NilZero.usu (N.to_uint value) Nonempty) as Printed.
 change (NilZero.uint_of_string (show_natural value) = Some (N.to_uint value)) in Printed.
 unfold Selvedge.Foundation.Numbers.parse_natural.
 destruct (show_natural value) eqn:Text; [cbn in Printed; discriminate|].
 rewrite Printed, DecimalN.Unsigned.of_to; reflexivity.
Qed.
Lemma array_wire_roundtrip : forall (A : Type) (encode : A -> json) (decode : json -> option A),
 (forall value, exists canonical, decode (encode value) = Some canonical /\ encode canonical = encode value) ->
 forall values, exists canonical,
 decode_list decode (map encode values) = Some canonical /\ map encode canonical = map encode values.
Proof.
 intros A encode decode Each values; induction values as [|value rest IH].
 - exists []; split; reflexivity.
 - destruct (Each value) as [head [Head Wire]], IH as [tail [Tail Wires]].
   exists (head :: tail). cbn. rewrite Head, Tail, Wire, Wires; split; reflexivity.
Qed.
Fixpoint protocol_kinds (description : kind) := match description with
 | KInteger | KDecimal => false | KArray element | KOptional element => protocol_kinds element | _ => true end.
Theorem typed_field_wire_is_decodable : forall description (value : denote description),
 protocol_kinds description = true ->
 exists canonical,
 decode_value description (encode_value description value) = Some canonical /\
 encode_value description canonical = encode_value description value.
Proof.
 induction description as [| | | | | |element IH|element IH|first rest]; intros value Supported.
 - exists value; split; reflexivity.
 - exists value; split; reflexivity.
 - exists value; cbn. rewrite natural_print_parse; split; reflexivity.
 - discriminate.
 - discriminate.
 - exists value; split; reflexivity.
 - destruct (array_wire_roundtrip _ _ _ (fun value => IH value Supported) value) as [canonical [Decoded Wire]].
   exists canonical; cbn; rewrite Decoded, Wire; split; reflexivity.
 - destruct value as [value|]; [|exists None; split; reflexivity].
   destruct (IH value Supported) as [canonical [Decoded Wire]].
   cbn. destruct (encode_value element value) eqn:Encoded.
   all: try (exists None; split; reflexivity).
   all: exists (Some canonical); cbn; rewrite Decoded; split; [reflexivity|exact Wire].
 - destruct value as [text Member]; cbn -[in_dec]. destruct (in_dec string_dec text (first :: rest)) as [Inside|Outside].
   + eexists; split; reflexivity.
   + contradiction.
Qed.

Lemma decode_fields_ignores_other_name : forall description source name value,
 existsb (String.eqb name) (declared_names description) = false ->
 decode_fields description ((name,value) :: source) = decode_fields description source.
Proof.
 induction description as [|field rest IH]; intros source name value Absent; [reflexivity|].
 cbn in Absent; apply orb_false_iff in Absent as [Different Absent].
 cbn [decode_fields lookup]. rewrite String.eqb_sym, Different.
 rewrite IH by exact Absent. reflexivity.
Qed.
Definition protocol_schema (description : schema) := forallb (fun field => protocol_kinds (field_kind field)) description.
Theorem typed_fields_wire_is_decodable : forall description (values : fields description),
 schema_valid description = true -> protocol_schema description = true ->
 exists canonical,
 decode_fields description (encode_fields values) = Some canonical /\ encode_fields canonical = encode_fields values.
Proof.
 intros description values; induction values as [|field rest value values IH]; intros Unique Supported.
 - exists FNil; split; reflexivity.
 - cbn [schema_valid declared_names unique_names] in Unique.
   apply andb_true_iff in Unique as [Absent Unique]; apply negb_true_iff in Absent.
   cbn [protocol_schema] in Supported; apply andb_true_iff in Supported as [HeadSupported TailSupported].
   destruct (typed_field_wire_is_decodable (field_kind field) value HeadSupported) as [head [Head Wire]].
   destruct (IH Unique TailSupported) as [tail [Tail Wires]].
   exists (FCons head tail). cbn [decode_fields encode_fields lookup]. rewrite String.eqb_refl.
   rewrite decode_fields_ignores_other_name by exact Absent.
   rewrite Head, Tail, Wire, Wires. split; reflexivity.
Qed.
Lemma encoded_keys_are_declared : forall description (values : fields description),
 keys_declared description (encode_fields values) = true.
Proof.
 intros description values. unfold keys_declared, source_keys.
 rewrite Selvedge.Foundation.SchemaProofs.encode_declared_fields.
 apply forallb_forall; intros name Inside. apply existsb_exists; exists name; split; [exact Inside|apply String.eqb_refl].
Qed.
Theorem schema_wire_roundtrip : forall description (values : fields description),
 schema_valid description = true -> protocol_schema description = true ->
 exists canonical,
 Schema.decode description (Schema.encode description values) = Some canonical /\
 Schema.encode description canonical = Schema.encode description values.
Proof.
 intros description values Unique Supported.
 destruct (typed_fields_wire_is_decodable description values Unique Supported) as [canonical [Decoded Wire]].
 exists canonical. unfold Schema.decode, Schema.encode.
 unfold source_keys. rewrite Selvedge.Foundation.SchemaProofs.encode_declared_fields.
 rewrite encoded_keys_are_declared, Unique.
 change (unique_names (declared_names description) = true) in Unique. rewrite Unique. cbn. rewrite Decoded, Wire. split; reflexivity.
Qed.

From Selvedge.Generated Require Import Commands.
Module G := Selvedge.Generated.Commands.
Open Scope string_scope.
Fixpoint rebuild_fields (description : schema) : fields description -> fields description :=
 match description as description return fields description -> fields description with
 | [] => fun _ => FNil
 | field :: rest => fun values => FCons (head values) (rebuild_fields rest (tail values)) end.
Lemma rebuild_fields_identity : forall description (values : fields description),
 rebuild_fields description values = values.
Proof. intros description values; induction values; cbn; [reflexivity|rewrite IHvalues; reflexivity]. Qed.
Lemma encoded_fields_have_no_undeclared_tag : forall description (values : fields description),
 existsb (String.eqb "op") (declared_names description) = false ->
 Json.remove_field "op" (encode_fields values) = encode_fields values.
Proof.
 intros description values; induction values; intros Absent; [reflexivity|].
 cbn in Absent; apply orb_false_iff in Absent as [Different Absent].
 cbn; rewrite Different, IHvalues by exact Absent; reflexivity.
Qed.
Lemma declared_command_reaches_its_named_decoder : forall specification (values : fields (command_fields specification)),
 unique_names ("op" :: declared_names (command_fields specification)) = true ->
 G.decode (Schema.encode_declared specification values) =
 G.decode_named (command_name specification) (Schema.encode _ values).
Proof.
 intros specification values Unique.
 assert (NoTag : existsb (String.eqb "op") (declared_names (command_fields specification)) = false).
 { cbn in Unique. apply andb_true_iff in Unique as [H _]. now apply negb_true_iff in H. }
 change ((if unique_names ("op" :: map fst (encode_fields values)) then
   G.decode_named (command_name specification) (JObject (remove_field "op" (encode_fields values)))
   else None) = G.decode_named (command_name specification) (Schema.encode _ values)).
 rewrite Selvedge.Foundation.SchemaProofs.encode_declared_fields, Unique.
 rewrite encoded_fields_have_no_undeclared_tag by exact NoTag. reflexivity.

Qed.
