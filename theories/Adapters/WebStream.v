From Stdlib Require Import String List Bool NArith Ascii.
From Selvedge.Adapters Require Import WebCommon ProviderCatalog.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Record stream_state := StreamState {
  pending : string; event_data : list string; event_bytes : N; event_name : string }.
Record stream_work := StreamWork { current : stream_state; frames : list json; stream_error : string }.
Definition read_state value := StreamState (str value "pending") (map text (items (get value "data")))
  (num value "size") (str value "name").
Definition write_state state := JObject [("pending",JString state.(pending));
  ("data",JArray (map JString state.(event_data)));("size",number state.(event_bytes));("name",JString state.(event_name))].
Definition work_json work := success (JObject ([("state",write_state work.(current));
  ("frames",JArray work.(frames))] ++ optional (negb (String.eqb work.(stream_error) "")) "error" (JString work.(stream_error)))).
Definition stream_fail work message := StreamWork work.(current) work.(frames) message.
Definition leading_space value := match value with String character rest =>
  if Ascii.eqb character " "%char then rest else value | _ => value end.
Fixpoint reverse_string source result := match source with EmptyString => result
  | String first rest => reverse_string rest (String first result) end.
Definition strip_cr value :=
  match List.rev_append (list_ascii_of_string value) [] with
  | [] => value | first::rest => if Ascii.eqb first (ascii_of_nat 13)
      then String.string_of_list_ascii (List.rev_append rest []) else value end.
Fixpoint drop_bytes (count : nat) value := match count,value with
  | O,_ => value | S rest,String _ tail => drop_bytes rest tail | _,EmptyString => EmptyString end.

Definition normalized_name value := if String.eqb value "" then "message" else value.
Definition emit_frame state := match state.(event_data) with [] => [] | _ =>
  [JObject [("event",JString state.(event_name));("data",JString (String.concat "
" state.(event_data)))]] end.
Definition process_line (line : string) (work : stream_work) maximum :=
  let original := line in let line := strip_cr line in let state := work.(current) in
  let work := StreamWork (StreamState original state.(event_data) state.(event_bytes) state.(event_name)) work.(frames) work.(stream_error) in
  if String.eqb line "" then StreamWork (StreamState "" [] 0 "message")
    (List.app work.(frames) (emit_frame state)) work.(stream_error)
  else let cleared := StreamState "" state.(event_data) state.(event_bytes) state.(event_name) in
  if String.prefix "event:" line then
    let size := state.(event_bytes) + N.of_nat (String.length line) + 1 in
    if size <=? maximum then StreamWork
      (StreamState "" state.(event_data) size (normalized_name (leading_space (drop_bytes 6 line)))) work.(frames) ""
    else stream_fail work "SSE event exceeds the configured limit"
  else if String.prefix "data:" line then
    let part := leading_space (drop_bytes 5 line) in
    let size := state.(event_bytes) + N.of_nat (String.length part) + 1 in
    if size <=? maximum then StreamWork
      (StreamState "" (List.app state.(event_data) [part]) size state.(event_name)) work.(frames) ""
    else stream_fail work "SSE event exceeds the configured limit"
  else StreamWork cleared work.(frames) "".
(* A reversed local line buffer makes each scalar transition linear in its UTF-8
   width. Overflow never splits a scalar into malformed output bytes. The
   serialized state contains only the actual pending text, never a second counter. *)
Definition scan_character maximum (buffer : (list ascii * N) * stream_work) (character : N * string) :=
  let '(reversed,bytes,work) := buffer in let character := snd character in
  if negb (String.eqb work.(stream_error) "") then buffer
  else if String.eqb character "
" then
    let line := String.string_of_list_ascii (List.rev_append reversed []) in
    let next := process_line line work maximum in
    if String.eqb next.(stream_error) "" then ([],0,next) else (reversed,bytes,next)
  else let bytes := bytes + N.of_nat (String.length character) in
    let reversed := fold_left (fun result byte => byte::result) (list_ascii_of_string character) reversed in
    let next := if bytes <=? maximum then work else stream_fail work "SSE line exceeds the configured limit" in
    (reversed,bytes,next).
Definition scan chunk reversed bytes work maximum :=
  fold_left (scan_character maximum) chunk (reversed,bytes,work).

Definition sse_step source := let state := read_state (get source "state") in
  let chunk := str source "chunk" in
  if boolean_field source "eof" then
    let pending := state.(pending) ++ chunk in
    work_json (StreamWork (StreamState pending state.(event_data) state.(event_bytes) state.(event_name)) []
      (if String.eqb pending "" && Nat.eqb (List.length state.(event_data)) 0
       then "" else "The SSE stream ended inside an event"))
  else let initial := StreamWork state [] "" in
    let maximum := num source "maximum" in
    let initial := if N.of_nat (String.length state.(pending)) <=? maximum then initial
      else stream_fail initial "SSE line exceeds the configured limit" in
    let reversed := fold_left (fun result byte => byte::result) (list_ascii_of_string state.(pending)) [] in
    match Utf8.chunks chunk with
    | None => err "Invalid ChatGPT Web JSON source"
    | Some characters =>
    let '(reversed,_,work) := scan characters reversed (N.of_nat (String.length state.(pending))) initial maximum in
    let pending := String.string_of_list_ascii (List.rev_append reversed []) in
    let state := work.(current) in
    work_json (StreamWork (StreamState pending state.(event_data) state.(event_bytes) state.(event_name)) work.(frames) work.(stream_error)) end.
Fixpoint trim_chunks (values : list (N * string)) := match values with
  | [] => [] | item::rest => if Utf8.whitespace (fst item) then trim_chunks rest else values end.
Definition trim_header value := match Utf8.chunks value with
  | Some chunks =>
    Utf8.render_chunks (List.rev (trim_chunks (List.rev (trim_chunks chunks))))
  | None => value end.
Fixpoint content_type_prefix source := match source with EmptyString => EmptyString
  | String first rest => if Ascii.eqb first ";"%char then EmptyString else String first (content_type_prefix rest) end.
Definition headers source :=
  if negb (is_null (get source "version") || eq source "version" "chatgpt-web.v1")
  then err "ChatGPT Web protocol version does not match v1"
  else if is_null (get source "content_type") then success (JString "sse")
  else match ProviderCatalog.lower_ascii (trim_header (content_type_prefix (str source "content_type"))) with
    | "application/json" => success (JString "json") | "text/event-stream" => success (JString "sse")
    | _ => err "ChatGPT Web did not return JSON or SSE" end.
