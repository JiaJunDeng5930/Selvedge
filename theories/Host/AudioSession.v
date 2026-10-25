From Selvedge.Foundation Require Import Schema.
From Selvedge.Kernel Require Import ModelDeclarations.
From Selvedge.Kernel Require Import ModelResultDeclarations.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Adapters Require Import Common.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Inductive session_phase := Connecting | Ready | Stopping | Closed.
Record session_state := SessionState {
  session_id : json; task_id : json; owner : json; generation : json;
  phase : session_phase; cursor : N; sequence : N; journal_pending : list json; delegations : list json
}.
Inductive primitive := Publish (event : json) | CommitSpeech (token command : json)
  | AppendContext (context : json) | ReadProgress (cursor : N) | StopTransport | Release | ArmLifetime | ArmConnect | Reject (message : string).
Definition initial (source : json) := SessionState (get source "id") (get source "task_id") (get source "browser_id")
  (get source "generation") Connecting (num source "cursor") 0 [] [].
Definition state_json (s : session_state) := JObject [("id",session_id s);("task_id",task_id s);("owner",owner s);
  ("generation",generation s);("phase",JString (match phase s with Connecting=>"connecting" | Ready=>"ready" | Stopping=>"stopping" | Closed=>"closed" end));
  ("cursor",number (cursor s));("sequence",number (sequence s));("pending",JArray (journal_pending s));("delegations",JArray (delegations s))].
Definition state_of (source : json) := SessionState (get source "id") (get source "task_id") (get source "owner") (get source "generation")
  (if String.eqb (str source "phase") "closed" then Closed else if String.eqb (str source "phase") "stopping" then Stopping
   else if String.eqb (str source "phase") "ready" then Ready else Connecting)
  (num source "cursor") (num source "sequence") (items (get source "pending")) (items (get source "delegations")).
Definition primitive_json (s : session_state) (effect : primitive) := match effect with
 | Publish event => ModelDeclarations.encode ModelResultDeclarations.audio_emit (Schema.FCons (field:=Schema.Field "event" Schema.KJson) (set (set event "session_id" (session_id s)) "task_id" (task_id s)) Schema.FNil)
 | CommitSpeech token command => ModelDeclarations.encode ModelResultDeclarations.audio_journal (Schema.FCons (field:=Schema.Field "token" Schema.KJson) (token) (Schema.FCons (field:=Schema.Field "command" Schema.KJson) (command) Schema.FNil))
 | AppendContext context => ModelDeclarations.encode ModelResultDeclarations.audio_context (Schema.FCons (field:=Schema.Field "context" Schema.KJson) (context) Schema.FNil)
 | ReadProgress after => ModelDeclarations.encode ModelResultDeclarations.audio_read (Schema.FCons (field:=Schema.Field "after" Schema.KNatural) (after) Schema.FNil)
 | StopTransport => ModelDeclarations.encode ModelResultDeclarations.audio_stop Schema.FNil
 | Release => ModelDeclarations.encode ModelResultDeclarations.audio_release Schema.FNil
 | ArmLifetime => ModelDeclarations.encode ModelResultDeclarations.audio_timer Schema.FNil
 | ArmConnect => ModelDeclarations.encode ModelResultDeclarations.audio_connect_timer Schema.FNil
 | Reject message => ModelDeclarations.encode ModelResultDeclarations.audio_reject (Schema.FCons (field:=Schema.Field "message" Schema.KText) (message) Schema.FNil)
 end.
Definition with_phase (s : session_state) (p : session_phase) := SessionState (session_id s) (task_id s) (owner s) (generation s)
  p (cursor s) (sequence s) (journal_pending s) (delegations s).
Definition event_type kind := JObject [("type",JString kind)].
Definition command (s : session_state) (event : json) :=
  let transcript := String.eqb (str event "type") "transcript" in
  JObject (List.app [("op",JString (if transcript then "record_speech_transcript" else "accept_speech_delegation"));
    ("task_id",task_id s);("session_id",session_id s)] (
    if transcript then [("item_id",get event "item_id");("speaker",get event "role");("text",get event "text");
      ("completion",if has event "completion" then get event "completion" else JString "completed")]
    else [("delegation_id",get event "delegation_id");("message",get event "text");
      ("mode",if has event "mode" then get event "mode" else JString "send")])).
Definition commit (s : session_state) (event : json) :=
  let token := number (sequence s + 1) in
  (SessionState (session_id s) (task_id s) (owner s) (generation s) (phase s) (cursor s) (sequence s + 1)
    (JObject [("token",token);("event",event)] :: journal_pending s) (delegations s),[CommitSpeech token (command s event)]).
