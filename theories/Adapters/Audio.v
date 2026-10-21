From Stdlib Require Import String List Bool NArith Ascii.
From Selvedge.Foundation Require Import Utf8.
From Selvedge.Adapters Require Import Common Observation.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition asr_max_bytes : N := 26214400.
Definition connect_timeout_ms : N := 20000.
Definition request_timeout_ms : N := 120000.
Definition session_max_ms : N := 3600000.
Definition nonempty_text (value : json) := is_text value && negb (String.eqb (text value) "").
Definition admit (accepted : bool) (value : json) (message : string) :=
  if accepted then success value else failure "audio_invalid_request" message.
Definition contract := JObject [("transcribe_url",JString "https://chatgpt.com/backend-api/transcribe");
  ("calls_url",JString "https://chatgpt.com/backend-api/wham/realtime/calls?intent=quicksilver&architecture=avas");
  ("sideband_base",JString "wss://api.openai.com/v1/live/");
  ("connect_timeout_ms",number connect_timeout_ms);("request_timeout_ms",number request_timeout_ms);
  ("session_max_ms",number session_max_ms);("asr_max_bytes",number asr_max_bytes);
  ("response_max_bytes",number 2097152);("event_max_bytes",number 2097152);("context_chunk_bytes",number 500)].
Definition authorized (source : json) := boolean_field source "authorized" && String.eqb (str source "source") "chatgpt_audio".
Definition eligible (source : json) := authorized source && nonempty_text (get source "id").
Definition capability (source : json) := JObject [("id",get source "id");("label",JString "ChatGPT");
  ("source",JString "chatgpt_audio");("asr",JBool true);("voice",JBool true)].
Definition request_connection (source : json) := nonempty_text (get source "connection") && authorized source.
Fixpoint before_semicolon (value : string) : string :=
  match value with EmptyString => "" | String c rest =>
    if Ascii.eqb c ";" then "" else String c (before_semicolon rest) end.
Definition mime_subtype (value : string) := before_semicolon (String.substring 6 (String.length value) value).
Definition asr_request (source : json) :=
  admit (request_connection source && bound (get source "bytes") 1 asr_max_bytes &&
    starts (str source "mime") "audio/" && negb (String.eqb (mime_subtype (str source "mime")) "") &&
    (is_null (get source "language") || nonempty_text (get source "language")))
    (JObject [("mime",get source "mime");("language",get source "language");
      ("filename",JString ("recording." ++ mime_subtype (str source "mime")))])
    "Audio transcription requires a signed-in ChatGPT connection and 1 to 26214400 audio bytes".
Definition initial_item (item : json) :=
  String.eqb (str item "type") "message" && existsb (String.eqb (str item "role")) ["user";"assistant"] &&
  is_array (get item "content") && forallb (fun content =>
    existsb (String.eqb (str content "type")) ["input_text";"output_text"] && nonempty_text (get content "text")) (items (get item "content")).
Definition session_instructions :=
  "You are speaking with the user in Selvedge. Converse naturally. Delegate explicit requests to perform work to the client; transcript events alone never start work. Use delegation context updates as the authoritative progress of accepted work. Ending this voice call does not cancel accepted tasks.".
Definition session_request (source : json) :=
  let initial := get source "initial_items" in
  admit (request_connection source && bound (get source "task_id") 0 9007199254740991 &&
    nonempty_text (get source "id") && nonempty_text (get source "sdp") &&
    (is_null initial || (is_array initial && forallb initial_item (items initial))))
    (JObject [("sdp",get source "sdp");("session",JObject [("model",JString "gpt-live-1-codex");
      ("delegation",JObject [("type",JString "client")]);("audio",JObject [("output",JObject [("voice",JString "arbor")])]);
      ("instructions",JString session_instructions);("voice_session_id",get source "id");
      ("initial_items",if is_array initial then initial else JArray [])])])
    "Voice requires a signed-in ChatGPT connection, an existing task and an SDP offer".
Definition response_failure (source : json) := failure "audio_upstream_rejected"
  ("ChatGPT audio request failed with HTTP " ++ diagnostic (get source "status")).
