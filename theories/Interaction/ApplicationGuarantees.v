From Stdlib Require Import String List Bool.
From Selvedge.Foundation Require Import Json.
From Selvedge.Interaction Require Import Application ApplicationState Input InputCodecs.
From Selvedge.Interaction.Interactive Require Import Types.

Theorem native_source_cannot_grant_authority namespace world state owner source closed ending allowed :
 native_language_input namespace world state (Types.SourceChanged owner source closed ending allowed)=false.
Proof. reflexivity. Qed.
Theorem native_client_cannot_change_external_authority namespace world state owner allowed :
 native_language_input namespace world state (Types.ExternalChanged owner allowed)=false.
Proof. reflexivity. Qed.
Theorem native_client_cannot_remove_document namespace world state owner :
 native_language_input namespace world state (Types.Remove owner)=false.
Proof. reflexivity. Qed.

Theorem forged_source_content_cannot_affect_entry namespace lagged now world state owner
 first_source second_source closed ending allowed :
 Application.step namespace lagged now world
  (Input.Interactive(Types.SourceChanged owner first_source closed ending allowed))state =
 Application.step namespace lagged now world
  (Input.Interactive(Types.SourceChanged owner second_source closed ending allowed))state.
Proof.
 unfold Application.step. cbn [ApplicationCore.local_step Application.native_language_input]. reflexivity.
Qed.

Theorem forged_external_authority_cannot_affect_entry namespace lagged now world state owner :
 Application.step namespace lagged now world(Input.Interactive(Types.ExternalChanged owner true))state =
 Application.step namespace lagged now world(Input.Interactive(Types.ExternalChanged owner false))state.
Proof.
 unfold Application.step. cbn [ApplicationCore.local_step Application.native_language_input]. reflexivity.
Qed.
