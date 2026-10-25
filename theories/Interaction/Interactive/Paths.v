From Stdlib Require Import String Ascii List Bool ZArith.
From Selvedge.Foundation Require Import Json Numbers TextJson.
From Selvedge.Interaction Require Import Codec.
From Selvedge.Interaction.Interactive Require Import Bounds Decimal Expression Syntax Registry Vocabulary Types State Expand.
Import ListNotations.
Open Scope list_scope.
Open Scope string_scope.

Inductive segment := Component (id:string) | Item (key:string).
Definition drop_prefix prefix text :=
 if String.prefix prefix text then Some (String.substring (String.length prefix) (String.length text) text) else None.
Fixpoint word text := match text with
 | EmptyString => ("", "")
 | String c rest => if Ascii.eqb c "/"%char then ("",text) else let '(head,tail):=word rest in (String c head,tail)
 end.
Definition item_segment text : option (string*string) :=
 match drop_prefix "s:" text with
 | Some quoted => match TextJson.quoted (S (String.length quoted)) quoted with
   | Scanned value rest =>
     if String.eqb quoted (TextJson.quote value++rest) then Some ("s:"++TextJson.quote value,rest) else None
   | _ => None end
 | None => match drop_prefix "n:" text with
   | Some number => let '(value,rest):=word number in
     d <- Decimal.parse value;;
     if Decimal.integral d && String.eqb value (Decimal.text d) then Some ("n:"++value,rest) else None
   | None => None end
 end.
Fixpoint segments fuel text : option (list segment) :=
 match fuel with
 | O => None
 | S rest => if String.eqb text "" then Some [] else
   match drop_prefix "/@item/" text with
   | Some text => pair <- item_segment text;; next <- segments rest (snd pair);; Some (Item(fst pair)::next)
   | None => text <- drop_prefix "/" text;; let '(id,tail):=word text in
     if Syntax.valid_id id then next <- segments rest tail;;Some(Component id::next) else None
   end
 end.
Definition parse_path path := tail <- drop_prefix "ui" path;;segments 128 tail.
Inductive descriptor := GraphDescriptor | TableDescriptor (columns:list(string*string)).
Definition column_fields nodes := fold_right (fun node rest => match node with
 | Element "column" attrs _ _ => match Registry.lexical_id attrs,Registry.literal_text "field" attrs with
   |Some id,Good field=>(id,field)::rest|_,_=>rest end
 | _=>rest end) [] nodes.
Fixpoint locate fuel nodes parts : option descriptor :=
 match fuel,nodes with
 | O,_ | _,[] => None
 | S rest,Element tag attrs children _::siblings =>
   let found := match parts,Registry.lexical_id attrs with
   | Component id::tail,Some actual => if String.eqb id actual then
     match Vocabulary.component tag with None=>None|Some spec=>
       match tail,spec.(component_role)with
       | [],Table=>Some(TableDescriptor(column_fields children))
       | [],Graph=>Some GraphDescriptor
       | Item _::tail,Repeat=>locate rest children tail
       | Item _::tail,Graph=>match children with
         |[Element template _ nested _]=>match Vocabulary.component template with
           |Some template=>match template.(component_role)with Template=>locate rest nested tail|_=>None end
           |None=>None end
         |_=>None end
       | _,Layout|_,Condition|_,Resource=>locate rest children tail
       | _,_=>None end
     end else None
   | _,_ => None end in
   match found with Some value=>Some value|None=>locate rest siblings parts end
 end.
Definition describe prepared path := parts <- parse_path path;;locate 4096 prepared.(visual) parts.
Definition accepts description value := match description,value with
 | GraphDescriptor,GraphView _ _ _ _ _ => true
 | TableDescriptor columns,TableView column _ _ => match column with
   | None=>true|Some field=>existsb(fun column=>String.eqb field(snd column))columns end
 | _,_=>false end.
Definition declared prepared entry := match describe prepared (fst entry) with
 | Some description=>accepts description (snd entry)|None=>false end.

(* A hidden subtree keeps its local view. Only an observed collection can
   establish that an item was removed; an absent expansion cannot. *)
Definition collection_keeps target event_id props :=
 match drop_prefix (event_id.(path)++"/@item/") target with
 | None => true
 | Some tail => match item_segment tail with
   | None=>false
   | Some (key,_) =>
     let '(key_field,items):=match props.(description).(component_role)with
       | Repeat=>(property_text "key" props,property_array "items" props)
       | Graph=>("identity",property_array "nodes" props)
       | _=>("",[]) end in
     match props.(description).(component_role)with
     | Repeat|Graph => existsb(fun item=>match key_value(get_path key_field item)with
       | Some actual=>String.eqb actual key|None=>false end)items
     | _=>true end
   end
 end.
Fixpoint collections_keep fuel target nodes := match fuel,nodes with
 | O,_=>true|_,[]=>true
 | S rest,Message _ _::tail=>collections_keep rest target tail
 | S rest,Mounted event_id props _ children::tail=>
   collection_keeps target event_id props && collections_keep rest target children && collections_keep rest target tail
 end.
Definition retained prepared nodes entry := declared prepared entry && collections_keep 8192 (fst entry) nodes.
Definition persistent_views prepared nodes entries := filter (retained prepared nodes) entries.
