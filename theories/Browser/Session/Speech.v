From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Programming Require Import Schema.
From Selvedge.Kernel Require Import Commands.
From Selvedge.Interaction Require Import Codec Identity.
From Selvedge.Browser.Session Require Import Services.
From Selvedge.Interaction.Submission Require Fields Parameters.
Import ListNotations.
Open Scope string_scope.
Record connection := Connection { connection_id:string; connection_label:string; asr:bool; voice:bool }.
Record target := Target { target_editor:editor; target_revision:N; selection_start:N; selection_end:N }.
Inductive activity := Idle | Acquiring(ticket:N)(owner:editor)(revision:N)
| Recording(ticket:N)(capture:target) | Transcribing(ticket:N)(capture:target)
| Retained(capture:target)(text:string) | CreatingTask(ticket:N)(origin:editor)(revision generation:N)
| ConnectingVoice(ticket task:N) | Voice(ticket task:N)(input_muted output_muted:bool).
Inductive login_method := DeviceCode | BrowserTab.
Inductive login_phase := ChooseMethod | StartingLogin(ticket:N)(method:login_method)
| BrowserOpened(ticket:N)
| DeviceCodeShown(ticket:N)(url code expires:string)(copied:option bool)
| SignInFailed(method:login_method)(reason:string) | SignedIn.
Record login := Login { login_occurrence:N; login_trigger:string; login_stage:login_phase }.
Inductive login_outcome := Authenticated | Rejected(reason:string) | Cancelled | Expired.
Record speech := Speech {
 connections:list connection; selected:option string; next:N; current:activity;
 notice:string; live_text:string; sign_in:option login
}.
Definition initial := Speech [] None 0 Idle "" "" None.
Definition active_ticket a := match a with Acquiring t _ _|Recording t _|Transcribing t _|CreatingTask t _ _ _|ConnectingVoice t _|Voice t _ _ _=>Some t|_=>None end.
Definition owns t a := match active_ticket a with Some u=>N.eqb t u|None=>false end.
Definition with_activity a s := Speech(connections s)(selected s)(next s)a(notice s)(live_text s)(sign_in s).
Definition with_notice n s := Speech(connections s)(selected s)(next s)(current s)n(live_text s)(sign_in s).
Definition idle_with_notice message s := Speech(connections s)(selected s)(next s)Idle message ""(sign_in s).
Definition with_next n s := Speech(connections s)(selected s)n(current s)(notice s)(live_text s)(sign_in s).
Definition with_login value s := Speech(connections s)(selected s)(next s)(current s)(notice s)(live_text s)value.
Definition at_phase phase dialog s :=
 with_login (Some(Login(login_occurrence dialog)(login_trigger dialog)phase))s.
Definition capable (realtime:bool) (c:connection) := if realtime then voice c else asr c.
Definition eligible realtime s :=
  match selected s with Some id=>find(fun c=>String.eqb id(connection_id c)&&capable realtime c)(connections s)
  |None=>find(capable realtime)(connections s)end.
