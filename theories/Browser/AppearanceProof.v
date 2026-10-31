From Stdlib Require Import String List Arith.
From Selvedge.Browser Require Import Appearance Typography Layout SemanticAppearance.
From Selvedge.Interaction.Presentation Require Roles.
From Selvedge.Programming.Presentation Require Surface.
Import ListNotations.
Open Scope string_scope.

Theorem explicit_light_overrides_system dark :
  theme Selvedge.Interaction.Appearance.LightAppearance dark = false.
Proof. reflexivity. Qed.
Theorem explicit_dark_overrides_system dark :
  theme Selvedge.Interaction.Appearance.DarkAppearance dark = true.
Proof. reflexivity. Qed.
Theorem system_theme_follows_observation dark :
  theme Selvedge.Interaction.Appearance.SystemAppearance dark = dark.
Proof. reflexivity. Qed.

Theorem rich_body_retains_parent_typography env parent strength :
  In ("--rich-body-font",Typography.font_family parent) (rich_properties env parent strength) /\
  In ("--rich-body-size",Typography.px (Typography.size (root_font_size_milli env) parent))
    (rich_properties env parent strength) /\
  In ("--rich-body-line",Typography.px (Typography.line_height (root_font_size_milli env) parent))
    (rich_properties env parent strength) /\
  In ("--rich-body-weight",Numbers.show_nat (Typography.weight strength))
    (rich_properties env parent strength).
Proof. unfold rich_properties. simpl. tauto. Qed.

Theorem rich_headings_keep_authored_emphasis env parent strength :
  In ("--rich-title-weight",Numbers.show_nat (Typography.weight Typography.Strong))
    (rich_properties env parent strength) /\
  In ("--rich-section-weight",Numbers.show_nat (Typography.weight Typography.Medium))
    (rich_properties env parent strength) /\
  In ("--rich-support-weight",Numbers.show_nat (Typography.weight Typography.Medium))
    (rich_properties env parent strength).
Proof. unfold rich_properties. simpl. tauto. Qed.

Theorem supporting_context_preserves_reading_role {A} env (value : Surface.meaning A) property :
  In property (Typography.properties (Layout.root_font_size_milli env)
    Typography.ActivitySupport (match value with Surface.InformationText role=>Typography.information_emphasis role|_=>Typography.Regular end)) ->
  In property (source_properties env (Surface.ActivityRow Surface.SupportingRow) value).
Proof.
  intros Reading. destruct value; cbn [source_properties];
    try unfold supporting_properties; repeat rewrite in_app_iff; auto.
Qed.

Theorem selected_navigation_rest_and_feedback_remain_distinct :
  background (ChoicePaint true) Rest = selected_wash SubtleWash /\
  background (ChoicePaint true) Hovered = selected_wash EmphasizedWash.
Proof. split; reflexivity. Qed.

Theorem heading_role_keeps_moderate_emphasis env :
  In ("font-weight",Numbers.show_nat(Typography.weight Typography.Medium))
    (role_typography env Roles.Heading).
Proof. simpl. auto. Qed.

Theorem ordinary_dialog_partitions_preserve_edges :
  style_frame (role_style Roles.DialogHeader) = Frame 24 14 0 /\
  style_frame (role_style Roles.DialogBody) = Frame 24 20 16 /\
  style_frame (role_style Roles.DialogActions) = Frame 24 12 12.
Proof. repeat split; reflexivity. Qed.

Theorem chosen_work_tab_keeps_canvas_background :
  chrome_paint (style_chrome (role_style (Roles.WorkTab true))) = CanvasPaint.
Proof. reflexivity. Qed.

Theorem user_message_cap_preserves_intrinsic_room env :
  In ("max-inline-size","calc-size(min-content,min(100%,max(size,70%)))")
    (role_properties env Roles.UserMessage).
Proof. unfold role_properties, style_properties. cbn [role_style enclosure_fields fields adaptive_width_limit].
  repeat rewrite in_app_iff. simpl. tauto. Qed.

Theorem embedded_markdown_retains_authored_spacing env parent :
  rich_code_frame (markdown_policy env parent EmbeddedMarkdown) = Frame 8 8 8 /\
  rich_block_gap (markdown_policy env parent EmbeddedMarkdown) = 12 /\
  rich_list_indent (markdown_policy env parent EmbeddedMarkdown) = 24.
Proof. repeat split; reflexivity. Qed.

Theorem published_markdown_spacing_uses_actual_parent_size env parent :
  rich_block_gap (markdown_policy env parent PublishedMarkdown) =
    Typography.size (Layout.root_font_size_milli env) parent /\
  rich_list_indent (markdown_policy env parent PublishedMarkdown) =
    2 * Typography.size (Layout.root_font_size_milli env) parent.
Proof. split; reflexivity. Qed.

Theorem composer_footer_preserves_group_clearance env :
  In ("gap",Typography.px 12) (role_properties env Roles.ComposerActions) /\
  In ("align-items","flex-end") (role_properties env Roles.ComposerActions).
Proof.
  unfold role_properties, style_properties. cbn [role_style fields].
  repeat rewrite in_app_iff. simpl. tauto.
Qed.

Theorem composer_rows_require_whole_group_measurement {A} activity (source : Surface.meaning A) :
  SemanticAppearance.responsive_row activity source Roles.ComposerActions Surface.Region = true /\
  SemanticAppearance.responsive_row activity source Roles.Toolbar Surface.Region = true.
Proof. destruct source; split; reflexivity. Qed.

Theorem navigation_caption_preserves_single_line {A} env activity :
  In ("white-space","nowrap")
    (SemanticAppearance.meaning_properties env activity
      (@Surface.InformationText A Selvedge.Interaction.Presentation.Information.NavigationCaption)).
Proof. unfold SemanticAppearance.meaning_properties. repeat rewrite in_app_iff. simpl. tauto. Qed.

Theorem conversation_passes_its_available_height_to_the_reading_port {A} env activity view :
  In ("flex","1 1 auto")
    (SemanticAppearance.meaning_properties env activity (@Surface.PageContext A view)) /\
  In ("min-block-size","0")
    (SemanticAppearance.meaning_properties env activity (@Surface.PageContext A view)) /\
  In ("overflow","hidden")
    (SemanticAppearance.meaning_properties env activity (@Surface.PageContext A view)).
Proof. unfold SemanticAppearance.meaning_properties. repeat rewrite in_app_iff. simpl. tauto. Qed.
