From Stdlib Require Import String Bool NArith.
From Selvedge.Interaction Require Import Services.
Open Scope string_scope.

(** A single generation and a phase replace three independently writable
    generation counters. A prepared document always belongs to that generation. *)
Inductive phase := AwaitingDocument | Prepared | Published.
Record state := State {
  generation : N; current_phase : phase; namespace : string; sequence : N
}.
Definition initial namespace sequence := State 0 AwaitingDocument namespace sequence.
Definition fresh value := match current_phase value with Published => true | _ => false end.
Definition admit requested value :=
  N.eqb requested (generation value) &&
  match current_phase value with AwaitingDocument => false | _ => true end.
Definition advance value :=
  State (N.succ (generation value)) AwaitingDocument (namespace value) (sequence value).
(* DEFENSE: DOM work and its completion promises can finish after a newer
   semantic update. Only the currently requested generation may be prepared. *)
Definition document_ready requested value :=
  if N.eqb requested (generation value)
  then match current_phase value with
    | AwaitingDocument => State (generation value) Prepared (namespace value) (sequence value)
    | _ => value
    end
  else value.
(* DEFENSE: a renderer promise can settle after a newer update or before that
   update has a document. Such a receipt must not publish the newer generation. *)
Definition publish requested value :=
  if N.eqb requested (generation value) then
    match current_phase value with
    | Prepared => State (generation value) Published (namespace value) (sequence value)
    | _ => value
    end
  else value.
Definition observe namespace sequence value :=
  State (generation value) (current_phase value) namespace sequence.
Definition refresh_needed source_namespace source_sequence sources_fresh value :=
  negb (String.eqb source_namespace (namespace value) &&
    N.leb source_sequence (sequence value) && sources_fresh).
Inductive snapshot_origin := Authentication | ExistingSession.
Definition admit_snapshot origin expected incoming incoming_sequence value :=
  String.eqb expected (namespace value) &&
  if String.eqb incoming (namespace value) then N.leb (sequence value) incoming_sequence
  else match origin with Authentication => true | ExistingSession => false end.

(** Authentication can finish after another request has acquired the connection.
    Reuse the service's ticket, so a late snapshot cannot install its world before
    the owning authentication completion is checked. *)
Definition admit_authenticated_snapshot ticket connection expected incoming incoming_sequence value :=
  Services.connection_active connection && Services.connection_matches ticket connection &&
    admit_snapshot Authentication expected incoming incoming_sequence value.

(** A command can refresh its admission snapshot after the event connection has
    failed. That refresh updates the world, not the observation of that connection. *)
Definition snapshot_freshness (origin : snapshot_origin) (accepted previous : bool) :=
  if accepted then match origin with
    | Authentication => true | ExistingSession => previous end
  else previous.
