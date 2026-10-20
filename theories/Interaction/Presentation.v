From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers Schema TextJson.
From Selvedge.Kernel Require Import Commands Conversation Streams.
From Selvedge.Kernel Require Search.
From Selvedge.Features Require BoardFilter.
From Selvedge.Interaction Require Documents.
From Selvedge.Interaction Require Import Codec Identity Resource Services Forms Speech ApplicationState ApplicationOps Origin Input InputCodecs Scene ApplicationCore SkillMention.
From Selvedge.Interaction Require Audit.
Import ListNotations.
Open Scope string_scope.

Record ui_action := UiAction { action_input:option Input.input }.
Definition invoke i:=UiAction(Some i).
Inductive presentation_property := JsonProperty(value:json)|InputProperty(value:ui_action)|FieldProperty(value:field_spec)|KeyProperty(values:list(string*Input.input)).
Coercion JsonProperty : json >-> presentation_property.
Coercion InputProperty : ui_action >-> presentation_property.
Definition scene_data_key name:=match name with
|"label"=>Some Scene.Label|"value"=>Some Scene.Value|"attrs"=>Some Scene.Attributes|"disabled"=>Some Scene.Disabled|"checked"=>Some Scene.Checked|"multiline"=>Some Scene.Multiline|"options"=>Some Scene.Options|"help"=>Some Scene.Help|"invalid"=>Some Scene.Invalid|"role"=>Some Scene.Role|"value_kind"=>Some Scene.ValueKind|"url"=>Some Scene.Url|"complete"=>Some Scene.Complete|"origin"=>Some Scene.Origin|"document_key"=>Some Scene.DocumentKey|"epoch"=>Some Scene.Epoch|"revision"=>Some Scene.Revision|"ending"=>Some Scene.Ending|"appearance"=>Some Scene.Appearance|"layout"=>Some Scene.Layout|"target"=>Some Scene.Target|_=>None end.
Definition scene_property role '(name,value):list(Scene.property Input.input):=
 match value with
 |FieldProperty spec=>[Scene.Specification spec]
 |KeyProperty keys=>[Scene.KeyActions keys]
 |JsonProperty value=>match scene_data_key name with Some key=>[Scene.Data key value]|None=>[]end
 |InputProperty value=>match action_input value with None=>[]|Some input=>
   if String.eqb name "dismiss_action"then [Scene.Dismiss input]else
   if String.eqb name "file_action"then [Scene.Files input]else
   [Scene.Bind(match role with Scene.Field|Scene.Select|Scene.Checkbox=>Scene.Supply
      (match input with ServiceInput(AddFile _ _)=>Scene.FileInjection|Input.Interactive _=>Scene.InteractiveValueInjection|_=>Scene.ValueInjection end)input
      |_=>Scene.Activate input end)]end end.
Definition node role key (props:list(string*presentation_property))(children:list(Scene.scene Input.input)):=
 Scene.make role key(flat_map(scene_property(proj1_sig role))props)children.
Definition text_node key text := node Scene.Text_role key[("value",JsonProperty(JString text))] [].
Definition heading key text := node Scene.Heading_role key[("label",JsonProperty(JString text))] [].
Definition group key children := node Scene.Group_role key [] children.
Definition command_action op props := UiAction(option_map Input.Command(decode_command command_specs(JObject(("op",JString op)::props)))).
Definition history_action task index:=UiAction(match natural task,natural index with Some task,Some index=>Some(Input.OpenHistoryMessage task index)|_,_=>None end).
Definition button key caption input disabled := Scene.ActionButton key[("label",JString caption)](action_input input)disabled[].
Definition navigation_action r := invoke(Input.Navigate r).
Definition editor_button key caption e := button key caption(invoke(Input.OpenEditor e key))false.
Definition edit_action e name := invoke(Input.Edit e name JNull None).
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
Definition observed_task_field task name world:=
 t<-find_task task world;;
 match name with
 |"profile"|"reasoning"=>field name t
 |"sandbox"|"network_access"=>settings<-field "settings" t;;sandbox<-field "sandbox" settings;;field(if String.eqb name "sandbox"then "mode"else "network_access")sandbox
 |"approval"|"reviewer_profile"=>settings<-field "settings" t;;policy<-field "approval" settings;;
   if String.eqb name "approval"then field "mode" policy else Some(value_or JNull(field "reviewer_profile" policy))
 |_=>None end.
Definition displayed_value f d world s:=
 let name:=field_name(specification f)in
 match owner d with Message task=>if configuration_active(owner d)s then get name d else match observed_task_field task name world with Some value=>value|None=>get name d end|_=>get name d end.
