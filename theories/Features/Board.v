From Selvedge.Programming Require Callback.
From Selvedge.Programming Require InputRoute.
From Selvedge.Programming Require CommandResult DecisionComposition.
From Stdlib Require Import String Ascii List Bool NArith.
From Selvedge.Foundation Require Import Json Utf8.
From Selvedge.Programming Require Import Schema Completion.
From Selvedge.Kernel Require Import Numbers Domain State Codec Tasks Workspace CommandExecution.
From Selvedge.Programming Require Import TicketedRequest.
From Selvedge.Generated Require Import Commands.
From Selvedge.Features Require Import Domain State Observation Titles TitleRuntime Worktree BoardFacts.
From Selvedge.Features Require Import BoardParameters BoardDrafting.
Module BD := BoardDrafting.
Module FRA := FeatureRequestAdmission.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Definition registry (value:world) := Selvedge.Features.Domain.feature_board (world_features value).
Definition store (board:Selvedge.Features.Domain.board) (value:world) := Selvedge.Kernel.State.with_features (Selvedge.Features.State.with_board board (world_features value)) value.
Definition lookup (id:N) (value:world) := match registry_at id (Selvedge.Features.Domain.board_cards (registry value)) with Some card=>card | None=>None end.
Definition lookup_agent (id:N) (value:world) := match registry_at id (Selvedge.Features.Domain.board_agents (registry value)) with Some agent=>agent | None=>None end.
Definition put := TicketedRequest.Scoped.put_card.
Definition result (id:N) (card:Selvedge.Features.Domain.card) := JObject [("card_id",number id);("revision",number (Selvedge.Features.Domain.card_revision card))].
Definition save_change (id:N) (card:Selvedge.Features.Domain.card) (value:world) :=
 CommandResult.Change (result id card) (put id card value) [].
Definition save (id:N) (card:Selvedge.Features.Domain.card) (value:world) :=
 CommandResult.accept (save_change id card value).
Record patch := Patch { patch_title:option string;patch_description:option string;
 patch_stage:option Selvedge.Features.Domain.board_stage;patch_priority:option Selvedge.Features.Domain.priority;
 patch_owner:option Selvedge.Features.Domain.owner;patch_project:option (option N);
 patch_labels:option (list string);patch_attachments:option (list Selvedge.Features.Domain.attachment) }.
Definition retained {A:Type} (input:option A) (old:A) := match input with Some value=>value | None=>old end.
Definition apply_patch (input:patch) (old:Selvedge.Features.Domain.card_draft) :=
 Selvedge.Features.Domain.CardDraft
 (retained (patch_title input) (Selvedge.Features.Domain.draft_title old))
 (retained (patch_description input) (Selvedge.Features.Domain.draft_description old))
 (retained (patch_stage input) (Selvedge.Features.Domain.draft_stage old))
 (retained (patch_priority input) (Selvedge.Features.Domain.draft_priority old))
 (retained (patch_owner input) (Selvedge.Features.Domain.draft_owner old))
 (retained (patch_project input) (Selvedge.Features.Domain.draft_project old))
 (retained (patch_labels input) (Selvedge.Features.Domain.draft_labels old))
 (retained (patch_attachments input) (Selvedge.Features.Domain.draft_attachments old)).
Definition valid_draft := BoardFacts.valid_draft.
Definition empty_draft := Selvedge.Features.Domain.CardDraft "" "" Selvedge.Features.Domain.Todo Selvedge.Features.Domain.NoPriority Selvedge.Features.Domain.Unassigned None [] [].
Definition linked_task := BoardFacts.linked_task.
Definition busy_task := BoardFacts.busy_task.
Definition busy := BoardFacts.busy.
Definition pending := BoardFacts.pending.
Definition mutable := BoardFacts.mutable.
Definition unlinked := BoardFacts.unlinked.
Definition revised := BoardFacts.revised.
Definition with_stage (stage:Selvedge.Features.Domain.board_stage) (draft:Selvedge.Features.Domain.card_draft) := (set Selvedge.Features.Domain.draft_stage (fun _=>stage) (draft)).
Definition owner_agent := BoardFacts.owner_agent.
Definition active_for := BoardFacts.active_for.
Definition runnable := BoardFacts.runnable.
Definition latest_failure := BoardFacts.latest_failure.
Definition activity := BoardFacts.activity.
Definition card_json (id:N) (card:Selvedge.Features.Domain.card) (value:world) := Observation.card_json_in_world value id card.
Definition visible_cards (value:world) := fold_right (fun id rest=>match lookup id value with Some card=>card_json id card value::rest | None=>rest end) [] (Selvedge.Features.Domain.board_order (registry value)).
Definition handle_list_cards (p:Selvedge.Generated.Commands.list_cards_payload) (caller:option N) (value:world) :json :=
 Selvedge.Kernel.State.success (JObject [("cards",JArray (visible_cards value));("automatic",JBool (Selvedge.Features.Domain.board_automatic (registry value)));("draft_profile",JString (Selvedge.Features.Domain.board_draft_profile (registry value)))]).
