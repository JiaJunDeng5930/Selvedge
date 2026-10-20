From Stdlib Require Import String List Bool Ascii NArith.
From Selvedge.Foundation Require Import Json Utf8.
From Selvedge.Kernel Require Import Numbers.
From Selvedge.Features Require Import Domain Titles.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Inductive tab := All | Assigned | UnassignedTab | Working.
Inductive category := Status | Priority | Date | Assignee | Creator | Project | Label.
Scheme Equality for category.
Definition categories := [Status;Priority;Date;Assignee;Creator;Project;Label].
Definition category_name (value:category) := match value with Status=>"status" | Priority=>"priority" | Date=>"date" | Assignee=>"assignee" | Creator=>"creator" | Project=>"project" | Label=>"label" end.
Definition parse_category (name:string) := find (fun value=>String.eqb name (category_name value)) categories.
Record filter := Filter { filter_tab : tab; filter_query : string; filter_values : category -> list string }.
Definition empty := Filter All "" (fun _=>[]).
Definition tab_name (value:tab) := match value with All=>"all" | Assigned=>"assigned" | UnassignedTab=>"unassigned" | Working=>"working" end.
Definition parse_tab (name:string) := if String.eqb name "assigned" then Assigned else if String.eqb name "unassigned" then UnassignedTab else if String.eqb name "working" then Working else All.
Definition set_query (text:string) (value:filter) := Filter (filter_tab value) text (filter_values value).
Definition set_tab (name:string) (value:filter) := Filter (parse_tab name) (filter_query value) (filter_values value).
Definition set_values (key:category) (entries:list string) (value:filter) := Filter (filter_tab value) (filter_query value) (fun other=>if category_beq key other then entries else filter_values value other).
Definition toggle (name entry:string) (value:filter) := match parse_category name with None=>value | Some key=>let previous:=filter_values value key in set_values key (if existsb (String.eqb entry) previous then List.filter (fun item=>negb (String.eqb item entry)) previous else previous++[entry]) value end.
Definition edit := toggle.
Definition encode (value:filter) := JObject (("view",JString (tab_name (filter_tab value)))::("search",JString (filter_query value))::map (fun key=>(category_name key,JArray (map JString (filter_values value key)))) categories).
Definition texts (value:json) := match value with JArray values=>fold_right (fun item rest=>match item with JString text=>text::rest | _=>rest end) [] values | _=>[] end.
Definition decode (source:json) := Filter (parse_tab (match string_field "view" source with Some value=>value | None=>"all" end)) (match string_field "search" source with Some value=>value | None=>"" end) (fun key=>match field (category_name key) source with Some value=>texts value | None=>[] end).
Definition text (name:string) (source:json) := match string_field name source with Some value=>value | None=>"" end.
Definition flag (name:string) (source:json) := match bool_field name source with Some value=>value | None=>false end.
Definition selected (values:list string) (value:string) := match values with []=>true | _=>existsb (String.eqb value) values end.
Definition labels (values:list string) (actual:list string) := match values with []=>true | _=>existsb (fun item=>existsb (String.eqb item) actual) values end.
Definition lower (c:ascii) := let n:=nat_of_ascii c in if Nat.leb 65 n && Nat.leb n 90 then ascii_of_nat (n+32) else c.
Fixpoint lower_text (source:string) := match source with EmptyString=>EmptyString | String c rest=>String (lower c) (lower_text rest) end.
Fixpoint contains (needle haystack:string) := match haystack with EmptyString=>String.eqb needle "" | String _ rest=>String.prefix needle haystack || contains needle rest end.
Definition trim (source:string) := match Utf8.chunks source with Some values=>Utf8.render_chunks (Titles.trim_both Utf8.whitespace values) | None=>source end.
Definition elapsed (now then_:N) := N.sub now then_.
Definition day_limit (name:string) :N := if String.eqb name "1" then 86400 else if String.eqb name "7" then 604800 else if String.eqb name "30" then 2592000 else 0.
Definition date_matches (values:list string) (age:N) := match values with []=>true | _=>existsb (fun name=>N.leb age (day_limit name)) values end.
Definition id_text (value:json) := match value with JNumber source=>source | _=>"" end.
Definition matches (selection:filter) (now:N) (card:json) :=
 let owner:=text "assignee" card in
 negb (flag "archived" card) &&
 (match filter_tab selection with All=>true | Assigned=>negb (String.eqb owner "none" || String.eqb owner "") | UnassignedTab=>String.eqb owner "none" || String.eqb owner "" | Working=>flag "working" card end) &&
 selected (filter_values selection Status) (text "status" card) &&
 selected (filter_values selection Priority) (text "priority" card) &&
 selected (filter_values selection Assignee) owner && selected (filter_values selection Creator) "self" &&
 selected (filter_values selection Project) (match string_field "project" card with Some value=>value | None=>"" end) &&
 labels (filter_values selection Label) (match field "labels" card with Some value=>texts value | None=>[] end) &&
 date_matches (filter_values selection Date) (elapsed now (match field "updated_at" card with Some value=>match value with JString source=>match natural (JNumber source) with Some value=>value | None=>0 end | _=>0 end | None=>0 end)) &&
 contains (lower_text (trim (filter_query selection))) (lower_text ((text "identifier" card)++" "++text "title" card++" "++text "description" card)).
Definition task_working (card world:json) := match field "task_id" card, array_field "tasks" world with Some (JNumber id),Some tasks=>existsb (fun task=>match field "id" task with Some (JNumber other)=>String.eqb id other && flag "working" task | _=>false end) tasks | _,_=>false end.
Definition matches_in_world (selection:filter) (now:N) (card world:json) := matches selection now (match card with JObject fields=>JObject (set_field "working" (JBool (task_working card world)) fields) | _=>card end).
Definition apply (selection:filter) (now:N) (cards:list json) := List.filter (matches selection now) cards.
Definition apply_in_world (selection:filter) (now:N) (cards:list json) (world:json) := List.filter (fun card=>matches_in_world selection now card world) cards.
Definition choices (entries:list (string*string)) := map (fun entry=>JObject [("value",JString (fst entry));("label",JString (snd entry))]) entries.
Definition stage_choices := choices (map (fun stage=>(Domain.stage_name stage,Domain.stage_label stage)) stages).
Definition priority_choices := choices (map (fun level=>(Domain.priority_name level,Domain.priority_label level)) priorities).
Definition display_cards (cards:list json) := List.filter (flag "pinned") cards ++ List.filter (fun card=>negb (flag "pinned" card)) cards.