Definition field_value f d world s := match raw_text(field_name(specification f))d with Some s=>JString s|None=>
  match Schema.field_kind(specification f),displayed_value f d world s with
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
Definition mention_suggestions e world s:=match mention_for e s with Suggesting trigger _=>
 node Scene.ListView_role(editor_key e++"/skill-suggestions")[("role",JsonProperty(JString "listbox"))]
  (map(fun skill=>button(editor_key e++"/skill/"++skill_path skill)(skill_name skill)(invoke(Input.SkillSelected e(skill_path skill)))false)(mention_candidates(catalog_for e world s)(mention_for e s)))
 |_=>group(editor_key e++"/skill-suggestions")[]end.
Definition field_disabled e name world:=match e with
 |Card(Some id)=>match find_world "cards" "card_id" id(value_or JNull(field "board" world))with None=>true|Some card=>
  if String.eqb name "keep_open"then false else
  negb(flag(if existsb(String.eqb name)["title";"description";"assignee";"project";"assisted";"draft_profile"]then "edit"else "metadata")(value_or JNull(field "capabilities" card)))end
 |_=>false end.
Definition worktree_unavailable d world s := negb(workspace_git_available d world(service_state s)).
Definition preserve_selected selected options :=
 if Json.equal selected(JString "") || Json.equal selected JNull || existsb(fun choice=>Json.equal selected(value_or JNull(field "value" choice)))options
 then options else option_node selected("当前选择已不可用："++value_or ""(as_string selected))::options.
Definition model_key d world s := match owner d with
 |Message task=>if configuration_active(owner d)s then read_text "profile" d else value_or(read_text "profile" d)(bind(observed_task_field task "profile" world)as_string)
 |_=>read_text "profile" d end.
Definition field_applies d world s name :=
 let observed name:=match owner d with Message task=>if configuration_active(owner d)s then get name d else value_or(get name d)(observed_task_field task name world)|_=>get name d end in
 if String.eqb name "reviewer_profile"then Json.equal(observed "approval")(JString "approval-for-me")else
 if String.eqb name "network_access"then negb(Json.equal(observed "approval")(JString "full-access"))else
 if String.eqb name "sandbox"then negb(Json.equal(observed "approval")(JString "full-access"))else
 if String.eqb name "draft_profile"then read_flag "assisted" d else true.
Definition attachment_field e:=match e with NewTask _|Message _=>Some "message"|Card _=>Some "description"|_=>None end.
Definition can_attach e:=match attachment_field e with Some _=>true|None=>false end.
Definition attach_action e:=invoke(Input.ServiceInput(AddFile e(SelectedFile "" "" "" 0))).
Definition field_scene d world s f :=
  let name:=field_name(specification f)in let key:=editor_key(owner d)++"/"++name in
  let efforts:=ModelSelection.reasoning_values world(model_key d world s)in
  let reasoning:=String.eqb name "reasoning" && negb(match efforts with []=>true|_=>false end)in
  let select:=reasoning||String.eqb(widget f)"select"||String.eqb(widget f)"profile"||String.eqb(widget f)"project"in
  let kind:=if select then Scene.Select_role else if String.eqb(widget f)"checkbox"then Scene.Checkbox_role else Scene.Field_role in
  let options:=if reasoning then map(fun value=>option_node(JString value)value)efforts else
   if String.eqb(widget f)"profile"then (match Schema.field_kind(specification f)with KOptional _=>option_node(JString "")"继承默认值"::profile_choices world|_=>profile_choices world end)
   else if String.eqb(widget f)"project"then project_options world else kind_options(Schema.field_kind(specification f))world in
  let options:=if select then preserve_selected(field_value f d world s)options else options in
  node kind key[("disabled",JsonProperty(JBool(field_disabled(owner d)name world || (String.eqb name "create_worktree" && worktree_unavailable d world s))));("specification",FieldProperty(specification f));("keys",KeyProperty(if String.eqb name "message"then mention_keys(owner d)world s else []));("attrs",JsonProperty(JObject[("data-field",JString(field_key(owner d)name));("data-object-owner",JString(field_owner_key(owner d)name))]));("label",JsonProperty(JString(label f)));("value",JsonProperty(field_value f d world s));("value_kind",JsonProperty(JString(kind_name(Schema.field_kind(specification f)))));("action",InputProperty(edit_action(owner d)name));
    ("file_action",InputProperty(if connected(service_state s) && (match attachment_field(owner d)with Some target=>String.eqb name target|None=>false end)then attach_action(owner d)else UiAction None));
    ("multiline",JsonProperty(JBool(existsb(String.eqb(widget f))["textarea";"lines";"json";"graph_nodes";"graph_rules"])));
    ("options",JsonProperty(JArray options));("help",JsonProperty(JString(help f)));("invalid",JsonProperty(JBool(match raw_text name d with Some _=>true|None=>false end)))]
    (List.app (if String.eqb name "message"then [mention_suggestions(owner d)world s]else
      if existsb(String.eqb name)["roots";"primary_root";"project_id";"sandbox";"network_access";"approval";"reviewer_profile"]then
       [button(key++"/source")"查看来源"(invoke(Input.InspectSource(owner d)name(key++"/source")))false]else []) (if String.eqb(widget f)"directory"then [button(key++"/browse")"Browse"(invoke(Input.ServiceInput(OpenDirectory (owner d) (read_text name d) (key++"/browse"))))false]else [])).
