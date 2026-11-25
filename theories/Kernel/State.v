From Stdlib Require Import String List NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Foundation Require IndexedRegistry IndexedRegistryProofs.
From Selvedge.Programming Require Import RequestEnvelope.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Kernel Require Import Numbers Domain WorkspaceBackend ModelRequest.
From Selvedge.Kernel Require TaskRegistry.
From Selvedge.Features Require Import Domain CompactionTypes.
From Selvedge.Features Require State.
From Selvedge.Programming Require Import RequestTypes.
Import ListNotations.

Record world := World {
 world_sequence : N;
 world_task_registry : TaskRegistry.t;
 world_next_ticket : N;
 world_environment : environment;
 world_projects : list project;
 world_features : Selvedge.Features.Domain.state
}.
Definition initial := World 0 TaskRegistry.empty 0 empty_environment [] Selvedge.Features.Domain.initial.
Definition task_rows (value : world) := TaskRegistry.rows (world_task_registry value).
Definition world_tasks (value : world) := IndexedRegistry.contents (task_rows value).
Definition scheduling_tasks (value : world) :=
 TaskRegistry.selected_entries (TaskRegistry.scheduling (world_task_registry value)).
Definition side_tasks (value : world) :=
 TaskRegistry.selected_entries (TaskRegistry.side_conversations (world_task_registry value)).
Definition plugin_tasks (value : world) :=
 TaskRegistry.selected_entries (TaskRegistry.notification_recipients (world_task_registry value)).
Definition title_tasks (value : world) :=
 TaskRegistry.selected_entries (TaskRegistry.title_requests (world_task_registry value)).
Definition with_sequence (replacement : N) (value : world) :=
 set world_sequence (fun _ => replacement) value.
Definition with_task_registry (replacement : TaskRegistry.t) (value : world) :=
 set world_task_registry (fun _ => replacement) value.
Definition with_tasks (replacement : list task) (value : world) :=
 with_task_registry (TaskRegistry.extend replacement
   (TaskRegistry.empty_with_issued_titles (TaskRegistry.issued_titles (world_task_registry value)))) value.
Definition mark_title_started id value :=
 with_task_registry (TaskRegistry.title_started id (world_task_registry value)) value.
Definition restore_title_scope value :=
 IndexedRegistry.Slots.fold (fun address _ current => mark_title_started (N.pred (N.pos address)) current)
  (Selvedge.Features.Domain.feature_titles (world_features value)) value.
Definition with_ticket (replacement : N) (value : world) :=
 set world_next_ticket (fun _ => replacement) value.
Definition with_environment (replacement : environment) (value : world) :=
 set world_environment (fun _ => replacement) value.
Definition with_projects (replacement : list project) (value : world) :=
 set world_projects (fun _ => replacement) value.
Definition with_features (replacement : Selvedge.Features.Domain.state) (value : world) :=
 set world_features (fun _ => replacement) value.
Inductive identity_space := TaskTicket | ConnectionIdentity.
Definition next_identity (space : identity_space) (before : world) :=
 match space with
 | TaskTicket => world_next_ticket before
 | ConnectionIdentity => Selvedge.Features.Domain.sharing_next
     (Selvedge.Features.Domain.feature_sharing (world_features before)) end.
Definition allocate_identity (space : identity_space) (before : world) : N * world :=
 let identity := next_identity space before in
 (identity, match space with
 | TaskTicket => with_ticket (N.succ identity) before
 | ConnectionIdentity => with_features
   (Selvedge.Features.State.with_sharing
     (set Selvedge.Features.Domain.sharing_next (fun _ => N.succ identity)
       (Selvedge.Features.Domain.feature_sharing (world_features before)))
     (world_features before)) before end).

Definition find_task (id : N) (value : world) := IndexedRegistry.lookup id (task_rows value).
Definition put_task (id : N) (replacement : task) (value : world) :=
 with_task_registry (TaskRegistry.replace_if_present id replacement (world_task_registry value)) value.