Inductive speech_input := Authorize(trigger:string) | ChooseLogin(method:login_method) | ReturnToMethods | CloseLogin
| LoginBrowserOpened(ticket:N) | LoginCodeReceived(ticket:N)(url code expires:string)
| LoginFinished(ticket:N)(outcome:login_outcome) | CopyLoginCode(key:string) | LoginCopyFinished(ticket:N)(copied:bool)
| Refresh | Capabilities(values:list connection) | CapabilitiesFailed(error:string)
| Select(id:string) | BeginDictation(owner:editor)(revision:N) | Captured(ticket start finish:N)
| FinishDictation | Transcribed(ticket:N)(text:string) | InsertTranscript | DismissTranscript
| BeginVoice(task:N) | BeginNewVoice(origin:editor)(revision generation:N)(command:command_value command_specs) | TaskCreated(ticket task:N) | VoiceReady(ticket:N)
| LiveText(ticket:N)(text:string) | ToggleInputMute | ToggleOutputMute | Cancel
| Failed(ticket:N)(reason:string) | Ended(ticket:N)(reason:string) | Released.
Inductive speech_effect := AudioLogin(ticket:N)(method:login_method) | ReleaseLogin(ticket:N)
| CopyDeviceCode(ticket:N)(key code:string) | LoadCapabilities | RecordAudio(ticket:N)(owner:editor)
| Transcribe(ticket:N)(connection:string) | Release(ticket:N) | CreateTask(ticket:N)(command:command_value command_specs)
| ConnectVoice(ticket:N)(connection:string)(task:N) | SetInputMute(ticket:N)(muted:bool) | SetOutputMute(ticket:N)(muted:bool).
Record speech_result := SpeechResult { speech_state:speech; speech_effects:list speech_effect; transcript:option(target*string) }.
Definition keep s:=SpeechResult s[]None.
Definition result s es:=SpeechResult s es None.
Definition free s:=match current s with Idle=>true|_=>false end.
Definition release s:=match active_ticket(current s)with Some t=>[Release t]|None=>[]end.
Definition can_authorize s:=free s && match connections s,sign_in s with [],None=>true|_,_=>false end.
Definition login_attempt stage:=match stage with
 |StartingLogin ticket method=>Some(ticket,method)
 |BrowserOpened ticket=>Some(ticket,BrowserTab)
 |DeviceCodeShown ticket _ _ _ _=>Some(ticket,DeviceCode)
 |_=>None end.
Definition release_login dialog:=
 match login_attempt(login_stage dialog)with Some(ticket,_)=>[ReleaseLogin ticket]|None=>[]end.
Definition close_login s:=match sign_in s with
 |Some dialog=>result(with_login None s)(release_login dialog)
 |None=>keep s end.
Definition observe_login receipt f s:=match sign_in s with
 |Some dialog=>match login_attempt(login_stage dialog)with
   |Some(ticket,method)=>if N.eqb receipt ticket then f dialog method else keep s
   |None=>keep s end
 |None=>keep s end.
Definition start_login method dialog s:=
 let ticket:=next s in result(at_phase(StartingLogin ticket method)dialog(with_next(N.succ ticket)s))[AudioLogin ticket method].
Definition begin_dictation e revision s :=
  (* DEFENSE: Native inputs can name settings editors with no message field;
     recording there cannot produce an insertable transcript. *)
  if existsb(fun field=>if Parameters.field_eq_dec field Fields.MessageText then true else false)(Parameters.fields e) && free s then match eligible false s with
  |Some _=>let t:=next s in result(with_next(N.succ t)(with_activity(Acquiring t e revision)(with_notice "" s)))[RecordAudio t e]
  |None=>keep s end else keep s.
Definition begin_voice task s :=
  if free s then match eligible true s with
  |Some c=>let t:=next s in result(with_next(N.succ t)(with_activity(ConnectingVoice t task)(with_notice "" s)))[ConnectVoice t(connection_id c)task]
  |None=>keep s end else keep s.