Definition feedback_scene d :=match status d with Editing=>[]|Accepted _=>[text_node(editor_key(owner d)++"/feedback")"Saved"]
|WorkspaceRejected reason=>[text_node(editor_key(owner d)++"/feedback")reason;button(editor_key(owner d)++"/workspace-retry")"重试工作区准备"(invoke(Input.RetryWorkspace(owner d)))false]
|Rejected reason=>[node Scene.Text_role(editor_key(owner d)++"/feedback")[("value",JsonProperty(JString reason));("role",JsonProperty(JString "alert"))][]]end.
Definition upload_scene d s :=map(fun upload=>match upload with
|Loading t r=>group("upload/"++show_natural t)[text_node("upload/"++show_natural t++"/name")(file_name(upload_file r));button("upload/"++show_natural t++"/cancel")"Cancel upload"(invoke(Input.ServiceInput(CancelUpload t)))false]
|Resource.Failed t r error=>group("upload/"++show_natural t)[text_node("upload/"++show_natural t++"/error")error;button("upload/"++show_natural t++"/retry")"Retry upload"(invoke(Input.ServiceInput(RetryUpload t)))(negb(connected(service_state s)));button("upload/"++show_natural t++"/cancel")"Remove"(invoke(Input.ServiceInput(CancelUpload t)))false]
|_=>group "unused-upload"[]end)
  (filter(fun r=>match upload_owner r with Some e=>same_editor(owner d)e|None=>false end)(uploads(service_state s))).
Definition image_scene key id caption:=node Scene.Image_role key[("url",JsonProperty(JString("/api/board/attachments/"++id)));("label",JsonProperty(JString caption))][].
Definition message_images key message:=
 map(fun part=>let image:=value_or JNull(field "image" part)in
  image_scene(key++"/image/"++text "id" image)(text "id" image)"Image")
 (filter(fun part=>String.eqb(text "type" part)"image"&&passive_mime(text "mime"(value_or JNull(field "image" part))))(items "content" message)).
Definition attachment_scene d :=map(fun a=>group(editor_key(owner d)++"/attachment/"++asset_id a)
 ((if passive_image a then [image_scene(editor_key(owner d)++"/attachment/"++asset_id a++"/image")(asset_id a)(asset_name a)]else [])++[button(editor_key(owner d)++"/attachment/"++asset_id a++"/preview")("Preview "++asset_name a)(invoke(Input.ServiceInput(OpenPreview (a) (editor_key(owner d)++"/attachment/"++asset_id a++"/preview"))))false;
  button(editor_key(owner d)++"/attachment/"++asset_id a++"/remove")"Remove attachment"(invoke(Input.RemoveAttachment (owner d) (asset_id a)))false]))(attachments d).
Definition can_speak e:=match e with NewTask _|Message _=>true|_=>false end.
Definition execution_summary task world := match find_task task world with
 |None=>"配置模型与权限"
 |Some task=>let profile:=text "profile" task in
  let name:=match find(fun candidate=>String.eqb(text "key" candidate)profile)(items "profiles" world)with
   |Some selected=>text "name" selected|None=>profile++"（已不可用）"end in
  let mode:=value_or ""(bind(bind(field "settings" task)(field "approval"))(string_field "mode"))in
  let permissions:=if String.eqb mode "full-access"then "完全访问"else if String.eqb mode "approval-for-me"then "自动审核"else "询问"in
  name++" · "++text "reasoning" task++" · "++permissions end.
