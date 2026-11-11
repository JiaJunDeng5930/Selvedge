From Stdlib Require Import String Bool NArith.
From Selvedge.Browser.Session Require Import Services.
From Selvedge.Interaction Require Import Origin.
Open Scope string_scope.

(** Requested work, committed native controls, and the published source prefix
    have different lifetimes. The synchronous DOM receipt authorizes ordinary
    controls. Authored controls also need the asynchronous prefix receipt. *)
Inductive phase := AwaitingDocument | Prepared | Published
 | AwaitingPresentation | PreparedPresentation | Recovering (reason : string).
Record state := State {
 generation : N; current_phase : phase; namespace : string; sequence : N;
 displayed_generation : option N; native_displayed_generation : option N
}.
Definition initial namespace sequence := State 0 AwaitingDocument namespace sequence None None.
Definition fresh value := match displayed_generation value with Some _=>true|None=>false end.
Definition admit requested value := match displayed_generation value with
 |Some displayed=>N.eqb requested displayed|None=>false end.
Definition native_fresh value := match native_displayed_generation value with Some _=>true|None=>false end.
Definition native_admit requested value := match native_displayed_generation value with
 |Some displayed=>N.eqb requested displayed|None=>false end.
Definition semantic_pending value := match current_phase value with
 |Published|AwaitingPresentation|PreparedPresentation=>false|_=>true end.
Definition advance value :=
 State (N.succ(generation value))
   (match current_phase value with Recovering reason=>Recovering reason|_=>AwaitingDocument end)
   (namespace value)(sequence value)(displayed_generation value)(native_displayed_generation value).
Definition present value := State (N.succ(generation value))
 (match current_phase value with Recovering reason=>Recovering reason
  |_=>if semantic_pending value then AwaitingDocument else AwaitingPresentation end)
 (namespace value)(sequence value)(displayed_generation value)(native_displayed_generation value).
Definition failed reason value := State(generation value)(Recovering reason)(namespace value)(sequence value)None None.
Definition retry value := State(N.succ(generation value))AwaitingDocument(namespace value)(sequence value)None None.
Definition recovery_reason value := match current_phase value with Recovering reason=>Some reason|_=>None end.
(* DEFENSE: A stale DOM receipt cannot install a new basis for input. Committing
   current native controls retires the preceding DOM and its prefix receipt. *)
Definition document_ready requested value :=
 if N.eqb requested(generation value)then match current_phase value with
 |AwaitingDocument=>State(generation value)Prepared(namespace value)(sequence value)None(Some requested)
 |AwaitingPresentation=>State(generation value)PreparedPresentation(namespace value)(sequence value)None(Some requested)
 |_=>value end else value.
(* DEFENSE: A renderer receipt can settle after another request replaced its DOM. *)
Definition publish requested value :=
 if N.eqb requested(generation value)then match current_phase value with
 |Prepared|PreparedPresentation=>State(generation value)Published(namespace value)(sequence value)(Some requested)(native_displayed_generation value)
 |_=>value end else value.
Definition replace_source observed_namespace observed_sequence value :=
 State(N.succ(generation value))
  (match current_phase value with Recovering reason=>Recovering reason|_=>AwaitingDocument end)
  observed_namespace observed_sequence None None.
Definition observe observed_namespace observed_sequence value :=
 if String.eqb observed_namespace(namespace value)then
 State(generation value)(current_phase value)observed_namespace observed_sequence
   (displayed_generation value)(native_displayed_generation value)
 else replace_source observed_namespace observed_sequence value.
Definition invalidate value := replace_source "" 0 value.
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

(** A failure belongs to the request's source cursor and connection. A command
    may install a newer snapshot while an older state read or SSE open waits. *)
Definition admit_request_failure expected expected_sequence ticket connection value :=
  String.eqb expected (namespace value) && N.eqb expected_sequence (sequence value) &&
  Services.connection_active connection && Services.connection_matches ticket connection.
Definition pending value := match current_phase value with Published=>false|_=>true end.