Definition asr_response (source : json) :=
  if bound (get source "status") 200 299 then
    admit (is_text (get (get source "value") "text")) (JObject [("text",get (get source "value") "text")])
      "ChatGPT transcription response is missing text"
  else response_failure source.
Definition session_response (source : json) :=
  if bound (get source "status") 200 299 then
    admit (nonempty_text (get source "sdp") && starts (str source "call_id") "rtc_" && negb (String.eqb (str source "call_id") "rtc_"))
      (JObject [("call_id",get source "call_id");("sdp",get source "sdp")]) "ChatGPT voice response is missing SDP or call identity"
  else response_failure source.
Definition input_text (content : list json) := String.concat "" (map (fun item =>
  if String.eqb (str item "type") "input_text" then str item "text" else "") content).
Fixpoint turn_text (turns : list json) (id : json) :=
  match turns with [] => "" | turn::rest =>
    if equal (get turn "turn_id") id then str turn "text" else turn_text rest id end.
Definition delegation (item source : json) :=
  let own := input_text (items (get item "content")) in
  let message := if String.eqb own "" then turn_text (items (get source "turns")) (get item "user_bidi_turn_id") else own in
  admit (String.eqb (str item "type") "delegation" && String.eqb (str item "target") "client" &&
    nonempty_text (get item "id") && (nonempty_text (get item "user_bidi_turn_id") || negb (String.eqb own "")))
    (JObject [("type",JString (if String.eqb message "" then "delegation_pending" else "delegation"));
      ("item_id",get item "id");("text",JString message);("turn_id",get item "user_bidi_turn_id")])
    "Invalid client voice delegation".
Definition transcript (turn : json) :=
  admit (existsb (String.eqb (str turn "role")) ["user";"assistant"] && is_text (get turn "transcript"))
    (if String.eqb (str turn "transcript") "" then JNull else JObject [("type",JString "transcript");
      ("role",get turn "role");("text",get turn "transcript");("item_id",get turn "id")]) "Invalid completed voice transcript".
Definition event (source : json) :=
  let value := get source "value" in let kind := str value "type" in
  if String.eqb kind "turn.done" then transcript (get value "turn")
  else if String.eqb kind "delegation.created" then delegation (get value "item") source
  else if existsb (String.eqb kind) ["session.started";"session.updated"] then success (JObject [("type",JString "ready")])
  else if existsb (String.eqb kind) ["input_transcript.added";"output_transcript.added"] then
    admit (is_text (get (get value "item") "text"))
      (JObject [("type",JString "delta");("role",JString (if String.eqb kind "input_transcript.added" then "user" else "assistant"));
        ("text",get (get value "item") "text")]) "Invalid voice transcript increment"
  else if String.eqb kind "conversation.handoff.requested" then
    delegation (JObject [("type",JString "delegation");("target",JString "client");
      ("id",get value "item_id");("user_bidi_turn_id",get value "user_bidi_turn_id");
      ("content",JArray [JObject [("type",JString "input_text");("text",get value "input_transcript")]])]) source
  else if String.eqb kind "turn.created" then
    let turn := get value "turn" in
    if String.eqb (str turn "role") "assistant" then success JNull
    else admit (String.eqb (str turn "role") "user" && nonempty_text (get turn "id") && nonempty_text (get turn "transcript"))
      (JObject [("type",JString "turn");("turn_id",get turn "id");("text",get turn "transcript")]) "Invalid voice user-turn association"
  else if String.eqb kind "error" then success (JObject [("type",JString "error");("error",JString "ChatGPT voice control reported an error")])
  else success JNull.
Definition context (source : json) :=
  let id := get source "delegation_item_id" in let channel := get source "channel" in
  admit (nonempty_text (get source "text") && (is_null id || nonempty_text id) &&
    (is_null channel || existsb (String.eqb (text channel)) ["commentary";"speakable"]))
    (JObject ([("type",JString (if is_null id then "session.context.append" else "delegation.context.append"));
      ("channel",if is_null channel then JString "speakable" else channel);
      ("content",JArray [JObject [("type",JString "input_text");("text",get source "text")]])] ++
      optional (negb (is_null id)) "delegation_item_id" id)) "Voice context requires text and an optional delegation identity".