Definition form_scene e world s :=
  let d:=value_or(new_draft e)(option_map fst(ensure e world s))in
  let blocked:=match obstruction world(service_state s)d with Some _=>true|None=>editor_pending e s end in
  let caption:=match e with Message _=>if String.eqb(read_text "delivery" d)"steer"then "Steer"else "Send"|NewTask _=>"Start task"|Fork _=>"Fork task"|Compact _=>"Compact history"|_=>"Save"end in
  let field_nodes := (map(field_scene d world s)(filter(fun f=>negb(String.eqb(field_name(specification f))"revision") && (match e with Message _=>existsb(String.eqb(field_name(specification f)))["message";"delivery"]|_=>true end) && field_applies d world s(field_name(specification f)))(form_fields e))++attachment_scene d++upload_scene d s)%list in
  let control_nodes := ((if can_attach e then [node Scene.Field_role(editor_key e++"/upload")[("disabled",JsonProperty(JBool(negb(connected(service_state s)))));("label",JsonProperty(JString "Attach files"));("attrs",JsonProperty(JObject[("type",JString "file");("multiple",JString "true")]));("action",InputProperty(attach_action e))][]]else [])++
   (if can_speak e then [button(editor_key e++"/dictate")"Dictate"(invoke(Input.SpeechInput(BeginDictation (e) (revision d))))(negb(free(speech_state s)));
      button(editor_key e++"/skills")"Skills"(invoke(Input.LoadSkills (e)))false]else [])++
   (match e with NewTask _=>[button(editor_key e++"/voice-new")"Start voice task"(invoke(Input.BeginVoiceNew e))(negb(free(speech_state s))||match voice_obstruction world(service_state s)d with Some _=>true|None=>false end)]|_=>[]end)++
   (if existsb(fun f=>String.eqb(field_name(specification f))"create_worktree")(form_fields e)&&worktree_unavailable d world s
    then [text_node(editor_key e++"/worktree-availability")"工作区的 Git 能力尚未确认，或此目录不可创建工作树。"]else [])++
   (match e with Message task=>[button(editor_key e++"/configure")(execution_summary task world)(invoke(Input.OpenConfiguration e(editor_key e++"/configure")))false]|_=>[]end)++
   (match e with TitlePrompts=>[button "title-prompts/reset" "Reset title prompts"(invoke(Input.ResetTitlePrompts))false]|_=>[]end)++
   feedback_scene d++[button(editor_key e++"/submit")caption(invoke(Input.Submit (e)))blocked]++
   match obstruction world(service_state s)d with None=>[]|Some reason=>[text_node(editor_key e++"/obstruction")reason]end)%list in
  node Scene.Form_role(editor_key e)[("attrs",JsonProperty(JObject[("tabindex",JString "-1")]));("action",InputProperty(invoke(Input.Submit (e))));("label",JsonProperty(JString caption))]
  (field_nodes ++ match e with
   |Message _=>[node Scene.Group_role(editor_key e++"/controls")[("layout",JsonProperty(JString "row"))]control_nodes]
   |_=>control_nodes end).
Definition task_title t :=let title:=text "title" t in if String.eqb title ""then "Task #"++text "id" t else title.
Definition task_id t :=natural_field "id" t.
Definition task_button t :=match task_id t with None=>group "invalid-task"[]|Some id=>button("task/"++show_natural id)(let title:=text "title" t in if String.eqb title ""then "Task #"++show_natural id else title)(navigation_action(Conversation id))false end.
Definition task_parent task:=match field "parent" task with Some value=>value_or None(decode_id value)|None=>None end.
Definition task_forest tasks:=
 map snd(fold_right(fun task pending=>match natural_field "id" task with None=>pending|Some id=>
   let children:=filter(fun entry=>match fst entry with Some parent=>N.eqb id parent|None=>false end)pending in
   let roots:=filter(fun entry=>match fst entry with Some parent=>negb(N.eqb id parent)|None=>true end)pending in
   (task_parent task,group("task-tree/"++show_natural id)(task_button task::map snd children))::roots end)
   ([]:list(option N*Scene.scene Input.input))tasks).
Definition task_project task:=bind(field "settings" task)(natural_field "project_id").
Definition project_task_group world s project:=match natural_field "project_id" project with None=>group "invalid-project"[]|Some id=>
 let tasks:=filter(fun task=>same_scope(Some id)(task_project task)&&match natural_field "id" task with Some task=>task_belongs(active_work(navigation_state s))task world|None=>false end)(items "tasks" world)in
 group("navigation/project/"++show_natural id)
  ([button("navigation/project/"++show_natural id++"/open")(text "name" project)(navigation_action(ProjectHome id))false;
    button("navigation/project/"++show_natural id++"/new")"New task"(invoke(Input.BeginProjectTask id))false;
    button("navigation/project/"++show_natural id++"/toggle")"Toggle project tasks"(invoke(Input.ToggleProjectGroup id))false;
    editor_button("navigation/project/"++show_natural id++"/edit")"Edit project"(Project(Some id))]++
   if existsb(N.eqb id)(collapsed_projects s)then []else task_forest tasks)end.
