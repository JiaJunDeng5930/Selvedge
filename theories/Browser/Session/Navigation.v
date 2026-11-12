From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Programming Require Import Schema.
From Selvedge.Kernel Require Import Commands Search.
From Selvedge.Generated Require Commands.
From Selvedge.Browser Require Import NavigationIdentity.
From Selvedge.Interaction Require Import Codec Identity.
From Selvedge.Programming Require Import Resource.
From Selvedge.Browser.Session Require Import Input.
From Selvedge.Browser Require Import DocumentState.
From Selvedge.Browser.Session Require State Services.
From Selvedge.Interaction.Submission Require Draft.
From Selvedge.Interaction.Experience Require Model Activity.
From Selvedge.Interaction.Submission Require Fields Parameters.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
Import ListNotations.
Open Scope list_scope.
Open Scope string_scope.

Inductive effect := Attend (target:string) | EnsureDraft (owner:editor)
| CancelEditor (owner:editor)
| Issue (command:State.public_command)(purpose:State.pending_purpose)
| LocateHistoryMessage (task index:N) (query:string) | FollowTaskLatest(task:N).
Record result := Result {
 result_state:State.state;
 result_effects:list effect;
 result_error:option json
}.
Definition keep state := Result state [] None.
Definition changed state effects := Result state effects None.
Definition refuse message state := Result state [] (Some(JString message)).
(** Reader generations count semantic visits, independently of DOM publication.
    A task without a prior visit has no retained choice to override following. *)
Definition reader_for state task := match find(fun reader=>N.eqb task(State.reading_task reader))(State.readers state)with
 |Some reader=>reader|None=>State.Reader task 0 State.FollowingLatest [] end.
Definition return_latest state task := match State.reader_position(reader_for state task)with
 |State.ReadingHistory=>true|State.FollowingLatest=>false end.
Definition store_reader reader state := State.with_readers
 (reader::filter(fun current=>negb(N.eqb(State.reading_task reader)(State.reading_task current)))(State.readers state))state.
Definition new_visit task state := let reader:=reader_for state task in
 store_reader(set State.reader_generation N.succ reader)state.
Definition side_layers state := filter(fun layer=>match State.layer_panel layer with State.SideConversationPanel _=>true|_=>false end)(State.layers(State.navigation_state state)).
Definition visible_task_views state :=
 List.app(match State.location(State.navigation_state state)with Conversation task=>[PrimaryTask task]|_=>[]end)
 (fold_right(fun layer rest=>match State.layer_panel layer with State.SideConversationPanel task=>SideTask task::rest|_=>rest end)[]
 (State.layers(State.navigation_state state))).
Definition task_visible state task := existsb(fun view=>N.eqb task(task_view_task view))(visible_task_views state).
Definition shared_occurrence state := match State.location(State.navigation_state state)with
 |SharedUI work task=>Some(DocumentState.SharedOccurrence work task)|_=>None end.
Definition expanded_for (beside:bool) (state:State.state) : bool :=
 if beside then State.desktop_task_list_visible(State.navigation_state state)else
 match State.navigation_intent(State.navigation_state state)with
 |State.AutomaticNavigation=>false|State.OpenNavigation=>true|State.ClosedNavigation=>false end.
Definition same_work lhs rhs := match lhs,rhs with
 |None,None=>true|Some lhs,Some rhs=>N.eqb lhs rhs|_,_=>false end.
Definition visited work navigation := match find(fun visit=>same_work work(fst visit))(State.visits navigation)with
 |Some visit=>snd visit|None=>Start end.
Definition select_scope work navigation :=
 if same_work work(State.active_work navigation)then navigation else
 let location:=match State.location navigation with GraphConversation _ _=>Graphs|other=>other end in
 let previous:=(State.active_work navigation,location)in
 set State.active_work(fun _=>work)
  (set State.visits(fun visits=>previous::filter(fun visit=>negb(same_work(fst previous)(fst visit)))visits)navigation).
