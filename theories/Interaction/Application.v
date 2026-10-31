From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Programming Require Import Schema.
From Selvedge.Interaction Require Import Codec Identity Input InputCodecs ControlPurpose Documents.
From Selvedge.Interaction.Session Require State Codec Runtime Authoring.
From Selvedge.Interaction.Presentation Require Gesture.
From Selvedge.Programming.Presentation Require Surface Model.
From Selvedge.Interaction.Presentation Require View.
From Selvedge.Interaction.Interactive Require Language.
From Selvedge.Browser Require Layout Observation Document.
Import ListNotations.
Open Scope string_scope.
Module Session:=Selvedge.Interaction.Session.State.
Module SC:=Selvedge.Interaction.Session.Codec.
Module SR:=Selvedge.Interaction.Session.Runtime.
Module SA:=Selvedge.Interaction.Session.Authoring.
Module S:=Selvedge.Programming.Presentation.Surface.
Module V:=Selvedge.Interaction.Presentation.View.
Module CP:=Selvedge.Interaction.ControlPurpose.
Module BM:=Selvedge.Programming.Presentation.Model.
Definition capacity environment:=match Layout.observe_capacity environment with
|Some(navigation,details)=>Some(BM.Capacity navigation details)|None=>None end.
Definition environment request:=bind(field "environment" request)Observation.decode_environment.
Definition state request:=bind(field "state" request)SC.decode_state.
Definition surface snapshot state environment:=option_map(fun capacity=>V.view snapshot state capacity)(capacity environment).
Definition element snapshot current environment generation raw:=
 incoming<-natural_field "generation" raw;;
 if N.eqb incoming generation then
 key<-string_field "key" raw;;gesture<-bind(string_field "gesture" raw)Gesture.decode_gesture;;
 value<-Some(value_or JNull(field "value" raw));;
 actual<-surface snapshot current environment;;
 S.resolve_element actual key gesture value else None.
Definition decode_input request snapshot current raw:=match string_field "op" raw with
|Some "element"=>env<-environment request;;generation<-natural_field "displayed_generation" request;;element snapshot current env generation raw
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
Definition decision_packet current effects error handled visible_error acknowledge (publication_event:string):=JObject[("state",SC.encode_state current);
 ("file_handles",JArray(map JString(Selvedge.Interaction.Services.retained_file_handles(Session.service_state current))));
 ("effects",JArray effects);("publication_event",JString publication_event);("error",match error with None=>JNull|Some diagnostic=>diagnostic end);
 ("visible_error",JBool visible_error);("feedback_update",JString(feedback_update error visible_error acknowledge));("handled",JBool handled)].
Definition refresh request snapshot decision:=match environment request with
|Some env=>match surface snapshot(SA.result_state decision)env with
 |Some actual=>SA.append decision(SA.refresh snapshot(S.current_actions actual)(SA.result_state decision))
 |None=>decision end|None=>decision end.
Definition input_publication input current updated :=
 let changed:=if Input.semantic_change input then "advance" else "present" in
 match input with
 |Input.Snapshot|Input.EnvironmentObserved=>changed
 |_=>if Json.equal(SC.encode_state current)(SC.encode_state updated)then "keep"else changed
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
Definition run_input request snapshot namespace input raw current:=
 let decision:=restore_rejected_field input raw
   (refresh request snapshot(native_step namespace snapshot(flag "semantic_lagged" request)input raw current))in
 (decision,input_publication input current(SA.result_state decision)).

Definition input_decision request snapshot namespace input raw current:=
 match input with
 |Input.CodeObserved source=>match Documents.admit_observation
   (SR.context namespace snapshot current)source(Session.document_retention current)with
  |Documents.MalformedObservation=>(SA.fail current "The document observation does not belong to the current output.","keep")
  |Documents.IrrelevantObservation=>(SA.keep current,"keep")
  |Documents.AdmittedObservation _ _=>run_input request snapshot namespace input raw current end
 |Input.Interactive language=>
   if SR.native_language namespace snapshot current language &&
      negb (flag "semantic_lagged" request && Selvedge.Interaction.Interactive.Runtime.authored_input language &&
        negb (match string_field "op" raw with Some "element"=>true|_=>false end))
   then run_input request snapshot namespace input raw current else (SA.keep current,"keep")
 |_=>run_input request snapshot namespace input raw current end.

Definition initialized := SC.encode_state Session.initial.
Definition call operation request:json:=
 if String.eqb operation "initial"then Json.success initialized else
 if String.eqb operation "interactive_storage_policy"then
  Selvedge.Interaction.Interactive.Language.call "storage_policy" request else
 match state request,field "world" request with
 |Some current,Some snapshot=>
 if String.eqb operation "observe"then
  match environment request,natural_field "generation" request with
  |Some env,Some generation=>if Json.equal snapshot JNull then Json.success(Document.bootstrap env generation)else match surface snapshot current env with
   |None=>Json.success(Document.bootstrap env generation)
   |Some actual=>Json.success(Document.compile(CP.describe snapshot current)env generation actual)end
  |_,_=>Json.failure "InvalidEnvironment" "A current physical environment and publication generation are required."end
 else if String.eqb operation "accepts_element"then
  match field "input" request,environment request,natural_field "generation" request with
  |Some raw,Some env,Some generation=>Json.success(JBool(match natural_field "displayed_generation" request with
  |Some displayed=>match element snapshot current env displayed raw with Some _=>true|None=>false end|None=>false end))
  |_,_,_=>Json.success(JBool false)end
 else if String.eqb operation "step"then match field "input" request with
  |None=>Json.failure "InvalidInput" "An input observation is required."
  |Some raw=>match decode_input request snapshot current raw with
   |None=>Json.success(decision_packet current [] None false false false "keep")
   |Some input=>match string_field "namespace" request with
    |None=>Json.failure "InvalidNamespace" "The runtime namespace is required."
    |Some namespace=>let '(decision,publication):=input_decision request snapshot namespace input raw current in
     Json.success(decision_packet(SA.result_state decision)(SA.result_effects decision)(SA.result_error decision)true(SA.result_visible_error decision)(Input.acknowledges_feedback input)publication)end end end
 else Json.failure "UnknownOperation" operation
 |_,_=>Json.failure "InvalidState" "The typed application state and admitted world observation are required."end.
