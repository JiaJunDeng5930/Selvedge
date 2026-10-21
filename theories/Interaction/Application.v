From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers Schema.
From Selvedge.Interaction Require Import Codec Identity Input InputCodecs ControlPurpose.
From Selvedge.Interaction.Session Require State Codec Runtime Authoring.
From Selvedge.Interaction.Presentation Require Gesture Surface Model View.
From Selvedge.Interaction.Interactive Require Language.
From Selvedge.Browser Require Layout Observation Document.
Import ListNotations.
Open Scope string_scope.
Module Session:=Selvedge.Interaction.Session.State.
Module SC:=Selvedge.Interaction.Session.Codec.
Module SR:=Selvedge.Interaction.Session.Runtime.
Module SA:=Selvedge.Interaction.Session.Authoring.
Module S:=Selvedge.Interaction.Presentation.Surface.
Module V:=Selvedge.Interaction.Presentation.View.
Module CP:=Selvedge.Interaction.ControlPurpose.
Module BM:=Selvedge.Interaction.Presentation.Model.
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
|Some "element"=>env<-environment request;;generation<-natural_field "generation" request;;element snapshot current env generation raw
|_=>InputCodecs.decode_runtime raw end.
Definition decision_packet current effects error handled:=JObject[("state",SC.encode_state current);
 ("effects",JArray effects);("error",match error with None=>JNull|Some message=>JString message end);("handled",JBool handled)].
Definition refresh request snapshot decision:=match environment request with
|Some env=>match surface snapshot(SA.result_state decision)env with
 |Some actual=>SA.append decision(SA.refresh snapshot(S.current_actions actual)(SA.result_state decision))
 |None=>decision end|None=>decision end.
Definition initialized := SC.encode_state Session.initial.
Definition call operation request:json:=
 if String.eqb operation "initial"then Json.success initialized else
 if String.eqb operation "interactive_storage_policy"then
  Selvedge.Interaction.Interactive.Language.call "storage_policy" request else
 match state request,field "world" request with
 |Some current,Some snapshot=>
 if String.eqb operation "observe"then
  match environment request,natural_field "generation" request with
  |Some env,Some generation=>match surface snapshot current env with
   |None=>Json.success(Document.bootstrap env generation)
   |Some actual=>Json.success(Document.compile(CP.describe snapshot current)env generation actual)end
  |_,_=>Json.failure "InvalidEnvironment" "A current physical environment and publication generation are required."end
 else if String.eqb operation "accepts_element"then
  match field "input" request,environment request,natural_field "generation" request with
  |Some raw,Some env,Some generation=>Json.success(JBool(match element snapshot current env generation raw with Some _=>true|None=>false end))
  |_,_,_=>Json.success(JBool false)end
 else if String.eqb operation "step"then match field "input" request with
  |None=>Json.failure "InvalidInput" "An input observation is required."
  |Some raw=>match decode_input request snapshot current raw with
   |None=>Json.success(decision_packet current [] None false)
   |Some input=>match string_field "namespace" request with
    |None=>Json.failure "InvalidNamespace" "The runtime namespace is required."
    |Some namespace=>let decision:=refresh request snapshot(SR.step namespace snapshot(flag "display_lagged" request)input current)in
     Json.success(decision_packet(SA.result_state decision)(SA.result_effects decision)(SA.result_error decision)true)end end end
 else Json.failure "UnknownOperation" operation
 |_,_=>Json.failure "InvalidState" "The typed application state and admitted world observation are required."end.
