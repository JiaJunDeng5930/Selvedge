From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers TextJson.
From Selvedge.Features Require Domain.
From Selvedge.Browser Require Import NavigationIdentity.
From Selvedge.Interaction Require Import Codec Identity.
From Selvedge.Browser.Session Require Import Appearance Input.
From Selvedge.Programming Require Import Resource.
From Selvedge.Browser.Session Require Import Services Speech.
From Selvedge.Interaction Require Import Attachments.
From Selvedge.Interaction.Submission Require Draft Fields.
From Selvedge.Browser.Session Require Configuration.
From Selvedge.Browser.Session Require State Authoring.
From Selvedge.Browser.Scene Require Import Surface Model Construction.
From Selvedge.Browser.Presentation Require Import Projection.
From Selvedge.Browser.Presentation Require Roles Information.
Import ListNotations.
Open Scope string_scope.

Definition speech_button parent id label (enabled:bool) event :=
 declared parent Roles.Button(Control("speech/"++id)label Secondary(Input.SpeechInput event)
  (if enabled then Available else Unavailable "Audio is busy")).
Definition speech_status parent text:node Input.input:=information parent "speech/status" Information.Status text.
Definition can_begin_voice speech realtime:=Speech.free speech&&match Speech.eligible realtime speech with Some _=>true|None=>false end.
Definition speech_controls snapshot s e revision parent (speech:Speech.speech) :=
 let free:=Speech.free speech in
 let choices:=match Speech.connections speech with
 |[]=>[speech_button parent "sign-in" "Sign in for voice"free Speech.Authorize]
 |values=>map(fun connection=>let selected:=match Speech.selected speech with Some selected=>String.eqb selected(Speech.connection_id connection)|None=>false end in
   declared parent(if selected then Roles.SelectedButton else Roles.Button)
    (Control(String.append "speech/connection/"(Speech.connection_id connection))(Speech.connection_label connection)Secondary
      (Input.SpeechInput(Speech.Select(Speech.connection_id connection)))
      (if free&&(Speech.asr connection||Speech.voice connection)then Available else Unavailable "The audio connection is unavailable")))values end in
 let cancel label:=speech_button parent "cancel"label true Speech.Cancel in
 let activity:=match Speech.current speech with
 |Speech.Idle=>List.app[speech_button parent "dictate" "Dictate"(can_begin_voice speech false)(Speech.BeginDictation e revision)]
   (match e with
    |Message task=>[speech_button parent "start-voice" "Start voice"(can_begin_voice speech true)(Speech.BeginVoice task)]
    |NewTask _=>[declared parent Roles.Button(Control "speech/start-voice" "Start voice"Secondary(Input.BeginVoiceNew e)
      (if can_begin_voice speech true then domain_availability(Authoring.new_voice_availability snapshot s e)
       else Unavailable "Select a connection with live voice"))]|_=>[]end)
 |Speech.Acquiring _ _ _=>[speech_status parent "Requesting microphone access…";cancel "Cancel"]
 |Speech.Recording _ _=>[speech_status parent "Recording…";speech_button parent "finish" "Finish dictation"true Speech.FinishDictation;cancel "Cancel"]
 |Speech.Transcribing _ _=>[speech_status parent "Transcribing…";cancel "Cancel"]
 |Speech.Retained _ transcript=>[read_only parent "speech/transcript" "Draft changed; transcript retained"transcript;
   speech_button parent "insert" "Append to original draft"true Speech.InsertTranscript;
   speech_button parent "dismiss" "Discard transcript"true Speech.DismissTranscript]
 |Speech.CreatingTask _ _ _ _=>[speech_status parent "Creating voice task…";cancel "Cancel voice"]
 |Speech.ConnectingVoice _ _=>[speech_status parent "Connecting voice…";cancel "Cancel voice"]
 |Speech.Voice _ _ input_muted output_muted=>[speech_status parent "Voice connected";
   speech_button parent "microphone"(if input_muted then "Unmute microphone"else"Mute microphone")true Speech.ToggleInputMute;
   speech_button parent "speaker"(if output_muted then "Unmute speaker"else"Mute speaker")true Speech.ToggleOutputMute;
   speech_button parent "end" "End voice"true Speech.Cancel]end in
 region parent "speech-controls" "Speech input"Roles.Toolbar
  (List.app choices(List.app activity(List.app
   (if String.eqb(Speech.notice speech)""then[]else[read_only parent "speech-notice" "Voice"(Speech.notice speech)])
   (List.app(if String.eqb(Speech.live_text speech)""then[]else[read_only parent "speech-live" "Voice"(Speech.live_text speech)])
    [speech_button parent "refresh" "Refresh audio connections"free Speech.Refresh])))).
