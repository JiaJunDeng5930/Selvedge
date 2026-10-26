From Stdlib Require Import String List Bool NArith Lia.
From Selvedge.Foundation Require Import Json Schema Utf8 Numbers NumbersProofs.
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
Lemma bounded_arguments_have_a_valid_canonical_wire : forall command timeout maximum,
 negb (String.eqb command "")=true -> Utf8.well_formed command=true ->
 (N.of_nat (String.length command) <= 32768)%N ->
 (100 <= timeout <= 1800000)%N -> (1 <= maximum <= 8192)%N ->
 valid_args (Schema.encode argument_declaration (argument_values command timeout maximum))=true.
Proof.
 intros command timeout maximum Nonempty Utf8 Length Timeout Maximum.
 unfold valid_args,admit_args,bounded_number,bounds,argument_values.
 cbv beta iota zeta delta -[parse_natural show_natural Utf8.well_formed N.leb].
 rewrite !natural_print_parse.
 cbn -[Utf8.well_formed N.leb].
 assert (LowerTimeout:(100<=?timeout)=true) by (apply N.leb_le;lia).
 assert (UpperTimeout:(timeout<=?1800000)=true) by (apply N.leb_le;lia).
 assert (LowerMaximum:(1<=?maximum)=true) by (apply N.leb_le;lia).
 assert (UpperMaximum:(maximum<=?8192)=true) by (apply N.leb_le;lia).
 assert (CommandLength:(N.of_nat (String.length command)<=?32768)=true) by (apply N.leb_le;exact Length).
 rewrite LowerTimeout,UpperTimeout,LowerMaximum,UpperMaximum.
 change ((match (if negb (String.eqb command "") && Utf8.well_formed command &&
  (N.of_nat (String.length command) <=? 32768)
  then Some (argument_values command timeout maximum) else None)
  with Some _=>true | None=>false end)=true).
 rewrite Nonempty,Utf8,CommandLength;reflexivity.
Qed.
Lemma admitted_arguments_have_a_valid_canonical_wire : forall source decoded,
 admit_args source = Some decoded -> valid_args (Schema.encode argument_declaration decoded)=true.
Proof.
 intros source decoded Accepted.
 unfold admit_args in Accepted.
 destruct (Schema.decode argument_declaration source) as [values|] eqn:Decoded; [|discriminate].
 destruct (bounded_number source "timeout_ms" && bounded_number source "max_output_length" &&
   match string_field "command" source with
   | Some command => negb (String.eqb command "") && Utf8.well_formed command &&
       (N.of_nat (String.length command) <=? 32768)
   | None => false end) eqn:Valid; [|discriminate].
 inversion Accepted; subst decoded.
 destruct source as [|boolean|numeric|text|items|members]; try discriminate Decoded.
 unfold Schema.decode in Decoded.
 destruct (schema_valid argument_declaration && unique_names (source_keys members) &&
   keys_declared argument_declaration members); [|discriminate].
 cbn [argument_declaration decode_fields decode_field Field field_name decode_value] in Decoded.
 destruct (lookup "command" members) as [command_json|] eqn:Command; [|discriminate].
 destruct command_json as [|boolean|numeric|command|items|fields]; try discriminate Decoded.
 destruct (lookup "timeout_ms" members) as [timeout_json|] eqn:TimeoutField; [|discriminate].
 destruct timeout_json as [|boolean|timeout_text|text|items|fields]; try discriminate Decoded.
 cbn [as_string as_number] in Decoded.
 destruct (parse_natural timeout_text) as [timeout|] eqn:Timeout; [|discriminate].
 destruct (lookup "max_output_length" members) as [maximum_json|] eqn:MaximumField; [|discriminate].
 destruct maximum_json as [|boolean|maximum_text|text|items|fields]; try discriminate Decoded.
 cbn [as_number] in Decoded.
 destruct (parse_natural maximum_text) as [maximum|] eqn:Maximum; [|discriminate].
 inversion Decoded; subst values.
 unfold bounded_number,number_field,string_field,field,bounds in Valid.
 rewrite Command,TimeoutField,MaximumField in Valid.
 cbn [as_number as_string] in Valid.
 rewrite Timeout,Maximum in Valid.
 change ((((100 <=? timeout) && (timeout <=? 1800000)) &&
   ((1 <=? maximum) && (maximum <=? 8192))) &&
   (negb (String.eqb command "") && Utf8.well_formed command &&
     (N.of_nat (String.length command) <=? 32768)) = true) in Valid.
 repeat rewrite andb_true_iff in Valid.
 apply bounded_arguments_have_a_valid_canonical_wire.
 - tauto.
 - tauto.
 - apply N.leb_le; tauto.
 - split; apply N.leb_le; tauto.
 - split; apply N.leb_le; tauto.
Qed.
