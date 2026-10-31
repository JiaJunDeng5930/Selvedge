From Stdlib Require Import String List Bool NArith.
From Selvedge.Adapters Require Import Common.
From Selvedge.Host Require Import Transaction.
Import ListNotations.
Open Scope string_scope.

Definition phase_name (p : phase) := match p with
| Idle => "idle" | KernelPending => "kernel_pending" | ReplayPending => "replay_pending"
| CommitPending => "commit_pending"
| Committed => "committed" | Retired => "retired" end.
Definition state_json (s : state) := JObject [("phase",JString (phase_name (current s)));
  ("generation",number (generation s))].
Definition phase_of (s : string) :=
  if String.eqb s "idle" then Some Idle else if String.eqb s "kernel_pending" then Some KernelPending
  else if String.eqb s "replay_pending" then Some ReplayPending
  else if String.eqb s "commit_pending" then Some CommitPending else if String.eqb s "committed" then Some Committed
  else if String.eqb s "retired" then Some Retired else None.
Definition state_of (source : json) :=
  match phase_of (str source "phase"), natural (get source "generation") with
  | Some p, Some g => Some (State p g) | _, _ => None end.
Definition observation_of (source : json) :=
  let kind := str source "kind" in
  if String.eqb kind "begin" then Some (Begin (boolean_field source "replay"))
  else if String.eqb kind "worker_result" then Some (WorkerResult (num source "generation") (boolean_field source "durable"))
  else if String.eqb kind "input_rejected" then Some (InputRejected (num source "generation"))
  else if String.eqb kind "worker_failed" then Some WorkerFailed
  else if String.eqb kind "commit_ack" then Some CommitAck
  else if String.eqb kind "commit_rejected" then Some CommitRejected
  else if String.eqb kind "commit_unknown" then Some CommitUnknown
  else if String.eqb kind "finish" then Some Finish
  else if String.eqb kind "close" then Some Close else None.
Definition primitive_json (p : primitive) :=
  match p with
  | Request g => JObject [("kind",JString "request");("generation",number g)]
  | Replay g => JObject [("kind",JString "replay");("generation",number g)]
  | _ => JObject [("kind",JString (match p with
      | Commit => "commit" | Publish => "publish" | Resolve => "resolve"
      | RejectDefinite => "reject_definite" | RejectUnknown => "reject_unknown"
      | Retire => "retire" | _ => "" end))] end.
Definition call (operation : string) (source : json) : json :=
  if String.eqb operation "control.transaction.initial" then success (state_json initial)
  else if String.eqb operation "control.transaction.step" then
    match state_of (get source "state"), observation_of (get source "observation") with
    | Some s, Some o => let '(next, effects) := step s o in success (JObject
        [("state",state_json next);("effects",JArray (map primitive_json effects))])
    | _, _ => type_error "Invalid transaction control state or observation" end
  else type_error "Unknown transaction control operation".
