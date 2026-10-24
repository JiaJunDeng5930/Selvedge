From Stdlib Require Import Arith Lia List String.
From Selvedge.Browser Require Import Layout Typography.
From Selvedge.Interaction.Presentation Require Composition.
Import ListNotations.
Open Scope string_scope.

Theorem every_page_preserves_content_edges env page :
  In ("padding-inline", Typography.px 24)
    (page_properties env page) /\
  In ("padding-block", Typography.px 24)
    (page_properties env page).
Proof. unfold page_properties. split; apply in_or_app; left; simpl; tauto. Qed.
Theorem every_page_preserves_section_separation env page :
  In ("gap", Typography.px 12)
    (page_properties env page).
Proof. unfold page_properties. apply in_or_app; left; simpl; tauto. Qed.

Theorem work_overview_preserves_its_reading_span_and_viewport_edges env :
  work_overview_width env <= 2 * reading_maximum_width (parameters env) /\
  work_overview_width env <= viewport_width env - 2 * work_overview_clearance /\
  work_overview_height env <= viewport_height env * 94 / 100 /\
  work_overview_height env <= viewport_height env - 2 * work_overview_clearance.
Proof. unfold work_overview_width, work_overview_height.
  repeat split; try apply Nat.le_min_l; try apply Nat.le_min_r.
  - apply Nat.Div0.div_le_mono. apply Nat.mul_le_mono_r. lia.
  - apply Nat.Div0.div_le_upper_bound. rewrite Nat.mul_comm.
    apply Nat.mul_le_mono_r. vm_compute. lia.
Qed.

Theorem compact_navigation_uses_the_viewport env details :
  observe_capacity env = Some (false,details) ->
  modal_navigation_width env = viewport_width env.
Proof. intros Capacity. unfold modal_navigation_width. rewrite Capacity. reflexivity. Qed.
Theorem modal_navigation_retains_its_full_height_and_leading_origin env :
  In ("block-size",Typography.px(viewport_height env)) (modal_navigation_properties env) /\
  In ("inset-inline-start","0") (modal_navigation_properties env) /\
  In ("inset-block-start","0") (modal_navigation_properties env).
Proof. simpl. tauto. Qed.

(* Keep comparison proofs abstract: reducing unary font-scaled bounds bloats checking. *)
Local Opaque Nat.leb.

(** These bounds express the product's touch/reading contract independently of CSS. *)
Theorem motor_targets_keep_minimum env : 32 <= motor_minimum env.
Proof. unfold motor_minimum, base_motor_minimum. apply Nat.le_max_l. Qed.
Theorem hierarchy_heading_separates_members grammar :
  member_gap grammar < heading_gap grammar.
Proof. unfold member_gap, heading_gap. lia. Qed.
Theorem hierarchy_groups_separate_headings grammar :
  heading_gap grammar < group_gap grammar.
Proof. unfold group_gap. lia. Qed.
Theorem hierarchy_indentation_is_positive grammar : 0 < nesting_inset grammar.
Proof. unfold nesting_inset. lia. Qed.

Theorem nested_members_preserve_both_inline_edges env activity :
  In ("padding-inline", Typography.px (nesting_inset (hierarchy_for env activity)))
    (member_properties env activity true).
Proof. unfold member_properties. simpl. auto. Qed.
Theorem multiline_editor_remains_bounded env :
  input_minimum_height (parameters env) <= input_maximum_height (parameters env).
Proof.
  change (input_minimum_height (parameters env) <=
    Nat.max (Typography.scaled (root_font_size_milli env) 240)
      (input_minimum_height (parameters env))).
  apply Nat.le_max_r.
Qed.
Theorem editor_contains_observed_body_line env :
  metric_height (body_metric (font_metrics env)) +
    2 * Typography.scaled (root_font_size_milli env) 12 <=
  input_minimum_height (parameters env).
Proof.
  change (metric_height (body_metric (font_metrics env)) +
    2 * Typography.scaled (root_font_size_milli env) 12 <=
    Nat.max (Typography.scaled (root_font_size_milli env) 44)
    (Nat.max (Typography.line_height (root_font_size_milli env) Typography.Body)
      (metric_height (body_metric (font_metrics env))) +
      2 * Typography.scaled (root_font_size_milli env) 12)).
  eapply Nat.le_trans; [|apply Nat.le_max_r].
  apply Nat.add_le_mono_r. apply Nat.le_max_r.
Qed.
Theorem admitted_metric_is_positive height advance value :
  admit_metric height advance = Some value ->
  0 < height /\ 0 < advance.
Proof. destruct height, advance; cbn; discriminate || lia. Qed.

(** A candidate sidebar reserves the original global rail and main minimum
    against the fixed native viewport, independently of its current placement. *)
Theorem navigation_capacity_keeps_content env workspace main details :
  workspace_inner_width env = Some workspace -> main_inner_width env = Some main ->
  observe_capacity env = Some (true, details) ->
  global_navigation_width env + navigation_width (parameters env) + main_minimum_width (parameters env) <= viewport_width env.
Proof.
  intros Workspace Main Capacity. unfold observe_capacity in Capacity.
  rewrite Workspace, Main in Capacity.
  pose proof (f_equal (fun packet : option (bool * bool) =>
    match packet with Some (navigation, _) => navigation | None => false end) Capacity) as Navigation.
  change (Nat.leb (global_navigation_width env + navigation_requirement env) (viewport_width env) = true) in Navigation.
  apply Nat.leb_le in Navigation. unfold navigation_requirement in Navigation. lia.
Qed.
Theorem supporting_capacity_keeps_reading_measure env workspace main navigation :
  workspace_inner_width env = Some workspace -> main_inner_width env = Some main ->
  observe_capacity env = Some (navigation, true) ->
  reading_minimum env + details_width (parameters env) <= main.
Proof.
  intros Workspace Main Capacity. unfold observe_capacity in Capacity.
  rewrite Workspace, Main in Capacity.
  pose proof (f_equal (fun packet : option (bool * bool) =>
    match packet with Some (_, supporting) => supporting | None => false end) Capacity) as Details.
  change (Nat.leb (details_requirement env) main = true) in Details.
  apply Nat.leb_le in Details. exact Details.
Qed.

Theorem horizontal_row_fits available minimum :
  row_flow available minimum = Horizontal -> minimum <= available.
Proof.
  unfold row_flow. destruct (Nat.leb minimum available) eqn:Fits; [|discriminate].
  intros _. apply Nat.leb_le. exact Fits.
Qed.
Theorem undersized_row_is_vertical available minimum :
  available < minimum -> row_flow available minimum = Vertical.
Proof.
  intros Small. unfold row_flow. destruct (Nat.leb minimum available) eqn:Fits; [|reflexivity].
  apply Nat.leb_le in Fits. lia.
Qed.

Theorem conversation_body_allocates_a_bounded_reading_port env :
  In ("display","flex") (region_properties env Composition.TimelineContent Composition.BodyPosition) /\
  In ("min-block-size","0") (region_properties env Composition.TimelineContent Composition.BodyPosition) /\
  In ("overflow","hidden") (region_properties env Composition.TimelineContent Composition.BodyPosition).
Proof. simpl. tauto. Qed.

Theorem layer_clearance_remains_positive env : 0 < layer_clearance env.
Proof. unfold layer_clearance, layer_unit. pose proof (Nat.le_max_l 1 (input_line_height (parameters env) / 4)). lia. Qed.

Theorem dialog_reading_span_is_bounded env :
  dialog_reading_width env <= reading_maximum_width (parameters env).
Proof. apply Nat.le_min_l. Qed.
