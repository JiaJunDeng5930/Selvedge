From Stdlib Require Import String List Bool Arith Lia ZArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Programming Require Import Graphics.
From Selvedge.Interaction.Interactive Require Import Bounds Decimal Expression Plot.
From Selvedge.Programming Require Import Outcome.
Import ListNotations.
Open Scope string_scope.
Open Scope Z_scope.

Module P := Selvedge.Interaction.Interactive.Plot.
Module D := Selvedge.Interaction.Interactive.Decimal.
Module E := Selvedge.Interaction.Interactive.Expression.
Module X := Selvedge.Interaction.Interactive.Expand.
Module V := Selvedge.Interaction.Interactive.Vocabulary.
Module G := Selvedge.Programming.Graphics.

Lemma firstn_nth_error_prefix {A} (limit : nat) (source : list A) index :
  (index < limit)%nat ->
  nth_error (firstn limit source) index = nth_error source index.
Proof.
  revert source index.
  induction limit as [|limit IH]; intros source index Within.
  - lia.
  - destruct source as [|head tail]; [reflexivity|].
    destruct index as [|index]; simpl; [reflexivity|].
    apply IH. lia.
Qed.

Theorem chart_rows_respect_the_point_bound properties :
  (List.length (P.chart_rows properties) <= Bounds.chart_points)%nat.
Proof.
  unfold P.chart_rows.
  rewrite length_firstn.
  lia.
Qed.

Theorem chart_rows_preserve_the_ordered_source_prefix properties index :
  (index < Bounds.chart_points)%nat ->
  nth_error (P.chart_rows properties) index =
    nth_error (X.property_array "data" properties) index.
Proof.
  intros Within.
  unfold P.chart_rows.
  apply firstn_nth_error_prefix.
  exact Within.
Qed.

(** The actual plot producer depends only on the selected prefix. Values in
    type-correct later rows cannot change it or fail numeric conversion. *)
Theorem chart_ignores_unplotted_values left right :
  X.property_text "x" left = X.property_text "x" right ->
  X.property_text "y" left = X.property_text "y" right ->
  P.x_title left = P.x_title right ->
  P.y_title left = P.y_title right ->
  P.chart_rows left = P.chart_rows right ->
  V.component_tag (X.description left) = V.component_tag (X.description right) ->
  P.chart left = P.chart right.
Proof.
  intros XAxis YAxis XTitle YTitle Rows Kind. unfold P.chart, P.chart_axes.
  rewrite XAxis, YAxis, Rows, Kind, XTitle, YTitle. reflexivity.
Qed.

Theorem data_point_admits_category_x x_path y_path row category y_value :
  get_path x_path row = JString category ->
  E.decimal_value (get_path y_path row) = Some y_value ->
  P.data_point x_path y_path row = Outcome.Good (P.Point None category y_value).
Proof.
  intros X Y.
  unfold P.data_point.
  rewrite X, Y.
  reflexivity.
Qed.

Theorem data_point_admits_finite_numeric_x x_path y_path row x_source x_value y_value :
  get_path x_path row = JNumber x_source ->
  E.decimal_value (JNumber x_source) = Some x_value ->
  E.decimal_value (get_path y_path row) = Some y_value ->
  P.data_point x_path y_path row = Outcome.Good (P.Point (Some x_value) (D.text x_value) y_value).
Proof.
  intros X FiniteX FiniteY.
  unfold P.data_point.
  rewrite X, FiniteY, FiniteX.
  reflexivity.
Qed.

Theorem data_point_rejects_non_decimal_y x_path y_path row :
  E.decimal_value (get_path y_path row) = None ->
  P.data_point x_path y_path row = Outcome.Error "Chart y field must be a finite fixed decimal".
Proof.
  intros InvalidY.
  unfold P.data_point.
  rewrite InvalidY.
  reflexivity.
Qed.

Theorem data_point_rejects_boolean_x x_path y_path row enabled y_value :
  get_path x_path row = JBool enabled ->
  E.decimal_value (get_path y_path row) = Some y_value ->
  P.data_point x_path y_path row = Outcome.Error "Chart x field must be numeric or a string category".
Proof.
  intros X FiniteY.
  unfold P.data_point.
  rewrite X, FiniteY.
  reflexivity.
Qed.

