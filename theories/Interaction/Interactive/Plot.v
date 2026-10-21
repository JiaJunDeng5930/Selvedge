From Stdlib Require Import String List Bool NArith ZArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Interaction Require Import Graphics.
From Selvedge.Interaction.Interactive Require Import Decimal Expression Types State Local Vocabulary Sources Expand.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Open Scope Z_scope.
Record point:=Point{x_number:option Decimal.decimal;x_label:string;y_number:Decimal.decimal}.
Definition axis_label p axis:=let label:=property_text(axis++"-label")p in
 if String.eqb label ""then property_text axis p else label.
Definition data_point x y row:=
 let vx:=get_path x row in let vy:=get_path y row in
 dy <-? from_option "Chart y field must be a finite fixed decimal"(decimal_value vy);;
 match vx with
 |JString s=>Good(Point None s dy)
 |JNumber _=>dx <-? from_option "Chart x field must be finite"(decimal_value vx);;Good(Point(Some dx)(Decimal.text dx)dy)
 |_=>Error "Chart x field must be numeric or a string category"end.
Definition minimum a b:=if Decimal.compare "<"a b then a else b.
Definition maximum a b:=if Decimal.compare ">"a b then a else b.
Definition fraction_coordinate(lo hi value:Decimal.decimal)(extent:Z):Z:=
 let span:=Decimal.units hi-Decimal.units lo in
 if Z.eqb span 0 then Z.quot extent 2 else
 match Decimal.rounded_division((Decimal.units value-Decimal.units lo)*extent)span with Some n=>n|None=>0 end.
Definition point_x (numeric:bool) lo hi index total p:=
 40+(if numeric then match p.(x_number)with Some x=>fraction_coordinate lo hi x 420|None=>0 end
 else if Nat.leb total 1 then 210 else Z.quot(Z.of_nat index*420)(Z.of_nat(total-1))).
Definition point_y lo hi p:=220-fraction_coordinate lo hi p.(y_number)200.
Fixpoint line_segments numeric xlo xhi ylo yhi index total previous points:list(primitive input):=
 match points with []=>[]|p::rest=>let x:=point_x numeric xlo xhi index total p in let y:=point_y ylo yhi p in
 (match previous with Some(a,b)=>[Line a b x y Accent]|None=>[]end)++
 [Circle x y 3 Accent]++line_segments numeric xlo xhi ylo yhi(S index)total(Some(x,y))rest end.
Fixpoint bar_segments ylo yhi total index points:list(primitive input):=
 match points with []=>[]|p::rest=>
 let slot:=Z.quot 420(Z.of_nat(Nat.max 1 total))in
 let width:=Z.max 1(slot-4)in
 let x:=42+Z.quot(Z.of_nat index*420)(Z.of_nat(Nat.max 1 total)) in let y:=point_y ylo yhi p in
 let zero:=220-fraction_coordinate ylo yhi Decimal.zero 200 in
 Rectangle x(Z.min y zero)(Z.to_N width)(Z.to_N(Z.abs(zero-y)))Accent::bar_segments ylo yhi total(S index)rest end.
Definition chart_rows p:=firstn Bounds.chart_points(property_array "data"p).
Definition chart p : outcome(plot input):=
 points <-? Sources.traverse(data_point(property_text "x"p)(property_text "y"p))(chart_rows p);;
 match points with
 |[]=>Good(Plot 480%positive 240%positive[Graphics.Label 200 120 "No data"Muted])
 |first::rest=>
 let numeric:=match first.(x_number)with Some _=>true|None=>false end in
 if forallb(fun p=>Bool.eqb numeric(match p.(x_number)with Some _=>true|None=>false end))rest then
 let ylo:=fold_left(fun n p=>minimum n p.(y_number))rest first.(y_number)in
 let yhi:=fold_left(fun n p=>maximum n p.(y_number))rest first.(y_number)in
 let is_bar:=String.eqb p.(description).(component_tag)"bar-chart"in
 let ylo:=if is_bar then minimum Decimal.zero ylo else ylo in
 let yhi:=if is_bar then maximum Decimal.zero yhi else yhi in
 let xfirst:=match first.(x_number)with Some x=>x|None=>Decimal.zero end in
 let xlo:=fold_left(fun n p=>match p.(x_number)with Some x=>minimum n x|None=>n end)rest xfirst in
 let xhi:=fold_left(fun n p=>match p.(x_number)with Some x=>maximum n x|None=>n end)rest xfirst in
 let drawing:=if is_bar then bar_segments ylo yhi(List.length points)0 points
   else line_segments numeric xlo xhi ylo yhi 0(List.length points)None points in
 Good(Plot 480%positive 240%positive(
 [Line 40 220 460 220 Neutral;Line 40 20 40 220 Neutral;
 Graphics.Label 2 30(Decimal.text yhi)Muted;Graphics.Label 2 220(Decimal.text ylo)Muted;
 Graphics.Label 40 235 first.(x_label)Muted;Graphics.Label 360 235(match List.rev points with p::_=>p.(x_label)|_=>""end)Muted]++drawing))
 else Error "Chart x values mix numeric and categorical types"end.
