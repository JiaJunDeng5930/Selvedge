From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Interaction Require Import Codec Identity Input Services Speech.
From Selvedge.Interaction.Session Require State NavigationCodec.
From Selvedge.Interaction.Interactive Require Types.
Import ListNotations.
Open Scope string_scope.
Definition service_receipts := ["connect";"command_assessed";"workspace_git_completed";
 "model_preference_restored";"storage_problem";"authenticated";"disconnected";
 "retry_connection";"uploaded";"previewed";"directory_listed"].
Definition speech_receipts := ["audio_capabilities";"audio_capabilities_failed";
 "audio_captured";"audio_transcribed";"voice_task_created";"voice_ready";"voice_text";
 "audio_failed";"audio_ended";"audio_released"].
(** Runtime receipts settle retained, typed requests. User actions are resolved
    from the current semantic surface; no arbitrary command/editor input codec
    is exported to native controls. *)
Definition decode_runtime value:option Input.input:=
 kind<-string_field "type" value;;
 if existsb(String.eqb kind)service_receipts then option_map Input.ServiceInput(Services.decode_service_input value)else
 if existsb(String.eqb kind)speech_receipts then option_map Input.SpeechInput(Speech.decode_input value)else
 match kind with
 |"snapshot"=>Some Input.Snapshot
 |"environment_observed"=>Some Input.EnvironmentObserved
 |"clock_observed"=>option_map Input.ClockObserved(natural_field "now" value)
 |"completed"=>ticket<-natural_field "ticket" value;;outcome<-Services.decode_outcome(fun value=>Some value)value;;Some(Input.Completed ticket outcome)
 |"directories_completed"=>ticket<-natural_field "ticket" value;;outcome<-Services.decode_outcome(fun value=>Some value)value;;Some(Input.DirectoriesCompleted ticket outcome)
 |"skill_catalog"=>ticket<-natural_field "ticket" value;;catalog<-field "skills" value;;Some(Input.SkillsLoaded ticket(inr catalog))
 |"skills_loaded"|"skill_catalog_loaded"=>ticket<-natural_field "ticket" value;;catalog<-field "value" value;;Some(Input.SkillsLoaded ticket(inr catalog))
 |"skills_failed"|"skill_catalog_failed"=>ticket<-natural_field "ticket" value;;reason<-string_field "error" value;;Some(Input.SkillsLoaded ticket(inl reason))
 |"stream"=>option_map Input.Stream(field "value" value)
 |"code_observed"=>Some(Input.CodeObserved value)
 |"interactive"=>option_map Input.Interactive(bind(field "input" value)Types.decode_input)
 |"appearance_restored"=>option_map Input.AppearanceRestored(bind(string_field "value" value)Appearance.decode_appearance)
 |"read_timeline"=>task<-natural_field "task" value;;generation<-natural_field "generation" value;;intent<-bind(field "intent" value)NavigationCodec.decode_reading;;Some(Input.ReadTimeline task generation intent)
 |_=>None end.
