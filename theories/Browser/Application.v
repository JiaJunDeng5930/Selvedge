From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Programming Require Import Schema Resource.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Browser Require Import NavigationIdentity.
From Selvedge.Interaction Require Import Codec Identity.
From Selvedge.Browser.Session Require Import Input InputCodecs.
From Selvedge.Browser.Presentation Require Import ActionPurpose.
From Selvedge.Browser Require Import Documents DocumentState AuditReading.
From Selvedge.Browser.Session Require State Codec Runtime Authoring Navigation NavigationCodec.
From Selvedge.Browser.Scene Require Construction.
From Selvedge.Interaction.Submission Require DraftCodec.
From Selvedge.Browser.Presentation Require Gesture.
From Selvedge.Browser.Presentation Require Composition.
From Selvedge.Browser.Scene Require Surface Model.
From Selvedge.Browser.Presentation Require View Pages Layers LiveUpdate Projection Navigation.
From Selvedge.Interaction.Experience Require Read.
From Selvedge.Kernel Require Streams.
From Selvedge.Interaction Require Origin CodeSource CommandAssessment World.
From Selvedge.Interaction.Interactive Require Language Types.
From Selvedge.Interaction.Interactive Require State.
From Selvedge.Browser.Interactive Require Render.
From Selvedge.Interaction.Experience Require Activity.
From Selvedge.Interaction.Submission Require Fields Parameters.
From Selvedge.Browser Require Layout Observation Document DOM DirectDOM Focus InputAuthority ControlContent.
Import ListNotations.
Open Scope string_scope.
Module Session:=Selvedge.Browser.Session.State.
Module Services:=Selvedge.Browser.Session.Services.
Module SC:=Selvedge.Browser.Session.Codec.
Module SR:=Selvedge.Browser.Session.Runtime.
Module SA:=Selvedge.Browser.Session.Authoring.
Module S:=Selvedge.Browser.Scene.Surface.
Module V:=Selvedge.Browser.Presentation.View.
Module PNav:=Selvedge.Browser.Presentation.Navigation.
Module CP:=Selvedge.Browser.Presentation.ActionPurpose.
Module BM:=Selvedge.Browser.Scene.Model.
Module UX:=Selvedge.Interaction.Experience.Model.
Definition capacity environment:=match Layout.observe_capacity environment with
|Some(navigation,details)=>Some(BM.Capacity navigation details)
|None=>Some(BM.Capacity false false)end.
Definition environment request:=bind(field "environment" request)Observation.decode_environment.
Definition state request:=bind(field "state" request)SC.decode_state.
Definition compact_picker environment :=
 let width:=Layout.viewport_width environment in
 Nat.leb width 600 && Nat.ltb width (Layout.viewport_height environment).

Definition native_resolver := string -> Gesture.gesture -> json -> option Input.input.
Record control_binding := ControlBinding {
  binding_modal : option string;
  binding_receive : S.receiver Input.input
}.
Record mounted_region := MountedRegion {
  mounted_identity : string;
  mounted_nodes : list (S.node Input.input)
}.
Record published_child_region := PublishedChildRegion {
  child_owner : string;
  child_identity : string;
  child_keys : list string
}.
Record published_controls := PublishedControls {
  published_receivers : S.BindingMap.t control_binding;
  published_modals : list Focus.scope;
  published_regions : list mounted_region;
  published_child_regions : list published_child_region
}.
Definition scoped_node := (option string * S.node Input.input)%type.
Definition bind_control (entry : scoped_node) := S.bind_node (ControlBinding (fst entry)) (snd entry).
Definition some_list {A} (value : option A) := match value with Some item=>[item]|None=>[] end.
Definition overlay_control (node : S.node Input.input) : scoped_node :=
 ((if S.is_modal_node node then Some (S.node_key node) else None), node).
Definition region_receiver_keys (roots : list scoped_node) :=
 let receivers:=fold_right (fun root=>S.bind_node (fun _=>tt) (snd root))
   (S.BindingMap.empty unit) roots in
 map fst (S.BindingMap.elements receivers).
Definition replace_child_region owner identity roots current :=
 let replaced entry:=String.eqb (child_owner entry) owner && String.eqb (child_identity entry) identity in
 let retained:=filter (fun entry=>negb(replaced entry)) current in
 match roots with []=>retained
 |_=>PublishedChildRegion owner identity (region_receiver_keys roots)::retained end.
Definition replace_controls current removed added scopes :=
 let retained := fold_right (@S.unbind_node Input.input control_binding) (published_receivers current) removed in
 PublishedControls (fold_right bind_control retained added) scopes (published_regions current)
   (published_child_regions current).
Definition retire_child_regions current owners :=
 let '(retired,remaining):=partition (fun entry=>existsb (String.eqb (child_owner entry)) owners)
   (published_child_regions current) in
 let receivers:=fold_left (fun bindings entry=>fold_left
   (fun bindings key=>S.BindingMap.remove key bindings) (child_keys entry) bindings)
   retired (published_receivers current) in
 PublishedControls receivers (published_modals current) (published_regions current) remaining.
Definition empty_controls := PublishedControls (S.BindingMap.empty control_binding) [Focus.Document] [] [].
Definition active_scope scopes :=
 match rev scopes with Focus.Temporary key _ _ _ _ :: _ => Some key | _ => None end.
Definition same_scope first second := match first,second with
 |None,None=>true|Some a,Some b=>String.eqb a b|_,_=>false end.
Definition published_input current : native_resolver := fun key gesture value =>
 binding<-S.BindingMap.find key (published_receivers current);;
 if same_scope (binding_modal binding) (active_scope (published_modals current))
 then binding_receive binding gesture value else None.

Record region_root := RegionRoot {
  region_node : scoped_node;
  region_area : Document.area;
  region_source : S.meaning Input.input;
  region_view : option task_view;
  region_append_to : option string
}.
Record region_update := RegionUpdate {
  region_before : list (S.node Input.input);
  region_roots : list region_root;
  region_remove : list string;
  region_scopes : option (list Focus.scope);
  region_with_workspace : bool
}.
(** Native inputs use the bindings of the committed presentation. Full and
    partial publications replace bindings only after their DOM is installed. *)
Record prepared := Prepared {
  prepared_world : json;
  prepared_state : Session.state;
  prepared_encoding : json;
  prepared_environment : option Layout.environment;
  prepared_previous : option (json * Session.state * json * option Layout.environment);
  prepared_stream_update : option (list LiveUpdate.part_update);
  prepared_controls : option published_controls;
  prepared_region_update : option region_update;
  prepared_input : option Input.input
}.
Definition context_for_state snapshot current encoded env :=
 Prepared snapshot current encoded env None None None None None.
Definition with_controls context controls :=
 Prepared (prepared_world context) (prepared_state context) (prepared_encoding context)
   (prepared_environment context) (prepared_previous context) (prepared_stream_update context) controls (prepared_region_update context)
   (prepared_input context).
Definition last_publication context :=
 Some (prepared_world context, prepared_state context, prepared_encoding context, prepared_environment context).
Definition carry_publication previous context :=
 Prepared (prepared_world context) (prepared_state context) (prepared_encoding context)
   (prepared_environment context) (prepared_previous previous) (prepared_stream_update context) (prepared_controls previous)
   (prepared_region_update context) (prepared_input context).
Definition committed context controls :=
 Prepared (prepared_world context) (prepared_state context) (prepared_encoding context)
   (prepared_environment context) (last_publication context) None (Some controls) None None.
Definition with_input context input :=
 Prepared (prepared_world context) (prepared_state context) (prepared_encoding context)
   (prepared_environment context) (prepared_previous context) (prepared_stream_update context) (prepared_controls context)
   (prepared_region_update context) (Some input).
Definition previous_context context :=
 publication<-prepared_previous context;;
 let '(world, current, encoding, env):=publication in
 Some (with_controls (context_for_state world current encoding env) (prepared_controls context)).
Definition prepare request :=
 snapshot<-field "world" request;; current<-state request;;
 let env:=environment request in
 Some(context_for_state snapshot current (SC.encode_state current) env).
