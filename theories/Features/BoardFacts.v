From Selvedge.Features Require WorkflowTypes.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Foundation Require IndexedRegistry ScopedRegistry.
From Selvedge.Foundation Require DependencyIndex.
From Selvedge.Kernel Require Import Numbers Domain State.
From Selvedge.Features Require Import Domain BoardParameters.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
Import ListNotations.
Open Scope string_scope.
Definition registry (value:world) := Selvedge.Features.Domain.feature_board (world_features value).
Definition title_has_content := Codec.nonempty.
Definition title_within_limit (title:string) := BoardParameters.limited title 2000.
Definition description_within_limit (description:string) := BoardParameters.limited description 400000.
Definition valid_metadata (draft:Selvedge.Features.Domain.card_draft) (value:world) :=
 title_has_content (Selvedge.Features.Domain.draft_title draft) &&
 title_within_limit (Selvedge.Features.Domain.draft_title draft) &&
 description_within_limit (Selvedge.Features.Domain.draft_description draft) &&
 Nat.leb (List.length (Selvedge.Features.Domain.draft_labels draft)) 32 && forallb (fun label=>Codec.nonempty label && BoardParameters.limited label 128) (Selvedge.Features.Domain.draft_labels draft) &&
 (match Selvedge.Features.Domain.draft_project draft with None=>true | Some id=>match find_project id value with Some project=>negb (project_deleted project) | None=>false end end).
Definition attachment_limit (draft:Selvedge.Features.Domain.card_draft) :=
 Nat.leb (List.length (Selvedge.Features.Domain.draft_attachments draft)) 4.
Definition valid_draft draft value := valid_metadata draft value && attachment_limit draft.
Definition revised (draft:Selvedge.Features.Domain.card_draft) (now:BoardClock.t) (card:Selvedge.Features.Domain.card) := (set Selvedge.Features.Domain.card_updated_at (fun _=>now) (set Selvedge.Features.Domain.card_contents (fun _=>draft) (set Selvedge.Features.Domain.card_revision (fun _=>(N.succ (Selvedge.Features.Domain.card_revision card))) (card)))).
Definition linked_task (card:Selvedge.Features.Domain.card) (value:world) := match Selvedge.Features.Domain.card_task card with Some id=>Selvedge.Kernel.State.find_task id value | None=>None end.
Definition busy_task := Selvedge.Kernel.Domain.task_busy.
Definition busy (card:Selvedge.Features.Domain.card) (value:world) := match linked_task card value with Some task=>busy_task task | None=>false end.
Definition pending (card:Selvedge.Features.Domain.card) := match Selvedge.Features.Domain.card_enrichment card with Selvedge.Features.Domain.Enriching _=>true | _=>false end.
Definition editable (card:Selvedge.Features.Domain.card) := negb (Selvedge.Features.Domain.card_archived card).
Definition request_available (card:Selvedge.Features.Domain.card) := editable card && negb (pending card).
Definition stage_available (card:Selvedge.Features.Domain.card) (destination:Selvedge.Features.Domain.board_stage) (value:world) :=
 negb (busy card value) || match destination with Selvedge.Features.Domain.InProgress=>true | _=>false end.
Definition unlinked (card:Selvedge.Features.Domain.card) := match Selvedge.Features.Domain.card_task card with None=>true | _=>false end.
Definition active_card_for owner value candidate :=
 match candidate with
 | Some card =>
   String.eqb (Selvedge.Features.Domain.owner_name owner)
     (Selvedge.Features.Domain.owner_name (Selvedge.Features.Domain.draft_owner (Selvedge.Features.Domain.card_contents card))) &&
   busy card value
 | None => false
 end.
Definition workflow_binding {A} id (bindings : list (N * A)) :=
 option_map snd (find (fun pair => N.eqb (fst pair) id) bindings).
Definition workflow_setting id value :=
 workflow_binding id (Selvedge.Features.Domain.feature_ticket_workflows (world_features value)).
Definition workflow_instance_id id value :=
 workflow_binding id (Selvedge.Features.Domain.feature_ticket_instances (world_features value)).
Definition workflow_instance id value :=
 match workflow_instance_id id value with
 | Some key => IndexedRegistry.lookup key
     (ScopedRegistry.rows (Selvedge.Features.Domain.feature_instances (world_features value)))
 | None => None end.
Definition workflow_in_progress id value :=
 match workflow_instance id value with
 | Some instance => WorkflowTypes.instance_in_progress instance
 | None => false end.
Definition has_workflow id value :=
 match workflow_setting id value with Some _=>true | None=>false end.
Definition runnable_profile_with (occupied : Selvedge.Features.Domain.owner -> world -> bool)
 (card:Selvedge.Features.Domain.card) (value:world) :=
 if request_available card && unlinked card then
 match Selvedge.Features.Domain.draft_owner (Selvedge.Features.Domain.card_contents card) with
 | Selvedge.Features.Domain.ProfileOwner profile=>
   if occupied (Selvedge.Features.Domain.ProfileOwner profile) value then None else Some profile
 | _=>None end else None.
Definition observe_failure (failed:bool) (event:message) := match event with
 |FailureMessage _=>true |UserMessage _|AssistantMessage _ _|ModelContext _ _=>false
 |_=>failed end.
Definition latest_failure (task:task) := fold_left observe_failure (task_history task) false.
Definition initial_link_stage := InProgress.
Definition stage_after_execution (previous:board_stage) (busy:bool) (failed:unit->bool) :=
 if busy then InProgress else
 match previous with InProgress=>if failed tt then Blocked else InReview|_=>previous end.
Definition stage_after_task previous task :=
 stage_after_execution previous (busy_task task) (fun _=>latest_failure task).
