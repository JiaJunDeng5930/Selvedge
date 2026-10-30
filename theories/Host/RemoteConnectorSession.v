From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema RemoteIdentity.
From Selvedge.Foundation Require ArgumentDeclaration DeclarationFields OptionList.
From Selvedge.Host Require Import RemoteProtocol.
From Selvedge.Kernel Require ModelDeclarations.
Module MD := Selvedge.Kernel.ModelDeclarations.
Module RP := RemoteProtocol.
Module D := ArgumentDeclaration.
Module F := DeclarationFields.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.
Open Scope list_scope.

Definition grant := RP.wire_authority.
Definition controller := RP.authority_controller.
Definition epoch := RP.authority_epoch.
Record connection := Connection { connection_identity : RP.identifier; authority : grant; after_notice : option N }.
Definition connection_id value := RP.identifier_text (connection_identity value).
Definition pairing := RP.pairing_announcement.
Definition code := RP.pairing_code.
Definition expires := RP.pairing_expiry.
Record queued := Queued { owner : string; bytes : N; queued_notice : option N }.
Record session := Session { pairing_code : option pairing; grants : RP.grant_set;
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
Definition same_grant := RP.same_authority.
Definition permitted values value := existsb (fun other => same_grant other value) (RP.grant_values values).
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
 (map (fun entry => if String.eqb (connection_id entry) id then Connection (connection_identity entry) (authority entry) after else entry)
   (connections data)) (pending data).
Definition notice_queued data id notice := existsb (fun job =>
 String.eqb (owner job) id && same_notice (queued_notice job) (Some notice)) (pending data).
Definition frame := RP.relay_frame.
Definition Request := RP.RelayRequest.
Inductive observation := Retire | SetPairing (value : pairing) (now : N) | CurrentPairing (now : N)
 | Grants (values : RP.grant_set) | Enqueue (id : string) (size : N) (notice : option N)
 | Dequeue (id : string) (size : N) (notice : option N)
 | Snapshot (id : string) (subscribe : bool) | Unsubscribe (id : string) | Deliver (id : string) (notice : N)
 | Frame (value : frame).
Inductive event := Install (generation : N) | Notice | Observe (generation : N) (value : observation).
Inductive action := Ignore | Installed | Retired | PublishPairing | PendingPairing | PairingExpired
 | GrantsUpdated | Enqueued | Dequeued | Disconnect | BecameReady
 | Opened (entry : connection) | Closed (id : RP.identifier)
 | Requested (entry : connection) (request : RP.rpc_request) | PairRequested (request : RP.pairing_request) | ReceivedPong
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
     | Negotiating g pairing_value => match value with Frame RP.RelayReady => (Ready g (Session pairing_value RP.no_grants [] []),BecameReady)
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
       | Frame RP.RelayReady => (s,Disconnect)
       | Frame (RP.RelayControllerOpen id requested) => let entry := Connection id requested None in
         match find_connection data (connection_id entry) with Some _ => (s,Disconnect) | None =>
         if N.of_nat (List.length (connections data)) <? 32 then
           (Ready g (Session (pairing_code data) (grants data) (entry::connections data) (pending data)),Opened entry)
         else (s,Disconnect) end
       | Frame (RP.RelayControllerClose id) => (Ready g (Session (pairing_code data) (grants data)
         (forget (connections data) (RP.identifier_text id)) (pending data)),Closed id)
       | Frame (RP.RelayRequest id requested request) => match find_connection data (RP.identifier_text id) with
         Some entry => (s,if same_grant (authority entry) requested then Requested entry request else Disconnect)
         | None => (s,Disconnect) end
       | Frame (RP.RelayPairRequest request) => (set_pairing s None,PairRequested request)
       | Frame RP.RelayPong => (s,ReceivedPong)
       | _ => (s,Ignore) end end end end.
Definition step s event : state * action :=
 let '(next,action) := phase_step (notice_sequence s) (current s) event in
 (State next (match event with Notice => N.succ (notice_sequence s) | _ => notice_sequence s end),action).

Definition natural := D.Value KNatural.
Definition optional_natural := D.nullable natural.
Definition natural_arguments (value : option N) : D.denote optional_natural :=
 match value with Some value => inl value | None => inr (inl tt) end.
Definition natural_from_arguments (value : D.denote optional_natural) := match value with
 | inl value => Some value | inr (inl _) => None | inr (inr impossible) => match impossible with end end.
Definition optional_pairing := D.nullable RP.pairing_declaration.
Definition pairing_arguments (value : option pairing) : D.denote optional_pairing := match value with
 | Some value => inl (RP.pairing_arguments value) | None => inr (inl tt) end.
Definition pairing_from_arguments (value : D.denote optional_pairing) := match value with
 | inl value => Some (RP.pairing_from_fields (snd (proj1_sig value)))
 | inr (inl _) => None | inr (inr impossible) => match impossible with end end.
Definition connection_fields := RP.authorized_fields [F.required "after" optional_natural].
Definition connection_declaration := D.Object connection_fields.
Definition connection_arguments entry : D.denote connection_declaration := F.construct connection_fields
 (RP.authorized_values [F.required "after" optional_natural] (connection_identity entry) (authority entry)
 [!natural_arguments (after_notice entry)!]).
Definition connection_from_arguments (value : D.denote connection_declaration) :=
 let value := proj1_sig value in
 let '(authority,after) := F.split RP.authority_fields [F.required "after" optional_natural] (snd value) in
 Connection (fst value) (RP.authority_from_fields authority) (natural_from_arguments (fst after)).
Definition queued_fields := [F.required "connection_id" (D.Value KText);F.required "bytes" natural;
 F.required "notice_sequence" optional_natural].
Definition queued_declaration := D.Object queued_fields.
Definition queued_arguments value : D.denote queued_declaration := F.construct queued_fields
 [!owner value;bytes value;natural_arguments (queued_notice value)!].
Definition queued_from_arguments (value : D.denote queued_declaration) :=
 let '(id,(bytes,(notice,_))) := proj1_sig value in Queued id bytes (natural_from_arguments notice).
Definition generation_field := F.required "generation" natural.
Definition notice_field := F.required "notice_sequence" natural.
Definition state_fields := [generation_field;F.required "pairing" optional_pairing;notice_field].
Definition state_declaration name extra
 `{DistinctNames ("phase" :: F.names (state_fields ++ extra))} := F.declare "phase" (JString name) (state_fields ++ extra).
Definition offline := state_declaration "offline" [].
Definition negotiating := state_declaration "negotiating" [].
Definition ready := state_declaration "ready" [F.required "grants" RP.grants_declaration;
 F.required "connections" (D.Array connection_declaration);F.required "pending" (D.Array queued_declaration)].
Definition state_packet s := match current s with
 | Offline n pairing_value => F.Packet offline [!n;pairing_arguments pairing_value;notice_sequence s!]
 | Negotiating n pairing_value => F.Packet negotiating [!n;pairing_arguments pairing_value;notice_sequence s!]
 | Ready n data => F.Packet ready [!n;pairing_arguments (pairing_code data);notice_sequence s;
     RP.grants_arguments (grants data);map connection_arguments (connections data);map queued_arguments (pending data)!] end.
Definition state_json s := F.encode_packet (state_packet s).
Definition state_decoders : list (F.decoder state) := [
 F.Decoder offline (fun '(n,(pairing,(sequence,_))) => Some (State (Offline n (pairing_from_arguments pairing)) sequence));
 F.Decoder negotiating (fun '(n,(pairing,(sequence,_))) => Some (State (Negotiating n (pairing_from_arguments pairing)) sequence));
 F.Decoder ready (fun '(n,(pairing,(sequence,(grants,(connections,(pending,_)))))) =>
   option_map (fun admitted => State (Ready n (Session (pairing_from_arguments pairing) admitted
     (map connection_from_arguments connections) (map queued_from_arguments pending))) sequence)
     (RP.grants_from_arguments grants))].
Definition state_of := F.decode_cases state_decoders.
Definition event_decoder name description (construct : F.values description -> option event)
 `{DistinctNames ("kind" :: F.names description)} : F.decoder event :=
 F.Decoder (F.declare "kind" (JString name) description) construct.
Definition observation_decoder name description (construct : F.values description -> option observation)
 `{DistinctNames ("kind" :: "generation" :: F.names description)} :=
 event_decoder name (generation_field::description)
   (fun values => option_map (Observe (fst values)) (construct (snd values))).
Definition queue_decoder name construct := observation_decoder name queued_fields
 (fun '(id,(bytes,(notice,_))) => Some (construct id bytes (natural_from_arguments notice))).
Definition event_decoders : list (F.decoder event) := [
 event_decoder "install" [generation_field] (fun '(generation,_) => Some (Install generation));
 observation_decoder "retire" [] (fun _ => Some Retire);
 observation_decoder "pair" [F.required "now" natural;F.required "frame" RP.pairing_declaration]
   (fun '(now,(pairing,_)) => Some (SetPairing (RP.pairing_from_fields (snd (proj1_sig pairing))) now));
 observation_decoder "pairing_current" [F.required "now" natural] (fun '(now,_) => Some (CurrentPairing now));
 observation_decoder "grants" [F.required "grants" RP.grants_declaration]
   (fun '(grants,_) => option_map Grants (RP.grants_from_arguments grants));
 queue_decoder "enqueue" Enqueue;queue_decoder "dequeue" Dequeue;
 event_decoder "notice" [] (fun _ => Some Notice);
 observation_decoder "capture" [F.required "connection_id" (D.Value KText);
     F.required "method" (D.Value (KEnum "snapshot" ["subscribe";"unsubscribe"]))]
   (fun '(id,(method,_)) => Some (match proj1_sig method with "unsubscribe" => Unsubscribe id
      | "subscribe" => Snapshot id true | _ => Snapshot id false end));
 observation_decoder "deliver" [F.required "connection_id" (D.Value KText);notice_field]
   (fun '(id,(notice,_)) => Some (Deliver id notice));
 observation_decoder "frame" [F.required "frame" RP.relay_frame_declaration]
   (fun '(frame,_) => option_map Frame (RP.relay_frame_from_arguments frame))].
Definition event_of := F.decode_cases event_decoders.
Definition simple_action name := F.declare "kind" (JString name) [].
Definition opened_action := F.declare "kind" (JString "controller_open") RP.controller_open_fields.
Definition closed_action := F.declare "kind" (JString "controller_close") RP.controller_close_fields.
Definition request_action := F.declare "kind" (JString "request") RP.relay_request_fields.
Definition pair_request_action := F.declare "kind" (JString "pair_request") [F.required "request" RP.pairing_request_declaration].
Definition simple_packet name := F.Packet (simple_action name) tt.
Definition action_packet value := match value with
 | Opened entry => F.Packet opened_action (RP.authorized_values [] (connection_identity entry) (authority entry) tt)
 | Closed id => F.Packet closed_action [!id!]
 | Requested entry request => F.Packet request_action
   (RP.authorized_values [F.required "request" RP.controller_request_declaration] (connection_identity entry)
     (authority entry) [!RP.controller_request_arguments request!])
 | PairRequested request => F.Packet pair_request_action [!RP.pairing_request_arguments request!]
 | Ignore => simple_packet "ignore" | Installed => simple_packet "installed" | Retired => simple_packet "retire"
 | PublishPairing => simple_packet "pairing" | PendingPairing => simple_packet "pending" | PairingExpired => simple_packet "expired"
 | GrantsUpdated => simple_packet "grants" | Enqueued => simple_packet "enqueue" | Dequeued => simple_packet "dequeue"
 | Disconnect => simple_packet "disconnect" | BecameReady => simple_packet "ready" | ReceivedPong => simple_packet "pong"
 | RecordedNotice => simple_packet "notice" | CapturedSnapshot => simple_packet "snapshot"
 | Unsubscribed => simple_packet "unsubscribed" | DeliverNotice => simple_packet "deliver" end.
Definition action_declarations := map (fun action => F.packet_branch (action_packet action))
 [Ignore;Installed;Retired;PublishPairing;PendingPairing;PairingExpired;GrantsUpdated;Enqueued;Dequeued;Disconnect;
  BecameReady;ReceivedPong;RecordedNotice;CapturedSnapshot;Unsubscribed;DeliverNotice] ++
 [opened_action;closed_action;request_action;pair_request_action].
Definition abi_variant declaration := MD.from_branch declaration (F.names (F.payload_fields declaration)) None.
Definition connector_step source observed := match state_of source,event_of observed with
 | Some state,Some event => let '(next,action) := step state event in
   let state := state_packet next in let action := action_packet action in
   let fields := [F.required "state" (F.branch_declaration (F.packet_branch state));
     F.required "action" (F.branch_declaration (F.packet_branch action))] in
   Some (D.encode (D.Object fields) (F.construct fields
     [!F.branch_arguments (F.packet_branch state) (F.packet_values state);
       F.branch_arguments (F.packet_branch action) (F.packet_values action)!]))
 | _,_ => None end.

Definition pairing_request := RP.pairing_request.
Definition request_id := RP.pairing_request_id.
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
Definition pairing_state_fields := [F.required "expires_at" natural;
 F.required "pending" (D.BoundedArray 0 1 RP.pairing_request_declaration)].
Definition pairing_state_arguments current : F.values pairing_state_fields := match current with
 | PairingIdle => [!0;exist _ [] eq_refl!]
 | AwaitingPairing deadline pending => [!deadline;match pending with
     | None => exist _ [] eq_refl
     | Some value => exist _ [RP.pairing_request_arguments value] eq_refl end!] end.
Definition pairing_state_json current := D.encode (D.Object pairing_state_fields)
 (F.construct pairing_state_fields (pairing_state_arguments current)).
Definition pairing_state_of source := match F.decode pairing_state_fields source with
 | Some (deadline,(pending,_)) => if N.eqb deadline 0 then Some PairingIdle else
     Some (AwaitingPairing deadline (option_map (fun value => RP.pairing_request_from_fields (proj1_sig value))
       (hd_error (proj1_sig pending))))
 | None => None end.
Definition pairing_event name fields (construct : N -> F.values fields -> option pairing_observation)
 `{DistinctNames ("kind" :: "now" :: F.names fields)} : F.decoder pairing_observation :=
 F.Decoder (F.declare "kind" (JString name) (F.required "now" natural :: fields))
   (fun '(now,values) => construct now values).
Definition pairing_event_of := F.decode_cases [
 pairing_event "begin" [F.required "expires_at" natural] (fun _ '(deadline,_) => Some (BeginPairing deadline));
 pairing_event "clear" [] (fun _ _ => Some ClearPairing);
 pairing_event "observe" [] (fun now _ => Some (ObservePairing now));
 pairing_event "receive" [F.required "request" RP.pairing_request_declaration]
   (fun now '(request,_) => Some (ReceivePairing now (RP.pairing_request_from_fields (proj1_sig request))));
 pairing_event "consume" [F.required "request_id" RP.identifier_declaration]
   (fun now '(request,_) => Some (ConsumePairing now (RP.identifier_text request)))].
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
