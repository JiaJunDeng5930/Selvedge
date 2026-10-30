From Stdlib Require Import String List Bool NArith Lia.
From Selvedge.Foundation Require Import Json JsonProofs NumbersProofs RegistryProofs Schema.
From Selvedge.Kernel Require Import Domain State Numbers Codec FeatureRequestAdmission TicketedRequest.
From Selvedge.Features Require Import Domain BoardFacts BoardParameters Observation Titles.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.
Module F := Selvedge.Features.Domain.
Module S := TicketedRequest.Scoped.

Lemma printed_identity_is_canonical : forall value,
 BoardParameters.text_id (F.decimal_text value) = Some value.
Proof.
 intros value; unfold BoardParameters.text_id, natural, F.decimal_text.
 change (match Selvedge.Foundation.Numbers.parse_natural
   (Selvedge.Foundation.Numbers.show_natural value) with
 | Some found => if String.eqb (Selvedge.Foundation.Numbers.show_natural value)
   (Selvedge.Foundation.Numbers.show_natural found) then Some found else None
 | None => None end = Some value).
 now rewrite natural_print_parse,String.eqb_refl.
Qed.

Lemma parsed_attachment_is_serializable : forall raw file,
 BoardParameters.attachment raw = Some file ->
 BoardParameters.attachment (Observation.attachment_json file) = Some file.
Proof.
 intros raw file Parsed; unfold BoardParameters.attachment in Parsed.
 destruct (Schema.decode BoardParameters.attachment_schema raw) as [values|]; [|discriminate].
 destruct (match head (tail (tail (tail (tail values)))) with
   Some text => BoardParameters.text_id text | None => Some 0 end) as [count|]; [|discriminate].
 destruct (_ && _) eqn:Valid; [|discriminate]. inversion Parsed; subst file.
 unfold BoardParameters.attachment,Observation.attachment_json.
 cbn -[BoardParameters.text_id Nat.eqb String.length nonempty BoardParameters.limited
   String.prefix N.leb F.decimal_text].
 rewrite printed_identity_is_canonical.
 match goal with |- (if ?condition then _ else _) = _ =>
   assert (Ready : condition = true) by exact Valid; now rewrite Ready end.
Qed.

Lemma parsed_attachments_are_serializable : forall raw files,
 Codec.traverse BoardParameters.attachment raw = Some files ->
 forallb (fun file => match BoardParameters.attachment (Observation.attachment_json file) with
   Some _ => true | None => false end) files = true.
Proof.
 induction raw as [|source rest IH]; intros files Parsed; cbn in Parsed.
 - inversion Parsed; reflexivity.
 - fold (Codec.traverse BoardParameters.attachment rest) in Parsed.
   destruct (BoardParameters.attachment source) as [file|] eqn:File; [|discriminate].
   destruct (Codec.traverse BoardParameters.attachment rest) as [remaining|] eqn:Rest; [|discriminate].
   inversion Parsed; subst files; cbn -[BoardParameters.attachment Observation.attachment_json].
   rewrite (parsed_attachment_is_serializable source file File), (IH remaining eq_refl); reflexivity.
Qed.

Definition lookup id before :=
 match registry_at id (F.board_cards (F.feature_board (world_features before))) with
 | Some card => card | None => None end.
Record card_reference (before : world) (id : N) := CardReference {
 selected_card : F.card;
 selected_card_found : lookup id before = Some selected_card
}.
Arguments CardReference {before id}.
Arguments selected_card {before id}.
Arguments selected_card_found {before id}.

Lemma reference_slot : forall before id (reference : card_reference before id),
 registry_at id (F.board_cards (F.feature_board (world_features before))) =
 Some (Some (selected_card reference)).
Proof.
 intros before id [card Found]; cbn in *; unfold lookup in Found.
 destruct (registry_at id _) as [[current|]|] eqn:At; try discriminate.
 inversion Found; reflexivity.
Qed.

Definition prompt card retitle before := Titles.board_prompt
 (F.title_task_prompt (F.feature_title_settings (world_features before)))
 (F.draft_title (F.card_contents card)) (F.draft_description (F.card_contents card)) retitle.