(** Rebase discards pending patches and keeps the controls still mounted in the browser. *)
Definition rebase request context :=
 snapshot<-field "world" request;;
 Some(carry_publication context (context_for_state snapshot (prepared_state context) (prepared_encoding context) (environment request))).
Definition with_state context current :=
 let encoded:=SC.encode_state current in
 if Json.equal(prepared_encoding context)encoded then context else
 let snapshot:=prepared_world context in let env:=prepared_environment context in
 carry_publication context (context_for_state snapshot current encoded env).

Definition without_fields excluded value := match value with
 |JObject fields=>JObject(filter(fun field=>negb(existsb(String.eqb(fst field))excluded))fields)
 |_=>value end.
Definition materialize_native_roots := @DirectDOM.materialize_roots.
Definition shell_surface (context : prepared) : S.surface Input.input :=
 S.Surface V.workspace_key V.main_key [] [] (Selvedge.Browser.Session.Services.theme
   (Session.service_state (prepared_state context))).
Definition native_document (request : json) (context : prepared) : option ((json * list DOM.node) * prepared) :=
 env<-prepared_environment context;; generation<-natural_field "generation" request;;
 let document := Document.compile_document (CP.describe (prepared_world context) (prepared_state context)) env generation (shell_surface context) in
 let mounted:=context_for_state (prepared_world context) (prepared_state context) (prepared_encoding context) (Some env) in
 Some ((DOM.document_metadata document, [DOM.root document]), with_controls mounted (Some empty_controls)).

Definition conversation_owner view := match view with
 |Some (SideTask task)=>"overlay/layer/"++V.task_parent (SideTask task)
 |_=>"main" end.
Definition remember_fence_roots roots regions :=
 fold_left (fun regions root=>
   let entry:=region_node root in
   replace_child_region (conversation_owner (region_view root)) (S.node_key (snd entry)) [entry] regions)
   roots regions.
Definition native_patch (request : json) (context : prepared) (patch : region_update) : option ((json * list DOM.node) * prepared) :=
 controls<-prepared_controls context;;
 env<-prepared_environment context;; generation<-natural_field "generation" request;;
 let describe := CP.describe (prepared_world context) (prepared_state context) in
 let compile root := Document.compile_node describe env generation (region_area root) false
   (region_source root) (region_view root) None (snd (region_node root)) in
 let append := flat_map (fun root => match region_append_to root with
   |None=>[]|Some target=>[JObject [("key",JString (S.node_key (snd (region_node root))));("target",JString target)]] end)
   (region_roots patch) in
 let updates := flat_map (fun root => Document.target_updates (region_view root) (snd (region_node root))) (region_roots patch) in
 let metadata := JObject ([("remove", JArray (map JString (region_remove patch)));("append", JArray append);
   ("target_updates",JArray (map DOM.update_json updates))] ++ match region_scopes patch with
   |Some scopes=>[("focus_scope",JArray (map DOM.scope_json scopes))]|None=>[]end)%list in
 let next := replace_controls controls (region_before patch) (map region_node (region_roots patch))
   (value_or (published_modals controls) (region_scopes patch)) in
 let children:=remember_fence_roots (region_roots patch) (published_child_regions next) in
 let next:=PublishedControls (published_receivers next) (published_modals next)
   (published_regions next) children in
 Some ((metadata, map compile (region_roots patch)), committed context next).

Definition native_stream (request:json) (context:prepared) : option ((json * list DOM.node) * prepared) :=
 controls<-prepared_controls context;;
 patch<-prepared_stream_update context;; env<-prepared_environment context;;
 generation<-natural_field "generation" request;;
 let describe:=CP.describe(prepared_world context)(prepared_state context)in
 let compile update:=
  let view:=LiveUpdate.updated_view update in
  Document.compile_node describe env generation
   (match view with PrimaryTask _=>Document.PageArea|SideTask _=>Document.DialogArea end)
   false (S.ReadingTimeline view (LiveUpdate.updated_reader_generation update)) (Some view) None
   (LiveUpdate.updated_preview update) in
 Some((JObject[("mode",JString "stream");("targets",JArray(map(fun update=>
    JString(S.node_key(LiveUpdate.updated_preview update)))patch))],map compile patch),committed context controls).

Definition resolve_native_element (resolve:native_resolver) generation raw:=
 incoming<-natural_field "generation" raw;;
 if N.eqb incoming generation then
 key<-string_field "key" raw;;gesture<-bind(string_field "gesture" raw)Gesture.decode_gesture;;
 value<-Some(value_or JNull(field "value" raw));;
 resolve key gesture value else None.
Definition context_element context generation raw :=
 controls<-prepared_controls context;;
 resolve_native_element (published_input controls) generation raw.
Definition admitted_element request context raw :=
 let native:=natural_field "native_displayed_generation" request in
 generation<-native;; input<-context_element context generation raw;;
 if InputAuthority.admit_generation generation input native (natural_field "displayed_generation" request)
 then Some input else None.
Definition decode_input request context raw:=match string_field "op" raw with
|Some "element"=>admitted_element request context raw
|_=>InputCodecs.decode_runtime raw end.

(** A native text edit observes its selection even when its byte offset has not
    moved. Process that observation after accepting the text, so replacement at
    the same caret cannot leave the skill query tied to the previous contents. *)
Definition native_step namespace snapshot lagged input raw current :=
 let decision:=SR.step namespace snapshot lagged input current in
 match SA.result_error decision,Input.native_selection input raw with
 |None,Some selection=>SA.append decision(SR.step namespace snapshot lagged selection(SA.result_state decision))
 |_,_=>decision end.
Definition feedback_update (error:option json) (visible acknowledge:bool) :=
 if visible || acknowledge then match error with
 |Some _=>"replace"|None=>"clear" end else "keep".
Definition browser_state context :=
 let state:=prepared_state context in
 JObject[("services",JObject[("connection",Services.encode_connection(Services.connection(Session.service_state state)))]);
   ("navigation",JObject[("generation",number(Session.generation(Session.navigation_state state)))])].
Definition returned_state (full : bool) context := if full then prepared_encoding context else browser_state context.
Definition decision_packet full context effects error handled visible_error acknowledge (publication_event:string) fence_admitted:=JObject[("state",returned_state full context);
 ("file_handles",JArray(map JString(Selvedge.Browser.Session.Services.retained_file_handles(Session.service_state(prepared_state context)))));
 ("effects",JArray effects);("publication_event",JString publication_event);("error",match error with None=>JNull|Some diagnostic=>diagnostic end);
 ("visible_error",JBool visible_error);("feedback_update",JString(feedback_update error visible_error acknowledge));("handled",JBool handled);
 ("fence_admitted",match fence_admitted with Some value=>JBool value|None=>JNull end);
 ("native_stream",JBool(match prepared_stream_update context with Some _=>true|None=>false end));
 ("native_region",JBool(match prepared_region_update context with Some _=>true|None=>false end))].
Definition refresh_roots context (roots : list region_root) decision :=
 let available:=flat_map (fun root=>S.node_actions (snd (region_node root))) roots in
 SA.append decision (SA.refresh (prepared_world context) available (SA.result_state decision)).

Record region_change := RegionChange {
  changed_identity : string;
  changed_roots : list region_root;
  changed_nodes : list (S.node Input.input);
  changed_owner : option string
}.
Definition broad_change name roots previous := RegionChange name roots previous None.
Definition child_change view name roots previous :=
 RegionChange name roots previous (Some (conversation_owner view)).
Record region_plan := RegionPlan {
  plan_changes : list region_change;
  plan_placements : list json;
  plan_row_cache : list mounted_region;
  plan_scopes : option (list Focus.scope);
  plan_page : bool;
  plan_layers : bool;
  plan_theme : bool
}.
Definition region_node_keys nodes := map (@S.node_key Input.input) nodes.
Definition cached_region controls key :=
 value_or [] (option_map mounted_nodes
   (find (fun entry=>String.eqb key (mounted_identity entry)) (published_regions controls))).
