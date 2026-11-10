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

Definition settings_root := "/settings".

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
 | ["chatgpt"] => ("ChatGPT model access", "Choose whether tasks can use models from your ChatGPT account.")
 | ["reasoning_evaluators"] => ("Reasoning evaluators", "Services that assess adaptive reasoning.")
 | ["mcp"] => ("MCP servers", "Connect tools and resources through Model Context Protocol.")
 | ["plugins"] => ("Plugins", "Programs the service can use to extend task capabilities.")
 | ["skills"] => ("Skill sources", "Files and directories where the service looks for skills.")
 | ["chatgpt_plugin"] => ("ChatGPT app connections", "Grant a ChatGPT app access to selected projects.")
 | ["max_fork"] => ("Forks per task", "Maximum number of direct forks a task can create.")
 | ["max_descendants"] => ("Task descendants", "Maximum number of tasks descended from a single root.")
 | ["cloud"] => ("Cloud workspaces", "Provision workspaces for tasks using Tencent Cloud.")
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
 | ["chatgpt"] => "Configure access" | ["remote"] => "Configure relay"
 | ["instructions"] => "Edit instructions"
 | ["cloud"] => "Configure cloud" | ["compaction"; "targets"] => "Edit limits"
 | ["skills"] => "Edit sources" | _ => "Edit " ++ fst (copy path)
 end.
Definition save_label path :=
 match path with
 | ["profiles"] => "Save profiles" | ["reasoning_evaluators"] => "Save evaluators"
 | ["chatgpt"] => "Save access settings" | ["chatgpt_plugin"] => "Save connections"
 | ["mcp"] => "Save servers" | ["plugins"] => "Save plugins" | ["skills"] => "Save sources"
 | ["remote"] => "Save relay" | ["cloud"] => "Save cloud settings"
 | ["compaction"; "targets"] => "Save limits"
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
Definition summary_lines parent path value : list (node Input.input) :=
 match path with
 | ["remote"] => match Common.get value "relay_url" with
      | JString url => [note parent "current-value" url] | _ => [] end
 | ["cloud"] => match Common.get value "tencent_cvm" with
      | JObject _ => [note parent "current-value"
        (detail_join "Tencent Cloud" (Common.text (Common.get (Common.get value "tencent_cvm") "region")))]
      | _ => [] end
 | ["compaction"; "targets"] =>
    map (fun '(index, item) =>
      let id := part parent ("target-summary-" ++ ConfigurationForms.index_label index) in
      Node id "settings-summary-item" "" Roles.Section Region
        (copy_nodes id (Common.text (Common.get item "profile"))
          (match Common.get item "window_tokens" with JNumber amount => amount ++ " tokens" | _ => "" end)))
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
     (if enabled then Available else Unavailable "Finish the current edit first")))
   [information id "label" Information.OptionLabel caption].

Definition form_setting parent services entry :=
 let path := Config.setting_path entry in
 let key := Config.setting_key path in
 let id := part parent key in
 let saved := Config.setting_value entry in
 let '(label, description) := copy path in
 let description := match path, saved with
   | ["chatgpt"], JBool false => "ChatGPT account access is turned off."
   | _, _ => description end in
 let lines := summary_lines (part id "settings-values") path saved in
 row parent key label description
   [editor_button path "open" (open_label path) (open_label path)
      (can_edit path services) (Services.SelectConfiguration path)]
   (match lines with [] => [] | _ => [named_region id "settings-values" "" lines] end).

(* The overview enumerates saved objects. Draft edits and removals become
   visible here after a successful write. *)
