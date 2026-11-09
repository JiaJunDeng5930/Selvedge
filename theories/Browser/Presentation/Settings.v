From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers TextJson.
From Selvedge.Adapters Require Common ProviderCatalog.
From Selvedge.Browser Require Import NavigationIdentity.
From Selvedge.Interaction Require Import Codec Identity.
From Selvedge.Interaction.Submission Require Fields.
From Selvedge.Browser.Session Require Import Appearance Input Services State.
From Selvedge.Browser.Session Require Configuration.
From Selvedge.Programming Require Import Resource.
From Selvedge.Browser.Scene Require Import Surface Model Construction.
From Selvedge.Browser.Presentation Require Import Projection.
From Selvedge.Browser.Presentation Require Roles Information ModelProfiles ConfigurationForms.
Import ListNotations.
Open Scope string_scope.

Module Config := Configuration.Config.

Definition sections :=
 [SettingsGeneral; SettingsModels; SettingsTools; SettingsTasks; SettingsContext; SettingsConnection].
Definition section_label section :=
 match section with
 | SettingsGeneral => "General" | SettingsModels => "Models" | SettingsTools => "Tools"
 | SettingsTasks => "Tasks" | SettingsContext => "Context" | SettingsConnection => "Connection"
 end.
Definition same_section left right :=
 String.eqb (settings_section_name left) (settings_section_name right).
Definition section_for path :=
 match path with
 | ["instructions"] => SettingsGeneral
 | ("profiles" | "chatgpt" | "reasoning_evaluators") :: _ => SettingsModels
 | ("mcp" | "plugins" | "skills" | "chatgpt_plugin") :: _ => SettingsTools
 | ("max_fork" | "max_descendants" | "cloud") :: _ => SettingsTasks
 | ("host" | "port" | "remote") :: _ => SettingsConnection
 | _ => SettingsContext
 end.

Definition copy path : string * string :=
 match path with
 | ["instructions"] => ("Instructions", "Standing guidance supplied to tasks by the local service.")
 | ["profiles"] => ("Model profiles", "Named configurations that tasks can use.")
 | ["chatgpt"] => ("Sign in with ChatGPT", "Use your ChatGPT account for model access.")
 | ["reasoning_evaluators"] => ("Reasoning evaluators", "Services that assess adaptive reasoning.")
 | ["mcp"] => ("MCP servers", "Connect tools and resources through Model Context Protocol.")
 | ["plugins"] => ("Plugins", "Programs the service can use to extend task capabilities.")
 | ["skills"] => ("Skill sources", "Files and directories where the service looks for skills.")
 | ["chatgpt_plugin"] => ("ChatGPT app connections", "Grant a ChatGPT app access to selected projects.")
 | ["max_fork"] => ("Forks per task", "Maximum number of direct forks a task can create.")
 | ["max_descendants"] => ("Task descendants", "Maximum number of tasks descended from a single root.")
 | ["cloud"] => ("Cloud workspaces", "Provision workspaces for tasks using Tencent Cloud.")
 | ["compaction"] => ("Compaction policy", "Edit the entire context compaction policy as JSON.")
 | ["compaction"; "enabled"] => ("Automatic compaction", "Summarize older context as a task approaches its model’s context limit.")
 | ["compaction"; "background_percent"] => ("Background threshold (%)", "Start summarizing while the task can still run.")
 | ["compaction"; "blocking_percent"] => ("Blocking threshold (%)", "Wait for compaction before sending the next request.")
 | ["compaction"; "idle_lead_ms"] => ("Idle lead time (ms)", "Start compaction this long before the cache expires.")
 | ["compaction"; "targets"] => ("Model-specific limits", "Set context windows and compaction methods by profile.")
 | ["host"] => ("Listen address", "Loopback address used when the service starts.")
 | ["port"] => ("Listen port", "Port used when the service starts. Use 0 to choose an available port.")
 | ["remote"] => ("Remote control relay", "Configure the relay used to pair remote controllers.")
 | _ => (String.concat " / " path, "")
 end.
