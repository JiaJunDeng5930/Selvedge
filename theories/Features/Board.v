From Selvedge.Kernel Require CallbackDeclarations.
From Selvedge.Kernel Require CommandResult DecisionComposition.
From Stdlib Require Import String Ascii List Bool NArith.
From Selvedge.Foundation Require Import Json Utf8 Schema.
From Selvedge.Kernel Require Import Numbers Domain State Codec Tasks Workspace CommandExecution TicketedRequest.
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
Lemma observed_clock_is_bounded : forall supplied now,
 clock supplied = Some now -> N.leb now 4294967295 = true.
Proof.
 intros [text|] now Clock; unfold clock in Clock.
 - destruct (text_id text) as [found|]; [|discriminate].
   destruct (N.leb found 4294967295) eqn:Bound; [|discriminate].
   inversion Clock; subst now; exact Bound.
 - inversion Clock; reflexivity.
Qed.
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
Definition select_clock (supplied:option string) := match clock supplied with
 | Some now=>CommandResult.Accepted now
 | None=>CommandResult.refuse "invalid_clock" "observed_at must be a canonical U32 decimal timestamp" end.
Definition at_clock (supplied:option string) (value:world) (run:N->decision) :=
 CommandResult.resolve value run (select_clock supplied).
Definition request_text_result {value} (target:BD.drafting_target value) (profile_name:string) :=
 let name:=if String.eqb profile_name "" then Selvedge.Features.Domain.board_draft_profile (registry value) else profile_name in
 FRA.observe (Tasks.find_profile name (environment_profiles (world_environment value)))
 (fun profile Selected =>
   FRA.require (TitleRuntime.ordinary profile) (fun Ordinary =>
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
Definition parsed_drafting_target parsed assisted value now
 (Clock : N.leb now 4294967295 = true)
 (Valid : valid_draft (normalized_draft assisted parsed) value &&
   Nat.ltb (BD.live_count value) 512 && N.ltb (BD.fresh_id value) 4294967295 = true)
 : BD.drafting_target value.
Proof.
 apply andb_true_iff in Valid as [DraftCapacity Identity].
 apply andb_true_iff in DraftCapacity as [Draft Capacity].
 exact (BD.fresh_target value (normalized_draft assisted parsed) now Clock Draft Capacity Identity).
Defined.
Definition create_card_result (input:patch) (supplied:option string) (assisted:bool) (profile:string) (value:world) :=
 FRA.observe (clock supplied) (fun now Clock =>
 FRA.observe (parse_patch input empty_draft) (fun parsed Parsed =>
 let draft:=normalized_draft assisted parsed in
 FRA.require (valid_draft draft value && Nat.ltb (BD.live_count value) 512 && N.ltb (BD.fresh_id value) 4294967295)
 (fun Valid => if assisted then request_text_result
   (parsed_drafting_target parsed assisted value now
     (observed_clock_is_bounded supplied now Clock) Valid) profile
   else CommandResult.Accepted (save_change (BD.fresh_id value) (BD.fresh_card draft now) value))
 "invalid_card" "Provide a nonempty title or assisted request, valid project/assignee and bounded text/files. The board holds at most 512 cards.")
 (fun _ => CommandResult.refuse "invalid_card" "Invalid board card fields"))
 (fun _ => CommandResult.refuse "invalid_clock" "observed_at must be a canonical U32 decimal timestamp").
Definition create_card (input:patch) (supplied:option string) (assisted:bool) (profile:string) (value:world) :=
 CommandResult.decide value (create_card_result input supplied assisted profile value).
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
 Selvedge.Kernel.State.accept (result id updated) (store ((set Selvedge.Features.Domain.board_order (fun _=>(insert_before id target (filter (fun other=>negb (N.eqb id other)) (Selvedge.Features.Domain.board_order b)))) (b))) changed) []
 else Selvedge.Kernel.State.reject "invalid_card_move" "The card must be editable and the insertion target must remain in the destination column and pin group" value
 | _,_=>Selvedge.Kernel.State.reject "invalid_card_move" "A destination status and valid insertion target are required" value end)).
