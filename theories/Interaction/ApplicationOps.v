From Selvedge.Kernel Require Import WorkspaceBackend.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers Schema.
From Selvedge.Kernel Require Import Commands Streams Codec.
From Selvedge.Kernel Require Search.
From Selvedge.Interaction Require Import Codec Identity Resource Services Forms Speech ApplicationState.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Inductive effect := Execute(ticket:N)(command:public_command) | Service(effect:service_effect)
| FollowLatest(task:N) | PersistModelPreference(profile effort:string)
| Audio(effect:speech_effect) | Focus(key:string) | ScrollTo(task message:N)
| LanguageEffect(value:Selvedge.Interaction.Interactive.Types.effect) | LoadSkills(owner:editor)(ticket:N)(workspace:json) | SelectionBytes(key:string)(position:N).
Record result := Result { resulting_state:state; emitted:list effect; reply:json }.
Definition keep s:=Result s[]JNull.
Definition reject code message s:=Result s[](failure code message).
Definition effects s es:=Result s es JNull.
Definition push_effects es result:=Result(resulting_state result)(es++emitted result)(reply result).
Definition encode_effect e:=match e with
|FollowLatest task=>JObject[("type",JString "follow_latest");("key",JString("conversation/"++show_natural task++"/history"))]
|PersistModelPreference profile effort=>JObject[("type",JString "persist_model_preference");("profile",JString profile);("reasoning",JString effort)]
|Execute t c=>JObject[("type",JString "command");("ticket",number t);("command",encode_command c)]
|Service e=>Services.encode_effect e|Audio e=>Speech.encode_effect e
|Focus key=>JObject[("type",JString "focus");("key",JString key)]
|ScrollTo t i=>JObject[("type",JString "scroll_to_message");("task_id",number t);("message_index",number i);("key",JString(history_key t i))]
|LanguageEffect e=>Selvedge.Interaction.Interactive.Types.encode_effect e|LoadSkills e t w=>JObject(task_observation_fields e[("type",JString "skill_catalog");("editor",encode_editor e);("ticket",number t);("workspace",w)])
|SelectionBytes key p=>JObject[("type",JString "selection_bytes");("key",JString key);("start",number p);("end",number p)] end.
Definition encode_result r:=JObject[("state",encode_state(resulting_state r));("effects",JArray(map encode_effect(emitted r)));("reply",reply r)].
Definition queue_command c purpose s :=
  let a:=authoring_state s in let t:=next a in
  effects(set_pending(Pending t c purpose::awaiting a)(N.succ t)s)[Execute t c].
Definition issue source purpose s :=
  if connected(service_state s)then match decode_command command_specs source with Some c=>queue_command c purpose s|None=>reject "InvalidCommand" "The command does not match the public protocol" s end
  else reject "Disconnected" "Connect to continue" s.
Definition initialized_profile d world := match first_profile world with
|None=>Some d|Some profile=>match owner d with NewTask _|Agent _=>restore_fields[("profile",JString profile);("reasoning",JString "default")]d|_=>Some d end end.
Fixpoint restore_snapshot fields source d := match fields with []=>Some d|f::rest=>
  match field(field_name(specification f))source with
  |None=>restore_snapshot rest source d|Some value=>d'<-restore_field(field_name(specification f))value d;;restore_snapshot rest source d' end end.
Definition context_snapshot settings :=
 let workspace:=value_or JNull(field "workspace" settings)in
 let sandbox:=value_or JNull(field "sandbox" settings)in
 let approval:=value_or JNull(field "approval" settings)in
 JObject(object_fields workspace++
  [("project_id",value_or JNull(field "project_id" settings));
   ("sandbox",value_or JNull(field "mode" sandbox));
   ("network_access",value_or JNull(field "network_access" sandbox));
   ("approval",value_or JNull(field "mode" approval));
   ("reviewer_profile",value_or JNull(field "reviewer_profile" approval))]).
