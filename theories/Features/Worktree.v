From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema Utf8.
From Selvedge.Kernel Require Import Numbers Domain State Codec Workspace Tasks CommandExecution.
From Selvedge.Generated Require Import Commands.
From Selvedge.Features Require Import Domain State Observation Work.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Definition lookup (id:N) (value:world) := find (fun tree=>N.eqb id (Selvedge.Features.Domain.worktree_task tree)) (Selvedge.Features.Domain.feature_worktrees (world_features value)).
Definition store (tree:Selvedge.Features.Domain.worktree) (value:world) := Selvedge.Kernel.State.with_features
 (Selvedge.Features.State.with_worktrees (tree::filter (fun previous=>negb (N.eqb (Selvedge.Features.Domain.worktree_task tree) (Selvedge.Features.Domain.worktree_task previous))) (Selvedge.Features.Domain.feature_worktrees (world_features value))) (world_features value)) value.
Definition primary (space:workspace) := match workspace_primary space with Some root=>root | None=>"" end.
Definition archived (task:task) := match task_lifecycle task with Archived=>true | _=>false end.
Definition inside (root path:string) := String.eqb root path || String.prefix (String.append root "/") path.
Definition any_inside (root:string) (roots:list string) := existsb (inside root) roots.
Definition task_uses_root (root:string) (task:task) :=
 any_inside root (workspace_roots (settings_workspace (contract_settings (task_contract task)))).
Definition job_uses_root (root:string) (job:Selvedge.Features.Domain.connection_job) :=
 match Selvedge.Features.Domain.job_state job with Selvedge.Features.Domain.JobRunning=>
 any_inside root (workspace_roots (Selvedge.Features.Domain.job_workspace job)) | _=>false end.
Definition root_unused (owner:N) (root:string) (value:world) :=
 forallb (fun pair=>N.eqb owner (fst pair) || archived (snd pair) || negb (task_uses_root root (snd pair)))
 (indexed (fun id task=>(id,task)) 0 (world_tasks value)) &&
 forallb (fun pair=>negb (job_uses_root root (snd pair)))
 (Selvedge.Features.Domain.sharing_jobs (Selvedge.Features.Domain.feature_sharing (world_features value))).
Definition archive_allowed (id:N) (value:world) := match lookup id value with
 | Some tree=>match Selvedge.Features.Domain.worktree_root tree with Some root=>root_unused id root value | None=>true end | None=>true end.
Definition pending (tree:Selvedge.Features.Domain.worktree) := match Selvedge.Features.Domain.worktree_phase tree with Selvedge.Features.Domain.TreeCreating _|Selvedge.Features.Domain.TreeArchiving _ _=>true | _=>false end.
Definition execution_allowed (id:N) (value:world) := match lookup id value with Some tree=>match Selvedge.Features.Domain.worktree_phase tree with Selvedge.Features.Domain.TreeCreateFailed _ _=>false | _=>true end | None=>true end.
Definition control_allowed (request:Tasks.control) (id:N) (value:world) := match request with
 | Tasks.Archive=>archive_allowed id value
 | Tasks.Freeze=>execution_allowed id value
 | _=>execution_allowed id value && match lookup id value with Some tree=>negb (pending tree) | None=>true end end.
Definition workspace_available (space:workspace) (value:world) := forallb
 (fun tree=>match Selvedge.Features.Domain.worktree_phase tree with Selvedge.Features.Domain.TreeReady _ _=>true | _=>
 match Selvedge.Features.Domain.worktree_root tree with Some root=>negb (any_inside root (workspace_roots space)) | None=>true end end)
 (Selvedge.Features.Domain.feature_worktrees (world_features value)).
