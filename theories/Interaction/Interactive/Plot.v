From Stdlib Require Import String List Bool NArith ZArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Programming Require Import Graphics.
From Selvedge.Interaction.Interactive Require Import Decimal Expression Types State Local Vocabulary Sources Expand.
From Selvedge.Programming Require Import Outcome.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Open Scope Z_scope.
Record point:=Point{x_number:option Decimal.decimal;y_number:Decimal.decimal}.
Definition data_point x y row:=
 let vx:=get_path x row in let vy:=get_path y row in
 dy <-? from_option "Chart y field must be a finite fixed decimal"(decimal_value vy);;
 match vx with
 |JString s=>Good(Point None dy)
 |JNumber _=>dx <-? from_option "Chart x field must be finite"(decimal_value vx);;Good(Point(Some dx)dy)
 |_=>Error "Chart x field must be numeric or a string category"end.
Definition chart_whole (value:Z)
 (valid:Z.leb (Z.abs(value*Decimal.scale)) Decimal.limit=true) :Decimal.decimal :=
 exist _ (value*Decimal.scale) (proj1 (Z.leb_le (Z.abs(value*Decimal.scale)) Decimal.limit) valid).
Definition x_origin:=chart_whole 240 eq_refl.
Definition y_origin:=chart_whole 120 eq_refl.
Definition x_span:=chart_whole 200 eq_refl.
Definition y_span:=chart_whole 90 eq_refl.
Definition magnitude (project:point->Z) (points:list point) :outcome Decimal.decimal :=
 from_option "Chart domain exceeds the supported decimal range"
  (Decimal.checked (fold_left (fun value p=>Z.max value (Z.abs(project p))) points 1)).
(* The original numeric axes include zero and are symmetric. Divide before
   scaling so the full admitted decimal range remains representable. *)
Definition chart_coordinate (origin span:Decimal.decimal) (add:bool)
 (value domain:Decimal.decimal) :outcome string :=
 ratio <-? from_option "Chart coordinate exceeds the supported decimal range" (Decimal.binary "/" value domain);;
 offset <-? from_option "Chart coordinate exceeds the supported decimal range" (Decimal.binary "*" span ratio);;
 result <-? from_option "Chart coordinate exceeds the supported decimal range"
  (Decimal.binary (if add then "+" else "-") origin offset);;
 Good(Decimal.text result).
Definition chart_x domain index total p :outcome string :=
 match p.(x_number) with
 |Some value=>chart_coordinate x_origin x_span true value domain
 |None=>Good(show_nat ((40+index*400/Nat.max 1(total-1))%nat)) end.
Fixpoint chart_coordinates (x_domain y_domain:Decimal.decimal) (index total:nat)
 (points:list point) :outcome(list(string*string)) :=
 match points with
 |[]=>Good[]
 |p::rest=>x <-? chart_x x_domain index total p;;
  y <-? chart_coordinate y_origin y_span false p.(y_number) y_domain;;
  rest <-? chart_coordinates x_domain y_domain (S index) total rest;;Good((x,y)::rest) end.
Fixpoint line_path (first:bool) (points:list(string*string)) :string :=
 match points with []=>""|(x,y)::rest=>
 ((if first then "M " else "L ")++x++" "++y++" "++line_path false rest)%string end.
Fixpoint point_path (points:list(string*string)) :string :=
 match points with []=>""|(x,y)::rest=>
 ("M "++x++" "++y++" m -2 0 l 4 0 m -2 -2 l 0 4 "++point_path rest)%string end.
Fixpoint bar_path (width:nat) (points:list(string*string)) :string :=
 match points with []=>""|(x,y)::rest=>
 ("M "++x++" 120 m -"++show_nat ((width/2)%nat)++" 0 V "++y++" h "++show_nat width++
  " V 120 Z "++bar_path width rest)%string end.
Definition bar_width (count:nat) := Nat.min 20 (Nat.max 1 (Nat.div 320 (Nat.max 1 count))).
Definition chart_rows p:=firstn Bounds.chart_points(property_array "data"p).
Definition chart p : outcome(plot input):=
 if negb(valid_field_path(property_text "x" p)&&valid_field_path(property_text "y" p))
 then Error "Chart x and y require nonempty field paths" else
 (* Expansion validates every row's axis types. Fixed-decimal conversion is
    only needed for the plotted prefix; values outside it do not affect it. *)
 points <-? Outcome.traverse(data_point(property_text "x"p)(property_text "y"p))(chart_rows p);;
 x_domain <-? magnitude (fun p=>match p.(x_number) with Some x=>Decimal.units x|None=>0 end) points;;
 y_domain <-? magnitude (fun p=>Decimal.units p.(y_number)) points;;
 coordinates <-? chart_coordinates x_domain y_domain 0 (List.length points) points;;
 let values:=if String.eqb p.(description).(component_tag) "bar-chart"
  then [FilledPath (bar_path (bar_width (List.length points)) coordinates) Neutral]
  else [StrokePath (line_path true coordinates) Neutral;StrokePath (point_path coordinates) Neutral] in
 Good(Plot 480%positive 240%positive
  ([Line 40 20 40 220 Neutral;Line 40 120 460 120 Neutral]++values)).
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
 match Expand.graph_selection_target p with Some id=>match find_local id b.(locals)with
 |Some l=>match canonical l with JString s=>s|_=>selection end|None=>selection end|_=>selection end.
Definition graph_extent count zoom fit pan_x pan_y:=
 fold_left(fun '(width,height) index=>let '(x,y):=position index zoom fit pan_x pan_y in
  (Z.max width(x+graph_width zoom+80),Z.max height(y+graph_height zoom+80)))(seq 0 count)(240,240).
Definition edge_curve nodes zoom fit pan_x pan_y edge : list(primitive input):=
 match string_field "sourceIdentity"edge,string_field "targetIdentity"edge with
 |Some source,Some target=>match node_index source 0 nodes,node_index target 0 nodes with
   |Some a,Some b=>let '(x1,y1):=position a zoom fit pan_x pan_y in let '(x2,y2):=position b zoom fit pan_x pan_y in
      let x:=x1+graph_width zoom in let y:=y1+Z.quot(graph_height zoom)2 in
      if String.eqb source target then
       [CubicCurve x y (x+60) (Z.max 0(y-60)) (x+60) (y+60) x (y+10) false Neutral]
      else let target_y:=y2+Z.quot(graph_height zoom)2 in
       [CubicCurve x y (x+30) y (Z.max 0(x2-30)) target_y x2 target_y true Neutral]
   |_,_=>[]end
 |_,_=>[]end.
Definition graph identity p b :plot input:=
 let nodes:=property_array "nodes"p in let edges:=property_array "edges"p in
 let '(zoom,x,y,fit,_):=graph_view identity.(path)b in
 let '(width,height):=graph_extent(List.length nodes)zoom fit x y in
 Plot(Z.to_pos width)(Z.to_pos height)(List.concat(map(edge_curve nodes zoom fit x y)edges)).