Definition attachment_node e parent (file:Domain.attachment) :=
 let id:=Domain.attachment_id file in
 let key:=part parent("attachment/"++id)in
 region parent("attachment/"++id)(Domain.attachment_name file)Roles.Card
 ((if String.prefix "image/" (Domain.attachment_mime file)then
    [Node(part key "image")"image-preview"(Domain.attachment_name file)Roles.Content
      (Image("/api/board/attachments/"++id)(Domain.attachment_name file))[]]
   else [])++
  [read_only key "name" "File"(Domain.attachment_name file);
  declared key Roles.Button(secondary "preview" "Preview"(Input.ServiceInput(Services.OpenPreview file(part key "preview"))));
  declared key Roles.Button(secondary "download" "Download"(Input.ServiceInput(Services.Download file)));
  declared key Roles.Button(secondary "remove" "Remove"(Input.RemoveAttachment e id))]).
Definition draft_files d :=match Draft.contents d with
|Draft.NewTaskBody message _ _ _ _ _|Draft.MessageBody _ message _=>Draft.text_images message
|Draft.CardBody _ _ card _ _ _=>Domain.draft_attachments card|_=>[]end.
Definition upload_node (connected:bool) parent (upload:resource Services.upload_request Domain.attachment) :=match upload with
|Resource.Loading ticket request=>Some(region parent("upload/"++show_natural ticket)"Uploading"Roles.Activity
 [read_only parent("upload/"++show_natural ticket++"/name")"Uploading"(file_name(Services.upload_file request));
  declared parent Roles.Button(secondary("cancel-upload/"++show_natural ticket)"Cancel upload"(Input.ServiceInput(Services.CancelUpload ticket)))])
|Resource.Failed ticket request reason=>Some(region parent("upload/"++show_natural ticket)"Upload failed"Roles.Alert
 [read_only parent("upload-error/"++show_natural ticket)"Upload failed"reason;
  declared parent Roles.Button(Control("retry-upload/"++show_natural ticket)"Retry upload" Secondary
    (Input.ServiceInput(Services.RetryUpload ticket))(if connected then Available else Unavailable "Reconnect to retry the upload"));
  declared parent Roles.Button(secondary("remove-upload/"++show_natural ticket)"Remove failed upload"(Input.ServiceInput(Services.CancelUpload ticket)))])
|_=>None end.
Definition file_picker e parent s :=
 Node(part parent "attach")"attach" "Attach files"Roles.Field
  (ReceiveFile e (Services.connected(State.service_state s)) (Input.attach_files e))[].
Definition file_items e parent s :=
 let services:=State.service_state s in
 let connected:=Services.connected services in
 (map(attachment_node e parent)(draft_files(State.current_draft s e))++
   fold_right(fun upload rest=>match Services.upload_owner upload,upload_node connected parent upload with
    |Some owner,Some node=>if same_editor e owner then node::rest else rest|_,_=>rest end)[](Services.uploads services))%list.
Definition files e parent s :=
 region parent "attachments" "Attachments" Roles.Section
  (file_picker e parent s :: file_items e parent s).
