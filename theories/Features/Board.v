From Stdlib Require Import String Ascii List Bool NArith.
From Selvedge.Foundation Require Import Json Utf8 Schema.
From Selvedge.Kernel Require Import Numbers Domain State Codec Tasks Workspace CommandExecution.
From Selvedge.Generated Require Import Commands.
From Selvedge.Features Require Import Domain State Observation Titles TitleRuntime Worktree BoardFacts.
From Selvedge.Features Require Import BoardParameters.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Definition registry (value:world) := Selvedge.Features.Domain.feature_board (world_features value).
Definition store (board:Selvedge.Features.Domain.board) (value:world) := Selvedge.Kernel.State.with_features (Selvedge.Features.State.with_board board (world_features value)) value.
Definition lookup (id:N) (value:world) := match registry_at id (Selvedge.Features.Domain.board_cards (registry value)) with Some card=>card | None=>None end.
Definition lookup_agent (id:N) (value:world) := match registry_at id (Selvedge.Features.Domain.board_agents (registry value)) with Some agent=>agent | None=>None end.
Definition put (id:N) (card:Selvedge.Features.Domain.card) (value:world) := let b:=registry value in
 store (Selvedge.Features.Domain.Board (if N.eqb id (N.of_nat (List.length (Selvedge.Features.Domain.board_cards b))) then Selvedge.Features.Domain.board_cards b++[Some card] else replace id (Some card) (Selvedge.Features.Domain.board_cards b))
 (if existsb (N.eqb id) (Selvedge.Features.Domain.board_order b) then Selvedge.Features.Domain.board_order b else Selvedge.Features.Domain.board_order b++[id]) (Selvedge.Features.Domain.board_agents b) (Selvedge.Features.Domain.board_agent_order b) (Selvedge.Features.Domain.board_automatic b) (Selvedge.Features.Domain.board_draft_profile b)) value.
Definition result (id:N) (card:Selvedge.Features.Domain.card) := JObject [("card_id",number id);("revision",number (Selvedge.Features.Domain.card_revision card))].
Definition save (id:N) (card:Selvedge.Features.Domain.card) (value:world) := Selvedge.Kernel.State.accept (result id card) (put id card value) [].
Definition clock (text:option string) :option N := match text with None=>Some 0 | Some text=>match text_id text with Some now=>if N.leb now 4294967295 then Some now else None | None=>None end end.
Record patch := Patch { patch_title:option string;patch_description:option string;patch_stage:option string;patch_priority:option string;
 patch_owner:option string;patch_project:option string;patch_labels:option (list string);patch_attachments:option (list json) }.
Definition retained {A:Type} (input:option A) (old:A) := match input with Some value=>value | None=>old end.
Definition parse_patch (input:patch) (old:Selvedge.Features.Domain.card_draft) :option Selvedge.Features.Domain.card_draft :=
 match (match patch_stage input with Some value=>stage value | None=>Some (Selvedge.Features.Domain.draft_stage old) end),
 (match patch_priority input with Some value=>priority value | None=>Some (Selvedge.Features.Domain.draft_priority old) end),
 (match patch_owner input with Some value=>owner value | None=>Some (Selvedge.Features.Domain.draft_owner old) end),
 (match patch_project input with Some value=>optional_project value | None=>Some (Selvedge.Features.Domain.draft_project old) end),
 (match patch_attachments input with Some files=>traverse attachment files | None=>Some (Selvedge.Features.Domain.draft_attachments old) end) with
 | Some stage,Some priority,Some owner,Some project,Some files=>Some (Selvedge.Features.Domain.CardDraft
 (retained (patch_title input) (Selvedge.Features.Domain.draft_title old)) (retained (patch_description input) (Selvedge.Features.Domain.draft_description old)) stage priority owner project
 (retained (patch_labels input) (Selvedge.Features.Domain.draft_labels old)) files) | _,_,_,_,_=>None end.
Definition valid_draft (draft:Selvedge.Features.Domain.card_draft) (value:world) :=
 nonempty (Selvedge.Features.Domain.draft_title draft) && limited (Selvedge.Features.Domain.draft_title draft) 2000 && limited (Selvedge.Features.Domain.draft_description draft) 400000 &&
 Nat.leb (List.length (Selvedge.Features.Domain.draft_labels draft)) 32 && forallb (fun label=>nonempty label && limited label 128) (Selvedge.Features.Domain.draft_labels draft) &&
 Nat.leb (List.length (Selvedge.Features.Domain.draft_attachments draft)) 4 &&
 (match Selvedge.Features.Domain.draft_owner draft with Selvedge.Features.Domain.AgentOwner id=>match lookup_agent id value with Some _=>true | None=>false end | _=>true end) &&
 (match Selvedge.Features.Domain.draft_project draft with None=>true | Some id=>match registry_at id (world_projects value) with Some project=>negb (project_deleted project) | None=>false end end).
Definition empty_draft := Selvedge.Features.Domain.CardDraft "" "" Selvedge.Features.Domain.Todo Selvedge.Features.Domain.NoPriority Selvedge.Features.Domain.Unassigned None [] [].
Definition linked_task := BoardFacts.linked_task.
Definition busy_task := BoardFacts.busy_task.
Definition busy := BoardFacts.busy.
Definition pending := BoardFacts.pending.
Definition mutable := BoardFacts.mutable.
Definition unlinked := BoardFacts.unlinked.
Definition revised (draft:Selvedge.Features.Domain.card_draft) (now:N) (card:Selvedge.Features.Domain.card) := Selvedge.Features.Domain.Card (N.succ (Selvedge.Features.Domain.card_revision card)) draft (Selvedge.Features.Domain.card_task card) (Selvedge.Features.Domain.card_archived card)
 (Selvedge.Features.Domain.card_created card) now (Selvedge.Features.Domain.card_enrichment card) (Selvedge.Features.Domain.card_start_error card) (Selvedge.Features.Domain.card_pinned card).
