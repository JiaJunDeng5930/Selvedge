From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Browser Require Import NavigationIdentity.
From Selvedge.Interaction Require Import Identity Codec.
From Selvedge.Interaction.Experience Require Read.
From Selvedge.Browser.Session Require Import Input Services.
From Selvedge.Browser.Session Require State Navigation Authoring.
Module SessionNavigation := Selvedge.Browser.Session.Navigation.
From Selvedge.Browser.Scene Require Import Surface Model Construction.
From Selvedge.Browser.Presentation Require Import Projection.
From Selvedge.Browser.Presentation Require Roles Information.
Import ListNotations.
Open Scope string_scope.

Definition destination := (string * string * route)%type.
Definition new_conversation_label := "新建对话".
Definition task_graphs_label := "任务图".
Definition settings_label := "设置".
Definition home_destination : destination := ("home","首页",Start).
Definition graph_destination : destination := ("task-graphs",task_graphs_label,Graphs).
Definition history_search_destination : destination := ("history-search","搜索对话",HistorySearch).
Definition destinations : list destination := [
 ("board","卡片看板",Board);("projects","项目",Projects);graph_destination;
 history_search_destination].
Definition route_eq_dec : forall a b:route,{a=b}+{a<>b}.
Proof. repeat decide equality. Defined.
Definition same_route a b := if route_eq_dec a b then true else false.
Definition destination_node entry_role current parent (entry:destination) :=
 let '(identity,label,target):=entry in
 declared parent (entry_role(same_route current target))
  (secondary identity label(Input.Navigate target)).
Definition new_task entry_role current :=
 declared "/navigation" (entry_role(same_route current Start))
  (secondary "new-task" new_conversation_label(Input.BeginTask None)).
Definition global_navigation s :=
 let current:=State.location(State.navigation_state s) in
 region "/workspace" "global-navigation" "Global navigation" (Roles.GlobalNavigation false)
  (List.app(map(destination_node Roles.NavigationEntry current "/global-navigation")destinations)
    [declared "/global-navigation" (Roles.NavigationEntry false)
     (secondary "settings/open" settings_label (Input.ServiceInput Services.OpenSettings))]).
Definition desktop_shortcuts s :=
 let current:=State.location(State.navigation_state s) in
 let entry_role selected:=Roles.GlobalNavigationEntry selected true in
 region "/workspace" "desktop-shortcuts" "快捷操作" (Roles.GlobalNavigation true)
  [declared "/global-navigation" (entry_role false)
    (secondary "tasks/expand" "Expand Task sidebar"(Input.TaskListVisible true));
   new_task entry_role current;
   destination_node entry_role current "/global-navigation" history_search_destination].
Definition all_conversations_label := "全部对话".
Definition conversation_scope_label := "对话范围".
Definition work_label snapshot s :=
 match State.active_work(State.navigation_state s)with
 |None=>all_conversations_label
 |Some id=>match find_work id snapshot with Some work=>work_name work|None=>"工作组不可用"end
 end.
Definition work_count snapshot := N.of_nat(S(List.length(value_or[](works snapshot)))).
Definition work_picker snapshot s parent identity :=
 let label:=work_label snapshot s in
 declared parent (Roles.CompactWorkScope label(work_count snapshot))
  (secondary identity (conversation_scope_label++" · "++label)(Input.OpenNavigation WorkOverview(part parent identity))).
Definition task_attention (task:Read.task) : option task_notice :=
 match task_status task with
 |"archived"=>Some NoticeArchived
 |status=>if Read.task_awaiting_human task then Some NoticeWaiting else
  if String.eqb status "frozen" then Some NoticePaused else
  if Read.task_execution_failed task then Some NoticeFailure else
  if String.eqb status "stopped" then Some NoticeStopped else
  if task_working task then Some NoticeRunning else None
 end.
Definition task_row current key (task:Read.task) (disclosure:option bool) : node Input.input :=
 let id:=task_id task in
 let selected:=task_selected current task in
 let toggle:=match disclosure with None=>[]|Some expanded=>
  let label:=(if expanded then "Collapse branches of " else "Expand branches of ")++task_title task in
  [Node(part key "toggle-branches")"toggle-branches" label Roles.Button
   (PanelToggle expanded(secondary "toggle-branches" label(Input.ToggleTaskBranches id)))[]]end in
 Node key "task-entry" (task_title task) Roles.Section
  (TaskRow id(task_status task)(task_attention task)selected)
  (toggle ++ [declared key(Roles.NavigationEntry selected)
     (secondary "open"(task_title task)(Input.Navigate(Conversation id)))])%list.
Definition with_task_branches (header:node Input.input) branches : node Input.input :=
 let 'Node key semantic label role meaning controls:=header in
 Node key semantic label role meaning (controls ++ branches)%list.
