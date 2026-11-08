From Stdlib Require Import String List Bool NArith.
From Selvedge.Adapters Require Import Common Audio.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Inductive stream_phase := Connecting | Ready | Closed.
Record audio_state := AudioState {
  identity : json; phase : stream_phase; sequence : N;
  user_tail : string; assistant_tail : string; turns : list json; pending : list Audio.delegation_reference
}.
Inductive primitive := Emit (event : json) | MarkReady.
Definition event_type (kind : string) := JObject [("type",JString kind)].
Definition stream_initial (source : json) := AudioState source Connecting 0 "" "" [] [].
Definition reference_json (value : Audio.delegation_reference) :=
 JObject [("id",JString value.(Audio.delegation_id));("turn_id",JString value.(Audio.delegation_turn))].
Definition reference_of value := Audio.DelegationReference (str value "id") (str value "turn_id").
Definition stream_json (s : audio_state) := JObject [
  ("identity",identity s);
  ("phase",JString (match phase s with Connecting => "connecting" | Ready => "ready" | Closed => "closed" end));
  ("sequence",number (sequence s));("user_tail",JString (user_tail s));("assistant_tail",JString (assistant_tail s));
  ("turns",JArray (turns s));("pending",JArray (map reference_json (pending s)))].
Definition stream_of (source : json) := AudioState (get source "identity")
  (if String.eqb (str source "phase") "closed" then Closed else if String.eqb (str source "phase") "ready" then Ready else Connecting)
  (num source "sequence") (str source "user_tail") (str source "assistant_tail")
  (items (get source "turns")) (map reference_of (items (get source "pending"))).
Definition event_json (s : audio_state) event :=
  set (set (set event "session_id" (get (identity s) "id"))
    "task_id" (get (identity s) "task_id")) "generation" (get (identity s) "generation").
Definition tails (s : audio_state) (role text : string) := AudioState (identity s) (phase s) (sequence s)
  (if String.eqb role "user" then text else user_tail s) (if String.eqb role "assistant" then text else assistant_tail s)
  (turns s) (pending s).
Definition with_pending (s : audio_state) (values : list Audio.delegation_reference) := AudioState (identity s) (phase s)
  (sequence s) (user_tail s) (assistant_tail s) (turns s) values.
Definition remember_turn (s : audio_state) (id : json) (text : string) := AudioState (identity s) (phase s)
  (sequence s) (user_tail s) (assistant_tail s)
  (JObject [("turn_id",id);("text",JString text)] :: filter (fun turn => negb (equal (get turn "turn_id") id)) (turns s)) (pending s).
Definition ready (s : audio_state) : audio_state * list primitive := match phase s with
  | Connecting => (AudioState (identity s) Ready (sequence s) (user_tail s) (assistant_tail s) (turns s) (pending s),
      [MarkReady; Emit (event_type "ready")])
  | _ => (s,[]) end.
Definition completed (s : audio_state) (event : json) (completion : string) : audio_state * primitive :=
  let next := sequence s + 1 in
  let item := if Audio.nonempty_text (get event "item_id") then get event "item_id"
    else JString (str (identity s) "id" ++ ":" ++ decimal next) in
  (AudioState (identity s) (phase s) next (user_tail s) (assistant_tail s) (turns s) (pending s),
   Emit (set (set (set (set event "type" (JString "transcript")) "item_id" item) "completion" (JString completion)) "final" (JBool true))).
Definition stop (s : audio_state) (message : string) : audio_state * list primitive := match phase s with
  | Closed => (s,[])
  | _ =>
    let flush s role value := if String.eqb value "" then (s,[]) else
      let '(next,effect) := completed s (JObject [("role",JString role);("text",JString value);("remaining",JString "")]) "interrupted" in (next,[effect]) in
    let '(s1,user) := flush s "user" (user_tail s) in
    let '(s2,assistant) := flush s1 "assistant" (assistant_tail s) in
    let unresolved := map (fun reference => Emit (JObject [("type",JString "error");
      ("error",JString "Voice delegation is missing its referenced user turn");("item_id",JString reference.(Audio.delegation_id))])) (pending s) in
    let failure := if String.eqb message "" then [] else [Emit (JObject [("type",JString "error");("error",JString message)])] in
    let closed := Emit (JObject [("type",JString "closed");("reason",if String.eqb message "" then JString "stopped" else JString "error")]) in
    (AudioState (identity s) Closed (sequence s2) "" "" [] [],
      List.concat [user;assistant;unresolved;failure;[closed]])
  end.
