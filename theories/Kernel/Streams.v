From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers Utf8 Schema TextMetrics.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Record stream_key := StreamKey { stream_task : N; stream_ticket : N }.
Record stream_part := StreamPart { part_index : N; part_text : string }.
Record stream := Stream { stream_identity : stream_key; stream_parts : list stream_part }.
Definition state := list stream.
Inductive event := Start (key : stream_key) | Delta (key : stream_key) (index : N) (text : string)
  | Snapshot (key : stream_key) (index : N) (text : string) | Finish (key : stream_key)
  | Restore (streams : state) | Ignore.
Record configuration := Configuration { bounded : bool; restore_enabled : bool }.
Definition browser_configuration := Configuration true true.
Definition host_configuration := Configuration false false.
Definition key_equal (left right : stream_key) :=
  N.eqb left.(stream_task) right.(stream_task) && N.eqb left.(stream_ticket) right.(stream_ticket).
Definition utf16_units := TextMetrics.utf16_units.
Definition text_within_budget (text : string) := match utf16_units text with
  | Some units => units <=? 4194304 | None => false end.
Definition parts_within_budget (parts : list stream_part) :=
  Nat.leb (List.length parts) 32 && forallb (fun part => text_within_budget part.(part_text)) parts.
Fixpoint put_part (value : stream_part) (parts : list stream_part) :=
  match parts with [] => [value] | part::rest =>
    if N.eqb part.(part_index) value.(part_index) then value::rest else part::put_part value rest end.
Fixpoint put_stream (value : stream) (streams : state) :=
  match streams with [] => [value] | entry::rest =>
    if key_equal entry.(stream_identity) value.(stream_identity) then value::rest else entry::put_stream value rest end.
Definition normalized_parts (parts : list stream_part) := fold_left (fun current value => put_part value current) parts [].
Definition normalized_state (streams : state) := fold_left (fun current value =>
  put_stream (Stream value.(stream_identity) (normalized_parts value.(stream_parts))) current) streams [].
Definition find_parts (streams : state) (task ticket : N) : option (list (N * string)) :=
  match find (fun entry => key_equal entry.(stream_identity) (StreamKey task ticket)) streams with
  | None => None | Some entry => Some (map (fun part => (part.(part_index),part.(part_text))) entry.(stream_parts)) end.
Definition part_value (parts : list stream_part) (index : N) :=
  option_map part_text (find (fun part => N.eqb part.(part_index) index) parts).
Definition update_part (delta : bool) (limits : configuration) (entry : stream) (index : N) (text : string) : option stream :=
  let found := part_value entry.(stream_parts) index in
  let combined := if delta then match found with Some previous => previous ++ text | None => text end else text in
  if negb limits.(bounded) || (text_within_budget combined &&
    (Nat.ltb (List.length entry.(stream_parts)) 32 || match found with Some _ => true | None => false end))
  then Some (Stream entry.(stream_identity) (put_part (StreamPart index combined) entry.(stream_parts))) else None.
Fixpoint update (delta : bool) (limits : configuration) (key : stream_key) (index : N) (text : string) (streams : state) : state * bool :=
  match streams with
  | [] => ([],false)
  | entry::rest => if key_equal entry.(stream_identity) key then
      match update_part delta limits entry index text with Some updated => (updated::rest,true) | None => (entry::rest,false) end
    else let '(tail,publish) := update delta limits key index text rest in (entry::tail,publish)
  end.
(** This is a transport accumulator. Application authorization relates its
    task/ticket to the committed pending request before assigning an origin. *)
