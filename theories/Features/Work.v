From Stdlib Require Import String List Bool NArith.
From Selvedge.Programming Require TaskBirth.
From Selvedge.Foundation Require Import Json Utf8.
From Selvedge.Kernel Require Import Numbers Domain State Tasks.
From Selvedge.Features Require Import Domain State WorkUIPatch.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Definition valid_name (name:string) := ArgumentDeclaration.check
 Selvedge.Features.Domain.work_name_declaration (JString name).
Definition lookup (id:N) (value:world) := registry_at id (Selvedge.Features.Domain.feature_works (world_features value)).
Definition plain_json (id:N) (value:Selvedge.Features.Domain.work) := JObject [("work_id",number id);("name",JString (Selvedge.Features.Domain.work_name value))].
Definition ui_json (id:N) (value:Selvedge.Features.Domain.work) := JObject [("work_id",number id);("source",JString (Selvedge.Features.Domain.work_ui_source value));("revision",number (Selvedge.Features.Domain.work_ui_revision value))].
Definition task_owner (id:N) (value:world) := match find_task id value with Some task=>Selvedge.Features.Domain.owner_id id (task_lineage task) (world_features value) | None=>None end.
Definition task_ids (id:N) (value:world) := fold_right (fun entry rest=>let '(key,task):=entry in match Selvedge.Features.Domain.owner_id key (task_lineage task) (world_features value) with Some owner=>if N.eqb id owner then number key::rest else rest | None=>rest end) [] (indexed (fun key task=>(key,task)) 0 (world_tasks value)).
Definition graph_ids (id:N) (value:world) :=
 (* Graph IDs are allocated in association order and never reused. Enumerating
    the registry keeps that order independent of association-map updates. *)
 fold_right (fun entry rest=>let '(key,graph):=entry in
 match graph,Selvedge.Features.Domain.association key (Selvedge.Features.Domain.feature_graph_owners (world_features value)) with
 | Some _,Some owner=>if N.eqb id owner then number key::rest else rest
 | _,_=>rest end) []
 (indexed (fun key graph=>(key,graph)) 0 (Selvedge.Features.Domain.feature_graphs (world_features value))).
Definition observe (id:N) (work:Selvedge.Features.Domain.work) (value:world) := JObject [("work_id",number id);("name",JString (Selvedge.Features.Domain.work_name work));
 ("ui_source",JString (Selvedge.Features.Domain.work_ui_source work));("ui_revision",number (Selvedge.Features.Domain.work_ui_revision work));
 ("task_ids",JArray (task_ids id value));("graph_ids",JArray (graph_ids id value))].
Definition list_works (value:world) := JArray (indexed (fun id work=>observe id work value) 0 (Selvedge.Features.Domain.feature_works (world_features value))).
Definition read (id:N) (value:world) := match lookup id value with Some work=>Selvedge.Kernel.State.success (observe id work value) | None=>Selvedge.Kernel.State.failure "work_not_found" "The Work does not exist." end.
Definition creation_name (id : N)
 (chosen : option (ArgumentDeclaration.denote Selvedge.Features.Domain.work_creation_name_declaration)) :=
 match chosen with
 | Some (inr (inl name)) => proj1_sig name
 | None | Some (inl _) => String.append "Work #" (Selvedge.Features.Domain.decimal_text id)
 | Some (inr (inr impossible)) => match impossible with end end.
Definition create (chosen : option (ArgumentDeclaration.denote Selvedge.Features.Domain.work_creation_name_declaration)) (value:world) :=
 let features:=world_features value in let id:=N.of_nat (List.length (Selvedge.Features.Domain.feature_works features)) in
 let name:=creation_name id chosen in
 if N.ltb id 4294967295 then
 let next:=Selvedge.Features.Domain.feature_works features++[Selvedge.Features.Domain.Work name "" 0] in
 Selvedge.Kernel.State.accept (plain_json id (Selvedge.Features.Domain.Work name "" 0)) (with_features (Selvedge.Features.State.with_works next features) value) []
 else Selvedge.Kernel.State.reject "capacity" "No more Work identifiers are available." value.
Definition rename (id:N) (name:ArgumentDeclaration.denote Selvedge.Features.Domain.work_name_declaration) (value:world) := match lookup id value with
 | None=>Selvedge.Kernel.State.reject "not_found" "Work does not exist." value
 | Some previous=>let work:=Selvedge.Features.Domain.Work (proj1_sig name) (Selvedge.Features.Domain.work_ui_source previous) (Selvedge.Features.Domain.work_ui_revision previous) in
 Selvedge.Kernel.State.accept (plain_json id work) (with_features (Selvedge.Features.State.with_works (replace id work (Selvedge.Features.Domain.feature_works (world_features value))) (world_features value)) value) [] end.
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
(** Ownership is attached only to a witnessed fresh Task and a Work observed
    in the plan's original world. The decoration frame cannot replace tasks or
    the Work registry while attaching resource metadata. *)
Record owner_scope (before : world) := OwnerScope {
 owner_identity : N;
 owner_value : Selvedge.Features.Domain.work;
 owner_observed : lookup owner_identity before = Some owner_value
}.
Arguments OwnerScope {before}.
Arguments owner_identity {before}.
Definition select_owner_decoded (id : N) (before : world)
 (found : option Selvedge.Features.Domain.work) (Found : lookup id before = found)
 : option (owner_scope before) :=
 match found as result return lookup id before = result -> option (owner_scope before) with
 | Some owner => fun Found => Some (OwnerScope id owner Found)
 | None => fun _ => None end Found.
Definition select_owner (id : N) (before : world) : option (owner_scope before) :=
 select_owner_decoded id before (lookup id before) eq_refl.
Theorem select_missing_owner : forall id before,
 lookup id before = None -> select_owner id before = None.
Proof.
 intros id before Missing.
 assert (Absent : forall found (Evidence : lookup id before = found),
   found = None -> select_owner_decoded id before found Evidence = None).
 { intros [owner|] Evidence Empty; [discriminate|reflexivity]. }
 unfold select_owner; apply Absent; exact Missing.
Qed.
Definition own_birth {origin before : world} (owner : owner_scope origin)
 (birth : TaskBirth.birth_result before) (value : world)
 (_tasks : world_tasks value = world_tasks (TaskBirth.birth_world birth))
 (_works : Selvedge.Features.Domain.feature_works (world_features value) =
   Selvedge.Features.Domain.feature_works (world_features origin)) :=
 with_features (Selvedge.Features.State.with_task_owners
   ((TaskBirth.birth_id birth,owner_identity owner)::Selvedge.Features.Domain.feature_task_owners (world_features value))
   (world_features value)) value.
From Selvedge.Generated Require Import Commands.
Definition handle_list_works (payload:Selvedge.Generated.Commands.list_works_payload) (caller:option N) (value:world) :json :=
 Selvedge.Kernel.State.success (JObject [("works",list_works value)]).
Definition handle_read_work (payload:Selvedge.Generated.Commands.read_work_payload) (caller:option N) (value:world) :json :=
 read (Selvedge.Generated.Commands.read_work_work_id payload) value.
Definition handle_read_work_ui (payload:Selvedge.Generated.Commands.read_work_ui_payload) (caller:option N) (value:world) :json :=
 read_ui caller value.
Definition handle_create_work (payload:Selvedge.Generated.Commands.create_work_payload) (caller:option N) (value:world) :decision :=
 create (Selvedge.Generated.Commands.create_work_name_admitted payload) value.
Definition handle_rename_work (payload:Selvedge.Generated.Commands.rename_work_payload) (caller:option N) (value:world) :decision :=
 rename (Selvedge.Generated.Commands.rename_work_work_id payload) (Selvedge.Generated.Commands.rename_work_name_admitted payload) value.
Definition handle_apply_work_ui_patch (payload:Selvedge.Generated.Commands.apply_work_ui_patch_payload) (caller:option N) (value:world) :decision :=
 apply_ui_patch caller (Selvedge.Generated.Commands.apply_work_ui_patch_patch payload) (Selvedge.Generated.Commands.apply_work_ui_patch_revision payload) value.
