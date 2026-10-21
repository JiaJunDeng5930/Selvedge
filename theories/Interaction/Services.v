From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers TextJson.
From Selvedge.Interaction Require Export Attachments.
From Selvedge.Interaction Require Import Codec Identity Resource Forms ModelSelection.
From Selvedge.Interaction Require CommandAssessment.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
Import ListNotations.
Open Scope string_scope.

Record upload_request := UploadRequest { upload_editor:editor; upload_file:selected_file }.
Definition encode_upload a := JObject[("editor",encode_editor(upload_editor a));("file",encode_file(upload_file a))].
Definition decode_upload j := e <- bind(field "editor" j) decode_editor ;; f <- bind(field "file" j) decode_file ;; Some(UploadRequest e f).
Record preview_request := PreviewRequest { preview_file:attachment; preview_trigger:string }.
Definition encode_preview p := JObject[("file",encode_attachment(preview_file p));("trigger",JString(preview_trigger p))].
Definition decode_preview j := f <- bind(field "file" j) decode_attachment ;; t <- string_field "trigger" j ;; Some(PreviewRequest f t).
Record directory_request := DirectoryRequest { directory_editor:editor; directory_path:string; directory_trigger:string }.
Definition encode_directory d := JObject[("editor",encode_editor(directory_editor d));("path",JString(directory_path d));("trigger",JString(directory_trigger d))].
Definition decode_directory j := e <- bind(field "editor" j) decode_editor ;; p <- string_field "path" j ;; t <- string_field "trigger" j ;; Some(DirectoryRequest e p t).
Inductive appearance := SystemAppearance | LightAppearance | DarkAppearance.
Definition appearance_name a := match a with SystemAppearance => "system" | LightAppearance => "light" | DarkAppearance => "dark" end.
Definition decode_appearance s := match s with "system"=>Some SystemAppearance|"light"=>Some LightAppearance|"dark"=>Some DarkAppearance|_=>None end.
Record preparation := Preparation { preparation_ticket:N; preparation_draft:Forms.draft; preparation_generation:N; preparation_trigger:string }.
Definition encode_preparation p := JObject[("ticket",number(preparation_ticket p));("draft",Forms.encode_draft(preparation_draft p));("generation",number(preparation_generation p));("trigger",JString(preparation_trigger p))].
Definition decode_preparation j := t<-natural_field "ticket" j;;d<-bind(field "draft" j)Forms.decode_draft;;g<-natural_field "generation" j;;trigger<-string_field "trigger" j;;Some(Preparation t d g trigger).
Definition encode_git_request (r:editor*string) := JObject[("editor",encode_editor(fst r));("primary",JString(snd r))].
Definition decode_git_request j := e<-bind(field "editor" j)decode_editor;;p<-string_field "primary" j;;Some(e,p).
Record services := Services {
  connection:resource unit unit; settings_return:option string; theme:appearance; next_ticket:N;
  uploads:list(resource upload_request attachment); preview:resource preview_request string;
  directory:resource directory_request json; directory_location:string;
  model_preference:option (string * string); storage_problem:option string;
  preparations:list preparation; workspace_git:resource (editor*string) bool;
  command_assessments:list(resource CommandAssessment.request CommandAssessment.observation) }.
Definition initial := Services Dormant None SystemAppearance 0 [] Dormant Dormant "" None None [] Dormant [].
Definition connected s := match connection s with Loaded _ _ _ => true | _ => false end.
Definition settings_focus_target trigger :=
  if String.eqb trigger "nav/settings" || String.eqb trigger "global-navigation-toggle"
  then "settings-return" else trigger.
