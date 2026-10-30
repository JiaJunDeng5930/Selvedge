From Stdlib Require Import String List Bool NArith Numbers.DecimalString Numbers.DecimalN.
From Selvedge.Foundation Require Import Json Numbers NumbersProofs Schema SchemaProofs.
Import ListNotations.

Definition natural_print_parse := NumbersProofs.natural_print_parse.
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
   destruct (IH Unique TailSupported) as [tail [Tail Wires]].
   destruct field as [name kind omittable]; destruct omittable;
     cbn [field_name field_kind] in Absent, HeadSupported.
   + destruct value as [value|].
     * destruct (typed_field_wire_is_decodable kind value HeadSupported) as [head [Head Wire]].
       exists (@FCons (FieldSpec name kind true) rest (Some head) tail).
       cbn [decode_fields encode_fields encode_field decode_field option_map lookup field_name].
       rewrite String.eqb_refl. rewrite decode_fields_ignores_other_name by exact Absent.
       rewrite Head, Tail, Wire, Wires. split; reflexivity.
     * exists (@FCons (FieldSpec name kind true) rest None tail).
       cbn [decode_fields encode_fields encode_field decode_field option_map field_name].
       rewrite (Selvedge.Foundation.SchemaProofs.encoded_lookup_is_absent rest values name Absent).
       rewrite Tail, Wires. split; reflexivity.
   + destruct (typed_field_wire_is_decodable kind value HeadSupported) as [head [Head Wire]].
     exists (@FCons (FieldSpec name kind false) rest head tail).
     cbn [decode_fields encode_fields encode_field decode_field option_map lookup field_name].
     rewrite String.eqb_refl. rewrite decode_fields_ignores_other_name by exact Absent.
     rewrite Head, Tail, Wire, Wires. split; reflexivity.
Qed.
Lemma encoded_keys_are_declared : forall description (values : fields description),
 keys_declared description (encode_fields values) = true.
Proof.
 intros description values. unfold keys_declared, source_keys.
 apply forallb_forall; intros name Inside. apply existsb_exists; exists name; split.
 - now apply (Selvedge.Foundation.SchemaProofs.encode_declared_fields description values).
 - apply String.eqb_refl.
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
 unfold source_keys. rewrite encoded_keys_are_declared, Unique.
 rewrite (Selvedge.Foundation.SchemaProofs.encoded_names_are_unique description values Unique).
 cbn. rewrite Decoded, Wire. split; reflexivity.
Qed.

Open Scope string_scope.
Fixpoint rebuild_fields (description : schema) : fields description -> fields description :=
 match description as description return fields description -> fields description with
 | [] => fun _ => FNil
 | field :: rest => fun values => FCons (head values) (rebuild_fields rest (tail values)) end.
Lemma rebuild_fields_identity : forall description (values : fields description),
 rebuild_fields description values = values.
Proof. intros description values; induction values; cbn; [reflexivity|rewrite IHvalues; reflexivity]. Qed.
