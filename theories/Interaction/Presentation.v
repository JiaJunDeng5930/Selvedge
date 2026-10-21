From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers Schema TextJson.
From Selvedge.Kernel Require Import Commands Conversation Streams.
From Selvedge.Kernel Require Search.
From Selvedge.Features Require BoardFilter.
From Selvedge.Interaction Require Documents.
From Selvedge.Interaction Require Import Codec Identity Resource Services Forms Speech ApplicationState ApplicationOps Origin Input InputCodecs Scene ApplicationCore SkillMention.
From Selvedge.Interaction Require Audit.
From Selvedge.Interaction Require Export SceneBuilders.
From Selvedge.Interaction Require ObjectActions Navigation ActivityPresentation Experience ExperienceObservation ExperienceAssessment Activities.
Import ListNotations.
Open Scope string_scope.

Definition optional_label id := match id with None=>"All Tasks"|Some id=>"Work #"++show_natural id end.
Fixpoint join_text delimiter xs := match xs with []=>""|[x]=>x|x::xs=>x++delimiter++join_text delimiter xs end.
Definition option_node value caption := JObject[("value",value);("label",JString caption)].
Definition key_suffix key id := key++show_natural id.
Definition project_choices world := map(fun p=>option_node(value_or JNull(field "project_id" p))(text "name" p))(items "projects" world).
Definition project_options world := option_node(JString "")"Environment defaults"::project_choices world.
Fixpoint kind_options k (world:json) := match k with
|KEnum first rest=>map(fun s=>option_node(JString s)s)(first::rest)
|KOptional k=>option_node(JString "")"Use default"::kind_options k world
|_=>[]end.
Fixpoint kind_name k :=match k with KText=>"text"|KBool=>"bool"|KNatural=>"natural"|KInteger=>"integer"|KDecimal=>"decimal"|KJson=>"json"|KArray KText=>"array_text"|KArray _=>"json"|KOptional k=>kind_name k|KEnum _ _=>"text"end.
Definition field_value f d (world:json)(s:ApplicationState.state) := match raw_text(field_name(specification f))d with Some s=>JString s|None=>
  match Schema.field_kind(specification f),get(field_name(specification f))d with
  |KArray KText,JArray xs=>JString(join_text(String(Ascii.ascii_of_nat 10)"")(map(fun j=>value_or ""(as_string j))xs))
  |KOptional _,JNull=>JString ""|_,v=>v end end.
Definition field_keys : list (string * (editor -> string)) := [
  ("message", fun e => "message-text");
  ("profile", fun e => "model-profile");
  ("reasoning", fun e => "reasoning-effort");
  ("primary_root", fun e => "workspace-primary");
  ("roots", fun e => "workspace-directories");
  ("project_id", fun e => "context-origin");
  ("sandbox", fun e => "sandbox-mode");
  ("network_access", fun e => "network-access");
  ("approval", fun e => "approval-policy");
  ("reviewer_profile", fun e => "approval-reviewer");
  ("create_worktree", fun e => "create-worktree");
  ("task_environment", fun e => "task-environment");
  ("delivery", fun e => "delivery-intent");
  ("name", fun e => match e with WorkName _=>"work-name"|Project _=>"project-name"|Agent _=>"agent-name"|_=>"name"end);
  ("title", fun e => "card-title");
  ("description", fun e => "card-description");
  ("status", fun e => "card-stage");
  ("priority", fun e => "card-priority");
  ("assignee", fun e => "card-owner");
  ("project", fun e => "card-project");
  ("labels", fun e => "card-labels");
  ("keep_open", fun e => "continue-capture");
  ("assisted", fun e => "assisted-capture");
  ("draft_profile", fun e => "assistance-profile");
  ("instructions", fun e => "agent-instructions");
  ("concurrency", fun e => "agent-concurrency");
  ("child_count", fun e => "fork-count");
  ("messages", fun e => "fork-messages");
  ("summary", fun e => "compaction-summary");
  ("declaration", fun e => "task-graph-declaration");
  ("task_prompt", fun e => "task-title-prompt");
  ("agent_prompt", fun e => "agent-title-prompt")
].
Definition field_key e name:=match find (fun entry => String.eqb (fst entry) (name)) field_keys with
  | Some (_, render) => render e | None => (name)
  end.
Definition field_owner_key e name:=
 if existsb(String.eqb name)["roots";"primary_root"]then "workspace/"++editor_key e else
 if existsb(String.eqb name)["profile";"reasoning";"sandbox";"network_access";"approval";"reviewer_profile"]then "execution-configuration/"++editor_key e else
 match e with Message task=>"message-draft/"++show_natural task|Project id=>"project/"++id_text id|TaskGraph id _=>"task-graph/"++id_text id|_=>"editor/"++editor_key e end.
Definition mention_keys e world s:=match mention_for e s with Suggesting _ _=>
 List.app [("ArrowDown",Input.SkillMove e false);("ArrowUp",Input.SkillMove e true);("Escape",Input.SkillDismiss e)] (
 match highlighted(catalog_for e world s)(mention_for e s)with None=>[]|Some skill=>[("Enter",Input.SkillSelected e(skill_path skill));("Tab",Input.SkillSelected e(skill_path skill))]end)|_=>[]end.
Definition skill_option_key e index skill := editor_key e++"/skill/"++Scene.key_component(skill_path skill)++"/"++show_natural(N.of_nat index).
Definition mention_attributes e world s :=
 let options:=mention_candidates(catalog_for e world s)(mention_for e s)in
 List.app [("role",JString "combobox");("aria-autocomplete",JString "list");
  ("aria-haspopup",JString "listbox");("aria-expanded",JString(match options with []=>"false"|_=>"true"end));
  ("aria-controls",JString(editor_key e++"/skill-suggestions"))]
 (match highlighted_choice(catalog_for e world s)(mention_for e s)with None=>[]|Some(index,skill)=>
  [("aria-activedescendant",JString(skill_option_key e index skill))]end).
Definition mention_suggestions e world s :=
 let options:=mention_candidates(catalog_for e world s)(mention_for e s)in
 match options with []=>group(editor_key e++"/skill-suggestions")[]|_=>
 node Scene.ListView_role(editor_key e++"/skill-suggestions")
  [("layout",JsonProperty(JString "anchored-listbox"));("attrs",JsonProperty(JObject
   [("role",JString "listbox");("data-anchor",JString(editor_key e++"/message"));("data-anchor-focus",JString "true")]))]
  (map(fun '(index,skill)=>let selected:=match highlighted_choice(catalog_for e world s)(mention_for e s)with
   Some(current,_)=>Nat.eqb current index|None=>false end in
   Scene.ActionButton(skill_option_key e index skill)
    [("label",JString(skill_name skill));("help",JString(skill_description skill));("layout",JString "skill-option");("attrs",JObject
      [("role",JString "option");("tabindex",JString "-1");("aria-selected",JString(if selected then "true"else "false"));
       ("data-retain-focus",JString "true");("data-reveal-on-layout",JString(if selected then "true"else "false"))])]
    (Some(Input.SkillSelected e(skill_path skill)))false
    [node Scene.Text_role(skill_option_key e index skill++"/description")[("value",JsonProperty(JString(skill_description skill)));("attrs",JsonProperty(JObject[("class",JString "skill-description")]))][];
     node Scene.Text_role(skill_option_key e index skill++"/path")[("value",JsonProperty(JString(skill_path skill)));("attrs",JsonProperty(JObject[("class",JString "skill-path")]))][]])(combine(seq 0(List.length options))options))
 end.
Definition field_disabled e name world:=match e with
 |Card(Some id)=>match find_world "cards" "card_id" id(value_or JNull(field "board" world))with None=>true|Some card=>
  if String.eqb name "keep_open"then false else
  negb(flag(if existsb(String.eqb name)["title";"description";"assignee";"project";"assisted";"draft_profile"]then "edit"else "metadata")(value_or JNull(field "capabilities" card)))end
 |_=>false end.
Definition worktree_unavailable d world s := negb(workspace_git_available d world(service_state s)).
Definition preserve_selected selected options :=
 if Json.equal selected(JString "") || Json.equal selected JNull || existsb(fun choice=>Json.equal selected(value_or JNull(field "value" choice)))options
 then options else option_node selected("当前选择已不可用："++value_or ""(as_string selected))::options.
Definition field_applies d name :=
 if String.eqb name "draft_profile"then read_flag "assisted" d else true.
Definition attachment_field e:=match e with NewTask _|Message _=>Some "message"|Card _=>Some "description"|_=>None end.
Definition can_attach e:=match attachment_field e with Some _=>true|None=>false end.
Definition attach_action e:=invoke(Input.ServiceInput(AddFile e(SelectedFile "" "" "" 0))).
Definition workspace_option_caption value :=
 if String.eqb value "current"then "Current workspace"else
 if String.eqb value(WorkspaceBackend.name WorkspaceBackend.Local)then "Local worktree"else "Tencent Cloud CVM".
Definition workspace_options := map(fun value=>option_node(JString value)(workspace_option_caption value))
 ("current"::managed_workspace_names).