Definition open_label path :=
 match path with
 | ["profiles"] => "Manage profiles" | ["reasoning_evaluators"] => "Manage evaluators"
 | ["mcp"] => "Manage servers" | ["plugins"] => "Manage plugins"
 | ["skills"] => "Manage sources" | ["chatgpt_plugin"] => "Manage connections"
 | ["chatgpt"] => "Configure access" | ["remote"] => "Configure relay"
 | ["cloud"] => "Configure cloud workspaces" | ["compaction"; "targets"] => "Manage limits"
 | ["compaction"] => "Edit policy JSON" | _ => "Edit " ++ fst (copy path)
 end.
Definition save_label path :=
 match path with
 | ["profiles"] => "Save profiles" | ["reasoning_evaluators"] => "Save evaluators"
 | ["chatgpt"] => "Save access settings" | ["chatgpt_plugin"] => "Save connections"
 | ["mcp"] => "Save servers" | ["plugins"] => "Save plugins" | ["skills"] => "Save sources"
 | ["remote"] => "Save relay" | ["cloud"] => "Save cloud settings"
 | ["compaction"; "targets"] => "Save limits" | ["compaction"] => "Save policy"
 | ["instructions"] => "Save instructions" | ["host"] => "Save address" | ["port"] => "Save port"
 | _ => "Save"
 end.

Definition action parent key label emphasis (enabled : bool) input : node Input.input :=
 declared parent Roles.Button (Control key label emphasis (Input.ServiceInput input)
   (if enabled then Available else Unavailable "Unavailable in the current state")).
Definition button parent key label := action parent key label Secondary.
Definition note parent key text : node Input.input := information parent key Information.Description text.
Definition named_region parent key label (children : list (node Input.input)) := region parent key label Roles.Section children.
Definition title_block parent label description :=
 let heading := part parent "settings-title" in
 named_region parent "settings-title" ""
   (title heading label :: if String.eqb description "" then [] else [note heading "description" description]).
Definition section_group parent key label rows : list (node Input.input) :=
 match rows with
 | [] => []
 | _ => [Node (part parent key) "settings-group" "" Roles.Section Region
       (group_title (part parent key) label :: rows)]
 end.
Definition copy_nodes parent label description : list (node Input.input) :=
 information parent "setting-name" Information.FieldLabel label ::
   (if String.eqb description "" then [] else [note parent "description" description]).
Definition row parent key label description controls below : node Input.input :=
 let id := part parent key in
 Node id "settings-row" "" Roles.Section Region
   ([named_region id "settings-copy" "" (copy_nodes (part id "settings-copy") label description);
     named_region id "settings-controls" "" controls] ++ below)%list.

Definition configuration_field parent key label multiline raw options enabled path :=
 ModelProfiles.field parent key label multiline raw options enabled (Services.EditConfigurationAt path).
Definition active_raw path view :=
 draft <- Configuration.current_draft view ;;
 if Configuration.matches_path path draft then Some (Configuration.draft_input draft) else None.
Definition is_active path view :=
 match active_raw path view with Some _ => true | None => false end.
Definition value_label value :=
 match value with JBool true => "On" | JBool false => "Off" | _ => Config.display_value value end.
Definition options_for raw options :=
 let choices := map (fun value => Fields.ChoiceValue (render_json value) (value_label value)) options in
 if existsb (fun value => String.eqb (render_json value) raw) options then choices
 else Fields.ChoiceValue raw "Choose a value" :: choices.
Definition can_edit path services :=
 Services.connected services && Configuration.can_select path (service_configuration services).

Definition write_status parent view : list (node Input.input) :=
 match Configuration.writing view with
 | Loading _ _ => [information parent "saving" Information.Status "Saving…"]
 | Failed _ _ reason => [information parent "save-error" Information.Status reason]
 | Loaded _ _ _ => [information parent "saved" Information.Status "Configuration updated"]
 | Dormant => []
 end.
Definition is_resettable entry := Config.setting_resettable entry && Config.setting_explicit entry.
Definition reset_button parent entry enabled label :=
 if is_resettable entry then [button parent "restore-default" label enabled Services.ResetConfiguration] else [].
