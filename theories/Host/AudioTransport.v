From Stdlib Require Import String List Bool NArith.
From Selvedge.Adapters Require Import Common.
From Selvedge.Foundation Require Import Schema.
From Selvedge.Kernel Require Import ModelDeclarations ModelResultDeclarations.
From Selvedge.Host Require Import AudioConnection AudioState.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

(* Arrival admission and emission settlement have separate clocks: an accepted
   provider prefix is folded immediately even while its journal commit waits. *)
Inductive transport_phase := Live | Draining | Retired | Closed.
Inductive primitive := Connect (attempt : N) | Retry (attempt delay : N)
  | Ready | Emit (event : json) | Close (event : json).
Record transport_state := TransportState {
  connection : AudioConnection.connection_state;
  stream : AudioState.audio_state;
  phase : transport_phase;
  waiting : list primitive;
  active : option (N * primitive);
  serial : N
}.
Definition primitive_json effect := match effect with
  | Connect attempt => ModelDeclarations.encode ModelResultDeclarations.audio_transport_connect
      (Schema.FCons (field:=Schema.Field "attempt" Schema.KNatural) attempt Schema.FNil)
  | Retry attempt delay => ModelDeclarations.encode ModelResultDeclarations.audio_transport_retry
      (Schema.FCons (field:=Schema.Field "attempt" Schema.KNatural) attempt
        (Schema.FCons (field:=Schema.Field "delay" Schema.KNatural) delay Schema.FNil))
  | Ready => ModelDeclarations.encode ModelResultDeclarations.audio_transport_ready Schema.FNil
  | Emit event => ModelDeclarations.encode ModelResultDeclarations.audio_transport_emit
      (Schema.FCons (field:=Schema.Field "event" Schema.KJson) event Schema.FNil)
  | Close event => ModelDeclarations.encode ModelResultDeclarations.audio_transport_close
      (Schema.FCons (field:=Schema.Field "event" Schema.KJson) event Schema.FNil) end.
Definition primitive_of source := let kind := str source "type" in
  if String.eqb kind "connect" then Connect (num source "attempt")
  else if String.eqb kind "retry" then Retry (num source "attempt") (num source "delay")
  else if String.eqb kind "ready" then Ready
  else if String.eqb kind "close" then Close (get source "event") else Emit (get source "event").
Definition state_json s := JObject [("connection",AudioConnection.state_json (connection s));
  ("stream",AudioState.stream_json (stream s));("phase",JString (match phase s with Live=>"live" | Draining=>"draining" | Retired=>"retired" | Closed=>"closed" end));
  ("waiting",JArray (map primitive_json (waiting s)));("active",match active s with None=>JNull | Some (token,effect)=>JObject [("token",number token);("effect",primitive_json effect)] end);
  ("serial",number (serial s))].
Definition state_of source := TransportState (AudioConnection.state_of (get source "connection"))
  (AudioState.stream_of (get source "stream"))
  (if String.eqb (str source "phase") "closed" then Closed else if String.eqb (str source "phase") "retired" then Retired
    else if String.eqb (str source "phase") "draining" then Draining else Live)
  (map primitive_of (items (get source "waiting")))
  (if equal (get source "active") JNull then None else Some (num (get source "active") "token",primitive_of (get (get source "active") "effect")))
  (num source "serial").
Definition initial source := TransportState AudioConnection.initial (AudioState.stream_initial source) Live [Connect 0] None 0.
Definition begin (s : transport_state) : transport_state * list json :=
  match active s, waiting s with
  | None, effect::rest => let token := serial s + 1 in
    (TransportState (connection s) (stream s) (phase s) rest (Some (token,effect)) token,
      [JObject [("token",number token);("effect",primitive_json effect)]])
  | _,_ => (s,[]) end.
Definition stream_effects s effects :=
  let ordinary := flat_map (fun effect => match effect with
    | AudioState.MarkReady => [Ready]
    | AudioState.Emit event => if String.eqb (str event "type") "closed" then []
      else [Emit (get (AudioState.primitive_json s effect) "event")]
    | AudioState.CloseTransport => [] end) effects in
  let closes := flat_map (fun effect => match effect with
    | AudioState.Emit event => if String.eqb (str event "type") "closed" then let event := get (AudioState.primitive_json s effect) "event" in [Close event;Emit event] else []
    | _ => [] end) effects in List.app ordinary closes.