Definition field_scene d world s f :=
  let name:=field_name(specification f)in let key:=editor_key(owner d)++"/"++name in
  let efforts:=ModelSelection.reasoning_values world(read_text "profile" d)in
  let reasoning:=String.eqb name "reasoning" && negb(match efforts with []=>true|_=>false end)in
  let select:=reasoning||String.eqb(widget f)"select"||String.eqb(widget f)"profile"||String.eqb(widget f)"project"in
  let kind:=if select then Scene.Select_role else if String.eqb(widget f)"checkbox"then Scene.Checkbox_role else Scene.Field_role in
  let options:=if reasoning then map(fun value=>option_node(JString value)value)efforts else
   if String.eqb(widget f)"profile"then (match Schema.field_kind(specification f)with KOptional _=>option_node(JString "")"继承默认值"::profile_choices world|_=>profile_choices world end)
   else if String.eqb(widget f)"project"then project_options world
   else if String.eqb name "task_environment"then workspace_options else kind_options(Schema.field_kind(specification f))world in
  let options:=if select then preserve_selected(field_value f d world s)options else options in
  node kind key[("disabled",JsonProperty(JBool(field_disabled(owner d)name world || (String.eqb name "create_worktree" && worktree_unavailable d world s))));("specification",FieldProperty(specification f));("keys",KeyProperty(if String.eqb name "message"then mention_keys(owner d)world s else []));("attrs",JsonProperty(JObject([("data-field",JString(field_key(owner d)name));("data-object-owner",JString(field_owner_key(owner d)name))]++if String.eqb name "message"then mention_attributes(owner d)world s else [])));("label",JsonProperty(JString(label f)));("value",JsonProperty(field_value f d world s));("value_kind",JsonProperty(JString(kind_name(Schema.field_kind(specification f)))));("action",InputProperty(edit_action(owner d)name));
    ("file_action",InputProperty(if connected(service_state s) && (match attachment_field(owner d)with Some target=>String.eqb name target|None=>false end)then attach_action(owner d)else UiAction None));
    ("multiline",JsonProperty(JBool(existsb(String.eqb(widget f))["textarea";"lines";"json";"graph_nodes";"graph_rules"])));
    ("options",JsonProperty(JArray options));("help",JsonProperty(JString(help f)));("invalid",JsonProperty(JBool(match raw_text name d with Some _=>true|None=>false end)))]
    (List.app (if String.eqb name "message"then [mention_suggestions(owner d)world s]else
      if existsb(String.eqb name)["roots";"primary_root";"project_id";"sandbox";"network_access";"approval";"reviewer_profile"]then
       [button(key++"/source")"查看来源"(invoke(Input.InspectSource(owner d)name(key++"/source")))false]else []) (if String.eqb(widget f)"directory"then [button(key++"/browse")"Browse"(invoke(Input.ServiceInput(OpenDirectory (owner d) (read_text name d) (key++"/browse"))))false]else [])).
Definition upload_scene d s :=map(fun upload=>match upload with
|Loading t r=>group("upload/"++show_natural t)[text_node("upload/"++show_natural t++"/name")(file_name(upload_file r));button("upload/"++show_natural t++"/cancel")"Cancel upload"(invoke(Input.ServiceInput(CancelUpload t)))false]
|Resource.Failed t r error=>group("upload/"++show_natural t)[text_node("upload/"++show_natural t++"/error")error;button("upload/"++show_natural t++"/retry")"Retry upload"(invoke(Input.ServiceInput(RetryUpload t)))(negb(connected(service_state s)));button("upload/"++show_natural t++"/cancel")"Remove"(invoke(Input.ServiceInput(CancelUpload t)))false]
|_=>group "unused-upload"[]end)
  (filter(fun r=>match upload_owner r with Some e=>same_editor(owner d)e|None=>false end)(uploads(service_state s))).
Definition image_scene key id caption:=node Scene.Image_role key[("url",JsonProperty(JString("/api/board/attachments/"++id)));("label",JsonProperty(JString caption))][].
Definition attachment_scene d :=map(fun a=>group(editor_key(owner d)++"/attachment/"++asset_id a)
 ((if passive_image a then [image_scene(editor_key(owner d)++"/attachment/"++asset_id a++"/image")(asset_id a)(asset_name a)]else [])++[button(editor_key(owner d)++"/attachment/"++asset_id a++"/preview")("Preview "++asset_name a)(invoke(Input.ServiceInput(OpenPreview (a) (editor_key(owner d)++"/attachment/"++asset_id a++"/preview"))))false;
  button(editor_key(owner d)++"/attachment/"++asset_id a++"/remove")"Remove attachment"(invoke(Input.RemoveAttachment (owner d) (asset_id a)))false]))(attachments d).
Definition can_speak e:=match e with NewTask _|Message _=>true|_=>false end.
Definition execution_entries task world :=
 match initialize(Execution task)world with
 |None=>[]
 |Some observed=>List.app(ActivityPresentation.property_entry observed world true ExperienceObservation.ModelFamily)
   (ActivityPresentation.property_entry observed world true ExperienceObservation.PermissionFamily)
 end.
Definition form_scene e world s :=
  (* Accepting a message clears its Send action; the initiating composer remains
     the return point when its side conversation is closed. *)
  let submission_trigger:=editor_key e++match e with Message _=>"/message"|_=>"/submit"end in
  let d:=value_or(new_draft e)(option_map fst(ensure e world s))in
  let assessed:=ExperienceAssessment.assess_draft d world(service_state s)(editor_pending e s)in
  let blocked:=negb(Experience.can_prepare assessed)in
  let caption:=match e with Message _=>if String.eqb(read_text "delivery" d)"steer"then "Steer"else "Send"|NewTask _=>"Start task"|Fork _=>"Fork task"|Compact _=>"Compact history"|_=>"Save"end in
  let composer_fields:=filter(fun f=>String.eqb(field_name(specification f))"message" ||
    match meaning f with Scalar|TaskEnvironmentSelection=>true|_=>false end)(form_fields e)in
  let ordinary_fields:=filter(fun f=>negb(String.eqb(field_name(specification f))"revision")&&field_applies d(field_name(specification f))&&
    match meaning f with Scalar|ProjectWorktreePreference|TaskEnvironmentSelection=>true|_=>false end)(form_fields e)in
  let field_nodes := ((match e with
   |NewTask _=>ActivityPresentation.property_entry d world false ExperienceObservation.ProjectFamily++
     ActivityPresentation.property_entry d world false ExperienceObservation.WorkspaceFamily++
     map(field_scene d world s)composer_fields++
     ActivityPresentation.property_entry d world false ExperienceObservation.ModelFamily++
     ActivityPresentation.property_entry d world false ExperienceObservation.PermissionFamily
   |Message task=>map(field_scene d world s)(filter(fun f=>String.eqb(field_name(specification f))"message")(form_fields e))++
     execution_entries task world++
     ActivityPresentation.property_entry d world true ExperienceObservation.DeliveryFamily
   |_=>map(field_scene d world s)ordinary_fields++
     flat_map(ActivityPresentation.property_entry d world false)
      [ExperienceObservation.ProjectFamily;ExperienceObservation.WorkspaceFamily;ExperienceObservation.ModelFamily;ExperienceObservation.PermissionFamily;ExperienceObservation.DeliveryFamily]end)++attachment_scene d++upload_scene d s)%list in
  let control_nodes := ((if can_attach e then [node Scene.Field_role(editor_key e++"/upload")[("disabled",JsonProperty(JBool(negb(connected(service_state s)))));("label",JsonProperty(JString "Attach files"));("attrs",JsonProperty(JObject[("type",JString "file");("multiple",JString "true")]));("action",InputProperty(attach_action e))][]]else [])++
   (if can_speak e then [button(editor_key e++"/dictate")"Dictate"(invoke(Input.SpeechInput(BeginDictation (e) (revision d))))(negb(free(speech_state s)));
      button(editor_key e++"/skills")"Skills"(invoke(Input.LoadSkills (e)))false]else [])++
   (match e with NewTask _=>if cloud_workspace d then
      [text_node(editor_key e++"/cloud-voice")"Create the cloud task before starting voice"]else
      [button(editor_key e++"/voice-new")"Start voice task"(invoke(Input.BeginVoiceNew e))(negb(free(speech_state s))||match voice_obstruction world(service_state s)d with Some _=>true|None=>false end)]|_=>[]end)++
   (if (local_worktree d || existsb(fun f=>String.eqb(field_name(specification f))"create_worktree")(form_fields e))&&worktree_unavailable d world s
    then [text_node(editor_key e++"/worktree-availability")"工作区的 Git 能力尚未确认，或此目录不可创建工作树。"]else [])++
   (match e with TitlePrompts=>[button "title-prompts/reset" "Reset title prompts"(invoke(Input.ResetTitlePrompts))false]|_=>[]end)++
   feedback_scene d++ActivityPresentation.assessment_scene assessed++[button(editor_key e++"/submit")caption(invoke(Input.Submit e submission_trigger))blocked])%list in
  node Scene.Form_role(editor_key e)[("attrs",JsonProperty(JObject[("tabindex",JString "-1")]));("action",InputProperty(invoke(Input.Submit e submission_trigger)));("label",JsonProperty(JString caption))]
  (field_nodes ++ match e with
   |Message _=>[node Scene.Group_role(editor_key e++"/controls")[("layout",JsonProperty(JString "row"))]control_nodes]
   |_=>control_nodes end).
Definition task_title := Navigation.task_title.
Definition task_id t :=natural_field "id" t.
Definition task_button_at prefix current t :=match task_id t with None=>group(prefix++"/invalid-task")[]|Some id=>
 let key:=prefix++"/task/"++show_natural id in
 let selected:=Navigation.route_selected current(Conversation id)in
 node Scene.Group_role(key++"/row")[("layout",JsonProperty(JString "task-row"));
  ("attrs",JsonProperty(JObject[("data-selected",JString(if selected then "true"else "false"))]))]
 [Scene.ActionButton key[("label",JString(Navigation.task_title t));("icon",JString(Navigation.task_status_icon t));
  ("attrs",JObject([("aria-label",JString(Navigation.task_title t++", "++Navigation.task_status_caption t));
    ("title",JString(Navigation.task_title t++" · "++Navigation.task_status_caption t))]++
    if selected then [("aria-current",JString "page")]else []))]
   (Some(Input.Navigate(Conversation id)))false[];
  icon_button(key++"/more")"More" "more-dots"(invoke(Input.OpenObjectActions(TaskActions id)(key++"/more")))false]end.