Definition with_stage (stage:Selvedge.Features.Domain.board_stage) (draft:Selvedge.Features.Domain.card_draft) := Selvedge.Features.Domain.CardDraft (Selvedge.Features.Domain.draft_title draft) (Selvedge.Features.Domain.draft_description draft) stage (Selvedge.Features.Domain.draft_priority draft)
 (Selvedge.Features.Domain.draft_owner draft) (Selvedge.Features.Domain.draft_project draft) (Selvedge.Features.Domain.draft_labels draft) (Selvedge.Features.Domain.draft_attachments draft).
Definition owner_agent := BoardFacts.owner_agent.
Definition active_for := BoardFacts.active_for.
Definition runnable := BoardFacts.runnable.
Definition latest_failure := BoardFacts.latest_failure.
Definition activity := BoardFacts.activity.
Definition card_json (id:N) (card:Selvedge.Features.Domain.card) (value:world) := Observation.card_json_in_world value id card.
Definition visible_cards (value:world) := fold_right (fun id rest=>match lookup id value with Some card=>card_json id card value::rest | None=>rest end) [] (Selvedge.Features.Domain.board_order (registry value)).
Definition query (command:Selvedge.Generated.Commands.command) (_caller:option N) (value:world) :option json := match command with
 | Selvedge.Generated.Commands.Cmd_list_cards _=>Some (Selvedge.Kernel.State.success (JObject [("cards",JArray (visible_cards value));("automatic",JBool (Selvedge.Features.Domain.board_automatic (registry value)));("draft_profile",JString (Selvedge.Features.Domain.board_draft_profile (registry value)))]))
 | Selvedge.Generated.Commands.Cmd_read_card p=>Some (match lookup (Selvedge.Generated.Commands.read_card_card_id p) value with Some card=>Selvedge.Kernel.State.success (card_json (Selvedge.Generated.Commands.read_card_card_id p) card value) | None=>Selvedge.Kernel.State.failure "card_not_found" "The board card does not exist" end)
 | Selvedge.Generated.Commands.Cmd_list_board_agents _=>Some (Selvedge.Kernel.State.success (JObject [("agents",JArray (Observation.agents_json_in_world value))])) | _=>None end.
Definition with_card (id revision:N) (value:world) (run:Selvedge.Features.Domain.card->decision) := match lookup id value with
 | None=>Selvedge.Kernel.State.reject "card_not_found" "The board card does not exist" value
 | Some card=>if N.eqb revision (Selvedge.Features.Domain.card_revision card) then run card else Selvedge.Kernel.State.reject "card_conflict" "The card changed in another view or during execution. Refresh its current values before applying this edit." value end.
Definition at_clock (supplied:option string) (value:world) (run:N->decision) := match clock supplied with Some now=>run now | None=>Selvedge.Kernel.State.reject "invalid_clock" "observed_at must be a canonical U32 decimal timestamp" value end.
Definition request_text (id:N) (card:Selvedge.Features.Domain.card) (profile_name:string) (retitle:bool) (value:world) :=
 let name:=if String.eqb profile_name "" then Selvedge.Features.Domain.board_draft_profile (registry value) else profile_name in
 match Tasks.find_profile name (environment_profiles (world_environment value)) with
 | None=>Selvedge.Kernel.State.reject "draft_profile_required" "Choose a configured ordinary drafting endpoint" value
 | Some profile=>if negb (TitleRuntime.ordinary profile) then Selvedge.Kernel.State.reject "draft_profile_invalid" "Title/description assistance requires an ordinary tool-free endpoint" value else
 let '(ticket,allocated):=Selvedge.Kernel.State.allocate_ticket value in
 let pending:=Selvedge.Features.Domain.Card (Selvedge.Features.Domain.card_revision card) (Selvedge.Features.Domain.card_contents card) (Selvedge.Features.Domain.card_task card) (Selvedge.Features.Domain.card_archived card) (Selvedge.Features.Domain.card_created card) (Selvedge.Features.Domain.card_updated card) (Selvedge.Features.Domain.Enriching ticket (Selvedge.Features.Domain.card_revision card) retitle) (Selvedge.Features.Domain.card_start_error card) (Selvedge.Features.Domain.card_pinned card) in
 Selvedge.Kernel.State.accept (result id card) (put id pending allocated) [Selvedge.Kernel.State.SuggestCard id ticket (Selvedge.Features.Domain.card_revision card) profile (Titles.board_prompt (Selvedge.Features.Domain.title_task_prompt (Selvedge.Features.Domain.feature_title_settings (world_features value))) (Selvedge.Features.Domain.draft_title (Selvedge.Features.Domain.card_contents card)) (Selvedge.Features.Domain.draft_description (Selvedge.Features.Domain.card_contents card)) retitle) (Selvedge.Features.Domain.card_contents card) retitle] end.
