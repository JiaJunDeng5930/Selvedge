From Stdlib Require Import String Bool NArith.
From Selvedge.Interaction Require Import Services Origin.
Open Scope string_scope.

(** A single generation and a phase replace three independently writable
    generation counters. A prepared document always belongs to that generation. *)
Inductive phase := AwaitingDocument | Prepared | Published
 | AwaitingPresentation | PreparedPresentation | Recovering (reason : string).
Record state := State {
  generation : N; current_phase : phase; namespace : string; sequence : N
}.
Definition initial namespace sequence := State 0 AwaitingDocument namespace sequence.
Definition fresh value := match current_phase value with
 |Published|AwaitingPresentation|PreparedPresentation=>true|_=>false end.
Definition admit requested value :=
  N.eqb requested (generation value) &&
  match current_phase value with
  |Prepared|AwaitingPresentation|PreparedPresentation|Published=>true|_=>false end.
Definition semantic_pending value := match current_phase value with
 |Published|AwaitingPresentation|PreparedPresentation=>false|_=>true end.
Definition advance value :=
  State (N.succ (generation value))
    (match current_phase value with Recovering reason=>Recovering reason|_=>AwaitingDocument end)
    (namespace value) (sequence value).
Definition present value := State (N.succ(generation value))
 (match current_phase value with Recovering reason=>Recovering reason
  |_=>if semantic_pending value then AwaitingDocument else AwaitingPresentation end)
 (namespace value) (sequence value).
Definition failed reason value := State (generation value) (Recovering reason) (namespace value) (sequence value).
Definition retry value := State (N.succ(generation value)) AwaitingDocument (namespace value) (sequence value).
Definition recovery_reason value := match current_phase value with Recovering reason=>Some reason|_=>None end.
(* DEFENSE: DOM work and its completion promises can finish after a newer
   semantic update. Only the currently requested generation may be prepared. *)
Definition document_ready requested value :=
  if N.eqb requested (generation value)
  then match current_phase value with
    | AwaitingDocument => State (generation value) Prepared (namespace value) (sequence value)
    | AwaitingPresentation => State (generation value) PreparedPresentation (namespace value) (sequence value)
    | _ => value
    end
  else value.
(* DEFENSE: a renderer promise can settle after a newer update or before that
   update has a document. Such a receipt must not publish the newer generation. *)
Definition publish requested value :=
  if N.eqb requested (generation value) then
    match current_phase value with
    | Prepared | PreparedPresentation => State (generation value) Published (namespace value) (sequence value)
    | _ => value
    end
  else value.
Definition observe namespace sequence value :=
  State (generation value) (current_phase value) namespace sequence.
Definition invalidate value := State (generation value)
  (match current_phase value with Recovering reason=>Recovering reason|_=>AwaitingDocument end) "" 0.
Definition refresh_needed source_namespace source_sequence sources_fresh connection value :=
  match source_namespace,source_sequence with
  |Some ns,Some seq => negb (Origin.valid_namespace (namespace value) &&
    String.eqb ns (namespace value) && N.leb seq (sequence value) && sources_fresh &&
    match connection with Services.ConnectionReady _ => true | _ => false end)
  |_,_ => true end.
Inductive snapshot_origin := Authentication | ExistingSession.
Definition admit_snapshot origin expected incoming incoming_sequence value :=
  Origin.valid_namespace incoming && String.eqb expected (namespace value) &&
  if String.eqb incoming (namespace value) then N.leb (sequence value) incoming_sequence
  else match origin with Authentication => true | ExistingSession => false end.
Definition admit_completion expected incoming value :=
  Origin.valid_namespace incoming && String.eqb expected (namespace value) &&
  String.eqb incoming (namespace value).
Definition install_snapshot incoming incoming_sequence value :=
  negb(String.eqb incoming(namespace value)) || N.ltb(sequence value)incoming_sequence.

(** Authentication can finish after another request has acquired the connection.
    Reuse the service's ticket, so a late snapshot cannot install its world before
    the owning authentication completion is checked. *)
Definition admit_authentication ticket connection expected incoming value :=
  Services.connection_active connection && Services.connection_matches ticket connection &&
  Origin.valid_namespace incoming && String.eqb expected (namespace value).
Definition admit_authenticated_snapshot ticket connection expected incoming incoming_sequence value :=
  admit_authentication ticket connection expected incoming value &&
    admit_snapshot Authentication expected incoming incoming_sequence value.

(** A command can refresh its admission snapshot after the event connection has
    failed. That refresh updates the world, not the observation of that connection.
    Conversely, an owned authentication restores freshness even when a newer
    command snapshot has already won the world cursor. *)
Definition snapshot_freshness (origin : snapshot_origin) (authenticated previous : bool) :=
  if authenticated then match origin with
    | Authentication => true | ExistingSession => previous end
  else previous.