Definition task_button current := task_button_at "navigation" current.
Definition task_parent task:=match field "parent" task with Some value=>value_or None(decode_id value)|None=>None end.
Definition task_forest current tasks:=
 map snd(fold_right(fun task pending=>match natural_field "id" task with None=>pending|Some id=>
   let children:=filter(fun entry=>match fst entry with Some parent=>N.eqb id parent|None=>false end)pending in
   let roots:=filter(fun entry=>match fst entry with Some parent=>negb(N.eqb id parent)|None=>true end)pending in
   (task_parent task,node Scene.Group_role("task-tree/"++show_natural id)[("layout",JsonProperty(JString "task-branch"))](task_button current task::map snd children))::roots end)
   ([]:list(option N*Scene.scene Input.input))tasks).
Definition task_project := Navigation.task_project.
Definition project_task_group world s project:=match natural_field "project_id" project with None=>group "invalid-project"[]|Some id=>
 let key:="navigation/project/"++show_natural id in
 let tasks:=Navigation.project_navigation_tasks id(active_work(navigation_state s))world in
 let selected:=same_scope(Some id)(Navigation.active_project world s)in
 let closed:=existsb(N.eqb id)(collapsed_projects s)in
 node Scene.Group_role key[("layout",JsonProperty(JString "project-task-group"))]
  [node Scene.Group_role(key++"/row")[("layout",JsonProperty(JString "project-row"));
    ("attrs",JsonProperty(JObject[("data-selected",JString(if selected then "true"else "false"))]))]
    [Scene.ActionButton(key++"/toggle")[("label",JString "Toggle project tasks");("icon",JString(if closed then "chevron-right"else "chevron-down"));
       ("attrs",JObject[("aria-expanded",JString(if closed then "false"else "true"));("aria-controls",JString(key++"/tasks"))])]
      (Some(Input.ToggleProjectGroup id))false[];
     Scene.ActionButton(key++"/open")[("label",JString(text "name" project));("icon",JString "folder");
       ("attrs",JObject[("aria-pressed",JString(if selected then "true"else "false"))])](Some(Input.BeginProjectTask id))false[];
     icon_button(key++"/new")"New task" "plus"(invoke(Input.BeginProjectTask id))false;
     icon_button(key++"/more")"More" "more-dots"(invoke(Input.OpenObjectActions(ProjectActions id)(key++"/more")))false];
   node Scene.Group_role(key++"/tasks")[("layout",JsonProperty(JString "project-tasks"))](if closed then []else task_forest(location(navigation_state s))tasks)]end.
Definition navigation_tasks world s : list(Scene.scene Input.input):=
 map(project_task_group world s)(Navigation.projects_in_navigation(active_work(navigation_state s))world)++
 [heading "independent-task-heading" "Independent tasks";
  group "independent-task-tree"(task_forest(location(navigation_state s))(filter(fun task=>match task_project task,natural_field "id" task with None,Some id=>task_belongs(active_work(navigation_state s))id world|_,_=>false end)(items "tasks" world)))].
Definition work_button work caption s :=
 let selected:=same_scope work(active_work(navigation_state s))in
 Scene.ActionButton(work_tab_key work)
  [("label",JString caption);("attrs",JObject
    (("aria-pressed",JString(if selected then "true"else "false"))::
     if selected then [("data-reveal-on-layout",JString "true")]else []))]
  (Some(Input.SelectWork work))false[].
Definition destination_button prefix current (destination:Navigation.destination) :=
 Scene.ActionButton(prefix++Navigation.destination_key destination)
  [("label",JString(Navigation.destination_label destination));("icon",JString(Navigation.destination_icon destination));("attrs",JObject
    (if Navigation.route_selected current(Navigation.destination_route destination)
      then [("aria-current",JString "page")]else []))]
  (Some(Input.Navigate(Navigation.destination_route destination)))false[].
Definition global_navigation prefix (world:json) s :=
 node Scene.Navigation_role (prefix++"global-navigation")[("layout",JsonProperty(JString "global-navigation"));("label",JsonProperty(JString "Main navigation"))]
  (heading (prefix++"brand") "Selvedge"::map(destination_button prefix(location(navigation_state s)))Navigation.global_destinations++
   [Scene.ActionButton (prefix++"nav/settings")[("label",JString "Settings");("icon",JString "settings");
    ("attrs",JObject(if String.eqb prefix ""then [("data-focus-alias",JString "settings-return")]else []))]
    (Some(Input.ServiceInput OpenSettings))false[]]).
Definition work_switcher world s :=
 let work:=active_work(navigation_state s)in
 node Scene.Group_role "work-switcher"[("layout",JsonProperty(JString "responsive-alternative"))]
  [node Scene.Navigation_role "work-tabs"[("layout",JsonProperty(JString "simultaneous-only"));("label",JsonProperty(JString "Works"))]
    (work_button None "All Tasks" s::
     map(fun w=>match natural_field "work_id" w with None=>group "invalid-work"[]|Some id=>work_button(Some id)(text "name" w)s end)(items "works" world)++
     [button "work/create" "New Work"(invoke(Input.CreateWork))(negb(connected(service_state s)))]);
   node Scene.Group_role "compact-work-switcher"[("layout",JsonProperty(JString "sequential-only"))]
    [Scene.ActionButton(work_tab_key work)
      [("label",JString(Navigation.work_label work world));("attrs",JObject[("aria-haspopup",JString "dialog")])]
      (Some(Input.OpenNavigation WorkOverview(work_tab_key work)))false
      [text_node "current-work-summary"(Navigation.work_summary work world)]]].
Definition navigation_header world s :=
 let n:=navigation_state s in
 node Scene.Header_role "navigation-header"[("layout",JsonProperty(JString "navigation-header"))]
  [node Scene.Group_role "compact-global-menu"[("layout",JsonProperty(JString "sequential-only"))]
    [Scene.ActionButton "global-navigation-toggle"
      [("label",JString "Global menu");("icon",JString "menu-lines");("attrs",JObject[("aria-haspopup",JString "dialog");("data-focus-alias",JString "settings-return")])]
      (Some(Input.OpenNavigation GlobalMenu "global-navigation-toggle"))false[]];
   work_switcher world s;
   let drawer:=Navigation.tasks_drawer_open s in
   let beside:=expanded n||drawer in
   node Scene.Group_role "task-navigation-toggle-placement"[("layout",JsonProperty(JString "responsive-alternative"))]
    [node Scene.Group_role "task-navigation-toggle-beside"[("layout",JsonProperty(JString "simultaneous-only"))]
      [Scene.ActionButton "navigation-toggle"
       [("label",JString(if beside then "Collapse Task sidebar"else "Expand Task sidebar"));
        ("icon",JString(if beside then "sidebar-close"else "sidebar"));
        ("attrs",JObject[("aria-expanded",JString(if beside then "true"else "false"));("aria-controls",JString "task-tree")])]
       (Some(Input.NavigationExpanded(negb beside)))false[]];
     node Scene.Group_role "task-navigation-toggle-drawer"[("layout",JsonProperty(JString "sequential-only"))]
      [Scene.ActionButton "navigation-toggle"
       [("label",JString(if drawer then "Close Task list"else "Open Task list"));
        ("icon",JString(if drawer then "sidebar-close"else "sidebar"));
        ("attrs",JObject[("aria-expanded",JString(if drawer then "true"else "false"));("aria-controls",JString "task-tree");("aria-haspopup",JString "dialog")])]
       (Some(if drawer then Input.ClosePanel else Input.OpenNavigation TasksDrawer "navigation-toggle"))false[]]]].
Definition task_navigation world s :=
 let n:=navigation_state s in
 node Scene.Navigation_role "task-tree"
  [("layout",JsonProperty(JString "task-navigation"));("label",JsonProperty(JString "Tasks"));
   ("attrs",JsonProperty(JObject[("data-expanded",JString(if expanded n then "true"else "false"));("data-drawer-open",JString(if Navigation.tasks_drawer_open s then "true"else "false"))]));
   ("dismiss_action",InputProperty(invoke Input.ClosePanel))]
  ([icon_button "nav/new-task" "新建对话" "plus"(navigation_action Start)false]++
   (match active_work n with None=>[]|Some work=>[group "work/tabs"
    [button "work/tasks" "Tasks"(navigation_action Start)false;
     button "work/shared-ui" "Shared UI"(navigation_action(SharedUI work None))false;
     editor_button "work/name" "Rename Work"(WorkName work)]]end)++navigation_tasks world s).
Definition navigation_scene world s :=
 node Scene.Group_role "navigation"[("layout",JsonProperty(JString "workspace-navigation"))]
  [global_navigation "" world s;navigation_header world s;task_navigation world s].
Definition work_overview world s :=
 let choices:=Navigation.work_choices world in
 node Scene.Dialog_role "work-overview"
  [("label",JsonProperty(JString "Works"));("dismiss_action",InputProperty(invoke Input.ClosePanel))]
  (heading "work-overview/title" "Works"::
   map(fun work=>Scene.ActionButton(Navigation.work_overview_key work)
    [("label",JString(Navigation.work_label work world));("attrs",JObject
      [("aria-pressed",JString(if same_scope work(active_work(navigation_state s))then "true"else "false"))])]
    (Some(Input.SelectWork work))false[text_node(Navigation.work_overview_key work++"/summary")(Navigation.work_summary work world)])choices++
   [button "work-overview/create" "New Work"(invoke Input.CreateWork)(negb(connected(service_state s)));
    button "work-overview/close" "Close"(invoke Input.ClosePanel)false]).
