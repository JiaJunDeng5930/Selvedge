From Stdlib Require Import String List Bool NArith.
Import ListNotations.
Open Scope N_scope.

(** Transport observations contain clock readings and random samples, never
    assumptions about delivery. Only this controller chooses another attempt. *)
Record settings := Settings { retry_base : N; retry_max : N; heartbeat : N; heartbeat_timeout : N }.
Inductive state :=
| Stopped (generation : N)
| Connecting (generation attempt : N)
| Negotiating (generation attempt : N)
| Online (generation last_pong : N)
| Retrying (generation attempt deadline : N)
| AuthenticationFailed (generation : N).
Definition initial := Stopped 0.
Definition generation s := match s with
 | Stopped n | Connecting n _ | Negotiating n _ | Online n _ | Retrying n _ _ | AuthenticationFailed n => n end.
Definition running s := match s with Stopped _ | AuthenticationFailed _ => false | _ => true end.
Definition current s n := N.eqb (generation s) n && match s with
 | Connecting _ _ | Negotiating _ _ | Online _ _ => true | _ => false end.
Inductive observation :=
| Enable | Stop
| Probe (generation status now sample : N)
| Lost (generation now sample : N)
| Rejected (generation : N)
| Negotiated (generation now : N)
| Pong (generation now : N)
| Heartbeat (generation now sample : N)
| Retry (generation now : N).
Inductive action :=
| Connect (generation : N) | OpenSocket (generation : N)
| RetryAt (generation deadline : N) | HeartbeatAt (generation deadline : N)
| MarkOnline (generation : N) | Ping (generation : N)
| Retire | MarkStopped | MarkAuthenticationFailed.
Definition attempt s := match s with Connecting _ n | Negotiating _ n | Retrying _ n _ => n | _ => 0 end.
Definition retry_delay cfg tries sample :=
 let ceiling := N.min (retry_max cfg) (retry_base cfg * 2 ^ N.min tries 16) in
 N.max 1 (ceiling * (1000 + N.min sample 1000) / 2000).
Definition retry cfg s now sample :=
 let deadline := now + retry_delay cfg (attempt s) sample in
 (Retrying (generation s) (N.succ (attempt s)) deadline,
  [Retire;RetryAt (generation s) deadline]).
Definition step cfg s event : state * list action := match event with
 | Enable => if running s then (s,[]) else
   let n := N.succ (generation s) in (Connecting n 0,[Connect n])
 | Stop => (Stopped (N.succ (generation s)),[Retire;MarkStopped])
 | Retry n now => match s with Retrying g tries deadline =>
   if N.eqb g n && (deadline <=? now) then
     let next := N.succ g in (Connecting next tries,[Connect next]) else (s,[])
   | _ => (s,[]) end
 | _ =>
   let n := match event with Probe n _ _ _ | Lost n _ _ | Rejected n |
      Negotiated n _ | Pong n _ | Heartbeat n _ _ => n | _ => 0 end in
   if negb (current s n) then (s,[]) else
   match event with
   | Probe _ status now sample => match s with Connecting g tries =>
     if N.eqb status 401 || N.eqb status 403 || N.eqb status 404 then
       (AuthenticationFailed (N.succ g),[Retire;MarkAuthenticationFailed])
     else if N.eqb status 426 then (Negotiating g tries,[OpenSocket g])
     else retry cfg s now sample | _ => (s,[]) end
   | Rejected _ => (AuthenticationFailed (N.succ (generation s)),[Retire;MarkAuthenticationFailed])
   | Lost _ now sample => retry cfg s now sample
   | Negotiated _ now => match s with Negotiating g _ =>
     (Online g now,[MarkOnline g;HeartbeatAt g (now + heartbeat cfg)]) | _ => (s,[]) end
   | Pong _ now => match s with Online g _ => (Online g now,[]) | _ => (s,[]) end
   | Heartbeat _ now sample => match s with Online g last =>
     if heartbeat_timeout cfg <? now - last then retry cfg s now sample
     else (s,[Ping g;HeartbeatAt g (now + heartbeat cfg)]) | _ => (s,[]) end
   | _ => (s,[]) end
 end.

(** A capture may follow only the very observation whose sequence still equals
    the committed snapshot. Four constructors make the retry budget structural. *)
Inductive authorization := FirstCheck | SecondCheck | ThirdCheck | LastCheck
 | Authorized | Denied | RevisionChanged.
Inductive grant_observation := GrantChecked (active allowed : bool) (checked current : N).
Inductive grant_action := CheckAgain | Capture | Deny | Disconnect.
Definition authorize s event : authorization * grant_action :=
 match s with Authorized | Denied => (s,Deny) | RevisionChanged => (s,Disconnect)
 | _ => match event with GrantChecked active allowed checked current =>
   if negb active || negb allowed then (Denied,Deny)
   else if N.eqb checked current then (Authorized,Capture)
   else match s with FirstCheck => (SecondCheck,CheckAgain) | SecondCheck => (ThirdCheck,CheckAgain)
     | ThirdCheck => (LastCheck,CheckAgain) | _ => (RevisionChanged,Disconnect) end end end.

Theorem stale_transport_observation s cfg n now sample : current s n = false ->
 step cfg s (Lost n now sample) = (s,[]).
Proof. intros H; cbn; now rewrite H. Qed.
Theorem failed_authentication_stops cfg g tries status now sample :
 status = 401 \/ status = 403 \/ status = 404 ->
 running (fst (step cfg (Connecting g tries) (Probe g status now sample))) = false.
Proof.
 intros [H|[H|H]]; subst status; unfold step, current, generation;
 rewrite N.eqb_refl; reflexivity.
Qed.
Theorem last_changed_revision_disconnects checked current : N.eqb checked current = false ->
 authorize LastCheck (GrantChecked true true checked current) = (RevisionChanged,Disconnect).
Proof. intros H; cbn; now rewrite H. Qed.
Theorem capture_requires_current_revision s active allowed checked current :
 snd (authorize s (GrantChecked active allowed checked current)) = Capture ->
 active = true /\ allowed = true /\ checked = current.
Proof.
 destruct s; intros A; cbn in A; try discriminate;
 destruct active, allowed; cbn in A; try discriminate;
 destruct (N.eqb checked current) eqn:E; try discriminate;
 apply N.eqb_eq in E; auto.
Qed.