Definition initialize e world :=
  d<-match e with
   |Agent None=>restore_field "concurrency"(number 1)(new_draft e)
   |Fork _=>restore_field "child_count"(number 1)(new_draft e)
   |_=>Some(new_draft e)end;;
  let source:=match e with
  |Message id=>find_task id world
  |Project(Some id)=>find_project id world
  |Card(Some id)=>find_world "cards" "card_id" id(value_or JNull(field "board" world))
  |Agent(Some id)=>find_world "agents" "agent_id" id(value_or JNull(field "board" world))
  |TaskGraph(Some id) _=>find_world "graphs" "graph_id" id world
  |WorkName id=>find_work id world
  |TitlePrompts=>field "title_settings" world
  |_=>None end in
  d<-initialized_profile d world;;
  match source with None=>match e with Message _|Project(Some _)|Card(Some _)|Agent(Some _)|TaskGraph(Some _) _|WorkName _=>None|_=>Some d end|Some source=>
    let source:=match e with
    |Project _=>match field "workspace" source with Some(JObject ws)=>JObject(object_fields source++ws)|_=>source end
    |Agent _=>JObject(object_fields source++object_fields(context_snapshot(value_or JNull(field "settings" source))))
    |Message _=>let settings:=value_or JNull(field "settings" source)in
      let sandbox:=value_or JNull(field "sandbox" settings)in let approval:=value_or JNull(field "approval" settings)in
      JObject(object_fields source++[("sandbox",value_or JNull(field "mode" sandbox));("network_access",value_or JNull(field "network_access" sandbox));
       ("approval",value_or JNull(field "mode" approval));("reviewer_profile",value_or JNull(field "reviewer_profile" approval))])
    |TaskGraph _ _=>JObject[("declaration",JObject(filter(fun p=>existsb(String.eqb(fst p))(map field_name graph_fields))(object_fields source)))]
    |_=>source end in
    restore_snapshot(form_fields e)source d end.
Definition preferred_model d world s :=
 match owner d,model_preference(service_state s)with
 |NewTask _,Some preference=>if ModelSelection.valid_preference world preference then
   restore_fields[("profile",JString(fst preference));("reasoning",JString(snd preference))]d else Some d
 |_,_=>Some d end.
Definition initialize_for e world s :=
 d<-initialize e world;;
 let d:=match e with Project _|TitlePrompts=>with_revision(next(authoring_state s))d|_=>d end in
 preferred_model d world s.
Definition prepare_existing d world s :=
 if String.eqb(read_text "profile" d)""then
  d<-initialized_profile d world;;preferred_model d world s else Some d.
Definition ensure e world s := match find_draft e s with
 |Some d=>d'<-prepare_existing d world s;;Some(d',save_draft d' s)
 |None=>d<-initialize_for e world s;;Some(d,save_draft d s)end.
