From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Programming Require Import Schema.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Browser Require Import NavigationIdentity.
From Selvedge.Interaction Require Import Codec Identity.
From Selvedge.Browser.Session Require Import Input InputCodecs.
From Selvedge.Browser.Presentation Require Import ActionPurpose.
From Selvedge.Browser Require Import Documents.
From Selvedge.Browser.Session Require State Codec Runtime Authoring Navigation NavigationCodec.
From Selvedge.Interaction.Submission Require DraftCodec.
From Selvedge.Browser.Presentation Require Gesture.
From Selvedge.Browser.Presentation Require Composition.
From Selvedge.Browser.Scene Require Surface Model.
From Selvedge.Browser.Presentation Require View.
From Selvedge.Interaction.Interactive Require Language.
From Selvedge.Interaction.Experience Require Activity.
From Selvedge.Interaction.Submission Require Fields.
From Selvedge.Browser Require Layout Observation Document DOM DirectDOM.
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
|Some(navigation,details)=>Some(BM.Capacity navigation details)|None=>None end.
Definition environment request:=bind(field "environment" request)Observation.decode_environment.
Definition state request:=bind(field "state" request)SC.decode_state.
Definition surface snapshot state environment:=
 let width:=Layout.viewport_width environment in
 let portrait:=Nat.leb width 600 && Nat.ltb width (Layout.viewport_height environment) in
 option_map(fun capacity=>V.view snapshot state capacity portrait)(capacity environment).

Record picker_update := PickerUpdate {
  picker_before : option string;
  picker_after : option (S.node Input.input);
  picker_trigger : string
}.
(** One admitted world and physical environment own the scene used to resolve
    native events, collect action assessments, and compile the document. *)
Record prepared := Prepared {
  prepared_world : json;
  prepared_state : Session.state;
  prepared_encoding : json;
  prepared_environment : option Layout.environment;
  prepared_scene : option (S.surface Input.input);
  prepared_picker_update : option picker_update
}.
Definition scene snapshot current env := bind env (surface snapshot current).
Definition prepare request :=
 snapshot<-field "world" request;; current<-state request;;
 let env:=environment request in
 Some(Prepared snapshot current (SC.encode_state current) env (scene snapshot current env) None).
Definition with_state context current :=
 let encoded:=SC.encode_state current in
 if Json.equal(prepared_encoding context)encoded then context else
 let snapshot:=prepared_world context in let env:=prepared_environment context in
 Prepared snapshot current encoded env (scene snapshot current env) None.

Definition shown_picker context :=
 actual<-prepared_scene context;;
 node<-S.active_modal actual;;
 if String.eqb (S.semantic_key node) "model-picker" then Some node else None.
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
  Some(PickerUpdate(option_map (@S.node_key Input.input)old)next(Session.layer_trigger layer))else None in
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

Definition materialize_native_roots := @DirectDOM.materialize_roots.
Fixpoint native_controls (node:DOM.node) : bool :=
 match node with
 |DOM.Text _=>true
 |DOM.Element _ _ _ _ _ _ children=>forallb native_controls children
 |DOM.Markdown _ _ _ _|DOM.Mount _ _=>false
 end.
Definition native_picker (request:json) (context:prepared) : option (json * list DOM.node) :=
 patch<-prepared_picker_update context;;
 env<-prepared_environment context;;
 actual<-prepared_scene context;;
 generation<-natural_field "generation" request;;
 let describe:=CP.describe(prepared_world context)(prepared_state context)in
 let owns_picker (node:S.node Input.input):=match S.node_meaning node with
  |S.PageRegion Composition.ComposerInput _=>
    match V.find_presentation_node(picker_trigger patch)node with Some _=>true|None=>false end
  |_=>false end in
 let all:=(S.base actual++S.overlays actual)%list in
 match flat_map(Document.compile_regions owns_picker describe env generation
    Document.OutsideArea false S.Region None None)all with
 |[composer]=>
  let layer:=option_map(Document.compile_node describe env generation
    Document.OutsideArea false S.Region None None)(picker_after patch)in
  let theme:=Document.NativeAppearance.theme_name(S.surface_appearance actual)(Layout.system_dark env)in
  let metadata:=JObject[
   ("before",value_or JNull(option_map JString(picker_before patch)));
   ("after",value_or JNull(option_map(fun node=>JString(S.node_key node))(picker_after patch)));
   ("layer_stack",JString(S.workspace_key actual++"/overlays"));
   ("focus_scope",JArray(map DOM.scope_json(Document.surface_scopes(S.modal_nodes actual))));
   ("target_updates",JArray(map DOM.update_json
    (DOM.UpdateTarget "@document/root" [("data-theme",theme)] [("color-scheme",theme)]
       ::flat_map(Document.target_updates None)all)))]in
  let roots:=composer::match layer with Some node=>[node]|None=>[]end in
  if forallb native_controls roots then Some(metadata,roots)else None
 |_=>None end.

