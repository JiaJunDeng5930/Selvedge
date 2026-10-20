From Stdlib Require Import String List NArith ZArith.
From Selvedge.Foundation Require Import Json Numbers.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Inductive tone:=Neutral|Accent|Success|Warning|Danger|Muted.
Definition tone_name t:=match t with Neutral=>"neutral"|Accent=>"accent"|Success=>"success"|Warning=>"warning"|Danger=>"danger"|Muted=>"muted"end.
Inductive primitive(Action:Type):Type:=
| Line(x1 y1 x2 y2:Z)(color:tone)
| Rectangle(x y:Z)(width height:N)(color:tone)
| Circle(x y:Z)(radius:N)(color:tone)
| Label(x y:Z)(text:string)(color:tone)
| Hitbox(key:string)(x y:Z)(width height:N)(label:string)(action:Action).
Arguments Line {Action}.
Arguments Rectangle {Action}.
Arguments Circle {Action}.
Arguments Label {Action}.
Arguments Hitbox {Action}.
Record plot(Action:Type):Type:=Plot{width:positive;height:positive;primitives:list(primitive Action)}.
Arguments Plot {Action}.
Arguments width {Action}.
Arguments height {Action}.
Arguments primitives {Action}.
Definition coordinate n:=JNumber(show_integer n).
Definition extent n:=JNumber(show_natural n).
Definition encode_primitive{A}(encode_action:A->json)(p:primitive A):json:=
 let pack kind fields:=JObject(("kind",JString kind)::fields)in
 let position x y:=[("x",coordinate x);("y",coordinate y)]in
 match p with
 | Line x1 y1 x2 y2 color=>pack "line"[("x1",coordinate x1);("y1",coordinate y1);("x2",coordinate x2);("y2",coordinate y2);("tone",JString(tone_name color))]
 | Rectangle x y width height color=>pack "rect"(position x y++[("width",extent width);("height",extent height);("tone",JString(tone_name color))])
 | Circle x y radius color=>pack "circle"(position x y++[("radius",extent radius);("tone",JString(tone_name color))])
 | Label x y text color=>pack "text"(position x y++[("text",JString text);("tone",JString(tone_name color))])
 | Hitbox key x y width height label action=>pack "hitbox"(position x y++[("key",JString key);("width",extent width);("height",extent height);("label",JString label);("action",encode_action action)])end.
Definition encode{A}encode_action(p:plot A):json:=JObject[("width",extent(Npos p.(width)));("height",extent(Npos p.(height)));
 ("primitives",JArray(map(encode_primitive encode_action)p.(primitives)))].
Definition map_primitive{A B}(f:A->B)(p:primitive A):primitive B:=match p with
 |Line x y u v t=>Line x y u v t|Rectangle x y w h t=>Rectangle x y w h t|Circle x y r t=>Circle x y r t|Label x y text t=>Label x y text t
 |Hitbox key x y w h label a=>Hitbox key x y w h label(f a)end.
Definition map_actions{A B}(f:A->B)(p:plot A):plot B:=Plot p.(width)p.(height)(map(map_primitive f)p.(primitives)).
Definition opt_bind{A B}(value:option A)(f:A->option B):=match value with Some v=>f v|None=>None end.
Notation "x <-o a ;; b" :=(opt_bind a(fun x=>b))(at level 100,a at next level,right associativity).
Definition decode_tone source:=name <-o string_field "tone"source;;
 find(fun t=>String.eqb(tone_name t)name)[Neutral;Accent;Success;Warning;Danger;Muted].
Definition z_field name source:=text <-o number_field name source;;parse_integer text.
Definition n_field name source:=text <-o number_field name source;;parse_natural text.
Definition decode_primitive(source:json):option(primitive json):=
 kind <-o string_field "kind"source;;
 if String.eqb kind "line"then
 x1 <-o z_field "x1"source;;y1 <-o z_field "y1"source;;x2 <-o z_field "x2"source;;y2 <-o z_field "y2"source;;t <-o decode_tone source;;Some(Line x1 y1 x2 y2 t)
 else if String.eqb kind "rect"then
 x <-o z_field "x"source;;y <-o z_field "y"source;;w <-o n_field "width"source;;h <-o n_field "height"source;;t <-o decode_tone source;;Some(Rectangle x y w h t)
 else if String.eqb kind "circle"then
 x <-o z_field "x"source;;y <-o z_field "y"source;;r <-o n_field "radius"source;;t <-o decode_tone source;;Some(Circle x y r t)
 else if String.eqb kind "text"then
 x <-o z_field "x"source;;y <-o z_field "y"source;;text <-o string_field "text"source;;t <-o decode_tone source;;Some(Label x y text t)
 else if String.eqb kind "hitbox"then
 key <-o string_field "key"source;;x <-o z_field "x"source;;y <-o z_field "y"source;;w <-o n_field "width"source;;h <-o n_field "height"source;;
 label <-o string_field "label"source;;action <-o field "action"source;;Some(Hitbox key x y w h label action)
 else None.
Fixpoint decode_primitives source:=match source with []=>Some[]|head::tail=>head <-o decode_primitive head;;tail <-o decode_primitives tail;;Some(head::tail)end.
Definition positive_extent n:=match n with N0=>None|Npos p=>Some p end.
Definition decode(source:json):option(plot json):=
 w <-o n_field "width"source;;w <-o positive_extent w;;h <-o n_field "height"source;;h <-o positive_extent h;;
 xs <-o array_field "primitives"source;;xs <-o decode_primitives xs;;Some(Plot w h xs).