Fixpoint task_entry_tree current collapsed parent (tree:task_tree) : node Input.input :=
 let 'TaskTree task children:=tree in
 let id:=task_id task in
 let key:=part parent("task/"++show_natural id)in
 let expanded:=negb(existsb(N.eqb id)collapsed)in
 let disclosure:=match children with []=>None|_=>Some expanded end in
 with_task_branches (task_row current key task disclosure)
   (match disclosure with
    |Some true=>[Node(part key "children")"task-children" "Subtasks" Roles.NavigationCollection
      (TaskChildren id)(map(task_entry_tree current collapsed key)children)]
    |_=>[]end).

Record task_row_projection := TaskRowProjection {
  previous_row_controls : list (node Input.input);
  projected_task_row : node Input.input;
  projected_task_entry : node Input.input
}.

(* A task observation can change the header independently of the mounted branch. *)
Definition project_task_row current (task:Read.task) (previous:node Input.input) : option task_row_projection :=
 match node_meaning previous with
 |TaskRow id _ _ _=>
  if N.eqb id (task_id task) then
   let '(branches,controls):=partition
     (fun child=>match node_meaning child with TaskChildren _=>true|_=>false end)
     (node_children previous) in
   let disclosure:=fold_right (fun child rest=>match node_meaning child with
     |PanelToggle expanded _=>Some expanded|_=>rest end) None controls in
   let row:=task_row current (Surface.node_key previous) task disclosure in
   Some (TaskRowProjection controls row (with_task_branches row branches))
  else None
 |_=>None end.
Definition collect_task_rows
    (project : node Input.input -> node Input.input * list task_row_projection) :=
 fold_right (fun child result=>
   let '(nodes,rows):=result in
   let '(current,projected):=project child in
   (current::nodes,(projected++rows)%list)) ([],[]).
Fixpoint project_changed_task_node current (changed:N->option Read.task)
    (previous:node Input.input) : node Input.input * list task_row_projection :=
 let 'Node key semantic label role meaning children:=previous in
 let '(children,rows):=collect_task_rows (project_changed_task_node current changed) children in
 let mounted:=match rows with []=>previous|_=>Node key semantic label role meaning children end in
 let projection:=match meaning with
   |TaskRow id _ _ _=>task<-changed id;; project_task_row current task mounted
   |_=>None end in
 match projection with
 |Some row=>(projected_task_entry row,row::rows)
 |None=>(mounted,rows) end.
Definition project_changed_task_rows current changed :=
 collect_task_rows (project_changed_task_node current changed).
Definition project_entry snapshot s current parent tasks (project:project) :=
 let id:=project_id project in
 let key:=part parent("project/"++show_natural id)in
 let selected:=same_id(Some id)(selected_project snapshot s)in
 let expanded:=negb(existsb(N.eqb id)(State.collapsed_projects s))in
 Node key "project-group"(project_name project)Roles.Section(ProjectGroup id selected expanded)
  (region key "actions" "" Roles.Section
    [declared key Roles.Button(secondary "toggle"(if expanded then "收起项目" else "展开项目")(Input.ToggleProjectGroup id));
     declared key(Roles.NavigationEntry selected)(secondary "open"(project_name project)(Input.Navigate(ProjectHome id)));
     declared key Roles.Button(secondary "create" "在项目中开始对话"(Input.BeginTask(Some id)));
     declared key Roles.Button(secondary "more" "项目操作"(Input.OpenObjectActions(ProjectActions id)(part key "more")))] ::
   if expanded then map(task_entry_tree current (State.collapsed_tasks s) key)(forest(project_tasks(Some id)tasks)) else []).
Definition rename_work s :=
 match State.active_work(State.navigation_state s)with
 |None=>[]
 |Some work=>[declared "/navigation" Roles.Button
   (secondary "rename-work" "重命名工作组"(Input.OpenEditor(WorkName(Some work))(part "/navigation" "rename-work")))]
 end.
Definition work_destinations s controls :=
 let navigation:=State.navigation_state s in
 let current:=State.location navigation in
 match State.active_work navigation with None=>controls|Some work=>
 [region "/navigation" "work-destinations" "Work destinations" Roles.NavigationSection
  (declared "/navigation"(Roles.NavigationEntry(match current with SharedUI selected _=>N.eqb selected work|_=>false end))
      (secondary "work/shared-ui" "共享 UI"(Input.Navigate(SharedUI work
        (match current with SharedUI _ task=>task|_=>None end))))::controls)]
 end.
