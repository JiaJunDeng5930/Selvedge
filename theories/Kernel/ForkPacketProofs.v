From Stdlib Require Import String List Bool NArith PeanoNat Lia.
From Selvedge.Foundation Require Import Json TextJson.
From Selvedge.Generated Require Import Commands.
From Selvedge.Kernel Require Import Numbers Domain Codec State Tasks Inputs Images
 InputDecoder Packet Delivery Notifications NotificationsProofs ForkCommit ForkCommitProofs
 ForkPreservation ForkAuthorizationProofs ForkLineageProofs.
From Selvedge.Features Require Import Worktree.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Module G := Selvedge.Generated.Commands.

Definition requested_fork_admissible (request : G.fork_payload) messages before parent selected :=
 fork_admissible Tasks.ManualFork (ForkCommitProofs.settings_origin request)
   (G.fork_task_id request) (G.fork_child_count request) messages (G.fork_settings request)
   before parent selected.
Definition requested_fork_world (request : G.fork_payload) messages before parent selected :=
 fork_candidate Tasks.ManualFork (G.fork_task_id request) (G.fork_child_count request)
   messages parent selected before.
Definition requested_fork_decision (request : G.fork_payload) messages before parent selected :=
 Decision (requested_fork_world request messages before parent selected)
   (success (fork_reply (G.fork_child_count request) before)) [ContinueScheduling].

Lemma fork_births_are_exactly_the_new_registry_suffix :
 forall entry owner count messages parent selected before,
 skipn (List.length (world_tasks before))
   (world_tasks (fork_candidate entry owner count messages parent selected before)) =
 constructed_children (N.to_nat count) owner
   (fork_snapshot_parent entry (fork_invocation entry count messages parent before) parent)
   messages selected entry (next_task before) (next_task before)
   (fork_invocation entry count messages parent before).
Proof.
 intros; rewrite fork_candidate_registry.
 rewrite <- (fork_retained_keeps_the_registry_length entry owner
   (fork_invocation entry count messages parent before) parent before) at 1.
 rewrite skipn_app, skipn_all, Nat.sub_diag; reflexivity.
Qed.

Lemma an_admissible_public_fork_constructs_its_actual_candidate :
 forall request messages before parent selected,
 traverse Images.parse_content (message_sources request) = Some messages ->
 requested_fork_admissible request messages before parent selected ->
 Worktree.execution_guard (G.fork_task_id request) before = None ->
 Worktree.workspace_available (settings_workspace selected) before &&
   Worktree.binding_available selected (requested_fork_world request messages before parent selected) = true ->
 ForkCommit.candidate request before = requested_fork_decision request messages before parent selected.
Proof.
 intros request messages before parent selected Parsed Admissible ParentAvailable WorkspaceAvailable.
 assert (Constructed : CommandHandlers.execute (G.Cmd_fork request) None before =
   accept (fork_reply (G.fork_child_count request) before)
     (requested_fork_world request messages before parent selected) []).
 { rewrite a_manual_fork_uses_the_actual_domain_constructor with (messages:=messages) by exact Parsed.
   apply every_admissible_fork_constructs_its_positive_business_result; exact Admissible. }
 assert (Positive : (0 < G.fork_child_count request)%N).
 { unfold requested_fork_admissible, fork_admissible in Admissible.
   destruct Admissible as (_ & _ & Count & _).
   unfold TaskConstraints.fork_count_valid in Count; apply andb_true_iff in Count as [Count _].
   now apply N.ltb_lt in Count. }
 pose proof (fork_births_are_exactly_the_new_registry_suffix Tasks.ManualFork
   (G.fork_task_id request) (G.fork_child_count request) messages parent selected before) as Births.
 remember (constructed_children (N.to_nat (G.fork_child_count request)) (G.fork_task_id request)
   (fork_snapshot_parent Tasks.ManualFork
     (fork_invocation Tasks.ManualFork (G.fork_child_count request) messages parent before) parent)
   messages selected Tasks.ManualFork (next_task before) (next_task before)
   (fork_invocation Tasks.ManualFork (G.fork_child_count request) messages parent before)) as children eqn:Children.
 destruct children as [|child rest].
 - pose proof (fork_constructs_exactly_the_requested_number_of_children
     (N.to_nat (G.fork_child_count request)) (G.fork_task_id request)
     (fork_snapshot_parent Tasks.ManualFork
       (fork_invocation Tasks.ManualFork (G.fork_child_count request) messages parent before) parent)
     messages selected Tasks.ManualFork (next_task before) (next_task before)
     (fork_invocation Tasks.ManualFork (G.fork_child_count request) messages parent before)) as Count.
   rewrite <- Children in Count; cbn in Count.
   apply (f_equal N.of_nat) in Count; rewrite N2Nat.id in Count; cbn in Count; lia.
 - assert (Selected : task_current_settings child = selected).
   { pose proof (every_constructed_child_has_its_inherited_execution_frame
       (N.to_nat (G.fork_child_count request)) (G.fork_task_id request)
       (fork_snapshot_parent Tasks.ManualFork
         (fork_invocation Tasks.ManualFork (G.fork_child_count request) messages parent before) parent)
       messages selected Tasks.ManualFork (next_task before) (next_task before)
       (fork_invocation Tasks.ManualFork (G.fork_child_count request) messages parent before)) as Frames.
     rewrite <- Children in Frames; inversion Frames as [|? ? Frame Tail]; subst.
     unfold child_execution_frame in Frame; tauto. }
   unfold requested_fork_decision.
   eapply a_constructed_fork_admits_its_workspace_once with (child:=child) (rest:=rest); try eassumption.
   rewrite Selected; exact WorkspaceAvailable.
