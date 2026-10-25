From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json RemoteIdentity.
From Selvedge.Host Require Import RemoteProtocol.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition grant := RemoteIdentity.authorization.
Definition Grant := RemoteIdentity.Authorization.
Definition controller := RemoteIdentity.authorization_controller.
Definition epoch := RemoteIdentity.authorization_epoch.
Record ticket := Ticket { ticket_digest : string; ticket_grant : grant; ticket_expiry : N }.
Record pairing := Pairing { pairing_digest : string; pairing_expiry : N }.
Record pairing_state := PairingState { pairing_revision : N; pending_pairing : option pairing }.
Record host_data := HostData { host_generation : N; host_pairing : pairing_state }.
Record controller_data := ControllerData { controller_generation : N; connection_id : string; connection_grant : grant }.

(* A host cannot own tickets until hello and its first grant snapshot have arrived. *)
Inductive state :=
 | Vacant (generation : N)
 | Negotiating (generation : N)
 | AwaitingGrants (host : host_data)
 | Ready (host : host_data) (tickets : list ticket)
 | Controller (connection : controller_data)
 | Closed.
Inductive observation :=
 | NewHost | Hello | GrantSnapshot (grants : list grant)
 | BeginPairing | InstallPairing (now revision : N) (value : pairing)
 | ConsumePairing (now : N) (digest : string)
 | DeliverPairing (now revision expiry : N)
 | IssueTicket (now : N) (grants : list grant) (value : ticket)
 | ConsumeTicket (now : N) (grants : list grant) (digest : string) (controller_count : N)
 | HostCurrent (generation : N) (require_ready : bool)
 | Delivery (generation : N) (grants : list grant) (host_ready : bool)
 | Frame (is_hello : bool)
 | Disconnected (generation : N) (host_ready : bool)
 | Unknown.
Inductive verdict := Permit | Deny.
Inductive reason := TicketLimit | HostOffline | ConnectionLimit | InvalidTicket.
Inductive action := Decision (allowed : verdict)
 | TicketIssued (allowed : verdict) (why : reason)
 | TicketConsumed (selected : option ticket) (allowed : verdict) (why : reason)
 | CloseControllers | NotifyHost (id : string) | NoAction.

Definition decide (allowed : bool) := if allowed then Permit else Deny.
Definition permitted value := match value with Permit=>true|Deny=>false end.
Definition same_grant left right := String.eqb (controller_text (controller left)) (controller_text (controller right)) &&
 N.eqb (epoch_number (epoch left)) (epoch_number (epoch right)).
Definition granted grants value := existsb (fun candidate=>same_grant candidate value) grants.
Definition current_ticket now grants value := (now <? value.(ticket_expiry)) && granted grants value.(ticket_grant).
Definition generation current := match current with
 | Vacant own | Negotiating own=>own | AwaitingGrants host | Ready host _=>host.(host_generation)
 | Controller connection=>connection.(controller_generation) | Closed=>0 end.
Definition initial_pairing := PairingState 0 None.
Definition update_pairing host pairing := HostData host.(host_generation) pairing.
Definition change_pairing current update := match current with
 | AwaitingGrants host=>AwaitingGrants (update_pairing host (update host.(host_pairing)))
 | Ready host tickets=>Ready (update_pairing host (update host.(host_pairing))) tickets | _=>current end.
Definition pairing_of current := match current with AwaitingGrants host | Ready host _=>Some host.(host_pairing)|_=>None end.
Definition host_current current expected require_ready :=
 N.eqb (generation current) expected && match current with
 | Ready _ _=>true | Negotiating _ | AwaitingGrants _=>negb require_ready | _=>false end.
Definition can_deliver current expected grants host_ready := host_ready && match current with
 | Controller connection=>N.eqb connection.(controller_generation) expected && granted grants connection.(connection_grant)
 | _=>false end.
Definition frame_allowed current is_hello := match current with
 | Negotiating _=>is_hello | AwaitingGrants _ | Ready _ _=>true | _=>false end.
Definition reason_text value := match value with TicketLimit=>"ticket_limit"|HostOffline=>"host_offline"
 | ConnectionLimit=>"connection_limit"|InvalidTicket=>"invalid_ticket" end.

