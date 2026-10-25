From Stdlib Require Import String List Bool NArith.
From Selvedge.Adapters Require Import Common Audio.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Inductive stream_phase := Connecting | Ready | Closed.
Record audio_state := AudioState {
  identity : json; generation : json; phase : stream_phase; sequence : N;
  user_tail : string; assistant_tail : string; turns : list json; pending : list json
}.
Inductive primitive := Emit (event : json) | CloseTransport | MarkReady.
Definition event_type (kind : string) := JObject [("type",JString kind)].
Definition stream_initial (source : json) := AudioState source (get source "generation") Connecting 0 "" "" [] [].
Definition stream_json (s : audio_state) := JObject [
  ("identity",identity s);("generation",generation s);
  ("phase",JString (match phase s with Connecting => "connecting" | Ready => "ready" | Closed => "closed" end));
  ("sequence",number (sequence s));("user_tail",JString (user_tail s));("assistant_tail",JString (assistant_tail s));
  ("turns",JArray (turns s));("pending",JArray (pending s))].
Definition stream_of (source : json) := AudioState (get source "identity") (get source "generation")
  (if String.eqb (str source "phase") "closed" then Closed else if String.eqb (str source "phase") "ready" then Ready else Connecting)
  (num source "sequence") (str source "user_tail") (str source "assistant_tail")
  (items (get source "turns")) (items (get source "pending")).
Definition primitive_json (s : audio_state) (effect : primitive) := match effect with
  | Emit event => JObject [("type",JString "emit");("event",set (set (set event "session_id" (get (identity s) "id"))
      "task_id" (get (identity s) "task_id")) "generation" (generation s))]
  | CloseTransport => event_type "close"
  | MarkReady => event_type "ready"
  end.
Definition tails (s : audio_state) (role text : string) := AudioState (identity s) (generation s) (phase s) (sequence s)
  (if String.eqb role "user" then text else user_tail s) (if String.eqb role "assistant" then text else assistant_tail s)
  (turns s) (pending s).
Definition with_pending (s : audio_state) (values : list json) := AudioState (identity s) (generation s) (phase s)
  (sequence s) (user_tail s) (assistant_tail s) (turns s) values.
Definition remember_turn (s : audio_state) (id : json) (text : string) := AudioState (identity s) (generation s) (phase s)
  (sequence s) (user_tail s) (assistant_tail s)
  (JObject [("turn_id",id);("text",JString text)] :: filter (fun turn => negb (equal (get turn "turn_id") id)) (turns s)) (pending s).
Definition ready (s : audio_state) : audio_state * list primitive := match phase s with
  | Connecting => (AudioState (identity s) (generation s) Ready (sequence s) (user_tail s) (assistant_tail s) (turns s) (pending s),
      [MarkReady; Emit (event_type "ready")])
  | _ => (s,[]) end.
Definition completed (s : audio_state) (event : json) (completion : string) : audio_state * primitive :=
  let next := sequence s + 1 in
  let item := if Audio.nonempty_text (get event "item_id") then get event "item_id"
    else JString (str (identity s) "id" ++ ":" ++ decimal next) in
  (AudioState (identity s) (generation s) (phase s) next (user_tail s) (assistant_tail s) (turns s) (pending s),
   Emit (set (set (set (set event "type" (JString "transcript")) "item_id" item) "completion" (JString completion)) "final" (JBool true))).
Definition stop (s : audio_state) (message : string) : audio_state * list primitive := match phase s with
  | Closed => (s,[])
  | _ =>
    let flush s role value := if String.eqb value "" then (s,[]) else
      let '(next,effect) := completed s (JObject [("role",JString role);("text",JString value);("remaining",JString "")]) "interrupted" in (next,[effect]) in
    let '(s1,user) := flush s "user" (user_tail s) in
    let '(s2,assistant) := flush s1 "assistant" (assistant_tail s) in
    let unresolved := map (fun raw => Emit (JObject [("type",JString "error");
      ("error",JString "Voice delegation is missing its referenced user turn");("item_id",get raw "id")])) (pending s) in
    let failure := if String.eqb message "" then [] else [Emit (JObject [("type",JString "error");("error",JString message)])] in
    let closed := Emit (JObject [("type",JString "closed");("reason",if String.eqb message "" then JString "stopped" else JString "error")]) in
    (AudioState (identity s) (generation s) Closed (sequence s2) "" "" [] [],
      CloseTransport :: List.concat [user;assistant;unresolved;failure;[closed]])
  end.