Definition create_card (input:patch) (supplied:option string) (assisted:bool) (profile:string) (value:world) := at_clock supplied value (fun now=>
 match parse_patch input empty_draft with None=>Selvedge.Kernel.State.reject "invalid_card" "Invalid board card fields" value | Some draft=>
 let title:=if assisted && negb (Utf8.nonblank (Selvedge.Features.Domain.draft_title draft)) then match Utf8.chunks (Selvedge.Features.Domain.draft_description draft) with Some chunks=>Utf8.render_chunks (firstn 120 (Titles.trim_both Utf8.whitespace chunks)) | None=>"" end else Selvedge.Features.Domain.draft_title draft in
 let draft:=Selvedge.Features.Domain.CardDraft title (Selvedge.Features.Domain.draft_description draft) (Selvedge.Features.Domain.draft_stage draft) (Selvedge.Features.Domain.draft_priority draft) (Selvedge.Features.Domain.draft_owner draft) (Selvedge.Features.Domain.draft_project draft) (Selvedge.Features.Domain.draft_labels draft) (Selvedge.Features.Domain.draft_attachments draft) in
 let count:=List.length (filter (fun card=>match card with Some _=>true | None=>false end) (Selvedge.Features.Domain.board_cards (registry value))) in
 let id:=N.of_nat (List.length (Selvedge.Features.Domain.board_cards (registry value))) in
 if valid_draft draft value && Nat.ltb count 512 && N.ltb id 4294967295 then
 let card:=Selvedge.Features.Domain.Card 0 draft None false now now Selvedge.Features.Domain.NoEnrichment "" false in
 if assisted then request_text id card profile false value else save id card value
 else Selvedge.Kernel.State.reject "invalid_card" "Provide a nonempty title or assisted request, valid project/assignee and bounded text/files. The board holds at most 512 cards." value end).
Definition changes_execution (input:patch) :=
 match patch_title input,patch_description input,patch_owner input,patch_project input,patch_attachments input with None,None,None,None,None=>false | _,_,_,_,_=>true end.
Definition update_card (id revision:N) (supplied:option string) (input:patch) (value:world) := at_clock supplied value (fun now=>with_card id revision value (fun card=>
 match parse_patch input (Selvedge.Features.Domain.card_contents card) with Some draft=>
 if mutable card value && (unlinked card || negb (changes_execution input)) && valid_draft draft value then save id (revised draft now card) value
 else Selvedge.Kernel.State.reject "card_locked" "The card is busy, archived or invalid. Execution inputs cannot be edited after a conversation is linked." value
 | None=>Selvedge.Kernel.State.reject "invalid_card" "Invalid board card fields" value end)).
Fixpoint insert_before (id:N) (before:option N) (order:list N) := match order with []=>[id] | item::rest=>
 if match before with Some target=>N.eqb target item | None=>false end then id::order else item::insert_before id before rest end.
Definition move_card (id revision:N) (supplied:option string) (status:option string) (before:option string) (value:world) := at_clock supplied value (fun now=>with_card id revision value (fun card=>
 let destination:=match status with Some status=>stage status | None=>None end in
 let target:=match before with Some text=>optional_project text | None=>Some None end in
 match destination,target with Some destination,Some target=>
 let valid_target:=match target with None=>true | Some target=>negb (N.eqb target id) && match lookup target value with Some other=>negb (Selvedge.Features.Domain.card_archived other) && String.eqb (Selvedge.Features.Domain.stage_name destination) (Selvedge.Features.Domain.stage_name (Selvedge.Features.Domain.draft_stage (Selvedge.Features.Domain.card_contents other))) && Bool.eqb (Selvedge.Features.Domain.card_pinned card) (Selvedge.Features.Domain.card_pinned other) | None=>false end end in
 if mutable card value && valid_target then let updated:=revised (with_stage destination (Selvedge.Features.Domain.card_contents card)) now card in
 let changed:=put id updated value in let b:=registry changed in
 Selvedge.Kernel.State.accept (result id updated) (store (Selvedge.Features.Domain.Board (Selvedge.Features.Domain.board_cards b) (insert_before id target (filter (fun other=>negb (N.eqb id other)) (Selvedge.Features.Domain.board_order b))) (Selvedge.Features.Domain.board_agents b) (Selvedge.Features.Domain.board_agent_order b) (Selvedge.Features.Domain.board_automatic b) (Selvedge.Features.Domain.board_draft_profile b)) changed) []
 else Selvedge.Kernel.State.reject "invalid_card_move" "The card must be editable and the insertion target must remain in the destination column and pin group" value
 | _,_=>Selvedge.Kernel.State.reject "invalid_card_move" "A destination status and valid insertion target are required" value end)).
Definition pin (id revision:N) (supplied:option string) (pinned:option bool) (value:world) := at_clock supplied value (fun now=>with_card id revision value (fun card=>
 match pinned with Some pinned=>if mutable card value then let updated:=revised (Selvedge.Features.Domain.card_contents card) now card in
 save id (Selvedge.Features.Domain.Card (Selvedge.Features.Domain.card_revision updated) (Selvedge.Features.Domain.card_contents updated) (Selvedge.Features.Domain.card_task card) (Selvedge.Features.Domain.card_archived card) (Selvedge.Features.Domain.card_created card) now (Selvedge.Features.Domain.card_enrichment card) (Selvedge.Features.Domain.card_start_error card) pinned) value
 else Selvedge.Kernel.State.reject "card_locked" "A running, archived or generating card cannot be pinned or unpinned" value | None=>Selvedge.Kernel.State.reject "invalid_card_command" "pinned is required" value end)).
