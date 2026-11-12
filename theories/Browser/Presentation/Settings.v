From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers TextJson.
From Selvedge.Adapters Require Common ProviderCatalog.
From Selvedge.Browser Require Import NavigationIdentity.
From Selvedge.Interaction Require Import Codec Identity.
From Selvedge.Interaction.Submission Require Fields.
From Selvedge.Browser.Session Require Import Appearance Input Services State.
From Selvedge.Browser.Session Require Configuration Speech.
From Selvedge.Programming Require Import Resource.
From Selvedge.Browser.Scene Require Import Surface Model Construction.
From Selvedge.Browser.Presentation Require Import Projection.
From Selvedge.Browser.Presentation Require Roles Information ModelProfiles ConfigurationForms Navigation.
Import ListNotations.
Open Scope string_scope.

Module Config := Configuration.Config.

Definition settings_root := "/settings".
Definition conversation_titles_label := "对话标题".

Definition section_label section :=
 match section with
 | SettingsGeneral => "常规" | SettingsModels => "模型" | SettingsTools => "连接器"
 | SettingsExtensions => "扩展"
 | SettingsTasks => "任务" | SettingsContext => "上下文" | SettingsConnection => "服务"
 end.
Definition same_section left right :=
 String.eqb (settings_section_name left) (settings_section_name right).
Inductive settings_group_content :=
| AppearanceSettings
| ConversationSettings (instructions : list string)
| LocalService
| ConfigurationSettings (paths : list (list string))
| ContextSources.

Record settings_section_design := SectionDesign {
 section_primary : option (string * list string);
 section_groups : list (string * string * settings_group_content)
}.

(* The primary collection owns the page's introductory copy and Add action.
   Its entries precede the secondary groups, which follow this reading order. *)
Definition section_design section : settings_section_design :=
 match section with
 | SettingsGeneral => SectionDesign None
   [("appearance", "", AppearanceSettings);
    ("conversation", "对话默认设置", ConversationSettings ["instructions"])]
 | SettingsModels => SectionDesign (Some ("model-configurations", ["profiles"]))
   [("model-services", "", ConfigurationSettings [["chatgpt"]; ["reasoning_evaluators"]])]
 | SettingsTools => SectionDesign (Some ("tool-connections", ["mcp"]))
   [("project-sharing", "", ConfigurationSettings [["chatgpt_plugin"]])]
 | SettingsExtensions => SectionDesign None
   [("tool-sources", "", ConfigurationSettings [["plugins"]; ["skills"]])]
 | SettingsTasks => SectionDesign None
   [("limits", "任务限制", ConfigurationSettings [["max_fork"]; ["max_descendants"]]);
    ("workspaces", "", ConfigurationSettings [["cloud"]])]
 | SettingsContext => SectionDesign None
   [("compaction", "上下文压缩",
      ConfigurationSettings [["compaction"; "enabled"]; ["compaction"; "background_percent"];
       ["compaction"; "blocking_percent"]; ["compaction"; "idle_lead_ms"]]);
    ("model-limits", "", ConfigurationSettings [["compaction"; "targets"]]);
    ("sources", "上下文来源", ContextSources)]
 | SettingsConnection => SectionDesign None
   [("connection", "", LocalService);
    ("binding", "本机监听", ConfigurationSettings [["host"]; ["port"]]);
    ("remote", "", ConfigurationSettings [["remote"]])]
 end.