Definition step (limits : configuration) (notice : event) (streams : state) : state * bool :=
  match notice with
  | Start key => (put_stream (Stream key []) streams,true)
  | Finish key => (filter (fun entry => negb (key_equal entry.(stream_identity) key)) streams,true)
  | Delta key index text => update true limits key index text streams
  | Snapshot key index text => update false limits key index text streams
  | Restore restored =>
    if limits.(restore_enabled) then
      let restored := normalized_state restored in
      (* DEFENSE: A reconnect can carry an unbounded host stream; restoration must obey the browser's existing text/part limits. *)
      if negb limits.(bounded) || forallb (fun entry => parts_within_budget entry.(stream_parts)) restored
      then (restored,true) else (streams,false)
    else (streams,false)
  | Ignore => (streams,false)
  end.
Record live_output := LiveOutput { output_task : N; output_operation : N; output_parts : list (N * string) }.
Definition cumulative (streams : state) (task ticket operation : N) : option live_output :=
  option_map (LiveOutput task operation) (find_parts streams task ticket).
Definition value (source : json) (key : string) := match field key source with Some value => value | None => JNull end.
Definition integer (source : json) : option N := match source with
  | JNumber text => match parse_natural text with
    | Some value => if String.eqb text (show_natural value) then Some value else None
    | None => None end
  | _ => None end.
Definition decode_key (source : json) := match integer (value source "task_id"),integer (value source "ticket") with
  | Some task,Some ticket => Some (StreamKey task ticket) | _,_ => None end.
Definition decode_part (source : json) := match integer (value source "output_index"),as_string (value source "text") with
  | Some index,Some text => if Utf8.well_formed text then Some (StreamPart index text) else None | _,_ => None end.
Fixpoint traverse {A B : Type} (parse : A -> option B) (values : list A) : option (list B) :=
  match values with [] => Some [] | value::rest => match parse value,traverse parse rest with
    Some value,Some rest => Some (value::rest) | _,_ => None end end.
Definition decode_stream (source : json) := match decode_key source,as_array (value source "parts") with
  | Some key,Some parts => option_map (Stream key) (traverse decode_part parts) | _,_ => None end.
Fixpoint unique_by {A : Type} (equal : A -> A -> bool) (values : list A) :=
  match values with [] => true | value::rest => negb (existsb (equal value) rest) && unique_by equal rest end.
Definition unique_state (streams : state) :=
  unique_by (fun left right => key_equal left.(stream_identity) right.(stream_identity)) streams &&
  forallb (fun entry => unique_by (fun left right => N.eqb left.(part_index) right.(part_index)) entry.(stream_parts)) streams.
Definition decode_state (source : json) : option state :=
  match as_array source with None => None | Some values => match traverse decode_stream values with
    | None => None | Some streams => if unique_state streams then Some streams else None end end.
Definition decode_event (source : json) : option event :=
  match as_string (value source "type") with
  | None => None
  | Some kind =>
    if String.eqb kind "stream-state" then
      match as_array (value source "streams") with Some values => option_map Restore (traverse decode_stream values) | None => None end
    else match decode_key source with
    | None => if (String.eqb kind "delta" || String.eqb kind "snapshot") &&
        negb (match as_string (value source "text") with Some text => Utf8.well_formed text | None => false end)
      then None else Some Ignore
    | Some key =>
      if String.eqb kind "stream_start" then Some (Start key)
      else if String.eqb kind "stream_end" || String.eqb kind "stream_cancel" then Some (Finish key)
      else if String.eqb kind "delta" || String.eqb kind "snapshot" then
        match integer (value source "output_index"),as_string (value source "text") with
        | Some index,Some text => if Utf8.well_formed text then Some (if String.eqb kind "delta" then Delta key index text else Snapshot key index text) else None
        | None,Some text => if Utf8.well_formed text then Some Ignore else None
        | _,_ => None end
      else Some Ignore
    end
  end.
Definition decode_event_in_namespace (namespace_is_valid : bool) (namespace : string) (source : json) : option event :=
  match string_field "namespace" source with
  | Some received =>
      if namespace_is_valid && String.eqb received namespace then decode_event source else Some Ignore
  | None => None
  end.
Definition part_json (part : stream_part) := JObject [("output_index",JNumber (show_natural part.(part_index)));("text",JString part.(part_text))].
Definition stream_json (entry : stream) := JObject [("task_id",JNumber (show_natural entry.(stream_identity).(stream_task)));
  ("ticket",JNumber (show_natural entry.(stream_identity).(stream_ticket)));("parts",JArray (map part_json entry.(stream_parts)))].
Definition state_json (streams : state) := JArray (map stream_json streams).
