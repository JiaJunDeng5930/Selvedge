From Stdlib Require Import String Ascii List Bool Arith Lia.
From Selvedge.Foundation Require Import Json Numbers Utf8 TextJson.
From Selvedge.Foundation Require Import TextJsonRoundtripTokens TextJsonRoundtripUtf8.
Import ListNotations.
Open Scope string_scope.
Open Scope nat_scope.

(* Validity is independent of the codec: strings are UTF-8 and numbers retain
   any accepted JSON number spelling. Object members have no uniqueness premise. *)
Fixpoint legal_json (value : json) : Prop :=
 match value with
 | JNull | JBool _ => True
 | JNumber text => number_lexeme text = true
 | JString text => Utf8.well_formed text = true
 | JArray values => fold_right (fun value rest => legal_json value /\ rest) True values
 | JObject members => fold_right (fun member rest => Utf8.well_formed (fst member) = true /\ legal_json (snd member) /\ rest) True members
 end.
(* This structural cost bounds token work without counting suffix bytes. The
   separate height records the parser's logical nesting budget. *)
Fixpoint render_cost (value : json) : nat :=
 match value with
 | JNull | JBool _ | JNumber _ => 1
 | JString text => S (String.length text)
 | JArray values => S (fold_right (fun value total => S (render_cost value) + total) 0 values)
 | JObject members => S (fold_right (fun member total => 4 + String.length (fst member) + render_cost (snd member) + total) 0 members)
 end.
Fixpoint json_height (value : json) : nat :=
 match value with
 | JArray values => S (fold_right (fun value height => Nat.max (json_height value) height) 0 values)
 | JObject members => S (fold_right (fun member height => Nat.max (json_height (snd member)) height) 0 members)
 | _ => 1
 end.
Definition json_suffix (text : string) : bool :=
 match text with EmptyString => true
 | String c _ => Ascii.eqb c "," || Ascii.eqb c "]" || Ascii.eqb c "}" end.

Lemma fold_reverse_map : forall (A B : Type) (f : A -> B) values reversed,
 fold_left (fun reversed value => f value :: reversed) values reversed =
 (List.rev (map f values) ++ reversed)%list.
Proof.
 intros A B f values. induction values as [|v vs IH]; intros reversed; cbn; [reflexivity|].
 rewrite IH. cbn. rewrite <- List.app_assoc. reflexivity.
Qed.
Lemma render_values : forall values,
 render_json (JArray values) = "[" ++ String.concat "," (map render_json values) ++ "]".
Proof.
 intros values. cbn [render_json]. rewrite fold_reverse_map, List.app_nil_r.
 rewrite <- List.rev_alt, List.rev_involutive. reflexivity.
Qed.
Lemma render_members : forall members,
 render_json (JObject members) = "{" ++ String.concat ","
 (map (fun member => quote (fst member) ++ ":" ++ render_json (snd member)) members) ++ "}".
Proof.
 intros members. cbn [render_json]. rewrite fold_reverse_map, List.app_nil_r.
 rewrite <- List.rev_alt, List.rev_involutive. reflexivity.
Qed.
Lemma json_induction : forall P : json -> Prop,
 P JNull -> (forall b, P (JBool b)) -> (forall n, P (JNumber n)) ->
 (forall s, P (JString s)) ->
 (forall values, Forall P values -> P (JArray values)) ->
 (forall members, Forall (fun member => P (snd member)) members -> P (JObject members)) ->
 forall value, P value.
Proof.
 intros P Null Bool Number Text Array Object. fix recur 1. intro value. destruct value.
 - exact Null.
 - apply Bool.
 - apply Number.
 - apply Text.
 - apply Array. induction values; constructor; auto.
 - apply Object. induction fields as [|[key value] rest IH]; constructor; auto.
Qed.
Lemma render_initial : forall value,
 legal_json value -> exists c rest,
 render_json value = String c rest /\ whitespace c = false /\
 Ascii.eqb c "]" = false /\ Ascii.eqb c "}" = false.
Proof.
 intros value Legal. destruct value; cbn in *.
 - eexists; eexists. repeat split; reflexivity.
 - destruct value; eexists; eexists; repeat split; reflexivity.
 - apply number_lexeme_initial in Legal as [c [rest [Shape First]]].
   exists c,rest. split; [exact Shape|]. now apply number_initial_delimiters in First as (?&?&?&?&?&?&?&?&?).
 - eexists; eexists. repeat split; reflexivity.
 - eexists; eexists. repeat split; reflexivity.
 - eexists; eexists. repeat split; reflexivity.
Qed.
Lemma render_trim : forall value suffix,
 legal_json value -> trim_left (render_json value ++ suffix) = render_json value ++ suffix.
Proof.
 intros value suffix Legal. destruct (render_initial value Legal) as [c [rest [Shape [Space _]]]].
 rewrite Shape. cbn [String.append trim_left]. now rewrite Space.
Qed.
Lemma json_suffix_number : forall suffix,
 json_suffix suffix = true ->
 (match suffix with EmptyString => true | String c _ => negb (number_char c) end) = true.
Proof.
 intros [|[a b c d e f g h] rest]; [reflexivity|].
 destruct a,b,c,d,e,f,g,h; vm_compute; intros; congruence.
Qed.
Lemma concat_comma_cons : forall head tail,
 String.concat "," (head :: tail) = head ++ match tail with [] => "" | _ => "," ++ String.concat "," tail end.
Proof. intros head [|second tail]; cbn; [symmetry; apply string_append_nil|reflexivity]. Qed.

Lemma array_items_roundtrip : forall next values,
 Forall (fun value => legal_json value /\ forall suffix,
   json_suffix suffix = true -> next (render_json value ++ suffix) = Scanned value suffix) values ->
 forall fuel reversed suffix,
 List.length values < fuel ->
 array_items next fuel (String.concat "," (map render_json values) ++ "]" ++ suffix) reversed =
 Scanned (List.rev_append reversed values) suffix.
Proof.
 intros next values Ready. induction Ready as [|value values [Legal Scan] Ready IH];
 intros [|fuel] reversed suffix Budget; cbn [List.length] in Budget; try lia.
 - cbn [map String.concat String.append array_items trim_left]. reflexivity.
 - rewrite map_cons, concat_comma_cons.
   rewrite <- string_append_assoc.
   destruct (render_initial _ Legal) as [c [rest [Shape [Space [Close _]]]]].
   cbn [array_items]. rewrite (render_trim _ _ Legal), Shape.
   cbn [String.append]. rewrite Close.
   destruct values as [|second tail].
   + cbn [map String.concat String.append]. specialize (Scan ("]" ++ suffix) eq_refl).
     rewrite Shape in Scan. cbn [String.append map String.concat] in Scan. rewrite Scan.
     cbn [String.append trim_left]. cbn [List.rev_append]. reflexivity.
   + cbn [map String.append]. specialize (Scan ("," ++ String.concat "," (map render_json (second :: tail)) ++ "]" ++ suffix) eq_refl).
     rewrite Shape in Scan. cbn [String.append map] in Scan. rewrite Scan.
     cbn -[String.concat map render_json array_items].
     inversion Ready as [|? ? [NextLegal NextScan] _]; subst.
     destruct (render_initial _ NextLegal) as [d [more [NextShape [NextSpace [NextClose _]]]]].
     rewrite concat_comma_cons, <- string_append_assoc.
     rewrite (render_trim _ _ NextLegal), NextShape. cbn [String.append trim_left]. rewrite NextClose.
     pose proof (IH fuel (value :: reversed) suffix ltac:(cbn in *; lia)) as TailScan.
     rewrite map_cons, concat_comma_cons, <- string_append_assoc, NextShape in TailScan.
     cbn [String.append] in TailScan. rewrite TailScan.
     cbn [List.rev_append]. reflexivity.
Qed.

Definition member_text (member : string * json) := quote (fst member) ++ ":" ++ render_json (snd member).
Lemma quote_shape : forall text, quote text = String """" (escape_string text ++ """").
Proof. reflexivity. Qed.
Lemma member_text_trim : forall key value suffix,
 trim_left (member_text (key,value) ++ suffix) = member_text (key,value) ++ suffix.
Proof. intros. reflexivity. Qed.
Lemma object_members_roundtrip : forall next token_budget members,
 Forall (fun member => String.length (fst member) < token_budget /\ forall suffix,
   json_suffix suffix = true -> next (render_json (snd member) ++ suffix) = Scanned (snd member) suffix) members ->
 forall fuel seen reversed suffix,
 List.length members < fuel ->
 object_members false next token_budget fuel seen
 (String.concat "," (map member_text members) ++ "}" ++ suffix) reversed =
 Scanned (List.rev_append reversed members) suffix.
Proof.
 intros next token_budget members Ready. induction Ready as [|[key value] members [KeyBudget Scan] Ready IH];
 intros [|fuel] seen reversed suffix Budget; cbn [List.length] in Budget; try lia.
 - reflexivity.
 - rewrite map_cons, concat_comma_cons, <- string_append_assoc.
   cbn [object_members]. rewrite member_text_trim.
   unfold member_text at 1. cbn [fst snd]. rewrite quote_shape.
   cbn -[quoted object_members String.concat map render_json].
   pose proof (quoted_quote key token_budget
     (":" ++ render_json value ++ (match map member_text members with [] => "" | _ => "," ++ String.concat "," (map member_text members) end) ++ "}" ++ suffix)
     KeyBudget) as KeyScan.
   rewrite quote_shape in KeyScan. unfold escape_string in KeyScan.
   repeat rewrite <- string_append_assoc in KeyScan.
   repeat rewrite <- string_append_assoc.
   cbn [String.append] in KeyScan |- *.
   repeat rewrite <- string_append_assoc in KeyScan.
   repeat rewrite <- string_append_assoc.
   cbn [String.append] in KeyScan |- *. rewrite KeyScan.
   cbn -[object_members String.concat map render_json].
   try rewrite <- string_append_assoc. rewrite Scan.
   2: { destruct members; reflexivity. }
   destruct members as [|[nextkey nextvalue] tail].
   + cbn -[object_members render_json]. reflexivity.
   + cbn -[object_members String.concat map render_json member_text quote].
     rewrite map_cons, concat_comma_cons.
     cbn -[object_members String.concat map render_json member_text quote].
     try rewrite <- string_append_assoc. rewrite member_text_trim. unfold member_text at 1. cbn [fst snd]. rewrite quote_shape.
     cbn -[object_members String.concat map render_json].
     pose proof (IH fuel (key :: seen) ((key,value) :: reversed) suffix ltac:(cbn in *; lia)) as TailScan.
     rewrite map_cons, concat_comma_cons, <- string_append_assoc in TailScan.
     unfold member_text at 1 in TailScan. cbn [fst snd] in TailScan. rewrite quote_shape in TailScan.
     unfold escape_string in TailScan.
     repeat rewrite <- string_append_assoc in TailScan.
     repeat rewrite <- string_append_assoc.
     cbn [String.append] in TailScan |- *.
     repeat rewrite <- string_append_assoc in TailScan.
     repeat rewrite <- string_append_assoc.
     cbn [String.append] in TailScan |- *. rewrite TailScan. reflexivity.
Qed.

Lemma legal_array_forall : forall values,
 legal_json (JArray values) <-> Forall legal_json values.
Proof.
 induction values; cbn; [split; constructor|]. rewrite IHvalues. split.
 - intros [Head Rest]. now constructor.
 - intros H. inversion H; tauto.
Qed.
Lemma legal_object_forall : forall members,
 legal_json (JObject members) <-> Forall (fun member => Utf8.well_formed (fst member) = true /\ legal_json (snd member)) members.
Proof.
 induction members as [|[key value] rest IH]; cbn; [split; constructor|].
 rewrite IH. split.
 - intros [Key [Value Rest]]. constructor; tauto.
 - intros H. inversion H. tauto.
Qed.
Lemma array_costs : forall values,
 List.length values <= fold_right (fun value total => S (render_cost value) + total) 0 values /\
 forall value, In value values ->
 render_cost value < render_cost (JArray values) /\ json_height value < json_height (JArray values).
Proof.
 induction values as [|head tail [Length IH]]; cbn in *; split; try lia.
 intros value [Same|Present].
 - subst value. split; [lia|]. pose proof (Nat.le_max_l (json_height head) (fold_right (fun value height => Nat.max (json_height value) height) 0 tail)). lia.
 - specialize (IH value Present). cbn in IH. split; [lia|].
     pose proof (Nat.le_max_r (json_height head) (fold_right (fun value height => Nat.max (json_height value) height) 0 tail)). lia.
Qed.
Lemma object_costs : forall members,
 List.length members <= fold_right (fun member total => 4 + String.length (fst member) + render_cost (snd member) + total) 0 members /\
 forall key value, In (key,value) members ->
 String.length key < render_cost (JObject members) /\
 render_cost value < render_cost (JObject members) /\ json_height value < json_height (JObject members).
Proof.
 induction members as [|[key head] tail [Length IH]]; cbn in *; split; try lia.
 intros name value [Same|Present].
 - inversion Same; subst. repeat split; try lia.

 - specialize (IH name value Present). cbn in IH. repeat split; try lia.

Qed.

(* Keeping the untouched suffix in the conclusion lets container proofs reuse
   this theorem for each value, including repeated object member names. *)
Theorem rendered_value_scans : forall value,
 legal_json value -> forall fuel nesting suffix,
 render_cost value < fuel -> json_height value <= nesting -> json_suffix suffix = true ->
 json_value_at false fuel nesting (render_json value ++ suffix) = Scanned value suffix.
Proof.
 refine (json_induction (fun value => legal_json value -> forall fuel nesting suffix,
   render_cost value < fuel -> json_height value <= nesting -> json_suffix suffix = true ->
   json_value_at false fuel nesting (render_json value ++ suffix) = Scanned value suffix) _ _ _ _ _ _).
 - intros _ [|fuel] [|nesting] suffix Budget Depth End; cbn in Budget,Depth; try lia. reflexivity.
 - intros [|] _ [|fuel] [|nesting] suffix Budget Depth End; cbn in Budget,Depth; try lia; reflexivity.
 - intros text Valid [|fuel] [|nesting] suffix Budget Depth End; cbn in Budget,Depth; try lia.
   destruct (number_lexeme_initial _ Valid) as [c [rest [Shape Initial]]].
   pose proof (number_initial_delimiters _ Initial) as [Space [Quote [Array [Object [CloseA [CloseO [True [False Null]]]]]]]].
   change (json_value_at false (S fuel) (S nesting) (text ++ suffix) = Scanned (JNumber text) suffix).
   cbn [json_value_at consume_input_nesting]. rewrite Shape. cbn [String.append trim_left]. rewrite Space.
   rewrite Quote, Array, Object, True, False, Null.
   pose proof (scan_number_lexeme text suffix Valid (json_suffix_number _ End)) as Number.
   rewrite Shape in Number. cbn [String.append] in Number. rewrite Number, <- Shape, Valid. reflexivity.
 - intros text Valid [|fuel] [|nesting] suffix Budget Depth End; cbn [render_cost json_height] in Budget,Depth; try lia.
   change (json_value_at false (S fuel) (S nesting) (quote text ++ suffix) = Scanned (JString text) suffix).
   pose proof (quoted_quote text fuel suffix ltac:(lia)) as Parsed.
   rewrite quote_shape in Parsed |- *. unfold quoted in Parsed.
   cbn -[quoted_body scan_map escape_string].
   cbn -[quoted_body scan_map escape_string] in Parsed. rewrite Parsed. reflexivity.
 - intros values Children Legal [|fuel] [|nesting] suffix Budget Depth End; try (cbn in Budget,Depth; lia).
   pose proof (array_costs values) as [Length Bounds].
   apply legal_array_forall in Legal.
   assert (Ready : Forall (fun value => legal_json value /\ forall suffix,
     json_suffix suffix = true -> json_value_at false fuel nesting (render_json value ++ suffix) = Scanned value suffix) values).
   { apply Forall_forall. intros value Present. split.
     - now apply (proj1 (Forall_forall _ _) Legal).
     - intros tail TailEnd. apply (proj1 (Forall_forall _ _) Children value Present).
       + now apply (proj1 (Forall_forall _ _) Legal).
       + specialize (Bounds value Present). lia.
       + specialize (Bounds value Present). lia.
       + exact TailEnd. }
   rewrite render_values. cbn -[array_items map String.concat render_json].
   repeat rewrite <- string_append_assoc.
   rewrite array_items_roundtrip by (assumption || (cbn [render_cost] in Budget; lia)). reflexivity.
 - intros members Children Legal [|fuel] [|nesting] suffix Budget Depth End; try (cbn in Budget,Depth; lia).
   pose proof (object_costs members) as [Length Bounds].
   apply legal_object_forall in Legal.
   assert (Ready : Forall (fun member => String.length (fst member) < fuel /\ forall suffix,
     json_suffix suffix = true -> json_value_at false fuel nesting (render_json (snd member) ++ suffix) = Scanned (snd member) suffix) members).
   { apply Forall_forall. intros [key value] Present. cbn. split.
     - specialize (Bounds key value Present). lia.
     - intros tail TailEnd. apply (proj1 (Forall_forall _ _) Children (key,value) Present).
       + exact (proj2 (proj1 (Forall_forall _ _) Legal (key,value) Present)).
       + cbn [fst snd]. specialize (Bounds key value Present). lia.
       + cbn [fst snd]. specialize (Bounds key value Present). lia.
       + exact TailEnd. }
   rewrite render_members. cbn -[object_members map String.concat render_json].
   repeat rewrite <- string_append_assoc.
   change (scan_map JObject (object_members false (json_value_at false fuel nesting) fuel fuel []
     (String.concat "," (map member_text members) ++ "}" ++ suffix) []) = Scanned (JObject members) suffix).
   rewrite object_members_roundtrip by (assumption || (cbn [render_cost] in Budget; lia)). reflexivity.
Qed.

Lemma concat_well_formed : forall separator values,
 Utf8.well_formed separator = true -> Forall (fun text => Utf8.well_formed text = true) values ->
 Utf8.well_formed (String.concat separator values) = true.
Proof.
 intros separator values Separator Valid. induction Valid as [|head tail Head Tail IH]; [reflexivity|].
 destruct tail; cbn [String.concat] in *; [exact Head|].
 repeat apply well_formed_append; assumption.
Qed.
Lemma concat_cost_bound : forall (A : Type) (render : A -> string) (cost : A -> nat) values,
 Forall (fun value => cost value <= String.length (render value)) values ->
 fold_right (fun value total => S (cost value) + total) 0 values <=
 S (String.length (String.concat "," (map render values))).
Proof.
 intros A render cost values Ready. induction Ready as [|value values Head Tail IH]; [cbn; lia|].
 destruct values as [|next tail].
 - cbn [fold_right map String.concat] in *. lia.
 - cbn [fold_right map]. rewrite concat_comma_cons.
   rewrite string_length_append. cbn [String.length].
   change (S (cost value) + fold_right (fun value total => S (cost value) + total) 0 (next :: tail) <=
     S (String.length (render value) + S (String.length (String.concat "," (map render (next :: tail)))))).
   lia.
Qed.
Lemma quote_length : forall text,
 S (S (String.length text)) <= String.length (quote text).
Proof.
 intro text. unfold quote. rewrite escape_string_spec.
 cbn [String.append String.length]. rewrite string_length_append. cbn [String.length].
 pose proof (escaped_length text). lia.
Qed.

Theorem rendered_value_properties : forall value,
 legal_json value -> Utf8.well_formed (render_json value) = true /\
 render_cost value <= String.length (render_json value).
Proof.
 refine (json_induction (fun value => legal_json value ->
   Utf8.well_formed (render_json value) = true /\ render_cost value <= String.length (render_json value)) _ _ _ _ _ _).
 - intros _. split; [reflexivity|cbn; lia].
 - intros [|] _; split; try reflexivity; cbn; lia.
 - intros text Legal. split; [now apply number_lexeme_well_formed|].
   destruct (number_lexeme_initial _ Legal) as [c [rest [Shape _]]]. rewrite Shape. cbn. lia.
 - intros text Legal. split; [now apply quote_well_formed|].
   pose proof (quote_length text). cbn [render_cost render_json]. lia.
 - intros values Children Legal. apply legal_array_forall in Legal.
   assert (Ready : Forall (fun value => Utf8.well_formed (render_json value) = true /\ render_cost value <= String.length (render_json value)) values).
   { apply Forall_forall. intros value Present. apply (proj1 (Forall_forall _ _) Children value Present).
     now apply (proj1 (Forall_forall _ _) Legal). }
   rewrite render_values. split.
   + repeat apply well_formed_append; try reflexivity. apply concat_well_formed; [reflexivity|].
     apply Forall_map, Forall_forall. intros value Present. exact (proj1 (proj1 (Forall_forall _ _) Ready value Present)).
   + pose proof (concat_cost_bound _ render_json render_cost values) as Bound.
     assert (Costs : Forall (fun value => render_cost value <= String.length (render_json value)) values).
     { eapply Forall_impl; [|exact Ready]. intros value H. exact (proj2 H). }
     specialize (Bound Costs). cbn [render_cost String.append String.length].
     rewrite string_length_append. cbn [String.length]. lia.
 - intros members Children Legal. apply legal_object_forall in Legal.
   assert (Ready : Forall (fun member => Utf8.well_formed (member_text member) = true /\
     3 + String.length (fst member) + render_cost (snd member) <= String.length (member_text member)) members).
   { apply Forall_forall. intros [key value] Present.
     pose proof (proj1 (Forall_forall _ _) Children (key,value) Present) as Child.
     pose proof (proj1 (Forall_forall _ _) Legal (key,value) Present) as [Key Value].
     specialize (Child Value). cbn [fst snd] in *. unfold member_text. cbn [fst snd]. split.
     - apply well_formed_append; [now apply quote_well_formed|].
       apply well_formed_append; [reflexivity|exact (proj1 Child)].
     - repeat rewrite string_length_append. cbn [String.length]. pose proof (quote_length key). lia. }
   rewrite render_members. change (Utf8.well_formed ("{" ++ String.concat "," (map member_text members) ++ "}") = true /\ render_cost (JObject members) <= String.length ("{" ++ String.concat "," (map member_text members) ++ "}")).
   split.
   + repeat apply well_formed_append; try reflexivity. apply concat_well_formed; [reflexivity|].
     apply Forall_map, Forall_forall. intros member Present. exact (proj1 (proj1 (Forall_forall _ _) Ready member Present)).
   + pose proof (concat_cost_bound _ member_text (fun member => 3 + String.length (fst member) + render_cost (snd member)) members) as Bound.
     assert (Costs : Forall (fun member => 3 + String.length (fst member) + render_cost (snd member) <= String.length (member_text member)) members).
     { eapply Forall_impl; [|exact Ready]. intros member H. exact (proj2 H). }
     specialize (Bound Costs). cbn [render_cost String.append String.length].
     rewrite string_length_append. cbn [String.length]. cbn in Bound |- *. lia.
Qed.

Theorem parse_render_members_at : forall value nesting,
 legal_json value -> json_height value <= nesting ->
 parse_json_members_at nesting (render_json value) = Some value.
Proof.
 intros value nesting Legal Depth.
 pose proof (rendered_value_properties value Legal) as [Utf8 Cost].
 pose proof (rendered_value_scans value Legal (S (String.length (render_json value))) nesting "" ltac:(lia) Depth eq_refl) as Parsed.
 rewrite string_append_nil in Parsed.
 unfold parse_json_members_at. rewrite Utf8, Parsed. reflexivity.
Qed.
