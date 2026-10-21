From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers Schema.
From Selvedge.Kernel Require Import Commands Conversation.
From Selvedge.Features Require BoardFilter Titles.
From Selvedge.Interaction Require Import Codec Identity Resource Services Forms Speech SkillMention ApplicationState ApplicationOps Input.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Definition set_mentions ms s:=let a:=authoring_state s in with_authoring(Authoring(drafts a)(next a)(awaiting a)(history_search a)(skill_catalogs a)ms)s.
Definition mention_for e s:=match find(fun p=>same_editor e(fst p))(mentions(authoring_state s))with Some(_,m)=>m|None=>Inactive end.
Definition save_mention e m s:=set_mentions((e,m)::filter(fun p=>negb(same_editor e(fst p)))(mentions(authoring_state s)))s.
Definition set_catalogs cs n s:=let a:=authoring_state s in with_authoring(Authoring(drafts a)n(awaiting a)(history_search a)cs(mentions a))s.
Definition catalog_owned e (r:resource skill_request(list SkillMention.skill)):=match resource_request r with Some request=>same_editor e(skill_editor request)|None=>false end.
Definition defaults_settings world:=bind(field "defaults" world)(field "settings").
Definition settings_workspace settings:=field "workspace" settings.
Definition workspace_for e world s : option json :=
 match find_draft e s with Some d=>draft_workspace d world|None=>None end.
Definition refresh_workspace_git e world r :=
 match reply r with JNull=>let s:=resulting_state r in
  match workspace_for e world s with None=>r|Some workspace=>
   let primary:=value_or ""(string_field "primary_root" workspace)in
   let services:=service_state s in
   let same_request:=match resource_request(workspace_git services)with
    |Some(owner,old)=>same_editor e owner&&String.eqb primary old|None=>false end in
   if same_request then r else
    let ticket:=Services.next_ticket services in
    Result(with_services(Services.with_next(N.succ ticket)(with_workspace_git(Loading ticket(e,primary))services))s)
      (emitted r++[Service(ObserveWorkspaceGit ticket primary e)])(reply r)
  end|_=>r end.
Definition refresh_active_workspace world r :=
 let s:=resulting_state r in
 match layers(navigation_state s)with EditorPanel e _::_=>refresh_workspace_git e world r
 |_=>match location(navigation_state s)with
  |Start=>refresh_workspace_git(NewTask(active_work(navigation_state s)))world r
  |Conversation task=>refresh_workspace_git(Message task)world r|_=>r end end.
Definition catalog_for e world s:=match find(catalog_owned e)(skill_catalogs(authoring_state s)),workspace_for e world s with
 |Some(Loaded _ request values),Some workspace=>if Json.equal workspace(skill_workspace request)then values else []|_,_=>[]end.
(* DEFENSE: a Git reply can outlive its editor or primary workspace selection. *)
Definition reset_unavailable_local input world previous r :=
 match input,workspace_git(service_state previous)with
 |WorkspaceGitCompleted ticket(inr false),Loading expected(e,primary)=>
   if N.eqb ticket expected then
    match find_draft e(resulting_state r)with
    |Some d=>let matching:=match draft_workspace d world with
      |Some workspace=>String.eqb primary(value_or ""(string_field "primary_root" workspace))
      |None=>false end in
      if local_worktree d&&matching then
       let changed:=edit e "task_environment"(JString "current")world(resulting_state r)in
       Result(resulting_state changed)(emitted r++emitted changed)(reply changed)
      else r
    |None=>r end else r
 |_,_=>r end.
Definition load_skills e world s:=
  match workspace_for e world s with None=>reject "WorkspaceUnavailable" "Choose an available workspace before loading skills" s
  |Some workspace=>let a:=authoring_state s in let t:=next a in
    let request:=SkillRequest e workspace in
    effects(set_catalogs(Loading t request::filter(fun r=>negb(catalog_owned e r))(skill_catalogs a))(N.succ t)s)[ApplicationOps.LoadSkills e t workspace]end.
Definition skills_loaded e ticket outcome world s:=
  match find(catalog_owned e)(skill_catalogs(authoring_state s)),workspace_for e world s with
  |Some(Loading current request),Some workspace=>
    if N.eqb current ticket&&Json.equal workspace(skill_workspace request)then
      keep(set_catalogs(map(fun r=>if catalog_owned e r then settle ticket outcome r else r)(skill_catalogs(authoring_state s)))(next(authoring_state s))s)
    else keep s
  |_,_=>keep s end.