Definition after_visit navigation :=
 set State.generation N.succ
  (set State.navigation_intent(fun intent=>match intent with State.OpenNavigation=>State.AutomaticNavigation|intent=>intent end)navigation).
Definition global_route route := match route with Projects|ProjectHome _|Board=>true|_=>false end.
Definition route_allowed snapshot route := match route with
 |GraphConversation (Some work) _=>match DocumentState.find_work work snapshot with Some _=>true|None=>false end
 |Conversation task=>match DocumentState.find_task task snapshot with Some _=>true|None=>false end
 |ProjectHome project=>match DocumentState.find_world "projects" "id" project snapshot with Some _=>true|None=>false end
 |SharedUI work selected=>match DocumentState.find_work work snapshot with
   |None=>false|Some _=>match selected with None=>true|Some task=>DocumentState.task_belongs(Some work)task snapshot end end
 |_=>true end.
Definition route_scope snapshot route navigation :=
 if global_route route then select_scope None navigation else match route,State.active_work navigation with
 |GraphConversation work _,_=>select_scope work navigation
 |Conversation task,Some work=>match DocumentState.find_task task snapshot with
   |Some observed=>let owner:=natural_field "work_id" observed in select_scope owner navigation
   |None=>navigation end
 |_,_=>navigation end.
Definition search_state state:=State.history_search(State.authoring_state state).
Definition set_search search state:=State.with_authoring
 (set State.history_search(fun _=>search)(State.authoring_state state))state.
Definition set_search_return origin state:=
 set_search(set State.search_return(fun _=>origin)(search_state state))state.
Definition visit snapshot destination state :=
 if route_allowed snapshot destination then
 let navigation:=route_scope snapshot destination(State.navigation_state state)in
 let navigation:=after_visit(set State.location(fun _=>destination)
   (set State.layers(fun _=>[])navigation))in
 let state:=set_search_return None(State.with_navigation navigation state)in
 let state:=match destination with
 |Conversation task=>new_visit task state
 |_=>state end in
 let draft_effects:=match destination with
 |Conversation task=>[EnsureDraft(Message task);EnsureDraft(NewTask(State.active_work navigation))]
 |Start|GraphConversation _ _=>[EnsureDraft(NewTask(State.active_work navigation))]|_=>[]end in
 let attention:=match destination with
  |Start=>NavigationIdentity.key_part "/main" "creation/title"
  |GraphConversation work _=>NavigationIdentity.key_part(editor_key(NewTask work))"message"
  |HistorySearch=>match State.search_result(search_state state)with
    |Some _=>"/main"|None=>NavigationIdentity.key_part "/main" "heading"end
  |_=>NavigationIdentity.key_part "/main" "heading"end in
 changed state(List.app draft_effects [Attend attention])
 else refuse "The requested destination is no longer available."state.

Definition request_key request:=match request with
 |Activity.PropertyActivity kind=>match kind with Model.ProjectProperty=>"project"|Model.WorkspaceProperty=>"workspace"|Model.PermissionsProperty=>"permissions"|Model.ModelProperty=>"model"|Model.DeliveryProperty=>"delivery"end
 |Activity.SubjectActivity field=>"field/"++field|Activity.WorkspaceActivity=>"workspace"end.
Definition information_key panel := match panel with
 |State.TaskDetails task=>"task-details/"++show_natural task
 |State.CardDetails card=>"card-details/"++show_natural card
 |State.TaskContext task=>"task-context/"++show_natural task
 |State.PropertySource owner request=>"property-source/"++editor_key owner++"/"++request_key request end.
Definition panel_key panel:=match panel with
 |State.PropertyPanel owner request=>"property/"++editor_key owner++"/"++request_key request
 |State.EditorPanel owner=>"editor/"++editor_key owner
 |State.SideConversationPanel task=>"side-conversation/"++show_natural task
 |State.BoardSettingsPanel=>"board-settings"|State.BoardFiltersPanel=>"board-filters"|State.ArchivedCardsPanel=>"archived-cards"
 |State.NavigationPanel kind=>match kind with GlobalMenu=>"global-navigation"|WorkOverview=>"work-overview"|TasksDrawer=>"tasks-drawer"end
 |State.ObjectActionsPanel subject=>menu_key subject
 |State.CardDecisionPanel card decision=>"card-decision/"++show_natural card++"/"++State.card_decision_key decision
 |State.InformationPanel kind=>information_key kind
 |State.Confirmation _ _ _=>"confirm/cancel"end.
