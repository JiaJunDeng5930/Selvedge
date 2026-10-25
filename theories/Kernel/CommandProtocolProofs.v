From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema SchemaProofs.
From Selvedge.Kernel Require Import ProtocolProofs CommandDeclarations.
From Selvedge.Generated Require Import Commands.
Module G := Selvedge.Generated.Commands.

(* The case references come from the same MetaRocq declaration derivation as
   the executable command constructors, rather than a second protocol list. *)
Ltac prove_payload_codec description to_fields from_fields constructor payload :=
 let canonical := fresh "canonical" in
 let Decoded := fresh "Decoded" in let Wire := fresh "Wire" in
 destruct (schema_wire_roundtrip description (to_fields payload) eq_refl eq_refl)
  as [canonical [Decoded Wire]];
 exists (constructor (from_fields canonical)); split;
 [ cbn [G.encode];
   rewrite declared_command_reaches_its_named_decoder by reflexivity;
   change (option_map constructor (option_map from_fields
    (Schema.decode description (Schema.encode description (to_fields payload)))) =
    Some (constructor (from_fields canonical)));
   rewrite Decoded; reflexivity
 | split; [reflexivity|];
   cbn [G.declared_payload];
   let Eta := fresh "Eta" in
   assert (Eta : to_fields (from_fields canonical) = canonical) by
    (change (rebuild_fields description canonical = canonical); apply rebuild_fields_identity);
   rewrite Eta; unfold Schema.encode in Wire; injection Wire as Wire; exact Wire ].

Theorem actual_command_codec_preserves_declared_payload : forall command,
 CommandDeclarations.valid true (G.encode command) = true ->
 exists canonical,
 G.decode (G.encode command) = Some canonical /\
 G.declared_command canonical = G.declared_command command /\
 G.declared_payload canonical = G.declared_payload command.
Proof.
 intros command Admitted. rewrite G.decode_observed_declaration, Admitted.
 destruct command; G.command_payload_case prove_payload_codec.
Qed.

(* This independently fixes the actual encoder to the declaration and original
   payload: the codec theorem cannot be satisfied by discarding all fields. *)
Theorem actual_command_encoding_has_original_fields : forall command,
 G.encode command = JObject (("op", JString (command_name (G.declared_command command))) :: G.declared_payload command).
Proof. apply G.encode_declared_wire. Qed.

Definition command_body (source : json) := match source with
 | JObject fields => JObject (remove_field "op" fields) | _ => JNull end.

(* Conversely, accepted external input is decoded by exactly the schema named
   by its tag, and every resulting field comes from that schema decoder. *)
Theorem accepted_command_uses_its_declared_field_decoder : forall source command,
 G.decode source = Some command ->
 exists values : fields (command_fields (G.declared_command command)),
 Schema.decode (command_fields (G.declared_command command)) (command_body source) = Some values /\
 G.declared_payload command = encode_fields values /\
 string_field "op" source = Some (command_name (G.declared_command command)).
Proof.
 intros source command Accepted; destruct source as [|boolean|number|text|array|source_fields]; try discriminate.
 rewrite G.decode_observed_declaration in Accepted.
 destruct (CommandDeclarations.valid true (JObject source_fields)); try discriminate.
 unfold G.decode_admitted in Accepted.
 destruct (unique_names (source_keys source_fields)); try discriminate.
 destruct (lookup "op" source_fields) as [tag|] eqn:Tag; try discriminate.
 destruct tag; try discriminate.
 unfold G.decode_named in Accepted.
 repeat match type of Accepted with
 | context [if String.eqb ?name ?declared then _ else _] =>
   let Matched := fresh "Matched" in destruct (String.eqb name declared) eqn:Matched;
   [ apply String.eqb_eq in Matched; subst name | ]
 end;
 match type of Accepted with
 | option_map ?constructor (?decoder ?body) = Some command =>
   unfold decoder in Accepted;
   match type of Accepted with
   | context [Schema.decode ?description ?body] =>
     let values := fresh "values" in let Decoded := fresh "Decoded" in
     destruct (Schema.decode description body) as [values|] eqn:Decoded; try discriminate;
     cbn in Accepted; inversion Accepted; subst command;
     exists values; split; [exact Decoded|]; split;
     [ change (encode_fields (rebuild_fields description values) = encode_fields values);
       rewrite rebuild_fields_identity; reflexivity
     | unfold string_field, field; rewrite Tag; reflexivity ]
   end
 | None = Some _ => discriminate
 end.
Qed.
