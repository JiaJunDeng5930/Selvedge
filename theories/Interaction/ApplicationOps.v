From Selvedge.Kernel Require Import WorkspaceBackend.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers Schema.
From Selvedge.Kernel Require Import Commands Streams Codec.
From Selvedge.Kernel Require Search.
From Selvedge.Interaction Require Import Codec Identity Resource Services Forms Speech Experience ExperienceObservation ExperienceAssessment Activities ApplicationState.
From Selvedge.Interaction Require CommandAssessment ObjectActions.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Inductive effect := Execute(ticket:N)(command:public_command) | Service(effect:service_effect)
| FollowLatest(task:N) | PersistModelPreference(profile effort:string)
| Audio(effect:speech_effect) | Focus(key:string) | RestoreFocus(key:string) | ScrollTo(task message:N)
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
|RestoreFocus key=>JObject[("type",JString "focus");("key",JString key);("fallback",JString "main")]
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
  |Message id|Execution id=>find_task id world
  |Project(Some id)=>find_project id world
  |Card(Some id)=>find_world "cards" "card_id" id(value_or JNull(field "board" world))
  |Agent(Some id)=>find_world "agents" "agent_id" id(value_or JNull(field "board" world))
  |TaskGraph(Some id) _=>find_world "graphs" "graph_id" id world
  |WorkName id=>find_work id world
  |TitlePrompts=>field "title_settings" world
  |_=>None end in
  d<-initialized_profile d world;;
  match source with None=>match e with Message _|Execution _|Project(Some _)|Card(Some _)|Agent(Some _)|TaskGraph(Some _) _|WorkName _=>None|_=>Some d end|Some source=>
    let source:=match e with
    |Project _=>match field "workspace" source with Some(JObject ws)=>JObject(object_fields source++ws)|_=>source end
    |Agent _=>JObject(object_fields source++object_fields(context_snapshot(value_or JNull(field "settings" source))))
    |Execution _=>let settings:=value_or JNull(field "settings" source)in
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
 let d:=match e with Project _|TitlePrompts|Execution _=>with_revision(next(authoring_state s))d|_=>d end in
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
Definition open_activity e request trigger world s :=
  let s:=match find_draft e s with Some d=>match status d with Accepted _=>
    let a:=authoring_state s in with_authoring(Authoring(filter(fun d=>negb(same_editor e(owner d)))(drafts a))(next a)(awaiting a)(history_search a)(skill_catalogs a)(mentions a))s
    |_=>s end|None=>s end in
  match ensure e world s with None=>reject "InvalidSnapshot" "Cannot initialize the editor from its current values" s
  |Some(d,s)=>match build_activity request d world(service_state s)(editor_pending e s)with
    |None=>reject "ActivityUnavailable" "The requested activity does not belong to this editor" s
    |Some activity=>let n:=navigation_state s in let occurrence:=N.succ(generation n)in
      effects(with_navigation(Navigation(location n)(active_work n)(visits n)(expanded n)occurrence
        (ActivityPanel e request(initial_view activity)occurrence trigger::layers n)(side_window n))s)
        [Focus(activity_panel_key e occurrence)]end end.
Definition open_editor e trigger world s := open_activity e EditObject trigger world s.
Definition discard_editor e s :=
 let a:=authoring_state s in
 let fresh:=match find_draft e s with None=>next a|Some d=>N.max(next a)(N.succ(revision d))end in
 let a:=Authoring(filter(fun d=>negb(same_editor e(owner d)))(drafts a))fresh(awaiting a)(history_search a)(skill_catalogs a)(mentions a)in
 with_services(cancel_editor e(service_state s))(with_authoring a s).
Definition close_panel s := let n:=navigation_state s in match layers n with []=>keep s|p::rest=>
  let trigger:=panel_trigger p in
  let s:=match p with ActivityPanel(Execution task) _ _ _ _=>
    if existsb(fun panel=>match panel with ActivityPanel e _ _ _ _=>same_editor e(Execution task)|_=>false end)rest
    then s else discard_editor(Execution task)s|_=>s end in
  effects(with_navigation(Navigation(location n)(active_work n)(visits n)(expanded n)(N.succ(generation n))rest(side_window n))s)[RestoreFocus trigger]end.
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
  changed <- if String.eqb name "approval"&&Json.equal(get "approval" changed)JNull
    then restore_field "reviewer_profile" JNull changed else Some changed;;
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
Definition draft_workspace := ExperienceObservation.resolved_workspace.
Definition workspace_git_available := ExperienceAssessment.workspace_git_available.
Definition first_reason {e}(requirements:list(Experience.obstruction e)):=
 match requirements with []=>None|first::_=>Some(obstruction_message first)end.
