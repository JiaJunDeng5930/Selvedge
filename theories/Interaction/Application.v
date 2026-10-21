From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers Schema.
From Selvedge.Interaction Require Import Codec Identity Services Forms ApplicationState
 ApplicationOps ApplicationCore Input InputCodecs Documents Presentation Scene.
From Selvedge.Interaction.Interactive Require Language Types State.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Definition append_result (before after:result) :=
 Result(resulting_state after)(emitted before++emitted after)
  (match reply after with JNull=>reply before|value=>value end).
Definition known_visible namespace world s owner := Documents.visible_owner namespace owner world s.
Definition current_language_state namespace world s :=
 Selvedge.Interaction.Interactive.State.State(map(fun block=>
  Selvedge.Interaction.Interactive.State.with_external
   (Documents.externally_allowed namespace(Selvedge.Interaction.Interactive.State.block_owner block)world s)block)
  (Selvedge.Interaction.Interactive.State.blocks(interactive_state s))).

(** The native client cannot grant a document authority or supply a definition.
    Those inputs are constructed below from an accepted world and its Markdown
    observation. IO completions retain the language reducer's ticket checks. *)
Definition native_language_input namespace world s input := match input with
 | Selvedge.Interaction.Interactive.Types.ValueChanged identity _ | Selvedge.Interaction.Interactive.Types.ActionClicked identity
 | Selvedge.Interaction.Interactive.Types.ViewChanged identity _=>known_visible namespace world s(Selvedge.Interaction.Interactive.Types.event_owner identity)
 | Selvedge.Interaction.Interactive.Types.SourceDisclosure owner | Selvedge.Interaction.Interactive.Types.CopyDefinition owner=>known_visible namespace world s owner
 | Selvedge.Interaction.Interactive.Types.Continue _ | Selvedge.Interaction.Interactive.Types.Feedback _ _ _ _ _ | Selvedge.Interaction.Interactive.Types.Restore _ _ _ _
 | Selvedge.Interaction.Interactive.Types.StorageResult _ _ _ _=>true
 | Selvedge.Interaction.Interactive.Types.SourceChanged _ _ _ _ _ | Selvedge.Interaction.Interactive.Types.ExternalChanged _ _
 | Selvedge.Interaction.Interactive.Types.EnvironmentChanged | Selvedge.Interaction.Interactive.Types.Remove _=>false end.

Definition interpret_language_effect namespace world (effect:Selvedge.Interaction.Interactive.Types.effect) s : result :=
 match effect with
 | Selvedge.Interaction.Interactive.Types.FillDraft owner _ text=>
   match Documents.owning_task namespace owner world s with
   |None=>reject "NoRecipient" "The interactive document has no active receiver" s
   |Some task=>if Documents.externally_allowed namespace owner world s then
     push_effects[Focus(editor_key(Message task)++"/message")]
      (edit_application(Message task)"message"(JString text)world s)
     else reject "ReadOnlyDocument" "The interactive document cannot change this draft" s end
 | Selvedge.Interaction.Interactive.Types.SendMessage owner path ticket message=>
   match Documents.owning_task namespace owner world s with
   |None=>reject "NoRecipient" "The interactive document has no active receiver" s
   |Some task=>if Documents.externally_allowed namespace owner world s then
     issue(JObject[("op",JString "send");("task_id",number task);("message",JString message)])
      (LanguageSubmission owner path ticket)s
     else reject "ReadOnlyDocument" "The interactive document cannot submit to this task" s end
 | _=>effects s[LanguageEffect effect]end.

Definition apply_language_in namespace world environment input s :=
 let decision:=Selvedge.Interaction.Interactive.Language.step_visible(known_visible namespace world s)input(current_language_state namespace world s)
   environment in
 let next:=with_interactive(Selvedge.Interaction.Interactive.State.next_state decision)s in
 fold_left(fun result effect=>append_result result
   (interpret_language_effect namespace world effect(resulting_state result)))
  (Selvedge.Interaction.Interactive.State.effects decision)(keep next).

Definition apply_language namespace lagged world input s :=
 apply_language_in namespace world (Documents.environment namespace lagged world s) input s.

Definition shared_definition namespace world s : option Selvedge.Interaction.Interactive.Types.input :=
 match location(navigation_state s)with
 |SharedUI work _=>found<-find_work work world;;source<-string_field "source" found;;
   revision<-natural_field "revision" found;;
   let owner:=Selvedge.Interaction.Interactive.Types.Owner(Documents.shared_key namespace work)revision in
   Some(Selvedge.Interaction.Interactive.Types.SourceChanged owner source true Selvedge.Interaction.Interactive.Types.Complete
     (Documents.externally_allowed namespace owner world s))
 |_=>None end.

Definition refresh_language namespace lagged (revoked:bool) world s :=
 let shared:=match shared_definition namespace world s with None=>keep s|Some input=>apply_language namespace lagged world input s end in
 let next:=resulting_state shared in
 (* Clear cached source values once; subsequent offline refreshes retain only the cleared handles. *)
 let environment:=Documents.environment_with_revocation namespace lagged revoked world next in
 append_result shared(apply_language_in namespace world environment Selvedge.Interaction.Interactive.Types.EnvironmentChanged next).

Definition pending_language ticket s :=
 match find(fun pending=>N.eqb ticket(ApplicationState.ticket pending))(awaiting(authoring_state s))with
 |Some pending=>match purpose pending with LanguageSubmission owner path language_ticket=>Some(owner,path,language_ticket)|_=>None end
 |None=>None end.
Definition completed_language namespace lagged world input before result :=
 match input with
 |Input.Completed ticket outcome=>match pending_language ticket before with
   |Some(owner,path,language_ticket)=>append_result result
      (apply_language namespace lagged world
       (Selvedge.Interaction.Interactive.Types.Feedback owner path language_ticket(completion_success outcome)(completion_error outcome))
       (resulting_state result))
   |None=>result end
 |_=>result end.

Definition prune_documents namespace lagged world before after:=
 fold_left(fun result stamp=>
   let current:=find(fun current=>String.eqb(document_identity stamp)(document_identity current))(document_lifetimes(resulting_state result))in
   let remove:=match current with None=>true|Some current=>document_archived current||negb(N.eqb(document_epoch stamp)(document_epoch current))end in
   if remove then fold_left(fun result ordinal=>append_result result
     (apply_language namespace lagged world(Selvedge.Interaction.Interactive.Types.Remove(Selvedge.Interaction.Interactive.Types.Owner(document_identity stamp++"/fence/"++show_natural ordinal)(document_epoch stamp)))(resulting_state result)))
     (document_fences stamp)result else result)(document_lifetimes before)(keep after).

Definition step namespace lagged now world input s :=
 let before:=s in
 let revoked:=match input with
 |Input.ServiceInput(Services.Disconnected ticket _ true)=>Services.ticket_matches ticket(Services.connection(service_state s))
 |_=>false end in
 let s:=Documents.synchronize_documents namespace lagged world s in
 let result:=match local_step now input world s with
 |Some result=>completed_language namespace lagged world input s result
 |None=>match input with
   |Input.CodeObserved observation=>match Documents.observe_document namespace observation world s with
     |Some(source,accepted)=>apply_language namespace lagged world source accepted
     |None=>reject "UnrecognizedDocument" "The Markdown observation does not belong to a visible document" s end
   |Input.RetainedOutput identity toggle=>keep(Documents.edit_retained namespace identity toggle world s)
   |Input.Interactive input=>if native_language_input namespace world s input
     then apply_language namespace lagged world input s
     else reject "UnauthorizedInput" "This interactive input is not a native capability" s
   |_=>reject "UnsupportedInput" "This interaction input has no reducer" s end end in
 let next:=Documents.synchronize_documents namespace lagged world(resulting_state result)in
 let pruned:=prune_documents namespace lagged world before next in
 append_result(append_result result pruned)(refresh_language namespace lagged revoked world(resulting_state pruned)).

Definition interactive_portals namespace lagged world s :=
 let environment:=Documents.environment namespace lagged world s in
 fold_right(fun block scenes=>let owner:=Selvedge.Interaction.Interactive.State.block_owner block in
   match Documents.portal_target namespace owner world s,
     Selvedge.Interaction.Interactive.Language.observe_owner owner(current_language_state namespace world s)environment with
   |Some target,Some scene=>
     Scene.Container Scene.CPortal("interactive/"++Selvedge.Interaction.Interactive.Types.owner_key owner++"/"++show_natural(Selvedge.Interaction.Interactive.Types.epoch owner))
      [("target",JString target)]None
      [Scene.map_actions Input.Interactive scene]::scenes
   |_,_=>scenes end)[](Selvedge.Interaction.Interactive.State.blocks(interactive_state s)).
Definition observe namespace lagged now world s :=
 Scene.Container Scene.CGroup "semantic-application" []None
  (Presentation.observe namespace now world s::interactive_portals namespace lagged world s).

Definition decode_payload payload :=
 state<-bind(field "state" payload)ApplicationState.decode_state;;
 world<-field "world" payload;;namespace<-string_field "namespace" payload;;
 lagged<-bool_field "display_lagged" payload;;now<-natural_field "now" payload;;
 Some(state,world,namespace,lagged,now).
Definition call operation payload := match operation with
 |"interactive_storage_policy"=>Selvedge.Interaction.Interactive.Language.call "storage_policy"payload
 |"initial"=>success(ApplicationState.encode_state ApplicationState.initial)
 |"step"=>match decode_payload payload,bind(field "input" payload)Input.decode_input with
   |Some(state,world,namespace,lagged,now),Some input=>
     success(encode_result(step namespace lagged now world input state))
   |_,_=>failure "InvalidInteraction" "Expected a valid state, world, native input and publication facts"end
 |"observe"=>match decode_payload payload with
   |Some(state,world,namespace,lagged,now)=>success(Scene.encode InputCodecs.encode_input(observe namespace lagged now world state))
   |None=>failure "InvalidObservation" "Expected a valid state, world and publication facts"end
 |_=>failure "UnknownInteractionOperation" "Unknown interaction operation"end.