Definition observe_skills e selection world s:=
  match selection,find_draft e s with Some(start,finish,composing),Some d=>
    let old:=mention_for e s in
    let m:=observe_mention(read_text "message" d)(N.to_nat start)(N.to_nat finish)composing old in
    let s:=save_mention e m s in
    match m with Suggesting _ _=>match find(catalog_owned e)(skill_catalogs(authoring_state s)),workspace_for e world s with
      |Some r,Some workspace=>match resource_request r with Some request=>if Json.equal workspace(skill_workspace request)then keep s else load_skills e world s|None=>load_skills e world s end
      |_,_=>load_skills e world s end|_=>keep s end
  |_,_=>keep s end.
Definition skill_selected e path (world:json) s:=
  let skills:=catalog_for e world s in
  match mention_for e s,find_draft e s with
  |Suggesting trigger _,Some d=>
    match find(fun skill=>String.eqb path(skill_path skill))(candidates(query trigger)skills)with
    |None=>reject "UnavailableSkill" "The selected skill is no longer in these choices" s
    |Some skill=>let replacement:=SkillMention.replacement skill
      (String.substring(trigger_end trigger)(String.length(read_text "message" d))(read_text "message" d))in
      let text:=splice(N.of_nat(trigger_start trigger))(N.of_nat(trigger_end trigger))replacement(read_text "message" d)in
      match edit_field "message"(JString text)d with None=>reject "UnavailableField" "This editor has no message field" s
      |Some d=>effects(save_mention e Inactive(save_draft d s))
        [Focus(String.append(editor_key e)"/message");SelectionBytes(String.append(editor_key e)"/message")(N.of_nat(trigger_start trigger+String.length replacement))]end end
  |_,_=>reject "UnavailableSkill" "A skill can only replace the current mention" s end.
Definition remove_attachment e id s:=match find_draft e s with None=>keep s|Some d=>keep(save_draft(with_attachments(filter(fun a=>negb(String.eqb id(asset_id a)))(attachments d))d)s)end.
Definition with_side side s:=let n:=navigation_state s in with_navigation(Navigation(location n)(active_work n)(visits n)(expanded n)(generation n)(layers n)side)s.
Definition show_side task world s:=match find_task task world with None=>reject "UnknownTask" "The side conversation is no longer available" s|Some _=>effects(with_side(Some task)s)[Focus(String.append(editor_key(Message task))"/message")]end.
Definition source_owner_active e s :=
 let nav:=navigation_state s in match layers nav with
 |EditorPanel parent _::_=>same_editor e parent
 |InformationPanel kind subject _::_=>String.eqb kind "execution_configuration"&&match bind(field "editor" subject)decode_editor with Some parent=>same_editor e parent|None=>false end
 |[]=>match e,location nav with
   |NewTask scope,Start=>same_scope scope(active_work nav)
   |Message task,Conversation current=>N.eqb task current || match side_task nav with Some side=>N.eqb task side|None=>false end
   |_,_=>false end
 |_=>false end.
Definition open_information kind subject trigger s:=let n:=navigation_state s in
  effects(with_navigation(Navigation(location n)(active_work n)(visits n)(expanded n)(N.succ(generation n))(InformationPanel kind subject trigger::layers n)(side_task n))s)[Focus(String.append "panel/" kind)].
Definition request_confirmation command caption destination trigger s:=let n:=navigation_state s in
  effects(with_navigation(Navigation(location n)(active_work n)(visits n)(expanded n)(N.succ(generation n))(ApplicationState.Confirmation command caption destination trigger::layers n)(side_task n))s)[Focus "confirmation"].
Definition execution_fields := filter(fun f=>negb(existsb(String.eqb(field_name(specification f)))["message";"delivery"]))(form_fields(Message 0)).
Definition refresh_configuration e world s :=
 current<-find_draft e s;;observed<-initialize e world;;
 refreshed<-restore_fields(map(fun f=>let name:=field_name(specification f)in(name,get name observed))execution_fields)current;;
 Some(save_draft(Draft(owner refreshed)(N.succ(revision refreshed))(values refreshed)(attachments refreshed)
   (filter(fun entry=>negb(existsb(fun f=>String.eqb(fst entry)(field_name(specification f)))execution_fields))(raw_fields refreshed))Editing)s).
