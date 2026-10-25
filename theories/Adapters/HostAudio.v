From Stdlib Require Import String List NArith.
From Selvedge.Adapters Require Import Common Audio.
From Selvedge.Host Require Import AudioState AudioSession AudioConnection AudioTransport.
From Selvedge.Kernel Require Import Conversation.
Import ListNotations.
Open Scope string_scope.

Definition stream_step (source : json) :=
  let state := AudioState.stream_of (get source "state") in
  let observed := get source "observation" in
  let kind := str observed "kind" in
  let observation := if String.eqb kind "open" then Some AudioState.Opened
    else if String.eqb kind "event" then Some (AudioState.ProviderEvent (get observed "value"))
    else if String.eqb kind "stop" then Some (AudioState.StopRequested (str observed "message"))
    else if String.eqb kind "startup_timeout" then Some (AudioState.StartupTimeout (str observed "message")) else None in
  match observation with None => failure "TypeError" "Unknown audio stream observation" | Some observation =>
    let '(next,effects) := AudioState.step state (get observed "generation") observation in
    success (JObject [("state",AudioState.stream_json next);("actions",JArray (map (AudioState.primitive_json next) effects))]) end.
Definition session_step (source : json) :=
  let state := AudioSession.state_of (get source "state") in let observed := get source "observation" in
  let kind := str observed "kind" in
  let observation := if String.eqb kind "event" then Some (AudioSession.Event (get observed "event"))
    else if String.eqb kind "ack" then Some (AudioSession.JournalAck (get observed "token") (get observed "reply"))
    else if String.eqb kind "journal_failed" then Some (AudioSession.JournalFailed (str observed "message"))
    else if String.eqb kind "stop" then Some AudioSession.Stop
    else if String.eqb kind "progress" then Some AudioSession.ProgressRequested
    else if String.eqb kind "progress_failed" then Some (AudioSession.ProgressFailed (num observed "token") (str observed "message"))
    else if String.eqb kind "delivered" then Some (AudioSession.ProgressDelivered (num observed "token"))
    else if String.eqb kind "creation_failed" then Some AudioSession.CreationFailed
    else if String.eqb kind "connected" then Some AudioSession.Connected
    else if String.eqb kind "cursor" then let page := get observed "page" in
      Some (AudioSession.InitialCursor (num page "after" + N.of_nat (List.length (items (get page "messages"))))%N)
    else if String.eqb kind "page" then
      let updates := Audio.task_progress Conversation.json_message_assistant Conversation.json_message_content (get observed "page") in
      Some (AudioSession.ProgressPage (num observed "token") (get observed "page") (items (get updates "value"))) else None in
  match observation with None => failure "TypeError" "Unknown audio session observation" | Some observation =>
    let '(next,effects) := AudioSession.step state (get observed "generation") observation in
    success (JObject [("state",AudioSession.state_json next);("actions",JArray (map (AudioSession.primitive_json next) effects))]) end.
Definition connection_step (source : json) :=
  let state := AudioConnection.state_of (get source "state") in let observed := get source "observation" in
  let attempt := num observed "attempt" in let kind := str observed "kind" in
  let observation := if String.eqb kind "open" then Some (AudioConnection.Opened attempt)
    else if String.eqb kind "upgrade" then Some (AudioConnection.UpgradeRejected attempt (num observed "status"))
    else if String.eqb kind "error" then Some (AudioConnection.SocketFailed attempt (str observed "message"))
    else if String.eqb kind "close" then Some (AudioConnection.SocketClosed attempt (num observed "code"))
    else if String.eqb kind "message" then Some (AudioConnection.ProviderMessage attempt (get observed "raw"))
    else if String.eqb kind "retry" then Some (AudioConnection.RetryElapsed attempt)
    else if String.eqb kind "stop" then Some AudioConnection.Stop else None in
  match observation with None => failure "TypeError" "Unknown audio connection observation" | Some observation =>
    let '(next,effects) := AudioConnection.step state observation in
    success (JObject [("state",AudioConnection.state_json next);("actions",JArray (map AudioConnection.primitive_json effects))]) end.
Definition transport_step (source : json) :=
  let state := AudioTransport.state_of (get source "state") in let observed := get source "observation" in
  let kind := str observed "kind" in let attempt := num observed "attempt" in
  let observation := if String.eqb kind "ack" then Some (AudioTransport.EmitAck (num observed "token"))
    else if String.eqb kind "failed" then Some (AudioTransport.EmitFailed (num observed "token"))
    else if String.eqb kind "stop" then Some (AudioTransport.GracefulStop (str observed "message"))
    else if String.eqb kind "startup_timeout" then Some (AudioTransport.StartupTimeout (str observed "message"))
    else if String.eqb kind "open" then Some (AudioTransport.Arrival (AudioConnection.Opened attempt))
    else if String.eqb kind "upgrade" then Some (AudioTransport.Arrival (AudioConnection.UpgradeRejected attempt (num observed "status")))
    else if String.eqb kind "error" then Some (AudioTransport.Arrival (AudioConnection.SocketFailed attempt (str observed "message")))
    else if String.eqb kind "close" then Some (AudioTransport.Arrival (AudioConnection.SocketClosed attempt (num observed "code")))
    else if String.eqb kind "message" then Some (AudioTransport.Arrival (AudioConnection.ProviderMessage attempt (get observed "value")))
    else if String.eqb kind "retry" then Some (AudioTransport.Arrival (AudioConnection.RetryElapsed attempt)) else None in
  match observation with None => failure "TypeError" "Unknown audio transport observation" | Some observation =>
    let '(next,actions) := AudioTransport.step state observation in
    success (JObject [("state",AudioTransport.state_json next);("actions",JArray actions)]) end.
Definition call (operation : string) (source : json) : json :=
  if String.eqb operation "control.audio.transport_initial" then
    let '(state,actions) := AudioTransport.begin (AudioTransport.initial source) in
    success (JObject [("state",AudioTransport.state_json state);("actions",JArray actions)])
  else if String.eqb operation "control.audio.transport_step" then transport_step source
  else if String.eqb operation "control.audio.connection_initial" then
    success (JObject [("state",AudioConnection.state_json AudioConnection.initial);("actions",JArray [AudioConnection.primitive_json (AudioConnection.Connect 0)])])
  else if String.eqb operation "control.audio.connection_step" then connection_step source
  else if String.eqb operation "control.audio.stream_initial" then success (AudioState.stream_json (AudioState.stream_initial source))
  else if String.eqb operation "control.audio.stream_step" then stream_step source
  else if String.eqb operation "control.audio.session_initial" then success (AudioSession.state_json (AudioSession.initial source))
  else if String.eqb operation "control.audio.session_step" then session_step source
  else if String.eqb operation "control.audio.task_matches" then
    success (JBool (equal (AudioSession.task_id (AudioSession.state_of (get source "state"))) (get source "task_id")))
  else if String.eqb operation "control.audio.headers" then
    success (JObject [("OpenAI-Alpha",JString "quicksilver=v2");("Thread-Id",JString (decimal (num source "task_id")));("Session-Id",get source "id")])
  else if String.eqb operation "control.audio.owner" then
    let state := AudioSession.state_of (get source "state") in
    success (JObject [("owner",AudioSession.owner state);("exists",JBool (match AudioSession.phase state with AudioSession.Closed => false | _ => true end))])
  else failure "TypeError" ("Unknown audio control operation: " ++ operation).
