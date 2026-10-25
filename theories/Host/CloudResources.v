From Stdlib Require Import String List Bool NArith.
From Selvedge.Adapters Require Import Common.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

(** Only immutable provisioning metadata crosses all phases. Mutable evidence is
    carried by the phase constructors and is projected into the durable receipt. *)
Record context := Context { metadata : json; destroyed : list string; recording_failed : bool }.
Inductive allocation := UnknownAllocation (confirmed candidates : list string) (ambiguous : bool)
  | KnownAllocation (instances : list string).
Record cleanup := Cleanup { cleanup_context : context; evidence : allocation; failures : list string }.
Inductive terminal := NoAttempt | Destroyed | DestroyFailed | NeedsCredential | NeedsReconcile | NeedsResolution.
Inductive state :=
  | Allocating (source : context)
  | Preparing (source : context) (instance : string)
  | Revalidating (source : context) (instance host : string) (guidance : json)
  | Ready (source : context) (instance : string) (host : string) (guidance : json)
  | Authorizing (source : cleanup)
  | Scanning (source : cleanup) (offset : N)
  | Terminating (source : cleanup)
  | Finished (source : cleanup) (outcome : terminal)
  | Persisting (next : state).
Inductive observation := Persisted | PersistenceFailed
  | Allocated (instances : list string) (complete : bool) | AllocationFailed
  | Prepared (host : string) (guidance : json) | PreparationFailed | Resume | CleanupRequested
  | Credentials (scope : json) | CredentialsFailed
  | ScanPage (instances : list json) (total : N) | ScanFailed
  | Terminated (instance : string) | TerminationFailed (instance : string).
Inductive action := Persist | Allocate | Prepare | CredentialsLookup | Scan | Terminate | Finish.
Definition action_name value := match value with Persist => "persist" | Allocate => "allocate" | Prepare => "prepare"
  | CredentialsLookup => "credentials" | Scan => "scan" | Terminate => "terminate" | Finish => "finish" end.
Definition terminal_name value := match value with NoAttempt => "no_attempt" | Destroyed => "destroyed"
  | DestroyFailed => "destroy_failed" | NeedsCredential => "needs_credential"
  | NeedsReconcile => "needs_reconcile" | NeedsResolution => "needs_resolution" end.
Definition texts (source : json) := fold_right (fun item rest => match item with
  | JString value => if String.eqb value "" then rest else value :: rest | _ => rest end) [] (items source).
Definition add_unique (values : list string) value := if existsb (String.eqb value) values then values else List.app values [value].
Definition merge values more := fold_left add_unique more values.
Definition nonempty {A} (values : list A) := negb (Nat.eqb (List.length values) 0).
Definition confirmed value := match value with UnknownAllocation values _ _ | KnownAllocation values => values end.
Definition candidates value := match value with UnknownAllocation _ values _ => values | KnownAllocation _ => [] end.
Definition unknown value := match value with UnknownAllocation _ _ _ => true | _ => false end.
Definition ambiguous value := match value with UnknownAllocation _ _ value => value | _ => false end.
Definition as_cleanup source instances := Cleanup source (KnownAllocation instances) [].
Fixpoint resources (value : state) : cleanup := match value with
  | Allocating source => Cleanup source (UnknownAllocation [] [] false) []
  | Preparing source instance | Revalidating source instance _ _ | Ready source instance _ _ => as_cleanup source [instance]
  | Authorizing source | Scanning source _ | Terminating source | Finished source _ => source
  | Persisting next => resources next end.
