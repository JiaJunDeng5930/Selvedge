From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Kernel Require Domain Codec.
From Selvedge.Features Require BoardFilter.
From Selvedge.Interaction Require Import Identity Codec DocumentState.
From Selvedge.Interaction.Session Require State Navigation Context Observation.
Module SessionNavigation := Selvedge.Interaction.Session.Navigation.
Module SessionObservation := Selvedge.Interaction.Session.Observation.
Import ListNotations.
Open Scope string_scope.

(** Read-only product observations. The snapshot is admitted by the application;
    missing objects remain explicit rather than becoming fabricated entities. *)
Record task := Task {
 task_id : N; task_title : string; task_status : string; task_caption : string; task_working : bool;
 task_project : option N; task_work : option N; task_parent : option N;
 task_observation : json
}.
Definition observe_task value :=
 id<-natural_field "id" value;;name<-string_field "title" value;;
 status<-string_field "status" value;;
 if existsb(String.eqb status)["active";"frozen";"stopped";"archived"]then
 caption<-string_field "status_label" value;;working<-bool_field "working" value;;
 settings<-field "settings" value;;project<-id_field "project_id" settings;;
 work<-id_field "work_id" value;;parent<-id_field "parent" value;;
 Some(Task id name status caption working project work parent value)else None.
Definition tasks snapshot := traverse observe_task (Selvedge.Interaction.Codec.items "tasks" snapshot).
Definition find_task id snapshot := bind (DocumentState.find_task id snapshot) observe_task.
Record project := Project {
 project_id : N; project_name : string; project_workspace : Domain.workspace;
 project_guidance : json; project_observation : json
}.
Definition observe_project value :=
 id<-natural_field "project_id" value;;name<-string_field "name" value;;
 workspace<-bind(field "workspace" value)Codec.parse_workspace;;
 guidance<-field "guidance" value;;Some(Project id name workspace guidance value).
Definition projects snapshot := traverse observe_project (Selvedge.Interaction.Codec.items "projects" snapshot).
Definition find_project id snapshot :=
 bind (DocumentState.find_world "projects" "project_id" id snapshot) observe_project.
Record work := Work { work_id:N;work_name:string;work_source:string }.
Definition observe_work value := id<-natural_field "work_id" value;;
 name<-string_field "name" value;;source<-string_field "source" value;;Some(Work id name source).
Definition works snapshot := traverse observe_work (Selvedge.Interaction.Codec.items "works" snapshot).
Definition find_work id snapshot := bind(DocumentState.find_work id snapshot)observe_work.
Definition same_id lhs rhs := match lhs,rhs with
|None,None=>true|Some lhs,Some rhs=>N.eqb lhs rhs|_,_=>false end.
Definition in_work selected value := match selected with
|None=>true|Some work=>same_id (Some work) (task_work value)end.
Definition project_tasks selected := filter (fun value=>same_id selected (task_project value)).
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
Definition board snapshot := field "board" snapshot.
Definition board_cards snapshot := bind(board snapshot)(array_field "cards").
Definition board_agents snapshot := bind(board snapshot)(array_field "agents").
Definition card id snapshot := value<-board snapshot;;DocumentState.find_world "cards" "id" id value.
Definition graphs snapshot := Selvedge.Interaction.Codec.items "graphs" snapshot.
Definition scoped_graphs selected snapshot :=match selected with
|None=>graphs snapshot
|Some work=>filter(fun value=>match id_field "work_id" value with
 |Some(Some owner)=>N.eqb work owner|_=>false end)(graphs snapshot)end.

Definition ordered_cards snapshot :=
 value<-board snapshot;;cards<-array_field "cards" value;;order<-list_field natural "order" value;;
 traverse(fun id=>DocumentState.find_world "cards" "id" id value)order.
Definition visible_cards snapshot s := now<-State.now s;;option_map
 (filter(fun card=>negb(flag "archived" card)&&BoardFilter.matches_in_world(State.board_selection s)now card snapshot))
 (ordered_cards snapshot).
Definition archived_cards snapshot := option_map(filter(flag "archived"))(board_cards snapshot).
Definition count_working snapshot := match board_cards snapshot with
|None=>0%N|Some cards=>N.of_nat(List.length(filter(fun card=>BoardFilter.task_working card snapshot)cards))end.
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
 Selvedge.Interaction.Session.Context.document_context
  (DocumentState.retention_namespace(State.document_retention s))snapshot s.