Definition step (current : state) (event : observation) : state * action :=
 match event with
 | NewHost=>(Negotiating (N.succ (generation current)),Decision Permit)
 | Hello=>match current with
   | Negotiating own=>(AwaitingGrants (HostData own initial_pairing),Decision Permit)
   | AwaitingGrants _ | Ready _ _=>(current,Decision Permit)
   | _=>(current,Decision Deny) end
 | GrantSnapshot grants=>match current with
   | AwaitingGrants host=>(Ready host [],Decision Permit)
   | Ready host tickets=>(Ready host (filter (fun value=>granted grants value.(ticket_grant)) tickets),Decision Permit)
   | _=>(current,Decision Deny) end
 | BeginPairing=>match pairing_of current with
   | Some previous=>(change_pairing current (fun _=>PairingState (N.succ previous.(pairing_revision)) None),Decision Permit)
   | None=>(current,Decision Deny) end
 | InstallPairing now revision value=>
   let allowed:=match pairing_of current with Some previous=>N.eqb previous.(pairing_revision) revision &&
     (now <? value.(pairing_expiry)) && (value.(pairing_expiry) <=? now + 300000) | None=>false end in
   (if allowed then change_pairing current (fun previous=>PairingState previous.(pairing_revision) (Some value)) else current,Decision (decide allowed))
 | ConsumePairing now digest=>
   let allowed:=match pairing_of current with Some previous=>match previous.(pending_pairing) with
     Some value=>(now <? value.(pairing_expiry)) && String.eqb value.(pairing_digest) digest | None=>false end | None=>false end in
   (if allowed then change_pairing current (fun previous=>PairingState previous.(pairing_revision) None) else current,Decision (decide allowed))
 | DeliverPairing now revision expiry=>(current,Decision (decide (match pairing_of current with
     Some previous=>N.eqb previous.(pairing_revision) revision && (now <? expiry) | None=>false end)))
 | IssueTicket now grants value=>match current with
   | Ready host tickets=>
     let live:=filter (fun entry=>now <? entry.(ticket_expiry)) tickets in
     let fresh:=current_ticket now grants value in
     let allowed:=(N.of_nat (List.length live) <? 8) && fresh in
     (Ready host (if allowed then live++[value] else live),TicketIssued (decide allowed) (if fresh then TicketLimit else HostOffline))
   | _=>(current,TicketIssued Deny HostOffline) end
 | ConsumeTicket now grants digest count=>match current with
   | Ready host tickets=>
     let selected:=find (fun entry=>String.eqb entry.(ticket_digest) digest) tickets in
     let remaining:=filter (fun entry=>negb (String.eqb entry.(ticket_digest) digest)) tickets in
     let fresh:=match selected with Some value=>current_ticket now grants value | None=>false end in
     (Ready host remaining,TicketConsumed selected (decide (fresh && (count <? 32))) (if fresh then ConnectionLimit else InvalidTicket))
   | _=>(current,TicketConsumed None Deny InvalidTicket) end
 | HostCurrent expected require_ready=>(current,Decision (decide (host_current current expected require_ready)))
 | Delivery expected grants host_ready=>(current,Decision (decide (can_deliver current expected grants host_ready)))
 | Frame is_hello=>(current,Decision (decide (frame_allowed current is_hello)))
 | Disconnected expected host_ready=>(Closed,match current with
   | Negotiating own=>if N.eqb own expected then CloseControllers else NoAction
   | AwaitingGrants host | Ready host _=>if N.eqb host.(host_generation) expected then CloseControllers else NoAction
   | Controller connection=>if N.eqb connection.(controller_generation) expected && host_ready
     then NotifyHost connection.(connection_id) else NoAction
   | _=>NoAction end)
 | Unknown=>(current,Decision Deny)
 end.

