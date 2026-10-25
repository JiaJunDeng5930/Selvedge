From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json RemoteIdentity.
From Selvedge.Host Require Import RemoteProtocol.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition grant := authorization.
Definition Grant := Authorization.
Definition controller := authorization_controller.
Definition epoch := authorization_epoch.
Record connection := Connection { connection_id : string; authority : grant }.
Record pairing := Pairing { code : string; expires : N }.
Record queued := Queued { owner : string; bytes : N }.
Record session := Session { pairing_code : option pairing; grants : list grant;
 connections : list connection; pending : list queued }.
Inductive state := Offline (generation : N) (pairing : option pairing)
 | Negotiating (generation : N) (pairing : option pairing)
 | Ready (generation : N) (data : session).
Definition initial := Offline 0 None.
Definition generation s := match s with Offline n _ | Negotiating n _ | Ready n _ => n end.
Definition pairing_of s := match s with Offline _ p | Negotiating _ p => p | Ready _ data => pairing_code data end.
Definition set_pairing s pairing_value := match s with Offline n _ => Offline n pairing_value | Negotiating n _ => Negotiating n pairing_value
 | Ready n data => Ready n (Session pairing_value (grants data) (connections data) (pending data)) end.
Definition same_grant left right := String.eqb (controller left) (controller right) && N.eqb (epoch left) (epoch right).
Definition permitted values value := existsb (fun other => same_grant other value) values.
Definition find_connection data id := find (fun entry => String.eqb (connection_id entry) id) (connections data).
Definition forget values id := filter (fun entry => negb (String.eqb (connection_id entry) id)) values.
Definition queued_for data id := N.of_nat (List.length (filter (fun job => String.eqb (owner job) id) (pending data))).
Definition queued_bytes data := fold_left (fun total job => total + bytes job) (pending data) 0.
Fixpoint complete values id size := match values with [] => [] | job::rest =>
 if String.eqb (owner job) id && N.eqb (bytes job) size then rest else job::complete rest id size end.
Inductive frame := RelayReady | ControllerOpen (entry : connection) | ControllerClose (id : string)
 | Request (id : string) (authority : grant) | PairRequest | Pong.
Inductive observation := Retire | SetPairing (value : pairing) (now : N) | CurrentPairing (now : N)
 | Grants (values : list grant) | Enqueue (id : string) (size : N) | Dequeue (id : string) (size : N)
 | Frame (value : frame).
Inductive event := Install (generation : N) | Observe (generation : N) (value : observation).
Inductive action := Ignore | Installed | Retired | PublishPairing | PendingPairing | PairingExpired
 | GrantsUpdated | Enqueued | Dequeued | Disconnect | BecameReady | Opened | Closed | Requested | PairRequested | ReceivedPong.