Definition global_navigation_dialog world s :=
 node Scene.Dialog_role "global-navigation-dialog"
  [("label",JsonProperty(JString "Global navigation"));("dismiss_action",InputProperty(invoke Input.ClosePanel))]
  [global_navigation "global-navigation-dialog/" world s;button "global-navigation/close" "Close"(invoke Input.ClosePanel)false].
Definition history_text message :=value_or ""(Conversation.json_message_text message).
Definition audit_failed := Audit.failed.
Definition audit_titles : list (string * (json -> string)) := [
  ("function_call", fun message => "Tool call: "++text "name"(value_or JNull(field "content" message)));
  ("function_output", fun message => "Tool output");
  ("operation_result", fun message => text "tool" message);
  ("hook_record", fun message => "Tool permission check");
  ("approval_record", fun message => "Approval: "++text "decision"(value_or JNull(field "content" message)));
  ("after_record", fun message => "Tool result processing");
  ("fork_result", fun message => "Task fork");
  ("context_replacement", fun message => "Context compacted");
  ("reasoning_record", fun message => "Reasoning: "++text "effort"(value_or JNull(field "content" message)));
  ("error", fun message => history_text message);
  ("task_context", fun message => if String.eqb(text "type" message)"reasoning_configuration"then "Reasoning changed to "++text "effort" message else "Task configuration");
  ("model_context", fun _ => "Model activity");
  ("tool_receipt", fun message => text "name"(value_or JNull(field "call" message)))
].
Definition audit_title message:=match find (fun entry => String.eqb (fst entry) (text "role" message)) audit_titles with
  | Some (_, render) => render message | None => "Conversation event"
  end.
