From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers TextJson.
From Selvedge.Interaction Require Import Codec Identity.
From Selvedge.Interaction Require World.
From Selvedge.Interaction.Experience Require Model Observation Read.
From Selvedge.Interaction.Submission Require Fields Parameters Draft GraphAuthoring.
From Selvedge.Browser.Session Require State Input.
From Selvedge.Browser.Scene Require Import Surface Model Construction.
From Selvedge.Browser.Presentation Require Roles Information.
Import ListNotations.
Open Scope string_scope.

Module UX := Selvedge.Interaction.Experience.Model.
Module Session := Selvedge.Browser.Session.State.

Definition form_input parent key label multiline value choices (receive : string -> option Input.input) :=
 Node (part parent key) key label Roles.Field
   (ConfigurationField multiline value choices true (fun raw => bind (as_string raw) receive)) [].
Definition text_field parent key label multiline source receive :=
 form_input parent key label multiline (value_or "" (string_field key source)) None
   (fun raw => receive (replace key (JString raw) source)).
Definition select_field parent key label value choices receive :=
 form_input parent key label false value (Some choices) receive.
Definition select_prompt label selected choices :=
 if existsb (fun choice => String.eqb selected (Fields.choice_value_of choice)) choices
 then choices else Fields.ChoiceValue selected label :: choices.
Definition form_action parent key label action : list (node Input.input) :=
 match action with
 | Some input => [declared parent Roles.Button (secondary key label input)]
 | None => []
 end.
Definition without_field key value := JObject (remove_field key (object_fields value)).
Definition indexed {A} (entries : list A) :=
 combine (seq 0 (List.length entries)) entries.
Definition replace_row {A} index (value : A) (entries : list A) :=
 (firstn index entries ++ value :: skipn (S index) entries)%list.
Definition remove_row {A} index (entries : list A) :=
 (firstn index entries ++ skipn (S index) entries)%list.
Definition row_number index := show_natural (N.of_nat (S index)).
Definition fresh_key prefix entries :=
 let candidates := map (fun index => prefix ++ "-" ++ row_number index)
   (seq 0 (S (List.length entries))) in
 value_or prefix (find (fun key => negb (existsb (fun entry =>
   match string_field "key" entry with Some existing => String.eqb existing key | None => false end) entries)) candidates).
Definition node_kind_label kind :=
 match kind with "entrance" => "入口" | "exit" => "出口" | _ => "任务" end.
Definition declaration_assignment e :=
 subject <- UX.admit_subject e (Parameters.name Fields.TaskGraphDeclaration);;
 Some (fun value => Input.assign_subject subject (JString (GraphAuthoring.render_declaration value))).
Definition task_choices snapshot work :=
 let tasks := Read.work_tasks work (value_or [] (Read.tasks snapshot)) in
 map (fun task =>
   let id := show_natural (Read.task_id task) in
   Fields.ChoiceValue id (Read.task_title task ++ " · #" ++ id))
   (filter (fun task => negb (String.eqb (Read.task_status task) "archived")) tasks).
Definition task_node_fields snapshot work parent (entry : json) save :=
 let existing := natural_field "task_id" entry in
 let existing_mode := match existing with Some _ => true | None => false end in
 let new_task := without_field "task_id" entry in
 let profiles := Observation.selectable_profile_choices snapshot in
 let conversations := task_choices snapshot work in
 let mode := if existing_mode then "existing" else "new" in
 let select_mode raw :=
   if String.eqb raw "existing" then
     match conversations with
     | choice :: _ => id <- parse_natural (Fields.choice_value_of choice);;
       save (replace "task_id" (number id) (without_field "settings" (without_field "creation" (without_field "profile" entry))))
     | [] => None end
   else
     save (replace "creation" (JString "once") (replace "profile" (JString "") new_task)) in
 select_field parent "task-mode" "任务来源" mode
   (Fields.ChoiceValue "new" "创建对话" :: match conversations, existing with
   | [], None => [] | _, _ => [Fields.ChoiceValue "existing" "使用已有对话"] end) select_mode ::
 match existing with
 | Some id =>
   let selected := show_natural id in
   [select_field parent "task-id" "对话" selected (select_prompt ("不可用的对话 #" ++ selected) selected conversations)
     (fun raw => next <- parse_natural raw;; save (replace "task_id" (number next) entry))]
 | None =>
   let selected := value_or "" (string_field "profile" entry) in
   let prompt := if String.eqb selected "" then "请选择模型" else "不可用的模型 · " ++ selected in
   [select_field parent "profile" "模型" selected (select_prompt prompt selected profiles)
      (fun raw => save (replace "profile" (JString raw) entry));
    select_field parent "creation" "对话创建方式" (value_or "once" (string_field "creation" entry))
      [Fields.ChoiceValue "once" "每个实例复用一条对话"; Fields.ChoiceValue "each" "每次收到消息时创建"]
      (fun raw => save (replace "creation" (JString raw) entry))]
 end.
Definition endpoint_uses key value :=
 match string_field key value with Some name => String.eqb name | None => fun _ => false end.
Definition rename_endpoint old next key edge :=
 if endpoint_uses key edge old then replace key (JString next) edge else edge.