Definition link (id revision:N) (supplied:option string) (target:option N) (value:world) := at_clock supplied value (fun now=>with_card id revision value (fun card=>
 match target with Some target=>match Selvedge.Kernel.State.find_task target value with None=>Selvedge.Kernel.State.reject "task_not_found" "The conversation to link does not exist" value | Some _=>
 let used:=existsb (fun candidate=>match candidate with Some other=>match Selvedge.Features.Domain.card_task other with Some linked=>N.eqb linked target | None=>false end | None=>false end) (Selvedge.Features.Domain.board_cards (registry value)) in
 if mutable card value && unlinked card && negb used then let updated:=revised (Selvedge.Features.Domain.card_contents card) now card in
 save id (Selvedge.Features.Domain.Card (Selvedge.Features.Domain.card_revision updated) (with_stage Selvedge.Features.Domain.InProgress (Selvedge.Features.Domain.card_contents card)) (Some target) false (Selvedge.Features.Domain.card_created card) now (Selvedge.Features.Domain.card_enrichment card) "" (Selvedge.Features.Domain.card_pinned card)) value
 else Selvedge.Kernel.State.reject "conversation_already_linked" "A card can link one conversation, and a conversation can belong to only one card" value end
 | None=>Selvedge.Kernel.State.reject "invalid_card_command" "task_id is required" value end)).
Definition archive_card (id revision:N) (supplied:option string) (archived:bool) (value:world) := at_clock supplied value (fun now=>with_card id revision value (fun card=>
 if pending card then Selvedge.Kernel.State.reject "card_locked" "Wait for pending drafting before archiving or restoring the card" value else
 let updated:=Selvedge.Features.Domain.Card (N.succ (Selvedge.Features.Domain.card_revision card)) (Selvedge.Features.Domain.card_contents card) (Selvedge.Features.Domain.card_task card) archived (Selvedge.Features.Domain.card_created card) now Selvedge.Features.Domain.NoEnrichment (Selvedge.Features.Domain.card_start_error card) (Selvedge.Features.Domain.card_pinned card) in
 let saved:=save id updated value in
 if archived && busy card value then match Selvedge.Features.Domain.card_task card with Some target=>
 let stopped:=Tasks.control_command target Tasks.Interrupt (decision_world saved) in
 Selvedge.Kernel.State.Decision (decision_world stopped) (decision_reply saved) (decision_effects stopped) | None=>saved end else saved)).
Definition delete_card (id revision:N) (value:world) := with_card id revision value (fun card=>if pending card || busy card value then Selvedge.Kernel.State.reject "card_locked" "Stop the running conversation and wait for pending drafting before deleting this card" value else
 let b:=registry value in Selvedge.Kernel.State.accept (JObject [("card_id",number id)]) (store (Selvedge.Features.Domain.Board (replace id None (Selvedge.Features.Domain.board_cards b)) (filter (fun other=>negb (N.eqb id other)) (Selvedge.Features.Domain.board_order b)) (Selvedge.Features.Domain.board_agents b) (Selvedge.Features.Domain.board_agent_order b) (Selvedge.Features.Domain.board_automatic b) (Selvedge.Features.Domain.board_draft_profile b)) value) []).