Definition primary_group design :=
 option_map (fun '(key, path) => (key, "", ConfigurationSettings [path])) (section_primary design).

Definition configuration_groups section :=
 let design := section_design section in
 match primary_group design with
 | Some group => group :: section_groups design
 | None => section_groups design
 end.

Definition primary_collection section := option_map snd (section_primary (section_design section)).

Definition same_setting_root (left right : list string) :=
 match left, right with
 | root :: _, candidate :: _ => String.eqb root candidate
 | _, _ => false
 end.

(* Configured families keep their descendants in the same section. The
   conversation instructions are a single setting. Context owns unlisted paths. *)
Definition declares_setting section path :=
 existsb (fun '(_, _, content) =>
   match content with
   | ConversationSettings instructions => String.eqb (Config.setting_key instructions) (Config.setting_key path)
   | ConfigurationSettings paths => existsb (same_setting_root path) paths
   | _ => false
   end) (configuration_groups section).

Definition section_for path :=
 value_or SettingsContext (find (fun section => declares_setting section path) settings_sections).

Definition copy path : string * string :=
 match path with
 | ["instructions"] => ("对话指引", "适用于新建对话。")
 | ["profiles"] => ("模型配置", "选择对话可用的模型及其提供方。")
 | ["chatgpt"] => ("ChatGPT 模型", "允许对话使用 ChatGPT 账号中的模型。")
 | ["reasoning_evaluators"] => ("推理评估器", "用于评估自适应推理结果的服务。")
 | ["mcp"] => ("MCP 服务器", "通过 MCP 连接工具和资源。")
 | ["plugins"] => ("插件", "扩展对话可用的功能。")
 | ["skills"] => ("技能来源", "服务查找技能的文件和目录。")
 | ["chatgpt_plugin"] => ("ChatGPT 应用连接", "允许 ChatGPT 应用访问选定项目。")
 | ["max_fork"] => ("直接分支上限", "每个对话能创建的直接分支数。")
 | ["max_descendants"] => ("分支总数上限", "从同一根对话派生的全部分支数。")
 | ["cloud"] => ("云端工作区", "通过腾讯云为对话创建工作区。")
 | ["compaction"; "enabled"] => ("自动压缩", "接近模型的上下文上限时，摘要较早的内容。")
 | ["compaction"; "background_percent"] => ("后台压缩阈值（%）", "达到阈值后在后台压缩，对话可继续运行。")
 | ["compaction"; "blocking_percent"] => ("等待压缩阈值（%）", "达到阈值后，等压缩完成再发送下一次请求。")
 | ["compaction"; "idle_lead_ms"] => ("空闲提前量（秒）", "在缓存过期前提前多久开始压缩，可精确到 0.001 秒。")
 | ["compaction"; "targets"] => ("模型上下文限制", "按模型配置设置上下文窗口和压缩方式。")
 | ["host"] => ("监听地址", "服务启动时绑定的回环地址。")
 | ["port"] => ("监听端口", "服务启动时使用的端口。填 0 自动选择可用端口。")
 | ["remote"] => ("远程控制中继", "设置配对远程控制设备所用的中继。")
 | _ => (String.concat " / " path, "")
 end.
Definition open_label path :=
 match path with
 | ["chatgpt"] => "配置账号访问" | ["remote"] => "配置中继"
 | ["instructions"] => "编辑指引"
 | ["cloud"] => "配置云端工作区" | ["compaction"; "targets"] => "编辑限制"
 | ["skills"] => "编辑来源" | _ => "编辑" ++ fst (copy path)
 end.
Definition save_label path :=
 match path with
 | ["profiles"] => "保存模型配置" | ["reasoning_evaluators"] => "保存评估器"
 | ["chatgpt"] => "保存账号访问设置" | ["chatgpt_plugin"] => "保存连接"
 | ["mcp"] => "保存服务器" | ["plugins"] => "保存插件" | ["skills"] => "保存来源"
 | ["remote"] => "保存中继" | ["cloud"] => "保存云端设置"
 | ["compaction"; "targets"] => "保存限制"
 | ["instructions"] => "保存指引" | ["host"] => "保存地址" | ["port"] => "保存端口"
 | _ => "保存"
 end.

Definition action parent key label emphasis (enabled : bool) input : node Input.input :=
 declared parent Roles.Button (Control key label emphasis (Input.ServiceInput input)
   (if enabled then Available else Unavailable "当前不可用")).
Definition button parent key label := action parent key label Secondary.
Definition note parent key text : node Input.input := information parent key Information.Description text.
Definition named_region parent key label (children : list (node Input.input)) := region parent key label Roles.Section children.
Definition title_block parent label description controls :=
 let heading := part parent "settings-title" in
 named_region parent "settings-title" ""
   [named_region heading "settings-row" ""
      [named_region heading "settings-copy" ""
         (title heading label :: if String.eqb description "" then [] else [note heading "description" description]);
       named_region heading "settings-controls" "" controls]].
Definition section_group parent key label rows : list (node Input.input) :=
 match rows with
 | [] => []
 | _ => [Node (part parent key) "settings-group" "" Roles.Section Region
       ((if String.eqb label "" then [] else [group_title (part parent key) label]) ++ rows)]
 end.
Definition copy_nodes parent label description : list (node Input.input) :=
 information parent "setting-name" Information.FieldLabel label ::
   (if String.eqb description "" then [] else [note parent "description" description]).
(* A setting owns its name, help, control and any details revealed by that
   control. The row can change columns without moving the details to another
   setting or turning the edit into a navigation destination. *)
Definition row parent key label description controls below : node Input.input :=
 let id := part parent key in
 Node id "settings-item" "" Roles.Section Region
   (Node (part id "row") "settings-row" "" Roles.Section Region
     [named_region id "settings-copy" "" (copy_nodes (part id "settings-copy") label description);
      named_region id "settings-controls" "" controls] :: below).

Definition configuration_field parent key label multiline raw options enabled path :=
 ModelProfiles.field parent key label multiline raw options enabled (Services.EditConfigurationAt path).
Definition active_raw path view :=
 draft <- Configuration.current_draft view ;;
 if Configuration.matches_path path draft then Some (Configuration.draft_input draft) else None.
Definition value_label value :=
 match value with JBool true => "开启" | JBool false => "关闭" | _ => Config.display_value value end.
Definition options_for raw options :=
 let choices := map (fun value => Fields.ChoiceValue (render_json value) (value_label value)) options in
 if existsb (fun value => String.eqb (render_json value) raw) options then choices
 else Fields.ChoiceValue raw "请选择" :: choices.
Definition can_edit path services :=
 Services.connected services && Configuration.can_select path (service_configuration services).

Definition write_status parent view : list (node Input.input) :=
 match Configuration.writing view with
 | Loading _ _ => [information parent "saving" Information.Status "正在保存…"]
 | Failed _ _ reason => [information parent "save-error" Information.Status reason]
 | Loaded _ _ _ => [information parent "saved" Information.Status "设置已保存"]
 | Dormant => []
 end.
Definition is_resettable := Config.can_reset.
Definition reset_button parent entry enabled label :=
 if is_resettable entry then [button parent "restore-default" label enabled Services.ResetConfiguration] else [].
Definition save_enabled entry raw view enabled :=
 enabled && Configuration.dirty view &&
 match Config.interpret_setting_input entry raw with Some _ => true | None => false end.
Definition boolean_control parent path label raw (enabled : bool) :=
 let key := "setting-switch" in
 let on := String.eqb raw "true" in
 Node (part parent key) key label Roles.Button
   (Choice ToggleChoice on ""
     (Control key label Secondary (Input.ServiceInput
       (Services.SetConfigurationAt path (if on then "false" else "true")))
       (if enabled then Available else Unavailable "请等待当前设置保存完成"))) [].
Definition compact_setting parent services entry :=
 let path := Config.setting_path entry in
 let key := Config.setting_key path in
 let '(label, description) := copy path in
 let view := service_configuration services in
 let enabled := can_edit path services in
 let draft := active_raw path view in
 let raw := value_or (Config.initial_input entry) draft in
 let id := part parent key in
 let controls := part id "settings-controls" in
 let widget := match Config.setting_input entry with
 | Config.Boolean => boolean_control controls path label (Config.initial_input entry) enabled
 | Config.Number => configuration_field controls "setting-number" label false raw None enabled path
 | Config.Choice options => configuration_field controls "setting-value" label false raw
       (Some (options_for raw options)) enabled path
 | _ => configuration_field controls "setting-value" label false raw None enabled path
 end in
 let defaults := if is_resettable entry && negb (Configuration.dirty view) then
   [button controls "restore-default" "恢复默认" enabled (Services.ResetConfigurationAt path)] else [] in
 let bar := part id "setting-feedback" in
 let updates := match draft with
 | Some _ =>
   (write_status bar view ++
    if Configuration.dirty view then
      [button bar "cancel" "撤销编辑" enabled Services.CancelConfigurationEdit;
       action bar "save" (match Config.setting_input entry with Config.Boolean => "重试保存" | _ => save_label path end)
         Primary (save_enabled entry raw view enabled) Services.SetConfiguration]
    else [])%list
 | None => []
 end in
 row parent key label description (widget :: defaults)
   (match updates with [] => [] | _ => [region id "setting-feedback" "" Roles.DialogActions updates] end).

Definition child_items path value : list (string * json) :=
 match Configuration.collection_root path with
 | Some None => Common.object_fields value
 | Some (Some wrapper) => Common.object_fields (Common.get value wrapper)
 | None => []
 end.
Definition meaningful text := negb (String.eqb text "").
Definition detail_join left right :=
 if meaningful left then if meaningful right then left ++ " · " ++ right else left else right.
Definition item_detail path value :=
 match path with
 | ["profiles"] =>
   let model := Common.text (Common.get value "model") in
   let provider := match ProviderCatalog.backend value with
       | Some registered => ModelProfiles.provider_label registered
       | None => Common.text (Common.get value "provider") end in
   if String.eqb provider (ModelProfiles.provider_label ProviderCatalog.Offline) && String.eqb model "echo" then provider
   else detail_join provider model
 | ["reasoning_evaluators"] => detail_join
     (value_or "vercel" (as_string (Common.get value "provider"))) (Common.text (Common.get value "model"))
 | ["mcp"] | ["plugins"] => Common.text (Common.get value "command")
 | ["chatgpt_plugin"] =>
   let count := List.length (Common.items (Common.get value "project_ids")) in
   show_natural (N.of_nat count) ++ " 个项目"
 | _ => ""
 end.
Definition summary_lines parent path value : list (node Input.input) :=
 match path with
 | ["remote"] => match Common.get value "relay_url" with
      | JString url => [note parent "current-value" url] | _ => [] end
 | ["cloud"] => match Common.get value "tencent_cvm" with
      | JObject _ => [note parent "current-value"
        (detail_join "腾讯云" (Common.text (Common.get (Common.get value "tencent_cvm") "region")))]
      | _ => [] end
 | ["compaction"; "targets"] =>
    map (fun '(index, item) =>
      let id := part parent ("target-summary-" ++ ConfigurationForms.index_label index) in
      Node id "settings-summary-item" "" Roles.Section Region
        (copy_nodes id (Common.text (Common.get item "profile"))
          (match Common.get item "window_tokens" with JNumber amount => amount ++ " 个 token" | _ => "" end)))
      (ConfigurationForms.indexed (Common.items value))
 | _ => map (fun '(index, item) => note parent
      ("item-" ++ ConfigurationForms.index_label index) (Config.display_value item))
      (ConfigurationForms.indexed (Common.items value))
 end.

(* The overview owns the saved values and the entry point. A focused editor
   is a separate layer and returns to the same entry point when it closes. *)
Definition setting_entry_parent path := part settings_root (Config.setting_key path).
Definition edit_item_key name := part "edit" name.
Definition editor_trigger path key := part (setting_entry_parent path) key.
Definition editor_button path key caption label (enabled : bool) input : node Input.input :=
 let id := editor_trigger path key in
 Node id "edit-setting" label Roles.Button
   (Activate (Control key label Secondary (Input.ServiceInput input)
     (if enabled then Available else Unavailable "请先完成当前编辑")))
   [information id "label" Information.OptionLabel caption].

Definition account_sign_in_button parent label unavailable (speech : Speech.speech) : node Input.input :=
 let key := "sign-in" in
 declared parent Roles.Button (Control key label Secondary
   (Input.SpeechInput (Speech.Authorize (part parent key)))
   (if Speech.can_authorize speech then Available else Unavailable unavailable)).
Definition sign_in_button parent := account_sign_in_button parent
 "Sign in with ChatGPT" "Sign-in is unavailable in the current state".

Definition form_setting parent services speech entry (measuring : bool) :=
 let path := Config.setting_path entry in
 let key := Config.setting_key path in
 let id := part parent key in
 let saved := Config.setting_value entry in
 let '(label, description) := copy path in
 let description := match path, saved with
   | ["chatgpt"], JBool false => "已关闭 ChatGPT 账号访问。"
   | _, _ => description end in
 let lines := if measuring then [] else summary_lines (part id "settings-values") path saved in
 row parent key label description
   ((match path, Speech.connections speech with
    | ["chatgpt"], [] => match saved with
      | JBool false => [] | _ => [account_sign_in_button (part id "settings-controls")
         "使用 ChatGPT 登录" "当前无法登录" speech] end
    | _, _ => [] end) ++
    [editor_button path "open" (open_label path) (open_label path)
      (can_edit path services) (Services.SelectConfiguration path)])
   (match lines with [] => [] | _ => [named_region id "settings-values" "" lines] end).

(* The overview enumerates saved objects. Draft edits and removals become
   visible here after a successful write. *)
Definition collection_add services path item :=
 button (setting_entry_parent path) "begin-add" ("添加" ++ item) (can_edit path services)
   (Services.BeginAddConfigurationItem path).

(* The editable collections inherit empty lists. Resetting a saved empty
   list has no effect on the entries. *)
Definition collection_reset_has_effect entry :=
 is_resettable entry &&
 match Configuration.collection_root (Config.setting_path entry), Config.setting_value entry with
 | Some None, JObject [] => false
 | Some (Some wrapper), JObject [(key, JObject [])] => negb (String.eqb key wrapper)
 (* DEFENSE: Editable snapshots can reflect malformed file contents. Keep
    Reset available for recovery even when there are no readable entries. *)
 | _, _ => true
 end.

Definition collection_controls parent services entry item :=
 let path := Config.setting_path entry in
 collection_add services path item ::
 if collection_reset_has_effect entry then
   [button parent "restore-default" "恢复列表默认值" (can_edit path services)
     (Services.ResetConfigurationAt path)] else [].

Definition collection_setting parent services entry item (page_collection measuring : bool) :=
 let path := Config.setting_path entry in
 let key := Config.setting_key path in
 let id := part parent key in
 let list_id := part id "settings-entries" in
 let header := part id "settings-collection-heading" in
 let view := service_configuration services in
 let enabled := can_edit path services in
 let entries := child_items path (Config.setting_value entry) in
 let '(label, description) := copy path in
 let entry_row '(name, value) :=
   row list_id (part "entry" name) name (item_detail path value)
     [editor_button path (edit_item_key name) "编辑" ("编辑「" ++ name ++ "」") enabled
       (Services.SelectConfigurationItem path name)] [] in
 let entries_body := if measuring then [] else
   [named_region id "settings-entries" label (match entries with
    | [] => [note list_id "description" (if collection_reset_has_effect entry
                then "无法读取" ++ label ++ "列表。" else "暂无" ++ label ++ "。")]
    | _ => map entry_row entries
    end)] in
 let feedback := if measuring then [] else match active_raw path view, Configuration.writing view with
   | Some _, Loading _ _ | Some _, Failed _ _ _ => write_status (part id "feedback") view
   | _, _ => []
   end in
 let heading := if page_collection then [] else
   [named_region id "settings-row" ""
     [named_region header "settings-copy" ""
        [group_title header label; note header "description" description];
      named_region header "settings-controls" "" (collection_controls header services entry item)]] in
 Node id "settings-collection" "" Roles.Section Region
   (heading ++ entries_body ++ feedback)%list.

Definition normal_entry parent services speech primary measuring entry :=
 let path := Config.setting_path entry in
 match ConfigurationForms.collection_item path with
 | Some item => collection_setting parent services entry item
     (match primary with Some main => String.eqb (Config.setting_key main) (Config.setting_key path)
       | None => false end) measuring
 | None => if Configuration.focused_editor entry then form_setting parent services speech entry measuring
           else compact_setting parent services entry
 end.

Definition catalog_entries services :=
 match Configuration.available (service_configuration services) with
 | Some snapshot => Config.entries snapshot | None => [] end.
Definition entries_for_paths services paths :=
 match Configuration.available (service_configuration services) with
 | Some snapshot => flat_map (fun path => match Config.find_setting path snapshot with
       | Some entry => [entry] | None => [] end) paths
 | None => []
 end.

Definition page_heading parent services section :=
 let label := section_label section in
 match primary_collection section with
 | None => title_block parent label "" []
 | Some path =>
   let controls := match entries_for_paths services [path], ConfigurationForms.collection_item path with
     | entry :: _, Some item => collection_controls (part parent "settings-title") services entry item
     | _, _ => [] end in
   title_block parent label (snd (copy path)) controls
 end.

Definition appearance_sample parent key : node Input.input :=
 let sample := part parent key in
 let rail := part sample "theme-sample-rail" in
 let main := part sample "theme-sample-main" in
 let composer := part main "theme-sample-composer" in
 let text parent name value := Node (part parent name) name "" Roles.Content (ReadOnly value) [] in
 region parent key "" Roles.Decorative
   [region sample "theme-sample-rail" "" Roles.Decorative
      [text rail "theme-sample-brand" "Selvedge";
       text rail "theme-sample-task" Navigation.all_conversations_label];
    region sample "theme-sample-main" "" Roles.Decorative
      [text main "theme-sample-title" Navigation.new_conversation_label;
       region main "theme-sample-composer" "" Roles.Decorative
         [text composer "theme-sample-prompt" "输入消息…";
          text composer "theme-sample-send" "↑"]]].

Definition appearance parent current :=
 let section := part parent "theme" in
 let id := part (part section "settings-controls") "theme-options" in
 let themes := [("浅色", Appearance.LightAppearance); ("跟随系统", Appearance.SystemAppearance); ("深色", Appearance.DarkAppearance)] in
 named_region parent "theme" ""
   [group_title section "外观";
    Node id "theme-options" "颜色主题" Roles.Section ChoiceGroup
     (map (fun '(label, theme) =>
        let key := Appearance.appearance_name theme in
        let choice := part id key in
        let light := appearance_sample choice "theme-sample-light" in
        let dark := appearance_sample choice "theme-sample-dark" in
        let samples := match theme with
          | Appearance.LightAppearance => [light]
          | Appearance.DarkAppearance => [dark]
          | Appearance.SystemAppearance => [light; dark]
          end in
        Node choice ("theme-" ++ key) label Roles.Button
          (Choice SingleChoice (String.eqb key (Appearance.appearance_name current)) ""
             (secondary key label (Input.ServiceInput (Services.ChooseAppearance theme))))
          (samples ++ [Node (part choice "theme-choice-label") "theme-choice-label" "" Roles.Content (ReadOnly label) []])%list) themes)].

Definition local_connection parent services :=
 let id := part (part parent "local") "settings-controls" in
 match Services.connection services with
 | ConnectionReady _ => row parent "local" "本地服务" "当前浏览器已连接 Selvedge。"
      [information id "service-connected" Information.OptionLabel "已连接"] []
 | ConnectionLoading _ => row parent "local" "本地服务" "正在连接 Selvedge…"
      [information id "service-connecting" Information.Status "连接中"] []
 | ConnectionDormant => row parent "local" "本地服务" "将当前浏览器连接到 Selvedge。"
      [button id "connect" "连接" true Services.Connect] []
 | ConnectionFailed _ reason | ConnectionRevoked _ reason =>
      row parent "local" "本地服务" "将当前浏览器连接到 Selvedge。"
        [button id "connect" "重新连接" true Services.Connect]
        [information (part parent "local") "service-error" Information.Status reason]
 end.
Definition overview root parent section services speech measuring groups :=
 let render_group '(key, label, content) :=
   let id := part parent key in
   let render_entries := map (normal_entry id services speech (primary_collection section) measuring) in
   let body :=
     match content with
     | AppearanceSettings => if measuring then [] else [appearance id (Services.theme services)]
     | ConversationSettings instructions =>
       (map (fun entry => form_setting id services speech entry measuring) (entries_for_paths services [instructions])
       ++ [row id "title-prompts" conversation_titles_label "选择生成标题的模型和提示词。"
           [declared root Roles.Button (secondary "title-prompts" "编辑标题设置"
              (Input.OpenEditor TitlePrompts (part root "title-prompts")))] []])%list
     | LocalService => [local_connection id services]
     | ConfigurationSettings paths => render_entries (entries_for_paths services paths)
     | ContextSources =>
       let unlisted entry :=
         let path := Config.setting_path entry in
         same_section (section_for path) section && negb (declares_setting section path) in
       render_entries (filter unlisted (catalog_entries services))
     end in
   section_group parent key label body in
 flat_map render_group groups.

Definition catalog_status parent services :=
 let load label := button parent "load-configuration" label (Services.connected services) Services.LoadConfiguration in
 match Configuration.catalog (service_configuration services) with
 | Dormant => if Services.connected services then [load "加载服务设置"]
       else [note parent "connection-needed" "连接本地服务后可编辑设置。"]
 | Loading _ _ => [information parent "loading" Information.Status "正在加载服务设置…"]
 | Failed _ _ reason => [information parent "load-error" Information.Status reason; load "重新加载设置"]
 | Loaded _ _ _ => []
 end.
Definition draft_notice parent section view :=
 match Configuration.current_draft view with
 | Some draft =>
   let path := Configuration.draft_path draft in
   let owner := section_for path in
   if (Configuration.has_unsaved_work view || Configuration.pending view) && negb (same_section section owner) then
     let id := part parent "draft-notice" in
     [named_region parent "draft-notice" ""
       [note id "description" ("正在编辑「" ++ fst (copy path) ++ "」（" ++ section_label owner ++ "）。");
        button id "return-to-edit" "返回编辑" true (Services.SelectSettingsSection owner)]]
   else []
 | None => []
 end.

Definition navigation parent current : list (node Input.input) :=
 let id := part parent "settings-nav" in
 let section_choice section :=
   let key := settings_section_name section in
   let label := section_label section in
   Node (part id key) "settings-category" label Roles.Button
     (Choice SingleChoice (same_section current section) ""
       (secondary key label (Input.ServiceInput (Services.SelectSettingsSection section)))) [] in
 [Node id "settings-nav" "设置分类" Roles.Section ChoiceGroup
   (map section_choice settings_sections)].

(* The same category choice moves from the rail to the settings heading
   when the rail would take up the document's reading space. *)
Definition compact_navigation parent current :=
 let options := map (fun section => Fields.ChoiceValue (settings_section_name section) (section_label section)) settings_sections in
 named_region parent "settings-mobile-nav" ""
   [Node (part parent "settings-section-picker") "settings-section-picker" "设置分类" Roles.Field
     (ConfigurationField false (settings_section_name current) (Some options) true
       (fun value => option_map (fun section => Input.ServiceInput (Services.SelectSettingsSection section))
         (bind (as_string value) decode_settings_section))) []].
(* Changing the category changes the scroll document. Editing a setting
   within it preserves the document and its scroll position. *)
Definition content root parent section services speech (measuring : bool) :=
 let view := service_configuration services in
 let id := part parent ("settings-content/" ++ settings_section_name section) in
 let design := section_design section in
 let header := (page_heading id services section ::
   if measuring then [] else catalog_status id services ++ draft_notice id section view)%list in
 (* The primary collection shares the page heading and its controls. *)
 let primary := match primary_group design with
   | Some group => [named_region id "settings-primary" ""
       (header ++ overview root id section services speech measuring [group])%list]
   | None => header
   end in
 Node id (if measuring then "settings-measure" else "settings-content") "" Roles.Section Region
   (primary ++ overview root id section services speech measuring (section_groups design))%list.

(* All categories contribute to the same desktop reading track. Keep only
   the selected document operable. Saved record details have no influence on
   the track, so the other documents need only their headings and controls. *)
Definition documents root parent section services speech :=
 named_region parent "settings-documents" ""
   (map (fun candidate => content root parent candidate services speech (negb (same_section candidate section)))
      settings_sections).

Definition view s :=
 let services := State.service_state s in
 match Services.settings_return services with
 | None => []
 | Some trigger =>
   let root := settings_root in
   let body := part root "body" in
   let section := Services.settings_section services in
   [Node root "settings" Navigation.settings_label Roles.Dialog
      (LayerRegion (LayerBehavior ModalDialog false (State.generation (State.navigation_state s))
        (part root "close") (Services.settings_focus_target trigger) "/main" trigger
        (Input.ServiceInput Services.CloseSettings) true true))
      [dialog_header root
         [named_region root "settings-identity" ""
           [declared root Roles.Button (secondary "close" "关闭设置" (Input.ServiceInput Services.CloseSettings));
            title root Navigation.settings_label];
          compact_navigation root section];
       dialog_body root (navigation body section ++ [documents root body section services (State.speech_state s)])]]
 end.

Definition configuration_action parent key caption label emphasis (enabled : bool) input : node Input.input :=
 let id := part parent key in
 Node id key label Roles.Button
   (Activate (Control key label emphasis (Input.ServiceInput input)
     (if enabled then Available else Unavailable "当前不可用")))
   [information id "label" Information.OptionLabel caption].

(* The fields describe the object and can scroll. Operations on the whole
   object share the fixed footer with the decision, outside the field order.
   A write's result belongs with the decision that initiated it. *)
Definition configuration_dialog generation id caption trigger fallback view
  (fields object_actions : list (node Input.input)) primary : node Input.input :=
 let dirty := Configuration.has_unsaved_work view in
 let ready := negb (Configuration.pending view) in
 let footer := part id "actions" in
 let controls := part footer "settings-editor-actions" in
 Node id "settings-configuration-editor" caption Roles.Dialog
   (LayerRegion (LayerBehavior ModalDialog false generation (part id "heading")
     trigger fallback trigger (Input.ServiceInput Services.CancelConfigurationEdit)
     false (ready && negb dirty)))
   [dialog_header id [title id caption];
    dialog_body id fields;
    dialog_actions id (write_status footer view ++
      [named_region footer "settings-editor-actions" "" (object_actions ++
        [named_region controls "settings-editor-decisions" ""
          [configuration_action id "cancel" (if dirty then "放弃" else "取消")
             (if dirty then "放弃更改" else "取消") Secondary ready Services.CancelConfigurationEdit;
           primary]])])].

Definition configuration_save id entry raw view enabled :=
 action id "save" "保存" Primary (save_enabled entry raw view enabled) Services.SetConfiguration.

Definition collection_editor generation id entry draft view enabled item : list (node Input.input) :=
 let path := Config.setting_path entry in
 let raw := Configuration.draft_input draft in
 let add := editor_trigger path "begin-add" in
 let dialog caption trigger := configuration_dialog generation id caption trigger add view in
 match Configuration.new_item view with
 | Some (name, value) =>
   [dialog ("新建" ++ item) add
     [ConfigurationForms.new_item_field id name enabled;
      ConfigurationForms.item_fields path id value view enabled] []
     (configuration_action id "add" "添加" ("添加" ++ item) Primary (enabled && Configuration.can_add_item view)
       Services.SetConfiguration)]
 | None => match Configuration.preferred_item (Configuration.form_editor_current view) with
   | None => []
   | Some name =>
     let saved := child_items path (Config.setting_value entry) in
     let trigger := match lookup name saved with
       | Some _ => editor_trigger path (edit_item_key name) | None => add end in
     match lookup name (Configuration.collection_entries view) with
     | Some source => [dialog ("编辑「" ++ name ++ "」") trigger
         [ConfigurationForms.item_fields path id source view enabled]
         [ConfigurationForms.button id "remove-item" ("移除" ++ item) enabled (Services.RemoveConfigurationItem name)]
         (configuration_save id entry raw view enabled)]
     | None => [dialog ("移除「" ++ name ++ "」？") trigger
         [note id "description" ("此" ++ item ++ "将从设置中移除。")] []
         (configuration_action id "confirm-remove" "移除" ("移除" ++ item) Destructive
           (save_enabled entry raw view enabled) Services.SetConfiguration)]
     end
   end
 end.

Definition configuration_editor s : list (node Input.input) :=
 let services := State.service_state s in
 let view := service_configuration services in
 match Services.settings_return services, Configuration.editing view with
 | Some _, Some (_, draft, entry) =>
   let path := Config.setting_path entry in
   if same_section (section_for path) (Services.settings_section services) && Configuration.focused_editor entry then
     let generation := State.generation (State.navigation_state s) in
     let id := part (part settings_root "configuration-editor") (Config.setting_key path) in
     let raw := Configuration.draft_input draft in
     let enabled := can_edit path services in
     match ConfigurationForms.collection_item path with
     | Some item => collection_editor generation id entry draft view enabled item
     | None =>
       let trigger := editor_trigger path "open" in
       let '(label, description) := copy path in
       let fields := match path with
         | ["instructions"] =>
           [note id "description" description;
            named_region id "settings-instructions-field" ""
              [configuration_field id "instructions-text" label true raw None enabled path]]
         | _ => ConfigurationForms.structured_form path id (Config.setting_value entry)
                   (value_or JNull (TextJson.parse_json raw)) view enabled
         end in
       let restore := if Configuration.dirty view then []
                      else reset_button id entry enabled "恢复默认" in
       [configuration_dialog generation id label trigger (part settings_root "close") view
         fields restore
         (configuration_save id entry raw view enabled)]
     end
   else []
 | _, _ => []
 end.
