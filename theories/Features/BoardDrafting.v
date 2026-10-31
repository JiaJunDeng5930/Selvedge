From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Programming Require Import Schema Receiver.
From Selvedge.Foundation Require Import Registry.
From Selvedge.Kernel Require Import Domain State Codec FeatureRequestAdmission TicketedRequest.
From Selvedge.Features Require Import Domain BoardFacts BoardParameters Observation Titles.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.
Module F := Selvedge.Features.Domain.
Module S := TicketedRequest.Scoped.

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

Definition prompt card retitle before := Titles.board_prompt
 (F.title_task_instructions (F.feature_title_settings (world_features before)))
 (F.draft_title (F.card_contents card)) (F.draft_description (F.card_contents card)) retitle.
Definition fresh_card draft now := F.Card 0 draft None false now now F.NoEnrichment "" false.
Definition fresh_id before := N.of_nat (List.length (F.board_cards (F.feature_board (world_features before)))).
Definition live_count before := List.length (filter (fun card => match card with
 Some _ => true | None => false end) (F.board_cards (F.feature_board (world_features before)))).

(** New and revised drafts retain only their distinct admission observations.
    Identity, revision, retitle mode and receiver position are interpretations
    of the same choice, so they cannot be supplied independently. *)
Inductive drafting_target (before : world) :=
| FreshTarget (draft : F.card_draft) (now : BoardParameters.clock)
    (Draft : BoardFacts.valid_draft draft before = true)
    (Capacity : Nat.ltb (live_count before) 512 = true)
    (Identity : (fresh_id before <? 4294967295) = true)
| RevisedTarget (id : N) (reference : card_reference before id) (now : BoardParameters.clock)
    (Mutable : BoardFacts.mutable (selected_card reference) before = true).
Definition fresh_target := FreshTarget.
Definition revised_target := RevisedTarget.
Definition target_id {before} (target : drafting_target before) := match target with
 | FreshTarget _ _ _ _ _ _ => fresh_id before
 | RevisedTarget _ id _ _ _ => id end.
Definition target_card {before} (target : drafting_target before) := match target with
 | FreshTarget _ draft now _ _ _ => fresh_card draft now
 | RevisedTarget _ _ reference now _ =>
     BoardFacts.revised (F.card_contents (selected_card reference)) now (selected_card reference) end.
Definition target_retitle {before} (target : drafting_target before) := match target with
 | FreshTarget _ _ _ _ _ _ => false | RevisedTarget _ _ _ _ _ => true end.
Definition target_location {before} (target : drafting_target before)
 : Receiver.located F.state F.card (world_features before).
Proof.
 refine (Receiver.Located (S.card_slot (target_id target)) _).
 destruct target as [draft now Draft Capacity Identity|id reference now Mutable].
 - exact (Receiver.position
     (Receiver.At.field (world_features before) F.feature_board
       (Receiver.At.focused (F.feature_board (world_features before)) S.board_contents
         (Receiver.At.inject (@Some F.card)
           (Receiver.At.ordered_append (Focus.read S.board_contents (F.feature_board (world_features before)))))))).
 - exact (Receiver.position
     (Receiver.At.field (world_features before) F.feature_board
       (Receiver.At.focused (F.feature_board (world_features before)) S.board_contents
         (Receiver.At.inject (@Some F.card)
           (Receiver.At.ordered_present (Focus.read S.board_contents (F.feature_board (world_features before)))
             id (selected_card reference) (selected_card_found reference)))))).
Defined.

Record drafting_request (before : world) := DraftingRequest {
 requested_target : drafting_target before;
 requested_profile : profile;
 profile_selected : exists name,
   Tasks.find_profile name (environment_profiles (world_environment before)) = Some requested_profile;
 profile_ordinary : FeatureRequestAdmission.ordinary_profile requested_profile = true
}.
Arguments DraftingRequest {before}.
Arguments requested_target {before}.
Arguments requested_profile {before}.
Arguments profile_selected {before}.
Arguments profile_ordinary {before}.
Definition protocol {before} (request : drafting_request before)
 : RequestTypes.located (N * bool) (world_features before) :=
 let target := requested_target request in
 RequestTypes.Protocol
   (Receiver.At.in_record (target_location target) F.card_enrichment F.Enriching (target_card target))
   ModelDeclarations.board_text_request
   (fun input _ => Schema.of_tuple (ModelDeclarations.request_body_fields ModelDeclarations.board_text_request)
     [!Codec.task_text_model_json (requested_profile request);
       prompt (target_card target) (target_retitle target) before;snd input!]).
Definition channel : S.feature_channel drafting_request (N * bool) :=
 @S.FeatureChannel drafting_request (N * bool) TicketedRequest.TaskTicket
   (fun _ request => let target := requested_target request in
     (F.card_revision (target_card target),target_retitle target))
   (fun _ request => protocol request).
Definition plan {before} (target : drafting_target before) name selected
 (Selected : Tasks.find_profile name (environment_profiles (world_environment before)) = Some selected)
 (Ordinary : FeatureRequestAdmission.ordinary_profile selected = true) : S.feature_plan before :=
 S.FeaturePlan channel (DraftingRequest target selected (ex_intro _ name Selected) Ordinary).