Definition broad_root scope node :=
 RegionRoot (scope,node) Document.OutsideArea S.Region None None.
Definition base_roots nodes := map (broad_root None) nodes.
Definition overlay_roots nodes := map (fun node=>broad_root (fst (overlay_control node)) node) nodes.
Definition placement target before nodes :=
 JObject ([("target",JString target);("keys",JArray(map JString(region_node_keys nodes)))]
   ++ match before with Some key=>[("before",JString key)]|None=>[]end)%list.
Definition changed_fields fields before after :=
 existsb (fun key=>negb(Json.equal (value_or JNull(field key before))
   (value_or JNull(field key after)))) fields.
Definition state_changed fields before after :=
 changed_fields fields (prepared_encoding before) (prepared_encoding after).
Definition state_section name context := value_or JNull (field name (prepared_encoding context)).
Definition section_changed name fields before after :=
 changed_fields fields (state_section name before) (state_section name after).
Definition navigation_without_layers context := without_fields ["layers";"generation"]
 (state_section "navigation" context).
Definition shell_mode_changed before after :=
 match prepared_environment before,prepared_environment after with
 |Some a,Some b=>match capacity a,capacity b with
   |Some x,Some y=>negb(Bool.eqb (BM.navigation_beside_content x) (BM.navigation_beside_content y) &&
     Bool.eqb (BM.details_beside_timeline x) (BM.details_beside_timeline y) &&
     Bool.eqb (compact_picker a) (compact_picker b))
   |_,_=>true end
 |_,_=>true end.
Definition layout_changed before after :=
 match prepared_environment before,prepared_environment after with
 |Some a,Some b=>negb (Nat.eqb (Layout.viewport_width a) (Layout.viewport_width b) &&
    Nat.eqb (Layout.viewport_height a) (Layout.viewport_height b) &&
    Nat.eqb (Layout.root_font_size_milli a) (Layout.root_font_size_milli b))
 |_,_=>true end.
Definition current_route ctx :=
 Session.location (Session.navigation_state (prepared_state ctx)).
Definition context_route_changed before after :=
 negb(Json.equal (encode_route(current_route before)) (encode_route(current_route after))) ||
 section_changed "navigation" ["work"] before after.
Definition world_fields_changed fields before after :=
 changed_fields fields (prepared_world before) (prepared_world after).
Definition task_field_changed fields task before after :=
 changed_fields fields
   (value_or JNull (World.find_task task (prepared_world before)))
   (value_or JNull (World.find_task task (prepared_world after))).
Definition task_availability_changed task before after :=
 let present context:=match Read.find_task task (prepared_world context) with Some _=>true|None=>false end in
 negb(Bool.eqb (present before) (present after)).
Definition task_workspace_changed task before after :=
 let workspace context:=value_or JNull
   (World.find_world "worktrees" "task_id" task (prepared_world context)) in
 negb(Json.equal (workspace before) (workspace after)).
Definition task_title_changed task before after := task_field_changed ["title"] task before after.
Definition task_relation_title_changed identity task before after :=
 let source context:=bind (World.find_task task (prepared_world context))
   (fun entry=>natural_field identity entry) in
 let title context:=bind (source context) (fun id=>option_map Read.task_title
   (Read.find_task id (prepared_world context))) in
 match title before,title after with
 |Some a,Some b=>negb(String.eqb a b)|None,None=>false|_,_=>true end.
Definition navigation_membership_fields entry :=
 let fields:=map (fun key=>value_or JNull(field key entry)) ["id";"work_id";"parent"] in
 let project:=bind (field "settings" entry) (field "project_id") in
 JArray (value_or JNull project::fields).
Definition navigation_world_changed before after :=
 world_fields_changed ["works";"projects"] before after ||
 let topology context:=JArray(map navigation_membership_fields (items "tasks" (prepared_world context))) in
 negb(Json.equal (topology before) (topology after)).
Definition changed_navigation_rows before after :=
 let tasks context:=items "tasks" (prepared_world context) in
 let columns:=["title";"status";"working";"awaitingHuman";"execution_failed"] in
 let changed:=flat_map (fun '(previous,current)=>if changed_fields columns previous current
   then some_list (Read.observe_task current) else []) (combine (tasks before) (tasks after)) in
 changed.
Definition main_world_changed before after :=
 match current_route after with
 |Conversation task=>task_availability_changed task before after
 |Start|GraphConversation _ _=>world_fields_changed
   ["projects";"works";"profiles";"defaults";"worktrees";"graphs"] before after
 |_=>world_fields_changed ["board";"projects";"works";"worktrees";"graphs";"tasks";"profiles"] before after
 end.
Definition detail_actions_changed before after (view : task_view) (size : BM.capacity) :=
 let expanded context:=existsb (fun layer=>match Session.layer_panel layer with
  |Session.InformationPanel(Session.TaskDetails task)=>N.eqb task(task_view_task view)
  |_=>false end) (Session.layers(Session.navigation_state(prepared_state context))) in
 let relocated context:=V.is_relocated
   (V.details_owner (prepared_world context) (prepared_state context) size) view in
 negb (Bool.eqb (expanded before) (expanded after) &&
       Bool.eqb (relocated before) (relocated after)).
Definition pending_key context := option_map Selvedge.Interaction.Submission.Draft.text_value
 (Navigation.creating_conversation (prepared_state context)).
Definition creation_changed before after := match pending_key before,pending_key after with
 |Some a,Some b=>negb(String.eqb a b)|None,None=>false|_,_=>true end.
Definition current_theme context := Selvedge.Browser.Session.Services.theme
 (Session.service_state (prepared_state context)).
Definition document_theme env context := Document.NativeAppearance.theme_name (current_theme context) (Layout.system_dark env).
Definition old_theme env before :=
 match prepared_environment before with Some previous=>document_theme previous before|None=>document_theme env before end.

Definition active_layer_owner current owner :=
 existsb (fun layer=>match Session.layer_panel layer with
 |Session.EditorPanel actual|Session.PropertyPanel actual _=>same_editor actual owner
 |_=>false end) (Session.layers (Session.navigation_state current)).
Definition composer_views current (owner : option editor) : list (option task_view) :=
 let has_owner editor:=match owner with Some e=>same_editor editor e|None=>true end in
 let primary:=match Session.location(Session.navigation_state current)with
  |Start|GraphConversation _ _=>if has_owner (NewTask (Session.active_work(Session.navigation_state current))) then [None] else []
  |_=>[] end in
 (primary ++ flat_map (fun view=>if has_owner (Message(task_view_task view)) then [Some view] else [])
  (Navigation.visible_task_views current))%list.
Definition scoped_view controls view := match view with
 |Some (SideTask task)=>let key:=Construction.part (V.task_parent (SideTask task)) "layer" in
   if existsb (fun scope=>match scope with Focus.Temporary actual _ _ _ _=>String.eqb actual key|_=>false end)
      (published_modals controls) then Some key else None
 |_=>None end.

Definition composer_roots controls context view :=
 let snapshot:=prepared_world context in let current:=prepared_state context in
 let '(area,source):=match view with
 |None=>(Document.CreationArea,S.PageBody(Pages.page_kind snapshot current))
 |Some (PrimaryTask _)=>(Document.PageArea,S.PageContext view)
 |Some (SideTask _)=>(Document.DialogArea,S.PageContext view) end in
 map (fun node=>RegionRoot (scoped_view controls view,node) area source view None)
  (some_list(V.view_composer snapshot current view)).
Definition composer_projection_change controls before after view :=
 let key:=match view with
 |None=>"composer/main"|Some (PrimaryTask _)=>"composer/main"
 |Some (SideTask task)=>"composer/side/"++show_natural task end in
 child_change view key (composer_roots controls after view)
   (map (fun root=>snd(region_node root)) (composer_roots controls before view)).
Definition observed_assessment_owner before incoming := match incoming with
 |Some (Input.ServiceInput (Services.CommandAssessed ticket _))=>
  let assessments:=Services.command_assessments(Session.service_state(prepared_state before))in
  resource<-find (fun resource=>match resource with Loading current _=>N.eqb ticket current|_=>false end) assessments;;
  request<-resource_request resource;;
  Some(CommandAssessment.request_owner request)
 |_=>None end.