Definition handle_read_card (p:Selvedge.Generated.Commands.read_card_payload) (caller:option N) (value:world) :json :=
 match lookup (Selvedge.Generated.Commands.read_card_card_id p) value with Some card=>Selvedge.Kernel.State.success (card_json (Selvedge.Generated.Commands.read_card_card_id p) card value) | None=>Selvedge.Kernel.State.failure "card_not_found" "The board card does not exist" end.
Definition handle_list_board_agents (p:Selvedge.Generated.Commands.list_board_agents_payload) (caller:option N) (value:world) :json :=
 Selvedge.Kernel.State.success (JObject [("agents",JArray (Observation.agents_json_in_world value))]).
Definition select_card_reference (id revision:N) (value:world) : CommandResult.result (BD.card_reference value id) :=
 FRA.observe (lookup id value) (fun card Found =>
   if N.eqb revision (Selvedge.Features.Domain.card_revision card)
   then CommandResult.Accepted (BD.CardReference card Found)
   else CommandResult.refuse "card_conflict" "The card changed in another view or during execution. Refresh its current values before applying this edit.")
 (fun _ => CommandResult.refuse "card_not_found" "The board card does not exist").
Definition select_card (id revision:N) (value:world) :=
 CommandResult.map BD.selected_card (select_card_reference id revision value).
Definition with_card (id revision:N) (value:world) (run:Selvedge.Features.Domain.card->decision) :=
 CommandResult.resolve value run (select_card id revision value).
Definition request_text_result {value} (target:BD.drafting_target value) (profile_name:string) :=
 let name:=if String.eqb profile_name "" then Selvedge.Features.Domain.board_draft_profile (registry value) else profile_name in
 FRA.observe (Tasks.find_profile name (environment_profiles (world_environment value)))
 (fun profile Selected =>
   CommandResult.require (TitleRuntime.ordinary profile) (fun Ordinary =>
     let request:=BD.plan target name profile Selected Ordinary in
     let issued:=TicketedRequest.Scoped.feature_issue_change request in
     CommandResult.Accepted (CommandResult.Change (result (BD.target_id target) (BD.target_card target))
       (CommandResult.change_world issued) (CommandResult.change_effects issued)))
   "draft_profile_invalid" "Title/description assistance requires an ordinary tool-free endpoint")
 (fun _ => CommandResult.refuse "draft_profile_required" "Choose a configured ordinary drafting endpoint").
Definition request_text {value} (target:BD.drafting_target value) (profile_name:string) :=
 CommandResult.decide value (request_text_result target profile_name).
Definition normalized_draft (assisted:bool) (draft:Selvedge.Features.Domain.card_draft) := if assisted then
   match Utf8.chunks (Selvedge.Features.Domain.draft_title draft) with
   | None=>draft
   | Some title_chunks=>
     let trimmed:=Titles.trim_both Utf8.whitespace title_chunks in
     let title:=match trimmed with
       | []=>match Utf8.chunks (Selvedge.Features.Domain.draft_description draft) with
         | Some description=>Utf8.render_chunks (firstn 120 (Titles.trim_both Utf8.whitespace description))
         | None=>"" end
       | _=>Utf8.render_chunks trimmed end in
     set Selvedge.Features.Domain.draft_title (fun _=>title) draft
   end else draft.
Definition parsed_drafting_target parsed assisted value (now : BoardClock.t)
 (Valid : valid_draft (normalized_draft assisted parsed) value &&
   Nat.ltb (BD.live_count value) 512 && N.ltb (BD.fresh_id value) 4294967295 = true)
 : BD.drafting_target value.
Proof.
 apply andb_true_iff in Valid as [DraftCapacity Identity].
 apply andb_true_iff in DraftCapacity as [Draft Capacity].
 exact (BD.fresh_target value (normalized_draft assisted parsed) now Draft Capacity Identity).
Defined.
Definition create_card_result (input:patch) (observed:BoardParameters.clock) (assisted:bool) (profile:string) (value:world) :=
 let parsed:=apply_patch input empty_draft in let draft:=normalized_draft assisted parsed in
 CommandResult.require (valid_draft draft value && Nat.ltb (BD.live_count value) 512 && N.ltb (BD.fresh_id value) 4294967295)
 (fun Valid => if assisted then request_text_result
   (parsed_drafting_target parsed assisted value observed Valid) profile
   else CommandResult.Accepted (save_change (BD.fresh_id value) (BD.fresh_card draft observed) value))
 "invalid_card" "Provide a nonempty title or assisted request, valid project/assignee and bounded text/files. The board holds at most 512 cards.".
Definition create_card (input:patch) (observed:BoardParameters.clock) (assisted:bool) (profile:string) (value:world) :=
 CommandResult.decide value (create_card_result input observed assisted profile value).
Definition changes_execution (input:patch) :=
 match patch_title input,patch_description input,patch_owner input,patch_project input,patch_attachments input with None,None,None,None,None=>false | _,_,_,_,_=>true end.
