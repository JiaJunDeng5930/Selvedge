From Stdlib Require Import List String Bool NArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Interaction Require Import Codec.
From Selvedge.Browser.Session Require Input Services.
From Selvedge.Browser.Session Require State Navigation NavigationCodec.
From Selvedge.Browser Require Import NavigationIdentity.
From Selvedge.Interaction.Experience Require Read.
From Selvedge.Browser.Scene Require Import Surface Model.
From Selvedge.Browser.Presentation Require Import Navigation Pages Layers ServiceControls Settings.
From Selvedge.Browser.Presentation Require Roles.
From Selvedge.Browser.Scene Require Import Construction.
Import ListNotations.
Open Scope string_scope.

Definition pending_notices (state : State.state) : list (node Input.input) :=
 flat_map (fun pending => match State.outcome_unknown pending with
 |None => []
 |Some reason => [information "/workspace" ("request/" ++ show_natural(State.ticket pending))
   Information.Status ("Connection interrupted. Submission status is unknown. " ++ reason)] end)
 (State.awaiting(State.authoring_state state)).

Definition occurrence_matches occurrence (value:node Input.input):=match layer_region(node_meaning value)with
 |Some behavior=>N.eqb occurrence(layer_occurrence behavior)|None=>false end.
Definition details_header_trigger trigger (value:node Input.input):=
 let 'Node key semantic label role meaning children:=value in
 match role with
 |Roles.DialogHeader=>Node key semantic label role meaning
   (List.app (filter (fun child=>negb(String.eqb (semantic_key child) "close")) children) [trigger])
 |_=>value end.
Definition place_details_trigger occurrence trigger (value:node Input.input):=
 let 'Node key semantic label role meaning children:=value in
 if occurrence_matches occurrence value then Node key semantic label role meaning
   (map (details_header_trigger trigger) children) else value.
Definition workspace_key := "/workspace".
Definition main_key := "/main".
Definition connection_main (state : State.state) : node Input.input :=
 let services:=State.service_state state in
 let connect label:=declared main_key Roles.PrimaryButton
   (primary "connect" label(Input.ServiceInput Services.Connect))in
 let content:=match Services.connection services with
 |Services.ConnectionFailed _ reason|Services.ConnectionRevoked _ reason=>
   [information main_key "connection-failed" Information.Status "无法连接 Selvedge。";
    information main_key "connection-reason" Information.Description reason;connect "重新连接"]
 |Services.ConnectionDormant=>
   [information main_key "not-connected" Information.Description "连接 Selvedge 后即可打开对话。";connect "连接"]
 |Services.ConnectionLoading _|Services.ConnectionReady _=>
   [information main_key "connecting" Information.Status "正在连接 Selvedge…"]
 end in
 region workspace_key "main" "Selvedge" Roles.Main (title main_key "Selvedge"::content).
Inductive presentation_region := NavigationRegionPart | MainRegionPart | NoticesRegionPart.

Definition task_parent view := match view with
 |PrimaryTask _=>main_key
 |SideTask task=>Selvedge.Browser.Session.Navigation.panel_key(State.SideConversationPanel task)
 end.
Definition view_task_mounted snapshot state view := match view with
 |PrimaryTask task=>match State.location(State.navigation_state state),
    Selvedge.Browser.Session.Navigation.creating_conversation state with
   |Conversation displayed,None=>N.eqb task displayed &&
      match Read.find_task task snapshot with Some _=>true|None=>false end
   |_,_=>false end
 |SideTask task=>existsb (fun layer=>match State.layer_panel layer with
   |State.SideConversationPanel displayed=>N.eqb task displayed|_=>false end)
   (Layers.visible_layers(State.layers(State.navigation_state state))) end.

(* The details layer borrows its trigger when it is modal. Determine the owner
   from the typed route and layer instead of looking through mounted history. *)
Definition details_owner snapshot state capacity : option (State.layer * task_view) :=
 layer<-hd_error(State.layers(State.navigation_state state));;
 match State.layer_panel layer with
 |State.InformationPanel(State.TaskDetails task)=>
   if modal_layer(Layers.behavior state capacity layer) then
     let view:=if String.eqb (State.layer_trigger layer) (part main_key "details")
               then PrimaryTask task else SideTask task in
     if String.eqb (State.layer_trigger layer) (part (task_parent view) "details") &&
        view_task_mounted snapshot state view then Some(layer,view) else None
   else None
 |_=>None end.
Definition is_relocated (owner : option (State.layer * task_view)) view := match owner with
 |Some (_,PrimaryTask before)=>match view with PrimaryTask after=>N.eqb before after|_=>false end
 |Some (_,SideTask before)=>match view with SideTask after=>N.eqb before after|_=>false end
 |None=>false end.
Definition relocate_primary (owner : option (State.layer * task_view)) :=
 match owner with Some (_,PrimaryTask _)=>true|_=>false end.
Definition workspace_overlay_with owner snapshot state capacity compact layer :=
 let hide_side_details:=match State.layer_panel layer with
  |State.SideConversationPanel task=>is_relocated owner (SideTask task)|_=>false end in
 let current:=Layers.layer_view snapshot state capacity compact layer hide_side_details in
 match owner with
 |Some (details,view)=>place_details_trigger (State.layer_occurrence details)
   (Pages.task_details_control state(task_view_task view)(task_parent view)) current
 |None=>current end.
