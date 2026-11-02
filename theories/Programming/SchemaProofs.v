From Stdlib Require Import String List Bool.
From Selvedge.Foundation Require Import Json.
From Selvedge.Programming Require Import Schema.
Import ListNotations.

Theorem encode_declared_fields : forall description (values : fields description),
  incl (map fst (encode_fields values)) (declared_names description).
Proof.
 intros description values; induction values as [|field rest value values IH].
 - intros name Inside; inversion Inside.
 - cbn [encode_fields declared_names]. destruct (encode_field field value); cbn.
   + intros name [Same|Inside]; [now left|right; now apply IH].
   + intros name Inside; right; now apply IH.
Qed.

Theorem encode_all_present_fields : forall description (values : fields description),
 forallb (fun field => negb (field_omittable field)) description = true ->
 map fst (encode_fields values) = declared_names description.
Proof.
 intros description values; induction values as [|field rest value values IH]; intros Present; [reflexivity|].
 destruct field as [name kind optional]; destruct optional; cbn in Present; try discriminate.
 cbn [encode_fields encode_field declared_names map field_name]. f_equal. now apply IH.
Qed.

Lemma encoded_name_is_absent : forall description (values : fields description) name,
 existsb (String.eqb name) (declared_names description) = false ->
 existsb (String.eqb name) (map fst (encode_fields values)) = false.
Proof.
 intros description values; induction values as [|field rest value values IH]; intros name Absent; [reflexivity|].
 cbn in Absent; apply Bool.orb_false_iff in Absent as [Different Absent].
 cbn [encode_fields]. destruct (encode_field field value); cbn; rewrite ?Different; now apply IH.
Qed.

Lemma encoded_lookup_is_absent : forall description (values : fields description) name,
 existsb (String.eqb name) (declared_names description) = false ->
 lookup name (encode_fields values) = None.
Proof.
 intros description values; induction values as [|field rest value values IH]; intros name Absent; [reflexivity|].
 cbn in Absent; apply Bool.orb_false_iff in Absent as [Different Absent].
 cbn [encode_fields]. destruct (encode_field field value); cbn; rewrite ?Different; now apply IH.
Qed.

Theorem encoded_names_are_unique : forall description (values : fields description),
 schema_valid description = true -> unique_names (map fst (encode_fields values)) = true.
Proof.
 intros description values; induction values as [|field rest value values IH]; intros Unique; [reflexivity|].
 cbn [schema_valid declared_names unique_names] in Unique.
 apply Bool.andb_true_iff in Unique as [Absent Unique]; apply Bool.negb_true_iff in Absent.
 cbn [encode_fields]. destruct (encode_field field value); cbn [map fst unique_names].
 - rewrite (encoded_name_is_absent rest values (field_name field) Absent), (IH Unique); reflexivity.
 - now apply IH.
Qed.

Theorem rejects_unknown_field : forall description source,
  keys_declared description source = false ->
  decode description (JObject source) = None.
Proof. intros; unfold decode; rewrite H; now rewrite !Bool.andb_false_r. Qed.

Theorem rejects_duplicate_fields : forall description source,
  unique_names (source_keys source) = false ->
  decode description (JObject source) = None.
Proof. intros; unfold decode; rewrite H; now rewrite Bool.andb_false_r. Qed.

Theorem rejects_duplicate_schema : forall description source,
  schema_valid description = false -> decode description source = None.
Proof. intros; destruct source; simpl; auto; now rewrite H. Qed.
