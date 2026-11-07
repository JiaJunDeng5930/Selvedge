From Stdlib Require Import String List Bool NArith.
From Selvedge.Adapters Require Import Common.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Record context := Context { metadata : json; recording_failed : bool }.
(** A task issues one allocation for one instance. An unknown result must be
    reconciled before cleanup; successful destruction leaves no pending identity. *)
Inductive allocation := UnknownAllocation | KnownAllocation (instance : option string).
Record cleanup := Cleanup { cleanup_context : context; evidence : allocation }.
Inductive terminal := NoAttempt | Destroyed | DestroyFailed | NeedsCredential | NeedsReconcile | NeedsResolution.
Inductive state :=
  | Allocating (source : context)
  | Preparing (source : context) (instance : string)
  | Revalidating (source : context) (instance host : string)
  | Ready (source : context) (instance host : string) (guidance : json)
  | Authorizing (source : cleanup)
  | Scanning (source : context)
  | Terminating (source : context) (instance : string)
  | Finished (source : cleanup) (outcome : terminal)
  | Persisting (next : state).
Inductive observation := Persisted | PersistenceFailed
  | Allocated (instance : string) | AllocationFailed
  | Prepared (host : string) (guidance : json) | PreparationFailed | Resume | CleanupRequested
  | Credentials (scope : json) | CredentialsFailed
  | ScanPage (instances : list json) (total : N) | ScanFailed
  | Terminated | TerminationFailed.
Inductive action := Persist | Allocate | Prepare | CredentialsLookup | Scan | Terminate | Finish.
Definition action_name value := match value with Persist => "persist" | Allocate => "allocate" | Prepare => "prepare"
  | CredentialsLookup => "credentials" | Scan => "scan" | Terminate => "terminate" | Finish => "finish" end.
Definition terminal_name value := match value with NoAttempt => "no_attempt" | Destroyed => "destroyed"
  | DestroyFailed => "destroy_failed" | NeedsCredential => "needs_credential"
  | NeedsReconcile => "needs_reconcile" | NeedsResolution => "needs_resolution" end.
Definition as_cleanup source instance := Cleanup source (KnownAllocation instance).
Fixpoint resources (value : state) : cleanup := match value with
  | Allocating source | Scanning source => Cleanup source UnknownAllocation
  | Preparing source instance | Revalidating source instance _ | Ready source instance _ _
  | Terminating source instance => as_cleanup source (Some instance)
  | Authorizing source | Finished source _ => source
  | Persisting next => resources next end.
Definition with_recording_failure source := Context (metadata source) true.
Definition mark_failed source := Cleanup (with_recording_failure (cleanup_context source)) (evidence source).
Definition save value := (Persisting value, [Persist]).
Definition terminate_or_finish source := match evidence source with
  | KnownAllocation (Some instance) => save (Terminating (cleanup_context source) instance)
  | KnownAllocation None => save (Finished source Destroyed)
  | UnknownAllocation => save (Finished source NeedsReconcile) end.
Definition matching_tag source instance := existsb (fun tag =>
  String.eqb (str tag "Key") "selvedge-task" && equal (get tag "Value") (get (metadata source) "token"))
  (items (get instance "Tags")).
Definition owned source instance :=
  let request := get (metadata source) "request" in
  matching_tag source instance && equal (get instance "ImageId") (get request "ImageId") &&
  equal (get instance "InstanceType") (get request "InstanceType") &&
  equal (get (get instance "Placement") "Zone") (get (get request "Placement") "Zone") &&
  equal (get (get instance "VirtualPrivateCloud") "VpcId") (get (get request "VirtualPrivateCloud") "VpcId") &&
  equal (get (get instance "VirtualPrivateCloud") "SubnetId") (get (get request "VirtualPrivateCloud") "SubnetId").
Definition scan_page source instances total :=
  match instances with
  | [instance] =>
      if N.eqb total 1 && owned source instance && is_text (get instance "InstanceId") &&
         negb (String.eqb (str instance "InstanceId") "")
      then save (Terminating source (str instance "InstanceId"))
      else save (Finished (Cleanup source UnknownAllocation) NeedsResolution)
  | [] => save (Finished (Cleanup source UnknownAllocation) NeedsReconcile)
  | _ => save (Finished (Cleanup source UnknownAllocation) NeedsResolution)
  end.
Definition run value : state * list action := match value with
  | Allocating _ => (value,[Allocate]) | Preparing _ _ | Revalidating _ _ _ => (value,[Prepare])
  | Authorizing _ => (value,[CredentialsLookup]) | Scanning _ => (value,[Scan])
  | Terminating _ _ => (value,[Terminate]) | Persisting _ => (value,[Persist])
  | Ready _ _ _ _ | Finished _ _ => (value,[Finish]) end.
