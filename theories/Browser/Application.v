From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Programming Require Import Schema Resource.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Browser Require Import NavigationIdentity.
From Selvedge.Interaction Require Import Codec Identity.
From Selvedge.Browser.Session Require Import Input InputCodecs.
From Selvedge.Browser.Presentation Require Import ActionPurpose.
From Selvedge.Browser Require Import Documents AuditReading.
From Selvedge.Browser.Session Require State Codec Runtime Authoring Navigation NavigationCodec.
From Selvedge.Browser.Scene Require Construction.
From Selvedge.Interaction.Submission Require DraftCodec.
From Selvedge.Browser.Presentation Require Gesture.
From Selvedge.Browser.Presentation Require Composition.
From Selvedge.Browser.Scene Require Surface Model.
From Selvedge.Browser.Presentation Require View Pages Layers LiveUpdate.
From Selvedge.Interaction.Experience Require Read.
From Selvedge.Kernel Require Streams.
From Selvedge.Interaction Require Origin CodeSource CommandAssessment.
From Selvedge.Interaction.Interactive Require Language Types.
From Selvedge.Interaction.Interactive Require State.
From Selvedge.Browser.Interactive Require Render.
From Selvedge.Interaction.Experience Require Activity.
From Selvedge.Interaction.Submission Require Fields Parameters.
From Selvedge.Browser Require Layout Observation Document DOM DirectDOM Focus InputAuthority.
Import ListNotations.
Open Scope string_scope.
Module Session:=Selvedge.Browser.Session.State.
Module SC:=Selvedge.Browser.Session.Codec.
Module SR:=Selvedge.Browser.Session.Runtime.
Module SA:=Selvedge.Browser.Session.Authoring.
Module S:=Selvedge.Browser.Scene.Surface.
Module V:=Selvedge.Browser.Presentation.View.
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
Definition surface snapshot state environment:=
 option_map(fun capacity=>V.view snapshot state capacity(compact_picker environment))(capacity environment).

Record composer_projection := ComposerProjection {
  composer_area : Document.area;
  composer_source : S.meaning Input.input;
  composer_view : option task_view;
  composer_node : S.node Input.input
}.
Record picker_projection := PickerProjection {
  projected_composer : option composer_projection;
  projected_overlays : list (S.node Input.input);
  removed_picker_targets : list string
}.

Record picker_update := PickerUpdate {
  picker_before : option string;
  picker_after : option (S.node Input.input);
  picker_trigger : string;
  picker_projection_for_update : option picker_projection
}.
Definition native_resolver := string -> Gesture.gesture -> json -> option Input.input.
Record control_binding := ControlBinding {
  binding_modal : option string;
  binding_receive : S.receiver Input.input
}.
Record published_controls := PublishedControls {
  published_receivers : S.BindingMap.t control_binding;
  published_modals : list Focus.scope;
  published_actions : list (option string * list Input.input)
}.
Definition scoped_node := (option string * S.node Input.input)%type.
Definition bind_control (entry : scoped_node) := S.bind_node (ControlBinding (fst entry)) (snd entry).
Definition some_list {A} (value : option A) := match value with Some item=>[item]|None=>[] end.
Definition overlay_control (node : S.node Input.input) : scoped_node :=
 ((if S.is_modal_node node then Some (S.node_key node) else None), node).
Definition replace_controls current removed added scopes actions :=
 let retained := fold_right (@S.unbind_node Input.input control_binding) (published_receivers current) removed in
 PublishedControls (fold_right bind_control retained added) scopes actions.
Definition initial_controls (value : S.surface Input.input) :=
 let scopes := Document.surface_scopes (S.modal_nodes value) in
 let actions := (None, flat_map S.node_actions (S.base value)) ::
   map (fun node => (fst (overlay_control node), S.node_actions node)) (S.overlays value) in
 replace_controls (PublishedControls (S.BindingMap.empty control_binding) [] []) []
   (map (fun node => (None, node)) (S.base value) ++ map overlay_control (S.overlays value)) scopes actions.
Definition active_scope scopes :=
 match rev scopes with Focus.Temporary key _ _ _ _ :: _ => Some key | _ => None end.
