From Stdlib Require Import String List Bool NArith Ascii.
From Selvedge.Foundation Require Import TextJson.
From Selvedge.Adapters Require Import Common Observation Audio.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Record route := Route { route_method : string; route_path : string;
  route_target : string; route_body : bool }.
(** One route declaration drives both target selection and body admission. *)
Definition routes := [
  Route "POST" "/api/accounts/refresh" "account_refresh" true;
  Route "POST" "/api/browser/command" "browser_command" true;
  Route "POST" "/api/browser/observation" "browser_observation" true;
  Route "POST" "/api/commands" "command" true;
  Route "POST" "/api/assess" "assess" true;
  Route "GET" "/api/browser/state" "browser_state" false;
  Route "GET" "/api/describe" "describe" false;
  Route "GET" "/api/events" "events" false;
  Route "GET" "/api/event-page" "event_page" false;
  Route "GET" "/api/health" "health" false;
  Route "POST" "/api/remote/enable" "remote_enable" true;
  Route "POST" "/api/remote/disable" "remote_disable" true;
  Route "POST" "/api/remote/pair" "remote_pair" true;
  Route "POST" "/api/remote/approve" "remote_approve" true;
  Route "POST" "/api/remote/revoke" "remote_revoke" true;
  Route "GET" "/api/remote/status" "remote_status" false;
  Route "GET" "/api/remote/pending" "remote_pending" false].
Definition matches_route (source : json) (route : route) :=
  String.eqb (str source "method") route.(route_method) &&
  String.eqb (str source "pathname") route.(route_path) &&
  (negb (starts route.(route_target) "remote_") || String.eqb (str source "search") "").
Definition selected_route (source : json) := find (matches_route source) routes.
Definition action (kind : string) := JObject [("action",JString kind)].
Definition rejection (status : N) (code message : string) :=
  JObject [("action",JString "respond");("status",number status);
    ("value",JObject [("ok",JBool false);("error",JObject [("code",JString code);("message",JString message)])])].
Definition exception (kind message : string) := JObject
  [("action",JString "throw");("kind",JString kind);("message",JString message)].
Definition unknown_route := rejection 404 "not_found" "Unknown local endpoint".
Definition header (source : json) (key : string) := get (get source "headers") key.
Definition host_valid (source : json) := boolean_field source "address_present" &&
  is_text (get source "expected_host") && negb (String.eqb (str source "expected_host") "") &&
  equal (header source "host") (get source "expected_host").
Definition open_valid (source : json) := equal (get source "closing") (JBool false).
Definition open_host_guard (source : json) (next : json -> json) :=
  (* DEFENSE: Reject shutdown and an unrelated Host header before URL or secret observations. *)
  if negb (open_valid source) then rejection 503 "stopping" "Server is stopping"
  else if negb (host_valid source) then rejection 400 "host" "Invalid local host"
  else next source.
Definition connection_path (source : json) := starts (str source "pathname") "/api/chatgpt/".
Definition credential_observed (source : json) :=
  let authorization := get source "authorization" in
  if boolean_field authorization "present" then String.eqb (str authorization "type") "string"
  else negb (connection_path source) && boolean_field (get source "cookie") "present" &&
    String.eqb (str (get source "cookie") "type") "string".
Definition authorized (source : json) := boolean_field source "authorized" && credential_observed source.
Definition authorization_rejection (source : json) :=
  rejection 401 "unauthorized" (if connection_path source
    then "A connection credential is required" else "A local access token is required").
Definition local_origin_valid (source : json) :=
  negb (truthy (header source "origin")) || equal (header source "origin") (get source "address").
Definition connection_origin_valid (source : json) :=
  negb (truthy (header source "origin")) && String.eqb (str source "search") "".
Definition request_guard (source : json) (local connection : json -> json) :=
  open_host_guard source (fun source =>
    (* DEFENSE: Peer supplied URL and headers may reach any later HTTP stage directly. *)
    if negb (authorized source) then authorization_rejection source
    else if connection_path source then
      if negb (String.eqb (str source "method") "POST") then rejection 405 "method" "Use POST"
      else if negb (connection_origin_valid source) then rejection 403 "origin" "Browser origins and query parameters are not accepted"
      else connection source
    else if negb (local_origin_valid source) then rejection 403 "origin" "Origin does not match this server"
    else local source).