Definition view_workspace_overlay snapshot state capacity compact layer :=
 workspace_overlay_with (details_owner snapshot state capacity) snapshot state capacity compact layer.

Inductive overlay_region :=
| DrawerOverlay | WorkspaceOverlay (layer : State.layer) | SettingsOverlay
| ConfigurationOverlay | DirectoryOverlay | PreviewOverlay | LoginOverlay.

Definition workspace_overlay_order state := partition
 (fun layer=>match State.layer_panel layer with
  |State.EditorPanel (Identity.TitlePrompts Identity.ConversationTitles)=>true|_=>false end)
 (rev (Layers.visible_layers (State.layers (State.navigation_state state)))).
Definition view_overlay_plan state : list overlay_region :=
 let '(settings_editors,workspace_layers):=workspace_overlay_order state in
 (* Settings-originated editors return to a Settings row. Service pickers
    can temporarily cover that editor and Settings itself. *)
 (DrawerOverlay :: map WorkspaceOverlay workspace_layers ++
  [SettingsOverlay;ConfigurationOverlay] ++ map WorkspaceOverlay settings_editors ++
  [DirectoryOverlay;PreviewOverlay;LoginOverlay])%list.
Definition overlay_region_identity section := match section with
 |DrawerOverlay=>"drawer"
 |WorkspaceOverlay layer=>"layer/"++Selvedge.Browser.Session.Navigation.panel_key(State.layer_panel layer)
 |SettingsOverlay=>"settings"|ConfigurationOverlay=>"configuration"
 |DirectoryOverlay=>"directory"|PreviewOverlay=>"preview"|LoginOverlay=>"login"end.
Definition overlay_region_descriptor section := match section with
 |WorkspaceOverlay layer=>NavigationCodec.encode_layer layer
 |_=>JString(overlay_region_identity section)end.
Definition overlay_side_task section := match section with
 |WorkspaceOverlay layer=>match State.layer_panel layer with State.SideConversationPanel task=>Some task|_=>None end
 |_=>None end.
Definition overlay_region_with render_layer section snapshot state capacity : list (node Input.input) :=
 match section with
 |DrawerOverlay=>Navigation.navigation_layers snapshot state capacity
 |WorkspaceOverlay layer=>[render_layer layer]
 |SettingsOverlay=>ServiceControls.settings state
 |ConfigurationOverlay=>Settings.configuration_editor state
 |DirectoryOverlay=>ServiceControls.directory_view snapshot state
 |PreviewOverlay=>ServiceControls.preview_view state
 |LoginOverlay=>ServiceControls.account_login_view state end.
Definition view_overlay_region section snapshot state capacity compact :=
 overlay_region_with (view_workspace_overlay snapshot state capacity compact) section snapshot state capacity.
Definition view_region section snapshot state capacity : list (node Input.input) :=
 if Json.equal snapshot JNull then match section with MainRegionPart=>[connection_main state]|_=>[]end
 else match section with
 |NavigationRegionPart=>Navigation.navigation_base snapshot state capacity
 |MainRegionPart=>[Pages.main_with_details snapshot state (relocate_primary (details_owner snapshot state capacity))]
 |NoticesRegionPart=>pending_notices state
 end.

Definition creation_editor state := match State.location(State.navigation_state state),
 Selvedge.Browser.Session.Navigation.creating_conversation state with
 |Start,None|GraphConversation _ _,None=>true|_,_=>false end.
Definition view_composer snapshot state (view : option task_view) : option (node Input.input) :=
 match view with
 |None=>if creation_editor state then Some(Pages.creation_composer snapshot state main_key)else None
 |Some view=>if view_task_mounted snapshot state view
   then Pages.conversation_composer snapshot state view (task_parent view) else None end.
Definition view_creation_introduction snapshot state : option (node Input.input) :=
 if creation_editor state then Some (Pages.creation_introduction snapshot state main_key) else None.
Definition view_task_actions snapshot state capacity task : option (node Input.input) :=
 task_record<-Read.find_task task snapshot;;
 Some(Pages.task_actions_with_details snapshot state task_record main_key
   (is_relocated (details_owner snapshot state capacity) (PrimaryTask task))).
Definition view_side_actions snapshot state capacity task : option (node Input.input) :=
 let view:=SideTask task in
 if view_task_mounted snapshot state view then
   Some(Layers.side_actions snapshot state task (task_parent view)
      (is_relocated (details_owner snapshot state capacity) view)) else None.
Definition view_timeline snapshot state view : option (node Input.input) :=
 let task:=task_view_task view in
 task_record<-Read.find_task task snapshot;;
 Some(Pages.task_timeline snapshot state view (task_parent view) task_record
   (value_or [] (Read.task_operations task snapshot))).
Definition view_approvals snapshot state view : list (node Input.input) :=
 let task:=task_view_task view in
 Pages.approvals snapshot state task (task_parent view)
   (value_or [] (Read.task_operations task snapshot)).
