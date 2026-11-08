From Stdlib Require Import String List.
From Selvedge.Foundation Require Import Json.
From Selvedge.Programming Require Import Resource.
From Selvedge.Interaction Require Import Codec Identity.
From Selvedge.Browser.Session Require Services.
From Selvedge.Browser.Session Require State Observation.
From Selvedge.Interaction.Experience Require Import Model Activity.
From Selvedge.Interaction.Experience Require EditorContext Observation.
From Selvedge.Interaction.Submission Require Parameters.
Import ListNotations.
Open Scope string_scope.
Module SO := Selvedge.Browser.Session.Observation.
Module EO := Selvedge.Interaction.Experience.Observation.
Module EC := Selvedge.Interaction.Experience.EditorContext.

Definition project_directory_buffer state owner:=
 match find(fun layer=>match State.layer_panel layer with State.PropertyPanel e _|State.EditorPanel e=>same_editor owner e|_=>false end)
   (State.layers(State.navigation_state state))with
 |Some layer=>match State.layer_parameter_buffer layer with Some value=>value|None=>""end
 |None=>""end.
Definition directory_result state draft :=
 match SO.directory_evidence state draft with
 | Some(Loaded _ _ value) => Some (inr (Services.observed_workspace value, Services.observed_guidance value))
 | Some(Failed _ _ reason) => Some (inl reason)
 | _ => None
 end.

Definition editor_context state :=
 let services := State.service_state state in
 EC.Context (State.current_draft state)
   (EC.Resources (fun e=>State.pending_editor e state) (fun e=>Services.preparing e services)
     (fun e=>Services.blocks e services) (project_directory_buffer state) (directory_result state)
     (Services.workspace_git services) (Services.connected services) (State.generation(State.navigation_state state))
     (Services.command_assessments services) (State.now state)).
Coercion editor_context : State.state >-> EC.context.

Definition layer_focus {e}(layer:State.layer):option(subject e):=
 field<-State.layer_decision_field layer;;Model.admit_subject e(Parameters.name field).
Definition current_view snapshot (state:State.state) e request:option(Activity.view e):=
 activity<-EO.observe_activity snapshot state e request;;
 match State.layers(State.navigation_state state)with
 |layer::_=>Some(EO.view_for activity(layer_focus layer)(State.layer_source_expanded layer))
 |[]=>Some(EO.view_for activity None false)end.
Definition activity_completion snapshot (state:State.state) e request:EO.completion:=
 match EO.observe_activity snapshot state e request,current_view snapshot state e request with
 |Some activity,Some view=>EO.completion_for activity view
 |_,_=>EO.ApplyAndDismiss end.
Definition activity_complete snapshot (state:State.state) e request:bool:=
 match activity_completion snapshot state e request with
 |EO.CommitOrDiscard=>match assessment_outcome(EO.observe_assessment snapshot state e)with PreparationReady=>true|_=>false end
 |_=>true end.