Definition initial_attention panel:=match panel with
 |State.EditorPanel (Identity.TitlePrompts|Identity.Fork _|Identity.TaskGraph _ _)=>
   (* Open at the visible introduction when the standard field is below it or collapsed. *)
   NavigationIdentity.key_part(panel_key panel)"heading"
 |State.InformationPanel(State.TaskDetails _)=>NavigationIdentity.key_part(panel_key panel)"heading"
 |State.EditorPanel owner=>NavigationIdentity.key_part(panel_key panel)(match Parameters.fields owner with []=>"heading"|field::_=>Parameters.name field end)
 |State.PropertyPanel _ _=>NavigationIdentity.key_part(panel_key panel)"heading"
 |State.CardDecisionPanel _ _=>NavigationIdentity.key_part(panel_key panel)"search"
 |_=>panel_key panel end.
Definition panel_initial_attention panel state:=match panel with
 |State.NavigationPanel WorkOverview=>
   (* WorkChoice nodes use the panel key as their parent. *)
   NavigationIdentity.key_part(panel_key panel)(NavigationIdentity.work_key(State.active_work(State.navigation_state state)))
 |_=>initial_attention panel end.
(** Closed layers never return their occurrence to the allocator: a delayed
    event from an earlier opening cannot acquire a later layer's ownership. *)
Definition open_panel panel trigger state :=
 let navigation:=State.navigation_state state in
 let occurrence:=State.next_layer state in
 let attention:=panel_initial_attention panel state in
 let decision:=match panel with State.PropertyPanel owner(Activity.SubjectActivity name)=>Parameters.find_subject_field owner name|_=>None end in
 let layer:=State.Layer panel trigger attention "" occurrence false decision None None false in
 let layers:=layer::filter(fun current=>negb(String.eqb(panel_key panel)(panel_key(State.layer_panel current))))(State.layers navigation)in
 changed(State.with_next_layer(N.succ occurrence)(State.with_navigation(set State.layers(fun _=>layers)navigation)state))
 [Attend attention].
Definition close_panel state := match State.layers(State.navigation_state state)with
 |[]=>keep state
 |layer::rest=>changed(State.with_navigation(set State.layers(fun _=>rest)(State.navigation_state state))state)[Attend(State.layer_trigger layer)]end.
Definition handoff (open_next:string->State.state->result) layer state :=
 open_next (State.layer_trigger layer) (result_state(close_panel state)).
Definition open_card_decision card decision trigger state :=
 let open_next:=open_panel(State.CardDecisionPanel card decision) in
 match State.layers(State.navigation_state state)with
 |layer::_=>match State.layer_panel layer with
  |State.ObjectActionsPanel(CardActions current)=>
    if N.eqb card current then handoff open_next layer state else open_next trigger state
  |_=>open_next trigger state end
 |[]=>open_next trigger state end.
(** Conversation composers own their drafts outside the dialog as well. *)
Definition discard_draft_on_dismiss owner :=
 match owner with Identity.NewTask _|Identity.Message _=>false|_=>true end.
Definition dismiss_panel state := match State.layers(State.navigation_state state)with
 |layer::_=>match State.layer_panel layer with
  |State.EditorPanel owner=>
    let closed:=close_panel state in
    if discard_draft_on_dismiss owner
    then changed(result_state closed)(CancelEditor owner::result_effects closed)
    else closed
  |_=>close_panel state end
 |[]=>keep state end.
Definition modify_top occurrence modify state :=match State.layers(State.navigation_state state)with
 |[]=>keep state
 |current::rest=>if N.eqb occurrence(State.layer_occurrence current)then
   match modify current with None=>keep state|Some updated=>changed(State.with_navigation(set State.layers(fun _=>updated::rest)(State.navigation_state state))state)[]end
   else keep state end.
Definition same_requested_field lhs rhs:=match lhs,rhs with
|None,None=>true|Some lhs,Some rhs=>if Parameters.field_eq_dec lhs rhs then true else false|_,_=>false end.
Definition request_view occurrence owner source field buffer state:=match State.layers(State.navigation_state state)with
|layer::rest=>if N.eqb occurrence(State.layer_occurrence layer)then
 match State.layer_panel layer with
 |State.PropertyPanel actual _|State.EditorPanel actual=>if same_editor owner actual then
  let changed:=negb(Bool.eqb source(State.layer_source_expanded layer)&&same_requested_field field(State.layer_decision_field layer))in
  let updated:=set State.layer_source_expanded(fun _=>source)(set State.layer_decision_field(fun _=>field)(set State.layer_parameter_buffer(fun _=>buffer)layer))in
  let updated:=if changed then set State.layer_occurrence(fun _=>State.next_layer state)(set State.layer_pending(fun _=>false)(set State.layer_feedback(fun _=>None)updated))else updated in
  let next:=State.with_navigation(set State.layers(fun _=>updated::rest)(State.navigation_state state))state in
  keep(if changed then State.with_next_layer(N.succ(State.next_layer state))next else next)
  else keep state|_=>keep state end else keep state|[]=>keep state end.
Definition leave_request occurrence owner state:=match State.layers(State.navigation_state state)with
|layer::_=>request_view occurrence owner(match State.layer_decision_field layer with Some _=>State.layer_source_expanded layer|None=>false end)None None state
|[]=>keep state end.
Definition editor_available snapshot owner:=match owner with
 |Message task|Fork task|Compact task=>match DocumentState.find_task task snapshot with Some _=>true|None=>false end
 |Project(Some id)=>match DocumentState.find_world "projects" "id" id snapshot with Some _=>true|None=>false end
 |Card(Some id)=>match field "board" snapshot with Some board=>match DocumentState.find_world "cards" "id" id board with Some _=>true|None=>false end|None=>false end
 |CardForConversation task=>match DocumentState.find_task task snapshot with Some _=>true|None=>false end
 |TaskGraph(Some id)_=>match DocumentState.find_world "graphs" "graph_id" id snapshot with Some _=>true|None=>false end
 |WorkName(Some id)=>match DocumentState.find_work id snapshot with Some _=>true|None=>false end
 |NewTask(Some work)=>match DocumentState.find_work work snapshot with Some _=>true|None=>false end
 |_=>true end.
Definition edit_object snapshot owner trigger state:=
 if editor_available snapshot owner then let result:=open_panel(State.EditorPanel owner)trigger state in
 set result_effects(fun effects=>EnsureDraft owner::effects)result
 else refuse "The object is no longer available."state.
Definition begin_graph_conversation snapshot state :=
 let navigation:=State.navigation_state state in
 match State.location navigation,State.layers navigation with
 |Graphs,layer::_=>match State.layer_panel layer with
   |State.EditorPanel(Identity.TaskGraph None work)=>
     visit snapshot (GraphConversation work(State.layer_trigger layer))state
   |_=>keep state end
 |_,_=>keep state end.
Definition return_to_graph_setup snapshot state :=
 match State.location(State.navigation_state state)with
 |GraphConversation work trigger=>
   let returned:=visit snapshot Graphs state in
   edit_object snapshot(Identity.TaskGraph None work)trigger(result_state returned)
 |_=>keep state end.
Definition open_activity snapshot owner request trigger state:=
 if editor_available snapshot owner then
 let prepared:=open_panel(State.PropertyPanel owner request)trigger state in
 let prepared:=match request with Activity.SubjectActivity name=>match Model.admit_subject owner name with
  |Some subject=>set result_state(fun state=>State.with_navigation
    (set State.layers(fun layers=>match layers with layer::rest=>set State.layer_decision_field(fun _=>Some(Model.subject_declaration subject))layer::rest|[]=>[]end)
      (State.navigation_state state))state)prepared
  |None=>prepared end|_=>prepared end in
 set result_effects(fun effects=>EnsureDraft owner::effects)prepared
 else refuse "The object is no longer available."state.
Definition work_available snapshot work := match work with None=>true|Some id=>match DocumentState.find_work id snapshot with Some _=>true|None=>false end end.
Definition overview_open state:=match State.layers(State.navigation_state state)with
 |layer::_=>match State.layer_panel layer with State.NavigationPanel WorkOverview=>true|_=>false end|_=>false end.
Definition message_target state:=let navigation:=State.navigation_state state in match State.location navigation with
 |Conversation task=>NavigationIdentity.message_key(PrimaryTask task)
 |_=>NavigationIdentity.key_part(editor_key(NewTask(State.active_work navigation)))"message"end.
Definition work_focus state:=match State.location(State.navigation_state state)with
 |Start|GraphConversation _ _|Conversation _=>message_target state|_=>NavigationIdentity.key_part "/main" "heading"end.
Definition select_work snapshot work state :=
 if work_available snapshot work then
 let navigation:=State.navigation_state state in
 let overview:=overview_open state in
 if same_work work(State.active_work navigation)then
 let state:=State.with_navigation(after_visit navigation)state in
 if overview then close_panel state else keep state
 else let destination:=visited work navigation in
 let navigation:=select_scope work navigation in
 let result:=visit snapshot destination(State.with_navigation navigation state)in
 set result_effects(fun effects=>EnsureDraft(NewTask work)::
   map(fun effect=>match effect with Attend _=>Attend(work_focus(result_state result))|_=>effect end)effects)result
 else refuse "The Work no longer exists."state.
Definition generated (command : Commands.proposal) purpose state:=
 match Schema.decode_command command_specs(Commands.encode command)with
 |Some command=>changed state[Issue command purpose]
 |None=>refuse "The operation does not match the public command protocol."state end.
Definition selection_intent state:=State.with_navigation
 (set State.generation N.succ(State.navigation_state state))state.
Definition foreground_current navigation layer state:=
 N.eqb navigation(State.generation(State.navigation_state state))&&N.eqb layer(State.next_layer state).
Definition create_work snapshot state:=
 match State.layers(State.navigation_state state)with
 |layer::_=>match State.layer_panel layer with
  |State.NavigationPanel WorkOverview=>handoff (edit_object snapshot(WorkName None)) layer state
  |_=>keep state end
 |[]=>keep state end.
Definition begin_side snapshot task trigger state:=
 match DocumentState.find_task task snapshot with None=>refuse "The task is no longer available."state
 |Some _=>let state:=selection_intent state in
 generated(Commands.Cmd_open_side_conversation(Commands.Build_open_side_conversation task
 (Some(JArray[JObject[("type",JString "text");("text",JString "")]]))None))
 (State.SideCreation task(State.generation(State.navigation_state state))(State.next_layer state)trigger)state end.
Definition side_message_target task:=NavigationIdentity.message_key(SideTask task).
Definition open_side_window task trigger state:=
 let state:=new_visit task state in
 let opened:=open_panel(State.SideConversationPanel task)trigger state in
 changed(result_state opened)[EnsureDraft(Message task);Attend(side_message_target task)].
Definition show_side snapshot task trigger state:=
 match DocumentState.find_task task snapshot with
 |None=>refuse "The side conversation no longer exists."state
 |Some observed=>match natural_field "side_parent" observed with
   |None=>refuse "This task is not a side conversation."state
   |Some parent=>let current:=State.navigation_state state in
    let prepared:=match State.location current with
      |Conversation current=>if N.eqb current parent then keep state else visit snapshot(Conversation parent)state
      |_=>visit snapshot(Conversation parent)state end in
    match result_error prepared with Some _=>prepared|None=>
     let opened:=open_side_window task trigger(result_state prepared)in
     set result_effects(fun effects=>List.app(result_effects prepared)effects)opened
    end end end.
Definition close_side state:=close_panel state.
Definition edit_search query project work state:=match State.location(State.navigation_state state)with
 |HistorySearch=>keep(set_search(State.Search query project work None None None)state)|_=>keep state end.
Definition search_obstruction state : option string :=
 if State.pending_search state then Some "正在搜索…" else
 if negb(Services.connected(State.service_state state))then Some "连接 Selvedge 后即可搜索。" else
 let query:=State.keyword(State.history_search(State.authoring_state state))in
 if Search.valid_query query then None else
 if String.eqb(Search.trim query)""then Some "输入标题或消息中的关键词。" else Some "请输入 1 到 240 个字符。".
Definition submit_search after state:=match State.location(State.navigation_state state)with
 |HistorySearch=>let search:=State.history_search(State.authoring_state state)in
 match search_obstruction state with Some _=>keep state|None=>
 let ticket:=State.next(State.authoring_state state)in
 let state:=set_search(State.Search(State.keyword search)(State.project_filter search)(State.work_filter search)None(Some ticket)None)state in
 generated(Commands.Cmd_search_history(Commands.Build_search_history(State.keyword search)(State.project_filter search)(State.work_filter search)(Some after)(Some 20%N)(Some true)))
 (State.SearchSubmission(State.keyword search)(State.project_filter search)(State.work_filter search)ticket)state end
 |_=>keep state end.
Definition open_history_result snapshot task index trigger state:=
 let navigation:=State.navigation_state state in
 match State.location navigation with
 |HistorySearch=>
   let visited:=visit snapshot(Conversation task)state in
   match result_error visited with Some _=>visited|None=>
     let origin:=State.SearchOrigin(State.active_work navigation)trigger in
     let state:=set_search_return(Some origin)(result_state visited)in
     match index with
     |None=>changed state(result_effects visited)
     |Some message=>
       let query:=Search.lower(Search.trim(State.keyword(search_state state)))in
       changed(store_reader(set State.reader_position(fun _=>State.ReadingHistory)(reader_for state task))state)
         (List.app(result_effects visited)[LocateHistoryMessage task message query])
     end
   end
 |_=>keep state end.
Definition return_to_history_search snapshot state:=
 let navigation:=State.navigation_state state in
 match State.location navigation,State.search_return(search_state state)with
 |Conversation _,Some origin=>
   let work:=State.search_origin_work origin in
   (* DEFENSE: The originating work group can be removed while the result is
      open. The global search remains available in the current scope. *)
   let state:=if work_available snapshot work then
     State.with_navigation(select_scope work navigation)state else state in
   let returned:=visit snapshot HistorySearch state in
   set result_effects(fun _=>[Attend(State.search_origin_hit origin)])returned
 |_,_=>keep state end.
(** DEFENSE: a scroll observer can finish after its task viewport was closed
    or revisited; only its still-visible visit owns the reading choice. *)
Definition read_current task generation intent state:=
 if task_visible state task && N.eqb generation(State.reader_generation(reader_for state task))then
 keep(store_reader(set State.reader_position(fun _=>intent)(reader_for state task))state)
 else keep state.
Definition follow_latest task state:=if task_visible state task then
 changed(store_reader(set State.reader_position(fun _=>State.FollowingLatest)(reader_for state task))state)
 [FollowTaskLatest task]
 else keep state.
Definition disclose task group occurrence expanded state:=
 if task_visible state task then
 let reader:=reader_for state task in
 let disclosures:=(group,occurrence,expanded)::filter(fun current=>let '(current,_,_):=current in negb(N.eqb group current))(State.disclosures reader)in
 keep(store_reader(set State.disclosures(fun _=>disclosures)reader)state)
 else keep state.
Definition confirm state:=match State.layers(State.navigation_state state)with
 |layer::rest=>match State.layer_panel layer with
   |State.Confirmation command _ _=>if State.layer_pending layer then keep state else
     let navigation:=State.navigation_state state in
     let state:=State.with_navigation(set State.layers(fun _=>set State.layer_pending(fun _=>true)layer::rest)navigation)state in
     changed state[Issue command(State.ConfirmationSubmission(State.generation navigation)(State.layer_occurrence layer))]
   |_=>keep state end
 |[]=>keep state end.
Definition toggle_disclosure id collapsed :=
 if existsb(N.eqb id)collapsed then filter(fun current=>negb(N.eqb id current))collapsed
 else id::collapsed.
Definition step snapshot input state:option result:=match input with
 |Input.Navigate destination=>Some(visit snapshot destination state)
 |Input.SelectWork work=>Some(select_work snapshot work state)
 |Input.CreateWork=>Some(create_work snapshot state)
 |Input.SelectSharedTask work task=>Some(visit snapshot(SharedUI work task)state)
 |Input.OpenNavigation kind trigger=>Some(open_panel(State.NavigationPanel kind)trigger state)
 |Input.OpenObjectActions subject trigger=>Some(open_panel(State.ObjectActionsPanel subject)trigger state)
 |Input.OpenCardDecision card decision trigger=>Some(open_card_decision card decision trigger state)
 |Input.ActivitySearch occurrence query=>Some(modify_top occurrence(fun layer=>
   match State.layer_panel layer with
   |State.PropertyPanel _ (Activity.PropertyActivity Model.ModelProperty)
   |State.CardDecisionPanel _ _|State.BoardFiltersPanel=>Some(set State.layer_query(fun _=>query)layer)
   |_=>None end)state)
 |Input.OpenEditor owner trigger=>Some(edit_object snapshot owner trigger state)
 |Input.BeginGraphConversation=>Some(begin_graph_conversation snapshot state)
 |Input.ReturnToGraphSetup=>Some(return_to_graph_setup snapshot state)
 |Input.OpenBoard kind trigger=>Some(open_panel(match kind with State.BoardSettings=>State.BoardSettingsPanel|State.BoardFilters=>State.BoardFiltersPanel|State.ArchivedCards=>State.ArchivedCardsPanel end)trigger state)
 |Input.OpenActivity owner request trigger=>Some(open_activity snapshot owner request trigger state)
 |Input.OpenInformation kind trigger=>Some(match kind,State.layers(State.navigation_state state)with
   |State.TaskDetails task,layer::_=>match State.layer_panel layer with
     |State.InformationPanel(State.TaskDetails actual)=>if N.eqb task actual then close_panel state
       else open_panel(State.InformationPanel kind)trigger state
     |_=>open_panel(State.InformationPanel kind)trigger state end
   |_,_=>open_panel(State.InformationPanel kind)trigger state end)
 |Input.InspectSource owner request trigger=>Some(open_panel(State.InformationPanel(State.PropertySource owner request))trigger state)
 |Input.TogglePropertySource owner occurrence=>Some(match State.layers(State.navigation_state state)with
 |layer::_=>request_view occurrence owner(negb(State.layer_source_expanded layer))None None state|[]=>keep state end)
 |Input.ClosePanel=>Some(dismiss_panel state)
 |Input.Confirmation command caption destination trigger=>Some(open_panel(State.Confirmation command caption destination)trigger state)
 |Input.Confirm=>Some(confirm state)
 |Input.ActivityFocus occurrence owner focus=>Some(match State.layers(State.navigation_state state)with
 |layer::_=>request_view occurrence owner(State.layer_source_expanded layer)(option_map Model.subject_declaration focus)None state|[]=>keep state end)
 |Input.ActivityParameter occurrence text=>Some(modify_top occurrence(fun layer=>match State.layer_panel layer with
   |State.PropertyPanel _ _|State.EditorPanel(Identity.Project _)=>Some(set State.layer_parameter_buffer(fun _=>Some text)layer)|_=>None end)state)
 |Input.BeginSide task trigger=>Some(begin_side snapshot task trigger state)
 |Input.ShowSide task trigger=>Some(show_side snapshot task trigger state)
 |Input.CloseSide=>Some(close_side state)
 |Input.NavigationExpanded expanded=>let state:=selection_intent state in
   Some(keep(State.with_navigation(set State.navigation_intent(fun _=>if expanded then State.OpenNavigation else State.ClosedNavigation)(State.navigation_state state))state))
 |Input.TaskListVisible visible=>let state:=selection_intent state in
   Some(changed(State.with_navigation(set State.desktop_task_list_visible(fun _=>visible)(State.navigation_state state))state)
    [Attend(if visible then NavigationIdentity.key_part(NavigationIdentity.key_part "/navigation" "header")"toggle"
      else NavigationIdentity.key_part "/global-navigation" "tasks/expand")])
 |Input.ToggleProjectGroup project=>Some(keep(State.with_collapsed
   (toggle_disclosure project(State.collapsed_projects state))state))
 |Input.ToggleTaskBranches task=>Some(keep(State.with_collapsed_tasks
   (toggle_disclosure task(State.collapsed_tasks state))state))
 |Input.WriteHistoryQuery query=>let old:=State.history_search(State.authoring_state state)in Some(edit_search query(State.project_filter old)(State.work_filter old)state)
 |Input.ChooseHistoryScope project scope=>let old:=State.history_search(State.authoring_state state)in Some(edit_search(State.keyword old)(if project then scope else State.project_filter old)(if project then State.work_filter old else scope)state)
 |Input.SubmitHistorySearch after=>Some(submit_search after state)
 |Input.OpenHistoryResult task index trigger=>Some(open_history_result snapshot task index trigger state)
 |Input.ReturnToHistorySearch=>Some(return_to_history_search snapshot state)
 |Input.ReadTimeline task generation intent=>Some(read_current task generation intent state)
 |Input.FollowLatest task=>Some(follow_latest task state)
 |Input.SetDisclosure task group occurrence expanded=>Some(disclose task group occurrence expanded state)
 |_=>None end.
Definition outcome_success(outcome:sum string json):=match outcome with inl _=>false|inr value=>flag "ok" value end.
Definition outcome_result(outcome:sum string json):=match outcome with inl _=>None|inr value=>field "result" value end.
(** Work/side IO must not reclaim selection after navigation or a different
    foreground layer has been opened, even when the page route did not change. *)
Definition complete snapshot purpose outcome state:option result:=match purpose with
 |State.SideCreation parent generation layer_generation trigger=>Some(if negb(outcome_success outcome)then
   Result state [](Some(Codec.command_failure outcome))else
   if N.eqb generation(State.generation(State.navigation_state state))&&N.eqb layer_generation(State.next_layer state)&&task_visible state parent then
   match bind(outcome_result outcome)(natural_field "task_id")with
   |Some task=>open_side_window task trigger state
   |None=>refuse "The side conversation result has no task identity."state end else keep state)
 |State.ConfirmationSubmission generation occurrence=>Some(if N.eqb generation(State.generation(State.navigation_state state))then
   match State.layers(State.navigation_state state)with
   |layer::_=>if N.eqb occurrence(State.layer_occurrence layer)then match State.layer_panel layer with
     |State.Confirmation _ _ destination=>if outcome_success outcome then visit snapshot destination state else
       let diagnostic:=Codec.command_failure outcome in
       let updated:=modify_top occurrence(fun layer=>Some(set State.layer_feedback(fun _=>Some diagnostic)(set State.layer_pending(fun _=>false)layer)))state in
       set result_error(fun _=>Some diagnostic)updated
     |_=>keep state end else keep state
   |[]=>keep state end else keep state)
 |State.SearchSubmission query project work ticket=>let current:=State.history_search(State.authoring_state state)in
   Some(if String.eqb query(State.keyword current)&&same_work project(State.project_filter current)&&same_work work(State.work_filter current)&&match State.search_latest current with Some latest=>N.eqb ticket latest|None=>false end then
    let reply:=match outcome with inl reason=>JObject[("ok",JBool false);("error",JString reason)]|inr value=>value end in
    let page:=State.SearchPage ticket reply in
    keep(set_search(set State.search_result(fun _=>Some page)
      (set State.search_latest(fun _=>None)current))state)else keep state)
 |_=>None end.