Definition navigation_tasks world s : list(Scene.scene Input.input):=
 map(project_task_group world s)(items "projects" world)++
 [heading "independent-task-heading" "Independent tasks";
  group "independent-task-tree"(task_forest(filter(fun task=>match task_project task,natural_field "id" task with None,Some id=>task_belongs(active_work(navigation_state s))id world|_,_=>false end)(items "tasks" world)))].
Definition work_button work caption s :=
 let selected:=same_scope work(active_work(navigation_state s))in
 Scene.ActionButton(work_tab_key work)
  [("label",JString caption);("attrs",JObject
    (("aria-pressed",JString(if selected then "true"else "false"))::
     if selected then [("data-reveal-on-layout",JString "true")]else []))]
  (Some(Input.SelectWork work))false[].
Definition navigation_scene world s :=let n:=navigation_state s in
  node Scene.Navigation_role "navigation"[("label",JsonProperty(JString "Navigation"));("attrs",JsonProperty(JObject[("aria-label",JString "Main navigation")]))]
  ([heading "brand" "Selvedge";
    button "navigation-toggle"(if expanded n then "Collapse Task sidebar"else "Expand Task sidebar")(invoke(Input.NavigationExpanded (negb(expanded n))))false;
    button "nav/new-task" "新建对话"(navigation_action Start)false;
    button "nav/projects" "项目"(navigation_action Projects)false;
    button "nav/board" "任务看板"(navigation_action Board)false;
    button "nav/agents" "智能体"(navigation_action Agents)false;
    button "nav/graphs" "Task graphs"(navigation_action Graphs)false;
    button "nav/search" "搜索对话"(navigation_action HistorySearch)false;
    button "nav/settings" "Settings"(invoke(Input.ServiceInput OpenSettings))false;
    node Scene.Navigation_role "work-switcher"[("label",JsonProperty(JString "Works"))]
     (work_button None "All Tasks" s::
      map(fun w=>match natural_field "work_id" w with None=>group "invalid-work"[]|Some id=>work_button(Some id)(text "name" w)s end)(items "works" world)++
      [button "work/create" "New Work"(invoke(Input.CreateWork))(negb(connected(service_state s)))]) ]++
    (match active_work n with None=>[]|Some work=>[group "work/tabs"
      [button "work/tasks" "Tasks"(navigation_action Start)false;
       button "work/shared-ui" "Shared UI"(navigation_action(SharedUI work None))false;
       editor_button "work/name" "Rename Work"(WorkName work)]]end)
   ++if expanded n then [node Scene.ListView_role "task-tree"[("label",JsonProperty(JString "Tasks"))](navigation_tasks world s)]else []).
Definition history_text message :=value_or ""(Conversation.json_message_text message).
Definition audit_failed := Audit.failed.
Definition audit_titles : list (string * (json -> string)) := [
  ("function_call", fun message => "Tool call: "++text "name"(value_or JNull(field "content" message)));
  ("function_output", fun message => "Tool output");
  ("operation_result", fun message => text "tool" message);
  ("hook_record", fun message => "Tool permission check");
  ("approval_record", fun message => "Tool approval");
  ("after_record", fun message => "Tool result processing");
  ("fork_result", fun message => "Task fork");
  ("context_replacement", fun message => "Context compacted");
  ("reasoning_record", fun message => "Reasoning configuration");
  ("error", fun message => history_text message);
  ("task_context", fun message => "Task configuration")
].
Definition audit_title message:=match find (fun entry => String.eqb (fst entry) (text "role" message)) audit_titles with
  | Some (_, render) => render message | None => (text "role" message)
  end.
