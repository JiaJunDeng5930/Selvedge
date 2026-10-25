From Stdlib Require Import String List Bool NArith.
From Selvedge.Adapters Require Import Common.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Inductive phase := NoAttempt | PersistPending | AllocationUnknown | KnownAllocation
  | Preparing | Ready | DestroyPending | DestroyFailed | NeedsCredential
  | NeedsReconcile | NeedsResolution | Destroyed.
Definition phase_name value := match value with
  | NoAttempt => "no_attempt" | PersistPending => "persist_pending"
  | AllocationUnknown => "allocation_unknown" | KnownAllocation => "allocated"
  | Preparing => "preparing" | Ready => "ready" | DestroyPending => "destroy_pending"
  | DestroyFailed => "destroy_failed" | NeedsCredential => "needs_credential"
  | NeedsReconcile => "needs_reconcile" | NeedsResolution => "needs_resolution"
  | Destroyed => "destroyed" end.
Inductive primitive := Persist | Allocate | Prepare | Credentials | Scan | Terminate | Finish | LocalCreate | LocalArchive | LocalObserve | LocalRemove.
Definition primitive_name value := match value with
  | Persist => "persist" | Allocate => "allocate" | Prepare => "prepare"
  | Credentials => "credentials" | Scan => "scan" | Terminate => "terminate" | Finish => "finish"
  | LocalCreate => "local_create" | LocalArchive => "local_archive"
  | LocalObserve => "local_observe" | LocalRemove => "local_remove" end.
Definition result state (effects : list primitive) := JObject [
  ("state",state);("effects",JArray (map (fun effect => JString (primitive_name effect)) effects))].
Definition status state value := set state "status" (JString (phase_name value)).
Definition continue state next := set state "continuation" (JString next).
Definition save state next := result (continue state next) [Persist].
Definition strings value := filter (fun item => is_text item && negb (String.eqb (text item) "")) (items value).
Definition add_unique values value := if existsb (equal value) values then values else List.app values [value].
Definition merge values more := fold_left add_unique more values.
Definition nonempty (values : list json) := negb (Nat.eqb (List.length values) 0).
Definition ids state := strings (get state "instance_ids").
Definition candidates state := strings (get state "candidate_ids").
Definition unknown state := boolean_field state "allocation_unknown".
Definition matching_tag state instance := existsb (fun tag =>
  String.eqb (str tag "Key") "selvedge-task" && equal (get tag "Value") (get state "token"))
  (items (get instance "Tags")).
Definition owned state instance :=
  let request := get state "request" in
  matching_tag state instance &&
  equal (get instance "ImageId") (get request "ImageId") &&
  equal (get instance "InstanceType") (get request "InstanceType") &&
  equal (get (get instance "Placement") "Zone") (get (get request "Placement") "Zone") &&
  equal (get (get instance "VirtualPrivateCloud") "VpcId") (get (get request "VirtualPrivateCloud") "VpcId") &&
  equal (get (get instance "VirtualPrivateCloud") "SubnetId") (get (get request "VirtualPrivateCloud") "SubnetId").
Definition unresolved state := boolean_field state "unresolved".
Definition cleanup state := result (status state DestroyPending) [Credentials].
Definition terminate_or_finish state :=
  if nonempty (ids state) then save (status state DestroyPending) "terminate"
  else if nonempty (strings (get state "failed_ids")) then
    save (set (status state DestroyFailed) "instance_ids" (get state "failed_ids")) "finish"
  else if unresolved state then save (status state NeedsResolution) "finish"
  else if unknown state then save (status state NeedsReconcile) "finish"
  else save (status state Destroyed) "finish".
Definition saved state :=
  let next := str state "continuation" in
  let state := continue state "" in
  if String.eqb next "allocate" then result (status state AllocationUnknown) [Allocate]
  else if String.eqb next "prepare" then result (status state Preparing) [Prepare]
  else if String.eqb next "cleanup" then cleanup state
  else if String.eqb next "scan" then result state [Scan]
  else if String.eqb next "terminate" then result state [Terminate]
  else if String.eqb next "local_create" then result state [LocalCreate]
  else if String.eqb next "local_archive" then result state [LocalArchive]
  else result state [Finish].