Definition save_enabled entry raw view enabled :=
 enabled && Configuration.dirty view &&
 match Config.interpret_input (Config.setting_input entry) raw with Some _ => true | None => false end.
Definition saved_actions parent entry raw view enabled (advanced include_cancel : bool) : list (node Input.input) :=
 let path := Config.setting_path entry in
 let id := part parent "save-bar" in
 let dirty := Configuration.dirty view in
 let controls :=
   ((if advanced then reset_button id entry enabled "Restore default"
    else []) ++
   (if include_cancel && dirty then
      [button id "cancel" "Discard changes" (negb (Configuration.pending view)) Services.CancelConfigurationEdit]
    else []) ++
   [action id "save" (save_label path) Primary (save_enabled entry raw view enabled) Services.SetConfiguration])%list in
 [region parent "save-bar" "" Roles.DialogActions (write_status id view ++ controls)%list].

Definition boolean_control parent path label raw (enabled : bool) :=
 let key := "setting-switch" in
 let on := String.eqb raw "true" in
 Node (part parent key) key label Roles.Button
   (Choice ToggleChoice on ""
     (Control key label Secondary (Input.ServiceInput
       (Services.SetConfigurationAt path (if on then "false" else "true")))
       (if enabled then Available else Unavailable "Finish saving the current setting"))) [].
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
 | Config.Choice options => configuration_field controls "setting-value" label false raw
       (Some (options_for raw options)) enabled path
 | _ => configuration_field controls "setting-value" label false raw None enabled path
 end in
 let defaults := if is_resettable entry && negb (Configuration.dirty view) then
   [button controls "restore-default" "Default" enabled (Services.ResetConfigurationAt path)] else [] in
 let bar := part id "setting-feedback" in
 let updates := match draft with
 | Some _ =>
   (write_status bar view ++
    if Configuration.dirty view then
      [button bar "cancel" "Undo edit" enabled Services.CancelConfigurationEdit;
       action bar "save" (match Config.setting_input entry with Config.Boolean => "Retry change" | _ => save_label path end)
         Primary (save_enabled entry raw view enabled) Services.SetConfiguration]
    else [])%list
 | None => []
 end in
 row parent key label description (widget :: defaults)
   (match updates with [] => [] | _ => [region id "setting-feedback" "" Roles.DialogActions updates] end).

Definition instructions parent services entry :=
 let path := Config.setting_path entry in
 let id := part parent "instructions" in
 let view := service_configuration services in
 let enabled := can_edit path services in
 let draft := active_raw path view in
 let raw := value_or (Config.initial_input entry) draft in
 let defaults := if is_resettable entry && negb (Configuration.dirty view) then
   [button id "restore-default" "Restore default instructions" enabled (Services.ResetConfigurationAt path)] else [] in
 named_region parent "settings-instructions" ""
   (copy_nodes id "Instructions" (snd (copy path)) ++
    [configuration_field id "instructions-text" "Instructions" true raw None enabled path] ++
    match draft with
    | None => defaults
    | Some _ => if Configuration.dirty view || Configuration.pending view then
        saved_actions id entry raw view enabled false true
      else write_status id view ++ defaults
    end)%list.

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
   if String.eqb provider "Offline echo" && String.eqb model "echo" then provider
   else detail_join provider model
 | ["reasoning_evaluators"] => detail_join
     (value_or "vercel" (as_string (Common.get value "provider"))) (Common.text (Common.get value "model"))
 | ["mcp"] | ["plugins"] => Common.text (Common.get value "command")
 | ["chatgpt_plugin"] =>
   let count := List.length (Common.items (Common.get value "project_ids")) in
   show_natural (N.of_nat count) ++ (if Nat.eqb count 1 then " project" else " projects")
 | _ => ""
 end.
Definition collection_lines parent path values :=
 map (fun '(name, value) =>
   Node (part parent name) "settings-object" "" Roles.Section Region
     (copy_nodes (part parent name) name (item_detail path value))) values.