Definition same_scope first second := match first,second with
 |None,None=>true|Some a,Some b=>String.eqb a b|_,_=>false end.
Definition scoped_actions scopes (actions : list (option string * list Input.input)) :=
 let active := active_scope scopes in
 flat_map snd (filter (fun entry=>same_scope (fst entry) active) actions).
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
  region_actions : list (option string * list Input.input)
}.
(** Native inputs use the bindings of the committed presentation. Full and
    partial publications replace bindings only after their DOM is installed. *)
Record prepared := Prepared {
  prepared_world : json;
  prepared_state : Session.state;
  prepared_encoding : json;
  prepared_environment : option Layout.environment;
  prepared_scene_at : unit -> option (S.surface Input.input);
  prepared_picker_update : option picker_update;
  prepared_active_picker : option (S.node Input.input);
  prepared_stream_update : option (list LiveUpdate.part_update);
  prepared_controls : option published_controls;
  prepared_region_update : option region_update
}.
Definition scene snapshot current env :=
 if Json.equal snapshot JNull then option_map(fun _=>V.initial_connection current)env
 else bind env (surface snapshot current).
Definition prepared_scene context := prepared_scene_at context tt.
Definition defer_scene (project : unit -> option (S.surface Input.input)) := project.
Definition context_for_state snapshot current encoded env :=
 Prepared snapshot current encoded env
   (defer_scene (fun _=>scene snapshot current env)) None None None None None.
Definition with_controls context controls :=
 Prepared (prepared_world context) (prepared_state context) (prepared_encoding context)
   (prepared_environment context) (prepared_scene_at context) (prepared_picker_update context)
   (prepared_active_picker context) (prepared_stream_update context) controls (prepared_region_update context).
Definition prepare request :=
 snapshot<-field "world" request;; current<-state request;;
 let env:=environment request in
 Some(context_for_state snapshot current (SC.encode_state current) env).
(** Rebase discards pending patches and keeps the controls still mounted in the browser. *)
Definition rebase request context :=
 snapshot<-field "world" request;;
 Some(with_controls (context_for_state snapshot (prepared_state context) (prepared_encoding context) (environment request))
   (prepared_controls context)).
Definition with_state context current :=
 let encoded:=SC.encode_state current in
 if Json.equal(prepared_encoding context)encoded then context else
 let snapshot:=prepared_world context in let env:=prepared_environment context in
 with_controls (context_for_state snapshot current encoded env) (prepared_controls context).

Definition as_picker (node:S.node Input.input) :=
 if String.eqb (S.semantic_key node) "model-picker" then Some node else None.

Definition shown_picker context :=
 match prepared_active_picker context with
 |Some node=>Some node
 |None=>actual<-prepared_scene context;; bind(S.active_modal actual)as_picker
 end.
Definition top_picker context :=
 layer<-hd_error(Session.layers(Session.navigation_state(prepared_state context)));;
 if SA.model_picker_layer layer then Some layer else None.
Definition without_fields excluded value := match value with
 |JObject fields=>JObject(filter(fun field=>negb(existsb(String.eqb(fst field))excluded))fields)
 |_=>value end.
Definition underlying_layers context :=
 let layers:=Session.layers(Session.navigation_state(prepared_state context))in
 match top_picker context with Some _=>tl layers|None=>layers end.
Definition retains_picker_underlay before after :=
 let nav context:=NavigationCodec.encode_navigation(Session.navigation_state(prepared_state context))in
 let stable context:=without_fields ["navigation";"authoring";"services";"next_layer"](prepared_encoding context)in
 let services context:=without_fields ["next";"command_assessments";"model_preference"]
   (value_or JNull(field "services"(prepared_encoding context)))in
 let authoring context:=without_fields ["drafts";"pending";"next";"draft_model_manual"]
   (value_or JNull(field "authoring"(prepared_encoding context)))in
 (* Task details can relocate its trigger into its own dialog when exposed. *)
 let layers:=underlying_layers before in
 negb(existsb(fun layer=>match Session.layer_panel layer with
  |Session.InformationPanel(Session.TaskDetails _)=>true|_=>false end)layers) &&
 Json.equal (without_fields ["layers"](nav before)) (without_fields ["layers"](nav after)) &&
 Json.equal (JArray(map NavigationCodec.encode_layer layers))
   (JArray(map NavigationCodec.encode_layer(underlying_layers after))) &&
 Json.equal (stable before) (stable after) &&
 Json.equal (services before) (services after) &&
 Json.equal (authoring before) (authoring after).