Definition initialize (before:world) (result:decision) :=
 if bool_default "ok" (decision_reply result) false then
 let id:=Selvedge.Kernel.State.next_task before in let value:=decision_world result in
 match Selvedge.Kernel.State.find_task id value with None=>result | Some task=>
 let space:=settings_workspace (task_current_settings task) in
 if negb (Workspace.valid_workspace space && Workspace.valid_path (primary space) && workspace_available space before) then
 Selvedge.Kernel.State.reject "invalid_workspace" "Managed worktree creation requires an available primary workspace" before
 else let frozen:=match task_lifecycle task with Running activity operations=>with_lifecycle (Frozen activity operations) task | _=>task end in
 Selvedge.Kernel.State.Decision (store (Selvedge.Features.Domain.Worktree id (primary space) (Selvedge.Features.Domain.TreeCreating false)) (Selvedge.Kernel.State.put_task id frozen value))
 (decision_reply result) (decision_effects result ++ [Selvedge.Kernel.State.CreateWorktree id (primary space) space]) end
 else result.
Definition create (name:string) (effort:option string) (contents:content) (settings:option json) (caller:option N) (managed:bool) (value:world) :=
 let result:=CommandExecution.create_in_context name effort contents settings false caller value in
 if managed then initialize value result else result.
Definition effective (id:N) (value:world) := match lookup id value with Some tree=>Some tree | None=>
 match Selvedge.Kernel.State.find_task id value with None=>None | Some task=>
 let selected:=primary (settings_workspace (contract_settings (task_contract task))) in
 find (fun tree=>match Selvedge.Features.Domain.worktree_root tree with Some root=>inside root selected | None=>false end) (Selvedge.Features.Domain.feature_worktrees (world_features value)) end end.
Definition query (command:Selvedge.Generated.Commands.command) (_caller:option N) (value:world) :option json := match command with
 | Selvedge.Generated.Commands.Cmd_list_worktrees _=>Some (Selvedge.Kernel.State.success (JObject [("worktrees",JArray (map Observation.worktree_json (Selvedge.Features.Domain.feature_worktrees (world_features value))))]))
 | Selvedge.Generated.Commands.Cmd_read_worktree p=>Some (match effective (Selvedge.Generated.Commands.read_worktree_task_id p) value with Some tree=>Selvedge.Kernel.State.success (Observation.worktree_json tree) | None=>Selvedge.Kernel.State.failure "not_found" "Task worktree does not exist." end)
 | _=>None end.
Definition archive_tree (tree:Selvedge.Features.Domain.worktree) (value:world) :decision :=
 let id:=Selvedge.Features.Domain.worktree_task tree in let source:=Selvedge.Features.Domain.worktree_source tree in
 match Selvedge.Features.Domain.worktree_root tree with None=>Selvedge.Kernel.State.accept (JObject [("accepted",JBool true)]) value [] | Some root=>
 let target:=Selvedge.Features.Domain.worktree_target_primary tree in
 if root_unused id root value then
 Selvedge.Kernel.State.accept (JObject [("accepted",JBool true)]) (store (Selvedge.Features.Domain.Worktree id source (Selvedge.Features.Domain.TreeArchiving root target)) value) [Selvedge.Kernel.State.ArchiveWorktree id source root]
 else Selvedge.Kernel.State.accept (JObject [("accepted",JBool true)]) (store (Selvedge.Features.Domain.Worktree id source (Selvedge.Features.Domain.TreeArchiveFailed root target "Worktree is still used by another task. Archive shared tasks before retrying.")) value) [] end.
Definition retry (id:N) (value:world) :=
 if negb (archive_allowed id value) then Selvedge.Kernel.State.reject "worktree_in_use" "This worktree is shared by other tasks. Archive those tasks before archiving its owner." value else
 match lookup id value,Selvedge.Kernel.State.find_task id value with
 | Some tree,Some task=>match Selvedge.Features.Domain.worktree_phase tree with
 | Selvedge.Features.Domain.TreeArchiveFailed _ _ _=>if archived task then archive_tree tree value
 else Selvedge.Kernel.State.reject "worktree_archive_not_retryable" "Only a failed worktree archive with a retained root can be retried" value
 | _=>Selvedge.Kernel.State.reject "worktree_archive_not_retryable" "Only a failed worktree archive with a retained root can be retried" value end
 | _,_=>Selvedge.Kernel.State.reject "worktree_archive_not_retryable" "Only a failed worktree archive with a retained root can be retried" value end.
