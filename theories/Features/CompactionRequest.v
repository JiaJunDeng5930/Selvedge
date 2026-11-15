From Selvedge.Programming Require Variant.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json JsonObjects.
From Selvedge.Foundation Require Comparison.
From Selvedge.Programming Require Import OptionObservation Receiver Schema.
From Selvedge.Kernel Require Import Domain State Tasks.
From Selvedge.Programming Require Import TaskScope.
From Selvedge.Kernel Require Import Capabilities Codec ContextSelection.
From Selvedge.Kernel Require TicketedRequest.
From Selvedge.Programming Require Import FeatureRequest.
From Selvedge.Kernel Require Import CompactionPlan.
From Selvedge.Features Require Import State CompactionTypes CompactionCodec.
From Selvedge.Programming Require Import RequestTypes.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Module F := Selvedge.Features.Domain.
Module C := Selvedge.Features.CompactionTypes.
Module S := FeatureRequest.

Definition capture_task (current : task) (before : world) :=
 C.Capture (task_history current) (task_current_profile current) (task_current_settings current)
   (Capabilities.task_tools current) (Capabilities.callable current (world_environment before)).
Definition same_reasoning_policy (left right : reasoning_policy) :=
 match left, right with
 | FixedReasoning, FixedReasoning => true
 | AdaptivePolicy prior, AdaptivePolicy current =>
   String.eqb (reasoning_evaluator prior) (reasoning_evaluator current) &&
   Comparison.list String.eqb (reasoning_efforts prior) (reasoning_efforts current) &&
   String.eqb (reasoning_baseline prior) (reasoning_baseline current) &&
   (match reasoning_transport_mode prior, reasoning_transport_mode current with
    | RequestEffort, RequestEffort | ConfigurationUpdates, ConfigurationUpdates => true
    | _, _ => false end) &&
   N.eqb (reasoning_max_lease prior) (reasoning_max_lease current)
 | _, _ => false end.

Definition same_measurement_profile (left right : profile) :=
 JsonObjects.equivalent (profile_metadata left) (profile_metadata right) &&
 String.eqb (profile_key left) (profile_key right) &&
 String.eqb (profile_provider left) (profile_provider right) &&
 String.eqb (profile_model left) (profile_model right) &&
 String.eqb (profile_reasoning left) (profile_reasoning right) &&
 same_reasoning_policy (profile_policy left) (profile_policy right).

Definition same_settings (left right : task_settings) :=
 let a := settings_workspace left in
 let b := settings_workspace right in
 Comparison.list String.eqb (workspace_roots a) (workspace_roots b) &&
 Comparison.option String.eqb (workspace_primary a) (workspace_primary b) &&
 (match sandbox_access (settings_sandbox left), sandbox_access (settings_sandbox right) with
  | ReadOnly, ReadOnly | WorkspaceWrite, WorkspaceWrite => true | _, _ => false end) &&
 Bool.eqb (sandbox_network (settings_sandbox left)) (sandbox_network (settings_sandbox right)) &&
 (match settings_approval left, settings_approval right with
  | FullAccess, FullAccess | AskForApproval, AskForApproval => true
  | ReviewWith a, ReviewWith b => String.eqb (profile_key a) (profile_key b)
  | _, _ => false end) &&
 Comparison.option N.eqb (settings_project left) (settings_project right) &&
 Comparison.option N.eqb (settings_resource left) (settings_resource right) &&
 Guidance.same (settings_guidance left) (settings_guidance right) &&
 Bool.eqb (settings_worktree left) (settings_worktree right).

Definition same_description (input : C.capture) (current : task) (before : world) :=
 same_measurement_profile (C.captured_profile input) (task_current_profile current) &&
 same_settings (C.captured_settings input) (task_current_settings current) &&
 Comparison.list (same_tool JsonObjects.equivalent) (C.captured_tools input) (Capabilities.task_tools current) &&
 Comparison.list String.eqb (C.captured_callable input) (Capabilities.callable current (world_environment before)).