Definition audit_expanded task index message s:=match find(fun reader=>N.eqb task(reading_task reader))(readers s)with
 |None=>audit_failed message|Some reader=>match find(fun '(group,occurrence,_)=>N.eqb index group)(disclosures reader)with Some(_,_,open)=>open|None=>audit_failed message end end.
Definition message_scene namespace task index message s :=
  let anchor:=history_key task(N.of_nat index) in
  let source:=history_text message in
  let origin:=bind(field "origin" message)decode_origin in
  let key:=match origin with Some o=>content_key namespace task o|None=>anchor++"/content"end in
  let observed:=match origin with Some o=>[("origin",JsonProperty(observation_origin namespace task o));("document_key",JsonProperty(JString key));("epoch",JsonProperty(number(epoch_for_key key s)));("revision",JsonProperty(number(N.of_nat(String.length source))));("ending",JsonProperty(JString "complete"))]|None=>[]end in
  node Scene.Section_role anchor[("attrs",JsonProperty(JObject[("data-reading-anchor",JString anchor)]))]
    (if existsb(String.eqb(value_or ""(Conversation.json_message_role message)))["user";"assistant"]then
      [text_node(anchor++"/role")(value_or "event"(Conversation.json_message_role message));
       node Scene.Markdown_role key(("value",JsonProperty(JString source))::("complete",JsonProperty(JBool true))::observed)[]]
     else let open:=audit_expanded task(N.of_nat index)message s in
      [button(anchor++"/disclose")(audit_title message)(invoke(Input.SetDisclosure task(N.of_nat index)0(negb open)))false]++
      if open then [node Scene.Code_role(anchor++"/detail")[("value",JsonProperty(JString(render_json message)))][]]else []).
Definition activity_expanded task group attention s :=
 match find(fun reader=>N.eqb task(reading_task reader))(readers s)with
 |Some reader=>match find(fun '(id,occurrence,_)=>N.eqb group id)(disclosures reader)with
   |Some(_,_,open)=>open|None=>negb(N.eqb attention 0)end
 |None=>negb(N.eqb attention 0)end.
Definition activity_summary entries :=
 match Audit.latest_failure entries with
 |Some index=>match find(fun entry=>Nat.eqb index(fst entry))entries with
   |Some(_,message)=>"失败："++audit_title message|None=>"失败"end
 |None=>match rev entries with (_,message)::_=>audit_title message|[]=>"活动"end end++
 " · "++show_natural(N.of_nat(List.length entries))++" 条事件 · "++show_natural(N.of_nat(Audit.operation_count entries))++" 次操作".
Definition activity_scene task first rest s :=
 let entries:=first::rest in let identity:=N.of_nat(fst first)in
 let attention:=Audit.attention entries in
 let key:=history_key task identity in let open:=activity_expanded task identity attention s in
 node Scene.Section_role(key++"/activity")[("attrs",JsonProperty(JObject[("data-reading-anchor",JString key)]))]
 (button(key++"/disclose")(activity_summary entries)(invoke(Input.SetDisclosure task identity attention(negb open)))false::
  if open then map(fun '(index,message)=>let anchor:=history_key task(N.of_nat index)in
   node Scene.Section_role anchor[("attrs",JsonProperty(JObject[("data-reading-anchor",JString anchor)]))]
    [text_node(anchor++"/title")(audit_title message);node Scene.Code_role(anchor++"/detail")[("value",JsonProperty(JString(render_json message)))][]])entries else []).
Definition history_scenes namespace task index messages s :=
 map(fun entry=>match entry with
 |Audit.Spoken(index,message)=>message_scene namespace task index message s
 |Audit.Activity first rest=>activity_scene task first rest s end)(Audit.groups index messages).
Definition live_scene namespace viewer world output s :=
  let phase:=match find_task(output_task output)world with Some t=>value_or JNull(field "model_pending" t)|None=>JNull end in
  let mode:=bind(string_field "mode" phase)decode_mode in
  map(fun item=>let source:=snd item in
    let origin:=option_map(fun m=>OutputOrigin(output_task output)(output_operation output)(fst item)m)mode in
    let fallback:="task/"++show_natural viewer++"/output/"++show_natural(output_operation output)++"/"++show_natural(fst item)in
    let key:=match origin with Some o=>content_key namespace viewer o|None=>fallback end in
    let observed:=match origin with Some o=>[("origin",JsonProperty(observation_origin namespace viewer o));("document_key",JsonProperty(JString key));("epoch",JsonProperty(number(epoch_for_key key s)));("revision",JsonProperty(number(N.of_nat(String.length source))));("ending",JsonProperty(JString "open"))]|None=>[]end in
    node Scene.Section_role(key++"/reading-anchor")[("attrs",JsonProperty(JObject[("data-reading-anchor",JString key)]))]
      [node Scene.Markdown_role key(("value",JsonProperty(JString source))::("complete",JsonProperty(JBool false))::observed)[]])(output_parts output).
Definition parameter_text value:=match value with JString text=>text|_=>render_json value end.
Definition operation_parameters key arguments:=match arguments with
 |JObject fields=>map(fun '(name,value)=>group(key++"/argument/"++name)
   [text_node(key++"/argument/"++name++"/label")(Forms.argument_label name);text_node(key++"/argument/"++name++"/value")(parameter_text value)])fields
 |_=>[text_node(key++"/arguments")(parameter_text arguments)]end.
Definition operation_scene task operation s:=
 let id:=value_or (0%N)(natural_field "operation_id" operation)in
 let key:="task/"++show_natural task++"/operation/"++show_natural id in
 let call:=value_or JNull(field "call" operation)in
 let context:=value_or JNull(field "context" operation)in
 let reviewer:=value_or JNull(field "reviewer" operation)in
 group key([text_node(key++"/summary")(text "tool" operation++" · "++text "status" operation)]++
 operation_parameters key(value_or JNull(field "arguments" call))++
 (match bind(field "workspace" context)(string_field "primary_root")with
  |Some directory=>[text_node(key++"/directory")("默认工作目录："++directory)]|None=>[]end)++
 (if String.eqb(text "kind" reviewer)"model"then
   [text_node(key++"/reviewer")("自动审核："++text "name"(value_or JNull(field "profile" reviewer)))]else [])++
 (if flag "awaitingHuman" operation then map(fun decision=>button(key++"/"++decision)(if String.eqb decision "allow"then "允许"else "拒绝")
   (command_action "review_approval"[("task_id",number task);("operation_id",number id);("decision",JString decision)])(negb(connected(service_state s))))["allow";"deny"]else [])++
 [button(key++"/cancel")"取消操作"(command_action "cancel_operation"[("task_id",number task);("operation_id",number id)])(negb(connected(service_state s))) ]).
Definition retained_scene namespace task world s:=
 map(fun stamp=>let identity:=document_identity stamp in
  group(identity++"/retained")
   ([text_node(identity++"/retention-notice")(if document_archived stamp then "未完成显示已收起"else match document_ending stamp with Selvedge.Interaction.Interactive.Types.Interrupted=>"生成未完成（仅在本次会话保留）"|_=>"输出同步中（仅在本次会话保留）"end);
     button(identity++"/dismiss")"Discard retained output"(invoke(Input.RetainedOutput identity false))false]++
    (if document_archived stamp then [button(identity++"/toggle")"Show or hide retained source"(invoke(Input.RetainedOutput identity true))false]else [])++
    (if negb(document_archived stamp)||document_revealed stamp then
      [node Scene.Markdown_role identity
        ([ ("value",JsonProperty(JString(document_source stamp)));("complete",JsonProperty(JBool true))]++
         if document_archived stamp then []else [ ("origin",JsonProperty(observation_origin namespace task(document_origin stamp)));("document_key",JsonProperty(JString identity));("epoch",JsonProperty(number(document_epoch stamp)));("revision",JsonProperty(number(N.of_nat(String.length(document_source stamp)))));("ending",JsonProperty(JString(Selvedge.Interaction.Interactive.Types.ending_name(document_ending stamp))))])[]]else [])))
 (filter(fun stamp=>N.eqb task(document_viewer stamp))(Documents.retained_stamps namespace world s)).
Definition worktree_scene task world s:=
 flat_map(fun tree=>match natural_field "task_id" tree with Some owner=>if N.eqb task owner then
  [group("worktree/"++show_natural task)
   ([text_node("worktree/"++show_natural task++"/state")(text "status" tree++": "++text "message" tree)]++
    if String.eqb(text "status" tree)"archive_failed"then
     [button("worktree/"++show_natural task++"/retry")"Retry workspace archive"(command_action "retry_worktree_archive"[("task_id",number task)])(negb(connected(service_state s)))]else [])]else []|None=>[]end)(items "worktrees" world).
Definition source_pairs key values := map(fun '(name,value)=>text_node(key++"/"++name)(name++"："++value_or ""(as_string value)))(object_fields values).
Definition context_source_scene index snapshot :=
 let key:="context-source/"++show_natural index in
 let identity:=value_or JNull(bind(field "key" snapshot)(field "identity"))in
 let values:=value_or JNull(bind(field "value" snapshot)(field "fields"))in
 group key (text_node(key++"/revision")("版本："++text "revision" snapshot)::source_pairs(key++"/identity")identity++source_pairs(key++"/value")values).
Definition task_details_scene subject world s :=
 match bind(field "task_id" subject)natural with
 |None=>text_node "task-details/unavailable" "The task no longer exists"
 |Some task=>match find_task task world with
  |None=>text_node "task-details/unavailable" "The task no longer exists"
  |Some found=>let key:="task-details/"++show_natural task in
   group key ([heading(key++"/title")"Execution context";
    text_node(key++"/model")("Model: "++text "profile" found++" · "++text "provider" found++" · "++text "model" found);
    text_node(key++"/reasoning")("Reasoning effort: "++text "reasoning" found);
    text_node(key++"/status")("Status: "++text "status" found);
    text_node(key++"/phase")("Phase: "++text "phase" found);
    text_node(key++"/settings")(TextJson.render_json(value_or JNull(field "settings" found)));
    text_node(key++"/guidance")("Creation guidance: "++TextJson.render_json(value_or JNull(field "guidance" found)));
    text_node(key++"/lineage")("Task ancestry: "++TextJson.render_json(value_or JNull(field "lineage" found)));
    heading(key++"/tools")"Available tools"]++
    map(fun tool=>text_node(key++"/tool/"++text "name" tool)(TextJson.render_json tool))(items "tools" found)++
    [heading(key++"/queued")"Queued messages"]++
    map(fun '(index,message)=>text_node(key++"/queued/"++show_natural index)
     (value_or ""(Conversation.public_text message)))
     (combine(map N.of_nat(seq 0(List.length(items "queued_messages" found))))(items "queued_messages" found))++
    [heading(key++"/sources")"Last observed context sources"]++
    map(fun '(index,snapshot)=>context_source_scene index snapshot)
     (combine(map N.of_nat(seq 0(List.length(items "context" found))))(items "context" found))++
    worktree_scene task world s)
  end end.
Definition conversation_scene namespace task world s :=
  match find_task task world with None=>group "missing-task"[heading "missing-task/title" "Task not found"]|Some found=>
  node Scene.Section_role("conversation/"++show_natural task)[("label",JsonProperty(JString(text "title" found)));("layout",JsonProperty(JString "fill"))]
    [heading("conversation/"++show_natural task++"/title")(text "title" found);
     text_node("conversation/"++show_natural task++"/status")(text "status" found);
     node Scene.Group_role("conversation/"++show_natural task++"/controls")[("layout",JsonProperty(JString "row"))]
       ([button("task/"++show_natural task++"/details")"Task details"
          (invoke(Input.OpenInformation "task_details"(JObject[("task_id",number task)])("task/"++show_natural task++"/details")))false;
         button("task/"++show_natural task++"/more")"More"(invoke(Input.OpenObjectActions(TaskActions task)("task/"++show_natural task++"/more")))false;
         button("task/"++show_natural task++"/latest")"Return to latest"(invoke(Input.FollowLatest task))false]++
        (match natural_field "side_parent" found with None=>[]|Some parent=>
         [button("task/"++show_natural task++"/return-side")("追加回 task #"++show_natural parent)
          (command_action "return_side_conversation"[("task_id",number task)])(negb(connected(service_state s)));
          button("task/"++show_natural task++"/show-side")"打开侧窗口"(invoke(Input.ShowSide task("task/"++show_natural task++"/show-side")))false]end)++
        [button("task/"++show_natural task++"/voice")"Start voice"(invoke(Input.SpeechInput(BeginVoice task)))(negb(free(speech_state s)))]);
     node Scene.Group_role("conversation/"++show_natural task++"/history")[("attrs",JsonProperty(JObject[("data-reading-root",JString "true")]))]
       (history_scenes namespace task 0(items "history" found)s++flat_map(fun output=>live_scene namespace task world output s)(filter(fun o=>N.eqb task(output_task o))(active_previews world s)));
     group("conversation/"++show_natural task++"/operations")(map(fun operation=>operation_scene task operation s)(items "operations" found));
     group("task/"++show_natural task++"/retained")
       (retained_scene namespace task world s++match find(fun entry=>N.eqb task(fst entry))(discarded_outputs s)with None=>[]|Some(_,count)=>[text_node("task/"++show_natural task++"/discarded")("已丢弃 "++show_natural count++" 个未完成输出") ]end);
     group("task/"++show_natural task++"/worktree")(worktree_scene task world s);
     form_scene(Message task)world s]
  end.
Definition conversation_view namespace view world s :=
 let scope:=task_view_scope view in
 Scene.scope scope(Input.scope_triggers scope)
  (conversation_scene namespace(task_view_task view)world s).
Definition project_actions id (s:ApplicationState.state) :=
 [button("project/"++show_natural id++"/new")"New task"(invoke(Input.BeginProjectTask id))false;
  button("project/"++show_natural id++"/more")"More"(invoke(Input.OpenObjectActions(ProjectActions id)("project/"++show_natural id++"/more")))false].
Definition project_scene id world s :=
 let key:="project-page/"++show_natural id in
 match find_project id world with
 |None=>group key[heading(key++"/missing")"This project no longer exists"]
 |Some project=>let workspace:=value_or JNull(field "workspace" project)in
  let guidance:=value_or JNull(field "guidance" project)in
  group key([heading(key++"/name")(text "name" project);group(key++"/actions")(project_actions id s);
   heading(key++"/workspace")"Default workspace";
   text_node(key++"/primary")("Primary directory: "++text "primary_root" workspace);
   node Scene.ListView_role(key++"/directories")[("label",JsonProperty(JString "Workspace directories"))]
    (map(fun directory=>text_node(key++"/directory/"++value_or ""(as_string directory))(value_or ""(as_string directory)))(items "roots" workspace));
   heading(key++"/guidance-heading")"Project guidance";
   text_node(key++"/guidance")(match guidance with JNull=>"No project guidance"|_=>text "instructions" guidance end);
   heading(key++"/tasks-heading")"Tasks"]++
   map(task_button_at key(location(navigation_state s)))(Navigation.tasks_in_project id world))
 end.
Definition projects_scene world s :=
 group "projects"(heading "projects/title" "项目"::editor_button "projects/new" "New project"(Project None)::
  map(fun project=>match natural_field "project_id" project with
   |None=>group "invalid-project"[]
   |Some id=>group("projects/"++show_natural id)
     (button("project/"++show_natural id++"/open")(text "name" project)(navigation_action(ProjectHome id))false::project_actions id s)
   end)(items "projects" world)).
Definition card_action op card now:=command_action op[("card_id",value_or JNull(field "card_id" card));("revision",value_or JNull(field "revision" card));("observed_at",JString(show_natural now))].
Definition board_cards board :=
  let cards:=items "cards" board in
  let ordered:=fold_right(fun id rest=>match natural id with Some id=>
    match find(fun card=>match natural_field "id" card with Some actual=>N.eqb id actual|None=>false end)cards with Some card=>card::rest|None=>rest end|None=>rest end)[](items "order" board)in
  List.app ordered(filter(fun card=>negb(existsb(fun other=>equal(value_or JNull(field "id" card))(value_or JNull(field "id" other)))ordered))cards).
Definition card_scene now board world card s:=let key:="card-summary/"++value_or ""(number_field "card_id" card)in
  let caps:=value_or JNull(field "capabilities" card)in
  let disabled capability:=negb(connected(service_state s))||negb(flag capability caps)in
  node Scene.Section_role key[("attrs",JsonProperty(JObject[
    ("draggable",JString(if disabled "drag"then "false"else "true"));
    ("data-card-id",JString(value_or ""(number_field "card_id" card)));
    ("data-card-revision",JString(value_or ""(number_field "revision" card)));
    ("data-card-observed-at",JString(show_natural now));("data-drop-status",JString(text "status" card));
    ("data-card-before",JString(value_or ""(number_field "card_id" card)))]))]
   ([heading(key++"/title")(text "title" card);text_node(key++"/description")(text "description" card);
    text_node(key++"/status")(text "status" card++" · "++text "priority" card);
    (match natural_field "card_id" card with Some id=>button(key++"/open")("打开 "++text "title" card)(invoke(Input.OpenInformation "card_details"(JObject[("card_id",number id)])(key++"/open")))false|None=>group(key++"/unavailable")[]end);
    (match natural_field "card_id" card with Some id=>button(key++"/more")"More"(invoke(Input.OpenObjectActions(CardActions id)(key++"/more")))false|None=>group(key++"/no-actions")[]end);
    node Scene.Select_role(key++"/move")[("disabled",JsonProperty(JBool(disabled "drag")));("label",JsonProperty(JString "Move to status"));("value",JsonProperty(JString(text "status" card)));("options",JsonProperty(JArray BoardFilter.stage_choices));("action",InputProperty(invoke(Input.CardField(value_or (0%N)(natural_field "card_id" card))(value_or (0%N)(natural_field "revision" card))now "status" "")))][]]++
    (match natural_field "task_id" card with None=>[]|Some task=>[button(key++"/task")"Open linked task"(navigation_action(Conversation task))false]end)++
    [node Scene.Select_role(key++"/before")[("disabled",JsonProperty(JBool(disabled "drag")));("label",JsonProperty(JString "Move before card"));("value",JsonProperty(JString ""));
      ("options",JsonProperty(JArray(option_node(JString "")"End of column"::map(fun other=>option_node(JString(value_or ""(number_field "id" other)))(text "title" other))
       (filter(fun other=>negb(equal(value_or JNull(field "id" other))(value_or JNull(field "id" card))))(items "cards" board)))));
      ("action",InputProperty(invoke(Input.CardField(value_or (0%N)(natural_field "card_id" card))(value_or (0%N)(natural_field "revision" card))now "before_card" "")))][];
     node Scene.Select_role(key++"/link")[("disabled",JsonProperty(JBool(disabled "edit")));("label",JsonProperty(JString "Link task"));("value",JsonProperty(optional_id(natural_field "task_id" card)));("options",JsonProperty(JArray(option_node(JString "")"No task"::map(fun task=>option_node(JString(value_or ""(number_field "id" task)))(text "title" task))(items "tasks" world))));("action",InputProperty(invoke(Input.CardField(value_or (0%N)(natural_field "card_id" card))(value_or (0%N)(natural_field "revision" card))now "task_id" "")))][]]).
Definition board_filter_choices category choices s:=
 let selected:=BoardFilter.filter_values(board_selection s)category in
 group("board/filter/"++BoardFilter.category_name category)(map(fun choice=>
 let value:=text "value" choice in button("board/filter/"++BoardFilter.category_name category++"/"++value)
 ((if existsb(String.eqb value)selected then "✓ "else "")++text "label" choice)
 (invoke(Input.BoardToggle(BoardFilter.category_name category)value))false)choices).
Definition board_scene now world s:=let board:=value_or JNull(field "board" world)in
 let selection:=board_selection s in let cards:=BoardFilter.display_cards(board_cards board)in
 group "board"([heading "board/title" "任务看板";editor_button "board/new" "Capture work"(Card None);
 node Scene.Field_role "board/search"[("label",JsonProperty(JString "Search cards"));("value",JsonProperty(JString(BoardFilter.filter_query selection)));("action",InputProperty(invoke(Input.BoardQuery "")))][];
 group "board/tabs"(map(fun tab=>button("board/tab/"++BoardFilter.tab_name tab)(BoardFilter.tab_name tab)(invoke(Input.BoardTab(BoardFilter.tab_name tab)))false)[BoardFilter.All;BoardFilter.Assigned;BoardFilter.UnassignedTab;BoardFilter.Working]);
 board_filter_choices BoardFilter.Status BoardFilter.stage_choices s;
 board_filter_choices BoardFilter.Priority BoardFilter.priority_choices s;
 board_filter_choices BoardFilter.Date [option_node(JString "1")"Last day";option_node(JString "7")"Last week";option_node(JString "30")"Last month"]s;
 board_filter_choices BoardFilter.Assignee(option_node(JString "none")"Unassigned"::option_node(JString "self")"Self"::map(fun p=>option_node(JString("profile:"++text "key" p))(text "name" p))(items "profiles" world)++map(fun a=>option_node(JString("agent:"++value_or ""(number_field "id" a)))(text "name" a))(items "agents" board))s;
 board_filter_choices BoardFilter.Creator [option_node(JString "self")"Self"]s;
 board_filter_choices BoardFilter.Project(map(fun p=>option_node(JString(value_or ""(number_field "id" p)))(text "name" p))(items "projects" world))s;
 board_filter_choices BoardFilter.Label(map(fun label=>option_node(JString label)label)(fold_right(fun card labels=>fold_right(fun value rest=>match as_string value with Some value=>if existsb(String.eqb value)rest then rest else value::rest|None=>rest end)labels(items "labels" card))[]cards))s;
 button "board/settings" "Board settings"(invoke(Input.OpenInformation "board_settings" JNull "board/settings"))false;
 button "board/archived" "Archived cards"(invoke(Input.OpenInformation "archived_cards" JNull "board/archived"))false;
 node Scene.ListView_role "board/cards"[](map(fun choice=>let stage:=text "value" choice in
   node Scene.Section_role("board/lane/"++stage)[("attrs",JsonProperty(JObject[("data-drop-status",JString stage)]))]
    (heading("board/lane/"++stage++"/title")(text "label" choice)::
     map(fun card=>card_scene now board world card s)(filter(fun card=>String.eqb(text "status" card)stage)(BoardFilter.apply_in_world selection now cards world))))BoardFilter.stage_choices);
 group "board/footer"[]]).
Definition agent_scene (world:json)(s:ApplicationState.state) agent id :=
 let key:="agent-summary/"++show_natural id in
 group key([heading(key++"/name")(text "name" agent)]++
  map(fun '(name,caption)=>text_node(key++"/"++name)(caption++": "++text name agent))
    [("profile","Model");("reasoning","Reasoning");("instructions","Instructions")]++
  [text_node(key++"/concurrency")("Concurrency: "++value_or ""(number_field "concurrency" agent));
   editor_button(key++"/edit")"Edit"(Agent(Some id));
   button(key++"/more")"More"(invoke(Input.OpenObjectActions(AgentActions id)(key++"/more")))false]++
  match natural_field "active" agent with None=>[]|Some active=>[text_node(key++"/active")("Working: "++show_natural active)]end).
Definition agents_scene world s:=let board:=value_or JNull(field "board" world)in
 group "agents"[heading "agents/title" "智能体";editor_button "agents/new" "New agent"(Agent None);
 node Scene.ListView_role "agents/list"[](flat_map(fun agent=>match natural_field "agent_id" agent with None=>[]|Some id=>[agent_scene world s agent id]end)(items "agents" board))].
Definition graph_endpoint graph key :=match find(fun node=>String.eqb key(text "key" node))(items "nodes" graph)with
 |None=>key|Some node=>key++" · Task #"++value_or ""(number_field "task_id" node)end.
Definition graph_scene world s graph id :=
 let key:="graph/"++show_natural id in
 group key([heading(key++"/name")(text "name" graph);
   editor_button(key++"/edit")"Edit"(TaskGraph(Some id)(active_work(navigation_state s)));
   button(key++"/delete")"Delete"(match decode_command command_specs(JObject[("op",JString "delete_task_graph");("graph_id",number id)])with Some command=>invoke(Input.Confirmation command(key++"/delete"))|None=>UiAction None end)(negb(connected(service_state s)));
   heading(key++"/nodes/title")"Tasks"]++
   map(fun node=>let nodekey:=key++"/node/"++text "key" node in
    match natural_field "task_id" node with None=>text_node nodekey(text "key" node)|Some task=>
     button nodekey(graph_endpoint graph(text "key" node))(navigation_action(Conversation task))
      (match find_task task world with None=>true|Some _=>false end)end)(items "nodes" graph)++
   [heading(key++"/rules/title")"Output rules"]++
   map(fun rule=>let rulekey:=key++"/rule/"++text "key" rule in
    group rulekey(heading(rulekey++"/name")(text "key" rule)::
     map(fun '(index,action)=>text_node(rulekey++"/action/"++show_natural(N.of_nat index))
      (graph_endpoint graph(text "source" rule)++" → "++graph_endpoint graph(text "target" action)++": "++
       TextJson.render_json(value_or JNull(field "message" action))))
      (combine(seq 0(List.length(items "actions" rule)))(items "actions" rule))))(items "rules" graph)++
   [heading(key++"/receipts/title")"Last delivery results"]++
   map(fun '(index,receipt)=>text_node(key++"/receipt/"++show_natural(N.of_nat index))
     ("Task #"++value_or ""(number_field "source" receipt)++" → Task #"++value_or ""(number_field "target" receipt)++
       " ("++text "rule" receipt++"): "++TextJson.render_json(value_or JNull(field "reply" receipt))))
    (combine(seq 0(List.length(items "receipts" graph)))(items "receipts" graph))).
Definition graphs_scene world s:=group "graphs"[heading "graphs/title" "Task graphs";
 editor_button "graphs/new" "New task graph"(TaskGraph None(active_work(navigation_state s)));
 node Scene.ListView_role "graphs/list"[](flat_map(fun graph=>match natural_field "graph_id" graph with None=>[]|Some id=>[graph_scene world s graph id]end)
  (filter(fun graph=>match active_work(navigation_state s)with
   |None=>true|Some work=>same_scope(Some work)(natural_field "work_id" graph)end)(items "graphs" world)))].
Definition search_hit_scene hit:=
 let task:=value_or JNull(field "task" hit)in
 let id:=value_or JNull(field "id" task)in
 let index:=value_or JNull(field "message_index" hit)in
 let key:="search-hit/"++value_or ""(as_number id)++"/"++value_or ""(as_number index)in
 group key
  ([button(key++"/open")(text "title" task++" · 消息 #"++match natural index with Some n=>show_natural(N.succ n)|None=>""end)(history_action id index)false;
    text_node(key++"/role")(text "role" hit)]++
   (if String.eqb(text "before" hit)""then []else[text_node(key++"/before")("上一条："++text "before" hit)])++
   [text_node(key++"/snippet")("命中消息："++text "snippet" hit)]++
   if String.eqb(text "after" hit)""then []else[text_node(key++"/after")("下一条："++text "after" hit)]).
Definition search_scene s world:=let search:=history_search(authoring_state s)in
 let disabled:=negb(connected(service_state s))in
 group "history-search"[heading "history-search/title" "搜索对话";
 node Scene.Field_role "history-search/query"[("label",JsonProperty(JString "关键词"));("value",JsonProperty(JString(keyword search)));("keys",KeyProperty[("Enter",Input.SubmitHistorySearch 0)]);("action",InputProperty(invoke(Input.WriteHistoryQuery "")))][];
 node Scene.Select_role "history-search/project"[("specification",FieldProperty(Schema.Field "project"(KOptional KNatural)));("label",JsonProperty(JString "项目"));("value",JsonProperty(optional_id(project_filter search)));("options",JsonProperty(JArray(option_node(JString "")"全部"::project_choices world)));("action",InputProperty(invoke(Input.ChooseHistoryScope true None)))][];
 node Scene.Select_role "history-search/work"[("specification",FieldProperty(Schema.Field "work"(KOptional KNatural)));("label",JsonProperty(JString "Work"));("value",JsonProperty(optional_id(work_filter search)));("options",JsonProperty(JArray(option_node(JString "")"全部"::map(fun w=>option_node(value_or JNull(field "work_id" w))(text "name" w))(items "works" world))));("action",InputProperty(invoke(Input.ChooseHistoryScope false None)))][];
 button "history-search/submit" "搜索"(invoke(Input.SubmitHistorySearch 0))disabled;
 group "history-search/results"(match search_result search with
 |None=>[text_node "history-search/prompt" "输入关键词，选择项目或 Work，然后搜索对话。"]
 |Some reply=>if flag "ok" reply then let result:=value_or JNull(field "result" reply)in
   match items "hits" result with
   |[]=>[text_node "history-search/empty" "没有找到匹配的消息。"]
   |hits=>map search_hit_scene hits++
    (match natural_field "after" result with Some after=>if N.eqb after 0 then []else[button "history-search/previous" "上一页"(invoke(Input.SubmitHistorySearch(N.sub after Search.default_limit)))disabled]|None=>[]end)++
    (match natural_field "next_after" result with Some after=>[button "history-search/more" "更多结果"(invoke(Input.SubmitHistorySearch after))disabled]|None=>[]end)
   end
   else[text_node "history-search/error"(text "message"(value_or JNull(field "error" reply)))]end)].

Definition speech_scene s:=let sp:=speech_state s in
 group "speech"([text_node "speech/notice"(notice sp);text_node "speech/live"(live_text sp)]++
 [node Scene.Select_role "speech/connection"[("label",JsonProperty(JString "Audio connection"));("value",JsonProperty(match selected sp with None=>JString ""|Some id=>JString id end));("options",JsonProperty(JArray(map(fun c=>option_node(JString(connection_id c))(connection_label c))(connections sp))));("action",InputProperty(invoke(Input.SpeechInput(Speech.Select ""))))][]]++
 match current sp with Idle=>[button "speech/authorize" "Sign in for voice"(invoke(Input.SpeechInput Authorize))false;button "speech/refresh" "Refresh audio connections"(invoke(Input.SpeechInput Refresh))false]
 |Recording _ _=>[button "speech/finish" "Finish dictation"(invoke(Input.SpeechInput FinishDictation))false;button "speech/cancel" "Cancel"(invoke(Input.SpeechInput Cancel))false]
 |Retained _ text=>[text_node "speech/retained" text;button "speech/insert" "Insert transcript"(invoke(Input.SpeechInput InsertTranscript))false;button "speech/dismiss" "Dismiss transcript"(invoke(Input.SpeechInput DismissTranscript))false]
 |Voice _ _ mic out=>[button "speech/input"(if mic then "Unmute microphone"else "Mute microphone")(invoke(Input.SpeechInput ToggleInputMute))false;
 button "speech/output"(if out then "Unmute playback"else "Mute playback")(invoke(Input.SpeechInput ToggleOutputMute))false;button "speech/stop" "Stop voice"(invoke(Input.SpeechInput Cancel))false]
 |_=>[button "speech/cancel" "Cancel audio"(invoke(Input.SpeechInput Cancel))false]end).
Definition settings_scene s:=if settings_open(service_state s)then
 [node Scene.Dialog_role "settings"[("label",JsonProperty(JString "Settings"));("attrs",JsonProperty(JObject[("tabindex",JString "-1")]));("dismiss_action",InputProperty(invoke(Input.ServiceInput CloseSettings)))]
 [heading "settings/title" "Settings";node Scene.Select_role "settings/appearance"[("specification",FieldProperty(Schema.Field "appearance"(KEnum "system"["light";"dark"])));("label",JsonProperty(JString "Appearance"));("value",JsonProperty(JString(appearance_name(theme(service_state s)))));("options",JsonProperty(JArray(map(fun v=>option_node(JString v)v)["system";"light";"dark"])));("action",InputProperty(invoke(Input.ServiceInput(ChooseAppearance SystemAppearance))))][];
 editor_button "settings/title-prompts" "标题生成" TitlePrompts;speech_scene s;
 button "settings/connect" "Connect"(invoke(Input.ServiceInput Connect))(connected(service_state s));button "settings/close" "Close settings"(invoke(Input.ServiceInput CloseSettings))false]]else[].
Definition object_action_scene (now:N) subject world s item :=
 let key:=menu_key subject++"/"++ObjectActions.item_key item in
 let occurrence:=generation(navigation_state s)in
 let availability:=ObjectActions.item_availability subject occurrence world s item in
 group(key++"/row")
  ([button key(ObjectActions.item_label item)(invoke(Input.MenuAction subject(ObjectActions.item_key item)occurrence))
    (match availability with ObjectActions.Available=>false|_=>true end)]++
   match availability with ObjectActions.Available=>[]|ObjectActions.Awaiting=>[text_node(key++"/availability")"Checking availability…"]
   |ObjectActions.Unavailable reason=>[text_node(key++"/availability")reason]
   |ObjectActions.AssessmentFailed reason=>[text_node(key++"/availability")reason;
     button(key++"/retry")"Retry availability check"(invoke(Input.RetryMenuAssessment subject(ObjectActions.item_key item)occurrence))false]end).
Definition object_actions_scene now subject trigger world s :=
 node Scene.Dialog_role(menu_key subject)
  [("label",JsonProperty(JString "Actions"));("layout",JsonProperty(JString "anchored-menu"));("attrs",JsonProperty(JObject[("tabindex",JString "-1");("data-anchor",JString trigger)]));("dismiss_action",InputProperty(invoke Input.ClosePanel))]
  (map(object_action_scene now subject world s)(ObjectActions.items_for now subject world(generation(navigation_state s))trigger)++
   [button(menu_key subject++"/close")"Close"(invoke Input.ClosePanel)false]).
Definition observed_card_fields card world s :=
 match initialize(Card(Some card))world with None=>[]|Some d=>
  match Activities.build_activity Activities.EditObject d world(service_state s)false with None=>[]|Some activity=>
   map(ActivityPresentation.readonly_observation("card-observation/"++show_natural card))(Activities.activity_information activity)
  end end.
Definition card_details_scene card world s :=
 let key:="card-details/"++show_natural card in
 match find_world "cards" "card_id" card(value_or JNull(field "board" world))with
 |None=>text_node(key++"/missing")"The card no longer exists"
 |Some value=>group key
  ([heading(key++"/title")(text "title" value);text_node(key++"/identifier")(text "identifier" value)]++
   observed_card_fields card world s++
   [text_node(key++"/enrichment")("Title generation: "++text "status"(value_or JNull(field "enrichment" value))++" "++text "reason"(value_or JNull(field "enrichment" value)));
    text_node(key++"/start-error")("Start error: "++text "start_error" value);
    editor_button(key++"/edit")"Edit card"(Card(Some card));
    button(key++"/more")"More"(invoke(Input.OpenObjectActions(CardActions card)(key++"/more")))false]++
   flat_map(fun file=>match decode_attachment file with None=>[]|Some attachment=>
    [button(key++"/attachment/"++asset_id attachment)(asset_name attachment)
      (invoke(Input.ServiceInput(OpenPreview attachment(key++"/attachment/"++asset_id attachment))))false]end)(items "attachments" value)++
   match natural_field "task_id" value with None=>[]|Some task=>
    [button(key++"/task")"Open linked task"(navigation_action(Conversation task))false]end)
 end.
Definition board_settings_scene world s :=
 let board:=value_or JNull(field "board" world)in
 group "board-settings"
  [button "board-settings/automatic"(if flag "automatic" board then "Pause automatic scheduling"else "Enable automatic scheduling")
    (command_action "board_settings"[("automatic",JBool(negb(flag "automatic" board)));("draft_profile",JString(text "draft_profile" board))])(negb(connected(service_state s)));
   node Scene.Select_role "board-settings/draft-profile"[("label",JsonProperty(JString "Draft profile"));("value",JsonProperty(JString(text "draft_profile" board)));
    ("options",JsonProperty(JArray(profile_choices world)));("action",InputProperty(invoke(Input.BoardProfile ""))) ][]].
Definition information_scene now kind subject world s :=
 if String.eqb kind "card_details"then match natural_field "card_id" subject with
  Some card=>card_details_scene card world s|None=>text_node "card-details/missing" "The card no longer exists"end
 else if String.eqb kind "board_settings"then board_settings_scene world s
 else if String.eqb kind "archived_cards"then
  let board:=value_or JNull(field "board" world)in
  group "archived-cards"(map(fun card=>card_scene now board world card s)(filter(flag "archived")(board_cards board)))
 else text_node "information/description"(text "description" subject).
Definition panel_scene now world s p:=match p with
|ActivityPanel e request view occurrence trigger=>ActivityPresentation.render_activity field_scene form_scene e request view occurrence trigger world s
|ObjectActionsPanel subject trigger=>object_actions_scene now subject trigger world s
|NavigationPanel GlobalMenu _=>global_navigation_dialog world s
|NavigationPanel WorkOverview _=>work_overview world s
|NavigationPanel TasksDrawer _=>group "task-navigation-presence"[]
|InformationPanel kind subject trigger=>
 let key:=information_panel_key kind subject in
 if String.eqb kind "task_details"then
  node Scene.Aside_role key[("label",JsonProperty(JString "Task details"));("attrs",JsonProperty(JObject[("tabindex",JString "-1")]));("layout",JsonProperty(JString "supporting-panel"));("dismiss_action",InputProperty(invoke Input.ClosePanel))]
   [node Scene.Header_role(key++"/header")[("layout",JsonProperty(JString "supporting-header"))]
     [heading(key++"/title")"Task details";icon_button(key++"/close")"Close" "close-cross"(invoke(Input.OpenInformation kind subject trigger))false];
    Scene.scope key(Input.scope_triggers key)(task_details_scene subject world s)]
 else node Scene.Dialog_role key[("label",JsonProperty(JString kind));("dismiss_action",InputProperty(invoke Input.ClosePanel))]
   [Scene.scope key(Input.scope_triggers key)(information_scene now kind subject world s);button(key++"/close")"Close"(invoke Input.ClosePanel)false]
|ApplicationState.Confirmation command caption _ _ feedback=>
 let availability:=ObjectActions.confirmation_availability world s command caption in
 let available:=match availability with ObjectActions.Available=>true|_=>false end in
 node Scene.Dialog_role "confirmation"[("label",JsonProperty(JString caption));("dismiss_action",InputProperty(invoke(Input.ClosePanel)))]
 ([heading "confirmation/title" caption]++
 (match feedback with None=>[]|Some reason=>[node Scene.Text_role "confirmation/feedback"[("value",JsonProperty(JString reason));("attrs",JsonProperty(JObject[("role",JString "alert")]))][]]end)++
 (match availability with ObjectActions.Available=>[]|ObjectActions.Awaiting=>[text_node "confirmation/availability" "Checking action availability"]
  |ObjectActions.Unavailable reason=>[text_node "confirmation/availability" reason]
  |ObjectActions.AssessmentFailed reason=>[text_node "confirmation/availability" reason]++
    match ObjectActions.confirmation_for command with None=>[]|Some(_,_,subject)=>
    [button "confirmation/retry" "Retry"(invoke(Input.RetryMenuAssessment subject "delete"(generation(navigation_state s))))false]end end)++
 [button "confirmation/confirm" "Confirm"(invoke(Input.Confirm))(confirmation_pending s||negb available);
  button "confirmation/cancel" "Cancel"(invoke(Input.ClosePanel))false])end.
Definition preview_scene s:=match preview(service_state s)with
|Dormant=>[]|Loading _ request=>[node Scene.Dialog_role "file-preview"[("label",JsonProperty(JString(asset_name(preview_file request))));("dismiss_action",InputProperty(invoke(Input.ServiceInput ClosePreview)))][text_node "file-preview/loading" "Loading…"]]
|Resource.Failed _ request error=>[node Scene.Dialog_role "file-preview"[("label",JsonProperty(JString(asset_name(preview_file request))));("dismiss_action",InputProperty(invoke(Input.ServiceInput ClosePreview)))][text_node "file-preview/error" error;button "file-preview/close" "Close"(invoke(Input.ServiceInput ClosePreview))false]]
|Loaded _ request url=>[node Scene.Dialog_role "file-preview"[("label",JsonProperty(JString(asset_name(preview_file request))));("dismiss_action",InputProperty(invoke(Input.ServiceInput ClosePreview)))]
 [(if passive_image(preview_file request)then image_scene "file-preview/image"(asset_id(preview_file request))(asset_name(preview_file request))else text_node "file-preview/text" "Inline preview is unavailable for this file type.");
 button "file-preview/download" "Download"(invoke(Input.ServiceInput(Download (preview_file request))))false;button "file-preview/close" "Close"(invoke(Input.ServiceInput ClosePreview))false]]end.
Definition directory_scene s:=match directory(service_state s)with
|Dormant=>[]|r=>let owner:=match r with Loading _ q|Loaded _ q _|Resource.Failed _ q _=>Some q|Dormant=>None end in
 [node Scene.Dialog_role "directory-picker"[("label",JsonProperty(JString "Choose directory"));("dismiss_action",InputProperty(invoke(Input.ServiceInput CloseDirectory)))]
  ([node Scene.Field_role "directory-picker/location"[("label",JsonProperty(JString "Directory"));("value",JsonProperty(JString(directory_location(service_state s))));("action",InputProperty(invoke(Input.ServiceInput(WriteDirectoryLocation ""))))][];
   button "directory-picker/go" "Go"(invoke(Input.ServiceInput GoDirectory))false]++
   match r with
   |Loading _ _=>[text_node "directory-picker/loading" "Loading…"]
   |Resource.Failed _ _ error=>[text_node "directory-picker/error" error]
   |Loaded _ _ catalog=>(match string_field "parent" catalog with Some parent=>[button "directory-picker/parent" "Parent directory"(invoke(Input.ServiceInput(VisitDirectory parent)))false]|None=>[]end)++map(fun entry=>button("directory/"++text "path" entry)(text "name" entry)(invoke(Input.ServiceInput(VisitDirectory (value_or ""(as_string(value_or JNull(field "path" entry)))))))false)(items "entries" catalog)++[button "directory-picker/choose" "Use this directory"(invoke(Input.ServiceInput ChooseDirectory))false]
   |Dormant=>[]end++[button "directory-picker/close" "Cancel"(invoke(Input.ServiceInput CloseDirectory))false])]
 end.
Definition shared_ui_scene work task world (s:ApplicationState.state):=match find_work work world with
 |None=>group "shared-ui/missing"[heading "shared-ui/title" "Work not found"]
 |Some found=>group "shared-ui"[heading "shared-ui/title"(text "name" found);
   node Scene.Select_role "shared-ui/recipient"[("specification",FieldProperty(Schema.Field "task"(KOptional KNatural)));("label",JsonProperty(JString "Receiver task"));("value",JsonProperty(optional_id task));
    ("options",JsonProperty(JArray(option_node(JString "")"Choose receiver task"::map(fun task=>option_node(value_or JNull(field "id" task))(text "title" task))(filter(fun task=>match natural_field "id" task with Some id=>task_belongs(Some work)id world|None=>false end)(items "tasks" world)))));
    ("action",InputProperty(invoke(Input.SelectSharedTask work None)))][];
   group(work_ui_target work)[]]end.
Definition storage_notice s := match storage_problem(service_state s)with
 |None=>[]
 |Some message=>[node Scene.Section_role "local-storage-notice"[("attrs",JsonProperty(JObject[("role",JString "status")]))]
    [text_node "local-storage-notice/message" message;
     button "local-storage-notice/dismiss" "知道了"(invoke(Input.ServiceInput DismissStorageProblem))false]]end.
Definition observe namespace now world s :=
  let main:=match location(navigation_state s)with
  |Start=>group "start"[heading "start/title"(Navigation.work_label(active_work(navigation_state s))world);form_scene(NewTask(active_work(navigation_state s)))world s]
  |Conversation task=>conversation_view namespace(PrimaryTask task)world s|Projects=>projects_scene world s|ProjectHome id=>project_scene id world s
  |Board=>board_scene now world s|Agents=>agents_scene world s|Graphs=>graphs_scene world s
  |HistorySearch=>search_scene s world|SharedUI work task=>shared_ui_scene work task world s end in
  node Scene.Group_role "application"[("layout",JsonProperty(JString "workspace"));("appearance",JsonProperty(JString(appearance_name(theme(service_state s)))));("attrs",JsonProperty(JObject[("class",JString "application")]))]
  ([navigation_scene world s;node Scene.Main_role "main"[("attrs",JsonProperty(JObject[("tabindex",JString "-1")]))](storage_notice s++[main])]++
   match side_task(navigation_state s)with None=>[]|Some task=>[node Scene.Aside_role "side-conversation"[("label",JsonProperty(JString "Side conversation"));("dismiss_action",InputProperty(invoke(Input.CloseSide)))][node Scene.Header_role "side-conversation/header"[("layout",JsonProperty(JString "supporting-header"))]
    [heading "side-conversation/title"("Side conversation · task #"++show_natural task);icon_button "side-conversation/close" "关闭" "close-cross"(invoke Input.CloseSide)false];
   conversation_view namespace(SideTask task)world s]]end++
   settings_scene s++flat_map(fun panel=>match panel with NavigationPanel TasksDrawer _=>[]|_=>[panel_scene now world s panel]end)(rev(layers(navigation_state s)))++preview_scene s++directory_scene s).
