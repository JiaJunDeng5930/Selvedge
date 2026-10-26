From Selvedge.Kernel Require CommandResult CommitPacket.
From Selvedge.Kernel Require Import TaskChangesProofs.
From Stdlib Require Import String List Bool NArith Lia.
From Selvedge.Foundation Require Import Json.
From Selvedge.Generated Require Import Commands.
From Selvedge.Kernel Require Import Domain Codec State Inputs CommandHandlers
 CommandExecution Tasks ForkCommit Delivery Notifications.
From Selvedge.Features Require Import Worktree.
Import ListNotations.
Open Scope string_scope.
Module G := Selvedge.Generated.Commands.

Definition settings_origin (request : G.fork_payload) :=
 match G.fork_settings_origin request with
 | Some source => if String.eqb (proj1_sig source) "environment"
   then Tasks.EnvironmentSettings else Tasks.ParentSettings
 | None => Tasks.ParentSettings
 end.
Definition message_sources (request : G.fork_payload) :=
 match G.fork_messages request with Some values => values | None => [] end.

Lemma the_fork_constructor_emits_no_unbound_effects : forall entry origin owner count messages raw before,
 decision_effects (Tasks.fork_with_caller entry origin owner count messages raw before) = [].
Proof.
 intros; rewrite TaskChangesProofs.fork_with_caller_expression; cbv beta zeta.
 destruct (find_task owner before) as [parent|]; [|reflexivity].
 destruct (_ && _) eqn:Eligible.
 2: { unfold Tasks.fork_refusal,Tasks.fork_refusal_reason; destruct entry;
      try destruct (Tasks.fork_parent_ready Tasks.ManualFork parent); reflexivity. }
 destruct (Tasks.resolve_settings _ _ _ _) as [selected|]; [|reflexivity].
 destruct (Tasks.admit_fork_selection _ _ _) as [selection|]; [|reflexivity].
 destruct (match entry with Tasks.ManualFork => false | Tasks.AcceptedNativeFork _ _ =>
   negb (Workspace.may_delegate (Tasks.fork_selected parent before selection) (task_current_settings parent) && Tasks.no_resource_observation raw) end);
 reflexivity.
Qed.

Lemma the_actual_fork_handler_has_its_typed_result : forall request context before,
 CommandHandlers.execute (G.Cmd_fork request) context before =
 CommandResult.decide before (CommandExecution.handle_fork_result request context before).
Proof. intros request [context|] before; reflexivity. Qed.

Lemma workspace_admission_commutes_with_typed_outcomes : forall before outcome,
 CommandResult.decide before (ForkCommit.admit_workspace before outcome) =
 ForkCommit.admit_decision before (CommandResult.decide before outcome).
Proof.
 intros before [change|reason]; unfold ForkCommit.admit_workspace,ForkCommit.admit_decision;
 cbn [CommandResult.bind CommandResult.decide CommandResult.resolve CommandResult.accept CommandResult.reject
   accept reject decision_world].
 - destruct (ForkCommit.workspace_error before (CommandResult.change_world change)); reflexivity.
 - unfold ForkCommit.workspace_error; rewrite skipn_all; reflexivity.
Qed.

Lemma the_actual_fork_handler_interprets_its_message_admission : forall request context before,
 CommandHandlers.execute (G.Cmd_fork request) context before =
 match Selvedge.Kernel.Codec.traverse Images.parse_content (message_sources request) with
 | Some messages => Tasks.fork_with_caller
   (match context with Some accepted =>
     if N.eqb (Tasks.native_owner accepted) (G.fork_task_id request)
     then Tasks.AcceptedNativeFork (Tasks.native_invocation accepted) (Tasks.native_remaining accepted)
     else Tasks.ManualFork | None => Tasks.ManualFork end)
   (settings_origin request) (G.fork_task_id request) (G.fork_child_count request)
   messages (G.fork_settings request) before
 | None => reject "invalid_message" "Child messages contain invalid content parts" before end.
Proof.
 intros request context before.
 rewrite the_actual_fork_handler_has_its_typed_result.
 change (CommandExecution.handle_fork_result request context before) with
   (match Selvedge.Kernel.Codec.traverse Images.parse_content (message_sources request) with
    | Some messages => Tasks.fork_result
        (match context with Some accepted =>
         if N.eqb (Tasks.native_owner accepted) (G.fork_task_id request)
         then Tasks.AcceptedNativeFork (Tasks.native_invocation accepted) (Tasks.native_remaining accepted)
         else Tasks.ManualFork | None => Tasks.ManualFork end)
        (settings_origin request) (G.fork_task_id request) (G.fork_child_count request)
        messages (G.fork_settings request) before
    | None => CommandResult.refuse "invalid_message" "Child messages contain invalid content parts" end).
 destruct (Selvedge.Kernel.Codec.traverse Images.parse_content (message_sources request)); reflexivity.
Qed.
Definition the_actual_manual_fork_handler_interprets_its_message_admission request :=
 the_actual_fork_handler_interprets_its_message_admission request None.

Lemma the_manual_fork_handler_emits_no_unbound_effects : forall request before,
 decision_effects (CommandHandlers.execute (G.Cmd_fork request) None before) = [].
