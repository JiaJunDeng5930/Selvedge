From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Host Require Import RemoteProtocol.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition result state action := JObject [("state",state);("action",JString action)].
Definition fresh_state generation := JObject [("running",JBool true);("generation",number generation);("ready",JBool false);("connections",JArray []);("grants",JArray []);("queued",number 0);("bytes",number 0)].
Definition enabled state := equal (get state "running") (JBool true).
Definition current state event := enabled state && N.eqb (num state "generation") (num event "generation").
Definition connection state id := find (fun entry=>String.eqb (str entry "connection_id") id) (items (get state "connections")).
Definition same_grant grants entry := existsb (fun grant=>String.eqb (str entry "controller_id") (str grant "controller_id") && N.eqb (num entry "grant_epoch") (num grant "grant_epoch")) grants.
Definition connections state values := set state "connections" (JArray values).
Definition forget state id := connections state (filter (fun entry=>negb (String.eqb (str entry "connection_id") id)) (items (get state "connections"))).
Definition connector_step state event :=
 let kind:=str event "kind" in let frame:=get event "frame" in
 if String.eqb kind "enable" then result (set state "running" (JBool true)) "enabled"
 else if String.eqb kind "start" then result (set (fresh_state (N.succ (num state "generation"))) "pairing" (get state "pairing")) "connect"
 else if String.eqb kind "stop" then result (set (fresh_state (N.succ (num state "generation"))) "running" (JBool false)) "stop"
 else if negb (current state event) then result state "ignore"
 else if String.eqb kind "retire" then result (set (set (connections state []) "ready" (JBool false)) "pairing" JNull) "retire"
 else if String.eqb kind "pair" then
 let next:=set state "pairing" frame in
 result next (if equal (get state "ready") (JBool true) && (num event "now" <? num frame "expires_at") then "pairing" else "pending")
 else if String.eqb kind "pairing_current" then
 if num event "now" <? num (get state "pairing") "expires_at" then result state "pairing" else result (set state "pairing" JNull) "expired"
 else if String.eqb kind "grants" then
 let grants:=items (get event "grants") in
 result (set (connections state (filter (same_grant grants) (items (get state "connections")))) "grants" (JArray grants)) "grants"
 else if String.eqb kind "enqueue" then
 match connection state (str event "connection_id") with None=>result state "ignore" | Some entry=>
 if (num entry "queued" <? 32) && (num state "queued" <? 256) && (num state "bytes" + num event "bytes" <=? 33554432) then
 let entry:=set entry "queued" (number (N.succ (num entry "queued"))) in
 let next:=connections (forget state (str event "connection_id")) (entry::items (get (forget state (str event "connection_id")) "connections")) in
 result (set (set next "queued" (number (N.succ (num state "queued")))) "bytes" (number (num state "bytes" + num event "bytes"))) "enqueue"
 else result state "disconnect" end
 else if String.eqb kind "dequeue" then
 let next:=match connection state (str event "connection_id") with None=>state | Some entry=>
 connections (forget state (str event "connection_id")) (set entry "queued" (number (N.pred (num entry "queued")))::items (get (forget state (str event "connection_id")) "connections")) end in
 result (set (set next "queued" (number (N.pred (num state "queued")))) "bytes" (number (num state "bytes" - num event "bytes"))) "dequeue"
 else if String.eqb kind "frame" then
 let kind:=str frame "type" in
 if String.eqb kind "ready" then
   if equal (get state "ready") (JBool true) then result state "disconnect" else result (set state "ready" (JBool true)) "ready"
 else if negb (equal (get state "ready") (JBool true)) then result state "disconnect"
 else if String.eqb kind "controller_open" then
 match connection state (str frame "connection_id") with Some _=>result state "disconnect" | None=>
 if N.of_nat (List.length (items (get state "connections"))) <? 32 then
 result (connections state (set frame "queued" (number 0)::items (get state "connections"))) kind else result state "disconnect" end
 else if String.eqb kind "pair_request" then result (set state "pairing" JNull) kind
 else if String.eqb kind "controller_close" then result (forget state (str frame "connection_id")) kind
 else if String.eqb kind "request" then
 match connection state (str frame "connection_id") with Some entry=>
 if String.eqb (str entry "controller_id") (str frame "controller_id") && N.eqb (num entry "grant_epoch") (num frame "grant_epoch") then result state kind else result state "disconnect"
 | None=>result state "disconnect" end
 else result state kind
 else result state "ignore".

