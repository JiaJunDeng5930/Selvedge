From Stdlib Require Import String List Bool NArith.
From Selvedge.Adapters Require Import Common.
From Selvedge.Foundation Require Import Schema.
From Selvedge.Host Require Import RemoteTransport.
From Selvedge.Kernel Require Import ModelDeclarations ModelResultDeclarations.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition tagged field tag values := JObject ((field,JString tag)::values).
Definition declared declarations value := existsb (fun declaration =>
 equal (get value declaration.(ModelDeclarations.tag_field)) declaration.(ModelDeclarations.tag_value) &&
 match Schema.decode declaration.(ModelDeclarations.payload_fields)
   (without value declaration.(ModelDeclarations.tag_field)) with Some _ => true | None => false end) declarations.
Definition state_json s := let g := [("generation",number (generation s))] in match s with
 | Stopped _ => tagged "phase" "stopped" g
 | Connecting _ tries => tagged "phase" "connecting" (g++[("attempt",number tries)])
 | Negotiating _ tries => tagged "phase" "negotiating" (g++[("attempt",number tries)])
 | Online _ last => tagged "phase" "online" (g++[("last_pong",number last)])
 | Retrying _ tries deadline => tagged "phase" "retrying" (g++[("attempt",number tries);("deadline",number deadline)])
 | AuthenticationFailed _ => tagged "phase" "auth_failed" g end.
Definition state_of source :=
 if negb (declared remote_transport_states source) then None else
 let g := num source "generation" in let tries := num source "attempt" in
 let phase := str source "phase" in
 if String.eqb phase "stopped" then Some (Stopped g)
 else if String.eqb phase "connecting" then Some (Connecting g tries)
 else if String.eqb phase "negotiating" then Some (Negotiating g tries)
 else if String.eqb phase "online" then Some (Online g (num source "last_pong"))
 else if String.eqb phase "retrying" then Some (Retrying g tries (num source "deadline"))
 else Some (AuthenticationFailed g).
Definition action_json action := let g := fun n => [("generation",number n)] in match action with
 | Connect n => tagged "kind" "connect" (g n)
 | OpenSocket n => tagged "kind" "open" (g n)
 | RetryAt n deadline => tagged "kind" "retry" (g n++[("deadline",number deadline)])
 | HeartbeatAt n deadline => tagged "kind" "heartbeat" (g n++[("deadline",number deadline)])
 | MarkOnline n => tagged "kind" "online" (g n)
 | Ping n => tagged "kind" "ping" (g n)
 | Retire => tagged "kind" "retire" []
 | MarkStopped => tagged "kind" "stopped" []
 | MarkAuthenticationFailed => tagged "kind" "auth_failed" [] end.
Definition observation_of source :=
 if negb (declared remote_transport_observations source) then None else
 let kind := str source "kind" in let n := num source "generation" in
 let now := num source "now" in let sample := num source "sample" in
 if String.eqb kind "enable" then Some Enable
 else if String.eqb kind "stop" then Some Stop
 else if String.eqb kind "probe" then Some (Probe n (num source "status") now sample)
 else if String.eqb kind "lost" then Some (Lost n now sample)
 else if String.eqb kind "rejected" then Some (Rejected n)
 else if String.eqb kind "negotiated" then Some (Negotiated n now)
 else if String.eqb kind "pong" then Some (Pong n now)
 else if String.eqb kind "heartbeat" then Some (Heartbeat n now sample)
 else Some (Retry n now).
Definition settings_of source := Settings (num source "retry_base") (num source "retry_max")
 (num source "heartbeat") (num source "heartbeat_timeout").
Definition authorization_json s := tagged "phase" (match s with
 | FirstCheck => "first" | SecondCheck => "second" | ThirdCheck => "third" | LastCheck => "last"
 | Authorized => "authorized" | Denied => "denied" | RevisionChanged => "revision_changed" end) [].
Definition authorization_of source :=
 if negb (declared remote_authorization_states source) then None else
 let phase := str source "phase" in
 if String.eqb phase "first" then Some FirstCheck else if String.eqb phase "second" then Some SecondCheck
 else if String.eqb phase "third" then Some ThirdCheck else if String.eqb phase "last" then Some LastCheck
 else if String.eqb phase "authorized" then Some Authorized else if String.eqb phase "denied" then Some Denied
 else Some RevisionChanged.
Definition grant_action_json action := tagged "kind" (match action with
 | CheckAgain => "check" | Capture => "capture" | Deny => "deny" | Disconnect => "disconnect" end) [].
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
