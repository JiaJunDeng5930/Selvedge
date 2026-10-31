From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers TextJson.
From Selvedge.Programming Require Import Schema.
From Selvedge.Interaction Require Export Attachments Appearance.
From Selvedge.Interaction Require Import Codec Identity Resource ModelSelection.
From Selvedge.Interaction.Session Require Draft DraftCodec.
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
Definition directory_entry_schema := [Schema.Field "name" Schema.KText;Schema.Field "path" Schema.KText].
Definition directory_catalog_schema := [Schema.Field "ok" Schema.KBool;Schema.Field "path" Schema.KText;
 Schema.Field "parent" Schema.KJson;Schema.Field "entries" (Schema.KArray Schema.KJson);
 Schema.Field "truncated" Schema.KBool].
Definition valid_directory_entry value := match Schema.decode directory_entry_schema value with
 |Some _=>negb(String.eqb(text "name" value)"")&&Json.starts_with "/"(text "path" value)
 |None=>false end.
Definition decode_directory_catalog value : option json :=
 match Schema.decode directory_catalog_schema value with
 |None=>None
 |Some _=>if flag "ok" value && Json.starts_with "/"(text "path" value) &&
   (match field "parent" value with Some JNull=>true
    |Some(JString path)=>Json.starts_with "/" path|_=>false end) &&
   forallb valid_directory_entry(items "entries" value)
   then Some value else None end.
Definition directory_response value : sum string json :=
 match decode_directory_catalog value with
 |Some catalog=>inr catalog
 |None=>match Schema.decode [Schema.Field "ok" Schema.KBool;Schema.Field "error" Schema.KText] value with
   |Some _=>if negb(flag "ok" value)then inl(text "error" value)else inl "Invalid folder listing"
   |None=>inl "Invalid folder listing" end end.
Inductive preparation_intent := PreviewContext | CommitPrepared.
Record preparation := Preparation { preparation_draft:Draft.draft; preparation_generation:N;
 preparation_layer:N; preparation_trigger:string; preparation_intent_of:preparation_intent;
 preparation_preference:option(Schema.command_value Selvedge.Kernel.Commands.command_specs) }.
Record directory_observation := DirectoryObservation {
 observed_workspace:Selvedge.Kernel.Domain.workspace; observed_guidance:json }.
Definition encode_preparation p := JObject[("draft",DraftCodec.encode_draft(preparation_draft p));
 ("generation",number(preparation_generation p));("layer",number(preparation_layer p));("trigger",JString(preparation_trigger p));
 ("commit",JBool(match preparation_intent_of p with CommitPrepared=>true|_=>false end));
 ("preference",match preparation_preference p with None=>JNull|Some command=>Schema.encode_command command end)].
Definition decode_preparation j := d<-bind(field "draft" j)DraftCodec.decode_draft;;
 g<-natural_field "generation" j;;layer<-natural_field "layer" j;;trigger<-string_field "trigger" j;;commit<-bool_field "commit" j;;
 preference<-bind(field "preference" j)(fun value=>match value with JNull=>Some None
 |value=>option_map Some(Schema.decode_command Selvedge.Kernel.Commands.command_specs value)end);;
 Some(Preparation d g layer trigger(if commit then CommitPrepared else PreviewContext)preference).
Definition encode_directory_observation value:=JObject[("workspace",Selvedge.Kernel.Codec.workspace_json(observed_workspace value));("guidance",observed_guidance value)].
Definition decode_directory_observation value:=workspace<-bind(field "workspace" value)Selvedge.Kernel.Codec.parse_workspace;;guidance<-field "guidance" value;;
 match Selvedge.Kernel.Codec.parse_guidance workspace guidance with Some _=>Some(DirectoryObservation workspace guidance)|None=>None end.
Definition encode_git_request (r:editor*string) := JObject[("editor",encode_editor(fst r));("primary",JString(snd r))].
Definition decode_git_request j := e<-bind(field "editor" j)decode_editor;;p<-string_field "primary" j;;Some(e,p).
Inductive connection_observation :=
| ConnectionDormant
| ConnectionLoading (ticket:N)
| ConnectionReady (ticket:N)
| ConnectionFailed (ticket:N) (reason:string)
| ConnectionRevoked (ticket:N) (reason:string).
Definition connection_ticket observation := match observation with
 |ConnectionDormant=>None
 |ConnectionLoading ticket|ConnectionReady ticket|ConnectionFailed ticket _|ConnectionRevoked ticket _=>Some ticket end.
Definition connection_active observation := match observation with
 |ConnectionLoading _|ConnectionReady _=>true|_=>false end.
Definition connection_revoked observation := match observation with ConnectionRevoked _ _=>true|_=>false end.
Definition connection_matches ticket observation := match connection_ticket observation with
 |Some current=>N.eqb ticket current|None=>false end.