Lemma tick_step_positive span : 0 < P.tick_step span.
Proof.
  unfold P.tick_step.
  set (rough := Z.max 1 ((span + 3) / 4)).
  set (decade := Z.pow 10 (Z.of_nat (Nat.pred (String.length (show_integer rough))))).
  assert (0 < decade) by (unfold decade; apply Z.pow_pos_nonneg; lia).
  destruct (rough <=? decade), (rough <=? 2 * decade), (rough <=? 5 * decade); lia.
Qed.

Theorem chart_axis_covers_values lower upper :
  let axis := P.make_axis lower upper in
  P.axis_lower axis <= lower /\ upper <= P.axis_upper axis /\
  P.axis_lower axis < P.axis_upper axis.
Proof.
  unfold P.make_axis.
  set (step := if lower =? upper then D.scale else P.tick_step (upper - lower)).
  assert (Positive : 0 < step).
  { unfold step. destruct (lower =? upper).
    - vm_compute. reflexivity.
    - apply tick_step_positive. }
  cbn.
  pose proof (Z.mod_pos_bound lower step Positive).
  pose proof (Z.mod_pos_bound (-upper) step Positive).
  pose proof (Z.div_mod lower step ltac:(lia)).
  pose proof (Z.div_mod (-upper) step ltac:(lia)).
  repeat split; lia.
Qed.

Theorem chart_axis_coordinates_reach_both_plot_edges origin span axis :
  P.axis_lower axis < P.axis_upper axis ->
  P.axis_coordinate origin span axis (P.axis_lower axis) = origin * D.scale /\
  P.axis_coordinate origin span axis (P.axis_upper axis) = (origin + span) * D.scale.
Proof.
  intros Strict. unfold P.axis_coordinate.
  assert (Nonzero : P.axis_upper axis - P.axis_lower axis <> 0) by lia.
  split.
  - replace ((P.axis_lower axis - P.axis_lower axis) * span * D.scale) with 0 by ring.
    rewrite Z.div_0_l by exact Nonzero. ring.
  - replace ((P.axis_upper axis - P.axis_lower axis) * span * D.scale)
      with ((span * D.scale) * (P.axis_upper axis - P.axis_lower axis)) by ring.
    rewrite Z.div_mul by exact Nonzero. ring.
Qed.

Theorem chart_axis_ticks_are_bounded axis :
  (List.length (P.axis_ticks axis) <= 7)%nat.
Proof. unfold P.axis_ticks. rewrite length_map, length_seq. lia. Qed.

Theorem line_geometry_connects_points_in_order :
  P.line_path true [("40", "210"); ("440", "30")] = "M 40 210 L 440 30 " /\
  P.point_path [("40", "210"); ("440", "30")] =
    "M 40 210 m -2 0 l 4 0 m -2 -2 l 0 4 M 440 30 m -2 0 l 4 0 m -2 -2 l 0 4 ".
Proof. split; reflexivity. Qed.

Theorem bar_geometry_returns_to_the_zero_baseline :
  P.bar_path "120" 4 [("40", "210"); ("440", "30")] =
    "M 40 120 m -2 0 V 210 h 4 V 120 Z M 440 120 m -2 0 V 30 h 4 V 120 Z ".
Proof. reflexivity. Qed.

Theorem successful_chart_has_a_bounded_nontrivial_plot properties drawing :
  P.chart properties = Outcome.Good drawing ->
  G.width drawing = 480%positive /\
  G.height drawing = 204%positive /\
  exists points,
    Outcome.traverse (P.data_point (X.property_text "x" properties) (X.property_text "y" properties))
      (P.chart_rows properties) = Outcome.Good points /\
    exists marks, G.primitives drawing =
      List.app (P.chart_axes properties (P.numeric_x_axis points) (P.y_axis points) points) marks /\
    (1 <= List.length marks <= 2)%nat.
Proof.
  intros Admitted.
  unfold P.chart in Admitted.
  destruct(negb(E.valid_field_path(X.property_text "x" properties)&&
    E.valid_field_path(X.property_text "y" properties)))eqn:Paths;try discriminate.
  cbn [Outcome.bind] in Admitted.
  destruct (Outcome.traverse
    (P.data_point (X.property_text "x" properties) (X.property_text "y" properties))
    (P.chart_rows properties)) as [points|reason] eqn:Rows;
    cbn [Outcome.bind] in Admitted; try discriminate.
  inversion Admitted; subst drawing.
  repeat split; try reflexivity.
  exists points. split; [reflexivity|].
  eexists.
  split; [reflexivity|].
  unfold P.chart_marks.
  destruct (String.eqb properties.(X.description).(V.component_tag) "bar-chart"); simpl; lia.
Qed.
