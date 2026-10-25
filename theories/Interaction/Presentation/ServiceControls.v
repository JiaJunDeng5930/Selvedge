From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Features Require Domain.
From Selvedge.Interaction Require Import Codec Identity Appearance Input Resource Services Speech Attachments.
From Selvedge.Interaction.Session Require Draft State Authoring.
From Selvedge.Interaction.Presentation Require Import Surface Model Construction.
From Selvedge.Interaction.Presentation Require Roles Information.
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
Definition files e parent s :=
 let services:=State.service_state s in
 let connected:=Services.connected services in
 let receive := Input.attach_files e in
 region parent "attachments" "Attachments" Roles.Section
 (Node(part parent "attach")"attach" "Attach files"Roles.Field(ReceiveFile e connected receive)[]::
  (map(attachment_node e parent)(draft_files(State.current_draft s e))++
   fold_right(fun upload rest=>match Services.upload_owner upload,upload_node connected parent upload with
    |Some owner,Some node=>if same_editor e owner then node::rest else rest|_,_=>rest end)[](Services.uploads services)))%list.
Definition settings s :=
 match Services.settings_return(State.service_state s)with
 |None=>[]
 |Some trigger=>let parent:="/settings"in
  [Node parent "settings" "Settings"Roles.Dialog
   (LayerRegion(LayerBehavior ModalDialog false(State.generation(State.navigation_state s))
     (part parent "connect")
     (Services.settings_focus_target trigger) "/main"trigger(Input.ServiceInput Services.CloseSettings) true true))
   [dialog_header parent [title parent "Settings";
     declared parent Roles.Button(secondary "close" "Close settings"(Input.ServiceInput Services.CloseSettings))];
    dialog_body parent
     [region parent "appearance" "Appearance"Roles.Section
       (map(fun theme=>let label:=match theme with Appearance.SystemAppearance=>"System"|Appearance.LightAppearance=>"Light"|Appearance.DarkAppearance=>"Dark"end in
         Node(part parent("appearance/"++Appearance.appearance_name theme))"appearance"label Roles.Button
          (Choice SingleChoice(String.eqb(Appearance.appearance_name theme)(Appearance.appearance_name(Services.theme(State.service_state s))))""
           (secondary("appearance/"++Appearance.appearance_name theme)label(Input.ServiceInput(Services.ChooseAppearance theme))))[])
         [Appearance.SystemAppearance;Appearance.LightAppearance;Appearance.DarkAppearance]);
      declared parent Roles.Button(secondary "title-prompts" "标题生成设置"(Input.OpenEditor TitlePrompts(part parent "title-prompts")))];
    dialog_actions parent[declared parent Roles.Button(secondary "connect" "Connect"(Input.ServiceInput Services.Connect))]]]
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
