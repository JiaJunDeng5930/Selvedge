From Selvedge.Programming Require Variant.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Adapters Require Import Common.
From Selvedge.Programming Require Import Schema.
From Selvedge.Host Require Import RemoteTransport.
From Selvedge.Kernel Require Import ModelResultDeclarations.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition state_packet s := match s with
 | Stopped g => Variant.pack remote_stopped [!g!]
 | Connecting g tries => Variant.pack remote_connecting [!g;tries!]
 | Negotiating g tries => Variant.pack remote_negotiating [!g;tries!]
 | Online g last => Variant.pack remote_online [!g;last!]
 | Retrying g tries deadline => Variant.pack remote_retrying [!g;tries;deadline!]
 | AuthenticationFailed g => Variant.pack remote_auth_failed [!g!] end.
Definition state_json s := Variant.encode_packet (state_packet s).
Definition state_of := Variant.decode_cases remote_state_decoders.
Definition action_packet action := match action with
 | Connect n => Variant.pack remote_connect [!n!]
 | OpenSocket n => Variant.pack remote_open [!n!]
 | RetryAt n deadline => Variant.pack remote_retry [!n;deadline!]
 | HeartbeatAt n deadline => Variant.pack remote_heartbeat [!n;deadline!]
 | Ping => Variant.pack remote_ping [!!]
 | Retire => Variant.pack remote_retire [!!]
 | MarkAuthenticationFailed => Variant.pack remote_mark_auth_failed [!!] end.
Definition action_json action := Variant.encode_packet (action_packet action).
Definition observation_of := Variant.decode_cases remote_observation_decoders.
Definition settings_of source := Settings (num source "retry_base") (num source "retry_max")
 (num source "heartbeat") (num source "heartbeat_timeout").
Definition call operation source :=
 if String.eqb operation "control.remote.transport_initial" then success (state_json initial)
 else match state_of (get source "state") with
 | None => type_error "Invalid remote transport state"
 | Some state =>
   if String.eqb operation "control.remote.transport_running" then success (JBool (running state))
   else if String.eqb operation "control.remote.transport" then
     match observation_of (get source "observation") with None => type_error "Invalid remote transport observation"
     | Some observation => let '(next,actions) := step (settings_of (get source "settings")) state observation in
       success (JObject [("state",state_json next);("actions",JArray (map action_json actions))]) end
   else type_error "Unknown remote transport operation"
 end.