Definition current_lines parent path value : list (node Input.input) :=
 match Configuration.collection_root path with
 | Some _ => match child_items path value with
      | [] => [note parent "empty" "None configured"]
      | items => collection_lines parent path items end
 | None =>
   match path with
   | ["chatgpt"] => [note parent "current-value" (match value with
        | JBool false => "Account model access is off"
        | JNull | JObject [] => "Default connection"
        | _ => "Custom connection" end)]
   | ["remote"] => [note parent "current-value" (match Common.get value "relay_url" with
        | JString url => url | _ => "No relay configured" end)]
   | ["cloud"] => [note parent "current-value" (match value with JObject _ =>
        detail_join "Tencent Cloud" (Common.text (Common.get (Common.get value "tencent_cvm") "region"))
        | _ => "No cloud backend configured" end)]
   | ["compaction"; "targets"] =>
      let targets := Common.items value in
      match targets with [] => [note parent "empty" "No profile limits configured"] | _ =>
      map (fun '(index, item) =>
        let key := "target-" ++ ConfigurationForms.index_label index in
        let label := Common.text (Common.get item "profile") in
        let window := Common.get item "window_tokens" in
        Node (part parent key) "settings-object" "" Roles.Section Region
          (copy_nodes (part parent key) label (match window with
            | JNumber amount => amount ++ " tokens" | _ => "" end)))
        (ConfigurationForms.indexed targets)
      end
   | ["compaction"] => []
   | _ => match value with JArray [] => [note parent "empty" "None configured"]
          | JArray items => map (fun '(index, item) => note parent
              ("item-" ++ ConfigurationForms.index_label index) (Config.display_value item)) (ConfigurationForms.indexed items)
          | _ => [] end
   end
 end.
Definition workspace_entry parent services entry :=
 let path := Config.setting_path entry in
 let key := Config.setting_key path in
 let id := part parent key in
 let controls := part id "settings-controls" in
 let lines := current_lines (part id "settings-values") path (Config.setting_value entry) in
 row parent key (fst (copy path)) (snd (copy path))
   [button controls "manage" (open_label path) (can_edit path services) (Services.SelectConfiguration path)]
   (match lines with [] => [] | _ => [named_region id "settings-values" "" lines] end).

Definition needs_workspace entry :=
 match Config.setting_input entry with Config.Structured => true | _ => false end.
Definition normal_entry parent services entry :=
 if needs_workspace entry then workspace_entry parent services entry else compact_setting parent services entry.

Definition catalog_entries services :=
 match Configuration.available (service_configuration services) with
 | Some snapshot => Config.entries snapshot | None => [] end.
Definition for_paths services parent paths :=
 flat_map (fun path => map (normal_entry parent services)
   (filter (fun entry => if list_eq_dec String.string_dec (Config.setting_path entry) path then true else false)
      (catalog_entries services))) paths.

Definition appearance parent current :=
 let id := part parent "theme-options" in
 let themes := [("Light", Appearance.LightAppearance); ("System", Appearance.SystemAppearance); ("Dark", Appearance.DarkAppearance)] in
 Node id "theme-options" "Color theme" Roles.Section ChoiceGroup
  (map (fun '(label, theme) =>
     let key := Appearance.appearance_name theme in
     let option := part id key in
     let semantic := match theme with Appearance.LightAppearance => "theme-light"
       | Appearance.DarkAppearance => "theme-dark" | Appearance.SystemAppearance => "theme-system" end in
     Node option semantic label Roles.Button
       (Choice SingleChoice (String.eqb key (Appearance.appearance_name current)) ""
          (secondary key label (Input.ServiceInput (Services.ChooseAppearance theme))))
       [named_region option "theme-swatch" "" []; information option "theme-label" Information.OptionLabel label]) themes).

Definition local_connection parent services :=
 let id := part (part parent "local") "settings-controls" in
 match Services.connection services with
 | ConnectionReady _ => row parent "local" "Local service" "This browser is connected to Selvedge."
      [information id "service-connected" Information.OptionLabel "Connected"] []
 | ConnectionLoading _ => row parent "local" "Local service" "Connecting to Selvedge…"
      [information id "service-connecting" Information.Status "Connecting"] []
 | ConnectionDormant => row parent "local" "Local service" "Connect this browser to Selvedge."
      [button id "connect" "Connect" true Services.Connect] []
 | ConnectionFailed _ reason | ConnectionRevoked _ reason => row parent "local" "Local service" reason
      [button id "connect" "Reconnect" true Services.Connect] []
 end.