Definition picker_update_for input before after :=
 let old:=shown_picker before in let next:=shown_picker after in
 let update layer:=if retains_picker_underlay before after then
  Some(PickerUpdate(option_map (@S.node_key Input.input)old)next(Session.layer_trigger layer)None)else None in
 match input,old,next with
 |Input.OpenActivity _ (Activity.PropertyActivity UX.ModelProperty) _,None,Some _=>
   bind(top_picker after)update
 |Input.ClosePanel,Some _,None=>bind(top_picker before)update
 |Input.ActivityFocus _ _ _,Some _,Some _
 |Input.ActivitySearch _ _,Some _,Some _=>
   bind(top_picker after)update
 |Input.ActivityAssignment _ _ assignment,Some _,Some _=>
   match UX.subject_declaration(Activity.assignment_subject assignment)with
   |Fields.ModelProfile|Fields.ReasoningEffort=>bind(top_picker after)update
   |_=>None end
 |_,_,_=>None end.

Definition active_picker_assessment context ticket :=
 match top_picker context with
 |Some layer=>match Session.layer_panel layer with
   |Session.PropertyPanel owner _=>
     let assessments:=Selvedge.Browser.Session.Services.command_assessments(Session.service_state(prepared_state context))in
     existsb(fun resource=>match resource with
     |Loading current request=>
       match CommandAssessment.request_owner request with
       |CommandAssessment.CandidateOwner actual name _=>N.eqb ticket current && same_editor owner actual &&
         (String.eqb name(Parameters.name Fields.ModelProfile)||String.eqb name(Parameters.name Fields.ReasoningEffort))
       |_=>false end
     |_=>false end)assessments
   |_=>false end
 |None=>false end.
Definition picker_input context input := match input with
 |Input.OpenActivity _ (Activity.PropertyActivity UX.ModelProperty) _
 |Input.ClosePanel|Input.ActivityFocus _ _ _|Input.ActivitySearch _ _=>true
 |Input.ActivityAssignment _ _ assignment=>match UX.subject_declaration(Activity.assignment_subject assignment)with
   |Fields.ModelProfile|Fields.ReasoningEffort=>true|_=>false end
 |Input.ServiceInput(Selvedge.Browser.Session.Services.CommandAssessed ticket _)=>
   active_picker_assessment context ticket
 |_=>false end.
Definition picker_underlay layer := match Session.layer_panel layer with
 |Session.SideConversationPanel _=>true|_=>false end.
Definition modal_from_overlays nodes := hd_error(rev(filter (@S.is_modal_node Input.input) nodes)).
Definition projected_overlays_with (project:json->Session.state->BM.capacity->bool->list(S.node Input.input)) context :=
 env<-prepared_environment context;;
 if Json.equal (prepared_world context) JNull then Some [] else
 size<-capacity env;;
 if forallb picker_underlay (underlying_layers context) then
   Some(project(prepared_world context)(prepared_state context)size(compact_picker env))
 else None.
Definition projected_picker_overlays := projected_overlays_with V.view_overlays.
Definition projected_picker_scopes := projected_overlays_with V.view_overlay_scopes.

Definition project_task_composer snapshot current view parent area :=
 option_map (ComposerProjection area (S.PageContext(Some view)) (Some view))
   (Pages.conversation_composer snapshot current view parent).