Definition composer_input before incoming := match incoming with
 |Some input=>match SR.composer_editor input with
   |Some owner=>Some owner
   |None=>match input with
    |Input.ApplyAssignment owner _|Input.ActivityAssignment _ owner _
    |Input.AttachFiles owner _|Input.RemoveAttachment owner _|Input.Submit owner _
    |Input.RetryWorkspace owner _=>Some owner
    |Input.ServiceInput (Services.CommandAssessed _ _)=>
      match observed_assessment_owner before incoming with Some (CommandAssessment.DraftOwner owner)=>Some owner|_=>None end
    |_=>None end end
 |None=>None end.
Definition main_local context incoming := match incoming with
 |Some (Input.WriteHistoryQuery _)|Some (Input.ChooseHistoryScope _ _)
 |Some (Input.SubmitHistorySearch _)|Some Input.ReturnToHistorySearch
 |Some (Input.BoardQuery _)|Some (Input.BoardTab _)|Some (Input.BoardToggle _ _)
 |Some Input.BoardClear|Some (Input.BoardProfile _)|Some (Input.CardPlaced _ _ _ _ _)
 |Some (Input.CardField _ _ _ _)=>true
 |Some (Input.RetainedOutput _ _)=>match current_route context with
   |Conversation _=>false|_=>true end
 |Some (Input.ApplyAssignment e _)=>match e with NewTask _|Message _=>false|_=>negb(active_layer_owner (prepared_state context) e)end
 |_=>false end.
Definition latest_changed task before after :=
 negb(Bool.eqb (Navigation.return_latest (prepared_state before) task)
   (Navigation.return_latest (prepared_state after) task)).
Definition timeline_project context view :=
 V.view_timeline (prepared_world context) (prepared_state context) view.
Definition reading_controls_changed before incoming task :=
 match observed_assessment_owner before incoming with
 |Some (CommandAssessment.ObjectActionOwner (TaskActions owner) key)=>
   N.eqb owner task && existsb (fun prefix=>String.prefix prefix key) ["approve/";"deny/";"cancel/"]
 |_=>false end.
Definition conversation_change controls (before after:prepared) view identity project :=
 child_change (Some view) (identity++"/"++V.task_parent view)
   (map (fun node=>RegionRoot (scoped_view controls (Some view),node)
      (match view with PrimaryTask _=>Document.PageArea|SideTask _=>Document.DialogArea end)
      (S.PageContext (Some view)) (Some view) None) (project after))
   (project before).
Definition approvals_project context view :=
 V.view_approvals (prepared_world context) (prepared_state context) view.
Definition tail_project context view :=
 let snapshot:=prepared_world context in let task:=task_view_task view in
 match Read.find_task task snapshot with
 |Some entry=>[Pages.task_timeline_tail snapshot (prepared_state context) view (V.task_parent view)
     entry (value_or [] (Read.task_operations task snapshot))]
 |None=>[] end.
Definition discarded_project context view :=
 [Pages.task_discarded_notice (prepared_state context) (task_view_task view) (V.task_parent view)].
Definition title_project context view :=
 let world:=prepared_world context in let parent:=V.task_parent view in
 let task:=task_view_task view in
 match view with
 |PrimaryTask _=>some_list(option_map (fun entry=>Pages.task_title_region world entry parent) (Read.find_task task world))
 |SideTask _=>[Layers.side_heading world task parent] end.
Definition task_title_projection_changed task view before after :=
 task_title_changed task before after ||
 match view with PrimaryTask _=>task_workspace_changed task before after|SideTask _=>false end.
Definition operation_projection_changed task before after :=
 task_field_changed ["operations"] task before after ||
 (world_fields_changed ["profiles"] before after &&
   match Read.task_operations task (prepared_world after) with Some (_::_)=>true|_=>false end).
Definition task_composer_projection_changed task before after :=
 task_field_changed ["status";"working";"control";"queued";"phase";"settings";"profile";"execution_profile";
                     "provider";"model";"reasoning"] task before after ||
 task_workspace_changed task before after ||
 world_fields_changed ["profiles";"defaults";"projects"] before after.
Definition task_actions_projection_changed task before after :=
 let side_children context:=filter (fun entry=>
   match natural_field "side_parent" entry with Some id=>N.eqb task id|None=>false end)
   (items "tasks" (prepared_world context)) in
 let child_ids context:=JArray(map (fun entry=>value_or JNull(field "id" entry)) (side_children context)) in
 task_field_changed ["status";"status_label";"working";"side_parent";"work_id"] task before after ||
 negb(Json.equal (child_ids before) (child_ids after)).
Definition reply_projection_changed task before after :=
 let source context:=Projection.document_context (prepared_world context) (prepared_state context) in
 let retention context:=Session.document_retention (prepared_state context) in
 AuditReading.task_reply_changed (source before) (retention before) (source after) (retention after) task.
Definition discarded_projection_changed task before after :=
 let count context:=Documents.discarded_count task (Session.document_retention (prepared_state context)) in
 negb(N.eqb (count before) (count after)).
Definition scope_equal one other := Json.equal (JArray(map DOM.scope_json one)) (JArray(map DOM.scope_json other)).
Definition replace_region_cache changes current :=
 fold_left (fun cache change=>
  let name:=changed_identity change in
  if existsb (String.eqb name) ["header";"navigation";"main";"notices"] ||
     String.prefix "overlay/" name then
  let nodes:=map (fun root=>snd(region_node root)) (changed_roots change) in
  let remaining:=filter (fun old=>negb(String.eqb name(mounted_identity old))) cache in
  match nodes with []=>remaining|_=>MountedRegion name nodes::remaining end else cache) changes current.
Definition overlay_key layer := "overlay/"++V.overlay_region_identity layer.
Definition overlay_projection_dirty before after incoming snapshot layer :=
 match layer with
 |V.DrawerOverlay=>negb(Json.equal(navigation_without_layers before)(navigation_without_layers after)) ||
   state_changed ["collapsed_projects";"collapsed_tasks"] before after ||
   (snapshot && navigation_world_changed before after)
 |V.WorkspaceOverlay current=>
   match Session.layer_panel current with
   |Session.SideConversationPanel task=>snapshot && task_availability_changed task before after
   |panel=>if snapshot then match panel with
     |Session.InformationPanel(Session.TaskDetails task)=>
       task_availability_changed task before after || task_workspace_changed task before after ||
       task_field_changed ["model";"reasoning";"phase";"status";"status_label";"working";"lineage";
         "tools";"queued_messages";"settings";"work_id"] task before after ||
       task_relation_title_changed "parent" task before after ||
       world_fields_changed ["works";"profiles";"projects"] before after
     |_=>true end else match incoming with
     |Some (Input.ReadTimeline _ _ _)|Some (Input.FollowLatest _)|Some (Input.SetDisclosure _ _ _ _)=>false
     |_=>section_changed "authoring" ["drafts";"pending";"mentions";"skills"] before after ||
         section_changed "services" ["command_assessments";"directory";"preparations";"workspace_git"] before after
     end
   end
 |V.DirectoryOverlay=>section_changed "services" ["directory";"directory_location";"preparations"] before after ||
   section_changed "authoring" ["drafts"] before after
 |V.SettingsOverlay|V.ConfigurationOverlay|V.PreviewOverlay|V.LoginOverlay=>
   snapshot || match incoming with Some (Input.ServiceInput _) |Some (Input.SpeechInput _) => true|_=>false end end.
