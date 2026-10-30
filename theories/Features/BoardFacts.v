From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain State.
From Selvedge.Features Require Import Domain BoardParameters.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
Import ListNotations.
Open Scope string_scope.
Definition registry (value:world) := Selvedge.Features.Domain.feature_board (world_features value).
Definition lookup_agent (id:N) (value:world) := match registry_at id (Selvedge.Features.Domain.board_agents (registry value)) with Some agent=>agent | None=>None end.
Definition valid_draft (draft:Selvedge.Features.Domain.card_draft) (value:world) :=
 Codec.nonempty (Selvedge.Features.Domain.draft_title draft) && BoardParameters.limited (Selvedge.Features.Domain.draft_title draft) 2000 && BoardParameters.limited (Selvedge.Features.Domain.draft_description draft) 400000 &&
 Nat.leb (List.length (Selvedge.Features.Domain.draft_labels draft)) 32 && forallb (fun label=>Codec.nonempty label && BoardParameters.limited label 128) (Selvedge.Features.Domain.draft_labels draft) &&
 Nat.leb (List.length (Selvedge.Features.Domain.draft_attachments draft)) 4 &&
 (match Selvedge.Features.Domain.draft_owner draft with Selvedge.Features.Domain.AgentOwner id=>match lookup_agent id value with Some _=>true | None=>false end | _=>true end) &&
 (match Selvedge.Features.Domain.draft_project draft with None=>true | Some id=>match registry_at id (world_projects value) with Some project=>negb (project_deleted project) | None=>false end end).
Definition revised (draft:Selvedge.Features.Domain.card_draft) (now:N) (card:Selvedge.Features.Domain.card) := (set Selvedge.Features.Domain.card_updated (fun _=>now) (set Selvedge.Features.Domain.card_contents (fun _=>draft) (set Selvedge.Features.Domain.card_revision (fun _=>(N.succ (Selvedge.Features.Domain.card_revision card))) (card)))).
Definition linked_task (card:Selvedge.Features.Domain.card) (value:world) := match Selvedge.Features.Domain.card_task card with Some id=>Selvedge.Kernel.State.find_task id value | None=>None end.
Definition busy_task := Selvedge.Kernel.Domain.task_busy.
Definition busy (card:Selvedge.Features.Domain.card) (value:world) := match linked_task card value with Some task=>busy_task task | None=>false end.
Definition pending (card:Selvedge.Features.Domain.card) := match Selvedge.Features.Domain.card_enrichment card with Selvedge.Features.Domain.Enriching (RequestEnvelope.Envelope _ (_, _))=>true | _=>false end.
Definition mutable (card:Selvedge.Features.Domain.card) (value:world) := negb (Selvedge.Features.Domain.card_archived card || pending card || busy card value).
Definition unlinked (card:Selvedge.Features.Domain.card) := match Selvedge.Features.Domain.card_task card with None=>true | _=>false end.
Definition owner_agent (owner:Selvedge.Features.Domain.owner) (value:world) := match owner with
 | Selvedge.Features.Domain.ProfileOwner key=>Some (Selvedge.Features.Domain.BoardAgent 0 key key "default" "" (JObject []) 1)
 | Selvedge.Features.Domain.AgentOwner id=>lookup_agent id value | _=>None end.
Definition active_for (owner:Selvedge.Features.Domain.owner) (value:world) := N.of_nat (List.length (filter
 (fun candidate=>match candidate with Some card=>String.eqb (Selvedge.Features.Domain.owner_name owner) (Selvedge.Features.Domain.owner_name (Selvedge.Features.Domain.draft_owner (Selvedge.Features.Domain.card_contents card))) && busy card value | None=>false end) (Selvedge.Features.Domain.board_cards (registry value)))).
Definition runnable (card:Selvedge.Features.Domain.card) (value:world) := mutable card value && unlinked card &&
 match owner_agent (Selvedge.Features.Domain.draft_owner (Selvedge.Features.Domain.card_contents card)) value with Some agent=>N.ltb (active_for (Selvedge.Features.Domain.draft_owner (Selvedge.Features.Domain.card_contents card)) value) (Selvedge.Features.Domain.agent_concurrency agent) | None=>false end.
Fixpoint latest_failure_events (history:list message) := match history with
 | []=>false | FailureMessage _::_=>true | UserMessage _::_|AssistantMessage _ _::_|ModelContext _ _::_=>false | _::rest=>latest_failure_events rest end.
Definition latest_failure (task:task) := latest_failure_events (rev (task_history task)).
(** A queued card may still be waiting for its agent's concurrency slot. *)
Definition queued_candidate (card:Selvedge.Features.Domain.card) :=
 negb (Selvedge.Features.Domain.card_archived card) && unlinked card &&
 (match Selvedge.Features.Domain.card_enrichment card with Selvedge.Features.Domain.NoEnrichment=>true|_=>false end) &&
 (match Selvedge.Features.Domain.draft_stage (Selvedge.Features.Domain.card_contents card) with Selvedge.Features.Domain.Todo|Selvedge.Features.Domain.InProgress=>true|_=>false end) &&
 match Selvedge.Features.Domain.draft_owner (Selvedge.Features.Domain.card_contents card) with Selvedge.Features.Domain.ProfileOwner _|Selvedge.Features.Domain.AgentOwner _=>true|_=>false end.
Definition activity (card:Selvedge.Features.Domain.card) (value:world) := match Selvedge.Features.Domain.card_enrichment card with
 | Selvedge.Features.Domain.Enriching (RequestEnvelope.Envelope _ (_, _))=>"generating" | Selvedge.Features.Domain.EnrichmentFailed _=>"draft_failed" | _=>match linked_task card value with
 | Some task=>match task_lifecycle task with Archived _=>"archived" | Stopped Idle []=>"interrupted" | Frozen _ _=>"paused"
 | Running (EvaluatingReasoning _ _) _=>"evaluating" | _=>if existsb (fun operation=>match operation_stage operation with AwaitingApproval _ _=>true | _=>false end) (task_operations task) then "awaiting_approval" else if busy_task task then "working" else if latest_failure task then "failed" else "completed" end
 | None=>if Selvedge.Features.Domain.board_automatic (registry value) && queued_candidate card then "queued" else "not_started" end end.