Definition picker_composer context trigger :=
 let snapshot:=prepared_world context in let current:=prepared_state context in
 let nav:=Session.navigation_state current in
 let matches composer:=match V.find_presentation_node trigger (composer_node composer) with
  |Some _=>true|None=>false end in
 let primary:=match Session.location nav with
 |Start|GraphConversation _ _=>Some(ComposerProjection Document.CreationArea (S.PageBody(Pages.page_kind snapshot current)) None
   (Pages.creation_composer snapshot current V.main_key))
 |Conversation task=>project_task_composer snapshot current (PrimaryTask task) V.main_key Document.PageArea
 |_=>None end in
 let selected:=match primary with Some composer=>if matches composer then Some composer else None|None=>None end in
 match selected with Some _=>selected|None=>
   fold_right(fun layer rest=>match Session.layer_panel layer with
   |Session.SideConversationPanel task=>
     match project_task_composer snapshot current (SideTask task)
       (Navigation.panel_key(Session.layer_panel layer)) Document.DialogArea with
     |Some composer=>if matches composer then Some composer else rest|None=>rest end
   |_=>rest end)None(underlying_layers context) end.

Definition composer_updates projection :=
 Document.target_updates(composer_view projection)(composer_node projection).
Definition picker_composer_unchanged input before after := match input with
 |Input.ActivityFocus _ _ _|Input.ActivitySearch _ _
 |Input.ServiceInput(Selvedge.Browser.Session.Services.CommandAssessed _ _)=>
  let services context:=value_or JNull(field "services"(prepared_encoding context))in
  let material_assessments context:=
   let items:=Selvedge.Browser.Session.Services.command_assessments(Session.service_state(prepared_state context))in
   let matters resource:=match resource_request resource with
   |Some request=>match CommandAssessment.request_owner request with
      |CommandAssessment.CandidateOwner _ _ _=>false|_=>true end
   |None=>true end in
   JArray(map(encode_resource CommandAssessment.encode_request CommandAssessment.encode_observation)
     (filter matters items))in
  let parameter context:=bind(top_picker context)Session.layer_parameter_buffer in
  Json.equal (value_or JNull(field "authoring"(prepared_encoding before)))
             (value_or JNull(field "authoring"(prepared_encoding after))) &&
  Json.equal (without_fields ["next";"command_assessments"](services before))
             (without_fields ["next";"command_assessments"](services after)) &&
  Json.equal (material_assessments before)(material_assessments after) &&
  match parameter before,parameter after with
  |None,None=>true|Some previous,Some next=>String.eqb previous next|_,_=>false end
 |_=>false end.

Definition picker_patch input before after overlays :=
 let next:=bind(modal_from_overlays overlays)as_picker in
 let old:=match top_picker before with Some _=>shown_picker before|None=>None end in
 let owner:=match input,old,next with
 |Input.OpenActivity _ (Activity.PropertyActivity UX.ModelProperty) _,None,Some _=>top_picker after
 |Input.ClosePanel,Some _,None=>top_picker before
 |_,Some _,Some _=>top_picker after
 |_,_,_=>None end in
 layer<-owner;;
 if retains_picker_underlay before after then
   let trigger:=Session.layer_trigger layer in
   let update projection:=Some(PickerUpdate(option_map (@S.node_key Input.input)old)next trigger(Some projection))in
   if picker_composer_unchanged input before after then update(PickerProjection None overlays [])else
   old_composer<-picker_composer before trigger;; composer<-picker_composer after trigger;;
   let targets:=map DOM.target (composer_updates composer)in
   let removed:=filter(fun key=>negb(existsb(String.eqb key)targets))
     (map DOM.target(composer_updates old_composer))in
   update(PickerProjection (Some composer) overlays removed)
 else None.

Definition materialize_native_roots := @DirectDOM.materialize_roots.
Definition native_document (request : json) (context : prepared) : option ((json * list DOM.node) * prepared) :=
 env<-prepared_environment context;; generation<-natural_field "generation" request;; actual<-prepared_scene context;;
 let document := Document.compile_document (CP.describe (prepared_world context) (prepared_state context)) env generation actual in
 Some ((DOM.document_metadata document, [DOM.root document]), with_controls context (Some (initial_controls actual))).

Definition native_region (request : json) (context : prepared) : option ((json * list DOM.node) * prepared) :=
 patch<-prepared_region_update context;; controls<-prepared_controls context;;
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
   (value_or (published_modals controls) (region_scopes patch)) (region_actions patch) in
 Some ((metadata, map compile (region_roots patch)), with_controls context (Some next)).