Definition encode_connection observation := match observation with
 |ConnectionDormant=>JObject[("status",JString "idle")]
 |ConnectionLoading ticket=>JObject[("status",JString "loading");("ticket",number ticket);("request",JNull)]
 |ConnectionReady ticket=>JObject[("status",JString "ready");("ticket",number ticket);("request",JNull);("value",JNull)]
 |ConnectionFailed ticket reason=>JObject[("status",JString "failed");("ticket",number ticket);("request",JNull);("error",JString reason)]
 |ConnectionRevoked ticket reason=>JObject[("status",JString "revoked");("ticket",number ticket);("request",JNull);("error",JString reason)] end.
Definition decode_connection value := match string_field "status" value with
 |Some "idle"=>Some ConnectionDormant
 |Some "loading"=>ticket<-natural_field "ticket" value;;request<-bind(field "request" value)(fun j=>match j with JNull=>Some tt|_=>None end);;Some(ConnectionLoading ticket)
 |Some "ready"=>ticket<-natural_field "ticket" value;;request<-bind(field "request" value)(fun j=>match j with JNull=>Some tt|_=>None end);;result<-bind(field "value" value)(fun j=>match j with JNull=>Some tt|_=>None end);;Some(ConnectionReady ticket)
 |Some "failed"=>ticket<-natural_field "ticket" value;;request<-bind(field "request" value)(fun j=>match j with JNull=>Some tt|_=>None end);;reason<-string_field "error" value;;Some(ConnectionFailed ticket reason)
 |Some "revoked"=>ticket<-natural_field "ticket" value;;request<-bind(field "request" value)(fun j=>match j with JNull=>Some tt|_=>None end);;reason<-string_field "error" value;;Some(ConnectionRevoked ticket reason)
 |_=>None end.
Record services := Services {
  connection:connection_observation; settings_return:option string; theme:appearance; next_ticket:N;
  uploads:list(resource upload_request attachment); preview:resource preview_request string;
  directory:resource directory_request json; directory_location:string;
  model_preference:option (string * string); storage_problem:option string;
  preparations:list(resource preparation directory_observation); workspace_git:resource (editor*string) bool;
  command_assessments:list(resource CommandAssessment.request CommandAssessment.observation) }.
Definition initial := Services ConnectionDormant None SystemAppearance 0 [] Dormant Dormant "" None None [] Dormant [].
Definition connected s := match connection s with ConnectionReady _ => true | _ => false end.
Definition retained_file_handles s := flat_map(fun resource=>match resource with
 |Loading _ request|Failed _ request _=>[file_handle(upload_file request)]
 |_=>[]end)(uploads s).
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
Definition assessment_editor_owned e (resource:resource CommandAssessment.request CommandAssessment.observation):=match resource_request resource with
|Some request=>match CommandAssessment.request_owner request with
 |CommandAssessment.DraftOwner owner|CommandAssessment.CandidateOwner owner _ _=>same_editor e owner
 |_=>false end|None=>false end.
Definition forget_assessment e s:=with_command_assessments(filter(fun resource=>negb(assessment_editor_owned e resource))(command_assessments s))s.
Definition preparation_owned e (resource:resource preparation directory_observation) :=match resource_request resource with
|Some request=>same_editor e(Draft.owner(preparation_draft request))|None=>false end.
Definition captured_preparation (resource:resource preparation directory_observation):=match resource with
|Loading _ request|Loaded _ request _=>match preparation_intent_of request with CommitPrepared=>true|PreviewContext=>false end
|_=>false end.
Definition replaceable_preparation e resource:=preparation_owned e resource && negb(captured_preparation resource).
Definition preparing e s := existsb(fun resource=>preparation_owned e resource &&
 captured_preparation resource)(preparations s).
Definition forget_preparation ticket s :=
 let s:=with_command_assessments(filter(fun resource=>match resource_request resource with
 |Some request=>match CommandAssessment.request_owner request with
  |CommandAssessment.PreparationOwner actual _=>negb(N.eqb ticket actual)|_=>true end
 |None=>true end)(command_assessments s))s in
 with_preparations(filter(fun resource=>
 match resource_ticket resource with Some actual=>negb(N.eqb ticket actual)|None=>true end)(preparations s))s.
Definition cancel_editor e s :=
 let s:=forget_assessment e s in
 let s:=with_preparations(filter(fun resource=>negb(replaceable_preparation e resource))(preparations s))s in
 match directory s with Loading _ request|Loaded _ request _|Failed _ request _=>
   if same_editor e(directory_editor request)then with_directory Dormant "" s else s|Dormant=>s end.
Definition upload_owner (r:resource upload_request attachment) := match r with Dormant=>None|Loading _ a|Loaded _ a _|Failed _ a _=>Some(upload_editor a) end.
Definition blocks e s := existsb(fun r=>match upload_owner r with Some owner=>same_editor e owner|None=>false end)(uploads s).
Definition ticket_matches {A B} (ticket:N) (resource:resource A B) :=
 match resource_ticket resource with Some current=>N.eqb ticket current|None=>false end.
Definition connection_ticket_matches (t:N) (observation:connection_observation) := connection_matches t observation.
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
| Authenticate(ticket:N) | Reconnect(ticket:N)(milliseconds:N) | InvalidateSource
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
  effects(with_next(N.succ t)(with_connection(ConnectionLoading t)clean))
    (service_effects ended++[Authenticate t]).