Definition planned_regions (context : prepared) : option region_plan :=
 controls<-prepared_controls context;; env<-prepared_environment context;; size<-capacity env;;
 let previous:=previous_context context in
 let before:=value_or context previous in
 let first:=match previous with None=>true|_=>false end in
 let world:=prepared_world context in let current:=prepared_state context in
 let online:=negb(Json.equal world JNull) in
 let incoming:=prepared_input context in
 let snapshot:=match incoming with Some Input.Snapshot=>true|_=>false end in
 let connected:=negb (Bool.eqb online (negb(Json.equal (prepared_world before) JNull))) in
 let resized:=layout_changed before context in
 let layout:=shell_mode_changed before context in
 let invalidate:=first || connected || layout in
 let main:=invalidate || (snapshot && main_world_changed before context) ||
   context_route_changed before context || creation_changed before context ||
   main_local context incoming || negb online ||
   state_changed ["board"] before context ||
   section_changed "authoring" ["search"] before context in
 let nav:=invalidate || resized || (snapshot && navigation_world_changed before context) ||
   negb(Json.equal(navigation_without_layers before)(navigation_without_layers context)) ||
   state_changed ["collapsed_projects";"collapsed_tasks"] before context in
 let notices:=invalidate || section_changed "authoring" ["pending"] before context in
 let project part:=V.view_region part world current size in
 let base name nodes:=broad_change name (base_roots nodes) (cached_region controls name) in
 let nav_nodes:=if nav then project V.NavigationRegionPart else [] in
 let headers:=filter Document.is_header nav_nodes in
 let sidebar:=filter Document.is_navigation nav_nodes in
 let main_nodes:=if main then project V.MainRegionPart else [] in
 let notice_nodes:=if notices then project V.NoticesRegionPart else [] in
 let old_layers:=if Json.equal (prepared_world before) JNull then [] else V.view_overlay_plan(prepared_state before) in
 let layers:=if online then V.view_overlay_plan current else [] in
 let old_descriptor layer:=find (fun old=>String.eqb (V.overlay_region_identity layer)(V.overlay_region_identity old)) old_layers in
 let layer_changes:=flat_map (fun layer=>
   let key:=overlay_key layer in
   let old:=cached_region controls key in
   if invalidate || resized || overlay_projection_dirty before context incoming snapshot layer ||
      negb (Json.equal (value_or JNull(option_map V.overlay_region_descriptor(old_descriptor layer)))
         (V.overlay_region_descriptor layer)) then
     [broad_change key (overlay_roots(V.view_overlay_region layer world current size (compact_picker env))) old]
   else []) layers in
 let removed_layers:=flat_map (fun layer=>
   let key:=overlay_key layer in
   if existsb (fun next=>String.eqb key(overlay_key next)) layers then []
   else [broad_change key [] (cached_region controls key)]) old_layers in
 let layers_changed_in_drawer:=existsb (fun change=>String.eqb (changed_identity change)
   (overlay_key V.DrawerOverlay)) (layer_changes++removed_layers)%list in
 let rows:=if snapshot && negb nav && negb layers_changed_in_drawer then
   match changed_navigation_rows before context with
   |[]=>[]
   |changed=>
   let find_changed id:=find (fun task=>N.eqb id (Read.task_id task)) changed in
   flat_map (fun key=>
     let '(nodes,projections):=PNav.project_changed_task_rows (current_route context) find_changed (cached_region controls key) in
     match projections with []=>[]|_=>[(MountedRegion key nodes, projections)] end)
     ["navigation";overlay_key V.DrawerOverlay] end
   else [] in
 let row_changes:=flat_map (fun '(region,projections)=>
   let drawer:=String.eqb (mounted_identity region) (overlay_key V.DrawerOverlay) in
   let roots projection:=
     let scope:=if drawer then Some "/navigation/modal" else None in
     RegionRoot (scope,PNav.projected_task_row projection)
       (if drawer then Document.TouchNavigationArea else Document.NavigationArea) S.Region None None in
   map (fun projection=>broad_change "navigation-row" [roots projection]
      (PNav.previous_row_controls projection)) projections) rows in
 let layers_changed:=match (layer_changes++removed_layers)%list with []=>false|_=>true end in
 let next_layer_nodes:=flat_map (fun layer=>let key:=overlay_key layer in
   match find (fun change=>String.eqb key(changed_identity change)) layer_changes with
   |Some change=>map (fun root=>snd(region_node root)) (changed_roots change)
   |None=>cached_region controls key end) layers in
 let next_scopes:=Document.surface_scopes (filter S.is_modal_node next_layer_nodes) in
 let scopes:=if layers_changed && negb(scope_equal (published_modals controls) next_scopes)
     then Some next_scopes else None in
 let owner:=composer_input before incoming in
 let dirty_composer:=match owner with Some _=>true|_=>false end ||
   state_changed ["speech"] before context ||
   section_changed "authoring" ["drafts";"pending";"skills";"mentions";"draft_model_manual"] before context ||
   section_changed "services" ["command_assessments";"uploads";"preparations";"workspace_git";"model_preference";"connection"] before context in
 let configuring state:=Pages.run_environment_configuring state
   (NewTask(Session.active_work(Session.navigation_state state))) in
 let creation_feedback:=V.creation_editor current &&
   negb(Bool.eqb (configuring(prepared_state before)) (configuring current)) in
 let stable view :=
   V.view_task_mounted (prepared_world before) (prepared_state before) view &&
   V.view_task_mounted world current view &&
   match view with
   |PrimaryTask _=>negb main
   |SideTask _=>negb(existsb (fun change=>String.eqb (changed_identity change)
       ("overlay/layer/"++V.task_parent view)) layer_changes) end in
 let visible:=filter stable (Navigation.visible_task_views current) in
 let composers:=filter (fun view=>match view with
   |Some view=>stable view && (dirty_composer || (snapshot &&
     (task_composer_projection_changed (task_view_task view) before context ||
      match SA.current_command current (Session.current_draft current (Message(task_view_task view))) with
      |Some _=>world_fields_changed ["sequence"] before context|None=>false end)))
   |None=>negb main && (dirty_composer || creation_feedback) end) (composer_views current owner) in
 let lifecycle:=match incoming with
   |Some (Input.Stream _)|Some (Input.RetainedOutput _ _)|Some (Input.ClearDiscarded _)
   |Some (Input.ClockObserved _)|Some Input.EnvironmentObserved=>true
   |_=>snapshot end in
 let assessment_changed:=snapshot && world_fields_changed ["sequence"] before context in
 let admission_pending:=section_changed "authoring" ["pending"] before context in
 let reading_controls view:=reading_controls_changed before incoming (task_view_task view) in
 let per_task view :=
   let task:=task_view_task view in
   let parent:=V.task_parent view in
   let local_reading:=match incoming with
     |Some (Input.SetDisclosure id _ _ _)=>N.eqb task id|_=>false end in
   (* The published cursor counts the append-only task history. Replacing a
      connection or route is already handled by the containing region. *)
   let history:=local_reading || (snapshot && task_field_changed ["cursor"] task before context) in
   let operations:=(snapshot && operation_projection_changed task before context) ||
     ((assessment_changed || admission_pending) &&
       match Read.task_operations task world with Some (_::_)=>true|_=>false end) in
   let tail:=reading_controls view || operations || (lifecycle && reply_projection_changed task before context) ||
     (snapshot && task_field_changed ["working"] task before context) in
   let discarded:=lifecycle && discarded_projection_changed task before context in
   let patch name project:=conversation_change controls before context view name project in
   let title_change:=match view with
     |PrimaryTask _=>patch "title" (fun ctx=>title_project ctx view)
     |SideTask _=>child_change (Some view) ("title/"++parent)
       (map (fun node=>RegionRoot (scoped_view controls (Some view),node)
         Document.DialogArea S.Region None None) (title_project context view))
       (title_project before view) end in
   let latest ctx:=Pages.task_latest_action (prepared_state ctx) task parent in
   let side_origin ctx:=Layers.side_source (prepared_world ctx) task parent in
   ((if history then [patch "timeline" (fun ctx=>some_list(timeline_project ctx view))]
     else (if tail then [patch "timeline-tail" (fun ctx=>tail_project ctx view)] else []) ++
          (if discarded then [patch "discarded" (fun ctx=>discarded_project ctx view)] else []) ++
          (if latest_changed task before context then [patch "latest" latest] else [])) ++
    (if operations || reading_controls view then [patch "approvals" (fun ctx=>approvals_project ctx view)] else []) ++
    (if snapshot && task_title_projection_changed task view before context then
      [title_change] else []) ++
    match view with
    |SideTask _=>if snapshot && task_relation_title_changed "side_parent" task before context
      then [child_change (Some view) ("side-source/"++parent) (map (fun node=>RegionRoot
        (scoped_view controls (Some view),node) Document.DialogArea S.Region None None)
        (side_origin context)) (side_origin before)] else []
    |PrimaryTask _=>[] end)%list in
 let task_changes:=flat_map per_task visible in
 let own_actions view :=
   let parent:=V.task_parent view in
   let relevant:=detail_actions_changed before context view size ||
    (snapshot && task_actions_projection_changed (task_view_task view) before context) ||
    (assessment_changed &&
     match Read.find_task (task_view_task view) world with
     |Some entry=>Read.task_working entry || String.eqb (Read.task_status entry) "frozen" ||
       match Read.task_side_parent world (Read.task_id entry) with Some _=>true|_=>false end
     |None=>false end) ||
    admission_pending ||
    (section_changed "services" ["command_assessments";"connection"] before context &&
       match incoming with Some (Input.ServiceInput _) => true|_=>false end) in
   let roots ctx:=
    let state:=prepared_state ctx in
    let world:=prepared_world ctx in
    let view:=Some view in
    match view with
    |Some (PrimaryTask task)=>map (fun node=>RegionRoot (None,node)
      Document.PageArea (S.PageContext view) view None)
      (some_list(V.view_task_actions world state size task))
    |Some (SideTask task)=>map (fun node=>RegionRoot (scoped_view controls view,node)
      Document.DialogArea S.Region None None)
      (some_list(V.view_side_actions world state size task))
    |None=>[] end in
   if relevant
   then [child_change (Some view) ("actions/"++parent) (roots context) (map (fun root=>snd(region_node root)) (roots before))]
   else [] in
 let actions:=flat_map own_actions visible in
 let introduction:=if negb main && V.creation_editor current &&
   (match incoming with Some (Input.ApplyAssignment _ _)|Some (Input.ServiceInput _) => true|_=>false end)
   then [child_change None "introduction" (base_roots (some_list(V.view_creation_introduction world current)))
    (some_list(V.view_creation_introduction (prepared_world before) (prepared_state before)))] else [] in
 let theme:=first || negb(String.eqb (old_theme env before)(document_theme env context)) in
 let fence:=match prepared_region_update context with
   |Some patch=>if region_with_workspace patch then
      [broad_change "fence" (region_roots patch) (region_before patch)] else []
   |None=>[] end in
 let composer_changes:=map (composer_projection_change controls before context) composers in
 let local_placements view :=
   let parent:=V.task_parent view in
   let conversation:=Construction.part parent "conversation" in
   let target_changes key changes:=flat_map (fun change=>
     if String.eqb (changed_identity change) key
     then map (fun root=>snd(region_node root)) (changed_roots change) else []) changes in
   let key:=match view with PrimaryTask _=>"composer/main"|SideTask task=>"composer/side/"++show_natural task end in
   let composer:=target_changes key composer_changes in
   let new_composer:=match composer with []=>[]|_=>[placement conversation None composer] end in
   let approvals:=target_changes ("approvals/"++parent) task_changes in
   let new_approvals:=match approvals with
     |[]=>[]|_=>
       let before_composer:=if Pages.task_composer_mounted world current view then
         Some(Construction.part parent (Construction.part "region" (Composition.region_name Composition.ComposerInput)))
         else None in
       [placement conversation before_composer approvals] end in
   let source:=target_changes ("side-source/"++parent) task_changes in
   let new_source:=match source with []=>[]|_=>
     [placement (Construction.part parent "body") (Some (Construction.part parent "side/actions")) source] end in
   let latest:=target_changes ("latest/"++parent) task_changes in
   let new_latest:=match latest with []=>[]|_=>
     [placement (Construction.part parent (Construction.part "region" (Composition.region_name Composition.TimelineContent))) None latest] end in
   (new_composer++new_approvals++new_source++new_latest)%list in
 let changes := ((if nav then [base "header" headers; base "navigation" sidebar] else []) ++
   (if main then [base "main" main_nodes] else []) ++ (if notices then [base "notices" notice_nodes]else[]) ++
   layer_changes ++ removed_layers ++ row_changes ++ composer_changes ++ task_changes ++ actions ++ introduction ++ fence)%list in
 let places:=((if nav then [placement V.workspace_key (Some "workspace-body") headers;
  placement "workspace-body" (Some "main-layout") sidebar] else []) ++
  (if main then [placement "main-layout" (Some (String.append V.workspace_key "/beside"))
     ((main_nodes ++ (if notices then notice_nodes else cached_region controls "notices"))%list)] else
    if notices then [placement "main-layout" (Some (String.append V.workspace_key "/beside")) notice_nodes]else[]) ++
  (if layers_changed then [placement (String.append V.workspace_key "/beside") None (filter Document.beside_layer next_layer_nodes);
   placement (String.append V.workspace_key "/overlays") None (filter (fun node=>negb(Document.beside_layer node)) next_layer_nodes)]else[]) ++
  flat_map local_placements visible)%list in
 Some (RegionPlan changes places (map fst rows) scopes main layers_changed theme).