Definition overview root parent section services :=
 let group key label body := section_group parent key label (body (part parent key)) in
 let paths key label values := group key label (fun p => for_paths services p values) in
 match section with
 | SettingsGeneral =>
   group "appearance" "Appearance" (fun p => [appearance p (Services.theme services)])
   ++ group "conversation" "Conversation defaults" (fun p =>
      (map (instructions p services) (filter (fun entry => if list_eq_dec String.string_dec
        (Config.setting_path entry) ["instructions"] then true else false) (catalog_entries services))
      ++ [row p "title-prompts" "Conversation titles" "Set the model and prompts used to name conversations and tasks."
          [declared root Roles.Button (secondary "title-prompts" "Edit title prompts"
             (Input.OpenEditor TitlePrompts (part root "title-prompts")))] []])%list)
 | SettingsModels =>
   paths "model-configurations" "Available models" [["profiles"]; ["chatgpt"]]
   ++ paths "adaptive" "Adaptive reasoning" [["reasoning_evaluators"]]
 | SettingsTools =>
   paths "tool-connections" "Tools and integrations" [["mcp"]; ["plugins"]; ["chatgpt_plugin"]]
   ++ paths "sources" "Reusable instructions" [["skills"]]
 | SettingsTasks =>
   paths "limits" "Task limits" [["max_fork"]; ["max_descendants"]]
   ++ paths "workspaces" "Workspaces" [["cloud"]]
 | SettingsContext =>
   paths "compaction" "Context compaction"
      [["compaction"; "enabled"]; ["compaction"; "background_percent"];
       ["compaction"; "blocking_percent"]; ["compaction"; "idle_lead_ms"]]
   ++ paths "model-limits" "Per-model settings" [["compaction"; "targets"]]
   ++ group "sources" "Context sources" (fun p =>
       map (normal_entry p services) (filter (fun entry =>
          let path := Config.setting_path entry in
          match path with ["compaction"] => false | "compaction" :: _ => false | _ =>
             same_section (section_for path) SettingsContext end) (catalog_entries services)))
   ++ paths "advanced" "Advanced" [["compaction"]]
 | SettingsConnection =>
   group "connection" "Current connection" (fun p => [local_connection p services])
   ++ paths "binding" "Listen on this device" [["host"]; ["port"]]
   ++ paths "remote" "Access from another device" [["remote"]]
 end%list.

Definition catalog_status parent services :=
 let load label := button parent "load-configuration" label (Services.connected services) Services.LoadConfiguration in
 match Configuration.catalog (service_configuration services) with
 | Dormant => if Services.connected services then [load "Load service settings"]
       else [note parent "connection-needed" "Connect to the local service to edit its settings."]
 | Loading _ _ => [information parent "loading" Information.Status "Loading service settings…"]
 | Failed _ _ reason => [information parent "load-error" Information.Status reason; load "Reload settings"]
 | Loaded _ _ _ => []
 end.
Definition draft_notice parent section view :=
 match Configuration.current_draft view with
 | Some draft =>
   let path := Configuration.draft_path draft in
   let owner := section_for path in
   if (Configuration.dirty view || Configuration.pending view) && negb (same_section section owner) then
     let id := part parent "draft-notice" in
     [named_region parent "draft-notice" ""
       [note id "description" ("Editing " ++ fst (copy path) ++ " in " ++ section_label owner ++ ".");
        button id "return-to-edit" "Return to edit" true (Services.SelectSettingsSection owner)]]
   else []
 | None => []
 end.

