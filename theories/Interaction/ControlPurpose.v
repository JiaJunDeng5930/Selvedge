From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema.
From Selvedge.Features Require Import BoardFilter.
From Selvedge.Interaction Require Import Codec Identity Input Services Speech CommandAssessment ObjectActions.
From Selvedge.Interaction.Session Require State Navigation Authoring.
From Selvedge.Interaction.Experience Require Model Activity.
From Selvedge.Browser Require ControlPurpose.
Import ListNotations.
Open Scope string_scope.
Module SS:=Selvedge.Interaction.Session.State.
Module P:=Selvedge.Browser.ControlPurpose.
Definition route_symbol route:=match route with
|Start=>"home"|Conversation _=>"conversation"|SharedUI _ _=>"columns"|Projects|ProjectHome _=>"folder"
|Board=>"columns"|Agents=>"agents"|Graphs=>"branch"|HistorySearch=>"search"end.
Definition editor_purpose owner:=match owner with
|Identity.Project None|Identity.Card None|Identity.Agent None|Identity.TaskGraph None _=>P.CreateItem
|Identity.NewTask _|Identity.Message _=>P.MessageSubmission
|Identity.Fork _=>P.ForkTask|Identity.Compact _=>P.CompactTask|_=>P.EditItem end.
Definition command_purpose (command:SS.public_command):=let source:=Schema.encode_command command in
 match string_field "op" source with
 |Some "stop"=>P.StopExecution|Some "freeze"=>P.PauseExecution|Some "unfreeze"=>P.ResumeExecution
 |Some "interrupt"=>P.InterruptExecution|Some "cancel_operation"=>P.AbortOperation
 |Some "review_approval"=>P.ApprovalDecision(flag "allow" source)
 |Some "archive"|Some "archive_card"|Some "delete_work"=>P.ArchiveItem false
 |Some "restore_card"=>P.ArchiveItem true
 |Some "delete_project"|Some "delete_card"|Some "delete_board_agent"|Some "delete_task_graph"=>P.DeleteItem
 |Some "pin_card"=>P.PinItem(negb(flag "pinned" source))
 |Some "board_settings"=>P.AutomaticScheduling(negb(flag "automatic" source))
 |Some "regenerate_card_title"=>P.Regenerate
 |Some "run_card"|Some "run_board_agent"=>P.ResumeExecution
 |_=>P.NamedAction end.
Definition activity_expanded owner request state:=match State.layers(State.navigation_state state)with
|layer::_=>match State.layer_panel layer with State.PropertyPanel actual requested=>
 same_editor owner actual&&String.eqb(Navigation.request_key request)(Navigation.request_key requested)|_=>false end|[]=>false end.
Definition panel_open trigger state := existsb
 (fun layer=>String.eqb trigger (State.layer_trigger layer))
 (State.layers(State.navigation_state state)).
Definition describe snapshot state input:P.purpose:=match input with
|Input.Submit owner _=>editor_purpose owner
|Input.NewCard _ _=>P.CreateItem
|Input.CreateWork=>P.WorkCreation
|Input.BeginTask None=>P.CreateItem|Input.BeginTask(Some _)=>P.ProjectTaskCreation
|Input.OpenEditor owner _=>editor_purpose owner
|Input.Navigate route=>P.NavigateTo(route_symbol route)
|Input.OpenObjectActions subject _=>P.MoreActions(match State.layers(State.navigation_state state)with
 |layer::_=>match State.layer_panel layer with State.ObjectActionsPanel actual=>if CommandAssessment.menu_subject_eq_dec subject actual then true else false|_=>false end|[]=>false end)
|Input.MenuAction subject key _=>match ObjectActions.resolve snapshot state subject key with
 |Some action=>match ObjectActions.command action with Some command=>command_purpose command|None=>match ObjectActions.action_operation action with
  ObjectActions.Editor owner=>editor_purpose owner|ObjectActions.Destination route=>P.NavigateTo(route_symbol route)|_=>P.NamedAction end end|None=>P.NamedAction end