Definition update_card (id revision:N) (observed:BoardParameters.clock) (input:patch) (value:world) :=
 with_card id revision value (fun card=>let draft:=apply_patch input (Selvedge.Features.Domain.card_contents card) in
 if mutable card value && (unlinked card || negb (changes_execution input)) && valid_draft draft value
 then save id (revised draft observed card) value
 else Selvedge.Kernel.State.reject "card_locked" "The card is busy, archived or invalid. Execution inputs cannot be edited after a conversation is linked." value).
Fixpoint insert_before (id:N) (before:option N) (order:list N) := match order with []=>[id] | item::rest=>
 if match before with Some target=>N.eqb target item | None=>false end then id::order else item::insert_before id before rest end.
Definition move_card (id revision:N) (observed:BoardParameters.clock)
 (destination:Selvedge.Features.Domain.board_stage) (target:option N) (value:world) :=
 let now:=observed in with_card id revision value (fun card=>
 let valid_target:=match target with None=>true | Some target=>negb (N.eqb target id) && match lookup target value with Some other=>negb (Selvedge.Features.Domain.card_archived other) && String.eqb (Selvedge.Features.Domain.stage_name destination) (Selvedge.Features.Domain.stage_name (Selvedge.Features.Domain.draft_stage (Selvedge.Features.Domain.card_contents other))) && Bool.eqb (Selvedge.Features.Domain.card_pinned card) (Selvedge.Features.Domain.card_pinned other) | None=>false end end in
 if mutable card value && valid_target then let updated:=revised (with_stage destination (Selvedge.Features.Domain.card_contents card)) now card in
 let changed:=put id updated value in let b:=registry changed in
 Selvedge.Kernel.State.accept (result id updated) (store ((set Selvedge.Features.Domain.board_order (fun _=>(insert_before id target (filter (fun other=>negb (N.eqb id other)) (Selvedge.Features.Domain.board_order b)))) (b))) changed) []
 else Selvedge.Kernel.State.reject "invalid_card_move" "The card must be editable and the insertion target must remain in the destination column and pin group" value).
Definition pin (id revision:N) (observed:BoardParameters.clock) (pinned:bool) (value:world) :=
 let now:=observed in with_card id revision value (fun card=>
 if mutable card value then let updated:=revised (Selvedge.Features.Domain.card_contents card) now card in
 save id ((set Selvedge.Features.Domain.card_pinned (fun _=>pinned) (set Selvedge.Features.Domain.card_updated_at (fun _=>now) (set Selvedge.Features.Domain.card_contents (fun _=>(Selvedge.Features.Domain.card_contents updated)) (set Selvedge.Features.Domain.card_revision (fun _=>(Selvedge.Features.Domain.card_revision updated)) (card)))))) value
 else Selvedge.Kernel.State.reject "card_locked" "A running, archived or generating card cannot be pinned or unpinned" value).
Definition link (id revision:N) (observed:BoardParameters.clock) (target:N) (value:world) :=
 let now:=observed in with_card id revision value (fun card=>
 match Selvedge.Kernel.State.find_task target value with None=>Selvedge.Kernel.State.reject "task_not_found" "The conversation to link does not exist" value | Some _=>
 let used:=existsb (fun candidate=>match candidate with Some other=>match Selvedge.Features.Domain.card_task other with Some linked=>N.eqb linked target | None=>false end | None=>false end) (Selvedge.Features.Domain.board_cards (registry value)) in
 if mutable card value && unlinked card && negb used then let updated:=revised (Selvedge.Features.Domain.card_contents card) now card in
 save id ((set Selvedge.Features.Domain.card_start_error (fun _=>"") (set Selvedge.Features.Domain.card_updated_at (fun _=>now) (set Selvedge.Features.Domain.card_archived (fun _=>false) (set Selvedge.Features.Domain.card_task (fun _=>(Some target)) (set Selvedge.Features.Domain.card_contents (fun _=>(with_stage Selvedge.Features.Domain.InProgress (Selvedge.Features.Domain.card_contents card))) (set Selvedge.Features.Domain.card_revision (fun _=>(Selvedge.Features.Domain.card_revision updated)) (card)))))))) value
 else Selvedge.Kernel.State.reject "conversation_already_linked" "A card can link one conversation, and a conversation can belong to only one card" value end).
Definition archive_interrupt_target (archived:bool) (card:Selvedge.Features.Domain.card) (value:world) :=
 if archived then match Selvedge.Features.Domain.card_task card with
 | Some target=>match Selvedge.Kernel.State.find_task target value with
   | Some task=>if task_busy task && negb (task_archived task) then Some target else None
   | None=>None end
 | None=>None end else None.