Fixpoint remember_pending (values : list json) (id raw : json) : list json :=
  let entry := JObject [("id",id);("raw",raw)] in
  match values with [] => [entry] | value :: rest =>
    if equal (get value "id") id then entry :: rest else value :: remember_pending rest id raw end.
Definition consume (s : audio_state) (raw event : json) : audio_state * list primitive :=
  let kind := str event "type" in
  if String.eqb kind "ready" then ready s
  else if String.eqb kind "delta" then
    let role := str event "role" in
    (tails s role ((if String.eqb role "user" then user_tail s else assistant_tail s) ++ str event "text"),[Emit event])
  else if String.eqb kind "transcript" then
    let role := str event "role" in
    let remaining := get (Audio.transcript_tail (JObject [("pending",JString (if String.eqb role "user" then user_tail s else assistant_tail s));("completed",get event "text")])) "value" in
    let next := tails s role (text remaining) in
    let next := if String.eqb role "user" && Audio.nonempty_text (get event "item_id")
      then remember_turn next (get event "item_id") (str event "text") else next in
    let '(next,effect) := completed next (set event "remaining" remaining) "completed" in (next,[effect])
  else if String.eqb kind "turn" then
    (tails (remember_turn s (get event "turn_id") (str event "text")) "user" (str event "text"),[])
  else if String.eqb kind "delegation_pending" then
    (with_pending s (remember_pending (pending s) (get event "item_id") raw),[])
  else if String.eqb kind "delegation" then
    (with_pending s (filter (fun value => negb (equal (get value "id") (get event "item_id"))) (pending s)),
     [Emit (set event "delegation_id" (get event "item_id"))])
  else if String.eqb kind "error" then stop s (str event "error") else (s,[]).
Fixpoint resolve_pending (values : list json) (s : audio_state) : audio_state * list primitive :=
  match values with [] => (s,[]) | entry :: rest =>
    let raw := get entry "raw" in
    let decoded := Audio.event (JObject [("value",raw);("turns",JArray (turns s))]) in
    let event := get decoded "value" in
    let '(next,effects) := if String.eqb (str event "type") "delegation" then consume s raw event else (s,[]) in
    let '(final,following) := resolve_pending rest next in (final,List.app effects following) end.
Inductive observation := Opened | ProviderEvent (raw : json) | StopRequested (message : string) | StartupTimeout (message : string).
Definition step (s : audio_state) (observed_generation : json) (observed : observation) : audio_state * list primitive :=
  if negb (equal (generation s) observed_generation) then (s,[]) else match phase s with Closed => (s,[]) | _ =>
    match observed with
    | Opened => ready s
    | StopRequested message => stop s message
    | StartupTimeout message => match phase s with Connecting => stop s message | _ => (s,[]) end
    | ProviderEvent raw =>
      let decoded := Audio.event (JObject [("value",raw);("turns",JArray (turns s))]) in
      if boolean_field decoded "ok" then
        let '(next,effects) := consume s raw (get decoded "value") in
        let '(final,following) := resolve_pending (pending next) next in (final,List.app effects following)
      else stop s (str decoded "error")
    end end.

Theorem closed_stream_is_inert : forall s generation observation,
  phase s = Closed -> step s generation observation = (s,[]).
Proof. intros s generation observation H. unfold step. destruct (negb _); auto. rewrite H. reflexivity. Qed.
Theorem stale_stream_is_inert : forall s observed_generation observation,
  equal (generation s) observed_generation = false -> step s observed_generation observation = (s,[]).
Proof. intros s observed_generation observation H. unfold step. rewrite H. reflexivity. Qed.