Qed.

(** The actual exported packet commits a fork from every lawful background
    world. Scheduling is its already durable continuation; no condition removes
    operations, plugins, archived tasks or unfinished resources from that world.
    The two budgets refer to the actual input and constructed business decision. *)
Theorem every_admissible_exported_fork_commits_its_expected_business_result :
 forall source request messages before parent selected,
 WorldInvariant.well_formed before ->
 InputDecoder.decode source = Some (UserCommand (G.Cmd_fork request)) ->
 Delivery.fits_json source = true ->
 traverse Images.parse_content (message_sources request) = Some messages ->
 requested_fork_admissible request messages before parent selected ->
 Worktree.execution_guard (G.fork_task_id request) before = None ->
 Worktree.workspace_available (settings_workspace selected) before &&
   Worktree.binding_available selected (requested_fork_world request messages before parent selected) = true ->
 Delivery.fits true (requested_fork_decision request messages before parent selected) = true ->
 Packet.packet source before =
 (with_sequence (N.succ (world_sequence before)) (requested_fork_world request messages before parent selected),
  Notifications.envelope true true (Some (UserCommand (G.Cmd_fork request))) before
    (requested_fork_decision request messages before parent selected)).
Proof.
 intros source request messages before parent selected Valid Decoded InputFits Parsed Admissible
   ParentAvailable WorkspaceAvailable OutputFits.
 unfold Packet.packet, Packet.packet_admitted.
 rewrite InputDecoder.admitted_input_is_its_decoder_result.
 fold (Delivery.fits_json source).
 rewrite InputFits, Decoded; cbn [Packet.manual_fork_input].
 eapply a_fork_with_an_admitted_output_budget_is_delivered with
   (candidate:=requested_fork_decision request messages before parent selected).
 - apply an_admissible_public_fork_constructs_its_actual_candidate; assumption.
 - exact OutputFits.
Qed.

Corollary every_admissible_exported_fork_returns_its_exact_allocated_references :
 forall source request messages before parent selected,
 WorldInvariant.well_formed before ->
 InputDecoder.decode source = Some (UserCommand (G.Cmd_fork request)) ->
 Delivery.fits_json source = true ->
 traverse Images.parse_content (message_sources request) = Some messages ->
 requested_fork_admissible request messages before parent selected ->
 Worktree.execution_guard (G.fork_task_id request) before = None ->
 Worktree.workspace_available (settings_workspace selected) before &&
   Worktree.binding_available selected (requested_fork_world request messages before parent selected) = true ->
 Delivery.fits true (requested_fork_decision request messages before parent selected) = true ->
 let result := Packet.packet source before in
 bool_default "ok" (value_or_null "reply" (snd result)) false = true /\
 array_default "children" (value_or_null "result" (value_or_null "reply" (snd result))) =
   map (fun offset => number (next_task before + N.of_nat offset))
     (seq 0 (N.to_nat (G.fork_child_count request))) /\
 world_sequence (fst result) = N.succ (world_sequence before).