Fixpoint split_path (path : string) : list string :=
  match path with
  | EmptyString => [""]
  | String c rest =>
    if Ascii.eqb c "/" then ""::split_path rest
    else match split_path rest with first::tail => String c first::tail | [] => [] end
  end.
Definition audio_kind (source : json) :=
  match split_path (str source "pathname") with
  | ["";"api";"audio";kind] =>
    if existsb (String.eqb kind) ["capabilities";"transcribe";"sessions";"login"]
    then if String.eqb kind "sessions" then "create" else kind else ""
  | ["";"api";"audio";"sessions";id;kind] =>
    if negb (String.eqb id "") && existsb (String.eqb kind) ["events";"stop"] then kind else ""
  | _ => ""
  end.
Definition audio_target (source : json) :=
  let kind := audio_kind source in
  let method := if existsb (String.eqb kind) ["capabilities";"events"] then "GET" else "POST" in
  if negb (String.eqb kind "") && String.eqb (str source "method") method then "audio_" ++ kind else "".
Definition body_target (source : json) :=
  let audio := audio_target source in
  if existsb (String.eqb audio) ["audio_create";"audio_login"] then audio
  else match selected_route source with
    | Some route => if route.(route_body) then route.(route_target) else ""
    | None => if connection_path source && String.eqb (str source "method") "POST"
              then "connection_command" else ""
    end.
Definition local_target (source : json) :=
  if String.eqb (str source "method") "POST" && String.eqb (str source "pathname") "/api/board/attachments"
  then "attachment_upload"
  else if String.eqb (str source "method") "GET" && starts (str source "pathname") "/api/board/attachments/"
  then "attachment_download"
  else match selected_route source with Some route => route.(route_target) | None => audio_target source end.
Definition content_target (target : string) := JObject [("action",JString "observe_content_type");("target",JString target)].
Definition remote_path (source : json) := existsb (fun route =>
  starts route.(route_target) "remote_" && String.eqb (str source "pathname") route.(route_path)) routes.
Definition unknown_local (source : json) :=
  if remote_path source then
    if String.eqb (str source "search") "" then rejection 405 "method" "Use the remote management endpoint's supported method"
    else exception "TypeError" "Remote management endpoints do not accept query parameters"
  else unknown_route.
Definition upload (source : json) :=
  if negb (String.eqb (str source "method") "POST" && String.eqb (str source "pathname") "/api/board/attachments")
  then unknown_route
  else match get source "query" with
  | JArray [JArray [JString "name";JString _]] =>
    let length := header source "content-length" in
    let bounded := match length with JNull => true | JString value =>
      match parse_natural value with Some n => n <=? 10485760 | None => false end | _ => false end in
    if bounded then action "attachment_upload"
    else exception "RangeError" "Each board attachment is limited to 10 MiB"
  | _ => exception "TypeError" "An attachment upload needs exactly one filename"
  end.
Definition local_route (source : json) :=
  let target := local_target source in
  if String.eqb target "attachment_upload" then upload source
  else if String.eqb target "" then unknown_local source
  else if negb (String.eqb (body_target source) "") then content_target (body_target source)
  else action target.
Definition nonempty_text (value : json) := is_text value && negb (String.eqb (text value) "").
Definition permissions (body : json) :=
  exact_fields ["read";"control";"configure";"approve"] body &&
  forallb (fun key => is_bool (get body key)) ["read";"control";"configure";"approve"].
Definition body_shape (target : string) (body : json) :=
  if String.eqb target "remote_approve" then
    exact_fields ["request_id";"permissions"] body && nonempty_text (get body "request_id") && permissions (get body "permissions")
  else if String.eqb target "remote_revoke" then exact_fields ["controller_id"] body && nonempty_text (get body "controller_id")
  else if starts target "remote_" || String.eqb target "account_refresh" then exact_fields [] body
  else if String.eqb target "browser_command" then exact_fields ["command"] body
  else if String.eqb target "assess" then exact_fields ["command";"editor";"revision";"sequence"] body &&
    is_object (get body "command") &&
    (match natural (get body "revision"), natural (get body "sequence") with Some _,Some _ => true | _,_ => false end)
  else if String.eqb target "audio_login" then exact_fields ["browser_id"] body && nonempty_text (get body "browser_id")
  else if String.eqb target "audio_create" then exact_fields ["connection";"task_id";"sdp";"browser_id"] body &&
    forallb (fun key => nonempty_text (get body key)) ["connection";"sdp";"browser_id"]
  else true.
