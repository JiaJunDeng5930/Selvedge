From Stdlib Require Import String List NArith DecimalString DecimalN DecimalPos.
From Selvedge.Foundation Require Import Json Numbers NumbersProofs.
From Selvedge.Foundation Require ArgumentDeclaration.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.
Module D := ArgumentDeclaration.
Lemma check_text_reflects : forall constraints source,
 D.check (D.Text constraints) (JString source) = D.check_text constraints source.
Proof.
 intros; unfold D.check; cbn [D.decode]; destruct (D.check_text constraints source); reflexivity.
Qed.
Definition natural_spelling_roundtrip := NumbersProofs.natural_print_parse.
Lemma natural_schema_interpreted : forall fuel lower upper,
 lower <= upper ->
 D.parse_fuel (S fuel) (D.schema (D.Natural lower upper)) = Some (D.Natural lower upper).
Proof.
 intros fuel lower upper Ordered.
 cbv beta iota zeta delta -[parse_natural show_natural N.leb].
 rewrite !natural_spelling_roundtrip.
 apply N.leb_le in Ordered.
 rewrite Ordered. reflexivity.
Qed.
Lemma unbounded_natural_schema_interpreted : forall fuel minimum,
 D.parse_fuel (S fuel) (D.schema (D.UnboundedNatural minimum)) = Some (D.UnboundedNatural minimum).
Proof.
 intros fuel minimum. cbv beta iota zeta delta -[parse_natural show_natural N.leb].
 rewrite natural_spelling_roundtrip. reflexivity.
Qed.
Lemma constrained_text_schema_interpreted : forall fuel lower upper bytes no_nul nonblank lower_hex,
 lower <= upper ->
 let constraints := D.TextConstraints lower upper bytes no_nul nonblank lower_hex None in
 D.parse_fuel (S fuel) (D.schema (D.Text constraints)) = Some (D.Text constraints).
Proof.
 intros fuel lower upper bytes no_nul nonblank lower_hex Ordered.
 destruct no_nul,nonblank,lower_hex;
 cbv beta iota zeta delta -[parse_natural show_natural N.leb];
 rewrite !natural_spelling_roundtrip;
 apply N.leb_le in Ordered; rewrite Ordered; reflexivity.
Qed.
Lemma bounded_array_schema_interpreted : forall fuel lower upper element,
 lower <= upper -> D.parse_fuel fuel (D.schema element) = Some element ->
 D.parse_fuel (S fuel) (D.schema (D.BoundedArray lower upper element)) =
 Some (D.BoundedArray lower upper element).
Proof.
 intros fuel lower upper element Ordered Parsed.
 cbv beta iota zeta delta -[parse_natural show_natural N.leb D.parse_fuel D.schema] in Parsed |- *.
 cbn [D.parse_fuel D.schema].
 cbv beta iota zeta delta -[parse_natural show_natural N.leb D.parse_fuel D.schema].
 rewrite !natural_spelling_roundtrip. cbn. rewrite Parsed.
 apply N.leb_le in Ordered. rewrite Ordered. reflexivity.
Qed.

Lemma array_schema_interpreted : forall fuel element,
 D.parse_fuel fuel (D.schema element) = Some element ->
 D.parse_fuel (S fuel) (D.schema (D.Array element)) = Some (D.Array element).
Proof.
 intros fuel element Parsed.
 cbn [D.parse_fuel D.schema].
 cbv beta iota zeta delta -[D.parse_fuel D.schema].
 rewrite Parsed. reflexivity.
Qed.
Lemma prefixed_text_schema_interpreted : forall fuel prefix suffix,
 D.parse_fuel fuel (D.schema suffix) = Some suffix ->
 D.parse_fuel (S fuel) (D.schema (D.PrefixedText prefix suffix)) = Some (D.PrefixedText prefix suffix).
Proof.
 intros fuel prefix suffix Parsed.
 cbn [D.parse_fuel D.schema].
 cbv beta iota zeta delta -[D.parse_fuel D.schema].
 rewrite Parsed. reflexivity.
Qed.
Lemma natural_text_schema_interpreted : forall fuel minimum maximum,
 (match maximum with None => True | Some maximum => minimum <= maximum end) ->
 D.parse_fuel (S fuel) (D.schema (D.NaturalText minimum maximum)) = Some (D.NaturalText minimum maximum).
Proof.
 intros fuel minimum [maximum|] Ordered;
 cbv beta iota zeta delta -[parse_natural show_natural N.leb];
 rewrite !natural_spelling_roundtrip; cbn; [|reflexivity].
 apply N.leb_le in Ordered. rewrite Ordered. reflexivity.
Qed.
Lemma traverse_parsed_schema : forall declarations fuel,
 Forall (fun declaration => D.parse_fuel fuel (D.schema declaration) = Some declaration) declarations ->
 D.traverse (D.parse_fuel fuel) (map D.schema declarations) = Some declarations.
