From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers Schema.
From Selvedge.Kernel Require Import Commands Conversation.
From Selvedge.Features Require BoardFilter Titles.
From Selvedge.Interaction Require Navigation ObjectActions.
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
 match layers(navigation_state s)with ActivityPanel e _ _ _ _::_=>refresh_workspace_git e world r
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
Definition with_side side s:=let n:=navigation_state s in with_navigation(Navigation(location n)(active_work n)(visits n)(expanded n)(N.succ(generation n))(layers n)side)s.
Definition show_side task trigger world s:=match find_task task world with
 |None=>reject "UnknownTask" "The side conversation is no longer available" s
 |Some _=>effects(with_side(Some(SideWindow task trigger))s)
   [Focus(task_view_key(SideTask task)(String.append(editor_key(Message task))"/message"))]end.
Definition close_side s :=match side_window(navigation_state s)with
 |None=>keep s|Some window=>effects(with_side None s)[Focus(window_trigger window)]end.

Definition open_information kind subject trigger s :=
 let n:=navigation_state s in
 let matching:=fun panel=>match panel with
  |InformationPanel current target _=>String.eqb kind "task_details"&&String.eqb kind current&&Json.equal subject target
  |_=>false end in
 if existsb matching(layers n)then
  effects(with_navigation(Navigation(location n)(active_work n)(visits n)(expanded n)(N.succ(generation n))
    (filter(fun panel=>negb(matching panel))(layers n))(side_window n))s)[Focus trigger]
 else effects(with_navigation(Navigation(location n)(active_work n)(visits n)(expanded n)(N.succ(generation n))
    (InformationPanel kind subject trigger::layers n)(side_window n))s)[Focus(information_panel_key kind subject)].
Definition open_navigation kind trigger s :=
 let n := navigation_state s in
 let occurrence := N.succ(generation n) in
 let target := match kind with GlobalMenu => "global-navigation-dialog" | WorkOverview => Navigation.work_overview_key(active_work n) | TasksDrawer=>"navigation-toggle" end in
 effects(with_navigation(Navigation(location n)(active_work n)(visits n)(expanded n)occurrence
   (NavigationPanel kind trigger::layers n)(side_window n))s)[Focus target].
Definition open_object_actions subject trigger s :=
 let n:=navigation_state s in
 effects(with_navigation(Navigation(location n)(active_work n)(visits n)(expanded n)(N.succ(generation n))
  (ObjectActionsPanel subject trigger::layers n)(side_window n))s)[Focus(menu_key subject)].
Definition request_confirmation command caption destination trigger s:=let n:=navigation_state s in
  effects(with_navigation(Navigation(location n)(active_work n)(visits n)(expanded n)(N.succ(generation n))(ApplicationState.Confirmation command caption destination trigger None::layers n)(side_window n))s)[Focus "confirmation"].
Definition confirm world s:=match layers(navigation_state s)with
 |ApplicationState.Confirmation command caption _ _ _::_=>
  (* DEFENSE: a second native click may arrive before pending state disables Confirm. *)
  if confirmation_pending s then keep s else
  match ObjectActions.confirmation_availability world s command caption with
  |ObjectActions.Available=>issue(encode_command command)(ConfirmationSubmission(generation(navigation_state s)))s
  |ObjectActions.Unavailable reason|ObjectActions.AssessmentFailed reason=>reject "ActionUnavailable" reason s
  |ObjectActions.Awaiting=>reject "AssessmentPending" "Checking action availability" s end
 |_=>reject "NoConfirmation" "There is no pending confirmation" s end.
Definition request_direct command purpose trigger s:=match ObjectActions.confirmation_for command with
 |Some(caption,destination,_)=>request_confirmation command caption destination trigger s
 |None=>push_effects[Focus trigger](queue_command command purpose s)end.
Definition set_expanded value s:=let n:=navigation_state s in
 let closing_drawer:=negb value&&Navigation.tasks_drawer_open s in
 let next_generation:=if Bool.eqb value(expanded n)&&negb closing_drawer then generation n else N.succ(generation n)in
 let remaining:=if value then layers n else filter(fun panel=>match panel with NavigationPanel TasksDrawer _=>false|_=>true end)(layers n)in
 with_navigation(Navigation(location n)(active_work n)(visits n)value next_generation remaining(side_window n))s.
