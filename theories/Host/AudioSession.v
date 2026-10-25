From Selvedge.Foundation Require Import Schema.
From Selvedge.Kernel Require Import ModelDeclarations.
From Selvedge.Kernel Require Import ModelResultDeclarations.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Adapters Require Import Common.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Inductive session_phase := Connecting | Ready | Stopping | Closed.
Inductive progress_phase := Reading | Delivering (more idle : bool).
Record progress_operation := ProgressOperation {
  progress_token : N; issued_cursor : N; captured_delegations : list json; progress_stage : progress_phase
}.
Definition progress_json (p : progress_operation) := JObject [("token",number (progress_token p));
  ("after",number (issued_cursor p));("delegations",JArray (captured_delegations p));
  ("stage",JString (match progress_stage p with Reading => "reading" | _ => "delivering" end));
  ("more",JBool (match progress_stage p with Delivering more _ => more | _ => false end));
  ("idle",JBool (match progress_stage p with Delivering _ idle => idle | _ => false end))].
Definition progress_of source := ProgressOperation (num source "token") (num source "after") (items (get source "delegations"))
  (if String.eqb (str source "stage") "reading" then Reading else Delivering (boolean_field source "more") (boolean_field source "idle")).
Record session_state := SessionState {
  session_id : json; task_id : json; owner : json; generation : json;
  phase : session_phase; cursor : N; sequence : N; journal_pending : list json; delegations : list json; progress_pending : option progress_operation; progress_dirty : bool
}.
Inductive primitive := Publish (event : json) | CommitSpeech (token command : json)
  | AppendContext (context : json) | DeliverContexts (token : N) (contexts : list json) | ReadProgress (token cursor : N) | StopTransport | Release | ArmLifetime | ArmConnect | Reject (message : string).
Definition initial (source : json) := SessionState (get source "id") (get source "task_id") (get source "browser_id")
  (get source "generation") Connecting (num source "cursor") 0 [] [] None false.
Definition state_json (s : session_state) := JObject [("id",session_id s);("task_id",task_id s);("owner",owner s);
  ("generation",generation s);("phase",JString (match phase s with Connecting=>"connecting" | Ready=>"ready" | Stopping=>"stopping" | Closed=>"closed" end));
  ("cursor",number (cursor s));("sequence",number (sequence s));("pending",JArray (journal_pending s));("delegations",JArray (delegations s));("progress",match progress_pending s with None => JNull | Some p => progress_json p end);("dirty",JBool (progress_dirty s))].
Definition state_of (source : json) := SessionState (get source "id") (get source "task_id") (get source "owner") (get source "generation")
  (if String.eqb (str source "phase") "closed" then Closed else if String.eqb (str source "phase") "stopping" then Stopping
   else if String.eqb (str source "phase") "ready" then Ready else Connecting)
  (num source "cursor") (num source "sequence") (items (get source "pending")) (items (get source "delegations"))
  (if equal (get source "progress") JNull then None else Some (progress_of (get source "progress"))) (boolean_field source "dirty").
