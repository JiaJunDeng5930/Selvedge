From Stdlib Require Import String List Bool NArith ZArith.
From Selvedge.Foundation Require Import Json Numbers TextJson Utf8 Schema.
From Selvedge.Interaction Require Import Codec.
From Selvedge.Interaction.Interactive Require Import Bounds Decimal Expression Syntax Local Sources Registry Types State.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Definition optional_text(value:option string):json:=match value with Some text=>JString text|None=>JNull end.
Definition decode_optional_text(value:json):option(option string):=match value with JNull=>Some None|JString text=>Some(Some text)|_=>None end.
Definition encode_action(value:action):json:=
 let pack kind fields:=JObject(("kind",JString kind)::fields)in match value with
 |Assign target value=>pack "assign"[("target",JString target);("value",value)]|ResetAll=>pack "reset"[]
 |Draft text=>pack "draft"[("text",JString text)]|Submit text=>pack "submit"[("text",JString text)]
 |Copy text=>pack "copy"[("text",JString text)]|Navigate text=>pack "navigate"[("text",JString text)]end.
Definition decode_action value:=kind <- string_field "kind"value;;match kind with
 |"assign"=>target <- string_field "target"value;;v <- field "value"value;;Some(Assign target v)|"reset"=>Some ResetAll
 |"draft"=>text <- string_field "text"value;;Some(Draft text)|"submit"=>text <- string_field "text"value;;Some(Submit text)
 |"copy"=>text <- string_field "text"value;;Some(Copy text)|"navigate"=>text <- string_field "text"value;;Some(Navigate text)|_=>None end.
Definition encode_view(value:view_state):json:=match value with
 |SourceView open=>JObject[("kind",JString "source");("open",JBool open)]
 |GraphView zoom x y fit selected=>JObject[("kind",JString "graph");("zoom",JString(Decimal.text zoom));("x",JString(Decimal.text x));("y",JString(Decimal.text y));("fit",JBool fit);("selected",JString selected)]
 |TableView sort_field descending page=>JObject[("kind",JString "table");("sort_field",optional_text sort_field);("descending",JBool descending);("page",JNumber(show_nat page))]end.
Definition decimal_field name value:=text <- string_field name value;;Decimal.parse text.
Definition decode_view value:=kind <- string_field "kind"value;;match kind with
 |"source"=>open <- bool_field "open"value;;Some(SourceView open)
 |"graph"=>zoom <- decimal_field "zoom"value;;x <- decimal_field "x"value;;y <- decimal_field "y"value;;fit <- bool_field "fit"value;;selected <- string_field "selected"value;;
   if Z.leb (Z.quot Decimal.scale 4)(Decimal.units zoom)&&Z.leb(Decimal.units zoom)(2*Decimal.scale)&&
      Z.leb(-2000*Decimal.scale)(Decimal.units x)&&Z.leb(Decimal.units x)(2000*Decimal.scale)&&
      Z.leb(-2000*Decimal.scale)(Decimal.units y)&&Z.leb(Decimal.units y)(2000*Decimal.scale)
   then Some(GraphView zoom x y fit selected)else None
 |"table"=>sort_field <- field "sort_field"value;;sort_field <- decode_optional_text sort_field;;descending <- bool_field "descending"value;;page <- number_field "page"value;;page <- parse_nat page;;
   if Nat.leb page Bounds.table_max_page_index then Some(TableView sort_field descending page)else None|_=>None end.
Definition encode_views views:=JArray(map(fun kv=>JObject[("path",JString(fst kv));("value",encode_view(snd kv))])views).
Definition decode_views value:=items <- as_array value;;pairs <- Codec.traverse(fun item=>path <- string_field "path"item;;value <- field "value"item;;value <- decode_view value;;Some(path,value))items;;
 if Schema.unique_names(map fst pairs)then Some pairs else None.
Definition encode_feedback value:=let base:=[("path",JString value.(feedback_path))]in
 JObject(base++match value.(feedback_transaction)with
 |Waiting ticket occurrence action=>[("kind",JString "waiting");("ticket",Codec.number ticket);("occurrence",Codec.number occurrence);("action",encode_action action)]
 |CopyingDefinition ticket=>[("kind",JString "definition");("ticket",Codec.number ticket)]
 |Answered ticket ok message=>[("kind",JString "answered");("ticket",Codec.number ticket);("ok",JBool ok);("message",JString message)]end).
Definition decode_feedback value:=path <- string_field "path"value;;kind <- string_field "kind"value;;ticket <- natural_field "ticket"value;;
 transaction <- match kind with
 |"waiting"=>occurrence <- natural_field "occurrence"value;;action <- field "action"value;;action <- decode_action action;;Some(Waiting ticket occurrence action)
 |"definition"=>Some(CopyingDefinition ticket)
 |"answered"=>ok <- bool_field "ok"value;;message <- string_field "message"value;;Some(Answered ticket ok message)|_=>None end;;Some(FeedbackEntry path transaction).
Definition encode_restoration value:=match value with
 |Unrequested=>JObject[("kind",JString "unrequested")]|RestorationSettled=>JObject[("kind",JString "settled")]
 |LoadingSnapshot revision=>JObject[("kind",JString "loading");("revision",Codec.number revision)]end.
Definition decode_restoration value:=kind <- string_field "kind"value;;match kind with
 |"unrequested"=>Some Unrequested|"settled"=>Some RestorationSettled|"loading"=>revision <- natural_field "revision"value;;Some(LoadingSnapshot revision)|_=>None end.
