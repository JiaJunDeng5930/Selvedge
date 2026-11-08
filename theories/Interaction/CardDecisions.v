From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Features Require Domain.
From Selvedge.Generated Require Commands.
From Selvedge.Interaction Require Import Codec.
From Selvedge.Interaction.Experience Require Read.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Module G := Selvedge.Generated.Commands.

Inductive kind := MoveCard | LinkCard.
Definition kinds := [MoveCard; LinkCard].
Definition kind_name decision := match decision with MoveCard => "move" | LinkCard => "link" end.
Definition decode_kind name := match name with "move" => Some MoveCard | "link" => Some LinkCard | _ => None end.

Inductive position :=
| EndOfStage (stage : Domain.board_stage)
| BeforeCard (stage : Domain.board_stage) (target : N) (title : string).
Definition position_stage place := match place with EndOfStage stage | BeforeCard stage _ _ => stage end.
Definition position_target place := match place with EndOfStage _ => None | BeforeCard _ id _ => Some id end.

Record task_target := TaskTarget { target_task : N; target_title : string }.
Inductive choice := MoveTo (place : position) | LinkTo (task : task_target).

Definition move_positions_from_cards (cards:list Read.card) card :=
 map EndOfStage Domain.stages ++
 flat_map (fun other =>
   if negb (N.eqb card (Read.card_id other)) && negb (Read.card_archived other)
   then [BeforeCard (Read.card_stage other) (Read.card_id other) (Read.card_title other)]
   else []) cards.
Definition link_targets (tasks:list Read.task) :=
 map (fun task => TaskTarget (Read.task_id task) (Read.task_title task)) tasks.
Record opportunity := Opportunity {
 source_card : N;
 source_revision : N;
 move_choices : list position;
 link_choices : list task_target
}.
Definition has_card snapshot card := match Read.find_card card snapshot with Some _ => true | None => false end.
Definition observe snapshot card :=
 source <- Read.find_card card snapshot;;
 cards <- Read.board_cards snapshot;;
 tasks <- Read.tasks snapshot;;
 Some (Opportunity (Read.card_id source) (Read.card_revision source)
   (move_positions_from_cards cards card) (link_targets tasks)).
Definition choices decision value := match decision with
| MoveCard => map MoveTo (move_choices value)
| LinkCard => map LinkTo (link_choices value)
end.

Definition move_proposal card revision observed stage before :=
 G.Cmd_move_card (G.Build_move_card card revision (Some (show_natural observed)) (Some stage)
   (Some (match before with None => "" | Some target => show_natural target end))).
Definition proposal opportunity observed selected :=
 let card := source_card opportunity in
 let revision := source_revision opportunity in
 match selected with
 | MoveTo place => move_proposal card revision observed (Domain.stage_name (position_stage place)) (position_target place)
 | LinkTo task => G.Cmd_link_card (G.Build_link_card card revision (Some (show_natural observed)) (Some (target_task task)))
 end.

Definition encode_position place :=
 let stage := JString (Domain.stage_name (position_stage place)) in
 match place with
 | EndOfStage _ => JObject [("status", stage); ("before_card", JString "")]
 | BeforeCard _ target title => JObject [("status", stage); ("before_card", JString (show_natural target)); ("title", JString title)]
 end.
Definition encode_target task := JObject [("task_id", number (target_task task)); ("title", JString (target_title task))].
Definition encode_opportunity value :=
 JObject [("card_id", number (source_card value)); ("revision", number (source_revision value));
   ("move_card", JArray (map encode_position (move_choices value)));
   ("link_card", JArray (map encode_target (link_choices value)))].