Definition with_recording_failure source := Context (metadata source) (destroyed source) true.
Definition mark_failed source := Cleanup (with_recording_failure (cleanup_context source)) (evidence source) (failures source).
Definition save value := (Persisting value, [Persist]).
Definition terminate_or_finish source :=
  if nonempty (confirmed (evidence source)) then save (Terminating source)
  else if nonempty (failures source) then save (Finished (Cleanup (cleanup_context source)
    (KnownAllocation (failures source)) (failures source)) DestroyFailed)
  else if ambiguous (evidence source) then save (Finished source NeedsResolution)
  else if unknown (evidence source) then save (Finished source NeedsReconcile)
  else save (Finished source Destroyed).
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
Definition scan_page source offset instances total :=
  let current := evidence source in
  let observed := texts (JArray (map (fun instance => get instance "InstanceId") instances)) in
  let accepted := texts (JArray (map (fun instance => get instance "InstanceId")
    (filter (owned (cleanup_context source)) instances))) in
  let known := merge (confirmed current) accepted in
  let seen := merge (candidates current) observed in
  let conflict := ambiguous current || existsb (fun instance => negb (owned (cleanup_context source) instance)) instances in
  let next_offset := offset + N.of_nat (List.length instances) in
  let source := Cleanup (cleanup_context source) (UnknownAllocation known seen conflict) (failures source) in
  if next_offset <? total then
    if nonempty instances then save (Scanning source next_offset) else terminate_or_finish source
  else
    let missing := existsb (fun id => negb (existsb (String.eqb id) known)) seen in
    let conflict := conflict || missing in
    terminate_or_finish (Cleanup (cleanup_context source)
      (if nonempty known && negb conflict then KnownAllocation known else UnknownAllocation known seen conflict) (failures source)).
Definition retire_instance source instance (failed : bool) :=
  let current := evidence source in
  let remaining := filter (fun value => negb (String.eqb value instance)) (confirmed current) in
  let next := match current with UnknownAllocation _ seen conflict => UnknownAllocation remaining seen conflict
    | KnownAllocation _ => KnownAllocation remaining end in
  let context := cleanup_context source in
  Cleanup (if failed then context else Context (metadata context) (add_unique (destroyed context) instance) (recording_failed context))
    next (if failed then add_unique (failures source) instance else failures source).
Definition run value : state * list action := match value with
  | Allocating _ => (value,[Allocate]) | Preparing _ _ | Revalidating _ _ _ _ => (value,[Prepare])
  | Authorizing _ => (value,[CredentialsLookup]) | Scanning _ _ => (value,[Scan])
  | Terminating _ => (value,[Terminate]) | Persisting _ => (value,[Persist])
  | Ready _ _ _ _ | Finished _ _ => (value,[Finish]) end.
Definition step (value : state) (observed : observation) : state * list action :=
  match value, observed with
  | Persisting next, Persisted => run next
  | Persisting (Allocating source), PersistenceFailed => (Finished (as_cleanup (with_recording_failure source) []) NoAttempt,[Finish])
  | Persisting (Preparing source instance), PersistenceFailed => (Authorizing (as_cleanup (with_recording_failure source) [instance]),[CredentialsLookup])
  | Persisting (Ready source instance _ _), PersistenceFailed => (Authorizing (as_cleanup (with_recording_failure source) [instance]),[CredentialsLookup])
  | Persisting next, PersistenceFailed => run (match next with
      | Authorizing source => Authorizing (mark_failed source) | Scanning source offset => Scanning (mark_failed source) offset
      | Terminating source => Terminating (mark_failed source) | Finished source outcome => Finished (mark_failed source) outcome
      | _ => next end)
  | Allocating source, Allocated [instance] true => save (Preparing source instance)
  | Allocating source, Allocated instances _ => save (Authorizing (Cleanup source (UnknownAllocation [] instances false) []))
  | Allocating source, AllocationFailed => save (Authorizing (Cleanup source (UnknownAllocation [] [] false) []))
  | Preparing source instance, Prepared host guidance | Revalidating source instance _ _, Prepared host guidance => save (Ready source instance host guidance)
  | Preparing source instance, PreparationFailed | Revalidating source instance _ _, PreparationFailed => save (Authorizing (as_cleanup source [instance]))
  | Ready source instance host guidance, Resume | Persisting (Ready source instance host guidance), Resume => (Revalidating source instance host guidance,[Prepare])
  | _, CleanupRequested => (Authorizing (resources value),[CredentialsLookup])
  | Authorizing source, Credentials scope =>
      if equal (get (metadata (cleanup_context source)) "scope") scope then
        if unknown (evidence source) then (Scanning source 0,[Scan]) else terminate_or_finish source
      else save (Finished source NeedsCredential)
  | Authorizing source, CredentialsFailed => save (Finished source NeedsCredential)
  | Scanning source offset, ScanPage instances total => scan_page source offset instances total
  | Scanning source _, ScanFailed => terminate_or_finish source
  | Terminating source, Terminated instance => terminate_or_finish (retire_instance source instance false)
  | Terminating source, TerminationFailed instance => terminate_or_finish (retire_instance source instance true)
  | _, _ => (value,[])
  end.