Definition archive_card (id revision:N) (observed:BoardParameters.clock) (archived:bool) (value:world) :=
 let now:=observed in with_card id revision value (fun card=>
 if pending card then Selvedge.Kernel.State.reject "card_locked" "Wait for pending drafting before archiving or restoring the card" value else
 let target:=archive_interrupt_target archived card value in
 let updated:=(set Selvedge.Features.Domain.card_enrichment (fun _=>Selvedge.Features.Domain.NoEnrichment) (set Selvedge.Features.Domain.card_updated_at (fun _=>now) (set Selvedge.Features.Domain.card_archived (fun _=>archived) (set Selvedge.Features.Domain.card_revision (fun _=>(N.succ (Selvedge.Features.Domain.card_revision card))) (card))))) in
 let saved:=save id updated value in
 match target with Some target=>
 let stopped:=Tasks.control_command target Tasks.Interrupt (decision_world saved) in
 Selvedge.Kernel.State.Decision (decision_world stopped) (decision_reply saved) (decision_effects stopped) | None=>saved end).
Definition delete_card (id revision:N) (value:world) := with_card id revision value (fun card=>if pending card || busy card value then Selvedge.Kernel.State.reject "card_locked" "Stop the running conversation and wait for pending drafting before deleting this card" value else
 let b:=registry value in Selvedge.Kernel.State.accept (JObject [("card_id",number id)]) (store ((set Selvedge.Features.Domain.board_order (fun _=>(filter (fun other=>negb (N.eqb id other)) (Selvedge.Features.Domain.board_order b))) (set Selvedge.Features.Domain.board_cards (fun _=>(replace id None (Selvedge.Features.Domain.board_cards b))) (b)))) value) []).
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
 Codec.with_requested_project (Selvedge.Features.Domain.draft_project draft)
   (Selvedge.Features.Domain.agent_settings_request agent).
Definition run_result (id revision:N) (observed:BoardParameters.clock) (caller:option N) (value:world) :=
 let now:=observed in CommandResult.bind (select_card id revision value) (fun card=>
 if negb (runnable card value) then CommandResult.refuse "card_not_runnable" "The card already has a conversation, is locked, has no agent, or the assigned agent has reached its concurrency limit" else
 match owner_agent (Selvedge.Features.Domain.draft_owner (Selvedge.Features.Domain.card_contents card)) value with None=>CommandResult.refuse "agent_required" "Assign a configured endpoint or board agent before starting this card" | Some agent=>
 let settings:=launch_settings agent (Selvedge.Features.Domain.card_contents card) in
 CommandResult.map (fun birth=>
 let updated:=(set Selvedge.Features.Domain.card_start_error (fun _=>"") (set Selvedge.Features.Domain.card_enrichment (fun _=>Selvedge.Features.Domain.NoEnrichment) (set Selvedge.Features.Domain.card_updated_at (fun _=>now) (set Selvedge.Features.Domain.card_archived (fun _=>false) (set Selvedge.Features.Domain.card_task (fun _=>(Some (Worktree.transition_identity birth))) (set Selvedge.Features.Domain.card_contents (fun _=>(with_stage Selvedge.Features.Domain.InProgress (Selvedge.Features.Domain.card_contents card))) (set Selvedge.Features.Domain.card_revision (fun _=>(N.succ revision)) (card)))))))) in
 CommandResult.Change (JObject [("card_id",number id);("task_id",number (Worktree.transition_identity birth));("revision",number (N.succ revision))]) (put id updated (Worktree.transition_world birth)) (Worktree.transition_effects birth))
   (Worktree.create_selected_result (Selvedge.Features.Domain.agent_profile agent) (Some (Selvedge.Features.Domain.agent_reasoning agent)) (task_contents id (Selvedge.Features.Domain.card_contents card) (Selvedge.Features.Domain.agent_instructions agent)) (Some settings) false caller None value) end).
Definition run (id revision:N) (observed:BoardParameters.clock) (caller:option N) (value:world) :=
 CommandResult.decide value (run_result id revision observed caller value).
Definition agent_name_valid (name:string) := D.check agent_name_declaration (JString name).
Definition agent_profile_valid (profile:string) := D.check agent_profile_declaration (JString profile).
Definition agent_reasoning_valid (reasoning:string) := D.check agent_reasoning_declaration (JString reasoning).
Definition agent_instructions_valid (instructions:string) := D.check agent_instructions_declaration (JString instructions).
Definition agent_concurrency_valid (capacity:N) := D.check agent_capacity_declaration (number capacity).
Definition agent_execution_available (agent:Selvedge.Features.Domain.board_agent) (value:world) :=
 match Tasks.find_profile (Selvedge.Features.Domain.agent_profile agent) (environment_profiles (world_environment value)) with None=>false | Some profile=>
 match Tasks.selected_reasoning (Some (Selvedge.Features.Domain.agent_reasoning agent)) profile,Tasks.resolve_settings profile (Some (Selvedge.Features.Domain.agent_settings_request agent)) (Tasks.creation_defaults (world_environment value)) value with Some _,Some _=>true | _,_=>false end end.
Definition agent_identity (source : Selvedge.Generated.Commands.save_board_agent_payload) :=
 project_of_values (Selvedge.Generated.Commands.save_board_agent_agent_admitted source).
