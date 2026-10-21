From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Utf8.
From Selvedge.Kernel Require Import Numbers Domain Codec WorkspaceBackend.
From Selvedge.Features Require Import Domain BoardFacts Titles.
From Selvedge.Kernel Require Import State.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Definition work_json (id : N) (value : Selvedge.Features.Domain.work) := JObject [
 ("work_id", number id); ("name", JString (Selvedge.Features.Domain.work_name value));
 ("source", JString (Selvedge.Features.Domain.work_ui_source value)); ("revision", number (Selvedge.Features.Domain.work_ui_revision value))].
Definition stage_name := Selvedge.Features.Domain.stage_name.
Definition priority_name := Selvedge.Features.Domain.priority_name.
Definition owner_name := Selvedge.Features.Domain.owner_name.
Definition attachment_json (value : Selvedge.Features.Domain.attachment) := JObject [
 ("id", JString (Selvedge.Features.Domain.attachment_id value)); ("name", JString (Selvedge.Features.Domain.attachment_name value));
 ("mime", JString (Selvedge.Features.Domain.attachment_mime value)); ("path", JString (Selvedge.Features.Domain.attachment_path value));
 ("bytes", JString (Selvedge.Features.Domain.decimal_text (Selvedge.Features.Domain.attachment_bytes value)))].
Definition enrichment_json (value:Selvedge.Features.Domain.enrichment) := match value with
 | Selvedge.Features.Domain.NoEnrichment=>JObject [("status",JString "idle")]
 | Selvedge.Features.Domain.Enriching ticket revision retitle=>JObject [("status",JString "running");("ticket",number ticket);("revision",number revision);("retitle",JBool retitle)]
 | Selvedge.Features.Domain.EnrichmentFailed reason=>JObject [("status",JString "failed");("reason",JString reason)] end.
Definition card_json (id : N) (value : Selvedge.Features.Domain.card) :=
 let draft := Selvedge.Features.Domain.card_contents value in JObject [
 ("id", number id); ("card_id", number id); ("identifier",JString (String.append "SV-" (Selvedge.Features.Domain.decimal_text (N.succ id)))); ("enrichment",enrichment_json (Selvedge.Features.Domain.card_enrichment value)); ("revision", number (Selvedge.Features.Domain.card_revision value));
 ("title", JString (Selvedge.Features.Domain.draft_title draft)); ("description", JString (Selvedge.Features.Domain.draft_description draft));
 ("status", JString (stage_name (Selvedge.Features.Domain.draft_stage draft))); ("priority", JString (priority_name (Selvedge.Features.Domain.draft_priority draft)));
 ("assignee", JString (owner_name (Selvedge.Features.Domain.draft_owner draft))); ("project", JString (match Selvedge.Features.Domain.draft_project draft with Some id=>Selvedge.Features.Domain.decimal_text id | None=>"" end));
 ("labels", JArray (map JString (Selvedge.Features.Domain.draft_labels draft)));
 ("attachments", JArray (map attachment_json (Selvedge.Features.Domain.draft_attachments draft)));
 ("task_id", optional_number (Selvedge.Features.Domain.card_task value)); ("archived", JBool (Selvedge.Features.Domain.card_archived value));
 ("pinned", JBool (Selvedge.Features.Domain.card_pinned value)); ("created_at", JString (Selvedge.Features.Domain.decimal_text (Selvedge.Features.Domain.card_created value)));
 ("updated_at", JString (Selvedge.Features.Domain.decimal_text (Selvedge.Features.Domain.card_updated value))); ("start_error", JString (Selvedge.Features.Domain.card_start_error value))].