Definition policy_fields := ["controller_phase";"controller_persisting";"status";"continuation";"allocation_unknown";"instance_ids";"instance_id";"candidate_ids";
  "failed_ids";"destroyed_ids";"unresolved";"scan_offset";"recording_failed";"dispatch_count";"host";"guidance"].
Definition context_of source := Context (JObject (filter (fun field => negb (existsb (String.eqb (fst field)) policy_fields)) (object_fields source)))
  (texts (get source "destroyed_ids")) (boolean_field source "recording_failed").
Definition cleanup_of source := Cleanup (context_of source)
  (if boolean_field source "allocation_unknown" then UnknownAllocation (texts (get source "instance_ids"))
    (texts (get source "candidate_ids")) (boolean_field source "unresolved") else KnownAllocation (texts (get source "instance_ids")))
  (texts (get source "failed_ids")).
Fixpoint phase_name value := match value with
  | Allocating _ => "allocation_unknown" | Preparing _ _ | Revalidating _ _ _ _ => "preparing" | Ready _ _ _ _ => "ready"
  | Authorizing _ | Scanning _ _ | Terminating _ => "destroy_pending" | Finished _ outcome => terminal_name outcome
  | Persisting next => match next with Allocating _ => "persist_pending" | Preparing _ _ => "allocated"
    | Authorizing _ => "needs_reconcile" | _ => phase_name next end end.
Definition continuation value := match value with
  | Allocating _ => "allocate" | Preparing _ _ => "prepare" | Authorizing _ => "cleanup"
  | Scanning _ _ => "scan" | Terminating _ => "terminate" | _ => "finish" end.
Definition output_state value := match value with Persisting next => next | _ => value end.
Definition phase_tag value := match value with
  | Allocating _ => "allocate" | Preparing _ _ => "prepare" | Revalidating _ _ _ _ => "resume" | Ready _ _ _ _ => "ready"
  | Authorizing _ => "credentials" | Scanning _ _ => "scan" | Terminating _ => "terminate"
  | Finished _ outcome => terminal_name outcome | Persisting _ => "invalid" end.
Definition encode_state value :=
  let source := resources value in let context := cleanup_context source in let current := evidence source in
  let base := metadata context in
  let fields := [("controller_phase",JString (phase_tag (output_state value)));
    ("controller_persisting",JBool (match value with Persisting _ => true | _ => false end));("status",JString (phase_name value));("continuation",JString (match value with Persisting next => continuation next | _ => "" end));
    ("allocation_unknown",JBool (unknown current));("instance_ids",JArray (map JString (confirmed current)));
    ("candidate_ids",JArray (map JString (candidates current)));("unresolved",JBool (ambiguous current));
    ("failed_ids",JArray (map JString (failures source)));("destroyed_ids",JArray (map JString (destroyed context)));
    ("recording_failed",JBool (recording_failed context));("dispatch_count",number 1)] in
  let specific := match output_state value with
    | Preparing _ instance => [("instance_id",JString instance)]
    | Ready _ instance host guidance | Revalidating _ instance host guidance => [("instance_id",JString instance);("host",JString host);("guidance",guidance)]
    | Scanning _ offset => [("scan_offset",number offset)] | _ => [] end in
  JObject (List.app (object_fields base) (List.app fields specific)).
