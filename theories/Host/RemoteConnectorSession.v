From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema RemoteIdentity.
From Selvedge.Host Require Import RemoteProtocol.
From Selvedge.Kernel Require ModelDeclarations.
Module MD := Selvedge.Kernel.ModelDeclarations.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.
Open Scope list_scope.

Definition grant := authorization.
Definition Grant := Authorization.
Definition controller := authorization_controller.
Definition epoch := authorization_epoch.
Record connection := Connection { connection_id : string; authority : grant; after_notice : option N }.
Record pairing := Pairing { code : string; expires : N }.
Record queued := Queued { owner : string; bytes : N; queued_notice : option N }.
Record session := Session { pairing_code : option pairing; grants : list grant;
 connections : list connection; pending : list queued }.
Inductive phase := Offline (generation : N) (pairing : option pairing)
 | Negotiating (generation : N) (pairing : option pairing)
 | Ready (generation : N) (data : session).
Record state := State { current : phase; notice_sequence : N }.
Definition initial := State (Offline 0 None) 0.
Definition phase_generation s := match s with Offline n _ | Negotiating n _ | Ready n _ => n end.
Definition generation s := phase_generation (current s).
Definition pairing_of s := match s with Offline _ p | Negotiating _ p => p | Ready _ data => pairing_code data end.
Definition set_pairing s pairing_value := match s with Offline n _ => Offline n pairing_value | Negotiating n _ => Negotiating n pairing_value
 | Ready n data => Ready n (Session pairing_value (grants data) (connections data) (pending data)) end.
Definition same_grant left right := String.eqb (controller left) (controller right) && N.eqb (epoch left) (epoch right).
Definition permitted values value := existsb (fun other => same_grant other value) values.
Definition find_connection data id := find (fun entry => String.eqb (connection_id entry) id) (connections data).
Definition forget values id := filter (fun entry => negb (String.eqb (connection_id entry) id)) values.
Definition queued_for data id := N.of_nat (List.length (filter (fun job => String.eqb (owner job) id) (pending data))).
Definition queued_bytes data := fold_left (fun total job => total + bytes job) (pending data) 0.
Definition same_notice first second := match first,second with
 | None,None => true | Some earlier,Some later => N.eqb earlier later | _,_ => false end.
Fixpoint complete values id size notice := match values with [] => [] | job::rest =>
 if String.eqb (owner job) id && N.eqb (bytes job) size && same_notice (queued_notice job) notice
 then rest else job::complete rest id size notice end.
Definition notice_eligible sequence data id notice := match find_connection data id with
 | Some entry => match after_notice entry with Some after => (after <? notice) && (notice <=? sequence) | None => false end
 | None => false end.
Definition subscription data id after := Session (pairing_code data) (grants data)
 (map (fun entry => if String.eqb (connection_id entry) id then Connection id (authority entry) after else entry)
   (connections data)) (pending data).
Definition notice_queued data id notice := existsb (fun job =>
 String.eqb (owner job) id && same_notice (queued_notice job) (Some notice)) (pending data).
Inductive frame := RelayReady | ControllerOpen (entry : connection) | ControllerClose (id : string)
 | Request (id : string) (authority : grant) | PairRequest | Pong.
Inductive observation := Retire | SetPairing (value : pairing) (now : N) | CurrentPairing (now : N)
 | Grants (values : list grant) | Enqueue (id : string) (size : N) (notice : option N)
 | Dequeue (id : string) (size : N) (notice : option N)
 | Snapshot (id : string) (subscribe : bool) | Unsubscribe (id : string) | Deliver (id : string) (notice : N)
 | Frame (value : frame).
Inductive event := Install (generation : N) | Notice | Observe (generation : N) (value : observation).
Inductive action := Ignore | Installed | Retired | PublishPairing | PendingPairing | PairingExpired
 | GrantsUpdated | Enqueued | Dequeued | Disconnect | BecameReady | Opened | Closed | Requested | PairRequested | ReceivedPong
 | RecordedNotice | CapturedSnapshot | Unsubscribed | DeliverNotice.
Definition deliver_notice sequence data id notice :=
 if notice_eligible sequence data id notice && notice_queued data id notice
 then (subscription data id (Some notice),DeliverNotice) else (data,Ignore).