Definition recording_failure state :=
  let state := set state "recording_failed" (JBool true) in
  let next := str state "continuation" in
  if String.eqb next "allocate" || String.eqb next "local_create" then result (status state NoAttempt) [Finish]
  else if String.eqb next "local_archive" then result state [Finish]
  else if negb (String.eqb (str state "local_mode") "") then
    if String.eqb (str state "local_mode") "create" && String.eqb next "finish"
    then result state [LocalRemove] else result state [Finish]
  else if String.eqb next "prepare" ||
    (String.eqb next "finish" && String.eqb (str state "status") "ready")
  then cleanup state else saved state.
Definition start receipt := save
  (set (set (set (set (status receipt PersistPending) "dispatch_count" (number 1))
    "allocation_unknown" (JBool true)) "instance_ids" (JArray [])) "candidate_ids" (JArray [])) "allocate".
(** Recovery never dispatches Allocate, even when the last durable continuation was allocation. *)
Definition recover receipt :=
  if String.eqb (str receipt "status") "destroyed" then result receipt [Finish]
  else cleanup (set (set (continue receipt "") "instance_ids"
    (JArray (merge (ids receipt) (strings (get receipt "failed_ids"))))) "failed_ids" (JArray [])).
Definition scan_page state observation :=
  let instances := items (get observation "instances") in
  let observed := strings (JArray (map (fun instance => get instance "InstanceId") instances)) in
  let confirmed := strings (JArray (map (fun instance => get instance "InstanceId") (filter (owned state) instances))) in
  let state := set (set state "candidate_ids" (JArray (merge (candidates state) observed)))
    "instance_ids" (JArray (merge (ids state) confirmed)) in
  let ambiguous := existsb (fun instance => negb (owned state instance)) instances in
  let state := set state "unresolved" (JBool (unresolved state || ambiguous)) in
  let offset := num state "scan_offset" + N.of_nat (List.length instances) in
  if (offset <? num observation "total") && nonempty instances then
    save (set state "scan_offset" (number offset)) "scan"
  else if (offset <? num observation "total") then terminate_or_finish (set state "allocation_unknown" (JBool true))
  else
    let missing := existsb (fun id => negb (existsb (equal id) (ids state))) (candidates state) in
    let state := set state "unresolved" (JBool (unresolved state || missing)) in
    terminate_or_finish (set state "allocation_unknown"
      (JBool (negb (nonempty (ids state)) || unresolved state))).
Definition step state observation :=
  let kind := str observation "kind" in
  if String.eqb kind "persisted" then saved state
  else if String.eqb kind "persistence_failed" then recording_failure state
  else if String.eqb kind "allocated" then
    let values := strings (get observation "ids") in
    if Nat.eqb (List.length values) 1 && boolean_field observation "complete" then
      save (set (set (set (status state KnownAllocation) "instance_ids" (JArray values))
        "instance_id" (hd JNull values)) "allocation_unknown" (JBool false)) "prepare"
    else save (set (status state NeedsReconcile) "candidate_ids" (JArray (merge (candidates state) values))) "cleanup"
  else if String.eqb kind "allocation_failed" || String.eqb kind "preparation_failed"
    then save (status state NeedsReconcile) "cleanup"
  else if String.eqb kind "prepared" then
    save (set (set (status state Ready) "host" (get observation "host"))
      "guidance" (get observation "guidance")) "finish"
  else if String.eqb kind "resume" then result (status state Preparing) [Prepare]
  else if String.eqb kind "cleanup" then cleanup state
  else if String.eqb kind "credentials" then
    if equal (get state "scope") (get observation "scope") then
      if unknown state then result (set state "scan_offset" (number 0)) [Scan]
      else terminate_or_finish state
    else save (status state NeedsCredential) "finish"
  else if String.eqb kind "credentials_failed" then save (status state NeedsCredential) "finish"
  else if String.eqb kind "scan_page" then scan_page state observation
  else if String.eqb kind "scan_failed" then terminate_or_finish (set state "allocation_unknown" (JBool true))
  else if String.eqb kind "terminated" then
    terminate_or_finish (set (set state "instance_ids" (JArray (filter (fun id => negb (equal id (get observation "id"))) (ids state))))
      "destroyed_ids" (JArray (add_unique (strings (get state "destroyed_ids")) (get observation "id"))))
  else if String.eqb kind "termination_failed" then
    terminate_or_finish (set (set state "instance_ids" (JArray (filter (fun id => negb (equal id (get observation "id"))) (ids state))))
      "failed_ids" (JArray (add_unique (strings (get state "failed_ids")) (get observation "id"))))
  else if String.eqb kind "local_created" || String.eqb kind "local_archived" || String.eqb kind "local_observed" then
    let next := set (set (set state "root" (get observation "root")) "workspace" (get observation "workspace"))
      "guidance" (get observation "guidance") in
    save (set next "status" (get observation "status")) "finish"
  else if String.eqb kind "local_failed" then
    if boolean_field observation "reserved" then result (status state DestroyPending) [LocalRemove]
    else result state [Finish]
  else if String.eqb kind "local_removed" then result (status state NoAttempt) [Finish]
  else if String.eqb kind "local_remove_failed" then result (status state DestroyFailed) [Finish]
  else result state [Finish].

