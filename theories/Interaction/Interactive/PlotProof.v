From Stdlib Require Import String List Bool Arith Lia ZArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Interaction Require Import Graphics.
From Selvedge.Interaction.Interactive Require Import Bounds Decimal Expression Plot.
Import ListNotations.
Open Scope string_scope.
Open Scope Z_scope.

Module P := Selvedge.Interaction.Interactive.Plot.
Module D := Selvedge.Interaction.Interactive.Decimal.
Module E := Selvedge.Interaction.Interactive.Expression.
Module X := Selvedge.Interaction.Interactive.Expand.
Module Src := Selvedge.Interaction.Interactive.Sources.
Module V := Selvedge.Interaction.Interactive.Vocabulary.
Module G := Selvedge.Interaction.Graphics.

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

Theorem data_point_admits_category_x x_path y_path row category y_value :
  get_path x_path row = JString category ->
  E.decimal_value (get_path y_path row) = Some y_value ->
  P.data_point x_path y_path row = E.Good (P.Point None y_value).
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
  P.data_point x_path y_path row = E.Good (P.Point (Some x_value) y_value).
Proof.
  intros X FiniteX FiniteY.
  unfold P.data_point.
  rewrite X, FiniteY, FiniteX.
  reflexivity.
Qed.

Theorem data_point_rejects_non_decimal_y x_path y_path row :
  E.decimal_value (get_path y_path row) = None ->
  P.data_point x_path y_path row = E.Error "Chart y field must be a finite fixed decimal".
Proof.
  intros InvalidY.
  unfold P.data_point.
  rewrite InvalidY.
  reflexivity.
Qed.

Theorem data_point_rejects_boolean_x x_path y_path row enabled y_value :
  get_path x_path row = JBool enabled ->
  E.decimal_value (get_path y_path row) = Some y_value ->
  P.data_point x_path y_path row = E.Error "Chart x field must be numeric or a string category".
Proof.
  intros X FiniteY.
  unfold P.data_point.
  rewrite X, FiniteY.
  reflexivity.
Qed.

Theorem chart_magnitude_stays_within_the_decimal_range project points magnitude :
  P.magnitude project points = E.Good magnitude ->
  Z.abs (D.units magnitude) <= D.limit.
Proof.
  unfold P.magnitude, E.from_option.
  destruct (D.checked
    (fold_left (fun value point => Z.max value (Z.abs (project point))) points 1))
    as [value|] eqn:Checked; simpl; try discriminate.
  intros Admitted.
  inversion Admitted; subst magnitude.
  unfold D.checked in Checked.
  destruct (Z_le_dec (Z.abs
    (fold_left (fun value point => Z.max value (Z.abs (project point))) points 1)) D.limit)
    as [Within|Outside]; inversion Checked; exact Within.
Qed.

Definition negative_one := P.chart_whole (-1)%Z eq_refl.
Definition positive_one := P.chart_whole 1%Z eq_refl.
Definition negative_two := P.chart_whole (-2)%Z eq_refl.
Definition positive_two := P.chart_whole 2%Z eq_refl.
Definition zero := P.chart_whole 0%Z eq_refl.

Theorem negative_y_lies_below_the_zero_baseline :
  P.chart_coordinate P.y_origin P.y_span false negative_one positive_one =
    E.Good "210".
Proof. vm_compute. reflexivity. Qed.

Theorem zero_y_lies_on_the_zero_baseline :
  P.chart_coordinate P.y_origin P.y_span false zero positive_one =
    E.Good "120".
Proof. vm_compute. reflexivity. Qed.

Theorem numeric_x_uses_both_sides_of_zero :
  P.chart_coordinate P.x_origin P.x_span true negative_two positive_two = E.Good "40" /\
  P.chart_coordinate P.x_origin P.x_span true positive_two positive_two = E.Good "440".
Proof. vm_compute. repeat split; reflexivity. Qed.

Theorem line_geometry_connects_points_in_order :
  P.line_path true [("40", "210"); ("440", "30")] = "M 40 210 L 440 30 " /\
  P.point_path [("40", "210"); ("440", "30")] =
    "M 40 210 m -2 0 l 4 0 m -2 -2 l 0 4 M 440 30 m -2 0 l 4 0 m -2 -2 l 0 4 ".
Proof. split; reflexivity. Qed.

Theorem bar_geometry_returns_to_the_zero_baseline :
  P.bar_path 4 [("40", "210"); ("440", "30")] =
    "M 40 120 m -2 0 V 210 h 4 V 120 Z M 440 120 m -2 0 V 30 h 4 V 120 Z ".
Proof. reflexivity. Qed.

Theorem successful_chart_has_a_bounded_nontrivial_plot properties drawing :
  P.chart properties = E.Good drawing ->
  G.width drawing = 480%positive /\
  G.height drawing = 240%positive /\
  exists values,
    G.primitives drawing =
      List.app [G.Line 40 20 40 220 G.Neutral; G.Line 40 120 460 120 G.Neutral] values /\
    (1 <= List.length values <= 2)%nat.
Proof.
  intros Admitted.
  unfold P.chart in Admitted.
  cbn [E.bind] in Admitted.
  destruct (Src.traverse
    (P.data_point (X.property_text "x" properties) (X.property_text "y" properties))
    (P.chart_rows properties)) as [points|reason] eqn:Rows;
    cbn [E.bind] in Admitted; try discriminate.
  destruct (P.homogeneous_x_axis points) eqn:Homogeneous;
    cbn [E.bind] in Admitted; try discriminate.
  destruct (P.magnitude
    (fun point => match P.x_number point with Some x => D.units x | None => 0 end) points)
    as [x_domain|reason] eqn:XDomain; cbn [E.bind] in Admitted; try discriminate.
  destruct (P.magnitude (fun point => D.units (P.y_number point)) points)
    as [y_domain|reason] eqn:YDomain; cbn [E.bind] in Admitted; try discriminate.
  destruct (P.chart_coordinates x_domain y_domain 0 (List.length points) points)
    as [coordinates|reason] eqn:Coordinates; cbn [E.bind] in Admitted; try discriminate.
  inversion Admitted; subst drawing.
  repeat split; try reflexivity.
  exists (if String.eqb properties.(X.description).(V.component_tag) "bar-chart"
    then [G.FilledPath (P.bar_path (P.bar_width (List.length points)) coordinates) G.Neutral]
    else [G.StrokePath (P.line_path true coordinates) G.Neutral;
      G.StrokePath (P.point_path coordinates) G.Neutral]).
  split; [reflexivity|].
  destruct (String.eqb properties.(X.description).(V.component_tag) "bar-chart"); simpl; lia.
Qed.