Definition agent_parameters revision (source : Selvedge.Generated.Commands.save_board_agent_payload) :=
 Selvedge.Features.Domain.BoardAgent revision
   (Selvedge.Generated.Commands.save_board_agent_name source)
   (Selvedge.Generated.Commands.save_board_agent_profile source)
   (Selvedge.Generated.Commands.save_board_agent_reasoning source)
   (Selvedge.Generated.Commands.save_board_agent_instructions source)
   (retained (option_map (Codec.settings_request_of_values true)
     (Selvedge.Generated.Commands.save_board_agent_settings_admitted source)) Codec.empty_settings_request)
   (Selvedge.Generated.Commands.save_board_agent_concurrency source).
Definition save_agent (source : Selvedge.Generated.Commands.save_board_agent_payload) (value:world) :=
 let selected:=agent_identity source in
 let id:=match selected with Some id=>id | None=>N.of_nat (List.length (Selvedge.Features.Domain.board_agents (registry value))) end in
 let expected:=Selvedge.Generated.Commands.save_board_agent_revision source in
 let revision:=match selected with Some _=>N.succ expected | None=>0%N end in
 let agent:=agent_parameters revision source in
 let failure:=if negb (agent_execution_available agent value) then
   Some ("invalid_agent","Choose a configured endpoint with supported reasoning and valid execution settings")
 else match selected with
 | None=>if Nat.ltb (List.length (filter (fun item=>match item with Some _=>true | None=>false end)
     (Selvedge.Features.Domain.board_agents (registry value)))) 64 && N.ltb id 4294967295
   then None else Some ("agent_limit","The board holds at most 64 agents")
 | Some _=>match lookup_agent id value with
   | None=>Some ("agent_not_found","The board agent no longer exists")
   | Some previous=>if N.eqb expected (Selvedge.Features.Domain.agent_revision previous)
     then None else Some ("agent_conflict","This board agent changed") end end in
 match failure with Some (code,message)=>Selvedge.Kernel.State.reject code message value | None=>
 let b:=registry value in
 Selvedge.Kernel.State.accept (JObject [("agent_id",number id);("revision",number revision)])
 (store (set Selvedge.Features.Domain.board_agent_order (fun _=>id::filter (fun other=>negb (N.eqb id other)) (Selvedge.Features.Domain.board_agent_order b))
   (set Selvedge.Features.Domain.board_agents (fun _=>match selected with
     | None=>Selvedge.Features.Domain.board_agents b++[Some agent]
     | Some _=>replace id (Some agent) (Selvedge.Features.Domain.board_agents b) end) b)) value) [] end.
Definition delete_agent (id expected:N) (value:world) := match lookup_agent id value with None=>Selvedge.Kernel.State.reject "agent_not_found" "The board agent no longer exists" value | Some agent=>
 let used:=existsb (fun item=>match item with Some card=>match Selvedge.Features.Domain.draft_owner (Selvedge.Features.Domain.card_contents card) with Selvedge.Features.Domain.AgentOwner owner=>N.eqb id owner | _=>false end | None=>false end) (Selvedge.Features.Domain.board_cards (registry value)) in
 if N.eqb expected (Selvedge.Features.Domain.agent_revision agent) && negb used then let b:=registry value in
 Selvedge.Kernel.State.accept (JObject [("agent_id",number id)]) (store ((set Selvedge.Features.Domain.board_agent_order (fun _=>(filter (fun other=>negb (N.eqb id other)) (Selvedge.Features.Domain.board_agent_order b))) (set Selvedge.Features.Domain.board_agents (fun _=>(replace id None (Selvedge.Features.Domain.board_agents b))) (b)))) value) []
 else Selvedge.Kernel.State.reject "agent_in_use" "The board agent changed or is still assigned to a card" value end.
Definition settings (automatic:bool) (profile:string) (value:world) :=
 let valid:=String.eqb profile "" || match Tasks.find_profile profile (environment_profiles (world_environment value)) with Some chosen=>TitleRuntime.ordinary chosen | None=>false end in
 if valid then let b:=registry value in Selvedge.Kernel.State.accept (JObject [("automatic",JBool automatic);("draft_profile",JString profile)])
 (store ((set Selvedge.Features.Domain.board_draft_profile (fun _=>profile) (set Selvedge.Features.Domain.board_automatic (fun _=>automatic) (b)))) value) []
 else Selvedge.Kernel.State.reject "draft_profile_invalid" "Choose a configured ordinary drafting endpoint" value.
Definition regenerate_result (id revision:N) (observed:BoardParameters.clock) (profile:string) (value:world) :=
 CommandResult.bind (select_card_reference id revision value) (fun reference =>
 CommandResult.require (mutable (BD.selected_card reference) value) (fun Mutable =>
   request_text_result (BD.revised_target value id reference observed Mutable) profile)
 "card_locked" "A running, archived or already-generating card cannot start another title request").
