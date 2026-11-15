From Stdlib Require Import String List Bool NArith ZArith.
From Selvedge.Foundation Require ListCount.
From Selvedge.Programming Require Import Graphics.
From Selvedge.Interaction.Experience Require Read.
Import ListNotations.
Open Scope Z_scope.

Definition node_width : Z := 195.
Definition node_height : Z := 54.
Definition inset : Z := 32.
Definition column_gap : Z := 158.
Definition row_gap : Z := 36.
Record flow_geometry := FlowGeometry {
  vertical : bool;
  along : Z;
  across : Z;
  along_gap : Z;
  across_gap : Z;
  margin : Z
}.
Definition conversation_geometry :=
 FlowGeometry false node_width node_height column_gap row_gap inset.
Definition workflow_geometry (compact : bool) :=
 if compact then FlowGeometry true 98 136 56 16 18
 else FlowGeometry false 168 76 84 28 20.
Definition card_width geometry := if vertical geometry then across geometry else along geometry.
Definition card_height geometry := if vertical geometry then along geometry else across geometry.

Definition connections (graph : Read.graph) : list (string * string) :=
  flat_map (fun node =>
    let source := Read.node_key node in
    let outgoing := filter (fun rule => String.eqb source (Read.rule_source rule))
      (Read.graph_rules graph) in
    let targets := flat_map (fun rule => map Read.action_target (Read.rule_actions rule)) outgoing in
    map (fun target => (source, target)) (nodup String.string_dec targets))
    (Read.graph_nodes graph).

Definition has_predecessor edges nodes node :=
  existsb (fun '(source, target) =>
    String.eqb target (Read.node_key node) && negb (String.eqb source target) &&
    existsb (fun entry => String.eqb source (Read.node_key entry)) nodes) edges.

Fixpoint columns (fuel : nat) edges nodes : list (list Read.graph_node) :=
  match fuel, nodes with
  | S fuel, first :: rest =>
      match partition (fun node => negb (has_predecessor edges nodes node)) nodes with
      | ([], _) =>
          (* With only cyclic dependencies left, place one node to keep the
             layout progressing. The original edge directions are retained. *)
          [first] :: columns fuel edges rest
      | (ready, waiting) => ready :: columns fuel edges waiting
      end
  | _, _ => []
  end.

Record positioned_node := PositionedNode {
  entry : Read.graph_node;
  column : nat;
  left : Z;
  top : Z
}.

Definition extent item gap count :=
  Z.of_nat count * item + Z.of_nat (Nat.pred count) * gap.

Definition position_nodes geometry height (groups : list (list Read.graph_node)) :=
  flat_map (fun '(column, nodes) =>
    let x := margin geometry + Z.of_nat column * (along geometry + along_gap geometry) in
    let y := margin geometry + (height - extent (across geometry) (across_gap geometry) (List.length nodes)) / 2 in
    map (fun '(row, node) =>
      PositionedNode node column x (y + Z.of_nat row * (across geometry + across_gap geometry)))
      (combine (seq 0 (List.length nodes)) nodes))
    (combine (seq 0 (List.length groups)) groups).

Definition position_of nodes key :=
  find (fun node => String.eqb key (Read.node_key (entry node))) nodes.

Definition position_connection nodes (edge : string * string) :=
  match position_of nodes (fst edge), position_of nodes (snd edge) with
  | Some source, Some target => [(source, target)]
  | _, _ => []
  end.

Definition adjacent (edge : positioned_node * positioned_node) :=
  Nat.eqb (S (column (fst edge))) (column (snd edge)).

Definition center_y geometry node := top node + across geometry / 2.

