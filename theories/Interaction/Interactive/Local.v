From Stdlib Require Import String List Bool NArith ZArith.
From Selvedge.Foundation Require Import Json Numbers Schema TextJson Utf8.
From Selvedge.Interaction.Interactive Require Import Bounds Decimal Expression Syntax.
Import ListNotations.
Open Scope string_scope.
Open Scope nat_scope.
Inductive shape :=
| Numeric (integer:bool)(minimum maximum:option Decimal.decimal)(step:Decimal.decimal)
| Boolean | Text (maximum:nat) | Enumeration(first:string)(rest:list string).
Definition denote s : Type :=match s with Numeric _ _ _ _=>Decimal.decimal|Boolean=>bool|Text _|Enumeration _ _=>string end.
Definition accepts(s:shape):denote s->bool:=
 match s as s return denote s->bool with
 | Numeric integer minimum maximum step=>fun value=>
   (negb integer||Decimal.integral value)&&
   (match minimum with Some n=>Decimal.compare ">="value n|None=>true end)&&
   (match maximum with Some n=>Decimal.compare "<="value n|None=>true end)&&
   match minimum with Some n=>Decimal.on_grid value n step
   | None=>Z.ltb 0(Decimal.units step)&&Z.eqb(Z.rem(Decimal.units value)(Decimal.units step))0 end
 | Boolean=>fun _=>true
 | Text maximum=>fun s=>within_scalars maximum s
 | Enumeration first rest=>fun s=>existsb(String.eqb s)(first::rest)
 end.
Definition value(s:shape):Type:={v:denote s|accepts s v=true}.
Definition base_json(s:shape):denote s->json:=
 match s as s return denote s->json with
 | Numeric _ _ _ _=>fun d=>decimal_json d|Boolean=>JBool|Text _|Enumeration _ _=>JString end.
Definition value_json{s}(v:value s):json:=base_json s(proj1_sig v).
Definition decode_base(s:shape):json->option(denote s):=
 match s as s return json->option(denote s)with
 | Numeric _ _ _ _=>decimal_value|Boolean=>as_bool|Text _|Enumeration _ _=>as_string end.
Definition admit(s:shape)(source:json):option(value s):=
 match decode_base s source with
 | None=>None
 | Some v=>match Bool.bool_dec(accepts s v)true with left proof=>Some(exist _ v proof)|right _=>None end end.
Record local := Local{
 local_id:string; local_shape:shape; initial:value local_shape; current:value local_shape;
 raw:string; validation:option string }.
Definition canonical(l:local):json:=value_json l.(current).
Definition edit_value(l:local)(v:value l.(local_shape))(buffer:string)(error:option string):local:=
 Local l.(local_id)l.(local_shape)l.(initial)v buffer error.
Definition invalid(l:local)(buffer reason:string):local:=edit_value l l.(current)buffer(Some reason).
Definition reset(l:local):local:=edit_value l l.(initial)
 (match value_json l.(initial)with JString s|JNumber s=>s|JBool true=>"true"|JBool false=>"false"|_=>""end)None.
Definition optional_literal name attrs:=match attr name attrs with None=>Good JNull|Some _=>literal_attr name attrs end.
Definition literal_or fallback name attrs:=match attr name attrs with None=>Good fallback|Some _=>literal_attr name attrs end.
Definition optional_decimal j : outcome(option Decimal.decimal):=
 match j with JNull=>Good None|_=>d <-? from_option "Numeric bound must be a fixed decimal"(decimal_value j);;Good(Some d)end.
Definition enum_strings j : outcome(string*list string):=
 match j with
 | JArray(JString first::rest)=>
   strings <-? from_option "Enum options must be strings"(Schema.decode_list as_string rest);;
   if negb(String.eqb first "")&&forallb(fun s=>negb(String.eqb s ""))strings&&
      Schema.unique_names(first::strings)&&(List.length strings<?256)
   then Good(first,strings)else Error "Enum options must be unique and nonempty"
 | _=>Error "Enum options must be a nonempty string list"end.