Fixpoint native_controls (node:DOM.node) : bool :=
 match node with
 |DOM.Text _=>true
 |DOM.Element _ _ _ _ _ _ children=>forallb native_controls children
 |DOM.Markdown _ _ _ _|DOM.Mount _ _=>false
 end.
Definition native_picker (request:json) (context:prepared) : option ((json * list DOM.node) * prepared) :=
 patch<-prepared_picker_update context;;
 controls<-prepared_controls context;;
 env<-prepared_environment context;;
 generation<-natural_field "generation" request;;
 let describe:=CP.describe(prepared_world context)(prepared_state context)in
 let layer:=option_map(Document.compile_node describe env generation
    Document.OutsideArea false S.Region None None)(picker_after patch)in
 let publish workspace overlays targets flags composer composer_node :=
  let scopes:=Document.surface_scopes(filter S.is_modal_node overlays) in
  let key:=match composer with Some(DOM.Element key _ _ _ _ _ _)=>JString key|_=>JNull end in
  let metadata:=JObject([
   ("composer",key);
   ("before",value_or JNull(option_map JString(picker_before patch)));
   ("after",value_or JNull(option_map(fun node=>JString(S.node_key node))(picker_after patch)));
   ("layer_stack",JString(workspace++"/overlays"));
   ("focus_scope",JArray(map DOM.scope_json scopes));
   ("target_updates",JArray(map DOM.update_json targets))]++flags)%list in
  let nodes value:=match value with Some node=>[node]|None=>[]end in
  let roots:=List.app(nodes composer)(nodes layer)in
  let bindings:=match picker_before patch with
   |Some key=>S.BindingMap.fold (fun id value kept=>
      if same_scope (binding_modal value) (Some key) then S.BindingMap.remove id kept else kept)
     (published_receivers controls) (published_receivers controls)
   |None=>published_receivers controls end in
  let added:=(some_list (option_map overlay_control (picker_after patch)) ++ some_list composer_node)%list in
  let actions:=(filter (fun entry=>match fst entry,picker_before patch with
   |Some old,Some key=>negb(String.eqb old key)|_,_=>true end) (published_actions controls) ++
   map (fun node=>(fst (overlay_control node),S.node_actions node)) (some_list (picker_after patch)))%list in
  let next:=PublishedControls (fold_right bind_control bindings added) scopes actions in
  if forallb native_controls roots then Some((metadata,roots),with_controls context (Some next))else None in
 match picker_projection_for_update patch with
 |Some projection=>
   let composer:=projected_composer projection in
   let root:=option_map(fun composer=>Document.compile_node describe env generation (composer_area composer) false
      (composer_source composer)(composer_view composer)None(composer_node composer))composer in
   publish V.workspace_key (projected_overlays projection)(value_or [](option_map composer_updates composer))
    [("partial_target_updates",JBool true);
     ("removed_target_updates",JArray(map JString(removed_picker_targets projection)))] root
     (option_map (fun projection=>(match composer_view projection with
       |Some (SideTask _)=>active_scope (published_modals controls)|_=>None end, composer_node projection)) composer)
 |None=>
 actual<-prepared_scene context;;
 let owns_picker (node:S.node Input.input):=match S.node_meaning node with
  |S.PageRegion Composition.ComposerInput _=>
    match V.find_presentation_node(picker_trigger patch)node with Some _=>true|None=>false end
  |_=>false end in
 let all:=(S.base actual++S.overlays actual)%list in
 match flat_map(Document.compile_regions owns_picker describe env generation
    Document.OutsideArea false S.Region None None)all with
 |[composer]=>
  let theme:=Document.NativeAppearance.theme_name(S.surface_appearance actual)(Layout.system_dark env)in
  publish (S.workspace_key actual)(S.overlays actual)
   (DOM.UpdateTarget "@document/root" [("data-theme",theme)] [("color-scheme",theme)]
       ::flat_map(Document.target_updates None)all) [] (Some composer) None
 |_=>None end end.

