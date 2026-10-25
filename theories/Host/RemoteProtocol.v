From Stdlib Require Import String List Bool Ascii NArith ZArith.
From Selvedge.Foundation Require Import Json Numbers Schema Utf8 RemoteIdentity.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition get (source : json) (name : string) := match field name source with Some value => value | None => JNull end.
Definition str source name := match get source name with JString value => value | _ => "" end.
Definition num source name := match get source name with JNumber value => match parse_natural value with Some n=>n | None=>0 end | _=>0 end.
Definition number value := JNumber (show_natural value).
Definition items value := match value with JArray values=>values | _=>[] end.
Definition set source name value := match source with JObject fields=>JObject (set_field name value fields) | _=>source end.
Definition shape source names := match source with JObject fields =>
 Nat.eqb (List.length fields) (List.length names) &&
 forallb (fun name=>has_field name source) names && Schema.unique_names (map fst fields)
 | _=>false end.
Fixpoint printable value := match value with EmptyString=>true | String character rest=>
 let code:=N.of_nat (nat_of_ascii character) in (32 <=? code) && negb (N.eqb code 127) && printable rest end.
Definition wire_length text := match Utf8.decode text with
 Some values=>fold_left (fun total scalar=>total + if scalar <=? 65535 then 1 else 2) values 0
 | None=>0 end.
Definition bounded value maximum := match value with JString text=>
 negb (String.eqb text "") && (N.of_nat (String.length text) <=? 4 * maximum) && (wire_length text <=? maximum) && Utf8.well_formed text && printable text | _=>false end.
Definition identifier value := bounded value 128.
Definition controller value := match value with JString text=>RemoteIdentity.controller_valid text | _=>false end.
Definition safe_signed value := match value with JNumber source=>match parse_integer source with
 Some integer=>Z.leb (Z.abs integer) 9007199254740991%Z | None=>false end | _=>false end.
Definition positive value := match value with JNumber source=>match parse_natural source with
 Some n=>RemoteIdentity.epoch_valid n | None=>false end | _=>false end.
Definition version source := equal (get source "version") (number 1).
Definition epoch source := positive (get source "grant_epoch").
Definition rpc_id source := identifier (get source "id") || safe_signed (get source "id").
Definition controller_request source := shape source ["id";"method";"params"] && rpc_id source &&
 let params:=get source "params" in
 if String.eqb (str source "method") "command" then
 shape params ["request_id";"command"] &&
 (match get params "request_id" with JString text=>RemoteIdentity.request_valid text | _=>false end) &&
 is_object (get params "command") && bounded (get (get params "command") "op") 80
 else (existsb (String.eqb (str source "method")) ["snapshot";"subscribe";"unsubscribe"]) && shape params [].
Definition response source := rpc_id source &&
 if has_field "error" source then shape source ["id";"error"] &&
 shape (get source "error") ["code";"message"] && bounded (get (get source "error") "code") 80 && bounded (get (get source "error") "message") 1024
 else shape source ["id";"result"].
Definition grant source := shape source ["controller_id";"grant_epoch"] && controller (get source "controller_id") && epoch source.
Definition grants value := match value with JArray values=>
 (N.of_nat (List.length values) <=? 64) && forallb grant values && Schema.unique_names (map (fun source=>str source "controller_id") values) | _=>false end.
Definition host_frame source :=
 match str source "type" with
 | "hello"=>shape source ["type";"version"] && version source
 | "grants"=>shape source ["type";"grants"] && grants (get source "grants")
 | "pairing"=>shape source ["type";"code";"expires_at"] && bounded (get source "code") 128 &&
 (20 <=? wire_length (str source "code")) && positive (get source "expires_at")
 | "response"=>shape source ["type";"connection_id";"response"] && identifier (get source "connection_id") && response (get source "response")
 | "event"=>shape source ["type";"connection_id";"event"] && identifier (get source "connection_id") && is_object (get source "event")
 | "ping"=>shape source ["type"] | _=>false end.
Definition relay_frame source :=
 match str source "type" with
 | "ready"=>shape source ["type";"version"] && version source
 | "pair_request"=>shape source ["type";"request_id";"controller_id";"label"] && identifier (get source "request_id") && controller (get source "controller_id") && bounded (get source "label") 80
 | "controller_open"=>shape source ["type";"connection_id";"controller_id";"grant_epoch"] && identifier (get source "connection_id") && controller (get source "controller_id") && epoch source
 | "request"=>shape source ["type";"connection_id";"controller_id";"grant_epoch";"request"] && identifier (get source "connection_id") && controller (get source "controller_id") && epoch source && controller_request (get source "request")
 | "controller_close"=>shape source ["type";"connection_id"] && identifier (get source "connection_id")
 | "pong"=>shape source ["type"] | _=>false end.
Definition controller_frame source := match str source "type" with
 | "ready"=>shape source ["type";"version";"controller_id";"grant_epoch"] && version source && controller (get source "controller_id") && epoch source
 | "event"=>shape source ["type";"event"] && is_object (get source "event")
 | _=>response source end.
