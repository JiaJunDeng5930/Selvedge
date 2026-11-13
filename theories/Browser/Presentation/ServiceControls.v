From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers TextJson.
From Selvedge.Adapters Require Common.
From Selvedge.Features Require Domain.
From Selvedge.Kernel Require WorkspaceBackend.
From Selvedge.Browser Require Import NavigationIdentity.
From Selvedge.Interaction Require Import Codec Identity.
From Selvedge.Interaction Require World.
From Selvedge.Interaction.Experience Require ContextObservation.
From Selvedge.Interaction.Experience Require Observation.
From Selvedge.Browser.Session Require Import Appearance Input.
From Selvedge.Programming Require Import Resource.
From Selvedge.Browser.Session Require Import Services Speech.
From Selvedge.Interaction Require Import Attachments.
From Selvedge.Interaction.Submission Require Draft Fields.
From Selvedge.Interaction.Submission Require Observation.
From Selvedge.Browser.Session Require Configuration.
From Selvedge.Browser.Session Require State Authoring.
From Selvedge.Browser.Session Require Observation.
From Selvedge.Browser.Scene Require Import Surface Model Construction.
From Selvedge.Browser.Presentation Require Import Projection.
From Selvedge.Browser.Presentation Require Roles Information Settings.
Import ListNotations.
Open Scope string_scope.
Module SO := Selvedge.Browser.Session.Observation.
Module Submission := Selvedge.Interaction.Submission.Observation.
Module Experience := Selvedge.Interaction.Experience.Observation.

Definition speech_button parent id label (enabled:bool) event :=
 declared parent Roles.Button(Control("speech/"++id)label Secondary(Input.SpeechInput event)
  (if enabled then Available else Unavailable "Audio is busy")).
Definition speech_status parent text:node Input.input:=information parent "speech/status" Information.Status text.
Definition can_begin_voice speech realtime:=Speech.free speech&&match Speech.eligible realtime speech with Some _=>true|None=>false end.
Definition speech_controls snapshot s e revision parent (speech:Speech.speech) :=
 let free:=Speech.free speech in
 let choices:=match Speech.connections speech with
 |[]=>[Settings.sign_in_button (part parent "speech") speech]
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
Definition file_picker e parent s caption :=
 Node(part parent "attach")"attach" caption Roles.Field
  (ReceiveFile e (Services.connected(State.service_state s)) (Input.attach_files e))[].
Definition file_items e parent s :=
 let services:=State.service_state s in
 let connected:=Services.connected services in
 (map(attachment_node e parent)(draft_files(State.current_draft s e))++
   fold_right(fun upload rest=>match Services.upload_owner upload,upload_node connected parent upload with
    |Some owner,Some node=>if same_editor e owner then node::rest else rest|_,_=>rest end)[](Services.uploads services))%list.
Definition files e parent s caption :=
 region parent "attachments" caption Roles.Section
  (file_picker e parent s caption :: file_items e parent s).
Definition settings := Settings.view.