Definition fold_stream (s : transport_state) observation :=
  let '(next,effects) := AudioState.step (stream s) (AudioState.generation (stream s)) observation in
  let ended := match AudioState.phase next with AudioState.Closed => true | _ => false end in
  let c := if ended then fst (AudioConnection.step (connection s) AudioConnection.Stop) else connection s in
  TransportState c next (if ended then Draining else phase s) (List.app (waiting s) (stream_effects next effects)) (active s) (serial s).
Fixpoint fold_connection (s : transport_state) (effects : list AudioConnection.primitive) : transport_state :=
  match effects with [] => s | effect::rest =>
  let next := match effect with
    | AudioConnection.Connect attempt => TransportState (connection s) (stream s) (phase s) (List.app (waiting s) [Connect attempt]) (active s) (serial s)
    | AudioConnection.ScheduleRetry attempt delay => TransportState (connection s) (stream s) (phase s) (List.app (waiting s) [Retry attempt delay]) (active s) (serial s)
    | AudioConnection.OpenStream => fold_stream s AudioState.Opened
    | AudioConnection.StopStream message => fold_stream s (AudioState.StopRequested message)
    | AudioConnection.Deliver raw => fold_stream s (AudioState.ProviderEvent raw) end in
  fold_connection next rest end.
Inductive observation := Arrival (observed : AudioConnection.observation)
  | GracefulStop (message : string) | StartupTimeout (message : string)
  | EmitAck (token : N) | EmitFailed (token : N).
Definition retire (s : transport_state) :=
  let '(next,_) := AudioState.stop (stream s) "" in
  let event := get (AudioState.primitive_json next (AudioState.Emit (JObject [("type",JString "closed");("reason",JString "error")]))) "event" in
  TransportState (fst (AudioConnection.step (connection s) AudioConnection.Stop)) next Retired [Close event;Emit event] None (serial s).
Definition step (s : transport_state) observation : transport_state * list json :=
  match observation with
  | EmitAck token => match active s with Some (issued,effect) =>
      if N.eqb token issued then
        let p := match waiting s, phase s with [],Draining | [],Retired => Closed | _,p => p end in
        begin (TransportState (connection s) (stream s) p (waiting s) None (serial s))
      else (s,[]) | None => (s,[]) end
  | EmitFailed token => match active s with Some (issued,effect) =>
      if N.eqb token issued then match effect with
      | Emit event => if String.eqb (str event "type") "closed" then
          (TransportState (connection s) (stream s) Closed [] None (serial s),[]) else begin (retire s)
      | Close _ => begin (TransportState (connection s) (stream s) Retired (waiting s) None (serial s))
      | _ => begin (retire s) end else (s,[]) | None => (s,[]) end
  | _ => match phase s with Live =>
      let next := match observation with
      | Arrival observed => let '(c,effects) := AudioConnection.step (connection s) observed in
          fold_connection (TransportState c (stream s) Live (waiting s) (active s) (serial s)) effects
      | GracefulStop message => fold_stream s (AudioState.StopRequested message)
      | StartupTimeout message => fold_stream s (AudioState.StartupTimeout message)
      | _ => s end in begin next
    | _ => (s,[]) end end.

Theorem stale_ack_is_inert : forall s token issued effect,
  active s = Some (issued,effect) -> N.eqb token issued = false -> step s (EmitAck token) = (s,[]).
Proof. intros s token issued effect H E. cbn [step]. rewrite H,E. reflexivity. Qed.
Theorem begin_has_one_owner : forall s next actions token effect,
  begin s = (next,actions) -> active s = Some (token,effect) -> next = s /\ actions = [].
Proof. intros s next actions token effect H E. unfold begin in H. rewrite E in H. injection H. auto. Qed.

Theorem closed_stream_ends_its_connection_in_the_same_step : forall s observed next effects,
  AudioState.step (stream s) (AudioState.generation (stream s)) observed = (next,effects) ->
  AudioState.phase next = AudioState.Closed ->
  AudioConnection.phase (connection (fold_stream s observed)) = AudioConnection.Ended.
Proof.
  intros s observed next effects Hstep Hclosed.
  unfold fold_stream. rewrite Hstep,Hclosed. reflexivity.
Qed.

Theorem draining_transport_rejects_new_arrivals : forall s observed,
  phase s = Draining -> step s (Arrival observed) = (s,[]).
Proof. intros s observed H. cbn [step]. rewrite H. reflexivity. Qed.