Fixpoint remember_pending (values : list Audio.delegation_reference) (reference : Audio.delegation_reference) :=
  match values with [] => [reference] | value :: rest =>
    if String.eqb value.(Audio.delegation_id) reference.(Audio.delegation_id)
    then reference :: rest else value :: remember_pending rest reference end.
Definition delegation_emission id turn message := Emit (JObject [
  ("type",JString "delegation");("item_id",JString id);("text",JString message);
  ("turn_id",turn);("delegation_id",JString id)]).
Definition turn_text (s : audio_state) (id : string) :=
  match find (fun turn => equal (get turn "turn_id") (JString id)) (turns s) with
  | Some turn => str turn "text" | None => "" end.
Definition emit_delegation s id turn message :=
  (with_pending s (filter (fun value => negb (String.eqb value.(Audio.delegation_id) id)) (pending s)),
   [delegation_emission id turn message]).
Definition accept_delegation s item :=
  match item with
  | Audio.TextDelegation id turn message => emit_delegation s id turn message
  | Audio.ReferencedDelegation reference =>
    let turn := reference.(Audio.delegation_turn) in
    let message := turn_text s turn in
    if String.eqb message "" then (with_pending s (remember_pending (pending s) reference),[])
    else emit_delegation s reference.(Audio.delegation_id) (JString turn) message end.
Definition resolve_turn s id message :=
  let '(resolved,waiting) := partition (fun reference => String.eqb reference.(Audio.delegation_turn) id) (pending s) in
  (with_pending s waiting, map (fun reference => delegation_emission reference.(Audio.delegation_id) (JString id) message) resolved).
Definition consume (s : audio_state) (event : json) : audio_state * list primitive :=
  let kind := str event "type" in
  if String.eqb kind "ready" then ready s
  else if String.eqb kind "delta" then
    let role := str event "role" in
    (tails s role ((if String.eqb role "user" then user_tail s else assistant_tail s) ++ str event "text"),[Emit event])
  else if String.eqb kind "transcript" then
    let role := str event "role" in
    let message := str event "text" in
    let remaining := Audio.transcript_tail (if String.eqb role "user" then user_tail s else assistant_tail s) message in
    let '(next,effect) := completed (tails s role remaining) (set event "remaining" (JString remaining)) "completed" in
    if String.eqb role "user" && Audio.nonempty_text (get event "item_id") then
      let id := get event "item_id" in
      let '(final,following) := resolve_turn (remember_turn next id message) (text id) message in
      (final,effect :: following)
    else (next,[effect])
  else if String.eqb kind "turn" then
    let id := get event "turn_id" in let message := str event "text" in
    resolve_turn (tails (remember_turn s id message) "user" message) (text id) message
  else if String.eqb kind "error" then stop s (str event "error") else (s,[]).
Inductive observation := Opened | ProviderEvent (raw : json) | StopRequested (message : string) | StartupTimeout (message : string).
Definition step (s : audio_state) (observed : observation) : audio_state * list primitive :=
  match phase s with Closed => (s,[]) | _ =>
    match observed with
    | Opened => ready s
    | StopRequested message => stop s message
    | StartupTimeout message => match phase s with Connecting => stop s message | _ => (s,[]) end
    | ProviderEvent raw =>
      match Audio.event raw with
      | inl message => stop s message
      | inr (Audio.ControlEvent event) => consume s event
      | inr (Audio.DelegationEvent item) => accept_delegation s item end
    end end.

Theorem closed_stream_is_inert : forall s observation,
  phase s = Closed -> step s observation = (s,[]).
Proof. intros s observation H. unfold step. rewrite H. reflexivity. Qed.