Definition account_login_view s : list(node Input.input) :=
 match Speech.sign_in(State.speech_state s)with
 |None=>[]
 |Some dialog=>
  let parent:="/account-sign-in" in
  let trigger:=Speech.login_trigger dialog in
  let fallback:=match Services.settings_return(State.service_state s)with
    |Some _=>part Settings.settings_root "close"|None=>"/main" end in
  let close:=Input.SpeechInput Speech.CloseLogin in
  let button key label emphasis action:=
    declared parent Roles.Button(Control key label emphasis(Input.SpeechInput action)Available) in
  let choose key label emphasis method:=button key label emphasis(Speech.ChooseLogin method)in
  let description key text:=information parent key Information.Description text in
  let status text:=information parent "status" Information.Status text in
  let code_key:=part(part parent "device-code")"value" in
  let methods:=button "methods" "Other sign-in methods" Secondary Speech.ReturnToMethods in
  let '(body, actions):=match Speech.login_stage dialog with
   |Speech.ChooseMethod=>(
     [region parent "login-methods" "Sign-in methods" Roles.Section
       [region parent "device-method" "" Roles.Section
         [choose "device" "Use a device code" Primary Speech.DeviceCode;
          description "device-help" "Recommended when Selvedge runs on a remote machine."];
        region parent "browser-method" "" Roles.Section
         [choose "browser" "Continue in a browser tab" Secondary Speech.BrowserTab;
          description "browser-help" "Use this when Selvedge runs on this computer or its callback port is forwarded."]]],
     [button "cancel" "Cancel" Secondary Speech.CloseLogin])
   |Speech.StartingLogin _ _=>([status "Starting sign-in…"],[button "cancel" "Cancel" Secondary Speech.CloseLogin])
   |Speech.BrowserOpened _=>(
     [status "Complete sign-in in the ChatGPT tab, then return here."],
     [button "close" "Close" Secondary Speech.CloseLogin;methods])
   |Speech.DeviceCodeShown _ url code expires copied=>(
     ([description "instructions" "Open ChatGPT verification and enter the code below. Only enter it on auth.openai.com.";
       Node(part parent "verification")"device-verification" "Open ChatGPT verification" Roles.Content(ExternalLink url)[];
       region parent "device-code-actions" "" Roles.Toolbar
        [read_only parent "device-code" "Device code" code;
         button "copy" "Copy code" Secondary (Speech.CopyLoginCode code_key)];
       description "expiry" (String.append "Expires " expires);
       description "security" "If prompted, enable device code authorization in your ChatGPT security settings.";
       status "Waiting for authorization…"] ++
       [information parent "copy-status" Information.Status
         (match copied with
          |Some true=>"Code copied."
          |Some false=>"Copy the selected code, or enter it manually."
          |None=>"" end)])%list,
     [button "cancel" "Cancel" Secondary Speech.CloseLogin;methods])
   |Speech.SignInFailed method reason=>(
     [status reason],
     [button "close" "Close" Secondary Speech.CloseLogin;
      methods;
      choose "retry" "Try again" Primary method])
   |Speech.SignedIn=>(
     [status "Signed in to ChatGPT."],[button "done" "Done" Primary Speech.CloseLogin])
   end in
  [Node parent "account-sign-in" "Sign in with ChatGPT" Roles.Dialog
    (LayerRegion(LayerBehavior ModalDialog false(Speech.login_occurrence dialog)
      (part parent "heading") trigger fallback trigger close false true))
    [dialog_header parent[title parent "Sign in with ChatGPT"];dialog_body parent body;dialog_actions parent actions]]
 end.

Theorem settings_preserves_return_attention s trigger :
 Services.settings_return (State.service_state s) = Some trigger ->
 exists tree, settings s = [tree] /\
 option_map layer_return_attention (layer_region (node_meaning tree)) =
   Some (Services.settings_focus_target trigger).
Proof.
 intros Open. unfold settings, Settings.view. rewrite Open.
 eexists. split; reflexivity.
Qed.

Definition directory_backend snapshot owner := match Identity.editor_task owner with
 |None=>Some WorkspaceBackend.Local
 |Some task=>settings<-ContextObservation.task_settings task snapshot;;
  match Selvedge.Kernel.Domain.settings_resource settings with
  |None=>Some WorkspaceBackend.Local
  |Some workspace=>value<-World.find_world "worktrees" "task_id" workspace snapshot;;
   bind(string_field "backend" value)WorkspaceBackend.decode
  end
 end.
Definition directory_git_status (label:string->string->string) preview := match preview with
 |None=>None
 |Some SO.AwaitingDirectory=>Some(label "按 Enter 或点「前往」打开输入的目录。" "Press Enter or click Go to open the entered directory.")
 |Some(SO.PreviewDirectory _ primary problem)=>Some(
  (if primary then "" else label "将作为辅助目录添加。" "This will be added as an additional directory. ")++
  match problem with
  |None=>label "可作为 Git 工作树的主目录。" "This directory can be the primary for a Git worktree."
  |Some Submission.GitCheckPending=>label "正在检查此目录是否支持 Git 工作树…" "Checking this directory for Git worktrees…"
  |Some Submission.GitCheckFailed=>label "无法检查此目录是否支持 Git 工作树。" "Could not check this directory for Git worktrees."
  |Some _=>if primary then label "主目录须位于包含提交的 Git 仓库中。" "The primary directory must be in a Git repository with a commit."
    else label "此目录不能用作 Git 工作树的主目录。" "This directory cannot be the primary for a Git worktree." end)
 end.
Definition directory_error_message (label:string->string->string) code := match code with
 |"ENOENT"=>label "找不到这个目录，请检查路径。" "Directory not found. Check the path."
 |"ENOTDIR"=>label "这个路径不是目录。" "This path is not a directory."
 |"EACCES"|"EPERM"=>label "无法访问此目录，请检查权限。" "Cannot access this directory. Check permissions."
 |_=>label "无法读取目录，请检查路径或稍后再试。" "Cannot read this directory. Check the path or try again."
 end.