Definition pin (id revision:N) (supplied:option string) (pinned:option bool) (value:world) := at_clock supplied value (fun now=>with_card id revision value (fun card=>
 match pinned with Some pinned=>if mutable card value then let updated:=revised (Selvedge.Features.Domain.card_contents card) now card in
 save id ((set Selvedge.Features.Domain.card_pinned (fun _=>pinned) (set Selvedge.Features.Domain.card_updated (fun _=>now) (set Selvedge.Features.Domain.card_contents (fun _=>(Selvedge.Features.Domain.card_contents updated)) (set Selvedge.Features.Domain.card_revision (fun _=>(Selvedge.Features.Domain.card_revision updated)) (card)))))) value
 else Selvedge.Kernel.State.reject "card_locked" "A running, archived or generating card cannot be pinned or unpinned" value | None=>Selvedge.Kernel.State.reject "invalid_card_command" "pinned is required" value end)).
Definition link (id revision:N) (supplied:option string) (target:option N) (value:world) := at_clock supplied value (fun now=>with_card id revision value (fun card=>
 match target with Some target=>match Selvedge.Kernel.State.find_task target value with None=>Selvedge.Kernel.State.reject "task_not_found" "The conversation to link does not exist" value | Some _=>
 let used:=existsb (fun candidate=>match candidate with Some other=>match Selvedge.Features.Domain.card_task other with Some linked=>N.eqb linked target | None=>false end | None=>false end) (Selvedge.Features.Domain.board_cards (registry value)) in
 if mutable card value && unlinked card && negb used then let updated:=revised (Selvedge.Features.Domain.card_contents card) now card in
 save id ((set Selvedge.Features.Domain.card_start_error (fun _=>"") (set Selvedge.Features.Domain.card_updated (fun _=>now) (set Selvedge.Features.Domain.card_archived (fun _=>false) (set Selvedge.Features.Domain.card_task (fun _=>(Some target)) (set Selvedge.Features.Domain.card_contents (fun _=>(with_stage Selvedge.Features.Domain.InProgress (Selvedge.Features.Domain.card_contents card))) (set Selvedge.Features.Domain.card_revision (fun _=>(Selvedge.Features.Domain.card_revision updated)) (card)))))))) value
 else Selvedge.Kernel.State.reject "conversation_already_linked" "A card can link one conversation, and a conversation can belong to only one card" value end
 | None=>Selvedge.Kernel.State.reject "invalid_card_command" "task_id is required" value end)).
Definition archive_interrupt_target (archived:bool) (card:Selvedge.Features.Domain.card) (value:world) :=
 if archived then match Selvedge.Features.Domain.card_task card with
 | Some target=>match Selvedge.Kernel.State.find_task target value with
   | Some task=>if task_busy task && negb (task_archived task) then Some target else None
   | None=>None end
 | None=>None end else None.
Definition archive_card (id revision:N) (supplied:option string) (archived:bool) (value:world) := at_clock supplied value (fun now=>with_card id revision value (fun card=>
 if pending card then Selvedge.Kernel.State.reject "card_locked" "Wait for pending drafting before archiving or restoring the card" value else
 let target:=archive_interrupt_target archived card value in
 (* The resource owner can still be preparing. Refuse the entire card edit
    before its revision changes; an already archived task only needs the edit. *)
 match match target with Some target=>Worktree.control_guard Tasks.Interrupt target value | None=>None end with
 | Some refused=>refused
 | None=>
 let updated:=(set Selvedge.Features.Domain.card_enrichment (fun _=>Selvedge.Features.Domain.NoEnrichment) (set Selvedge.Features.Domain.card_updated (fun _=>now) (set Selvedge.Features.Domain.card_archived (fun _=>archived) (set Selvedge.Features.Domain.card_revision (fun _=>(N.succ (Selvedge.Features.Domain.card_revision card))) (card))))) in
 let saved:=save id updated value in
 match target with Some target=>
 let stopped:=Tasks.control_command target Tasks.Interrupt (decision_world saved) in
 Selvedge.Kernel.State.Decision (decision_world stopped) (decision_reply saved) (decision_effects stopped) | None=>saved end end)).
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
 let fields:=match Selvedge.Features.Domain.agent_settings agent with JObject fields=>fields|_=>[] end in
 let fields:=remove_field "project_id" fields in
 JObject (match Selvedge.Features.Domain.draft_project draft with Some project=>Json.set_field "project_id" (number project) fields | None=>fields end).
