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