Fixpoint attachment_prompt (files:list Selvedge.Features.Domain.attachment) := match files with []=>"" | file::rest=>String.append "
- " (String.append (Selvedge.Features.Domain.attachment_name file) (String.append ": " (String.append (Selvedge.Features.Domain.attachment_path file) (attachment_prompt rest)))) end.
Definition task_contents (id:N) (draft:Selvedge.Features.Domain.card_draft) (instructions:string) :=
 TextPart (String.append instructions (String.append "

Board card SV-" (String.append (Selvedge.Features.Domain.decimal_text (N.succ id)) (String.append ": "
 (String.append (Selvedge.Features.Domain.draft_title draft) (String.append "

" (String.append (Selvedge.Features.Domain.draft_description draft) (String.append "

Attached files (read only when needed):" (attachment_prompt (Selvedge.Features.Domain.draft_attachments draft)))))))))) ::
 fold_right (fun file rest=>if String.prefix "image/" (Selvedge.Features.Domain.attachment_mime file) then ImagePart (ImageAsset (Selvedge.Features.Domain.attachment_id file) (Selvedge.Features.Domain.attachment_mime file) (Selvedge.Features.Domain.attachment_bytes file) ImageAuto)::rest else rest) [] (Selvedge.Features.Domain.draft_attachments draft).
Definition launch_settings (agent:Selvedge.Features.Domain.board_agent) (draft:Selvedge.Features.Domain.card_draft) :=
 let fields:=match Selvedge.Features.Domain.agent_settings agent with JObject fields=>fields|_=>[] end in
 let fields:=remove_field "project_id" fields in
 JObject (match Selvedge.Features.Domain.draft_project draft with Some project=>Json.set_field "project_id" (number project) fields | None=>fields end).
Definition run (id revision:N) (supplied:option string) (caller:option N) (value:world) := at_clock supplied value (fun now=>with_card id revision value (fun card=>
 if negb (runnable card value) then Selvedge.Kernel.State.reject "card_not_runnable" "The card already has a conversation, is locked, has no agent, or the assigned agent has reached its concurrency limit" value else
 match owner_agent (Selvedge.Features.Domain.draft_owner (Selvedge.Features.Domain.card_contents card)) value with None=>Selvedge.Kernel.State.reject "agent_required" "Assign a configured endpoint or board agent before starting this card" value | Some agent=>
 let settings:=launch_settings agent (Selvedge.Features.Domain.card_contents card) in
 let created:=Worktree.create_selected (Selvedge.Features.Domain.agent_profile agent) (Some (Selvedge.Features.Domain.agent_reasoning agent)) (task_contents id (Selvedge.Features.Domain.card_contents card) (Selvedge.Features.Domain.agent_instructions agent)) (Some settings) false caller None value in
 if bool_default "ok" (decision_reply created) false then
 let updated:=Selvedge.Features.Domain.Card (N.succ revision) (with_stage Selvedge.Features.Domain.InProgress (Selvedge.Features.Domain.card_contents card)) (Some (Selvedge.Kernel.State.next_task value)) false (Selvedge.Features.Domain.card_created card) now Selvedge.Features.Domain.NoEnrichment "" (Selvedge.Features.Domain.card_pinned card) in
 Selvedge.Kernel.State.Decision (put id updated (decision_world created)) (Selvedge.Kernel.State.success (JObject [("card_id",number id);("task_id",number (Selvedge.Kernel.State.next_task value));("revision",number (N.succ revision))])) (decision_effects created) else created end)).
Definition agent_name_valid (name:string) := nonempty name && limited name 160.
Definition agent_profile_valid (profile:string) := nonempty profile && limited profile 1024.
Definition agent_reasoning_valid (reasoning:string) := nonempty reasoning && limited reasoning 64.
Definition agent_instructions_valid (instructions:string) := limited instructions 100000.
Definition agent_concurrency_valid (capacity:N) := N.leb 1 capacity && N.leb capacity 64.
Definition valid_agent (agent:Selvedge.Features.Domain.board_agent) (value:world) :=
 agent_name_valid (Selvedge.Features.Domain.agent_name agent) &&
 agent_profile_valid (Selvedge.Features.Domain.agent_profile agent) &&
 agent_reasoning_valid (Selvedge.Features.Domain.agent_reasoning agent) &&
 agent_instructions_valid (Selvedge.Features.Domain.agent_instructions agent) &&
 agent_concurrency_valid (Selvedge.Features.Domain.agent_concurrency agent) &&
 match Tasks.find_profile (Selvedge.Features.Domain.agent_profile agent) (environment_profiles (world_environment value)) with None=>false | Some profile=>
 match Tasks.selected_reasoning (Some (Selvedge.Features.Domain.agent_reasoning agent)) profile,Tasks.resolve_settings profile (Some (Selvedge.Features.Domain.agent_settings agent)) (Tasks.creation_defaults (world_environment value)) value with Some _,Some _=>true | _,_=>false end end.
Definition save_agent (supplied:string) (expected:N) (name profile reasoning instructions:string) (settings:option json) (capacity:N) (value:world) :=
 let id:=if String.eqb supplied "" then Some (N.of_nat (List.length (Selvedge.Features.Domain.board_agents (registry value)))) else text_id supplied in
 match id with None=>Selvedge.Kernel.State.reject "invalid_agent" "Invalid board agent identifier" value | Some id=>
 let creating:=String.eqb supplied "" in
 let revision:=if creating then 0 else N.succ expected in
 let agent:=Selvedge.Features.Domain.BoardAgent revision name profile reasoning instructions (retained settings (JObject [])) capacity in
 let current:=lookup_agent id value in
 let valid_revision:=if creating then Nat.ltb (List.length (filter (fun item=>match item with Some _=>true | None=>false end) (Selvedge.Features.Domain.board_agents (registry value)))) 64 && N.ltb id 4294967295 else match current with Some previous=>N.eqb expected (Selvedge.Features.Domain.agent_revision previous) | None=>false end in
 if negb (valid_agent agent value) then Selvedge.Kernel.State.reject "invalid_agent" "Provide a valid name, endpoint, reasoning, settings and concurrency from 1 to 64" value
 else if negb valid_revision then Selvedge.Kernel.State.reject "agent_conflict" "This board agent changed or the board has reached its agent limit" value
 else let b:=registry value in
 Selvedge.Kernel.State.accept (JObject [("agent_id",number id);("revision",number revision)]) (store (Selvedge.Features.Domain.Board (Selvedge.Features.Domain.board_cards b) (Selvedge.Features.Domain.board_order b)
 (if creating then Selvedge.Features.Domain.board_agents b++[Some agent] else replace id (Some agent) (Selvedge.Features.Domain.board_agents b)) (id::filter (fun other=>negb (N.eqb id other)) (Selvedge.Features.Domain.board_agent_order b)) (Selvedge.Features.Domain.board_automatic b) (Selvedge.Features.Domain.board_draft_profile b)) value) [] end.
Definition delete_agent (id expected:N) (value:world) := match lookup_agent id value with None=>Selvedge.Kernel.State.reject "agent_not_found" "The board agent no longer exists" value | Some agent=>
 let used:=existsb (fun item=>match item with Some card=>match Selvedge.Features.Domain.draft_owner (Selvedge.Features.Domain.card_contents card) with Selvedge.Features.Domain.AgentOwner owner=>N.eqb id owner | _=>false end | None=>false end) (Selvedge.Features.Domain.board_cards (registry value)) in
 if N.eqb expected (Selvedge.Features.Domain.agent_revision agent) && negb used then let b:=registry value in
 Selvedge.Kernel.State.accept (JObject [("agent_id",number id)]) (store (Selvedge.Features.Domain.Board (Selvedge.Features.Domain.board_cards b) (Selvedge.Features.Domain.board_order b) (replace id None (Selvedge.Features.Domain.board_agents b)) (filter (fun other=>negb (N.eqb id other)) (Selvedge.Features.Domain.board_agent_order b)) (Selvedge.Features.Domain.board_automatic b) (Selvedge.Features.Domain.board_draft_profile b)) value) []
 else Selvedge.Kernel.State.reject "agent_in_use" "The board agent changed or is still assigned to a card" value end.
Definition settings (automatic:bool) (profile:string) (value:world) :=
 let valid:=String.eqb profile "" || match Tasks.find_profile profile (environment_profiles (world_environment value)) with Some chosen=>TitleRuntime.ordinary chosen | None=>false end in
 if valid then let b:=registry value in Selvedge.Kernel.State.accept (JObject [("automatic",JBool automatic);("draft_profile",JString profile)])
 (store (Selvedge.Features.Domain.Board (Selvedge.Features.Domain.board_cards b) (Selvedge.Features.Domain.board_order b) (Selvedge.Features.Domain.board_agents b) (Selvedge.Features.Domain.board_agent_order b) automatic profile) value) []
 else Selvedge.Kernel.State.reject "draft_profile_invalid" "Choose a configured ordinary drafting endpoint" value.
Definition regenerate (id revision:N) (supplied:option string) (profile:string) (value:world) := at_clock supplied value (fun now=>with_card id revision value (fun card=>
 if mutable card value then request_text id (revised (Selvedge.Features.Domain.card_contents card) now card) profile true value else Selvedge.Kernel.State.reject "card_locked" "A running, archived or already-generating card cannot start another title request" value)).
Definition command (command:Selvedge.Generated.Commands.command) (caller:option N) (value:world) :option decision := match command with
 | Selvedge.Generated.Commands.Cmd_create_card p=>Some (create_card (Patch (Selvedge.Generated.Commands.create_card_title p) (Selvedge.Generated.Commands.create_card_description p) (Selvedge.Generated.Commands.create_card_status p) (Selvedge.Generated.Commands.create_card_priority p) (Selvedge.Generated.Commands.create_card_assignee p) (Selvedge.Generated.Commands.create_card_project p) (Selvedge.Generated.Commands.create_card_labels p) (Selvedge.Generated.Commands.create_card_attachments p)) (Selvedge.Generated.Commands.create_card_observed_at p) (retained (Selvedge.Generated.Commands.create_card_assisted p) false) (retained (Selvedge.Generated.Commands.create_card_draft_profile p) "") value)
 | Selvedge.Generated.Commands.Cmd_update_card p=>Some (update_card (Selvedge.Generated.Commands.update_card_card_id p) (Selvedge.Generated.Commands.update_card_revision p) (Selvedge.Generated.Commands.update_card_observed_at p) (Patch (Selvedge.Generated.Commands.update_card_title p) (Selvedge.Generated.Commands.update_card_description p) (Selvedge.Generated.Commands.update_card_status p) (Selvedge.Generated.Commands.update_card_priority p) (Selvedge.Generated.Commands.update_card_assignee p) (Selvedge.Generated.Commands.update_card_project p) (Selvedge.Generated.Commands.update_card_labels p) (Selvedge.Generated.Commands.update_card_attachments p)) value)
 | Selvedge.Generated.Commands.Cmd_move_card p=>Some (move_card (Selvedge.Generated.Commands.move_card_card_id p) (Selvedge.Generated.Commands.move_card_revision p) (Selvedge.Generated.Commands.move_card_observed_at p) (Selvedge.Generated.Commands.move_card_status p) (Selvedge.Generated.Commands.move_card_before_card p) value)
 | Selvedge.Generated.Commands.Cmd_archive_card p=>Some (archive_card (Selvedge.Generated.Commands.archive_card_card_id p) (Selvedge.Generated.Commands.archive_card_revision p) (Selvedge.Generated.Commands.archive_card_observed_at p) true value)
 | Selvedge.Generated.Commands.Cmd_restore_card p=>Some (archive_card (Selvedge.Generated.Commands.restore_card_card_id p) (Selvedge.Generated.Commands.restore_card_revision p) (Selvedge.Generated.Commands.restore_card_observed_at p) false value)
 | Selvedge.Generated.Commands.Cmd_run_card p=>Some (run (Selvedge.Generated.Commands.run_card_card_id p) (Selvedge.Generated.Commands.run_card_revision p) (Selvedge.Generated.Commands.run_card_observed_at p) caller value)
 | Selvedge.Generated.Commands.Cmd_link_card p=>Some (link (Selvedge.Generated.Commands.link_card_card_id p) (Selvedge.Generated.Commands.link_card_revision p) (Selvedge.Generated.Commands.link_card_observed_at p) (Selvedge.Generated.Commands.link_card_task_id p) value)
 | Selvedge.Generated.Commands.Cmd_regenerate_card_title p=>Some (regenerate (Selvedge.Generated.Commands.regenerate_card_title_card_id p) (Selvedge.Generated.Commands.regenerate_card_title_revision p) (Selvedge.Generated.Commands.regenerate_card_title_observed_at p) (retained (Selvedge.Generated.Commands.regenerate_card_title_draft_profile p) "") value)
 | Selvedge.Generated.Commands.Cmd_pin_card p=>Some (pin (Selvedge.Generated.Commands.pin_card_card_id p) (Selvedge.Generated.Commands.pin_card_revision p) (Selvedge.Generated.Commands.pin_card_observed_at p) (Selvedge.Generated.Commands.pin_card_pinned p) value)
 | Selvedge.Generated.Commands.Cmd_delete_card p=>Some (delete_card (Selvedge.Generated.Commands.delete_card_card_id p) (Selvedge.Generated.Commands.delete_card_revision p) value)
 | Selvedge.Generated.Commands.Cmd_board_settings p=>Some (settings (Selvedge.Generated.Commands.board_settings_automatic p) (Selvedge.Generated.Commands.board_settings_draft_profile p) value)
 | Selvedge.Generated.Commands.Cmd_save_board_agent p=>Some (save_agent (Selvedge.Generated.Commands.save_board_agent_agent p) (Selvedge.Generated.Commands.save_board_agent_revision p) (Selvedge.Generated.Commands.save_board_agent_name p) (Selvedge.Generated.Commands.save_board_agent_profile p) (Selvedge.Generated.Commands.save_board_agent_reasoning p) (Selvedge.Generated.Commands.save_board_agent_instructions p) (Selvedge.Generated.Commands.save_board_agent_settings p) (Selvedge.Generated.Commands.save_board_agent_concurrency p) value)
 | Selvedge.Generated.Commands.Cmd_delete_board_agent p=>Some (delete_agent (Selvedge.Generated.Commands.delete_board_agent_agent_id p) (Selvedge.Generated.Commands.delete_board_agent_revision p) value)
 | _=>None end.
Definition failure_text (source:string) := match Utf8.chunks source with Some chunks=>Utf8.render_chunks (firstn 1000 chunks) | None=>"Invalid UTF-8 drafting failure" end.
Definition valid_completion_payload (source:json) (ok:bool) :=
 if ok then Worktree.shape [Field "kind" KText;Field "card_id" KNatural;Field "ticket" KNatural;Field "ok" KBool;Field "title" KText;Field "description" KText] source && limited (text_default "title" source "") Titles.response_title_bytes
 else Worktree.shape [Field "kind" KText;Field "card_id" KNatural;Field "ticket" KNatural;Field "ok" KBool;Field "message" KText] source && limited (text_default "message" source "") 4096.
Definition suggestion (ok retitle:bool) (title description message:string) (card:Selvedge.Features.Domain.card) (value:world) :=
 let old:=Selvedge.Features.Domain.card_contents card in
 let draft:=Selvedge.Features.Domain.CardDraft (Titles.normalize title) (if retitle then Selvedge.Features.Domain.draft_description old else description) (Selvedge.Features.Domain.draft_stage old) (Selvedge.Features.Domain.draft_priority old) (Selvedge.Features.Domain.draft_owner old) (Selvedge.Features.Domain.draft_project old) (Selvedge.Features.Domain.draft_labels old) (Selvedge.Features.Domain.draft_attachments old) in
 let valid:=ok && valid_draft draft value in
 Selvedge.Features.Domain.Card (N.succ (Selvedge.Features.Domain.card_revision card)) (if valid then draft else old) (Selvedge.Features.Domain.card_task card) (Selvedge.Features.Domain.card_archived card) (Selvedge.Features.Domain.card_created card) (Selvedge.Features.Domain.card_updated card)
 (if valid then Selvedge.Features.Domain.NoEnrichment else Selvedge.Features.Domain.EnrichmentFailed (failure_text (if ok then "The drafting endpoint returned an empty or oversized title/description. The original request is preserved." else message))) (Selvedge.Features.Domain.card_start_error card) (Selvedge.Features.Domain.card_pinned card).
Definition completion (source:json) (value:world) :option (bool*bool*decision) := match string_field "kind" source with Some "board_text"=>
 match natural_field "card_id" source,natural_field "ticket" source,bool_field "ok" source with Some id,Some ticket,Some ok=>
 let valid:=valid_completion_payload source ok in
 let ignored:=Selvedge.Kernel.State.accept (JObject [("accepted",JBool false)]) value [] in
 if negb valid then None else Some (match lookup id value with Some card=>match Selvedge.Features.Domain.card_enrichment card with
 | Selvedge.Features.Domain.Enriching expected revision retitle=>if N.eqb ticket expected && N.eqb revision (Selvedge.Features.Domain.card_revision card) && negb (Selvedge.Features.Domain.card_archived card) then
 (true,true,Selvedge.Kernel.State.accept (JObject [("accepted",JBool true)]) (put id (suggestion ok retitle (text_default "title" source "") (text_default "description" source "") (text_default "message" source "") card value) value) [])
 else (false,false,ignored)
 | _=>(false,false,ignored) end | None=>(false,false,ignored) end)
 | _,_,_=>None end | _=>None end.
Definition synchronize_card (card:Selvedge.Features.Domain.card) (value:world) :=
 if Selvedge.Features.Domain.card_archived card || pending card then card else match linked_task card value with None=>card | Some task=>
 let previous:=Selvedge.Features.Domain.draft_stage (Selvedge.Features.Domain.card_contents card) in
 let next:=if busy_task task then Selvedge.Features.Domain.InProgress else match previous with Selvedge.Features.Domain.InProgress=>if latest_failure task then Selvedge.Features.Domain.Blocked else Selvedge.Features.Domain.InReview | _=>previous end in
 if String.eqb (Selvedge.Features.Domain.stage_name previous) (Selvedge.Features.Domain.stage_name next) then card else revised (with_stage next (Selvedge.Features.Domain.card_contents card)) (Selvedge.Features.Domain.card_updated card) card end.
Definition synchronize (value:world) := let b:=registry value in
 store (Selvedge.Features.Domain.Board (map (option_map (fun card=>synchronize_card card value)) (Selvedge.Features.Domain.board_cards b)) (Selvedge.Features.Domain.board_order b) (Selvedge.Features.Domain.board_agents b) (Selvedge.Features.Domain.board_agent_order b) (Selvedge.Features.Domain.board_automatic b) (Selvedge.Features.Domain.board_draft_profile b)) value.
Definition ready (card:Selvedge.Features.Domain.card) (value:world) := runnable card value &&
 (match Selvedge.Features.Domain.card_enrichment card with Selvedge.Features.Domain.NoEnrichment=>true | _=>false end) && match Selvedge.Features.Domain.draft_stage (Selvedge.Features.Domain.card_contents card) with Selvedge.Features.Domain.Todo|Selvedge.Features.Domain.InProgress=>true | _=>false end.
Definition priority_rank (p:Selvedge.Features.Domain.priority) :N := match p with Selvedge.Features.Domain.Urgent=>4 | Selvedge.Features.Domain.High=>3 | Selvedge.Features.Domain.Medium=>2 | Selvedge.Features.Domain.Low=>1 | Selvedge.Features.Domain.NoPriority=>0 end.
Definition queued (value:world) := let order:=Selvedge.Features.Domain.board_order (registry value) in
 flat_map (fun pinned=>flat_map (fun priority=>filter (fun id=>match lookup id value with Some card=>
 Bool.eqb pinned (Selvedge.Features.Domain.card_pinned card) && N.eqb priority (priority_rank (Selvedge.Features.Domain.draft_priority (Selvedge.Features.Domain.card_contents card))) && ready card value | None=>false end) order) [4%N;3%N;2%N;1%N;0%N]) [true;false].
Definition next (value:world) := if Selvedge.Features.Domain.board_automatic (registry value) then hd_error (queued value) else None.
Definition start_failed (id:N) (card:Selvedge.Features.Domain.card) (reason:string) (value:world) := put id
 (Selvedge.Features.Domain.Card (N.succ (Selvedge.Features.Domain.card_revision card)) (with_stage Selvedge.Features.Domain.Blocked (Selvedge.Features.Domain.card_contents card)) (Selvedge.Features.Domain.card_task card) (Selvedge.Features.Domain.card_archived card) (Selvedge.Features.Domain.card_created card) (Selvedge.Features.Domain.card_updated card) (Selvedge.Features.Domain.card_enrichment card) (failure_text reason) (Selvedge.Features.Domain.card_pinned card)) value.
Fixpoint pump (fuel:nat) (result:decision) :decision := match fuel with O=>result | S rest=>
 let value:=decision_world result in match next value with None=>result | Some id=>match lookup id value with None=>result | Some card=>
 let advanced:=run id (Selvedge.Features.Domain.card_revision card) (Some (Selvedge.Features.Domain.decimal_text (Selvedge.Features.Domain.card_updated card))) None value in
 let current:=if bool_default "ok" (decision_reply advanced) false then Selvedge.Kernel.State.Decision (decision_world advanced) (decision_reply result) (decision_effects result++decision_effects advanced)
 else Selvedge.Kernel.State.Decision (start_failed id card (String.append (text_default "code" (value_or_null "error" (decision_reply advanced)) "") (String.append ": " (text_default "message" (value_or_null "error" (decision_reply advanced)) ""))) value) (decision_reply result) (decision_effects result) in
 pump rest current end end end.
Definition after_transition (_before:world) (result:decision) := pump 8 (Selvedge.Kernel.State.Decision (synchronize (decision_world result)) (decision_reply result) (decision_effects result)).
Definition finish (result:decision) := let value:=synchronize (decision_world result) in
 let more:=match next value with Some _=>true | None=>false end in
 let continuing:=existsb (fun effect=>match effect with Selvedge.Kernel.State.ContinueScheduling=>true | _=>false end) (decision_effects result) in
 Selvedge.Kernel.State.Decision value (decision_reply result) (if more && negb continuing then decision_effects result++[Selvedge.Kernel.State.ContinueScheduling] else decision_effects result).
Definition recover (value:world) := let b:=registry value in
 let cards:=map (option_map (fun card=>if pending card then
 Selvedge.Features.Domain.Card (N.succ (Selvedge.Features.Domain.card_revision card)) (Selvedge.Features.Domain.card_contents card) (Selvedge.Features.Domain.card_task card) (Selvedge.Features.Domain.card_archived card) (Selvedge.Features.Domain.card_created card) (Selvedge.Features.Domain.card_updated card) (Selvedge.Features.Domain.EnrichmentFailed "The service restarted during drafting. Review the saved request and explicitly retry; no paid drafting request was replayed.") (Selvedge.Features.Domain.card_start_error card) (Selvedge.Features.Domain.card_pinned card) else card)) (Selvedge.Features.Domain.board_cards b) in
 store (Selvedge.Features.Domain.Board cards (Selvedge.Features.Domain.board_order b) (Selvedge.Features.Domain.board_agents b) (Selvedge.Features.Domain.board_agent_order b) (Selvedge.Features.Domain.board_automatic b) (Selvedge.Features.Domain.board_draft_profile b)) value.

Definition project_used (id:N) (value:world) := existsb (fun item=>match item with
 | Some card=>match Selvedge.Features.Domain.draft_project (Selvedge.Features.Domain.card_contents card) with Some project=>N.eqb id project | None=>false end
 | None=>false end) (Selvedge.Features.Domain.board_cards (registry value)).