Definition step (value : state) (observed : observation) : state * list action :=
  match value, observed with
  | Persisting next, Persisted => run next
  | Persisting (Allocating source), PersistenceFailed => (Finished (as_cleanup (with_recording_failure source) None) NoAttempt,[Finish])
  | Persisting (Preparing source instance), PersistenceFailed
  | Persisting (Ready source instance _ _), PersistenceFailed =>
      (Authorizing (as_cleanup (with_recording_failure source) (Some instance)),[CredentialsLookup])
  | Persisting next, PersistenceFailed => run (match next with
      | Authorizing source => Authorizing (mark_failed source)
      | Scanning source => Scanning (with_recording_failure source)
      | Terminating source instance => Terminating (with_recording_failure source) instance
      | Finished source outcome => Finished (mark_failed source) outcome
      | _ => next end)
  | Allocating source, Allocated instance => save (Preparing source instance)
  | Allocating source, AllocationFailed => save (Authorizing (Cleanup source UnknownAllocation))
  | Preparing source instance, Prepared host guidance | Revalidating source instance _, Prepared host guidance => save (Ready source instance host guidance)
  | Preparing source instance, PreparationFailed | Revalidating source instance _, PreparationFailed => save (Authorizing (as_cleanup source (Some instance)))
  | Ready source instance host _, Resume | Persisting (Ready source instance host _), Resume => (Revalidating source instance host,[Prepare])
  | _, CleanupRequested => (Authorizing (resources value),[CredentialsLookup])
  | Authorizing source, Credentials scope =>
      if equal (get (metadata (cleanup_context source)) "scope") scope then
        match evidence source with UnknownAllocation => (Scanning (cleanup_context source),[Scan])
        | _ => terminate_or_finish source end
      else save (Finished source NeedsCredential)
  | Authorizing source, CredentialsFailed => save (Finished source NeedsCredential)
  | Scanning source, ScanPage instances total => scan_page source instances total
  | Scanning source, ScanFailed => save (Finished (Cleanup source UnknownAllocation) NeedsReconcile)
  | Terminating source _, Terminated => save (Finished (as_cleanup source None) Destroyed)
  | Terminating source instance, TerminationFailed => save (Finished (as_cleanup source (Some instance)) DestroyFailed)
  | _, _ => (value,[])
  end.

Definition policy_fields := ["controller_phase";"controller_persisting";"status";"allocation_unknown";"instance_id";
  "recording_failed";"host";"guidance"].
Definition nonempty_text source := match source with
  | JString value => if String.eqb value "" then None else Some value | _ => None end.
Definition context_of source := Context (JObject (filter (fun field => negb (existsb (String.eqb (fst field)) policy_fields)) (object_fields source)))
  (boolean_field source "recording_failed").
Definition cleanup_of source := Cleanup (context_of source)
  (if boolean_field source "allocation_unknown" then UnknownAllocation
   else KnownAllocation (nonempty_text (get source "instance_id"))).
Fixpoint phase_name value := match value with
  | Allocating _ => "allocation_unknown" | Preparing _ _ | Revalidating _ _ _ => "preparing" | Ready _ _ _ _ => "ready"
  | Authorizing _ | Scanning _ | Terminating _ _ => "destroy_pending" | Finished _ outcome => terminal_name outcome
  | Persisting next => match next with Allocating _ => "persist_pending" | Preparing _ _ => "allocated"
    | Authorizing _ => "needs_reconcile" | _ => phase_name next end end.
Definition output_state value := match value with Persisting next => next | _ => value end.
Definition phase_tag value := match value with
  | Allocating _ => "allocate" | Preparing _ _ => "prepare" | Revalidating _ _ _ => "resume" | Ready _ _ _ _ => "ready"
  | Authorizing _ => "credentials" | Scanning _ => "scan" | Terminating _ _ => "terminate"
  | Finished _ outcome => terminal_name outcome | Persisting _ => "invalid" end.
Definition encode_state value :=
  let source := resources value in let context := cleanup_context source in let current := evidence source in
  let fields := [("controller_phase",JString (phase_tag (output_state value)));
    ("controller_persisting",JBool (match value with Persisting _ => true | _ => false end));
    ("status",JString (phase_name value));
    ("allocation_unknown",JBool (match current with UnknownAllocation => true | _ => false end));
    ("instance_id",match current with KnownAllocation (Some instance) => JString instance | _ => JNull end);
    ("recording_failed",JBool (recording_failed context))] in
  let specific := match output_state value with
    | Ready _ _ host guidance => [("host",JString host);("guidance",guidance)]
    | Revalidating _ _ host => [("host",JString host)]
    | _ => [] end in
  JObject (List.app (object_fields (metadata context)) (List.app fields specific)).
Definition encode_result result := let '(next, actions) := result in JObject [
  ("state",encode_state next);("effects",JArray (map (fun action => JString (action_name action)) actions))].
Definition decode_terminal name :=
  if String.eqb name "no_attempt" then Some NoAttempt else if String.eqb name "destroyed" then Some Destroyed
  else if String.eqb name "destroy_failed" then Some DestroyFailed else if String.eqb name "needs_credential" then Some NeedsCredential
  else if String.eqb name "needs_reconcile" then Some NeedsReconcile else if String.eqb name "needs_resolution" then Some NeedsResolution else None.
