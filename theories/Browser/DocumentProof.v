From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Browser Require Import DOM Document Observation.
From Selvedge.Interaction Require Import DocumentPublication.
From Selvedge.Interaction.Presentation Require Surface Roles.
Import ListNotations.
Open Scope string_scope.

(** Active previews hide the original source target. The browser applies this
    checked update to the existing Markdown pre element, rather than creating
    a second source representation. Native target identity remains an IO
    obligation, including the task-view scope supplied by the typed page. *)
Theorem active_preview_hides_original_source : forall A env_view key semantic label role identity (children:list(Surface.node A)),
 In (DOM.UpdateTarget
   (Observation.physical_target env_view(DocumentPublication.target_key identity DocumentPublication.Source))
   [] [("display","none")])
 (Document.target_updates env_view
   (Surface.Node key semantic label role
     (Surface.InteractiveRegion(DocumentPublication.FencePolicy identity false true)) children)).
Proof. intros; simpl; left; reflexivity. Qed.

Theorem active_preview_removes_original_code_frame : forall A env_view key semantic label role identity (children:list(Surface.node A)),
 In (DOM.UpdateTarget
   (Observation.physical_target env_view(DocumentPublication.target_key identity DocumentPublication.Frame))
   [("data-interactive-active","true")]
   [("border","0");("background","transparent");("padding","0")])
 (Document.target_updates env_view
   (Surface.Node key semantic label role
     (Surface.InteractiveRegion(DocumentPublication.FencePolicy identity false true)) children)).
Proof. intros; simpl; right; left; reflexivity. Qed.