Definition regenerate (id revision:N) (observed:BoardParameters.clock) (profile:string) (value:world) :=
 CommandResult.decide value (regenerate_result id revision observed profile value).
Definition handle_create_card_result (p:Selvedge.Generated.Commands.create_card_payload) (caller:option N) (value:world) :CommandResult.result CommandResult.change :=
 create_card_result (Patch (Selvedge.Generated.Commands.create_card_title p) (Selvedge.Generated.Commands.create_card_description p) (option_map stage_of_values (Selvedge.Generated.Commands.create_card_status_admitted p)) (option_map priority_of_values (Selvedge.Generated.Commands.create_card_priority_admitted p)) (option_map owner_of_values (Selvedge.Generated.Commands.create_card_assignee_admitted p)) (option_map project_of_values (Selvedge.Generated.Commands.create_card_project_admitted p)) (Selvedge.Generated.Commands.create_card_labels p) (option_map attachments_of_values (Selvedge.Generated.Commands.create_card_attachments_admitted p))) (observed_clock (Selvedge.Generated.Commands.create_card_observed_at_admitted p)) (retained (Selvedge.Generated.Commands.create_card_assisted p) false) (retained (Selvedge.Generated.Commands.create_card_draft_profile p) "") value.
Definition handle_create_card (p:Selvedge.Generated.Commands.create_card_payload) (caller:option N) (value:world) :decision :=
 CommandResult.decide value (handle_create_card_result p caller value).
Definition handle_update_card (p:Selvedge.Generated.Commands.update_card_payload) (caller:option N) (value:world) :decision :=
 update_card (Selvedge.Generated.Commands.update_card_card_id p) (Selvedge.Generated.Commands.update_card_revision p) (observed_clock (Selvedge.Generated.Commands.update_card_observed_at_admitted p)) (Patch (Selvedge.Generated.Commands.update_card_title p) (Selvedge.Generated.Commands.update_card_description p) (option_map stage_of_values (Selvedge.Generated.Commands.update_card_status_admitted p)) (option_map priority_of_values (Selvedge.Generated.Commands.update_card_priority_admitted p)) (option_map owner_of_values (Selvedge.Generated.Commands.update_card_assignee_admitted p)) (option_map project_of_values (Selvedge.Generated.Commands.update_card_project_admitted p)) (Selvedge.Generated.Commands.update_card_labels p) (option_map attachments_of_values (Selvedge.Generated.Commands.update_card_attachments_admitted p))) value.
Definition handle_move_card (p:Selvedge.Generated.Commands.move_card_payload) (caller:option N) (value:world) :decision :=
 move_card (Selvedge.Generated.Commands.move_card_card_id p) (Selvedge.Generated.Commands.move_card_revision p) (observed_clock (Selvedge.Generated.Commands.move_card_observed_at_admitted p)) (stage_of_values (Selvedge.Generated.Commands.move_card_status_admitted p)) (match Selvedge.Generated.Commands.move_card_before_card_admitted p with Some value=>project_of_values value | None=>None end) value.
Definition handle_archive_card (p:Selvedge.Generated.Commands.archive_card_payload) (caller:option N) (value:world) :decision :=
 archive_card (Selvedge.Generated.Commands.archive_card_card_id p) (Selvedge.Generated.Commands.archive_card_revision p) (observed_clock (Selvedge.Generated.Commands.archive_card_observed_at_admitted p)) true value.
Definition handle_restore_card (p:Selvedge.Generated.Commands.restore_card_payload) (caller:option N) (value:world) :decision :=
 archive_card (Selvedge.Generated.Commands.restore_card_card_id p) (Selvedge.Generated.Commands.restore_card_revision p) (observed_clock (Selvedge.Generated.Commands.restore_card_observed_at_admitted p)) false value.
Definition handle_run_card (p:Selvedge.Generated.Commands.run_card_payload) (caller:option N) (value:world) :decision :=
 run (Selvedge.Generated.Commands.run_card_card_id p) (Selvedge.Generated.Commands.run_card_revision p) (observed_clock (Selvedge.Generated.Commands.run_card_observed_at_admitted p)) caller value.
Definition handle_link_card (p:Selvedge.Generated.Commands.link_card_payload) (caller:option N) (value:world) :decision :=
 link (Selvedge.Generated.Commands.link_card_card_id p) (Selvedge.Generated.Commands.link_card_revision p) (observed_clock (Selvedge.Generated.Commands.link_card_observed_at_admitted p)) (proj1_sig (Selvedge.Generated.Commands.link_card_task_id_admitted p)) value.
Definition handle_regenerate_card_title (p:Selvedge.Generated.Commands.regenerate_card_title_payload) (caller:option N) (value:world) :decision :=
 regenerate (Selvedge.Generated.Commands.regenerate_card_title_card_id p) (Selvedge.Generated.Commands.regenerate_card_title_revision p) (observed_clock (Selvedge.Generated.Commands.regenerate_card_title_observed_at_admitted p)) (retained (Selvedge.Generated.Commands.regenerate_card_title_draft_profile p) "") value.
