From Stdlib Require Import String List Bool NArith ZArith.
From Selvedge.Foundation Require Import Json Numbers Utf8.
From Selvedge.Programming Require Import Graphics.
From Selvedge.Interaction.Interactive Require Import Decimal Expression Types State Local Vocabulary Sources Expand.
From Selvedge.Programming Require Import Outcome.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Open Scope Z_scope.
Record point:=Point{x_number:option Decimal.decimal;x_text:string;y_number:Decimal.decimal}.
Definition data_point x y row:=
 let vx:=get_path x row in let vy:=get_path y row in
 dy <-? from_option "Chart y field must be a finite fixed decimal"(decimal_value vy);;
 match vx with
 |JString s=>Good(Point None s dy)
 |JNumber _=>dx <-? from_option "Chart x field must be finite"(decimal_value vx);;
             Good(Point(Some dx)(Decimal.text dx)dy)
 |_=>Error "Chart x field must be numeric or a string category"end.

Record chart_axis := ChartAxis { axis_lower:Z; axis_upper:Z; axis_step:Z }.
Definition tick_step (span:Z) : Z :=
 let rough:=Z.max 1 ((span+3)/4) in
 let decade:=Z.pow 10 (Z.of_nat (Nat.pred (String.length (show_integer rough)))) in
 if rough <=? decade then decade else
 if rough <=? 2*decade then 2*decade else
 if rough <=? 5*decade then 5*decade else 10*decade.
Definition make_axis lower upper : chart_axis :=
 let step:=if lower =? upper then Decimal.scale else tick_step (upper-lower) in
 let start:=(lower/step)*step in
 let stop:=(-((-upper)/step))*step in
 ChartAxis start (Z.max (start+step) stop) step.
Definition axis_ticks axis :=
 map (fun index=>axis.(axis_lower)+Z.of_nat index*axis.(axis_step))
   (seq 0 (Nat.min 7 (S (Z.to_nat ((axis.(axis_upper)-axis.(axis_lower))/axis.(axis_step)))))).
Definition axis_coordinate origin span axis value :=
 origin*Decimal.scale +
 ((value-axis.(axis_lower))*span*Decimal.scale)/(axis.(axis_upper)-axis.(axis_lower)).
Definition axis_pixel origin span axis value :=
 (axis_coordinate origin span axis value + Decimal.scale/2)/Decimal.scale.
Definition plot_left : Z := 104.
Definition plot_right : Z := 442.
Definition plot_top : Z := 30.
Definition plot_bottom : Z := 150.
Definition plot_width := plot_right-plot_left.
Definition plot_height := plot_bottom-plot_top.
Definition category_coordinate index total :=
 plot_left*Decimal.scale + ((2*Z.of_nat index+1)*plot_width*Decimal.scale)/(2*Z.of_nat (Nat.max 1 total)).
Definition chart_x axis index total p :=
 match axis,p.(x_number) with
 |Some domain,Some value=>axis_coordinate (plot_left+10) (plot_width-20) domain (Decimal.units value)
 |_,_=>category_coordinate index total end.
Definition chart_y axis value := axis_coordinate plot_bottom (-plot_height) axis value.
Definition chart_coordinates (x_axis:option chart_axis) y_axis points :=
 let total:=List.length points in
 map (fun '(index,p)=>(Decimal.render (chart_x x_axis index total p),
                       Decimal.render (chart_y y_axis (Decimal.units p.(y_number)))))
   (combine (seq 0 total) points).

Definition extend_axis '(lower,upper) value := (Z.min lower value,Z.max upper value).
Definition numeric_x_axis points :=
 let values:=fold_right (fun p rest=>match p.(x_number) with
   |Some value=>Decimal.units value::rest|None=>rest end) [] points in
 match values with
 |first::rest=>if Nat.eqb (List.length values) (List.length points) then
   let '(lower,upper):=fold_left extend_axis rest (first,first) in Some(make_axis lower upper)
   else None
 |_=>None end.
Definition y_axis points :=
 let '(lower,upper):=fold_left (fun bounds p=>extend_axis bounds (Decimal.units p.(y_number))) points (0,0) in
 make_axis lower upper.
Definition axis_title p label binding :=
 let title:=property_text label p in
 if String.eqb title "" then property_text binding p else title.
Definition x_title p := axis_title p "x-label" "x".
Definition y_title p := axis_title p "y-label" "y".
Definition label_width (scalar:N) : nat := if (scalar <? 128)%N then 9 else 16.
Fixpoint label_prefix budget (chunks:list(N*string)) :=
 match chunks with
 |[]=>[]
 |(scalar,text)::rest=>let width:=label_width scalar in
   if Nat.leb width budget then (scalar,text)::label_prefix (budget-width)%nat rest else [] end.
