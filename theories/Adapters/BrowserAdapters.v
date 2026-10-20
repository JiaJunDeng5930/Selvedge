From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Utf8.
From Selvedge.Kernel Require Import Images Streams.
From Selvedge.Adapters Require Import Common Observation.
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
Definition stream_step (configuration : Streams.configuration) (source : json) :=
  match Streams.decode_state (get source "state"),Streams.decode_event (get source "notice") with
  | Some state,Some event => let '(state,publish) := Streams.step configuration event state in
    success (JObject [("state",Streams.state_json state);("publish",JBool publish)])
  | _,_ => err "Invalid browser stream source: expected typed stream state and notice"
  end.
Definition call (operation : string) (source : json) :=
  if String.eqb operation "browser.link" then success (link source)
  else if String.eqb operation "browser.image" then success (image source)
  else if String.eqb operation "browser.stream_step" then stream_step Streams.browser_configuration source
  else if String.eqb operation "browser.host_stream_step" then stream_step Streams.host_configuration source
  else err ("Unknown browser model operation: " ++ operation).