|Input.Command command|Input.Confirmation command _ _ _=>command_purpose command
|Input.OpenNavigation kind trigger=>match kind with GlobalMenu=>P.GlobalDestinations(panel_open trigger state)
 |WorkOverview=>P.OpenPanel "columns" false (panel_open trigger state)|TasksDrawer=>P.OpenPanel "conversation" false (panel_open trigger state) end
|Input.OpenBoard kind trigger=>P.OpenPanel(match kind with State.BoardSettings=>"settings"|State.BoardFilters=>"filter-funnel"|State.ArchivedCards=>"archive-box"end)false (panel_open trigger state)
|Input.BoardToggle category value=>match BoardFilter.parse_category category with
 |Some category=>P.BoardFilterChoice category value|None=>P.NamedAction end
|Input.OpenInformation(SS.CardDetails card) _=>P.OpenCardDetails card
|Input.OpenInformation(SS.TaskDetails task) _=>P.OpenPanel "inspector" false
 (match State.layers(State.navigation_state state)with
  |layer::_=>match State.layer_panel layer with
    |State.InformationPanel(State.TaskDetails actual)=>N.eqb task actual|_=>false end
  |[]=>false end)
|Input.OpenInformation _ _=>P.OpenPanel "inspector" false false
|Input.OpenActivity owner request _=>match request with Activity.WorkspaceActivity|Activity.PropertyActivity Selvedge.Interaction.Experience.Model.WorkspaceProperty=>P.WorkspacePicker(activity_expanded owner request state)
 |_=>P.ChooseValue(activity_expanded owner request state)end
|Input.ActivityAssignment _ _ _=>P.SelectedOption false
|Input.ApplyAssignment _ assignment=>
 match Model.subject_declaration(Activity.assignment_subject assignment)with
 |Fields.SandboxMode|Fields.ApprovalPolicy=>
   match Schema.encode_value (Model.subject_kind(Activity.assignment_subject assignment))
     (Activity.assignment_value assignment)with JNull=>P.ResetDefaults|_=>P.NamedAction end
 |_=>P.NamedAction end
|Input.ActivityFocus _ _ _|Input.InspectSource _ _ _|Input.TogglePropertySource _ _=>P.ShowActivity false
|Input.ClosePanel=>P.Dismiss|Input.CloseSide=>P.Dismiss
|Input.NavigationExpanded _=>P.ToggleNavigation(Navigation.expanded_for false state)
|Input.TaskListVisible _=>P.ToggleNavigation(State.desktop_task_list_visible(State.navigation_state state))
|Input.ToggleProjectGroup project=>P.ProjectDisclosure project
|Input.FollowLatest _=>P.Latest|Input.ResetTitlePrompts=>P.ResetDefaults
|Input.RemoveAttachment _ _|Input.ActivityWorkspaceChange _ (Input.RemoveDirectory _)=>P.RemoveValue
|Input.RetryWorkspace _ _=>P.NamedAction|Input.RetryMenuAssessment _ _ _=>P.RetryTransfer
|Input.ServiceInput input=>match input with
 |Services.Connect|Services.RetryConnection _=>
   match Services.connection(State.service_state state)with
   |Services.ConnectionLoading _=>P.Connect true None
   |Services.ConnectionFailed _ reason|Services.ConnectionRevoked _ reason=>P.Connect false (Some reason)
   |_=>P.Connect false None end
 |Services.OpenSettings=>P.ApplicationSettings(Services.settings_open(State.service_state state))
 |Services.CloseSettings|Services.ClosePreview=>P.Dismiss|Services.CloseDirectory=>P.NamedAction
 |Services.RetryUpload _|Services.RetryAssessment _=>P.RetryTransfer
 |Services.CancelUpload _=>P.AbortOperation|Services.OpenPreview _ _=>P.PreviewFile|Services.Download _=>P.DownloadFile
 |Services.OpenDirectory _ _ _=>P.OpenPanel "folder"false false|_=>P.NamedAction end
|Input.RetainedOutput _ toggle=>P.ShowActivity(negb toggle)
|Input.Interactive _=>P.NamedAction
|_=>P.NamedAction end.
