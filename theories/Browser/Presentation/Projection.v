From Stdlib Require Import String List Bool NArith.
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

Definition in_work selected value := match selected with
|None=>true|Some work=>same_id (Some work) (task_work value)end.
Definition work_tasks selected := filter (in_work selected).
Inductive task_tree := TaskTree (entry:task)(children:list task_tree).
Definition tree_entry(tree:task_tree):task:=match tree with TaskTree entry _=>entry end.
(** Snapshots retain the kernel's parent-before-child registry order.  Folding
    from the right attaches complete descendants, while a parent outside the
    selected Work/project leaves its child at the collection root. *)
Fixpoint forest(values:list task):list task_tree:=match values with
|[]=>[]
|entry::rest=>let '(children,roots):=partition
  (fun tree=>same_id(Some(task_id entry))(task_parent(tree_entry tree)))(forest rest)in
 TaskTree entry children::roots end.
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
 |Start=>match SessionObservation.draft_preview snapshot
   (State.current_draft s (NewTask(State.active_work navigation)))with
   |Context.ProspectiveContext _ project _ _ _ _=>project
   |_=>None end
 |_=>None end.
Definition document_context snapshot s :=
 Selvedge.Browser.Session.Context.document_context
  (DocumentState.retention_namespace(State.document_retention s))snapshot s.
