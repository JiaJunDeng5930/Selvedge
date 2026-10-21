From Stdlib Require Import String List Bool NArith ZArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Interaction Require Import Graphics.
From Selvedge.Interaction.Interactive Require Import Decimal Expression Types State Local Vocabulary Sources Expand.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Open Scope Z_scope.
Record point:=Point{x_number:option Decimal.decimal;x_label:string;y_number:Decimal.decimal}.
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
 40+(if numeric then match p.(x_number)with Some x=>fraction_coordinate lo hi x 560|None=>0 end
 else if Nat.leb total 1 then 280 else Z.quot(Z.of_nat index*560)(Z.of_nat(total-1))).
Definition point_y lo hi p:=200-fraction_coordinate lo hi p.(y_number)160.
Fixpoint line_segments numeric xlo xhi ylo yhi index total previous points:list(primitive input):=
 match points with []=>[]|p::rest=>let x:=point_x numeric xlo xhi index total p in let y:=point_y ylo yhi p in
 (match previous with Some(a,b)=>[Line a b x y Accent]|None=>[]end)++
 [Circle x y 3 Accent]++line_segments numeric xlo xhi ylo yhi(S index)total(Some(x,y))rest end.
Fixpoint bar_segments ylo yhi total index points:list(primitive input):=
 match points with []=>[]|p::rest=>
 let slot:=Z.quot 560(Z.of_nat(Nat.max 1 total))in
 let width:=Z.max 1(slot-4)in
 let x:=42+Z.of_nat index*slot in let y:=point_y ylo yhi p in
 let zero:=200-fraction_coordinate ylo yhi Decimal.zero 160 in
 Rectangle x(Z.min y zero)(Z.to_N width)(Z.to_N(Z.abs(zero-y)))Accent::bar_segments ylo yhi total(S index)rest end.
Definition chart p : outcome(plot input):=
 let raw:=property_array "data"p in
 points <-? Sources.traverse(data_point(property_text "x"p)(property_text "y"p))(firstn Bounds.chart_points raw);;
 match points with
 |[]=>Good(Plot 640%positive 260%positive[Graphics.Label 280 120 "No data"Muted])
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
 Good(Plot 640%positive 260%positive(
 [Line 40 200 600 200 Neutral;Line 40 40 40 200 Neutral;
 Graphics.Label 2 48(Decimal.text yhi)Muted;Graphics.Label 2 200(Decimal.text ylo)Muted;
 Graphics.Label 40 222 first.(x_label)Muted;Graphics.Label 480 222(match List.rev points with p::_=>p.(x_label)|_=>""end)Muted;
 Graphics.Label 40 250(property_text "x-label"p)Muted]++drawing))
 else Error "Chart x values mix numeric and categorical types"end.
Fixpoint node_index wanted index nodes:=match nodes with []=>None|node::rest=>
 match string_field "identity"node with Some id=>if String.eqb id wanted then Some index else node_index wanted(S index)rest|None=>None end end.
Definition rounded_integer d:=match Decimal.rounded_division(Decimal.units d)Decimal.scale with Some n=>n|None=>0 end.
Definition position (index:nat) zoom pan_x pan_y:=
 (40+Z.quot((60+Z.of_nat((index mod 4)%nat)*150)*Decimal.units zoom)Decimal.scale-rounded_integer pan_x,
  20+Z.quot((40+Z.of_nat((index/4)%nat)*100)*Decimal.units zoom)Decimal.scale-rounded_integer pan_y).
Definition graph_view path b:=match State.view_at path true b with GraphView zoom x y selected=>(zoom,x,y,selected)|_ =>(Decimal.one,Decimal.zero,Decimal.zero,"")end.
Definition selected p path b:=let '(zoom,x,y,selection):=graph_view path b in
 match property "select"p with Some(JString id)=>match find_local id b.(locals)with Some l=>match canonical l with JString s=>s|_=>selection end|None=>selection end|_=>selection end.
Definition node_tone node:=match field "task"node with
 |Some task=>match bool_field "awaitingHuman"task,bool_field "working"task with Some true,_=>Warning|_,Some true=>Accent|_,_=>Neutral end
 |None=>Muted end.
Definition node_label node:=match field "task"node with Some task=>match string_field "title"task with Some s=>s|None=>"Unavailable"end|None=>"Unavailable"end.
Definition edge_line nodes zoom pan_x pan_y edge : list(primitive input):=
 match string_field "sourceIdentity"edge,string_field "targetIdentity"edge with
 |Some source,Some target=>match node_index source 0 nodes,node_index target 0 nodes with
   |Some a,Some b=>let '(x1,y1):=position a zoom pan_x pan_y in let '(x2,y2):=position b zoom pan_x pan_y in
      if String.eqb source target then [Circle x1(y1-16)16 Muted]else[Line x1 y1 x2 y2 Muted]
   |_,_=>[]end
 |_,_=>[]end.
Fixpoint graph_nodes (identity:event)(active:bool) selection zoom pan_x pan_y index nodes:list(primitive input):=
 match nodes with []=>[]|node::rest=>
 let '(x,y):=position index zoom pan_x pan_y in
 let id:=match string_field "identity"node with Some id=>id|None=>""end in
 let label:=node_label node in
 [Circle x y 12(node_tone node);Graphics.Label(x-36)(y+30)label Neutral]++
 (if String.eqb selection id then[Circle x y 18 Accent]else[])++
 (if active then[Hitbox((Types.event_key identity++"/@select/"++id)%string)(x-30)(y-24)100 64 label(ViewChanged identity(SelectNode id))]else[])++
 graph_nodes identity active selection zoom pan_x pan_y(S index)rest end.
Definition graph identity p b active :plot input:=
 let nodes:=property_array "nodes"p in let edges:=property_array "edges"p in
 let '(zoom,x,y,_):=graph_view identity.(path)b in
 Plot 640%positive 400%positive(List.concat(map(edge_line nodes zoom x y)edges)++
  graph_nodes identity active(selected p identity.(path)b)zoom x y 0 nodes).
