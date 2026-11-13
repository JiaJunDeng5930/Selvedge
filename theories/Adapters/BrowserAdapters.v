From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Utf8.
From Selvedge.Kernel Require Import Images Streams.
From Selvedge.Kernel Require Conversation OutputClassification Search.
From Selvedge.Adapters Require Import Common Observation.
From Selvedge.Interaction Require Codec.
From Selvedge.Interaction Require Import Origin.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition navigation_character (code : N) := (32 <? code) && negb (N.eqb code 127 || N.eqb code 92).
Definition allowed_target (target : string) := starts target "https:" || starts target "http:" || starts target "mailto:".
Definition raw_valid (raw : json) :=
  is_text raw && match Utf8.decode (text raw) with
    | Some values => forallb navigation_character values | None => false end.
Definition link (source : json) :=
  let raw := get source "raw" in let observation := get source "observation" in
  if raw_valid raw then
    if starts (text raw) "#" then raw
    else if existsb (String.eqb (str observation "scheme")) ["https:";"http:";"mailto:"] &&
      boolean_field observation "parsed" && is_text (get observation "href") && Utf8.well_formed (str observation "href") &&
      (* DEFENSE: The final external URL observation itself must retain an allowed scheme. *)
      allowed_target (str observation "href")
    then get observation "href" else JNull
  else JNull.
Definition image (source : json) :=
  let raw := get source "raw" in let prefix := "/api/board/attachments/" in
  if is_text raw && starts (text raw) prefix &&
    Images.valid_identifier (String.substring (String.length prefix) (String.length (text raw)) (text raw))
  then raw else JNull.

Definition history_excerpt (needle : string) (width : nat) (text : string) : option string :=
  let lowered := Search.lower text in
  if Search.contains needle lowered then
    Codec.bind (Utf8.chunks text) (fun chunks =>
    let position := Search.match_offset needle lowered 0 in
    let start := (position - 44)%nat in
    let stop := (position + width + 100)%nat in
    Some ((if Nat.eqb start 0 then "" else "…") ++
      Search.trim (Utf8.render_chunks (firstn (stop - start)%nat (skipn start chunks))) ++
      (if Nat.ltb stop (List.length chunks) then "…" else "")))
  else None.
Fixpoint first_history_excerpt (needle : string) (width : nat) (blocks : list json) : option string :=
  match blocks with
  | [] => None
  | block :: rest =>
    let found := if OutputClassification.interactive_markdown_fence_observation (get block "fence")
      then None else Codec.bind (string_field "text" block) (history_excerpt needle width) in
    match found with Some excerpt => Some excerpt | None => first_history_excerpt needle width rest end
  end.
Definition history_preview (source : json) :=
  let query := Search.trim (str source "query") in
  match Utf8.scalar_count query with
  | Some width => if Search.valid_length width
    then success (match first_history_excerpt (Search.lower query) width (items (get source "blocks")) with
      | Some excerpt => JString excerpt | None => JNull end)
    else type_error "Expected a valid history search query"
  | None => type_error "Expected a valid history search query"
  end.
Definition stream_step (configuration : Streams.configuration) (source : json) :=
  match Streams.decode_state (get source "state"),Streams.decode_event (get source "notice") with
  | Some state,Some event => let '(state,publish) := Streams.step configuration event state in
    success (JObject [("state",Streams.state_json state);("publish",JBool publish)])
  | _,_ => err "Invalid browser stream source: expected typed stream state and notice"
  end.
Definition public_stream_step (source : json) :=
  match Streams.decode_state (get source "state"),string_field "namespace" source with
  | Some state,Some namespace =>
    match Streams.decode_event_in_namespace (Origin.valid_namespace namespace) namespace (get source "notice") with
    | Some event => let '(state,publish) := Streams.step Streams.browser_configuration event state in
      success (JObject [("state",Streams.state_json state);("publish",JBool publish)])
    | None => err "Invalid browser stream source: expected a namespaced typed notice"
    end
  | _,_ => err "Invalid browser stream source: expected current namespace and typed stream state"
  end.
Definition call (operation : string) (source : json) :=
  if String.eqb operation "browser.link" then success (link source)
  else if String.eqb operation "browser.image" then success (image source)
  else if String.eqb operation "browser.history_text"
    then success (Conversation.json_message_content (get source "message"))
  else if String.eqb operation "browser.history_preview" then history_preview source
  else if String.eqb operation "browser.stream_step" then public_stream_step source
  else if String.eqb operation "browser.host_stream_step" then stream_step Streams.host_configuration source
  else err ("Unknown browser model operation: " ++ operation).