(* Route in the flow's own coordinates. Convert endpoints and arrowheads
   together so both orientations enter the destination's near edge. *)
Definition flow_curve {A} geometry x1 y1 a b c d x2 y2 (arrow : bool) tone : Graphics.primitive A :=
 if vertical geometry then
   Graphics.StrokePath
     (String.append (Graphics.curve_path y1 x1 b a d c y2 x2 false)
       (if arrow then " l -4 -8 m 4 8 l 4 -8"%string else ""%string)) tone
 else Graphics.CubicCurve x1 y1 a b c d x2 y2 arrow tone.
Definition flow_line {A} geometry x1 y1 x2 y2 tone : Graphics.primitive A :=
 if vertical geometry then Graphics.Line y1 x1 y2 x2 tone
 else Graphics.Line x1 y1 x2 y2 tone.

Definition adjacent_curve {A} geometry (edge : positioned_node * positioned_node) y1 y2 : Graphics.primitive A :=
  let '(source, target) := edge in
  let x1 := left source + along geometry in
  let x2 := left target in
  let middle := (x1 + x2) / 2 in
  flow_curve geometry x1 y1 middle y1 middle y2 x2 y2 true Graphics.Neutral.

Definition outside_curve {A} geometry lane index (spread : bool) shift nodes
 (edge : positioned_node * positioned_node) y1 y2 : list (Graphics.primitive A) :=
  let '(source, target) := edge in
  let x1 := left source + along geometry in
  let x2 := left target in
  let offset := margin geometry / 2 + (if spread then 6 * Z.of_nat (index mod 4)%nat else 0) in
  let exit := x1 + offset in
  let enter := x2 - offset in
  let tone := if spread then if Nat.even index then Graphics.Accent else Graphics.Success else Graphics.Neutral in
  let above := lane <? top target + shift in
  let side_clear := negb (existsb (fun node => Nat.eqb (column node) (column target) &&
    (if above then top node <? top target else top target <? top node)) nodes) in
  let start := flow_curve geometry x1 y1 exit y1 exit y1 exit lane false tone in
  if spread && side_clear && (column source <? column target)%nat then
    let x := x2 + along geometry / 2 in
    let y := top target + shift + (if above then 0 else across geometry) in
    let tail := y + (if above then -8 else 8) in
    [start; flow_curve geometry exit lane x lane x lane x y false tone;
      flow_line geometry (x - 4) tail x y tone; flow_line geometry (x + 4) tail x y tone]
  else [start; flow_line geometry exit lane enter lane tone;
        flow_curve geometry enter lane enter y2 enter y2 x2 y2 true tone].

Record layout (A : Type) := Layout {
  nodes : list positioned_node;
  edges : Graphics.plot A
}.
Arguments Layout {A}.
Arguments nodes {A}.
Arguments edges {A}.

Definition port_coordinate geometry (spread : bool) (pairs : list (positioned_node * positioned_node)) index project node :=
 if spread then
  let same edge := String.eqb (Read.node_key (entry (project edge))) (Read.node_key (entry node)) in
  let count := Z.of_nat (ListCount.count same pairs) in
  let rank := Z.of_nat (ListCount.count same (firstn index pairs)) in
  top node + 5 + (across geometry - 10) * (rank + 1) / (count + 1)
 else center_y geometry node.
Definition arrange_flow {A} geometry (spread : bool) entries routes : layout A :=
  let groups := columns (List.length entries) routes entries in
  let rows := fold_left (fun count group => Nat.max count (List.length group)) groups 0%nat in
  let content_height := extent (across geometry) (across_gap geometry) rows in
  let placed := position_nodes geometry content_height groups in
  let pairs := flat_map (position_connection placed) routes in
  let outside_count := ListCount.count (fun entry=>negb (adjacent entry)) pairs in
  let lane_spacing := if spread then 16 else 8 in
  let reserved_above := if spread then lane_spacing * Z.of_nat (Nat.div2 (S outside_count)) else 0 in
  let shift item := PositionedNode (entry item) (column item) (left item) (top item + reserved_above) in
  let connections := map (fun '(index, (source, target)) =>
    ((source, target),(reserved_above + port_coordinate geometry spread pairs index fst source,
                      reserved_above + port_coordinate geometry spread pairs index snd target)))
    (combine (seq 0 (List.length pairs)) pairs) in
  let '(forward, outside) := partition (fun connection=>adjacent (fst connection)) connections in
  let width := 2 * margin geometry + extent (along geometry) (along_gap geometry) (List.length groups) in
  let height := 2 * margin geometry + content_height in
  let lanes := List.length outside in
  let curves := map (fun '(edge,(y1,y2))=>adjacent_curve geometry edge y1 y2) forward ++
    flat_map (fun '(index, (edge,(y1,y2))) =>
      let lane := if spread && Nat.even index then
        reserved_above - Z.of_nat (Nat.div2 index) * lane_spacing - lane_spacing / 2
        else height + (if spread then reserved_above + Z.of_nat (Nat.div2 index) * lane_spacing
          else Z.of_nat index * lane_spacing) in
      outside_curve geometry lane index spread reserved_above placed edge y1 y2)
      (combine (seq 0 lanes) outside) in
  let height := height + Z.of_nat lanes * lane_spacing in
  let placed := map shift placed in
  if vertical geometry then
    Layout (map (fun item => PositionedNode (entry item) (column item) (top item) (left item)) placed)
      (Graphics.Plot (Z.to_pos height) (Z.to_pos width) curves)
  else Layout placed (Graphics.Plot (Z.to_pos width) (Z.to_pos height) curves).

Definition arrange_nodes {A} entries routes : layout A :=
 arrange_flow conversation_geometry false entries routes.

Definition arrange {A} (graph : Read.graph) : layout A :=
  arrange_nodes (A:=A) (Read.graph_nodes graph) (connections graph).
