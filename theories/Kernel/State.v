From Stdlib Require Import String List NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Programming Require Import RequestEnvelope.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Kernel Require Import Numbers Domain WorkspaceBackend ModelRequest.
From Selvedge.Features Require Import Domain CompactionTypes RequestTypes.
Import ListNotations.

Record world := World {
 world_sequence : N;
 world_tasks : list task;
 world_next_ticket : N;
 world_environment : environment;
 world_projects : list project;
 world_features : Selvedge.Features.Domain.state
}.
Definition initial := World 0 [] 0 empty_environment [] Selvedge.Features.Domain.initial.
Definition with_sequence (replacement : N) (value : world) :=
 set world_sequence (fun _ => replacement) value.
Definition with_tasks (replacement : list task) (value : world) :=
 set world_tasks (fun _ => replacement) value.
Definition with_ticket (replacement : N) (value : world) :=
 set world_next_ticket (fun _ => replacement) value.
Definition allocate_ticket (value : world) : N * world :=
 let ticket := world_next_ticket value in
 (ticket, with_ticket (N.succ ticket) value).
Definition with_environment (replacement : environment) (value : world) :=
 set world_environment (fun _ => replacement) value.
Definition with_projects (replacement : list project) (value : world) :=
 set world_projects (fun _ => replacement) value.
Definition with_features (replacement : Selvedge.Features.Domain.state) (value : world) :=
 set world_features (fun _ => replacement) value.
Definition find_task (id : N) (value : world) := registry_at id (world_tasks value).
Definition put_task (id : N) (replacement : task) (value : world) :=
 with_tasks (replace id replacement (world_tasks value)) value.
Definition next_task (value : world) := N.of_nat (List.length (world_tasks value)).
Definition append_task (task : task) (value : world) :=
 with_tasks (world_tasks value ++ [task]) value.
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
| ArchiveWorktree (task_id : N) (source_root root : string) (backend : WorkspaceBackend.backend)
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

Definition ignored (value : world) := accept (JObject [("ignored"%string,JBool true)]) value [].