Definition element (actual:option(S.surface Input.input)) generation raw:=
 incoming<-natural_field "generation" raw;;
 if N.eqb incoming generation then
 key<-string_field "key" raw;;gesture<-bind(string_field "gesture" raw)Gesture.decode_gesture;;
 value<-Some(value_or JNull(field "value" raw));;
 actual<-actual;;
 S.resolve_element actual key gesture value else None.
Definition decode_input request context raw:=match string_field "op" raw with
|Some "element"=>generation<-natural_field "displayed_generation" request;;element (prepared_scene context) generation raw
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
Definition decision_packet context effects error handled visible_error acknowledge (publication_event:string):=JObject[("state",prepared_encoding context);
 ("file_handles",JArray(map JString(Selvedge.Browser.Session.Services.retained_file_handles(Session.service_state(prepared_state context)))));
 ("effects",JArray effects);("publication_event",JString publication_event);("error",match error with None=>JNull|Some diagnostic=>diagnostic end);
 ("visible_error",JBool visible_error);("feedback_update",JString(feedback_update error visible_error acknowledge));("handled",JBool handled);
 ("native_picker",JBool(match prepared_picker_update context with Some _=>true|None=>false end))].
Definition refresh context decision:=match prepared_scene context with
|Some actual=>SA.append decision(SA.refresh (prepared_world context)(S.current_actions actual)(SA.result_state decision))
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
Definition run_input request context namespace input raw:=
 let stepped:=native_step namespace(prepared_world context)(flag "semantic_lagged" request)input raw(prepared_state context)in
 let stepped_context:=with_state context(SA.result_state stepped)in
 let decision:=restore_rejected_field input raw(refresh stepped_context stepped)in
 let updated:=with_state stepped_context(SA.result_state decision)in
 let final:=Prepared (prepared_world updated)(prepared_state updated)(prepared_encoding updated)
   (prepared_environment updated)(prepared_scene updated)(picker_update_for input context updated)in
 (decision,input_publication input(prepared_encoding context)(prepared_encoding final),final).

Definition input_decision request context namespace input raw:=
 let snapshot:=prepared_world context in let current:=prepared_state context in
 match input with
 |Input.CodeObserved source=>match Documents.admit_observation
   (SR.context namespace snapshot current)source(Session.document_retention current)with
  |Documents.MalformedObservation=>(SA.fail current "The document observation does not belong to the current output.","keep",context)
  |Documents.IrrelevantObservation=>(SA.keep current,"keep",context)
  |Documents.AdmittedObservation _ _=>run_input request context namespace input raw end
 |Input.Interactive language=>
   if SR.native_language namespace snapshot current language &&
      negb (flag "semantic_lagged" request && Selvedge.Interaction.Interactive.Runtime.authored_input language &&
        negb (match string_field "op" raw with Some "element"=>true|_=>false end))
   then run_input request context namespace input raw else (SA.keep current,"keep",context)
 |_=>run_input request context namespace input raw end.

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
 if String.eqb operation "observe"then
  unchanged(match prepared_environment context,natural_field "generation" request with
  |Some env,Some generation=>if Json.equal snapshot JNull then Json.success(Document.bootstrap env generation)
   else match prepared_scene context with
   |None=>Json.success(Document.bootstrap env generation)
   |Some actual=>Json.success(Document.compile(CP.describe snapshot(prepared_state context))env generation actual)end
  |_,_=>Json.failure "InvalidEnvironment" "A current physical environment and publication generation are required."end)
 else if String.eqb operation "accepts_element"then
  unchanged(match field "input" request,natural_field "generation" request with
  |Some raw,Some _=>Json.success(JBool(match natural_field "displayed_generation" request with
  |Some displayed=>match element(prepared_scene context)displayed raw with Some _=>true|None=>false end|None=>false end))
  |_,_=>Json.success(JBool false)end)
 else if String.eqb operation "step"then match field "input" request with
  |None=>unchanged(Json.failure "InvalidInput" "An input observation is required.")
  |Some raw=>match decode_input request context raw with
   |None=>unchanged(Json.success(decision_packet context [] None false false false "keep"))
   |Some input=>match string_field "namespace" request with
    |None=>unchanged(Json.failure "InvalidNamespace" "The runtime namespace is required.")
    |Some namespace=>let '(decision,publication,next):=input_decision request context namespace input raw in
     (Json.success(decision_packet next(SA.result_effects decision)(SA.result_error decision)true(SA.result_visible_error decision)(Input.acknowledges_feedback input)publication),next)end end end
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