Definition encode_result result := let '(next, actions) := result in JObject [
  ("state",encode_state next);("effects",JArray (map (fun action => JString (action_name action)) actions))].
Definition decode_terminal name :=
  if String.eqb name "no_attempt" then Some NoAttempt else if String.eqb name "destroyed" then Some Destroyed
  else if String.eqb name "destroy_failed" then Some DestroyFailed else if String.eqb name "needs_credential" then Some NeedsCredential
  else if String.eqb name "needs_reconcile" then Some NeedsReconcile else if String.eqb name "needs_resolution" then Some NeedsResolution else None.
Definition nonempty_text source := match source with
  | JString value => if String.eqb value "" then None else Some value | _ => None end.
Definition instance_of source :=
  match nonempty_text (get source "instance_id"), texts (get source "instance_ids") with
  | Some instance, [known] => if String.eqb instance known && negb (boolean_field source "allocation_unknown")
      then Some instance else None
  | _, _ => None end.
Definition decode_active source name :=
  let context := context_of source in let cleanup := cleanup_of source in
  if String.eqb name "allocate" then Some (Allocating context)
  else if String.eqb name "prepare" then option_map (Preparing context) (instance_of source)
  else if String.eqb name "cleanup" then Some (Authorizing cleanup)
  else if String.eqb name "scan" then Some (Scanning cleanup (num source "scan_offset"))
  else if String.eqb name "terminate" then
    if nonempty (confirmed (evidence cleanup)) then Some (Terminating cleanup) else None
  else if String.eqb name "finish" then
    if String.eqb (str source "status") "ready" then match instance_of source, nonempty_text (get source "host") with
      Some instance, Some host => Some (Ready context instance host (get source "guidance")) | _, _ => None end
    else match decode_terminal (str source "status") with Some terminal => Some (Finished cleanup terminal) | None => None end
  else None.
Definition decode_state source :=
  let name := str source "controller_phase" in
  let context := context_of source in let cleanup := cleanup_of source in
  let parsed := if String.eqb name "ready" || String.eqb name "resume" then match instance_of source, nonempty_text (get source "host") with
    | Some instance, Some host => Some (if String.eqb name "ready" then Ready context instance host (get source "guidance")
      else Revalidating context instance host (get source "guidance")) | _, _ => None end
  else if String.eqb name "credentials" then Some (Authorizing cleanup)
  else match decode_terminal name with Some terminal => Some (Finished cleanup terminal)
    | None => decode_active source name end in
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
  else if String.eqb name "allocated" then Some (Allocated (texts (get source "ids")) (boolean_field source "complete"))
  else if String.eqb name "allocation_failed" then Some AllocationFailed
  else if String.eqb name "prepared" then option_map (fun host=>Prepared host (get source "guidance")) (nonempty_text (get source "host"))
  else if String.eqb name "preparation_failed" then Some PreparationFailed else if String.eqb name "resume" then Some Resume
  else if String.eqb name "cleanup" then Some CleanupRequested else if String.eqb name "credentials" then Some (Credentials (get source "scope"))
  else if String.eqb name "credentials_failed" then Some CredentialsFailed
  else if String.eqb name "scan_page" then Some (ScanPage (items (get source "instances")) (num source "total"))
  else if String.eqb name "scan_failed" then Some ScanFailed
  else if String.eqb name "terminated" then Some (Terminated (str source "id"))
  else if String.eqb name "termination_failed" then Some (TerminationFailed (str source "id")) else None.