Definition navigate r s := let n:=navigation_state s in
  let global:=match r with Projects|ProjectHome _|Board|Agents|HistorySearch=>true|_=>false end in
  let w:=if global then None else active_work n in
  let n':=Navigation r w(record_visit w r(visits n))(expanded n)(N.succ(generation n))[]None in
  effects(with_navigation n' s)[Focus "main"].
Definition work_tab_key work := match work with None=>"work/all"|Some id=>String.append "work/"(show_natural id) end.
Definition select_work work world s :=
  let n:=navigation_state s in
  let allowed:=match work with None=>true|Some id=>match find_work id world with Some _=>true|None=>false end end in
  if allowed then
    let saved:=record_visit(active_work n)(location n)(visits n)in
    let r:=match find(fun v=>same_scope work(fst v))saved with Some(_,r)=>r|None=>Start end in
    let n':=Navigation r work saved(expanded n)(N.succ(generation n))[]None in
    match ensure(NewTask work)world(with_navigation n' s)with Some(_,s)=>effects s(Focus(work_tab_key work)::match r with Start=>[Focus(String.append(editor_key(NewTask work))"/message")]|Conversation task=>[Focus(String.append(editor_key(Message task))"/message")]|_=>[]end)|None=>reject "InvalidSnapshot" "Cannot initialize the Work editor" s end
  else reject "UnknownWork" "The selected Work is no longer available" s.
Definition open_editor e trigger world s :=
  let s:=match find_draft e s with Some d=>match status d with Accepted _=>
    let a:=authoring_state s in with_authoring(Authoring(filter(fun d=>negb(same_editor e(owner d)))(drafts a))(next a)(awaiting a)(history_search a)(skill_catalogs a)(mentions a))s
    |_=>s end|None=>s end in
  match ensure e world s with None=>reject "InvalidSnapshot" "Cannot initialize the editor from its current values" s
  |Some(_,s)=>let n:=navigation_state s in
    effects(with_navigation(Navigation(location n)(active_work n)(visits n)(expanded n)(N.succ(generation n))(EditorPanel e trigger::layers n)(side_task n))s)[Focus(editor_key e)]end.
Definition configuration_active e s := match layers(navigation_state s)with
 |InformationPanel kind subject _::_=>String.eqb kind "execution_configuration"&&
  match bind(field "editor" subject)decode_editor with Some parent=>same_editor parent e|None=>false end
 |_=>false end.
Definition configuration_pending e s := existsb(fun pending=>match purpose pending with
 |ConfigurationSubmission snapshot _=>same_editor e(owner snapshot)|_=>false end)(awaiting(authoring_state s)).
Definition discard_editor e s :=
 let a:=authoring_state s in
 let fresh:=match find_draft e s with None=>next a|Some d=>N.max(next a)(N.succ(revision d))end in
 let a:=Authoring(filter(fun d=>negb(same_editor e(owner d)))(drafts a))fresh(awaiting a)(history_search a)(skill_catalogs a)(mentions a)in
 with_services(cancel_editor e(service_state s))(with_authoring a s).
Definition close_panel s := let n:=navigation_state s in match layers n with []=>keep s|p::rest=>
  let trigger:=match p with EditorPanel _ t|InformationPanel _ _ t|Confirmation _ _ _ t=>t end in
  let s:=match p with EditorPanel(Project id) _=>discard_editor(Project id)s|EditorPanel TitlePrompts _=>discard_editor TitlePrompts s|_=>s end in
  effects(with_navigation(Navigation(location n)(active_work n)(visits n)(expanded n)(N.succ(generation n))rest(side_task n))s)[Focus trigger]end.
Definition inherited_sandbox d world :=
 let settings:=match owner d with Fork task|Message task=>t<-find_task task world;;field "settings" t
 |_=>bind(field "defaults" world)(field "settings")end in
 settings<-settings;;field "sandbox" settings.
Definition edited_sandbox name d world :=
 if String.eqb name "sandbox" || String.eqb name "network_access"then
  match get "sandbox" d with
  |JNull=>if String.eqb name "sandbox"then restore_field "network_access" JNull d else
    sandbox<-inherited_sandbox d world;;mode<-field "mode" sandbox;;restore_field "sandbox" mode d
  |_=>match get "network_access" d with JNull=>
    sandbox<-inherited_sandbox d world;;network<-field "network_access" sandbox;;restore_field "network_access" network d
    |_=>Some d end end
 else Some d.
Definition edited_field name value d world :=
  changed <- edit_raw_field name value d;;
  changed <- workspace_after_edit name changed;;
  changed <- edited_sandbox name changed world;;
  changed <- match owner changed with NewTask _=>if String.eqb name "project_id"then
    restore_field "task_environment"(JString(task_workspace_name(match natural(get "project_id" changed)with
      Some id=>match find_project id world with
       |Some project=>if flag "create_worktree" project then ManagedWorkspace WorkspaceBackend.Local else CurrentWorkspace
       |None=>CurrentWorkspace end
      |None=>CurrentWorkspace end)))changed else Some changed
    |_=>Some changed end;;
  if String.eqb name "profile" then
    match ModelSelection.observed_profile world (read_text "profile" changed) with
    | None => Some changed
    | Some _ => restore_field "reasoning"
        (JString(ModelSelection.selected_effort world (read_text "profile" changed) (read_text "reasoning" changed))) changed end
  else Some changed.
Definition remember_model world preference r :=
  if ModelSelection.valid_preference world preference then
    Result (with_services(with_model_preference(Some preference)(service_state(resulting_state r)))(resulting_state r))
      (PersistModelPreference(fst preference)(snd preference)::emitted r)(reply r)
  else r.
Definition edit e name value world s :=
  match ensure e world s with None=>reject "UnknownEditor" "This editor cannot be opened" s
  |Some(d,s)=>match edited_field name value d world with Some d'=>keep(save_draft d' s)|None=>reject "InvalidField" "This field does not accept the supplied value" s end end.
Definition draft_workspace d world :=
 match owner d with
 |Message task=>t<-find_task task world;;settings<-field "settings" t;;field "workspace" settings
 |Fork task=>match field "workspace"(Forms.settings d)with Some workspace=>Some workspace|None=>
   match natural(get "project_id" d)with Some id=>p<-find_project id world;;field "workspace" p
   |None=>t<-find_task task world;;settings<-field "settings" t;;field "workspace" settings end end
 |Project _=>Some(workspace d)
 |_=>match field "workspace"(Forms.settings d)with Some workspace=>Some workspace|None=>
   match natural(get "project_id" d)with Some id=>p<-find_project id world;;field "workspace" p
   |None=>settings<-bind(field "defaults" world)(field "settings");;field "workspace" settings end end end.
Definition workspace_git_available d world services :=
 match draft_workspace d world,workspace_git services with
 |Some workspace,Loaded _ (e,primary) available=>
  same_editor(owner d)e&&String.eqb primary(value_or ""(string_field "primary_root" workspace))&&available
 |_,_=>false end.
Definition domain_obstruction world services d :=
 match owner d with
 |NewTask _|Agent _=>if ModelSelection.valid_preference world(read_text "profile" d,read_text "reasoning" d)then
   match owner d with NewTask _=>if local_worktree d&&negb(workspace_git_available d world services)
    then Some "Wait for Git verification of the primary workspace before creating a worktree."else None|_=>None end
   else Some "Choose an available model and reasoning effort"
 |_=>None end.
Definition service_obstruction services d :=
 if negb(connected services)then Some "Connect to continue"
 else if preparing(owner d)services then Some "正在准备工作区，请稍候。"
 else if blocks(owner d)services then Some "Finish or cancel this editor's uploads"else None.
Definition obstruction world services d :=
 match service_obstruction services d with Some reason=>Some reason|None=>
  match intrinsic_obstruction d with Some reason=>Some reason|None=>domain_obstruction world services d end end.
Definition voice_obstruction world services d :=
 if cloud_workspace d then Some "Create the cloud task before starting voice" else
 match service_obstruction services d with Some reason=>Some reason|None=>
  match raw_fields d with (name,_)::_=>Some(String.append "Correct the value of " name)
  |[]=>domain_obstruction world services d end end.
Theorem disconnected_submission_is_blocked : forall world s d,
  connected s=false -> obstruction world s d=Some "Connect to continue".
Proof. intros. unfold obstruction,service_obstruction. now rewrite H. Qed.
Definition preparation_workspace d := match owner d with
 |Project _=>Some(workspace d)
 |NewTask _|Agent _|Fork _=>field "workspace"(Forms.settings d)
 |_=>None end.
Definition begin_preparation d workspace s :=
 let services:=service_state s in let t:=Services.next_ticket services in
 let pending:=Preparation t d(generation(navigation_state s))in
 effects(with_services(Services.with_next(N.succ t)(with_preparations(pending::preparations services)services))s)
   [Service(ObserveDirectories t workspace(owner d))].
Definition submit now e world s :=
  let original:=s in
  match ensure e world s with None=>reject "UnknownEditor" "This editor cannot be submitted" s
  |Some(d,s)=>if editor_pending e s then reject "PendingSubmission" "This editor already has a pending submission" original else
    match obstruction world(service_state s)d with Some reason=>reject "SubmissionBlocked" reason original
    |None=>let source:=match e with Card _=>replace "observed_at"(JString(show_natural now))(command d)|_=>command d end in
       match preparation_workspace d with
       |Some workspace=>begin_preparation d workspace s
       |None=>issue source(DraftSubmission d(generation(navigation_state s)))s end end end.
Definition retry_workspace now e world s := match find_draft e s with
 |Some d=>match status d with WorkspaceRejected _=>submit now e world(save_draft(with_status Editing d)s)
   |_=>reject "WorkspaceRetryUnavailable" "Only the failed workspace preparation can be retried" s end
 |None=>reject "UnknownEditor" "This editor cannot be submitted" s end.
Definition admit_directories observation :=
 if String.eqb(text "kind" observation)"directories"then
 workspace_json<-field "workspace" observation;;
 checked<-Selvedge.Kernel.Codec.parse_workspace workspace_json;;
 guidance<-field "guidance" observation;;
 if Selvedge.Kernel.Codec.valid_guidance guidance && Selvedge.Kernel.Codec.guidance_member checked guidance
 then Some workspace_json else None else None.
Definition prepared_command snapshot workspace :=
 let source:=command snapshot in match owner snapshot with
 |Project _=>replace "workspace" workspace source
 |_=>let settings:=value_or JNull(field "settings" source)in
   replace "settings"(replace "workspace" workspace settings)source end.
Definition preparation_failed snapshot reason s :=
 Result(save_draft(with_status(WorkspaceRejected reason)snapshot)s)[](failure "WorkspaceObservationFailed" reason).
Definition directories_completed world ticket outcome s :=
 match find(fun p=>N.eqb ticket(preparation_ticket p))(preparations(service_state s))with
 |None=>keep s
 |Some pending=>let snapshot:=preparation_draft pending in
   let s:=with_services(forget_preparation ticket(service_state s))s in
   match find_draft(owner snapshot)s with
   |Some current=>if N.eqb(revision current)(revision snapshot)then
     if editor_pending(owner snapshot)s then keep s else
     match obstruction world(service_state s)snapshot with
     |Some reason=>preparation_failed snapshot reason s
     |None=>match outcome with
       |inl reason=>preparation_failed snapshot reason s
       |inr observation=>match admit_directories observation with
         |None=>preparation_failed snapshot "目录观察返回了无效的工作区或项目指导。" s
         |Some workspace=>issue(prepared_command snapshot workspace)
           (DraftSubmission snapshot(preparation_generation pending))s end end end
     else keep s
   |None=>keep s end end.
Definition completion_error (outcome:sum string json) := match outcome with inl e=>e|inr j=>text "error" j end.
Definition completion_success (outcome:sum string json) := match outcome with inl _=>false|inr j=>flag "ok" j end.
Definition completion_value (outcome:sum string json) := match outcome with inl _=>JNull|inr j=>value_or JNull(field "result" j)end.
Definition cleared_values e : fields(form_schema e)->fields(form_schema e) :=
 match e as e return fields(form_schema e)->fields(form_schema e) with
 |NewTask work=>fun values=>@FCons(Schema.Field "message" KText)_ ""(tail values)
 |Message task=>fun values=>@FCons(Schema.Field "message" KText)_ ""(tail values)
 |Card None=>fun values=>@FCons(Schema.Field "title" KText)_ ""(@FCons(Schema.Field "description" KText)_ ""(tail(tail values)))
 |_=>fun values=>values end.
Definition clear_accepted d value :=
 let changed:=match owner d with NewTask _|Message _|Card None=>true|_=>false end in
 Draft(owner d)(if changed then N.succ(revision d)else revision d)(cleared_values(owner d)(values d))
   (if changed then []else attachments d)(if changed then []else raw_fields d)(Accepted value).
Definition settle_draft snapshot outcome s :=
  match find_draft(owner snapshot)s with None=>s|Some current=>
    if N.eqb(revision current)(revision snapshot)then
      save_draft(if completion_success outcome then clear_accepted current(completion_value outcome)
        else with_status(Rejected(completion_error outcome))current)s
    else s end.
Definition created_task outcome := natural_field "task_id"(completion_value outcome).
Definition remember_accepted_model (accepted:public_command) world r :=
 let source:=encode_command accepted in
 match string_field "profile" source,string_field "reasoning" source with
 |Some profile,Some effort=>remember_model world(profile,effort)r|_,_=>r end.
Definition complete_purpose purpose (accepted:public_command) outcome world s :=
  match purpose with
  |DraftSubmission snapshot g=>
      let owned:=match find_draft(owner snapshot)s with Some d=>N.eqb(revision d)(revision snapshot)|None=>false end in
      let s:=settle_draft snapshot outcome s in
      if completion_success outcome && owned && N.eqb g(generation(navigation_state s))then
        match owner snapshot,created_task outcome with
        |NewTask _,Some task=>navigate(Conversation task)s
        |Message _,Some task=>if String.eqb(text "op"(encode_command accepted))"open_side_conversation"then
          let n:=navigation_state s in
          effects(with_navigation(Navigation(location n)(active_work n)(visits n)(expanded n)(generation n)(layers n)(Some task))s)
            [Focus(editor_key(Message task))]else keep s
        |Message _,None=>keep s
        |Card _,_=>if read_flag "keep_open" snapshot then keep s else close_panel s
        |_,_=>match layers(navigation_state s)with
          |EditorPanel current _::_=>if same_editor current(owner snapshot)then close_panel s else keep s
          |_=>keep s end end else keep s
  |SideCreation parent g=>
      if completion_success outcome && N.eqb g(generation(navigation_state s)) then
       match location(navigation_state s),created_task outcome with Conversation current,Some task=>
        if N.eqb parent current then let n:=navigation_state s in
         effects(with_navigation(Navigation(location n)(active_work n)(visits n)(expanded n)(generation n)(layers n)(Some task))s)[Focus(String.append(editor_key(Message task))"/message")]else keep s
       |_,_=>keep s end else keep s
  |SearchSubmission q p w=>let old:=history_search(authoring_state s)in
      if String.eqb q(keyword old)&&same_scope p(project_filter old)&&same_scope w(work_filter old)
      then keep(set_search(Search q p w(Some(match outcome with inl error=>failure "SearchFailed" error|inr value=>value end)))s)else keep s
  |WorkCreation g=>if completion_success outcome&&N.eqb g(generation(navigation_state s))then
      match natural_field "work_id"(completion_value outcome)with Some work=>select_work(Some work)world s|None=>keep s end else keep s
  |ConfigurationSubmission snapshot g=>
      let owned:=configuration_active(owner snapshot)s&&N.eqb g(generation(navigation_state s))in
      let settled:=match find_draft(owner snapshot)s with
       |Some current=>if owned&&N.eqb(revision current)(revision snapshot)then
         if completion_success outcome then close_panel(save_draft(with_status(Accepted(completion_value outcome))current)s)
         else keep(save_draft(with_status(Rejected(completion_error outcome))current)s)
         else keep s
       |None=>keep s end in
      if completion_success outcome then remember_accepted_model accepted world settled else settled
  |ExecutionSelection=>if completion_success outcome then remember_accepted_model accepted world(keep s)else keep s
  |LanguageSubmission _ _ _|DirectSubmission=>keep s end.
Definition complete t outcome world s :=
  match find(fun p=>N.eqb t(ticket p))(awaiting(authoring_state s))with
  |None=>keep s
  |Some p=>let s:=set_pending(filter(fun p=>negb(N.eqb t(ticket p)))(awaiting(authoring_state s)))(next(authoring_state s))s in
    complete_purpose(purpose p)(accepted_command p)outcome world s end.
Definition apply_service_effect e world s := match e with
|DirectoryChosen owner path=>match ensure owner world s with Some(d,s)=>match edited_field "primary_root"(JString path)d world with Some d=>save_draft d s|None=>s end|None=>s end
|_=>s end.
Definition service input world s :=
  let s:=match input with OpenSettings|CloseSettings=>let n:=navigation_state s in with_navigation(Navigation(location n)(active_work n)(visits n)(expanded n)(N.succ(generation n))[](side_task n))s|_=>s end in
  let was_connected:=connected(service_state s)in
  let r:=service_step input(service_state s)in
  let s:=with_services(Services.service_state r)s in
  let s:=match attached r with None=>s|Some(e,file)=>match ensure e world s with None=>s|Some(d,s)=>save_draft(with_attachments(attachments d++[file])d)s end end in
  let s:=fold_left(fun s e=>apply_service_effect e world s)(service_effects r)s in
  effects s(map Service(filter(fun e=>match e with DirectoryChosen _ _=>false|_=>true end)(service_effects r))++
    match input with Authenticated _ (inr _)=>if connected(Services.service_state r)&&negb(was_connected)then [Audio LoadCapabilities]else []|_=>[]end).
Definition splice start finish insert text :=
  String.append (String.substring 0(N.to_nat start)text) (String.append insert (String.substring(N.to_nat finish)(String.length text)text)).
Definition insert_transcript explicit capture text world s :=
  match ensure(target_editor capture)world s with
  |None=>s
  |Some(d,s)=>if N.eqb(revision d)(target_revision capture)||explicit then
    let old:=read_text "message" d in
    let changed:=if explicit then String.append old text else splice(selection_start capture)(selection_end capture)text old in
    match edit_field "message"(JString changed)d with Some d=>with_speech(acknowledge(speech_state s))(save_draft d s)|None=>s end
  else with_speech(with_notice "The draft changed; insert the transcript explicitly"(speech_state s))s end.
Definition speech input world s :=
  let before:=current(speech_state s)in
  let r:=speech_step input(speech_state s)in
  let s:=with_speech(Speech.speech_state r)s in
  let s:=match transcript r with None=>s|Some(capture,text)=>insert_transcript(match input with InsertTranscript=>true|_=>false end)capture text world s end in
  let base:=effects s(map Audio(speech_effects r))in
  match input,before with TaskCreated ticket task,CreatingTask captured e revision generation=>
   if N.eqb ticket captured&&N.eqb generation(ApplicationState.generation(navigation_state s))then
    match find_draft e s with Some d=>if N.eqb revision(Forms.revision d)then
      let navigated:=navigate(Conversation task)s in Result(resulting_state navigated)(emitted base++emitted navigated)JNull else base
    |None=>base end else base
  |_,_=>base end.
Definition edit_search query project work s :=set_search(Search query project work None)s.
Definition submit_search after s :=let search:=history_search(authoring_state s)in
  issue(JObject(("op",JString "search_history")::("query",JString(keyword search))::("after",number after)::("limit",number Search.default_limit)::
    present "project_id"(optional_id(project_filter search))(present "work_id"(optional_id(work_filter search))[])))
    (SearchSubmission(keyword search)(project_filter search)(work_filter search))s.
Definition active_previews world s :=
 fold_right(fun entry rest=>let identity:=stream_identity entry in
  match find_task(stream_task identity)world with None=>rest|Some task=>
   let pending:=value_or JNull(field "model_pending" task)in
   match natural_field "ticket" pending,natural_field "operation_id" pending with
   |Some ticket,Some operation=>if N.eqb ticket(stream_ticket identity)then
     match Streams.cumulative(stream_state s)(stream_task identity)ticket operation with Some output=>output::rest|None=>rest end else rest
   |_,_=>rest end end)[](stream_state s).
Definition retain_live world s:=with_streams(filter(fun entry=>let identity:=stream_identity entry in
 match find_task(stream_task identity)world with None=>false|Some task=>
  match bind(field "model_pending" task)(natural_field "ticket")with Some ticket=>N.eqb ticket(stream_ticket identity)|None=>false end end)(stream_state s))s.
Definition stream value (world:json) s:=
 match Streams.decode_event value with None=>reject "InvalidStream" "The stream notice does not match its transport protocol" s
 |Some notice=>let '(streams,publish):=Streams.step Streams.browser_configuration notice(stream_state s)in keep(with_streams streams s)end.
