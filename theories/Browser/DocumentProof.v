From Stdlib Require Import String List Bool NArith Arith Lia.
From Selvedge.Foundation Require Import Json.
From Selvedge.Browser Require Import DOM Document Observation.
From Selvedge.Interaction Require Import DocumentPublication.
From Selvedge.Interaction.Presentation Require Surface Roles.
Import ListNotations.
Open Scope string_scope.

Theorem native_range_retains_browser_appearance :
  native_field_properties "range" = [("appearance","auto")].
Proof. reflexivity. Qed.
Theorem authored_fields_replace_browser_appearance kind :
  String.eqb kind "range" = false ->
  native_field_properties kind = [("appearance","none")].
Proof. intros Other. unfold native_field_properties. rewrite Other. reflexivity. Qed.

Theorem heading_context_preserves_the_reading_hierarchy env :
  heading_properties env false CreationArea =
    Typography.properties (Layout.root_font_size_milli env) Typography.Display Typography.Medium /\
  heading_properties env false PageArea =
    Typography.properties (Layout.root_font_size_milli env) Typography.Title Typography.Medium /\
  heading_properties env false OutsideArea =
    Typography.properties (Layout.root_font_size_milli env) Typography.Section Typography.Medium.
Proof. repeat split; reflexivity. Qed.

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
  | Surface.ActivityRow _ | Surface.ActivityGroup _ _ _ _ | Surface.LayerRegion _ | Surface.NavigationRegion _ _ => True
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
  eexists. split.
  2: { apply in_or_app; left. right; left; reflexivity. }
  eapply Nat.le_trans; [|apply Nat.le_max_l].
  unfold Layout.touch_minimum. apply Nat.le_max_l.
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

Theorem every_action_retains_motor_extent env activity role area purpose icon choice supporting :
  exists width height,
    32 <= width /\ 32 <= height /\
    In ("min-inline-size",Typography.px width)
      (control_geometry_properties env activity role area purpose icon choice supporting) /\
    In ("min-block-size",Typography.px height)
      (control_geometry_properties env activity role area purpose icon choice supporting).
Proof.
  unfold control_geometry_properties.
  set (motor := if activity then Layout.motor_minimum env else Layout.base_motor_minimum).
  assert (Motor : 32 <= motor).
  { unfold motor. destruct activity; [unfold Layout.motor_minimum; apply Nat.le_max_l|reflexivity]. }
  exists motor, (Nat.max (if navigation_target env role area then Layout.touch_minimum env else motor)
    (if activity then Nat.max motor
      (target_height (geometry_for purpose area icon choice supporting))
     else (if activity then match target_height (geometry_for purpose area icon choice supporting) with
       | 0 => 0 | S _ => Typography.scaled (Layout.root_font_size_milli env)
         (target_height (geometry_for purpose area icon choice supporting)) end
       else target_height (geometry_for purpose area icon choice supporting)))).
  split; [exact Motor|]. split.
  - eapply Nat.le_trans; [|apply Nat.le_max_l].
    destruct (navigation_target env role area).
    + unfold Layout.touch_minimum. eapply Nat.le_trans; [|apply Nat.le_max_l]. vm_compute. lia.
    + exact Motor.
  - split; apply in_or_app; left; simpl; auto.
Qed.