Definition open_configuration e trigger world s :=
 match e with Message _=>if source_owner_active e s then
  match ensure e world s with None=>reject "UnavailableConfiguration" "The task no longer exists" s
  |Some(_,s)=>match refresh_configuration e world s with
    |Some s=>open_information "execution_configuration"(JObject[("editor",encode_editor e)])trigger s
    |None=>reject "UnavailableConfiguration" "The task no longer exists" s end end
  else reject "UnavailableConfiguration" "Configure the currently open task" s
 |_=>reject "UnavailableConfiguration" "This task configuration belongs to a conversation" s end.
Definition apply_configuration e world s :=
 if configuration_active e s then match e,find_draft e s with
 |Message task,Some d=>if configuration_pending e s then reject "PendingConfiguration" "This configuration is already being applied" s else
   match filter(fun entry=>existsb(fun f=>String.eqb(fst entry)(field_name(specification f)))execution_fields)(raw_fields d)with
   |(_,_)::_=>reject "InvalidConfiguration" "Correct the configuration values before applying" s
   |[]=>if ModelSelection.valid_preference world(read_text "profile" d,read_text "reasoning" d)then
     issue(execution_command task d)(ConfigurationSubmission d(generation(navigation_state s)))s
     else reject "InvalidConfiguration" "Choose an available model and reasoning effort" s end
 |_,_=>reject "UnavailableConfiguration" "The task configuration is no longer available" s end
 else reject "UnavailableConfiguration" "Open the task configuration before applying" s.
Definition dismiss_panel world s := match layers(navigation_state s)with
 |InformationPanel kind subject _::_=>if String.eqb kind "execution_configuration"then
   match bind(field "editor" subject)decode_editor with Some e=>
    match refresh_configuration e world s with Some s=>close_panel s|None=>close_panel s end
   |None=>close_panel s end else close_panel s
 |_=>close_panel s end.
Definition inspect_source e name trigger s :=
 if source_owner_active e s && existsb(String.eqb name)["roots";"primary_root";"project_id";"sandbox";"network_access";"approval";"reviewer_profile"]then
 open_information "property_source"(JObject[("editor",encode_editor e);("field",JString name)])trigger s
 else reject "SourceUnavailable" "The source belongs to the currently open editor" s.
Definition confirm s:=match layers(navigation_state s)with ApplicationState.Confirmation c _ _ _::_=>issue(encode_command c)DirectSubmission(resulting_state(close_panel s))|_=>reject "NoConfirmation" "There is no pending confirmation" s end.
Definition set_expanded value s:=let n:=navigation_state s in
 let next_generation:=if Bool.eqb value(expanded n)then generation n else N.succ(generation n)in
 with_navigation(Navigation(location n)(active_work n)(visits n)value next_generation(layers n)(side_task n))s.