Definition parser_prefix b:=match Utf8.take b.(syntax).(characters)b.(source)with Some value=>value|None=>""end.
Definition encode_parser b:=let processed:=parser_prefix b in
 JObject[("cursor",JNumber(show_nat(String.length processed-String.length b.(syntax).(tail))));
 ("characters",JNumber(show_nat b.(syntax).(characters)));("error",optional_text b.(syntax).(syntax_error));("sealed",JBool b.(syntax).(sealed))].
Fixpoint drain(turns:nat)(syntax:Syntax.syntax):Syntax.syntax:=match turns with
 |O=>syntax|S rest=>if Syntax.pending syntax then drain rest(Syntax.turn Bounds.parser_turn syntax)else syntax end.
Definition decode_parser source value:=
 cursor <- number_field "cursor"value;;cursor <- parse_nat cursor;;count <- number_field "characters"value;;count <- parse_nat count;;
 error <- field "error"value;;error <- decode_optional_text error;;sealed <- bool_field "sealed"value;;
 processed <- Utf8.take count source;;
 if Nat.leb cursor(String.length processed)then
 let prefix:=String.substring 0 cursor processed in
 let parsed:=drain 16(Syntax.append prefix Syntax.empty)in
 if String.eqb parsed.(tail)""&&(match parsed.(syntax_error)with None=>true|_=>false end)then
 let parser:=Syntax.Syntax parsed.(roots_reversed)parsed.(frames)(String.substring cursor(String.length processed-cursor)processed)error false parsed.(accepted)count in
 if sealed then let finished:=Syntax.finish parser in if finished.(Syntax.sealed)then Some finished else None else Some parser
 else None else None.
Definition encode_block b:=JObject[("owner",encode_owner b.(block_owner));("source",JString b.(source));("parser",encode_parser b);
 ("ending",JString(ending_name b.(block_ending)));("closed",JBool b.(fence_closed));("external",JBool b.(external));
 ("locals",JArray(map Local.local_json b.(locals)));("sources",JObject b.(State.sources));("views",encode_views b.(views));
 ("mounts",JArray(map(fun kv=>JObject[("path",JString(fst kv));("occurrence",Codec.number(snd kv))])b.(mounts)));
 ("feedbacks",JArray(map encode_feedback b.(feedbacks)));("revision",Codec.number b.(revision));("next_ticket",Codec.number b.(next_ticket));("next_occurrence",Codec.number b.(next_occurrence));
 ("edited",JBool b.(edited));("restoration",encode_restoration b.(restore_state));("notice",optional_text b.(storage_notice))].
Definition restore_local declared value:=
 id <- string_field "id"value;;schema <- field "schema"value;;canonical <- field "value"value;;raw <- string_field "raw"value;;validation <- field "validation"value;;validation <- decode_optional_text validation;;
 if String.eqb id declared.(local_id)&&Json.equal schema(Local.schema_json declared)&&within_scalars Bounds.raw_scalars raw then
 current <- Local.admit declared.(local_shape)canonical;;Some(Local.edit_value declared current raw validation)else None.
Definition decode_block value:=
 ownerj <- field "owner"value;;owner <- decode_owner ownerj;;source <- string_field "source"value;;parserj <- field "parser"value;;parser <- decode_parser source parserj;;
 ending <- string_field "ending"value;;ending <- decode_ending ending;;closed <- bool_field "closed"value;;external <- bool_field "external"value;;
 raw_sources <- field "sources"value;;raw_sources <- as_object raw_sources;;
 let prepared:=Registry.prepare parser [] raw_sources(JObject[("connected",JBool false)])in
 localj <- array_field "locals"value;;
 if Nat.eqb(List.length localj)(List.length prepared.(prepared_locals))then
 locals <- Codec.traverse(fun pair=>restore_local(fst pair)(snd pair))(combine prepared.(prepared_locals)localj);;
 viewsj <- field "views"value;;views <- decode_views viewsj;;
 mounts <- array_field "mounts"value;;mounts <- Codec.traverse(fun item=>path <- string_field "path"item;;n <- natural_field "occurrence"item;;Some(path,n))mounts;;
 feedbacks <- array_field "feedbacks"value;;feedbacks <- Codec.traverse decode_feedback feedbacks;;
 revision <- natural_field "revision"value;;next_ticket <- natural_field "next_ticket"value;;next_occurrence <- natural_field "next_occurrence"value;;edited <- bool_field "edited"value;;
 restoration <- field "restoration"value;;restoration <- decode_restoration restoration;;notice <- field "notice"value;;notice <- decode_optional_text notice;;
 if Schema.unique_names(map fst mounts)&&Schema.unique_names(map feedback_path feedbacks)&&
    forallb(fun kv=>N.ltb(snd kv)next_occurrence)mounts&&
    forallb(fun feedback=>match feedback.(feedback_transaction)with Waiting ticket occurrence _=>N.ltb ticket next_ticket&&N.ltb occurrence next_occurrence|CopyingDefinition ticket|Answered ticket _ _=>N.ltb ticket next_ticket end)feedbacks
 then Some(Block owner source parser ending closed external locals prepared.(Registry.sources)views mounts feedbacks revision next_ticket next_occurrence edited restoration notice)else None else None.
Definition encode_state value:=JObject[("blocks",JArray(map encode_block value.(blocks)))].
Definition decode_state value:=items <- array_field "blocks"value;;blocks <- Codec.traverse decode_block items;;
 if Schema.unique_names(map(fun block=>block.(block_owner).(owner_key))blocks)then Some(State blocks)else None.