Definition domain_obstruction world services d :=
 first_reason(context_requirements d world++body_requirements d world++workspace_requirements d world services).
Definition service_obstruction services d :=
 first_reason(service_requirements d services false).
Definition obstruction world services d :=
 first_reason(assessment_obstructions(assess_draft d world services false)).
Definition voice_obstruction world services d :=
 if cloud_workspace d then Some "Create the cloud task before starting voice" else
 match service_obstruction services d with Some reason=>Some reason|None=>
  match raw_fields d with (name,_)::_=>Some(String.append "Correct the value of " name)
  |[]=>domain_obstruction world services d end end.
Theorem disconnected_submission_is_blocked : forall world s d,
  connected s=false -> obstruction world s d=Some "Connect to continue".
Proof. intros. unfold obstruction,assess_draft,action_requirements,draft_requirements,service_requirements,require_editor.
 rewrite H. reflexivity. Qed.
Definition preparation_workspace := ExperienceAssessment.preparation_workspace.
Definition begin_preparation d workspace trigger s :=
 let services:=service_state s in let t:=Services.next_ticket services in
 let pending:=Preparation t d(generation(navigation_state s))trigger in
 effects(with_services(Services.with_next(N.succ t)(with_preparations(pending::preparations services)services))s)
   [Service(ObserveDirectories t workspace(owner d))].
Definition issue_draft_source snapshot captured trigger source world s :=
  match decode_command command_specs source with
  |None=>reject "InvalidCommand" "The command does not match the public protocol" s
  |Some prepared=>
    let preference:=match owner snapshot,selected_workspace snapshot,natural(get "project_id" snapshot)with
    |NewTask _,CurrentWorkspace,Some id=>Some(id,false)
    |NewTask _,ManagedWorkspace WorkspaceBackend.Local,Some id=>Some(id,true)
    |_,_,_=>None end in
    match preference with
    |None=>queue_command prepared(DraftSubmission snapshot captured trigger)s
    |Some(id,selected)=>match find_project id world with
      |None=>reject "ProjectUnavailable" "The selected project is no longer available" s
      |Some project=>if Bool.eqb selected(flag "create_worktree" project)then
          queue_command prepared(DraftSubmission snapshot captured trigger)s
        else issue(JObject[("op",JString "update_project");("project_id",number id);("create_worktree",JBool selected)])
          (ProjectPreference snapshot prepared captured trigger)s end end end.
Definition submit now e trigger world s :=
  (* DEFENSE: Native inputs can name any editor; Task execution has immediate
     selections and owns no compound draft submission. *)
  if negb(editor_can_submit e)then reject "ExecutionUsesSelection" "Choose an execution value in its owning activity" s else
  let original:=s in
  match ensure e world s with None=>reject "UnknownEditor" "This editor cannot be submitted" s
  |Some(d,s)=>match assessment_outcome(assess_draft d world(service_state s)(editor_pending e s))with
    |PreparationBlocked first _=>reject(obstruction_code first)(obstruction_message first)original
    |DirectoryObservationRequired workspace=>begin_preparation d workspace trigger s
    |PreparationReady=>let source:=match e with Card _=>replace "observed_at"(JString(show_natural now))(command d)|_=>command d end in
      issue_draft_source d(generation(navigation_state s))trigger source world s end end.
Definition retry_workspace now e trigger world s := match find_draft e s with
 |Some d=>match status d with WorkspaceRejected _=>submit now e trigger world(save_draft(with_status Editing d)s)
   |_=>reject "WorkspaceRetryUnavailable" "Only the failed workspace preparation can be retried" s end
 |None=>reject "UnknownEditor" "This editor cannot be submitted" s end.

Definition dismiss_panel (world:json) s := match layers(navigation_state s)with
|ActivityPanel e EditObject PrincipalView _ _::_=>
  match e with Project _|TitlePrompts=>close_panel(discard_editor e s)|_=>close_panel s end