Definition handle_pin_card (p:Selvedge.Generated.Commands.pin_card_payload) (caller:option N) (value:world) :decision :=
 pin (Selvedge.Generated.Commands.pin_card_card_id p) (Selvedge.Generated.Commands.pin_card_revision p) (observed_clock (Selvedge.Generated.Commands.pin_card_observed_at_admitted p)) (Selvedge.Generated.Commands.pin_card_pinned_admitted p) value.
Definition handle_delete_card (p:Selvedge.Generated.Commands.delete_card_payload) (caller:option N) (value:world) :decision :=
 delete_card (Selvedge.Generated.Commands.delete_card_card_id p) (Selvedge.Generated.Commands.delete_card_revision p) value.
Definition handle_board_settings (p:Selvedge.Generated.Commands.board_settings_payload) (caller:option N) (value:world) :decision :=
 settings (Selvedge.Generated.Commands.board_settings_automatic p) (Selvedge.Generated.Commands.board_settings_draft_profile p) value.
Definition handle_save_board_agent (p:Selvedge.Generated.Commands.save_board_agent_payload) (caller:option N) (value:world) :decision :=
 save_agent p value.
Definition handle_delete_board_agent (p:Selvedge.Generated.Commands.delete_board_agent_payload) (caller:option N) (value:world) :decision :=
 delete_agent (Selvedge.Generated.Commands.delete_board_agent_agent_id p) (Selvedge.Generated.Commands.delete_board_agent_revision p) value.
Definition failure_text (source:string) := match Utf8.chunks source with Some chunks=>Utf8.render_chunks (firstn 1000 chunks) | None=>"Invalid UTF-8 drafting failure" end.
Definition suggestion (ok retitle:bool) (title description message:string)
 (card:Selvedge.Features.Domain.card) (value:world)
 : Completion.Row.amendment Selvedge.Features.Domain.card Selvedge.Features.Domain.Enriching :=
 let old:=Selvedge.Features.Domain.card_contents card in
 let draft:=set Selvedge.Features.Domain.draft_description
   (fun _=>if retitle then Selvedge.Features.Domain.draft_description old else description)
   (set Selvedge.Features.Domain.draft_title (fun _=>Titles.normalize title) old) in
 let valid:=ok && valid_draft draft value in
 Completion.Row.Amend
   [Completion.Row.assign Selvedge.Features.Domain.card_revision (N.succ (Selvedge.Features.Domain.card_revision card));
    Completion.Row.assign Selvedge.Features.Domain.card_contents (if valid then draft else old)]
   (if valid then Completion.done Selvedge.Features.Domain.NoEnrichment
    else Completion.done (Selvedge.Features.Domain.EnrichmentFailed (failure_text (if ok then
      "The drafting endpoint returned an empty or oversized title/description. The original request is preserved." else message)))).
Definition suggestion_from_reply (reply : Callback.reply_fields ModelDeclarations.BoardText)
 (retitle : bool) (card : Selvedge.Features.Domain.card) (value : world) :=
 let '(existT _ ok fields) := reply in
 (if ok as ok return DeclarationFields.values (Callback.payload ModelDeclarations.BoardText ok) ->
   Completion.Row.amendment Selvedge.Features.Domain.card Selvedge.Features.Domain.Enriching
  then fun fields => suggestion true retitle (proj1_sig (fst fields))
     (proj1_sig (fst (snd fields))) "" card value
  else fun fields => suggestion false retitle "" "" (proj1_sig (fst fields)) card value) fields.
Definition completion_choice reply value (card : Selvedge.Features.Domain.card)
 (request : RequestEnvelope.t (N * bool)) :=
 let '(revision,retitle) := RequestEnvelope.input request in
 if N.eqb revision (Selvedge.Features.Domain.card_revision card) && negb (Selvedge.Features.Domain.card_archived card)
 then Some (suggestion_from_reply reply retitle card value) else None.
Definition completion_path id := Receiver.field world_features (TicketedRequest.Scoped.card_slot id).
Definition completion (received : Callback.decoded ModelDeclarations.BoardText) (value : world)
 : bool * bool * decision :=
 let '(existT _ ok (address,fields)) := received in
 let id := head address in let ticket := head (tail address) in
 let ignored := Selvedge.Kernel.State.accept (JObject [("accepted",JBool false)]) value [] in
 match Completion.Row.consume (completion_path id) Selvedge.Features.Domain.card_enrichment
   Selvedge.Features.Domain.Enriching Completion.Ticket ticket
   (completion_choice (existT _ ok fields) value) value with
 | Some received => (true,true,Selvedge.Kernel.State.accept (JObject [("accepted",JBool true)]) (Completion.Row.after received) [])
 | None => (false,false,ignored) end.
Definition completion_inputs := [InputRoute.callback ModelDeclarations.BoardText
 (fun received => Some (completion received))].