Definition task_collection snapshot s :=
 let navigation:=State.navigation_state s in
 let current:=State.location navigation in
 let content:=match tasks snapshot,projects snapshot with
 |Some all,Some groups=>
   let scoped:=work_tasks(State.active_work navigation)all in
   let visible:=match State.active_work navigation with
    |None=>groups|Some _=>filter(fun p=>negb(Nat.eqb(List.length(project_tasks(Some(project_id p))scoped))0))groups end in
   let independent:=match forest(project_tasks None scoped)with
    |[]=>[]
    |trees=>[region "/navigation" "independent-tasks" "" Roles.NavigationSection
        (information(part "/navigation" "independent-tasks")"title" Information.NavigationCaption "未归入项目的对话"::
        map(task_entry_tree current (State.collapsed_tasks s) "/navigation")trees)]end in
   List.app(map(project_entry snapshot s current "/navigation" scoped)visible)independent
 |_,_=>[read_only "/navigation" "unavailable" "Tasks" "Task navigation observations unavailable"]end in
 region "/navigation" "contents" "" Roles.NavigationCollection
  (region "/navigation" "task-creation" "" Roles.NavigationSection
    [new_task Roles.NavigationEntry current]::content).
Definition task_navigation snapshot s :=
 Node "/navigation" "navigation" "Task tree" Roles.Navigation Region
  ([region "/navigation" "header" "Task tree" Roles.NavigationHeader
   (title(part "/navigation" "header") "对话"::rename_work s)]++
   work_destinations s []++[task_collection snapshot s])%list.
Definition desktop_task_navigation snapshot s :=
 let '(home_key,home_label,home_route):=home_destination in
 Node "/navigation" "navigation" "Task tree" Roles.Navigation Region
  ([region "/navigation" "header" "Workspace" Roles.NavigationHeader
    [declared "/global-navigation" (Roles.NavigationEntry false)
      (secondary home_key home_label(Input.Navigate home_route));
     declared(part "/navigation" "header") Roles.Button
      (secondary "toggle" "Collapse Task sidebar"(Input.TaskListVisible false))];
   work_picker snapshot s "/work-tabs" "work/overview"]++
   work_destinations s (rename_work s)++[
   task_collection snapshot s;
   global_navigation s])%list.
Definition work_summary snapshot selected :=
 match tasks snapshot with
 |None=>"对话列表不可用"
 |Some all=>show_natural(N.of_nat(List.length(work_tasks selected all)))++" 个对话"
 end.
Definition work_overview snapshot s parent :=
 let active:=State.active_work(State.navigation_state s)in
 let choice work name :=
   let key:=part parent(NavigationIdentity.work_key work)in
   Node key "work-choice" name Roles.Button
    (WorkChoice work(same_id active work)(secondary(NavigationIdentity.work_key work)name(Input.SelectWork work)))
    [information key "name" Information.OptionLabel name;
     information key "description" Information.Description(work_summary snapshot work)]in
 let entries:=choice None all_conversations_label::
   match works snapshot with
   |None=>[read_only parent "unavailable" "" "工作组不可用"]
   |Some entries=>map(fun work=>choice(Some(work_id work))(work_name work))entries end in
 (entries++[declared parent Roles.Button(secondary "work/new" "新建工作组" Input.CreateWork)])%list.
Definition global_menu s parent :=
 let current:=State.location(State.navigation_state s)in
 [region parent "global-menu" "Global destinations" Roles.CompactNavigationMenu
   (List.app(map(fun entry=>let '(identity,label,target):=entry in
     declared parent(Roles.CompactNavigationEntry(same_route current target))
       (secondary identity label(Input.Navigate target)))(home_destination::destinations))
    [declared parent(Roles.CompactNavigationEntry false)
      (secondary "settings" settings_label(Input.ServiceInput Services.OpenSettings))])].
Definition compact_header snapshot s :=
 region "/workspace" "compact-header" "Workspace navigation" Roles.CompactHeader
  [declared "/compact-header" Roles.Button (secondary "global" "Global navigation"(Input.OpenNavigation GlobalMenu(part "/compact-header" "global")));
   work_picker snapshot s "/compact-header" "works";
   declared "/compact-header" Roles.Button(secondary "tasks" (if SessionNavigation.expanded_for false s then "Back to conversation"else"Open Task list")(Input.NavigationExpanded(negb(SessionNavigation.expanded_for false s))))].
Definition navigation_base snapshot s capacity :=
 let expanded:=SessionNavigation.expanded_for(navigation_beside_content capacity)s in
 if navigation_beside_content capacity then
  if expanded then [desktop_task_navigation snapshot s] else [desktop_shortcuts s]
 else if expanded then[]else[compact_header snapshot s].
Definition navigation_layers snapshot s capacity :=
 if navigation_beside_content capacity || negb(SessionNavigation.expanded_for false s)then[]else
 [Node "/navigation/modal" "task-navigation" "Task tree" Roles.Dialog
  (NavigationRegion TasksDrawer(LayerBehavior ModalDialog false(State.generation(State.navigation_state s))
    "/navigation"(part "/compact-header" "tasks")"/main"(part "/compact-header" "tasks") (Input.NavigationExpanded false) true true))
  [dialog_header "/navigation/modal" [compact_header snapshot s];
   dialog_body "/navigation/modal" [task_navigation snapshot s]]].