Definition phase_step sequence s event : phase * action := match event with
 | Install n => (Negotiating n (pairing_of s),Installed)
 | Notice => (s,RecordedNotice)
 | Observe n value => if negb (N.eqb (phase_generation s) n) then (s,Ignore) else
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
       | Enqueue id size notice => match find_connection data id with None => (s,Ignore) | Some _ =>
         if match notice with Some value => notice_eligible sequence data id value | None => true end then
         if (queued_for data id <? 32) && (N.of_nat (List.length (pending data)) <? 256) &&
           (queued_bytes data + size <=? 33554432) then
           (Ready g (Session (pairing_code data) (grants data) (connections data) (Queued id size notice::pending data)),Enqueued)
         else (s,Disconnect) else (s,Ignore) end
       | Dequeue id size notice => (Ready g (Session (pairing_code data) (grants data) (connections data)
         (complete (pending data) id size notice)),Dequeued)
       | Snapshot id subscribe => match find_connection data id with None => (s,Ignore) | Some _ =>
         (Ready g (if subscribe then subscription data id (Some sequence) else data),CapturedSnapshot) end
       | Unsubscribe id => match find_connection data id with None => (s,Ignore) | Some _ =>
         (Ready g (subscription data id None),Unsubscribed) end
       | Deliver id notice => let '(next,action) := deliver_notice sequence data id notice in (Ready g next,action)
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
Definition step s event : state * action :=
 let '(next,action) := phase_step (notice_sequence s) (current s) event in
 (State next (match event with Notice => N.succ (notice_sequence s) | _ => notice_sequence s end),action).

Definition grant_json entry := JObject [("controller_id",JString (controller entry));("grant_epoch",number (epoch entry))].
Definition grant_of value := Grant (ControllerId (str value "controller_id")) (GrantEpoch (num value "grant_epoch")).
Definition connection_json entry := JObject [("connection_id",JString (connection_id entry));
 ("controller_id",JString (controller (authority entry)));("grant_epoch",number (epoch (authority entry)));
 ("after",match after_notice entry with Some value => number value | None => JNull end)].
Definition connection_of value := Connection (str value "connection_id") (grant_of value) (Schema.decode_value Schema.KNatural (get value "after")).
Definition pairing_json value := match value with None => JNull | Some pairing_value => JObject
 [("type",JString "pairing");("code",JString (code pairing_value));("expires_at",number (expires pairing_value))] end.
Definition pairing_decode value := match value with JObject _ => Some (Pairing (str value "code") (num value "expires_at")) | _ => None end.
Definition queued_json value := JObject [("connection_id",JString (owner value));("bytes",number (bytes value));
 ("notice_sequence",match queued_notice value with Some sequence => number sequence | None => JNull end)].
Definition queued_of value := Queued (str value "connection_id") (num value "bytes")
 (Schema.decode_value Schema.KNatural (get value "notice_sequence")).
Definition generation_field := Field "generation" KNatural.
Definition notice_field := Field "notice_sequence" KNatural.
Definition state_fields := [generation_field;Field "pairing" KJson;notice_field].
Definition state_declaration name extra := MD.Variant "phase" (JString name) (state_fields ++ extra)
 (map field_name (state_fields ++ extra)) None.
Definition offline := state_declaration "offline" [].
Definition negotiating := state_declaration "negotiating" [].
Definition ready := state_declaration "ready"
 [Field "grants" (KArray KJson);Field "connections" (KArray KJson);Field "pending" (KArray KJson)].
Definition state_packet s := match current s with
 | Offline n pairing_value=>MD.pack offline [!n;pairing_json pairing_value;notice_sequence s!]
 | Negotiating n pairing_value=>MD.pack negotiating [!n;pairing_json pairing_value;notice_sequence s!]
 | Ready n data=>MD.pack ready [!n;pairing_json (pairing_code data);notice_sequence s;
     map grant_json (grants data);map connection_json (connections data);map queued_json (pending data)!] end.
Definition state_json s := MD.encode_packet (state_packet s).
Definition state_decoders : list (MD.decoder state) := [
 MD.Decoder offline (fun v=>Some (State (Offline (head v) (pairing_decode (head (tail v)))) (head (tail (tail v)))));
 MD.Decoder negotiating (fun v=>Some (State (Negotiating (head v) (pairing_decode (head (tail v)))) (head (tail (tail v)))));
 MD.Decoder ready (fun v=>let n:=head v in let v:=tail v in let pairing_value:=pairing_decode (head v) in
   let v:=tail v in let sequence:=head v in let v:=tail v in
   Some (State (Ready n (Session pairing_value (map grant_of (head v))
     (map connection_of (head (tail v))) (map queued_of (head (tail (tail v)))))) sequence))].
Definition state_of := MD.decode_cases state_decoders.
Definition frame_of source := match str source "type" with
 | "ready" => Some RelayReady | "controller_open" => Some (ControllerOpen (Connection (str source "connection_id") (grant_of source) None))
 | "controller_close" => Some (ControllerClose (str source "connection_id"))
 | "request" => Some (Request (str source "connection_id") (grant_of source))
 | "pair_request" => Some PairRequest | "pong" => Some Pong | _ => None end.
Definition event_decoder name description construct : MD.decoder event :=
 MD.Decoder (MD.Variant "kind" (JString name) description (map field_name description) None) construct.