Definition primitive_json (s : session_state) (effect : primitive) := match effect with
 | Publish event => ModelDeclarations.encode ModelResultDeclarations.audio_emit (Schema.FCons (field:=Schema.Field "event" Schema.KJson) (set (set event "session_id" (session_id s)) "task_id" (task_id s)) Schema.FNil)
 | CommitSpeech token command => ModelDeclarations.encode ModelResultDeclarations.audio_journal (Schema.FCons (field:=Schema.Field "token" Schema.KJson) (token) (Schema.FCons (field:=Schema.Field "command" Schema.KJson) (command) Schema.FNil))
 | AppendContext context => ModelDeclarations.encode ModelResultDeclarations.audio_context (Schema.FCons (field:=Schema.Field "context" Schema.KJson) (context) Schema.FNil)
 | DeliverContexts token contexts => ModelDeclarations.encode ModelResultDeclarations.audio_contexts (Schema.FCons (field:=Schema.Field "token" Schema.KJson) (number token) (Schema.FCons (field:=Schema.Field "contexts" (Schema.KArray Schema.KJson)) contexts Schema.FNil))
 | ReadProgress token after => ModelDeclarations.encode ModelResultDeclarations.audio_read (Schema.FCons (field:=Schema.Field "token" Schema.KJson) (number token) (Schema.FCons (field:=Schema.Field "after" Schema.KNatural) (after) Schema.FNil))
 | StopTransport => ModelDeclarations.encode ModelResultDeclarations.audio_stop Schema.FNil
 | Release => ModelDeclarations.encode ModelResultDeclarations.audio_release Schema.FNil
 | ArmLifetime => ModelDeclarations.encode ModelResultDeclarations.audio_timer Schema.FNil
 | ArmConnect => ModelDeclarations.encode ModelResultDeclarations.audio_connect_timer Schema.FNil
 | Reject message => ModelDeclarations.encode ModelResultDeclarations.audio_reject (Schema.FCons (field:=Schema.Field "message" Schema.KText) (message) Schema.FNil)
 end.
Definition with_phase (s : session_state) (p : session_phase) := SessionState (session_id s) (task_id s) (owner s) (generation s)
  p (cursor s) (sequence s) (journal_pending s) (delegations s) (progress_pending s) (progress_dirty s).
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
    (JObject [("token",token);("event",event)] :: journal_pending s) (delegations s) (progress_pending s) (progress_dirty s),[CommitSpeech token (command s event)]).
Definition set_progress (s : session_state) (reservation : option progress_operation) (dirty : bool) (after serial : N) (ids : list json) :=
  SessionState (session_id s) (task_id s) (owner s) (generation s) (phase s) after serial (journal_pending s) ids reservation dirty.
Definition request_progress (s : session_state) : session_state * list primitive :=
  match phase s with Ready => match progress_pending s with
  | Some p => (set_progress s (Some p) true (cursor s) (sequence s) (delegations s),[])
  | None => let token := sequence s + 1 in
    (set_progress s (Some (ProgressOperation token (cursor s) (delegations s) Reading)) false (cursor s) token (delegations s),
      [ReadProgress token (cursor s)]) end
  | _ => (s,[]) end.
Definition observe_event (s : session_state) (event : json) : session_state * list primitive :=
  let kind := str event "type" in
  if String.eqb kind "ready" then match phase s with Connecting =>
    let '(next,reads) := request_progress (with_phase s Ready) in
    (next,List.app [ArmLifetime;Publish (event_type "ready")] reads) | _ => (s,[]) end
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
      (filter (fun entry => negb (equal (get entry "token") token)) (journal_pending s)) next_delegations (progress_pending s) (progress_dirty s) in
    let '(next,reads) := if negb transcript && accepted then request_progress next else (next,[]) in
    (next,if transcript then if accepted then [Publish event] else [Reject (str (get reply "error") "message")]
     else List.app [AppendContext (JObject [("delegation_item_id",get event "delegation_id");("channel",JString "commentary");
       ("text",JString (if accepted then "Task #" ++ decimal (nat_value (task_id s)) ++ " accepted the requested work."
         else "The work was rejected: " ++ str (get reply "error") "message"))])] reads)
  end.
Definition progress (s : session_state) (token : N) (page : json) (updates : list json) : session_state * list primitive :=
  match progress_pending s with Some p => match progress_stage p with Reading =>
  if N.eqb token (progress_token p) && N.eqb (num page "after") (issued_cursor p) then
  let contexts := flat_map (fun update => map (fun delegation => JObject [
    ("delegation_item_id",delegation);("channel",get update "channel");("text",JString ("Task #" ++ decimal (nat_value (task_id s)) ++
      " progress (accepted requests can be combined): " ++ str update "text"))])
      (match captured_delegations p with [] => [JNull] | values => values end)) updates in
  let next_cursor := num page "after" + N.of_nat (List.length (items (get page "messages"))) in
  let reservation := ProgressOperation token (issued_cursor p) (captured_delegations p)
    (Delivering (boolean_field page "has_more") (String.eqb (str (get page "task") "phase") "idle")) in
  (set_progress s (Some reservation) (progress_dirty s) next_cursor (sequence s) (delegations s),[DeliverContexts token contexts])
  else (s,[]) | _ => (s,[]) end | None => (s,[]) end.