Definition settings_row parent key label description controls editor : node Input.input :=
 let row := part parent key in
 let copy := part row "settings-copy" in
 Node row "settings-row" "" Roles.Section Region
  ([region row "settings-copy" "" Roles.Section
     [information copy "setting-name" Information.FieldLabel label;
      information copy "description" Information.Description description];
    region row "settings-controls" "" Roles.Section controls] ++ editor)%list.

Definition settings_group parent key label rows : list (node Input.input) :=
 let group := part parent key in
 match rows with
 | [] => []
 | _ => [Node group "settings-group" "" Roles.Section Region
          (group_title group label :: rows)]
 end.

Module Config := Configuration.Config.
Definition configuration_control key label (enabled : bool) input :=
 Control key label Secondary (Input.ServiceInput input)
   (if enabled then Available else Unavailable "Unavailable in the current state").
Definition configuration_button parent key label enabled input :=
 declared parent Roles.Button (configuration_control key label enabled input).
Definition configuration_switch parent label enabled path raw :=
 let key := "setting-switch" in
 let checked := String.eqb raw "true" in
 Node (part parent key) key label Roles.Button
   (Choice MultipleChoice checked ""
     (configuration_control key label enabled
       (Services.EditConfigurationAt path (if checked then "false" else "true")))) [].
Definition configuration_field parent key label multiline raw choices enabled path :=
 Node (part parent key) key label Roles.Field
   (ConfigurationField multiline raw choices enabled (fun value => option_map
     (fun raw => Input.ServiceInput (Services.EditConfigurationAt path raw)) (as_string value))) [].
Definition configuration_status parent status : node Input.input := information parent "result" Information.Status status.
Definition configuration_value_label value :=
 match value with
 | JBool true => "On"
 | JBool false => "Off"
 | JNull | JString "" => "Not configured"
 | _ => Config.display_value value
 end.
Definition configuration_choices options raw :=
 let options := map (fun value => Fields.ChoiceValue (TextJson.render_json value)
   (configuration_value_label value)) options in
 if existsb (fun option => String.eqb (Fields.choice_value_of option) raw) options then options
 else Fields.ChoiceValue raw "Choose a value" :: options.
Definition configuration_summary value :=
 match value with
 | JObject [] | JArray [] => "None configured"
 | JObject _ | JArray _ => "Configured"
 | _ => configuration_value_label value
 end.
Definition configuration_resettable entry := Config.setting_resettable entry && Config.setting_explicit entry.
Definition configuration_actions parent entry raw enabled view :=
 let accepted := match Config.interpret_input (Config.setting_input entry) raw with
   | Some _ => true | None => false end in
 let apply := configuration_button parent "apply" "Apply configuration change"
   (enabled && accepted && Configuration.dirty view) Services.SetConfiguration in
 let cancel := configuration_button parent "cancel" "Cancel" enabled Services.CancelConfigurationEdit in
 let reset := if configuration_resettable entry then
   [configuration_button parent "reset" "Reset configuration item" enabled Services.ResetConfiguration]
   else [] in
 let status := match Configuration.writing view with
   | Resource.Loading _ _ => [configuration_status parent "Applying configuration change…"]
   | Resource.Loaded _ _ _ => [configuration_status parent "Configuration updated"]
   | Resource.Failed _ _ reason => [configuration_status parent reason]
   | Resource.Dormant => []
   end in
 (status ++ [region parent "configuration-actions" "" Roles.DialogActions
   (reset ++ [cancel; apply])])%list.