Definition settings_open s := match settings_return s with Some _=>true|None=>false end.
Definition with_connection c s := set connection (fun _ => c) s.
Definition with_settings_return trigger s := set settings_return (fun _ => trigger) s.
Definition with_theme t s := set theme (fun _ => t) s.
Definition with_next n s := set next_ticket (fun _ => n) s.
Definition with_uploads u s := set uploads (fun _ => u) s.
Definition with_preview p s := set preview (fun _ => p) s.
Definition with_directory d location s := set directory_location (fun _ => location) (set directory (fun _ => d) s).
Definition with_model_preference value s := set model_preference (fun _ => value) s.
Definition with_storage_problem value s := set storage_problem (fun _ => value) s.
Definition with_preparations ps s := set preparations (fun _ => ps) s.
Definition with_workspace_git value s := set workspace_git (fun _ => value) s.
Definition with_command_assessments values s := set command_assessments (fun _ => values) s.
Definition owned_assessment owner (r:resource CommandAssessment.request CommandAssessment.observation) :=
  match resource_request r with Some request=>CommandAssessment.same_owner owner(CommandAssessment.request_owner request)|None=>false end.
Definition assessment_owned e := owned_assessment(CommandAssessment.DraftOwner e).
Definition forget_owned_assessment owner s := with_command_assessments
  (filter(fun r=>negb(owned_assessment owner r))(command_assessments s))s.
Definition forget_assessment e := forget_owned_assessment(CommandAssessment.DraftOwner e).
Definition preparing e s := existsb(fun p=>same_editor e(Forms.owner(preparation_draft p)))(preparations s).
Definition forget_preparation ticket s := with_preparations(filter(fun p=>negb(N.eqb ticket(preparation_ticket p)))(preparations s))s.
Definition cancel_editor e s :=
  let s:=forget_assessment e s in
  let s:=with_preparations(filter(fun p=>negb(same_editor e(Forms.owner(preparation_draft p))))(preparations s))s in
  match directory s with Loading _ request|Loaded _ request _|Failed _ request _=>
    if same_editor e(directory_editor request)then with_directory Dormant "" s else s|Dormant=>s end.
Definition upload_owner (r:resource upload_request attachment) := match r with Dormant=>None|Loading _ a|Loaded _ a _|Failed _ a _=>Some(upload_editor a) end.
Definition blocks e s := existsb(fun r=>match upload_owner r with Some owner=>same_editor e owner|None=>false end)(uploads s).
Definition ticket_matches {A B} (t:N) (r:resource A B) := match resource_ticket r with Some u=>N.eqb t u|None=>false end.
Definition forget_upload t s := with_uploads(filter(fun r=>negb(ticket_matches t r))(uploads s))s.
Inductive service_input :=
| CommandAssessed(ticket:N)(outcome:sum string CommandAssessment.observation) | RetryAssessment(owner:editor)
| RestoreModelPreference(raw:string) | StorageProblem(message:string) | DismissStorageProblem
| WorkspaceGitCompleted(ticket:N)(outcome:sum string bool)
| OpenSettings | CloseSettings | Connect | Authenticated(ticket:N)(outcome:sum string unit)
| Disconnected(ticket:N)(reason:string)(revoked:bool) | RetryConnection(ticket:N) | ChooseAppearance(value:appearance)
| AddFile(owner:editor)(file:selected_file) | RetryUpload(ticket:N) | CancelUpload(ticket:N)
| Uploaded(ticket:N)(outcome:sum string attachment)
| OpenPreview(file:attachment)(trigger:string) | Previewed(ticket:N)(outcome:sum string string) | ClosePreview
| Download(file:attachment) | OpenDirectory(owner:editor)(path trigger:string)
| WriteDirectoryLocation(value:string) | VisitDirectory(path:string) | GoDirectory
| DirectoryListed(ticket:N)(outcome:sum string json) | ChooseDirectory | CloseDirectory.
Inductive service_effect :=
| AssessCommand(ticket:N)(request:CommandAssessment.request)
| Authenticate(ticket:N) | Reconnect(ticket:N)(milliseconds:N)
| SaveAppearance(value:appearance) | Upload(ticket:N)(request:upload_request) | AbortUpload(ticket:N)
| FetchPreview(ticket:N)(file:attachment) | ReleasePreview(url:string) | DownloadFile(file:attachment)
| ObserveDirectories(ticket:N)(workspace:json)(owner:editor) | ObserveWorkspaceGit(ticket:N)(primary:string)(owner:editor)
| ListDirectory(ticket:N)(path:string)(owner:editor) | DirectoryChosen(owner:editor)(path:string) | Focus(trigger:string).
Record service_result := ServiceResult { service_state:services; service_effects:list service_effect; attached:option(editor*attachment) }.
Definition keep s := ServiceResult s [] None.
Definition effects s es := ServiceResult s es None.
Definition ensure_assessment owner revision sequence command s :=
  let current:=match find(owned_assessment owner)(command_assessments s)with
    |Some resource=>match resource_request resource with
      |Some request=>CommandAssessment.matches owner revision sequence command request|None=>false end
    |None=>false end in
  if current then keep s else
    let ticket:=next_ticket s in let request:=CommandAssessment.Request owner revision sequence command in
    effects(with_next(N.succ ticket)(with_command_assessments
      (Loading ticket request::filter(fun resource=>negb(owned_assessment owner resource))(command_assessments s))s))
      [AssessCommand ticket request].