|_=>close_panel s end.
Definition edit_application e name value world s :=
  let readonly:=match layers(navigation_state s)with
    |ActivityPanel parent _ (SourceView _) _ _::_=>same_editor e parent|_=>false end in
  if readonly then reject "ReadOnlySource" "Source information cannot edit its parent" s else
  match e with
  |Execution task=>
    match initialize e world with None=>reject "UnknownTask" "This task can no longer be configured" s
    |Some observed=>match edited_field name value observed world with
      |None=>reject "InvalidField" "This field does not configure the task" s
      |Some changed=>match raw_fields changed with
        |[]=>issue(execution_command task changed)(if String.eqb name "profile"||String.eqb name "reasoning"then ExecutionSelection else DirectSubmission)s
        |_=>match find_draft e s with None=>keep(save_draft changed s)|Some original=>
          keep(save_draft(Draft(owner original)(N.succ(revision original))(values original)(attachments original)(raw_fields changed)Editing)s)end end end end
  |NewTask _=>let result:=edit e name value world s in
    match reply result with JNull=>if String.eqb name "profile"||String.eqb name "reasoning"then
      match find_draft e(resulting_state result)with Some d=>remember_model world(read_text "profile" d,read_text "reasoning" d)result|None=>result end
      else result|_=>result end
  |_=>edit e name value world s end.
Record active_activity := ActiveActivity {
  active_draft:draft; active_request:activity_request; active_view:view_intent;
  active_occurrence:N; active_trigger:string; active_body:activity(owner active_draft)
}.
Definition current_activity occurrence world s :=
  match layers(navigation_state s)with
  |ActivityPanel e request view current trigger::_=>
    (* DEFENSE: A native action may arrive after its view was replaced or closed. *)
    if N.eqb occurrence current then d<-find_draft e s;;
      body<-build_activity request d world(service_state s)(editor_pending e s);;
      Some(ActiveActivity d request view current trigger body)else None
  |_=>None end.
Definition push_activity_view current intent trigger s :=
  let n:=navigation_state s in let occurrence:=N.succ(generation n)in
  let e:=owner(active_draft current)in
  effects(with_navigation(Navigation(location n)(active_work n)(visits n)(expanded n)occurrence
    (ActivityPanel e(active_request current)intent occurrence trigger::layers n)(side_window n))s)
    [Focus(activity_panel_key e occurrence)].
Definition request_activity_view occurrence intent world s :=
  match current_activity occurrence world s with
  |None=>reject "StaleActivity" "This activity view is no longer current" s
  |Some current=>match intent with
    |PrincipalView=>close_panel s
    |_=>let source_allowed:=match intent with SourceView _=>
        match active_request current,active_view current with
        |EditObject,_|Compare WorkspaceFamily,_|Explain WorkspaceFamily,_|_,InspectionView=>true
        |_,_=>false end|_=>true end in
      let readonly:=match active_view current with SourceView _=>true|_=>false end in
      if source_allowed&&negb readonly then
        match admit_view(active_body current)intent with
        |Some _=>push_activity_view current intent(view_entry_key(owner(active_draft current))occurrence intent)s
        |None=>reject "UnavailableView" "This subject is not active in the owning activity" s end
      else reject "UnavailableView" "Open the owning settings inspection before requesting a source" s
    end end.
Definition inspect_source e name trigger world s :=
  match layers(navigation_state s)with
  |ActivityPanel parent request view occurrence _::_=>
    let allowed:=match request,view with EditObject,_|Compare WorkspaceFamily,_|Explain WorkspaceFamily,_|_,InspectionView=>true|_,_=>false end in
    let readonly:=match view with SourceView _=>true|_=>false end in
    if same_editor e parent&&allowed&&negb readonly then
      match current_activity occurrence world s with
      |Some current=>match admit_view(active_body current)(SourceView name)with
        |Some _=>push_activity_view current(SourceView name)trigger s
        |None=>reject "SourceUnavailable" "This subject is not retained by the owning activity" s end
      |None=>reject "SourceUnavailable" "The source activity is no longer current" s end
    else reject "SourceUnavailable" "Open the owning settings inspection first" s
  |_=>reject "SourceUnavailable" "The source belongs to an open settings activity" s end.
