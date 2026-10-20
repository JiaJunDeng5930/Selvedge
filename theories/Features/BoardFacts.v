From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain State.
From Selvedge.Features Require Import Domain.
Import ListNotations.
Open Scope string_scope.
Definition registry (value:world) := Selvedge.Features.Domain.feature_board (world_features value).
Definition lookup_agent (id:N) (value:world) := match registry_at id (Selvedge.Features.Domain.board_agents (registry value)) with Some agent=>agent | None=>None end.
Definition linked_task (card:Selvedge.Features.Domain.card) (value:world) := match Selvedge.Features.Domain.card_task card with Some id=>Selvedge.Kernel.State.find_task id value | None=>None end.
Definition busy_task := Selvedge.Kernel.Domain.task_busy.
Definition busy (card:Selvedge.Features.Domain.card) (value:world) := match linked_task card value with Some task=>busy_task task | None=>false end.
Definition pending (card:Selvedge.Features.Domain.card) := match Selvedge.Features.Domain.card_enrichment card with Selvedge.Features.Domain.Enriching _ _ _=>true | _=>false end.
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
Definition activity (card:Selvedge.Features.Domain.card) (value:world) := match Selvedge.Features.Domain.card_enrichment card with
 | Selvedge.Features.Domain.Enriching _ _ _=>"generating" | Selvedge.Features.Domain.EnrichmentFailed _=>"draft_failed" | _=>match linked_task card value with
 | Some task=>match task_lifecycle task with Archived=>"archived" | Stopped Idle []=>"interrupted" | Frozen _ _=>"paused"
 | Running (EvaluatingReasoning _ _) _=>"evaluating" | _=>if existsb (fun operation=>match operation_stage operation with AwaitingApproval _ _=>true | _=>false end) (task_operations task) then "awaiting_approval" else if busy_task task then "working" else if latest_failure task then "failed" else "completed" end
 | None=>if runnable card value && (match Selvedge.Features.Domain.draft_stage (Selvedge.Features.Domain.card_contents card) with Selvedge.Features.Domain.Todo|Selvedge.Features.Domain.InProgress=>true | _=>false end) then "queued" else "not_started" end end.