Definition start receipt := encode_result (save (Allocating (context_of receipt))).
Definition recovery_state receipt :=
  let source := cleanup_of receipt in
  let current := evidence source in
  let merged := merge (confirmed current) (failures source) in
  let next := match current with UnknownAllocation _ candidates conflict => UnknownAllocation merged candidates conflict
    | KnownAllocation _ => KnownAllocation merged end in
  if String.eqb (str receipt "status") "destroyed" then Finished source Destroyed
    else Authorizing (Cleanup (cleanup_context source) next []).
Definition recover receipt := encode_result (run (recovery_state receipt)).
Definition call_step source observed := match decode_state source, decode_observation observed with
  | Some value, Some observation => Some (encode_result (step value observation))
  | _, _ => None end.

(** RUNNING precedes SSH readiness. Exit 255 permits another bounded probe;
    an image missing its required programs is a definite preparation failure. *)
Inductive ssh_state := SshProbing (deadline : N) | SshWaiting (deadline : N)
  | SshConnected | SshRejected (message : string).
Inductive ssh_observation := SshBegin (now : N) | SshProbeResult (now exit_code : N) (error : string) | SshWake (now : N).
Inductive ssh_action := Probe (timeout : N) | Delay (milliseconds : N) | Connected | Reject (message : string).
Definition deadline_message := "Cloud SSH startup deadline exceeded".
Definition ssh_probe deadline now := if deadline <=? now then (SshRejected deadline_message,[Reject deadline_message])
  else (SshProbing deadline,[Probe (N.min 15000 (deadline - now))]).
Definition ssh_step value observed := match value, observed with
  | SshProbing deadline, SshBegin now | SshWaiting deadline, SshWake now => ssh_probe deadline now
  | SshProbing deadline, SshProbeResult now code error =>
      if N.eqb code 0 then (SshConnected,[Connected]) else if N.eqb code 255 then
        if deadline <=? now then (SshRejected deadline_message,[Reject deadline_message])
        else (SshWaiting deadline,[Delay (N.min 2000 (deadline - now))])
      else let message := "Cloud image requires bash, git and setsid: " ++ error in (SshRejected message,[Reject message])
  | _, _ => (value,[]) end.
Definition ssh_state_json value := match value with
  | SshProbing deadline => JObject [("phase",JString "probe");("deadline",number deadline)]
  | SshWaiting deadline => JObject [("phase",JString "wait");("deadline",number deadline)]
  | SshConnected => JObject [("phase",JString "connected")]
  | SshRejected message => JObject [("phase",JString "rejected");("message",JString message)] end.
Definition ssh_action_json value := match value with
  | Probe timeout => JObject [("kind",JString "probe");("timeout",number timeout)]
  | Delay milliseconds => JObject [("kind",JString "delay");("milliseconds",number milliseconds)]
  | Connected => JObject [("kind",JString "connected")]
  | Reject message => JObject [("kind",JString "reject");("message",JString message)] end.
Definition ssh_call source :=
  let current := get source "state" in let observed := get source "observation" in
  let phase := str current "phase" in
  let state := if String.eqb phase "probe" then Some (SshProbing (num current "deadline"))
    else if String.eqb phase "wait" then Some (SshWaiting (num current "deadline"))
    else if String.eqb phase "connected" then Some SshConnected
    else if String.eqb phase "rejected" then Some (SshRejected (str current "message")) else None in
  let kind := str observed "kind" in
  let observation := if String.eqb kind "begin" then Some (SshBegin (num observed "now"))
    else if String.eqb kind "result" then Some (SshProbeResult (num observed "now") (num observed "exit_code") (str observed "stderr"))
    else if String.eqb kind "wake" then Some (SshWake (num observed "now")) else None in
  match state, observation with
  | Some value, Some event => let '(next, actions) := ssh_step value event in Some (JObject [
      ("state",ssh_state_json next);("actions",JArray (map ssh_action_json actions))])
  | _, _ => None end.