Definition disclose task group occurrence expanded s:=
 match find(fun r=>N.eqb task(reading_task r))(readers s)with None=>with_readers(Reader task[(group,occurrence,expanded)]::readers s)s|Some r=>
 let ds:=(group,occurrence,expanded)::filter(fun '(a,b,_)=>negb(N.eqb a group&&N.eqb b occurrence))(disclosures r)in
 with_readers(Reader task ds::filter(fun r=>negb(N.eqb task(reading_task r)))(readers s))s end.
Definition initialize_unselected_profiles world s:=
 fold_left(fun s d=>match owner d with NewTask _|Agent _=>
  if String.eqb(read_text "profile" d)""then match initialized_profile d world with Some d'=>save_draft d' s|None=>s end else s|_=>s end)(drafts(authoring_state s))s.
Definition edit_application e name value world s:=
 match e with
 |Message task=>if configuration_active e s || String.eqb name "message"||String.eqb name "delivery"then edit e name value world s else
   match initialize e world with None=>reject "UnknownTask" "This task can no longer be configured" s|Some observed=>
    match edited_field name value observed world with None=>reject "InvalidField" "This field does not configure the task" s
    |Some changed=>match raw_fields changed with []=>issue(execution_command task changed)(if String.eqb name "profile"||String.eqb name "reasoning"then ExecutionSelection else DirectSubmission)s
      |_=>match find_draft e s with None=>keep(save_draft changed s)|Some original=>
        let retained:=Draft(owner original)(N.succ(revision original))(values original)(attachments original)(raw_fields changed)Editing in keep(save_draft retained s)end end end end
 |NewTask _=>let r:=edit e name value world s in
   match reply r with JNull=>
     if String.eqb name "profile"||String.eqb name "reasoning"then
       match find_draft e(resulting_state r)with
       |Some d=>remember_model world(read_text "profile" d,read_text "reasoning" d)r|None=>r end
     else r
   |_=>r end
 |_=>edit e name value world s end.
Definition begin_voice_new e world s:=match e,ensure e world s with
|NewTask work,Some(d,s)=>
 match voice_obstruction world(service_state s)d with None=>
   let command:=JObject(present "work_id"(optional_id work)[("op",JString "create_idle");("profile",get "profile" d);("reasoning",get "reasoning" d);("settings",Forms.settings d);("create_worktree",JBool(local_worktree d))])in
  match decode_command command_specs command with None=>reject "InvalidCommand" "The voice task does not match the creation protocol" s
  |Some command=>speech(BeginNewVoice e(revision d)(generation(navigation_state s))command)world s end
 |Some reason=>reject "SubmissionBlocked" reason s end
|_,_=>reject "UnavailableVoice" "A new voice conversation needs a new-task editor" s end.
Definition reset_title_values e :fields(form_schema e)->fields(form_schema e):=
 match e as e return fields(form_schema e)->fields(form_schema e)with
 |TitlePrompts=>fun values=>@FCons(Schema.Field "revision" KNatural)_ (head values)
   (@FCons(Schema.Field "task_prompt" KText)_ Titles.instructions(@FCons(Schema.Field "agent_prompt" KText)[] Titles.instructions FNil))
 |_=>fun values=>values end.
Definition reset_title_prompts world s:=match ensure TitlePrompts world s with None=>reject "MissingTitleSettings" "Title settings are unavailable" s
 |Some(d,s)=>keep(save_draft(Draft(owner d)(N.succ(revision d))(reset_title_values(owner d)(values d))(attachments d)[]Editing)s)end.
Definition local_step now input world s : option result :=
  match input with
  |ResetTitlePrompts=>Some(reset_title_prompts world s)
  |ToggleProjectGroup id=>Some(keep(with_collapsed_projects(if existsb(N.eqb id)(collapsed_projects s)then filter(fun old=>negb(N.eqb id old))(collapsed_projects s)else id::collapsed_projects s)s))
  |BeginProjectTask id=>Some(match find_project id world with None=>reject "MissingProject" "The project no longer exists" s|Some _=>let next:=navigate Start s in
    let edited:=edit(NewTask(active_work(navigation_state s)))"project_id"(number id)world(resulting_state next)in
    Result(resulting_state edited)(emitted next++emitted edited)(reply edited)end)
  |BeginVoiceNew e=>Some(begin_voice_new e world s)
  |SelectSharedTask work task=>Some(match task with None=>navigate(SharedUI work None)s|Some task=>if task_belongs(Some work)task world then navigate(SharedUI work(Some task))s else reject "WrongWork" "This task does not belong to the selected Work" s end)
  |Navigate r=>Some(navigate r s)|SelectWork w=>Some(refresh_active_workspace world(select_work w world s))
  |CreateWork=>Some(issue(JObject[("op",JString "create_work")])(WorkCreation(generation(navigation_state s)))s)
  |OpenEditor e trigger=>Some(refresh_workspace_git e world(open_editor e trigger world s))
  |Edit e name value selection=>let readonly:=match layers(navigation_state s)with
      InformationPanel kind _ _::_=>String.eqb kind "property_source"|_=>false end in
      let r:=if readonly then reject "ReadOnlySource" "Source information does not edit its parent" s else edit_application e name value world s in
      let r:=if existsb(String.eqb name)["roots";"primary_root";"project_id"]then refresh_workspace_git e world r else r in
      if String.eqb name "message"then Some(match reply r with
       |JNull=>push_effects(emitted r)(observe_skills e selection world(resulting_state r))|_=>r end)else Some r
  |RetryWorkspace e=>Some(retry_workspace now e world s)
  |DirectoriesCompleted ticket outcome=>Some(directories_completed world ticket outcome s)
  |Submit e=>Some(match layers(navigation_state s)with
     |InformationPanel kind _ _::_=>if String.eqb kind "property_source"then reject "ReadOnlySource" "Source information does not submit its parent" s else submit now e world s
     |_=>submit now e world s end)|RemoveAttachment e id=>Some(remove_attachment e id s)
  |Command c=>Some(if connected(service_state s)then queue_command c DirectSubmission s else reject "Disconnected" "Connect to continue" s)
  |Completed ticket outcome=>Some(complete ticket outcome world s)
  |ServiceInput input=>let r:=service input world s in
      Some(match input with
       |Authenticated _ (inr _)=>if connected(service_state s)then r else refresh_active_workspace world r
       |ChooseDirectory=>refresh_active_workspace world r
       |WorkspaceGitCompleted _ _=>reset_unavailable_local input world s r|_=>r end)|SpeechInput input=>Some(speech input world s)
  |OpenConfiguration e trigger=>Some(open_configuration e trigger world s)
  |ApplyConfiguration e=>Some(apply_configuration e world s)
  |InspectSource e name trigger=>Some(inspect_source e name trigger s)
  |ClosePanel=>Some(dismiss_panel world s)|OpenInformation kind subject trigger=>Some(open_information kind subject trigger s)
  |Confirm=>Some(confirm s)|Input.Confirmation c caption destination trigger=>Some(request_confirmation c caption destination trigger s)
  |BeginSide parent=>Some(issue(JObject[("op",JString "open_side_conversation");("task_id",number parent);("message",content ""[])])(SideCreation parent(generation(navigation_state s)))s)
  |ShowSide t=>Some(show_side t world s)|CloseSide=>Some(effects(with_side None s)[Focus "main"])
  |NavigationExpanded expanded=>Some(keep(set_expanded expanded s))
  |WriteHistoryQuery query=>let old:=history_search(authoring_state s)in Some(keep(edit_search query(project_filter old)(work_filter old)s))
  |ChooseHistoryScope project scope=>let old:=history_search(authoring_state s)in
    Some(keep(edit_search(keyword old)(if project then scope else project_filter old)(if project then work_filter old else scope)s))
  |SubmitHistorySearch after=>Some(submit_search after s)
  |OpenHistoryMessage task index=>Some(push_effects[ScrollTo task index](navigate(Conversation task)s))
  |Input.FollowLatest task=>Some(effects s[ApplicationOps.FollowLatest task])
  |SetDisclosure task group occurrence expanded=>Some(keep(disclose task group occurrence expanded s))
  |CardPlaced id revision observed_at status before=>Some(
    match find_world "cards" "card_id" id(value_or JNull(field "board" world))with
    |Some card=>if flag "drag"(value_or JNull(field "capabilities" card))&&
       N.eqb revision(value_or (0%N)(natural_field "revision" card))then
      issue(JObject[("op",JString "move_card");("card_id",number id);("revision",number revision);("observed_at",JString(show_natural observed_at));
       ("status",JString status);("before_card",JString(match before with None=>""|Some id=>show_natural id end))])DirectSubmission s
      else reject "CardMoveUnavailable" "The card is no longer movable at this revision" s
    |None=>reject "CardMoveUnavailable" "The card no longer exists" s end)
  |CardField id revision observed_at name value=>Some(
      let command:=if String.eqb name "task_id"then JObject[("op",JString "link_card");("card_id",number id);("revision",number revision);("observed_at",JString(show_natural observed_at));("task_id",if String.eqb value ""then JNull else JNumber value)]
       else JObject[("op",JString "move_card");("card_id",number id);("revision",number revision);("observed_at",JString(show_natural observed_at));(name,JString value)]in
      if existsb(String.eqb name)["status";"before_card";"task_id"]then issue command DirectSubmission s else reject "UnknownField" "Unsupported card control" s)
  |BoardProfile value=>Some(issue(JObject[("op",JString "board_settings");("automatic",JBool(flag "automatic"(value_or JNull(field "board" world))));("draft_profile",JString value)])DirectSubmission s)
  |BoardQuery value=>Some(keep(with_board_selection(BoardFilter.set_query value(board_selection s))s))
  |BoardTab value=>Some(keep(with_board_selection(BoardFilter.set_tab value(board_selection s))s))
  |BoardToggle category value=>Some(keep(with_board_selection(BoardFilter.toggle category value(board_selection s))s))
  |Snapshot=>Some(keep(initialize_unselected_profiles world(retain_live world s)))
  |Stream value=>Some(stream value world s)
  |CodeObserved _|Interactive _|RetainedOutput _ _=>None
  |AppearanceRestored a=>Some(keep(with_services(with_theme a(service_state s))s))
  |Viewport _ _=>Some(keep s)
  |Input.LoadSkills e=>Some(load_skills e world s)
  |SkillsLoaded e t outcome=>Some(skills_loaded e t outcome world s)
  |SkillSelected e path=>Some(skill_selected e path world s)
  |SkillSelection e selection=>Some(observe_skills e(Some selection)world s)
  |SkillMove e backward=>Some(keep(save_mention e(move_mention backward(catalog_for e world s)(mention_for e s))s))
  |SkillDismiss e=>Some(keep(save_mention e(dismiss_mention(mention_for e s))s))
  end.