Proof.
 intros request before.
 rewrite the_actual_manual_fork_handler_interprets_its_message_admission.
 destruct (Selvedge.Kernel.Codec.traverse Images.parse_content (message_sources request)) as [messages|]; [|reflexivity].
 apply the_fork_constructor_emits_no_unbound_effects.
Qed.

Lemma the_manual_fork_proposal_emits_no_unbound_effects : forall request before,
 decision_effects (ForkCommit.propose request before) = [].
Proof.
 intros; unfold ForkCommit.propose, ForkCommit.propose_result.
 destruct (Worktree.execution_allowed _ _); [|reflexivity].
 apply the_manual_fork_handler_emits_no_unbound_effects.
Qed.

Lemma the_fork_transaction_emits_only_its_durable_continuation : forall request before,
 Forall (fun effect => effect = ContinueScheduling) (decision_effects (ForkCommit.candidate request before)).
Proof.
 intros request before; unfold ForkCommit.candidate.
 destruct (ForkCommit.admit_workspace before (ForkCommit.propose_result request before)); repeat constructor.
Qed.
Lemma workspace_admission_keeps_the_constructor_or_the_before_world : forall before proposed,
 decision_world (CommandResult.decide before (ForkCommit.admit_workspace before proposed)) =
   decision_world (CommandResult.decide before proposed) \/
 decision_world (CommandResult.decide before (ForkCommit.admit_workspace before proposed)) = before.
Proof.
 intros before [proposed|reason]; [|left; reflexivity].
 unfold ForkCommit.admit_workspace,ForkCommit.workspace_error; cbn [CommandResult.bind].
 destruct (skipn _ _) as [|child rest]; [left; reflexivity|].
 destruct (_ && _); [left|right]; reflexivity.
Qed.
Lemma the_fork_transaction_keeps_the_admitted_world : forall request before,
 decision_world (ForkCommit.candidate request before) =
 decision_world (CommandResult.decide before (ForkCommit.admit_workspace before
   (ForkCommit.propose_result request before))).
Proof.
 intros; unfold ForkCommit.candidate.
 destruct (ForkCommit.admit_workspace before (ForkCommit.propose_result request before)); reflexivity.
Qed.

Lemma delivered_fork_effects_are_only_continuations : forall request before,
 let delivered := snd (Delivery.deliver_with_status true (ForkCommit.candidate request before) before) in
 Forall (fun effect => effect = ContinueScheduling) (decision_effects delivered).
Proof.
 intros request before; cbn zeta; unfold Delivery.deliver_with_status.
 destruct (Delivery.fits true (ForkCommit.candidate request before)); cbn [snd];
 [apply the_fork_transaction_emits_only_its_durable_continuation|constructor].
Qed.

Lemma a_manual_fork_uses_the_actual_domain_constructor : forall request messages before,
 Selvedge.Kernel.Codec.traverse Images.parse_content (message_sources request) = Some messages ->
 CommandHandlers.execute (G.Cmd_fork request) None before =
 Tasks.fork_with_caller Tasks.ManualFork (settings_origin request)
   (G.fork_task_id request) (G.fork_child_count request) messages (G.fork_settings request) before.
Proof.
 intros request messages before Parsed.
 rewrite the_actual_manual_fork_handler_interprets_its_message_admission, Parsed; reflexivity.
Qed.

Lemma a_constructed_fork_admits_its_workspace_once : forall request before after reply child rest,
 Worktree.execution_guard (G.fork_task_id request) before = None ->
 CommandHandlers.execute (G.Cmd_fork request) None before = accept reply after [] ->
 skipn (List.length (world_tasks before)) (world_tasks after) = child :: rest ->
 Worktree.workspace_available (settings_workspace (task_current_settings child)) before &&
 Worktree.binding_available (task_current_settings child) after = true ->
 ForkCommit.candidate request before = Decision after (success reply) [ContinueScheduling].
Proof.
 intros request before after reply child rest ParentAvailable Constructed Births Available.
 unfold Worktree.execution_guard in ParentAvailable.
 destruct (Worktree.execution_allowed (G.fork_task_id request) before) eqn:Parent; [|discriminate].
 change (CommandResult.decide before (CommandExecution.handle_fork_result request None before) =
   accept reply after []) in Constructed.
 unfold ForkCommit.candidate,ForkCommit.propose_result; rewrite Parent.
 destruct (CommandExecution.handle_fork_result request None before)
   as [[result next effects]|reason]; [|discriminate].
 cbn [CommandResult.decide CommandResult.resolve CommandResult.accept accept] in Constructed.
 injection Constructed as World Reply Effects.
 subst next result effects.
 unfold ForkCommit.admit_workspace,ForkCommit.workspace_error; cbn [CommandResult.bind CommandResult.change_world].
 rewrite Births,Available; reflexivity.
Qed.

Lemma a_fork_with_an_admitted_output_budget_is_delivered : forall request before candidate,
 ForkCommit.candidate request before = candidate ->
 Delivery.fits true candidate = true ->
 ForkCommit.packet request before =
 (with_sequence (N.succ (world_sequence before)) (decision_world candidate),
  Notifications.envelope true true (Some (UserCommand (G.Cmd_fork request))) before candidate).
Proof.
 intros request before candidate Constructed Fits.
 unfold ForkCommit.packet, ForkCommit.select, CommitPacket.choose; rewrite Constructed.
 unfold Delivery.deliver_with_status; rewrite Fits; reflexivity.
Qed.
