From Stdlib Require Import String Ascii List Bool NArith.
From Selvedge.Foundation Require Import Json Utf8.
From Selvedge.Kernel Require Import Numbers Domain Codec Conversation Observation State Pagination.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Definition default_limit : N := Pagination.search_default.
Definition lower_ascii (c : ascii) := let n := nat_of_ascii c in
 if (Nat.leb 65 n && Nat.leb n 90) then ascii_of_nat (n+32) else c.
(* Reconstruct once after folding, so long admitted transcripts do not require
   one compiler stack frame per byte. *)
Definition lower (s : string) := String.string_of_list_ascii
 (List.rev_append (fold_left (fun acc c => lower_ascii c :: acc) (String.list_ascii_of_string s) []) []).
Fixpoint contains (query text : string) :=
 if String.prefix query text then true else
 match text with EmptyString => false | String _ rest => contains query rest end.
Definition searchable (message : json) :=
 match json_message_role message with Some "user" | Some "assistant" => true | _ => false end.
Definition take_text (limit : nat) (text : string) :=
 match Utf8.take limit text with Some value => value | None => "" end.
Fixpoint match_offset (query text : string) (offset : nat) : nat :=
 if String.prefix query text then offset else match text with
 | EmptyString => offset
 | String character rest => match_offset query rest
   (if Nat.leb 128 (nat_of_ascii character) && Nat.ltb (nat_of_ascii character) 192 then offset else S offset)
 end.
Definition snippet (query text : string) :=
 match Utf8.chunks text with
 | Some chunks => Utf8.render_chunks (firstn 320 (skipn (match_offset (lower query) (lower text) 0 - 80) chunks))
 | None => "" end.
Definition readable (message : message) :=
 let wire := Codec.message_json 0 message in
 match json_message_role wire,as_string (json_message_content wire) with
 | Some role,Some text => if existsb (String.eqb role) ["user";"assistant"] then Some (role,text) else None
 | _,_ => None end.
Fixpoint newer_context (messages : list message) : list (message * string) * string :=
 match messages with
 | [] => ([],"")
 | message :: rest => let '(annotated,newer) := newer_context rest in
   ((message,newer) :: annotated,match readable message with Some (_,text) => take_text 180 text | None => newer end)
 end.
Definition history_hits (query : string) (id : N) (task : task) (features : Features.Domain.state) :=
 let '(annotations,_) := newer_context (task_history task) in
 let '(_,_,hits) := fold_left (fun state annotation =>
   let '(index,before,hits) := state in let '(message,after) := annotation in
   match readable message with
   | None => (N.succ index,before,hits)
   | Some (role,text) =>
     (N.succ index,take_text 180 text,
      if contains (lower query) (lower text) then
      JObject [("task",task_summary id task features);("message_index",number index);
       ("role",JString role);("snippet",JString (snippet query text));
       ("before",JString before);("after",JString after)] :: hits else hits)
   end) annotations (0%N,"",[]) in hits.
Definition task_hits (query : string) (project work : option N) (id : N) (task : task) (value : world) :=
 if (match project with None => true | Some id => match settings_project (task_current_settings task) with Some actual => N.eqb actual id | None => false end end) &&
    (match work with None => true | Some owner => match task_owner id task (world_features value) with Some actual => N.eqb actual owner | None => false end end)
 then history_hits query id task (world_features value) else [].
Fixpoint drop_space (chunks : list (N * string)) :=
 match chunks with [] => [] | (scalar,_) :: rest => if Utf8.whitespace scalar then drop_space rest else chunks end.
Definition trim (text : string) := match Utf8.chunks text with
 | None => text | Some chunks => Utf8.render_chunks (rev (drop_space (rev (drop_space chunks)))) end.
Definition search (query : string) (project work : option N) (after limit : N) (value : world) :=
 let project_exists := match project with None => true | Some id =>
   match registry_at id (world_projects value) with Some entry => negb (project_deleted entry) | None => false end end in
 let work_exists := match work with None => true | Some id =>
   match registry_at id (Features.Domain.feature_works (world_features value)) with Some _ => true | None => false end end in
 if negb project_exists then State.failure "project_not_found" "The project does not exist" else
 if negb work_exists then State.failure "work_not_found" "The Work does not exist" else
 let query := trim query in
 match Utf8.scalar_count query with
 | Some length => if Nat.leb 1 length && Nat.leb length 240 && (N.leb 1 limit && N.leb limit Pagination.search_limit) then
   let hits := concat (rev (indexed (fun id task => task_hits query project work id task value) 0 (world_tasks value))) in
   let remaining := if N.leb after (N.of_nat (List.length hits)) then skipn (N.to_nat after) hits else [] in
   let more := N.ltb limit (N.of_nat (List.length remaining)) in
   State.success (JObject [("hits", JArray (firstn (N.to_nat limit) remaining)); ("after", number after);
    ("has_more", JBool more); ("next_after", if more then number (after+limit)%N else JNull)])
   else State.failure "invalid_search" "Search requires a query of 1..240 characters and a page size of 1..50"
 | None => State.failure "invalid_search" "Search query must contain valid Unicode" end.