Definition native_planned request context : option ((json * list DOM.node) * prepared) :=
 plan<-planned_regions context;; controls<-prepared_controls context;;
 env<-prepared_environment context;; generation<-natural_field "generation" request;;
 let changes:=plan_changes plan in
 let roots:=flat_map changed_roots changes in
 let old:=flat_map changed_nodes changes in
 let next:=map (fun root=>snd(region_node root)) roots in
 let retained key:=existsb (String.eqb key) (region_node_keys next) in
 let removals:=filter (fun key=>negb(retained key)) (region_node_keys old) in
 let describe:=CP.describe (prepared_world context) (prepared_state context) in
 let compile root:=
   let node:=snd(region_node root) in
   let dom:=Document.compile_node describe env generation (region_area root) false
     (region_source root) (region_view root) None node in
   match S.node_meaning node with
   |S.TaskRow _ _ _ _=>some_list (ControlContent.find_native (Document.task_row_native_key (S.node_key node)) dom)
   |_=>[dom] end in
 let targets:=flat_map (fun root=>Document.target_updates (region_view root) (snd(region_node root))) roots in
 let theme:=document_theme env context in
 let updates:=if plan_theme plan then
   DOM.UpdateTarget "@document/root" [("data-theme",theme)] [("color-scheme",theme)]::targets else targets in
 let updates:=match previous_context context with
  |Some old=>if layout_changed old context then
    DOM.UpdateTarget "selvedge" [] (Document.NativeAppearance.root_properties env)::updates else updates
  |None=>updates end in
 let retired_targets:=map DOM.target (flat_map (Document.target_updates None) old) in
 let target_keys:=map DOM.target targets in
 let removed_targets:=filter (fun key=>negb (existsb (String.eqb key) target_keys)) retired_targets in
 let display:=value_or (published_modals controls) (plan_scopes plan) in
 let replanned:=replace_region_cache changes (published_regions controls) in
 let rows:=plan_row_cache plan in
 let replaced region:=existsb (fun entry=>String.eqb (mounted_identity entry) (mounted_identity region)) rows in
 let mounted:=(rows++filter (fun region=>negb(replaced region)) replanned)%list in
 let replaced_owners:=map changed_identity (filter (fun change=>
   let identity:=changed_identity change in
   String.eqb identity "main" || String.prefix "overlay/layer/" identity) changes) in
 let controls:=retire_child_regions controls replaced_owners in
 let changed_controls:=replace_controls controls old (map region_node roots) display in
 let children:=fold_left (fun regions change=>match changed_owner change with
   |Some owner=>replace_child_region owner (changed_identity change) (map region_node (changed_roots change)) regions
   |None=>if String.eqb (changed_identity change) "fence"
     then remember_fence_roots (changed_roots change) regions else regions end)
   changes (published_child_regions changed_controls) in
 let next_controls:=PublishedControls (published_receivers changed_controls) display mounted children in
 let metadata:=JObject ([("remove",JArray(map JString removals));
    ("place",JArray(plan_placements plan));("page_changed",JBool(plan_page plan));
    ("layers_changed",JBool(plan_layers plan));
    ("removed_target_updates",JArray(map JString removed_targets));
    ("target_updates",JArray(map DOM.update_json updates))]
    ++ match plan_scopes plan with Some scopes=>[("focus_scope",JArray(map DOM.scope_json scopes))]|None=>[]end)%list in
 Some ((metadata,flat_map compile roots),committed context next_controls).
