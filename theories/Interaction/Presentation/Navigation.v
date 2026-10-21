From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Interaction Require Import Identity Input Services Codec.
From Selvedge.Interaction.Session Require State Navigation Authoring.
Module SessionNavigation := Selvedge.Interaction.Session.Navigation.
From Selvedge.Interaction.Presentation Require Import Surface Model Construction Projection.
From Selvedge.Interaction.Presentation Require Roles Information.
Import ListNotations.
Open Scope string_scope.

Definition destination := (string * string * route)%type.
Definition destinations : list destination := [
 ("home","Home",Start);("history-search","搜索对话",HistorySearch);
 ("board","任务看板",Board);("projects","项目",Projects);
 ("agents","智能体",Agents);("task-graphs","Task graphs",Graphs)].
Definition route_eq_dec : forall a b:route,{a=b}+{a<>b}.
Proof. repeat decide equality. Defined.
Definition same_route a b := if route_eq_dec a b then true else false.
Definition destination_node compact current parent (entry:destination) :=
 let '(identity,label,target):=entry in
 declared parent (Roles.GlobalNavigationEntry(same_route current target)compact)
  (secondary identity label(Input.Navigate target)).
Definition global_navigation compact s :=
 let current:=State.location(State.navigation_state s) in
 region "/workspace" "global-navigation" "Global navigation" (Roles.GlobalNavigation compact)
  (List.app(map(destination_node compact current "/global-navigation")destinations)
   [declared "/global-navigation" (Roles.GlobalNavigationEntry false compact)
    (secondary "settings/open" "Settings" (Input.ServiceInput Services.OpenSettings))]).
Definition work_tab active (work:option N) label :=
 declared "/work-tabs" (Roles.WorkTab(same_id active work))
  (secondary (Identity.work_key work) label(Input.SelectWork work)).
Definition work_tabs snapshot s :=
 let active:=State.active_work(State.navigation_state s)in
 let entries:=match works snapshot with
 |None=>[read_only "/work-tabs" "unavailable" "Works" "Work observations unavailable"]
 |Some values=>map(fun work=>work_tab active(Some(work_id work))(work_name work))values end in
 region "/workspace" "work-tabs" "Works" Roles.WorkTabs
  ([work_tab active None "All Tasks";
    region "/work-tabs" "collection" "" Roles.WorkTabGroup entries;
    declared "/work-tabs" Roles.Button (observe_control(fun input=>domain_availability(Authoring.input_availability snapshot s input))(secondary "work/new" "New Work" Input.CreateWork));
    declared "/work-tabs" (Roles.WorkOverviewButton(N.of_nat(S(List.length(value_or[](works snapshot))))))
      (secondary "work/overview" "Work overview" (Input.OpenNavigation WorkOverview(part "/work-tabs" "work/overview")))]).
Fixpoint task_entry_tree current parent (tree:task_tree) : node Input.input :=
 let 'TaskTree task children:=tree in
 let key:=part parent("task/"++show_natural(task_id task))in
 Node key "task-entry" (task_title task) Roles.Section
  (TaskRow(task_id task)(task_status task)(task_caption task)(task_working task)(task_selected current task))
  ([declared key(Roles.NavigationEntry(task_selected current task))
      (secondary "open"(task_title task)(Input.Navigate(Conversation(task_id task))))] ++
   match children with
   |[]=>[]
   |_=>[Node(part key "children")"task-children" "" Roles.NavigationCollection
         (TaskChildren(task_id task))(map(task_entry_tree current key)children)]end)%list.
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
   if expanded then map(task_entry_tree current key)(forest(project_tasks(Some id)tasks)) else []).
Definition task_navigation snapshot s (expanded:bool) :=
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
        map(task_entry_tree current "/navigation")trees)]end in
   List.app(map(project_entry snapshot s current "/navigation" scoped)visible)independent
 |_,_=>[read_only "/navigation" "unavailable" "Tasks" "Task navigation observations unavailable"]end in
 let shared:=match State.active_work navigation with None=>[]|Some work=>
   [declared "/navigation"(Roles.NavigationEntry(match current with SharedUI selected _=>N.eqb selected work|_=>false end))
    (secondary "work/shared-ui" "共享 UI"(Input.Navigate(SharedUI work
      (match current with SharedUI _ task=>task|_=>None end))))]end in
 Node "/navigation" "navigation" "Task tree" Roles.Navigation Region
  (region "/navigation" "header" "Task tree" Roles.NavigationHeader
   (declared(part "/navigation" "header") Roles.Button
      (secondary "toggle"(if expanded then "Collapse Task sidebar"else"Expand Task sidebar")(Input.NavigationExpanded(negb expanded)))::
    match State.active_work navigation with None=>[]|Some work=>
     [declared "/navigation" Roles.Button(secondary "rename-work" "Rename Work"(Input.OpenEditor(WorkName work)(part "/navigation" "rename-work")))]end)::
   List.app shared(if expanded then
    [region "/navigation" "contents" "" Roles.NavigationCollection
      (region "/navigation" "task-creation" "" Roles.NavigationSection
        [declared "/navigation"(Roles.NavigationEntry(match current with Start=>true|_=>false end))
          (secondary "new-task" "新建对话"(Input.BeginTask None))]::content)]
    else [])).
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
Fixpoint work_choice_rows(parent:string)(index:N)(choices:list(node Input.input))
 {struct choices}:list(node Input.input):=match choices with