Definition next_task (value : world) := IndexedRegistry.next (task_rows value).
Definition append_task (task : task) (value : world) :=
 with_task_registry (TaskRegistry.append task (world_task_registry value)) value.
Definition append_tasks (tasks : list task) (value : world) :=
 with_task_registry (TaskRegistry.extend tasks (world_task_registry value)) value.

Lemma find_task_as_list id value :
 find_task id value = registry_at id (world_tasks value).
Proof. symmetry; apply IndexedRegistryProofs.contents_lookup. Qed.
Lemma next_task_as_list value :
 next_task value = N.of_nat (List.length (world_tasks value)).
Proof. symmetry; apply IndexedRegistryProofs.contents_length. Qed.
Lemma world_tasks_replaced tasks value : world_tasks (with_tasks tasks value) = tasks.
Proof.
 change (IndexedRegistry.contents (TaskRegistry.rows (TaskRegistry.extend tasks
   (TaskRegistry.empty_with_issued_titles (TaskRegistry.issued_titles (world_task_registry value))))) = tasks).
 rewrite TaskRegistry.rows_extend. apply IndexedRegistryProofs.contents_from_list.
Qed.
Lemma world_tasks_updated id task value :
 world_tasks (put_task id task value) = replace id task (world_tasks value).
Proof.
 change (IndexedRegistry.contents (TaskRegistry.rows (TaskRegistry.replace_if_present id task (world_task_registry value))) =
   replace id task (world_tasks value)).
 rewrite TaskRegistry.rows_replace. apply IndexedRegistryProofs.contents_put.
Qed.
Lemma world_tasks_appended task value :
 world_tasks (append_task task value) = world_tasks value ++ [task].
Proof. apply IndexedRegistryProofs.contents_append. Qed.
Lemma world_tasks_extended tasks value :
 world_tasks (append_tasks tasks value) = world_tasks value ++ tasks.
Proof.
 change (IndexedRegistry.contents (TaskRegistry.rows (TaskRegistry.extend tasks (world_task_registry value))) =
   world_tasks value ++ tasks).
 rewrite TaskRegistry.rows_extend. apply IndexedRegistryProofs.fold_append_contents.
Qed.
Inductive execution_access := DefaultAccess | ElevatedAccess.
Inductive effect :=
| ObserveContext (task_id ticket : N) (task : task)
| RequestModel (request : ModelRequest.t)
| RequestReasoning (task_id ticket : N) (task : task)
| ExecuteTool (task_id ticket operation_id : N) (tool : tool) (call : call) (settings : task_settings) (access : execution_access)
| RequestApproval (task_id ticket : N) (profile : profile) (call : call) (task : task)
| CheckTool (task_id ticket : N) (plugin : json) (tool : tool) (call : call)
| CheckResult (task_id ticket operation_id : N) (plugin : json) (call : call) (value : json) (error : bool)
| ResetModelSession (task_id : N)
| CancelTask (task_id : N)
| CancelTicket (task_id ticket : N)
| ContinueScheduling
| CreateWorktree (task_id : N) (source_root : string) (workspace : workspace) (backend : WorkspaceBackend.backend)
| ArchiveWorktree (task_id : N) (source_root root : string) (backend : WorkspaceBackend.backend) (environment : option string)
| RequestFeature (request : RequestTypes.packet)
| CancelConnectionJob (operation_id : N)
| MaintainContext (request : Selvedge.Features.CompactionTypes.effect).

Record decision := Decision {
 decision_world : world;
 decision_reply : json;
 decision_effects : list effect
}.
Definition success (value : json) := JObject [("ok"%string, JBool true); ("result"%string, value)].
Definition failure (code reason : string) := JObject [("ok"%string,JBool false);
 ("error"%string,JObject [("code"%string,JString code);("message"%string,JString reason)])].
Definition reject (code reason : string) (value : world) :=
 Decision value (failure code reason) [].
Definition accept (result : json) (value : world) (effects : list effect) :=
 Decision value (success result) effects.

Definition ignored (value : world) := accept JNull value [].