Definition native_region request context :=
 match prepared_region_update context with
 |Some patch=>if region_with_workspace patch then native_planned request context else native_patch request context patch
 |None=>native_planned request context end.
Definition refresh context decision :=
 match planned_regions context with
 |Some plan=>refresh_roots context (flat_map changed_roots (plan_changes plan)) decision
 |None=>decision end.

Definition input_publication input current updated :=
 let changed:=if Input.semantic_change input then "advance" else "present" in
 match input with
 |Input.Snapshot|Input.EnvironmentObserved=>changed
 |_=>if Json.equal current updated then "keep"else changed
 end.
(** A rejected native assignment leaves the domain value unchanged, but the
    browser has already edited its control. Restore that published value even
    when no new page is required. *)
Definition restore_rejected_field input raw decision:=
 match SA.result_error decision,input with
 |Some _,Input.ApplyAssignment _ _|Some _,Input.ActivityAssignment _ _ _=>
  match string_field "op" raw,string_field "key" raw with
  |Some "element",Some key=>SA.Result(SA.result_state decision)
    (SA.result_effects decision++[SA.emit "restore_field_buffer"[("key",JString key)]])
    (SA.result_error decision)(SA.result_visible_error decision)
  |_,_=>decision end
 |_,_=>decision end.

Definition language_owner input := match input with
 |Types.SourceChanged owner _ _ _ _|Types.SourceDisclosure owner|Types.CopyDefinition owner=>Some owner
 |Types.ValueChanged identity _|Types.ActionClicked identity|Types.ViewChanged identity _=>Some (Types.event_owner identity)
 |_=>SR.callback_owner input end.

Definition published_fence namespace context owner : list region_root :=
 let snapshot:=prepared_world context in let state:=prepared_state context in
 let retained:=Session.document_retention state in let authority:=SR.context namespace snapshot state in
 match Documents.publication_identity authority owner retained,
   State.find_block owner (State.blocks (Session.interactive_state state)) with
 |Some identity,Some block=>match CodeSource.document_source identity with
   |CodeSource.Generated _ viewing _ _=>
     let source:=Render.fence_for identity block (Documents.environment authority false) in
     let modal:=match prepared_controls context with Some controls=>active_scope (published_modals controls)|None=>None end in
     flat_map (fun view=>if N.eqb viewing (task_view_task view) then
       let '(scope,area):=match view with
        |PrimaryTask _=>(None,Document.PageArea)
        |SideTask task=>let key:=Construction.part (Navigation.panel_key (Session.SideConversationPanel task)) "layer" in
          (if same_scope modal (Some key) then Some key else None,Document.DialogArea) end in
       [RegionRoot (scope,AuditReading.in_view view (S.map_node Input.Interactive source)) area
       (S.ReadingTimeline view (Session.reader_generation (Navigation.reader_for state viewing))) (Some view) None]
       else []) (Navigation.visible_task_views state)
   |_=>[] end
 |_,_=>[] end.

Definition fence_region namespace owner before after : option region_update :=
 controls<-prepared_controls before;;
 let stable context:=without_fields ["interactive";"documents"] (prepared_encoding context) in
 match published_fence namespace after owner with
 |[]=>None
 |roots=>Some (RegionUpdate (map (fun root=>snd (region_node root)) (published_fence namespace before owner))
     roots [] None (negb (Json.equal (stable before) (stable after)))) end.

Definition requested_region namespace input := match input with
 |Input.Interactive language=>option_map (fence_region namespace) (language_owner language)
 |_=>None end.

Definition finish_input context input raw project stepped :=
 let prepare current:=with_input (with_state context current) input in
 let updated:=prepare(SA.result_state stepped) in
 let changed:=negb (Json.equal (prepared_encoding context) (prepared_encoding updated)) in
 let region:=bind project (fun choose=>choose context updated) in
 let decision:=restore_rejected_field input raw
  (match region with
   |Some patch=>if region_with_workspace patch then
      refresh_roots updated (region_roots patch) (refresh updated stepped)
     else refresh_roots updated (region_roots patch) stepped
   |None=>match input with Input.Snapshot|Input.EnvironmentObserved=>refresh updated stepped
     |_=>if changed then refresh updated stepped else stepped end end) in
 let final:=prepare(SA.result_state decision) in
 let region:=if Json.equal (prepared_encoding updated) (prepared_encoding final) then region
    else bind project (fun choose=>choose context final) in
 let published:=Prepared (prepared_world final) (prepared_state final) (prepared_encoding final)
    (prepared_environment final) (prepared_previous final) None (prepared_controls final) region (Some input) in
 (decision,input_publication input (prepared_encoding context) (prepared_encoding final),published).
Definition run_input request context namespace input raw:=
 let stepped:=native_step namespace (prepared_world context) (flag "semantic_lagged" request)
    input raw (prepared_state context) in
 finish_input context input raw (requested_region namespace input) stepped.

Definition stable_stream_context before after source :=
 let stable context:=without_fields ["streams";"documents"](prepared_encoding context)in
 let documents context:=value_or JNull(field "documents"(prepared_encoding context))in
 let contents context:=value_or [](bind(field "documents"(documents context))as_array)in
 let strip value:=match source,string_field "key" value with
 |Some key,Some actual=>if String.eqb key actual then without_fields ["source"] value else value
 |_,_=>value end in
 Json.equal (stable before)(stable after) &&
 Json.equal(without_fields ["documents"](documents before))(without_fields ["documents"](documents after)) &&
 Json.equal(JArray(map strip(contents before)))(JArray(map strip(contents after))).

Inductive stream_change :=
 |HiddenStream (document:option string)
 |VisibleStream (document:option string) (updates:list LiveUpdate.part_update).

Definition stream_projection namespace source context next :=
 event<-Streams.decode_event_in_namespace(Origin.valid_namespace namespace)namespace source;;
 coordinates<-LiveUpdate.edit_coordinates event;;
 let current:=prepared_state next in
 let projection:=LiveUpdate.edit_part (prepared_world context)(prepared_state context)current
      (fst coordinates)(snd coordinates)in
 if Navigation.task_visible current (Streams.stream_task(fst coordinates)) then
   edit<-projection;;
   env<-prepared_environment next;; _<-capacity env;;
   match snd edit with
   |[]=>None
   |updates=>if stable_stream_context context next (fst edit)
     then Some(VisibleStream(fst edit)updates)else None end
 else let document:=bind projection fst in
   if stable_stream_context context next document then Some(HiddenStream document)else None.

Definition run_stream_with_synchronization request context namespace source :=
 let input:=Input.Stream source in
 let snapshot:=prepared_world context in
 let stepped:=SR.step namespace snapshot (flag "semantic_lagged" request)input(prepared_state context)in
 let next:=with_state context(SA.result_state stepped)in
 let finish decision final :=
  (decision,input_publication input(prepared_encoding context)(prepared_encoding final),final)in
 let prepare_current current:=with_input (with_state context current) input in
 match stream_projection namespace source context next with
 |None=>let observed:=prepare_current(SA.result_state stepped)in
   let decision:=refresh observed stepped in
   finish decision (prepare_current(SA.result_state decision))
 |Some change=>
   let decision:=stepped in
   let final:=next in
   let present document patch :=
    if stable_stream_context context final document then
     Some(Prepared snapshot (prepared_state final)(prepared_encoding final)
       (prepared_environment final)(prepared_previous context) patch(prepared_controls context) None (Some input))
    else None in
   match change with
   |HiddenStream document=>match present document None with
     |Some retained=>(decision,"keep",retained)
     |None=>finish decision(prepare_current(SA.result_state decision))end
   |VisibleStream document patch=>match present document (Some patch)with
     |Some updated=>finish decision updated
     |None=>finish decision(prepare_current(SA.result_state decision))end end
 end.