Definition speech_step input s :=
  match input with
  |Authorize trigger=>if can_authorize s then
    let ticket:=next s in keep(with_login(Some(Login ticket trigger ChooseMethod))(with_next(N.succ ticket)s))
    else keep s
  |ChooseLogin method=>match sign_in s with
    |Some dialog=>match login_stage dialog with
       |ChooseMethod|SignInFailed _ _=>start_login method dialog s
       |_=>keep s end
    |None=>keep s end
  |ReturnToMethods=>match sign_in s with
    |Some dialog=>match login_stage dialog with
       |BrowserOpened _|DeviceCodeShown _ _ _ _ _|SignInFailed _ _=>
         result(at_phase ChooseMethod dialog s)(release_login dialog)
       |_=>keep s end
    |None=>keep s end
  |CloseLogin=>close_login s
  |LoginBrowserOpened ticket=>observe_login ticket (fun dialog _=>
    match login_stage dialog with
    |StartingLogin _ BrowserTab=>keep(at_phase(BrowserOpened ticket)dialog s)
    |_=>keep s end)s
  |LoginCodeReceived ticket url code expires=>observe_login ticket(fun dialog _=>
    match login_stage dialog with
    |StartingLogin _ DeviceCode=>keep(at_phase(DeviceCodeShown ticket url code expires None)dialog s)
    |_=>keep s end)s
  |LoginFinished ticket outcome=>observe_login ticket(fun dialog method=>
    match outcome with
    |Authenticated=>result(at_phase SignedIn dialog s)[LoadCapabilities]
    |Rejected reason=>keep(at_phase(SignInFailed method reason)dialog s)
    |Cancelled=>keep(at_phase(SignInFailed method "Sign-in was cancelled.")dialog s)
    |Expired=>keep(at_phase(SignInFailed method "The device code expired.")dialog s)
    end)s
  |CopyLoginCode key=>match sign_in s with
    |Some dialog=>match login_stage dialog with
       |DeviceCodeShown ticket _ code _ _=>result s[CopyDeviceCode ticket key code]
       |_=>keep s end
    |None=>keep s end
  |LoginCopyFinished ticket copied=>observe_login ticket(fun dialog _=>
    match login_stage dialog with
    |DeviceCodeShown _ url code expires _=>keep(at_phase(DeviceCodeShown ticket url code expires(Some copied))dialog s)
    |_=>keep s end)s
  |Refresh=>result s[LoadCapabilities]
  |Capabilities cs=>let available:=fun c=>asr c||voice c in
      let first:=option_map connection_id(find available cs)in
      let chosen:=match selected s with Some id=>if existsb(fun c=>String.eqb id(connection_id c)&&available c)cs then Some id else first|None=>first end in
      let updated:=Speech cs chosen(next s)(current s)""(live_text s)(sign_in s) in
      match cs,sign_in s with
      | _::_,Some dialog=>match login_stage dialog with
        |BrowserOpened ticket=>result(at_phase SignedIn dialog updated)[ReleaseLogin ticket]
        |ChooseMethod=>keep(at_phase SignedIn dialog updated)
        |_=>keep updated end
      |_,_=>keep updated end
  |CapabilitiesFailed e=>keep(with_notice e s)
  |Select id=>if free s && existsb(fun c=>String.eqb id(connection_id c)&&(asr c||voice c))(connections s)then keep(Speech(connections s)(Some id)(next s)(current s)""(live_text s)(sign_in s))else keep s
  |BeginDictation e rev=>begin_dictation e rev s
  |Captured t start finish=>match current s with Acquiring u e rev=>if N.eqb t u then keep(with_activity(Recording t(Target e rev start finish))s)else keep s|_=>keep s end
  |FinishDictation=>match current s,eligible false s with Recording t capture,Some c=>result(with_activity(Transcribing t capture)s)[Transcribe t(connection_id c)]|_,_=>keep s end
  |Transcribed t text=>match current s with Transcribing u capture=>if N.eqb t u then SpeechResult(with_activity(Retained capture text)s)[Release t](Some(capture,text))else keep s|_=>keep s end
  |InsertTranscript=>match current s with Retained capture text=>SpeechResult s[](Some(capture,text))|_=>keep s end
  |DismissTranscript=>match current s with Retained _ _=>keep(with_activity Idle s)|_=>keep s end
  |BeginVoice task=>begin_voice task s
  |BeginNewVoice origin revision generation command=>if free s then match eligible true s with Some _=>let t:=next s in result(with_next(N.succ t)(with_activity(CreatingTask t origin revision generation)(with_notice "" s)))[CreateTask t command]|None=>keep s end else keep s
  |TaskCreated t task=>match current s with CreatingTask u _ _ _=>if N.eqb t u then
    match eligible true s with Some connection=>result(with_activity(ConnectingVoice t task)(with_notice "" s))[ConnectVoice t(connection_id connection)task]|None=>keep s end
    else keep s|_=>keep s end
  |VoiceReady t=>match current s with ConnectingVoice u task=>if N.eqb t u then keep(with_activity(Voice t task false false)s)else keep s|_=>keep s end
  |LiveText t text=>if owns t(current s)then keep(Speech(connections s)(selected s)(next s)(current s)(notice s)text(sign_in s))else keep s
  |ToggleInputMute=>match current s with Voice t task mic out=>result(with_activity(Voice t task(negb mic)out)s)[SetInputMute t(negb mic)]|_=>keep s end
  |ToggleOutputMute=>match current s with Voice t task mic out=>result(with_activity(Voice t task mic(negb out))s)[SetOutputMute t(negb out)]|_=>keep s end
  |Cancel=>result(idle_with_notice "" s)(release s)
  |Failed t e|Ended t e=>if owns t(current s)then result(idle_with_notice e s)(release s)else keep s
  |Released=>keep s
  end.