Definition agent_json (id : N) (value : Selvedge.Features.Domain.board_agent) := JObject [
 ("id", number id); ("agent_id", number id); ("revision", number (Selvedge.Features.Domain.agent_revision value));
 ("name", JString (Selvedge.Features.Domain.agent_name value)); ("profile", JString (Selvedge.Features.Domain.agent_profile value));
 ("reasoning", JString (Selvedge.Features.Domain.agent_reasoning value)); ("instructions", JString (Selvedge.Features.Domain.agent_instructions value));
 ("settings", Selvedge.Features.Domain.agent_settings value); ("concurrency", number (Selvedge.Features.Domain.agent_concurrency value))].
Definition present_values {A : Type} (f : N -> A -> json) (values : list (option A)) :=
 fold_right (fun value rest => match value with Some value => value :: rest | None => rest end) []
 (indexed (fun id value => option_map (f id) value) 0 values).
Definition agents_json (value:Selvedge.Features.Domain.board) := fold_right (fun id rest=>match registry_at id (Selvedge.Features.Domain.board_agents value) with
 | Some (Some agent)=>agent_json id agent::rest | _=>rest end) [] (Selvedge.Features.Domain.board_agent_order value).
Definition board_json (value : Selvedge.Features.Domain.board) := JObject [
 ("cards", JArray (present_values card_json (Selvedge.Features.Domain.board_cards value)));
 ("agents", JArray (agents_json value));
 ("order", JArray (map number (Selvedge.Features.Domain.board_order value)));
 ("automatic", JBool (Selvedge.Features.Domain.board_automatic value)); ("draft_profile", JString (Selvedge.Features.Domain.board_draft_profile value))].
Definition rights_json (value : Selvedge.Features.Domain.rights) := JObject [
 ("read", JBool (Selvedge.Features.Domain.may_read value)); ("control", JBool (Selvedge.Features.Domain.may_control value));
 ("configure", JBool (Selvedge.Features.Domain.may_configure value)); ("approve", JBool (Selvedge.Features.Domain.may_approve value))].
Definition grant_json (value : Selvedge.Features.Domain.remote_grant) := JObject [
 ("controller_id", JString (Selvedge.Features.Domain.grant_controller value)); ("grant_epoch", number (Selvedge.Features.Domain.grant_epoch value));
 ("permissions", rights_json (Selvedge.Features.Domain.grant_rights value))].
Definition remote_json (value : Selvedge.Features.Domain.remote) := JObject [
 ("enabled", JBool (Selvedge.Features.Domain.remote_enabled value)); ("controllers", JArray (map grant_json (Selvedge.Features.Domain.remote_grants value)))].
Definition worktree_json (value : Selvedge.Features.Domain.worktree) := JObject [
 ("task_id", number (Selvedge.Features.Domain.worktree_task value)); ("source_root", JString (Selvedge.Features.Domain.worktree_source value));
 ("backend", JString (WorkspaceBackend.name (Selvedge.Features.Domain.worktree_backend value)));
 ("root", optional_string (Selvedge.Features.Domain.worktree_root value)); ("target_primary", JString (Selvedge.Features.Domain.worktree_target_primary value)); ("message", JString (Selvedge.Features.Domain.worktree_message value));
 ("status", JString (match Selvedge.Features.Domain.worktree_state value with
 | Selvedge.Features.Domain.Creating => "creating" | Selvedge.Features.Domain.CreatingArchived => "creating_archived" | Selvedge.Features.Domain.Ready => "ready" | Selvedge.Features.Domain.CreationFailed => "create_failed"
 | Selvedge.Features.Domain.Archiving => "archiving" | Selvedge.Features.Domain.ArchiveFailed => "archive_failed" | Selvedge.Features.Domain.WorktreeArchived => "archived" end))].
Fixpoint graph_message_json (value : Selvedge.Features.Domain.graph_message) : json :=
 match value with
 | Selvedge.Features.Domain.GraphOutput => JObject [("kind", JString "output")]
 | Selvedge.Features.Domain.GraphLiteral text => JObject [("kind", JString "literal"); ("value", JString text)]
 | Selvedge.Features.Domain.GraphConcat parts => JObject [("kind", JString "concat"); ("parts", JArray (map graph_message_json parts))] end.