Definition auth_result t (result:sum string unit) s :=
  match connection s with
  | ConnectionLoading u => if N.eqb t u then
      let observation:=match result with inl error=>ConnectionFailed t error|inr _=>ConnectionReady t end in
      let s':=with_connection observation s in
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
  | OpenSettings=>effects(with_settings_return(Some "nav/settings")s)[]
  | CloseSettings=>effects(with_settings_return None s)(match settings_return s with Some trigger=>[Focus(settings_focus_target trigger)]|None=>[]end)
  | Connect=>connect s
  | Authenticated t r=>auth_result t r s
  | Disconnected t error revoked=>if connection_active(connection s)&&connection_ticket_matches t(connection s)then
      let ended:=end_connection error s in
      let observation:=if revoked then ConnectionRevoked t error else ConnectionFailed t error in
      effects(with_connection observation(service_state ended))
        (service_effects ended++(if revoked then [InvalidateSource] else [])++[Reconnect t 1000])else keep s
  | RetryConnection t=>match connection s with
      |ConnectionFailed u _|ConnectionRevoked u _=>if N.eqb t u then connect s else keep s
      |_=>keep s end
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
  | DirectoryListed t r=>let ready:=settle t r(directory s)in
    let location:=match directory s,ready with
    |Loading _ _,Loaded _ _ catalog=>text "path" catalog
    |_,_=>directory_location s end in keep(with_directory ready location s)
  | ChooseDirectory=>match directory s with Loaded _ r catalog=>effects(with_directory Dormant "" s)[DirectoryChosen(directory_editor r)(text "path" catalog);Focus(directory_trigger r)]|_=>keep s end
  | CloseDirectory=>effects(with_directory Dormant "" s)(match directory s with Loading _ r|Loaded _ r _|Failed _ r _=>[Focus(directory_trigger r)]|Dormant=>[]end)
  end.
Definition encode_unit (_:unit):json:=JNull.
Definition decode_unit(j:json):option unit:=match j with JNull=>Some tt|_=>None end.
Definition encode_services s := JObject[("connection",encode_connection(connection s));("settings_return",match settings_return s with None=>JNull|Some trigger=>JString trigger end);("appearance",JString(appearance_name(theme s)));("next",number(next_ticket s));("uploads",JArray(map(encode_resource encode_upload encode_attachment)(uploads s)));("preview",encode_resource encode_preview JString(preview s));("directory",encode_resource encode_directory(fun j=>j)(directory s));("directory_location",JString(directory_location s));("preparations",JArray(map(encode_resource encode_preparation encode_directory_observation)(preparations s)));("workspace_git",encode_resource encode_git_request JBool(workspace_git s));("command_assessments",JArray(map(encode_resource CommandAssessment.encode_request CommandAssessment.encode_observation)(command_assessments s)));("model_preference",match model_preference s with None=>JNull|Some value=>preference_json value end);("storage_problem",match storage_problem s with None=>JNull|Some message=>JString message end)].
Definition decode_services j :=
  c<-bind(field "connection" j)decode_connection;;o<-bind(field "settings_return" j)(fun value=>match value with JNull=>Some None|JString trigger=>Some(Some trigger)|_=>None end);;
  a<-bind(string_field "appearance" j)decode_appearance;;n<-natural_field "next" j;;
  u<-list_field(decode_resource decode_upload decode_attachment)"uploads" j;;
  p<-bind(field "preview" j)(decode_resource decode_preview as_string);;
  d<-bind(field "directory" j)(decode_resource decode_directory decode_directory_catalog);;
  l<-string_field "directory_location" j;;pref<-bind(field "model_preference" j)(fun value=>match value with JNull=>Some None|_=>option_map (@Some (string*string))(decode_preference value)end);;problem<-bind(field "storage_problem" j)(fun value=>match value with JNull=>Some None|JString message=>Some(Some message)|_=>None end);;ps<-list_field(decode_resource decode_preparation decode_directory_observation) "preparations" j;;git<-bind(field "workspace_git" j)(decode_resource decode_git_request as_bool);;assessments<-list_field(decode_resource CommandAssessment.decode_request CommandAssessment.decode_observation)"command_assessments" j;;Some(Services c o a n u p d l pref problem ps git assessments).
Definition encode_effect e :=
  let effect kind fields:=JObject(("type",JString kind)::fields)in
  match e with
  | AssessCommand t request=>effect "assess_command"[("ticket",number t);("request",CommandAssessment.encode_request request)]
  | InvalidateSource=>effect "invalidate_source"[]
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
Definition decode_directory_outcome value :=
 outcome<-decode_outcome(fun value=>Some value)value;;
 Some(match outcome with inl reason=>inl reason|inr catalog=>directory_response catalog end).
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
  ("directory_listed", fun j => t<-natural_field "ticket" j;;r<-decode_directory_outcome j;;Some(DirectoryListed t r));
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
