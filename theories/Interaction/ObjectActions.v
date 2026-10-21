From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers Schema.
From Selvedge.Kernel Require Import Commands.
From Selvedge.Features Require BoardFilter.
From Selvedge.Interaction Require Import Codec Identity Resource Services ApplicationState.
From Selvedge.Interaction Require CommandAssessment.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Inductive menu_operation := NativeCommand(command:public_command)(purpose:pending_purpose)
 | MenuDestination(destination:route) | MenuEditor(owner:editor).
Record menu_item := MenuItem { item_key:string; item_label:string; item_operation:menu_operation }.
Definition native_item key caption purpose op fields :=
 option_map(fun command=>MenuItem key caption(NativeCommand command purpose))
  (decode_command command_specs(JObject(("op",JString op)::fields))).
Definition local_item key caption input := MenuItem key caption(input).
Definition confirmation_for(command:public_command):option(string*route*menu_subject):=
 let value:=encode_command command in
 match string_field "op" value with
 |Some "delete_project"=>id<-natural_field "project_id" value;;Some("Delete project",Projects,ProjectActions id)
 |Some "delete_task_graph"=>id<-natural_field "graph_id" value;;Some("Delete task graph",Graphs,GraphActions id)
 |Some "delete_card"=>id<-natural_field "card_id" value;;Some("Delete card",Board,CardActions id)
 |_=>None end.
Definition confirmation_item command caption :=MenuItem "delete" caption(NativeCommand command DirectSubmission).
Definition subject_value world subject :=match subject with
  |TaskActions task=>find_task task world
  |ProjectActions project=>find_project project world
  |CardActions card=>find_world "cards" "card_id" card(value_or JNull(field "board" world))
  |AgentActions agent=>find_world "agents" "agent_id" agent(value_or JNull(field "board" world))
  |GraphActions graph=>find_world "graphs" "graph_id" graph world end.
Definition subject_live world subject :=match subject_value world subject with Some _=>true|None=>false end.
Definition panel_live world panel :=match panel with
  |ObjectActionsPanel subject _=>subject_live world subject
  |ApplicationState.Confirmation command _ _ _ _=>match confirmation_for command with
    |Some(_,_,subject)=>subject_live world subject|None=>true end
  |_=>true end.
Definition panel_retained world pending panel :=match panel with
  |ApplicationState.Confirmation _ _ _ _ _=>pending||panel_live world panel
  |_=>panel_live world panel end.
Definition menu_owner_live world panel :=match panel with
  |ObjectActionsPanel subject _=>subject_live world subject|_=>true end.
Definition task_items task generation trigger :=
 flat_map(fun '(key,caption)=>match native_item key caption DirectSubmission key[("task_id",number task)]with
   None=>[]|Some item=>[item]end)
  [("interrupt","Interrupt");("freeze","Freeze");("unfreeze","Resume");("stop","Stop");("archive","Archive")]++
 (match native_item "side" "Side conversation"(SideCreation task generation trigger) "open_side_conversation"
   [("task_id",number task);("message",Forms.content ""[])]with
   None=>[]|Some item=>[item]end)++
 [local_item "fork" "Fork"(MenuEditor(Fork task));
  local_item "compact" "Compact"(MenuEditor(Compact task))].
Definition project_items project :=
 [local_item "details" "Project details"(MenuDestination(ProjectHome project));
  local_item "edit" "Edit project"(MenuEditor(Project(Some project)))]++
 match native_item "delete" "Delete project" DirectSubmission "delete_project"[("project_id",number project)]with
  None=>[]|Some item=>[item]end.
Definition card_items now board world card :=
 let identity:=[("card_id",value_or JNull(field "card_id" card));("revision",value_or JNull(field "revision" card));("observed_at",JString(show_natural now))]in
 let command key caption op extra:=match native_item key caption DirectSubmission op(identity++extra)with None=>[]|Some item=>[item]end in
 command "run" "Run" "run_card"[]++
 command "archive" "Archive or restore"(if flag "archived" card then "restore_card"else "archive_card")[]++
 command "pin" "Pin or unpin" "pin_card"[("pinned",JBool(negb(flag "pinned" card)))]++
 command "delete" "Delete" "delete_card"[]++
 command "regenerate" "Regenerate title" "regenerate_card_title"[("draft_profile",JString(text "draft_profile" board))]++
 flat_map(fun stage=>command(String.append "move/" stage)(String.append "Move to " stage)"move_card"[("status",JString stage);("before_card",JString "")])
  (map (text "value") BoardFilter.stage_choices)++
 flat_map(fun other=>match natural_field "card_id" other,natural_field "card_id" card with
 |Some target,Some own=>if negb(flag "archived" other)&&negb(N.eqb target own)then
  command(String.append "before/"(show_natural target))(String.append "Move before "(text "title" other))"move_card"
   [("status",JString(text "status" other));("before_card",JString(show_natural target))]else[]|_,_=>[]end)(items "cards" board)++
 flat_map(fun task=>match natural_field "id" task with None=>[]|Some id=>
  command(String.append "link/"(show_natural id))(String.append "Link "(text "title" task))"link_card"[("task_id",number id)]end)(items "tasks" world).