Definition native_stream (request:json) (context:prepared) : option (json * list DOM.node) :=
 patch<-prepared_stream_update context;; env<-prepared_environment context;;
 generation<-natural_field "generation" request;;
 let describe:=CP.describe(prepared_world context)(prepared_state context)in
 let compile update:=
  let view:=LiveUpdate.updated_view update in
  Document.compile_node describe env generation
   (match view with PrimaryTask _=>Document.PageArea|SideTask _=>Document.DialogArea end)
   false (S.ReadingTimeline view (LiveUpdate.updated_reader_generation update)) (Some view) None
   (LiveUpdate.updated_preview update) in
 Some(JObject[("mode",JString "stream");("targets",JArray(map(fun update=>
    JString(S.node_key(LiveUpdate.updated_preview update)))patch))],map compile patch).

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
Definition decision_packet context effects error handled visible_error acknowledge (publication_event:string) fence_admitted:=JObject[("state",prepared_encoding context);
 ("file_handles",JArray(map JString(Selvedge.Browser.Session.Services.retained_file_handles(Session.service_state(prepared_state context)))));
 ("effects",JArray effects);("publication_event",JString publication_event);("error",match error with None=>JNull|Some diagnostic=>diagnostic end);
 ("visible_error",JBool visible_error);("feedback_update",JString(feedback_update error visible_error acknowledge));("handled",JBool handled);
 ("fence_admitted",match fence_admitted with Some value=>JBool value|None=>JNull end);
 ("native_picker",JBool(match prepared_picker_update context with Some _=>true|None=>false end));
 ("native_stream",JBool(match prepared_stream_update context with Some _=>true|None=>false end));
 ("native_region",JBool(match prepared_region_update context with Some _=>true|None=>false end))].
Definition refresh context decision:=match prepared_scene context with
|Some actual=>SA.append decision(SA.refresh (prepared_world context)(S.current_actions actual)(SA.result_state decision))
|None=>decision end.
Definition deferred_state_change context current :=
 let encoded:=SC.encode_state current in
 if Json.equal(prepared_encoding context)encoded then (context,false) else
 let snapshot:=prepared_world context in let env:=prepared_environment context in
 (with_controls (context_for_state snapshot current encoded env) (prepared_controls context),true).
Definition deferred_state context current := fst(deferred_state_change context current).
Definition refresh_picker stepped_context stepped scopes :=
 let fast:=bind(bind scopes modal_from_overlays)as_picker in
 let modal:=match fast with Some _=>fast
   |None=>bind(projected_picker_overlays stepped_context)modal_from_overlays end in
 match modal with
 |Some modal=>SA.append stepped(SA.refresh(prepared_world stepped_context)(S.node_actions modal)(SA.result_state stepped))
 |None=>refresh stepped_context stepped end.
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

Definition details_layer state :=
 layer<-hd_error (Session.layers (Session.navigation_state state));;
 match Session.layer_panel layer with
 |Session.InformationPanel (Session.TaskDetails task)=>Some (task, layer)
 |_=>None end.

Definition details_input context input := match input with
 |Input.OpenInformation (Session.TaskDetails _) _=>true
 |Input.ClosePanel=>match details_layer (prepared_state context) with Some _=>true|None=>false end
 |_=>false end.

Definition details_navigation context :=
 let current:=prepared_state context in
 let nav:=NavigationCodec.encode_navigation (Session.navigation_state current) in
 let layers:=Session.layers (Session.navigation_state current) in
 let underlying:=match details_layer current with Some _=>tl layers|None=>layers end in
 JObject [("navigation", without_fields ["layers"] nav);
   ("layers", JArray (map NavigationCodec.encode_layer underlying))].

