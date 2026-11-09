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

Definition position_nodes height (groups : list (list Read.graph_node)) :=
  flat_map (fun '(column, nodes) =>
    let x := inset + Z.of_nat column * (node_width + column_gap) in
    let y := inset + (height - extent node_height row_gap (List.length nodes)) / 2 in
    map (fun '(row, node) =>
      PositionedNode node column x (y + Z.of_nat row * (node_height + row_gap)))
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

Definition center_y node := top node + node_height / 2.

Definition adjacent_curve {A} (edge : positioned_node * positioned_node) : Graphics.primitive A :=
  let '(source, target) := edge in
  let x1 := left source + node_width in
  let x2 := left target in
  let y1 := center_y source in
  let y2 := center_y target in
  let middle := (x1 + x2) / 2 in
  Graphics.CubicCurve x1 y1 middle y1 middle y2 x2 y2 true Graphics.Neutral.

Definition lane_spacing : Z := 8.

Definition outside_curve {A} lane (edge : positioned_node * positioned_node) : list (Graphics.primitive A) :=
  let '(source, target) := edge in
  let x1 := left source + node_width in
  let x2 := left target in
  let y1 := center_y source in
  let y2 := center_y target in
  let exit := x1 + inset / 2 in
  let enter := x2 - inset / 2 in
  (* Route skipped columns and feedback below the cards, leaving the source
     on its right and entering the target on its left even for a self-loop. *)
  [Graphics.CubicCurve x1 y1 exit y1 exit y1 exit lane false Graphics.Neutral;
   Graphics.Line exit lane enter lane Graphics.Neutral;
   Graphics.CubicCurve enter lane enter y2 enter y2 x2 y2 true Graphics.Neutral].

Record layout (A : Type) := Layout {
  nodes : list positioned_node;
  edges : Graphics.plot A
}.
Arguments Layout {A}.
Arguments nodes {A}.
Arguments edges {A}.

Definition arrange {A} (graph : Read.graph) : layout A :=
  let routes := connections graph in
  let entries := Read.graph_nodes graph in
  let groups := columns (List.length entries) routes entries in
  let rows := fold_left (fun count group => Nat.max count (List.length group)) groups 0%nat in
  let content_height := extent node_height row_gap rows in
  let placed := position_nodes content_height groups in
  let '(forward, outside) := partition adjacent (flat_map (position_connection placed) routes) in
  let width := 2 * inset + extent node_width column_gap (List.length groups) in
  let height := 2 * inset + content_height in
  let lanes := List.length outside in
  let curves := map adjacent_curve forward ++
    flat_map (fun '(index, edge) => outside_curve (height + Z.of_nat index * lane_spacing) edge)
      (combine (seq 0 lanes) outside) in
  Layout placed (Graphics.Plot (Z.to_pos width) (Z.to_pos (height + Z.of_nat lanes * lane_spacing)) curves).