Definition fit_label budget label :=
 match Utf8.chunks label with
 |Some chunks=>let width:=fold_left (fun total chunk=>(total+label_width (fst chunk))%nat) chunks 0%nat in
   if Nat.leb width budget then label
   else String.append (Utf8.render_chunks (label_prefix (budget-16)%nat chunks)) "…"
 (* DEFENSE: Only valid UTF-8 is admitted in chart data. An invalid observation
    cannot be displayed as a partial byte sequence. *)
 |None=>"" end.
Definition y_ticks axis : list(primitive input) :=
 List.concat (map (fun tick=>
   let y:=axis_pixel plot_bottom (-plot_height) axis tick in
   [Line plot_left y plot_right y (if tick =? 0 then Neutral else Muted);
    Label (plot_left-10) (y+5) LabelEnd (Decimal.render tick) Muted]) (axis_ticks axis)).
Definition x_ticks axis : list(primitive input) :=
 let ticks:=axis_ticks axis in
 let label anchor tick:=Label (axis_pixel (plot_left+10) (plot_width-20) axis tick)
   (plot_bottom+21) anchor (Decimal.render tick) Muted in
 (* Close numeric values can require all six fractional digits at large
    magnitudes. Keep exact endpoints without crowding their text. *)
 if existsb (fun tick=>Nat.ltb 10 (String.length (Decimal.render tick))) ticks
 then [label LabelStart axis.(axis_lower);label LabelEnd axis.(axis_upper)]
 else map (label LabelMiddle) ticks.
Definition category_ticks points : list(primitive input) :=
 let total:=List.length points in
 let shown:=Nat.min 6 total in
 let budget:=Nat.min 132 (Z.to_nat plot_width/Nat.max 1 shown-6)%nat in
 flat_map (fun sample=>
   let index:=(sample*Nat.pred total/Nat.max 1 (Nat.pred shown))%nat in
   match nth_error points index with
   |Some p=>let x:=(category_coordinate index total+Decimal.scale/2)/Decimal.scale in
     [Label x (plot_bottom+21) LabelMiddle (fit_label budget p.(x_text)) Muted]
   |None=>[] end) (seq 0 shown).
Definition chart_axes p x_axis y_axis points : list(primitive input) :=
 y_ticks y_axis++[Line plot_left plot_top plot_left plot_bottom Muted]++
 (match x_axis with Some axis=>x_ticks axis|None=>category_ticks points end)++
 [Label plot_left 19 LabelStart (fit_label 350 (y_title p)) Neutral;
  Label ((plot_left+plot_right)/2) (plot_bottom+42) LabelMiddle (fit_label 350 (x_title p)) Neutral].
Fixpoint line_path (first:bool) (points:list(string*string)) :string :=
 match points with []=>""|(x,y)::rest=>
 ((if first then "M " else "L ")++x++" "++y++" "++line_path false rest)%string end.
Fixpoint point_path (points:list(string*string)) :string :=
 match points with []=>""|(x,y)::rest=>
 ("M "++x++" "++y++" m -2 0 l 4 0 m -2 -2 l 0 4 "++point_path rest)%string end.
Fixpoint bar_path (baseline:string) (width:nat) (points:list(string*string)) :string :=
 match points with []=>""|(x,y)::rest=>
 ("M "++x++" "++baseline++" m -"++show_nat ((width/2)%nat)++" 0 V "++y++" h "++show_nat width++
  " V "++baseline++" Z "++bar_path baseline width rest)%string end.
Definition bar_width (count:nat) := Nat.min 22 (Nat.max 1 (Nat.div 240 (Nat.max 1 count))).
Definition chart_marks (is_bar:bool) y_axis coordinates : list(primitive input) :=
 if is_bar then [FilledPath (bar_path (Decimal.render (chart_y y_axis 0))
                               (bar_width (List.length coordinates)) coordinates) Accent]
 else [StrokePath (line_path true coordinates) Accent;StrokePath (point_path coordinates) Accent].
Definition chart_rows p:=firstn Bounds.chart_points(property_array "data"p).
Definition chart p : outcome(plot input):=
 if negb(valid_field_path(property_text "x" p)&&valid_field_path(property_text "y" p))
 then Error "Chart x and y require nonempty field paths" else
 (* Expansion validates every row's axis types. Fixed-decimal conversion is
    only needed for the plotted prefix; values outside it do not affect it. *)
 points <-? Outcome.traverse(data_point(property_text "x"p)(property_text "y"p))(chart_rows p);;
 let x_axis:=numeric_x_axis points in let y_axis:=y_axis points in
 let coordinates:=chart_coordinates x_axis y_axis points in
 Good(Plot 480%positive 204%positive
  (chart_axes p x_axis y_axis points++
   chart_marks (String.eqb p.(description).(component_tag) "bar-chart") y_axis coordinates)).
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