(* JSON translates the one attachment format; no transition mutates JSON fields. *)
Definition decode_grant source := Grant (ControllerId (str source "controller_id")) (GrantEpoch (num source "grant_epoch")).
Definition encode_grant value := [("controller_id",JString (controller_text (controller value)));("grant_epoch",number (epoch_number (epoch value)))].
Definition decode_ticket source := Ticket (str source "digest") (decode_grant source) (num source "expires_at").
Definition encode_ticket value := JObject (("digest",JString value.(ticket_digest))::encode_grant value.(ticket_grant)++[("expires_at",number value.(ticket_expiry))]).
Definition decode_pairing source := if is_object source then Some (Pairing (str source "digest") (num source "expires_at")) else None.
Definition encode_pairing value := match value with None=>JNull|Some value=>JObject [("digest",JString value.(pairing_digest));("expires_at",number value.(pairing_expiry))] end.
Definition decode_state source :=
 let own:=num source "generation" in
 match str source "role" with
 | "host"=>if equal (get source "negotiated") (JBool true) then
   let host:=HostData own (PairingState (num source "pairing_revision") (decode_pairing (get source "pairing"))) in
   if equal (get source "synced") (JBool true) then Ready host (map decode_ticket (items (get source "tickets"))) else AwaitingGrants host
   else Negotiating own
 | "controller"=>Controller (ControllerData own (str source "connection_id") (decode_grant source))
 | "closed"=>Closed | _=>Vacant own end.
Definition encode_host own negotiated synced pairing tickets := JObject
 [("role",JString "host");("generation",number own);("negotiated",JBool negotiated);("synced",JBool synced);
 ("pairing",encode_pairing pairing.(pending_pairing));("pairing_revision",number pairing.(pairing_revision));("tickets",JArray (map encode_ticket tickets))].
Definition encode_state current := match current with
 | Vacant own=>JObject [("generation",number own)]
 | Negotiating own=>encode_host own false false initial_pairing []
 | AwaitingGrants host=>encode_host host.(host_generation) true false host.(host_pairing) []
 | Ready host tickets=>encode_host host.(host_generation) true true host.(host_pairing) tickets
 | Controller connection=>JObject ([("role",JString "controller");("generation",number connection.(controller_generation));("connection_id",JString connection.(connection_id))]++encode_grant connection.(connection_grant))
 | Closed=>JObject [("role",JString "closed")] end.
Definition decode_observation source :=
 let now:=num source "now" in let grants:=map decode_grant (items (get source "grants")) in
 match str source "kind" with
 | "host_new"=>NewHost | "hello"=>Hello | "grants"=>GrantSnapshot grants | "pairing_begin"=>BeginPairing
 | "pairing_install"=>InstallPairing now (num source "revision") (Pairing (str (get source "pairing") "digest") (num source "expires_at"))
 | "pair_consume"=>ConsumePairing now (str source "digest")
 | "pair_delivery"=>DeliverPairing now (num source "revision") (num source "expires_at")
 | "ticket_issue"=>IssueTicket now grants (decode_ticket (get source "ticket"))
 | "ticket_consume"=>ConsumeTicket now grants (str source "digest") (num source "controller_count")
 | _=>Unknown end.
Definition encode_result next output :=
 let fields:=[("state",encode_state next)] in JObject (fields++match output with
 | Decision allowed=>[("allowed",JBool (permitted allowed))]
 | TicketIssued allowed why=>[("allowed",JBool (permitted allowed));("reason",JString (reason_text why))]
 | TicketConsumed selected allowed why=>[("allowed",JBool (permitted allowed));("ticket",match selected with Some value=>encode_ticket value|None=>JNull end);("reason",JString (reason_text why))]
 | CloseControllers=>[("action",JString "close_controllers")]
 | NotifyHost id=>[("action",JString "notify_host");("connection_id",JString id)]
 | NoAction=>[("action",JString "none")] end).
Definition relay_step source event := let '(next,output):=step (decode_state source) (decode_observation event) in encode_result next output.
Definition ticket_current now grants source := current_ticket now (map decode_grant grants) (decode_ticket source).
Definition is_permitted output := match output with Decision Permit=>true|_=>false end.
Definition delivery_allowed source := is_permitted (snd (step (decode_state (get source "connection"))
 (Delivery (num source "generation") (map decode_grant (items (get source "grants"))) (equal (get source "host_ready") (JBool true))))).
Definition relay_host_current source := is_permitted (snd (step (decode_state (get source "connection"))
 (HostCurrent (num source "generation") (equal (get source "ready") (JBool true))))).
Definition relay_frame_allowed source := is_permitted (snd (step (decode_state (get source "state"))
 (Frame (String.eqb (str (get source "frame") "type") "hello")))).
Definition disconnect source := let '(next,output):=step (decode_state (get source "connection"))
 (Disconnected (num source "generation") (equal (get source "host_ready") (JBool true))) in encode_result next output.