Definition details_region before after : option region_update :=
 controls<-prepared_controls before;; env<-prepared_environment after;; size<-capacity env;;
 let stable context:=without_fields ["navigation";"next_layer"] (prepared_encoding context) in
 if negb (Json.equal (stable before) (stable after) && Json.equal (details_navigation before) (details_navigation after))
 then None else
 let old:=prepared_state before in let current:=prepared_state after in let snapshot:=prepared_world after in
 task<-match Session.location (Session.navigation_state current) with Conversation task=>Some task|_=>None end;;
 info<-Read.find_task task snapshot;;
 let actions:=Pages.task_actions snapshot current info V.main_key in
 let trigger:=Pages.task_details_control current task V.main_key in
 let matches pair:=N.eqb task (fst pair) && String.eqb (Session.layer_trigger (snd pair)) (S.node_key trigger) in
 match details_layer old, details_layer current with
 |None, Some opening | Some opening, None=>
   if matches opening then
   let overlays:=V.view_overlay_scopes snapshot current size (compact_picker env) in
   let scopes:=Document.surface_scopes (filter S.is_modal_node overlays) in
   let render layer:=Layers.layer_view snapshot current size (compact_picker env) layer in
   let old_layer:=option_map (fun pair=>Layers.layer_view snapshot old size (compact_picker env) (snd pair)) (details_layer old) in
   let new_layer:=option_map (fun pair=>render (snd pair)) (details_layer current) in
   let '(page_nodes, layers):=V.relocate_details_trigger current size [actions] (some_list new_layer) in
   let root scope area source view target node:=RegionRoot (scope,node) area source view target in
   let region_actions:=map (root None Document.PageArea (S.PageContext (Some (PrimaryTask task))) (Some (PrimaryTask task)) None) page_nodes in
   let region_layer:=map (fun node=>root (fst (overlay_control node)) Document.OutsideArea S.Region None
     (Some (V.workspace_key++(if Document.beside_layer node then "/beside" else "/overlays"))) node) layers in
   let actions:=(filter (fun entry=>match fst entry,old_layer with
     |Some key,Some node=>negb(String.eqb key (S.node_key node))|_,_=>true end) (published_actions controls) ++
     map (fun node=>(fst (overlay_control node),S.node_actions node)) (filter S.is_modal_node layers))%list in
   Some (RegionUpdate (Pages.task_actions snapshot old info V.main_key :: some_list old_layer)
     (region_actions++region_layer)%list (some_list (option_map (@S.node_key Input.input) old_layer)) (Some scopes) actions)
   else None
 |_,_=>None end.

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
 if negb (Json.equal (stable before) (stable after)) then None else
 match published_fence namespace after owner with
 |[]=>None
 |roots=>Some (RegionUpdate (map (fun root=>snd (region_node root)) (published_fence namespace before owner))
     roots [] None (published_actions controls)) end.

Definition requested_region namespace input context := match input with
 |Input.CodeObserved source=>match Documents.admit_observation
   (SR.context namespace (prepared_world context) (prepared_state context)) source
   (Session.document_retention (prepared_state context)) with
   |Documents.AdmittedObservation language _=>option_map (fence_region namespace) (language_owner language)
   |_=>None end
 |Input.Interactive language=>option_map (fence_region namespace) (language_owner language)
 |_=>if details_input context input then Some details_region else None end.

Definition run_input request context namespace input raw:=
 let stepped:=native_step namespace(prepared_world context)(flag "semantic_lagged" request)input raw(prepared_state context)in
 let candidate:=picker_input context input && match input with
  |Input.OpenActivity _ _ _=>true
  |_=>match top_picker context with Some _=>true|None=>false end end in
 let stepped_context:=if candidate then deferred_state context(SA.result_state stepped)
                      else with_state context(SA.result_state stepped)in
 let scopes:=if candidate then projected_picker_scopes stepped_context else None in
 let project:=requested_region namespace input context in
 let changed:=negb (Json.equal (prepared_encoding context) (prepared_encoding stepped_context)) in
 let region:=if changed then bind project (fun project=>project context stepped_context) else None in
 let decision:=restore_rejected_field input raw
  (match region with
   |Some patch=>match prepared_controls context with
     |Some controls=>SA.append stepped (SA.refresh (prepared_world context)
       (scoped_actions (value_or (published_modals controls) (region_scopes patch)) (region_actions patch)) (SA.result_state stepped))
     |None=>stepped end
   |None=>if candidate then refresh_picker stepped_context stepped scopes else
     match input with
     |Input.Snapshot|Input.EnvironmentObserved=>refresh stepped_context stepped
     |_=>if negb changed then stepped
     else refresh stepped_context stepped end end)in
 let '(updated, changed):=if candidate then deferred_state_change stepped_context(SA.result_state decision)
              else (with_state stepped_context(SA.result_state decision),false)in
 let patch:=if candidate then
    let overlays:=if changed then projected_picker_scopes updated else scopes in
    match bind overlays (picker_patch input context updated)with
    |Some patch=>Some patch|None=>picker_update_for input context updated end else None in
 let final:=Prepared (prepared_world updated)(prepared_state updated)(prepared_encoding updated)
   (prepared_environment updated)(prepared_scene_at updated)patch (bind patch picker_after) None (prepared_controls updated)
   (if Json.equal (prepared_encoding updated) (prepared_encoding stepped_context) then region
    else bind project (fun project=>project context updated)) in
 (decision,input_publication input(prepared_encoding context)(prepared_encoding final),final).

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