Definition run_result (id revision:N) (supplied:option string) (caller:option N) (value:world) :=
 CommandResult.bind (select_clock supplied) (fun now=>CommandResult.bind (select_card id revision value) (fun card=>
 if negb (runnable card value) then CommandResult.refuse "card_not_runnable" "The card already has a conversation, is locked, has no agent, or the assigned agent has reached its concurrency limit" else
 match owner_agent (Selvedge.Features.Domain.draft_owner (Selvedge.Features.Domain.card_contents card)) value with None=>CommandResult.refuse "agent_required" "Assign a configured endpoint or board agent before starting this card" | Some agent=>
 let settings:=launch_settings agent (Selvedge.Features.Domain.card_contents card) in
 CommandResult.map (fun birth=>
 let updated:=(set Selvedge.Features.Domain.card_start_error (fun _=>"") (set Selvedge.Features.Domain.card_enrichment (fun _=>Selvedge.Features.Domain.NoEnrichment) (set Selvedge.Features.Domain.card_updated (fun _=>now) (set Selvedge.Features.Domain.card_archived (fun _=>false) (set Selvedge.Features.Domain.card_task (fun _=>(Some (Worktree.transition_identity birth))) (set Selvedge.Features.Domain.card_contents (fun _=>(with_stage Selvedge.Features.Domain.InProgress (Selvedge.Features.Domain.card_contents card))) (set Selvedge.Features.Domain.card_revision (fun _=>(N.succ revision)) (card)))))))) in
 CommandResult.Change (JObject [("card_id",number id);("task_id",number (Worktree.transition_identity birth));("revision",number (N.succ revision))]) (put id updated (Worktree.transition_world birth)) (Worktree.transition_effects birth))
   (Worktree.create_selected_result (Selvedge.Features.Domain.agent_profile agent) (Some (Selvedge.Features.Domain.agent_reasoning agent)) (task_contents id (Selvedge.Features.Domain.card_contents card) (Selvedge.Features.Domain.agent_instructions agent)) (Some settings) false caller None value) end)).
Definition run (id revision:N) (supplied:option string) (caller:option N) (value:world) :=
 CommandResult.decide value (run_result id revision supplied caller value).
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
 let failure:=if negb (valid_agent agent value) then
   Some ("invalid_agent","Provide a valid name, endpoint, reasoning, settings and concurrency from 1 to 64")
 else if creating then
   if Nat.ltb (List.length (filter (fun item=>match item with Some _=>true | None=>false end)
     (Selvedge.Features.Domain.board_agents (registry value)))) 64 && N.ltb id 4294967295
   then None else Some ("agent_limit","The board holds at most 64 agents")
 else match lookup_agent id value with
   | None=>Some ("agent_not_found","The board agent no longer exists")
   | Some previous=>if N.eqb expected (Selvedge.Features.Domain.agent_revision previous)
     then None else Some ("agent_conflict","This board agent changed") end in
 match failure with Some (code,message)=>Selvedge.Kernel.State.reject code message value | None=>
 let b:=registry value in
 Selvedge.Kernel.State.accept (JObject [("agent_id",number id);("revision",number revision)]) (store ((set Selvedge.Features.Domain.board_agent_order (fun _=>(id::filter (fun other=>negb (N.eqb id other)) (Selvedge.Features.Domain.board_agent_order b))) (set Selvedge.Features.Domain.board_agents (fun _=>(if creating then Selvedge.Features.Domain.board_agents b++[Some agent] else replace id (Some agent) (Selvedge.Features.Domain.board_agents b))) (b)))) value) [] end end.
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
Definition regenerate_result (id revision:N) (supplied:option string) (profile:string) (value:world) :=
 FRA.observe (clock supplied) (fun now Clock =>
 CommandResult.bind (select_card_reference id revision value) (fun reference =>
 FRA.require (mutable (BD.selected_card reference) value) (fun Mutable =>
   request_text_result (BD.revised_target value id reference now
     (observed_clock_is_bounded supplied now Clock) Mutable) profile)
 "card_locked" "A running, archived or already-generating card cannot start another title request"))
 (fun _ => CommandResult.refuse "invalid_clock" "observed_at must be a canonical U32 decimal timestamp").