Fixpoint node_index wanted index nodes:=match nodes with []=>None|node::rest=>
 match string_field "identity"node with Some id=>if String.eqb id wanted then Some index else node_index wanted(S index)rest|None=>None end end.
Definition rounded_integer d:=match Decimal.rounded_division(Decimal.units d)Decimal.scale with Some n=>n|None=>0 end.
(* Positions belong to topology and the reader's viewport. Task status changes
   only the node content, so they cannot move a node or reset navigation. *)
Definition graph_width zoom:=Z.max 80(Z.quot(160*Decimal.units zoom)Decimal.scale).
Definition graph_height zoom:=Z.max 80(Z.quot(120*Decimal.units zoom)Decimal.scale).
(* At 25% zoom the original 50px stride overlapped the 80px minimum node.
   Derive spacing from the same enclosure used for controls and edge centers. *)
Definition graph_gap zoom:=Z.max 20(Z.quot(40*Decimal.units zoom)Decimal.scale).
Definition position (index:nat) zoom (fit:bool) pan_x pan_y:=
 let columns:=if fit then 1%nat else 4%nat in
 ((if fit then 0 else 40)+Z.of_nat((index mod columns)%nat)*(graph_width zoom+graph_gap zoom)+rounded_integer pan_x,
  40+Z.of_nat((index/columns)%nat)*(graph_height zoom+graph_gap zoom)+rounded_integer pan_y).
Definition graph_view path b:=match State.view_at path true b with
 |GraphView zoom x y fit selected=>(zoom,x,y,fit,selected)
 |_ =>(Decimal.one,Decimal.zero,Decimal.zero,false,"")end.
Definition selected p path b:=let '(zoom,x,y,fit,selection):=graph_view path b in
 match property "select"p with Some(JString id)=>match find_local id b.(locals)with
 |Some l=>match canonical l with JString s=>s|_=>selection end|None=>selection end|_=>selection end.
Definition graph_extent count zoom fit pan_x pan_y:=
 fold_left(fun '(width,height) index=>let '(x,y):=position index zoom fit pan_x pan_y in
  (Z.max width(x+graph_width zoom+80),Z.max height(y+graph_height zoom+80)))(seq 0 count)(240,240).
Definition edge_line nodes zoom fit pan_x pan_y edge : list(primitive input):=
 match string_field "sourceIdentity"edge,string_field "targetIdentity"edge with
 |Some source,Some target=>match node_index source 0 nodes,node_index target 0 nodes with
   |Some a,Some b=>let '(x1,y1):=position a zoom fit pan_x pan_y in let '(x2,y2):=position b zoom fit pan_x pan_y in
      if String.eqb source target then [Circle(x1+Z.quot(graph_width zoom)2)(y1+12)20 Muted]
      else[Line(x1+Z.quot(graph_width zoom)2)(y1+Z.quot(graph_height zoom)2)(x2+Z.quot(graph_width zoom)2)(y2+Z.quot(graph_height zoom)2)Muted]
   |_,_=>[]end
 |_,_=>[]end.
Definition graph identity p b :plot input:=
 let nodes:=property_array "nodes"p in let edges:=property_array "edges"p in
 let '(zoom,x,y,fit,_):=graph_view identity.(path)b in
 let '(width,height):=graph_extent(List.length nodes)zoom fit x y in
 Plot(Z.to_pos width)(Z.to_pos height)(List.concat(map(edge_line nodes zoom fit x y)edges)).