Definition capture_compatible (input : C.capture) (current : task) (before : world) :=
 same_description input current before && ContextSelection.history_extends (C.captured_history input) (task_history current).
Definition compaction_entry (owner : N) (before : world) :=
 option_map (@snd N C.entry) (find (fun pair => N.eqb owner (fst pair))
   (C.maintenance_entries (F.feature_compaction (world_features before)))).
(* A provider request consumes an observation from the actual registry. A
   caller's proposed entry or captured history cannot create that capability. *)
Definition maintenance_ready_from (input : C.capture) (current : task) (entry : C.entry) (before : world) :=
 (match task_lifecycle current with Running _ _ => true | _ => false end) &&
 TicketedRequest.Scoped.resources_available current before && capture_compatible input current before &&
 match C.entry_observation entry with
 | Some observed => capture_compatible observed current before &&
     ContextSelection.history_extends (C.captured_history observed) (C.captured_history input)
 | None => false end.
(** Inspection has one continuation. A validation candidate cannot occur
    without its compaction purpose, and every stage retains its complete input. *)
Inductive inspection_purpose := MeterOnly | PrepareFor (purpose : C.reason) | ValidateCandidate (candidate : C.validation).
Inductive maintenance_action :=
| InspectRequest (input : C.capture) (purpose : inspection_purpose) (stage : C.inspection_stage) (entry : C.entry)
| CompactRequest (input : C.compaction_input) (entry : C.entry).
Definition initial_purpose purpose := match purpose with None => MeterOnly | Some purpose => PrepareFor purpose end.
Definition ScopeRequest input purpose entry := InspectRequest input (initial_purpose purpose) C.InspectScope entry.
Definition ValidationScopeRequest input purpose candidate preview entry :=
 InspectRequest input (ValidateCandidate (C.Candidate purpose candidate preview)) C.InspectScope entry.
Definition MeasureRequest input purpose scope entry := InspectRequest input purpose (C.InspectCount scope) entry.
Definition maintenance_input request := match request with
 | InspectRequest input _ _ _ => input | CompactRequest input _ => C.compact_capture input end.
Definition request_entry request := match request with InspectRequest _ _ _ entry | CompactRequest _ entry => entry end.
Definition purpose_reason purpose := match purpose with
 | MeterOnly => None | PrepareFor purpose => Some purpose | ValidateCandidate candidate => Some (C.candidate_reason candidate) end.
Definition purpose_candidate purpose := match purpose with
 | ValidateCandidate candidate => Some (C.candidate_artifact candidate) | _ => None end.
Definition maintenance_waiting_entry request :=
 (match request with InspectRequest _ purpose _ _ => purpose_reason purpose
  | CompactRequest input _ => Some (C.compact_reason input) end, request_entry request).
Definition maintenance_replacement_ready request := match request with
 | InspectRequest _ MeterOnly _ _ | InspectRequest _ (PrepareFor _) _ _ => true
 | InspectRequest input (ValidateCandidate _) _ _ => ContextSelection.closed_prefix (C.captured_history input)
 | CompactRequest input _ => ContextSelection.closed_prefix (C.captured_history (C.compact_capture input)) end.
Record maintenance_reference (before : world) (owner : N) (request : maintenance_action) := MaintenanceReference {
 maintenance_current : task;
 maintenance_current_found : find_task owner before = Some maintenance_current;
 maintenance_previous : C.entry;
 maintenance_previous_found : compaction_entry owner before = Some maintenance_previous;
 maintenance_eligible : maintenance_ready_from (maintenance_input request) maintenance_current maintenance_previous before &&
   maintenance_replacement_ready request = true
}.
Arguments maintenance_current {before owner request}.
Arguments maintenance_current_found {before owner request}.
Arguments maintenance_previous {before owner request}.
Arguments maintenance_previous_found {before owner request}.
Arguments maintenance_eligible {before owner request}.
Definition boolean_admission (condition : bool) : option (condition = true) :=
 match Bool.bool_dec condition true with left evidence => Some evidence | right _ => None end.
Definition maintenance_observed owner request before current
 (Found : find_task owner before = Some current) entry
 (Stored : compaction_entry owner before = Some entry) : option (maintenance_reference before owner request) :=
 option_map (fun Eligible => MaintenanceReference before owner request current Found entry Stored Eligible)
   (boolean_admission (maintenance_ready_from (maintenance_input request) current entry before &&
     maintenance_replacement_ready request)).
Definition maintenance_selected owner request before current
 (Found : find_task owner before = Some current) : option (maintenance_reference before owner request) :=
 OptionObservation.observe (compaction_entry owner before)
   (fun entry Stored => maintenance_observed owner request before current Found entry Stored) (fun _ => None).
Definition compaction_entries owner (before : C.state) :=
 Receiver.At.field before C.maintenance_entries
   (Receiver.At.inject (@pair N C.entry owner)
     (Receiver.At.keyed (C.maintenance_entries before) (@fst N C.entry))).
Definition compaction_slot owner (before : F.state) :=
 Receiver.At.field before F.feature_compaction (compaction_entries owner (F.feature_compaction before)).
Definition put_compaction owner entry before :=
 S.install_feature (Receiver.path (compaction_slot owner (world_features before))) entry before.
Definition can_observe_maintenance (current : task) (before : world) :=
 TicketedRequest.Scoped.resources_available current before && match task_lifecycle current with
 | Running Idle _ | Running ReadyForModel _ => true | _ => false end.
Definition maintenance_prefix_ready (purpose : option C.reason) (history : list message) :=
 match purpose with None => true | Some _ => ContextSelection.closed_prefix history end.
Definition maintenance_context_ready (purpose : option C.reason) (current : task) (before : world) :=
 can_observe_maintenance current before && maintenance_prefix_ready purpose (task_history current).
Record maintenance_context_plan (before : world) := MaintenanceContextPlan {
 maintenance_context_target : task_reference before;
 maintenance_context_purpose : option C.reason;
 maintenance_context_entry : C.entry;
 maintenance_context_admitted : maintenance_context_ready maintenance_context_purpose
   (selected maintenance_context_target) before = true
}.
Arguments MaintenanceContextPlan {before}.
Arguments maintenance_context_target {before}.
Arguments maintenance_context_purpose {before}.
Arguments maintenance_context_entry {before}.
Definition maintenance_context_selected {before} (target : task_reference before) purpose entry
 : option (maintenance_context_plan before) :=
 option_map (fun admitted => MaintenanceContextPlan target purpose entry admitted)
   (boolean_admission (maintenance_context_ready purpose (selected target) before)).
Definition maintenance_observe {before} (request : maintenance_context_plan before) :=
 let target := maintenance_context_target request in
 let current := selected target in
 let '(ticket,allocated) := allocate_identity TaskTicket before in
 let resume_model := match task_activity current with ReadyForModel => true | _ => false end in
 let entry := set C.entry_observation (fun _ => None)
   (set C.entry_measurement (fun _ => C.Unmeasured)
    (set C.entry_job (fun _ => C.NoJob) (maintenance_context_entry request))) in
 accept JNull
  (put_compaction (owner target) entry
    (put_task (owner target) (with_activity (ObservingContext ticket (List.length (task_history current))
      (ForMaintenance (maintenance_context_purpose request) resume_model)) current) allocated))
  [ObserveContext (owner target) ticket current].
Definition purpose_data purpose : Type := match purpose with
 | MeterOnly => unit | PrepareFor _ => C.reason | ValidateCandidate _ => C.validation end.
Definition purpose_value purpose : purpose_data purpose := match purpose with
 | MeterOnly => tt | PrepareFor purpose => purpose | ValidateCandidate candidate => candidate end.
Definition counting_input purpose : purpose_data purpose -> C.capture -> C.capture := match purpose with
 | MeterOnly | PrepareFor _ => fun _ input => input
 | ValidateCandidate _ => fun candidate input =>
     set C.captured_history (fun _ => C.candidate_preview candidate) input end.
Definition payload request : Type := match request with
 | InspectRequest _ purpose _ _ => C.inspection_input (purpose_data purpose)
 | CompactRequest _ _ => C.compaction_input end.
Definition request_input request : payload request := match request with
 | InspectRequest input purpose stage _ => C.InspectInput input (purpose_value purpose) stage
 | CompactRequest input _ => input end.
Definition retained_entry request previous :=
 let base := set C.entry_observation (fun _ => C.entry_observation previous) (request_entry request) in
 match request with
 | InspectRequest _ (PrepareFor _) C.InspectScope _
 | InspectRequest _ (ValidateCandidate _) C.InspectScope _ => set C.entry_measurement (fun _ => C.Unmeasured) base
 | _ => base end.
Definition inspection_protocol {before} owner purpose stage
 (receiver : Receiver.located F.state (RequestEnvelope.t (C.inspection_input (purpose_data purpose))) before)
 : RequestTypes.located (C.inspection_input (purpose_data purpose)) before :=
 RequestTypes.task_bound (match stage with
 | C.InspectScope => RequestTypes.Protocol receiver ModelDeclarations.context_scope_request
     (fun input _ => CompactionCodec.scope_fields (C.inspection_capture input))
 | C.InspectCount scope => RequestTypes.Protocol receiver ModelDeclarations.context_measure_request
     (fun input _ => CompactionCodec.measure_fields owner
       (counting_input purpose (C.inspection_continuation input) (C.inspection_capture input)) scope)
 end).
Definition request_protocol owner features previous request : RequestTypes.located (payload request) features :=
 let base := retained_entry request previous in
 let slot := compaction_slot owner features in
 match request as request return RequestTypes.located (payload request) features with
 | InspectRequest _ MeterOnly stage _ => inspection_protocol owner MeterOnly stage
     (Receiver.At.in_record slot C.entry_measurement C.Measuring base)
 | InspectRequest _ (PrepareFor purpose) stage _ => inspection_protocol owner (PrepareFor purpose) stage
     (Receiver.At.in_record slot C.entry_job C.Preparing base)
 | InspectRequest _ (ValidateCandidate candidate) stage _ => inspection_protocol owner (ValidateCandidate candidate) stage
     (Receiver.At.in_record slot C.entry_job C.Validating base)
 | CompactRequest _ _ => RequestTypes.task_bound (RequestTypes.Protocol
     (Receiver.At.in_record slot C.entry_job C.Compacting base) ModelDeclarations.context_compaction_request
     (fun input _ => CompactionCodec.compact_fields (C.compact_capture input)
       (C.compact_scope input) (CompactionPlan.plan_json (C.compact_progress input))))
 end.
Definition channel owner request
 : S.feature_channel (fun before => maintenance_reference before owner request) (payload request) :=
 @S.FeatureChannel (fun before => maintenance_reference before owner request) (payload request)
   TaskTicket (fun _ _ => request_input request)
   (fun before selected => request_protocol owner (world_features before) (maintenance_previous selected) request).
Definition plan {before owner request} (selected : maintenance_reference before owner request) :=
 S.FeaturePlan (channel owner request) selected.
Definition maintenance_issue {before owner request} (selected : maintenance_reference before owner request) :=
 S.feature_issue (plan selected).
(** Sizing uses the same wire projection; it does not allocate or install a
    receiver. Only a resolved plan reaches the shared issue constructor. *)
Definition preview owner ticket request before :=
 RequestTypes.encode_packet
   (RequestTypes.Packet (RequestTypes.release (request_protocol owner (world_features before) (request_entry request) request))
     (RequestEnvelope.Envelope ticket (request_input request)))
   (world_features before).
Definition preview_json owner ticket request before := Variant.encode_packet (preview owner ticket request before).
