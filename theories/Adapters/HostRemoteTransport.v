From Stdlib Require Import String List Bool NArith.
From Selvedge.Adapters Require Import Common.
From Selvedge.Foundation Require Import Schema.
From Selvedge.Host Require Import RemoteTransport.
From Selvedge.Kernel Require Import ModelDeclarations ModelResultDeclarations.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition state_packet s := match s with
 | Stopped g => ModelDeclarations.pack remote_stopped [!g!]
 | Connecting g tries => ModelDeclarations.pack remote_connecting [!g;tries!]
 | Negotiating g tries => ModelDeclarations.pack remote_negotiating [!g;tries!]
 | Online g last => ModelDeclarations.pack remote_online [!g;last!]
 | Retrying g tries deadline => ModelDeclarations.pack remote_retrying [!g;tries;deadline!]
 | AuthenticationFailed g => ModelDeclarations.pack remote_auth_failed [!g!] end.
Definition state_json s := ModelDeclarations.encode_packet (state_packet s).
Definition state_of := ModelDeclarations.decode_cases remote_state_decoders.
Definition action_packet action := match action with
 | Connect n => ModelDeclarations.pack remote_connect [!n!]
 | OpenSocket n => ModelDeclarations.pack remote_open [!n!]
 | RetryAt n deadline => ModelDeclarations.pack remote_retry [!n;deadline!]
 | HeartbeatAt n deadline => ModelDeclarations.pack remote_heartbeat [!n;deadline!]
 | MarkOnline n => ModelDeclarations.pack remote_mark_online [!n!]
 | Ping n => ModelDeclarations.pack remote_ping [!n!]
 | Retire => ModelDeclarations.pack remote_retire [!!]
 | MarkStopped => ModelDeclarations.pack remote_mark_stopped [!!]
 | MarkAuthenticationFailed => ModelDeclarations.pack remote_mark_auth_failed [!!] end.
Definition action_json action := ModelDeclarations.encode_packet (action_packet action).
Definition observation_of := ModelDeclarations.decode_cases remote_observation_decoders.
Definition settings_of source := Settings (num source "retry_base") (num source "retry_max")
 (num source "heartbeat") (num source "heartbeat_timeout").
Definition authorization_json s := ModelDeclarations.encode_packet
 (ModelDeclarations.pack (remote_authorization_declaration s) [!!]).
Definition authorization_of := ModelDeclarations.decode_cases remote_authorization_decoders.
Definition grant_action_json action := ModelDeclarations.encode_packet
 (ModelDeclarations.pack (remote_authorization_action_declaration action) [!!]).
Definition call operation source :=
 if String.eqb operation "control.remote.transport_initial" then success (state_json initial)
 else if String.eqb operation "control.remote.authorization_initial" then success (authorization_json FirstCheck)
 else if String.eqb operation "control.remote.authorization" then
   match authorization_of (get source "state") with None => type_error "Invalid remote authorization state"
   | Some state => let '(next,action) := authorize state (GrantChecked (boolean_field source "active")
       (boolean_field source "allowed") (num source "checked") (num source "current")) in
     success (JObject [("state",authorization_json next);("action",grant_action_json action)]) end
 else match state_of (get source "state") with
 | None => type_error "Invalid remote transport state"
 | Some state =>
   if String.eqb operation "control.remote.transport_running" then success (JBool (running state))
   else if String.eqb operation "control.remote.transport_current" then success (JBool (current state (num source "generation")))
   else if String.eqb operation "control.remote.transport" then
     match observation_of (get source "observation") with None => type_error "Invalid remote transport observation"
     | Some observation => let '(next,actions) := step (settings_of (get source "settings")) state observation in
       success (JObject [("state",state_json next);("actions",JArray (map action_json actions))]) end
   else type_error "Unknown remote transport operation"
 end.
