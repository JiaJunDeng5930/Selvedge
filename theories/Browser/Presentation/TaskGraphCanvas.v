From Stdlib Require Import String List Bool NArith ZArith.
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
 if compact then FlowGeometry true 70 126 48 12 16
 else FlowGeometry false 195 70 86 26 24.
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
Definition flow_curve {A} geometry x1 y1 a b c d x2 y2 (arrow : bool) : Graphics.primitive A :=
 if vertical geometry then
   Graphics.StrokePath
     (String.append (Graphics.curve_path y1 x1 b a d c y2 x2 false)
       (if arrow then " l -4 -8 m 4 8 l 4 -8"%string else ""%string)) Graphics.Neutral
 else Graphics.CubicCurve x1 y1 a b c d x2 y2 arrow Graphics.Neutral.
Definition flow_line {A} geometry x1 y1 x2 y2 : Graphics.primitive A :=
 if vertical geometry then Graphics.Line y1 x1 y2 x2 Graphics.Neutral
 else Graphics.Line x1 y1 x2 y2 Graphics.Neutral.

Definition adjacent_curve {A} geometry (edge : positioned_node * positioned_node) : Graphics.primitive A :=
  let '(source, target) := edge in
  let x1 := left source + along geometry in
  let x2 := left target in
  let y1 := center_y geometry source in
  let y2 := center_y geometry target in
  let middle := (x1 + x2) / 2 in
  flow_curve geometry x1 y1 middle y1 middle y2 x2 y2 true.

Definition lane_spacing : Z := 8.

Definition outside_curve {A} geometry lane (edge : positioned_node * positioned_node) : list (Graphics.primitive A) :=
  let '(source, target) := edge in
  let x1 := left source + along geometry in
  let x2 := left target in
  let y1 := center_y geometry source in
  let y2 := center_y geometry target in
  let exit := x1 + margin geometry / 2 in
  let enter := x2 - margin geometry / 2 in
  [flow_curve geometry x1 y1 exit y1 exit y1 exit lane false;
   flow_line geometry exit lane enter lane;
   flow_curve geometry enter lane enter y2 enter y2 x2 y2 true].

Record layout (A : Type) := Layout {
  nodes : list positioned_node;
  edges : Graphics.plot A
}.
Arguments Layout {A}.
Arguments nodes {A}.
Arguments edges {A}.

Definition arrange_flow {A} geometry entries routes : layout A :=
  let groups := columns (List.length entries) routes entries in
  let rows := fold_left (fun count group => Nat.max count (List.length group)) groups 0%nat in
  let content_height := extent (across geometry) (across_gap geometry) rows in
  let placed := position_nodes geometry content_height groups in
  let '(forward, outside) := partition adjacent (flat_map (position_connection placed) routes) in
  let width := 2 * margin geometry + extent (along geometry) (along_gap geometry) (List.length groups) in
  let height := 2 * margin geometry + content_height in
  let lanes := List.length outside in
  let curves := map (adjacent_curve geometry) forward ++
    flat_map (fun '(index, edge) => outside_curve geometry (height + Z.of_nat index * lane_spacing) edge)
      (combine (seq 0 lanes) outside) in
  let height := height + Z.of_nat lanes * lane_spacing in
  if vertical geometry then
    Layout (map (fun item => PositionedNode (entry item) (column item) (top item) (left item)) placed)
      (Graphics.Plot (Z.to_pos height) (Z.to_pos width) curves)
  else Layout placed (Graphics.Plot (Z.to_pos width) (Z.to_pos height) curves).

Definition arrange_nodes {A} entries routes : layout A :=
 arrange_flow conversation_geometry entries routes.

Definition arrange {A} (graph : Read.graph) : layout A :=
  arrange_nodes (A:=A) (Read.graph_nodes graph) (connections graph).
