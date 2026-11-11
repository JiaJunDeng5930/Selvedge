From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain State.
From Selvedge.Features Require Import Domain BoardParameters.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
Import ListNotations.
Open Scope string_scope.
Definition registry (value:world) := Selvedge.Features.Domain.feature_board (world_features value).
Definition valid_draft (draft:Selvedge.Features.Domain.card_draft) (value:world) :=
 Codec.nonempty (Selvedge.Features.Domain.draft_title draft) && BoardParameters.limited (Selvedge.Features.Domain.draft_title draft) 2000 && BoardParameters.limited (Selvedge.Features.Domain.draft_description draft) 400000 &&
 Nat.leb (List.length (Selvedge.Features.Domain.draft_labels draft)) 32 && forallb (fun label=>Codec.nonempty label && BoardParameters.limited label 128) (Selvedge.Features.Domain.draft_labels draft) &&
 Nat.leb (List.length (Selvedge.Features.Domain.draft_attachments draft)) 4 &&
 (match Selvedge.Features.Domain.draft_project draft with None=>true | Some id=>match registry_at id (world_projects value) with Some project=>negb (project_deleted project) | None=>false end end).
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
Definition active_for (owner:Selvedge.Features.Domain.owner) (value:world) := N.of_nat (List.length (filter
 (fun candidate=>match candidate with Some card=>String.eqb (Selvedge.Features.Domain.owner_name owner) (Selvedge.Features.Domain.owner_name (Selvedge.Features.Domain.draft_owner (Selvedge.Features.Domain.card_contents card))) && busy card value | None=>false end) (Selvedge.Features.Domain.board_cards (registry value)))).
Definition runnable_profile (card:Selvedge.Features.Domain.card) (value:world) :=
 if request_available card && unlinked card then
 match Selvedge.Features.Domain.draft_owner (Selvedge.Features.Domain.card_contents card) with
 | Selvedge.Features.Domain.ProfileOwner profile=>
   if N.ltb (active_for (Selvedge.Features.Domain.ProfileOwner profile) value) 1 then Some profile else None
 | _=>None end else None.
Definition runnable (card:Selvedge.Features.Domain.card) (value:world) :=
 match runnable_profile card value with Some _=>true | None=>false end.
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