Definition regenerate (id revision:N) (supplied:option string) (profile:string) (value:world) :=
 CommandResult.decide value (regenerate_result id revision supplied profile value).
Definition handle_create_card_result (p:Selvedge.Generated.Commands.create_card_payload) (caller:option N) (value:world) :CommandResult.result CommandResult.change :=
 create_card_result (Patch (Selvedge.Generated.Commands.create_card_title p) (Selvedge.Generated.Commands.create_card_description p) (Selvedge.Generated.Commands.create_card_status p) (Selvedge.Generated.Commands.create_card_priority p) (Selvedge.Generated.Commands.create_card_assignee p) (Selvedge.Generated.Commands.create_card_project p) (Selvedge.Generated.Commands.create_card_labels p) (Selvedge.Generated.Commands.create_card_attachments p)) (Selvedge.Generated.Commands.create_card_observed_at p) (retained (Selvedge.Generated.Commands.create_card_assisted p) false) (retained (Selvedge.Generated.Commands.create_card_draft_profile p) "") value.
Definition handle_create_card (p:Selvedge.Generated.Commands.create_card_payload) (caller:option N) (value:world) :decision :=
 CommandResult.decide value (handle_create_card_result p caller value).
Definition handle_update_card (p:Selvedge.Generated.Commands.update_card_payload) (caller:option N) (value:world) :decision :=
 update_card (Selvedge.Generated.Commands.update_card_card_id p) (Selvedge.Generated.Commands.update_card_revision p) (Selvedge.Generated.Commands.update_card_observed_at p) (Patch (Selvedge.Generated.Commands.update_card_title p) (Selvedge.Generated.Commands.update_card_description p) (Selvedge.Generated.Commands.update_card_status p) (Selvedge.Generated.Commands.update_card_priority p) (Selvedge.Generated.Commands.update_card_assignee p) (Selvedge.Generated.Commands.update_card_project p) (Selvedge.Generated.Commands.update_card_labels p) (Selvedge.Generated.Commands.update_card_attachments p)) value.
Definition handle_move_card (p:Selvedge.Generated.Commands.move_card_payload) (caller:option N) (value:world) :decision :=
 move_card (Selvedge.Generated.Commands.move_card_card_id p) (Selvedge.Generated.Commands.move_card_revision p) (Selvedge.Generated.Commands.move_card_observed_at p) (Selvedge.Generated.Commands.move_card_status p) (Selvedge.Generated.Commands.move_card_before_card p) value.
Definition handle_archive_card (p:Selvedge.Generated.Commands.archive_card_payload) (caller:option N) (value:world) :decision :=
 archive_card (Selvedge.Generated.Commands.archive_card_card_id p) (Selvedge.Generated.Commands.archive_card_revision p) (Selvedge.Generated.Commands.archive_card_observed_at p) true value.