Definition delivered (s : session_state) (token : N) : session_state * list primitive :=
  match progress_pending s with Some p => match progress_stage p with Delivering more idle =>
  if N.eqb token (progress_token p) then
    let ids := if negb more && idle then filter (fun id => negb (existsb (equal id) (captured_delegations p))) (delegations s) else delegations s in
    let next := set_progress s None false (cursor s) (sequence s) ids in
    if more || progress_dirty s then request_progress next else (next,[])
  else (s,[]) | _ => (s,[]) end | None => (s,[]) end.
Definition progress_failed (s : session_state) (token : N) (message : string) :=
  match progress_pending s with Some p => if N.eqb token (progress_token p) then
    let next := set_progress s None false (cursor s) (sequence s) (delegations s) in
    let '(next,actions) := if progress_dirty s then request_progress next else (next,[]) in
    (next,Publish (JObject [("type",JString "error");("message",JString message)]) :: actions) else (s,[])
  | None => (s,[]) end.
Inductive observation := Event (event : json) | JournalAck (token reply : json) | JournalFailed (message : string) | Stop | ProgressRequested
  | ProgressPage (token : N) (page : json) (updates : list json) | ProgressDelivered (token : N) | ProgressFailed (token : N) (message : string) | CreationFailed | InitialCursor (after : N) | Connected.
Definition step (s : session_state) (observed_generation : json) (observed : observation) : session_state * list primitive :=
  if negb (equal (generation s) observed_generation) then (s,[]) else match phase s with Closed => (s,[]) | _ =>
  match observed with
  | Event event => observe_event s event
  | JournalAck token reply => acknowledge s token reply
  | JournalFailed message => (with_phase s Closed,[Publish (JObject [("type",JString "error");("message",JString message)]);Release])
  | Stop => match phase s with Stopping => (s,[]) | _ => (with_phase s Stopping,[StopTransport]) end
  | ProgressRequested => request_progress s
  | ProgressFailed token message => match phase s with Ready => progress_failed s token message | _ => (s,[]) end
  | ProgressDelivered token => match phase s with Ready => delivered s token | _ => (s,[]) end
  | CreationFailed => (with_phase s Closed,[Release])
  | ProgressPage token page updates => match phase s with Ready => progress s token page updates | _ => (s,[]) end
  | Connected => match phase s with Connecting => (s,[ArmConnect]) | _ => (s,[]) end
  | InitialCursor after => (SessionState (session_id s) (task_id s) (owner s) (generation s) (phase s) after
      (sequence s) (journal_pending s) (delegations s) (progress_pending s) (progress_dirty s),[])
  end end.
Theorem stale_session_is_inert : forall s observed_generation observed,
  equal (generation s) observed_generation = false -> step s observed_generation observed = (s,[]).
Proof. intros s observed_generation observed H. unfold step. rewrite H. reflexivity. Qed.
Theorem closed_session_is_inert : forall s observed_generation observed,
  phase s = Closed -> step s observed_generation observed = (s,[]).
Proof. intros s observed_generation observed H. unfold step. destruct (negb _); auto. rewrite H. reflexivity. Qed.

Theorem pending_progress_does_not_issue_another_read : forall s p,
  phase s = Ready -> progress_pending s = Some p -> snd (request_progress s) = [].
Proof. intros s p Hphase Hpending. unfold request_progress. rewrite Hphase,Hpending. reflexivity. Qed.

Theorem delivering_progress_does_not_deliver_a_page_twice : forall s p token page updates more idle,
  progress_pending s = Some p -> progress_stage p = Delivering more idle ->
  progress s token page updates = (s,[]).
Proof. intros s p token page updates more idle Hpending Hstage. unfold progress. rewrite Hpending,Hstage. reflexivity. Qed.