Definition agent_items agent value :=
 [local_item "edit" "Edit"(MenuEditor(Agent(Some agent)))]++
 match native_item "delete" "Delete" DirectSubmission "delete_board_agent"
  [("agent_id",number agent);("revision",value_or JNull(field "revision" value))]with None=>[]|Some item=>[item]end.
Definition items_for now subject world generation trigger :=
 let board:=value_or JNull(field "board" world)in
  match subject_value world subject with None=>[]|Some value=>match subject with
  |TaskActions task=>task_items task generation trigger
  |ProjectActions project=>project_items project
  |CardActions _=>card_items now board world value
  |AgentActions agent=>agent_items agent value
  |GraphActions _=>[]end end.
Definition assessment_items now world s :=match layers(navigation_state s)with
 |ObjectActionsPanel subject trigger::_=>Some(subject,items_for now subject world(generation(navigation_state s))trigger)
 |ApplicationState.Confirmation command caption _ _ _::_=>
   match confirmation_for command with Some(_,_,subject)=>Some(subject,[confirmation_item command caption])|None=>None end
 |_=>None end.
Definition lookup_assessment now subject key occurrence world s :=
 if N.eqb occurrence(generation(navigation_state s))then
  match assessment_items now world s with Some(current,items)=>
   if CommandAssessment.menu_subject_eq_dec subject current then find(fun item=>String.eqb key(item_key item))items else None
  |None=>None end else None.
Definition active_menu subject occurrence s :=
 N.eqb occurrence(generation(navigation_state s))&&match layers(navigation_state s)with
 |ObjectActionsPanel current _::_=>if CommandAssessment.menu_subject_eq_dec subject current then true else false|_=>false end.
Definition menu_trigger s :=match layers(navigation_state s)with panel::_=>panel_trigger panel|_=>"main"end.
Definition lookup now subject key occurrence world s :=
 if active_menu subject occurrence s then find(fun item=>String.eqb key(item_key item))(items_for now subject world occurrence(menu_trigger s))else None.
Definition item_owner subject item := CommandAssessment.MenuOwner subject(item_key item).
Definition assessment_for subject item s := find(Services.owned_assessment(item_owner subject item))(Services.command_assessments(service_state s)).
Inductive availability := Available | Awaiting | Unavailable(reason:string) | AssessmentFailed(reason:string).
Definition item_availability subject occurrence world s item :=
 match item_operation item with MenuDestination _|MenuEditor _=>Available|NativeCommand command _=>
 if negb(Services.connected(service_state s))then Unavailable "Connect to continue"else
 match natural_field "sequence" world,assessment_for subject item s with
 |Some sequence,Some(Loaded _ request observation)=>
  if CommandAssessment.matches(item_owner subject item)occurrence sequence command request&&
    CommandAssessment.current_owned(item_owner subject item)occurrence sequence observation
  then match CommandAssessment.observed_admission observation with CommandAssessment.Admitted=>Available
    |CommandAssessment.Refused _ reason=>Unavailable reason end else Awaiting
 |Some sequence,Some(Failed _ request reason)=>
  if CommandAssessment.matches(item_owner subject item)occurrence sequence command request
   then AssessmentFailed reason else Awaiting
 |_,_=>Awaiting end end.
Definition confirmation_availability world s command caption :=match confirmation_for command with
 |Some(_,_,subject)=>item_availability subject(generation(navigation_state s))world s(confirmation_item command caption)
 |None=>Unavailable "This command has no confirmation activity"end.
Definition refresh_menu_assessments now world s : Services.service_result :=
 let current:=assessment_items now world s in
 let retained:=filter(fun resource=>match resource_request resource with None=>false|Some request=>
  match CommandAssessment.request_owner request with CommandAssessment.DraftOwner _=>true
  |CommandAssessment.MenuOwner subject _=>match current with None=>false|Some(own,_)=>
   if CommandAssessment.menu_subject_eq_dec subject own then
    N.eqb(CommandAssessment.request_revision request)(generation(navigation_state s))else false end end end)
   (Services.command_assessments(service_state s))in
 let clean:=Services.with_command_assessments retained(service_state s)in
 match current,natural_field "sequence" world with
 |Some(subject,items),Some sequence=>if Services.connected clean then
  fold_left(fun result item=>match item_operation item with MenuDestination _|MenuEditor _=>result|NativeCommand command _=>
   let next:=Services.ensure_assessment(item_owner subject item)(generation(navigation_state s))sequence command(Services.service_state result)in
   Services.ServiceResult(Services.service_state next)(Services.service_effects result++Services.service_effects next)None end)
    items(Services.keep clean)
  else Services.keep clean
 |_,_=>Services.keep clean end.
