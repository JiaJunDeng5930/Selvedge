From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Browser Require Import NavigationIdentity.
From Selvedge.Interaction Require Import Identity Codec.
From Selvedge.Browser.Session Require Import Input Services.
From Selvedge.Browser.Session Require State Navigation Authoring.
Module SessionNavigation := Selvedge.Browser.Session.Navigation.
From Selvedge.Browser.Scene Require Import Surface Model Construction.
From Selvedge.Browser.Presentation Require Import Projection.
From Selvedge.Browser.Presentation Require Roles Information.
Import ListNotations.
Open Scope string_scope.

Definition destination := (string * string * route)%type.
Definition home_destination : destination := ("home","Home",Start).
Definition graph_destination : destination := ("task-graphs","Task graphs",Graphs).
Definition destinations : list destination := [
 ("board","任务看板",Board);("projects","项目",Projects);
 ("history-search","搜索对话",HistorySearch)].
Definition route_eq_dec : forall a b:route,{a=b}+{a<>b}.
Proof. repeat decide equality. Defined.
Definition same_route a b := if route_eq_dec a b then true else false.
Definition destination_node current parent (entry:destination) :=
 let '(identity,label,target):=entry in
 declared parent (Roles.NavigationEntry(same_route current target))
  (secondary identity label(Input.Navigate target)).
Definition global_navigation s :=
 let current:=State.location(State.navigation_state s) in
 region "/workspace" "global-navigation" "Global navigation" (Roles.GlobalNavigation false)
  (List.app(map(destination_node current "/global-navigation")destinations)
    [declared "/global-navigation" (Roles.NavigationEntry false)
     (secondary "settings/open" "Settings" (Input.ServiceInput Services.OpenSettings))]).
Definition work_label snapshot s :=
 match State.active_work(State.navigation_state s)with
 |None=>"All Tasks"
 |Some id=>match find_work id snapshot with Some work=>work_name work|None=>"Work unavailable"end
 end.
Definition work_count snapshot := N.of_nat(S(List.length(value_or[](works snapshot)))).
Definition work_picker snapshot s parent identity :=
 let label:=work_label snapshot s in
 declared parent (Roles.CompactWorkScope label(work_count snapshot))
  (secondary identity ("Work overview: "++label)(Input.OpenNavigation WorkOverview(part parent identity))).
Fixpoint task_entry_tree current collapsed parent (tree:task_tree) : node Input.input :=
 let 'TaskTree task children:=tree in
 let id:=task_id task in
 let key:=part parent("task/"++show_natural id)in
 let expanded:=negb(existsb(N.eqb id)collapsed)in
 let disclosure:=match children with []=>[]|_=>
  let label:=(if expanded then "Collapse branches of " else "Expand branches of ")++task_title task in
  [Node(part key "toggle-branches")"toggle-branches" label Roles.Button
   (PanelToggle expanded(secondary "toggle-branches" label(Input.ToggleTaskBranches id)))[]]end in
 Node key "task-entry" (task_title task) Roles.Section
  (TaskRow id(task_status task)(task_caption task)(task_working task)(task_selected current task))
  (disclosure ++ [declared key(Roles.NavigationEntry(task_selected current task))
      (secondary "open"(task_title task)(Input.Navigate(Conversation id)))] ++
   match children,expanded with
   |[],_ |_,false=>[]
   |_,true=>[Node(part key "children")"task-children" "Subtasks" Roles.NavigationCollection
         (TaskChildren id)(map(task_entry_tree current collapsed key)children)]end)%list.
Definition project_entry snapshot s current parent tasks (project:project) :=
 let id:=project_id project in
 let key:=part parent("project/"++show_natural id)in
 let selected:=same_id(Some id)(selected_project snapshot s)in
 let expanded:=negb(existsb(N.eqb id)(State.collapsed_projects s))in
 Node key "project-group"(project_name project)Roles.Section(ProjectGroup id selected expanded)
  (region key "actions" "" Roles.Section
    [declared key Roles.Button(secondary "toggle"(if expanded then "Collapse project" else "Expand project")(Input.ToggleProjectGroup id));
     declared key(Roles.NavigationEntry selected)(secondary "open"(project_name project)(Input.BeginTask(Some id)));
     declared key Roles.Button(secondary "create" "New task"(Input.BeginTask(Some id)));
     declared key Roles.Button(secondary "more" "Project actions"(Input.OpenObjectActions(ProjectActions id)(part key "more")))] ::
   if expanded then map(task_entry_tree current (State.collapsed_tasks s) key)(forest(project_tasks(Some id)tasks)) else []).
Definition rename_work s :=
 match State.active_work(State.navigation_state s)with
 |None=>[]
 |Some work=>[declared "/navigation" Roles.Button
   (secondary "rename-work" "Rename Work"(Input.OpenEditor(WorkName work)(part "/navigation" "rename-work")))]
 end.
