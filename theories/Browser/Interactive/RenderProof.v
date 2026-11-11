From Stdlib Require Import String List Arith Lia.
From Selvedge.Foundation Require Import Numbers.
From Selvedge.Interaction Require Import CodeSource.
From Selvedge.Browser.Scene Require Surface.
From Selvedge.Interaction.Interactive Require Import Bounds Types Registry Expand Plot.
From Selvedge.Browser.Interactive Require Import Render.
Import ListNotations.
Open Scope string_scope.

Theorem chart_accessible_values_keep_order event_id properties index row :
  nth_error (Plot.chart_rows properties) index = Some row ->
  match Surface.node_meaning (chart_summary_table event_id properties) with
  | Surface.Table _ _ rows => nth_error rows index
  | _ => None end = Some [scalar_text (Expression.get_path (property_text "x" properties) row);
                         scalar_text (Expression.get_path (property_text "y" properties) row)].
Proof. intros Row. cbn [chart_summary_table Surface.node_meaning].
  rewrite nth_error_map, Row. reflexivity. Qed.

Theorem over_budget_presentation_is_replaced identity state prepared nodes budget :
  Bounds.expanded_components < expansion_cost 64 nodes + fst(presentation_diagnostics state prepared nodes) ->
  admitted_content identity state prepared nodes budget =
    [diagnostic_node (String.append (CodeSource.key identity) "/@presentation-limit") "ui"
      "交互界面展开超过 4096 个节点；局部输入已保留，请查看源码。"].
Proof. intros Over. unfold admitted_content.
  destruct (presentation_diagnostics state prepared nodes) as [count issues].
  change (Bounds.expanded_components < expansion_cost 64 nodes + count) in Over.
  rewrite (proj2 (Nat.leb_gt _ _) Over). reflexivity. Qed.

Theorem admitted_presentation_keeps_actual_render identity state prepared nodes budget :
  expansion_cost 64 nodes + fst(presentation_diagnostics state prepared nodes) <= Bounds.expanded_components ->
  admitted_content identity state prepared nodes budget =
    (fst (render_nodes 64 identity state prepared nodes budget)++
     diagnostic_nodes identity(snd(presentation_diagnostics state prepared nodes)))%list.
Proof. intros Within. unfold admitted_content.
  destruct (presentation_diagnostics state prepared nodes) as [count issues].
  change (expansion_cost 64 nodes + count <= Bounds.expanded_components) in Within.
  rewrite (proj2 (Nat.leb_le _ _) Within). reflexivity. Qed.
