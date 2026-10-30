From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema RemoteIdentity.
From Selvedge.Foundation Require ArgumentDeclaration DeclarationFields.
From Selvedge.Host Require Import RemoteProtocol.
Module RP := RemoteProtocol.
Module D := ArgumentDeclaration.
Module F := DeclarationFields.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.
Open Scope list_scope.

Definition natural := D.Value Schema.KNatural.
Definition digest_declaration := D.exact_lower_hex 64.
Definition expiry_fields := [F.required "expires_at" natural].
Definition grant := RP.wire_authority.
Definition controller := RP.authority_controller.
Definition epoch := RP.authority_epoch.
Definition ticket_fields := F.required "digest" digest_declaration :: RP.authority_fields ++ expiry_fields.
Definition ticket_declaration := D.Object ticket_fields.
Definition ticket := D.denote ticket_declaration.
Definition ticket_parts (value : ticket) := F.split RP.authority_fields expiry_fields (snd (proj1_sig value)).
Definition ticket_digest (value : ticket) := proj1_sig (fst (proj1_sig value)).
Definition ticket_grant value := RP.authority_from_fields (fst (ticket_parts value)).
Definition ticket_expiry value := fst (snd (ticket_parts value)).
Definition pairing_fields := F.required "digest" digest_declaration :: expiry_fields.
Definition pairing_declaration := D.Object pairing_fields.
Definition pairing := D.denote pairing_declaration.
Definition pairing_digest (value : pairing) := proj1_sig (fst (proj1_sig value)).
Definition pairing_expiry (value : pairing) := fst (snd (proj1_sig value)).
Record pairing_state := PairingState { pairing_revision : N; pending_pairing : option pairing }.
Record host_data := HostData { host_generation : N; host_pairing : pairing_state }.
Record controller_data := ControllerData { controller_generation : N; connection_id : RP.identifier; connection_grant : grant }.

(* A host cannot own tickets until hello and its first grant snapshot have arrived. *)
Inductive state :=
 | Vacant (generation : N)
 | Negotiating (generation : N)
 | AwaitingGrants (host : host_data)
 | Ready (host : host_data) (tickets : list ticket)
 | Controller (connection : controller_data)
 | Closed.
Inductive observation :=
 | NewHost | Hello | GrantSnapshot (grants : RP.grant_set)
 | BeginPairing | InstallPairing (now revision : N) (value : pairing)
 | ConsumePairing (now : N) (digest : string)
 | DeliverPairing (now revision expiry : N)
 | IssueTicket (now : N) (grants : RP.grant_set) (value : ticket)
 | ConsumeTicket (now : N) (grants : RP.grant_set) (digest : string) (controller_count : N)
 | HostCurrent (generation : N) (require_ready : bool)
 | Delivery (generation : N) (grants : RP.grant_set) (host_ready : bool)
 | Frame (value : RP.host_frame)
 | Disconnected (generation : N) (host_ready : bool).
Inductive verdict := Permit | Deny.
Inductive reason := TicketLimit | HostOffline | ConnectionLimit | InvalidTicket.
Inductive action := Decision (allowed : verdict)
 | TicketIssued (allowed : verdict) (why : reason)
 | TicketConsumed (selected : option ticket) (allowed : verdict) (why : reason)
 | CloseControllers | NotifyHost (id : RP.identifier) | AcceptedFrame (value : RP.host_frame) | NoAction.