Definition node_fields snapshot work parent nodes edges save '(index, entry) :=
 let key := part parent (row_number index) in
 let name := value_or "" (string_field "key" entry) in
 let kind := value_or "task" (string_field "kind" entry) in
 let caption := node_kind_label kind ++ " " ++ row_number index in
 let same_key value := endpoint_uses "key" value in
 let other_nodes := remove_row index nodes in
 let accepts raw :=
   if existsb (fun node => same_key node raw) other_nodes then None
   else
     let renamed := map (fun edge => rename_endpoint name raw "target" (rename_endpoint name raw "source" edge)) edges in
     save (replace_row index (replace "key" (JString raw) entry) nodes) renamed in
 Node key "workflow-node-editor" caption Roles.Section Region
   ([group_title key caption; form_input key "key" "节点名称" false name None accepts] ++
    (if String.eqb kind "task" then task_node_fields snapshot work key entry
      (fun updated => save (replace_row index updated nodes) edges) else []) ++
    form_action key "remove-node" ("移除" ++ caption)
      (save other_nodes (filter (fun edge => negb (endpoint_uses "source" edge name || endpoint_uses "target" edge name)) edges)))%list.
Definition connection_fields parent nodes edges save '(index, entry) :=
 let key := part parent (row_number index) in
 let caption := "连线 " ++ row_number index in
 let assign updated := save (replace_row index updated edges) in
 let endpoint_options := map (fun node =>
   let name := value_or "" (string_field "key" node) in
   Fields.ChoiceValue name name) (filter (fun node => negb (endpoint_uses "key" node "")) nodes) in
 let endpoint field label :=
   let selected := value_or "" (string_field field entry) in
   select_field key field label selected (Fields.ChoiceValue "" "请选择节点" :: endpoint_options)
     (fun raw => assign (if String.eqb raw "" then without_field field entry else replace field (JString raw) entry)) in
 let message := value_or JNull (Json.field "message" entry) in
 let message_kind := value_or "output" (string_field "kind" message) in
 let message_fields :=
   if String.eqb message_kind "output" || String.eqb message_kind "literal" then
     select_field key "message-kind" "发送内容" message_kind
       [Fields.ChoiceValue "output" "转发原消息"; Fields.ChoiceValue "literal" "使用固定消息"]
       (fun raw => assign (if String.eqb raw "output" then without_field "message" entry
         else replace "message" (JObject [("kind",JString "literal");("value",JString "")]) entry)) ::
     (if String.eqb message_kind "literal" then
       [text_field key "value" "固定消息" true message (fun updated => assign (replace "message" updated entry))]
      else [])
   else [information key "custom-message" Information.Description "在高级选项中编辑此自定义消息。"] in
 Node key "workflow-connection-editor" caption Roles.Section Region
   ([group_title key caption; endpoint "source" "来源节点"; endpoint "target" "接收节点";
     text_field key "description" "连线说明" false entry assign] ++ message_fields ++
    form_action key "remove-connection" ("移除" ++ caption) (save (remove_row index edges)))%list.

Definition definition_fields snapshot parent work value (save : json -> option Input.input) :=
 let nodes := items "nodes" value in
 let edges := items "connections" value in
 let node_panel := part parent "workflow-nodes" in
 let edge_panel := part parent "workflow-connections" in
 let set_graph next_nodes next_edges :=
   save (replace "connections" (JArray next_edges) (replace "nodes" (JArray next_nodes) value)) in
 let add_node kind :=
   let prefix := match kind with "entrance" => "start" | "exit" => "finish" | _ => "task" end in
   let fields := [("key",JString (fresh_key prefix nodes));("kind",JString kind)] in
   let entry := JObject (fields ++ if String.eqb kind "task" then
     [("profile",JString "");("creation",JString "once")] else [])%list in
   form_action node_panel ("add-" ++ kind) ("添加" ++ node_kind_label kind) (set_graph (nodes ++ [entry])%list edges) in
 [text_field parent "name" "工作流名称" false value save;
  region parent "workflow-nodes" "节点" Roles.Section
    (group_title node_panel "节点" :: map (node_fields snapshot work node_panel nodes edges set_graph) (indexed nodes) ++
     flat_map add_node ["entrance";"task";"exit"])%list;
  region parent "workflow-connections" "连线" Roles.Section
    (group_title edge_panel "连线" ::
     map (connection_fields edge_panel nodes edges (set_graph nodes)) (indexed edges) ++
     form_action edge_panel "add-connection" "添加连线"
       (set_graph nodes (edges ++ [JObject [("key",JString (fresh_key "route" edges))]])%list))%list].

Definition definition snapshot (s : Session.state) parent e id work :=
 let scope := match id with
 | None => work
 | Some workflow => bind (World.find_world "workflows" "workflow_id" workflow snapshot) (natural_field "work_id")
 end in
 match Draft.contents (Session.current_draft s e), declaration_assignment e with
 | Draft.WorkflowDefinitionBody _ _ source, Some save =>
   match parse_json source with
   | Some (JObject _ as value) => definition_fields snapshot parent scope value save
   | _ => []
   end
 | _, _ => []
 end.
Definition start snapshot (s : Session.state) parent e id :=
 match World.find_world "workflows" "workflow_id" id snapshot,
       Draft.contents (Session.current_draft s e), declaration_assignment e with
 | Some workflow, Draft.WorkflowStartBody _ source, Some save =>
   match parse_json source with
   | Some value =>
     let entries := flat_map (fun node => match string_field "kind" node, string_field "key" node with
       | Some "entrance", Some key => [Fields.ChoiceValue key key]
       | _, _ => [] end) (items "nodes" workflow) in
     let selected := value_or "" (string_field "entrance" value) in
     [read_only parent "workflow-name" "工作流" (value_or "" (string_field "name" workflow));
      select_field parent "entrance" "入口" selected (select_prompt "请选择入口" selected entries)
        (fun raw => save (replace "entrance" (JString raw) value));
      text_field parent "message" "消息" true value save]
   | None => []
   end
 | _, _, _ => []
 end.