Fixpoint apply_assignments {e}(assignments:list(assignment e))d world :=
  match assignments with []=>Some d|assignment::rest=>
    changed<-edited_field(subject_name(assignment_subject assignment))(assignment_json assignment)d world;;
    apply_assignments rest changed world end.
Definition apply_activity_assignments (current:active_activity)(assignments:list(assignment(owner(active_draft current)))) world s :=
  let original:=active_draft current in
  let base:=match owner original with Execution _=>
    observed<-initialize(owner original)world;;Some(with_revision(revision original)observed)
    |_=>Some original end in
  match bind base(fun draft=>apply_assignments assignments draft world)with
  |None=>reject "InvalidSelection" "The selected value is not admitted by this editor" s
  |Some changed=>match raw_fields changed with
    |_::_=>reject "InvalidSelection" "Correct the complete value before applying it" s
    |[]=>let selected:=save_draft changed s in
      match owner changed with
      |Execution task=>issue(execution_command task changed)(ActivitySelection changed(active_occurrence current))selected
      |NewTask _=>let result:=close_panel selected in
        if existsb(fun assignment=>match meaning(subject_description(assignment_subject assignment))with
          ProfileSelection|ReasoningSelection=>true|_=>false end)assignments
        then remember_model world(read_text "profile" changed,read_text "reasoning" changed)result else result
      |_=>close_panel selected end end end.
Definition choose_activity_alternative occurrence name value world s :=
  match current_activity occurrence world s with
  |None=>reject "StaleActivity" "This activity view is no longer current" s
  |Some current=>let exposed:=match active_view current with
    |PrincipalView|SearchView _=>match activity_group(active_body current)with
      Some group=>String.eqb name(subject_name(decision_subject(root_decision group)))|None=>false end
    |DecisionView field=>String.eqb name field|_=>false end in
    if exposed then match choose_json(active_body current)name value with
      Some assignments=>apply_activity_assignments current assignments world s
      |None=>reject "UnavailableChoice" "This alternative is not admitted by the current observation" s end
    else reject "UnavailableChoice" "Open this decision before choosing its value" s end.
Definition edit_activity_parameter occurrence buffer world s :=
  match current_activity occurrence world s with
  |None=>reject "StaleActivity" "This activity view is no longer current" s
  |Some current=>match active_view current with
    |ParameterView name _=>let n:=navigation_state s in
      match layers n with
      |_::rest=>keep(with_navigation(Navigation(location n)(active_work n)(visits n)(expanded n)(generation n)
        (ActivityPanel(owner(active_draft current))(active_request current)(ParameterView name buffer)
          occurrence(active_trigger current)::rest)(side_window n))s)
      |[]=>keep s end
    |_=>reject "UnavailableParameter" "There is no open parameter buffer" s end end.
Definition search_activity occurrence query world s :=
  match current_activity occurrence world s with
  |None=>reject "StaleActivity" "This activity view is no longer current" s
  |Some current=>match active_view current with
    |SearchView _=>let n:=navigation_state s in match layers n with
      |_::rest=>keep(with_navigation(Navigation(location n)(active_work n)(visits n)(expanded n)(generation n)
        (ActivityPanel(owner(active_draft current))(active_request current)(SearchView query)
          occurrence(active_trigger current)::rest)(side_window n))s)
      |[]=>keep s end
    |_=>reject "UnavailableSearch" "Search belongs to the initial model comparison" s end end.
Definition complete_activity now occurrence world s :=
  match current_activity occurrence world s with
  |None=>reject "StaleActivity" "This activity view is no longer current" s
  |Some current=>match active_view current,active_request current with
    |ParameterView name buffer,_=>match complete_parameter(active_body current)name buffer world with
      Some assignments=>apply_activity_assignments current assignments world s
      |None=>reject "InvalidParameter" "The complete value is not permitted by the selected model" s end
    |PrincipalView,EditObject=>submit now(owner(active_draft current))(activity_panel_key(owner(active_draft current))occurrence)world s
    |_,_=>close_panel s end end.
Definition add_workspace_path d path world :=
  if Workspace.valid_path path then
    source<-resolved_workspace d world;;
    let roots:=items "roots" source in
    let roots:=if existsb(Json.equal(JString path))roots then roots else roots++[JString path]in
    let primary:=match field "primary_root" source with Some(JString current)=>JString current|_=>JString path end in
    changed<-choose_workspace roots primary d;;
    changed<-restore_field "directory_entry"(JString "")changed;;
    Some(with_status Editing(with_revision(N.succ(revision d))changed))
  else None.