Definition handle_restore_card (p:Selvedge.Generated.Commands.restore_card_payload) (caller:option N) (value:world) :decision :=
 archive_card (Selvedge.Generated.Commands.restore_card_card_id p) (Selvedge.Generated.Commands.restore_card_revision p) (Selvedge.Generated.Commands.restore_card_observed_at p) false value.
Definition handle_run_card (p:Selvedge.Generated.Commands.run_card_payload) (caller:option N) (value:world) :decision :=
 run (Selvedge.Generated.Commands.run_card_card_id p) (Selvedge.Generated.Commands.run_card_revision p) (Selvedge.Generated.Commands.run_card_observed_at p) caller value.
Definition handle_link_card (p:Selvedge.Generated.Commands.link_card_payload) (caller:option N) (value:world) :decision :=
 link (Selvedge.Generated.Commands.link_card_card_id p) (Selvedge.Generated.Commands.link_card_revision p) (Selvedge.Generated.Commands.link_card_observed_at p) (Selvedge.Generated.Commands.link_card_task_id p) value.
Definition handle_regenerate_card_title (p:Selvedge.Generated.Commands.regenerate_card_title_payload) (caller:option N) (value:world) :decision :=
 regenerate (Selvedge.Generated.Commands.regenerate_card_title_card_id p) (Selvedge.Generated.Commands.regenerate_card_title_revision p) (Selvedge.Generated.Commands.regenerate_card_title_observed_at p) (retained (Selvedge.Generated.Commands.regenerate_card_title_draft_profile p) "") value.
Definition handle_pin_card (p:Selvedge.Generated.Commands.pin_card_payload) (caller:option N) (value:world) :decision :=
 pin (Selvedge.Generated.Commands.pin_card_card_id p) (Selvedge.Generated.Commands.pin_card_revision p) (Selvedge.Generated.Commands.pin_card_observed_at p) (Selvedge.Generated.Commands.pin_card_pinned p) value.
Definition handle_delete_card (p:Selvedge.Generated.Commands.delete_card_payload) (caller:option N) (value:world) :decision :=
 delete_card (Selvedge.Generated.Commands.delete_card_card_id p) (Selvedge.Generated.Commands.delete_card_revision p) value.
Definition handle_board_settings (p:Selvedge.Generated.Commands.board_settings_payload) (caller:option N) (value:world) :decision :=
 settings (Selvedge.Generated.Commands.board_settings_automatic p) (Selvedge.Generated.Commands.board_settings_draft_profile p) value.
Definition handle_save_board_agent (p:Selvedge.Generated.Commands.save_board_agent_payload) (caller:option N) (value:world) :decision :=
 save_agent (Selvedge.Generated.Commands.save_board_agent_agent p) (Selvedge.Generated.Commands.save_board_agent_revision p) (Selvedge.Generated.Commands.save_board_agent_name p) (Selvedge.Generated.Commands.save_board_agent_profile p) (Selvedge.Generated.Commands.save_board_agent_reasoning p) (Selvedge.Generated.Commands.save_board_agent_instructions p) (Selvedge.Generated.Commands.save_board_agent_settings p) (Selvedge.Generated.Commands.save_board_agent_concurrency p) value.
Definition handle_delete_board_agent (p:Selvedge.Generated.Commands.delete_board_agent_payload) (caller:option N) (value:world) :decision :=
 delete_agent (Selvedge.Generated.Commands.delete_board_agent_agent_id p) (Selvedge.Generated.Commands.delete_board_agent_revision p) value.
Definition failure_text (source:string) := match Utf8.chunks source with Some chunks=>Utf8.render_chunks (firstn 1000 chunks) | None=>"Invalid UTF-8 drafting failure" end.
Record completion_payload := CompletionPayload {
 completion_card : N; completion_ticket : N;
 completion_title : string; completion_description : string; completion_message : string
}.
Definition decode_completion_payload (source:json) (ok:bool) : option completion_payload :=
 if ok then match CallbackDeclarations.decode_branch ModelDeclarations.BoardText true source with
 | Some (address,values) => Some (CompletionPayload (head address) (head (tail address))
     (proj1_sig (fst values)) (proj1_sig (fst (snd values))) "")
 | None => None end
 else match CallbackDeclarations.decode_branch ModelDeclarations.BoardText false source with
 | Some (address,values) => Some (CompletionPayload (head address) (head (tail address)) "" "" (proj1_sig (fst values)))
 | None => None end.