Definition work_destinations s controls :=
 let navigation:=State.navigation_state s in
 let current:=State.location navigation in
 region "/navigation" "work-destinations" "Work destinations" Roles.NavigationSection
  (destination_node current "/global-navigation" graph_destination::
   List.app (match State.active_work navigation with None=>[]|Some work=>
    [declared "/navigation"(Roles.NavigationEntry(match current with SharedUI selected _=>N.eqb selected work|_=>false end))
      (secondary "work/shared-ui" "共享 UI"(Input.Navigate(SharedUI work
        (match current with SharedUI _ task=>task|_=>None end))))]
   end) controls).
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
       (information(part "/navigation" "independent-tasks")"title" Information.NavigationCaption "Tasks without a project"::
        map(task_entry_tree current (State.collapsed_tasks s) "/navigation")trees)]end in
   List.app(map(project_entry snapshot s current "/navigation" scoped)visible)independent
 |_,_=>[read_only "/navigation" "unavailable" "Tasks" "Task navigation observations unavailable"]end in
 region "/navigation" "contents" "" Roles.NavigationCollection
  (region "/navigation" "task-creation" "" Roles.NavigationSection
    [declared "/navigation"(Roles.NavigationEntry(same_route current Start))
      (secondary "new-task" "新建对话"(Input.BeginTask None))]::content).
Definition task_navigation snapshot s :=
 Node "/navigation" "navigation" "Task tree" Roles.Navigation Region
  [region "/navigation" "header" "Task tree" Roles.NavigationHeader
   (title(part "/navigation" "header") "Task tree"::rename_work s);
   work_destinations s [];
   task_collection snapshot s].
Definition desktop_task_navigation snapshot s :=
 let '(home_key,home_label,home_route):=home_destination in
 Node "/navigation" "navigation" "Task tree" Roles.Navigation Region
  [region "/navigation" "header" "Workspace" Roles.NavigationHeader
    [declared "/global-navigation" (Roles.NavigationEntry false)
      (secondary home_key home_label(Input.Navigate home_route));
     declared(part "/navigation" "header") Roles.Button
      (secondary "toggle" "Collapse Task sidebar"(Input.TaskListVisible false))];
   work_picker snapshot s "/work-tabs" "work/overview";
   work_destinations s (rename_work s);
   task_collection snapshot s;
   global_navigation s].
Definition work_summary snapshot selected :=
 match tasks snapshot with
 |None=>"Task observations unavailable"
 |Some all=>match work_tasks selected all with
  |[]=>"No tasks yet"
  |first::rest=>
    let count:=S(List.length rest)in
    (if Nat.eqb count 1 then "1 task"else show_natural(N.of_nat count)++" tasks")++
     " · "++task_title first++" · "++task_caption first
  end end.
Definition work_overview snapshot s parent :=
 let active:=State.active_work(State.navigation_state s)in
 let choice work name :=
   let key:=part parent(NavigationIdentity.work_key work)in
   Node key "work-choice" name Roles.Button
    (WorkChoice work(same_id active work)(secondary(NavigationIdentity.work_key work)name(Input.SelectWork work)))
    [information key "name" Information.OptionLabel name;
     information key "description" Information.Description(work_summary snapshot work)]in
 let entries:=choice None "All Tasks"::
   match works snapshot with
   |None=>[read_only parent "unavailable" "Works" "Work observations unavailable"]
   |Some entries=>map(fun work=>choice(Some(work_id work))(work_name work))entries end in
 [dialog_header parent
   [title parent "Works";
    declared parent Roles.Button(secondary "done" "Close work overview" Input.ClosePanel)];
  dialog_body parent [Node(part parent "work-choices")"work-choices" "Works" Roles.Section ChoiceGroup entries];
  dialog_actions parent
   [declared parent Roles.Button(observe_control(fun input=>domain_availability(Authoring.input_availability snapshot s input))(secondary "work/new" "New Work" Input.CreateWork))]].
Definition global_menu s parent :=
 let current:=State.location(State.navigation_state s)in
 [region parent "global-menu" "Global destinations" Roles.CompactNavigationMenu
   (List.app(map(fun entry=>let '(identity,label,target):=entry in
     declared parent(Roles.CompactNavigationEntry(same_route current target))
       (secondary identity label(Input.Navigate target)))(home_destination::destinations))
    [declared parent(Roles.CompactNavigationEntry false)
      (secondary "settings" "Settings"(Input.ServiceInput Services.OpenSettings))])].
Definition compact_header snapshot s :=
 region "/workspace" "compact-header" "Workspace navigation" Roles.CompactHeader
  [declared "/compact-header" Roles.Button (secondary "global" "Global navigation"(Input.OpenNavigation GlobalMenu(part "/compact-header" "global")));
   work_picker snapshot s "/compact-header" "works";
   declared "/compact-header" Roles.Button(secondary "tasks" (if SessionNavigation.expanded_for false s then "Back to conversation"else"Open Task list")(Input.NavigationExpanded(negb(SessionNavigation.expanded_for false s))))].
Definition navigation_base snapshot s capacity :=
 let expanded:=SessionNavigation.expanded_for(navigation_beside_content capacity)s in
 if navigation_beside_content capacity then
  if expanded then [desktop_task_navigation snapshot s] else
   [declared "/global-navigation" Roles.Button
     (secondary "tasks/expand" "Expand Task sidebar" (Input.TaskListVisible true))]
 else if expanded then[]else[compact_header snapshot s].
Definition navigation_layers snapshot s capacity :=
 if navigation_beside_content capacity || negb(SessionNavigation.expanded_for false s)then[]else
 [Node "/navigation/modal" "task-navigation" "Task tree" Roles.Dialog
  (NavigationRegion TasksDrawer(LayerBehavior ModalDialog false(State.generation(State.navigation_state s))
    "/navigation"(part "/compact-header" "tasks")"/main"(part "/compact-header" "tasks") (Input.NavigationExpanded false) true true))
  [dialog_header "/navigation/modal" [compact_header snapshot s];
   dialog_body "/navigation/modal" [task_navigation snapshot s]]].
