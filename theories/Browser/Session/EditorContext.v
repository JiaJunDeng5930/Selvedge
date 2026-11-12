From Stdlib Require Import String List Bool.
From Selvedge.Foundation Require Import Json.
From Selvedge.Programming Require Import Resource.
From Selvedge.Interaction Require Import Codec Identity.
From Selvedge.Browser.Session Require Services.
From Selvedge.Browser.Session Require State Observation.
From Selvedge.Interaction.Experience Require Import Model Activity.
From Selvedge.Interaction.Experience Require EditorContext Observation.
From Selvedge.Interaction.Submission Require Fields Parameters.
Import ListNotations.
Open Scope string_scope.
Module SO := Selvedge.Browser.Session.Observation.
Module EO := Selvedge.Interaction.Experience.Observation.
Module EC := Selvedge.Interaction.Experience.EditorContext.

Definition run_environment_request := Activity.SubjectActivity(Parameters.name Fields.TaskEnvironment).
Definition is_run_environment_request request:=match request with
 |Activity.SubjectActivity name=>String.eqb name(Parameters.name Fields.TaskEnvironment)
 |_=>false end.
Definition run_environment_panel owner panel:=match panel with
 |State.PropertyPanel e request=>same_editor owner e&&is_run_environment_request request
 |_=>false end.

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
     (Services.workspace_git services) (Services.cloud_repository services)
     (Services.connected services) (State.generation(State.navigation_state state))
     (Services.command_assessments services) (State.now state)).
Coercion editor_context : State.state >-> EC.context.

Definition layer_focus {e}(layer:State.layer):option(subject e):=
 field<-State.layer_decision_field layer;;Model.admit_subject e(Parameters.name field).
Definition activity_completion snapshot (state:State.state) e request:EO.completion:=
 let '(focus,inspection):=match State.layers(State.navigation_state state)with
 |layer::_=>(layer_focus layer,State.layer_source_expanded layer)
 |[]=>(None,false)end in
 (* Only a compound editor or a requested subview needs its alternatives to
    determine how a completed choice returns to its owner. *)
 let inspect:=match e,focus,inspection with
 |Identity.Project _,_,_=>true
 |_,None,false=>false
 |_,_,_=>true end in
 if inspect then match EO.observe_activity snapshot state e request with
 |Some activity=>EO.completion_for activity(EO.view_for activity focus inspection)
 |None=>EO.ApplyAndDismiss end else EO.ApplyAndDismiss.
Definition activity_complete snapshot (state:State.state) e request:bool:=
 match activity_completion snapshot state e request with
 |EO.CommitOrDiscard=>match assessment_outcome(EO.observe_assessment snapshot state e)with PreparationReady=>true|_=>false end
 |_=>true end.