Proof.
 intros declarations fuel All. unfold D.traverse in *. induction All; cbn; [reflexivity|].
 rewrite H,IHAll. reflexivity.
Qed.
Lemma union_schema_interpreted : forall fuel first rest,
 Forall (fun declaration => D.parse_fuel fuel (D.schema declaration) = Some declaration) (first::rest) ->
 D.parse_fuel (S fuel) (D.schema (D.Union (first::rest))) = Some (D.Union (first::rest)).
Proof.
 intros fuel first rest Parsed.
 cbn [D.parse_fuel D.schema].
 cbv beta iota zeta delta -[D.parse_fuel D.schema D.traverse List.map].
 rewrite (traverse_parsed_schema (first::rest) fuel Parsed). reflexivity.
Qed.

Lemma object_schema_fields_interpreted : forall fuel encoded required properties allow_extra,
 Schema.unique_names (map fst encoded) = true ->
 D.required_names encoded (Some (JArray (map JString required))) = Some required ->
 D.traverse (fun property => option_map
   (fun declaration => (fst property,D.member (fst property) required,declaration))
   (D.parse_fuel fuel (snd property))) encoded = Some properties ->
 D.parse_fuel (S fuel) (JObject [("type",JString "object");
   ("additionalProperties",JBool allow_extra);("properties",JObject encoded);
   ("required",JArray (map JString required))]) =
 Some (if allow_extra then D.OpenObject properties else D.Object properties).
Proof.
 intros fuel encoded required properties [|] Unique Required Parsed;
 cbn [D.parse_fuel];
 cbv beta iota zeta delta -[D.parse_fuel D.required_names D.traverse] in Unique,Required,Parsed |- *;
 rewrite Unique,Required,Parsed; reflexivity.
Qed.
Lemma traverse_object_parsed_schemas : forall fuel required properties,
 Forall (fun property =>
   D.parse_fuel fuel (D.schema (snd property)) = Some (snd property) /\
   D.member (fst (fst property)) required = snd (fst property)) properties ->
 D.traverse (fun property => option_map
   (fun declaration => (fst property,D.member (fst property) required,declaration))
   (D.parse_fuel fuel (snd property)))
   (map (fun property => (fst (fst property),D.schema (snd property))) properties) = Some properties.
Proof.
 intros fuel required properties All. unfold D.traverse in *. induction All; cbn; [reflexivity|].
 destruct H as [Parsed Required]. rewrite Parsed,Required,IHAll.
 destruct x as [[name needed] declaration]. reflexivity.
Qed.
Lemma quoted_names_parsed : forall names,
 D.strings (map JString names) = Some names.
Proof. induction names; cbn; [reflexivity|]. rewrite IHnames. reflexivity. Qed.
Lemma required_names_interpreted : forall encoded required,
 Schema.unique_names required = true ->
 forallb (fun name => D.member name (map fst encoded)) required = true ->
 D.required_names encoded (Some (JArray (map JString required))) = Some required.
Proof.
 intros encoded required Unique Declared. unfold D.required_names.
 rewrite quoted_names_parsed,Unique,Declared. reflexivity.
Qed.
Lemma object_schema_interpreted : forall fuel (properties : list (string * bool * D.t)) (allow_extra : bool),
 let encoded := map (fun property => (fst (fst property),D.schema (snd property))) properties in
 let required := map (fun property => fst (fst property)) (filter (fun property => snd (fst property)) properties) in
 Schema.unique_names (map fst encoded) = true ->
 D.required_names encoded (Some (JArray (map JString required))) = Some required ->
 Forall (fun property =>
   D.parse_fuel fuel (D.schema (snd property)) = Some (snd property) /\
   D.member (fst (fst property)) required = snd (fst property)) properties ->
 D.parse_fuel (S fuel) (D.schema (if allow_extra then D.OpenObject properties else D.Object properties)) =
 Some (if allow_extra then D.OpenObject properties else D.Object properties).
Proof.
 intros fuel properties allow_extra encoded required Unique Required Children.
 destruct allow_extra; cbn [D.schema];
 rewrite <- (map_map (fun property : string * bool * D.t => fst (fst property)) JString
   (filter (fun property => snd (fst property)) properties)).
 - apply (object_schema_fields_interpreted fuel encoded required properties true);
   [exact Unique|exact Required|]. apply traverse_object_parsed_schemas. exact Children.
 - apply (object_schema_fields_interpreted fuel encoded required properties false);
   [exact Unique|exact Required|]. apply traverse_object_parsed_schemas. exact Children.
Qed.

(** Built-in registries also discharge this condition: a legacy schema parser
    failure must not be mistaken for a valid declaration of an unusable tool. *)
Fixpoint reject_free (declaration : D.t) : bool := match declaration with
 | D.Reject => false
 | D.Array element | D.BoundedArray _ _ element | D.PrefixedText _ element => reject_free element
 | D.Object properties | D.OpenObject properties => forallb (fun property => reject_free (snd property)) properties
 | D.Union alternatives => forallb reject_free alternatives
 | _ => true end.