Definition acknowledge s := with_activity Idle s.
Definition encode_connection c:=JObject[("id",JString(connection_id c));("label",JString(connection_label c));("asr",JBool(asr c));("voice",JBool(voice c))].
Definition decode_connection j:=id<-string_field "id" j;;l<-string_field "label" j;;a<-bool_field "asr" j;;v<-bool_field "voice" j;;Some(Connection id l a v).
Definition encode_target t:=JObject[("editor",encode_editor(target_editor t));("revision",number(target_revision t));("start",number(selection_start t));("end",number(selection_end t))].
Definition decode_target j:=e<-bind(field "editor" j)decode_editor;;r<-natural_field "revision" j;;s<-natural_field "start" j;;f<-natural_field "end" j;;Some(Target e r s f).
Definition encode_activity a :=
  let record kind fields:=JObject(("kind",JString kind)::fields)in
  match a with Idle=>record "idle"[]|Acquiring t e rev=>record "acquiring"[("ticket",number t);("editor",encode_editor e);("revision",number rev)]
  |Recording t c=>record "recording"[("ticket",number t);("target",encode_target c)]
  |Transcribing t c=>record "transcribing"[("ticket",number t);("target",encode_target c)]
  |Retained c text=>record "retained"[("target",encode_target c);("text",JString text)]
  |CreatingTask t e revision generation=>record "creating_task"[("ticket",number t);("editor",encode_editor e);("revision",number revision);("generation",number generation)]
  |ConnectingVoice t task=>record "connecting_voice"[("ticket",number t);("task_id",number task)]
  |Voice t task mic out=>record "voice"[("ticket",number t);("task_id",number task);("input_muted",JBool mic);("output_muted",JBool out)]end.
Definition decode_activity j:=match string_field "kind" j with
  |Some "idle"=>Some Idle|Some "acquiring"=>t<-natural_field "ticket" j;;e<-bind(field "editor" j)decode_editor;;r<-natural_field "revision" j;;Some(Acquiring t e r)
  |Some "recording"=>t<-natural_field "ticket" j;;c<-bind(field "target" j)decode_target;;Some(Recording t c)
  |Some "transcribing"=>t<-natural_field "ticket" j;;c<-bind(field "target" j)decode_target;;Some(Transcribing t c)
  |Some "retained"=>c<-bind(field "target" j)decode_target;;s<-string_field "text" j;;Some(Retained c s)
  |Some "creating_task"=>t<-natural_field "ticket" j;;e<-bind(field "editor" j)decode_editor;;r<-natural_field "revision" j;;g<-natural_field "generation" j;;Some(CreatingTask t e r g)
  |Some "connecting_voice"=>t<-natural_field "ticket" j;;task<-natural_field "task_id" j;;Some(ConnectingVoice t task)
  |Some "voice"=>t<-natural_field "ticket" j;;task<-natural_field "task_id" j;;mic<-bool_field "input_muted" j;;out<-bool_field "output_muted" j;;Some(Voice t task mic out)
  |_=>None end.
