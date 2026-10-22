From Stdlib Require Import String List Bool NArith Arith Lia.
From Selvedge.Foundation Require Import Json.
From Selvedge.Browser Require Import DOM Document Observation.
From Selvedge.Interaction Require Import DocumentPublication.
From Selvedge.Interaction.Presentation Require Surface Roles.
Import ListNotations.
Open Scope string_scope.

Theorem compiled_document_uses_configured_theme {A} (describe : A -> ControlPurpose.purpose)
    env generation (surface : Surface.surface A) :
  field "target_updates" (compile describe env generation surface) = Some (JArray
    (DOM.update_json (DOM.UpdateTarget "@document/root"
      [("data-theme",Appearance.theme_name (Surface.surface_appearance surface) (Layout.system_dark env))]
      [("color-scheme",Appearance.theme_name (Surface.surface_appearance surface) (Layout.system_dark env))]) ::
      map DOM.update_json
        (flat_map (target_updates None) (Surface.base surface ++ Surface.overlays surface)))).
Proof. reflexivity. Qed.

Theorem physical_markdown_uses_parent_typography env tier kind wrapper key text complete metadata :
  match physical_markdown env tier kind wrapper key text complete metadata with
  | DOM.Element _ _ _ properties _ _ _ =>
      properties = Appearance.markdown_properties env tier kind
  | _ => False end.
Proof. reflexivity. Qed.

Theorem supporting_role_survives_nested_content {A} (value : Surface.meaning A) :
  match value with
  | Surface.ActivityRow _ | Surface.ActivityGroup _ _ _ _ | Surface.LayerRegion _ => True
  | _ => source_context (Surface.ActivityRow Surface.SupportingRow) value =
      Surface.ActivityRow Surface.SupportingRow end.
Proof. destruct value; exact I || reflexivity. Qed.

Theorem composer_submission_retains_its_circular_geometry :
  geometry_for ControlPurpose.MessageSubmission ComposerArea true false false =
    ControlGeometry 32 32 16 (Enclosure.Insets 4 4) 0.
Proof. reflexivity. Qed.
Theorem composer_picker_keeps_distinct_geometry expanded :
  geometry_for (ControlPurpose.ChooseValue expanded) ComposerArea false false false =
    ControlGeometry 0 28 6 (Enclosure.Insets 8 4) 6.
Proof. reflexivity. Qed.
Theorem touch_navigation_has_44_pixel_floor env activity role area purpose icon choice supporting :
  navigation_target env role area = true ->
  exists height, 44 <= height /\
    In ("min-block-size", Typography.px height)
      (control_geometry_properties env activity role area purpose icon choice supporting).
Proof.
  intros Touch. unfold control_geometry_properties. rewrite Touch.
  eexists. split; [apply Nat.le_max_l|].
  apply in_or_app; left. simpl. auto.
Qed.

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