Definition ticket_current now grants ticket := (now <? num ticket "expires_at") && same_grant grants ticket.
Definition relay_result state allowed := JObject [("state",state);("allowed",JBool allowed)].
Definition relay_step state event :=
 let kind:=str event "kind" in let now:=num event "now" in
 let grants:=items (get event "grants") in
 if String.eqb kind "host_new" then relay_result (JObject [("role",JString "host");("generation",number (N.succ (num state "generation")));("negotiated",JBool false);("synced",JBool false);("pairing",JNull);("pairing_revision",number 0);("tickets",JArray [])]) true
 else if String.eqb kind "hello" then relay_result (set state "negotiated" (JBool true)) true
 else if String.eqb kind "grants" then relay_result (set (set state "synced" (JBool true)) "tickets"
   (JArray (filter (same_grant grants) (items (get state "tickets"))))) true
 else if String.eqb kind "pairing_begin" then relay_result (set (set state "pairing_revision" (number (N.succ (num state "pairing_revision")))) "pairing" JNull) true
 else if String.eqb kind "pairing_install" then
 let expiry:=num event "expires_at" in
 let allowed:=N.eqb (num state "pairing_revision") (num event "revision") && (now <? expiry) && (expiry <=? now + 300000) in
 relay_result (if allowed then set state "pairing" (get event "pairing") else state) allowed
 else if String.eqb kind "pair_consume" then
 let pairing:=get state "pairing" in
 let allowed:=is_object pairing && (now <? num pairing "expires_at") && String.eqb (str pairing "digest") (str event "digest") in
 relay_result (if allowed then set state "pairing" JNull else state) allowed
 else if String.eqb kind "pair_delivery" then relay_result state
 (N.eqb (num state "pairing_revision") (num event "revision") && (now <? num event "expires_at"))
 else if String.eqb kind "ticket_issue" then
 let live:=filter (fun entry=>now <? num entry "expires_at") (items (get state "tickets")) in
 let ticket:=get event "ticket" in
 let allowed:=(N.of_nat (List.length live) <? 8) && ticket_current now grants ticket in
 JObject [("state",set state "tickets" (JArray (if allowed then live++[ticket] else live)));("allowed",JBool allowed);
 ("reason",JString (if ticket_current now grants ticket then "ticket_limit" else "host_offline"))]
 else if String.eqb kind "ticket_consume" then
 let tickets:=items (get state "tickets") in
 let selected:=find (fun entry=>String.eqb (str entry "digest") (str event "digest")) tickets in
 let remaining:=filter (fun entry=>negb (String.eqb (str entry "digest") (str event "digest"))) tickets in
 JObject [("state",set state "tickets" (JArray remaining));("allowed",JBool (match selected with
 Some entry=>ticket_current now grants entry && (num event "controller_count" <? 32) | None=>false end));
 ("ticket",match selected with Some entry=>entry | None=>JNull end);
 ("reason",JString (match selected with Some entry=>
   if ticket_current now grants entry then "connection_limit" else "invalid_ticket" | None=>"invalid_ticket" end))]
 else relay_result state false.
Definition delivery_allowed source :=
 equal (get source "host_ready") (JBool true) && N.eqb (num (get source "connection") "generation") (num source "generation") &&
 same_grant (items (get source "grants")) (get source "connection").

Definition pairing_step state event :=
 let kind:=str event "kind" in let now:=num event "now" in
 let live:=if now <? num state "expires_at" then items (get state "pending") else [] in
 let state:=set state "pending" (JArray live) in
 if String.eqb kind "begin" then set (set state "pending" (JArray [])) "expires_at" (get event "expires_at")
 else if String.eqb kind "clear" then JObject [("expires_at",number 0);("pending",JArray [])]
 else if String.eqb kind "receive" then
 if (now <? num state "expires_at") && Nat.eqb (List.length live) 0 then set state "pending" (JArray [get event "request"]) else state
 else if String.eqb kind "consume" then set state "pending" (JArray (filter (fun request=>negb (String.eqb (str request "request_id") (str event "request_id"))) live))
 else state.

Definition relay_host_current source :=
 let state:=get source "connection" in
 String.eqb (str state "role") "host" && N.eqb (num state "generation") (num source "generation") &&
 (negb (equal (get source "ready") (JBool true)) ||
 (equal (get state "negotiated") (JBool true) && equal (get state "synced") (JBool true))).

Definition relay_frame_allowed source := String.eqb (str (get source "frame") "type") "hello" || equal (get (get source "state") "negotiated") (JBool true).