Definition configuration_copy path :=
 match path with
 | ["instructions"] => ("Instructions", "Provide standing instructions for the model.")
 | ["profiles"] => ("Model profiles", "Set the providers and models available to tasks.")
 | ["chatgpt"] => ("ChatGPT connection", "Configure Sign in with ChatGPT for model access.")
 | ["reasoning_evaluators"] => ("Reasoning evaluators", "Choose which profiles evaluate adaptive reasoning.")
 | ["mcp"] => ("MCP servers", "Connect local tools and resources through Model Context Protocol.")
 | ["plugins"] => ("Plugins", "Configure the plugins available to the service.")
 | ["skills"] => ("Skills", "Choose where Selvedge loads reusable instructions.")
 | ["chatgpt_plugin"] => ("ChatGPT app", "Configure the ChatGPT app integration.")
 | ["max_fork"] => ("Forks per task", "Limit how many direct forks a task can create.")
 | ["max_descendants"] => ("Task descendants", "Limit how many tasks can descend from one root task.")
 | ["cloud"] => ("Cloud environments", "Configure where cloud tasks run.")
 | ["compaction"] => ("Compaction policy", "Edit the complete context compaction policy as JSON.")
 | ["compaction"; "enabled"] => ("Automatic compaction", "Summarize older context as tasks approach the model's context limit.")
 | ["compaction"; "background_percent"] => ("Background threshold", "Start background compaction at this percentage of the context window.")
 | ["compaction"; "blocking_percent"] => ("Blocking threshold", "Wait for compaction before sending the next request at this percentage.")
 | ["compaction"; "idle_lead_ms"] => ("Idle lead time", "Schedule compaction this many milliseconds before the cache expires.")
 | ["compaction"; "targets"] => ("Target profiles", "Set model-specific context windows and compaction methods.")
 | ["host"] => ("Listen address", "Choose the loopback address the local service listens on.")
 | ["port"] => ("Listen port", "Choose the port the local service listens on.")
 | ["remote"] => ("Remote control", "Configure the relay used to control this service remotely.")
 | _ => (String.concat " / " path, "Edit this service configuration value.")
 end.

Definition configuration_row parent connected view entry :=
 let path := Config.setting_path entry in
 let key := Config.setting_key path in
 let row := part parent key in
 let controls := part row "settings-controls" in
 let editor := part row "setting-editor" in
 let '(label, description) := configuration_copy path in
 let draft := match Configuration.current_draft view with
   | Some draft => if Configuration.matches_path path draft
       then Some (Configuration.draft_input draft) else None
   | None => None
   end in
 let raw := match draft with Some raw => raw | None => Config.initial_input entry end in
 let enabled := connected && Configuration.can_select path view in
 let field parent key multiline options :=
   configuration_field parent key label multiline raw options enabled path in
 let activate key label := configuration_button controls key label enabled (Services.SelectConfiguration path) in
 let compact := match Config.setting_input entry with
   | Config.Boolean => Some (configuration_switch controls label enabled path raw)
   | Config.Choice options =>
       Some (field controls "setting-value" false (Some (configuration_choices options raw)))
   | Config.Number => Some (field controls "setting-value" false None)
   | Config.Text | Config.Structured => None
   end in
 let actions := match draft with
   | None => []
   | Some raw =>
     [region row "setting-editor" "" Roles.Section
        ((match compact with
          | Some _ => []
          | None => [field editor "setting-editor-value" true None]
          end)
         ++ configuration_actions editor entry raw enabled view)%list]
   end in
 settings_row parent key label description
   (match compact with
    | Some control => control ::
      (match draft with
       | None => if configuration_resettable entry then [activate "start-reset" "Reset…"] else []
       | Some _ => []
       end)
    | None => [information controls "setting-summary" Information.FieldValue (configuration_summary (Config.setting_value entry));
               activate "edit" (if String.eqb label "Instructions" then "Edit instructions" else "Edit " ++ label)]
    end)
   actions.

Inductive configuration_group :=
| InstructionsGroup | ModelsGroup | ToolsGroup | TasksGroup | CompactionGroup
| CompactionDocumentGroup | ContextSourcesGroup | ConnectionGroup.

Definition setting_group path :=
 match path with
 | "instructions" :: _ => InstructionsGroup
 | ("profiles" | "chatgpt" | "reasoning_evaluators") :: _ => ModelsGroup
 | ("mcp" | "plugins" | "skills" | "chatgpt_plugin") :: _ => ToolsGroup
 | ("max_fork" | "max_descendants" | "cloud") :: _ => TasksGroup
 | ["compaction"] => CompactionDocumentGroup
 | "compaction" :: _ => CompactionGroup
 | ("host" | "port" | "remote") :: _ => ConnectionGroup
 | _ => ContextSourcesGroup
 end.