Definition create_selected (name:string) (effort:option string) (contents:content) (settings:option json) (idle:bool) (caller:option N) (managed:option bool) (value:world) :=
 let result:=CommandExecution.create_in_context name effort contents settings idle caller value in
 let needs_tree:=match managed with Some choice=>choice | None=>
 match Selvedge.Kernel.State.find_task (Selvedge.Kernel.State.next_task value) (decision_world result) with Some task=>settings_worktree (task_current_settings task) | None=>false end end in
 if needs_tree then initialize value result else result.
Definition create_in_work (work:option N) (run:world->decision) (value:world) :=
 match work with Some id=>Work.create_owned id run value | None=>run value end.
Definition command (command:Selvedge.Generated.Commands.command) (caller:option N) (value:world) :option decision := match command with
 | Selvedge.Generated.Commands.Cmd_create p=>Some (CommandExecution.with_content (Selvedge.Generated.Commands.create_message p) (Selvedge.Generated.Commands.create_images p)
   (fun contents=>create_selected (Selvedge.Generated.Commands.create_profile p) (Selvedge.Generated.Commands.create_reasoning p) contents (Selvedge.Generated.Commands.create_settings p) false caller None value) value)
 | Selvedge.Generated.Commands.Cmd_create_idle p=>Some (create_in_work (Selvedge.Generated.Commands.create_idle_work_id p)
   (fun current=>create_selected (Selvedge.Generated.Commands.create_idle_profile p) (Selvedge.Generated.Commands.create_idle_reasoning p) [] (Selvedge.Generated.Commands.create_idle_settings p) true caller (Selvedge.Generated.Commands.create_idle_create_worktree p) current) value)
 | Selvedge.Generated.Commands.Cmd_create_worktree_task p=>Some (CommandExecution.with_content (Selvedge.Generated.Commands.create_worktree_task_message p) (Selvedge.Generated.Commands.create_worktree_task_images p)
   (fun contents=>create (Selvedge.Generated.Commands.create_worktree_task_profile p) (Selvedge.Generated.Commands.create_worktree_task_reasoning p) contents (Selvedge.Generated.Commands.create_worktree_task_settings p) caller true value) value)
 | Selvedge.Generated.Commands.Cmd_create_work_task p=>Some (Work.create_owned (Selvedge.Generated.Commands.create_work_task_work_id p)
   (fun current=>CommandExecution.with_content (Selvedge.Generated.Commands.create_work_task_message p) (Selvedge.Generated.Commands.create_work_task_images p)
   (fun contents=>create (Selvedge.Generated.Commands.create_work_task_profile p) (Selvedge.Generated.Commands.create_work_task_reasoning p) contents (Selvedge.Generated.Commands.create_work_task_settings p) caller
   (match Selvedge.Generated.Commands.create_work_task_create_worktree p with Some enabled=>enabled | None=>false end) current) current) value)
 | Selvedge.Generated.Commands.Cmd_retry_worktree_archive p=>Some (retry (Selvedge.Generated.Commands.retry_worktree_archive_task_id p) value)
 | _=>None end.
Definition selected_workspace (target:string) (space:workspace) := match workspace_primary space with
 | None=>space | Some source=>Workspace (map (fun root=>if String.eqb root source then target else root) (workspace_roots space)) (Some target) end.
Definition selected_settings (space:workspace) (guidance:json) (settings:task_settings) := Settings space (settings_project settings)
 (settings_sandbox settings) (settings_approval settings) guidance (settings_worktree settings).
Definition completed_task (space:workspace) (guidance:json) (task:task) :=
 let old:=task_contract task in
 let frozen:=selected_settings (selected_workspace (primary space) (settings_workspace (contract_settings old))) guidance (contract_settings old) in
 let chosen:=selected_settings space guidance (task_current_settings task) in
 let contract:=Contract (contract_profile old) (contract_tools old) frozen (contract_max_fork old) (contract_max_descendants old) (contract_plugins old) (contract_reviewers old) in
 let phase:=match task_lifecycle task with Frozen activity operations=>Running activity operations | other=>other end in
 Tasks.promote (Task contract (task_current_profile task) chosen phase
 (task_history task ++ [SettingsMessage chosen (profile_key (task_current_profile task)) (profile_reasoning (task_current_profile task))])
 (task_queued task) (task_lineage task) (task_side_parent task) (task_side_cursor task) (task_model_cursor task)).