Definition change_workspace e change world s :=
  match find_draft e s with None=>reject "UnknownEditor" "The workspace draft is no longer available" s
  |Some d=>let changed:=match change with
    |AddDirectory=>add_workspace_path d(trim(read_text "directory_entry" d))world
    |ClearDirectoryEntry=>edit_field "directory_entry"(JString "")d
    |UseInheritedWorkspace=>changed<-use_inherited_workspace d;;
      Some(with_status Editing(with_revision(N.succ(revision d))changed))
    |RemoveDirectory path=>source<-resolved_workspace d world;;
      let roots:=filter(fun value=>negb(Json.equal value(JString path)))(items "roots" source)in
      changed<-edit_field "roots"(JArray roots)d;;workspace_after_edit "roots" changed
    |ChoosePrimary path=>source<-resolved_workspace d world;;
      if existsb(Json.equal(JString path))(items "roots" source)then
        changed<-choose_workspace(items "roots" source)(JString path)d;;
        Some(with_status Editing(with_revision(N.succ(revision d))changed))else None end in
    match changed with Some changed=>keep(save_draft changed s)
    |None=>reject "InvalidWorkspaceEdit" "Use a valid member of the workspace directory collection" s end end.
Definition change_activity_workspace occurrence change world s :=
  match current_activity occurrence world s with
  |None=>reject "StaleActivity" "This activity view is no longer current" s
  |Some current=>let allowed:=match active_view current,active_request current with
    |SourceView _,_=>false
    |_,EditObject|_,Compare WorkspaceFamily|_,Explain WorkspaceFamily=>true|_,_=>false end in
    if allowed then change_workspace(owner(active_draft current))change world s
    else reject "UnavailableWorkspace" "This activity does not own workspace editing" s end.
Definition repair_subject e captured name trigger world s :=
  match find_draft e s with None=>reject "UnknownAction" "The assessed draft no longer exists" s
  |Some d=>
    (* DEFENSE: A repair affordance can outlive the draft revision it assessed. *)
    if N.eqb captured(revision d)then match admit_subject e name with
    |None=>reject "UnknownSubject" "This field does not belong to the assessed editor" s
    |Some subject=>match owner d,meaning(subject_description subject)with
      |Project _,_|_,Scalar|_,DirectoryEntry|_,TaskEnvironmentSelection|_,ProjectWorktreePreference=>effects s[Focus(String.append(editor_key e)(String.append "/" name))]
      |_,role=>let request:=match family role with PermissionFamily=>Explain PermissionFamily|kind=>Compare kind end in
        let opened:=open_activity e request trigger world s in
        match reply opened with JNull=>let selected:=resulting_state opened in
          match layers(navigation_state selected)with ActivityPanel _ _ _ occurrence _::_=>
            match current_activity occurrence world selected with
            |Some current=>let root:=match activity_group(active_body current)with
              |Some group=>String.eqb name(subject_name(decision_subject(root_decision group)))|None=>false end in
              let target:=if root then PrincipalView else if existsb(fun decision=>String.eqb name(subject_name(decision_subject decision)))(activity_decisions(active_body current))
              then DecisionView name else
              match find(fun parameter=>String.eqb name(subject_name(fst parameter)))(activity_parameters(active_body current))with
              |Some(_,OpenEntry)=>ParameterView name(value_or(read_text name d)(raw_text name d))
              |_=>PrincipalView end in
              match target with PrincipalView=>opened|_=>push_effects(emitted opened)(request_activity_view occurrence target world selected)end
            |None=>opened end|_=>opened end
          |_=>opened end
      end end else reject "StaleAction" "The draft changed after this assessment" s end.
Definition admit_directories observation :=
 if String.eqb(text "kind" observation)"directories"then
 workspace_json<-field "workspace" observation;;
 checked<-Selvedge.Kernel.Codec.parse_workspace workspace_json;;
 guidance<-field "guidance" observation;;
 if Selvedge.Kernel.Codec.valid_guidance guidance && Selvedge.Kernel.Codec.guidance_member checked guidance
 then Some(workspace_json,guidance)else None else None.