Definition configuration_group_eq_dec :
 forall left right : configuration_group, {left = right} + {left <> right}.
Proof. decide equality. Defined.

Definition configuration_group_section parent key label group services :=
 let view := Services.service_configuration services in
 match Configuration.available view with
 | None => []
 | Some snapshot =>
   settings_group parent key label
     (map (configuration_row (part parent key) (Services.connected services) view)
       (filter (fun entry => if configuration_group_eq_dec (setting_group (Config.setting_path entry)) group
                              then true else false) (Config.entries snapshot)))
 end.

Definition settings_section_label section :=
 match section with
 | Services.SettingsGeneral => "General"
 | Services.SettingsModels => "Models & tools"
 | Services.SettingsTasks => "Tasks"
 | Services.SettingsContext => "Context"
 | Services.SettingsConnection => "Connection"
 end.
Definition settings_sections :=
 [Services.SettingsGeneral; Services.SettingsModels; Services.SettingsTasks;
  Services.SettingsContext; Services.SettingsConnection].
Definition settings_navigation parent current : node Input.input :=
 let nav := part parent "settings-nav" in
 Node nav "settings-nav" "Settings categories" Roles.Section ChoiceGroup
   (map (fun section =>
     let key := Services.settings_section_name section in
     let label := settings_section_label section in
     Node (part nav key) "settings-category" label Roles.Button
       (Choice SingleChoice (String.eqb key (Services.settings_section_name current)) ""
         (secondary key label (Input.ServiceInput (Services.SelectSettingsSection section)))) [])
   settings_sections).

Definition settings_appearance parent current :=
 let controls := part (part parent "appearance") "settings-controls" in
 let options := part controls "themes" in
 settings_row parent "appearance" "Color theme" "Choose how Selvedge looks in this browser."
   [Node options "theme-options" "Color theme" Roles.Section ChoiceGroup
     (map (fun theme =>
       let label := match theme with Appearance.SystemAppearance => "System"
         | Appearance.LightAppearance => "Light" | Appearance.DarkAppearance => "Dark" end in
       let key := Appearance.appearance_name theme in
       Node (part options key) "appearance" label Roles.Button
         (Choice SingleChoice (String.eqb key (Appearance.appearance_name current)) ""
           (secondary key label (Input.ServiceInput (Services.ChooseAppearance theme)))) [])
       [Appearance.SystemAppearance; Appearance.LightAppearance; Appearance.DarkAppearance])] [].

Definition settings_catalog_status parent services :=
 let view := Services.service_configuration services in
 let load label := configuration_button parent "load-configuration" label (Services.connected services)
   Services.LoadConfiguration in
 match Configuration.catalog view with
 | Resource.Dormant =>
   if Services.connected services then [load "Load service configuration"]
   else [configuration_status parent "Connect to the local service to edit its settings."]
 | Resource.Loading _ _ => [configuration_status parent "Loading service configuration…"]
 | Resource.Failed _ _ reason => [configuration_status parent reason; load "Reload configuration"]
 | Resource.Loaded _ _ _ => []
 end.

Definition settings_configuration_groups section : list (configuration_group * string * string) :=
 match section with
 | Services.SettingsGeneral => [(InstructionsGroup, "instructions", "Model instructions")]
 | Services.SettingsModels => [(ModelsGroup, "models", "Models"); (ToolsGroup, "tools", "Tools")]
 | Services.SettingsTasks => [(TasksGroup, "task-execution", "Task execution")]
 | Services.SettingsContext =>
   [(CompactionGroup, "compaction", "Compaction");
    (CompactionDocumentGroup, "compaction-document", "Advanced");
    (ContextSourcesGroup, "context-sources", "Context sources")]
 | Services.SettingsConnection => [(ConnectionGroup, "service-config", "Service settings")]
 end.
