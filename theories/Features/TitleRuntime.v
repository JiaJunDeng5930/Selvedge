From Selvedge.Kernel Require CallbackDeclarations.
From Stdlib Require Import String Ascii List Bool NArith.
From Selvedge.Foundation Require Import Json Utf8 Schema.
From Selvedge.Kernel Require Import Numbers Domain State Tasks TicketedRequest DecisionComposition FeatureRequestAdmission.
From Selvedge.Generated Require Import Commands.
From Selvedge.Features Require Import Domain State Titles Observation.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Definition entry := FeatureRequestAdmission.title_entry.
Definition store := TicketedRequest.Scoped.put_title.
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
Definition protocol (features : Selvedge.Features.Domain.state) owner
 : RequestTypes.located (profile * string) features :=
 RequestTypes.Protocol
   (Receiver.At.inject Selvedge.Features.Domain.TitlePending
     (Receiver.At.field features Selvedge.Features.Domain.feature_titles
       (Receiver.At.inject (Selvedge.Features.Domain.TitleEntry owner)
         (Receiver.At.keyed (Selvedge.Features.Domain.feature_titles features) Selvedge.Features.Domain.title_task))))
   ModelDeclarations.task_title_request
   (fun input _ => Schema.of_tuple (ModelDeclarations.request_body_fields ModelDeclarations.task_title_request)
     [!Codec.task_text_model_json (fst input);snd input!]).
Definition channel : TicketedRequest.Scoped.feature_channel FeatureRequestAdmission.resolved_title (profile * string) :=
 TicketedRequest.Scoped.FeatureChannel TicketedRequest.TaskTicket
   (fun before request => (FeatureRequestAdmission.title_profile request,
     FeatureRequestAdmission.title_prompt (TaskScope.selected (FeatureRequestAdmission.title_reference request)) before))
   (fun before request => protocol (world_features before)
     (TaskScope.owner (FeatureRequestAdmission.title_reference request))).
Definition plan {before} (request : FeatureRequestAdmission.resolved_title before) :=
 TicketedRequest.Scoped.FeaturePlan channel request.
Definition issue {before} (request : FeatureRequestAdmission.resolved_title before) : CommandResult.change :=
 let issued := TicketedRequest.Scoped.feature_issue_change (plan request) in
 CommandResult.Change JNull (CommandResult.change_world issued) (CommandResult.change_effects issued).
Definition start (id:N) (result:decision) :decision :=
 match FeatureRequestAdmission.resolve_title id (decision_world result) with
 | None => result
 | Some request => DecisionComposition.follow result (CommandResult.accept (issue request))
 end.
Definition complete (id ticket:N) (ok:bool) (text:string) (value:world) :=
 let correlated:=match entry id value with Some item=>match Selvedge.Features.Domain.title_value item with Selvedge.Features.Domain.TitlePending (RequestEnvelope.Envelope expected (_, _))=>N.eqb ticket expected | _=>false end | None=>false end in
 let normalized:=Titles.normalize text in
 let next:=if correlated then store id (if ok && negb (String.eqb normalized "") then Selvedge.Features.Domain.Named normalized else Selvedge.Features.Domain.TitleFailed text) value else value in
 Selvedge.Kernel.State.accept (JObject [("accepted",JBool correlated)]) next [].
Definition completion (source:json) (value:world) :option (bool*bool*decision) :=
 match CallbackDeclarations.decode ModelDeclarations.TaskTitle source with
 | Some (existT _ ok (address,values)) =>
   Some (true,true,complete (head address) (head (tail address)) ok (proj1_sig (fst values)) value)
 | None => None end.
Definition recover (value:world) := Selvedge.Kernel.State.with_features
 (Selvedge.Features.State.with_titles (map (fun item=>match Selvedge.Features.Domain.title_value item with
 | Selvedge.Features.Domain.TitlePending (RequestEnvelope.Envelope _ (_, _))=>Selvedge.Features.Domain.TitleEntry (Selvedge.Features.Domain.title_task item) (Selvedge.Features.Domain.TitleFailed "Interrupted before title generation completed")
 | _=>item end) (Selvedge.Features.Domain.feature_titles (world_features value))) (world_features value)) value.