Definition prepared_command snapshot (observation:json*json) :=
 let '(workspace,_):=observation in
 (* Browser observation establishes preparation readiness. The service observes
    authoritative guidance again at submission; a client cannot supply it. *)
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
         |Some observation=>issue_draft_source snapshot(preparation_generation pending)(preparation_trigger pending)
           (prepared_command snapshot observation)world s end end end
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
  |ConfirmationSubmission occurrence=>
      let n:=navigation_state s in
      if N.eqb occurrence(generation n)then match layers n with
      |ApplicationState.Confirmation command caption destination trigger _::rest=>
        if completion_success outcome then navigate destination s else
        keep(with_navigation(Navigation(location n)(active_work n)(visits n)(expanded n)(generation n)
          (ApplicationState.Confirmation command caption destination trigger(Some(match outcome with inl reason=>reason|inr result=>match field "error" result with Some(JString reason)=>reason|Some error=>text "message" error|None=>text "message" result end end))::rest)(side_window n))s)
      |_=>keep s end else keep s
  |ProjectPreference snapshot prepared captured trigger=>
      if completion_success outcome then issue(encode_command prepared)(DraftSubmission snapshot captured trigger)s
      else keep(settle_draft snapshot outcome s)
  |DraftSubmission snapshot g trigger=>
      let owned:=match find_draft(owner snapshot)s with Some d=>N.eqb(revision d)(revision snapshot)|None=>false end in
      let s:=settle_draft snapshot outcome s in
      if completion_success outcome && owned && N.eqb g(generation(navigation_state s))then
        match owner snapshot,created_task outcome with
        |NewTask _,Some task=>navigate(Conversation task)s
        |Message _,Some task=>if String.eqb(text "op"(encode_command accepted))"open_side_conversation"then
          let n:=navigation_state s in
          effects(with_navigation(Navigation(location n)(active_work n)(visits n)(expanded n)(generation n)(layers n)(Some(SideWindow task trigger)))s)
            [Focus(task_view_key(SideTask task)(String.append(editor_key(Message task))"/message"))]else keep s
        |Message _,None=>keep s
        |Card _,_=>if read_flag "keep_open" snapshot then keep s else close_panel s
        |_,_=>match layers(navigation_state s)with
          |ActivityPanel current _ _ _ _::_=>if same_editor current(owner snapshot)then close_panel s else keep s
          |_=>keep s end end else keep s
  |SideCreation parent g trigger=>
      if completion_success outcome && N.eqb g(generation(navigation_state s)) then
       match location(navigation_state s),created_task outcome with Conversation current,Some task=>
        if N.eqb parent current then let n:=navigation_state s in
         effects(with_navigation(Navigation(location n)(active_work n)(visits n)(expanded n)(generation n)(layers n)(Some(SideWindow task trigger)))s)[Focus(task_view_key(SideTask task)(String.append(editor_key(Message task))"/message"))]else keep s
       |_,_=>keep s end else keep s
  |SearchSubmission q p w=>let old:=history_search(authoring_state s)in
      if String.eqb q(keyword old)&&same_scope p(project_filter old)&&same_scope w(work_filter old)
      then keep(set_search(Search q p w(Some(match outcome with inl error=>failure "SearchFailed" error|inr value=>value end)))s)else keep s
  |WorkCreation g=>if completion_success outcome&&N.eqb g(generation(navigation_state s))then
      match natural_field "work_id"(completion_value outcome)with Some work=>select_work(Some work)world s|None=>keep s end else keep s
  |ActivitySelection snapshot occurrence=>
      let s:=match find_draft(owner snapshot)s with
      |Some current=>if N.eqb(revision current)(revision snapshot)then
          save_draft(with_status(if completion_success outcome then Editing
            else Rejected(completion_error outcome))current)s else s
      |None=>s end in
      let settled:=if completion_success outcome then match layers(navigation_state s)with
        |ActivityPanel e _ _ current _::_=>if same_editor e(owner snapshot)&&N.eqb occurrence current
          then close_panel s else keep s
        |_=>keep s end else keep s in
      if completion_success outcome then remember_accepted_model accepted world settled else settled
  |ExecutionSelection=>if completion_success outcome then remember_accepted_model accepted world(keep s)else keep s
  |LanguageSubmission _ _ _|DirectSubmission=>keep s end.