Definition observation_decoder name description (construct : fields description -> option observation) :=
 event_decoder name (generation_field::description)
   (fun values=>option_map (Observe (head values)) (construct (tail values))).
Definition queue_fields := [Field "connection_id" KText;Field "bytes" KNatural;Field "notice_sequence" KJson].
Definition queue_decoder name construct := observation_decoder name queue_fields
 (fun values=>Some (construct (head values) (head (tail values))
   (Schema.decode_value KNatural (head (tail (tail values)))))).
Definition event_decoders : list (MD.decoder event) := [
 event_decoder "install" [generation_field] (fun v=>Some (Install (head v)));
 observation_decoder "retire" [] (fun _=>Some Retire);
 observation_decoder "pair" [Field "now" KNatural;Field "frame" KJson]
   (fun v=>option_map (fun pairing_value=>SetPairing pairing_value (head v)) (pairing_decode (head (tail v))));
 observation_decoder "pairing_current" [Field "now" KNatural] (fun v=>Some (CurrentPairing (head v)));
 observation_decoder "grants" [Field "grants" (KArray KJson)] (fun v=>Some (Grants (map grant_of (head v))));
 queue_decoder "enqueue" Enqueue;queue_decoder "dequeue" Dequeue;
 event_decoder "notice" [] (fun _=>Some Notice);
 observation_decoder "capture" [Field "connection_id" KText;Field "method" (KEnum "snapshot" ["subscribe";"unsubscribe"])]
   (fun v=>Some (match proj1_sig (head (tail v)) with "unsubscribe"=>Unsubscribe (head v)
      | "subscribe"=>Snapshot (head v) true | _=>Snapshot (head v) false end));
 observation_decoder "deliver" [Field "connection_id" KText;notice_field]
   (fun v=>Some (Deliver (head v) (head (tail v))));
 observation_decoder "frame" [Field "frame" KJson] (fun v=>option_map Frame (frame_of (head v)))].
Definition event_of := MD.decode_cases event_decoders.
Definition action_text value := match value with Ignore => "ignore" | Installed => "installed" | Retired => "retire"
 | PublishPairing => "pairing" | PendingPairing => "pending" | PairingExpired => "expired" | GrantsUpdated => "grants"
 | Enqueued => "enqueue" | Dequeued => "dequeue" | Disconnect => "disconnect" | BecameReady => "ready"
 | Opened => "controller_open" | Closed => "controller_close" | Requested => "request" | PairRequested => "pair_request" | ReceivedPong => "pong"
 | RecordedNotice => "notice" | CapturedSnapshot => "snapshot" | Unsubscribed => "unsubscribed" | DeliverNotice => "deliver" end.
Definition action_kind := KEnum (action_text Ignore) (map action_text
 [Installed;Retired;PublishPairing;PendingPairing;PairingExpired;GrantsUpdated;Enqueued;Dequeued;Disconnect;
  BecameReady;Opened;Closed;Requested;PairRequested;ReceivedPong;RecordedNotice;CapturedSnapshot;Unsubscribed;DeliverNotice]).
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
Proof. destruct s as [phase sequence]. intro Stale.
 unfold step,phase_step,generation in *; cbn in *. rewrite Stale. reflexivity. Qed.
Theorem retire_discards_all_queued_work s :
 step s (Observe (generation s) Retire) = (State (Offline (generation s) None) (notice_sequence s),Retired).
Proof. unfold step,phase_step,generation. now rewrite N.eqb_refl. Qed.

Theorem unqueued_notice_cannot_publish sequence data id notice :
 notice_queued data id notice = false -> snd (deliver_notice sequence data id notice) = Ignore.
Proof. intro H. unfold deliver_notice. rewrite H,andb_false_r. reflexivity. Qed.
Theorem unsubscribed_connection_cannot_publish sequence data id notice entry :
 find_connection data id = Some entry -> after_notice entry = None ->
 snd (deliver_notice sequence data id notice) = Ignore.
Proof. intros Found Unsubscribed. unfold deliver_notice,notice_eligible.
 rewrite Found,Unsubscribed. reflexivity. Qed.
Theorem captured_prefix_cannot_publish sequence data id notice entry after :
 find_connection data id = Some entry -> after_notice entry = Some after ->
 (after <? notice) = false -> snd (deliver_notice sequence data id notice) = Ignore.
Proof. intros Found Subscribed Old. unfold deliver_notice,notice_eligible.
 rewrite Found,Subscribed,Old. reflexivity. Qed.
Theorem notice_sequence_survives_transport_retirement s :
 notice_sequence (fst (step s (Observe (generation s) Retire))) = notice_sequence s.
Proof. rewrite retire_discards_all_queued_work. reflexivity. Qed.