Definition suggestion (ok retitle:bool) (title description message:string) (card:Selvedge.Features.Domain.card) (value:world) :=
 let old:=Selvedge.Features.Domain.card_contents card in
 let draft:=(set Selvedge.Features.Domain.draft_description (fun _=>(if retitle then Selvedge.Features.Domain.draft_description old else description)) (set Selvedge.Features.Domain.draft_title (fun _=>(Titles.normalize title)) (old))) in
 let valid:=ok && valid_draft draft value in
 (set Selvedge.Features.Domain.card_enrichment (fun _=>(if valid then Selvedge.Features.Domain.NoEnrichment else Selvedge.Features.Domain.EnrichmentFailed (failure_text (if ok then "The drafting endpoint returned an empty or oversized title/description. The original request is preserved." else message)))) (set Selvedge.Features.Domain.card_contents (fun _=>(if valid then draft else old)) (set Selvedge.Features.Domain.card_revision (fun _=>(N.succ (Selvedge.Features.Domain.card_revision card))) (card)))).
Definition completion (source:json) (value:world) :option (bool*bool*decision) := match string_field "kind" source with Some "board_text"=>
 match bool_field "ok" source with Some ok=>
 match decode_completion_payload source ok with Some payload=>
 let id:=completion_card payload in let ticket:=completion_ticket payload in
 let ignored:=Selvedge.Kernel.State.accept (JObject [("accepted",JBool false)]) value [] in
 Some (match lookup id value with Some card=>match Selvedge.Features.Domain.card_enrichment card with
 | Selvedge.Features.Domain.Enriching (RequestEnvelope.Envelope expected (revision, retitle))=>if N.eqb ticket expected && N.eqb revision (Selvedge.Features.Domain.card_revision card) && negb (Selvedge.Features.Domain.card_archived card) then
 (true,true,Selvedge.Kernel.State.accept (JObject [("accepted",JBool true)]) (put id (suggestion ok retitle (completion_title payload) (completion_description payload) (completion_message payload) card value) value) [])
 else (false,false,ignored)
 | _=>(false,false,ignored) end | None=>(false,false,ignored) end)
 | None=>None end | None=>None end | _=>None end.
Definition synchronize_card (card:Selvedge.Features.Domain.card) (value:world) :=
 if Selvedge.Features.Domain.card_archived card || pending card then card else match linked_task card value with None=>card | Some task=>
 let previous:=Selvedge.Features.Domain.draft_stage (Selvedge.Features.Domain.card_contents card) in
 let next:=if busy_task task then Selvedge.Features.Domain.InProgress else match previous with Selvedge.Features.Domain.InProgress=>if latest_failure task then Selvedge.Features.Domain.Blocked else Selvedge.Features.Domain.InReview | _=>previous end in
 if String.eqb (Selvedge.Features.Domain.stage_name previous) (Selvedge.Features.Domain.stage_name next) then card else revised (with_stage next (Selvedge.Features.Domain.card_contents card)) (Selvedge.Features.Domain.card_updated card) card end.
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
   (Some (Selvedge.Features.Domain.decimal_text (Selvedge.Features.Domain.card_updated card))) None value with
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

Definition project_used (id:N) (value:world) := existsb (fun item=>match item with
 | Some card=>match Selvedge.Features.Domain.draft_project (Selvedge.Features.Domain.card_contents card) with Some project=>N.eqb id project | None=>false end
 | None=>false end) (Selvedge.Features.Domain.board_cards (registry value)).