Definition complete t outcome world s :=
  match find(fun p=>N.eqb t(ticket p))(awaiting(authoring_state s))with
  |None=>keep s
  |Some p=>let s:=set_pending(filter(fun p=>negb(N.eqb t(ticket p)))(awaiting(authoring_state s)))(next(authoring_state s))s in
    complete_purpose(purpose p)(accepted_command p)outcome world s end.
Definition apply_service_effect e world s := match e with
|DirectoryChosen e path=>if editor_pending e s then s else match find_draft e s with
  |Some d=>match add_workspace_path d path world with Some changed=>save_draft changed s
    |None=>save_draft(with_status(Rejected "Use a valid absolute workspace path")d)s end
  |None=>s end
|_=>s end.
Definition service input world s :=
  let workspace_allowed:=match input with OpenDirectory e _ _=>workspace_editor e|_=>true end in
  (* DEFENSE: A native OpenDirectory request may name a Message or Execution
     editor, neither of which owns workspace fields. *)
  if negb workspace_allowed then reject "UnavailableWorkspace" "This editor does not own workspace editing" s else
  let settings_trigger:=match layers(navigation_state s)with
    NavigationPanel GlobalMenu trigger::_=>trigger|_=>"nav/settings"end in
  let s:=match input with OpenSettings|CloseSettings=>let n:=navigation_state s in with_navigation(Navigation(location n)(active_work n)(visits n)(expanded n)(N.succ(generation n))[](side_window n))s|_=>s end in
  let was_connected:=connected(service_state s)in
  let r:=service_step input(service_state s)in
  let services:=match input with OpenSettings=>with_settings_return(Some settings_trigger)(Services.service_state r)|_=>Services.service_state r end in
  let s:=with_services services s in
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

Definition visible_editors s :=
  let n:=navigation_state s in
  (match layers n with ActivityPanel e _ _ _ _::_=>filter editor_can_submit[e]|_=>[]end)++
  (match location n with Start=>[NewTask(active_work n)]|Conversation task=>[Message task]|_=>[]end)++
  match side_task n with Some task=>[Message task]|None=>[]end.
Definition refresh_editor_assessment now world e result :=
  let s:=resulting_state result in
  match find_draft e s with
  |None=>result
  |Some d=>match draft_requirements d world(service_state s)(editor_pending e s),preparation_workspace d,natural_field "sequence" world with
    |[],None,Some sequence=>
      let source:=match e with Card _=>replace "observed_at"(JString(show_natural now))(command d)|_=>command d end in
      match decode_command command_specs source with
      |None=>result
      |Some command=>let assessed:=Services.ensure_assessment(CommandAssessment.DraftOwner e)
          (revision d)sequence command(service_state s)in
        Result(with_services(Services.service_state assessed)s)
          (emitted result++map Service(Services.service_effects assessed))(reply result)
      end
    |_,_,_=>result end end.
Definition refresh_menu_ownership world result :=
  let s:=resulting_state result in let n:=navigation_state s in
  let retained:=ObjectActions.panel_retained world(confirmation_pending s)in
  if forallb retained(layers n)then result else
  (* DEFENSE: another client can delete the object of an open menu or delete confirmation.
     A submitted confirmation awaits its own completion: HTTP publishes the new world first. *)
  let remaining:=filter retained(layers n)in
  Result(with_navigation(Navigation(location n)(active_work n)(visits n)(expanded n)
    (N.succ(generation n))remaining(side_window n))s)
    (emitted result++match remaining with []=>[Focus "main"]|_=>[]end)(reply result).
Definition refresh_preflight now world result :=
  let result:=refresh_menu_ownership world result in
  let clean:=fold_left(fun s draft=>match owner draft with
    |Execution task=>if existsb(fun panel=>match panel with ActivityPanel e _ _ _ _=>same_editor e(Execution task)|_=>false end)
        (layers(navigation_state s))then s else discard_editor(Execution task)s
    |_=>s end)(drafts(authoring_state(resulting_state result)))(resulting_state result)in
  let result:=Result clean(emitted result)(reply result)in
  let result:=fold_left(fun current e=>refresh_editor_assessment now world e current)
    (visible_editors(resulting_state result))result in
  let assessed:=ObjectActions.refresh_menu_assessments now world(resulting_state result)in
  Result(with_services(Services.service_state assessed)(resulting_state result))
    (emitted result++map Service(Services.service_effects assessed))(reply result).