Definition body_error (target : string) := exception "TypeError"
  (if String.eqb target "audio_login" then "Voice sign-in contains only browser_id"
   else if String.eqb target "audio_create" then "Voice session requires connection, Task, SDP and browser identity"
   else if starts target "remote_" then "Invalid remote management request body"
   else if String.eqb target "account_refresh" then "Account refresh takes an empty object"
   else "A browser command contains only command").
Definition body_stage (body : bool) (source : json) :=
  let target := body_target source in
  if String.eqb target "" || negb (String.eqb (str source "target") target) then unknown_route
  else if negb (starts (str source "content_type") "application/json")
    then rejection 415 "content_type" "Send application/json"
  else if negb body then action target
  else match as_string (get source "text") with
  | None => body_error target
  | Some original =>
    match TextJson.parse_json original with
    | Some value => if body_shape target value then JObject
      [("action",JString target);("body",value)] else body_error target
    | None => body_error target
    end
  end.
Definition audio_limits := JObject [("allowed",JBool true);("max_bytes",number Audio.asr_max_bytes);
  ("timeout_ms",number Audio.request_timeout_ms);("connect_timeout_ms",number Audio.connect_timeout_ms);
  ("session_max_ms",number Audio.session_max_ms)].
Definition audio_reject (message : string) := JObject [("allowed",JBool false);("error",JString message)].
Definition audio_admission (source : json) :=
  let kind := str source "kind" in
  if String.eqb kind "create" then
    if nonempty_text (get source "browser_id") && boolean_field source "task_valid" && bound (get source "session_count") 0 0
    then audio_limits else audio_reject "Voice requires an existing Task and one session per browser"
  else if String.eqb kind "transcribe" then
    if nonempty_text (get source "browser_id") && starts (str source "mime") "audio/" &&
       bound (get source "body_bytes") 0 Audio.asr_max_bytes && bound (get source "elapsed_ms") 0 Audio.request_timeout_ms
    then audio_limits else audio_reject "Audio upload requires audio MIME and is limited to 25 MiB and 120 seconds"
  else if nonempty_text (get source "browser_id") && equal (get source "browser_id") (get source "owner") &&
    boolean_field source "exists" && bound (get source "elapsed_ms") 0 Audio.session_max_ms
  then audio_limits else audio_reject "Audio session is unavailable to this browser".
Definition call (operation : string) (source : json) :=
  if String.eqb operation "http.closing" then success
    (if boolean_field source "closing" then rejection 503 "stopping" "Server is stopping" else action "observe_host")
  else if String.eqb operation "http.preflight" then success (open_host_guard source (fun _ => action "parse_url"))
  else if String.eqb operation "http.route" then success (open_host_guard source (fun source =>
    if String.eqb (str source "method") "GET" && boolean_field source "asset" then action "asset"
    else action (if connection_path source then "observe_connection_authorization" else "observe_local_authorization")))
  else if String.eqb operation "http.connection_authorization" || String.eqb operation "http.local_authorization"
    then success (open_host_guard source (fun source =>
      if authorized source then action (if connection_path source then "connection_method_origin" else "local_origin")
      else authorization_rejection source))
  else if String.eqb operation "http.connection_method_origin" || String.eqb operation "http.local_origin"
    then success (request_guard source local_route (fun source => content_target (body_target source)))
  else if String.eqb operation "http.content_type" || String.eqb operation "http.body"
    then success (request_guard source (body_stage (String.eqb operation "http.body")) (body_stage (String.eqb operation "http.body")))
  else if String.eqb operation "http.reply_status" then success (number (if boolean_field (get source "reply") "ok" then 200 else 400))
  else if String.eqb operation "http.audio" then success (audio_admission source)
  else if String.eqb operation "http.public_command" then success (JObject [("allowed",JBool
    (negb (existsb (String.eqb (str (get source "command") "op")) ["record_speech_transcript";"accept_speech_delegation"])))])
  else err "Unknown HTTP operation".
