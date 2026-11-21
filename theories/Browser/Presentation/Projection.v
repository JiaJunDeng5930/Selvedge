From Stdlib Require Import String List Bool NArith.
From Stdlib Require FSets.FMapAVL Structures.OrderedTypeEx.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Browser Require Import NavigationIdentity.
From Selvedge.Interaction Require Import Identity Codec.
From Selvedge.Browser Require Import DocumentState.
From Selvedge.Interaction.Experience Require Model.
From Selvedge.Interaction.Experience Require Export Read.
From Selvedge.Browser.Session Require State Context Observation.
From Selvedge.Browser.Scene Require Import Model.
Module SessionObservation := Selvedge.Browser.Session.Observation.
Import ListNotations.
Open Scope string_scope.

Definition domain_availability(value:Selvedge.Interaction.Experience.Model.availability):availability:=match value with
|Selvedge.Interaction.Experience.Model.Available=>Available
|Selvedge.Interaction.Experience.Model.Unavailable reason=>Unavailable reason end.

Inductive task_tree := TaskTree (entry:task)(children:list task_tree).
Module TaskIdMap := FMapAVL.Make OrderedTypeEx.N_as_OT.
Definition waiting_children id (pending:TaskIdMap.t (list task_tree)) :=
 value_or [] (TaskIdMap.find id pending).

(** Only a parent already seen in this Work/project can receive the current
    entry. On the return traversal each parent takes its completed children
    from one bucket; prepending preserves the original sibling and root order. *)
Fixpoint assemble_forest (earlier:TaskIdMap.t unit) (values:list task)
    : list task_tree * TaskIdMap.t (list task_tree) :=
 match values with
 |[]=>([],TaskIdMap.empty _)
 |entry::rest=>
   let id:=task_id entry in
   let '(roots,pending):=assemble_forest (TaskIdMap.add id tt earlier) rest in
   let tree:=TaskTree entry (waiting_children id pending) in
   let remaining:=TaskIdMap.remove id pending in
   match task_parent entry with
   |Some parent=>if TaskIdMap.mem parent earlier then
      (roots,TaskIdMap.add parent (tree::waiting_children parent remaining) remaining)
     else (tree::roots,remaining)
   |None=>(tree::roots,remaining)
   end
 end.
Definition forest (values:list task) :=
 if existsb (fun entry=>match task_parent entry with Some _=>true|None=>false end) values
 then fst (assemble_forest (TaskIdMap.empty unit) values)
 else map (fun entry=>TaskTree entry []) values.
Definition task_selected route value := match route with
|Conversation id=>N.eqb id(task_id value)|SharedUI _ (Some id)=>N.eqb id(task_id value)|_=>false end.
Definition task_details_observation snapshot id :=
 task<-find_task id snapshot;; details<-task_details_for id snapshot;;Some(task,details).
Definition project_members snapshot id :=
 option_map(project_tasks(Some id))(tasks snapshot).
Definition scoped_graphs selected snapshot :=
 option_map(filter(fun value=>match selected with
 |None=>true|Some work=>same_id(Some work)(graph_work value)end))(graphs snapshot).
Definition visible_cards snapshot s :=
 now<-State.now s;;Read.visible_cards snapshot(State.board_selection s)now.
Definition selected_project snapshot s :=
 let navigation:=State.navigation_state s in
 match State.location navigation with
 |ProjectHome id=>Some id
 |Conversation task=>bind(find_task task snapshot)task_project
 |Start|GraphConversation _ _=>match SessionObservation.draft_preview snapshot
   (State.current_draft s (NewTask(State.active_work navigation)))with
   |Context.ProspectiveContext _ project _ _ _ _=>project
   |_=>None end
 |_=>None end.
Definition document_context snapshot s :=
 Selvedge.Browser.Session.Context.document_context
  (DocumentState.retention_namespace(State.document_retention s))snapshot s.