Definition synchronize_card (card:Selvedge.Features.Domain.card) (value:world) :=
 if Selvedge.Features.Domain.card_archived card || pending card then card else match linked_task card value with None=>card | Some task=>
 let previous:=Selvedge.Features.Domain.draft_stage (Selvedge.Features.Domain.card_contents card) in
 let next:=if busy_task task then Selvedge.Features.Domain.InProgress else match previous with Selvedge.Features.Domain.InProgress=>if latest_failure task then Selvedge.Features.Domain.Blocked else Selvedge.Features.Domain.InReview | _=>previous end in
 if String.eqb (Selvedge.Features.Domain.stage_name previous) (Selvedge.Features.Domain.stage_name next) then card else revised (with_stage next (Selvedge.Features.Domain.card_contents card)) (Selvedge.Features.Domain.card_updated_at card) card end.
Definition synchronize (value:world) := let b:=registry value in
 store ((set Selvedge.Features.Domain.board_cards (fun _=>(map (option_map (fun card=>synchronize_card card value)) (Selvedge.Features.Domain.board_cards b))) (b))) value.
Definition ready (card:Selvedge.Features.Domain.card) (value:world) := runnable card value &&
 (match Selvedge.Features.Domain.card_enrichment card with Selvedge.Features.Domain.NoEnrichment=>true | _=>false end) && match Selvedge.Features.Domain.draft_stage (Selvedge.Features.Domain.card_contents card) with Selvedge.Features.Domain.Todo|Selvedge.Features.Domain.InProgress=>true | _=>false end.
Definition priority_rank (p:Selvedge.Features.Domain.priority) :N := match p with Selvedge.Features.Domain.Urgent=>4 | Selvedge.Features.Domain.High=>3 | Selvedge.Features.Domain.Medium=>2 | Selvedge.Features.Domain.Low=>1 | Selvedge.Features.Domain.NoPriority=>0 end.
Definition queued (value:world) := let order:=Selvedge.Features.Domain.board_order (registry value) in
 flat_map (fun pinned=>flat_map (fun priority=>filter (fun id=>match lookup id value with Some card=>
 Bool.eqb pinned (Selvedge.Features.Domain.card_pinned card) && N.eqb priority (priority_rank (Selvedge.Features.Domain.draft_priority (Selvedge.Features.Domain.card_contents card))) && ready card value | None=>false end) order) [4%N;3%N;2%N;1%N;0%N]) [true;false].
Definition next (value:world) := if Selvedge.Features.Domain.board_automatic (registry value) then hd_error (queued value) else None.
Definition start_failed (id:N) (card:Selvedge.Features.Domain.card) (reason:string) (value:world) := put id
 ((set Selvedge.Features.Domain.card_start_error (fun _=>(failure_text reason)) (set Selvedge.Features.Domain.card_contents (fun _=>(with_stage Selvedge.Features.Domain.Blocked (Selvedge.Features.Domain.card_contents card))) (set Selvedge.Features.Domain.card_revision (fun _=>(N.succ (Selvedge.Features.Domain.card_revision card))) (card))))) value.
Fixpoint pump (fuel:nat) : DecisionComposition.step := fun value effects => match fuel with
 | O=>DecisionComposition.unchanged value
 | S rest=>match next value with None=>DecisionComposition.unchanged value | Some id=>
 match lookup id value with None=>DecisionComposition.unchanged value | Some card=>
 let current:=match run_result id (Selvedge.Features.Domain.card_revision card)
   (Selvedge.Features.Domain.card_updated_at card) None value with
 | CommandResult.Accepted advanced=>DecisionComposition.from_decision (CommandResult.accept advanced)
 | CommandResult.Rejected reason=>DecisionComposition.unchanged
   (start_failed id card (String.append (CommandResult.refusal_code reason)
     (String.append ": " (CommandResult.refusal_message reason))) value) end in
 DecisionComposition.and_then (fun _ _=>current) (pump rest) value effects end end end.
Definition after_transition (_before:world) : DecisionComposition.step :=
 DecisionComposition.and_then (DecisionComposition.world_only synchronize) (pump 8).
Definition finish : DecisionComposition.step := fun value effects =>
 let value:=synchronize value in
 let more:=match next value with Some _=>true | None=>false end in
 let continuing:=existsb (fun effect=>match effect with Selvedge.Kernel.State.ContinueScheduling=>true | _=>false end) effects in
 DecisionComposition.Update value (if more && negb continuing then [Selvedge.Kernel.State.ContinueScheduling] else []).
Definition recover (value:world) := let b:=registry value in
 let cards:=map (option_map (fun card=>if pending card then
 (set Selvedge.Features.Domain.card_enrichment (fun _=>(Selvedge.Features.Domain.EnrichmentFailed "The service restarted during drafting. Review the saved request and explicitly retry; no paid drafting request was replayed.")) (set Selvedge.Features.Domain.card_revision (fun _=>(N.succ (Selvedge.Features.Domain.card_revision card))) (card))) else card)) (Selvedge.Features.Domain.board_cards b) in
 store ((set Selvedge.Features.Domain.board_cards (fun _=>cards) (b))) value.
