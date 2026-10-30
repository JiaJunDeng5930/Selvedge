From Stdlib Require Import String Ascii List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Foundation Require KeyedCollection.
From Selvedge.Kernel Require Import Domain Compaction ContextSelection.
Import ListNotations.
Open Scope N_scope.

Inductive reason := Background | Blocking | IdleMaintenance | Manual.
Record token_budget := TokenBudget { reserve_room : N; window_room : N }.
Definition reserve_tokens (value : token_budget) := Compaction.minimum_reserve + reserve_room value.
Definition window_tokens (value : token_budget) :=
 N.max Compaction.minimum_window (4 * reserve_tokens value) + window_room value.
Record target := Target {
 target_profile : ascii * string;
 target_budget : token_budget;
 target_cache_ttl : N;
 target_method : method
}.
Definition target_key (value : target) := let '(head, tail) := target_profile value in String head tail.
Module TargetEntries.
 Definition t := target.
 Definition key := string.
 Definition key_of := target_key.
 Definition key_eq_dec := String.string_dec.
End TargetEntries.
Module Targets := KeyedCollection.Make TargetEntries.
Record policy := Policy {
 policy_enabled : bool;
 policy_background : N;
 policy_blocking : N;
 policy_idle_lead : N;
 policy_target_collection : Targets.t;
 policy_thresholds : ((0 <? policy_background) && (policy_background <? policy_blocking) && (policy_blocking <=? 100)) = true
}.
Definition policy_targets value := Targets.values (policy_target_collection value).
Definition with_targets targets value := Policy (policy_enabled value) (policy_background value)
 (policy_blocking value) (policy_idle_lead value) targets (policy_thresholds value).
Definition initial_policy := Policy false 65 90 60000 Targets.empty eq_refl.

(* A lease owns the complete pure request input, including the catalog-dependent
   callable names. A later catalog change must not validate an earlier count. *)
Record capture := Capture {
 captured_history : list message;
 captured_profile : profile;
 captured_settings : task_settings;
 captured_tools : list tool;
 captured_callable : list string
}.
Inductive inspection_stage := InspectScope | InspectCount (scope : string).
Inductive measurement :=
| Unmeasured
| Measuring (ticket : N) (input : capture) (stage : inspection_stage)
| Measured (input : capture) (scope : string) (tokens : N) (budget : token_budget)
| Oversized (input : capture) (scope : string) (budget : token_budget)
| MeasurementFailed (input : capture).
Inductive job :=
| NoJob
| WaitingForResource (purpose : option reason)
| AwaitingContext (ticket : N) (purpose : option reason) (resume_model : bool)
| Resuming (input : capture) (purpose : reason)
| Preparing (ticket : N) (input : capture) (purpose : reason) (stage : inspection_stage)
| Compacting (ticket : N) (input : capture) (purpose : reason) (progress : compaction_state) (scope : string)
| Validating (ticket : N) (input : capture) (purpose : reason) (candidate : artifact)
    (preview : list message) (stage : inspection_stage).
Record entry := Entry {
 (* This is the actual completed workspace observation. It is not reconstructed
    from the existence of a compaction job or a current task snapshot. *)
 entry_observation : option capture;
 entry_measurement : measurement;
 entry_job : job;
 entry_useful : N;
 entry_maintained : N;
 entry_attempted : N;
 entry_last_activity : N;
 entry_cache_deadline : N;
 entry_cache_history : list message;
 entry_cache_scope : string
}.
Definition empty_entry := Entry None Unmeasured NoJob 0 0 0 0 0 [] ""%string.
Record state := MaintenanceState {
 maintenance_policy : policy;
 maintenance_entries : list (N * entry);
 maintenance_now : N;
 maintenance_timer : N
}.
Definition initial := MaintenanceState initial_policy [] 0 0.

Inductive effect :=
| Scope (task_id ticket : N) (input : capture)
| Measure (task_id ticket : N) (input : capture) (scope : string) (validating : bool)
| Compact (task_id ticket : N) (input : capture) (target : target) (progress : compaction_state) (scope : string)
| ArmClock (deadline : N)
| Cancel (task_id ticket : N).
Inductive inspection :=
| ScopeObserved (scope : string)
| InputMeasured (scope : string) (tokens : N) (budget : token_budget)
| InspectionFailed (message : string).
Inductive completion :=
| Configure (policy : policy) (now : N)
| Clock (now : N)
| Activity (task_id source_length now : N) (scope : string)
| MeasuredInput (task_id ticket : N) (outcome : inspection)
| Completed (task_id ticket : N) (value : json) (error : bool).
