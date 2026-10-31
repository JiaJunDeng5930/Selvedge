From Stdlib Require Import List Bool String.
From Selvedge.Interaction.Experience Require Model Observation.
From Selvedge.Interaction.Presentation Require Import Editors.
From Selvedge.Programming.Presentation Require Import Surface.
From Selvedge.Programming.Presentation Require Model.
Import ListNotations.
Module UX := Selvedge.Interaction.Experience.Model.
Module Observe := Selvedge.Interaction.Experience.Observation.

Local Lemma passive_causes_have_no_attention e (causes:list(UX.obstruction e)) :
 Forall (fun cause=>Observe.passive_obstruction cause=true) causes ->
 find (fun cause=>negb(Observe.passive_obstruction cause)) causes=None.
Proof.
 intros Passive. induction Passive; [reflexivity|].
 cbn. rewrite H. exact IHPassive.
Qed.

(** A complete assessment remains attached to its actual presentation node,
    while normal editing states do not become errors or repair controls. *)
Theorem passive_assessment_has_no_error_content e parent (assessment:UX.assessment e) :
 Forall (fun cause=>Observe.passive_obstruction cause=true)
   (Observe.assessment_obstructions(UX.assessment_outcome assessment)) ->
 node_children(assessment_nodes parent assessment)=[].
Proof.
 intros Passive. unfold assessment_nodes,Observe.action_obstruction,Observe.attention_obstruction.
 rewrite (passive_causes_have_no_attention _ _ Passive). reflexivity.
Qed.

Theorem assessment_presentation_retains_complete_observation e parent (assessment:UX.assessment e) :
 node_meaning(assessment_nodes parent assessment)=ActionExplanation e assessment.
Proof. reflexivity. Qed.

Theorem blocked_editing_explains_all_commit_obstructions e identity (first:UX.obstruction e) rest :
 assessment_availability(UX.Assessment identity(UX.PreparationBlocked first rest))=
 Model.Unavailable(String.concat " · "(map(fun cause=>UX.obstruction_message cause)(first::rest))).
Proof. reflexivity. Qed.

Theorem field_obstruction_is_explained_at_its_field e parent (assessment:UX.assessment e) cause subject :
 Observe.attention_obstruction(UX.assessment_outcome assessment)=Some cause ->
 UX.obstruction_target cause=UX.RepairField subject ->
 node_children(assessment_nodes parent assessment)=[].
Proof.
 intros Attention Target. unfold assessment_nodes,Observe.action_obstruction.
 rewrite Attention,Target. reflexivity.
Qed.
