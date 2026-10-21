From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema.
From Selvedge.Interaction Require Import Codec Identity Input Services Speech Resource CommandAssessment ObjectActions.
From Selvedge.Interaction.Session Require State Navigation Authoring.
From Selvedge.Interaction.Experience Require Model Activity.
From Selvedge.Browser Require ControlPurpose.
Import ListNotations.
Open Scope string_scope.
Module SS:=Selvedge.Interaction.Session.State.
Module P:=Selvedge.Browser.ControlPurpose.
Definition route_symbol route:=match route with
|Start=>"home"|Conversation _|SharedUI _ _=>"conversation"|Projects|ProjectHome _=>"folder"
|Board=>"columns"|Agents=>"agents"|Graphs=>"branch"|HistorySearch=>"search"end.
Definition editor_purpose owner:=match owner with
|Identity.Project None|Identity.Card None|Identity.Agent None|Identity.TaskGraph None _=>P.CreateItem
|Identity.NewTask _|Identity.Message _=>P.MessageSubmission|_=>P.EditItem end.
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
Definition describe snapshot state input:P.purpose:=match input with
|Input.Submit owner _=>editor_purpose owner
|Input.NewCard _ _=>P.CreateItem
|Input.CreateWork=>P.WorkCreation|Input.BeginProjectTask _=>P.ProjectTaskCreation
|Input.OpenEditor owner _=>editor_purpose owner
|Input.Navigate route=>P.NavigateTo(route_symbol route)
|Input.OpenObjectActions subject _=>P.MoreActions(match State.layers(State.navigation_state state)with
 |layer::_=>match State.layer_panel layer with State.ObjectActionsPanel actual=>if CommandAssessment.menu_subject_eq_dec subject actual then true else false|_=>false end|[]=>false end)
|Input.MenuAction subject key _=>match ObjectActions.resolve snapshot state subject key with
 |Some action=>match ObjectActions.command action with Some command=>command_purpose command|None=>match ObjectActions.action_operation action with
  ObjectActions.Editor owner=>editor_purpose owner|ObjectActions.Destination route=>P.NavigateTo(route_symbol route)|_=>P.NamedAction end end|None=>P.NamedAction end
|Input.Command command|Input.Confirmation command _ _ _=>command_purpose command
|Input.OpenNavigation kind _=>P.OpenPanel(match kind with GlobalMenu=>"menu-lines"|WorkOverview=>"home"|TasksDrawer=>"conversation"end)true false
|Input.OpenBoard kind _=>P.OpenPanel(match kind with State.BoardSettings=>"settings"|State.BoardFilters=>"filter-funnel"|State.ArchivedCards=>"archive-box"end)false false
|Input.OpenInformation(SS.CardDetails card) _=>P.OpenCardDetails card
|Input.OpenInformation _ _=>P.OpenPanel "inspector" false false
|Input.OpenActivity owner request _=>match request with Activity.WorkspaceActivity|Activity.PropertyActivity Selvedge.Interaction.Experience.Model.WorkspaceProperty=>P.WorkspacePicker(activity_expanded owner request state)
 |_=>P.ChooseValue(activity_expanded owner request state)end
|Input.ActivityAssignment _ _ _=>P.SelectedOption false
|Input.ActivityFocus _ _ _|Input.InspectSource _ _ _|Input.TogglePropertySource _ _=>P.ShowActivity false
|Input.ClosePanel|Input.CloseSide=>P.Dismiss
|Input.NavigationExpanded expanded=>P.ToggleNavigation expanded
|Input.ToggleProjectGroup project=>P.ProjectDisclosure project
|Input.FollowLatest _=>P.Latest|Input.ResetTitlePrompts=>P.ResetDefaults
|Input.RemoveAttachment _ _|Input.ActivityWorkspaceChange _ (Input.RemoveDirectory _)=>P.RemoveValue
|Input.RetryWorkspace _ _|Input.RetryMenuAssessment _ _ _=>P.RetryTransfer
|Input.ServiceInput input=>match input with
 |Services.Connect|Services.RetryConnection _=>P.Connect(match Services.connection(State.service_state state)with Resource.Loading _ _=>true|_=>false end)
 |Services.OpenSettings=>P.OpenPanel "settings"false(Services.settings_open(State.service_state state))
 |Services.CloseSettings|Services.CloseDirectory|Services.ClosePreview=>P.Dismiss
 |Services.RetryUpload _|Services.RetryAssessment _=>P.RetryTransfer
 |Services.CancelUpload _=>P.AbortOperation|Services.OpenPreview _ _=>P.PreviewFile|Services.Download _=>P.DownloadFile
 |Services.OpenDirectory _ _ _=>P.OpenPanel "folder"false false|_=>P.NamedAction end
|Input.RetainedOutput _ toggle=>P.ShowActivity(negb toggle)
|Input.Interactive _=>P.NamedAction
|_=>P.NamedAction end.