|[]=>[]
|first::rest=>
 let key:=part parent("work-row/"++show_natural index)in
 match rest with
 |[]=>[region parent("work-row/"++show_natural index)"" Roles.WorkChoiceRow
    [first;region key "gap" "" Roles.Section []]]
 |second::remaining=>
   region parent("work-row/"++show_natural index)"" Roles.WorkChoiceRow[first;second]::
   work_choice_rows parent(N.succ index)remaining
 end end.
Definition work_overview snapshot s parent :=
 let active:=State.active_work(State.navigation_state s)in
 let choice work name :=
   let key:=part parent(Identity.work_key work)in
   Node key "work-choice" name Roles.Button
    (WorkChoice work(same_id active work)(secondary(Identity.work_key work)name(Input.SelectWork work)))
    [information key "name" Information.OptionLabel name;
     information key "description" Information.Description(work_summary snapshot work)]in
 let entries:=choice None "All Tasks"::
   match works snapshot with
   |None=>[read_only parent "unavailable" "Works" "Work observations unavailable"]
   |Some entries=>map(fun work=>choice(Some(work_id work))(work_name work))entries end in
 [Node(part parent "work-choices")"work-choices" "Works" Roles.Section ChoiceGroup(work_choice_rows parent 0 entries);
  region parent "actions" "Actions" Roles.DialogActions
   [declared parent Roles.Button(observe_control(fun input=>domain_availability(Authoring.input_availability snapshot s input))(secondary "work/new" "New Work" Input.CreateWork));
    region parent "action-space" "" Roles.Section [];
    declared parent Roles.Button(secondary "done" "Done" Input.ClosePanel)]].
Definition global_menu s parent :=
 let current:=State.location(State.navigation_state s)in
 region parent "global-menu" "Global destinations" Roles.CompactNavigationMenu
 (List.app(map(fun entry=>let '(identity,label,target):=entry in
   declared parent(Roles.CompactNavigationEntry(same_route current target))
     (secondary identity label(Input.Navigate target)))destinations)
  [declared parent(Roles.CompactNavigationEntry false)(secondary "settings" "Settings"(Input.ServiceInput Services.OpenSettings));
   declared parent Roles.Button(secondary "done" "Done" Input.ClosePanel)]).
Definition compact_header snapshot s :=
 let navigation:=State.navigation_state s in
 let work_label:=match State.active_work navigation with
 |None=>"All Tasks"|Some id=>match find_work id snapshot with Some work=>work_name work|None=>"Work unavailable"end end in
 region "/workspace" "compact-header" "" Roles.CompactHeader
  [declared "/compact-header" Roles.Button (secondary "global" "Global navigation"(Input.OpenNavigation GlobalMenu(part "/compact-header" "global")));
   declared "/compact-header"(Roles.CompactWorkScope work_label (N.of_nat(S(List.length(value_or[](works snapshot))))))(secondary "works"work_label(Input.OpenNavigation WorkOverview(part "/compact-header" "works")));
   declared "/compact-header" Roles.Button(secondary "tasks" "Open Task list"(Input.NavigationExpanded(negb(SessionNavigation.expanded_for false s))))].
Definition navigation_base snapshot s capacity :=
 let expanded:=SessionNavigation.expanded_for(navigation_beside_content capacity)s in
 if navigation_beside_content capacity then
  [global_navigation false s;work_tabs snapshot s;task_navigation snapshot s expanded]
 else if expanded then[]else[compact_header snapshot s].
Definition navigation_layers snapshot s capacity :=
 if navigation_beside_content capacity || negb(SessionNavigation.expanded_for false s)then[]else
 [Node "/navigation/modal" "task-navigation" "Task tree" Roles.Dialog
  (LayerRegion(LayerBehavior ModalDialog false(State.generation(State.navigation_state s))
    "/navigation"(part "/compact-header" "tasks")"/main"(part "/compact-header" "tasks") (Input.NavigationExpanded false) true true))
  [compact_header snapshot s;task_navigation snapshot s true]].