Definition automatic_stage stage := match stage with Todo|InProgress=>true|_=>false end.
Definition enrichment_ready (card:Selvedge.Features.Domain.card) :=
 match Selvedge.Features.Domain.card_enrichment card with NoEnrichment=>true|_=>false end.
(** A queued card may still be waiting for its model profile's concurrency slot. *)
Definition queued_candidate (card:Selvedge.Features.Domain.card) :=
 negb (Selvedge.Features.Domain.card_archived card) && unlinked card &&
 enrichment_ready card && automatic_stage (Selvedge.Features.Domain.draft_stage (Selvedge.Features.Domain.card_contents card)) &&
 match Selvedge.Features.Domain.draft_owner (Selvedge.Features.Domain.card_contents card) with Selvedge.Features.Domain.ProfileOwner _=>true|_=>false end.

Module F := Selvedge.Features.Domain.
Record card_dependencies := CardDependencies {
 task_cards : DependencyIndex.t N;
 owner_cards : DependencyIndex.t N;
 owner_unlinked : DependencyIndex.t N;
 profile_queue : DependencyIndex.t N;
 queued_profiles : IndexedRegistry.Slots.t string
}.
Definition update_dependencies (add : bool) id (candidate : option F.card) current :=
 match candidate with
 | None => current
 | Some card =>
   let update key index :=
     if add then DependencyIndex.include key id id index else DependencyIndex.exclude key id index in
   let owner := F.draft_owner (F.card_contents card) in
   let address := DependencyIndex.text_address (F.owner_name owner) in
   let linked := match F.card_task card with
     | Some task => (update (IndexedRegistry.key task) (task_cards current), update address (owner_cards current))
     | None => (task_cards current, owner_cards current) end in
   let queues := profile_queue current in
   let profiles := queued_profiles current in
   let '(queues, profiles) := if queued_candidate card then
     let next := update address queues in
     (next, match owner with
       | F.ProfileOwner profile =>
         if add then IndexedRegistry.Slots.add address profile profiles
         else match IndexedRegistry.Slots.find address next with
           | None => IndexedRegistry.Slots.remove address profiles | Some _ => profiles end
       | _ => profiles end)
     else (queues, profiles) in
   CardDependencies (fst linked) (snd linked)
     (if unlinked card then update address (owner_unlinked current) else owner_unlinked current)
     queues profiles
 end.
Definition projections := DependencyIndex.project
 (CardDependencies (IndexedRegistry.Slots.empty _) (IndexedRegistry.Slots.empty _)
   (IndexedRegistry.Slots.empty _) (IndexedRegistry.Slots.empty _) (IndexedRegistry.Slots.empty _))
 (update_dependencies true) (update_dependencies false).
Definition rows value := F.board_card_registry (registry value).
Definition dependencies value := projections (rows value).
Definition linked_card_ids task value :=
 DependencyIndex.members (IndexedRegistry.key task) (task_cards (dependencies value)).
Definition unlinked_card_ids profile value :=
 DependencyIndex.members (DependencyIndex.text_address (F.owner_name (F.ProfileOwner profile)))
   (owner_unlinked (dependencies value)).
Definition linked_card_profile (candidate : option F.card) :=
 match candidate with
 | Some card => match F.card_task card, F.draft_owner (F.card_contents card) with
   | Some _, F.ProfileOwner profile => Some profile | _, _ => None end
 | None => None end.
Definition has_active_card owner value :=
 existsb (fun id => match IndexedRegistry.lookup id (rows value) with
   | Some row => active_card_for owner value row | None => false end)
 (DependencyIndex.members (DependencyIndex.text_address (F.owner_name owner)) (owner_cards (dependencies value))).
Definition runnable_profile := runnable_profile_with has_active_card.
Definition runnable card value :=
 match runnable_profile card value with Some _=>true | None=>false end.
Inductive save_consequence := SaveManual | SaveNeedsStage | SaveStarts | SaveQueues | SaveWaitsForModel
 | SaveDrafts | SaveDraftsThenQueues | SaveLinked.
Definition save_consequence_name consequence := match consequence with
 |SaveManual=>"manual"|SaveNeedsStage=>"needs_stage"|SaveStarts=>"starts"|SaveQueues=>"queues"
 |SaveWaitsForModel=>"waits_for_model"|SaveDrafts=>"drafts"|SaveDraftsThenQueues=>"drafts_then_queues"
 |SaveLinked=>"linked" end.
Definition save_consequence_of_name name :=
 find(fun consequence=>String.eqb name(save_consequence_name consequence))
 [SaveManual;SaveNeedsStage;SaveStarts;SaveQueues;SaveWaitsForModel;SaveDrafts;SaveDraftsThenQueues;SaveLinked].
Definition activity (card:Selvedge.Features.Domain.card) (value:world) := match Selvedge.Features.Domain.card_enrichment card with
 | Selvedge.Features.Domain.Enriching _=>"generating" | Selvedge.Features.Domain.EnrichmentFailed _=>"draft_failed" | _=>match linked_task card value with
 | Some task=>match task_lifecycle task with Archived _=>"archived" | Stopped Idle []=>"interrupted" | Frozen _ _=>"paused"
 | Running (EvaluatingReasoning _ _) _=>"evaluating" | _=>if existsb (fun operation=>match operation_stage operation with AwaitingApproval _ _=>true | _=>false end) (task_operations task) then "awaiting_approval" else if busy_task task then "working" else if latest_failure task then "failed" else "completed" end
 | None=>if Selvedge.Features.Domain.board_automatic (registry value) && queued_candidate card then "queued" else "not_started" end end.
