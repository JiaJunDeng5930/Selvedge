From Selvedge.Programming Require RequestTypes.
From Selvedge.Programming Require CommandResult TaskScope.
From Selvedge.Programming Require Callback Variant.
From Selvedge.Programming Require InputRoute.
From Stdlib Require Import String Ascii List Bool NArith.
From Selvedge.Foundation Require Import Json Utf8.
From Selvedge.Programming Require Import Schema Completion.
From Selvedge.Kernel Require Import Numbers Domain State Tasks.
From Selvedge.Programming Require Import FeatureRequest DecisionComposition.
From Selvedge.Kernel Require Import FeatureRequestAdmission.
From Selvedge.Generated Require Import Commands.
From Selvedge.Features Require Import Domain State Titles Observation.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Definition entry := FeatureRequestAdmission.title_entry.
Definition configure (revision:N) (task_prompt agent_prompt : Titles.instruction) (value:world) :=
 let current:=Selvedge.Features.Domain.feature_title_settings (world_features value) in
 if negb (N.eqb revision (Selvedge.Features.Domain.title_revision current)) then
 Selvedge.Kernel.State.reject "title_settings_conflict" "Title settings changed; reopen the settings before saving" value
 else let updated:=Selvedge.Features.Domain.TitleSettings (N.succ revision) task_prompt agent_prompt in
 Selvedge.Kernel.State.accept (Observation.title_settings_json updated) (Selvedge.Kernel.State.with_features (Selvedge.Features.State.with_title_settings updated (world_features value)) value) [].
Definition handle_read_title_settings (_payload : Selvedge.Generated.Commands.read_title_settings_payload)
 (_caller : option N) (value : Selvedge.Kernel.State.world) : json :=
 Selvedge.Kernel.State.success (Observation.title_settings_json (Selvedge.Features.Domain.feature_title_settings (world_features value))).

Definition handle_configure_title_settings (p : Selvedge.Generated.Commands.configure_title_settings_payload)
 (_caller : option N) (value : Selvedge.Kernel.State.world) : decision :=
 configure (Selvedge.Generated.Commands.configure_title_settings_revision p)
   (Selvedge.Generated.Commands.configure_title_settings_task_prompt_admitted p)
   (Selvedge.Generated.Commands.configure_title_settings_agent_prompt_admitted p) value.

Definition first_request := Observation.first_request.
Definition split_slash := FeatureRequestAdmission.split_slash.
Definition account_prefix := FeatureRequestAdmission.account_prefix.
Definition capable := FeatureRequestAdmission.capable_profile.
Definition ordinary := FeatureRequestAdmission.ordinary_profile.
Definition selected_profile := FeatureRequestAdmission.selected_title_profile.
Definition prompt := Titles.prompt_with.
Definition accepts := FeatureRequestAdmission.title_accepts.
Definition storage (features : Selvedge.Features.Domain.state) owner :=
 Receiver.At.field features Selvedge.Features.Domain.feature_titles
   (Receiver.At.inject (Selvedge.Features.Domain.TitleEntry owner)
     (Receiver.At.keyed (Selvedge.Features.Domain.feature_titles features) Selvedge.Features.Domain.title_task)).
Definition protocol (features : Selvedge.Features.Domain.state) owner
 : RequestTypes.located (profile * string) features :=
 RequestTypes.Protocol
   (Receiver.At.inject Selvedge.Features.Domain.TitlePending (storage features owner))
   ModelDeclarations.task_title_request
   (fun input _ => Schema.of_tuple (Variant.request_body_fields ModelDeclarations.task_title_request)
     [!Codec.task_text_model_json (fst input);snd input!]).
Definition channel : FeatureRequest.feature_channel FeatureRequestAdmission.resolved_title (profile * string) :=
 FeatureRequest.FeatureChannel Selvedge.Kernel.State.TaskTicket
   (fun before request => (FeatureRequestAdmission.title_profile request,
     FeatureRequestAdmission.title_prompt (TaskScope.selected (FeatureRequestAdmission.title_reference request)) before))
   (fun before request => protocol (world_features before)
     (TaskScope.owner (FeatureRequestAdmission.title_reference request))).
Definition plan {before} (request : FeatureRequestAdmission.resolved_title before) :=
 FeatureRequest.FeaturePlan channel request.
Definition issue {before} (request : FeatureRequestAdmission.resolved_title before) : CommandResult.change :=
 let issued := FeatureRequest.feature_issue_change (plan request) in
 CommandResult.Change JNull (CommandResult.change_world issued) (CommandResult.change_effects issued).
Definition start (id:N) (result:decision) :decision :=
 match FeatureRequestAdmission.resolve_title id (decision_world result) with
 | None => result
 | Some request => DecisionComposition.follow result (CommandResult.accept (issue request))
 end.
Definition reception features id := Completion.direct
 (Receiver.field world_features (Receiver.path (storage features id))).
Definition completed_name (ok : bool) (text : string)
 : Completion.terminal Selvedge.Features.Domain.TitlePending :=
 let normalized:=Titles.normalize text in
 if ok && negb (String.eqb normalized "") then Completion.done (Selvedge.Features.Domain.Named normalized)
 else Completion.done (Selvedge.Features.Domain.TitleFailed text).
Definition complete (id ticket:N) (ok:bool) (text:string) (value:world) :=
 let '(correlated,next) := Completion.run (reception (world_features value) id) Selvedge.Features.Domain.TitlePending
   Completion.Ticket ticket (fun _ => completed_name ok text) value in
 Selvedge.Kernel.State.accept (JObject [("accepted",JBool correlated)]) next [].
Definition completion (received : Callback.decoded ModelDeclarations.TaskTitle) (value : world)
 : bool * bool * decision :=
 let '(existT _ ok (address,fields)) := received in
 (true,true,complete (head address) (head (tail address)) ok (proj1_sig (fst fields)) value).
Definition completion_inputs := [InputRoute.callback ModelDeclarations.TaskTitle
 (fun received => Some (completion received))].
Definition recover (value:world) := Selvedge.Kernel.State.with_features
 (Selvedge.Features.State.with_titles (map (fun item=>match Selvedge.Features.Domain.title_value item with
 | Selvedge.Features.Domain.TitlePending (RequestEnvelope.Envelope _ (_, _))=>Selvedge.Features.Domain.TitleEntry (Selvedge.Features.Domain.title_task item) (Selvedge.Features.Domain.TitleFailed "Interrupted before title generation completed")
 | _=>item end) (Selvedge.Features.Domain.feature_titles (world_features value))) (world_features value)) value.