Definition directory_view snapshot s :=
 let services:=State.service_state s in
 match Services.directory services with
 |Resource.Dormant=>[]
 |resource=>match resource_ticket resource,resource_request resource with
  |Some ticket,Some request=>let parent:="/directory-browser"in
   let owner:=Services.directory_editor request in
   let label (chinese english:string):=match owner with Identity.Project _=>chinese|_=>english end in
   let preview:=SO.directory_preview snapshot s in
   let git_status:=directory_git_status label preview in
   let draft:=State.current_draft s owner in
   let source:=if SO.cloud_workspace_configured snapshot && SO.cloud_workspace_requested draft then
    [information parent "cloud-workspace-source" Information.Description(Experience.cloud_source_caption snapshot draft)]
    else[]in
   let caption:=label "选择 Selvedge 主机上的目录" (match directory_backend snapshot owner with
    |Some WorkspaceBackend.Local=>"Choose a directory on the Selvedge host"
    |Some WorkspaceBackend.TencentCvm=>"Choose a directory in the conversation's cloud workspace"
    |None=>"Choose a directory" end) in
   let content:=match resource with
    |Resource.Loading _ _=>[information parent "loading" Information.Status (label "正在读取目录…" "Loading directories…")]
    |Resource.Failed _ _ code=>
      region parent "failure" "" Roles.Alert [information parent "failure-detail" Information.Description(directory_error_message label code)]::
      (match Services.directory_previous request with None=>[]|Some path=>
       [declared parent Roles.Button(secondary "previous" (label "返回上一个可用目录" "Back to previous directory")
        (Input.ServiceInput(Services.VisitDirectory path)))]end)
    |Resource.Loaded _ _ catalog=>let entries:=Selvedge.Interaction.Codec.items "entries" catalog in
      (map(fun entry=>declared parent Roles.Button(secondary("directory/"++text "path" entry)(text "name" entry)
       (Input.ServiceInput(Services.VisitDirectory(text "path" entry)))))entries++
      (if flag "truncated" catalog then[information parent "truncated" Information.Description
        (label "目录列表仅显示部分结果。" "The directory listing is truncated.")]else
        match entries,preview with
        |[],Some SO.AwaitingDirectory=>[]
        |[],_=>[information parent "empty-folders" Information.Status
          (label "此目录没有子目录。" "This directory has no subdirectories.")]
        |_,_=>[]end))%list
    |_=>[]end in
   let parent_action:=match resource with Resource.Loaded _ _ catalog=>
        match string_field "parent" catalog with None=>[]|Some path=>
         [declared parent Roles.Button(secondary "parent" (label "上一级" "Up")(Input.ServiceInput(Services.VisitDirectory path)))]end
       |_=>[]end in
   let navigation:=region parent "directory-location-actions" (label "目录导航" "Folder navigation") Roles.Section
        (parent_action++
         [Node(part parent "location")"directory-location" (label "目录路径" "Directory") Roles.Field
          (EnterDirectory owner (Services.directory_location services)
           (fun value=>option_map(fun path=>Input.ServiceInput(Services.WriteDirectoryLocation path))(as_string value))
           (Some(Input.ServiceInput Services.GoDirectory)))[];
         declared parent Roles.Button(secondary "go" (label "前往" "Go")(Input.ServiceInput Services.GoDirectory))]) in
   [Node parent "directory-browser" caption Roles.Dialog
    (LayerRegion(LayerBehavior ModalDialog false ticket (part parent "location")
     (Services.directory_trigger request)"/main"(Services.directory_trigger request)
     (Input.ServiceInput Services.CloseDirectory)true true))
    [dialog_header parent [title parent caption];
     dialog_body parent((source++navigation::match resource with
      |Resource.Loaded _ _ _=>[region parent "folders" (label "子目录" "Folders") Roles.Section content]
      |_=>content end)%list);
     dialog_actions parent
      ((match resource,git_status with Resource.Loaded _ _ _,Some status=>
        [information parent "directory-git-status" Information.Status status]|_,_=>[]end)++
       (match preview with Some(SO.PreviewDirectory _ _ (Some Submission.GitCheckFailed))=>
        [declared parent Roles.Button(secondary "retry-git" (label "重试 Git 检查" "Retry Git check")(Input.ServiceInput Services.GoDirectory))]|_=>[]end)++
       [declared parent Roles.Button(secondary "cancel" (label "取消" "Cancel")(Input.ServiceInput Services.CloseDirectory))]++
       match resource with Resource.Loaded _ _ _=>
       [declared parent Roles.PrimaryButton(Control "choose" (label "使用此目录" "Use this directory") Secondary
        (Input.ServiceInput Services.ChooseDirectory)
        (if SO.directory_selection_allowed preview then Available else Unavailable(value_or "" git_status)))]|_=>[]end)%list
       ]]
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