Definition login_method_name method:=match method with DeviceCode=>"device_code"|BrowserTab=>"browser"end.
Definition decode_login_method method:=match method with "device_code"=>Some DeviceCode|"browser"=>Some BrowserTab|_=>None end.
Definition encode_login_phase phase:=
 let record kind fields:=JObject(("kind",JString kind)::fields)in
 match phase with
 |ChooseMethod=>record "choose"[]
 |StartingLogin ticket method=>record "starting"[("ticket",number ticket);("method",JString(login_method_name method))]
 |BrowserOpened ticket=>record "browser_opened"[("ticket",number ticket)]
 |DeviceCodeShown ticket url code expires copied=>record "device_code"
  [("ticket",number ticket);("url",JString url);("code",JString code);("expires",JString expires);
   ("copied",match copied with None=>JNull|Some value=>JBool value end)]
 |SignInFailed method reason=>record "failed"[("method",JString(login_method_name method));("reason",JString reason)]
 |SignedIn=>record "signed_in"[]
 end.
Definition decode_login_phase j:=
 let method:=bind(string_field "method" j)decode_login_method in
 match string_field "kind" j with
 |Some "choose"=>Some ChooseMethod
 |Some "starting"=>ticket<-natural_field "ticket" j;;m<-method;;Some(StartingLogin ticket m)
 |Some "browser_opened"=>option_map BrowserOpened(natural_field "ticket" j)
 |Some "device_code"=>
   ticket<-natural_field "ticket" j;;url<-string_field "url" j;;code<-string_field "code" j;;
   expires<-string_field "expires" j;;Some(DeviceCodeShown ticket url code expires(bool_field "copied" j))
 |Some "failed"=>m<-method;;reason<-string_field "reason" j;;Some(SignInFailed m reason)
 |Some "signed_in"=>Some SignedIn
 |_=>None end.
Definition encode_login value:=JObject[("occurrence",number(login_occurrence value));
 ("trigger",JString(login_trigger value));("phase",encode_login_phase(login_stage value))].
Definition decode_login j:=occurrence<-natural_field "occurrence" j;;trigger<-string_field "trigger" j;;
 phase<-bind(field "phase" j)decode_login_phase;;Some(Login occurrence trigger phase).
Definition encode_speech s:=JObject[("connections",JArray(map encode_connection(connections s)));
 ("selected",match selected s with None=>JNull|Some id=>JString id end);("next",number(next s));
 ("activity",encode_activity(current s));("notice",JString(notice s));("live_text",JString(live_text s));
 ("sign_in",match sign_in s with None=>JNull|Some value=>encode_login value end)].
Definition decode_speech j:=
 cs<-list_field decode_connection "connections" j;;
 selected<-bind(field "selected" j)(fun j=>match j with JNull=>Some None|JString s=>Some(Some s)|_=>None end);;
 n<-natural_field "next" j;;a<-bind(field "activity" j)decode_activity;;
 notice<-string_field "notice" j;;live<-string_field "live_text" j;;
 login<-bind(field "sign_in" j)(fun j=>match j with JNull=>Some None|_=>option_map Some(decode_login j)end);;
 Some(Speech cs selected n a notice live login).
Definition encode_effect e :=
  let record kind fields:=JObject(("type",JString kind)::fields)in
  match e with
  |AudioLogin ticket method=>record "audio_login"[("ticket",number ticket);("method",JString(login_method_name method))]
  |ReleaseLogin ticket=>record "release_audio_login"[("ticket",number ticket)]
  |CopyDeviceCode ticket key code=>record "copy_audio_login_code"[("ticket",number ticket);("key",JString key);("code",JString code)]
  |LoadCapabilities=>record "audio_capabilities"[]
  |RecordAudio t owner=>record "record_audio"[("ticket",number t);("editor",encode_editor owner)]
  |Transcribe t c=>record "transcribe_audio"[("ticket",number t);("connection",JString c)]
  |Release t=>record "release_audio"[("ticket",number t)]
  |CreateTask t command=>record "voice_create_task"[("ticket",number t);("command",encode_command command)]
  |ConnectVoice t c task=>record "connect_voice"[("ticket",number t);("connection",JString c);("task_id",number task)]
  |SetInputMute t mic=>record "voice_input_mute"[("ticket",number t);("muted",JBool mic)]
  |SetOutputMute t out=>record "voice_output_mute"[("ticket",number t);("muted",JBool out)]end.
Definition decode_login_outcome j:=match string_field "status" j with
 |Some "signed_in"=>Some Authenticated
 |Some "failed"=>option_map Rejected(string_field "error" j)
 |Some "cancelled"=>Some Cancelled
 |Some "expired"=>Some Expired
 |_=>None end.