Definition decide (allowed : bool) := if allowed then Permit else Deny.
Definition permitted value := match value with Permit=>true|Deny=>false end.
Definition same_grant := RP.same_authority.
Definition granted grants value := existsb (fun candidate=>same_grant candidate value) (RP.grant_values grants).
Definition current_ticket now grants value := (now <? (ticket_expiry value)) && granted grants (ticket_grant value).
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
Definition frame_allowed current frame := match current with
 | Negotiating _=>match frame with RP.HostHello => true | _ => false end | AwaitingGrants _ | Ready _ _=>true | _=>false end.
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
   | Ready host tickets=>(Ready host (filter (fun value=>granted grants (ticket_grant value)) tickets),Decision Permit)
   | _=>(current,Decision Deny) end
 | BeginPairing=>match pairing_of current with
   | Some previous=>(change_pairing current (fun _=>PairingState (N.succ previous.(pairing_revision)) None),Decision Permit)
   | None=>(current,Decision Deny) end
 | InstallPairing now revision value=>
   let allowed:=match pairing_of current with Some previous=>N.eqb previous.(pairing_revision) revision &&
     (now <? (pairing_expiry value)) && ((pairing_expiry value) <=? now + 300000) | None=>false end in
   (if allowed then change_pairing current (fun previous=>PairingState previous.(pairing_revision) (Some value)) else current,Decision (decide allowed))
 | ConsumePairing now digest=>
   let allowed:=match pairing_of current with Some previous=>match previous.(pending_pairing) with
     Some value=>(now <? (pairing_expiry value)) && String.eqb (pairing_digest value) digest | None=>false end | None=>false end in
   (if allowed then change_pairing current (fun previous=>PairingState previous.(pairing_revision) None) else current,Decision (decide allowed))
 | DeliverPairing now revision expiry=>(current,Decision (decide (match pairing_of current with
     Some previous=>N.eqb previous.(pairing_revision) revision && (now <? expiry) | None=>false end)))
 | IssueTicket now grants value=>match current with
   | Ready host tickets=>
     let live:=filter (fun entry=>now <? (ticket_expiry entry)) tickets in
     let fresh:=current_ticket now grants value in
     let allowed:=(N.of_nat (List.length live) <? 8) && fresh in
     (Ready host (if allowed then live++[value] else live),TicketIssued (decide allowed) (if fresh then TicketLimit else HostOffline))
   | _=>(current,TicketIssued Deny HostOffline) end
 | ConsumeTicket now grants digest count=>match current with
   | Ready host tickets=>
     let selected:=find (fun entry=>String.eqb (ticket_digest entry) digest) tickets in
     let remaining:=filter (fun entry=>negb (String.eqb (ticket_digest entry) digest)) tickets in
     let fresh:=match selected with Some value=>current_ticket now grants value | None=>false end in
     (Ready host remaining,TicketConsumed selected (decide (fresh && (count <? 32))) (if fresh then ConnectionLimit else InvalidTicket))
   | _=>(current,TicketConsumed None Deny InvalidTicket) end
 | HostCurrent expected require_ready=>(current,Decision (decide (host_current current expected require_ready)))
 | Delivery expected grants host_ready=>(current,Decision (decide (can_deliver current expected grants host_ready)))
 | Frame frame=>(current,if frame_allowed current frame then AcceptedFrame frame else Decision Deny)
 | Disconnected expected host_ready=>(Closed,match current with
   | Negotiating own=>if N.eqb own expected then CloseControllers else NoAction
   | AwaitingGrants host | Ready host _=>if N.eqb host.(host_generation) expected then CloseControllers else NoAction
   | Controller connection=>if N.eqb connection.(controller_generation) expected && host_ready
     then NotifyHost connection.(connection_id) else NoAction
   | _=>NoAction end)
 end.

Definition optional_pairing := D.nullable pairing_declaration.
Definition pairing_arguments (value : option pairing) : D.denote optional_pairing :=
 match value with Some value => inl value | None => inr (inl tt) end.
Definition pairing_of_arguments (value : D.denote optional_pairing) := match value with
 | inl value => Some value | inr (inl _) => None | inr (inr impossible) => match impossible with end end.
Definition generation_field := F.required "generation" natural.
Definition host_branch negotiated synced pairing revision tickets := F.declare "role" (JString "host") [
 generation_field;F.required "negotiated" (D.Const (JBool negotiated));F.required "synced" (D.Const (JBool synced));
 F.required "pairing" pairing;F.required "pairing_revision" revision;F.required "tickets" tickets].
