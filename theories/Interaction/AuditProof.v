From Stdlib Require Import List.
From Selvedge.Foundation Require Import Json.
From Selvedge.Interaction Require Import Audit AuditReading.
From Selvedge.Interaction.Presentation Require Import Surface.
Import ListNotations.

Module AR := Selvedge.Interaction.AuditReading.
Module S := Selvedge.Interaction.Presentation.Surface.

Definition activity_sources {Action} (node : S.node Action) : option (list json) :=
 match S.node_meaning node with
 | S.ActivityContent _ faces => Some (map Audit.face_source faces)
 | _ => None
 end.

(** The timeline's disclosure choice changes only ActivityContent's expansion
    flag. The rendered group, including after view scoping, retains every exact
    source produced by Audit.faces. *)
Theorem timeline_activity_groups_retain_exact_sources_for_every_disclosure :
 forall {Action} (action : AR.actions Action) context retained interactive task
   disclosures history first rest view,
 activity_sources
   (AR.in_view view
     (AR.group action context retained interactive task disclosures history
       (Audit.Activity first rest))) =
 Some (map Audit.face_source (Audit.faces history (first :: rest))).
Proof. reflexivity. Qed.