Definition graph_action_json (value : Selvedge.Features.Domain.graph_action) := JObject [
 ("target", JString (Selvedge.Features.Domain.action_target value)); ("message", graph_message_json (Selvedge.Features.Domain.action_message value))].
Definition graph_rule_json (value : Selvedge.Features.Domain.graph_rule) := JObject [
 ("key", JString (Selvedge.Features.Domain.rule_key value)); ("source", JString (Selvedge.Features.Domain.rule_source value));
 ("actions", JArray (map graph_action_json (Selvedge.Features.Domain.rule_actions value)))].
Definition graph_json (id : N) (value : Selvedge.Features.Domain.task_graph) := JObject [
 ("graph_id", number id); ("name", JString (Selvedge.Features.Domain.graph_name value));
 ("nodes", JArray (map (fun node => JObject [("key", JString (Selvedge.Features.Domain.node_key node)); ("task_id", number (Selvedge.Features.Domain.node_task node))]) (Selvedge.Features.Domain.graph_nodes value)));
 ("rules", JArray (map graph_rule_json (Selvedge.Features.Domain.graph_rules value)));
 ("receipts", JArray (map (fun receipt => JObject [
 ("source", number (Selvedge.Features.Domain.receipt_source receipt)); ("rule", JString (Selvedge.Features.Domain.receipt_rule receipt));
 ("target", number (Selvedge.Features.Domain.receipt_target receipt)); ("reply", Selvedge.Features.Domain.receipt_reply receipt)]) (Selvedge.Features.Domain.graph_receipts value)))].

Definition title_settings_json (value : Selvedge.Features.Domain.title_settings) := JObject [
 ("revision", number (Selvedge.Features.Domain.title_revision value));
 ("task_prompt", JString (Selvedge.Features.Domain.title_task_prompt value));
 ("agent_prompt", JString (Selvedge.Features.Domain.title_agent_prompt value))].

Definition card_json_in_world (value:world) (id:N) (card:Selvedge.Features.Domain.card) := match card_json id card with JObject fields=>JObject (fields++[
 ("activity",JString (BoardFacts.activity card value));("capabilities",JObject [
 ("edit",JBool (BoardFacts.mutable card value && BoardFacts.unlinked card));("metadata",JBool (BoardFacts.mutable card value));("regenerate",JBool (BoardFacts.mutable card value));("drag",JBool (BoardFacts.mutable card value));
 ("run",JBool (BoardFacts.runnable card value));("archive",JBool (negb (Selvedge.Features.Domain.card_archived card || BoardFacts.pending card)));("restore",JBool (Selvedge.Features.Domain.card_archived card));("delete",JBool (negb (BoardFacts.pending card || BoardFacts.busy card value)))])]) | other=>other end.
Definition board_json_in_world (value:world) := let board:=world_features value in let b:=Selvedge.Features.Domain.feature_board board in
 match board_json b with JObject fields=>JObject (Json.set_field "cards" (JArray (present_values (card_json_in_world value) (Selvedge.Features.Domain.board_cards b))) fields) | other=>other end.

Fixpoint first_request (messages:list message) :string := match messages with
 | []=>"" | UserMessage contents::rest=>let text:=(Selvedge.Kernel.Domain.content_text contents) in if Utf8.nonblank text then text else first_request rest
 | _::rest=>first_request rest end.
Definition task_title (id:N) (task:task) (features:Selvedge.Features.Domain.state) :=
 let request:=Titles.preview (first_request (task_history task)) in
 let fallback:=if String.eqb request "" then String.append "Task #" (Selvedge.Features.Domain.decimal_text id) else request in
 match find (fun item=>N.eqb id (Selvedge.Features.Domain.title_task item)) (Selvedge.Features.Domain.feature_titles features) with
 | Some item=>match Selvedge.Features.Domain.title_value item with Selvedge.Features.Domain.Named title=>title | _=>fallback end
 | None=>fallback end.