Definition audit_expanded task index message s:=match find(fun reader=>N.eqb task(reading_task reader))(readers s)with
 |None=>audit_failed message|Some reader=>match find(fun '(group,occurrence,_)=>N.eqb index group&&N.eqb occurrence 0)(disclosures reader)with Some(_,_,open)=>open|None=>audit_failed message end end.
Definition message_scene namespace task index message s :=
  let anchor:=history_key task(N.of_nat index) in
  let source:=history_text message in
  let origin:=bind(field "origin" message)decode_origin in
  let key:=match origin with Some o=>content_key namespace task o|None=>anchor++"/content"end in
  let observed:=match origin with Some o=>[("origin",JsonProperty(observation_origin namespace task o));("document_key",JsonProperty(JString key));("epoch",JsonProperty(number(epoch_for_key key s)));("revision",JsonProperty(number(N.of_nat(String.length source))));("ending",JsonProperty(JString "complete"))]|None=>[]end in
  node Scene.Section_role anchor[("attrs",JsonProperty(JObject[("data-reading-anchor",JString anchor)]))]
    (if existsb(String.eqb(value_or ""(Conversation.json_message_role message)))["user";"assistant"]then
      [text_node(anchor++"/role")(value_or "event"(Conversation.json_message_role message));
       node Scene.Markdown_role key(("value",JsonProperty(JString source))::("complete",JsonProperty(JBool true))::observed)[]]++message_images anchor message
     else let open:=audit_expanded task(N.of_nat index)message s in
      [button(anchor++"/disclose")(audit_title message)(invoke(Input.SetDisclosure task(N.of_nat index)0(negb open)))false]++
      if open then [node Scene.Code_role(anchor++"/detail")[("value",JsonProperty(JString(render_json message)))][]]else []).
Definition activity_expanded task group attention s :=
 match find(fun reader=>N.eqb task(reading_task reader))(readers s)with
 |Some reader=>match find(fun '(id,occurrence,_)=>N.eqb group id&&N.eqb attention occurrence)(disclosures reader)with
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
   [text_node(key++"/argument/"++name++"/label")name;text_node(key++"/argument/"++name++"/value")(parameter_text value)])fields
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
     [button("worktree/"++show_natural task++"/retry")"Retry worktree archive"(command_action "retry_worktree_archive"[("task_id",number task)])(negb(connected(service_state s)))]else [])]else []|None=>[]end)(items "worktrees" world).
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
       (map(fun control=>button("task/"++show_natural task++"/"++control)control(command_action control[("task_id",number task)])(negb(connected(service_state s))))
         (map(fun j=>value_or ""(as_string j))(items "controls" found))++
        [button("task/"++show_natural task++"/details")"Task details"
          (invoke(Input.OpenInformation "task_details"(JObject[("task_id",number task)])("task/"++show_natural task++"/details")))false;
         button("task/"++show_natural task++"/latest")"Return to latest"
          (invoke(Input.FollowLatest task))false;
         editor_button("task/"++show_natural task++"/fork")"Fork"(Fork task);
         editor_button("task/"++show_natural task++"/compact")"Compact history"(Compact task);
         button("task/"++show_natural task++"/side")"Side conversation"(invoke(Input.BeginSide task))(negb(connected(service_state s)));
         button("task/"++show_natural task++"/return-side")(match natural_field "parent" found with Some parent=>("追加回 task #"++show_natural parent)%string|None=>"追加回上级 task"end)(command_action "return_side_conversation"[("task_id",number task)])(negb(connected(service_state s)));
         button("task/"++show_natural task++"/voice")"Start voice"(invoke(Input.SpeechInput(BeginVoice (task))))(negb(free(speech_state s)))]);
     node Scene.Group_role("conversation/"++show_natural task++"/history")[("attrs",JsonProperty(JObject[("data-reading-root",JString "true")]))]
       (history_scenes namespace task 0(items "history" found)s++flat_map(fun output=>live_scene namespace task world output s)(filter(fun o=>N.eqb task(output_task o))(active_previews world s)));
     group("conversation/"++show_natural task++"/operations")(map(fun operation=>operation_scene task operation s)(items "operations" found));
     group("task/"++show_natural task++"/retained")
       (retained_scene namespace task world s++match find(fun entry=>N.eqb task(fst entry))(discarded_outputs s)with None=>[]|Some(_,count)=>[text_node("task/"++show_natural task++"/discarded")("已丢弃 "++show_natural count++" 个未完成输出") ]end);
     group("task/"++show_natural task++"/worktree")(worktree_scene task world s);
     form_scene(Message task)world s]
  end.
Definition projects_scene world s:=group "projects"(heading "projects/title" "项目"::editor_button "projects/new" "New project"(Project None)::map(fun p=>match natural_field "project_id" p with None=>group "invalid-project"[]|Some id=>group("project/"++show_natural id)
 [heading("project/"++show_natural id++"/name")(text "name" p);editor_button("project/"++show_natural id++"/edit")"Edit project"(Project(Some id));button("project/"++show_natural id++"/delete")"Delete project"(command_action "delete_project"[("project_id",number id)])(negb(connected(service_state s)))]end)(items "projects" world)).
Definition card_action op card now:=command_action op[("card_id",value_or JNull(field "card_id" card));("revision",value_or JNull(field "revision" card));("observed_at",JString(show_natural now))].
Definition board_cards board :=
  let cards:=items "cards" board in
  let ordered:=fold_right(fun id rest=>match natural id with Some id=>
    match find(fun card=>match natural_field "id" card with Some actual=>N.eqb id actual|None=>false end)cards with Some card=>card::rest|None=>rest end|None=>rest end)[](items "order" board)in
  List.app ordered(filter(fun card=>negb(existsb(fun other=>equal(value_or JNull(field "id" card))(value_or JNull(field "id" other)))ordered))cards).