Definition editor_section parent section services entry raw : list (node Input.input) :=
 let path := Config.setting_path entry in
 let '(label, description) := copy path in
 let view := service_configuration services in
 let enabled := can_edit path services in
 let source := value_or JNull (TextJson.parse_json raw) in
 let is_profiles := if list_eq_dec String.string_dec path Configuration.profiles_path then true else false in
 let form := if is_profiles then Some [ModelProfiles.editor parent view raw enabled]
             else ConfigurationForms.structured_form path parent (Config.setting_value entry) source view enabled in
 let raw_only := match form with None => true | Some _ => false end in
 let advanced := Configuration.json_mode view || raw_only in
 let can_return := match Configuration.collection_root path with
   | Some _ => Configuration.collection_form_available view
   | None => match TextJson.parse_json raw with Some _ => true | None => false end
   end in
 let mode_controls :=
   if is_profiles then
     [ModelProfiles.mode_control parent view enabled]
   else if raw_only then []
   else if advanced then
     [button parent "back-to-form" "Back to form" (enabled && can_return) (Services.ShowConfigurationJSON false)]
   else [button parent "advanced-json" "Edit JSON" enabled (Services.ShowConfigurationJSON true)] in
 let fields :=
   if is_profiles then value_or [] form else if advanced then
     [configuration_field parent "configuration-json" (label ++ " JSON") true raw None enabled path]
   else value_or [] form in
 ([button parent "back-to-section"
     (if Configuration.dirty view then "Discard and return to " ++ section_label section
      else "Back to " ++ section_label section)
     (negb (Configuration.pending view)) Services.CancelConfigurationEdit;
  title_block parent label description] ++ fields ++
 (match mode_controls with [] => [] | _ => [named_region parent "settings-advanced" "" mode_controls] end) ++
 saved_actions parent entry raw view enabled advanced false)%list.

Definition navigation parent current : list (node Input.input) :=
 let id := part parent "settings-nav" in
 let section_choice section :=
   let key := settings_section_name section in
   let label := section_label section in
   Node (part id key) "settings-category" label Roles.Button
     (Choice SingleChoice (same_section current section) ""
       (secondary key label (Input.ServiceInput (Services.SelectSettingsSection section)))) [] in
 let options := map (fun section => Fields.ChoiceValue (settings_section_name section) (section_label section)) sections in
 [Node id "settings-nav" "Settings categories" Roles.Section ChoiceGroup (map section_choice sections);
  named_region parent "settings-mobile-nav" ""
   [Node (part parent "settings-section-picker") "settings-section-picker" "Settings section" Roles.Field
     (ConfigurationField false (settings_section_name current) (Some options) true
       (fun value => option_map (fun section => Input.ServiceInput (Services.SelectSettingsSection section))
         (bind (as_string value) decode_settings_section))) []]].
Definition content root parent section services :=
 let view := service_configuration services in
 let editing := match Configuration.editing view with
    | Some (_, draft, entry) =>
      if needs_workspace entry && same_section section (section_for (Configuration.draft_path draft))
      then Some (entry, Configuration.draft_input draft) else None
    | None => None end in
 let key := "settings-content/" ++ settings_section_name section ++
   (match editing with Some (entry, _) => "/" ++ Config.setting_key (Config.setting_path entry) | None => "" end) in
 let id := part parent key in
 Node id "settings-content" "" Roles.Section Region
   (match editing with
    | Some (entry, raw) => editor_section id section services entry raw
    | None => [title_block id (section_label section) ""] ++ catalog_status id services ++
        draft_notice id section view ++ overview root id section services
    end)%list.

Definition view s :=
 let services := State.service_state s in
 match Services.settings_return services with
 | None => []
 | Some trigger =>
   let root := "/settings" in
   let body := part root "body" in
   let section := Services.settings_section services in
   [Node root "settings" "Settings" Roles.Dialog
      (LayerRegion (LayerBehavior ModalDialog false (State.generation (State.navigation_state s))
        (part root "close") (Services.settings_focus_target trigger) "/main" trigger
        (Input.ServiceInput Services.CloseSettings) true true))
      [dialog_header root
         [declared root Roles.Button (secondary "close" "Close settings" (Input.ServiceInput Services.CloseSettings));
          title root "Settings"];
       dialog_body root (navigation body section ++ [content root body section services])]]
 end.
