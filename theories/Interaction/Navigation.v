From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Interaction Require Import Codec Identity ApplicationState.
Import ListNotations.
Open Scope string_scope.

Definition visible_task_views s :=
 List.app (match location(navigation_state s)with Conversation task=>[PrimaryTask task]|_=>[]end)
 (match side_task(navigation_state s)with None=>[]|Some task=>[SideTask task]end).

Definition tasks_drawer_open s :=existsb(fun panel=>match panel with
 |NavigationPanel TasksDrawer _=>true|_=>false end)(layers(navigation_state s)).

Record destination := Destination {
  destination_key : string;
  destination_label : string;
  destination_icon : string;
  destination_route : route
}.

Definition global_destinations := [
  Destination "nav/projects" "项目" "folder" Projects;
  Destination "nav/board" "任务看板" "columns" Board;
  Destination "nav/agents" "智能体" "agents" Agents;
  Destination "nav/graphs" "Task graphs" "branch" Graphs;
  Destination "nav/search" "搜索对话" "search" HistorySearch
].

Definition route_eq_dec : forall (a b : route), {a = b} + {a <> b}.
Proof. repeat decide equality. Defined.
Definition route_selected current target :=
  if route_eq_dec current target then true else false.

Definition task_project task :=
  bind (field "settings" task) (natural_field "project_id").
Definition task_in_work work task := match work with
  | None => true
  | Some work => match natural_field "work_id" task with
    | Some owner => N.eqb work owner | None => false end
  end.
Definition tasks_in_work work world :=
  filter (task_in_work work) (items "tasks" world).
Definition tasks_in_project project world :=
  filter (fun task => same_scope (Some project) (task_project task))
    (items "tasks" world).
Definition project_navigation_tasks project work world :=
  filter (task_in_work work) (tasks_in_project project world).
Definition independent_navigation_tasks work world :=
  filter (fun task => match task_project task with
    | None => true | Some _ => false end) (tasks_in_work work world).

Definition active_project world s :=
 let requested:=match location(navigation_state s)with
 |ProjectHome id=>Some id|Conversation task=>bind(find_task task world)task_project
 |Start=>bind(find_draft(NewTask(active_work(navigation_state s)))s)(fun d=>natural(Forms.get "project_id" d))
 |_=>None end in
 match requested with Some id=>match find_project id world with Some _=>Some id|None=>None end|None=>None end.
Definition projects_in_navigation work world :=match work with None=>items "projects" world|Some _=>
 filter(fun project=>match natural_field "project_id" project with None=>false|Some id=>
  match project_navigation_tasks id work world with []=>false|_=>true end end)(items "projects" world)end.

Definition task_title task :=
  let title := text "title" task in
  if String.eqb title "" then "Task #" ++ text "id" task else title.
Definition task_status_icon task :=match text "status" task with
 |"active"=>if flag "working" task then "play-triangle"else "idle-circle"
 |"frozen"=>"pause-bars"|"stopped"=>"stop-square"|"archived"=>"archive-box"|_=>"conversation"end.
Definition task_status_caption task := text "status_label" task.

Definition work_label work world := match work with
  | None => "All Tasks"
  | Some id => match find_work id world with
    | Some value => text "name" value | None => "Work #" ++ show_natural id end
  end.
Definition task_count count := show_natural (N.of_nat count) ++
  if Nat.eqb count 1 then " task" else " tasks".
Definition work_summary work world :=
  let tasks := tasks_in_work work world in
  match tasks with
  | [] => "No tasks yet"
  | task :: _ => task_count (List.length tasks) ++ " · " ++
      task_title task ++ " · " ++ task_status_caption task
  end.

Definition work_overview_key work := match work with
  | None => "work-overview/all" | Some id => "work-overview/" ++ show_natural id end.

Definition work_choices world : list (option N) :=
  None :: flat_map (fun work => match natural_field "work_id" work with
    | Some id => [Some id] | None => [] end) (items "works" world).

Theorem project_navigation_membership project work world task :
  In task (project_navigation_tasks project work world) ->
  same_scope (Some project) (task_project task) = true /\
  task_in_work work task = true.
Proof.
  unfold project_navigation_tasks, tasks_in_project.
  intros member. apply filter_In in member as [member work_member].
  apply filter_In in member as [_ project_member]. auto.
Qed.