Definition step s event : state * action := match event with
 | Install n => (Negotiating n (pairing_of s),Installed)
 | Observe n value => if negb (N.eqb (generation s) n) then (s,Ignore) else
   match value with
   | Retire => (Offline n None,Retired)
   | SetPairing pairing_value now => (set_pairing s (Some pairing_value),
     match s with Ready _ _ => if now <? expires pairing_value then PublishPairing else PendingPairing | _ => PendingPairing end)
   | CurrentPairing now => match pairing_of s with
     Some pairing_value => if now <? expires pairing_value then (s,PublishPairing) else (set_pairing s None,PairingExpired)
     | None => (s,PairingExpired) end
   | _ => match s with
     | Offline _ _ => (s,Ignore)
     | Negotiating g pairing_value => match value with Frame RelayReady => (Ready g (Session pairing_value [] [] []),BecameReady)
       | Frame _ => (s,Disconnect) | _ => (s,Ignore) end
     | Ready g data => match value with
       | Grants values => (Ready g (Session (pairing_code data) values
         (filter (fun entry => permitted values (authority entry)) (connections data)) (pending data)),GrantsUpdated)
       | Enqueue id size => match find_connection data id with None => (s,Ignore) | Some _ =>
         if (queued_for data id <? 32) && (N.of_nat (List.length (pending data)) <? 256) &&
           (queued_bytes data + size <=? 33554432) then
           (Ready g (Session (pairing_code data) (grants data) (connections data) (Queued id size::pending data)),Enqueued)
         else (s,Disconnect) end
       | Dequeue id size => (Ready g (Session (pairing_code data) (grants data) (connections data)
         (complete (pending data) id size)),Dequeued)
       | Frame RelayReady => (s,Disconnect)
       | Frame (ControllerOpen entry) => match find_connection data (connection_id entry) with Some _ => (s,Disconnect) | None =>
         if N.of_nat (List.length (connections data)) <? 32 then
           (Ready g (Session (pairing_code data) (grants data) (entry::connections data) (pending data)),Opened)
         else (s,Disconnect) end
       | Frame (ControllerClose id) => (Ready g (Session (pairing_code data) (grants data)
         (forget (connections data) id) (pending data)),Closed)
       | Frame (Request id requested) => match find_connection data id with
         Some entry => (s,if same_grant (authority entry) requested then Requested else Disconnect)
         | None => (s,Disconnect) end
       | Frame PairRequest => (set_pairing s None,PairRequested)
       | Frame Pong => (s,ReceivedPong)
       | _ => (s,Ignore) end end end end.

Definition grant_json entry := JObject [("controller_id",JString (controller entry));("grant_epoch",number (epoch entry))].
Definition grant_of value := Grant (ControllerId (str value "controller_id")) (GrantEpoch (num value "grant_epoch")).
Definition connection_json entry := JObject [("connection_id",JString (connection_id entry));
 ("controller_id",JString (controller (authority entry)));("grant_epoch",number (epoch (authority entry)))].
Definition connection_of value := Connection (str value "connection_id") (grant_of value).
Definition pairing_json value := match value with None => JNull | Some pairing_value => JObject
 [("type",JString "pairing");("code",JString (code pairing_value));("expires_at",number (expires pairing_value))] end.
Definition pairing_decode value := match value with JObject _ => Some (Pairing (str value "code") (num value "expires_at")) | _ => None end.
Definition queued_json value := JObject [("connection_id",JString (owner value));("bytes",number (bytes value))].
Definition state_json s := JObject ([("generation",number (generation s));("pairing",pairing_json (pairing_of s))] ++
 match s with Offline _ _ => [("phase",JString "offline")]
 | Negotiating _ _ => [("phase",JString "negotiating")]
 | Ready _ data => [("phase",JString "ready");("grants",JArray (map grant_json (grants data)));
   ("connections",JArray (map connection_json (connections data)));("pending",JArray (map queued_json (pending data)))] end).
Definition state_of source :=
 let n := num source "generation" in let pairing_value := pairing_decode (get source "pairing") in
 match str source "phase" with
 | "offline" => Some (Offline n pairing_value) | "negotiating" => Some (Negotiating n pairing_value)
 | "ready" => Some (Ready n (Session pairing_value (map grant_of (items (get source "grants")))
     (map connection_of (items (get source "connections")))
     (map (fun value => Queued (str value "connection_id") (num value "bytes")) (items (get source "pending")))))
 | _ => None end.
Definition frame_of source := match str source "type" with
 | "ready" => Some RelayReady | "controller_open" => Some (ControllerOpen (connection_of source))
 | "controller_close" => Some (ControllerClose (str source "connection_id"))
 | "request" => Some (Request (str source "connection_id") (grant_of source))
 | "pair_request" => Some PairRequest | "pong" => Some Pong | _ => None end.
Definition event_of source :=
 let n := num source "generation" in
 if String.eqb (str source "kind") "install" then Some (Install n) else
 option_map (Observe n) (match str source "kind" with
 | "retire" => Some Retire | "pair" => option_map (fun pairing_value => SetPairing pairing_value (num source "now")) (pairing_decode (get source "frame"))
 | "pairing_current" => Some (CurrentPairing (num source "now"))
 | "grants" => Some (Grants (map grant_of (items (get source "grants"))))
 | "enqueue" => Some (Enqueue (str source "connection_id") (num source "bytes"))
 | "dequeue" => Some (Dequeue (str source "connection_id") (num source "bytes"))
 | "frame" => option_map Frame (frame_of (get source "frame")) | _ => None end).