(** Local recovery observes existing receipts and Git registration; it never replays mutation. *)
Definition local (source : json) :=
  let operation := str source "operation" in
  let state := set (get source "receipt") "local_mode" (JString operation) in
  if String.eqb operation "recover" then
    if boolean_field source "creating" && negb (String.eqb (str state "status") "ready")
    then result (set state "recovery_failed" (JBool true)) [Finish]
    else result state [LocalObserve]
  else if String.eqb operation "create" then save (set state "status" (JString "creating")) "local_create"
  else if String.eqb (str state "status") "archived" then result state [Finish]
  else save (set state "status" (JString "archiving")) "local_archive".

Definition supplied_or (value fallback : json) := if is_null value then fallback else value.
Definition provider_request (source : json) :=
  let settings := get source "settings" in
  JObject [("InstanceChargeType",JString "SPOTPAID");("InstanceCount",number 1);("MinCount",number 1);
    ("Placement",JObject [("Zone",get settings "zone")]);("ImageId",get settings "image_id");
    ("InstanceType",get settings "instance_type");
    ("VirtualPrivateCloud",JObject [("VpcId",get settings "vpc_id");("SubnetId",get settings "subnet_id")]);
    ("InternetAccessible",JObject [("PublicIpAssigned",JBool (negb (String.eqb (str settings "address_type") "private")));
      ("InternetMaxBandwidthOut",supplied_or (get settings "internet_max_bandwidth_out") (number 5));
      ("InternetChargeType",JString "TRAFFIC_POSTPAID_BY_HOUR")]);
    ("SecurityGroupIds",get settings "security_group_ids");
    ("LoginSettings",JObject [("KeyIds",JArray [get settings "key_id"])]);
    ("InstanceName",JString ("selvedge-task-" ++ decimal (num source "task_id")));
    ("ClientToken",get source "token");
    ("InstanceMarketOptions",JObject [("MarketType",JString "spot");("SpotOptions",JObject [
      ("MaxPrice",get settings "spot_max_price");("SpotInstanceType",JString "one-time")])]);
    ("TagSpecification",JArray [JObject [("ResourceType",JString "instance");("Tags",JArray [
      JObject [("Key",JString "selvedge-task");("Value",get source "token")]])]])].
Definition provider (source : json) :=
  let instance := get source "instance" in
  let state := str instance "InstanceState" in
  let expired := num source "deadline" <=? num source "now" in
  let action name := JObject [("action",JString name)] in
  if String.eqb (str source "operation") "ready" then
    if expired then action "timeout"
    else if String.eqb state "LAUNCH_FAILED" || String.eqb state "TERMINATED" then action "failed"
    else
      let addresses := items (get instance (if String.eqb (str (get source "settings") "address_type") "private"
        then "PrivateIpAddresses" else "PublicIpAddresses")) in
      if String.eqb state "RUNNING" && nonempty addresses
      then JObject [("action",JString "ready");("host",hd JNull addresses)]
      else action "wait"
  else if is_null instance || String.eqb state "TERMINATED" then action "done"
  else if expired then action "timeout"
  else if String.eqb (str source "operation") "destroy_before" then action "terminate"
  else action "wait".