Definition disclose task group occurrence expanded s:=
 match find(fun r=>N.eqb task(reading_task r))(readers s)with None=>with_readers(Reader task[(group,occurrence,expanded)]::readers s)s|Some r=>
 let ds:=(group,occurrence,expanded)::filter(fun '(a,b,_)=>negb(N.eqb a group&&N.eqb b occurrence))(disclosures r)in
 with_readers(Reader task ds::filter(fun r=>negb(N.eqb task(reading_task r)))(readers s))s end.
Definition initialize_unselected_profiles world s:=
 fold_left(fun s d=>match owner d with NewTask _|Agent _=>
  if String.eqb(read_text "profile" d)""then match initialized_profile d world with Some d'=>save_draft d' s|None=>s end else s|_=>s end)(drafts(authoring_state s))s.
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
Definition source_view_active s := match layers(navigation_state s)with
 |ActivityPanel _ _ (Activities.SourceView _) _ _::_=>true|_=>false end.
Definition consume_object_menu s :=
 let n:=navigation_state s in match layers n with
 |ObjectActionsPanel _ _::rest=>with_navigation(Navigation(location n)(active_work n)(visits n)(expanded n)(generation n)rest(side_window n))s
 |_=>s end.
Definition choose_menu_action now subject key occurrence world s :=
 match ObjectActions.lookup now subject key occurrence world s with
 |None=>reject "StaleAction" "This action menu is no longer current" s
 |Some item=>match ObjectActions.item_availability subject occurrence world s item with
  |ObjectActions.Available=>let trigger:=match layers(navigation_state s)with
    |panel::_=>panel_trigger panel|_=>"main"end in
    let clean:=consume_object_menu s in
    match ObjectActions.item_operation item with
    |ObjectActions.NativeCommand command purpose=>request_direct command purpose trigger clean
    |ObjectActions.MenuDestination destination=>navigate destination clean
    |ObjectActions.MenuEditor e=>refresh_workspace_git e world(open_editor e trigger world clean)end
  |ObjectActions.Unavailable reason|ObjectActions.AssessmentFailed reason=>reject "ActionUnavailable" reason s
  |ObjectActions.Awaiting=>reject "AssessmentPending" "Checking action availability" s end end.
Definition retry_menu_action now subject key occurrence world s :=
 match ObjectActions.lookup_assessment now subject key occurrence world s with
 |Some item=>match ObjectActions.item_availability subject occurrence world s item with
  |ObjectActions.AssessmentFailed _=>keep(with_services(Services.forget_owned_assessment(ObjectActions.item_owner subject item)(service_state s))s)
  |_=>keep s end
 |None=>reject "StaleAction" "This action menu is no longer current" s end.
Definition local_step now input world s : option result :=
  match input with
  |ResetTitlePrompts=>Some(reset_title_prompts world s)
  |ToggleProjectGroup id=>Some(keep(with_collapsed_projects(if existsb(N.eqb id)(collapsed_projects s)then filter(fun old=>negb(N.eqb id old))(collapsed_projects s)else id::collapsed_projects s)s))
  |BeginProjectTask id=>Some(match find_project id world with None=>reject "MissingProject" "The project no longer exists" s|Some _=>let next:=navigate Start s in
    let edited:=edit(NewTask(active_work(navigation_state s)))"project_id"(number id)world(resulting_state next)in
    refresh_active_workspace world(Result(resulting_state edited)(emitted next++emitted edited)(reply edited))end)
  |BeginVoiceNew e=>Some(begin_voice_new e world s)
  |SelectSharedTask work task=>Some(match task with None=>navigate(SharedUI work None)s|Some task=>if task_belongs(Some work)task world then navigate(SharedUI work(Some task))s else reject "WrongWork" "This task does not belong to the selected Work" s end)
  |Navigate r=>Some(navigate r s)|SelectWork w=>Some(refresh_active_workspace world(select_work w world s))
  |CreateWork=>Some(issue(JObject[("op",JString "create_work")])(WorkCreation(generation(navigation_state s)))s)
  |OpenEditor e trigger=>Some(refresh_workspace_git e world(open_editor e trigger world s))
  |OpenNavigation kind trigger=>Some(open_navigation kind trigger s)
  |OpenObjectActions subject trigger=>Some(open_object_actions subject trigger s)
  |MenuAction subject key occurrence=>Some(choose_menu_action now subject key occurrence world s)
  |RetryMenuAssessment subject key occurrence=>Some(retry_menu_action now subject key occurrence world s)
  |RepairSubject e revision name trigger=>Some(repair_subject e revision name trigger world s)
  |OpenActivity e request trigger=>Some(refresh_active_workspace world(open_activity e request trigger world s))
  |ActivityView occurrence view=>Some(request_activity_view occurrence view world s)
  |ActivitySelect occurrence name value=>Some(refresh_active_workspace world(choose_activity_alternative occurrence name value world s))
  |ActivitySearch occurrence query=>Some(search_activity occurrence query world s)
  |ActivityParameter occurrence buffer=>Some(edit_activity_parameter occurrence buffer world s)
  |ActivityComplete occurrence=>Some(complete_activity now occurrence world s)
  |ActivityWorkspaceChange occurrence change=>Some(refresh_active_workspace world(change_activity_workspace occurrence change world s))
  |Edit e name value selection=>let readonly:=source_view_active s in
      let r:=if readonly then reject "ReadOnlySource" "Source information does not edit its parent" s else edit_application e name value world s in
      let r:=if existsb(String.eqb name)["roots";"primary_root";"project_id"]then refresh_workspace_git e world r else r in
      if String.eqb name "message"then Some(match reply r with
       |JNull=>push_effects(emitted r)(observe_skills e selection world(resulting_state r))|_=>r end)else Some r
  |RetryWorkspace e trigger=>Some(retry_workspace now e trigger world s)
  |DirectoriesCompleted ticket outcome=>Some(directories_completed world ticket outcome s)
  (* DEFENSE: The public input entry may receive an edit or submission captured
     before a source child opened; that child has no parent editing authority. *)
  |Submit e trigger=>Some(if source_view_active s then reject "ReadOnlySource" "Source information does not submit its parent" s else submit now e trigger world s)|RemoveAttachment e id=>Some(remove_attachment e id s)
  |Command c=>Some(if connected(service_state s)then match ObjectActions.confirmation_for c with Some(caption,destination,_)=>request_confirmation c caption destination "main" s|None=>queue_command c DirectSubmission s end else reject "Disconnected" "Connect to continue" s)
  |Completed ticket outcome=>Some(complete ticket outcome world s)
  |ServiceInput input=>let r:=service input world s in
      Some(match input with
       |Authenticated _ (inr _)=>if connected(service_state s)then r else refresh_active_workspace world r
       |ChooseDirectory=>refresh_active_workspace world r
       |WorkspaceGitCompleted _ _=>reset_unavailable_local input world s r|_=>r end)|SpeechInput input=>Some(speech input world s)
  |InspectSource e name trigger=>Some(inspect_source e name trigger world s)
  |ClosePanel=>Some(dismiss_panel world s)|OpenInformation kind subject trigger=>Some(open_information kind subject trigger s)
  |Confirm=>Some(confirm world s)|Input.Confirmation c trigger=>Some(match ObjectActions.confirmation_for c with
   |Some(caption,destination,_)=>request_confirmation c caption destination trigger s
   |None=>reject "UnavailableConfirmation" "This command has no confirmation activity" s end)
  |BeginSide parent trigger=>Some(issue(JObject[("op",JString "open_side_conversation");("task_id",number parent);("message",content ""[])])(SideCreation parent(generation(navigation_state s))trigger)s)
  |ShowSide t trigger=>Some(show_side t trigger world s)|CloseSide=>Some(close_side s)
  |NavigationExpanded expanded=>Some(effects(set_expanded expanded s)[Focus "navigation-toggle"])
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