(* A delta to a mounted preview changes only that source prefix. Its fence
   parser reports new components separately. Lifecycle events, newly mounted
   previews and changed document identities go through synchronization. *)
Definition append_stream_preview context namespace event : option (SA.result * prepared) :=
 match event with
 |Streams.Delta key index delta=>
   let old:=prepared_state context in let snapshot:=prepared_world context in
   controls<-prepared_controls context;; env<-prepared_environment context;;
   if String.eqb namespace (retention_namespace (Session.document_retention old)) then
   let '(streams, changed):=Streams.step Streams.browser_configuration event (Session.stream_state old) in
   if changed then
   let next:=Session.with_streams streams old in
   let authority:=SR.context namespace snapshot old in
   previous<-LiveUpdate.visible_part authority key index;;
   let source:=AuditReading.preview_source authority (fst previous) index in
   let retained:=Session.document_retention old in
   let update:=match source with
    |CodeSource.Generated received viewer origin _=>
      if Origin.interactive_origin origin then
       let previous:=Documents.Document viewer origin (snd (snd previous)) false in
       let appended:=Documents.Document viewer origin (Documents.markdown previous++delta) false in
       stamp<-Documents.document_stamp received previous retained;;
       if Documents.same_ending (document_ending stamp) Types.Open &&
          String.eqb (document_source stamp) (Documents.markdown previous)
       then Some (Session.with_retention (Documents.remember_document received appended retained) next)
       else None
      else Some next
    |_=>Some next end in
   current<-update;;
   edit<-LiveUpdate.edit_part snapshot old current key index;;
   match snd edit with
   |[]=>None
   |parts=>let encoded:=SC.encode_state current in
     Some (SA.keep current, Prepared snapshot current encoded (Some env)
       (prepared_previous context) (Some parts) (Some controls) None None)
   end else None else None
 |_=>None end.

Definition run_stream request context namespace source :=
 let local:=bind (Streams.decode_event_in_namespace (Origin.valid_namespace namespace) namespace source)
   (append_stream_preview context namespace) in
 match local with
 |Some (decision, next)=>(decision,"advance",next)
 |None=>run_stream_with_synchronization request context namespace source
 end.

Definition input_decision request context namespace input raw:=
 let snapshot:=prepared_world context in let current:=prepared_state context in
 match input with
 |Input.Stream source=>(run_stream request context namespace source,None)
 |Input.CodeObserved source=>match Documents.admit_observation
   (SR.context namespace snapshot current)source(Session.document_retention current)with
  |Documents.MalformedObservation=>((SA.fail current "The document observation does not belong to the current output.","keep",context),Some false)
  |Documents.IrrelevantObservation=>((SA.keep current,"keep",context),Some false)
  |Documents.AdmittedObservation language retained=>
    let decision:=SR.admitted_document_step namespace snapshot (flag "semantic_lagged" request) language retained current in
    (finish_input context input raw (option_map (fence_region namespace) (language_owner language)) decision,Some true) end
 |Input.Interactive language=>
   if SR.native_language namespace snapshot current language &&
      negb (flag "semantic_lagged" request && Selvedge.Interaction.Interactive.Runtime.authored_input language &&
        negb (match string_field "op" raw with Some "element"=>true|_=>false end))
   then (run_input request context namespace input raw,None) else ((SA.keep current,"keep",context),None)
 |_ => (run_input request context namespace input raw,None) end.

Definition initialized := SC.encode_state Session.initial.
(* Only navigation and drafts belong to the tab across a release change.
   Authentication, pending commands and other IO start with the new page. *)
Definition update_session current := JObject[
 ("navigation",NavigationCodec.encode_navigation(Session.navigation_state current));
 ("drafts",JArray(map DraftCodec.encode_draft(Session.drafts(Session.authoring_state current))));
 ("next_layer",number(Session.next_layer current))].
Definition retained_update_layer snapshot layer := match Session.layer_panel layer with
 |Session.Confirmation _ _ _=>false
 |Session.SideConversationPanel task=>Navigation.route_allowed snapshot(NavigationIdentity.Conversation task)
 |_=>true end.
Definition restore_update_session snapshot checkpoint current :=
 navigation<-bind(field "navigation" checkpoint)NavigationCodec.decode_navigation;;
 drafts<-list_field DraftCodec.decode_draft "drafts" checkpoint;;
 next_layer<-natural_field "next_layer" checkpoint;;
 let authoring:=set Session.drafts(fun _=>drafts)(Session.authoring_state current)in
 let restored:=Session.with_next_layer next_layer(Session.with_authoring authoring current)in
 (* DEFENSE: A task or project may have been deleted after the old page's last snapshot. *)
 Some(if Navigation.route_allowed snapshot(Session.location navigation)then
   let layers:=map(set Session.layer_pending(fun _=>false))
    (filter(retained_update_layer snapshot)(Session.layers navigation))in
   Session.with_navigation(set Session.layers(fun _=>layers)navigation)restored
 else restored).
Definition prepared_call (full : bool) operation request context : json * prepared :=
 let snapshot:=prepared_world context in
 let unchanged response:=(response,context) in
 if String.eqb operation "accepts_element"then
  unchanged(match field "input" request,natural_field "generation" request with
  |Some raw,Some _=>Json.success(JBool(match admitted_element request context raw with Some _=>true|None=>false end))
  |_,_=>Json.success(JBool false)end)
 else if String.eqb operation "update_session" then
  unchanged(Json.success(update_session(prepared_state context)))
 else if String.eqb operation "restore_update_session" then
  match bind(field "checkpoint" request)(fun checkpoint=>restore_update_session snapshot checkpoint (prepared_state context))with
  |Some restored=>let next:=with_state context restored in
    (Json.success(returned_state full next),next)
  |None=>unchanged(Json.failure "InvalidUpdateSession" "The update session checkpoint is invalid.")end
 else if String.eqb operation "step"then match field "input" request with
  |None=>unchanged(Json.failure "InvalidInput" "An input observation is required.")
  |Some raw=>match decode_input request context raw with
   |None=>unchanged(Json.success(decision_packet full context [] None false false false "keep" None))
   |Some input=>match string_field "namespace" request with
    |None=>unchanged(Json.failure "InvalidNamespace" "The runtime namespace is required.")
    |Some namespace=>let '((decision,publication,next),fence_admitted):=input_decision request context namespace input raw in
     (Json.success(decision_packet full next(SA.result_effects decision)(SA.result_error decision)true(SA.result_visible_error decision)(Input.acknowledges_feedback input)publication fence_admitted),next)end end end
 else unchanged(Json.failure "UnknownOperation" operation).

Definition call operation request:json:=
 if String.eqb operation "initial"then Json.success initialized else
 if String.eqb operation "interactive_storage_policy"then
  Selvedge.Interaction.Interactive.Language.call "storage_policy" request else
 if String.eqb operation "update_session"then
  match state request with
  |Some current=>Json.success(update_session current)
  |None=>Json.failure "InvalidState" "The typed application state is required."end else
 let invalid:=Json.failure "InvalidState" "The typed application state and admitted world observation are required."in
 if String.eqb operation "restore_update_session"then
  match state request,field "world" request with
  |Some current,Some snapshot=>
   match bind(field "checkpoint" request)(fun checkpoint=>restore_update_session snapshot checkpoint current)with
   |Some restored=>Json.success(SC.encode_state restored)
   |None=>Json.failure "InvalidUpdateSession" "The update session checkpoint is invalid."end
  |_,_=>invalid end
 else match prepare request with
 |Some context=>fst(prepared_call true operation request context)
 |None=>invalid end.