Proof.
 intros source request messages before parent selected Valid Decoded InputFits Parsed Admissible
   ParentAvailable WorkspaceAvailable OutputFits; cbn zeta.
 rewrite (every_admissible_exported_fork_commits_its_expected_business_result source request messages before parent selected
   Valid Decoded InputFits Parsed Admissible ParentAvailable WorkspaceAvailable OutputFits).
 cbn [fst snd].
 unfold value_or_null; rewrite notification_envelopes_preserve_the_committed_reply.
 repeat split; reflexivity.
Qed.

Lemma a_journal_cursor_preserves_all_fork_requirements : forall sequence value,
 WorldInvariant.well_formed value -> WorldInvariant.well_formed (with_sequence sequence value).
Proof.
 intros sequence [cursor tasks ticket environment projects features] [Environment Projects Tasks Tickets Features].
 constructor; assumption.
Qed.

Corollary every_admissible_exported_fork_preserves_its_world_and_existing_task_frames :
 forall source request messages before parent selected,
 WorldInvariant.well_formed before ->
 InputDecoder.decode source = Some (UserCommand (G.Cmd_fork request)) ->
 Delivery.fits_json source = true ->
 traverse Images.parse_content (message_sources request) = Some messages ->
 requested_fork_admissible request messages before parent selected ->
 Worktree.execution_guard (G.fork_task_id request) before = None ->
 Worktree.workspace_available (settings_workspace selected) before &&
   Worktree.binding_available selected (requested_fork_world request messages before parent selected) = true ->
 Delivery.fits true (requested_fork_decision request messages before parent selected) = true ->
 let result := Packet.packet source before in
 WorldInvariant.well_formed (fst result) /\
 List.length (world_tasks (fst result)) =
   (List.length (world_tasks before) + N.to_nat (G.fork_child_count request))%nat /\
 (forall queried old, find_task queried before = Some old ->
   exists next, find_task queried (fst result) = Some next /\ fork_retains_task old next) /\
 world_environment (fst result) = world_environment before /\
 world_projects (fst result) = world_projects before /\
 world_features (fst result) = world_features before.
Proof.
 intros source request messages before parent selected Valid Decoded InputFits Parsed Admissible
   ParentAvailable WorkspaceAvailable OutputFits; cbn zeta.
 rewrite (every_admissible_exported_fork_commits_its_expected_business_result source request messages before parent selected
   Valid Decoded InputFits Parsed Admissible ParentAvailable WorkspaceAvailable OutputFits).
 cbn [fst].
 pose proof Admissible as (Parent & Ready & Count & Messages & Ancestors & Resolved & Selection & Delegation).
 split.
 - apply a_journal_cursor_preserves_all_fork_requirements.
   apply admissible_forks_preserve_every_world_requirement with (origin:=settings_origin request) (raw:=G.fork_settings request);
     [exact Valid|exact Admissible|exact I].
 - split.
   + change (List.length (world_tasks (requested_fork_world request messages before parent selected)) =
       (List.length (world_tasks before) + N.to_nat (G.fork_child_count request))%nat).
     unfold requested_fork_world; rewrite fork_candidate_registry, length_app,
       fork_retained_keeps_the_registry_length, fork_constructs_exactly_the_requested_number_of_children; reflexivity.
   + split.
     * intros queried old Found.
       change (exists next, find_task queried (requested_fork_world request messages before parent selected) = Some next /\
         fork_retains_task old next).
       apply every_fork_retains_its_existing_task_fields; assumption.
     * change (world_environment (requested_fork_world request messages before parent selected) = world_environment before /\
         world_projects (requested_fork_world request messages before parent selected) = world_projects before /\
         world_features (requested_fork_world request messages before parent selected) = world_features before).
       apply (proj2 (fork_candidate_keeps_the_non_task_world_frame Tasks.ManualFork
         (G.fork_task_id request) (G.fork_child_count request) messages parent selected before)).
Qed.