Definition release_preview s := match preview s with Loaded _ _ url=>[ReleasePreview url]|_=>[]end.
Definition end_connection reason s :=
  let aborts:=flat_map(fun r=>match r with Loading ticket _=>[AbortUpload ticket]|_=>[]end)(uploads s)in
  let failed:=map(fun r=>match r with Loading ticket request=>Failed ticket request reason|_=>r end)(uploads s)in
  (* A connection owns in-flight transfers and admission observations. Its
     replacement must not attach old receipts to the next authenticated world. *)
  effects(with_command_assessments[](with_preview Dormant(with_uploads failed s)))
    (aborts++release_preview s).
Definition connect s :=
  let ended:=end_connection "Connection replaced" s in
  let clean:=service_state ended in let t:=next_ticket clean in
  effects(with_next(N.succ t)(with_connection(Loading t tt)clean))
    (service_effects ended++[Authenticate t]).
Definition auth_result t result s :=
  match connection s with
  | Loading u _ => if N.eqb t u then
      let s':=with_connection(settle t result (connection s))s in
      match result with inr _=>effects(with_settings_return None s')[]
      |inl _=>effects(with_settings_return(Some(match settings_return s' with
          Some trigger=>trigger|None=>"main"end))s')[Reconnect t 1000]end
    else keep s
  | _=>keep s end.
Definition begin_upload e f s := let t:=next_ticket s in
  let r:=UploadRequest e f in effects(with_next(N.succ t)(with_uploads(Loading t r::uploads s)s))[Upload t r].
Definition retry_upload t s :=
  if connected s then match find(ticket_matches t)(uploads s) with
  | Some(Failed _ a _) => begin_upload(upload_editor a)(upload_file a)(forget_upload t s)
  | _=>keep s end else keep s.
Definition finish_upload t result s :=
  match find(ticket_matches t)(uploads s) with
  | Some(Loading _ a) => match result with
    | inl error=>keep(with_uploads(map(settle t (inl error))(uploads s))s)
    | inr value=>ServiceResult(forget_upload t s)[] (Some(upload_editor a,value)) end
  | _=>keep s end.
Definition begin_directory e path trigger s := let t:=next_ticket s in
  effects(with_next(N.succ t)(with_directory(Loading t (DirectoryRequest e path trigger))path s))[ListDirectory t path e].
Definition service_step input s :=
  match input with
  | CommandAssessed ticket outcome =>
      let settle_assessment r:=match r with Loading current request=>
        if N.eqb ticket current then match outcome with
        |inl reason=>Failed current request reason
        |inr observation=>
          (* DEFENSE: An IO completion can name an action other than the one
             captured by its ticket; it must not become that action's verdict. *)
          if CommandAssessment.correlated request observation then Loaded current request observation
          else Failed current request "The action assessment reply does not match its request"
        end else r|_=>r end in
      keep(with_command_assessments(map settle_assessment(command_assessments s))s)
  | RetryAssessment e=>keep(forget_assessment e s)
  | WorkspaceGitCompleted t outcome => keep(with_workspace_git(settle t outcome(workspace_git s))s)
  | RestoreModelPreference raw =>
      match bind (TextJson.parse_json raw) ModelSelection.decode_preference with
      |Some preference => keep (with_model_preference (Some preference) s)
      |None => keep (with_storage_problem (Some "无法恢复本地模型偏好：存储内容无效。") s) end
  | StorageProblem message => keep (with_storage_problem (Some message) s)
  | DismissStorageProblem => keep (with_storage_problem None s)
  | OpenSettings=>effects(with_settings_return(Some "nav/settings")s)[Focus "settings"]
  | CloseSettings=>effects(with_settings_return None s)(match settings_return s with Some trigger=>[Focus(settings_focus_target trigger)]|None=>[]end)
  | Connect=>match connection s with Loading _ _|Loaded _ _ _=>keep s|_=>connect s end
  | Authenticated t r=>auth_result t r s
  | Disconnected t error _=>if ticket_matches t(connection s)then
      let ended:=end_connection error s in
      effects(with_connection(Failed t tt error)(service_state ended))
        (service_effects ended++[Reconnect t 1000])else keep s
  | RetryConnection t=>match connection s with Failed u _ _=>if N.eqb t u then connect s else keep s|_=>keep s end
  | ChooseAppearance a=>effects(with_theme a s)[SaveAppearance a]
  | AddFile e f=>if connected s then begin_upload e f s else keep s | RetryUpload t=>retry_upload t s
  | CancelUpload t=>effects(forget_upload t s)(match find(ticket_matches t)(uploads s)with Some(Loading _ _)=>[AbortUpload t]|_=>[]end)
  | Uploaded t r=>finish_upload t r s
  | OpenPreview f trigger=>let t:=next_ticket s in effects(with_next(N.succ t)(with_preview(Loading t(PreviewRequest f trigger))s))(release_preview s++[FetchPreview t f])
  | Previewed t r=>match preview s with
    | Loading current _=>if N.eqb t current then keep(with_preview(settle t r(preview s))s)else
      (* DEFENSE: A replaced preview fetch can return its allocated object URL after the new request owns the panel. *)
      effects s(match r with inr url=>[ReleasePreview url]|inl _=>[]end)
    |_=>
      (* DEFENSE: Closing a preview cannot synchronously stop its pending fetch from allocating an object URL. *)
      effects s(match r with inr url=>[ReleasePreview url]|inl _=>[]end)end
  | ClosePreview=>effects(with_preview Dormant s)(release_preview s++match preview s with Loading _ p|Loaded _ p _|Failed _ p _=>[Focus(preview_trigger p)]|Dormant=>[]end)
  | Download f=>effects s[DownloadFile f]
  | OpenDirectory e path trigger=>begin_directory e path trigger s
  | WriteDirectoryLocation v=>keep(with_directory(directory s)v s)
  | VisitDirectory path=>match directory s with Loading _ r|Loaded _ r _|Failed _ r _=>begin_directory(directory_editor r)path(directory_trigger r)s|Dormant=>keep s end
  | GoDirectory=>match directory s with Loading _ r|Loaded _ r _|Failed _ r _=>begin_directory(directory_editor r)(directory_location s)(directory_trigger r)s|Dormant=>keep s end
  | DirectoryListed t r=>keep(with_directory(settle t r(directory s))(directory_location s)s)
  | ChooseDirectory=>match directory s with Loaded _ r catalog=>effects(with_directory Dormant "" s)[DirectoryChosen(directory_editor r)(text "path" catalog);Focus(directory_trigger r)]|_=>keep s end
  | CloseDirectory=>effects(with_directory Dormant "" s)(match directory s with Loading _ r|Loaded _ r _|Failed _ r _=>[Focus(directory_trigger r)]|Dormant=>[]end)
  end.
Definition encode_unit (_:unit):json:=JNull.
Definition decode_unit(j:json):option unit:=match j with JNull=>Some tt|_=>None end.
Definition encode_services s := JObject[("connection",encode_resource encode_unit encode_unit(connection s));("settings_return",match settings_return s with None=>JNull|Some trigger=>JString trigger end);("appearance",JString(appearance_name(theme s)));("next",number(next_ticket s));("uploads",JArray(map(encode_resource encode_upload encode_attachment)(uploads s)));("preview",encode_resource encode_preview JString(preview s));("directory",encode_resource encode_directory(fun j=>j)(directory s));("directory_location",JString(directory_location s));("preparations",JArray(map encode_preparation(preparations s)));("workspace_git",encode_resource encode_git_request JBool(workspace_git s));("command_assessments",JArray(map(encode_resource CommandAssessment.encode_request CommandAssessment.encode_observation)(command_assessments s)));("model_preference",match model_preference s with None=>JNull|Some value=>preference_json value end);("storage_problem",match storage_problem s with None=>JNull|Some message=>JString message end)].
Definition decode_services j :=
  c<-bind(field "connection" j)(decode_resource decode_unit decode_unit);;o<-bind(field "settings_return" j)(fun value=>match value with JNull=>Some None|JString trigger=>Some(Some trigger)|_=>None end);;
  a<-bind(string_field "appearance" j)decode_appearance;;n<-natural_field "next" j;;
  u<-list_field(decode_resource decode_upload decode_attachment)"uploads" j;;
  p<-bind(field "preview" j)(decode_resource decode_preview as_string);;
  d<-bind(field "directory" j)(decode_resource decode_directory (fun j=>Some j));;
  l<-string_field "directory_location" j;;pref<-bind(field "model_preference" j)(fun value=>match value with JNull=>Some None|_=>option_map (@Some (string*string))(decode_preference value)end);;problem<-bind(field "storage_problem" j)(fun value=>match value with JNull=>Some None|JString message=>Some(Some message)|_=>None end);;ps<-list_field decode_preparation "preparations" j;;git<-bind(field "workspace_git" j)(decode_resource decode_git_request as_bool);;assessments<-list_field(decode_resource CommandAssessment.decode_request CommandAssessment.decode_observation)"command_assessments" j;;Some(Services c o a n u p d l pref problem ps git assessments).
Definition encode_effect e :=
  let effect kind fields:=JObject(("type",JString kind)::fields)in
  match e with
  | AssessCommand t request=>effect "assess_command"[("ticket",number t);("request",CommandAssessment.encode_request request)]
  | Authenticate t=>effect "authenticate"[("ticket",number t)]
  | Reconnect t delay=>effect "schedule_reconnect"[("ticket",number t);("milliseconds",number delay)]
  | SaveAppearance a=>effect "save_appearance"[("value",JString(appearance_name a))]
  | Upload t a=>effect "upload"[("ticket",number t);("editor",encode_editor(upload_editor a));("file",encode_file(upload_file a))]
  | AbortUpload t=>effect "abort_upload"[("ticket",number t)]
  | FetchPreview t a=>effect "preview"[("ticket",number t);("file",encode_attachment a)]
  | ReleasePreview url=>effect "release_preview"[("url",JString url)]
  | DownloadFile a=>effect "download"[("file",encode_attachment a)]
  | ObserveDirectories t workspace e=>effect "observe_directories"(task_observation_fields e[("ticket",number t);("workspace",workspace)])
  | ObserveWorkspaceGit t primary e=>effect "workspace_git"(task_observation_fields e[("ticket",number t);("primary",JString primary)])
  | ListDirectory t p e=>effect "list_directory"(task_observation_fields e[("ticket",number t);("path",JString p)])
  | DirectoryChosen e p=>effect "directory_chosen"[("editor",encode_editor e);("path",JString p)]
  | Focus t=>effect "focus"[("key",JString t)]end.
Definition decode_outcome {A} (decode:json->option A) (j:json) : option(sum string A):=
  ok<-bool_field "ok" j;;if ok then v<-bind(field "value" j)decode;;Some(inr v)else e<-string_field "error" j;;Some(inl e).
Definition service_input_decoders : list (string * (json -> option service_input)) := [
  ("command_assessed", fun j => t<-natural_field "ticket" j;;outcome<-decode_outcome CommandAssessment.decode_observation j;;Some(CommandAssessed t outcome));
  ("retry_assessment", fun j => option_map RetryAssessment(bind(field "editor" j)decode_editor));
  ("workspace_git_completed", fun j => t<-natural_field "ticket" j;;outcome<-decode_outcome as_bool j;;Some(WorkspaceGitCompleted t outcome));
  ("model_preference_restored", fun j => option_map RestoreModelPreference (string_field "value" j));
  ("storage_problem", fun j => option_map StorageProblem (string_field "message" j));
  ("dismiss_storage_problem", fun _ => Some DismissStorageProblem);
  ("open_settings", fun j => Some OpenSettings);
  ("close_settings", fun j => Some CloseSettings);
  ("connect", fun j => Some Connect);
  ("authenticated", fun j => t<-natural_field "ticket" j;;r<-decode_outcome decode_unit j;;Some(Authenticated t r));
  ("disconnected", fun j => t<-natural_field "ticket" j;;r<-string_field "error" j;;revoked<-bool_field "revoked" j;;Some(Disconnected t r revoked));
  ("retry_connection", fun j => t<-natural_field "ticket" j;;Some(RetryConnection t));
  ("appearance", fun j => a<-bind(string_field "value" j)decode_appearance;;Some(ChooseAppearance a));
  ("add_file", fun j => e<-bind(field "editor" j)decode_editor;;f<-bind(field "file" j)decode_file;;Some(AddFile e f));
  ("retry_upload", fun j => t<-natural_field "ticket" j;;Some(RetryUpload t));
  ("cancel_upload", fun j => t<-natural_field "ticket" j;;Some(CancelUpload t));
  ("uploaded", fun j => t<-natural_field "ticket" j;;r<-decode_outcome decode_attachment j;;Some(Uploaded t r));
  ("open_preview", fun j => a<-bind(field "file" j)decode_attachment;;t<-string_field "trigger" j;;Some(OpenPreview a t));
  ("previewed", fun j => t<-natural_field "ticket" j;;r<-decode_outcome as_string j;;Some(Previewed t r));
  ("close_preview", fun j => Some ClosePreview);
  ("download", fun j => a<-bind(field "file" j)decode_attachment;;Some(Download a));
  ("open_directory", fun j => e<-bind(field "editor" j)decode_editor;;p<-string_field "path" j;;t<-string_field "trigger" j;;Some(OpenDirectory e p t));
  ("write_directory", fun j => v<-string_field "value" j;;Some(WriteDirectoryLocation v));
  ("visit_directory", fun j => p<-string_field "path" j;;Some(VisitDirectory p));
  ("go_directory", fun j => Some GoDirectory);
  ("directory_listed", fun j => t<-natural_field "ticket" j;;r<-decode_outcome(fun v=>match v with JObject _=>Some v|_=>None end)j;;Some(DirectoryListed t r));
  ("choose_directory", fun j => Some ChooseDirectory);
  ("close_directory", fun j => Some CloseDirectory)
].
Definition decode_service_input j :=
  let fallback (_ : unit) := None in
  match string_field "type" j with
  | Some name => match find (fun entry => String.eqb (fst entry) name) service_input_decoders with
      | Some (_, decode) => decode j | None => fallback tt end
  | None => fallback tt
  end.