Definition negotiating_branch := host_branch false false (D.Const JNull) (D.Const (number 0)) (D.Const (JArray [])).
Definition awaiting_branch := host_branch true false optional_pairing natural (D.Const (JArray [])).
Definition ready_branch := host_branch true true optional_pairing natural (D.Array ticket_declaration).
Definition controller_branch := F.declare "role" (JString "controller") (generation_field :: RP.authorized_fields []).
Definition closed_branch := F.declare "role" (JString "closed") [].
Definition encode_state current := match current with
 | Vacant own => F.encode [generation_field] eq_refl (own,tt)
 | Negotiating own => F.branch_encode negotiating_branch [!own;tt;tt;tt;tt;tt!]
 | AwaitingGrants host => F.branch_encode awaiting_branch [!host.(host_generation);tt;tt;
     pairing_arguments host.(host_pairing).(pending_pairing);host.(host_pairing).(pairing_revision);tt!]
 | Ready host tickets => F.branch_encode ready_branch [!host.(host_generation);tt;tt;
     pairing_arguments host.(host_pairing).(pending_pairing);host.(host_pairing).(pairing_revision);tickets!]
 | Controller connection => F.branch_encode controller_branch
     (connection.(controller_generation),RP.authorized_values [] connection.(connection_id) connection.(connection_grant) tt)
 | Closed => F.branch_encode closed_branch tt end.
