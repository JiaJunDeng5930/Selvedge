From Stdlib Require Import String List Bool NArith Lia.
From Selvedge.Foundation Require Import Json Schema SchemaProofs Utf8 Numbers NumbersProofs.
From Selvedge.Kernel Require Import ChatgptArguments.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.
Definition argument_values (command : string) (timeout maximum : N) : Schema.fields argument_declaration :=
 @Schema.FCons (Schema.Field "command" Schema.KText)
  [Schema.Field "timeout_ms" Schema.KNatural;Schema.Field "max_output_length" Schema.KNatural]
  command (@Schema.FCons (Schema.Field "timeout_ms" Schema.KNatural)
  [Schema.Field "max_output_length" Schema.KNatural] timeout
  (@Schema.FCons (Schema.Field "max_output_length" Schema.KNatural) [] maximum Schema.FNil)).
Lemma arguments_validity_survives_canonical_encoding : forall values,
 arguments_valid values = true -> valid_args (Schema.encode argument_declaration values) = true.
Proof.
 intros values Valid.
 rewrite (fields_eta _ values), (fields_eta _ (tail values)), (fields_eta _ (tail (tail values))),
   (fields_eta _ (tail (tail (tail values)))) in *.
 unfold valid_args, admit_args.
 cbv beta iota zeta delta -[parse_natural show_natural arguments_valid head tail].
 rewrite !natural_print_parse; cbn [option_map].
 unfold arguments_valid in *; cbn [head tail] in *.
 match goal with |- context [if ?condition then _ else _] =>
   assert (Checked : condition = true) by exact Valid; rewrite Checked; reflexivity end.
Qed.
Lemma bounded_arguments_have_a_valid_canonical_wire : forall command timeout maximum,
 negb (String.eqb command "")=true -> Utf8.well_formed command=true ->
 (N.of_nat (String.length command) <= 32768)%N ->
 (100 <= timeout <= 1800000)%N -> (1 <= maximum <= 8192)%N ->
 valid_args (Schema.encode argument_declaration (argument_values command timeout maximum))=true.
Proof.
 intros command timeout maximum Nonempty Utf8 Length Timeout Maximum.
 apply arguments_validity_survives_canonical_encoding.
 change ((((100 <=? timeout) && (timeout <=? 1800000)) &&
   ((1 <=? maximum) && (maximum <=? 8192))) &&
   negb (String.eqb command "") && Utf8.well_formed command &&
   (N.of_nat (String.length command) <=? 32768) = true).
 rewrite Nonempty, Utf8. repeat rewrite andb_true_iff.
 repeat split; try reflexivity; apply N.leb_le; lia.
Qed.
Lemma admitted_arguments_have_a_valid_canonical_wire : forall source decoded,
 admit_args source = Some decoded -> valid_args (Schema.encode argument_declaration decoded)=true.
Proof.
 intros source decoded Accepted; apply arguments_validity_survives_canonical_encoding.
 eapply admitted_arguments_are_valid; exact Accepted.
Qed.