Definition from_attributes attrs : outcome local:=
 idj <-? literal_attr "id"attrs;;id <-? from_option "State id must be text"(as_string idj);;
 kindj <-? literal_attr "type"attrs;;kind <-? from_option "State type must be text"(as_string kindj);;
 initialj <-? literal_attr "initial"attrs;;
 shape <-? (
 if String.eqb kind "integer"||String.eqb kind "number"then
   minj <-? optional_literal "min"attrs;;maxj <-? optional_literal "max"attrs;;
   stepj <-? literal_or(JNumber(if String.eqb kind "integer"then "1"else "0.01"))"step"attrs;;
   minimum <-? optional_decimal minj;;maximum <-? optional_decimal maxj;;
   step <-? from_option "Step must be a positive fixed decimal"(decimal_value stepj);;
   if Z.ltb 0(Decimal.units step)&&(negb(String.eqb kind "integer")||Decimal.integral step)&&
      (match minimum,maximum with Some a,Some b=>Decimal.compare "<="a b|_,_=>true end)
   then Good(Numeric(String.eqb kind "integer")minimum maximum step)else Error "Invalid numeric range or step"
 else if String.eqb kind "boolean"then Good Boolean else
 if String.eqb kind "string"then
   maximum <-? literal_or(JNumber "4096")"max-length"attrs;;
   maximum <-? from_option "String maximum must be 0..16384"(as_small Bounds.string_scalars maximum);;Good(Text maximum)
 else if String.eqb kind "enum"then
   options <-? literal_attr "options"attrs;;options <-? enum_strings options;;let '(first,rest):=options in Good(Enumeration first rest)
 else Error "Unknown state type");;
 v <-? from_option "Initial value violates its type, range, step or options"(admit shape initialj);;
 if valid_binding id then Good(reset(Local id shape v v ""None))else Error "Invalid state id".
Definition optional_number j :=match j with Some n=>decimal_json n|None=>JNull end.
Definition shape_json s:=match s with
 | Numeric integer minimum maximum step=>JObject[("type",JString(if integer then "integer"else "number"));
   ("min",optional_number minimum);("max",optional_number maximum);("step",decimal_json step)]
 | Boolean=>JObject[("type",JString "boolean")]
 | Text maximum=>JObject[("type",JString "string");("max-length",JNumber(show_nat maximum))]
 | Enumeration first rest=>JObject[("type",JString "enum");("options",JArray(map JString(first::rest)))]end.
Definition schema_json(l:local):json:=
 match shape_json l.(local_shape)with JObject fs=>JObject(("initial",value_json l.(initial))::fs)|_=>JNull end.
Definition local_json(l:local):json:=JObject[("id",JString l.(local_id));("schema",schema_json l);
 ("value",canonical l);("raw",JString l.(raw));("validation",match l.(validation)with Some e=>JString e|None=>JNull end)].
Definition find_local id locals:=find(fun l=>String.eqb id l.(local_id))locals.
Definition reuse(previous:list local)(next:local):local:=match find_local next.(local_id)previous with
 | Some old=>if Json.equal(schema_json old)(schema_json next)then old else next|None=>next end.
Definition input_raw j:=match j with JString s|JNumber s=>Some s|JBool true=>Some "true"|JBool false=>Some "false"|_=>None end.
Definition edit(l:local)(input:json):local*bool:=
 match input_raw input with
 | None=>(invalid l l.(raw)"Unsupported field payload",false)
 | Some buffer=>
   if within_scalars Bounds.raw_scalars buffer then
   let source:=match l.(local_shape)with
   | Numeric _ _ _ _=>JNumber buffer|Boolean=>if String.eqb buffer "true"then JBool true else if String.eqb buffer "false"then JBool false else JNull
   | Text _|Enumeration _ _=>JString buffer end in
   match admit l.(local_shape)source with
   | Some v=>(edit_value l v buffer None,true)
   | None=>(invalid l buffer "Input violates its declared type, range or step grid",false)end
   else (invalid l l.(raw)"Input exceeds 16384 Unicode scalars",false)
 end.
Definition assign(l:local)(source:json):option local:=
 match admit l.(local_shape)source with
 | Some v=>Some(edit_value l v (match source with JString s|JNumber s=>s|JBool true=>"true"|JBool false=>"false"|_=>""end)None)
 | None=>None end.
Definition replace_local(next:local)(locals:list local):list local:=map(fun old=>if String.eqb old.(local_id)next.(local_id)then next else old)locals.
Definition environment(locals:list local):list(string*outcome json):=map(fun l=>(l.(local_id),Good(canonical l)))locals.