Definition action_text value := match value with Ignore => "ignore" | Installed => "installed" | Retired => "retire"
 | PublishPairing => "pairing" | PendingPairing => "pending" | PairingExpired => "expired" | GrantsUpdated => "grants"
 | Enqueued => "enqueue" | Dequeued => "dequeue" | Disconnect => "disconnect" | BecameReady => "ready"
 | Opened => "controller_open" | Closed => "controller_close" | Requested => "request" | PairRequested => "pair_request" | ReceivedPong => "pong" end.
Definition connector_step source observed := match state_of source,event_of observed with
 | Some state,Some event => let '(next,action) := step state event in
   Some (JObject [("state",state_json next);("action",JString (action_text action))])
 | _,_ => None end.

Record pairing_request := PairingRequest { request_id : string; requested_controller : controller_id; label : string }.
Inductive local_pairing := PairingIdle | AwaitingPairing (deadline : N) (pending : option pairing_request).
Inductive pairing_observation := BeginPairing (deadline : N) | ClearPairing
 | ObservePairing (now : N) | ReceivePairing (now : N) (request : pairing_request) | ConsumePairing (now : N) (id : string).
Definition live_pairing current now := match current with AwaitingPairing deadline _ =>
 if now <? deadline then current else PairingIdle | _ => PairingIdle end.
Definition local_pairing_step current event := match event with
 | BeginPairing deadline => AwaitingPairing deadline None | ClearPairing => PairingIdle
 | ObservePairing now => live_pairing current now
 | ReceivePairing now request => match live_pairing current now with
   AwaitingPairing deadline None => AwaitingPairing deadline (Some request) | other => other end
 | ConsumePairing now id => match live_pairing current now with
   AwaitingPairing deadline (Some request) => AwaitingPairing deadline
     (if String.eqb (request_id request) id then None else Some request) | other => other end end.
Definition request_json value := JObject [("request_id",JString (request_id value));
 ("controller_id",JString (controller_text (requested_controller value)));("label",JString (label value))].
Definition pairing_state_json current := match current with
 | PairingIdle => JObject [("expires_at",number 0);("pending",JArray [])]
 | AwaitingPairing deadline pending => JObject [("expires_at",number deadline);
   ("pending",JArray (match pending with Some value => [request_json value] | None => [] end))] end.
Definition request_decode source := PairingRequest (str source "request_id") (ControllerId (str source "controller_id")) (str source "label").
Definition pairing_state_of source :=
 if N.eqb (num source "expires_at") 0 then Some PairingIdle else
 match items (get source "pending") with [] => Some (AwaitingPairing (num source "expires_at") None)
 | [value] => Some (AwaitingPairing (num source "expires_at") (Some (request_decode value))) | _ => None end.
Definition pairing_event_of source := match str source "kind" with
 | "begin" => Some (BeginPairing (num source "expires_at")) | "clear" => Some ClearPairing
 | "observe" => Some (ObservePairing (num source "now"))
 | "receive" => Some (ReceivePairing (num source "now") (request_decode (get source "request")))
 | "consume" => Some (ConsumePairing (num source "now") (str source "request_id")) | _ => None end.
Definition pairing_step source observed := match pairing_state_of source,pairing_event_of observed with
 | Some current,Some event => Some (pairing_state_json (local_pairing_step current event)) | _,_ => None end.

Theorem stale_generation_is_ignored s n value : N.eqb (generation s) n = false ->
 step s (Observe n value) = (s,Ignore).
Proof. intro Stale; cbn [step]; now rewrite Stale. Qed.
Theorem retire_discards_all_queued_work s :
 step s (Observe (generation s) Retire) = (Offline (generation s) None,Retired).
Proof. cbn [step]; now rewrite N.eqb_refl. Qed.