Definition settings_has_configuration_group section kind :=
 existsb (fun '(group, _, _) => if configuration_group_eq_dec kind group then true else false)
   (settings_configuration_groups section).
Definition settings_draft_notice parent section services : list (node Input.input) :=
 let view := Services.service_configuration services in
 match Configuration.current_draft view with
 | Some draft =>
   let path := Configuration.draft_path draft in
   let kind := setting_group path in
   if (Configuration.dirty view || Configuration.pending view) &&
      negb (settings_has_configuration_group section kind)
   then
     match find (fun owner => settings_has_configuration_group owner kind) settings_sections with
     | Some owner =>
       [information parent "settings-draft-notice" Information.Description
          ("Finish editing " ++ fst (configuration_copy path) ++ " in " ++ settings_section_label owner ++ ".")]
     | None => []
     end
   else []
 | None => []
 end.

Definition settings_content root parent section services : node Input.input :=
 let content := part parent ("settings-content/" ++ Services.settings_section_name section) in
 let group key label rows := settings_group content key label rows in
 let general := match section with
 | Services.SettingsGeneral =>
   group "appearance" "Appearance" [settings_appearance (part content "appearance") (Services.theme services)] ++
   group "conversation-titles" "Conversation titles"
     [settings_row (part content "conversation-titles") "title-prompts" "Title generation"
        "Choose the model and prompts used to name conversations and tasks."
        [declared root Roles.Button (secondary "title-prompts" "Edit title prompts"
           (Input.OpenEditor TitlePrompts (part root "title-prompts")))] []]
 | Services.SettingsConnection =>
   group "service" "Service connection"
     [settings_row (part content "service") "connect" "Current service"
       "Connect this browser to the local Selvedge service."
       [declared root Roles.Button (secondary "connect" "Connect" (Input.ServiceInput Services.Connect))] []]
 | _ => []
 end%list in
 let configured := flat_map (fun '(kind, key, label) =>
   configuration_group_section content key label kind services) (settings_configuration_groups section) in
 Node content "settings-content" "" Roles.Section Region
   (title content (settings_section_label section) ::
     (settings_catalog_status content services ++ settings_draft_notice content section services ++
      general ++ configured))%list.

Definition settings s :=
 let services := State.service_state s in
 match Services.settings_return services with
 |None=>[]
 |Some trigger=>let parent:="/settings"in
  let body := part parent "body" in
  let section := Services.settings_section services in
  [Node parent "settings" "Settings"Roles.Dialog
   (LayerRegion(LayerBehavior ModalDialog false(State.generation(State.navigation_state s))
     (part parent "close")
     (Services.settings_focus_target trigger) "/main"trigger(Input.ServiceInput Services.CloseSettings) true true))
   [dialog_header parent
      [declared parent Roles.Button(secondary "close" "Close settings"(Input.ServiceInput Services.CloseSettings));
       title parent "Settings"];
    dialog_body parent [settings_navigation body section; settings_content parent body section services]]]
  end.

Theorem settings_preserves_return_attention s trigger :
 Services.settings_return (State.service_state s) = Some trigger ->
 exists tree, settings s = [tree] /\
 option_map layer_return_attention (layer_region (node_meaning tree)) =
   Some (Services.settings_focus_target trigger).
Proof.
 intros Open. unfold settings. rewrite Open.
 eexists. split; reflexivity.
Qed.

Definition directory_view s :=
 let services:=State.service_state s in
 match Services.directory services with
 |Resource.Dormant=>[]
 |resource=>match resource_ticket resource,resource_request resource with
  |Some ticket,Some request=>let parent:="/directory-browser"in
   let content:=match resource with
    |Resource.Loading _ _=>[read_only parent "loading" "Working directories" "Loading directories…"]
    |Resource.Failed _ _ reason=>[read_only parent "failure" "Directory listing failed"reason;
      declared parent Roles.Button(secondary "retry" "Retry"(Input.ServiceInput Services.GoDirectory))]
    |Resource.Loaded _ _ catalog=>(
      map(fun entry=>declared parent Roles.Button(secondary("directory/"++text "path" entry)(text "name" entry)
       (Input.ServiceInput(Services.VisitDirectory(text "path" entry)))))(Selvedge.Interaction.Codec.items "entries" catalog)++
      (if flag "truncated" catalog then[read_only parent "truncated" "Directories" "The directory listing is truncated"]else[]))%list
    |_=>[]end in
   [Node parent "directory-browser" "Choose directory"Roles.Dialog
    (LayerRegion(LayerBehavior ModalDialog false ticket
     (match resource with Resource.Loaded _ _ _=>part parent "location"|_=>parent end)
     (Services.directory_trigger request)"/main"(Services.directory_trigger request)
     (Input.ServiceInput Services.CloseDirectory)true true))
    [dialog_header parent [title parent "Choose directory"];
     dialog_body parent(match resource with
      |Resource.Loaded _ _ catalog=>
       [region parent "navigation" "Folder navigation" Roles.Section
        ([Node(part parent "location")"directory-location" "Directory"Roles.Field
          (EnterDirectory(Services.directory_editor request)(Services.directory_location services)
           (fun value=>option_map(fun path=>Input.ServiceInput(Services.WriteDirectoryLocation path))(as_string value))
           (Some(Input.ServiceInput Services.GoDirectory)))[];
         declared parent Roles.Button(secondary "go" "Go"(Input.ServiceInput Services.GoDirectory))]++
         match string_field "parent" catalog with None=>[]|Some path=>
          [declared parent Roles.Button(secondary "parent" "Parent directory"(Input.ServiceInput(Services.VisitDirectory path)))]end);
        region parent "folders" "Folders" Roles.Section content]
      |_=>content end);
     dialog_actions parent
      (List.app(match resource with Resource.Loaded _ _ _=>
       [declared parent Roles.PrimaryButton(secondary "choose" "Use this directory"(Input.ServiceInput Services.ChooseDirectory))]|_=>[]end)
       [declared parent Roles.Button(secondary "cancel" "Cancel"(Input.ServiceInput Services.CloseDirectory))])]]
  |_,_=>[]end end.
Definition preview_view s :=match Services.preview(State.service_state s)with
|Resource.Dormant=>[]
|resource=>match resource_ticket resource,resource_request resource with
 |Some ticket,Some request=>let parent:="/file-preview"in
  let body:=match resource with
    |Resource.Loading _ _=>[read_only parent "loading" "Preview" "Loading preview…"]
    |Resource.Failed _ _ reason=>[read_only parent "failure" "Preview failed"reason]
    |Resource.Loaded _ _ url=>if String.prefix "image/"(asset_mime(Services.preview_file request))then
      [Node(part parent "image")"preview-image" ""Roles.Content(Image url(asset_name(Services.preview_file request)))[]]else []
    |_=>[]end in
  [Node parent "file-preview"(asset_name(Services.preview_file request))Roles.Dialog
   (LayerRegion(LayerBehavior ModalDialog false ticket parent(Services.preview_trigger request)"/main"(Services.preview_trigger request)
    (Input.ServiceInput Services.ClosePreview)true true))
   ([dialog_header parent [title parent(asset_name(Services.preview_file request));
     declared parent Roles.Button(secondary "close" "Close preview"(Input.ServiceInput Services.ClosePreview))]] ++
    (match body with []=>[]|_=>[dialog_body parent body]end) ++
    [dialog_actions parent[declared parent Roles.Button
      (Control "download" "Download" Secondary(Input.ServiceInput(Services.Download(Services.preview_file request)))
       (match resource with Resource.Loaded _ _ _=>Available|_=>Unavailable "The preview is not ready"end))]])%list]
 |_,_=>[]end end.
Definition dialogs s :=(settings s++directory_view s++preview_view s)%list.