Definition state_decoders : list (F.decoder state) := [
 F.Decoder negotiating_branch (fun '(own,_) => Some (Negotiating own));
 F.Decoder awaiting_branch (fun '(own,(_,(_,(pairing,(revision,_))))) =>
   Some (AwaitingGrants (HostData own (PairingState revision (pairing_of_arguments pairing)))));
 F.Decoder ready_branch (fun '(own,(_,(_,(pairing,(revision,(tickets,_)))))) =>
   Some (Ready (HostData own (PairingState revision (pairing_of_arguments pairing))) tickets));
 F.Decoder controller_branch (fun '(own,(id,authority)) =>
   Some (Controller (ControllerData own id (RP.authority_from_fields authority))));
 F.Decoder closed_branch (fun _ => Some Closed)].
Definition decode_state source := match F.decode [generation_field] source with
 | Some (own,_) => Some (Vacant own) | None => F.decode_cases state_decoders source end.
Definition observed name fields (construct : F.values fields -> option observation)
 `{Schema.DistinctNames ("kind" :: F.names fields)} : F.decoder observation :=
 F.Decoder (F.declare "kind" (JString name) fields) construct.
Definition now_field := F.required "now" natural.
Definition digest_field := F.required "digest" digest_declaration.
Definition revision_field := F.required "revision" natural.
Definition grants_field := F.required "grants" RP.grants_declaration.
Definition observation_decoders : list (F.decoder observation) := [
 observed "host_new" [] (fun _ => Some NewHost);
 observed "hello" [] (fun _ => Some Hello);
 observed "grants" [grants_field] (fun '(values,_) => option_map GrantSnapshot (RP.grants_from_arguments values));
 observed "pairing_begin" [] (fun _ => Some BeginPairing);
 observed "pairing_install" [now_field;revision_field;F.required "pairing" pairing_declaration]
   (fun '(now,(revision,(pairing,_))) => Some (InstallPairing now revision pairing));
 observed "pair_consume" [now_field;digest_field]
   (fun '(now,(digest,_)) => Some (ConsumePairing now (proj1_sig digest)));
 observed "pair_delivery" [now_field;revision_field;F.required "expires_at" natural]
   (fun '(now,(revision,(expiry,_))) => Some (DeliverPairing now revision expiry));
 observed "ticket_issue" [now_field;grants_field;F.required "ticket" ticket_declaration]
   (fun '(now,(grants,(ticket,_))) => option_map (fun grants => IssueTicket now grants ticket) (RP.grants_from_arguments grants));
 observed "ticket_consume" [now_field;grants_field;digest_field;F.required "controller_count" natural]
   (fun '(now,(grants,(digest,(count,_)))) => option_map
     (fun grants => ConsumeTicket now grants (proj1_sig digest) count) (RP.grants_from_arguments grants))].
Definition decode_observation := F.decode_cases observation_decoders.
Definition encode_result next output :=
 let fields:=[("state",encode_state next)] in JObject (fields++match output with
 | Decision allowed=>[("allowed",JBool (permitted allowed))]
 | TicketIssued allowed why=>[("allowed",JBool (permitted allowed));("reason",JString (reason_text why))]
 | TicketConsumed selected allowed why=>[("allowed",JBool (permitted allowed));("ticket",match selected with
     Some value=>D.encode ticket_declaration value|None=>JNull end);("reason",JString (reason_text why))]
 | CloseControllers=>[("action",JString "close_controllers")]
 | NotifyHost id=>[("action",JString "notify_host");("connection_id",JString (RP.identifier_text id))]
 | AcceptedFrame value=>[("frame",RP.encode_host_frame value)]
 | NoAction=>[("action",JString "none")] end).
Definition relay_step source event := match decode_state source,decode_observation event with
 | Some state,Some event => let '(next,output):=step state event in Some (encode_result next output)
 | _,_ => None end.
Definition connection_context_fields := [F.required "connection" D.Any;generation_field;F.required "host_ready" D.Boolean].
Definition delivery_allowed source := match F.decode (connection_context_fields ++ [grants_field]) source with
 | Some (connection,(generation,(host_ready,(grants,_)))) =>
   match decode_state connection,RP.grants_from_arguments grants with
   | Some connection,Some grants => Some (can_deliver connection generation grants host_ready)
   | _,_ => None end
 | None => None end.
Definition relay_host_current source := match F.decode [F.required "connection" D.Any;generation_field;F.required "ready" D.Boolean] source with
 | Some (connection,(generation,(ready,_))) => option_map
     (fun connection => host_current connection generation ready) (decode_state connection)
 | None => None end.
Definition relay_frame_allowed source := match F.decode [F.required "state" D.Any;F.required "frame" RP.host_frame_declaration] source with
 | Some (state,(frame,_)) => match decode_state state,RP.host_frame_from_arguments frame with
   | Some state,Some frame => match snd (step state (Frame frame)) with
     | AcceptedFrame value => Some (RP.encode_host_frame value) | _ => None end
   | _,_ => None end
 | None => None end.
Definition forward_request source := match F.decode [F.required "connection" D.Any;
 F.required "request" RP.controller_request_declaration] source with
 | Some (connection,(request,_)) => match decode_state connection,RP.controller_request_from_arguments request with
   | Some (Controller connection),Some request => Some (RP.encode_relay_frame
       (RP.RelayRequest connection.(connection_id) connection.(connection_grant) request))
   | _,_ => None end
 | None => None end.
Definition install_controller source := match F.decode [generation_field;F.required "connection_id" RP.identifier_declaration;
 F.required "ticket" ticket_declaration] source with
 | Some (generation,(id,(ticket,_))) => let authority := ticket_grant ticket in
   let connection := ControllerData generation id authority in
   Some (JObject [("state",encode_state (Controller connection));
     ("host_frame",RP.encode_relay_frame (RP.RelayControllerOpen id authority));
     ("controller_frame",D.encode RP.controller_frame_declaration
       (inl (F.branch_arguments RP.controller_ready_branch (RP.version_value,RP.authority_to_fields authority))))])
 | None => None end.
Definition disconnect source := match F.decode connection_context_fields source with
 | Some (connection,(generation,(ready,_))) => option_map (fun current =>
     let '(next,output):=step current (Disconnected generation ready) in encode_result next output) (decode_state connection)
 | None => None end.