Record drafting_target (before : world) := DraftingTarget {
 target_id : N;
 target_card : F.card;
 target_retitle : bool;
 target_position : (target_id <=? N.of_nat (List.length
   (F.board_cards (F.feature_board (world_features before))))) = true;
 target_scope : forall selected,
   FeatureRequestAdmission.registered_profile selected before = true ->
   FeatureRequestAdmission.ordinary_profile selected = true ->
   FeatureRequestAdmission.card target_id target_card selected
     (prompt target_card target_retitle before) target_retitle before = true
}.
Arguments DraftingTarget {before}.
Arguments target_id {before}.
Arguments target_card {before}.
Arguments target_retitle {before}.
Arguments target_position {before}.
Arguments target_scope {before}.

Definition fresh_card draft now := F.Card 0 draft None false now now F.NoEnrichment "" false.
Definition fresh_id before := N.of_nat (List.length (F.board_cards (F.feature_board (world_features before)))).
Definition live_count before := List.length (filter (fun card => match card with
 Some _ => true | None => false end) (F.board_cards (F.feature_board (world_features before)))).

Definition fresh_target before draft now
 (Clock : (now <=? 4294967295) = true)
 (Draft : BoardFacts.valid_draft draft before = true)
 (Files : forallb (fun file => match BoardParameters.attachment (Observation.attachment_json file) with
   Some _ => true | None => false end) (F.draft_attachments draft) = true)
 (Capacity : Nat.ltb (live_count before) 512 = true)
 (Identity : (fresh_id before <? 4294967295) = true) : drafting_target before.
Proof.
 refine (DraftingTarget (fresh_id before) (fresh_card draft now) false _ _).
 - apply N.leb_refl.
 - intros selected Registered Ordinary.
   unfold FeatureRequestAdmission.card,prompt,fresh_card; cbn [F.card_updated F.card_contents].
   rewrite Registered,Ordinary,Clock,String.eqb_refl.
   unfold fresh_id; rewrite N.eqb_refl,Draft,Files.
   change (FeatureRequestAdmission.new_card (fresh_card draft now) &&
     (fresh_id before <? 4294967295) && Nat.ltb (live_count before) 512 = true).
   unfold FeatureRequestAdmission.new_card,BoardFacts.unlinked,fresh_card; cbn.
   rewrite N.eqb_refl,Identity. exact Capacity.
Defined.

Definition revised_target before id (reference : card_reference before id) now
 (Clock : (now <=? 4294967295) = true)
 (Mutable : BoardFacts.mutable (selected_card reference) before = true) : drafting_target before.
Proof.
 pose proof (reference_slot before id reference) as Found.
 pose proof (registry_lookup_implies_position_bound _ _ _ _ Found) as Bound.
 refine (DraftingTarget id (BoardFacts.revised (F.card_contents (selected_card reference))
   now (selected_card reference)) true _ _).
 - apply N.leb_le; lia.
 - intros selected Registered Ordinary.
   assert (Existing : N.eqb id (N.of_nat (List.length
     (F.board_cards (F.feature_board (world_features before))))) = false)
     by (apply N.eqb_neq; lia).
   unfold FeatureRequestAdmission.card,prompt.
   replace (F.card_updated (BoardFacts.revised (F.card_contents (selected_card reference)) now (selected_card reference))) with now by reflexivity.
   replace (F.card_contents (BoardFacts.revised (F.card_contents (selected_card reference)) now (selected_card reference))) with (F.card_contents (selected_card reference)) by reflexivity.
   now rewrite Registered,Ordinary,Clock,String.eqb_refl,Existing,Found,Mutable,equal_is_reflexive.
Defined.

Lemma selected_profile_is_registered : forall name before selected,
 Tasks.find_profile name (environment_profiles (world_environment before)) = Some selected ->
 FeatureRequestAdmission.registered_profile selected before = true.
Proof.
 intros name before selected Found; apply FeatureRequestAdmission.registered_profile_from_membership.
 unfold Tasks.find_profile in Found; apply find_some in Found; tauto.
Qed.

Definition plan {before} (target : drafting_target before) selected
 (Registered : FeatureRequestAdmission.registered_profile selected before = true)
 (Ordinary : FeatureRequestAdmission.ordinary_profile selected = true) : S.feature_plan before :=
 S.card_plan (target_id target) (target_card target) selected
   (prompt (target_card target) (target_retitle target) before) (target_retitle target)
   (target_position target) (target_scope target selected Registered Ordinary).