Definition initial_context_plan (source : json) :=
  admit (bound (get source "cursor") 0 9007199254740991)
    (JObject [("after",number (num source "cursor" - 100));("limit",number 100)]) "Voice history requires a committed Task cursor".
Definition initial_message (role : string) (content : json) := JObject [("type",JString "message");("role",JString role);
  ("content",JArray [JObject [("type",JString (if String.eqb role "assistant" then "output_text" else "input_text"));("text",content)]])].
Definition initial_history_item (assistant : json -> bool) (content : json -> json) (message : json) : list json :=
  let role := if assistant message then JString "assistant"
    else if String.eqb (str message "role") "speech_transcript" then get message "speaker" else get message "role" in
  (if existsb (String.eqb (text role)) ["user";"assistant"] && nonempty_text (content message)
   then [initial_message (text role) (content message)] else []) ++
  if String.eqb (str message "role") "context_replacement" && nonempty_text (get message "content")
  then [initial_message "user" (JString ("Previous Task context summary:
" ++ str message "content"))] else [].
Definition initial_context (assistant : json -> bool) (content : json -> json) (source : json) :=
  admit (is_array (get source "messages"))
    (JArray (flat_map (initial_history_item assistant content) (items (get source "messages")))) "Voice history requires committed Task messages".
Definition task_progress (assistant : json -> bool) (content : json -> json) (source : json) :=
  let channel := if String.eqb (str (get source "task") "phase") "idle" then "speakable" else "commentary" in
  admit (is_array (get source "messages")) (JArray (flat_map (fun message =>
    if (assistant message || String.eqb (str message "role") "error") && nonempty_text (content message)
    then [JObject [("text",content message);("channel",JString channel)]] else []) (items (get source "messages"))))
    "Voice progress requires committed Task messages".
Definition transcript_tail (source : json) :=
  let pending := str source "pending" in let completed := str source "completed" in
  admit (is_text (get source "pending") && is_text (get source "completed"))
    (JString (if starts pending completed then String.substring (String.length completed) (String.length pending) pending
      else if starts completed pending then "" else pending)) "Voice transcript completion requires its accumulated partial text".
Definition login_target (source : json) :=
  admit (nonempty_text (get source "url") && String.eqb (str source "protocol") "https:" &&
    String.eqb (str source "hostname") "auth.openai.com" && String.eqb (str source "pathname") "/oauth/authorize" &&
    String.eqb (str source "username") "" && String.eqb (str source "password") "" &&
    existsb (String.eqb (str source "port")) ["";"443"])
    (JObject [("url",get source "url")]) "Invalid ChatGPT authorization URL".
Definition call (transport : json -> json) (assistant : json -> bool) (content : json -> json)
  (operation : string) (source : json) :=
  if String.eqb operation "audio.contract" then success contract
  else if String.eqb operation "audio.capability" then admit (eligible source) (capability source) "ChatGPT audio sign-in is required"
  else if String.eqb operation "audio.capabilities" then admit (is_array (get source "connections"))
    (JArray (map capability (filter eligible (items (get source "connections"))))) "Audio account discovery requires ChatGPT account observations"
  else if String.eqb operation "audio.asr_request" then asr_request source
  else if String.eqb operation "audio.asr_response" then asr_response source
  else if String.eqb operation "audio.session_request" then session_request source
  else if String.eqb operation "audio.session_response" then session_response source
  else if String.eqb operation "audio.event" then event source
  else if String.eqb operation "audio.context" then context source
  else if String.eqb operation "audio.initial_context_plan" then initial_context_plan source
  else if String.eqb operation "audio.initial_context" then initial_context assistant content source
  else if String.eqb operation "audio.task_progress" then task_progress assistant content source
  else if String.eqb operation "audio.transcript_tail" then transcript_tail source
  else if String.eqb operation "audio.login_target" then login_target source
  else if String.eqb operation "audio.transport" then transport source
  else err "Unknown audio operation".
