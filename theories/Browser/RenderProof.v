From Stdlib Require Import String List NArith.
From Selvedge.Browser Require Import DOM Document Observation Appearance.
From Selvedge.Interaction Require Import ControlPurpose DocumentPublication.
From Selvedge.Interaction.Presentation Require Import Surface Roles Model.
Import ListNotations.
Open Scope string_scope.

Theorem native_fence_retains_complete_payload {A} (describe : A -> ControlPurpose.purpose)
    env generation area activity source view component key semantic label policy
    (children : list (Surface.node A)) :
 Document.compile_node describe env generation area activity source view component
   (Surface.Node key semantic label Roles.Content (Surface.InteractiveRegion policy) children) =
 DOM.Mount
   (Observation.physical_target view
     (DocumentPublication.target_key (DocumentPublication.fence_identity policy) DocumentPublication.Preview))
   (Document.interactive_status env activity (String.append key "/@pending") "data-interactive-pending" "正在更新显示" ::
    map (Document.compile_node describe env generation
     (@Document.area_for A area Roles.Content (Surface.InteractiveRegion policy)) activity
     (Document.source_context source (Surface.InteractiveRegion policy)) view component) children).
Proof. reflexivity. Qed.

Theorem native_fence_preserves_payload_order {A} (describe : A -> ControlPurpose.purpose)
    env generation area activity source view component key semantic label policy
    (first later : list (Surface.node A)) :
 Document.compile_node describe env generation area activity source view component
   (Surface.Node key semantic label Roles.Content (Surface.InteractiveRegion policy) (first ++ later)) =
 DOM.Mount
   (Observation.physical_target view
     (DocumentPublication.target_key (DocumentPublication.fence_identity policy) DocumentPublication.Preview))
   (Document.interactive_status env activity (String.append key "/@pending") "data-interactive-pending" "正在更新显示" ::
    map (Document.compile_node describe env generation
       (@Document.area_for A area Roles.Content (Surface.InteractiveRegion policy)) activity
       (Document.source_context source (Surface.InteractiveRegion policy)) view component) first ++
    map (Document.compile_node describe env generation
       (@Document.area_for A area Roles.Content (Surface.InteractiveRegion policy)) activity
       (Document.source_context source (Surface.InteractiveRegion policy)) view component) later).
Proof. rewrite native_fence_retains_complete_payload, map_app; reflexivity. Qed.

Theorem interactive_chrome_preserves_rest_channels env style :
 Appearance.style_interactive style = true ->
 In ("--control-rest-color", Appearance.foreground (Appearance.chrome_paint (Appearance.style_chrome style)))
   (Appearance.style_properties env style) /\
 In ("--control-rest-background", Appearance.background (Appearance.chrome_paint (Appearance.style_chrome style)) Appearance.Rest)
   (Appearance.style_properties env style).
Proof.
 intro Interactive; unfold Appearance.style_properties.
 repeat rewrite Interactive.
 split; repeat rewrite in_app_iff; cbn [List.In]; intuition (try reflexivity).
Qed.

Definition unavailable_native_button (value : DOM.node) : Prop :=
 match value with
 | DOM.Element _ tag attributes _ _ _ _ => tag = "button" /\
   (In ("disabled", "disabled") attributes \/ In ("aria-disabled", "true") attributes)
 | _ => False
 end.

Theorem unavailable_action_renders_an_unavailable_native_button {A} (describe : A -> ControlPurpose.purpose)
    env generation area activity source view component key semantic label
    (action : Model.control A) (children : list (Surface.node A)) :
 Model.available (Model.control_availability action) = false ->
 unavailable_native_button
   (Document.compile_node describe env generation area activity source view component
     (Surface.Node key semantic label Roles.Button (Surface.Activate action) children)).
Proof.
 intro Unavailable.
 cbn [Document.compile_node Document.compile_element Document.area_for unavailable_native_button].
 split; [reflexivity|].
 unfold Document.control_attributes; rewrite !Unavailable.
 cbn [Document.disabled Surface.node_role Surface.node_meaning Document.area_for].
 rewrite !Bool.orb_true_r.
 cbn.
 right.
 repeat rewrite in_app_iff; cbn [List.In]; tauto.
Qed.