Definition collection_setting parent services entry item :=
 let path := Config.setting_path entry in
 let key := Config.setting_key path in
 let id := part parent key in
 let list_id := part id "settings-entries" in
 let view := service_configuration services in
 let enabled := can_edit path services in
 let entries := child_items path (Config.setting_value entry) in
 let '(label, description) := copy path in
 let entry_row '(name, value) :=
   row list_id (part "entry" name) name (item_detail path value)
     [editor_button path (edit_item_key name) "Edit" ("Edit " ++ name) enabled
       (Services.SelectConfigurationItem path name)] [] in
 let entries_body := match entries with
   | [] => [] | _ => [named_region id "settings-entries" label (map entry_row entries)] end in
 let footer := part id "settings-collection-actions" in
 let actions := if is_resettable entry then
   [button footer "restore-default" "Restore list defaults" enabled (Services.ResetConfigurationAt path)]
   else [] in
 let feedback := match active_raw path view, Configuration.writing view with
   | Some _, Loading _ _ | Some _, Failed _ _ _ => write_status footer view
   | _, _ => []
   end in
 (* A collection has a heading, saved objects and actions on the whole
    collection. Editing one object belongs to that object's row. *)
 Node id "settings-collection" "" Roles.Section Region
   ([named_region id "settings-collection-heading" ""
      [group_title (part id "settings-collection-heading") label;
       note (part id "settings-collection-heading") "description" description]]
    ++ entries_body
    ++ [named_region id "settings-collection-actions" ""
      (button (setting_entry_parent path) "begin-add" ("Add " ++ item) enabled
        (Services.BeginAddConfigurationItem path) :: (actions ++ feedback)%list)])%list.

Definition normal_entry parent services entry :=
 match ConfigurationForms.collection_item (Config.setting_path entry) with
 | Some item => collection_setting parent services entry item
 | None => if Configuration.focused_editor entry then form_setting parent services entry
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

Definition configuration_groups section : list (string * string * list (list string)) :=
 match section with
 | SettingsGeneral => []
 | SettingsModels =>
   [("model-configurations", "", [["profiles"]]);
    ("model-services", "", [["chatgpt"]; ["reasoning_evaluators"]])]
 | SettingsTools =>
   [("tool-connections", "", [["mcp"]; ["chatgpt_plugin"]]);
    ("tool-sources", "", [["plugins"]; ["skills"]])]
 | SettingsTasks =>
   [("limits", "Task limits", [["max_fork"]; ["max_descendants"]]);
    ("workspaces", "", [["cloud"]])]
 | SettingsContext =>
   [("compaction", "Context compaction",
      [["compaction"; "enabled"]; ["compaction"; "background_percent"];
       ["compaction"; "blocking_percent"]; ["compaction"; "idle_lead_ms"]]);
    ("model-limits", "", [["compaction"; "targets"]])]
 | SettingsConnection =>
   [("binding", "Listen on this device", [["host"]; ["port"]]);
    ("remote", "", [["remote"]])]
 end.
Definition section_entries services section : list (string * string * list Config.setting) :=
 let fixed := map (fun '(key, label, paths) => (key, label, entries_for_paths services paths))
   (configuration_groups section) in
 (fixed ++ match section with
 | SettingsContext =>
   let sources := filter (fun entry =>
     let path := Config.setting_path entry in
     match path with "compaction" :: _ => false | _ =>
       same_section (section_for path) SettingsContext end) (catalog_entries services) in
   [("sources", "Context sources", sources)]
 | _ => [] end)%list.

Definition appearance parent current :=
 let id := part (part (part parent "theme") "settings-controls") "theme-options" in
 let themes := [("Light", Appearance.LightAppearance); ("System", Appearance.SystemAppearance); ("Dark", Appearance.DarkAppearance)] in
 row parent "theme" "Appearance" ""
   [Node id "theme-options" "Color theme" Roles.Section ChoiceGroup
     (map (fun '(label, theme) =>
        let key := Appearance.appearance_name theme in
        Node (part id key) "theme-option" label Roles.Button
          (Choice SingleChoice (String.eqb key (Appearance.appearance_name current)) ""
             (secondary key label (Input.ServiceInput (Services.ChooseAppearance theme)))) []) themes)] [].

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
 let local := match section with
 | SettingsGeneral =>
   (group "appearance" "" (fun p => [appearance p (Services.theme services)])
   ++ group "conversation" "Conversation defaults" (fun p =>
      (map (form_setting p services) (entries_for_paths services [["instructions"]])
      ++ [row p "title-prompts" "Conversation titles" "Set the model and prompts used to name conversations and tasks."
          [declared root Roles.Button (secondary "title-prompts" "Edit title prompts"
             (Input.OpenEditor TitlePrompts (part root "title-prompts")))] []])%list))%list
 | SettingsConnection =>
   group "connection" "" (fun p => [local_connection p services])
 | _ => []
 end in
 (local ++ flat_map (fun '(key, label, entries) =>
   group key label (fun p => map (normal_entry p services) entries)) (section_entries services section))%list.

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
   if (Configuration.has_unsaved_work view || Configuration.pending view) && negb (same_section section owner) then
     let id := part parent "draft-notice" in
     [named_region parent "draft-notice" ""
       [note id "description" ("Editing " ++ fst (copy path) ++ " in " ++ section_label owner ++ ".");
        button id "return-to-edit" "Return to edit" true (Services.SelectSettingsSection owner)]]
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
 [Node id "settings-nav" "Settings categories" Roles.Section ChoiceGroup (map section_choice sections)].

(* The same category choice moves from the rail to the settings heading
   when the rail would take up the document's reading space. *)
Definition compact_navigation parent current :=
 let options := map (fun section => Fields.ChoiceValue (settings_section_name section) (section_label section)) sections in
 named_region parent "settings-mobile-nav" ""
   [Node (part parent "settings-section-picker") "settings-section-picker" "Settings section" Roles.Field
     (ConfigurationField false (settings_section_name current) (Some options) true
       (fun value => option_map (fun section => Input.ServiceInput (Services.SelectSettingsSection section))
         (bind (as_string value) decode_settings_section))) []].
(* Changing the category changes the scroll document. Editing a setting
   within it preserves the document and its scroll position. *)
Definition content root parent section services :=
 let view := service_configuration services in
 let id := part parent ("settings-content/" ++ settings_section_name section) in
 Node id "settings-content" "" Roles.Section Region
   ([title_block id (section_label section) ""] ++ catalog_status id services ++
    draft_notice id section view ++ overview root id section services)%list.

Definition view s :=
 let services := State.service_state s in
 match Services.settings_return services with
 | None => []
 | Some trigger =>
   let root := settings_root in
   let body := part root "body" in
   let section := Services.settings_section services in
   [Node root "settings" "Settings" Roles.Dialog
      (LayerRegion (LayerBehavior ModalDialog false (State.generation (State.navigation_state s))
        (part root "close") (Services.settings_focus_target trigger) "/main" trigger
        (Input.ServiceInput Services.CloseSettings) true true))
      [dialog_header root
         [named_region root "settings-identity" ""
           [declared root Roles.Button (secondary "close" "Close settings" (Input.ServiceInput Services.CloseSettings));
            title root "Settings"];
          compact_navigation root section];
       dialog_body root (navigation body section ++ [content root body section services])]]
 end.

(* A form has one reading order: object, fields, outcome, then decision.
   Only the field region scrolls. The saved overview stays in its own layer. *)
Definition configuration_dialog generation id caption trigger fallback view
  (fields : list (node Input.input)) primary : node Input.input :=
 let dirty := Configuration.has_unsaved_work view in
 let ready := negb (Configuration.pending view) in
 Node id "settings-configuration-editor" caption Roles.Dialog
   (LayerRegion (LayerBehavior ModalDialog false generation (part id "heading")
     trigger fallback trigger (Input.ServiceInput Services.CancelConfigurationEdit)
     false (ready && negb dirty)))
   [dialog_header id [title id caption];
    dialog_body id (fields ++ write_status id view)%list;
    dialog_actions id [
      button id "cancel" (if dirty then "Discard changes" else "Cancel") ready Services.CancelConfigurationEdit;
      primary]].

Definition configuration_save id entry raw view enabled :=
 action id "save" "Save" Primary (save_enabled entry raw view enabled) Services.SetConfiguration.

Definition collection_editor generation id entry draft view enabled item : list (node Input.input) :=
 let path := Config.setting_path entry in
 let raw := Configuration.draft_input draft in
 let add := editor_trigger path "begin-add" in
 let dialog caption trigger := configuration_dialog generation id caption trigger add view in
 match Configuration.new_item view with
 | Some (name, value) =>
   [dialog ("New " ++ item) add
     [ConfigurationForms.new_item_field id name enabled;
      ConfigurationForms.item_fields path id value enabled]
     (action id "add" ("Add " ++ item) Primary (enabled && Configuration.can_add_item view)
       Services.SetConfiguration)]
 | None => match Configuration.preferred_item (Configuration.form_editor_current view) with
   | None => []
   | Some name =>
     let saved := child_items path (Config.setting_value entry) in
     let trigger := match lookup name saved with
       | Some _ => editor_trigger path (edit_item_key name) | None => add end in
     match lookup name (Configuration.collection_entries view) with
     | Some source => [dialog ("Edit " ++ name) trigger
         (ConfigurationForms.item_form path id item name source enabled)
         (configuration_save id entry raw view enabled)]
     | None => [dialog ("Remove " ++ name ++ "?") trigger
         [note id "description" ("This " ++ item ++ " will be removed from settings.")]
         (action id "confirm-remove" ("Remove " ++ item) Destructive
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
                      else reset_button id entry enabled "Restore default" in
       [configuration_dialog generation id label trigger (part settings_root "close") view
         (fields ++ restore)%list
         (configuration_save id entry raw view enabled)]
     end
   else []
 | _, _ => []
 end.