Definition decode_input j := match string_field "type" j with
  |Some "audio_login_browser_opened"=>option_map LoginBrowserOpened(natural_field "ticket" j)
  |Some "audio_login_code_received"=>ticket<-natural_field "ticket" j;;url<-string_field "url" j;;
    code<-string_field "code" j;;expires<-string_field "expires" j;;Some(LoginCodeReceived ticket url code expires)
  |Some "audio_login_finished"=>ticket<-natural_field "ticket" j;;outcome<-decode_login_outcome j;;Some(LoginFinished ticket outcome)
  |Some "audio_login_copy_finished"=>ticket<-natural_field "ticket" j;;copied<-bool_field "copied" j;;Some(LoginCopyFinished ticket copied)
  |Some "audio_refresh"=>Some Refresh
  |Some "audio_capabilities"=>option_map Capabilities(list_field decode_connection "connections" j)
  |Some "audio_capabilities_failed"=>option_map CapabilitiesFailed(string_field "error" j)
  |Some "audio_select"=>option_map Select(string_field "value" j)
  |Some "dictate"=>e<-bind(field "editor" j)decode_editor;;r<-natural_field "revision" j;;Some(BeginDictation e r)
  |Some "audio_captured"=>t<-natural_field "ticket" j;;s<-natural_field "start" j;;f<-natural_field "end" j;;Some(Captured t s f)
  |Some "finish_dictation"=>Some FinishDictation
  |Some "audio_transcribed"=>t<-natural_field "ticket" j;;s<-string_field "text" j;;Some(Transcribed t s)
  |Some "insert_transcript"=>Some InsertTranscript|Some "dismiss_transcript"=>Some DismissTranscript
  |Some "begin_voice"=>option_map BeginVoice(natural_field "task_id" j)
  |Some "begin_new_voice"=>e<-bind(field "editor" j)decode_editor;;r<-natural_field "revision" j;;g<-natural_field "generation" j;;c<-bind(field "command" j)(decode_command command_specs);;Some(BeginNewVoice e r g c)
  |Some "voice_task_created"=>t<-natural_field "ticket" j;;task<-natural_field "task_id" j;;Some(TaskCreated t task)
  |Some "voice_ready"=>option_map VoiceReady(natural_field "ticket" j)
  |Some "voice_text"=>t<-natural_field "ticket" j;;s<-string_field "text" j;;Some(LiveText t s)
  |Some "voice_input_mute"=>Some ToggleInputMute|Some "voice_output_mute"=>Some ToggleOutputMute
  |Some "audio_cancel"=>Some Cancel
  |Some "audio_failed"=>t<-natural_field "ticket" j;;s<-string_field "error" j;;Some(Failed t s)
  |Some "audio_ended"=>t<-natural_field "ticket" j;;s<-string_field "error" j;;Some(Ended t s)
  |Some "audio_released"=>Some Released|_=>None end.

Theorem cancellation_releases_owned_microphone s :
 speech_effects(speech_step Cancel s)=release s /\
 current(speech_state(speech_step Cancel s))=Idle.
Proof. destruct s;cbn;simpl;split;reflexivity. Qed.

Theorem matching_transcription_retains_capture cs selected next ticket capture notice live text login :
 let result:=speech_step(Transcribed ticket text)(Speech cs selected next(Transcribing ticket capture)notice live login)in
 current(speech_state result)=Retained capture text /\
 transcript result=Some(capture,text) /\ speech_effects result=[Release ticket].
Proof. cbn;rewrite N.eqb_refl;repeat split;reflexivity. Qed.

Theorem stale_transcription_preserves_capture s selected next expected ticket capture notice live text login :
 N.eqb ticket expected=false ->
 speech_step(Transcribed ticket text)(Speech s selected next(Transcribing expected capture)notice live login)=
 keep(Speech s selected next(Transcribing expected capture)notice live login).
Proof. intro stale;cbn;rewrite stale;reflexivity. Qed.