Definition card_scene now board world card s:=let key:="card/"++value_or ""(number_field "card_id" card)in
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
    (match natural_field "card_id" card with Some id=>editor_button(key++"/edit")("打开 "++text "title" card)(Card(Some id))|None=>group(key++"/unavailable")[]end);
    button(key++"/run")"Run"(card_action "run_card" card now)(disabled "run");
    button(key++"/archive")"Archive or restore"(card_action(if flag "archived" card then "restore_card"else "archive_card")card now)(disabled(if flag "archived" card then "restore"else "archive"));
    button(key++"/pin")"Pin or unpin"(command_action "pin_card"[("card_id",value_or JNull(field "card_id" card));("revision",value_or JNull(field "revision" card));("observed_at",JString(show_natural now));("pinned",JBool(negb(flag "pinned" card)))])(disabled "metadata");
    button(key++"/delete")"Delete"(card_action "delete_card" card now)(disabled "delete");
    button(key++"/regenerate")"Regenerate title"(command_action "regenerate_card_title"[("card_id",value_or JNull(field "card_id" card));("revision",value_or JNull(field "revision" card));("observed_at",JString(show_natural now));("draft_profile",JString(text "draft_profile" board))])(disabled "edit");
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
 button "board/automatic"(if flag "automatic" board then "Pause automatic scheduling"else "Enable automatic scheduling")(command_action "board_settings"[("automatic",JBool(negb(flag "automatic" board)));("draft_profile",JString(text "draft_profile" board))])(negb(connected(service_state s)));
 node Scene.Select_role "board/draft-profile"[("label",JsonProperty(JString "Draft profile"));("value",JsonProperty(JString(text "draft_profile" board)));("options",JsonProperty(JArray(profile_choices world)));("action",InputProperty(invoke(Input.BoardProfile "")))][];
 node Scene.ListView_role "board/cards"[](map(fun choice=>let stage:=text "value" choice in
   node Scene.Section_role("board/lane/"++stage)[("attrs",JsonProperty(JObject[("data-drop-status",JString stage)]))]
    (heading("board/lane/"++stage++"/title")(text "label" choice)::
     map(fun card=>card_scene now board world card s)(filter(fun card=>String.eqb(text "status" card)stage)(BoardFilter.apply_in_world selection now cards world))))BoardFilter.stage_choices);
 node Scene.Section_role "board/archive"[("label",JsonProperty(JString "Archived cards"))](map(fun card=>card_scene now board world card s)(filter(flag "archived")cards))]).
Definition agents_scene world s:=let board:=value_or JNull(field "board" world)in
 group "agents"[heading "agents/title" "智能体";editor_button "agents/new" "New agent"(Agent None);
 node Scene.ListView_role "agents/list"[](map(fun agent=>match natural_field "agent_id" agent with None=>group "invalid-agent"[]|Some id=>group("agent/"++show_natural id)
 [heading("agent/"++show_natural id++"/name")(text "name" agent);editor_button("agent/"++show_natural id++"/edit")"Edit"(Agent(Some id));
 button("agent/"++show_natural id++"/delete")"Delete"(command_action "delete_board_agent"[("agent_id",number id);("revision",value_or JNull(field "revision" agent))])(negb(connected(service_state s)))]end)(items "agents" board))].
