From Stdlib Require Import String List Bool NArith.
From Selvedge.Adapters Require Import Common.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Inductive connection_phase := Connecting | Waiting | Active | Ended.
Record connection_state := ConnectionState { attempt : N; phase : connection_phase }.
Inductive observation := Opened (generation : N) | UpgradeRejected (generation status : N)
  | SocketFailed (generation : N) (message : string) | SocketClosed (generation code : N)
  | ProviderMessage (generation : N) (raw : json) | RetryElapsed (generation : N) | Stop.
Inductive primitive := Connect (generation : N) | ScheduleRetry (generation delay : N)
  | OpenStream | StopStream (message : string) | Deliver (raw : json).
Definition initial := ConnectionState 0 Connecting.
Definition state_json (s : connection_state) := JObject [("attempt",number (attempt s));("phase",JString
  (match phase s with Connecting=>"connecting" | Waiting=>"waiting" | Active=>"active" | Ended=>"ended" end))].
Definition state_of (source : json) := ConnectionState (num source "attempt")
  (if String.eqb (str source "phase") "ended" then Ended else if String.eqb (str source "phase") "waiting" then Waiting
   else if String.eqb (str source "phase") "active" then Active else Connecting).
Definition primitive_json (effect : primitive) := match effect with
  | Connect generation => JObject [("type",JString "connect");("attempt",number generation)]
  | ScheduleRetry generation delay => JObject [("type",JString "retry");("attempt",number generation);("delay",number delay)]
  | OpenStream => JObject [("type",JString "open")]
  | StopStream message => JObject [("type",JString "stop");("message",JString message)]
  | Deliver raw => JObject [("type",JString "provider");("raw",raw)] end.
Definition observed_attempt (observed : observation) := match observed with
  | Opened n | UpgradeRejected n _ | SocketFailed n _ | SocketClosed n _ | ProviderMessage n _ | RetryElapsed n => n
  | Stop => 0 end.
Definition step (s : connection_state) (observed : observation) : connection_state * list primitive :=
  match observed with Stop => (ConnectionState (attempt s) Ended,[]) | _ =>
  if negb (N.eqb (attempt s) (observed_attempt observed)) then (s,[]) else match phase s with
  | Ended => (s,[])
  | Waiting => match observed with RetryElapsed _ =>
      let next := attempt s + 1 in (ConnectionState next Connecting,[Connect next]) | _ => (s,[]) end
  | Connecting => match observed with
    | Opened _ => (ConnectionState (attempt s) Active,[OpenStream])
    | UpgradeRejected _ status =>
      (* DEFENSE: Instant Connect returns 404 until Chrome ICE activates its call; the observed activation window permits three bounded retries. *)
      if N.eqb status 404 && (attempt s <? 3) then
        (ConnectionState (attempt s) Waiting,[ScheduleRetry (attempt s) (if N.eqb (attempt s) 0 then 100 else if N.eqb (attempt s) 1 then 300 else 800)])
      else (ConnectionState (attempt s) Ended,[StopStream ("ChatGPT voice control connection failed (HTTP " ++ decimal status ++ ")")])
    | SocketFailed _ message => (ConnectionState (attempt s) Ended,[StopStream message])
    | SocketClosed _ code => (ConnectionState (attempt s) Ended,[StopStream (if N.eqb code 1000 then ""
        else "ChatGPT voice control connection closed (" ++ decimal code ++ ")")])
    | _ => (s,[]) end
  | Active => match observed with
    | ProviderMessage _ raw => (s,[Deliver raw])
    | SocketFailed _ message => (ConnectionState (attempt s) Ended,[StopStream message])
    | SocketClosed _ code => (ConnectionState (attempt s) Ended,[StopStream (if N.eqb code 1000 then ""
        else "ChatGPT voice control connection closed (" ++ decimal code ++ ")")])
    | _ => (s,[]) end
  end end.