Definition refresh_published context decision := match prepared_controls context with
|Some controls=>SA.append decision(SA.refresh(prepared_world context)
 (scoped_actions (published_modals controls) (published_actions controls))(SA.result_state decision))
|None=>refresh context decision end.

Definition run_stream request context namespace source :=
 let input:=Input.Stream source in
 let snapshot:=prepared_world context in
 let stepped:=SR.step namespace snapshot (flag "semantic_lagged" request)input(prepared_state context)in
 let next:=deferred_state context(SA.result_state stepped)in
 let finish decision final :=
  (decision,input_publication input(prepared_encoding context)(prepared_encoding final),final)in
 let prepare_current current:=with_state context current in
 match stream_projection namespace source context next with
 |None=>let observed:=with_state context(SA.result_state stepped)in
   let decision:=refresh observed stepped in
   finish decision (with_state observed(SA.result_state decision))
 |Some change=>
   (* The updated preview has no action descendants. Only the text changes,
      so the assessment inputs from the visible scene are still current. *)
   let decision:=refresh_published context stepped in
   let final:=deferred_state next(SA.result_state decision)in
   let present document scene patch :=
    if stable_stream_context context final document then
     Some(Prepared snapshot (prepared_state final)(prepared_encoding final)
       (prepared_environment final)scene None(prepared_active_picker context)patch(prepared_controls context) None)
    else None in
   match change with
   |HiddenStream document=>match present document (prepared_scene_at context)None with
     |Some retained=>(decision,"keep",retained)
     |None=>finish decision(prepare_current(SA.result_state decision))end
   |VisibleStream document patch=>match present document(prepared_scene_at final)(Some patch)with
     |Some updated=>finish decision updated
     |None=>finish decision(prepare_current(SA.result_state decision))end end
 end.

Definition input_decision request context namespace input raw:=
 let snapshot:=prepared_world context in let current:=prepared_state context in
 match input with
 |Input.Stream source=>(run_stream request context namespace source,None)
 |Input.CodeObserved source=>match Documents.admit_observation
   (SR.context namespace snapshot current)source(Session.document_retention current)with
  |Documents.MalformedObservation=>((SA.fail current "The document observation does not belong to the current output.","keep",context),Some false)
  |Documents.IrrelevantObservation=>((SA.keep current,"keep",context),Some false)
  |Documents.AdmittedObservation _ _=>(run_input request context namespace input raw,Some true) end
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
Definition prepared_call operation request context : json * prepared :=
 let snapshot:=prepared_world context in
 let unchanged response:=(response,context) in
 if String.eqb operation "accepts_element"then
  unchanged(match field "input" request,natural_field "generation" request with
  |Some raw,Some _=>Json.success(JBool(match admitted_element request context raw with Some _=>true|None=>false end))
  |_,_=>Json.success(JBool false)end)
 else if String.eqb operation "step"then match field "input" request with
  |None=>unchanged(Json.failure "InvalidInput" "An input observation is required.")
  |Some raw=>match decode_input request context raw with
   |None=>unchanged(Json.success(decision_packet context [] None false false false "keep" None))
   |Some input=>match string_field "namespace" request with
    |None=>unchanged(Json.failure "InvalidNamespace" "The runtime namespace is required.")
    |Some namespace=>let '((decision,publication,next),fence_admitted):=input_decision request context namespace input raw in
     (Json.success(decision_packet next(SA.result_effects decision)(SA.result_error decision)true(SA.result_visible_error decision)(Input.acknowledges_feedback input)publication fence_admitted),next)end end end
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
 |Some context=>fst(prepared_call operation request context)
 |None=>invalid end.