Definition decode_state source :=
  let name := str source "controller_phase" in
  let cleanup := cleanup_of source in let context := cleanup_context cleanup in
  let instance := match evidence cleanup with KnownAllocation value => value | UnknownAllocation => None end in
  let parsed := if String.eqb name "allocate" then Some (Allocating context)
  else if String.eqb name "prepare" then option_map (Preparing context) instance
  else if String.eqb name "scan" then Some (Scanning context)
  else if String.eqb name "terminate" then option_map (Terminating context) instance
  else if String.eqb name "ready" || String.eqb name "resume" then match instance, nonempty_text (get source "host") with
    | Some instance, Some host => Some (if String.eqb name "ready" then Ready context instance host (get source "guidance")
      else Revalidating context instance host) | _, _ => None end
  else if String.eqb name "credentials" then Some (Authorizing cleanup)
  else option_map (Finished cleanup) (decode_terminal name) in
  if boolean_field source "controller_persisting" then option_map Persisting parsed else parsed.
Definition durable_state value := without (without (encode_state value) "guidance") "recording_failed".
Definition receipt_state source := option_map durable_state (decode_state source).
Definition receipt_valid source := match decode_state source with
  | Some value => let canonical := durable_state value in
      forallb (fun name => equal (get source name) (get canonical name)) policy_fields
  | None => false end.
Definition decode_observation source :=
  let name := str source "kind" in
  if String.eqb name "persisted" then Some Persisted else if String.eqb name "persistence_failed" then Some PersistenceFailed
  else if String.eqb name "allocated" then match get source "ids" with
    | JArray [JString instance] => if negb (String.eqb instance "")
        then Some (Allocated instance) else Some AllocationFailed
    | _ => Some AllocationFailed end
  else if String.eqb name "allocation_failed" then Some AllocationFailed
  else if String.eqb name "prepared" then option_map (fun host=>Prepared host (get source "guidance")) (nonempty_text (get source "host"))
  else if String.eqb name "preparation_failed" then Some PreparationFailed else if String.eqb name "resume" then Some Resume
  else if String.eqb name "cleanup" then Some CleanupRequested else if String.eqb name "credentials" then Some (Credentials (get source "scope"))
  else if String.eqb name "credentials_failed" then Some CredentialsFailed
  else if String.eqb name "scan_page" then Some (ScanPage (items (get source "instances")) (num source "total"))
  else if String.eqb name "scan_failed" then Some ScanFailed
  else if String.eqb name "terminated" then Some Terminated
  else if String.eqb name "termination_failed" then Some TerminationFailed else None.
Definition start receipt := encode_result (save (Allocating (context_of receipt))).
Definition recovery_state receipt :=
  if String.eqb (str receipt "status") "destroyed" then Finished (cleanup_of receipt) Destroyed
  else Authorizing (cleanup_of receipt).
Definition recover receipt := encode_result (run (recovery_state receipt)).
Definition call_step source observed := match decode_state source, decode_observation observed with
  | Some value, Some observation => Some (encode_result (step value observation))
  | _, _ => None end.

(** RUNNING precedes SSH readiness. Exit 255 permits another bounded probe;
    an image missing its required programs is a definite preparation failure. *)
Inductive ssh_observation := SshCheck (now : N) | SshProbeResult (now exit_code : N) (error : string).
Inductive ssh_action := Probe (timeout : N) | Delay (milliseconds : N) | Connected | Reject (message : string).
Definition deadline_message := "Cloud SSH startup deadline exceeded".
Definition ssh_probe deadline now := if deadline <=? now then Reject deadline_message
  else Probe (N.min 15000 (deadline - now)).
Definition ssh_step deadline observed := match observed with
  | SshCheck now => ssh_probe deadline now
  | SshProbeResult now code error =>
      if N.eqb code 0 then Connected else if N.eqb code 255 then
        if deadline <=? now then Reject deadline_message
        else Delay (N.min 2000 (deadline - now))
      else Reject ("Cloud image requires bash, git and setsid: " ++ error) end.
Definition ssh_action_json value := match value with
  | Probe timeout => JObject [("kind",JString "probe");("timeout",number timeout)]
  | Delay milliseconds => JObject [("kind",JString "delay");("milliseconds",number milliseconds)]
  | Connected => JObject [("kind",JString "connected")]
  | Reject message => JObject [("kind",JString "reject");("message",JString message)] end.
Definition ssh_call source :=
  let observed := get source "observation" in
  let kind := str observed "kind" in
  let observation := if String.eqb kind "check" then Some (SshCheck (num observed "now"))
    else if String.eqb kind "result" then Some (SshProbeResult (num observed "now") (num observed "exit_code") (str observed "stderr"))
    else None in
  option_map (fun event => ssh_action_json (ssh_step (num source "deadline") event)) observation.
