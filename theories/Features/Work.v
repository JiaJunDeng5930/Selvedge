From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Utf8.
From Selvedge.Kernel Require Import Numbers Domain State.
From Selvedge.Features Require Import Domain State WorkUIPatch.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Definition valid_name (name:string) := negb (String.eqb name "") && Utf8.well_formed name && Nat.leb (String.length name) 4096.
Definition lookup (id:N) (value:world) := registry_at id (Selvedge.Features.Domain.feature_works (world_features value)).
Definition plain_json (id:N) (value:Selvedge.Features.Domain.work) := JObject [("work_id",number id);("name",JString (Selvedge.Features.Domain.work_name value))].
Definition ui_json (id:N) (value:Selvedge.Features.Domain.work) := JObject [("work_id",number id);("source",JString (Selvedge.Features.Domain.work_ui_source value));("revision",number (Selvedge.Features.Domain.work_ui_revision value))].
Definition task_owner (id:N) (value:world) := match find_task id value with Some task=>Selvedge.Features.Domain.owner_id id (task_lineage task) (world_features value) | None=>None end.
Definition task_ids (id:N) (value:world) := fold_right (fun entry rest=>let '(key,task):=entry in match Selvedge.Features.Domain.owner_id key (task_lineage task) (world_features value) with Some owner=>if N.eqb id owner then number key::rest else rest | None=>rest end) [] (indexed (fun key task=>(key,task)) 0 (world_tasks value)).
Definition graph_ids (id:N) (value:world) := fold_right (fun entry rest=>if N.eqb id (snd entry) then number (fst entry)::rest else rest) [] (Selvedge.Features.Domain.feature_graph_owners (world_features value)).
Definition observe (id:N) (work:Selvedge.Features.Domain.work) (value:world) := JObject [("work_id",number id);("name",JString (Selvedge.Features.Domain.work_name work));("task_ids",JArray (task_ids id value));("graph_ids",JArray (graph_ids id value))].
Definition list_works (value:world) := JArray (indexed (fun id work=>observe id work value) 0 (Selvedge.Features.Domain.feature_works (world_features value))).
Definition read (id:N) (value:world) := match lookup id value with Some work=>Selvedge.Kernel.State.success (observe id work value) | None=>Selvedge.Kernel.State.failure "work_not_found" "The Work does not exist." end.
Definition create (chosen:option string) (value:world) :=
 let features:=world_features value in let id:=N.of_nat (List.length (Selvedge.Features.Domain.feature_works features)) in
 let name:=match chosen with Some text=>if String.eqb text "" then String.append "Work #" (Selvedge.Features.Domain.decimal_text id) else text | None=>String.append "Work #" (Selvedge.Features.Domain.decimal_text id) end in
 if N.ltb id 4294967295 then if valid_name name then
 let next:=Selvedge.Features.Domain.feature_works features++[Selvedge.Features.Domain.Work name "" 0] in
 Selvedge.Kernel.State.accept (plain_json id (Selvedge.Features.Domain.Work name "" 0)) (with_features (Selvedge.Features.State.with_works next features) value) []
 else Selvedge.Kernel.State.reject "invalid_name" "Work names must contain between 1 and 4096 UTF-8 bytes." value
 else Selvedge.Kernel.State.reject "capacity" "No more Work identifiers are available." value.
Definition rename (id:N) (name:string) (value:world) := match lookup id value with
 | None=>Selvedge.Kernel.State.reject "not_found" "Work does not exist." value
 | Some previous=>if valid_name name then let work:=Selvedge.Features.Domain.Work name (Selvedge.Features.Domain.work_ui_source previous) (Selvedge.Features.Domain.work_ui_revision previous) in
 Selvedge.Kernel.State.accept (plain_json id work) (with_features (Selvedge.Features.State.with_works (replace id work (Selvedge.Features.Domain.feature_works (world_features value))) (world_features value)) value) []
 else Selvedge.Kernel.State.reject "invalid_name" "Work names must contain between 1 and 4096 UTF-8 bytes." value end.
Definition read_ui (caller:option N) (value:world) := match caller with
 | None=>Selvedge.Kernel.State.failure "task_call_required" "Read the shared UI through a Task tool call."
 | Some caller=>match task_owner caller value with
 | None=>Selvedge.Kernel.State.failure "no_work" "This Task does not belong to a Work."
 | Some id=>match lookup id value with Some work=>Selvedge.Kernel.State.success (ui_json id work) | None=>Selvedge.Kernel.State.failure "work_not_found" "The Work does not exist." end end end.
Definition patch_work (id:N) (patch:string) (expected:N) (value:world) := match lookup id value with
 | None=>Selvedge.Kernel.State.reject "work_not_found" "The Work does not exist." value
 | Some previous=>if N.ltb (Selvedge.Features.Domain.work_ui_revision previous) 4294967295 then
 if N.eqb expected (Selvedge.Features.Domain.work_ui_revision previous) then
 match WorkUIPatch.apply (Selvedge.Features.Domain.work_ui_source previous) patch with
 | WorkUIPatch.Fail reason=>Selvedge.Kernel.State.reject "invalid_patch" reason value
 | WorkUIPatch.Done source=>let work:=Selvedge.Features.Domain.Work (Selvedge.Features.Domain.work_name previous) source (N.succ expected) in
 Selvedge.Kernel.State.accept (ui_json id work) (with_features (Selvedge.Features.State.with_works (replace id work (Selvedge.Features.Domain.feature_works (world_features value))) (world_features value)) value) [] end
 else Selvedge.Kernel.State.reject "revision_conflict" "The Work UI changed. Read its current source and revision before applying another patch." value
 else Selvedge.Kernel.State.reject "capacity" "No more Work UI revisions are available." value end.
Definition apply_ui_patch (caller:option N) (patch:string) (expected:N) (value:world) := match caller with
 | None=>Selvedge.Kernel.State.reject "task_call_required" "Edit the shared UI through a Task tool call." value
 | Some caller=>match task_owner caller value with None=>Selvedge.Kernel.State.reject "no_work" "This Task does not belong to a Work." value | Some id=>patch_work id patch expected value end end.
Definition own_created (work_id:N) (original:world) (created:decision) :=
 match bool_field "ok" (decision_reply created) with
 | Some true=>let value:=decision_world created in let features:=world_features value in
 Decision (with_features (Selvedge.Features.State.with_task_owners ((next_task original,work_id)::Selvedge.Features.Domain.feature_task_owners features) features) value) (decision_reply created) (decision_effects created)
 | _=>Decision original (decision_reply created) [] end.
Definition create_owned (id:N) (create:world->decision) (value:world) := match lookup id value with
 | None=>Selvedge.Kernel.State.reject "work_not_found" "The Work does not exist." value
 | Some _=>own_created id value (create value) end.
From Selvedge.Generated Require Import Commands.
Definition query (command:Selvedge.Generated.Commands.command) (caller:option N) (value:world) :option json := match command with
 | Selvedge.Generated.Commands.Cmd_list_works _=>Some (Selvedge.Kernel.State.success (JObject [("works",list_works value)]))
 | Selvedge.Generated.Commands.Cmd_read_work payload=>Some (read (Selvedge.Generated.Commands.read_work_work_id payload) value)
 | Selvedge.Generated.Commands.Cmd_read_work_ui _=>Some (read_ui caller value)
 | _=>None end.
Definition command (command:Selvedge.Generated.Commands.command) (_caller:option N) (value:world) :option decision := match command with
 | Selvedge.Generated.Commands.Cmd_create_work payload=>Some (create (Selvedge.Generated.Commands.create_work_name payload) value)
 | Selvedge.Generated.Commands.Cmd_rename_work payload=>Some (rename (Selvedge.Generated.Commands.rename_work_work_id payload) (Selvedge.Generated.Commands.rename_work_name payload) value)
 | Selvedge.Generated.Commands.Cmd_apply_work_ui_patch payload=>Some (apply_ui_patch _caller (Selvedge.Generated.Commands.apply_work_ui_patch_patch payload) (Selvedge.Generated.Commands.apply_work_ui_patch_revision payload) value)
 | _=>None end.