Definition failed_task (message:string) (task:task) := with_lifecycle (if archived task then Archived else Stopped Idle []) (append_history [FailureMessage message] task).
Definition created_valid (root:string) (space:workspace) (guidance:json) (task:task) :=
 Workspace.valid_path root && Workspace.valid_workspace space && Workspace.valid_path (primary space) && inside root (primary space) &&
 match Json.equal (workspace_json space) (workspace_json (selected_workspace (primary space) (settings_workspace (task_current_settings task)))) with
 | true=>Codec.valid_guidance guidance && match guidance with JNull=>true | _=>String.eqb (text_default "workspace" guidance "") (primary space) end | false=>false end.
Definition created (tree:Selvedge.Features.Domain.worktree) (ok:bool) (root:option string) (space:option workspace) (guidance:json) (message:string) (value:world) :=
 let id:=Selvedge.Features.Domain.worktree_task tree in let source:=Selvedge.Features.Domain.worktree_source tree in
 match Selvedge.Kernel.State.find_task id value with None=>Selvedge.Kernel.State.accept (JObject [("accepted",JBool false)]) value [] | Some task=>
 let success:=match root,space with Some root,Some space=>ok && created_valid root space guidance task | _,_=>false end in
 if success then match root,space with Some root,Some space=>
 let ready:=Selvedge.Features.Domain.Worktree id source (Selvedge.Features.Domain.TreeReady root (primary space)) in
 if archived task then archive_tree ready (store ready value)
 else Selvedge.Kernel.State.accept (JObject [("accepted",JBool true)]) (store ready (Selvedge.Kernel.State.put_task id (completed_task space guidance task) value)) []
 | _,_=>Selvedge.Kernel.State.accept (JObject [("accepted",JBool false)]) value [] end
 else let reason:=if ok then "Worktree creation returned an invalid workspace or guidance" else message in
 let failed:=Selvedge.Features.Domain.Worktree id source (Selvedge.Features.Domain.TreeCreateFailed root reason) in
 let updated:=store failed (Selvedge.Kernel.State.put_task id (failed_task reason task) value) in
 if archived task then archive_tree failed updated else Selvedge.Kernel.State.accept (JObject [("accepted",JBool true)]) updated [] end.
Definition shape (fields:Schema.schema) (source:json) := match Schema.decode fields source with Some _=>true | None=>false end.
Definition completion (source:json) (value:world) :option (bool*bool*decision) :=
 match string_field "kind" source,natural_field "task_id" source,bool_field "ok" source with
 | Some kind,Some id,Some ok=>
 if String.eqb kind "worktree_created" then
 let root:=string_field "root" source in
 let space:=match field "workspace" source with Some source=>parse_workspace source | None=>None end in
 let guidance:=value_or_null "guidance" source in
 let valid:=if ok then shape [Field "kind" KText;Field "task_id" KNatural;Field "ok" KBool;Field "root" KText;Field "workspace" KJson;Field "guidance" KJson] source &&
 match root,space with Some root,Some _=>Workspace.valid_path root && Codec.valid_guidance guidance | _,_=>false end
 else shape [Field "kind" KText;Field "task_id" KNatural;Field "ok" KBool;Field "root" (KOptional KText);Field "message" KText] source &&
 match root with Some root=>Workspace.valid_path root | None=>true end in
 if negb valid then None else Some (true,true,match lookup id value with
 | Some tree=>match Selvedge.Features.Domain.worktree_phase tree with Selvedge.Features.Domain.TreeCreating _=>created tree ok root space guidance (text_default "message" source "") value
 | _=>Selvedge.Kernel.State.accept (JObject [("accepted",JBool false)]) value [] end
 | None=>Selvedge.Kernel.State.accept (JObject [("accepted",JBool false)]) value [] end)
 else if String.eqb kind "worktree_archived" then
 if negb (if ok then shape [Field "kind" KText;Field "task_id" KNatural;Field "ok" KBool;Field "root" KText] source && Workspace.valid_path (text_default "root" source "")
 else shape [Field "kind" KText;Field "task_id" KNatural;Field "ok" KBool;Field "message" KText] source) then None else
 Some (true,true,match lookup id value with Some tree=>match Selvedge.Features.Domain.worktree_phase tree with
 | Selvedge.Features.Domain.TreeArchiving root target=>Selvedge.Kernel.State.accept (JObject [("accepted",JBool true)])
   (store (Selvedge.Features.Domain.Worktree id (Selvedge.Features.Domain.worktree_source tree) (if ok then Selvedge.Features.Domain.TreeArchived (Some (text_default "root" source "")) target else Selvedge.Features.Domain.TreeArchiveFailed root target (text_default "message" source ""))) value) []
 | _=>Selvedge.Kernel.State.accept (JObject [("accepted",JBool false)]) value [] end | None=>Selvedge.Kernel.State.accept (JObject [("accepted",JBool false)]) value [] end)
 else None | _,_,_=>None end.