Definition graphs_scene world s:=group "graphs"[heading "graphs/title" "Task graphs";editor_button "graphs/new" "New task graph"(TaskGraph None(active_work(navigation_state s)));
 node Scene.ListView_role "graphs/list"[](map(fun graph=>match natural_field "graph_id" graph with None=>group "invalid-graph"[]|Some id=>group("graph/"++show_natural id)
 [heading("graph/"++show_natural id++"/name")(text "name" graph);editor_button("graph/"++show_natural id++"/edit")"Edit"(TaskGraph(Some id)(active_work(navigation_state s)));
 button("graph/"++show_natural id++"/delete")"Delete"(command_action "delete_task_graph"[("graph_id",number id)])(negb(connected(service_state s)))]end)(filter(fun graph=>match active_work(navigation_state s)with
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
Definition property_source_scene subject world s :=
 match bind(field "editor" subject)decode_editor with None=>text_node "property-source/unavailable" "来源所属的编辑器已不可用。"
 |Some e=>let task:=match e with Message task=>find_task task world|_=>None end in
  let d:=value_or(new_draft e)(find_draft e s)in
  let settings:=match task with Some task=>value_or JNull(field "settings" task)|None=>Forms.settings d end in
  let project:=natural_field "project_id" settings in
  let project_name:=match project with None=>"默认设置"|Some id=>match find_project id world with Some p=>text "name" p|None=>"已不可用的项目"end end in
  let workspace:=value_or JNull(workspace_for e world s)in
  let snapshots:=match task with Some task=>items "context" task|None=>[]end in
  group "property-source" ([heading "property-source/title" "设置与上下文来源";
    text_node "property-source/project"("项目："++project_name);
    text_node "property-source/primary"("主目录："++value_or ""(string_field "primary_root" workspace))]++
    map(fun root=>text_node("property-source/root/"++value_or ""(as_string root))(value_or ""(as_string root)))(items "roots" workspace)++
    match snapshots with []=>[text_node "property-source/context" "此编辑器尚无已记录的上下文来源。"]
    |_=>map(fun '(index,snapshot)=>context_source_scene index snapshot)(combine(map N.of_nat(seq 0(List.length snapshots)))snapshots)end)end.
Definition configuration_scene subject world s :=
 match bind(field "editor" subject)decode_editor with None=>text_node "configuration/unavailable" "任务配置已不可用。"
 |Some e=>match find_draft e s with None=>text_node "configuration/unavailable" "任务配置已不可用。"
 |Some d=>group "execution-configuration" ([heading "configuration/title" "模型与权限"]++
   map(field_scene d world s)(filter(fun f=>field_applies d world s(field_name(specification f)))execution_fields)++feedback_scene d++
   [button "configuration/apply" "应用"(invoke(Input.ApplyConfiguration e))(negb(connected(service_state s))||configuration_pending e s)])end end.
Definition panel_scene world s p:=match p with
|EditorPanel e _=>node Scene.Dialog_role("panel/"++editor_key e)[("label",JsonProperty(JString "Edit"));("dismiss_action",InputProperty(invoke(Input.ClosePanel)))][form_scene e world s;button("panel/"++editor_key e++"/close")"Close"(invoke(Input.ClosePanel))false]
|InformationPanel kind subject _=>node Scene.Dialog_role("panel/"++kind)[("label",JsonProperty(JString(if String.eqb kind "execution_configuration"then "模型与权限"else if String.eqb kind "property_source"then "设置与上下文来源"else if String.eqb kind "task_details"then "Task details"else kind)));("dismiss_action",InputProperty(invoke(Input.ClosePanel)))][(if String.eqb kind "execution_configuration"then configuration_scene subject world s else if String.eqb kind "property_source"then property_source_scene subject world s else if String.eqb kind "task_details"then task_details_scene subject world s else text_node("panel/"++kind++"/text")(text "description" subject));button("panel/"++kind++"/close")"Close"(invoke(Input.ClosePanel))false]
|ApplicationState.Confirmation _ caption _ _=>node Scene.Dialog_role "confirmation"[("label",JsonProperty(JString caption));("dismiss_action",InputProperty(invoke(Input.ClosePanel)))][heading "confirmation/title" caption;button "confirmation/confirm" "Confirm"(invoke(Input.Confirm))(negb(connected(service_state s)));button "confirmation/cancel" "Cancel"(invoke(Input.ClosePanel))false]end.
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
  |Start=>group "start"[heading "start/title"(optional_label(active_work(navigation_state s)));form_scene(NewTask(active_work(navigation_state s)))world s]
  |Conversation task=>conversation_scene namespace task world s|Projects|ProjectHome _=>projects_scene world s
  |Board=>board_scene now world s|Agents=>agents_scene world s|Graphs=>graphs_scene world s
  |HistorySearch=>search_scene s world|SharedUI work task=>shared_ui_scene work task world s end in
  node Scene.Group_role "application"[("layout",JsonProperty(JString "workspace"));("appearance",JsonProperty(JString(appearance_name(theme(service_state s)))));("attrs",JsonProperty(JObject[("class",JString "application")]))]
  ([navigation_scene world s;node Scene.Main_role "main"[("attrs",JsonProperty(JObject[("tabindex",JString "-1")]))](storage_notice s++[main])]++
   match side_task(navigation_state s)with None=>[]|Some task=>[node Scene.Aside_role "side-conversation"[("label",JsonProperty(JString "Side conversation"))][heading "side-conversation/title"("Side conversation · task #"++show_natural task);button "side-conversation/close" "关闭"(invoke(Input.CloseSide))false;conversation_scene namespace task world s]]end++
   map(panel_scene world s)(rev(layers(navigation_state s)))++settings_scene s++preview_scene s++directory_scene s).