Definition observe_event (s : session_state) (event : json) : session_state * list primitive :=
  let kind := str event "type" in
  if String.eqb kind "ready" then match phase s with Connecting =>
    (with_phase s Ready,[ArmLifetime;Publish (event_type "ready");ReadProgress (cursor s)]) | _ => (s,[]) end
  else if (String.eqb kind "transcript" && boolean_field event "final") || String.eqb kind "delegation" then commit s event
  else if String.eqb kind "delta" then (s,[Publish (set (set event "type" (JString "transcript")) "final" (JBool false))])
  else if String.eqb kind "error" then (s,[Publish (set event "message" (if has event "error" then get event "error" else get event "message"))])
  else if existsb (String.eqb kind) ["closed";"stopped"] then
    (with_phase s Closed,[Publish (set event "type" (JString "stopped"));Release]) else (s,[]).
Definition acknowledge (s : session_state) (token reply : json) : session_state * list primitive :=
  match find (fun entry => equal (get entry "token") token) (journal_pending s) with
  | None => (s,[])
  | Some entry =>
    let event := get entry "event" in let accepted := boolean_field reply "ok" in
    let transcript := String.eqb (str event "type") "transcript" in
    let id := get event "delegation_id" in
    let next_delegations := if negb transcript && accepted && negb (existsb (equal id) (delegations s))
      then List.app (delegations s) [id] else delegations s in
    let next := SessionState (session_id s) (task_id s) (owner s) (generation s) (phase s) (cursor s) (sequence s)
      (filter (fun entry => negb (equal (get entry "token") token)) (journal_pending s)) next_delegations in
    (next,if transcript then if accepted then [Publish event] else [Reject (str (get reply "error") "message")]
     else List.app [AppendContext (JObject [("delegation_item_id",get event "delegation_id");("channel",JString "commentary");
       ("text",JString (if accepted then "Task #" ++ decimal (nat_value (task_id s)) ++ " accepted the requested work."
         else "The work was rejected: " ++ str (get reply "error") "message"))])] (if accepted then [ReadProgress (cursor next)] else []))
  end.
Definition progress (s : session_state) (page : json) (updates : list json) : session_state * list primitive :=
  let contexts := flat_map (fun update => map (fun delegation => AppendContext (JObject [
    ("delegation_item_id",delegation);("channel",get update "channel");("text",JString ("Task #" ++ decimal (nat_value (task_id s)) ++
      " progress (accepted requests can be combined): " ++ str update "text"))]))
      (match delegations s with [] => [JNull] | values => values end)) updates in
  let next_cursor := num page "after" + N.of_nat (List.length (items (get page "messages"))) in
  let more := boolean_field page "has_more" in
  let next := SessionState (session_id s) (task_id s) (owner s) (generation s) (phase s) next_cursor (sequence s) (journal_pending s)
    (if negb more && String.eqb (str (get page "task") "phase") "idle" then [] else delegations s) in
  (next,List.app contexts (if more then [ReadProgress next_cursor] else [])).
Inductive observation := Event (event : json) | JournalAck (token reply : json) | JournalFailed (message : string) | Stop | ProgressRequested
  | ProgressPage (page : json) (updates : list json) | ProgressFailed (message : string) | CreationFailed | InitialCursor (after : N) | Connected.
Definition step (s : session_state) (observed_generation : json) (observed : observation) : session_state * list primitive :=
  if negb (equal (generation s) observed_generation) then (s,[]) else match phase s with Closed => (s,[]) | _ =>
  match observed with
  | Event event => observe_event s event
  | JournalAck token reply => acknowledge s token reply
  | JournalFailed message => (with_phase s Closed,[Publish (JObject [("type",JString "error");("message",JString message)]);Release])
  | Stop => match phase s with Stopping => (s,[]) | _ => (with_phase s Stopping,[StopTransport]) end
  | ProgressRequested => match phase s with Ready => (s,[ReadProgress (cursor s)]) | _ => (s,[]) end
  | ProgressFailed message => (s,[Publish (JObject [("type",JString "error");("message",JString message)])])
  | CreationFailed => (with_phase s Closed,[Release])
  | ProgressPage page updates => match phase s with Ready => progress s page updates | _ => (s,[]) end
  | Connected => match phase s with Connecting => (s,[ArmConnect]) | _ => (s,[]) end
  | InitialCursor after => (SessionState (session_id s) (task_id s) (owner s) (generation s) (phase s) after
      (sequence s) (journal_pending s) (delegations s),[])
  end end.
Theorem stale_session_is_inert : forall s observed_generation observed,
  equal (generation s) observed_generation = false -> step s observed_generation observed = (s,[]).
Proof. intros s observed_generation observed H. unfold step. rewrite H. reflexivity. Qed.
Theorem closed_session_is_inert : forall s observed_generation observed,
  phase s = Closed -> step s observed_generation observed = (s,[]).
Proof. intros s observed_generation observed H. unfold step. destruct (negb _); auto. rewrite H. reflexivity. Qed.