Definition archive_after (tree:Selvedge.Features.Domain.worktree) (result:decision) :=
 let value:=decision_world result in
 match Selvedge.Kernel.State.find_task (Selvedge.Features.Domain.worktree_task tree) value with Some task=>if archived task then
 match Selvedge.Features.Domain.worktree_phase tree with
 | Selvedge.Features.Domain.TreeCreating false=>Selvedge.Kernel.State.Decision (store (Selvedge.Features.Domain.Worktree (Selvedge.Features.Domain.worktree_task tree) (Selvedge.Features.Domain.worktree_source tree) (Selvedge.Features.Domain.TreeCreating true)) value) (decision_reply result) (decision_effects result)
 | Selvedge.Features.Domain.TreeReady _ _ | Selvedge.Features.Domain.TreeCreateFailed _ _=>let next:=archive_tree tree value in Selvedge.Kernel.State.Decision (decision_world next) (decision_reply result) (decision_effects result++decision_effects next)
 | _=>result end else result | None=>result end.
Definition after_transition (_before:world) (result:decision) := fold_left (fun current tree=>archive_after tree current) (Selvedge.Features.Domain.feature_worktrees (world_features (decision_world result))) result.
Definition recover (value:world) := value.
Definition guard_command (command:Selvedge.Generated.Commands.command) (_caller:option N) (value:world) :option decision :=
 let request:=match command with
 | Selvedge.Generated.Commands.Cmd_freeze p=>Some (Selvedge.Generated.Commands.freeze_task_id p,Tasks.Freeze) | Selvedge.Generated.Commands.Cmd_unfreeze p=>Some (Selvedge.Generated.Commands.unfreeze_task_id p,Tasks.Unfreeze)
 | Selvedge.Generated.Commands.Cmd_stop p=>Some (Selvedge.Generated.Commands.stop_task_id p,Tasks.Stop) | Selvedge.Generated.Commands.Cmd_interrupt p=>Some (Selvedge.Generated.Commands.interrupt_task_id p,Tasks.Interrupt)
 | Selvedge.Generated.Commands.Cmd_archive p=>Some (Selvedge.Generated.Commands.archive_task_id p,Tasks.Archive) | _=>None end in
 match request with Some (id,action)=>if control_allowed action id value then None else Some (Selvedge.Kernel.State.reject "worktree_busy" "The managed worktree is unavailable or still used by another task" value) | None=>None end.
Definition guard_result (before:world) (result:decision) :=
 if forallb (fun pair=>match Selvedge.Kernel.State.find_task (fst pair) before with
 | Some old=>if Json.equal (workspace_json (settings_workspace (task_current_settings old))) (workspace_json (settings_workspace (task_current_settings (snd pair)))) then true else workspace_available (settings_workspace (task_current_settings (snd pair))) before
 | None=>workspace_available (settings_workspace (task_current_settings (snd pair))) before end)
 (indexed (fun id task=>(id,task)) 0 (world_tasks (decision_world result))) then result
 else Selvedge.Kernel.State.reject "worktree_unavailable" "The selected workspace belongs to an unavailable managed worktree" before.
